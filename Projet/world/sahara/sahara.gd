extends Node3D
## Sahara de 4 × 4 km : charge les régions Terrain3D construites par SaharaBuilder,
## les quatre sols (sable, terre sèche, gravier, roche) et leurs réglages d'anti-répétition.
## En jeu : caméra libre. Avec la sonde de mesure : tournée de captures depuis les points
## de vue, puis parcours de collision à pied, en course et à pleine vitesse, caméra en poursuite.

const DATA_PATH: String = "res://data/sahara/sahara.json"
const CONTEXT: String = "sahara.json › scene"
const LOG_CATEGORY: String = "sahara"
const COLLISION_CHECK_INTERVAL_SECONDS: float = 1.0
const COLLISION_RAY_LENGTH_METERS: float = 1000.0
const SETTLE_SECONDS: float = 2.0

var _terrain: Terrain3D
var _camera: FreeCamera
var _runner: RouteRunner
var _probe: PerformanceProbe
var _viewpoints: Array[Dictionary] = []
var _viewpoint_seconds: float = 1.0
var _viewpoint_index: int = -1
var _viewpoint_timer: float = 0.0
var _chase_distance: float = 7.0
var _chase_height: float = 2.5
var _chase_smoothing: float = 8.0
var _collision_timer: float = 0.0
var _collision_checks: int = 0
var _collision_failures: int = 0
var _ray_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()


func _ready() -> void:
	var start_usec: int = Time.get_ticks_usec()
	var errors: PackedStringArray = PackedStringArray()
	var data: Dictionary = JsonData.load_dictionary(DATA_PATH)
	var generation: SaharaSettings = SaharaSettings.from_dictionary(JsonData.read_dictionary(data, "generation", errors, "sahara.json"))
	errors.append_array(generation.errors)
	var scene: Dictionary = JsonData.read_dictionary(data, "scene", errors, "sahara.json")
	if errors.is_empty():
		SceneEnvironment.build(self, JsonData.read_dictionary(scene, "environment", errors, CONTEXT), errors, CONTEXT + " › environment")
		_create_terrain(generation, scene, errors)
	if errors.is_empty():
		_create_camera(JsonData.read_dictionary(scene, "camera", errors, CONTEXT), generation, errors)
		_probe = get_tree().get_first_node_in_group(PerformanceProbe.GROUP) as PerformanceProbe
		if _probe != null:
			_prepare_measure(scene, errors)
	if not errors.is_empty():
		for message: String in errors:
			GameLog.error(LOG_CATEGORY, message)
		get_tree().quit(PerformanceProbe.EXIT_FAILURE)
		return
	if _probe == null:
		SceneEnvironment.add_help(self, JsonData.read_string(scene, "help_text", errors, CONTEXT))
		set_process(false)
		set_physics_process(false)
	(
		GameLog
		. info(
			LOG_CATEGORY,
			(
				"Sahara chargé en %.0f ms : %d régions Terrain3D, %d sols (%s)."
				% [
					float(Time.get_ticks_usec() - start_usec) / 1000.0,
					_terrain.data.get_region_count(),
					_terrain.assets.get_texture_count(),
					"parcours de mesure" if _probe != null else "caméra libre",
				]
			)
		)
	)


func _process(delta: float) -> void:
	if not _probe.is_measuring():
		return
	if _probe.is_warming_up():
		_run_viewpoint_tour(delta)
		return
	_follow_runner(delta)


func _physics_process(delta: float) -> void:
	if not _probe.is_measuring() or _probe.is_warming_up():
		return
	_runner.step(delta, _probe.measured_fraction())
	_collision_timer += delta
	if _collision_timer < COLLISION_CHECK_INTERVAL_SECONDS:
		return
	_collision_timer -= COLLISION_CHECK_INTERVAL_SECONDS
	_ray_query.from = _runner.global_position + Vector3.UP * 2.0
	_ray_query.to = _ray_query.from + Vector3.DOWN * COLLISION_RAY_LENGTH_METERS
	_collision_checks += 1
	if get_world_3d().direct_space_state.intersect_ray(_ray_query).is_empty():
		_collision_failures += 1
		GameLog.warning(LOG_CATEGORY, "Collision absente sous %s." % str(_runner.global_position))
	_probe.report_metric("collision_checks", _collision_checks)
	_probe.report_metric("collision_failures", _collision_failures)
	_probe.report_metric("body_below_ground_events", _runner.below_ground_events)
	_probe.report_metric("body_stuck_events", _runner.stuck_events)
	_probe.report_metric("route_distance_meters", _runner.distance_meters)


func _create_terrain(generation: SaharaSettings, scene: Dictionary, errors: PackedStringArray) -> void:
	var context: String = CONTEXT + " › terrain"
	var settings: Dictionary = JsonData.read_dictionary(scene, "terrain", errors, CONTEXT)
	var collision: Dictionary = JsonData.read_dictionary(settings, "collision", errors, context)
	if not DirAccess.dir_exists_absolute(SaharaBuilder.TERRAIN_DIR) or DirAccess.get_files_at(SaharaBuilder.TERRAIN_DIR).is_empty():
		errors.append("Terrain non construit (%s) : lancez valider.bat." % SaharaBuilder.TERRAIN_DIR)
	var assets: Terrain3DAssets = _create_assets(scene.get("textures"), errors)
	if not errors.is_empty():
		return

	_terrain = Terrain3D.new()
	_terrain.name = "Terrain3D"
	_terrain.free_editor_textures = false
	_terrain.vertex_spacing = generation.vertex_spacing_meters
	_terrain.mesh_lods = int(JsonData.read_number(settings, "mesh_lods", errors, context))
	_terrain.mesh_size = int(JsonData.read_number(settings, "mesh_size", errors, context))
	_terrain.assets = assets
	_terrain.data_directory = SaharaBuilder.TERRAIN_DIR
	# Options du shader fixées avant l'entrée dans l'arbre : une seule compilation
	# (les changer ensuite recompile le shader et retarde la première image de plusieurs secondes).
	var material: Terrain3DMaterial = Terrain3DMaterial.new()
	material.world_background = Terrain3DMaterial.FLAT
	material.auto_shader_enabled = false
	material.macro_variation_enabled = true
	material.dual_scaling_enabled = true
	_terrain.material = material
	add_child(_terrain)

	# Au-delà de la carte, un sol plat à l'altitude de base prolonge l'horizon.
	material.set_shader_param(&"ground_level", generation.base_height_meters)
	var macro: Dictionary = JsonData.read_dictionary(settings, "macro_variation", errors, context)
	material.set_shader_param(&"macro_variation1", JsonData.read_color(macro, "color_1", errors, context + " › macro_variation"))
	material.set_shader_param(&"macro_variation2", JsonData.read_color(macro, "color_2", errors, context + " › macro_variation"))
	material.set_shader_param(&"macro_variation_slope", JsonData.read_number(macro, "slope", errors, context + " › macro_variation"))
	material.set_shader_param(&"noise1_scale", JsonData.read_number(macro, "noise_1_scale", errors, context + " › macro_variation"))
	material.set_shader_param(&"noise2_scale", JsonData.read_number(macro, "noise_2_scale", errors, context + " › macro_variation"))
	material.set_shader_param(&"noise_texture", _create_macro_noise(macro, generation.world_seed, errors, context + " › macro_variation"))
	var dual: Dictionary = JsonData.read_dictionary(settings, "dual_scaling", errors, context)
	var dual_ground: int = SaharaSurface.GROUND_NAMES.find(JsonData.read_string(dual, "texture", errors, context + " › dual_scaling"))
	if dual_ground < 0:
		errors.append(context + " › dual_scaling : sol inconnu.")
	material.set_shader_param(&"dual_scale_texture", dual_ground)
	material.set_shader_param(&"dual_scale_reduction", JsonData.read_number(dual, "reduction", errors, context + " › dual_scaling"))
	material.set_shader_param(&"dual_scale_near", JsonData.read_number(dual, "near_meters", errors, context + " › dual_scaling"))
	material.set_shader_param(&"dual_scale_far", JsonData.read_number(dual, "far_meters", errors, context + " › dual_scaling"))
	material.set_shader_param(&"blend_sharpness", JsonData.read_number(settings, "blend_sharpness", errors, context))

	_terrain.collision.mode = Terrain3DCollision.DYNAMIC_GAME
	_terrain.collision.radius = int(JsonData.read_number(collision, "radius", errors, context + " › collision"))
	_terrain.collision.shape_size = int(JsonData.read_number(collision, "shape_size", errors, context + " › collision"))
	var expected_regions: int = int(pow(generation.map_size_meters / (generation.vertex_spacing_meters * generation.region_size), 2.0))
	if _terrain.data.get_region_count() != expected_regions:
		errors.append("Terrain3D : %d régions chargées au lieu de %d." % [_terrain.data.get_region_count(), expected_regions])


func _create_assets(textures: Variant, errors: PackedStringArray) -> Terrain3DAssets:
	var assets: Terrain3DAssets = Terrain3DAssets.new()
	if typeof(textures) != TYPE_ARRAY or (textures as Array).size() != SaharaSurface.GROUND_NAMES.size():
		errors.append(CONTEXT + " › textures : il faut un sol par identifiant (%s)." % ", ".join(SaharaSurface.GROUND_NAMES))
		return assets
	for ground_id: int in SaharaSurface.GROUND_NAMES.size():
		var entry: Dictionary = textures[ground_id]
		var context: String = CONTEXT + " › textures[%d]" % ground_id
		var ground: String = JsonData.read_string(entry, "ground", errors, context)
		if ground != SaharaSurface.GROUND_NAMES[ground_id]:
			errors.append("%s : « %s » attendu à cette position." % [context, SaharaSurface.GROUND_NAMES[ground_id]])
			continue
		var albedo: Texture2D = load(SaharaBuilder.albedo_path(ground)) as Texture2D
		var normal: Texture2D = load(SaharaBuilder.normal_path(ground)) as Texture2D
		if albedo == null or normal == null:
			errors.append("%s : textures empaquetées absentes pour « %s » (lancez valider.bat)." % [context, ground])
			continue
		var texture: Terrain3DTextureAsset = Terrain3DTextureAsset.new()
		texture.name = ground
		texture.albedo_texture = albedo
		texture.normal_texture = normal
		texture.uv_scale = JsonData.read_number(entry, "uv_scale", errors, context)
		texture.detiling_rotation = JsonData.read_number(entry, "detiling_rotation", errors, context)
		texture.detiling_shift = JsonData.read_number(entry, "detiling_shift", errors, context)
		texture.normal_depth = JsonData.read_number(entry, "normal_depth", errors, context)
		texture.roughness = JsonData.read_number(entry, "roughness", errors, context)
		assets.set_texture_asset(ground_id, texture)
	return assets


static func _create_macro_noise(data: Dictionary, world_seed: int, errors: PackedStringArray, context: String) -> NoiseTexture2D:
	var size: int = int(JsonData.read_number(data, "noise_wavelength_pixels", errors, context))
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = world_seed + 301
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 4.0 / float(maxi(size, 1))
	noise.fractal_octaves = 4
	var texture: NoiseTexture2D = NoiseTexture2D.new()
	texture.width = size
	texture.height = size
	texture.seamless = true
	texture.generate_mipmaps = true
	texture.noise = noise
	return texture


func _create_camera(data: Dictionary, generation: SaharaSettings, errors: PackedStringArray) -> void:
	var context: String = CONTEXT + " › camera"
	_camera = FreeCamera.new()
	_camera.name = "FreeCamera"
	_camera.far = JsonData.read_number(data, "far", errors, context)
	_camera.terrain_data = _terrain.data
	_camera.map_half_extent = generation.half_extent()
	_camera.configure(JsonData.read_dictionary(data, "free", errors, context), errors, context + " › free")
	add_child(_camera)
	_camera.current = true
	_terrain.clipmap_target = _camera
	_terrain.collision_target = _camera
	var spawn: Vector3 = JsonData.read_vector3(data, "spawn", errors, context)
	var spawn_height: float = JsonData.read_number(data, "spawn_height_above_ground", errors, context)
	_place_camera(spawn, spawn_height, JsonData.read_vector3(data, "look_at", errors, context))


func _place_camera(position_xz: Vector3, height_above_ground: float, look_at_xz: Vector3) -> void:
	_camera.global_position = Vector3(position_xz.x, _terrain.data.get_height(position_xz) + height_above_ground, position_xz.z)
	var target: Vector3 = Vector3(look_at_xz.x, _terrain.data.get_height(look_at_xz) + 2.0, look_at_xz.z)
	_camera.look_toward(target)


func _prepare_measure(scene: Dictionary, errors: PackedStringArray) -> void:
	_camera.set_process(false)
	_camera.set_process_unhandled_input(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_viewpoint_seconds = JsonData.read_number(scene, "viewpoint_seconds", errors, CONTEXT)
	var viewpoints: Variant = scene.get("viewpoints")
	if typeof(viewpoints) != TYPE_ARRAY or (viewpoints as Array).size() < 3:
		errors.append(CONTEXT + " : au moins trois points de vue (général, au sol, pire cas).")
		return
	for viewpoint: Variant in viewpoints:
		var context: String = CONTEXT + " › viewpoints"
		var entry: Dictionary = viewpoint if typeof(viewpoint) == TYPE_DICTIONARY else {}
		(
			_viewpoints
			. append(
				{
					"name": JsonData.read_string(entry, "name", errors, context),
					"position": JsonData.read_vector3(entry, "position", errors, context),
					"height": JsonData.read_number(entry, "height_above_ground", errors, context),
					"look_at": JsonData.read_vector3(entry, "look_at", errors, context),
				}
			)
		)
	_probe.extend_warmup(_viewpoint_seconds * float(_viewpoints.size()) + SETTLE_SECONDS)

	var route: Dictionary = JsonData.read_dictionary(scene, "measure_route", errors, CONTEXT)
	var chase: Dictionary = JsonData.read_dictionary(route, "chase_camera", errors, CONTEXT + " › measure_route")
	_chase_distance = JsonData.read_number(chase, "distance_meters", errors, CONTEXT + " › chase_camera")
	_chase_height = JsonData.read_number(chase, "height_meters", errors, CONTEXT + " › chase_camera")
	_chase_smoothing = JsonData.read_number(chase, "smoothing", errors, CONTEXT + " › chase_camera")
	_runner = RouteRunner.new()
	_runner.name = "RouteRunner"
	_runner.terrain_data = _terrain.data
	_runner.configure(route, errors, CONTEXT + " › measure_route")
	if not errors.is_empty():
		return
	add_child(_runner)
	_runner.place_at_start()
	_terrain.collision_target = _runner
	_ray_query.collide_with_areas = false
	_ray_query.exclude = [_runner.get_rid()]


func _run_viewpoint_tour(delta: float) -> void:
	if _viewpoint_index >= _viewpoints.size():
		_follow_runner(delta)
		return
	if _viewpoint_index < 0:
		_viewpoint_index = 0
		_show_viewpoint()
		return
	_viewpoint_timer += delta
	if _viewpoint_timer < _viewpoint_seconds:
		return
	_probe.save_named_capture("vue_%s.png" % _viewpoints[_viewpoint_index]["name"])
	_viewpoint_index += 1
	_viewpoint_timer = 0.0
	if _viewpoint_index < _viewpoints.size():
		_show_viewpoint()
	else:
		_follow_runner(1.0)


func _show_viewpoint() -> void:
	var viewpoint: Dictionary = _viewpoints[_viewpoint_index]
	_place_camera(viewpoint["position"], viewpoint["height"], viewpoint["look_at"])


func _follow_runner(delta: float) -> void:
	var body: Vector3 = _runner.global_position
	var desired: Vector3 = body - _runner.heading() * _chase_distance + Vector3.UP * _chase_height
	var weight: float = 1.0 - exp(-_chase_smoothing * delta)
	var next_position: Vector3 = _camera.global_position.lerp(desired, weight)
	var ground: float = _terrain.data.get_height(next_position)
	if not is_nan(ground):
		next_position.y = maxf(next_position.y, ground + 1.0)
	_camera.global_position = next_position
	_camera.look_toward(body + Vector3.UP * 1.5)
