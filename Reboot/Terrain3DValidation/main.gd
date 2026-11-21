extends Node3D

const MAP_SIZE_METERS: int = 4096
const HEIGHTMAP_SIZE: int = 2048
const VERTEX_SPACING_METERS: float = 2.0
const CAMERA_HEIGHT_METERS: float = 12.0
const CAMERA_RADIUS_METERS: float = 1750.0
const CAMERA_SPEED_METERS_PER_SECOND: float = 70.0
const DEFAULT_DURATION_SECONDS: float = 1800.0
const HISTOGRAM_BIN_MS: float = 0.1
const HISTOGRAM_BIN_COUNT: int = 2000
const REPORT_INTERVAL_SECONDS: float = 10.0
const WARMUP_SECONDS: float = 5.0
const MAX_P99_FRAME_MS: float = 16.6
const MAX_SINGLE_FRAME_MS: float = 50.0
const MAX_DRAW_CALLS: int = 300
const MAX_VIDEO_MEMORY_BYTES: int = 512 * 1024 * 1024

var _terrain: Terrain3D
var _camera: Camera3D
var _elapsed_seconds: float = 0.0
var _measurement_elapsed_seconds: float = 0.0
var _report_elapsed_seconds: float = 0.0
var _target_duration_seconds: float = DEFAULT_DURATION_SECONDS
var _report_path: String = "res://reports/terrain3d-validation.json"
var _frame_count: int = 0
var _frame_time_sum_ms: float = 0.0
var _frame_time_max_ms: float = 0.0
var _frames_over_budget: int = 0
var _collision_checks: int = 0
var _collision_failures: int = 0
var _histogram: PackedInt32Array = PackedInt32Array()
var _last_collision_second: int = -1
var _initialization_ms: float = 0.0
var _capture_saved: bool = false
var _peak_draw_calls: int = 0
var _peak_primitives: int = 0
var _peak_video_memory_bytes: int = 0
var _peak_process_ms: float = 0.0
var _peak_physics_process_ms: float = 0.0


func _ready() -> void:
	_target_duration_seconds = _read_duration_argument()
	_report_path = _read_report_argument()
	_histogram.resize(HISTOGRAM_BIN_COUNT)
	if not ClassDB.class_exists(&"Terrain3D") or not ClassDB.can_instantiate(&"Terrain3D"):
		_fail("Terrain3D n'est pas chargé.")
		return

	var initialization_start_usec: int = Time.get_ticks_usec()
	_create_environment()
	_create_terrain()
	_initialization_ms = float(Time.get_ticks_usec() - initialization_start_usec) / 1000.0
	print("VALIDATION_READY version=", _terrain.get_version(), " init_ms=", snappedf(_initialization_ms, 0.01))


func _process(delta: float) -> void:
	if _terrain == null:
		return

	_elapsed_seconds += delta
	_move_camera()
	if not _capture_saved and _elapsed_seconds >= 2.0:
		_save_capture()
	if _elapsed_seconds < WARMUP_SECONDS:
		return
	_measurement_elapsed_seconds += delta
	_report_elapsed_seconds += delta
	_frame_count += 1
	var frame_time_ms: float = delta * 1000.0
	_frame_time_sum_ms += frame_time_ms
	_frame_time_max_ms = maxf(_frame_time_max_ms, frame_time_ms)
	if frame_time_ms > 16.6667:
		_frames_over_budget += 1
	var histogram_index: int = mini(int(frame_time_ms / HISTOGRAM_BIN_MS), HISTOGRAM_BIN_COUNT - 1)
	_histogram[histogram_index] += 1
	_peak_draw_calls = maxi(_peak_draw_calls, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	_peak_primitives = maxi(_peak_primitives, int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
	_peak_video_memory_bytes = maxi(_peak_video_memory_bytes, int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)))
	_peak_process_ms = maxf(_peak_process_ms, float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0)
	_peak_physics_process_ms = maxf(_peak_physics_process_ms, float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0)

	if _report_elapsed_seconds >= REPORT_INTERVAL_SECONDS:
		_report_elapsed_seconds = 0.0
		print(
			"VALIDATION_PROGRESS seconds=",
			int(_measurement_elapsed_seconds),
			" fps=",
			Engine.get_frames_per_second(),
			" draw_calls=",
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		)

	if _measurement_elapsed_seconds >= _target_duration_seconds:
		_finish()


func _physics_process(_delta: float) -> void:
	if _terrain == null or _elapsed_seconds < WARMUP_SECONDS:
		return
	_check_collision_once_per_second()


func _create_environment() -> void:
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.42, 0.64, 0.82)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.72, 0.75, 0.78)
	environment.ambient_light_energy = 0.65
	var world_environment: WorldEnvironment = WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)

	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -28.0, 0.0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.shadow_bias = 0.12
	sun.shadow_normal_bias = 1.8
	add_child(sun)

	_camera = Camera3D.new()
	_camera.current = true
	_camera.far = 6000.0
	add_child(_camera)


func _create_terrain() -> void:
	_terrain = Terrain3D.new()
	_terrain.name = "Terrain3D"
	_terrain.free_editor_textures = false
	_terrain.region_size = Terrain3D.SIZE_512
	_terrain.vertex_spacing = VERTEX_SPACING_METERS
	add_child(_terrain)

	_terrain.material.world_background = Terrain3DMaterial.NONE
	_terrain.material.auto_shader_enabled = false
	_terrain.assets.set_texture_asset(0, _create_sand_texture())

	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = 1332
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.00065
	noise.fractal_octaves = 5
	noise.fractal_lacunarity = 2.0
	noise.fractal_gain = 0.48
	var heightmap: Image = Image.create_empty(HEIGHTMAP_SIZE, HEIGHTMAP_SIZE, false, Image.FORMAT_RF)
	for image_z: int in HEIGHTMAP_SIZE:
		for image_x: int in HEIGHTMAP_SIZE:
			var sample_x: float = float(image_x) * VERTEX_SPACING_METERS
			var sample_z: float = float(image_z) * VERTEX_SPACING_METERS
			var height: float = noise.get_noise_2d(sample_x, sample_z)
			heightmap.set_pixel(image_x, image_z, Color(height, 0.0, 0.0, 1.0))
	_terrain.data.import_images([heightmap, null, null], Vector3(-MAP_SIZE_METERS * 0.5, 0.0, -MAP_SIZE_METERS * 0.5), 0.0, 95.0)
	_terrain.collision.mode = Terrain3DCollision.DYNAMIC_GAME
	_terrain.collision.radius = 128
	_terrain.collision.shape_size = 32
	_terrain.collision.build()


func _create_sand_texture() -> Terrain3DTextureAsset:
	var albedo_image: Image = Image.create_empty(256, 256, true, Image.FORMAT_RGBA8)
	albedo_image.fill(Color(0.67, 0.43, 0.20, 0.55))
	albedo_image.generate_mipmaps()
	var normal_image: Image = Image.create_empty(256, 256, true, Image.FORMAT_RGBA8)
	normal_image.fill(Color(0.5, 0.5, 1.0, 0.88))
	normal_image.generate_mipmaps()
	var texture_asset: Terrain3DTextureAsset = Terrain3DTextureAsset.new()
	texture_asset.name = "Validation Sand"
	texture_asset.albedo_texture = ImageTexture.create_from_image(albedo_image)
	texture_asset.normal_texture = ImageTexture.create_from_image(normal_image)
	texture_asset.uv_scale = 0.08
	return texture_asset


func _move_camera() -> void:
	var angular_speed: float = CAMERA_SPEED_METERS_PER_SECOND / CAMERA_RADIUS_METERS
	var angle: float = _elapsed_seconds * angular_speed
	var ground_position: Vector3 = Vector3(cos(angle), 0.0, sin(angle)) * CAMERA_RADIUS_METERS
	var ground_height: float = _terrain.data.get_height(ground_position)
	_camera.position = ground_position + Vector3.UP * (ground_height + CAMERA_HEIGHT_METERS)
	var look_target: Vector3 = ground_position + Vector3(-sin(angle), 0.0, cos(angle)) * 120.0
	look_target.y = _terrain.data.get_height(look_target) + 3.0
	_camera.look_at(look_target, Vector3.UP)


func _check_collision_once_per_second() -> void:
	var current_second: int = int(_measurement_elapsed_seconds)
	if current_second == _last_collision_second:
		return
	_last_collision_second = current_second
	_collision_checks += 1
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		_camera.global_position, _camera.global_position + Vector3.DOWN * 500.0
	)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		_collision_failures += 1
		push_warning("Collision Terrain3D absente à t=" + str(current_second) + " s.")


func _read_duration_argument() -> float:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--duration="):
			return maxf(float(argument.trim_prefix("--duration=")), 5.0)
	return DEFAULT_DURATION_SECONDS


func _read_report_argument() -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):
			return argument.trim_prefix("--report=")
	return "res://reports/terrain3d-validation.json"


func _percentile_ms(percentile: float) -> float:
	var target_count: int = ceili(float(_frame_count) * percentile)
	var cumulative_count: int = 0
	for index: int in _histogram.size():
		cumulative_count += _histogram[index]
		if cumulative_count >= target_count:
			return float(index) * HISTOGRAM_BIN_MS
	return float(HISTOGRAM_BIN_COUNT - 1) * HISTOGRAM_BIN_MS


func _save_capture() -> void:
	_capture_saved = true
	var absolute_report_path: String = ProjectSettings.globalize_path(_report_path)
	var capture_path: String = absolute_report_path.get_basename() + ".png"
	DirAccess.make_dir_recursive_absolute(capture_path.get_base_dir())
	var image: Image = get_viewport().get_texture().get_image()
	var save_error: Error = image.save_png(capture_path)
	if save_error != OK:
		_fail("Impossible d'écrire la capture de validation : " + error_string(save_error))


func _finish() -> void:
	var average_ms: float = _frame_time_sum_ms / maxf(float(_frame_count), 1.0)
	var p99_frame_ms: float = _percentile_ms(0.99)
	var budgets_passed: bool = (
		_collision_failures == 0
		and p99_frame_ms <= MAX_P99_FRAME_MS
		and _frame_time_max_ms < MAX_SINGLE_FRAME_MS
		and _peak_draw_calls <= MAX_DRAW_CALLS
		and _peak_video_memory_bytes <= MAX_VIDEO_MEMORY_BYTES
	)
	var report: Dictionary = {
		"terrain3d_version": _terrain.get_version(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"rendering_device": RenderingServer.get_video_adapter_name(),
		"duration_seconds": _measurement_elapsed_seconds,
		"warmup_seconds": WARMUP_SECONDS,
		"map_size_meters": MAP_SIZE_METERS,
		"heightmap_size": HEIGHTMAP_SIZE,
		"vertex_spacing_meters": VERTEX_SPACING_METERS,
		"initialization_ms": _initialization_ms,
		"frame_count": _frame_count,
		"average_frame_ms": average_ms,
		"p99_frame_ms": p99_frame_ms,
		"max_frame_ms": _frame_time_max_ms,
		"frames_over_16_67_ms": _frames_over_budget,
		"collision_checks": _collision_checks,
		"collision_failures": _collision_failures,
		"peak_draw_calls": _peak_draw_calls,
		"peak_primitives": _peak_primitives,
		"peak_video_memory_bytes": _peak_video_memory_bytes,
		"peak_process_ms": _peak_process_ms,
		"peak_physics_process_ms": _peak_physics_process_ms,
		"gpu_time_ms": null,
		"gpu_time_note": "Godot 4.7 n'expose pas le temps GPU par image dans Performance.",
		"budgets_passed": budgets_passed,
	}
	var absolute_report_path: String = ProjectSettings.globalize_path(_report_path)
	DirAccess.make_dir_recursive_absolute(absolute_report_path.get_base_dir())
	var report_file: FileAccess = FileAccess.open(absolute_report_path, FileAccess.WRITE)
	if report_file == null:
		_fail("Impossible d'écrire le rapport de validation.")
		return
	report_file.store_string(JSON.stringify(report, "  "))
	report_file.close()
	print("VALIDATION_COMPLETE ", JSON.stringify(report))
	get_tree().quit(0 if budgets_passed else 2)


func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
