"""Cheval original du jeu (ticket #106), étape 3 : squelette et animations.

Pose sur le cheval texturé (textures.blend) le squelette et les animations du cheval de
Quaternius (CC0) utilisé par la première version du jeu (Barq) : Idle, WalkSlow, Walk, Run, Jump,
Death. Le squelette est tourné et mis à l'échelle, puis chaque os est replacé sur l'anatomie du
cheval (épaule, genou, sabot, hanche, jarret, dos, encolure, tête, queue) ; les translations des
animations sont mises à la même échelle. Poids : distance aux segments des os, lissée le long des
arêtes (la pondération automatique de Blender échoue sur cette peau) ; selle, tapis et bride sont
rigides (dos ou tête). Exporte un GLB unique : maillages, textures, squelette, animations.

    blender --background --factory-startup --python-exit-code 1 --python squelette.py -- \
        --entree <textures.blend> --animations <animations_quaternius.glb> --sortie <cheval.glb> --rapport <rapport.json>
"""

import argparse
import json
import math
import sys
import time

import bpy
import numpy as np
from mathutils import Vector

_parser = argparse.ArgumentParser()
_parser.add_argument("--entree", required=True)
_parser.add_argument("--animations", required=True)
_parser.add_argument("--sortie", required=True)
_parser.add_argument("--rapport", required=True)
ARGS = _parser.parse_args(sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else [])
STARTED = time.time()

bpy.ops.wm.open_mainfile(filepath=ARGS.entree)
for ob in list(bpy.data.objects):
    if ob.type != "MESH" or ob.name == "Plane":
        bpy.data.objects.remove(ob, do_unlink=True)
horse_objects = list(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=ARGS.animations)
for ob in list(bpy.data.objects):
    if ob not in horse_objects and ob.type == "MESH":
        bpy.data.objects.remove(ob, do_unlink=True)
armatures = [o for o in bpy.data.objects if o.type == "ARMATURE"]
if len(armatures) != 1:
    raise SystemExit("ERREUR squelette.py : un seul squelette attendu dans %s." % ARGS.animations)
arm = armatures[0]
arm.name = "Cheval_squelette"
# Cheval de Quaternius : tête vers -Y, garrot à 4,11 unités. Ici : tête vers +X, garrot à 1,55 m.
S = 1.55 / 4.11
arm.rotation_euler = (0, 0, math.radians(90))
arm.scale = (S, S, S)
bpy.ops.object.select_all(action="DESELECT")
bpy.context.view_layer.objects.active = arm
arm.select_set(True)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def fcurves(action):
    out = []
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                out += list(bag.fcurves)
    return out

for action in bpy.data.actions:
    for fc in fcurves(action):
        if fc.data_path.endswith("location"):
            for k in fc.keyframe_points:
                k.co[1] *= S
                k.handle_left[1] *= S
                k.handle_right[1] *= S

FRONT = {1: (0.50, 0.57, 0.61), -1: (0.43, 0.50, 0.54)}
BACK = {1: (-0.79, -0.84, -0.74), -1: (-0.72, -0.77, -0.67)}
Y = 0.215
P = {
    "root": ((0, 0, 0), (0, 0, 0.6)),
    "Body": ((-0.15, 0, 1.00), (-0.15, 0, 1.45)),
    "Hips": ((-0.62, 0, 1.40), (-0.15, 0, 1.36)),
    "Torso": ((-0.15, 0, 1.36), (0.35, 0, 1.40)),
    "Back": ((-0.80, 0, 1.30), (-0.45, 0, 1.42)),
    "Tail1": ((-0.94, 0, 1.51), (-1.09, 0, 1.23)),
    "Tail2": ((-1.09, 0, 1.23), (-1.12, 0, 0.86)),
    "Tail3": ((-1.12, 0, 0.86), (-1.08, 0, 0.45)),
    "Tail4": ((-1.08, 0, 0.45), (-1.01, 0, 0.24)),
    "Shoulders": ((0.40, 0, 1.47), (0.52, 0, 1.66)),
    "Neck": ((0.52, 0, 1.66), (0.88, 0, 2.22)),
    "Head": ((0.88, 0, 2.22), (1.50, 0, 1.90)),
}
for side, suffix in ((1, "L"), (-1, "R")):
    top, knee, hoof = FRONT[side]
    y = side * Y
    P[f"FrontLeg.{suffix}"] = ((top, side * 0.05, 1.25), (top, y, 1.25))
    P[f"FrontUpLeg.{suffix}"] = ((top, y, 1.25), (knee, y, 0.66))
    P[f"FrontLowLeg.{suffix}"] = ((knee, y, 0.66), (hoof, y, 0.03))
    P[f"FrontFoot.{suffix}"] = ((hoof, y, 0.03), (hoof - 0.6, y, 0.03))
    top, hock, hoof = BACK[side]
    P[f"BackLeg.{suffix}"] = ((top, side * 0.05, 1.30), (top, y, 1.30))
    P[f"BackUpLeg.{suffix}"] = ((top, y, 1.30), (hock, y, 0.60))
    P[f"BackLowLeg.{suffix}"] = ((hock, y, 0.60), (hoof, y, 0.03))
    P[f"BackFoot.{suffix}"] = ((hoof, y, 0.03), (hoof - 0.6, y, 0.03))

bpy.ops.object.mode_set(mode="EDIT")
eb = arm.data.edit_bones
axes = {b.name: b.z_axis.copy() for b in eb}
for b in eb:
    b.use_connect = False
for name, (h, t) in P.items():
    b = eb[name]
    b.head = Vector(h)
    b.tail = Vector(t)
for name in P:
    eb[name].align_roll(axes[name])
bpy.ops.object.mode_set(mode="OBJECT")
NODEFORM = {"root", "FrontFoot.L", "FrontFoot.R", "BackFoot.L", "BackFoot.R", "FrontLeg.L", "FrontLeg.R", "BackLeg.L", "BackLeg.R", "Body"}
for b in arm.data.bones:
    b.use_deform = b.name not in NODEFORM
DEFORM = [b.name for b in arm.data.bones if b.use_deform]
SEGMENTS = {b.name: (np.array(arm.matrix_world @ b.head_local), np.array(arm.matrix_world @ b.tail_local)) for b in arm.data.bones}


def segment_distance(points, a, b):
    ab = b - a
    t = np.clip(((points - a) @ ab) / max(float(ab @ ab), 1e-9), 0.0, 1.0)
    closest = a + t[:, None] * ab
    return np.linalg.norm(points - closest, axis=1)


def assign_weights(ob, candidates, sharpness=6.0, keep=3, smooth=0, rigid=None):
    """Poids par distance aux segments des os candidats (les keep plus proches, ∝ 1/d^sharpness),
    puis lissage sur les arêtes du maillage. rigid : un seul os pour tout l'objet."""
    for g in list(ob.vertex_groups):
        ob.vertex_groups.remove(g)
    count = len(ob.data.vertices)
    co = np.empty(count * 3)
    ob.data.vertices.foreach_get("co", co)
    pts = (np.array(ob.matrix_world) @ np.c_[co.reshape(-1, 3), np.ones(count)].T).T[:, :3]
    if rigid:
        w = np.zeros((count, 1)); w[:] = 1.0; names = [rigid]
    else:
        names = list(candidates)
        d = np.stack([segment_distance(pts, *SEGMENTS[n]) for n in names], axis=1) + 0.01
        w = 1.0 / d ** sharpness
        if keep < len(names):
            cut = np.sort(w, axis=1)[:, -keep][:, None]
            w[w < cut] = 0.0
        w /= w.sum(axis=1, keepdims=True)
        if smooth:
            edges = np.empty(len(ob.data.edges) * 2, dtype=np.int64)
            ob.data.edges.foreach_get("vertices", edges)
            edges = edges.reshape(-1, 2)
            for _ in range(smooth):
                acc = w.copy(); deg = np.ones(count)
                np.add.at(acc, edges[:, 0], w[edges[:, 1]]); np.add.at(acc, edges[:, 1], w[edges[:, 0]])
                np.add.at(deg, edges[:, 0], 1); np.add.at(deg, edges[:, 1], 1)
                w = acc / deg[:, None]
            w[w < 0.02] = 0.0
            w /= w.sum(axis=1, keepdims=True)
    for j, n in enumerate(names):
        g = ob.vertex_groups.new(name=n)
        for value in np.unique(np.round(w[:, j], 3)):
            if value <= 0.0:
                continue
            idx = np.nonzero(np.round(w[:, j], 3) == value)[0].tolist()
            g.add(idx, float(value), "REPLACE")
    mod = ob.modifiers.new("Squelette", "ARMATURE")
    mod.object = arm
    ob.parent = arm
    ob.matrix_parent_inverse = arm.matrix_world.inverted()


BODY = [n for n in DEFORM if not n.startswith("Tail")]
t0 = time.time()
assign_weights(bpy.data.objects["Cheval_robe"], BODY, sharpness=5.0, keep=3, smooth=6)
assign_weights(bpy.data.objects["Cheval_crins"], ["Neck", "Shoulders", "Head", "Tail1", "Tail2", "Tail3", "Tail4", "Back"], keep=2, smooth=0)
assign_weights(bpy.data.objects["Cheval_sabots"], ["FrontLowLeg.L", "FrontLowLeg.R", "BackLowLeg.L", "BackLowLeg.R"], keep=1)
assign_weights(bpy.data.objects["Equipement_cuir"], ["Head", "Neck", "Torso", "Shoulders"], keep=2, smooth=0)
assign_weights(bpy.data.objects["Equipement_fer"], ["Head", "Torso"], keep=1)
for name in ("Equipement_tapis", "Equipement_galon", "Equipement_coutures"):
    assign_weights(bpy.data.objects[name], None, rigid="Torso")
for name in ("Cheval_yeux", "Cheval_creux_oreilles"):
    assign_weights(bpy.data.objects[name], None, rigid="Head")

# Repos : aucune action active (l'export reprend toutes les actions du squelette).
arm.animation_data_create()
arm.animation_data.action = None
for name, action in [(a.name, a) for a in bpy.data.actions]:
    action.use_fake_user = True
bpy.ops.object.select_all(action="DESELECT")
exported = [arm] + [o for o in bpy.data.objects if o.type == "MESH"]
for ob in exported:
    ob.select_set(True)
bpy.context.view_layer.objects.active = arm
bpy.ops.export_scene.gltf(
    filepath=ARGS.sortie,
    use_selection=True,
    export_format="GLB",
    export_image_format="AUTO",
    export_animations=True,
    export_animation_mode="ACTIONS",
    export_force_sampling=True,
    export_def_bones=False,
    export_yup=True,
)
triangles = 0
for ob in exported[1:]:
    ob.data.calc_loop_triangles()
    triangles += len(ob.data.loop_triangles)
report = {
    "triangles": triangles,
    "os": len(arm.data.bones),
    "animations": sorted(a.name for a in bpy.data.actions),
    "duree_secondes": round(time.time() - STARTED),
}
with open(ARGS.rapport, "w", encoding="utf8") as handle:
    json.dump(report, handle, indent=2, ensure_ascii=False)
print("squelette.py :", json.dumps(report, ensure_ascii=False), flush=True)
