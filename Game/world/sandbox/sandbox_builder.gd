class_name SandboxBuilder
extends RefCounted
## Construit la carte « bac à sable » à partir de res://data/sandbox/sandbox.json.
##
## Les objets de même taille partagent un seul maillage et les objets de même couleur un seul
## matériau : la mémoire et les changements d'état du rendu restent constants quand on ajoute
## des objets identiques.

const FREE_CAMERA_SCRIPT: String = "res://world/sandbox/free_camera.gd"
const POLYHAVEN_DIR: String = "res://assets/textures/polyhaven"
const CONTEXT: String = "sandbox.json"
const SUPPORTED_SHAPES: PackedStringArray = ["box"]


static func build(data: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Sandbox"
	root.add_child(_build_environment(JsonData.get_dictionary(data, "environment", CONTEXT)))
	root.add_child(_build_sun(JsonData.get_dictionary(data, "sun", CONTEXT)))
	root.add_child(_build_ground(JsonData.get_dictionary(data, "ground", CONTEXT)))
	var objects := Node3D.new()
	objects.name = "Objects"
	root.add_child(objects)
	_build_objects(objects, JsonData.get_array(data, "objects", CONTEXT))
	root.add_child(_build_camera(JsonData.get_dictionary(data, "camera", CONTEXT)))
	_assign_owner(root, root)
	return root


static func _build_environment(config: Dictionary) -> WorldEnvironment:
	var context: String = CONTEXT + " > environment"
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = JsonData.get_color(config, "sky_top_color", context)
	sky_material.sky_horizon_color = JsonData.get_color(config, "sky_horizon_color", context)
	sky_material.ground_horizon_color = JsonData.get_color(config, "ground_horizon_color", context)
	sky_material.ground_bottom_color = JsonData.get_color(config, "ground_bottom_color", context)
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	environment.tonemap_exposure = JsonData.get_float(config, "exposure", context)
	environment.ssao_enabled = JsonData.get_bool(config, "ssao", context)
	environment.fog_enabled = JsonData.get_bool(config, "fog", context)
	environment.fog_density = JsonData.get_float(config, "fog_density", context)
	environment.fog_light_color = JsonData.get_color(config, "sky_horizon_color", context)
	var node := WorldEnvironment.new()
	node.name = "Environment"
	node.environment = environment
	return node


static func _build_sun(config: Dictionary) -> DirectionalLight3D:
	var context: String = CONTEXT + " > sun"
	var light := DirectionalLight3D.new()
	light.name = "Sun"
	light.rotation_degrees = JsonData.get_vector3(config, "rotation_degrees", context)
	light.light_color = JsonData.get_color(config, "color", context)
	light.light_energy = JsonData.get_float(config, "energy", context)
	light.shadow_enabled = true
	light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	light.directional_shadow_max_distance = JsonData.get_float(config, "shadow_max_distance", context)
	return light


static func _build_ground(config: Dictionary) -> MeshInstance3D:
	var context: String = CONTEXT + " > ground"
	var texture_id: String = JsonData.get_string(config, "texture", context)
	var uv_scale: float = JsonData.get_float(config, "uv_scale", context)
	var material := StandardMaterial3D.new()
	material.albedo_color = JsonData.get_color(config, "tint", context)
	material.albedo_texture = _load_texture(texture_id, "diff")
	material.normal_enabled = true
	material.normal_texture = _load_texture(texture_id, "nor_gl")
	material.roughness_texture = _load_texture(texture_id, "rough")
	material.uv1_scale = Vector3(uv_scale, uv_scale, 1.0)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var mesh := PlaneMesh.new()
	mesh.size = JsonData.get_vector2(config, "size", context)
	mesh.material = material
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	ground.mesh = mesh
	return ground


static func _load_texture(texture_id: String, map_name: String) -> Texture2D:
	var path: String = "%s/%s/%s_%s.jpg" % [POLYHAVEN_DIR, texture_id, texture_id, map_name]
	if not ResourceLoader.exists(path):
		push_error("SandboxBuilder : texture absente %s. Lancez Scripts/Pipeline/importer-ressources.ps1." % path)
		return null
	var texture: Texture2D = load(path)
	if texture == null:
		push_error("SandboxBuilder : %s n'est pas une texture." % path)
	return texture


static func _build_objects(parent: Node3D, entries: Array) -> void:
	var meshes: Dictionary[String, BoxMesh] = {}
	var materials: Dictionary[String, StandardMaterial3D] = {}
	var ids: Dictionary[String, bool] = {}
	for raw: Variant in entries:
		if typeof(raw) != TYPE_DICTIONARY:
			push_error("SandboxBuilder : chaque objet doit être un objet JSON.")
			continue
		var entry: Dictionary = raw
		var object_id: String = JsonData.get_string(entry, "id", CONTEXT + " > objects")
		if object_id.is_empty() or object_id.validate_node_name() != object_id or ids.has(object_id):
			push_error("SandboxBuilder : identifiant d'objet absent, invalide ou en double « %s »." % object_id)
			continue
		ids[object_id] = true
		var context: String = CONTEXT + " > " + object_id
		var shape: String = JsonData.get_string(entry, "shape", context)
		if not SUPPORTED_SHAPES.has(shape):
			push_error(
				"SandboxBuilder : forme « %s » non prise en charge (%s) ; formes : %s." % [shape, object_id, ", ".join(SUPPORTED_SHAPES)]
			)
			continue
		var size: Vector3 = JsonData.get_vector3(entry, "size", context)
		if size.x <= 0.0 or size.y <= 0.0 or size.z <= 0.0:
			push_error("SandboxBuilder : taille invalide pour « %s »." % object_id)
			continue
		var color: Color = JsonData.get_color(entry, "color", context)
		var mesh_key: String = "%.4f|%.4f|%.4f" % [size.x, size.y, size.z]
		if not meshes.has(mesh_key):
			var box := BoxMesh.new()
			box.size = size
			meshes[mesh_key] = box
		var material_key: String = color.to_html(true)
		if not materials.has(material_key):
			var material := StandardMaterial3D.new()
			material.albedo_color = color
			material.roughness = 0.8
			materials[material_key] = material
		var instance := MeshInstance3D.new()
		instance.name = object_id
		instance.mesh = meshes[mesh_key]
		instance.material_override = materials[material_key]
		instance.position = JsonData.get_vector3(entry, "position", context)
		instance.rotation_degrees = JsonData.get_vector3_or(entry, "rotation_degrees", Vector3.ZERO, context)
		parent.add_child(instance)


static func _build_camera(config: Dictionary) -> Camera3D:
	var context: String = CONTEXT + " > camera"
	var camera := Camera3D.new()
	camera.name = "Camera"
	camera.set_script(load(FREE_CAMERA_SCRIPT))
	var position: Vector3 = JsonData.get_vector3(config, "position", context)
	var target: Vector3 = JsonData.get_vector3(config, "target", context)
	camera.transform = Transform3D(Basis.IDENTITY, position).looking_at(target, Vector3.UP)
	camera.fov = JsonData.get_float(config, "fov", context)
	camera.far = JsonData.get_float(config, "far", context)
	camera.current = true
	camera.set(&"move_speed", JsonData.get_float(config, "move_speed", context))
	camera.set(&"sprint_multiplier", JsonData.get_float(config, "sprint_multiplier", context))
	camera.set(&"mouse_sensitivity", JsonData.get_float(config, "mouse_sensitivity", context))
	camera.set(&"stick_look_speed", JsonData.get_float(config, "stick_look_speed", context))
	return camera


static func _assign_owner(node: Node, owner: Node) -> void:
	for child: Node in node.get_children():
		child.owner = owner
		_assign_owner(child, owner)
