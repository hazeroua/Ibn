"""Génère les modèles du désert avec Blender en ligne de commande : rochers, falaises de gorge, cailloux, pierres plates,
bois mort et chadouf (couleurs de sommets seules), et toute la végétation texturée — palmier dattier, acacia, tamaris,
arbres fruitiers de verger (grenadier, figuier, olivier), jujubier, laurier-rose, retam, buissons, herbes sèches, alfa,
drinn, roseaux, joncs, orge, fèves et fleurs —, leurs imposteurs, et l'atlas de textures peint qu'elle partage.

    blender --background --factory-startup --python Scripts/Blender/generer_props_desert.py -- \
        --manifest Game/data/assets/desert_props.json --output-dir Game/assets/desert --report <rapport.json>

Tout est piloté par le manifeste. Un fichier .glb par modèle et par niveau de détail ; une seule surface (un seul
matériau) par fichier, soit un appel de dessin par niveau de détail et par cellule. La végétation est faite de cartes
(plans découpés par l'alpha de l'atlas) dont les normales sont arrondies (volume de la couronne) : l'atlas
(foliage_atlas.dds : BC3 avec mipmaps qui conservent la couverture de l'alpha, peint par atlas_vegetation.py) multiplie la couleur de sommet, qui garde la teinte de chaque espèce
et les repères du shader (rouge de sommet supérieur à 0,8 pour fleurs et fruits). Les réglages d'import Godot de chaque
fichier produit sont écrits ici (pas de niveaux de détail automatiques, qui détruiraient les cartes).
Le résultat est déterministe (graines du manifeste) et les budgets de triangles sont contrôlés ici.
Compatible avec Blender 4.0 et plus récent (normales personnalisées et couleurs de sommets exportées dans les deux cas).
"""

import argparse
import json
import math
import os
import random
import sys

import bpy
import bmesh
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import atlas_vegetation  # noqa: E402  (module voisin, chemin ajouté juste au-dessus)

UP = Vector((0.0, 0.0, 1.0))
# Repère d'une vignette dans la planche « sprites » de l'atlas (2 x 2) : (u0, v0, u1, v1) dans la tuile.
SPRITE_CELLS = ((0.0, 0.0, 0.5, 0.5), (0.5, 0.0, 1.0, 0.5), (0.0, 0.5, 0.5, 1.0), (0.5, 0.5, 1.0, 1.0))


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
    material = bpy.data.materials.new("desert_props")
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    bsdf = nodes["Principled BSDF"]
    attribute = nodes.new("ShaderNodeVertexColor")
    attribute.layer_name = "Col"
    links.new(attribute.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.92
    return material


class Atlas:
    """Rectangles UV des tuiles de l'atlas (origine en haut à gauche de l'image)."""

    def __init__(self, rects: dict) -> None:
        self.rects = rects

    def uv(self, tile: str, u: float, v: float) -> tuple:
        if tile not in self.rects:
            raise KeyError(f"tuile d'atlas inconnue : {tile}")
        r = self.rects[tile]
        return (r[0] + (r[2] - r[0]) * u, r[1] + (r[3] - r[1]) * v)


def finish(name: str, bm: bmesh.types.BMesh, material: bpy.types.Material) -> bpy.types.Object:
    """Convertit en triangles, pose couleurs de sommets, UV (modèles texturés) et normales personnalisées, crée l'objet."""
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bm.normal_update()
    mesh = bpy.data.meshes.new(name)
    layer = bm.loops.layers.color.new("Col")
    source = bm.verts.layers.float_vector.get("c")
    uv_source = bm.verts.layers.float_vector.get("uv")
    normal_source = bm.verts.layers.float_vector.get("n")
    textured = any(v[uv_source].z > 0.5 for v in bm.verts)
    uv_layer = bm.loops.layers.uv.new("UVMap") if textured else None
    for face in bm.faces:
        for loop in face.loops:
            loop[layer] = tuple(loop.vert[source]) + (1.0,)
            if uv_layer is not None:
                uv = loop.vert[uv_source]
                if uv.z < 0.5:
                    raise RuntimeError(f"{name} : sommet sans coordonnées d'atlas dans un modèle texturé")
                # Blender compte v depuis le bas de l'image ; l'export glTF le retourne.
                loop[uv_layer].uv = (uv.x, 1.0 - uv.y)
    bm.verts.index_update()
    normals = [tuple(v[normal_source]) for v in bm.verts]
    custom = any(n != (0.0, 0.0, 0.0) for n in normals)
    bm.to_mesh(mesh)
    bm.free()
    # Couleur active et de rendu : sans cela, l'export glTF n'écrit aucune couleur et le modèle apparaît blanc dans Godot.
    attribute = mesh.color_attributes.get("Col")
    if attribute is None:
        raise RuntimeError(f"{name} : attribut de couleur Col absent")
    mesh.color_attributes.active_color = attribute
    mesh.color_attributes.render_color_index = list(mesh.color_attributes).index(attribute)
    if custom:
        # Blender 4.0 n'exporte les normales personnalisées qu'avec le lissage automatique (supprimé depuis 4.1).
        if hasattr(mesh, "use_auto_smooth"):
            mesh.use_auto_smooth = True
        mesh.normals_split_custom_set_from_vertices(normals)
    mesh.materials.append(material)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def new_bmesh() -> bmesh.types.BMesh:
    bm = bmesh.new()
    bm.verts.layers.float_vector.new("c")
    bm.verts.layers.float_vector.new("uv")  # z = 1 : coordonnées d'atlas posées
    bm.verts.layers.float_vector.new("n")  # normale personnalisée (nulle : normale calculée)
    return bm


def add_vert(bm: bmesh.types.BMesh, position: Vector, color: tuple, uv: tuple = None, normal: Vector = None) -> bmesh.types.BMVert:
    vert = bm.verts.new(position)
    vert[bm.verts.layers.float_vector.get("c")] = color
    if uv is not None:
        vert[bm.verts.layers.float_vector.get("uv")] = (uv[0], uv[1], 1.0)
    if normal is not None and normal.length > 1e-6:
        vert[bm.verts.layers.float_vector.get("n")] = normal.normalized()
    return vert


def mix(a: list, b: list, t: float) -> tuple:
    t = max(0.0, min(1.0, t))
    return tuple(a[i] * (1.0 - t) + b[i] * t for i in range(3))


def scaled(color: list, factor: float) -> tuple:
    return tuple(min(1.0, c * factor) for c in color)


def build_rock(spec: dict, index: int, subdivisions: int) -> bmesh.types.BMesh:
    rng = random.Random(spec["seeds"][index])
    # Même graine pour tous les niveaux de détail : mêmes bosses, donc silhouette stable.
    phases = [(rng.uniform(0, 6.28), rng.uniform(0, 6.28), rng.uniform(0.6, 1.4)) for _ in range(4)]
    bm = new_bmesh()
    bmesh.ops.create_icosphere(bm, subdivisions=subdivisions, radius=1.0)
    radius = spec["radius_m"][index]
    squash = spec["squash"][index]
    base = spec["colors"]["base"]
    top = spec["colors"]["top"]
    layer = bm.verts.layers.float_vector.get("c")
    for vert in bm.verts:
        d = vert.co.normalized()
        bump = 1.0
        for k, (p1, p2, f) in enumerate(phases):
            bump += 0.09 * math.sin(d.x * 2.3 * f * (k + 1) + p1) * math.cos(d.y * 2.1 * f * (k + 1) + p2) * math.sin(d.z * 1.9 * (k + 1) + p1)
        vert.co = Vector((d.x * bump * radius, d.y * bump * radius, d.z * bump * radius * squash))
        vert.co.z = max(vert.co.z, -0.25 * radius * squash)  # base aplatie : le rocher repose sur le sol
        vert[layer] = mix(base, top, d.z * 0.5 + 0.5)
    # Posé sur le sol : le point le plus bas à z = 0 avant la mise de côté d'un petit enfoncement.
    low = min(v.co.z for v in bm.verts)
    for vert in bm.verts:
        vert.co.z -= low - 0.05 * radius
    return bm


def ring(bm, center: Vector, radius: float, sides: int, color: tuple, phase: float = 0.0) -> list:
    return [
        add_vert(bm, center + Vector((math.cos(phase + 2 * math.pi * i / sides) * radius, math.sin(phase + 2 * math.pi * i / sides) * radius, 0.0)), color)
        for i in range(sides)
    ]



def build_cliff(spec: dict, index: int, lod: int) -> bmesh.types.BMesh:
    """Bloc de falaise : colonne haute aux facettes irrégulières, enterrée sur embed_m, strates colorées, sommet incliné.

    Même graine pour tous les niveaux de détail : silhouette stable. Pas de fond (le pied est enfoui dans la paroi).
    """
    rng = random.Random(spec["seeds"][index])
    phases = [(rng.uniform(0, 6.28), rng.uniform(0, 6.28), rng.uniform(0.7, 1.3)) for _ in range(3)]
    tilt = (rng.uniform(-1.0, 1.0), rng.uniform(-1.0, 1.0))
    bm = new_bmesh()
    sides = spec["sides"][lod]
    segments = spec["segments"][lod]
    radius = spec["radius_m"][index]
    height = spec["height_m"][index]
    embed = spec["embed_m"]
    base = spec["colors"]["base"]
    top = spec["colors"]["top"]
    rings = []
    for s in range(segments + 1):
        t = s / segments
        z = -embed + (height + embed) * t
        row = []
        for i in range(sides):
            angle = 2 * math.pi * i / sides
            jitter = 1.0
            for k, (p1, p2, f) in enumerate(phases):
                jitter += 0.12 * math.sin(angle * (k + 2) * f + p1 + t * 3.0 * (k + 1)) * math.cos(p2 + t * 2.0)
            r = radius * jitter * (1.0 - 0.28 * t)
            band = 0.5 + 0.5 * math.sin(t * 18.0 + phases[0][0])
            color = mix(base, top, 0.75 * t + 0.25 * band * (1.0 if lod == 0 else 0.5))
            row.append(add_vert(bm, Vector((math.cos(angle) * r, math.sin(angle) * r, z)), color))
        rings.append(row)
    for s in range(segments):
        for i in range(sides):
            j = (i + 1) % sides
            bm.faces.new((rings[s][i], rings[s][j], rings[s + 1][j], rings[s + 1][i]))
    apex = add_vert(bm, Vector((tilt[0] * radius * 0.25, tilt[1] * radius * 0.25, height + 0.35 * radius)), top)
    for i in range(sides):
        bm.faces.new((rings[-1][i], rings[-1][(i + 1) % sides], apex))
    return bm





def build_pebble(spec: dict, index: int) -> bmesh.types.BMesh:
    """Caillou : bipyramide hexagonale aplatie (12 triangles), un tiers enfoui dans le sol."""
    rng = random.Random(spec["seeds"][index])
    bm = new_bmesh()
    base = spec["colors"]["base"]
    top = spec["colors"]["top"]
    radius = spec["radius_m"][index]
    height = radius * spec["squash"][index]
    sides = 6
    phase = rng.uniform(0.0, 2 * math.pi)
    rim = []
    for i in range(sides):
        angle = phase + 2 * math.pi * i / sides + rng.uniform(-0.15, 0.15)
        r = radius * rng.uniform(0.75, 1.0)
        rim.append(add_vert(bm, Vector((math.cos(angle) * r, math.sin(angle) * r, height * rng.uniform(0.1, 0.3))), mix(base, top, 0.4)))
    apex = add_vert(bm, Vector((rng.uniform(-0.2, 0.2) * radius, rng.uniform(-0.2, 0.2) * radius, height)), top)
    bottom = add_vert(bm, Vector((0.0, 0.0, -height * 0.5)), base)
    for i in range(sides):
        j = (i + 1) % sides
        bm.faces.new((rim[i], rim[j], apex))
        bm.faces.new((rim[j], rim[i], bottom))
    return bm


def build_flat_stone(spec: dict, index: int) -> bmesh.types.BMesh:
    """Pierre plate : dalle pentagonale irrégulière (5 triangles dessus, 10 sur les côtés), posée à plat."""
    rng = random.Random(spec["seeds"][index])
    bm = new_bmesh()
    base = spec["colors"]["base"]
    top = spec["colors"]["top"]
    length = spec["length_m"][index]
    width = spec["width_m"][index]
    thickness = spec["thickness_m"][index]
    sides = 5
    phase = rng.uniform(0.0, 2 * math.pi)
    tilt = Vector((rng.uniform(-0.06, 0.06), rng.uniform(-0.06, 0.06)))
    upper = []
    lower = []
    for i in range(sides):
        angle = phase + 2 * math.pi * i / sides + rng.uniform(-0.2, 0.2)
        x = math.cos(angle) * length * 0.5 * rng.uniform(0.8, 1.0)
        y = math.sin(angle) * width * 0.5 * rng.uniform(0.8, 1.0)
        z = thickness + tilt.x * x + tilt.y * y + rng.uniform(-0.01, 0.01)
        upper.append(add_vert(bm, Vector((x, y, z)), mix(base, top, rng.uniform(0.6, 1.0))))
        lower.append(add_vert(bm, Vector((x * 0.97, y * 0.97, -0.02)), base))
    center = add_vert(bm, Vector((0.0, 0.0, thickness * 1.05)), top)
    for i in range(sides):
        j = (i + 1) % sides
        bm.faces.new((upper[i], upper[j], center))
        bm.faces.new((lower[i], lower[j], upper[j], upper[i]))
    return bm


def build_dead_wood(spec: dict, index: int) -> bmesh.types.BMesh:
    """Branche morte blanchie, tordue, posée au sol : tube triangulaire effilé en segments et une brindille."""
    rng = random.Random(spec["seeds"][index])
    bm = new_bmesh()
    base = spec["colors"]["base"]
    tip = spec["colors"]["tip"]
    length = spec["length_m"][index]
    radius = spec["radius_m"][index]
    segments = spec["segments"]
    wobble = spec["wobble_m"][index]
    phase = rng.uniform(0.0, 2 * math.pi)
    twist = rng.uniform(0.0, 2 * math.pi)

    def tube_ring(center: Vector, r: float, turn: float, color: tuple) -> list:
        return [
            add_vert(bm, center + Vector((0.0, math.cos(turn + 2 * math.pi * k / 3) * r, math.sin(turn + 2 * math.pi * k / 3) * r + r)), color)
            for k in range(3)
        ]

    def join(a: list, b: list) -> None:
        for k in range(3):
            n = (k + 1) % 3
            bm.faces.new((a[k], a[n], b[n], b[k]))

    rings = []
    for s in range(segments + 1):
        t = s / segments
        center = Vector((length * (t - 0.5), math.sin(phase + t * 5.0) * wobble, 0.0))
        rings.append(tube_ring(center, radius * (1.0 - 0.7 * t), twist + t * 2.0, mix(base, tip, t)))
    for s in range(segments):
        join(rings[s], rings[s + 1])
    for ring_verts, flip in ((rings[0], True), (rings[-1], False)):
        cap = (ring_verts[2], ring_verts[1], ring_verts[0]) if flip else (ring_verts[0], ring_verts[1], ring_verts[2])
        bm.faces.new(cap)
    # Brindille : un segment partant du milieu, relevée et rejetée sur le côté.
    start_index = segments // 2
    start_t = start_index / segments
    origin = Vector((length * (start_t - 0.5), math.sin(phase + start_t * 5.0) * wobble, 0.0))
    direction = Vector((rng.uniform(0.2, 0.5), rng.choice((-1.0, 1.0)) * rng.uniform(0.6, 1.0), 0.0)).normalized()
    twig_len = length * 0.28
    twig_base = tube_ring(origin, radius * 0.45, 0.0, mix(base, tip, start_t))
    twig_tip = [
        add_vert(bm, origin + direction * twig_len + Vector((0.0, 0.0, radius * 0.8 + twig_len * 0.15)) + (v.co - origin) * 0.4, tip)
        for v in twig_base
    ]
    join(twig_base, twig_tip)
    bm.faces.new((twig_tip[0], twig_tip[1], twig_tip[2]))
    return bm



def add_blob(bm, rng: random.Random, center: Vector, radii: tuple, subdivisions: int, bump: float, low: list, high: list, z_range: tuple) -> None:
    """Boule irrégulière à facettes (icosphère déformée) ajoutée à bm ; couleur de bas en haut selon la hauteur z_range."""
    part = bmesh.new()
    bmesh.ops.create_icosphere(part, subdivisions=subdivisions, radius=1.0)
    part.verts.index_update()
    created = [None] * len(part.verts)
    span = max(z_range[1] - z_range[0], 0.001)
    for vert in part.verts:
        d = vert.co.normalized()
        scale = 1.0 + rng.uniform(-bump, bump)
        co = Vector((d.x * radii[0] * scale, d.y * radii[1] * scale, d.z * radii[2] * scale)) + center
        created[vert.index] = add_vert(bm, co, mix(low, high, (co.z - z_range[0]) / span + rng.uniform(-0.06, 0.06)))
    for face in part.faces:
        bm.faces.new([created[v.index] for v in face.verts])
    part.free()


def add_tube(bm, centers: list, radii: list, sides: int, colors: list) -> None:
    """Tube effilé le long d'une ligne brisée (anneaux perpendiculaires à la direction, repère transporté sans torsion), non refermé."""
    count = len(centers)
    rings = []
    basis = None
    for k in range(count):
        tangent = (centers[min(k + 1, count - 1)] - centers[max(k - 1, 0)]).normalized()
        if basis is None:
            reference = Vector((1.0, 0.0, 0.0)) if abs(tangent.x) < 0.9 else Vector((0.0, 1.0, 0.0))
            basis = reference - tangent * reference.dot(tangent)
        else:
            basis = basis - tangent * basis.dot(tangent)
        basis.normalize()
        other = tangent.cross(basis)
        rings.append(
            [
                add_vert(
                    bm,
                    centers[k] + (basis * math.cos(2 * math.pi * i / sides) + other * math.sin(2 * math.pi * i / sides)) * radii[k],
                    colors[k],
                )
                for i in range(sides)
            ]
        )
    for k in range(count - 1):
        for i in range(sides):
            j = (i + 1) % sides
            bm.faces.new((rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i]))









def build_chadouf(spec: dict, index: int, lod: int) -> bmesh.types.BMesh:
    """Chadouf : socle et deux piliers de pisé, traverse, perche pivotante (bras long vers +X), contrepoids d'argile, corde et seau."""
    rng = random.Random(spec["seeds"][index])
    bm = new_bmesh()
    mud = spec["colors"]["mud"]
    wood = spec["colors"]["wood"]
    clay = spec["colors"]["clay"]
    rope = spec["colors"]["rope"]
    pillar_height = spec["pillar_height_m"]
    half = spec["pillar_half_spacing_m"]
    platform_radius = spec["platform_radius_m"]
    platform_height = spec["platform_height_m"]
    base_ring = ring(bm, Vector((0.0, 0.0, 0.0)), platform_radius, 6, [c * 0.85 for c in mud])
    top_ring = ring(bm, Vector((0.0, 0.0, platform_height)), platform_radius * 0.8, 6, mud)
    for i in range(6):
        j = (i + 1) % 6
        bm.faces.new((base_ring[i], base_ring[j], top_ring[j], top_ring[i]))
    top_center = add_vert(bm, Vector((0.0, 0.0, platform_height)), mud)
    for i in range(6):
        bm.faces.new((top_ring[(i + 1) % 6], top_ring[i], top_center))
    for side in (-1.0, 1.0):
        centers = [Vector((0.0, side * half, platform_height - 0.05)), Vector((0.0, side * half * 0.7, pillar_height))]
        add_tube(bm, centers, [spec["pillar_radius_m"], spec["pillar_radius_m"] * 0.7], 4, [mud, [c * 0.9 for c in mud]])
    add_tube(bm, [Vector((0.0, -half * 0.8, pillar_height - 0.05)), Vector((0.0, half * 0.8, pillar_height - 0.05))], [0.1, 0.1], 4, [wood, wood])
    back = Vector((-spec["pole_back_m"], 0.0, pillar_height - 0.25))
    pivot = Vector((0.0, 0.0, pillar_height + 0.1))
    tip = Vector((spec["pole_front_m"], 0.0, spec["pole_tip_z_m"]))
    pole_radius = spec["pole_radius_m"]
    add_tube(bm, [back, pivot, tip], [pole_radius * 1.2, pole_radius, pole_radius * 0.7], 4, [wood, wood, wood])
    weight = spec["counterweight_radius_m"]
    add_blob(bm, rng, back + Vector((-0.05, 0.0, -weight)), (weight, weight, weight), 1, 0.12, clay, clay, (0.0, 1.0))
    width = 0.015
    drop = spec["rope_drop_m"]
    bucket_top = tip - Vector((0.0, 0.0, drop))
    bm.faces.new(
        [
            add_vert(bm, tip - Vector((0.0, width, 0.0)), rope),
            add_vert(bm, tip + Vector((0.0, width, 0.0)), rope),
            add_vert(bm, bucket_top + Vector((0.0, width, 0.0)), rope),
            add_vert(bm, bucket_top - Vector((0.0, width, 0.0)), rope),
        ]
    )
    bucket_radius = spec["bucket_radius_m"]
    bottom = bucket_top - Vector((0.0, 0.0, spec["bucket_height_m"]))
    bucket_rings = [ring(bm, bucket_top, bucket_radius, 6, wood), ring(bm, bottom, bucket_radius * 0.75, 6, [c * 0.8 for c in wood])]
    for i in range(6):
        j = (i + 1) % 6
        bm.faces.new((bucket_rings[0][i], bucket_rings[0][j], bucket_rings[1][j], bucket_rings[1][i]))
    bottom_center = add_vert(bm, bottom, wood)
    for i in range(6):
        bm.faces.new((bucket_rings[1][(i + 1) % 6], bucket_rings[1][i], bottom_center))
    return bm


# ---------------------------------------------------------------------------------------------------------------------
# Végétation texturée : cartes de feuillage, troncs d'écorce, palmes
# ---------------------------------------------------------------------------------------------------------------------


def card_frame(normal: Vector, roll: float = 0.0) -> tuple:
    """Repère d'une carte de normale donnée : vecteur « droite » (horizontal avant roulis) et « haut »."""
    n = normal.normalized()
    right = UP.cross(n)
    if right.length < 1e-4:
        right = Vector((1.0, 0.0, 0.0))
    right.normalize()
    up = n.cross(right).normalized()
    if roll != 0.0:
        rotation = Matrix.Rotation(roll, 3, n)
        right = rotation @ right
        up = rotation @ up
    return right, up


def add_card(bm, atlas: Atlas, tile: str, origin: Vector, right: Vector, up: Vector, width: float, height: float, colors: tuple, normal_of, segments: int = 1, bend: Vector = None, sub: tuple = (0.0, 0.0, 1.0, 1.0), anchor_bottom: bool = False) -> None:
    """Carte découpée par l'alpha de l'atlas, en `segments` bandes du bas vers le haut ; bend déplace la pointe (croît
    comme le carré de la hauteur relative). colors : (bas, haut). normal_of(position) donne la normale arrondie."""
    rows = []
    for k in range(segments + 1):
        s = k / segments
        middle = origin + up * (height * (s if anchor_bottom else s - 0.5))
        if bend is not None:
            middle = middle + bend * (s * s)
        color = mix(colors[0], colors[1], s)
        v = sub[1] + (sub[3] - sub[1]) * (1.0 - s)
        left = middle - right * (width * 0.5)
        right_point = middle + right * (width * 0.5)
        rows.append(
            (
                add_vert(bm, left, color, atlas.uv(tile, sub[0], v), normal_of(left)),
                add_vert(bm, right_point, color, atlas.uv(tile, sub[2], v), normal_of(right_point)),
            )
        )
    for k in range(segments):
        a, b = rows[k]
        c, d = rows[k + 1]
        bm.faces.new((a, b, d, c))


def add_bark_tube(bm, atlas: Atlas, tile: str, centers: list, radii: list, sides: int, colors: list, tile_aspect: float) -> None:
    """Tube d'écorce le long d'une ligne brisée (repère transporté sans torsion). Chaque tronçon a ses propres sommets :
    la tuile d'écorce (raccord parfait) y est reprise sur une hauteur proportionnelle à sa longueur, sans étirement ;
    la couture verticale est dédoublée. Normales radiales (tronc arrondi même à peu de côtés)."""
    count = len(centers)
    frames = []
    basis = None
    for k in range(count):
        tangent = (centers[min(k + 1, count - 1)] - centers[max(k - 1, 0)]).normalized()
        if basis is None:
            reference = Vector((1.0, 0.0, 0.0)) if abs(tangent.x) < 0.9 else Vector((0.0, 1.0, 0.0))
            basis = reference - tangent * reference.dot(tangent)
        else:
            basis = basis - tangent * basis.dot(tangent)
        basis.normalize()
        frames.append((basis.copy(), tangent.cross(basis)))
    v_top = 0.0
    for k in range(count - 1):
        length = (centers[k + 1] - centers[k]).length
        circumference = 2.0 * math.pi * max(0.5 * (radii[k] + radii[k + 1]), 0.01)
        span = min(1.0, length / (circumference * tile_aspect))
        v_bottom = 1.0
        v_top = 1.0 - span
        rings = []
        for end, v in ((k, v_bottom), (k + 1, v_top)):
            first, second = frames[end]
            row = []
            for i in range(sides + 1):
                angle = 2.0 * math.pi * i / sides
                radial = first * math.cos(angle) + second * math.sin(angle)
                row.append(add_vert(bm, centers[end] + radial * radii[end], colors[end], atlas.uv(tile, i / sides, v), radial))
            rings.append(row)
        for i in range(sides):
            bm.faces.new((rings[0][i], rings[0][i + 1], rings[1][i + 1], rings[1][i]))


def fibonacci_direction(k: int, count: int, z_min: float) -> Vector:
    """Direction k sur count, répartie régulièrement sur la sphère (spirale d'or), z ramené dans [z_min, 1]."""
    z = 1.0 - 2.0 * (k + 0.5) / count
    z = z_min + (z + 1.0) * 0.5 * (1.0 - z_min)
    r = math.sqrt(max(0.0, 1.0 - z * z))
    phi = k * 2.399963
    return Vector((math.cos(phi) * r, math.sin(phi) * r, z))


def crown_cards(bm, atlas: Atlas, tile: str, center: Vector, radii: tuple, count: int, size: float, colors: tuple, rng: random.Random, settings: dict) -> None:
    """Couronne de cartes de feuillage sur un ellipsoïde : cartes tournées vers l'extérieur (roulis aléatoire), plus
    sombres au cœur et en bas, normales radiales (la couronne s'éclaire comme un volume)."""
    tilt_up = settings.get("tilt_up", 0.0)
    jitter = settings.get("orientation_jitter", 0.45)
    depth_min = settings.get("depth_min", 0.55)
    inner_value = settings.get("inner_value", 0.62)
    ground = settings.get("min_z", -1e9)
    rx, ry, rz = radii

    def normal_of(position: Vector) -> Vector:
        local = position - center
        radial = Vector((local.x / max(rx, 0.01), local.y / max(ry, 0.01), local.z / max(rz, 0.01)))
        return (radial.normalized() * 0.8 + UP * 0.35).normalized()

    # Lobes : la couronne est faite de quelques masses décalées (silhouette irrégulière), tirées d'une graine propre à
    # l'arbre et non au niveau de détail (même silhouette à toutes les distances).
    lobes = [(Vector((0.0, 0.0, 0.0)), 1.0)]
    lobe_rng = random.Random(settings.get("lobe_seed", 0))
    for _ in range(settings.get("lobes", 0)):
        angle = lobe_rng.uniform(0.0, 2.0 * math.pi)
        offset = Vector((math.cos(angle) * rx * 0.42, math.sin(angle) * ry * 0.42, lobe_rng.uniform(-0.25, 0.3) * rz))
        lobes.append((offset, lobe_rng.uniform(0.55, 0.7)))
    for k in range(count):
        lobe_offset, lobe_scale = lobes[k % len(lobes)]
        direction = fibonacci_direction(k // len(lobes), max(count // len(lobes), 1), settings.get("z_min", -0.7))
        depth = rng.uniform(depth_min, 0.95) * lobe_scale
        position = center + lobe_offset + Vector((direction.x * rx * depth, direction.y * ry * depth, direction.z * rz * depth))
        card_size = size * rng.uniform(0.82, 1.15)
        position.z = max(position.z, ground + card_size * 0.4)
        facing = direction + Vector((rng.uniform(-jitter, jitter), rng.uniform(-jitter, jitter), rng.uniform(-jitter, jitter) + tilt_up))
        right, up = card_frame(facing, rng.uniform(-0.6, 0.6))
        height_t = (position.z - (center.z - rz)) / max(2.0 * rz, 0.01)
        outer = (position - center).length / max(rx, ry, rz)
        value = inner_value + (1.0 - inner_value) * min(1.0, max(0.0, (outer - depth_min * 0.6) / max(1.0 - depth_min * 0.6, 0.01)))
        low = scaled(mix(colors[0], colors[1], height_t - 0.25), value)
        high = scaled(mix(colors[0], colors[1], height_t + 0.25), value)
        add_card(bm, atlas, tile, position, right, up, card_size, card_size, (low, high), normal_of)


def surface_quads(bm, atlas: Atlas, tile: str, sub: tuple, center: Vector, radii: tuple, count: int, size: float, color: list, rng: random.Random, z_min: float) -> None:
    """Petits motifs (fruits, fleurs) posés à la surface d'un ellipsoïde, tournés vers l'extérieur."""
    for k in range(count):
        direction = fibonacci_direction(k * 7 + 3, count * 7 + 5, z_min)
        position = center + Vector((direction.x * radii[0], direction.y * radii[1], direction.z * radii[2])) * rng.uniform(0.9, 1.0)
        quad_size = size * rng.uniform(0.85, 1.15)
        tone = scaled(color, rng.uniform(0.94, 1.06))
        # Deux plans verticaux croisés : le motif reste visible sous tous les angles horizontaux (jamais vu par la tranche).
        turn = rng.uniform(0.0, math.pi)
        for facing in (Vector((math.cos(turn), math.sin(turn), 0.0)), Vector((-math.sin(turn), math.cos(turn), 0.0))):
            right, up = card_frame(facing)
            add_card(bm, atlas, tile, position, right, up, quad_size, quad_size, (tone, tone), lambda p, d=direction: d, sub=sub)


def frond_strip(bm, atlas: Atlas, points: list, half_width: float, fold: float, colors: tuple, normal_of) -> None:
    """Palme le long de son rachis (points de la base à la pointe), tuile « palme » de l'atlas (base à gauche) : en V
    (deux demi-bandes relevées de fold radians de part et d'autre du rachis) si fold est donné, sinon à plat."""
    count = len(points) - 1
    rows = []
    for s, point in enumerate(points):
        t = s / count
        tangent = (points[min(s + 1, count)] - points[max(s - 1, 0)]).normalized()
        side = tangent.cross(UP)
        if side.length < 1e-4:
            side = tangent.cross(Vector((1.0, 0.0, 0.0)))
        side.normalize()
        lift = side.cross(tangent).normalized()
        if lift.z < 0.0:
            lift = -lift
        color = mix(colors[0], colors[1], t)
        if fold is not None:
            left = point + (side * math.cos(fold) + lift * math.sin(fold)) * half_width
            right = point + (-side * math.cos(fold) + lift * math.sin(fold)) * half_width
            rows.append(
                (
                    add_vert(bm, left, color, atlas.uv("palme", t, 0.0), normal_of(left)),
                    add_vert(bm, point, color, atlas.uv("palme", t, 0.5), normal_of(point)),
                    add_vert(bm, right, color, atlas.uv("palme", t, 1.0), normal_of(right)),
                )
            )
        else:
            left = point + side * half_width
            right = point - side * half_width
            rows.append(
                (
                    add_vert(bm, left, color, atlas.uv("palme", t, 0.0), normal_of(left)),
                    add_vert(bm, right, color, atlas.uv("palme", t, 1.0), normal_of(right)),
                )
            )
    for s in range(count):
        a = rows[s]
        b = rows[s + 1]
        for c in range(len(a) - 1):
            bm.faces.new((a[c], a[c + 1], b[c + 1], b[c]))


def build_palm(spec: dict, index: int, lod: int, atlas: Atlas) -> bmesh.types.BMesh:
    """Palmier dattier : stipe couvert de bases de palmes (écorce de l'atlas), couronne de palmes pennées en V (les jeunes
    dressées au centre, les anciennes retombantes), quelques palmes sèches pendantes au niveau le plus détaillé."""
    shape = random.Random(spec["seeds"][index] + 1000)  # silhouette commune à tous les niveaux de détail
    bm = new_bmesh()
    height = spec["height_m"][index]
    lean = spec["lean_m"][index]
    segments = spec["trunk_segments"][lod]
    sides = spec["trunk_sides"][lod]
    trunk_color = spec["colors"]["trunk"]
    frond_color = spec["colors"]["frond"]
    dry_color = spec["colors"]["dry_frond"]
    lean_angle = shape.uniform(0, 2 * math.pi)
    lean_dir = Vector((math.cos(lean_angle), math.sin(lean_angle), 0.0))

    def trunk_center(t: float) -> Vector:
        return Vector((lean_dir.x * lean * t * t, lean_dir.y * lean * t * t, height * t))

    base_radius = spec["trunk_radius_m"]
    centers = [trunk_center(s / segments) for s in range(segments + 1)]
    radii = [base_radius * (1.0 + 0.4 * (1.0 - s / segments) ** 6) * (1.0 - 0.12 * s / segments) for s in range(segments + 1)]
    colors = [mix(scaled(trunk_color, 0.78), trunk_color, s / segments) for s in range(segments + 1)]
    add_bark_tube(bm, atlas, "ecorce_palmier", centers, radii, sides, colors, spec["bark_tile_aspect"])

    crown = trunk_center(1.0)
    crown_center = crown + UP * 0.4
    total = spec["frond_count"][0]
    count = spec["frond_count"][lod]
    frond_segments = spec["frond_segments"][lod]
    folded = spec["frond_v"][lod]
    fold = math.radians(spec["frond_fold_deg"])
    # Paramètres tirés une fois pour toutes les palmes ; un niveau moins détaillé en garde une sur deux ou trois,
    # régulièrement réparties de la plus jeune (dressée) à la plus ancienne (retombante).
    fronds = []
    for k in range(total):
        rank = k / max(total - 1, 1)
        fronds.append(
            {
                "azimuth": k * 2.399963 + shape.uniform(-0.2, 0.2),
                "elevation": math.radians(spec["elevation_young_deg"] + (spec["elevation_old_deg"] - spec["elevation_young_deg"]) * rank + shape.uniform(-6.0, 6.0)),
                "length": spec["frond_length_m"] * shape.uniform(0.85, 1.05) * (0.8 + 0.2 * math.sin(math.pi * min(1.0, rank * 1.4))),
                "droop": spec["droop"] * (0.35 + rank),
                "value": 1.0 - spec["old_darkening"] * rank,
            }
        )
    chosen = sorted({round(i * (total - 1) / max(count - 1, 1)) for i in range(count)})

    def normal_of(position: Vector) -> Vector:
        return ((position - crown_center).normalized() * 0.65 + UP * 0.5).normalized()

    for k in chosen:
        frond = fronds[k]
        horizontal = Vector((math.cos(frond["azimuth"]), math.sin(frond["azimuth"]), 0.0))
        length = frond["length"]
        points = []
        for s in range(frond_segments + 1):
            t = s / frond_segments
            points.append(crown + horizontal * (math.cos(frond["elevation"]) * length * t) + UP * (math.sin(frond["elevation"]) * length * t - frond["droop"] * length * t * t))
        low = scaled(mix(frond_color, dry_color, 0.15), frond["value"] * 0.82)
        high = scaled(frond_color, frond["value"])
        frond_strip(bm, atlas, points, length * spec["frond_width_ratio"], fold if folded else None, (low, high), normal_of)

    # Palmes sèches pendues le long du stipe (jupe), dans les teintes de paille.
    for k in range(spec["dry_fronds"][lod]):
        azimuth = shape.uniform(0.0, 2.0 * math.pi)
        horizontal = Vector((math.cos(azimuth), math.sin(azimuth), 0.0))
        length = spec["frond_length_m"] * shape.uniform(0.55, 0.75)
        top = crown - UP * shape.uniform(0.0, 0.25)
        points = [top + horizontal * (0.25 + length * 0.22 * math.sin(math.pi * 0.5 * t)) - UP * (length * t) for t in (0.0, 0.5, 1.0)]
        frond_strip(bm, atlas, points, length * spec["frond_width_ratio"] * 0.8, None, (scaled(dry_color, 0.7), dry_color), normal_of)
    return bm


def build_palm_imposter(spec: dict, atlas: Atlas) -> bmesh.types.BMesh:
    """Imposteur du palmier : deux plans croisés portant la couronne peinte de l'atlas, deux plans pour le stipe."""
    bm = new_bmesh()
    crown_z = spec["crown_z_m"]
    width = spec["crown_width_m"]
    center_y = spec["crown_tile_center_y"]
    trunk_color = spec["colors"]["trunk"]
    frond_color = spec["colors"]["frond"]

    def normal_of(position: Vector) -> Vector:
        return (Vector((position.x, position.y, 0.0)) * 0.15 + UP).normalized()

    for axis in (Vector((1.0, 0.0, 0.0)), Vector((0.0, 1.0, 0.0))):
        add_card(bm, atlas, "ecorce_palmier", Vector((0.0, 0.0, 0.0)), axis, UP, spec["trunk_width_m"], crown_z, (scaled(trunk_color, 0.8), trunk_color), normal_of, anchor_bottom=True)
        origin = Vector((0.0, 0.0, crown_z + width * (0.5 - center_y)))
        add_card(bm, atlas, "couronne_palmier", origin, axis, UP, width, width, (scaled(frond_color, 0.8), frond_color), normal_of)
    return bm


def build_fruit_tree(spec: dict, index: int, lod: int, atlas: Atlas) -> bmesh.types.BMesh:
    """Arbre de verger (grenadier, figuier, olivier) : tronc noueux et maîtresses branches d'écorce, couronne de cartes de
    feuillage de l'espèce ; fruits en petits motifs dont le rouge de sommet dépasse 0,8 (mûrissent selon season_fruit)."""
    rng = random.Random(spec["seeds"][index])
    shape = random.Random(spec["seeds"][index] + 1000)
    bm = new_bmesh()
    height = spec["trunk_height_m"][index]
    lean = spec["lean_m"][index]
    segments = spec["trunk_segments"][lod]
    sides = spec["trunk_sides"][lod]
    trunk_color = spec["colors"]["trunk"]
    lean_angle = shape.uniform(0, 2 * math.pi)
    lean_dir = Vector((math.cos(lean_angle), math.sin(lean_angle), 0.0))
    gnarl = spec["gnarl_m"]
    phase = shape.uniform(0.0, 6.28)

    def trunk_center(t: float) -> Vector:
        wobble = Vector((math.sin(phase + t * 5.0), math.cos(phase * 1.3 + t * 4.0), 0.0)) * gnarl * math.sin(math.pi * t)
        return Vector((lean_dir.x * lean * t * t, lean_dir.y * lean * t * t, height * t)) + wobble

    centers = [trunk_center(s / segments) for s in range(segments + 1)]
    radii = [spec["trunk_radius_m"] * (1.0 + 0.5 * (1.0 - s / segments) ** 3) * (1.0 - 0.3 * s / segments) for s in range(segments + 1)]
    add_bark_tube(bm, atlas, "ecorce_arbre", centers, radii, sides, [mix(scaled(trunk_color, 0.8), trunk_color, s / segments) for s in range(segments + 1)], spec["bark_tile_aspect"])
    fork = centers[-1]
    crown_radius = spec["canopy_radius_m"][index]
    crown_height = spec["canopy_height_m"]
    center = fork + UP * (spec["canopy_rise_m"] + crown_height * 0.35)
    limb_total = spec["limb_count"][0]
    limb_angles = [2 * math.pi * k / max(limb_total, 1) + shape.uniform(-0.3, 0.3) for k in range(limb_total)]
    limb_count = spec["limb_count"][lod]
    limb_segments = spec["limb_segments"][lod]
    for k in range(limb_count):
        angle = limb_angles[round(k * limb_total / limb_count) % limb_total]
        end = center + Vector((math.cos(angle) * crown_radius * 0.55, math.sin(angle) * crown_radius * 0.55, crown_height * 0.15))
        limb_centers = [fork.lerp(end, s / limb_segments) + UP * (0.15 * math.sin(math.pi * s / limb_segments)) for s in range(limb_segments + 1)]
        limb_radii = [spec["limb_radius_m"] * (1.0 - 0.55 * s / limb_segments) for s in range(limb_segments + 1)]
        add_bark_tube(bm, atlas, "ecorce_arbre", limb_centers, limb_radii, spec["limb_sides"][lod], [scaled(trunk_color, 0.85)] * (limb_segments + 1), spec["bark_tile_aspect"])
    radii3 = (crown_radius, crown_radius, crown_height)
    crown_cards(
        bm, atlas, spec["leaf_tile"], center, radii3, spec["card_count"][lod], spec["card_size_m"] * spec["canopy_lod_scale"][lod],
        (spec["colors"]["leaf_low"], spec["colors"]["leaf_high"]), rng, dict(spec["crown"], lobe_seed=spec["seeds"][index] + 3000),
    )
    fruit_count = spec["fruit_count"][lod]
    if fruit_count > 0:
        fruit_rng = random.Random(spec["seeds"][index] + 2000)
        surface_quads(bm, atlas, "fruits_fleurs", SPRITE_CELLS[spec["fruit_sprite"]], center, (crown_radius * 0.92, crown_radius * 0.92, crown_height * 0.92), fruit_count, spec["fruit_size_m"] * 2.0, spec["colors"]["fruit"], fruit_rng, -0.5)
    return bm


def build_acacia(spec: dict, index: int, lod: int, atlas: Atlas) -> bmesh.types.BMesh:
    """Acacia en parasol : tronc court qui se divise en maîtresses branches obliques (puis en rameaux au niveau le plus
    détaillé), couronne plate de cartes de feuillage composé presque horizontales."""
    rng = random.Random(spec["seeds"][index])
    shape = random.Random(spec["seeds"][index] + 1000)
    bm = new_bmesh()
    trunk_height = spec["trunk_height_m"][index]
    lean = spec["lean_m"][index]
    segments = spec["trunk_segments"][lod]
    sides = spec["trunk_sides"][lod]
    trunk_color = spec["colors"]["trunk"]
    lean_angle = shape.uniform(0, 2 * math.pi)
    lean_dir = Vector((math.cos(lean_angle), math.sin(lean_angle), 0.0))
    fork_height = trunk_height * spec["fork_fraction"]
    centers = [Vector((lean_dir.x * lean * (s / segments) ** 2, lean_dir.y * lean * (s / segments) ** 2, fork_height * s / segments)) for s in range(segments + 1)]
    radii = [spec["trunk_radius_m"] * (1.0 + 0.5 * (1.0 - s / segments) ** 3) for s in range(segments + 1)]
    add_bark_tube(bm, atlas, "ecorce_arbre", centers, radii, sides, [mix(scaled(trunk_color, 0.8), trunk_color, s / segments) for s in range(segments + 1)], spec["bark_tile_aspect"])
    fork = centers[-1]
    canopy_radius = spec["canopy_radius_m"][index]
    base = Vector((fork.x, fork.y, trunk_height + spec["canopy_rise_m"]))
    limb_total = spec["limb_count"][0]
    angles = [2 * math.pi * k / limb_total + shape.uniform(-0.3, 0.3) + 0.4 for k in range(limb_total)]
    reaches = [shape.uniform(0.45, 0.7) for _ in range(limb_total)]
    limb_count = spec["limb_count"][lod]
    limb_segments = spec["limb_segments"][lod]
    for k in range(limb_count):
        index_k = round(k * limb_total / limb_count) % limb_total
        angle = angles[index_k]
        outward = Vector((math.cos(angle), math.sin(angle), 0.0))
        end = base + outward * canopy_radius * reaches[index_k] - UP * 0.3
        limb_centers = [fork.lerp(end, s / limb_segments) + outward * (0.25 * math.sin(math.pi * s / limb_segments)) for s in range(limb_segments + 1)]
        limb_radii = [spec["limb_radius_m"] * (1.0 - 0.55 * s / limb_segments) for s in range(limb_segments + 1)]
        add_bark_tube(bm, atlas, "ecorce_arbre", limb_centers, limb_radii, spec["limb_sides"][lod], [scaled(trunk_color, 0.85)] * (limb_segments + 1), spec["bark_tile_aspect"])
        for b in range(spec["branchlets"][lod]):
            side = Vector((-outward.y, outward.x, 0.0)) * (1.0 if b % 2 == 0 else -1.0)
            tip = end + (outward * 0.8 + side * 0.7).normalized() * canopy_radius * 0.35 + UP * 0.25
            add_bark_tube(bm, atlas, "ecorce_arbre", [end, end.lerp(tip, 0.5) + UP * 0.1, tip], [spec["limb_radius_m"] * 0.45, spec["limb_radius_m"] * 0.32, spec["limb_radius_m"] * 0.2], 3, [scaled(trunk_color, 0.85)] * 3, spec["bark_tile_aspect"])
    crown_cards(
        bm, atlas, "grappe_acacia", base, (canopy_radius, canopy_radius, spec["canopy_thickness_m"] * 0.5), spec["card_count"][lod],
        spec["card_size_m"] * spec["canopy_lod_scale"][lod], (spec["colors"]["leaf_low"], spec["colors"]["leaf_high"]), rng,
        dict(spec["crown"], lobe_seed=spec["seeds"][index] + 3000),
    )
    return bm


def build_tamaris(spec: dict, index: int, lod: int, atlas: Atlas) -> bmesh.types.BMesh:
    """Tamaris : quelques tiges sombres qui s'écartent depuis le pied, couronne en dôme de rameaux plumeux gris-vert."""
    rng = random.Random(spec["seeds"][index])
    shape = random.Random(spec["seeds"][index] + 1000)
    bm = new_bmesh()
    height = spec["height_m"][index]
    canopy_radius = spec["canopy_radius_m"][index]
    trunk_color = spec["colors"]["trunk"]
    stem_total = spec["stem_count"][0]
    jitters = [shape.uniform(-0.3, 0.3) for _ in range(stem_total)]
    lengths = [shape.uniform(0.75, 1.0) for _ in range(stem_total)]
    stem_count = spec["stem_count"][lod]
    stem_segments = spec["stem_segments"][lod]
    for k in range(stem_count):
        angle = 2 * math.pi * k / stem_count + jitters[k]
        outward = Vector((math.cos(angle), math.sin(angle), 0.0))
        top = height * 0.65 * lengths[k]
        lean = spec["stem_lean_m"][index]
        centers = [outward * (0.06 + lean * (s / stem_segments) ** 1.5) + UP * (top * s / stem_segments) for s in range(stem_segments + 1)]
        radii = [spec["stem_radius_m"] * (1.0 - 0.55 * s / stem_segments) for s in range(stem_segments + 1)]
        add_bark_tube(bm, atlas, "ecorce_arbre", centers, radii, spec["stem_sides"][lod], [mix(scaled(trunk_color, 0.85), trunk_color, s / stem_segments) for s in range(stem_segments + 1)], spec["bark_tile_aspect"])
    center = Vector((0.0, 0.0, height * spec["canopy_center_fraction"]))
    crown_cards(
        bm, atlas, "grappe_tamaris", center, (canopy_radius, canopy_radius, height * spec["canopy_height_fraction"]), spec["card_count"][lod],
        spec["card_size_m"] * spec["canopy_lod_scale"][lod], (spec["colors"]["leaf_low"], spec["colors"]["leaf_high"]), rng,
        dict(spec["crown"], lobe_seed=spec["seeds"][index] + 3000),
    )
    return bm


def build_tree_imposter(spec: dict, atlas: Atlas) -> bmesh.types.BMesh:
    """Imposteur d'arbre : deux plans croisés pour le tronc (écorce), deux pour la couronne (carte de feuillage de l'espèce)."""
    bm = new_bmesh()
    trunk_color = spec["colors"]["trunk"]
    width = 2.0 * spec["canopy_rx_m"] / spec["tile_fill"]

    def normal_of(position: Vector) -> Vector:
        return (Vector((position.x, position.y, 0.0)) * 0.15 + UP).normalized()

    for axis in (Vector((1.0, 0.0, 0.0)), Vector((0.0, 1.0, 0.0))):
        add_card(bm, atlas, "ecorce_arbre", Vector((0.0, 0.0, 0.0)), axis, UP, spec["trunk_width_m"], spec["trunk_height_m"], (scaled(trunk_color, 0.8), trunk_color), normal_of, anchor_bottom=True)
        origin = Vector((0.0, 0.0, spec["canopy_z_m"]))
        add_card(bm, atlas, spec["leaf_tile"], origin, axis, UP, width, width * spec["tile_aspect"], (spec["colors"]["leaf_low"], spec["colors"]["leaf_high"]), normal_of)
    return bm


def build_shrub(spec: dict, index: int, atlas: Atlas) -> bmesh.types.BMesh:
    """Buisson (buisson, jujubier, laurier-rose) : dôme de cartes de feuillage posé au sol, tiges d'écorce facultatives,
    fleurs facultatives (rouge de sommet supérieur à 0,8 : visibles seulement en floraison)."""
    rng = random.Random(spec["seeds"][index])
    bm = new_bmesh()
    height = spec["height_m"]
    radius = spec["radius_m"]
    colors = spec["colors"]
    for k in range(spec.get("stem_count", 0)):
        angle = 2 * math.pi * k / spec["stem_count"] + rng.uniform(-0.3, 0.3)
        outward = Vector((math.cos(angle), math.sin(angle), 0.0))
        top = height * rng.uniform(0.6, 0.8)
        reach = radius * rng.uniform(0.4, 0.6)
        segments = spec["stem_segments"]
        centers = [outward * (reach * (s / segments) ** 1.4) + UP * (top * s / segments) for s in range(segments + 1)]
        radii = [spec["stem_radius_m"] * (1.0 - 0.5 * s / segments) for s in range(segments + 1)]
        add_bark_tube(bm, atlas, "ecorce_arbre", centers, radii, spec["stem_sides"], [colors["stem"]] * (segments + 1), spec["bark_tile_aspect"])
    center = Vector((0.0, 0.0, height * 0.5))
    settings = dict(spec["crown"], min_z=0.0, lobe_seed=spec["seeds"][index] + 3000)
    crown_cards(bm, atlas, spec["leaf_tile"], center, (radius, radius, height * 0.5), spec["cards"], spec["card_size_m"], (colors["base"], colors["top"]), rng, settings)
    if spec.get("flower_count", 0) > 0:
        surface_quads(bm, atlas, "fruits_fleurs", SPRITE_CELLS[spec["flower_sprite"]], center, (radius * 0.95, radius * 0.95, height * 0.5), spec["flower_count"], spec["flower_size_m"], colors["flower"], rng, 0.0)
    return bm


def build_tuft(spec: dict, index: int, atlas: Atlas) -> bmesh.types.BMesh:
    """Touffe (herbes, alfa, drinn, roseau, jonc, retam, orge, fève, tiges des fleurs) : cartes verticales croisées en
    étoile autour du pied, chacune penchée et légèrement courbée, normales tournées vers le ciel (la touffe s'éclaire
    comme le sol qui la porte). Fleurs facultatives au sommet (rouge de sommet supérieur à 0,8)."""
    rng = random.Random(spec["seeds"][index])
    bm = new_bmesh()
    count = spec["cards"]
    height = spec["height_m"]
    width = 2.0 * spec["radius_m"]
    colors = (spec["colors"]["base"], spec["colors"]["tip"])

    def normal_of(position: Vector) -> Vector:
        return (UP + Vector((position.x, position.y, 0.0)) * spec["normal_spread"]).normalized()

    for k in range(count):
        angle = math.pi * k / count + rng.uniform(-0.25, 0.25)
        right = Vector((math.cos(angle), math.sin(angle), 0.0))
        across = UP.cross(right)
        offset = across * (rng.uniform(-0.12, 0.12) * width)
        lean = across * (height * spec["lean_factor"] * rng.uniform(-1.0, 1.0)) + right * (height * spec["lean_factor"] * rng.uniform(-0.4, 0.4))
        card_height = height * rng.uniform(0.85, 1.1)
        add_card(bm, atlas, spec["tile"], offset, right, UP, width * rng.uniform(0.85, 1.1), card_height, colors, normal_of, segments=spec["card_segments"], bend=lean, anchor_bottom=True)
    for k in range(spec.get("flower_count", 0)):
        angle = 2 * math.pi * k / spec["flower_count"] + rng.uniform(-0.4, 0.4)
        position = Vector((math.cos(angle), math.sin(angle), 0.0)) * (spec["radius_m"] * rng.uniform(0.15, 0.55)) + UP * (height * rng.uniform(0.75, 1.0))
        facing = Vector((math.cos(angle), math.sin(angle), 0.0)) * 0.6 + UP
        right, up = card_frame(facing, rng.uniform(0.0, 6.28))
        size = spec["flower_size_m"] * rng.uniform(0.8, 1.2)
        tone = scaled(spec["colors"]["flower"], rng.uniform(0.95, 1.05))
        add_card(bm, atlas, "fruits_fleurs", position, right, up, size, size, (tone, tone), lambda p, f=facing: f, sub=SPRITE_CELLS[spec["flower_sprite"]])
    return bm


# Réglages d'import Godot imposés aux fichiers produits (les autres lignes du fichier .import, dont l'uid, sont gardées).
# Modèles texturés (végétation) :
SCENE_IMPORT = {
    "header": ["[remap]", "", 'importer="scene"', "importer_version=1", 'type="PackedScene"'],
    "params": {
        # Les niveaux de détail sont faits ici : la simplification automatique de Godot détruirait les cartes.
        "meshes/generate_lods": "false",
        # Ni ombres simplifiées (le shader déplace les sommets : elles ne serviraient pas) ni tangentes (pas de normal map).
        "meshes/create_shadow_meshes": "false",
        "meshes/ensure_tangents": "false",
    },
}
# Modèles opaques sans texture (rochers, falaises, cailloux, bois mort, chadouf) : réglages par défaut de Godot, écrits
# explicitement (la simplification automatique y est sans risque et allège le lointain).
SOLID_SCENE_IMPORT = {
    "header": SCENE_IMPORT["header"],
    "params": {"meshes/generate_lods": "true", "meshes/create_shadow_meshes": "true", "meshes/ensure_tangents": "true"},
}
# Atlas : fichier DDS déjà compressé (BC3) avec ses mipmaps, que Godot garde tels quels.
TEXTURE_IMPORT = {
    "header": ["[remap]", "", 'importer="texture"', 'type="CompressedTexture2D"'],
    "params": {
        "compress/mode": "2",
        "compress/high_quality": "false",
        "compress/normal_map": "2",
        "mipmaps/generate": "true",
        "process/fix_alpha_border": "true",
        "process/premult_alpha": "false",
        "detect_3d/compress_to": "0",
    },
}


def write_import_settings(path: str, settings: dict) -> None:
    """Écrit ou met à jour <path>.import : les clés imposées remplacent les valeurs existantes, le reste est conservé."""
    target = path + ".import"
    lines = []
    if os.path.exists(target):
        with open(target, encoding="utf-8") as handle:
            lines = handle.read().splitlines()
    if not lines:
        lines = list(settings["header"]) + ["", "[params]", ""]
    if "[params]" not in lines:
        lines += ["", "[params]", ""]
    pending = dict(settings["params"])
    for i, line in enumerate(lines):
        key = line.split("=", 1)[0]
        if key in pending:
            lines[i] = f"{key}={pending.pop(key)}"
    start = lines.index("[params]") + 1
    while start < len(lines) and lines[start] == "":
        start += 1
    for key, value in pending.items():
        lines.insert(start, f"{key}={value}")
    with open(target, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(lines) + "\n")


def export(obj: bpy.types.Object, path: str) -> int:
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    # export_vertex_color n'existe qu'à partir de Blender 4.2 (avant, la couleur active est toujours exportée).
    options = {"export_vertex_color": "ACTIVE"} if bpy.app.version >= (4, 2, 0) else {}
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=True, export_yup=True, export_apply=True, export_materials="EXPORT", export_normals=True, export_texcoords=True, **options
    )
    write_import_settings(path, SCENE_IMPORT if len(obj.data.uv_layers) > 0 else SOLID_SCENE_IMPORT)
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def main() -> None:
    args = parse_args()
    with open(args.manifest, encoding="utf-8") as handle:
        manifest = json.load(handle)
    os.makedirs(args.output_dir, exist_ok=True)
    report: dict = {}
    failures: list = []
    # Atlas de la végétation, peint d'abord : les modèles y prennent leurs coordonnées.
    atlas_spec = manifest["atlas"]
    pixels, rects, rects_px = atlas_vegetation.build_atlas(atlas_spec)
    atlas_path = os.path.join(args.output_dir, atlas_spec["file"])
    atlas_vegetation.write_dds_bc3(atlas_path, atlas_vegetation.coverage_mips(pixels, rects_px, atlas_spec["alpha_threshold"]))
    write_import_settings(atlas_path, TEXTURE_IMPORT)
    atlas = Atlas(rects)
    print(f"{atlas_spec['file']}: {pixels.shape[1]} x {pixels.shape[0]} pixels, {len(rects)} tuiles")
    models = manifest["models"]
    jobs = []
    rock = models["rocher"]
    for i, variant in enumerate(rock["variants"]):
        for lod, subdivisions in enumerate(rock["subdivisions"]):
            jobs.append((f"rocher_{variant}_lod{lod}", rock["max_triangles"][lod], lambda i=i, s=subdivisions: build_rock(rock, i, s)))
    palm = models["palmier"]
    for i, variant in enumerate(palm["variants"]):
        for lod in range(3):
            jobs.append((f"palmier_{variant}_lod{lod}", palm["max_triangles"][lod], lambda i=i, lod=lod: build_palm(palm, i, lod, atlas)))
    cliff = models["falaise"]
    for i, variant in enumerate(cliff["variants"]):
        for lod in range(3):
            jobs.append((f"falaise_{variant}_lod{lod}", cliff["max_triangles"][lod], lambda i=i, lod=lod: build_cliff(cliff, i, lod)))
    imposter = models["imposteur_palmier"]
    jobs.append(("palmier_imposteur", imposter["max_triangles"], lambda: build_palm_imposter(imposter, atlas)))
    for shrub_id in ("buisson", "jujubier", "laurier_rose"):
        shrub = models[shrub_id]
        for i, variant in enumerate(shrub["variants"]):
            jobs.append((f"{shrub_id}_{variant}", shrub["max_triangles"], lambda i=i, shrub=shrub: build_shrub(shrub, i, atlas)))
    # Touffes : herbes, couvert du sol, rives des plans d'eau, genêt et cultures basses.
    for tuft_id in ("herbe_seche", "alfa", "drinn", "fleurs", "roseau", "jonc", "retam", "orge", "feve"):
        tuft = models[tuft_id]
        for i, variant in enumerate(tuft["variants"]):
            jobs.append((f"{tuft_id}_{variant}", tuft["max_triangles"], lambda i=i, tuft=tuft: build_tuft(tuft, i, atlas)))
    pebble = models["caillou"]
    for i, variant in enumerate(pebble["variants"]):
        jobs.append((f"caillou_{variant}", pebble["max_triangles"], lambda i=i: build_pebble(pebble, i)))
    slab = models["pierre_plate"]
    for i, variant in enumerate(slab["variants"]):
        jobs.append((f"pierre_plate_{variant}", slab["max_triangles"], lambda i=i: build_flat_stone(slab, i)))
    wood = models["bois_mort"]
    for i, variant in enumerate(wood["variants"]):
        jobs.append((f"bois_mort_{variant}", wood["max_triangles"], lambda i=i: build_dead_wood(wood, i)))
    for tree, builder in (("acacia", build_acacia), ("tamaris", build_tamaris), ("grenadier", build_fruit_tree), ("figuier", build_fruit_tree), ("olivier", build_fruit_tree)):
        spec = models[tree]
        for i, variant in enumerate(spec["variants"]):
            for lod in range(3):
                jobs.append((f"{tree}_{variant}_lod{lod}", spec["max_triangles"][lod], lambda i=i, lod=lod, spec=spec, builder=builder: builder(spec, i, lod, atlas)))
        tree_imposter = models[f"imposteur_{tree}"]
        jobs.append((f"{tree}_imposteur", tree_imposter["max_triangles"], lambda tree_imposter=tree_imposter: build_tree_imposter(tree_imposter, atlas)))
    chadouf = models["chadouf"]
    for i, variant in enumerate(chadouf["variants"]):
        jobs.append((f"chadouf_{variant}", chadouf["max_triangles"], lambda i=i: build_chadouf(chadouf, i, 0)))
    for name, budget, builder in jobs:
        reset_scene()
        material = make_material()
        bm = builder()
        obj = finish(name, bm, material)
        triangles = export(obj, os.path.join(args.output_dir, name + ".glb"))
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
