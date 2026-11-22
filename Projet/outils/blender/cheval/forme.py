"""Cheval original du jeu (ticket #106), étape 1 : la forme.

Surfaces par sections (thorax, encolure, tête, membres, sabots), union de la peau, naseaux
creusés, crins, tapis drapé, selle, bride et rênes. Aucun modèle tiers. Écrit forme.blend dans
le dossier de sortie ; avec --rendus, ajoute quatre vues sur un banc d'essai désertique.

    blender --background --factory-startup --python-exit-code 1 --python forme.py -- --sortie <dossier> [--rendus]

Étapes suivantes : textures.py (textures cuites), squelette.py (squelette et animations).
Itérations visuelles : Docs/cheval-sahara-iteration-2.md et -3.md.
"""
import argparse
import bpy
import math
import json
import random
import sys
from pathlib import Path
from mathutils import Vector, noise

_parser = argparse.ArgumentParser()
_parser.add_argument("--sortie", required=True)
_parser.add_argument("--rendus", action="store_true")
ARGS = _parser.parse_args(sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else [])
OUT = Path(ARGS.sortie)
OUT.mkdir(parents=True, exist_ok=True)
random.seed(106)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)

def mat(name, rgb, rough=.7, metal=0):
    m=bpy.data.materials.new(name)
    m.diffuse_color=(*rgb,1)
    m.use_nodes=True
    bs=m.node_tree.nodes.get('Principled BSDF')
    bs.inputs['Base Color'].default_value=(*rgb,1)
    bs.inputs['Roughness'].default_value=rough
    bs.inputs['Metallic'].default_value=metal
    return m

coat=mat('Baie sombre • robe',(.065,.019,.008),.68)
hair=mat('Crins noirs',(.009,.007,.005),.66)
horn=mat('Corne striee',(.036,.029,.019),.7)
leather=mat('Cuir patine',(.035,.016,.007),.78)
fabric=mat('Laine ecrue',(.22,.135,.068),.94)
trim=mat('Bordure terre rouge',(.105,.021,.011),.9)
stitch=mat('Fil de lin',(.30,.20,.10),.9)
metal=mat('Fer bruni',(.12,.105,.075),.42,.75)
eyes=mat('Oeil brun noir',(.008,.004,.002),.20)
inner=mat('Interieur oreille',(.055,.025,.018),.92)
skinparts=[]

def mesh(name, verts, faces, material, smooth=True):
    me=bpy.data.meshes.new(name)
    me.from_pydata(verts,[],faces)
    me.update()
    ob=bpy.data.objects.new(name,me)
    bpy.context.collection.objects.link(ob)
    ob.data.materials.append(material)
    for p in me.polygons: p.use_smooth=smooth
    return ob

def loft(name, sections, material, axis='Z', segments=32, body=False):
    # Sections carry centre x,y,z and two transverse radii.
    verts=[]
    for x,y,z,a,b in sections:
        for i in range(segments):
            t=math.tau*i/segments
            if axis=='X': v=(x,y+a*math.cos(t),z+b*math.sin(t))
            else: v=(x+a*math.cos(t),y+b*math.sin(t),z)
            verts.append(v)
    faces=[]
    for j in range(len(sections)-1):
        for i in range(segments):
            n=(i+1)%segments
            faces.append((j*segments+i,j*segments+n,(j+1)*segments+n,(j+1)*segments+i))
    faces.extend([tuple(reversed(range(segments))),tuple((len(sections)-1)*segments+i for i in range(segments))])
    ob=mesh(name,verts,faces,material)
    bpy.context.view_layer.objects.active=ob
    sub=ob.modifiers.new('Courbure sections','SUBSURF'); sub.levels=2
    bpy.ops.object.modifier_apply(modifier=sub.name)
    if body: skinparts.append(ob)
    return ob

def ell(name,loc,scale,material,body=False):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=24,ring_count=16,location=loc)
    ob=bpy.context.object; ob.name=name; ob.scale=scale
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    ob.data.materials.append(material)
    for p in ob.data.polygons: p.use_smooth=True
    if body: skinparts.append(ob)
    return ob

def cord(name,points,radius,material):
    cu=bpy.data.curves.new(name,'CURVE'); cu.dimensions='3D'
    cu.bevel_depth=radius; cu.bevel_resolution=2; cu.resolution_u=10
    sp=cu.splines.new('BEZIER'); sp.bezier_points.add(len(points)-1)
    for index,(p,v) in enumerate(zip(sp.bezier_points,points)):
        p.co=v; p.handle_left_type=p.handle_right_type='AUTO'
        if name in ('Crin','Queue'): p.radius=1.0 if index<len(points)-1 else .12
    ob=bpy.data.objects.new(name,cu); bpy.context.collection.objects.link(ob)
    ob.data.materials.append(material)
    return ob

# Anatomical surfaces: the topline, belly and neck are controlled independently.
loft('Thorax et croupe',[
    (-1.00,0,1.38,.04,.12),(-.87,0,1.40,.24,.29),(-.70,0,1.40,.31,.34),
    (-.43,0,1.36,.29,.34),(-.17,0,1.31,.31,.36),(.12,0,1.31,.30,.36),
    (.38,0,1.36,.265,.37),(.58,0,1.40,.23,.34),(.70,0,1.39,.10,.24)],coat,'X',body=True)
loft('Encolure profilee',[
    (.46,0,1.25,.22,.18),(.49,0,1.44,.31,.235),(.52,0,1.62,.30,.205),
    (.60,0,1.80,.265,.165),(.71,0,1.99,.22,.125),(.83,0,2.15,.16,.105),
    (.91,0,2.25,.11,.095),(.94,0,2.29,.06,.065)],coat,body=True)
loft('Tete chanfrein machoire',[
    (.84,0,2.25,.065,.10),(.93,0,2.23,.12,.17),(1.04,0,2.17,.135,.19),
    (1.14,0,2.10,.105,.145),(1.27,0,1.995,.087,.115),
    (1.42,0,1.91,.10,.10),(1.49,0,1.895,.088,.078),(1.52,0,1.895,.05,.05)],coat,'X',body=True)
for side in [-1,1]:
    y=side*.215
    # Far feet offset longitudinally so all four appuis can be seen.
    shift=.07 if side==1 else 0
    loft('Anterieur',[(.43+shift,y,1.39,.12,.10),(.40+shift,y,1.14,.105,.085),
         (.45+shift,y,.95,.073,.058),(.50+shift,y,.74,.052,.050),
         (.50+shift,y,.65,.060,.055),(.49+shift,y,.57,.043,.038),
         (.48+shift,y,.31,.033,.033),(.47+shift,y,.24,.049,.044),
         (.51+shift,y,.16,.044,.040),(.54+shift,y,.11,.046,.044)],coat,body=True)
    loft('Posterieur',[(-.72-shift,y,1.45,.21,.15),(-.65-shift,y,1.22,.19,.13),
         (-.48-shift,y,1.01,.12,.085),(-.56-shift,y,.84,.085,.062),
         (-.77-shift,y,.63,.055,.048),(-.79-shift,y,.56,.059,.053),
         (-.77-shift,y,.48,.033,.033),(-.73-shift,y,.27,.030,.032),
         (-.72-shift,y,.22,.047,.043),(-.67-shift,y,.12,.044,.043)],coat,body=True)
    for x in [.54+shift,-.67-shift]:
        loft('Sabot appui plat',[(x+.015,y,.012,.090,.065),(x+.015,y,.027,.090,.065),
             (x,y,.115,.064,.051),(x-.018,y,.145,.049,.043)],horn,segments=24)
    # Narrow pointed ears rather than rounded capsules.
    loft('Oreille',[(.89,side*.085,2.26,.057,.045),(.875,side*.10,2.35,.057,.037),
         (.88,side*.115,2.43,.031,.019),(.91,side*.125,2.48,.002,.002)],coat)
    loft('Creux oreille',[(.935,side*.10,2.34,.009,.022),(.924,side*.11,2.40,.009,.019),
         (.917,side*.12,2.45,.002,.002)],inner,segments=16)
    ell('Arcade',(1.055,side*.119,2.225),(.065,.034,.045),coat,True)
    ell('Oeil',(1.072,side*.144,2.221),(.032,.010,.020),eyes)
    cord('Paupiere',[(1.039,side*.145,2.220),(1.069,side*.150,2.241),(1.105,side*.139,2.221)],.006,coat)

bpy.ops.object.select_all(action='DESELECT')
for o in skinparts:o.select_set(True)
bpy.context.view_layer.objects.active=skinparts[0]
bpy.ops.object.join(); skin=bpy.context.object; skin.name='Cheval_sahara_peau'
rem=skin.modifiers.new('Union anatomique','REMESH'); rem.mode='VOXEL'; rem.voxel_size=.009
bpy.ops.object.modifier_apply(modifier=rem.name)
sm=skin.modifiers.new('Liaison musculaire','SMOOTH'); sm.factor=.7; sm.iterations=4
bpy.ops.object.modifier_apply(modifier=sm.name)
dec=skin.modifiers.new('Reduction','DECIMATE'); dec.ratio=.28
bpy.ops.object.modifier_apply(modifier=dec.name)
for p in skin.data.polygons:p.use_smooth=True

# Real inset nostrils, shaded interior and separated lip line.
for side in [-1,1]:
    cutter=ell('Decoupe naseau',(1.446,side*.085,1.94),(.040,.031,.027),coat)
    bpy.context.view_layer.objects.active=skin
    mod=skin.modifiers.new('Naseau creux','BOOLEAN'); mod.operation='DIFFERENCE'; mod.object=cutter
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.data.objects.remove(cutter,do_unlink=True)
    ell('Fond naseau',(1.446,side*.065,1.94),(.032,.015,.021),hair)
    cord('Levres',[(1.515,side*.033,1.875),(1.47,side*.082,1.867),(1.38,side*.09,1.88)],.0025,hair)

# Spatial pigment stored as vertex colours: survives GLB export.
def color_skin():
    attr=skin.data.color_attributes.new(name='Robe',type='FLOAT_COLOR',domain='POINT')
    for v,c in zip(skin.data.vertices,attr.data):
        x,y,z=skin.matrix_world@v.co
        n=noise.noise_vector(Vector((x*4,y*7,z*5)))[0]
        fine=noise.noise_vector(Vector((x*160,y*160,z*160)))[0]
        darklegs=max(0,min(1,(.83-z)/.40))
        muzzle=max(0,min(1,(x-1.27)/.19))*max(0,min(1,(2.05-z)/.10))
        dark=max(darklegs,muzzle)
        base=Vector((.055,.014,.0045))*(.70+.30*n+.06*fine)
        base=base.lerp(Vector((.011,.009,.007)),dark*.93)
        c.color=(*base,1)
    ns=coat.node_tree.nodes; ls=coat.node_tree.links
    vc=ns.new('ShaderNodeVertexColor'); vc.layer_name='Robe'
    bs=ns.get('Principled BSDF'); ls.new(vc.outputs['Color'],bs.inputs['Base Color'])
color_skin()

# Small material grain, without broad plastic highlights.
for m,scale,strength in [(coat,240,.16),(leather,110,.24),(horn,90,.2),(fabric,180,.3)]:
    ns=m.node_tree.nodes; ls=m.node_tree.links; bs=ns.get('Principled BSDF')
    tex=ns.new('ShaderNodeTexNoise'); tex.inputs['Scale'].default_value=scale
    bump=ns.new('ShaderNodeBump'); bump.inputs['Strength'].default_value=strength
    bump.inputs['Distance'].default_value=.002
    ls.new(tex.outputs['Fac'],bump.inputs['Height']);ls.new(bump.outputs['Normal'],bs.inputs['Normal'])

# Mane is laid on the actual rear edge of the curved neck.
for i in range(64):
    t=i/63; x=.29+.50*t; z=1.65+.65*t
    cord('Crin',[(x,0,z), (x-.035,-.07,z-.06), (x+.015,-.145,z-.17),
          (x+.06,-.16,z-.23-random.random()*.04)],.007+random.random()*.004,hair)
for i in range(75):
    a=random.random()*math.tau;r=random.random()*.045
    y=math.sin(a)*r;off=math.cos(a)*r
    cord('Queue', [(-.94,y,1.51),(-1.09+off,y*1.3,1.23),(-1.12+off,y*1.5,.86),
         (-1.08+off,y*1.6,.45),(-1.01+off,y*1.8,.24+random.random()*.13)],.006,hair)

# Cloth drapes as a thin surface over the back, not a cushion.
def blanket():
    verts=[]; faces=[]; nx=18; ny=32
    for i in range(nx):
        x=-.47+.80*i/(nx-1)
        for j in range(ny):
            a=-1.35+2.70*j/(ny-1)
            verts.append((x,.342*math.sin(a),1.36+.375*math.cos(a)+.005*math.sin(i*.8)))
    for i in range(nx-1):
        for j in range(ny-1):
            p=i*ny+j;faces.append((p,p+ny,p+ny+1,p+1))
    ob=mesh('Tapis laine',verts,faces,fabric)
    sol=ob.modifiers.new('Epaisseur laine','SOLIDIFY');sol.thickness=.012
    for x in [-.47,.33]:
        cord('Galon tapis',[(x,.347*math.sin(a),1.36+.38*math.cos(a)) for a in [-1.35+i*2.7/20 for i in range(21)]],.011,trim)
    for s in [-1,1]:
        cord('Bord bas tapis',[(x,s*.335,1.446) for x in [-.47,-.2,.1,.33]],.01,trim)
blanket()
loft('Siege selle',[(-.34,0,1.755,.19,.045),(-.29,0,1.77,.20,.05),(-.12,0,1.75,.18,.04),
      (.09,0,1.77,.16,.04),(.19,0,1.79,.16,.035)],leather,'X')
for x,z,width in [(-.32,1.78,.20),(.19,1.80,.16)]:
    loft('Arcon cuir',[(x-.035,0,z+.035,width,.065),(x,0,z+.045,width,.08),
         (x+.035,0,z+.035,width*.95,.065)],leather,'X')
for s in [-1,1]:
    verts=[(-.27,s*.26,1.72),(.18,s*.26,1.72),(.20,s*.335,1.42),(.08,s*.34,1.27),(-.24,s*.33,1.34)]
    ob=mesh('Quartier cuir',verts,[(0,1,2,3,4)],leather)
    so=ob.modifiers.new('Epaisseur cuir','SOLIDIFY');so.thickness=.008
    be=ob.modifiers.new('Bords souples','BEVEL');be.width=.025;be.segments=3
    cord('Couture quartier',[(-.24,s*.271,1.70),(.155,s*.271,1.70),(.17,s*.35,1.43),(.08,s*.355,1.30),(-.21,s*.35,1.36)],.002,stitch)
    cord('Etriviere',[(.07,s*.22,1.77),(.06,s*.37,1.36),(.08,s*.39,1.04)],.013,leather)
    cord('Etrier fer',[(.08,s*.39,1.06),(-.015,s*.39,.91),(.18,s*.39,.91),(.08,s*.39,1.06)],.009,metal)
    cord('Montant bride',[(.88,s*.12,2.30),(1.12,s*.133,2.15),(1.44,s*.105,1.89)],.009,leather)
    cord('Rene',[(1.44,s*.11,1.89),(1.12,s*.26,1.57),(.73,s*.31,1.45),(.21,s*.20,1.81)],.006,leather)
    ell('Attache mors',(1.44,s*.112,1.89),(.015,.012,.015),metal)
cord('Muserolle',[(1.39,-.10,1.91),(1.45,0,2.003),(1.39,.10,1.91)],.011,leather)
cord('Frontal',[(.96,-.13,2.29),(1.06,0,2.36),(.96,.13,2.29)],.01,leather)
cord('Sangle',[(.16,-.27,1.70),(.16,-.31,1.26),(.16,0,.962),(.16,.31,1.26),(.16,.27,1.70)],.026,leather)

asset=list(bpy.context.scene.objects)
# Convert all curves and modifiers so the export and measurements match.
bpy.ops.object.select_all(action='DESELECT')
for ob in asset:ob.select_set(True)
bpy.context.view_layer.objects.active=skin
bpy.ops.object.convert(target='MESH')
asset=list(bpy.context.selected_objects)
# Consolidate hair by material and reduce its tube resolution for the static export.
for material in [hair,leather,horn,metal,stitch]:
    group=[ob for ob in bpy.context.scene.objects if ob.type=='MESH' and len(ob.data.materials)==1 and ob.data.materials[0]==material]
    if not group:continue
    bpy.ops.object.select_all(action='DESELECT')
    for ob in group:ob.select_set(True)
    bpy.context.view_layer.objects.active=group[0]
    bpy.ops.object.join()
    ob=bpy.context.object
    dec=ob.modifiers.new('Reduction detail','DECIMATE');dec.ratio=.25
    bpy.ops.object.modifier_apply(modifier=dec.name)
asset=list(bpy.context.scene.objects)
bpy.ops.object.select_all(action='SELECT')
triangles=0
for ob in asset:
    ob.data.calc_loop_triangles(); triangles+=len(ob.data.loop_triangles)
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'forme.blend'))
(OUT/'forme.json').write_text(json.dumps({'triangles':triangles,'objets':len(asset)},indent=2),encoding='utf8')
if not ARGS.rendus:
    sys.exit(0)

# Desert test set: colour and lighting context, not a screenshot of the game.
ground=mat('Reg ocre',(.31,.20,.10),.96)
ns=ground.node_tree.nodes;ls=ground.node_tree.links;bs=ns.get('Principled BSDF')
tex=ns.new('ShaderNodeTexNoise');tex.inputs['Scale'].default_value=7
geo=ns.new('ShaderNodeNewGeometry');ls.new(geo.outputs['Position'],tex.inputs['Vector'])
ramp=ns.new('ShaderNodeValToRGB');ramp.color_ramp.elements[0].color=(.10,.050,.019,1)
ramp.color_ramp.elements[1].color=(.43,.30,.15,1)
ls.new(tex.outputs['Fac'],ramp.inputs[0]);ls.new(ramp.outputs[0],bs.inputs['Base Color'])
fine=ns.new('ShaderNodeTexNoise');fine.inputs['Scale'].default_value=260
ls.new(geo.outputs['Position'],fine.inputs['Vector'])
bump=ns.new('ShaderNodeBump');bump.inputs['Strength'].default_value=.6;bump.inputs['Distance'].default_value=.025
ls.new(fine.outputs['Fac'],bump.inputs['Height']);ls.new(bump.outputs['Normal'],bs.inputs['Normal'])
bpy.ops.mesh.primitive_plane_add(size=2000);bpy.context.object.data.materials.append(ground)
rock=mat('Galets',(.14,.075,.035),.96)
for i in range(100):
    x=random.uniform(-7,7);y=random.uniform(-6,8)
    if abs(x)<1.6 and abs(y)<.6:continue
    size=random.uniform(.012,.05)
    ob=ell('Galet',(x,y,size*.25),(size,size*.65,size*.35),rock)
world=bpy.context.scene.world;world.use_nodes=True
ns=world.node_tree.nodes;ls=world.node_tree.links
sky=ns.new('ShaderNodeTexSky');sky.sky_type='MULTIPLE_SCATTERING';sky.sun_disc=True
sky.sun_size=.009;sky.sun_intensity=.7;sky.altitude=0;sky.air_density=1
ls.new(sky.outputs['Color'],ns.get('Background').inputs['Color'])
ns.get('Background').inputs['Strength'].default_value=.065
bpy.ops.object.light_add(type='SUN',location=(3,-4,6));sun=bpy.context.object
sun.data.angle=.03
bpy.ops.object.camera_add(location=(3.3,-5.6,2.6));camera=bpy.context.object
camera.data.lens=52
scene=bpy.context.scene;scene.camera=camera;scene.render.engine='CYCLES'
scene.cycles.samples=32;scene.cycles.use_denoising=True
scene.render.resolution_x=1400;scene.render.resolution_y=1000;scene.render.resolution_percentage=100
scene.view_settings.view_transform='AgX'
scene.view_settings.look='AgX - Medium High Contrast'
scene.view_settings.exposure=.35

for name,elevation,energy,color,position in [
    ('matin',25,2.1,(1,.86,.68),(3.3,-5.6,2.6)),
    ('midi',65,2.5,(1,.97,.90),(3.3,-5.6,2.6)),
    ('soir',12,1.8,(1,.65,.35),(3.3,-5.6,2.6)),
    ('profil',35,2.2,(1,.89,.74),(.2,-6.6,2.2))]:
    sky.sun_elevation=math.radians(elevation);sky.sun_rotation=math.radians(130)
    sun.rotation_euler=(math.radians(90-elevation),math.radians(-20),math.radians(-35))
    sun.data.energy=energy;sun.data.color=color
    camera.location=position
    camera.rotation_euler=(Vector((.15,0,1.25))-camera.location).to_track_quat('-Z','Y').to_euler()
    scene.render.filepath=str(OUT/(name+'.png'))
    bpy.ops.render.render(write_still=True)
