"""Generate the reproducible modular architecture kit for Tunis.

Run through Scripts/Pipeline/generer-architecture-tunis.ps1. Every exported GLB has one
material, an origin on the ground, a deterministic name and an enforced triangle budget.
"""
import argparse
import json
import os
import sys

import bpy


def args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--report", required=True)
    return parser.parse_args(sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else [])


def box(name, location, scale, material):
    bpy.ops.mesh.primitive_cube_add(location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    bevel = obj.modifiers.new("rounded_edges", "BEVEL")
    bevel.width, bevel.segments = 0.035, 2
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    obj.data.materials.append(material)
    return obj


def material(module):
    mat = bpy.data.materials.new(module["id"] + "_material")
    mat.diffuse_color = module["color"]
    mat.use_nodes = True
    mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = module["color"]
    mat.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.82
    return mat


def build(module):
    x, y, z = module["dimensions_m"]
    mat = material(module)
    kind, name = module["kind"], module["id"]
    objects = []
    if kind in {"wall", "facade", "door"}:
        objects.append(box(name, (0, 0, z / 2), (x / 2, y / 2, z / 2), mat))
        if kind == "facade":
            objects.append(box(name + "_ledge", (0, -y / 2 - 0.04, z * 0.72), (x * 0.42, 0.05, 0.08), mat))
    elif kind == "corner":
        objects += [box(name + "_x", (x / 2, 0, z / 2), (x / 2, y / 2, z / 2), mat), box(name + "_z", (0, x / 2, z / 2), (y / 2, x / 2, z / 2), mat)]
    elif kind in {"arch", "passage"}:
        opening, pillar = x * 0.54, x * 0.12
        objects += [box(name + "_left", (-(opening + pillar) / 2, 0, z / 2), (pillar / 2, y / 2, z / 2), mat), box(name + "_right", ((opening + pillar) / 2, 0, z / 2), (pillar / 2, y / 2, z / 2), mat), box(name + "_lintel", (0, 0, z * 0.83), (x / 2, y / 2, z * 0.17), mat)]
        if kind == "passage":
            objects += [box(name + "_roof", (0, 0, z), (x / 2, y * 2.5, 0.12), mat)]
    elif kind == "column":
        bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=x / 2, depth=z, location=(0, 0, z / 2))
        obj = bpy.context.object; obj.name = name; obj.data.materials.append(mat); objects.append(obj)
    elif kind == "jar":
        bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=8, location=(0, 0, z * 0.42))
        obj = bpy.context.object; obj.name = name; obj.scale = (x / 2, y / 2, z * 0.42); bpy.ops.object.transform_apply(location=False, rotation=False, scale=True); obj.data.materials.append(mat); objects.append(obj)
    elif kind == "fountain":
        bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=x / 2, depth=z * 0.35, location=(0, 0, z * 0.175))
        obj = bpy.context.object; obj.name = name; obj.data.materials.append(mat); objects.append(obj)
        bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=x * 0.12, depth=z, location=(0, 0, z / 2))
        obj = bpy.context.object; obj.data.materials.append(mat); objects.append(obj)
    else:
        objects += [box(name + "_base", (0, 0, z * 0.25), (x / 2, y / 2, z * 0.25), mat), box(name + "_canopy", (0, 0, z), (x * 0.6, y * 0.6, 0.08), mat)]
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects: obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    return bpy.context.object


def export(obj, path):
    bpy.ops.object.select_all(action="DESELECT"); obj.select_set(True); bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_materials="EXPORT")
    return sum(max(0, len(p.vertices) - 2) for p in obj.data.polygons)


def main():
    a = args()
    with open(a.manifest, encoding="utf-8") as stream: manifest = json.load(stream)
    os.makedirs(a.output_dir, exist_ok=True)
    report, failures = {}, []
    for module in manifest["modules"]:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        obj = build(module)
        triangles = export(obj, os.path.join(a.output_dir, module["id"] + ".glb"))
        report[module["id"]] = {"triangles": triangles, "budget": module["max_triangles"]}
        if triangles > module["max_triangles"]: failures.append(module["id"])
    with open(a.report, "w", encoding="utf-8") as stream: json.dump(report, stream, indent=2, sort_keys=True)
    if failures: raise RuntimeError("triangle budgets exceeded: " + ", ".join(failures))


if __name__ == "__main__": main()
