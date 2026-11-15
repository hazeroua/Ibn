"""Génère les rochers, palmiers et l'imposteur de palmier du désert, avec Blender en ligne de commande.

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
