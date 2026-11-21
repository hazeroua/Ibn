class_name NatureAssetLab
extends Node3D
## Laboratoire isolé pour évaluer le pack local Quaternius sans l'ajouter au jeu livré.
## Les sources restent sous assets_local/, dossier ignoré par Git.

const SOURCE_ROOT := "res://assets_local/quaternius-stylized-nature-standard/glTF"
const PROFILE_PATH := "res://data/assets/oasis_nature_profile.json"
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
const ARCHIVE_SHA256 := "298f6732b872e4cf7b30e6e7abf9641c7f6dc6b326df37ac089533ed7e3d58c9"
const CAPTURE_DELAY_FRAMES := 90
const MEASURE_FRAMES := 420
const DENSE_EXPECTED_INSTANCES := 1250

var _capture_path := ""
var _report_path := ""
var _dense := false
var _frame_count := 0
var _loaded_models := 0
var _dense_instances := 0
var _peak_draw_calls := 0
var _peak_primitives := 0
var _frame_times_ms := PackedFloat64Array()
var _ground_offsets_m: Dictionary = {}


func _ready() -> void:
	_parse_arguments()
	_load_profile()
	_build_environment()
	_build_ground()
	if _dense:
		_build_dense_population()
		if _dense_instances != DENSE_EXPECTED_INSTANCES:
			push_error(
				(
					"Asset lab dense incomplet : %d/%d instances."
					% [_dense_instances, DENSE_EXPECTED_INSTANCES]
				)
			)
			get_tree().quit(1)
			return
		$Camera.position = Vector3(0.0, 35.0, 48.0)
		$Camera.look_at(Vector3.ZERO)
	else:
		_load_lineup()
		$Camera.look_at(Vector3(0.0, 0.7, -0.5))
	if not _dense and _loaded_models != MODELS.size():
		push_error("Asset lab incomplet : %d/%d modèles chargés." % [_loaded_models, MODELS.size()])
		get_tree().quit(1)


func _process(delta: float) -> void:
	_frame_count += 1
	_peak_draw_calls = maxi(
		_peak_draw_calls, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	)
	_peak_primitives = maxi(
		_peak_primitives, int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	)
	if _frame_count == CAPTURE_DELAY_FRAMES and not _capture_path.is_empty():
		_save_capture()
	if _frame_count > CAPTURE_DELAY_FRAMES:
		_frame_times_ms.append(delta * 1000.0)
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


func _load_profile() -> void:
	var profile := JsonData.load_dictionary(PROFILE_PATH)
	var families := profile.get("families", {}) as Dictionary
	for family_value: Variant in families.values():
		var family := family_value as Dictionary
		var offsets := family.get("required_ground_offsets_m", {}) as Dictionary
		_ground_offsets_m.merge(offsets, true)


func _build_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("8eb9d5")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("ffe2bc")
	environment.ambient_light_energy = 0.75
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
	sun.light_color = Color("fff1ce")
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	add_child(sun)


func _build_ground() -> void:
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(72.0, 72.0) if _dense else Vector2(30.0, 19.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("b98855")
	material.roughness = 0.94
	plane.material = material
	ground.mesh = plane
	add_child(ground)


func _load_lineup() -> void:
	for index: int in MODELS.size():
		var model_name: String = MODELS[index]
		var path := "%s/%s.gltf" % [SOURCE_ROOT, model_name]
		if not ResourceLoader.exists(path):
			push_error("Asset local absent : " + path)
			continue
		var packed := load(path) as PackedScene
		if packed == null:
			push_error("Asset non chargeable : " + path)
			continue
		var instance := packed.instantiate() as Node3D
		instance.name = model_name
		var column := index % 6
		var row := index / 6
		instance.position = Vector3(-10.0 + float(column) * 4.0, 0.0, -4.3 + float(row) * 4.2)
		add_child(instance)
		_add_label(model_name, instance.position + Vector3(0.0, 0.15, 1.45))
		_loaded_models += 1


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
	_add_multimesh_family(
		["Grass_Common_Short", "Grass_Common_Tall", "Grass_Wispy_Short", "Grass_Wispy_Tall"],
		1000,
		Vector2(0.65, 1.25),
		random
	)
	_add_multimesh_family(
		["Pebble_Round_1", "Pebble_Round_2", "Pebble_Round_3", "Pebble_Round_4", "Pebble_Round_5"],
		200,
		Vector2(0.65, 1.35),
		random
	)
	_add_multimesh_family(
		["Rock_Medium_1", "Rock_Medium_2", "Rock_Medium_3"], 50, Vector2(0.6, 1.0), random
	)


func _add_multimesh_family(
	model_names: Array[String],
	total_count: int,
	scale_range: Vector2,
	random: RandomNumberGenerator
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
			var origin := Vector3(
				random.randf_range(-31.0, 31.0), ground_offset, random.randf_range(-31.0, 31.0)
			)
			multimesh.set_instance_transform(instance_index, Transform3D(basis, origin))
		var multimesh_instance := MultiMeshInstance3D.new()
		multimesh_instance.name = model_name + "_MultiMesh"
		multimesh_instance.multimesh = multimesh
		multimesh_instance.material_override = _build_sahara_material(model_name, mesh_node.mesh)
		add_child(multimesh_instance)
		_dense_instances += count
		template.free()


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
	var p99_index := clampi(
		ceili(float(sorted_times.size()) * 0.99) - 1, 0, maxi(sorted_times.size() - 1, 0)
	)
	var report := {
		"archive_sha256": ARCHIVE_SHA256,
		"loaded_models": _loaded_models,
		"dense_instances": _dense_instances,
		"measured_frames": sorted_times.size(),
		"average_frame_ms":
		total_ms / float(sorted_times.size()) if not sorted_times.is_empty() else 0.0,
		"p99_frame_ms": sorted_times[p99_index] if not sorted_times.is_empty() else 0.0,
		"lineup_requested_models": MODELS.size(),
		"dense_model_variants": 12 if _dense else 0,
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
