extends Node3D
## Scène de test du socle : terrain Terrain3D de 4 × 4 km construit depuis
## data/terrain_test/terrain_test.json. En jeu, caméra libre ; avec la sonde de
## mesure, parcours automatique circulaire à grande vitesse et contrôle des
## collisions une fois par seconde.

const DATA_PATH: String = "res://data/terrain_test/terrain_test.json"
const LOG_CATEGORY: String = "terrain_test"
const COLLISION_CHECK_INTERVAL_SECONDS: float = 1.0
const COLLISION_RAY_LENGTH_METERS: float = 1000.0

var _terrain: Terrain3D
var _camera: FreeCamera
var _probe: PerformanceProbe
var _map_size_meters: float = 4096.0
var _route_radius_meters: float = 1750.0
var _route_speed_meters_per_second: float = 70.0
var _route_height_meters: float = 12.0
var _route_look_ahead_meters: float = 120.0
var _route_elapsed_seconds: float = 0.0
var _collision_timer_seconds: float = 0.0
var _collision_checks: int = 0
var _collision_failures: int = 0
var _ray_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()


func _ready() -> void:
	var start_usec: int = Time.get_ticks_usec()
	var errors: PackedStringArray = PackedStringArray()
	var data: Dictionary = JsonData.load_dictionary(DATA_PATH)
	var terrain_data: Dictionary = JsonData.read_dictionary(data, "terrain", errors, "terrain_test.json")
	var environment_data: Dictionary = JsonData.read_dictionary(data, "environment", errors, "terrain_test.json")
	var camera_data: Dictionary = JsonData.read_dictionary(data, "camera", errors, "terrain_test.json")
	var route_data: Dictionary = JsonData.read_dictionary(data, "measure_route", errors, "terrain_test.json")
	var help_text: String = JsonData.read_string(data, "help_text", errors, "terrain_test.json")
	if errors.is_empty():
		_create_environment(environment_data, errors)
		_create_terrain(terrain_data, errors)
	if errors.is_empty():
		_create_camera(camera_data, errors)
		_read_route(route_data, errors)
	if not errors.is_empty():
		for message: String in errors:
			GameLog.error(LOG_CATEGORY, message)
		get_tree().quit(PerformanceProbe.EXIT_FAILURE)
		return

	_probe = get_tree().get_first_node_in_group(PerformanceProbe.GROUP) as PerformanceProbe
	if _probe != null:
		_camera.set_process(false)
		_camera.set_process_unhandled_input(false)
		_ray_query.collide_with_areas = false
		_move_along_route()
	else:
		_create_help(help_text)
		set_process(false)
		set_physics_process(false)
	(
		GameLog
		. info(
			LOG_CATEGORY,
			(
				"Terrain3D %s : %.0f × %.0f m construit en %.0f ms (%s)."
				% [
					_terrain.get_version(),
					_map_size_meters,
					_map_size_meters,
					float(Time.get_ticks_usec() - start_usec) / 1000.0,
					"parcours automatique" if _probe != null else "caméra libre",
				]
			)
		)
	)


func _process(delta: float) -> void:
	if not _probe.is_measuring():
		return
	_route_elapsed_seconds += delta
	_move_along_route()


func _physics_process(delta: float) -> void:
	if not _probe.is_measuring():
		return
	_collision_timer_seconds += delta
	if _collision_timer_seconds < COLLISION_CHECK_INTERVAL_SECONDS:
		return
	_collision_timer_seconds -= COLLISION_CHECK_INTERVAL_SECONDS
	_ray_query.from = _camera.global_position
	_ray_query.to = _camera.global_position + Vector3.DOWN * COLLISION_RAY_LENGTH_METERS
	_collision_checks += 1
	if get_world_3d().direct_space_state.intersect_ray(_ray_query).is_empty():
		_collision_failures += 1
		GameLog.warning(LOG_CATEGORY, "Collision absente sous %s." % str(_camera.global_position))
	_probe.report_metric("collision_checks", _collision_checks)
	_probe.report_metric("collision_failures", _collision_failures)


func _create_environment(data: Dictionary, errors: PackedStringArray) -> void:
	var context: String = "terrain_test.json › environment"
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = JsonData.read_color(data, "sky_color", errors, context)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = JsonData.read_color(data, "ambient_color", errors, context)
	environment.ambient_light_energy = JsonData.read_number(data, "ambient_energy", errors, context)
	var world_environment: WorldEnvironment = WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)

	var sun_data: Dictionary = JsonData.read_dictionary(data, "sun", errors, context)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = JsonData.read_vector3(sun_data, "rotation_degrees", errors, context + " › sun")
	sun.light_energy = JsonData.read_number(sun_data, "energy", errors, context + " › sun")
	sun.shadow_enabled = true
	sun.shadow_bias = JsonData.read_number(sun_data, "shadow_bias", errors, context + " › sun")
	sun.shadow_normal_bias = JsonData.read_number(sun_data, "shadow_normal_bias", errors, context + " › sun")
	add_child(sun)


func _create_terrain(data: Dictionary, errors: PackedStringArray) -> void:
	var context: String = "terrain_test.json › terrain"
	if not ClassDB.class_exists(&"Terrain3D"):
		errors.append("Terrain3D n'est pas chargé (addons/terrain_3d absent ?).")
		return
	_map_size_meters = JsonData.read_number(data, "map_size_meters", errors, context)
	var spacing: float = JsonData.read_number(data, "vertex_spacing_meters", errors, context)
	var region_size: int = int(JsonData.read_number(data, "region_size", errors, context))
	var height_meters: float = JsonData.read_number(data, "height_meters", errors, context)
	var noise: TerrainHeightmap.NoiseSettings = TerrainHeightmap.NoiseSettings.from_dictionary(
		JsonData.read_dictionary(data, "noise", errors, context), errors, context + " › noise"
	)
	var collision_data: Dictionary = JsonData.read_dictionary(data, "collision", errors, context)
	var collision_radius: int = int(JsonData.read_number(collision_data, "radius", errors, context + " › collision"))
	var collision_shape_size: int = int(JsonData.read_number(collision_data, "shape_size", errors, context + " › collision"))
	var ground_color: Color = JsonData.read_color(data, "ground_color", errors, context)
	var ground_roughness: float = JsonData.read_number(data, "ground_roughness", errors, context)
	var uv_scale: float = JsonData.read_number(data, "uv_scale", errors, context)
	if spacing <= 0.0 or _map_size_meters <= 0.0 or not is_equal_approx(fmod(_map_size_meters, spacing), 0.0):
		errors.append(context + " : la taille de la carte doit être un multiple positif de l'espacement.")
	if region_size not in [64, 128, 256, 512, 1024, 2048]:
		errors.append(context + " : region_size doit être une puissance de 2 entre 64 et 2048.")
	if not errors.is_empty():
		return

	_terrain = Terrain3D.new()
	_terrain.name = "Terrain3D"
	# Les textures sont créées en mémoire : rien à libérer côté éditeur.
	_terrain.free_editor_textures = false
	_terrain.region_size = region_size as Terrain3D.RegionSize
	_terrain.vertex_spacing = spacing
	add_child(_terrain)
	_terrain.material.world_background = Terrain3DMaterial.NONE
	_terrain.material.auto_shader_enabled = false
	_terrain.assets.set_texture_asset(0, _create_ground_texture(ground_color, ground_roughness, uv_scale))

	var size_pixels: int = int(_map_size_meters / spacing)
	var heightmap: Image = TerrainHeightmap.generate(size_pixels, spacing, noise)
	var origin: Vector3 = Vector3(-_map_size_meters * 0.5, 0.0, -_map_size_meters * 0.5)
	_terrain.data.import_images([heightmap, null, null], origin, 0.0, height_meters)
	_terrain.collision.mode = Terrain3DCollision.DYNAMIC_GAME
	_terrain.collision.radius = collision_radius
	_terrain.collision.shape_size = collision_shape_size
	_terrain.collision.build()


func _create_ground_texture(color: Color, roughness: float, uv_scale: float) -> Terrain3DTextureAsset:
	# Texture unie en attendant l'identité visuelle (#64 et #66) : couleur RGB,
	# hauteur dans l'alpha de l'albédo, rugosité dans l'alpha de la normale.
	var albedo_image: Image = Image.create_empty(256, 256, true, Image.FORMAT_RGBA8)
	albedo_image.fill(Color(color, 0.5))
	albedo_image.generate_mipmaps()
	var normal_image: Image = Image.create_empty(256, 256, true, Image.FORMAT_RGBA8)
	normal_image.fill(Color(0.5, 0.5, 1.0, roughness))
	normal_image.generate_mipmaps()
	var texture_asset: Terrain3DTextureAsset = Terrain3DTextureAsset.new()
	texture_asset.name = "Sol de test"
	texture_asset.albedo_texture = ImageTexture.create_from_image(albedo_image)
	texture_asset.normal_texture = ImageTexture.create_from_image(normal_image)
	texture_asset.uv_scale = uv_scale
	return texture_asset


func _create_camera(data: Dictionary, errors: PackedStringArray) -> void:
	var context: String = "terrain_test.json › camera"
	_camera = FreeCamera.new()
	_camera.name = "FreeCamera"
	_camera.far = JsonData.read_number(data, "far", errors, context)
	_camera.terrain_data = _terrain.data
	_camera.map_half_extent = _map_size_meters * 0.5
	_camera.configure(JsonData.read_dictionary(data, "free", errors, context), errors, context + " › free")
	add_child(_camera)
	_camera.current = true
	var spawn: Vector3 = JsonData.read_vector3(data, "spawn", errors, context)
	var spawn_height: float = JsonData.read_number(data, "spawn_height_above_ground", errors, context)
	var look_target: Vector3 = JsonData.read_vector3(data, "look_at", errors, context)
	_camera.global_position = Vector3(spawn.x, _terrain.data.get_height(spawn) + spawn_height, spawn.z)
	look_target.y = _terrain.data.get_height(look_target) + spawn_height * 0.5
	_camera.look_toward(look_target)


func _read_route(data: Dictionary, errors: PackedStringArray) -> void:
	var context: String = "terrain_test.json › measure_route"
	_route_radius_meters = JsonData.read_number(data, "radius_meters", errors, context)
	_route_speed_meters_per_second = JsonData.read_number(data, "speed_meters_per_second", errors, context)
	_route_height_meters = JsonData.read_number(data, "height_above_ground_meters", errors, context)
	_route_look_ahead_meters = JsonData.read_number(data, "look_ahead_meters", errors, context)
	if _route_radius_meters <= 0.0 or _route_radius_meters >= _map_size_meters * 0.5:
		errors.append(context + " : le rayon doit rester à l'intérieur de la carte.")


func _move_along_route() -> void:
	var angle: float = _route_elapsed_seconds * _route_speed_meters_per_second / _route_radius_meters
	var ground_position: Vector3 = Vector3(cos(angle), 0.0, sin(angle)) * _route_radius_meters
	_camera.global_position = ground_position + Vector3.UP * (_terrain.data.get_height(ground_position) + _route_height_meters)
	var look_target: Vector3 = ground_position + Vector3(-sin(angle), 0.0, cos(angle)) * _route_look_ahead_meters
	look_target.y = _terrain.data.get_height(look_target) + _route_height_meters * 0.25
	_camera.look_toward(look_target)


func _create_help(text: String) -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = "Help"
	var label: Label = Label.new()
	label.text = text
	label.add_theme_color_override(&"font_color", Color(1.0, 1.0, 1.0, 0.85))
	label.add_theme_color_override(&"font_shadow_color", Color(0.0, 0.0, 0.0, 0.6))
	label.add_theme_constant_override(&"shadow_offset_x", 1)
	label.add_theme_constant_override(&"shadow_offset_y", 1)
	label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 24)
	label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	layer.add_child(label)
	add_child(layer)
