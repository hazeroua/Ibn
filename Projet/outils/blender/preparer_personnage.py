"""Prépare un personnage du jeu à partir de sa source libre, avec Blender en ligne de commande.

Lancé par Scripts/Pipeline/importer-personnages.ps1 :

    blender --background --factory-startup --python Scripts/Blender/preparer_personnage.py -- \
        --manifest Game/data/assets/characters.json --character ibn_khaldoun_jeune \
        --source-dir <dossier de la source téléchargée> --output <fichier .glb> --report <fichier .json>

Étapes, toutes pilotées par le manifeste (res://data/assets/characters.json) :
  1. import de la source (glTF), suppression de tout ce qui n'est pas le squelette et ses maillages ;
  2. mise à l'échelle (hauteur du manifeste), pieds à l'origine, regard vers -Z dans Godot ;
  3. une seule surface par personnage : les matériaux d'origine deviennent des couleurs de sommets
     (palette du manifeste) portées par un matériau unique, soit un appel de dessin par personnage ;
  4. animations du contrat, toutes sur place, recalculées image par image à la cadence du manifeste :
     boucles (raccord fermé exactement), arrêts (décélération puis pose de repos) et virages
     (rotation de l'os racine, pas sur place) ;
  5. contrôle des budgets (triangles, os) et des vitesses au sol, export GLB, rapport JSON.

Le résultat est déterministe pour une version donnée de Blender. Compatible Blender 4.0 à 5.x
(actions classiques et actions à emplacements).
"""

import argparse
import json
import math
import os
import re
import sys

import bpy
from mathutils import Euler, Matrix, Quaternion, Vector

CHANNEL_PATTERN = re.compile(r'^pose\.bones\["(.+)"\]\.(location|rotation_quaternion|scale)$')
# Hauteur au-dessus du point le plus bas d'un pied en dessous de laquelle le pied est considéré au sol.
STANCE_HEIGHT_M = 0.02
# Tolérances de contrôle de la mise à l'échelle.
HEIGHT_TOLERANCE_M = 0.001


class PreparationError(Exception):
    """Erreur bloquante : le message est affiché et Blender se termine avec un code non nul."""


# ---------------------------------------------------------------------------
# Arguments et manifeste
# ---------------------------------------------------------------------------


def parse_arguments() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else sys.argv[1:]
    parser = argparse.ArgumentParser(description="Prépare un personnage du jeu (Blender en ligne de commande).")
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--character", required=True)
    parser.add_argument("--source-dir", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--report", required=True)
    return parser.parse_args(argv)


def require(data: dict, key: str, kind: type, context: str):
    if key not in data:
        raise PreparationError(f"Clé « {key} » manquante ({context}).")
    value = data[key]
    if kind is float and isinstance(value, int) and not isinstance(value, bool):
        value = float(value)
    if not isinstance(value, kind) or (kind is int and isinstance(value, bool)):
        raise PreparationError(f"« {key} » a un type invalide ({context}).")
    return value


def load_character(manifest_path: str, character_id: str) -> dict:
    with open(manifest_path, encoding="utf-8") as handle:
        manifest = json.load(handle)
    for character in require(manifest, "characters", list, manifest_path):
        if character.get("id") == character_id:
            return character
    raise PreparationError(f"Personnage « {character_id} » absent de {manifest_path}.")


def parse_color(text: str, context: str) -> tuple:
    if not re.fullmatch(r"#[0-9a-fA-F]{6}", text):
        raise PreparationError(f"Couleur invalide « {text} » ({context}) : format attendu #rrggbb.")
    srgb = [int(text[i : i + 2], 16) / 255.0 for i in (1, 3, 5)]
    # Les attributs de couleur de Blender sont stockés en espace linéaire.
    linear = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in srgb]
    return (linear[0], linear[1], linear[2], 1.0)


# ---------------------------------------------------------------------------
# Scène : import, nettoyage, échelle et orientation
# ---------------------------------------------------------------------------


def import_source(path: str) -> float:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    if not os.path.isfile(path):
        raise PreparationError(f"Fichier source introuvable : {path}")
    result = bpy.ops.import_scene.gltf(filepath=path)
    if "FINISHED" not in result:
        raise PreparationError(f"Échec de l'import glTF : {path}")
    render = bpy.context.scene.render
    # Les images clés importées sont exprimées dans la cadence de la scène au moment de l'import.
    return render.fps / render.fps_base


def collect_character_objects(armature_name: str):
    armature = bpy.data.objects.get(armature_name)
    if armature is None or armature.type != "ARMATURE":
        raise PreparationError(f"Squelette « {armature_name} » introuvable dans la source.")
    meshes = [obj for obj in bpy.data.objects if obj.type == "MESH" and obj.parent == armature]
    if not meshes:
        raise PreparationError(f"Aucun maillage rattaché au squelette « {armature_name} ».")
    for pose_bone in armature.pose.bones:
        pose_bone.custom_shape = None
        if pose_bone.constraints:
            raise PreparationError(f"Contrainte inattendue sur l'os « {pose_bone.name} » : non prise en charge.")
    if armature.animation_data is not None:
        for track in list(armature.animation_data.nla_tracks):
            armature.animation_data.nla_tracks.remove(track)
    keep = {armature.name} | {mesh.name for mesh in meshes}
    for obj in list(bpy.data.objects):
        if obj.name not in keep:
            bpy.data.objects.remove(obj, do_unlink=True)
    return armature, meshes


def world_bounds(meshes) -> tuple:
    low = Vector((math.inf, math.inf, math.inf))
    high = Vector((-math.inf, -math.inf, -math.inf))
    for mesh in meshes:
        matrix = mesh.matrix_world
        for vertex in mesh.data.vertices:
            point = matrix @ vertex.co
            low = Vector((min(low.x, point.x), min(low.y, point.y), min(low.z, point.z)))
            high = Vector((max(high.x, point.x), max(high.y, point.y), max(high.z, point.z)))
    return low, high


def normalize_transform(armature, meshes, height_m: float) -> float:
    """Échelle à la hauteur voulue (pose de liaison), pieds à l'origine, regard tourné de 180° autour
    de la verticale : la source regarde vers -Y de Blender (+Z de glTF), Godot attend -Z (+Y de Blender)."""
    low, high = world_bounds(meshes)
    source_height = high.z - low.z
    if source_height <= 0.0:
        raise PreparationError("Hauteur du maillage source nulle.")
    scale = height_m / source_height
    armature.location = (0.0, 0.0, -low.z * scale)
    armature.rotation_mode = "XYZ"
    armature.rotation_euler = (0.0, 0.0, math.pi)
    armature.scale = (scale, scale, scale)
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action="DESELECT")
    for obj in [armature] + meshes:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = armature
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.context.view_layer.update()
    low, high = world_bounds(meshes)
    if abs((high.z - low.z) - height_m) > HEIGHT_TOLERANCE_M or abs(low.z) > HEIGHT_TOLERANCE_M:
        raise PreparationError(f"Mise à l'échelle incorrecte : hauteur {high.z - low.z:.4f} m, pieds à {low.z:.4f} m.")
    return scale


# ---------------------------------------------------------------------------
# Maillage : une surface, couleurs de sommets, budgets
# ---------------------------------------------------------------------------


def merge_materials(meshes, palette: dict, roughness: float, uv_maps: int) -> None:
    material = bpy.data.materials.new("M_Character")
    if bpy.app.version < (5, 0, 0):
        # Depuis Blender 5.0, tout matériau utilise des nœuds (la propriété est obsolète).
        material.use_nodes = True
    # Faces arrière éliminées : le maillage est fermé, rien ne doit être dessiné deux fois.
    material.use_backface_culling = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    bsdf = next(node for node in nodes if node.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = 0.0
    attribute = nodes.new("ShaderNodeVertexColor")
    attribute.layer_name = "Col"
    links.new(attribute.outputs["Color"], bsdf.inputs["Base Color"])
    for obj in meshes:
        mesh = obj.data
        colors_by_slot = []
        for slot_material in mesh.materials:
            name = slot_material.name if slot_material is not None else ""
            if name not in palette:
                raise PreparationError(f"Matériau « {name} » absent de la palette du manifeste.")
            colors_by_slot.append(parse_color(palette[name], f"palette > {name}"))
        if not colors_by_slot:
            raise PreparationError(f"Le maillage « {obj.name} » n'a aucun matériau à convertir.")
        for name in [layer.name for layer in mesh.color_attributes]:
            mesh.color_attributes.remove(mesh.color_attributes[name])
        layer = mesh.color_attributes.new(name="Col", type="BYTE_COLOR", domain="CORNER")
        values = [0.0] * (len(mesh.loops) * 4)
        for polygon in mesh.polygons:
            color = colors_by_slot[polygon.material_index]
            for loop_index in polygon.loop_indices:
                values[loop_index * 4 : loop_index * 4 + 4] = color
        layer.data.foreach_set("color", values)
        mesh.color_attributes.active_color = layer
        mesh.polygons.foreach_set("material_index", [0] * len(mesh.polygons))
        mesh.materials.clear()
        mesh.materials.append(material)
        while len(mesh.uv_layers) > uv_maps:
            mesh.uv_layers.remove(mesh.uv_layers[len(mesh.uv_layers) - 1])
        mesh.update()


def count_triangles(meshes) -> int:
    total = 0
    for obj in meshes:
        obj.data.calc_loop_triangles()
        total += len(obj.data.loop_triangles)
    return total


# ---------------------------------------------------------------------------
# Actions : lecture (actions classiques et à emplacements) et écriture
# ---------------------------------------------------------------------------


def action_fcurves(action) -> list:
    layers = getattr(action, "layers", None)
    if layers is not None and len(layers) > 0:
        if len(action.slots) != 1:
            raise PreparationError(f"Action « {action.name} » : un seul emplacement attendu, {len(action.slots)} trouvés.")
        curves = []
        for layer in layers:
            for strip in layer.strips:
                for channelbag in strip.channelbags:
                    curves.extend(channelbag.fcurves)
        return curves
    if hasattr(action, "fcurves"):
        return list(action.fcurves)
    return []


class SourceClip:
    """Animation source évaluée directement par ses courbes : indépendante de l'état de la scène."""

    def __init__(self, action, bone_names: list, source_fps: float, location_scale: float):
        self.name = action.name
        self.start = float(action.frame_range[0])
        self.end = float(action.frame_range[1])
        if self.end <= self.start:
            raise PreparationError(f"Animation source « {action.name} » vide.")
        self.source_fps = source_fps
        self.location_scale = location_scale
        index = {name: i for i, name in enumerate(bone_names)}
        self.curves = [{"location": [None] * 3, "rotation_quaternion": [None] * 4, "scale": [None] * 3} for _ in bone_names]
        for curve in action_fcurves(action):
            match = CHANNEL_PATTERN.match(curve.data_path)
            if match is None:
                if curve.data_path.startswith("pose.bones"):
                    raise PreparationError(f"Canal non pris en charge dans « {action.name} » : {curve.data_path}")
                continue
            bone, prop = match.group(1), match.group(2)
            if bone in index:
                self.curves[index[bone]][prop][curve.array_index] = curve

    @property
    def length_s(self) -> float:
        return (self.end - self.start) / self.source_fps

    def pose_at(self, seconds: float) -> list:
        frame = self.start + seconds * self.source_fps
        pose = []
        for channels in self.curves:
            loc = Vector([c.evaluate(frame) if c is not None else 0.0 for c in channels["location"]]) * self.location_scale
            defaults = (1.0, 0.0, 0.0, 0.0)
            rot = Quaternion([c.evaluate(frame) if c is not None else defaults[i] for i, c in enumerate(channels["rotation_quaternion"])])
            rot.normalize()
            scl = Vector([c.evaluate(frame) if c is not None else 1.0 for c in channels["scale"]])
            pose.append((loc, rot, scl))
        return pose


def blend_pose(a: list, b: list, weight: float) -> list:
    if weight <= 0.0:
        return [(loc.copy(), rot.copy(), scl.copy()) for loc, rot, scl in a]
    if weight >= 1.0:
        return [(loc.copy(), rot.copy(), scl.copy()) for loc, rot, scl in b]
    result = []
    for (la, ra, sa), (lb, rb, sb) in zip(a, b):
        rot = ra.slerp(rb, weight) if ra.dot(rb) >= 0.0 else ra.slerp(-rb, weight)
        result.append((la.lerp(lb, weight), rot, sa.lerp(sb, weight)))
    return result


def smoothstep(edge0: float, edge1: float, x: float) -> float:
    if edge1 <= edge0:
        return 1.0 if x >= edge1 else 0.0
    t = min(max((x - edge0) / (edge1 - edge0), 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)


def sample_cyclic(frames: list, position: float) -> list:
    """Pose d'une boucle fermée (dernière image = première) à une position fractionnaire en images."""
    period = len(frames) - 1
    position = position % period
    low = int(math.floor(position))
    return blend_pose(frames[low], frames[low + 1], position - low)


def build_loop(clip: SourceClip, time_scale: float, fps: float) -> tuple:
    """Boucle rééchantillonnée et fermée : l'écart de raccord est réparti linéairement sur le cycle."""
    if time_scale <= 0.0:
        raise PreparationError(f"time_scale doit être strictement positif ({clip.name}).")
    count = max(2, round(clip.length_s * time_scale * fps))
    frames = [clip.pose_at(clip.length_s * i / count) for i in range(count + 1)]
    seam_deg = 0.0
    seam_m = 0.0
    first = frames[0]
    last = frames[count]
    corrections = []
    for (l0, r0, s0), (ln, rn, sn) in zip(first, last):
        r_target = r0 if r0.dot(rn) >= 0.0 else -r0
        delta = r_target @ rn.inverted()
        seam_deg = max(seam_deg, math.degrees(rn.rotation_difference(r_target).angle))
        seam_m = max(seam_m, (l0 - ln).length)
        corrections.append((l0 - ln, delta, s0 - sn))
    identity = Quaternion()
    for i, frame in enumerate(frames):
        weight = i / count
        corrected = []
        for (loc, rot, scl), (d_loc, d_rot, d_scl) in zip(frame, corrections):
            corrected.append((loc + d_loc * weight, identity.slerp(d_rot, weight) @ rot, scl + d_scl * weight))
        frames[i] = corrected
    frames[count] = [(loc.copy(), rot.copy(), scl.copy()) for loc, rot, scl in frames[0]]
    return frames, seam_deg, seam_m


# ---------------------------------------------------------------------------
# Cinématique directe (pour les pieds et la racine), sans dépendre de l'évaluation de la scène
# ---------------------------------------------------------------------------


class Rig:
    def __init__(self, armature):
        bones = armature.data.bones
        self.names = [bone.name for bone in bones]
        index = {name: i for i, name in enumerate(self.names)}
        self.parents = [index[bone.parent.name] if bone.parent is not None else -1 for bone in bones]
        self.rest = []
        for bone in bones:
            if bone.inherit_scale != "FULL" or not bone.use_inherit_rotation or bone.use_local_location is False:
                raise PreparationError(f"Os « {bone.name} » : héritage d'échelle ou de rotation non standard.")
            if bone.parent is None:
                self.rest.append(bone.matrix_local.copy())
            else:
                self.rest.append(bone.parent.matrix_local.inverted() @ bone.matrix_local)
        for i, parent in enumerate(self.parents):
            if parent > i:
                raise PreparationError("Ordre des os inattendu : un parent suit son enfant.")
        self.index = index

    def armature_matrices(self, pose: list) -> list:
        result = []
        for i, (loc, rot, scl) in enumerate(pose):
            basis = Matrix.Translation(loc) @ rot.to_matrix().to_4x4() @ Matrix.Diagonal((scl.x, scl.y, scl.z, 1.0))
            local = self.rest[i] @ basis
            result.append(local if self.parents[i] < 0 else result[self.parents[i]] @ local)
        return result

    def bone(self, name: str) -> int:
        if name not in self.index:
            raise PreparationError(f"Os « {name} » introuvable dans le squelette.")
        return self.index[name]


def passing_frame(rig: Rig, frames: list, left_foot: int, right_foot: int) -> int:
    """Image où les deux pieds se croisent (écart avant-arrière minimal) : point de départ naturel
    d'un arrêt ou d'un pas sur place."""
    best = 0
    best_gap = math.inf
    for i, frame in enumerate(frames[:-1]):
        matrices = rig.armature_matrices(frame)
        gap = abs(matrices[left_foot].translation.y - matrices[right_foot].translation.y)
        if gap < best_gap:
            best_gap = gap
            best = i
    return best


def ground_speed(rig: Rig, frames: list, fps: float, feet: list) -> float:
    """Vitesse au sol d'une boucle : recul des pieds posés (vers -Y, l'avant étant +Y) entre images."""
    speeds = []
    for foot in feet:
        positions = [rig.armature_matrices(frame)[foot].translation.copy() for frame in frames]
        lowest = min(p.z for p in positions)
        for a, b in zip(positions[:-1], positions[1:]):
            if a.z <= lowest + STANCE_HEIGHT_M and b.z <= lowest + STANCE_HEIGHT_M:
                speeds.append((a.y - b.y) * fps)
    if not speeds:
        return 0.0
    # Médiane : insensible aux images de pose et de décollement du pied.
    speeds.sort()
    middle = len(speeds) // 2
    return speeds[middle] if len(speeds) % 2 == 1 else 0.5 * (speeds[middle - 1] + speeds[middle])


# ---------------------------------------------------------------------------
# Recettes d'animation
# ---------------------------------------------------------------------------


def build_stop(loop_frames: list, idle_pose: list, start: int, recipe: dict, fps: float, context: str) -> list:
    duration = require(recipe, "duration_s", float, context)
    deceleration = require(recipe, "deceleration_s", float, context)
    settle = require(recipe, "settle_s", float, context)
    if duration <= 0.0 or deceleration <= 0.0 or settle < 0.0 or settle >= duration:
        raise PreparationError(f"Durées incohérentes ({context}).")
    count = max(2, round(duration * fps))
    frames = []
    position = float(start)
    for i in range(count + 1):
        t = i / fps
        if i > 0:
            # Cadence de la boucle qui décroît jusqu'à l'arrêt : les jambes ralentissent naturellement.
            position += 1.0 - smoothstep(0.0, deceleration, t)
        weight = smoothstep(0.0, duration - settle, t)
        frames.append(blend_pose(sample_cyclic(loop_frames, position), idle_pose, weight))
    return frames


def build_turn(rig: Rig, step_frames: list, idle_pose: list, start: int, recipe: dict, fps: float, context: str) -> list:
    angle = math.radians(require(recipe, "angle_deg", float, context))
    duration = require(recipe, "duration_s", float, context)
    step_weight = require(recipe, "step_weight", float, context)
    step_rate = require(recipe, "step_rate", float, context)
    if duration <= 0.0 or not 0.0 <= step_weight <= 1.0 or step_rate <= 0.0:
        raise PreparationError(f"Paramètres de virage incohérents ({context}).")
    root = 0
    head = rig.rest[root].translation
    if rig.parents[root] != -1 or math.hypot(head.x, head.y) > HEIGHT_TOLERANCE_M:
        # Le virage tourne autour de la tête de l'os racine : elle doit être sur l'axe vertical de l'origine.
        raise PreparationError("L'os racine doit être le premier os et se trouver sur l'axe vertical de l'origine.")
    # Axe vertical du monde exprimé dans le repère de repos de l'os racine.
    up_local = (rig.rest[root].to_3x3().inverted() @ Vector((0.0, 0.0, 1.0))).normalized()
    count = max(2, round(duration * fps))
    frames = []
    for i in range(count + 1):
        u = i / count
        weight = step_weight * math.sin(math.pi * u)
        steps = sample_cyclic(step_frames, start + i * step_rate)
        pose = blend_pose(idle_pose, steps, weight)
        yaw = Quaternion(up_local, angle * smoothstep(0.0, 1.0, u))
        loc, rot, scl = pose[root]
        pose[root] = (yaw @ loc, yaw @ rot, scl)
        frames.append(pose)
    return frames


def offset_quaternion(degrees: list, context: str) -> Quaternion:
    """Rotation locale d'un os (degrés, ordre XYZ dans le repère de l'os)."""
    if len(degrees) != 3:
        raise PreparationError(f"Décalage d'os : trois angles attendus ({context}).")
    return Euler([math.radians(float(v)) for v in degrees], "XYZ").to_quaternion()


class PoseAdjustment:
    """Retouche d'une pose source : rotations locales ajoutées à certains os et déplacement de la racine
    exprimé dans le repère de l'armature (X droite, Y avant, Z haut, en mètres)."""

    def __init__(self, rig: Rig, data: dict, context: str):
        self.rig = rig
        self.anchor = None
        if "anchor" in data:
            # Ancrage : après les retouches, la racine est déplacée pour que la tête de l'os indiqué tombe à la
            # position voulue (repère de l'armature) : le bassin posé sur la selle, quelle que soit la pose source.
            anchor = require(data, "anchor", dict, context)
            position = require(anchor, "position_m", list, context)
            if len(position) != 3:
                raise PreparationError(f"anchor > position_m : trois valeurs attendues ({context}).")
            self.anchor = (rig.bone(require(anchor, "bone", str, context)), Vector([float(v) for v in position]))
        # Jambes posées par cinématique inverse (deux os) : cheville sur un point voulu, genou vers un point de visée.
        self.legs = []
        for leg_index, leg in enumerate(data.get("legs", [])):
            leg_context = f"{context} > jambe {leg_index}"
            ankle = require(leg, "ankle_m", list, leg_context)
            pole = require(leg, "pole_m", list, leg_context)
            if len(ankle) != 3 or len(pole) != 3:
                raise PreparationError(f"ankle_m et pole_m : trois valeurs attendues ({leg_context}).")
            self.legs.append(
                (
                    rig.bone(require(leg, "thigh", str, leg_context)),
                    rig.bone(require(leg, "shin", str, leg_context)),
                    rig.bone(require(leg, "foot", str, leg_context)),
                    Vector([float(v) for v in ankle]),
                    Vector([float(v) for v in pole]),
                )
            )
        self.rotations = []
        for bone_name, degrees in data.get("offsets", {}).items():
            self.rotations.append((rig.bone(bone_name), offset_quaternion(degrees, f"{context} > {bone_name}")))
        root_offset = data.get("root_offset_m", [0.0, 0.0, 0.0])
        if len(root_offset) != 3:
            raise PreparationError(f"root_offset_m : trois valeurs attendues ({context}).")
        # Déplacement de l'armature exprimé dans le repère de repos de l'os racine (premier os, sans parent).
        self.root_shift = rig.rest[0].to_3x3().inverted() @ Vector([float(v) for v in root_offset])

    def apply(self, pose: list) -> list:
        result = [(loc.copy(), rot.copy(), scl.copy()) for loc, rot, scl in pose]
        for bone, offset in self.rotations:
            loc, rot, scl = result[bone]
            result[bone] = (loc, rot @ offset, scl)
        loc, rot, scl = result[0]
        result[0] = (loc + self.root_shift, rot, scl)
        if self.anchor is not None:
            bone, target = self.anchor
            current = self.rig.armature_matrices(result)[bone].translation
            loc, rot, scl = result[0]
            result[0] = (loc + self.rig.rest[0].to_3x3().inverted() @ (target - current), rot, scl)
        for thigh, shin, foot, ankle, pole in self.legs:
            result = solve_leg(self.rig, result, thigh, shin, foot, ankle, pole)
        return result


def remove_rise(rig: Rig, pose: list, rest_pose: list, bone: int) -> list:
    """Abaisse la racine pour que l'os ne dépasse jamais sa hauteur dans la pose de repos."""
    height = rig.armature_matrices(pose)[bone].translation.z
    limit = rig.armature_matrices(rest_pose)[bone].translation.z
    if height <= limit:
        return pose
    result = list(pose)
    loc, rot, scl = result[0]
    result[0] = (loc + rig.rest[0].to_3x3().inverted() @ Vector((0.0, 0.0, limit - height)), rot, scl)
    return result


def rotate_bone_world(rig: Rig, pose: list, bone: int, world_rotation: Quaternion) -> list:
    """Tourne un os d'une rotation exprimée dans le repère de l'armature, autour de sa tête (enfants entraînés)."""
    matrices = rig.armature_matrices(pose)
    parent = rig.parents[bone]
    parent_rot = matrices[parent].to_quaternion() if parent >= 0 else Quaternion()
    frame = parent_rot @ rig.rest[bone].to_quaternion()
    loc, rot, scl = pose[bone]
    result = list(pose)
    result[bone] = (loc, frame.inverted() @ world_rotation @ frame @ rot, scl)
    return result


def solve_leg(rig: Rig, pose: list, thigh: int, shin: int, foot: int, ankle: Vector, pole: Vector) -> list:
    """Cinématique inverse à deux os : la cheville (tête de l'os du pied) va sur `ankle`, le genou se plie vers `pole`."""
    matrices = rig.armature_matrices(pose)
    hip = matrices[thigh].translation.copy()
    knee = matrices[shin].translation.copy()
    heel = matrices[foot].translation.copy()
    upper = (knee - hip).length
    lower = (heel - knee).length
    to_target = ankle - hip
    distance = min(max(to_target.length, abs(upper - lower) + 1e-4), upper + lower - 1e-4)
    axis = to_target.normalized()
    # Genou : sur le cercle de la loi des cosinus, du côté du point de visée.
    along = (upper * upper - lower * lower + distance * distance) / (2.0 * distance)
    radius = math.sqrt(max(upper * upper - along * along, 0.0))
    side = pole - hip
    side = (side - axis * side.dot(axis))
    if side.length < 1e-6:
        raise PreparationError("Point de visée du genou aligné avec la hanche et la cheville.")
    knee_target = hip + axis * along + side.normalized() * radius
    pose = rotate_bone_world(rig, pose, thigh, (knee - hip).rotation_difference(knee_target - hip))
    matrices = rig.armature_matrices(pose)
    knee_now = matrices[shin].translation.copy()
    heel_now = matrices[foot].translation.copy()
    ankle_target = hip + axis * distance
    return rotate_bone_world(rig, pose, shin, (heel_now - knee_now).rotation_difference(ankle_target - knee_now))


def build_clip(clip: SourceClip, recipe: dict, fps: float, context: str) -> list:
    """Animation ponctuelle rééchantillonnée (début et fin facultatifs, en secondes de la source)."""
    time_scale = require(recipe, "time_scale", float, context)
    start = float(recipe.get("start_s", 0.0))
    end = float(recipe.get("end_s", clip.length_s))
    if time_scale <= 0.0 or not 0.0 <= start < end <= clip.length_s + 1e-6:
        raise PreparationError(f"Plage ou échelle de temps incohérente ({context}).")
    count = max(2, round((end - start) * time_scale * fps))
    return [clip.pose_at(start + (end - start) * i / count) for i in range(count + 1)]


def build_sequence(rig: Rig, key_pose, recipe: dict, fps: float, context: str) -> list:
    """Suite de poses clés (chacune : animation source, instant, retouches), enchaînées en douceur.
    key_pose(source, seconds) rend la pose source à l'instant voulu."""
    keys = require(recipe, "keys", list, context)
    if len(keys) < 2:
        raise PreparationError(f"Une séquence demande au moins deux poses clés ({context}).")
    poses = []
    times = []
    for index, key in enumerate(keys):
        key_context = f"{context} > clé {index}"
        at = require(key, "at_s", float, key_context)
        if times and at <= times[-1]:
            raise PreparationError(f"Instants des poses clés non croissants ({key_context}).")
        source_pose = key_pose(require(key, "source", str, key_context), float(key.get("source_time_s", 0.0)))
        poses.append(PoseAdjustment(rig, key, key_context).apply(source_pose))
        times.append(at)
    if times[0] != 0.0:
        raise PreparationError(f"La première pose clé doit être à 0 s ({context}).")
    count = max(2, round(times[-1] * fps))
    frames = []
    segment = 0
    for i in range(count + 1):
        t = times[-1] * i / count
        while segment < len(times) - 2 and t > times[segment + 1]:
            segment += 1
        weight = smoothstep(times[segment], times[segment + 1], t)
        frames.append(blend_pose(poses[segment], poses[segment + 1], weight))
    return frames


# ---------------------------------------------------------------------------
# Écriture des actions et export
# ---------------------------------------------------------------------------


def write_action(armature, name: str, bone_names: list, frames: list):
    action = bpy.data.actions.new(name)
    action.use_fake_user = True
    if hasattr(action, "id_root"):
        action.id_root = "OBJECT"
    if armature.animation_data is None:
        armature.animation_data_create()
    armature.animation_data.action = action
    count = len(frames)
    for bone_index, bone in enumerate(bone_names):
        # Quaternions rendus continus (même hémisphère d'une image à l'autre) pour une interpolation sans saut.
        rotations = []
        for frame in frames:
            rot = frame[bone_index][1].copy()
            if rotations and rotations[-1].dot(rot) < 0.0:
                rot.negate()
            rotations.append(rot)
        channels = (
            ("location", 3, [frame[bone_index][0] for frame in frames]),
            ("rotation_quaternion", 4, rotations),
            ("scale", 3, [frame[bone_index][2] for frame in frames]),
        )
        for prop, size, values in channels:
            data_path = f'pose.bones["{bone}"].{prop}'
            for component in range(size):
                if hasattr(action, "fcurve_ensure_for_datablock"):
                    curve = action.fcurve_ensure_for_datablock(armature, data_path, index=component, group_name=bone)
                else:
                    curve = action.fcurves.new(data_path, index=component, action_group=bone)
                curve.keyframe_points.add(count)
                coordinates = []
                for frame_index, value in enumerate(values):
                    coordinates.extend((float(frame_index), float(value[component])))
                curve.keyframe_points.foreach_set("co", coordinates)
                for point in curve.keyframe_points:
                    point.interpolation = "LINEAR"
                curve.update()
    return action


def export_glb(armature, meshes, path: str, fps: int) -> None:
    scene = bpy.context.scene
    scene.render.fps = fps
    scene.render.fps_base = 1.0
    bpy.ops.object.select_all(action="DESELECT")
    for obj in [armature] + meshes:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = armature
    available = set(bpy.ops.export_scene.gltf.get_rna_type().properties.keys())
    options = {
        "filepath": path,
        "export_format": "GLB",
        "use_selection": True,
        "export_yup": True,
        "export_apply": False,
        "export_animations": True,
        "export_animation_mode": "ACTIONS",
        "export_force_sampling": True,
        "export_frame_range": False,
        "export_skins": True,
        "export_morph": False,
        "export_normals": True,
        "export_texcoords": True,
        "export_tangents": False,
        "export_cameras": False,
        "export_lights": False,
        "export_extras": False,
    }
    for name in sorted(options):
        if name not in available and name != "filepath":
            raise PreparationError(f"Option d'export glTF absente de cette version de Blender : {name}")
    optional = {
        "export_optimize_animation_size": False,
        "export_anim_slide_to_zero": False,
        "export_reset_pose_bones": True,
        "export_def_bones": False,
        "export_all_influences": False,
        "export_rest_position_armature": True,
    }
    for name, value in optional.items():
        if name in available:
            options[name] = value
    # Couleurs de sommets : option selon la version de l'exportateur.
    if "export_vertex_color" in available:
        options["export_vertex_color"] = "MATERIAL"
    elif "export_colors" in available:
        options["export_colors"] = True
    else:
        raise PreparationError("L'exportateur glTF ne sait pas exporter les couleurs de sommets.")
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    partial = path + ".partiel.glb"
    options["filepath"] = partial
    result = bpy.ops.export_scene.gltf(**options)
    if "FINISHED" not in result or not os.path.isfile(partial):
        raise PreparationError(f"Échec de l'export GLB : {path}")
    os.replace(partial, path)


# ---------------------------------------------------------------------------
# Programme principal
# ---------------------------------------------------------------------------


def prepare(args: argparse.Namespace) -> dict:
    character = load_character(args.manifest, args.character)
    context = f"personnage {args.character}"
    source_file = os.path.join(args.source_dir, require(character, "source_file", str, context))
    source_fps = import_source(source_file)
    armature, meshes = collect_character_objects(require(character, "armature", str, context))
    height_m = require(character, "height_m", float, context)
    scale = normalize_transform(armature, meshes, height_m)
    merge_materials(
        meshes,
        require(character, "palette", dict, context),
        require(character, "roughness", float, context),
        require(character, "uv_maps", int, context),
    )

    budget = require(character, "budget", dict, context)
    triangles = count_triangles(meshes)
    bones = len(armature.data.bones)
    if triangles > require(budget, "max_triangles", int, context):
        raise PreparationError(f"Budget de triangles dépassé : {triangles} > {budget['max_triangles']}.")
    if bones > require(budget, "max_bones", int, context):
        raise PreparationError(f"Budget d'os dépassé : {bones} > {budget['max_bones']}.")
    if len(meshes) > require(budget, "max_surfaces", int, context):
        raise PreparationError(f"Budget de surfaces dépassé : {len(meshes)} > {budget['max_surfaces']}.")

    rig = Rig(armature)
    skeleton = require(character, "skeleton", dict, context)
    if rig.bone(require(skeleton, "root_bone", str, context)) != 0:
        raise PreparationError("L'os racine du manifeste doit être le premier os du squelette.")
    left_foot = rig.bone(require(skeleton, "left_foot", str, context))
    right_foot = rig.bone(require(skeleton, "right_foot", str, context))
    fps = require(character, "fps", int, context)
    tolerance = require(character, "ground_speed_tolerance", float, context)

    clips = {}
    for action in list(bpy.data.actions):
        clips[action.name] = SourceClip(action, rig.names, source_fps, scale)

    def clip(name: str) -> SourceClip:
        # Selon la version, l'importateur glTF nomme l'action « <animation> » ou « <animation>_<objet> ».
        for candidate in (name, f"{name}_{armature.name}"):
            if candidate in clips:
                return clips[candidate]
        raise PreparationError(f"Animation source « {name} » absente.")

    loops = {}

    def loop_frames(name: str, time_scale: float) -> list:
        key = (name, time_scale)
        if key not in loops:
            loops[key] = build_loop(clip(name), time_scale, fps)
        return loops[key][0]

    outputs = []
    report_animations = []
    for entry in require(character, "animations", list, context):
        name = require(entry, "name", str, context)
        anim_context = f"{context} > {name}"
        recipe = require(entry, "recipe", dict, anim_context)
        kind = require(recipe, "type", str, anim_context)
        info = {"name": name, "type": kind, "loop": require(entry, "loop", bool, anim_context)}
        if kind == "loop":
            if not info["loop"]:
                raise PreparationError(f"Une recette « loop » doit être une boucle ({anim_context}).")
            source = require(recipe, "source", str, anim_context)
            time_scale = require(recipe, "time_scale", float, anim_context)
            frames = loop_frames(source, time_scale)
            info["seam_corrected_deg"] = round(loops[(source, time_scale)][1], 3)
            info["seam_corrected_m"] = round(loops[(source, time_scale)][2], 4)
            if "ground_speed_m_s" in entry:
                measured = ground_speed(rig, frames, fps, [left_foot, right_foot])
                expected = require(entry, "ground_speed_m_s", float, anim_context)
                info["ground_speed_m_s"] = round(measured, 3)
                if expected <= 0.0 or abs(measured - expected) > tolerance * expected:
                    raise PreparationError(f"Vitesse au sol de « {name} » : mesurée {measured:.3f} m/s, manifeste {expected:.3f} m/s.")
        elif kind == "stop":
            if info["loop"]:
                raise PreparationError(f"Un arrêt ne boucle pas ({anim_context}).")
            source_frames = loop_frames(require(recipe, "source", str, anim_context), 1.0)
            idle_pose = loop_frames(require(recipe, "idle", str, anim_context), 1.0)[0]
            start = passing_frame(rig, source_frames, left_foot, right_foot)
            frames = build_stop(source_frames, idle_pose, start, recipe, fps, anim_context)
            info["start_frame"] = start
        elif kind == "turn":
            if info["loop"]:
                raise PreparationError(f"Un virage ne boucle pas ({anim_context}).")
            step_frames = loop_frames(require(recipe, "step_source", str, anim_context), 1.0)
            idle_pose = loop_frames(require(recipe, "idle", str, anim_context), 1.0)[0]
            start = passing_frame(rig, step_frames, left_foot, right_foot)
            frames = build_turn(rig, step_frames, idle_pose, start, recipe, fps, anim_context)
            info["start_frame"] = start
            info["root_yaw_deg"] = require(recipe, "angle_deg", float, anim_context)
        elif kind == "clip":
            if info["loop"]:
                raise PreparationError(f"Une animation ponctuelle ne boucle pas ({anim_context}).")
            frames = build_clip(clip(require(recipe, "source", str, anim_context)), recipe, fps, anim_context)
            frames = [PoseAdjustment(rig, recipe, anim_context).apply(pose) for pose in frames]
            if "no_rise_bone" in recipe:
                # Le saut du jeu est porté par la physique : l'élévation propre de l'animation est retirée (le
                # bassin ne monte jamais au-dessus de sa hauteur de repos, les flexions sont gardées).
                idle_pose = loop_frames(require(recipe, "rest_source", str, anim_context), 1.0)[0]
                frames = [remove_rise(rig, pose, idle_pose, rig.bone(recipe["no_rise_bone"])) for pose in frames]
        elif kind == "loop_no_rise":
            if not info["loop"]:
                raise PreparationError(f"Une recette « loop_no_rise » doit être une boucle ({anim_context}).")
            idle_pose = loop_frames(require(recipe, "rest_source", str, anim_context), 1.0)[0]
            bone = rig.bone(require(recipe, "no_rise_bone", str, anim_context))
            frames = [remove_rise(rig, pose, idle_pose, bone) for pose in loop_frames(require(recipe, "source", str, anim_context), 1.0)]
        elif kind == "pose_loop":
            if not info["loop"]:
                raise PreparationError(f"Une recette « pose_loop » doit être une boucle ({anim_context}).")
            source = require(recipe, "source", str, anim_context)
            time_scale = require(recipe, "time_scale", float, anim_context)
            adjustment = PoseAdjustment(rig, recipe, anim_context)
            frames = [adjustment.apply(pose) for pose in loop_frames(source, time_scale)]
        elif kind == "sequence":
            if info["loop"]:
                raise PreparationError(f"Une séquence ne boucle pas ({anim_context}).")

            def key_pose(source: str, seconds: float) -> list:
                return clip(source).pose_at(min(max(seconds, 0.0), clip(source).length_s))

            frames = build_sequence(rig, key_pose, recipe, fps, anim_context)
        else:
            raise PreparationError(f"Type de recette inconnu « {kind} » ({anim_context}).")
        info["frames"] = len(frames)
        info["duration_s"] = round((len(frames) - 1) / fps, 4)
        outputs.append((name, frames))
        report_animations.append(info)

    names = [name for name, _ in outputs]
    if len(set(names)) != len(names):
        raise PreparationError("Noms d'animation en double dans le manifeste.")
    armature.animation_data.action = None
    for action in list(bpy.data.actions):
        bpy.data.actions.remove(action)
    for name, frames in outputs:
        write_action(armature, name, rig.names, frames)
    armature.animation_data.action = bpy.data.actions[names[0]]
    for pose_bone in armature.pose.bones:
        pose_bone.location = (0.0, 0.0, 0.0)
        pose_bone.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
        pose_bone.scale = (1.0, 1.0, 1.0)
    bpy.data.orphans_purge(do_local_ids=True, do_linked_ids=True, do_recursive=True)

    export_glb(armature, meshes, args.output, fps)
    return {
        "character": args.character,
        "blender": bpy.app.version_string,
        "output": os.path.abspath(args.output),
        "height_m": height_m,
        "scale": round(scale, 6),
        "triangles": triangles,
        "bones": bones,
        "surfaces": len(meshes),
        "animations": report_animations,
    }


def main() -> int:
    args = parse_arguments()
    try:
        report = prepare(args)
    except PreparationError as error:
        print(f"ERREUR preparer_personnage : {error}", file=sys.stderr)
        return 1
    except Exception as error:  # noqa: BLE001 - toute erreur de Blender doit arrêter le pipeline avec un code non nul
        import traceback

        traceback.print_exc()
        print(f"ERREUR preparer_personnage : {type(error).__name__} : {error}", file=sys.stderr)
        return 1
    with open(args.report, "w", encoding="utf-8") as handle:
        json.dump(report, handle, ensure_ascii=False, indent=2)
    print("PERSONNAGE " + json.dumps(report, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    code = main()
    sys.stdout.flush()
    sys.stderr.flush()
    # Sous Blender, sys.exit ne suffit pas toujours à transmettre le code de sortie : os._exit le garantit.
    os._exit(code)
