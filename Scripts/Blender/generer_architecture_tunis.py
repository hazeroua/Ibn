"""Build a textured, reproducible modular architectural kit for the Tunis medina.

The atlas is painted procedurally and packed into each GLB. All dimensions and collision
openings retain the versioned catalogue contract used by the city generator.
"""
import argparse
import json
import math
import os
import random
import sys

import bpy


def args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--report", required=True)
    return parser.parse_args(sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else [])


TILES = {
    "plaster": 0,
    "limewash": 1,
    "stone": 2,
    "brick": 3,
    "wood": 4,
    "tile": 5,
    "dark": 6,
    "bronze": 7,
}


def paint_atlas(path):
    size = 512
    cell_w, cell_h = size // 4, size // 2
    colors = [
        (0.77, 0.61, 0.43), (0.86, 0.81, 0.68),
        (0.58, 0.43, 0.30), (0.66, 0.36, 0.22),
        (0.30, 0.16, 0.09), (0.18, 0.40, 0.43),
        (0.16, 0.13, 0.12), (0.61, 0.48, 0.28),
    ]
    rng = random.Random(1348)
    pixels = [0.0] * (size * size * 4)
    for y in range(size):
        for x in range(size):
            tile = (y // cell_h) * 4 + x // cell_w
            u, v = x % cell_w, y % cell_h
            r, g, b = colors[tile]
            fleck = (rng.random() - 0.5) * 0.085
            wash = 0.035 * math.sin(u * 0.12 + v * 0.07) + 0.025 * math.sin(u * 0.43 - v * 0.28)
            if tile == TILES["stone"]:
                course = (v + (u // 48 % 2) * 10) % 36
                if course < 2 or u % 64 < 2:
                    wash -= 0.17
            elif tile == TILES["brick"]:
                if v % 19 < 2 or (u + (v // 19 % 2) * 29) % 58 < 2:
                    wash -= 0.15
            elif tile == TILES["wood"]:
                wash += 0.055 * math.sin(u * 0.42 + 0.08 * math.sin(v * 0.09))
            elif tile == TILES["tile"]:
                diamond = abs((u % 32) - 16) + abs((v % 32) - 16)
                if 14 <= diamond <= 17:
                    r, g, b = (0.84, 0.72, 0.48)
                elif diamond < 9:
                    wash += 0.09
            elif tile == TILES["bronze"]:
                wash += 0.07 * math.sin(u * 0.2)
            index = (y * size + x) * 4
            pixels[index:index + 4] = [
                max(0.0, min(1.0, channel + fleck + wash)) for channel in (r, g, b)
            ] + [1.0]
    image = bpy.data.images.new("tunis_painted_atlas", width=size, height=size, alpha=True)
    image.pixels.foreach_set(pixels)
    image.filepath_raw = path
    image.file_format = "PNG"
    image.save()


def paint_paving(path):
    size = 512
    rng = random.Random(1375)
    pixels = [0.0] * (size * size * 4)
    for y in range(size):
        course = y // 64
        mortar_y = y % 64 < 3
        for x in range(size):
            shifted = (x + (course % 2) * 64) % 128
            mortar = mortar_y or shifted < 3
            wear = 0.035 * math.sin(x * 0.10 + y * 0.07) + (rng.random() - 0.5) * 0.08
            tone = -0.22 if mortar else (0.035 if (course + x // 128) % 3 == 0 else 0.0)
            i = (y * size + x) * 4
            pixels[i:i + 4] = [max(0.0, min(1.0, c + wear + tone)) for c in (0.69, 0.57, 0.43)] + [1.0]
    image = bpy.data.images.new("tunis_paving", width=size, height=size, alpha=True)
    image.pixels.foreach_set(pixels)
    image.filepath_raw = path
    image.file_format = "PNG"
    image.save()


def use_tile(obj, tile):
    uv_layer = obj.data.uv_layers.active
    if uv_layer is None:
        uv_layer = obj.data.uv_layers.new(name="UVMap")
    index = TILES[tile]
    col, row = index % 4, index // 4
    for loop in uv_layer.data:
        u, v = loop.uv
        loop.uv = ((col + 0.025 + 0.95 * u) / 4, (row + 0.025 + 0.95 * v) / 2)


def box(name, location, scale, material, tile="plaster", bevel=0.0):
    bpy.ops.mesh.primitive_cube_add(location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel > 0:
        modifier = obj.modifiers.new("worn_edges", "BEVEL")
        modifier.width, modifier.segments = bevel, 1
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    use_tile(obj, tile)
    obj.data.materials.append(material)
    return obj


def material(module, atlas_path):
    mat = bpy.data.materials.new(module["id"] + "_material")
    mat.diffuse_color = (1.0, 1.0, 1.0, 1.0)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    bsdf = nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = 0.86
    image = nodes.new("ShaderNodeTexImage")
    image.image = bpy.data.images.load(atlas_path, check_existing=True)
    mat.node_tree.links.new(image.outputs["Color"], bsdf.inputs["Base Color"])
    return mat


def cylinder(name, radius, depth, location, mat, tile, vertices=12):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=location)
    obj = bpy.context.object
    obj.name = name
    use_tile(obj, tile)
    obj.data.materials.append(mat)
    return obj


def build_architecture(module, atlas_path):
    x, y, z = module["dimensions_m"]
    mat = material(module, atlas_path)
    kind, name = module["kind"], module["id"]
    objects = []

    def add(suffix, location, scale, tile="plaster", bevel=0.0):
        obj = box(name + suffix, location, scale, mat, tile, bevel)
        objects.append(obj)

    if kind == "wall":
        add("_mass", (0, 0, z * 0.47), (x / 2, y * 0.38, z * 0.47), "plaster", 0.025)
        add("_base", (0, -y * 0.41, z * 0.09), (x / 2, y * 0.09, z * 0.09), "stone")
        add("_back_base", (0, y * 0.41, z * 0.09), (x / 2, y * 0.09, z * 0.09), "stone")
        add("_cordon", (0, -y * 0.41, z * 0.79), (x / 2, y * 0.09, 0.055), "brick")
        bays = 2 if name == "terrace_parapet" else 4
        for index in range(bays):
            bay_x = -x / 2 + x * (index + 0.5) / bays
            if name != "terrace_parapet":
                add(f"_pier_{index}", (bay_x, -y * 0.42, z * 0.47), (x * 0.025, y * 0.08, z * 0.35), "stone")
            add(f"_merlon_{index}", (bay_x, 0, z * 0.97), (x * 0.062, y * 0.32, z * 0.03), "stone")
    elif kind == "corner":
        add("_east", (x / 2, 0, z * 0.47), (x / 2, y / 2, z * 0.47), "stone", 0.025)
        add("_north", (0, x / 2, z * 0.47), (y / 2, x / 2, z * 0.47), "stone", 0.025)
        add("_east_band", (x / 2, -y * 0.42, z * 0.79), (x / 2, y * 0.08, 0.055), "brick")
        add("_north_band", (-y * 0.42, x / 2, z * 0.79), (y * 0.08, x / 2, 0.055), "brick")
        for index in range(2):
            add(f"_top_{index}", (x * (0.25 + index * 0.5), 0, z * 0.97), (x * 0.12, y * 0.35, z * 0.03), "stone")
    elif kind == "facade":
        front = -y / 2 + 0.03
        add("_wall", (0, 0, z / 2), (x / 2, y * 0.46, z / 2), "limewash" if name == "facade_house" else "plaster", 0.025)
        add("_plinth", (0, front, z * 0.08), (x / 2, 0.03, z * 0.08), "stone")
        add("_frieze", (0, front, z * 0.82), (x * 0.48, 0.03, 0.065), "tile")
        add("_cornice", (0, front, z * 0.965), (x / 2, 0.03, 0.09), "stone")
        add("_back_edge", (0, -front, z * 0.85), (x / 2, 0.03, 0.045), "stone")
        for side in (-1, 1):
            sx = side * x * 0.44
            wx = side * x * 0.26
            add(f"_edge_{side}", (sx, front, z * 0.5), (x * 0.025, 0.03, z * 0.42), "stone")
            add(f"_window_{side}", (wx, front, z * 0.60), (x * 0.10, 0.03, z * 0.10), "dark")
            cap = cylinder(f"{name}_window_arch_{side}", x * 0.10, 0.06,
                           (wx, front, z * 0.70), mat, "dark", 10)
            cap.rotation_euler[0] = math.pi / 2
            objects.append(cap)
            add(f"_shutter_{side}", (wx + side * x * 0.07, front - 0.001, z * 0.62), (x * 0.032, 0.031, z * 0.13), "wood")
            add(f"_sill_{side}", (wx, front - 0.001, z * 0.48), (x * 0.13, 0.032, 0.045), "stone")
            add(f"_lattice_{side}", (wx, front - 0.001, z * 0.60), (x * 0.011, 0.031, z * 0.105), "wood")
        add("_door_recess", (0, front, z * 0.24), (x * 0.14, 0.031, z * 0.21), "dark")
        cap = cylinder(name + "_door_arch", x * 0.14, 0.06, (0, front, z * 0.45), mat, "dark", 10)
        cap.rotation_euler[0] = math.pi / 2
        objects.append(cap)
        add("_door_lintel", (0, front - 0.001, z * 0.46), (x * 0.17, 0.032, 0.07), "stone")
        for side in (-1, 1):
            add(f"_door_jamb_{side}", (side * x * 0.16, front - 0.001, z * 0.25), (x * 0.025, 0.032, z * 0.23), "stone")
        if name == "facade_shop":
            add("_awning", (0, front, z * 0.58), (x * 0.38, y * 0.08, 0.045), "wood")
    elif kind == "door":
        add("_panel", (0, 0, z / 2), (x / 2, y / 2, z / 2), "wood", 0.012)
        for side in (-1, 1):
            add(f"_frame_{side}", (side * x * 0.45, -y * 0.4, z / 2), (x * 0.035, y * 0.1, z * 0.48), "bronze")
        for index, level in enumerate((0.2, 0.5, 0.8)):
            add(f"_cross_{index}", (0, -y * 0.4, z * level), (x * 0.43, y * 0.1, z * 0.018), "bronze")
    elif kind in {"arch", "passage"}:
        opening, pillar = x * 0.54, x * 0.12
        front = -y / 2 + 0.04
        for side in (-1, 1):
            center_x = side * (opening + pillar) / 2
            add(f"_pier_{side}", (center_x, 0, z / 2), (pillar / 2, y / 2, z / 2), "stone", 0.025)
            add(f"_foot_{side}", (center_x, front, z * 0.09), (pillar * 0.44, 0.04, z * 0.09), "brick")
        add("_lintel", (0, 0, z * 0.83), (x / 2, y / 2, z * 0.17), "plaster", 0.025)
        for index in range(8):
            x0 = -opening * 0.8 + opening * 1.6 * index / 8
            x1 = -opening * 0.8 + opening * 1.6 * (index + 1) / 8
            h0 = z * 0.66 + 0.11 + z * 0.14 * math.sin(math.pi * index / 8)
            h1 = z * 0.66 + 0.11 + z * 0.14 * math.sin(math.pi * (index + 1) / 8)
            trim = box(f"{name}_arch_{index}", ((x0 + x1) / 2, front, (h0 + h1) / 2),
                       (math.hypot(x1 - x0, h1 - h0) / 2 + 0.025, 0.028, 0.045), mat, "tile")
            trim.rotation_euler[1] = -math.atan2(h1 - h0, x1 - x0)
            objects.append(trim)
        add("_upper_band", (0, front, z * 0.93), (x * 0.39, 0.04, z * 0.035), "tile")
        if kind == "passage":
            add("_roof", (0, 0, z), (x / 2, y * 2.5, 0.12), "wood")
    elif kind == "column":
        objects.append(cylinder(name + "_shaft", x * 0.31, z * 0.8, (0, 0, z * 0.5), mat, "stone", 8))
        add("_foot", (0, 0, z * 0.07), (x / 2, y / 2, z * 0.07), "stone")
        add("_capital", (0, 0, z * 0.93), (x / 2, y / 2, z * 0.07), "tile")
    elif kind == "jar":
        bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=7, location=(0, 0, z * 0.48))
        obj = bpy.context.object
        obj.name = name + "_body"
        obj.scale = (x / 2, y / 2, z * 0.48)
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        use_tile(obj, "brick")
        obj.data.materials.append(mat)
        objects.append(obj)
        objects.append(cylinder(name + "_lip", x * 0.21, z * 0.08, (0, 0, z * 0.96), mat, "stone"))
    elif kind == "fountain":
        objects.append(cylinder(name + "_basin", x / 2, z * 0.22, (0, 0, z * 0.11), mat, "stone", 16))
        objects.append(cylinder(name + "_water", x * 0.44, z * 0.015, (0, 0, z * 0.23), mat, "tile", 16))
        objects.append(cylinder(name + "_column", x * 0.11, z * 0.75, (0, 0, z * 0.59), mat, "stone"))
        objects.append(cylinder(name + "_finial", x * 0.17, z * 0.08, (0, 0, z * 0.96), mat, "bronze"))
    else:
        add("_counter", (0, 0, z * 0.23), (x / 2, y / 2, z * 0.23), "wood")
        for side in (-1, 1):
            add(f"_post_{side}", (side * x * 0.42, -y * 0.35, z * 0.62), (x * 0.035, y * 0.035, z * 0.35), "wood")
        add("_canopy", (0, 0, z * 0.96), (x * 0.6, y * 0.6, z * 0.04), "tile")
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    original_collision_names = {
        "rampart_corner": "rampart_corner_x",
        "city_gate": "city_gate_left",
        "medina_arch": "medina_arch_left",
        "covered_passage": "covered_passage_left",
        "market_stall": "market_stall_base",
    }
    bpy.context.object.name = original_collision_names.get(name, name)
    return bpy.context.object


def export(obj, path):
    bpy.ops.object.select_all(action="DESELECT"); obj.select_set(True); bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_materials="EXPORT")
    return sum(max(0, len(p.vertices) - 2) for p in obj.data.polygons)


def main():
    a = args()
    with open(a.manifest, encoding="utf-8") as stream: manifest = json.load(stream)
    os.makedirs(a.output_dir, exist_ok=True)
    atlas_path = os.path.join(a.output_dir, "tunis_painted_atlas.png")
    paint_atlas(atlas_path)
    paint_paving(os.path.join(a.output_dir, "tunis_paving.png"))
    report, failures = {}, []
    for module in manifest["modules"]:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        obj = build_architecture(module, atlas_path)
        triangles = export(obj, os.path.join(a.output_dir, module["id"] + ".glb"))
        report[module["id"]] = {"triangles": triangles, "budget": module["max_triangles"]}
        if triangles > module["max_triangles"]: failures.append(module["id"])
    with open(a.report, "w", encoding="utf-8") as stream: json.dump(report, stream, indent=2, sort_keys=True)
    if failures: raise RuntimeError("triangle budgets exceeded: " + ", ".join(failures))


if __name__ == "__main__": main()
