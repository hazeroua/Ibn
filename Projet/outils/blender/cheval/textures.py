"""Cheval original du jeu (ticket #106), étape 2 : les textures.

Reprend la forme (forme.blend, écrit par forme.py) et lui donne de vraies textures PBR cuites (couleur, rugosité, normales) :

- robe baie : poil orienté (le long du corps, vers le bas sur les jambes), pommelures discrètes,
  dos plus sombre, ventre et intérieur des membres plus clairs, extrémités noires, ombres de
  creux (occlusion ambiante) peintes dans la couleur ;
- relief musculaire : épaule, avant-bras, poitrail, encolure, côtes, croupe, cuisse, jarret et
  veines du chanfrein, sculptés sur une copie haute définition puis cuits en carte de normales ;
- cuir (grain, rayures, usure des arêtes), laine tissée à bandes, galon, fer piqué de rouille,
  corne striée des sabots, crins mèche à mèche.

Les textures sont des images PNG dans <sortie>/textures/ ; le fichier textures.blend les utilise.
Aucun modèle ni texture tiers.

    blender --background --factory-startup --python-exit-code 1 --python textures.py -- --entree <forme.blend> --sortie <dossier> [--rendus]
"""

import argparse
import bpy
import json
import math
import random
import sys
import time
from pathlib import Path
from mathutils import Vector

_parser = argparse.ArgumentParser()
_parser.add_argument("--entree", required=True)
_parser.add_argument("--sortie", required=True)
_parser.add_argument("--rendus", action="store_true")
ARGS = _parser.parse_args(sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else [])
SOURCE = Path(ARGS.entree)
OUT = Path(ARGS.sortie)
TEXTURES = OUT / "textures"
TEXTURES.mkdir(parents=True, exist_ok=True)
random.seed(1063)
STARTED = time.time()

if not SOURCE.exists():
    raise SystemExit("ERREUR textures.py : forme absente (%s) ; lancez d'abord forme.py." % SOURCE)
bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene

# --- Nettoyage : on ne garde que le cheval et son équipement -------------------------------
for ob in list(bpy.data.objects):
    if ob.type != "MESH" or ob.name.startswith("Galet") or ob.name == "Plane":
        bpy.data.objects.remove(ob, do_unlink=True)


def material_of(ob):
    return ob.data.materials[0].name if ob.data.materials else ""


def join(objects, name):
    bpy.ops.object.select_all(action="DESELECT")
    for ob in objects:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    if len(objects) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    return ob


groups = {}
for ob in list(bpy.data.objects):
    groups.setdefault(material_of(ob), []).append(ob)

# Oreilles et paupières partagent la robe : elles rejoignent la peau (même texture).
skin = join(groups["Baie sombre • robe"], "Cheval_robe")
hair = join(groups["Crins noirs"], "Cheval_crins")
hooves = join(groups["Corne striee"], "Cheval_sabots")
leather = join(groups["Cuir patine"], "Equipement_cuir")
wool = join(groups["Laine ecrue"], "Equipement_tapis")
trim = join(groups["Bordure terre rouge"], "Equipement_galon")
iron = join(groups["Fer bruni"], "Equipement_fer")
stitch = join(groups["Fil de lin"], "Equipement_coutures")
eyes = join(groups["Oeil brun noir"], "Cheval_yeux")
ear_inner = join(groups["Interieur oreille"], "Cheval_creux_oreilles")

for ob in bpy.data.objects:
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    ob.select_set(False)
    for poly in ob.data.polygons:
        poly.use_smooth = True


# --- Relief musculaire : copie sculptée par champs ellipsoïdaux, cuite en normales ---------
# (centre x, |y|, z), rayons (rx, ry, rz), amplitude en mètres (négatif = sillon).
MUSCLES = [
    ((0.42, 0.25, 1.36), (0.20, 0.10, 0.22), 0.016),   # épaule (deltoïde, sus-épineux)
    ((0.36, 0.26, 1.18), (0.12, 0.08, 0.10), 0.012),   # triceps
    ((0.53, 0.20, 1.20), (0.10, 0.10, 0.14), 0.010),   # poitrail (pectoral)
    ((0.44, 0.23, 0.98), (0.07, 0.06, 0.14), 0.008),   # avant-bras
    ((0.50, 0.19, 1.52), (0.06, 0.10, 0.30), -0.006),  # sillon jugulaire
    ((0.62, 0.17, 1.78), (0.10, 0.08, 0.22), 0.009),   # brachio-céphalique
    ((0.72, 0.05, 2.02), (0.18, 0.08, 0.06), 0.008),   # crête de l'encolure
    ((-0.70, 0.22, 1.42), (0.24, 0.14, 0.20), 0.016),  # fessier
    ((-0.80, 0.24, 1.14), (0.12, 0.10, 0.22), 0.014),  # biceps fémoral
    ((-0.66, 0.26, 1.16), (0.03, 0.06, 0.22), -0.007), # sillon de la cuisse
    ((-0.58, 0.22, 0.96), (0.09, 0.07, 0.12), 0.010),  # grasset
    ((-0.62, 0.21, 0.80), (0.07, 0.06, 0.10), 0.008),  # jambe (gastrocnémien)
    ((-0.18, 0.33, 1.42), (0.30, 0.05, 0.07), 0.004),  # surface du dos
    ((-0.05, 0.36, 1.12), (0.16, 0.05, 0.22), -0.003), # creux du flanc
    ((1.10, 0.10, 2.10), (0.10, 0.05, 0.05), 0.004),   # joue (masséter)
]
# Côtes : légères ondulations sur le flanc.
for i in range(7):
    MUSCLES.append(((0.22 - i * 0.075, 0.33, 1.20), (0.018, 0.06, 0.20), -0.0022))


MUSCLE_GAIN = 2.2


def sculpt_offset(co):
    y = abs(co.y)
    total = 0.0
    for (cx, cy, cz), (rx, ry, rz), amp in MUSCLES:
        d = ((co.x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 + ((co.z - cz) / rz) ** 2
        if d < 1.0:
            total += MUSCLE_GAIN * amp * (1.0 - d) ** 2
    # Veines du chanfrein et du bas des membres : fins cordons.
    if co.x > 1.0 and co.z > 1.95 and y > 0.07:
        total += 0.0012 * max(0.0, 1.0 - abs(math.sin(co.x * 55 + co.z * 20)) * 6)
    if co.z < 0.9 and co.z > 0.35:
        total += 0.0008 * max(0.0, 1.0 - abs(math.sin(co.z * 40 + co.x * 9)) * 5)
    return total


high = skin.copy()
high.data = skin.data.copy()
high.name = "Cheval_robe_sculptee"
bpy.context.collection.objects.link(high)
# Même topologie que la peau (60 000 triangles, assez denses pour ce relief) : chaque rayon
# de cuisson retrouve sa face, sans trou aux jonctions (coude, grasset) qu'une subdivision
# déplaçait trop loin de la surface basse.
mesh = high.data
# Normales lues une seule fois : modifier un sommet les invalide, et les relire à chaque
# sommet recalculerait celles de tout le maillage (temps quadratique).
count = len(mesh.vertices)
positions = [0.0] * (count * 3)
normals = [0.0] * (count * 3)
mesh.vertices.foreach_get("co", positions)
mesh.vertices.foreach_get("normal", normals)
for i in range(count):
    p = Vector(positions[i * 3 : i * 3 + 3])
    offset = sculpt_offset(p)
    if offset != 0.0:
        for k in range(3):
            positions[i * 3 + k] += normals[i * 3 + k] * offset
mesh.vertices.foreach_set("co", positions)
mesh.update()
print(f"copie sculptée : {len(mesh.vertices)} sommets, {time.time() - STARTED:.0f} s", flush=True)


# --- UV : dépliage automatique, îlots serrés -----------------------------------------------
def unwrap(ob, margin=0.004):
    t0 = time.time()
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    while ob.data.uv_layers:
        ob.data.uv_layers.remove(ob.data.uv_layers[0])
    ob.data.uv_layers.new(name="UVMap")
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=margin, area_weight=0.0)
    bpy.ops.object.mode_set(mode="OBJECT")
    print(f"dépliage {ob.name} en {time.time() - t0:.0f} s", flush=True)


# --- Outils de nœuds ------------------------------------------------------------------------
def new_material(name):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return m, nt, bsdf


def node(nt, kind, **inputs):
    n = nt.nodes.new(kind)
    for key, value in inputs.items():
        if key in n.inputs:
            n.inputs[key].default_value = value
        else:
            setattr(n, key, value)
    return n


def link(nt, a, b):
    nt.links.new(a, b)


def coords(nt, scale=(1, 1, 1), rotation=(0, 0, 0)):
    tc = node(nt, "ShaderNodeTexCoord")
    mp = node(nt, "ShaderNodeMapping")
    mp.inputs["Scale"].default_value = scale
    mp.inputs["Rotation"].default_value = rotation
    link(nt, tc.outputs["Object"], mp.inputs["Vector"])
    return mp.outputs["Vector"]


def mix(nt, a, b, fac, blend="MIX"):
    m = node(nt, "ShaderNodeMix", data_type="RGBA", blend_type=blend)
    if isinstance(fac, float):
        m.inputs["Factor"].default_value = fac
    else:
        link(nt, fac, m.inputs["Factor"])
    for socket, value in ((m.inputs[6], a), (m.inputs[7], b)):
        if isinstance(value, tuple):
            socket.default_value = (*value, 1.0) if len(value) == 3 else value
        else:
            link(nt, value, socket)
    return m.outputs[2]


def math_node(nt, op, a, b=0.0, clamp=False):
    n = node(nt, "ShaderNodeMath", operation=op, use_clamp=clamp)
    for socket, value in ((n.inputs[0], a), (n.inputs[1], b)):
        if isinstance(value, (int, float)):
            socket.default_value = value
        else:
            link(nt, value, socket)
    return n.outputs[0]


def ramp(nt, fac, stops):
    r = node(nt, "ShaderNodeValToRGB")
    els = r.color_ramp.elements
    while len(els) < len(stops):
        els.new(0.5)
    for el, (pos, col) in zip(els, stops):
        el.position = pos
        el.color = (*col, 1.0) if len(col) == 3 else col
    link(nt, fac, r.inputs[0])
    return r.outputs[0]


def separate_z(nt):
    tc = node(nt, "ShaderNodeTexCoord")
    sep = node(nt, "ShaderNodeSeparateXYZ")
    link(nt, tc.outputs["Object"], sep.inputs[0])
    return sep


def bump(nt, height, strength, distance, normal=None):
    b = node(nt, "ShaderNodeBump")
    b.inputs["Strength"].default_value = strength
    b.inputs["Distance"].default_value = distance
    link(nt, height, b.inputs["Height"])
    if normal is not None:
        link(nt, normal, b.inputs["Normal"])
    return b.outputs["Normal"]


# --- Robe baie ---------------------------------------------------------------------------------
def coat_material_clean():
    m, nt, bsdf = new_material("Robe baie")
    sep = separate_z(nt)
    x, z = sep.outputs["X"], sep.outputs["Z"]
    legs = math_node(nt, "MULTIPLY", math_node(nt, "SUBTRACT", 0.84, z), 7.0, clamp=True)
    belly = math_node(
        nt,
        "MULTIPLY",
        math_node(nt, "MULTIPLY", math_node(nt, "SUBTRACT", 1.30, z), 5.0, clamp=True),
        math_node(nt, "MULTIPLY", math_node(nt, "SUBTRACT", z, 0.90), 6.0, clamp=True),
    )
    back = math_node(nt, "MULTIPLY", math_node(nt, "SUBTRACT", z, 1.58), 6.0, clamp=True)
    muzzle = math_node(nt, "MULTIPLY", math_node(nt, "SUBTRACT", x, 1.30), 7.0, clamp=True)
    ears = math_node(nt, "MULTIPLY", math_node(nt, "SUBTRACT", z, 2.38), 10.0, clamp=True)

    slow = node(nt, "ShaderNodeTexNoise", Scale=3.5, Detail=4.0, Roughness=0.55)
    link(nt, coords(nt), slow.inputs["Vector"])
    color = ramp(nt, slow.outputs["Fac"], [(0.30, (0.055, 0.016, 0.006)), (0.70, (0.095, 0.030, 0.010))])
    color = mix(nt, color, (0.15, 0.060, 0.024), math_node(nt, "MULTIPLY", belly, 0.5))
    color = mix(nt, color, (0.030, 0.010, 0.005), math_node(nt, "MULTIPLY", back, 0.6))

    body_hair = node(nt, "ShaderNodeTexNoise", Scale=1.0, Detail=6.0, Roughness=0.7)
    link(nt, coords(nt, scale=(14, 520, 520)), body_hair.inputs["Vector"])
    leg_hair = node(nt, "ShaderNodeTexNoise", Scale=1.0, Detail=6.0, Roughness=0.7)
    link(nt, coords(nt, scale=(520, 520, 18)), leg_hair.inputs["Vector"])
    strands = node(nt, "ShaderNodeMix", data_type="FLOAT")
    link(nt, legs, strands.inputs["Factor"])
    link(nt, body_hair.outputs["Fac"], strands.inputs[2])
    link(nt, leg_hair.outputs["Fac"], strands.inputs[3])
    strand = strands.outputs[0]
    color = mix(nt, color, ramp(nt, strand, [(0.30, (0.78, 0.78, 0.78)), (0.70, (1.10, 1.10, 1.10))]), 1.0, "MULTIPLY")
    # Reflets du poil couché : plaques allongées dans le sens du poil, à l'échelle du décimètre.
    sheen = node(nt, "ShaderNodeTexNoise", Scale=1.0, Detail=3.0, Roughness=0.5)
    link(nt, coords(nt, scale=(3, 14, 14)), sheen.inputs["Vector"])
    color = mix(nt, color, ramp(nt, sheen.outputs["Fac"], [(0.35, (0.86, 0.86, 0.86)), (0.65, (1.12, 1.12, 1.12))]), 1.0, "MULTIPLY")

    dapple = node(nt, "ShaderNodeTexVoronoi", feature="F1")
    dapple.inputs["Scale"].default_value = 9.0
    link(nt, coords(nt), dapple.inputs["Vector"])
    dap_fac = ramp(nt, dapple.outputs["Distance"], [(0.05, (0.35, 0.35, 0.35)), (0.40, (0, 0, 0))])
    dap_fac = math_node(nt, "MULTIPLY", node_bw(nt, dap_fac), math_node(nt, "SUBTRACT", 1.0, math_node(nt, "MAXIMUM", legs, back)))
    color = mix(nt, color, (0.13, 0.045, 0.016), dap_fac)

    points = math_node(nt, "MAXIMUM", math_node(nt, "MAXIMUM", legs, muzzle), ears)
    black = ramp(nt, strand, [(0.3, (0.010, 0.008, 0.007)), (0.7, (0.026, 0.019, 0.014))])
    color = mix(nt, color, black, points)

    ao = node(nt, "ShaderNodeAmbientOcclusion", samples=8, only_local=True)
    ao.inputs["Distance"].default_value = 0.15
    color = mix(nt, color, ramp(nt, ao.outputs["AO"], [(0.30, (0.42, 0.42, 0.42)), (0.95, (1, 1, 1))]), 1.0, "MULTIPLY")
    geometry = node(nt, "ShaderNodeNewGeometry")
    relief = ramp(nt, geometry.outputs["Pointiness"], [(0.47, (0.80, 0.80, 0.80)), (0.50, (1.0, 1.0, 1.0)), (0.54, (1.35, 1.35, 1.35))])
    color = mix(nt, color, relief, 1.0, "MULTIPLY")
    link(nt, color, bsdf.inputs["Base Color"])
    bsdf.inputs["Specular IOR Level"].default_value = 0.155

    rough = ramp(nt, strand, [(0.3, (0.46, 0.46, 0.46)), (0.7, (0.64, 0.64, 0.64))])
    link(nt, node_bw(nt, rough), bsdf.inputs["Roughness"])
    link(nt, bump(nt, strand, 0.45, 0.0015), bsdf.inputs["Normal"])
    return m


def node_bw(nt, color):
    n = node(nt, "ShaderNodeRGBToBW")
    link(nt, color, n.inputs[0])
    return n.outputs[0]


# --- Crins ---------------------------------------------------------------------------------
def hair_material():
    m, nt, bsdf = new_material("Crins")
    strand = node(nt, "ShaderNodeTexNoise", Scale=1.0, Detail=3.0)
    link(nt, coords(nt, scale=(160, 160, 6)), strand.inputs["Vector"])
    color = ramp(nt, strand.outputs["Fac"], [(0.3, (0.004, 0.003, 0.003)), (0.62, (0.016, 0.011, 0.008)), (0.85, (0.035, 0.021, 0.012))])
    link(nt, color, bsdf.inputs["Base Color"])
    link(nt, node_bw(nt, ramp(nt, strand.outputs["Fac"], [(0.3, (0.68, 0.68, 0.68)), (0.7, (0.82, 0.82, 0.82))])), bsdf.inputs["Roughness"])
    bsdf.inputs["Specular IOR Level"].default_value = 0.3
    link(nt, bump(nt, strand.outputs["Fac"], 0.6, 0.002), bsdf.inputs["Normal"])
    return m


# --- Corne des sabots ----------------------------------------------------------------------
def hoof_material():
    m, nt, bsdf = new_material("Corne")
    sep = separate_z(nt)
    striae = node(nt, "ShaderNodeTexWave", wave_type="BANDS", bands_direction="Z")
    striae.inputs["Scale"].default_value = 1.0
    striae.inputs["Distortion"].default_value = 4.0
    striae.inputs["Detail"].default_value = 3.0
    link(nt, coords(nt, scale=(90, 90, 2)), striae.inputs["Vector"])
    base = ramp(nt, sep.outputs["Z"], [(0.02, (0.020, 0.016, 0.012)), (0.14, (0.050, 0.038, 0.026))])
    color = mix(nt, base, ramp(nt, striae.outputs["Fac"], [(0.2, (0.75, 0.75, 0.75)), (0.8, (1.1, 1.1, 1.1))]), 1.0, "MULTIPLY")
    link(nt, color, bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.62
    link(nt, bump(nt, striae.outputs["Fac"], 0.5, 0.0015), bsdf.inputs["Normal"])
    return m


# --- Cuir ----------------------------------------------------------------------------------
def leather_material():
    m, nt, bsdf = new_material("Cuir")
    grain = node(nt, "ShaderNodeTexVoronoi", feature="F1")
    grain.inputs["Scale"].default_value = 420.0
    link(nt, coords(nt), grain.inputs["Vector"])
    patina = node(nt, "ShaderNodeTexNoise", Scale=6.0, Detail=6.0, Roughness=0.6)
    link(nt, coords(nt), patina.inputs["Vector"])
    scratches = node(nt, "ShaderNodeTexNoise", Scale=1.0, Detail=1.0)
    link(nt, coords(nt, scale=(4, 120, 4), rotation=(0.3, 0.6, 0.2)), scratches.inputs["Vector"])
    scratch = ramp(nt, scratches.outputs["Fac"], [(0.48, (0, 0, 0)), (0.5, (1, 1, 1)), (0.52, (0, 0, 0))])
    edge = node(nt, "ShaderNodeNewGeometry")
    wear = ramp(nt, edge.outputs["Pointiness"], [(0.50, (0, 0, 0)), (0.56, (1, 1, 1))])
    color = ramp(nt, patina.outputs["Fac"], [(0.3, (0.022, 0.010, 0.005)), (0.7, (0.050, 0.023, 0.010))])
    color = mix(nt, color, (0.11, 0.058, 0.028), math_node(nt, "MULTIPLY", node_bw(nt, wear), 0.7))
    color = mix(nt, color, (0.13, 0.070, 0.035), math_node(nt, "MULTIPLY", node_bw(nt, scratch), 0.5))
    ao = node(nt, "ShaderNodeAmbientOcclusion", samples=8, only_local=False)
    ao.inputs["Distance"].default_value = 0.05
    color = mix(nt, color, ramp(nt, ao.outputs["AO"], [(0.2, (0.45, 0.45, 0.45)), (0.95, (1, 1, 1))]), 1.0, "MULTIPLY")
    link(nt, color, bsdf.inputs["Base Color"])
    link(nt, node_bw(nt, ramp(nt, patina.outputs["Fac"], [(0.3, (0.48, 0.48, 0.48)), (0.7, (0.72, 0.72, 0.72))])), bsdf.inputs["Roughness"])
    height = math_node(nt, "ADD", grain.outputs["Distance"], math_node(nt, "MULTIPLY", node_bw(nt, scratch), -0.6))
    link(nt, bump(nt, height, 0.45, 0.0012), bsdf.inputs["Normal"])
    return m


# --- Laine tissée à bandes (tapis) -----------------------------------------------------------
def wool_material():
    m, nt, bsdf = new_material("Laine tissee")
    sep = separate_z(nt)
    # Bandes tissées le long du dos (axe X) : écru, terre rouge, indigo passé, ocre.
    stripes = ramp(
        nt,
        math_node(nt, "FRACT", math_node(nt, "MULTIPLY", math_node(nt, "ADD", sep.outputs["X"], 0.47), 1.25)),
        [
            (0.00, (0.30, 0.20, 0.11)),
            (0.09, (0.30, 0.20, 0.11)),
            (0.10, (0.16, 0.035, 0.018)),
            (0.16, (0.16, 0.035, 0.018)),
            (0.17, (0.30, 0.20, 0.11)),
            (0.20, (0.30, 0.20, 0.11)),
            (0.21, (0.040, 0.045, 0.070)),
            (0.23, (0.040, 0.045, 0.070)),
            (0.24, (0.30, 0.20, 0.11)),
            (0.76, (0.30, 0.20, 0.11)),
            (0.77, (0.22, 0.12, 0.040)),
            (0.83, (0.22, 0.12, 0.040)),
            (0.84, (0.16, 0.035, 0.018)),
            (0.90, (0.16, 0.035, 0.018)),
            (0.91, (0.30, 0.20, 0.11)),
        ],
    )
    weave_a = node(nt, "ShaderNodeTexWave", wave_type="BANDS", bands_direction="X")
    weave_a.inputs["Scale"].default_value = 1.0
    link(nt, coords(nt, scale=(260, 260, 260)), weave_a.inputs["Vector"])
    weave_b = node(nt, "ShaderNodeTexWave", wave_type="BANDS", bands_direction="Y")
    weave_b.inputs["Scale"].default_value = 1.0
    link(nt, coords(nt, scale=(260, 260, 260)), weave_b.inputs["Vector"])
    weave = math_node(nt, "MULTIPLY", weave_a.outputs["Fac"], weave_b.outputs["Fac"])
    fuzz = node(nt, "ShaderNodeTexNoise", Scale=60.0, Detail=8.0)
    link(nt, coords(nt), fuzz.inputs["Vector"])
    dirt = node(nt, "ShaderNodeTexNoise", Scale=4.0, Detail=5.0)
    link(nt, coords(nt), dirt.inputs["Vector"])
    color = mix(nt, stripes, ramp(nt, weave, [(0.0, (0.82, 0.82, 0.82)), (1.0, (1.06, 1.06, 1.06))]), 1.0, "MULTIPLY")
    color = mix(nt, color, (0.20, 0.12, 0.06), math_node(nt, "MULTIPLY", ramp_bw(nt, dirt.outputs["Fac"], 0.55, 0.75), 0.45))
    ao = node(nt, "ShaderNodeAmbientOcclusion", samples=8)
    ao.inputs["Distance"].default_value = 0.05
    color = mix(nt, color, ramp(nt, ao.outputs["AO"], [(0.2, (0.55, 0.55, 0.55)), (0.95, (1, 1, 1))]), 1.0, "MULTIPLY")
    link(nt, color, bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.93
    height = math_node(nt, "ADD", weave, math_node(nt, "MULTIPLY", fuzz.outputs["Fac"], 0.4))
    link(nt, bump(nt, height, 0.55, 0.002), bsdf.inputs["Normal"])
    return m


def ramp_bw(nt, fac, low, high):
    return node_bw(nt, ramp(nt, fac, [(low, (0, 0, 0)), (high, (1, 1, 1))]))


# --- Galon, fer, fil -------------------------------------------------------------------------
def trim_material():
    m, nt, bsdf = new_material("Galon")
    weave = node(nt, "ShaderNodeTexWave", wave_type="BANDS", bands_direction="DIAGONAL")
    weave.inputs["Scale"].default_value = 1.0
    link(nt, coords(nt, scale=(300, 300, 300)), weave.inputs["Vector"])
    color = mix(nt, (0.15, 0.030, 0.015), ramp(nt, weave.outputs["Fac"], [(0.0, (0.75, 0.75, 0.75)), (1.0, (1.1, 1.1, 1.1))]), 1.0, "MULTIPLY")
    link(nt, color, bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.9
    link(nt, bump(nt, weave.outputs["Fac"], 0.6, 0.0015), bsdf.inputs["Normal"])
    return m


def iron_material():
    m, nt, bsdf = new_material("Fer")
    rust = node(nt, "ShaderNodeTexNoise", Scale=40.0, Detail=8.0, Roughness=0.7)
    link(nt, coords(nt), rust.inputs["Vector"])
    rust_mask = ramp_bw(nt, rust.outputs["Fac"], 0.55, 0.68)
    color = mix(nt, (0.16, 0.15, 0.13), (0.14, 0.045, 0.015), rust_mask)
    link(nt, color, bsdf.inputs["Base Color"])
    metallic = math_node(nt, "SUBTRACT", 0.85, math_node(nt, "MULTIPLY", rust_mask, 0.85))
    link(nt, metallic, bsdf.inputs["Metallic"])
    link(nt, math_node(nt, "ADD", 0.38, math_node(nt, "MULTIPLY", rust_mask, 0.5)), bsdf.inputs["Roughness"])
    pits = node(nt, "ShaderNodeTexVoronoi", feature="F1")
    pits.inputs["Scale"].default_value = 300.0
    link(nt, coords(nt), pits.inputs["Vector"])
    link(nt, bump(nt, pits.outputs["Distance"], 0.25, 0.001), bsdf.inputs["Normal"])
    return m


def plain_material(name, rgb, roughness, metallic=0.0):
    m, nt, bsdf = new_material(name)
    bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    return m


# --- Cuisson ---------------------------------------------------------------------------------
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 16
scene.render.bake.margin = 8


def bake_target(ob, image, colorspace):
    for slot in ob.material_slots:
        nt = slot.material.node_tree
        for n in nt.nodes:
            n.select = False
        img = nt.nodes.get("Cuisson") or nt.nodes.new("ShaderNodeTexImage")
        img.name = "Cuisson"
        img.image = image
        image.colorspace_settings.name = colorspace
        img.select = True
        nt.nodes.active = img


def bake(ob, kind, size, suffix, colorspace="sRGB", high_poly=None, samples=16):
    image = bpy.data.images.new(f"{ob.name}_{suffix}", size, size, alpha=False, float_buffer=False)
    image.generated_color = (0.5, 0.5, 1.0, 1.0) if kind == "NORMAL" else (0, 0, 0, 1)
    bake_target(ob, image, colorspace)
    bpy.ops.object.select_all(action="DESELECT")
    scene.cycles.samples = samples
    if high_poly is not None:
        bake_target(high_poly, image, colorspace)
        high_poly.select_set(True)
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    settings = dict(type=kind, margin=8, use_clear=True)
    if kind == "DIFFUSE":
        settings["pass_filter"] = {"COLOR"}
    if high_poly is not None:
        settings.update(use_selected_to_active=True, cage_extrusion=0.09, max_ray_distance=0.18)
    t0 = time.time()
    bpy.ops.object.bake(**settings)
    path = TEXTURES / f"{image.name}.png"
    image.filepath_raw = str(path)
    image.file_format = "PNG"
    image.save()
    print(f"cuisson {image.name} ({kind}, {size}px) en {time.time() - t0:.0f} s", flush=True)
    return image


def bake_object(ob, material, size, high_poly=None):
    ob.data.materials.clear()
    ob.data.materials.append(material)
    unwrap(ob)
    if high_poly is not None:
        high_poly.data.materials.clear()
        high_poly.data.materials.append(material)
    color = bake(ob, "DIFFUSE", size, "couleur", high_poly=high_poly, samples=4)
    rough = bake(ob, "ROUGHNESS", size, "rugosite", "Non-Color", samples=1)
    normal = bake(ob, "NORMAL", size, "normales", "Non-Color", high_poly=high_poly, samples=4)
    final = textured_material(material.name + " (textures)", color, rough, normal, metallic_value=0.6 if material.name == "Fer" else 0.0)
    ob.data.materials.clear()
    ob.data.materials.append(final)
    return [color, rough, normal]


def textured_material(name, color, rough, normal, metallic_value=0.0):
    m, nt, bsdf = new_material(name)
    tc = node(nt, "ShaderNodeTexImage")
    tc.image = color
    tr = node(nt, "ShaderNodeTexImage")
    tr.image = rough
    tn = node(nt, "ShaderNodeTexImage")
    tn.image = normal
    nm = node(nt, "ShaderNodeNormalMap")
    link(nt, tc.outputs["Color"], bsdf.inputs["Base Color"])
    link(nt, tr.outputs["Color"], bsdf.inputs["Roughness"])
    link(nt, tn.outputs["Color"], nm.inputs["Color"])
    link(nt, nm.outputs["Normal"], bsdf.inputs["Normal"])
    bsdf.inputs["Metallic"].default_value = metallic_value
    return m


report = {"textures": [], "objets": {}}
plan = [
    (skin, coat_material_clean(), 2048, high),
    (hair, hair_material(), 1024, None),
    (hooves, hoof_material(), 512, None),
    (leather, leather_material(), 1024, None),
    (wool, wool_material(), 1024, None),
    (trim, trim_material(), 512, None),
    (iron, iron_material(), 512, None),
]
for ob, material, size, hp in plan:
    images = bake_object(ob, material, size, hp)
    report["textures"] += [f"textures/{im.name}.png" for im in images]
bpy.data.objects.remove(high, do_unlink=True)
for ob, rgb, rough in [(stitch, (0.30, 0.21, 0.11), 0.85), (ear_inner, (0.045, 0.022, 0.016), 0.9)]:
    ob.data.materials.clear()
    ob.data.materials.append(plain_material(ob.name, rgb, rough))
eyes.data.materials.clear()
eyes.data.materials.append(plain_material("Oeil", (0.010, 0.005, 0.003), 0.12))

# --- Sauvegarde : textures.blend (chemins des images relatifs au dossier de sortie) -----------
for image in bpy.data.images:
    if image.filepath_raw.startswith(str(TEXTURES)):
        image.filepath_raw = "//" + str(Path(image.filepath_raw).relative_to(OUT)).replace("\\", "/")
asset = [ob for ob in bpy.data.objects if ob.type == "MESH"]
triangles = 0
for ob in asset:
    ob.data.calc_loop_triangles()
    triangles += len(ob.data.loop_triangles)
    report["objets"][ob.name] = len(ob.data.loop_triangles)
report.update({"triangles": triangles, "duree_secondes": round(time.time() - STARTED)})
bpy.ops.wm.save_as_mainfile(filepath=str(OUT / "textures.blend"))
(OUT / "textures.json").write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding="utf8")
if not ARGS.rendus:
    sys.exit(0)


# --- Banc d'essai de rendu (même décor que l'itération 2) -------------------------------------
def ground():
    m, nt, bsdf = new_material("Reg ocre")
    tex = node(nt, "ShaderNodeTexNoise", Scale=7.0)
    link(nt, coords(nt), tex.inputs["Vector"])
    link(nt, ramp(nt, tex.outputs["Fac"], [(0.3, (0.10, 0.050, 0.019)), (0.7, (0.43, 0.30, 0.15))]), bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.96
    fine = node(nt, "ShaderNodeTexNoise", Scale=260.0)
    link(nt, coords(nt), fine.inputs["Vector"])
    link(nt, bump(nt, fine.outputs["Fac"], 0.6, 0.025), bsdf.inputs["Normal"])
    bpy.ops.mesh.primitive_plane_add(size=2000)
    bpy.context.object.data.materials.append(m)


ground()
world = scene.world
world.use_nodes = True
ns, ls = world.node_tree.nodes, world.node_tree.links
sky = ns.get("Sky Texture") or ns.new("ShaderNodeTexSky")
sky.sky_type = "MULTIPLE_SCATTERING"
sky.sun_disc = True
sky.sun_size = 0.009
sky.sun_intensity = 0.7
ls.new(sky.outputs["Color"], ns.get("Background").inputs["Color"])
ns.get("Background").inputs["Strength"].default_value = 0.065
bpy.ops.object.light_add(type="SUN")
sun = bpy.context.object
sun.data.angle = 0.03
bpy.ops.object.camera_add()
camera = bpy.context.object
scene.camera = camera
scene.cycles.samples = 48
scene.cycles.use_denoising = True
scene.render.resolution_x = 1400
scene.render.resolution_y = 1000
scene.view_settings.view_transform = "AgX"
scene.view_settings.look = "AgX - Medium High Contrast"
scene.view_settings.exposure = 0.35

renders = [
    ("midi", 65, 2.5, (1, 0.97, 0.90), (3.3, -5.6, 2.6), (0.15, 0, 1.25), 52),
    ("soir", 12, 1.8, (1, 0.65, 0.35), (3.3, -5.6, 2.6), (0.15, 0, 1.25), 52),
    ("profil", 35, 2.2, (1, 0.89, 0.74), (0.2, -6.6, 2.2), (0.15, 0, 1.25), 52),
    ("gros-plan-tete", 40, 2.3, (1, 0.92, 0.80), (2.2, -1.6, 2.35), (1.15, 0, 2.08), 70),
    ("gros-plan-selle", 45, 2.3, (1, 0.92, 0.80), (0.9, -2.2, 2.2), (-0.05, 0, 1.55), 60),
]
for name, elevation, energy, colour, position, target, lens in renders:
    sky.sun_elevation = math.radians(elevation)
    sky.sun_rotation = math.radians(130)
    sun.rotation_euler = (math.radians(90 - elevation), math.radians(-20), math.radians(-35))
    sun.data.energy = energy
    sun.data.color = colour
    camera.location = position
    camera.data.lens = lens
    camera.rotation_euler = (Vector(target) - camera.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = str(OUT / f"{name}.png")
    t0 = time.time()
    bpy.ops.render.render(write_still=True)
    print(f"rendu {name} en {time.time() - t0:.0f} s", flush=True)
print("rendus terminés", flush=True)
