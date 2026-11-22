class_name NatureAssetLab
extends Node3D
## Laboratoire isolé pour évaluer le pack local Quaternius sans l'ajouter au jeu livré.
## Les sources restent sous assets_local/, dossier ignoré par Git.

const SOURCE_ROOT := "res://assets_local/quaternius-stylized-nature-standard/glTF"
const ULTIMATE_SOURCE_ROOT := "res://assets_local/quaternius-ultimate-stylized-nature"
const PROFILE_PATH := "res://data/assets/oasis_nature_profile.json"
const GAME_DESIGN_PROFILE_PATH := "res://data/assets/sahara_game_design_profile.json"
const MODELS: PackedStringArray = [
	"Rock_Medium_1",
	"Rock_Medium_2",
	"Rock_Medium_3",
	"Pebble_Round_1",
	"Pebble_Round_2",
	"Pebble_Round_3",
	"Pebble_Round_4",
	"Pebble_Round_5",
	"Grass_Common_Short",
	"Grass_Common_Tall",
	"Grass_Wispy_Short",
	"Grass_Wispy_Tall",
	"Bush_Common",
	"Plant_1",
	"Plant_1_Big",
	"Plant_7",
	"Plant_7_Big",
]
const ULTIMATE_MODELS: PackedStringArray = [
	"PalmTree_1",
	"PalmTree_2",
	"PalmTree_3",
	"PalmTree_4",
	"PalmTree_5",
	"Rock_1",
	"Rock_2",
	"Rock_3",
	"Rock_4",
	"Rock_5",
]
const ARCHIVE_SHA256 := "298f6732b872e4cf7b30e6e7abf9641c7f6dc6b326df37ac089533ed7e3d58c9"
const ULTIMATE_FBX_ARCHIVE_SHA256 := "3f696cc76f2e70277761e98abeb5552a" + "a39c10a97d015fd65628fc8ab51d32e0"
const CAPTURE_DELAY_FRAMES := 90
const MEASURE_FRAMES := 420

var _capture_path := ""
var _report_path := ""
var _dense := false
var _stress := false
var _ultimate := false
var _lighting_preset := "day"
var _frame_count := 0
var _loaded_models := 0
var _dense_instances := 0
var _dense_model_variants := 0
var _peak_draw_calls := 0
var _peak_primitives := 0
var _frame_times_ms := PackedFloat64Array()
var _frame_sample_index := 0
var _ground_offsets_m: Dictionary = {}
var _game_design_profile: Dictionary = {}
var _patch_noise := FastNoiseLite.new()
var _expected_dense_instances := 0
var _rock_positions: Array[Vector2] = []
var _placement_failed := false


func _ready() -> void:
	_parse_arguments()
	_load_profile()
	_load_game_design_profile()
	_frame_times_ms.resize(MEASURE_FRAMES - CAPTURE_DELAY_FRAMES)
	_build_environment()
	_build_ground()
	if _dense:
		_build_dense_population()
		if _placement_failed:
			get_tree().quit(1)
			return
		if _dense_instances != _expected_dense_instances:
			push_error("Asset lab dense incomplet : %d/%d instances." % [_dense_instances, _expected_dense_instances])
			get_tree().quit(1)
			return
		if _stress:
			$Camera.position = Vector3(0.0, 35.0, 48.0)
			$Camera.look_at(Vector3.ZERO)
		else:
			$Camera.position = Vector3(0.0, 7.5, 28.0)
			$Camera.look_at(Vector3(0.0, 0.7, -7.0))
	else:
		_load_lineup()
		$Camera.look_at(Vector3(0.0, 0.7, -0.5))
	var lineup_models := ULTIMATE_MODELS if _ultimate else MODELS
	if not _dense and _loaded_models != lineup_models.size():
		push_error("Asset lab incomplet : %d/%d modèles chargés." % [_loaded_models, lineup_models.size()])
		get_tree().quit(1)


func _process(delta: float) -> void:
	_frame_count += 1
	_peak_draw_calls = maxi(_peak_draw_calls, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	_peak_primitives = maxi(_peak_primitives, int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
	if _frame_count == CAPTURE_DELAY_FRAMES and not _capture_path.is_empty():
		_save_capture()
	if _frame_count > CAPTURE_DELAY_FRAMES:
		_frame_times_ms[_frame_sample_index] = delta * 1000.0
		_frame_sample_index += 1
	if _frame_count >= MEASURE_FRAMES:
		_write_report()
		get_tree().quit(0)


func _parse_arguments() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			_capture_path = argument.trim_prefix("--capture=")
		elif argument.begins_with("--report="):
			_report_path = argument.trim_prefix("--report=")
		elif argument == "--dense":
			_dense = true
		elif argument == "--stress":
			_dense = true
			_stress = true
		elif argument == "--ultimate":
			_ultimate = true
		elif argument.begins_with("--lighting="):
			_lighting_preset = argument.trim_prefix("--lighting=")


func _load_profile() -> void:
	var profile := JsonData.load_dictionary(PROFILE_PATH)
	var families := profile.get("families", {}) as Dictionary
	for family_value: Variant in families.values():
		var family := family_value as Dictionary
		var offsets := family.get("required_ground_offsets_m", {}) as Dictionary
		_ground_offsets_m.merge(offsets, true)


func _load_game_design_profile() -> void:
	_game_design_profile = JsonData.load_dictionary(GAME_DESIGN_PROFILE_PATH)
	var lighting := _game_design_profile.get("lighting", {}) as Dictionary
	if not lighting.has(_lighting_preset):
		push_error("Éclairage inconnu : " + _lighting_preset)
		get_tree().quit(1)
		return
	var composition := _game_design_profile.get("composition", {}) as Dictionary
	_patch_noise.seed = 7601
	_patch_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_patch_noise.frequency = float(composition.get("patch_noise_frequency", 0.055))


func _build_environment() -> void:
	var lighting := (_game_design_profile.get("lighting", {}) as Dictionary).get(_lighting_preset, {}) as Dictionary
	var environment := Environment.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(String(lighting.get("sky_top", "#4C9ED3")))
	sky_material.sky_horizon_color = Color(String(lighting.get("sky_horizon", "#C9E6EB")))
	sky_material.ground_horizon_color = sky_material.sky_horizon_color
	sky_material.ground_bottom_color = Color(String(lighting.get("ground", "#8E5C34")))
	var sky := Sky.new()
	sky.sky_material = sky_material
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(String(lighting.get("ambient", "#F0D0A1")))
	environment.ambient_light_energy = float(lighting.get("ambient_energy", 0.72))
	environment.fog_enabled = true
	environment.fog_light_color = sky_material.sky_horizon_color
	environment.fog_density = float(lighting.get("fog_density", 0.002))
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)

	var sun := DirectionalLight3D.new()
	var sun_rotation := lighting.get("sun_rotation_degrees", [-48.0, -32.0, 0.0]) as Array
	sun.rotation_degrees = Vector3(float(sun_rotation[0]), float(sun_rotation[1]), float(sun_rotation[2]))
	sun.light_color = Color(String(lighting.get("sun", "#FFF0C8")))
	sun.light_energy = float(lighting.get("sun_energy", 1.05))
	sun.shadow_enabled = true
	add_child(sun)


func _build_ground() -> void:
	var lighting := (_game_design_profile.get("lighting", {}) as Dictionary).get(_lighting_preset, {}) as Dictionary
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(140.0, 140.0) if _dense else Vector2(30.0, 19.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(String(lighting.get("ground", "#B8793D")))
	material.roughness = 0.94
	plane.material = material
	ground.mesh = plane
	add_child(ground)


func _load_lineup() -> void:
	var lineup_models := ULTIMATE_MODELS if _ultimate else MODELS
	for index: int in lineup_models.size():
		var model_name: String = lineup_models[index]
		var path := _model_path(model_name, _ultimate)
		if not ResourceLoader.exists(path):
			push_error("Asset local absent : " + path)
			continue
		var packed := load(path) as PackedScene
		if packed == null:
			push_error("Asset non chargeable : " + path)
			continue
		var instance := packed.instantiate() as Node3D
		instance.name = model_name
		if _ultimate:
			_adapt_ultimate_instance(instance, model_name)
		var column := index % 5
		var row := index / 5
		instance.position = Vector3(-10.0 + float(column) * 5.0, 0.0, -4.3 + float(row) * 6.0)
		add_child(instance)
		_add_label(model_name, instance.position + Vector3(0.0, 0.15, 1.45))
		_loaded_models += 1


func _model_path(model_name: String, ultimate: bool) -> String:
	if ultimate:
		return "%s/FBX/%s.fbx" % [ULTIMATE_SOURCE_ROOT, model_name]
	return "%s/%s.gltf" % [SOURCE_ROOT, model_name]


func _adapt_ultimate_instance(instance: Node3D, model_name: String) -> void:
	for node_value: Node in instance.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node_value as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		for surface_index: int in mesh_node.mesh.get_surface_count():
			var source_material := mesh_node.mesh.surface_get_material(surface_index)
			var material_name := source_material.resource_name if source_material != null else ""
			mesh_node.set_surface_override_material(surface_index, _build_ultimate_material(model_name, material_name))


func _build_ultimate_material(model_name: String, material_name: String) -> Material:
	var material := StandardMaterial3D.new()
	material.roughness = 0.92
	if model_name.begins_with("Rock_"):
		material.albedo_texture = load(ULTIMATE_SOURCE_ROOT + "/Textures/Rocks.jpg") as Texture2D
		material.albedo_color = Color(0.62, 0.43, 0.29)
		return material
	if material_name == "PalmTree_Leaves":
		material.albedo_texture = (load(ULTIMATE_SOURCE_ROOT + "/Textures/PalmTree_Leaves.png") as Texture2D)
		material.albedo_color = Color(0.48, 0.57, 0.31)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		material.alpha_scissor_threshold = 0.45
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		return material
	material.albedo_texture = (load(ULTIMATE_SOURCE_ROOT + "/Textures/PalmTree_Trunk.jpg") as Texture2D)
	material.normal_enabled = true
	material.normal_texture = (load(ULTIMATE_SOURCE_ROOT + "/Textures/PalmTree_Trunk_Normal.png") as Texture2D)
	material.albedo_color = Color(0.78, 0.64, 0.46)
	return material


func _add_label(model_name: String, world_position: Vector3) -> void:
	var label := Label3D.new()
	label.text = model_name
	label.position = world_position
	label.font_size = 28
	label.outline_size = 6
	label.modulate = Color.WHITE
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	add_child(label)


func _build_dense_population() -> void:
	var random := RandomNumberGenerator.new()
	random.seed = 7601
	var counts := (_game_design_profile.get("stress_test", {}) if _stress else _game_design_profile.get("composition", {})) as Dictionary
	var grass_count := int(counts.get("grass_instances", 0))
	var pebble_count := int(counts.get("pebble_instances", 0))
	var rock_count := int(counts.get("rock_instances", 0))
	_expected_dense_instances = grass_count + pebble_count + rock_count
	if _ultimate:
		_expected_dense_instances += 12 if _stress else 6
	var grass_models: Array[String] = ["Grass_Wispy_Short", "Grass_Wispy_Tall"]
	if _stress:
		grass_models.assign(["Grass_Common_Short", "Grass_Common_Tall", "Grass_Wispy_Short", "Grass_Wispy_Tall"])
	_add_multimesh_family(grass_models, grass_count, Vector2(0.65, 1.25), random, "grass")
	_add_multimesh_family(
		["Pebble_Round_1", "Pebble_Round_2", "Pebble_Round_3", "Pebble_Round_4", "Pebble_Round_5"],
		pebble_count,
		Vector2(0.65, 1.35),
		random,
		"pebble"
	)
	_add_multimesh_family(["Rock_Medium_1", "Rock_Medium_2", "Rock_Medium_3"], rock_count, Vector2(0.6, 1.0), random, "rock")
	if _ultimate:
		_add_ultimate_palm_landmark(10 if _stress else 5, random)
		_add_ultimate_rock_landmark(2 if _stress else 1)


func _add_ultimate_palm_landmark(count: int, random: RandomNumberGenerator) -> void:
	var model_names: Array[String] = ["PalmTree_1", "PalmTree_3"]
	if _stress:
		model_names.assign(["PalmTree_1", "PalmTree_2", "PalmTree_3", "PalmTree_4"])
	for model_index: int in model_names.size():
		var model_name := model_names[model_index]
		var packed := load(_model_path(model_name, true)) as PackedScene
		if packed == null:
			push_error("Palmier Ultimate non chargeable : " + model_name)
			continue
		var template := packed.instantiate() as Node3D
		var mesh_nodes := template.find_children("*", "MeshInstance3D", true, false)
		if mesh_nodes.is_empty():
			push_error("Palmier Ultimate sans maillage : " + model_name)
			template.free()
			continue
		var mesh_node := mesh_nodes[0] as MeshInstance3D
		var adapted_mesh := mesh_node.mesh.duplicate() as ArrayMesh
		for surface_index: int in adapted_mesh.get_surface_count():
			var source_material := adapted_mesh.surface_get_material(surface_index)
			var material_name := source_material.resource_name if source_material != null else ""
			adapted_mesh.surface_set_material(surface_index, _build_ultimate_material(model_name, material_name))
		var source_transform := mesh_node.transform
		var parent := mesh_node.get_parent()
		while parent != template and parent is Node3D:
			source_transform = (parent as Node3D).transform * source_transform
			parent = parent.get_parent()
		var variant_count := count / model_names.size()
		if model_index < count % model_names.size():
			variant_count += 1
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = adapted_mesh
		multimesh.instance_count = variant_count
		for variant_index: int in variant_count:
			var index := model_index + variant_index * model_names.size()
			var basis := Basis(Vector3.UP, random.randf_range(0.0, TAU)).scaled(Vector3.ONE * random.randf_range(0.9, 1.15))
			var position := Vector3(
				-22.0 + float(index % 5) * 3.2 + random.randf_range(-0.5, 0.5),
				0.05,
				-12.0 + float(index / 5) * 4.0 + random.randf_range(-0.5, 0.5)
			)
			multimesh.set_instance_transform(variant_index, Transform3D(basis, position) * source_transform)
		var multimesh_instance := MultiMeshInstance3D.new()
		multimesh_instance.name = model_name + "_Landmark_MultiMesh"
		multimesh_instance.multimesh = multimesh
		add_child(multimesh_instance)
		_dense_instances += variant_count
		_dense_model_variants += 1
		template.free()


func _add_ultimate_rock_landmark(count: int) -> void:
	var packed := load(_model_path("Rock_4", true)) as PackedScene
	if packed == null:
		push_error("Rocher-repere Ultimate non chargeable : Rock_4")
		return
	var template := packed.instantiate() as Node3D
	var mesh_nodes := template.find_children("*", "MeshInstance3D", true, false)
	if mesh_nodes.is_empty():
		push_error("Rocher-repere Ultimate sans maillage : Rock_4")
		template.free()
		return
	var mesh_node := mesh_nodes[0] as MeshInstance3D
	var adapted_mesh := mesh_node.mesh.duplicate() as ArrayMesh
	for surface_index: int in adapted_mesh.get_surface_count():
		adapted_mesh.surface_set_material(surface_index, _build_ultimate_material("Rock_4", "Rock"))
	var source_transform := mesh_node.transform
	var parent := mesh_node.get_parent()
	while parent != template and parent is Node3D:
		source_transform = (parent as Node3D).transform * source_transform
		parent = parent.get_parent()
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = adapted_mesh
	multimesh.instance_count = count
	for index: int in count:
		var scale := 2.8 + float(index) * 0.35
		var basis := Basis(Vector3.UP, -0.3 + float(index) * 0.55).scaled(Vector3.ONE * scale)
		var position := Vector3(24.0 + float(index) * 4.0, 0.6, -27.0 + float(index) * 6.0)
		multimesh.set_instance_transform(index, Transform3D(basis, position) * source_transform)
	var multimesh_instance := MultiMeshInstance3D.new()
	multimesh_instance.name = "Rock_4_Landmark_MultiMesh"
	multimesh_instance.multimesh = multimesh
	multimesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(multimesh_instance)
	_dense_instances += count
	_dense_model_variants += 1
	template.free()


func _add_multimesh_family(
	model_names: Array[String], total_count: int, scale_range: Vector2, random: RandomNumberGenerator, family: String
) -> void:
	for model_index: int in model_names.size():
		var model_name: String = model_names[model_index]
		var packed := load("%s/%s.gltf" % [SOURCE_ROOT, model_name]) as PackedScene
		if packed == null:
			push_error("Asset dense non chargeable : " + model_name)
			continue
		var template := packed.instantiate()
		var mesh_nodes := template.find_children("*", "MeshInstance3D", true, false)
		if mesh_nodes.is_empty():
			push_error("Asset dense sans maillage : " + model_name)
			template.free()
			continue
		var mesh_node := mesh_nodes[0] as MeshInstance3D
		var count := total_count / model_names.size()
		if model_index < total_count % model_names.size():
			count += 1
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = mesh_node.mesh
		multimesh.instance_count = count
		for instance_index: int in count:
			var scale := random.randf_range(scale_range.x, scale_range.y)
			var basis := Basis(Vector3.UP, random.randf_range(0.0, TAU)).scaled(Vector3.ONE * scale)
			var ground_offset := float(_ground_offsets_m.get(model_name, 0.0)) * scale
			var origin := _sample_position(random, family, ground_offset)
			multimesh.set_instance_transform(instance_index, Transform3D(basis, origin))
		var multimesh_instance := MultiMeshInstance3D.new()
		multimesh_instance.name = model_name + "_MultiMesh"
		multimesh_instance.multimesh = multimesh
		if family == "grass":
			multimesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		multimesh_instance.material_override = _build_sahara_material(model_name, mesh_node.mesh)
		add_child(multimesh_instance)
		_dense_instances += count
		_dense_model_variants += 1
		template.free()


func _sample_position(random: RandomNumberGenerator, family: String, ground_offset: float) -> Vector3:
	var gameplay := _game_design_profile.get("gameplay", {}) as Dictionary
	var composition := _game_design_profile.get("composition", {}) as Dictionary
	var corridor_half_width := float(gameplay.get("clear_route_half_width_m", 5.0))
	var rock_spacing := float(gameplay.get("minimum_rock_spacing_m", 8.0))
	if _stress:
		rock_spacing = 2.0
	var threshold := -1.0
	if family == "grass":
		threshold = float(composition.get("grass_patch_threshold", 0.05))
	elif family == "pebble":
		threshold = float(composition.get("pebble_patch_threshold", -0.25))
	for attempt: int in 32:
		var x := random.randf_range(-31.0, 31.0)
		var z := random.randf_range(-31.0, 31.0)
		if absf(x) < corridor_half_width:
			continue
		if threshold > -1.0 and _patch_noise.get_noise_2d(x, z) < threshold:
			continue
		if family == "rock":
			var candidate := Vector2(x, z)
			var too_close := false
			for position: Vector2 in _rock_positions:
				if position.distance_to(candidate) < rock_spacing:
					too_close = true
					break
			if too_close:
				continue
			_rock_positions.append(candidate)
		return Vector3(x, ground_offset, z)
	push_error("Impossible de placer un asset %s sans obstruer la route." % family)
	_placement_failed = true
	return Vector3(corridor_half_width + 1.0, ground_offset, 0.0)


func _build_sahara_material(model_name: String, mesh: Mesh) -> Material:
	if model_name.begins_with("Rock_Medium_"):
		var desert_rock := StandardMaterial3D.new()
		desert_rock.albedo_texture = load(SOURCE_ROOT + "/Rocks_Desert_Diffuse.png") as Texture2D
		desert_rock.albedo_color = Color(0.68, 0.56, 0.42)
		desert_rock.roughness = 0.96
		return desert_rock
	var source := mesh.surface_get_material(0) as BaseMaterial3D
	if source == null:
		return null
	var adapted := source.duplicate() as BaseMaterial3D
	if model_name.begins_with("Grass_Common_"):
		adapted.albedo_color *= Color(0.72, 0.66, 0.48)
	elif model_name.begins_with("Grass_Wispy_"):
		adapted.albedo_color *= Color(0.88, 0.82, 0.68)
	return adapted


func _save_capture() -> void:
	DirAccess.make_dir_recursive_absolute(_capture_path.get_base_dir())
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		push_error("Capture du laboratoire impossible.")
		return
	var error := image.save_png(_capture_path)
	if error != OK:
		push_error("Écriture de la capture impossible : %s" % error_string(error))


func _write_report() -> void:
	if _report_path.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(_report_path.get_base_dir())
	var sorted_times := _frame_times_ms.duplicate()
	sorted_times.sort()
	var total_ms := 0.0
	for frame_ms: float in sorted_times:
		total_ms += frame_ms
	var p99_index := clampi(ceili(float(sorted_times.size()) * 0.99) - 1, 0, maxi(sorted_times.size() - 1, 0))
	var report := {
		"archive_sha256": ARCHIVE_SHA256,
		"ultimate_fbx_archive_sha256": ULTIMATE_FBX_ARCHIVE_SHA256 if _ultimate else "",
		"ultimate_complement_enabled": _ultimate,
		"loaded_models": _loaded_models,
		"dense_instances": _dense_instances,
		"measured_frames": sorted_times.size(),
		"average_frame_ms": total_ms / float(sorted_times.size()) if not sorted_times.is_empty() else 0.0,
		"p99_frame_ms": sorted_times[p99_index] if not sorted_times.is_empty() else 0.0,
		"lineup_requested_models": ULTIMATE_MODELS.size() if _ultimate else MODELS.size(),
		"dense_model_variants": _dense_model_variants,
		"stress_test": _stress,
		"lighting_preset": _lighting_preset,
		"clear_route_width_m": float((_game_design_profile.get("gameplay", {}) as Dictionary).get("clear_route_half_width_m", 5.0)) * 2.0,
		"peak_draw_calls": _peak_draw_calls,
		"peak_primitives": _peak_primitives,
		"rendering_device": RenderingServer.get_video_adapter_name(),
		"rendering_driver": RenderingServer.get_current_rendering_driver_name(),
		"rendering_method": RenderingServer.get_current_rendering_method(),
		"viewport": [get_viewport().size.x, get_viewport().size.y],
	}
	var file := FileAccess.open(_report_path, FileAccess.WRITE)
	if file == null:
		push_error("Écriture du rapport impossible : " + _report_path)
		return
	file.store_string(JSON.stringify(report, "  "))
	file.close()
