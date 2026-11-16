"""Génère les modèles de la faune d'ambiance du désert (oiseaux, gazelle dorcas, libellule) avec Blender en ligne de commande.

    blender --background --factory-startup --python Scripts/Blender/generer_faune.py -- \
        --manifest Game/data/assets/fauna_models.json --output-dir Game/assets/faune --report <rapport.json>

Tout est piloté par le manifeste. Un fichier .glb par modèle ; une seule surface (couleurs de sommets, un seul matériau).
Convention : l'animal regarde vers +Y dans Blender (soit -Z dans Godot, après l'export glTF), le haut est +Z.
La couleur de sommet porte, dans son canal alpha, le poids d'animation lu par les shaders du jeu :
  - oiseaux et libellules : 0 au corps, 1 en bout d'aile (le battement est calculé dans le vertex shader) ;
  - gazelle : 0 au corps, 0,5 au genou, 1 au sabot (la course est calculée dans le vertex shader).
Le résultat est déterministe et les budgets de triangles sont contrôlés ici.
"""

import argparse
import json
import math
import os
import sys

import bpy
import bmesh
from mathutils import Vector


def parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--report", default="")
    return parser.parse_args(argv)


def reset_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)


def make_material() -> bpy.types.Material:
    material = bpy.data.materials.new("faune")
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    bsdf = nodes["Principled BSDF"]
    attribute = nodes.new("ShaderNodeVertexColor")
    attribute.layer_name = "Col"
    links.new(attribute.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.92
    return material


def new_bmesh() -> bmesh.types.BMesh:
    bm = bmesh.new()
    bm.verts.layers.float_vector.new("c")
    bm.verts.layers.float.new("w")
    return bm


def add_vert(bm: bmesh.types.BMesh, position: Vector, color: tuple, weight: float = 0.0) -> bmesh.types.BMVert:
    vert = bm.verts.new(position)
    vert[bm.verts.layers.float_vector.get("c")] = color
    vert[bm.verts.layers.float.get("w")] = weight
    return vert


def mix(a: list, b: list, t: float) -> tuple:
    t = max(0.0, min(1.0, t))
    return tuple(a[i] * (1.0 - t) + b[i] * t for i in range(3))


def finish(name: str, bm: bmesh.types.BMesh, material: bpy.types.Material) -> bpy.types.Object:
    """Convertit en triangles, pose les couleurs de sommets (RVB = couleur, alpha = poids d'animation) et crée l'objet."""
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bm.normal_update()
    mesh = bpy.data.meshes.new(name)
    layer = bm.loops.layers.color.new("Col")
    source = bm.verts.layers.float_vector.get("c")
    weight = bm.verts.layers.float.get("w")
    for face in bm.faces:
        for loop in face.loops:
            loop[layer] = tuple(loop.vert[source]) + (loop.vert[weight],)
    bm.to_mesh(mesh)
    bm.free()
    # Couleur active et de rendu : sans cela, l'export glTF (export_vertex_color="ACTIVE") n'écrit aucune couleur.
    attribute = mesh.color_attributes.get("Col")
    if attribute is None:
        raise RuntimeError(f"{name} : attribut de couleur Col absent")
    mesh.color_attributes.active_color = attribute
    mesh.color_attributes.render_color_index = list(mesh.color_attributes).index(attribute)
    mesh.materials.append(material)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def ring(bm, y: float, center_z: float, radius_x: float, radius_z: float, sides: int, belly: list, back: list, weight: float = 0.0) -> list:
    """Anneau perpendiculaire à l'axe Y ; couleur du ventre en bas, du dos en haut."""
    verts = []
    for i in range(sides):
        angle = 2.0 * math.pi * i / sides
        x = math.cos(angle) * radius_x
        z = math.sin(angle) * radius_z
        verts.append(add_vert(bm, Vector((x, y, center_z + z)), mix(belly, back, 0.5 + 0.5 * math.sin(angle)), weight))
    return verts


def bridge(bm, first: list, second: list) -> None:
    count = len(first)
    for i in range(count):
        j = (i + 1) % count
        bm.faces.new((first[i], first[j], second[j], second[i]))


def cap(bm, tip: bmesh.types.BMVert, loop: list, toward_tip_last: bool) -> None:
    count = len(loop)
    for i in range(count):
        j = (i + 1) % count
        face = (loop[i], loop[j], tip) if toward_tip_last else (tip, loop[j], loop[i])
        bm.faces.new(face)


def build_bird(spec: dict) -> bmesh.types.BMesh:
    """Oiseau : corps fusiforme à cinq côtés, deux ailes en deux segments (poids 0 → 0,5 → 1), queue."""
    bm = new_bmesh()
    colors = spec["colors"]
    length = spec["body_length_m"]
    radius = spec["body_radius_m"]
    sides = 5
    stations = [(0.5, 0.55), (0.25, 0.9), (-0.1, 1.0), (-0.38, 0.55)]
    rings = []
    for fraction, size in stations:
        rings.append(ring(bm, fraction * length, 0.0, radius * size, radius * size, sides, colors["belly"], colors["back"]))
    beak = add_vert(bm, Vector((0.0, 0.5 * length + spec["beak_length_m"], 0.0)), colors["beak"])
    tail_tip = add_vert(bm, Vector((0.0, -0.38 * length - spec["tail_length_m"], 0.0)), colors["tail"])
    for index in range(len(rings) - 1):
        bridge(bm, rings[index], rings[index + 1])
    cap(bm, beak, rings[0], True)
    cap(bm, tail_tip, rings[-1], False)
    span = spec["wing_span_m"] * 0.5
    chord = spec["wing_chord_m"]
    for side in (-1.0, 1.0):
        root_front = add_vert(bm, Vector((side * radius * 0.6, 0.2 * length, radius * 0.5)), colors["wing"], 0.0)
        root_back = add_vert(bm, Vector((side * radius * 0.6, -0.15 * length, radius * 0.5)), colors["wing"], 0.0)
        mid_front = add_vert(bm, Vector((side * span * 0.5, 0.18 * length, radius * 0.5)), colors["wing"], 0.5)
        mid_back = add_vert(bm, Vector((side * span * 0.5, 0.18 * length - chord, radius * 0.5)), colors["wing"], 0.5)
        tip = add_vert(bm, Vector((side * span, 0.05 * length - chord * 0.6, radius * 0.5)), colors["wing_tip"], 1.0)
        if side < 0.0:
            bm.faces.new((root_front, mid_front, mid_back, root_back))
            bm.faces.new((mid_front, tip, mid_back))
        else:
            bm.faces.new((root_front, root_back, mid_back, mid_front))
            bm.faces.new((mid_front, mid_back, tip))
    tail_width = spec["tail_width_m"] * 0.5
    tail_left = add_vert(bm, Vector((-tail_width, -0.38 * length - spec["tail_length_m"], 0.0)), colors["tail"])
    tail_right = add_vert(bm, Vector((tail_width, -0.38 * length - spec["tail_length_m"], 0.0)), colors["tail"])
    tail_root_left = add_vert(bm, Vector((-radius * 0.3, -0.38 * length, 0.0)), colors["tail"])
    tail_root_right = add_vert(bm, Vector((radius * 0.3, -0.38 * length, 0.0)), colors["tail"])
    bm.faces.new((tail_root_left, tail_root_right, tail_right, tail_left))
    return bm


def leg(bm, hip_x: float, hip_y: float, spec: dict, colors: dict) -> None:
    """Patte à quatre côtés : hanche (poids 0), genou (0,5), sabot (1)."""
    height = spec["body_height_m"]
    sides = 4
    levels = [
        (height * 0.96, spec["leg_top_radius_m"], 0.0, colors["body"]),
        (height * 0.5, spec["leg_knee_radius_m"], 0.5, colors["leg"]),
        (0.0, spec["leg_hoof_radius_m"], 1.0, colors["hoof"]),
    ]
    loops = []
    for z, radius, weight, color in levels:
        loop = []
        for i in range(sides):
            angle = 2.0 * math.pi * i / sides + math.pi / 4.0
            loop.append(add_vert(bm, Vector((hip_x + math.cos(angle) * radius, hip_y + math.sin(angle) * radius, z)), color, weight))
        loops.append(loop)
    for index in range(len(loops) - 1):
        bridge(bm, loops[index], loops[index + 1])


def build_gazelle(spec: dict) -> bmesh.types.BMesh:
    """Gazelle dorcas : corps à huit côtés, cou et tête, quatre pattes animables, cornes en lyre, oreilles, queue courte."""
    bm = new_bmesh()
    colors = spec["colors"]
    length = spec["body_length_m"]
    height = spec["body_height_m"]
    sides = 8
    # (position le long de Y en fraction de la longueur, hauteur du centre en fraction de la hauteur, rayon x, rayon z)
    stations = [
        (0.52, 0.99, 0.05, 0.06),
        (0.42, 1.1, 0.07, 0.09),
        (0.30, 1.05, 0.10, 0.13),
        (0.12, 0.92, 0.12, 0.15),
        (-0.15, 0.9, 0.12, 0.15),
        (-0.4, 0.9, 0.09, 0.12),
    ]
    rings = []
    for fraction, center, radius_x, radius_z in stations:
        belly = colors["belly"]
        back = colors["back"]
        rings.append(ring(bm, fraction * length, center * height * 0.82, radius_x, radius_z, sides, belly, back))
    nose = add_vert(bm, Vector((0.0, 0.52 * length + spec["snout_length_m"], 0.99 * height * 0.82)), colors["nose"])
    rump = add_vert(bm, Vector((0.0, -0.4 * length - 0.04, 0.9 * height * 0.82)), colors["back"])
    for index in range(len(rings) - 1):
        bridge(bm, rings[index], rings[index + 1])
    cap(bm, nose, rings[0], True)
    cap(bm, rump, rings[-1], False)
    leg_x = spec["leg_spacing_m"]
    leg_y = length * 0.3
    for hip_x in (-leg_x, leg_x):
        leg(bm, hip_x, leg_y, spec, colors)
        leg(bm, hip_x, -leg_y, spec, colors)
    # Cornes : deux triangles fins en arc vers l'arrière.
    head_y = 0.42 * length
    head_z = 1.1 * height * 0.82 + 0.09
    for side in (-1.0, 1.0):
        base_a = add_vert(bm, Vector((side * 0.03, head_y, head_z)), colors["horn"])
        base_b = add_vert(bm, Vector((side * 0.045, head_y - 0.04, head_z)), colors["horn"])
        tip = add_vert(bm, Vector((side * 0.07, head_y - 0.1, head_z + spec["horn_length_m"])), colors["horn"])
        bm.faces.new((base_a, base_b, tip) if side > 0.0 else (base_b, base_a, tip))
        ear_a = add_vert(bm, Vector((side * 0.045, head_y - 0.02, head_z - 0.03)), colors["back"])
        ear_b = add_vert(bm, Vector((side * 0.05, head_y - 0.06, head_z - 0.03)), colors["back"])
        ear_tip = add_vert(bm, Vector((side * 0.12, head_y - 0.05, head_z + 0.02)), colors["back"])
        bm.faces.new((ear_a, ear_b, ear_tip) if side > 0.0 else (ear_b, ear_a, ear_tip))
    return bm


def build_dragonfly(spec: dict) -> bmesh.types.BMesh:
    """Libellule : corps allongé à trois côtés, quatre ailes triangulaires (poids 1 en bout d'aile)."""
    bm = new_bmesh()
    colors = spec["colors"]
    length = spec["body_length_m"]
    radius = spec["body_radius_m"]
    rings = []
    for fraction, size in ((0.5, 1.0), (0.3, 1.3), (-0.1, 0.8), (-0.5, 0.4)):
        rings.append(ring(bm, fraction * length, 0.0, radius * size, radius * size, 3, colors["belly"], colors["body"]))
    for index in range(len(rings) - 1):
        bridge(bm, rings[index], rings[index + 1])
    head = add_vert(bm, Vector((0.0, 0.5 * length + radius, 0.0)), colors["body"])
    tail = add_vert(bm, Vector((0.0, -0.5 * length - radius, 0.0)), colors["body"])
    cap(bm, head, rings[0], True)
    cap(bm, tail, rings[-1], False)
    span = spec["wing_span_m"] * 0.5
    chord = spec["wing_chord_m"]
    for side in (-1.0, 1.0):
        for offset in (0.22, 0.04):
            root_front = add_vert(bm, Vector((side * radius, offset * length + 0.5 * chord, radius * 0.8)), colors["wing"], 0.0)
            root_back = add_vert(bm, Vector((side * radius, offset * length - 0.5 * chord, radius * 0.8)), colors["wing"], 0.0)
            tip = add_vert(bm, Vector((side * span, offset * length - 0.2 * chord, radius * 0.8)), colors["wing"], 1.0)
            bm.faces.new((root_front, tip, root_back) if side > 0.0 else (root_front, root_back, tip))
    return bm


BUILDERS = {"bird": build_bird, "gazelle": build_gazelle, "dragonfly": build_dragonfly}


def export(obj: bpy.types.Object, path: str) -> int:
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=True, export_yup=True, export_apply=True, export_vertex_color="ACTIVE", export_materials="EXPORT"
    )
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def main() -> None:
    args = parse_args()
    with open(args.manifest, encoding="utf-8") as handle:
        manifest = json.load(handle)
    os.makedirs(args.output_dir, exist_ok=True)
    report: dict = {}
    failures: list = []
    for name, spec in manifest["models"].items():
        reset_scene()
        material = make_material()
        builder = BUILDERS.get(spec["kind"])
        if builder is None:
            failures.append(f"{name} : type de modèle inconnu « {spec['kind']} »")
            continue
        obj = finish(name, builder(spec), material)
        triangles = export(obj, os.path.join(args.output_dir, name + ".glb"))
        budget = spec["max_triangles"]
        report[name] = {"triangles": triangles, "budget": budget}
        if triangles > budget:
            failures.append(f"{name} : {triangles} triangles pour un budget de {budget}")
        print(f"{name}: {triangles} triangles (budget {budget})")
    if args.report:
        with open(args.report, "w", encoding="utf-8") as handle:
            json.dump(report, handle, indent=2)
    if failures:
        print("\n".join(failures), file=sys.stderr)
        sys.exit(1)


main()
