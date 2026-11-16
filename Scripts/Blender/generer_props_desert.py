"""Génère les rochers, palmiers, acacias, tamaris, buissons, herbes sèches, falaises de gorge, les imposteurs d'arbres et le couvert
du sol (alfa, drinn, fleurs, cailloux, pierres plates, bois mort) du désert, avec Blender en ligne de commande.

    blender --background --factory-startup --python Scripts/Blender/generer_props_desert.py -- \
        --manifest Game/data/assets/desert_props.json --output-dir Game/assets/desert --report <rapport.json>

Tout est piloté par le manifeste. Un fichier .glb par modèle et par niveau de détail ; une seule surface
(couleurs de sommets, un seul matériau) par fichier, soit un appel de dessin par instance.
Le résultat est déterministe (graines du manifeste) et les budgets de triangles sont contrôlés ici.
"""

import argparse
import json
import math
import os
import random
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


def finish(name: str, bm: bmesh.types.BMesh, material: bpy.types.Material) -> bpy.types.Object:
    """Convertit en triangles, pose les couleurs de sommets (une couleur par sommet) et crée l'objet."""
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bm.normal_update()
    mesh = bpy.data.meshes.new(name)
    layer = bm.loops.layers.color.new("Col")
    source = bm.verts.layers.float_vector.get("c")
    for face in bm.faces:
        for loop in face.loops:
            loop[layer] = tuple(loop.vert[source]) + (1.0,)
    bm.to_mesh(mesh)
    bm.free()
    # Couleur active et de rendu : sans cela, l'export glTF (export_vertex_color="ACTIVE") n'écrit
    # aucune couleur et le modèle apparaît blanc dans Godot.
    attribute = mesh.color_attributes.get("Col")
    if attribute is None:
        raise RuntimeError(f"{name} : attribut de couleur Col absent")
    mesh.color_attributes.active_color = attribute
    mesh.color_attributes.render_color_index = list(mesh.color_attributes).index(attribute)
    mesh.materials.append(material)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def new_bmesh() -> bmesh.types.BMesh:
    bm = bmesh.new()
    bm.verts.layers.float_vector.new("c")
    return bm


def add_vert(bm: bmesh.types.BMesh, position: Vector, color: tuple) -> bmesh.types.BMVert:
    vert = bm.verts.new(position)
    vert[bm.verts.layers.float_vector.get("c")] = color
    return vert


def mix(a: list, b: list, t: float) -> tuple:
    t = max(0.0, min(1.0, t))
    return tuple(a[i] * (1.0 - t) + b[i] * t for i in range(3))


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


def build_palm(spec: dict, index: int, lod: int) -> bmesh.types.BMesh:
    rng = random.Random(spec["seeds"][index])
    bm = new_bmesh()
    height = spec["height_m"][index]
    lean = spec["lean_m"][index]
    segments = spec["trunk_segments"][lod]
    sides = spec["trunk_sides"][lod]
    trunk_color = spec["colors"]["trunk"]
    frond_color = spec["colors"]["frond"]
    lean_angle = rng.uniform(0, 2 * math.pi)
    lean_dir = Vector((math.cos(lean_angle), math.sin(lean_angle), 0.0))

    def trunk_center(t: float) -> Vector:
        return Vector((lean_dir.x * lean * t * t, lean_dir.y * lean * t * t, height * t))

    rings = []
    for s in range(segments + 1):
        t = s / segments
        radius = 0.28 * (1.0 - 0.45 * t)
        color = mix(trunk_color, [c * 0.8 for c in trunk_color], (s % 2) * 0.5 if lod == 0 else 0.3)
        rings.append(ring(bm, trunk_center(t), radius, sides, color))
    for s in range(segments):
        for i in range(sides):
            j = (i + 1) % sides
            bm.faces.new((rings[s][i], rings[s][j], rings[s + 1][j], rings[s + 1][i]))
    crown = trunk_center(1.0)
    cap = add_vert(bm, crown + Vector((0, 0, 0.1)), trunk_color)
    for i in range(sides):
        bm.faces.new((rings[-1][(i + 1) % sides], rings[-1][i], cap))
    # Palmes : bandes courbes retombantes, deux triangles par segment de largeur 2 côtés.
    count = spec["frond_count"][lod]
    frond_segments = spec["frond_segments"][lod]
    for f in range(count):
        angle = 2 * math.pi * f / count + rng.uniform(-0.15, 0.15)
        direction = Vector((math.cos(angle), math.sin(angle), 0.0))
        side = Vector((-direction.y, direction.x, 0.0))
        length = rng.uniform(3.2, 4.2)
        previous = None
        for s in range(frond_segments + 1):
            t = s / frond_segments
            width = 0.55 * math.sin(math.pi * min(1.0, t * 0.9 + 0.1)) if s < frond_segments else 0.0
            along = length * t
            drop = -0.9 * t * t * length * 0.5 + 0.9 * t * (1.0 - t) * 1.5
            center = crown + direction * along + Vector((0, 0, drop + 0.15))
            color = mix([c * 0.7 for c in frond_color], frond_color, t)
            left = add_vert(bm, center + side * width, color)
            right = add_vert(bm, center - side * width, color) if width > 0 else left
            if previous is not None:
                pl, pr = previous
                if left is right:
                    bm.faces.new((pl, pr, left))
                else:
                    bm.faces.new((pl, pr, right, left))
            previous = (left, right)
    return bm


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


def build_imposter(spec: dict) -> bmesh.types.BMesh:
    """Deux plans croisés : tronc et couronne simplifiés, 12 triangles au plus."""
    bm = new_bmesh()
    height = spec["height_m"]
    width = spec["width_m"]
    trunk_color = spec["colors"]["trunk"]
    frond_color = spec["colors"]["frond"]
    for axis in (Vector((1, 0, 0)), Vector((0, 1, 0))):
        half_trunk = 0.3
        a = add_vert(bm, -axis * half_trunk, trunk_color)
        b = add_vert(bm, axis * half_trunk, trunk_color)
        c = add_vert(bm, axis * (half_trunk * 0.7) + Vector((0, 0, height * 0.85)), trunk_color)
        d = add_vert(bm, -axis * (half_trunk * 0.7) + Vector((0, 0, height * 0.85)), trunk_color)
        bm.faces.new((a, b, c, d))
        crown_z = height * 0.85
        e = add_vert(bm, -axis * width * 0.5 + Vector((0, 0, crown_z - 0.9)), frond_color)
        g = add_vert(bm, axis * width * 0.5 + Vector((0, 0, crown_z - 0.9)), frond_color)
        top = add_vert(bm, Vector((0, 0, height)), frond_color)
        bm.faces.new((e, g, top))
    return bm


def build_bush(spec: dict, index: int) -> bmesh.types.BMesh:
    """Touffe de feuillage : quelques boules irrégulières à facettes, base sombre, sommet clair."""
    rng = random.Random(spec["seeds"][index])
    bm = new_bmesh()
    layer = bm.verts.layers.float_vector.get("c")
    base = spec["colors"]["base"]
    top = spec["colors"]["top"]
    height = spec["height_m"]
    radius = spec["radius_m"]
    for blob in range(spec["blobs"]):
        angle = 2 * math.pi * blob / spec["blobs"] + rng.uniform(-0.4, 0.4)
        offset = radius * 0.45 * (0.0 if blob == 0 else 1.0)
        center = Vector((math.cos(angle) * offset, math.sin(angle) * offset, 0.0))
        size = radius * (0.75 if blob == 0 else rng.uniform(0.5, 0.65))
        part = bmesh.new()
        bmesh.ops.create_icosphere(part, subdivisions=spec["subdivisions"], radius=1.0)
        for vert in part.verts:
            d = vert.co.normalized()
            bump = 1.0 + rng.uniform(-0.18, 0.18)
            co = Vector((d.x * size * bump, d.y * size * bump, max(d.z, -0.35) * size * bump * (height / radius)))
            co += center + Vector((0.0, 0.0, size * 0.35 * (height / radius)))
            new = bm.verts.new(co)
            new[layer] = mix(base, top, max(0.0, co.z) / height + rng.uniform(-0.08, 0.08))
            vert.index = len(bm.verts) - 1
        bm.verts.ensure_lookup_table()
        for face in part.faces:
            bm.faces.new([bm.verts[v.index] for v in face.verts])
        part.free()
    low = min(v.co.z for v in bm.verts)
    for vert in bm.verts:
        vert.co.z -= low + 0.05
    return bm


def build_grass(spec: dict, index: int) -> bmesh.types.BMesh:
    """Touffe d'herbe sèche : brins effilés et courbés (trois triangles par brin), base sombre, pointe claire."""
    rng = random.Random(spec["seeds"][index])
    bm = new_bmesh()
    base = spec["colors"]["base"]
    tip = spec["colors"]["tip"]
    for blade in range(spec["blades"]):
        angle = 2 * math.pi * blade / spec["blades"] + rng.uniform(-0.3, 0.3)
        direction = Vector((math.cos(angle), math.sin(angle), 0.0))
        side = Vector((-direction.y, direction.x, 0.0))
        height = spec["height_m"] * rng.uniform(0.7, 1.15)
        width = spec["blade_width_m"]
        root = direction * rng.uniform(0.0, spec["radius_m"] * 0.4)
        # lean_factor : 1 pour une herbe souple, proche de 0 pour une touffe raide (drinn).
        lean = spec["radius_m"] * rng.uniform(0.6, 1.0) * spec.get("lean_factor", 1.0)
        a = add_vert(bm, root - side * width, base)
        b = add_vert(bm, root + side * width, base)
        mid = root + direction * lean * 0.35 + Vector((0.0, 0.0, height * 0.55))
        c = add_vert(bm, mid + side * width * 0.6, mix(base, tip, 0.55))
        d = add_vert(bm, mid - side * width * 0.6, mix(base, tip, 0.55))
        e = add_vert(bm, root + direction * lean + Vector((0.0, 0.0, height)), tip)
        bm.faces.new((a, b, c, d))
        bm.faces.new((d, c, e))
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


def build_flowers(spec: dict, index: int) -> bmesh.types.BMesh:
    """Fleurs éphémères : quatre tiges (1 triangle) portant chacune une tête de trois pétales (3 triangles)."""
    rng = random.Random(spec["seeds"][index])
    bm = new_bmesh()
    stem_base = spec["colors"]["stem_base"]
    stem_tip = spec["colors"]["stem_tip"]
    petal = spec["colors"]["petal"]
    heart = spec["colors"]["heart"]
    count = spec["flowers"]
    for f in range(count):
        angle = 2 * math.pi * f / count + rng.uniform(-0.4, 0.4)
        direction = Vector((math.cos(angle), math.sin(angle), 0.0))
        side = Vector((-direction.y, direction.x, 0.0))
        root = direction * rng.uniform(0.02, spec["radius_m"] * 0.5)
        height = spec["height_m"] * rng.uniform(0.7, 1.1)
        top = root + direction * spec["radius_m"] * rng.uniform(0.2, 0.5) + Vector((0.0, 0.0, height))
        width = spec["stem_width_m"]
        a = add_vert(bm, root - side * width, stem_base)
        b = add_vert(bm, root + side * width, stem_base)
        c = add_vert(bm, top, stem_tip)
        bm.faces.new((a, b, c))
        head = spec["head_radius_m"] * rng.uniform(0.8, 1.2)
        center = add_vert(bm, top + Vector((0.0, 0.0, 0.005)), heart)
        rim = [
            add_vert(bm, top + Vector((math.cos(angle + 2 * math.pi * k / 3), math.sin(angle + 2 * math.pi * k / 3), 0.35)) * head, petal)
            for k in range(3)
        ]
        for k in range(3):
            bm.faces.new((center, rim[k], rim[(k + 1) % 3]))


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


def build_acacia(spec: dict, index: int, lod: int) -> bmesh.types.BMesh:
    """Acacia en parasol : tronc court en anneaux (comme le palmier), quelques maîtresses branches, couronne plate en boules aplaties."""
    rng = random.Random(spec["seeds"][index])
    shape = random.Random(spec["seeds"][index] + 1000)  # silhouette commune à tous les niveaux de détail
    bm = new_bmesh()
    trunk_height = spec["trunk_height_m"][index]
    lean = spec["lean_m"][index]
    segments = spec["trunk_segments"][lod]
    sides = spec["trunk_sides"][lod]
    trunk_color = spec["colors"]["trunk"]
    lean_angle = shape.uniform(0, 2 * math.pi)
    lean_dir = Vector((math.cos(lean_angle), math.sin(lean_angle), 0.0))

    def trunk_center(t: float) -> Vector:
        return Vector((lean_dir.x * lean * t * t, lean_dir.y * lean * t * t, trunk_height * t))

    rings = []
    for s in range(segments + 1):
        t = s / segments
        radius = spec["trunk_radius_m"] * (1.0 + 0.6 * (1.0 - t) ** 3) * (1.0 - 0.4 * t)
        rings.append(ring(bm, trunk_center(t), radius, sides, mix(trunk_color, [c * 0.7 for c in trunk_color], t * 0.7)))
    for s in range(segments):
        for i in range(sides):
            j = (i + 1) % sides
            bm.faces.new((rings[s][i], rings[s][j], rings[s + 1][j], rings[s + 1][i]))
    fork = trunk_center(1.0)
    cap = add_vert(bm, fork + Vector((0, 0, 0.1)), trunk_color)
    for i in range(sides):
        bm.faces.new((rings[-1][(i + 1) % sides], rings[-1][i], cap))

    canopy_radius = spec["canopy_radius_m"][index]
    thickness = spec["canopy_thickness_m"]
    base = fork + Vector((0.0, 0.0, spec["canopy_rise_m"]))
    # Paramètres des boules et des branches tirés pour le niveau le plus détaillé : les autres niveaux en gardent les premiers.
    subdivisions = spec["canopy_blob_subdivisions"]
    blob_total = len(subdivisions[0])
    blobs = []
    for k in range(blob_total):
        if k == 0:
            blobs.append((Vector((0.0, 0.0, 0.0)), canopy_radius * 0.72))
        else:
            angle = 2 * math.pi * (k - 1) / (blob_total - 1) + shape.uniform(-0.3, 0.3)
            distance = canopy_radius * shape.uniform(0.5, 0.62)
            blobs.append((Vector((math.cos(angle) * distance, math.sin(angle) * distance, shape.uniform(-0.12, 0.12))), canopy_radius * shape.uniform(0.42, 0.54)))
    jitters = [shape.uniform(-0.25, 0.25) for _ in range(spec["limb_count"][0])]

    limb_count = spec["limb_count"][lod]
    limb_segments = spec["limb_segments"][lod]
    limb_sides = spec["limb_sides"][lod]
    for k in range(limb_count):
        angle = 2 * math.pi * k / limb_count + jitters[k] + 0.4
        reach = canopy_radius * 0.55
        start = fork + Vector((0.0, 0.0, -0.15))
        end = base + Vector((math.cos(angle) * reach, math.sin(angle) * reach, -0.25))
        centers = [start.lerp(end, s / limb_segments) + Vector((0.0, 0.0, 0.25 * math.sin(math.pi * s / limb_segments))) for s in range(limb_segments + 1)]
        radii = [spec["limb_radius_m"] * (1.0 - 0.55 * s / limb_segments) for s in range(limb_segments + 1)]
        colors = [mix(trunk_color, [c * 0.7 for c in trunk_color], 0.7)] * (limb_segments + 1)
        add_tube(bm, centers, radii, limb_sides, colors)

    scale = spec["canopy_lod_scale"][lod]
    half = thickness * 0.5
    for k, blob_subdivisions in enumerate(subdivisions[lod]):
        offset, size = blobs[k]
        add_blob(
            bm,
            rng,
            base + offset,
            (size * scale, size * scale, half),
            blob_subdivisions,
            0.14,
            spec["colors"]["leaf_low"],
            spec["colors"]["leaf_high"],
            (base.z - half, base.z + half),
        )
    return bm


def build_tamaris(spec: dict, index: int, lod: int) -> bmesh.types.BMesh:
    """Tamaris : quelques tiges sombres qui s'écartent depuis le pied, couronne touffue gris-vert en dôme de boules à facettes."""
    rng = random.Random(spec["seeds"][index])
    shape = random.Random(spec["seeds"][index] + 1000)
    bm = new_bmesh()
    height = spec["height_m"][index]
    canopy_radius = spec["canopy_radius_m"][index]
    trunk_color = spec["colors"]["trunk"]
    stem_total = spec["stem_count"][0]
    angle_jitters = [shape.uniform(-0.3, 0.3) for _ in range(stem_total)]
    stem_lengths = [shape.uniform(0.75, 1.0) for _ in range(stem_total)]
    stem_leans = [shape.uniform(0.7, 1.2) for _ in range(stem_total)]
    subdivisions = spec["canopy_blob_subdivisions"]
    blob_total = len(subdivisions[0])
    blobs = []
    for k in range(blob_total):
        angle = k * 2.39996 + shape.uniform(-0.2, 0.2)  # angle d'or : couverture régulière sans alignement
        distance = canopy_radius * 0.9 * math.sqrt((k + 0.5) / blob_total)
        rise = 0.55 + 0.4 * (1.0 - distance / canopy_radius)
        blobs.append((Vector((math.cos(angle) * distance, math.sin(angle) * distance, height * rise)), canopy_radius * (0.5 if k < 4 else 0.36)))

    stem_count = spec["stem_count"][lod]
    stem_segments = spec["stem_segments"][lod]
    stem_sides = spec["stem_sides"][lod]
    for k in range(stem_count):
        angle = 2 * math.pi * k / stem_count + angle_jitters[k]
        outward = Vector((math.cos(angle), math.sin(angle), 0.0))
        lean = spec["stem_lean_m"][index] * stem_leans[k]
        top = height * 0.62 * stem_lengths[k]
        centers = [outward * (0.08 + lean * (s / stem_segments) ** 1.5) + Vector((0.0, 0.0, top * s / stem_segments)) for s in range(stem_segments + 1)]
        radii = [spec["stem_radius_m"] * (1.0 - 0.5 * s / stem_segments) for s in range(stem_segments + 1)]
        colors = [mix(trunk_color, [c * 0.75 for c in trunk_color], s / stem_segments) for s in range(stem_segments + 1)]
        add_tube(bm, centers, radii, stem_sides, colors)

    scale = spec["canopy_lod_scale"][lod]
    for k, blob_subdivisions in enumerate(subdivisions[lod]):
        center, size = blobs[k]
        radius = size * scale
        add_blob(
            bm,
            rng,
            center,
            (radius, radius, radius * 0.85),
            blob_subdivisions,
            0.16,
            spec["colors"]["leaf_low"],
            spec["colors"]["leaf_high"],
            (height * 0.3, height * 1.05),
        )
    return bm


def build_tree_imposter(spec: dict) -> bmesh.types.BMesh:
    """Imposteur d'arbre : deux plans croisés (tronc et couronne en hexagone), 12 triangles au plus."""
    bm = new_bmesh()
    half = spec["trunk_width_m"] * 0.5
    trunk_color = spec["colors"]["trunk"]
    low = spec["colors"]["leaf_low"]
    high = spec["colors"]["leaf_high"]
    top_z = spec["trunk_height_m"]
    for axis in (Vector((1, 0, 0)), Vector((0, 1, 0))):
        a = add_vert(bm, -axis * half, trunk_color)
        b = add_vert(bm, axis * half, trunk_color)
        c = add_vert(bm, axis * (half * 0.7) + Vector((0, 0, top_z)), trunk_color)
        d = add_vert(bm, -axis * (half * 0.7) + Vector((0, 0, top_z)), trunk_color)
        bm.faces.new((a, b, c, d))
        crown = []
        for i in range(6):
            angle = math.pi * i / 3
            point = axis * (math.cos(angle) * spec["canopy_rx_m"]) + Vector((0, 0, spec["canopy_z_m"] + math.sin(angle) * spec["canopy_rz_m"]))
            crown.append(add_vert(bm, point, mix(low, high, (math.sin(angle) + 1.0) * 0.5)))
        bm.faces.new(crown)
    return bm


def build_jujubier(spec: dict, index: int, lod: int) -> bmesh.types.BMesh:
    """Jujubier sauvage : motte basse de boules à facettes, hérissée de rameaux pâles en zigzag."""
    rng = random.Random(spec["seeds"][index])
    bm = new_bmesh()
    height = spec["height_m"]
    radius = spec["radius_m"]
    base = spec["colors"]["base"]
    top = spec["colors"]["top"]
    subdivisions = spec["blob_subdivisions"]
    for k, blob_subdivisions in enumerate(subdivisions):
        angle = 2 * math.pi * k / len(subdivisions) + rng.uniform(-0.4, 0.4)
        offset = 0.0 if k == 0 else radius * 0.45
        size = radius * (0.62 if k == 0 else rng.uniform(0.4, 0.52))
        rz = height * rng.uniform(0.36, 0.46)
        center = Vector((math.cos(angle) * offset, math.sin(angle) * offset, rz * 0.8))
        add_blob(bm, rng, center, (size, size, rz), blob_subdivisions, 0.18, base, top, (0.0, height))
    twig_color = spec["colors"]["twig"]
    width = spec["twig_width_m"]
    for k in range(spec["twig_count"]):
        angle = 2 * math.pi * k / spec["twig_count"] + rng.uniform(-0.3, 0.3)
        direction = Vector((math.cos(angle), math.sin(angle), 0.0))
        side = Vector((-direction.y, direction.x, 0.0))
        zig = radius * rng.uniform(0.12, 0.2)
        p0 = direction * radius * 0.25 + Vector((0.0, 0.0, height * 0.3))
        p1 = p0 + direction * radius * 0.5 + side * zig + Vector((0.0, 0.0, height * 0.4))
        p2 = p1 + direction * radius * 0.4 - side * zig * 1.4 + Vector((0.0, 0.0, height * 0.3))
        a0 = add_vert(bm, p0 - side * width, twig_color)
        b0 = add_vert(bm, p0 + side * width, twig_color)
        a1 = add_vert(bm, p1 - side * width, twig_color)
        b1 = add_vert(bm, p1 + side * width, twig_color)
        tip = add_vert(bm, p2, mix(twig_color, top, 0.5))
        bm.faces.new((a0, b0, b1, a1))
        bm.faces.new((a1, b1, tip))
    return bm


def build_laurier_rose(spec: dict, index: int, lod: int) -> bmesh.types.BMesh:
    """Laurier-rose : tiges arquées, deux masses de feuilles sombres et grappes de fleurs roses (rouge des sommets > 0,8 : repérées par le shader)."""
    rng = random.Random(spec["seeds"][index])
    bm = new_bmesh()
    height = spec["height_m"]
    spread = spec["spread_m"]
    colors = spec["colors"]
    stem_total = spec["stem_count"]
    segments = spec["stem_segments"]
    tips = []
    mids = []
    for k in range(stem_total):
        angle = 2 * math.pi * k / stem_total + rng.uniform(-0.3, 0.3)
        outward = Vector((math.cos(angle), math.sin(angle), 0.0))
        top = height * rng.uniform(0.8, 1.0)
        reach = spread * rng.uniform(0.7, 1.0)
        centers = [outward * (reach * (s / segments) ** 1.4) + Vector((0.0, 0.0, top * s / segments)) for s in range(segments + 1)]
        radii = [spec["stem_radius_m"] * (1.0 - 0.5 * s / segments) for s in range(segments + 1)]
        add_tube(bm, centers, radii, spec["stem_sides"], [colors["stem"]] * (segments + 1))
        tips.append((outward, centers[-1]))
        mids.append((outward, centers[0].lerp(centers[-1], 0.75)))
    leaves = spec["leaf_blob_subdivisions"]
    for k, blob_subdivisions in enumerate(leaves):
        size = spread * (0.75 if k == 0 else 0.55)
        center = Vector((rng.uniform(-0.1, 0.1), rng.uniform(-0.1, 0.1), height * (0.5 if k == 0 else 0.78)))
        add_blob(bm, rng, center, (size, size, height * (0.36 if k == 0 else 0.26)), blob_subdivisions, 0.15, colors["leaf_low"], colors["leaf_high"], (0.0, height))
    size = spec["flower_size_m"]
    anchors = tips + mids
    for k in range(spec["flower_count"]):
        outward, anchor = anchors[k % len(anchors)]
        right = Vector((-outward.y, outward.x, 0.0))
        center = anchor + outward * 0.12 + Vector((0.0, 0.0, 0.06))
        color = mix(colors["flower"], colors["flower_light"], rng.uniform(0.0, 1.0))
        corners = [
            add_vert(bm, center - right * size - Vector((0.0, 0.0, size * 0.8)), color),
            add_vert(bm, center + right * size - Vector((0.0, 0.0, size * 0.8)), color),
            add_vert(bm, center + right * size + Vector((0.0, 0.0, size * 0.8)), color),
            add_vert(bm, center - right * size + Vector((0.0, 0.0, size * 0.8)), color),
        ]
        bm.faces.new(corners)
    return bm


def build_retam(spec: dict, index: int, lod: int) -> bmesh.types.BMesh:
    """Retam : petite motte et gerbe de tiges fines et souples qui retombent en balai (trois triangles par tige)."""
    rng = random.Random(spec["seeds"][index])
    bm = new_bmesh()
    height = spec["height_m"]
    radius = spec["radius_m"]
    base = spec["colors"]["base"]
    tip_color = spec["colors"]["tip"]
    add_blob(bm, rng, Vector((0.0, 0.0, height * 0.12)), (radius * 0.3, radius * 0.3, height * 0.18), spec["mound_subdivisions"], 0.12, base, base, (0.0, height))
    width = spec["switch_width_m"]
    for k in range(spec["switch_count"]):
        angle = 2 * math.pi * k / spec["switch_count"] + rng.uniform(-0.25, 0.25)
        direction = Vector((math.cos(angle), math.sin(angle), 0.0))
        side = Vector((-direction.y, direction.x, 0.0))
        root = direction * radius * rng.uniform(0.05, 0.15)
        reach = radius * rng.uniform(0.75, 1.0)
        top = height * rng.uniform(0.8, 1.0)
        mid = root + direction * reach * 0.45 + Vector((0.0, 0.0, top * 0.7))
        tip = root + direction * reach + Vector((0.0, 0.0, top * 0.82))
        a = add_vert(bm, root - side * width, base)
        b = add_vert(bm, root + side * width, base)
        c = add_vert(bm, mid - side * width * 0.7, mix(base, tip_color, 0.5))
        d = add_vert(bm, mid + side * width * 0.7, mix(base, tip_color, 0.5))
        e = add_vert(bm, tip, tip_color)
        bm.faces.new((a, b, d, c))
        bm.faces.new((c, d, e))
    return bm


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
    jobs = []
    rock = manifest["models"]["rocher"]
    for i, variant in enumerate(rock["variants"]):
        for lod, subdivisions in enumerate(rock["subdivisions"]):
            jobs.append((f"rocher_{variant}_lod{lod}", rock["max_triangles"][lod], lambda i=i, s=subdivisions: build_rock(rock, i, s)))
    palm = manifest["models"]["palmier"]
    for i, variant in enumerate(palm["variants"]):
        for lod in range(3):
            jobs.append((f"palmier_{variant}_lod{lod}", palm["max_triangles"][lod], lambda i=i, lod=lod: build_palm(palm, i, lod)))
    cliff = manifest["models"]["falaise"]
    for i, variant in enumerate(cliff["variants"]):
        for lod in range(3):
            jobs.append((f"falaise_{variant}_lod{lod}", cliff["max_triangles"][lod], lambda i=i, lod=lod: build_cliff(cliff, i, lod)))
    imposter = manifest["models"]["imposteur_palmier"]
    jobs.append(("palmier_imposteur", imposter["max_triangles"], lambda: build_imposter(imposter)))
    bush = manifest["models"]["buisson"]
    for i, variant in enumerate(bush["variants"]):
        jobs.append((f"buisson_{variant}", bush["max_triangles"], lambda i=i: build_bush(bush, i)))
    grass = manifest["models"]["herbe_seche"]
    for i, variant in enumerate(grass["variants"]):
        jobs.append((f"herbe_seche_{variant}", grass["max_triangles"], lambda i=i: build_grass(grass, i)))
    cover = manifest["models"]
    for tuft_id in ("alfa", "drinn"):
        tuft = cover[tuft_id]
        for i, variant in enumerate(tuft["variants"]):
            jobs.append((f"{tuft_id}_{variant}", tuft["max_triangles"], lambda i=i, tuft=tuft: build_grass(tuft, i)))
    flowers = cover["fleurs"]
    for i, variant in enumerate(flowers["variants"]):
        jobs.append((f"fleurs_{variant}", flowers["max_triangles"], lambda i=i: build_flowers(flowers, i)))
    pebble = cover["caillou"]
    for i, variant in enumerate(pebble["variants"]):
        jobs.append((f"caillou_{variant}", pebble["max_triangles"], lambda i=i: build_pebble(pebble, i)))
    slab = cover["pierre_plate"]
    for i, variant in enumerate(slab["variants"]):
        jobs.append((f"pierre_plate_{variant}", slab["max_triangles"], lambda i=i: build_flat_stone(slab, i)))
    wood = cover["bois_mort"]
    for i, variant in enumerate(wood["variants"]):
        jobs.append((f"bois_mort_{variant}", wood["max_triangles"], lambda i=i: build_dead_wood(wood, i)))
    for tree in ("acacia", "tamaris"):
        spec = manifest["models"][tree]
        builder = build_acacia if tree == "acacia" else build_tamaris
        for i, variant in enumerate(spec["variants"]):
            for lod in range(3):
                jobs.append((f"{tree}_{variant}_lod{lod}", spec["max_triangles"][lod], lambda i=i, lod=lod, spec=spec, builder=builder: builder(spec, i, lod)))
        tree_imposter = manifest["models"][f"imposteur_{tree}"]
        jobs.append((f"{tree}_imposteur", tree_imposter["max_triangles"], lambda tree_imposter=tree_imposter: build_tree_imposter(tree_imposter)))
    for shrub, builder in (("jujubier", build_jujubier), ("laurier_rose", build_laurier_rose), ("retam", build_retam)):
        spec = manifest["models"][shrub]
        for i, variant in enumerate(spec["variants"]):
            jobs.append((f"{shrub}_{variant}", spec["max_triangles"], lambda i=i, spec=spec, builder=builder: builder(spec, i, 0)))
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
