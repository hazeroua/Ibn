"""Génère les rochers, palmiers, buissons, herbes sèches, l'imposteur de palmier et le couvert du sol (alfa, drinn,
fleurs, cailloux, pierres plates, bois mort) du désert, avec Blender en ligne de commande.

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
