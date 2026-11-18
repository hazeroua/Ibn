"""Build a textured, reproducible modular architectural kit for the Tunis medina.

The atlas is painted procedurally and packed into each GLB. All dimensions and collision
openings retain the versioned catalogue contract used by the city generator.
"""
import argparse
from array import array
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
    references = {
        TILES["plaster"]: ("patterned_clay_plaster.jpg", 0.24),
        TILES["limewash"]: ("white_rough_plaster.jpg", 0.19),
        TILES["stone"]: ("white_sandstone_bricks.jpg", 0.50),
        TILES["wood"]: ("rough_wood.jpg", 0.48),
    }
    source_images = {}
    for tile, (filename, strength) in references.items():
        source_path = os.path.join(os.path.dirname(path), "material_sources", filename)
        source = bpy.data.images.load(source_path, check_existing=True)
        data = array("f", [0.0]) * (source.size[0] * source.size[1] * 4)
        source.pixels.foreach_get(data)
        source_images[tile] = (data, source.size[0], source.size[1], strength)
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
            if tile in source_images:
                data, source_width, source_height, strength = source_images[tile]
                sample_x = min(source_width - 1, u * source_width // cell_w)
                sample_y = min(source_height - 1, v * source_height // cell_h)
                sample = (sample_y * source_width + sample_x) * 4
                r = r * (1.0 - strength) + data[sample] * strength
                g = g * (1.0 - strength) + data[sample + 1] * strength
                b = b * (1.0 - strength) + data[sample + 2] * strength
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


def arch_ring(name, center_x, front_y, spring_z, radius, mat, tile, rise_ratio=1.0):
    """A real, thick half-arch: the void behind it remains visibly recessed."""
    vertices = []
    faces = []
    segments = 12
    for i in range(segments + 1):
        angle = math.pi * (1.0 - i / segments)
        for depth in (0.0, 0.07):
            for ring_radius in (radius, radius + 0.11):
                vertices.append((center_x + ring_radius * math.cos(angle),
                                 front_y + depth, spring_z + ring_radius * rise_ratio * math.sin(angle)))
    for i in range(segments):
        a, b = i * 4, (i + 1) * 4
        faces.extend(((a, b, b + 1, a + 1), (a + 2, a + 3, b + 3, b + 2),
                      (a, a + 2, b + 2, b), (a + 1, b + 1, b + 3, a + 3)))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    uv = mesh.uv_layers.new(name="UVMap")
    for face in mesh.polygons:
        for loop_index in face.loop_indices:
            vertex = mesh.vertices[mesh.loops[loop_index].vertex_index].co
            uv.data[loop_index].uv = ((vertex.x - center_x) / (2.0 * radius + 0.3) + 0.5,
                                      (vertex.z - spring_z) / (radius + 0.3))
    use_tile(obj, tile)
    obj.data.materials.append(mat)
    return obj


def arch_spandrel(name, half_width, depth, spring_z, rise, top, mat):
    """Masonry above a curved opening; its underside follows a shallow Tunisian arch."""
    vertices, faces = [], []
    segments = 16
    for i in range(segments + 1):
        x = -half_width + 2.0 * half_width * i / segments
        ratio = x / half_width
        bottom = spring_z + rise * math.sqrt(max(0.0, 1.0 - ratio * ratio))
        vertices.extend(((x, -depth / 2, bottom), (x, -depth / 2, top),
                         (x, depth / 2, bottom), (x, depth / 2, top)))
    for i in range(segments):
        a, b = i * 4, (i + 1) * 4
        faces.extend(((a, a + 1, b + 1, b), (a + 2, b + 2, b + 3, a + 3),
                      (a, b, b + 2, a + 2), (a + 1, a + 3, b + 3, b + 1)))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    uv = mesh.uv_layers.new(name="UVMap")
    for face in mesh.polygons:
        for loop_index in face.loop_indices:
            vertex = mesh.vertices[mesh.loops[loop_index].vertex_index].co
            uv.data[loop_index].uv = ((vertex.x / half_width + 1.0) / 2.0,
                                      (vertex.z - spring_z) / (top - spring_z))
    use_tile(obj, "plaster")
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

    if kind == "roof_mass":
        add("_body", (0, 0, z * 0.49), (x / 2, y / 2, z * 0.49), "plaster")
        add("_roof", (0, 0, z * 0.985), (x / 2, y / 2, z * 0.015), "limewash")
    elif kind == "minaret":
        # A compact Hafsid-inspired square shaft with a real projecting gallery and
        # open lantern. One landmark is placed above the mosque, never tiled as a wall.
        add("_base", (0, 0, z * 0.10), (x * 0.46, y * 0.46, z * 0.10), "stone")
        add("_shaft", (0, 0, z * 0.49), (x * 0.34, y * 0.34, z * 0.38), "limewash")
        for level in (0.19, 0.43, 0.70):
            add(f"_band_{int(level * 100)}", (0, 0, z * level),
                (x * 0.37, y * 0.37, z * 0.012), "tile")
        add("_gallery_floor", (0, 0, z * 0.80), (x * 0.50, y * 0.50, z * 0.025), "stone")
        for side in (-1, 1):
            for axis in (0, 1):
                loc = (side * x * 0.43, 0, z * 0.85) if axis == 0 else (0, side * y * 0.43, z * 0.85)
                scale = (x * 0.035, y * 0.43, z * 0.05) if axis == 0 else (x * 0.43, y * 0.035, z * 0.05)
                add(f"_gallery_{side}_{axis}", loc, scale, "stone")
        for cx in (-x * 0.28, x * 0.28):
            for cy in (-y * 0.28, y * 0.28):
                add(f"_lantern_{cx:.1f}_{cy:.1f}", (cx, cy, z * 0.92),
                    (x * 0.045, y * 0.045, z * 0.09), "stone")
        add("_lantern_roof", (0, 0, z * 0.99), (x * 0.40, y * 0.40, z * 0.01), "tile")
    elif kind == "wall":
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
        wall_tile = "limewash" if name.startswith("facade_house") else "plaster"
        # Structural backing sits half a metre behind the plaster face. The gaps in the
        # street skin are actual geometry, so side reveals catch light and cast shadows.
        add("_backing", (0, y * 0.25, z / 2), (x / 2, y * 0.23, z / 2), wall_tile)
        skin_y = -y * 0.18
        skin_half_depth = y * 0.16

        def skin(suffix, left, right, low, high):
            add(suffix, ((left + right) / 2, skin_y, (low + high) / 2),
                ((right - left) / 2, skin_half_depth, (high - low) / 2), wall_tile)

        door_half = x * 0.14
        window_half = x * 0.10
        window_low, window_top = z * 0.50, z * 0.75
        door_top = min(z * 0.58, 2.65)
        window_left = -x * 0.26
        window_right = x * 0.26
        skin("_outer_l", -x / 2, window_left - window_half, 0, z)
        skin("_outer_r", window_right + window_half, x / 2, 0, z)
        skin("_post_l", window_left + window_half, -door_half, 0, z)
        skin("_post_r", door_half, window_right - window_half, 0, z)
        skin("_door_header", -door_half, door_half, door_top, z)
        for side, wx in ((-1, window_left), (1, window_right)):
            skin(f"_window_lower_{side}", wx - window_half, wx + window_half, 0, window_low)
            skin(f"_window_upper_{side}", wx - window_half, wx + window_half, window_top, z)
            add(f"_window_back_{side}", (wx, -0.005, (window_low + window_top) / 2),
                (window_half, 0.016, (window_top - window_low) / 2), "dark")
            add(f"_window_reveal_l_{side}", (wx - window_half, skin_y, (window_low + window_top) / 2),
                (0.035, y * 0.17, (window_top - window_low) / 2), "stone")
            add(f"_window_reveal_r_{side}", (wx + window_half, skin_y, (window_low + window_top) / 2),
                (0.035, y * 0.17, (window_top - window_low) / 2), "stone")
            add(f"_window_reveal_top_{side}", (wx, skin_y, window_top),
                (window_half, y * 0.17, 0.035), "stone")
            objects.append(arch_ring(f"{name}_window_arch_{side}", wx, front - 0.005,
                                     window_top - window_half, window_half, mat, "stone"))
            # The projecting timber grille and hood create a silhouette from the street.
            add(f"_oriel_{side}", (wx, front + 0.09, (window_low + window_top) / 2),
                (window_half * 0.85, 0.085, (window_top - window_low) * 0.40), "wood")
            add(f"_oriel_hood_{side}", (wx, front + 0.04, window_top + 0.055),
                (window_half * 1.20, 0.15, 0.05), "wood")
            for bar in (-1, 0, 1):
                add(f"_grille_{side}_{bar}", (wx + bar * window_half * 0.45, front - 0.002,
                    (window_low + window_top) / 2), (0.026, 0.02, (window_top - window_low) * 0.45), "bronze")
        add("_door_back", (0, -0.005, door_top / 2), (door_half, 0.016, door_top / 2), "wood")
        for side in (-1, 1):
            add(f"_door_reveal_{side}", (side * door_half, skin_y, door_top / 2),
                (0.04, y * 0.17, door_top / 2), "stone")
        objects.append(arch_ring(name + "_door_arch", 0, front - 0.005,
                                 door_top - door_half, door_half, mat, "stone"))
        add("_plinth", (0, front, z * 0.08), (x / 2, 0.03, z * 0.08), "stone")
        add("_frieze", (0, front, z * 0.82), (x * 0.48, 0.03, 0.065), "tile")
        add("_cornice", (0, front, z * 0.965), (x / 2, 0.03, 0.09), "stone")
        add("_back_edge", (0, -front, z * 0.85), (x / 2, 0.03, 0.045), "stone")
        for side in (-1, 1):
            sx = side * x * 0.44
            add(f"_edge_{side}", (sx, front, z * 0.5), (x * 0.025, 0.03, z * 0.42), "stone")
        add("_door_step", (0, front - 0.005, 0.045), (door_half * 1.18, 0.04, 0.045), "stone")
        if name == "facade_house_loggia":
            # A single raised timber gallery joins the two upper bays. It projects
            # from the recessed wall and has its own posts, sill and deep eaves.
            add("_gallery_floor", (0, front + y * 0.21, window_low - 0.05),
                (x * 0.36, y * 0.22, 0.075), "wood")
            add("_gallery_rail", (0, front - 0.005, window_low + z * 0.085),
                (x * 0.34, 0.035, 0.05), "wood")
            for index in range(7):
                gx = -x * 0.33 + index * x * 0.11
                add(f"_gallery_baluster_{index}",
                    (gx, front - 0.005, window_low + z * 0.04),
                    (0.025, 0.035, z * 0.09), "wood")
            add("_gallery_eaves", (0, front + y * 0.22, window_top + 0.12),
                (x * 0.39, y * 0.25, 0.075), "wood")
        if name == "facade_shop":
            add("_awning", (0, front + 0.18, z * 0.60), (x * 0.41, y * 0.27, 0.06), "wood")
            for side in (-1, 1):
                add(f"_awning_brace_{side}", (side * x * 0.37, front + 0.15, z * 0.55),
                    (0.04, y * 0.18, z * 0.09), "wood")
    elif kind == "door":
        add("_panel", (0, 0, z / 2), (x / 2, y / 2, z / 2), "wood", 0.012)
        for side in (-1, 1):
            add(f"_frame_{side}", (side * x * 0.45, -y * 0.4, z / 2), (x * 0.035, y * 0.1, z * 0.48), "bronze")
        for index, level in enumerate((0.2, 0.5, 0.8)):
            add(f"_cross_{index}", (0, -y * 0.4, z * level), (x * 0.43, y * 0.1, z * 0.018), "bronze")
    elif kind in {"arch", "passage"}:
        opening, pillar = x * 0.54, x * 0.12
        half_opening = opening / 2
        spring = z * 0.66
        rise = min(z * 0.18, half_opening * 0.55)
        front = -y / 2 + 0.04
        for side in (-1, 1):
            center_x = side * (opening + pillar) / 2
            add(f"_pier_{side}", (center_x, 0, z / 2), (pillar / 2, y / 2, z / 2), "stone", 0.025)
            add(f"_foot_{side}", (center_x, front, z * 0.09), (pillar * 0.44, 0.04, z * 0.09), "brick")
        objects.append(arch_spandrel(name + "_curved_masonry", half_opening,
                                     y, spring, rise, z, mat))
        for side in (-1, 1):
            shoulder = (x / 2 - (opening + pillar) / 2 - pillar / 2)
            add(f"_shoulder_{side}",
                (side * (x / 2 - shoulder / 2), 0, (spring + z) / 2),
                (shoulder / 2, y / 2, (z - spring) / 2), "plaster")
        objects.append(arch_ring(name + "_arch_moulding", 0, front - 0.005,
                                 spring, half_opening, mat, "tile", rise / half_opening))
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
