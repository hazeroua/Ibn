class_name HorseVisual
extends Node3D
## Modèle de Barq mis aux dimensions réelles (horse.json > model) : échelle déduite de la hauteur du modèle,
## orientation ramenée à l'avant de Godot (-Z), couleurs de robe lues dans les couleurs de sommets du modèle
## (matériau partagé), animations en boucle pour les allures. Construit une fois par cheval ; rien par image.

var animation_player: AnimationPlayer
var skeleton: Skeleton3D
## Échelle appliquée au modèle source (pour convertir les distances de ses animations).
var model_scale: float = 1.0


## Construit le visuel d'après les réglages de horse.json ; null (et erreur) si le modèle manque.
static func build(settings: Dictionary) -> HorseVisual:
	var context: String = "horse.json > model"
	var model_data: Dictionary = JsonData.get_dictionary(settings, "model", "horse.json")
	var scene: PackedScene = load(JsonData.get_string(model_data, "path", context)) as PackedScene
	if scene == null:
		push_error("Barq : modèle introuvable (%s)." % JsonData.get_string(model_data, "path", context))
		return null
	var visual := HorseVisual.new()
	visual.name = "BarqVisuel"
	var model: Node3D = scene.instantiate() as Node3D
	model.name = "Modele"
	visual.add_child(model)
	visual.animation_player = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	visual.skeleton = model.find_child("Skeleton3D", true, false) as Skeleton3D
	if visual.animation_player == null or visual.skeleton == null:
		push_error("Barq : le modèle doit avoir un squelette et un AnimationPlayer (%s)." % context)
		return visual
	# Hauteur du modèle au repos (sommet de la tête) : l'échelle ramène le cheval à sa taille réelle.
	var top: float = 0.0
	for mesh_node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance: MeshInstance3D = mesh_node as MeshInstance3D
		var bounds: AABB = mesh_instance.transform * mesh_instance.get_aabb()
		top = maxf(top, bounds.end.y)
		_apply_coat(mesh_instance, model_data, context)
	if top <= 0.0:
		push_error("Barq : hauteur du modèle nulle (%s)." % context)
		return visual
	visual.model_scale = JsonData.get_float(model_data, "height_m", context) / top
	# Largeur réglable : le modèle source a un tronc plus large qu'un cheval arabe, où les jambes du cavalier disparaissent.
	var width: float = JsonData.get_float(model_data, "width_scale", context)
	model.scale = Vector3(visual.model_scale * width, visual.model_scale, visual.model_scale)
	model.rotation.y = deg_to_rad(JsonData.get_float(model_data, "yaw_offset_deg", context))
	for clip: Variant in JsonData.get_array(model_data, "looped_clips", context):
		var animation: Animation = visual.animation_player.get_animation(StringName(str(clip)))
		if animation == null:
			push_error("Barq : animation « %s » absente du modèle (%s)." % [clip, context])
			continue
		animation.loop_mode = Animation.LOOP_LINEAR
	return visual


## Robe : le modèle n'a ni texture ni couleurs de sommets ; chaque surface reçoit le matériau de robe partagé ou
## celui des crins (horse.json > model > coat > hair_surfaces : numéros des surfaces de crins).
static func _apply_coat(mesh_instance: MeshInstance3D, model_data: Dictionary, context: String) -> void:
	var coat_data: Dictionary = JsonData.get_dictionary(model_data, "coat", context)
	var coat_context: String = context + " > coat"
	var hair_surfaces: Array = JsonData.get_array(coat_data, "hair_surfaces", coat_context)
	var shader: Shader = load(JsonData.get_string(coat_data, "shader", coat_context)) as Shader
	if shader == null:
		push_error("Barq : shader de robe introuvable (%s)." % coat_context)
		return
	var materials: Array[ShaderMaterial] = []
	for hair: bool in [false, true]:
		var material := ShaderMaterial.new()
		material.shader = shader
		material.set_shader_parameter(&"coat_color", JsonData.get_color(coat_data, "coat_color", coat_context))
		material.set_shader_parameter(&"points_color", JsonData.get_color(coat_data, "points_color", coat_context))
		material.set_shader_parameter(&"points_height_m", JsonData.get_float(coat_data, "points_height_m", coat_context))
		material.set_shader_parameter(&"points_blend_m", JsonData.get_float(coat_data, "points_blend_m", coat_context))
		material.set_shader_parameter(&"hair_variation", JsonData.get_float(coat_data, "hair_variation", coat_context))
		material.set_shader_parameter(&"roughness_value", JsonData.get_float(coat_data, "roughness", coat_context))
		material.set_shader_parameter(&"is_hair", hair)
		materials.append(material)
	for surface: int in mesh_instance.mesh.get_surface_count():
		var hair_surface: bool = hair_surfaces.has(float(surface)) or hair_surfaces.has(surface)
		mesh_instance.set_surface_override_material(surface, materials[1] if hair_surface else materials[0])


## Position du point de selle (monde) : os de selle du modèle plus décalage (repère du cheval, mètres réels).
func saddle_transform(bone: int, offset: Vector3) -> Transform3D:
	var pose: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(bone)
	var basis_flat: Basis = global_basis.orthonormalized()
	return Transform3D(basis_flat, pose.origin + basis_flat * offset)
