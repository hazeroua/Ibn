extends GutTest
## Autoload Wind : uniformes globaux, sable, brume, son ; pire cas (force maximale) mesuré.

const FRAMES: int = 600
const HUNDRED_HOURS: float = 360000.0
const FRAME: float = 1.0 / 60.0
## Budget de calcul du vent par image sur la machine de développement (hors rendu GPU), en microsecondes.
const BUDGET_USEC_PER_FRAME: float = 300.0

var _wind: WindSystem = null


func before_each() -> void:
	_wind = WindSystem.new()
	_wind.configure(WindSettings.load_default())
	add_child_autofree(_wind)


func test_globals_are_declared_and_published() -> void:
	var names: Array[StringName] = RenderingServer.global_shader_parameter_get_list()
	for uniform: StringName in [&"wind_direction", &"wind_strength", &"wind_time"]:
		assert_true(names.has(uniform), "uniforme global %s" % uniform)
	_wind.set_base_strength(1.0)
	assert_eq(_wind.strength, 1.0)
	assert_almost_eq(_wind.direction.length(), 1.0, 0.0001)
	# Le moteur sans rendu (tests sur machine sans GPU) ne relit pas les uniformes : on ne compare que s'il les rend.
	var published: Variant = RenderingServer.global_shader_parameter_get(&"wind_strength")
	if published != null:
		assert_eq(published, 1.0)


func test_declaring_twice_is_harmless() -> void:
	var second := WindSystem.new()
	second.configure(WindSettings.load_default())
	add_child_autofree(second)
	assert_true(RenderingServer.global_shader_parameter_get_list().has(&"wind_time"))


func test_sand_follows_strength() -> void:
	_wind.set_base_strength(0.0)
	_wind.set_model_time(0.0)
	_wind.get_sand().apply_wind(Vector2.RIGHT, 0.0)
	assert_false(_wind.get_sand().emitting, "pas de sable par vent calme")
	_wind.set_base_strength(1.0)
	assert_true(_wind.get_sand().emitting)
	assert_eq(_wind.get_sand().amount_ratio, 1.0, "force maximale : pleine émission")
	assert_eq(_wind.get_sand().amount, WindSettings.load_default().sand_max_particles)


func test_audio_is_louder_in_a_storm() -> void:
	_wind.set_base_strength(0.0)
	_wind.get_audio().apply_wind(0.0, 0.0)
	var calm: float = _wind.get_audio().get_rumble_player().volume_db
	_wind.set_base_strength(1.0)
	var storm: float = _wind.get_audio().get_rumble_player().volume_db
	assert_gt(storm, calm)
	assert_true(_wind.get_audio().get_rumble_player().playing)
	assert_true(_wind.get_audio().get_gust_player().playing)
	assert_ne(AudioServer.get_bus_index(&"Wind"), -1)


func test_haze_mesh_is_a_closed_ring() -> void:
	var haze: WindHaze = _wind.get_haze()
	var settings: WindSettings = WindSettings.load_default()
	var arrays: Array = haze.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	assert_eq(vertices.size(), (settings.haze_segments + 1) * (settings.haze_rings + 1))
	assert_eq((arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size(), settings.haze_segments * settings.haze_rings * 6)
	assert_true(vertices[0].is_equal_approx(vertices[settings.haze_segments]), "la dernière colonne reprend la première")


func test_follows_camera() -> void:
	var camera := Camera3D.new()
	add_child_autofree(camera)
	camera.global_position = Vector3(123.0, 4.0, -77.0)
	camera.make_current()
	_wind._process(FRAME)
	assert_eq(_wind.get_haze().global_position, camera.global_position)


func test_worst_case_has_no_allocation_and_fits_budget() -> void:
	_wind.set_base_strength(1.0)
	_wind.set_model_time(HUNDRED_HOURS)
	for i: int in 120:
		_wind._process(FRAME)
	var nodes_before: int = get_tree().get_node_count()
	var objects_before: float = Performance.get_monitor(Performance.OBJECT_COUNT)
	var started: int = Time.get_ticks_usec()
	for i: int in FRAMES:
		_wind._process(FRAME)
	var per_frame: float = float(Time.get_ticks_usec() - started) / float(FRAMES)
	var objects_after: float = Performance.get_monitor(Performance.OBJECT_COUNT)
	var nodes_after: int = get_tree().get_node_count()
	gut.p("Vent, force maximale, 100 h de jeu : %.1f us par image (budget %.0f us)" % [per_frame, BUDGET_USEC_PER_FRAME])
	assert_eq(nodes_after, nodes_before, "aucun nœud créé par image")
	assert_eq(objects_after, objects_before, "aucun objet créé par image")
	PerfCheck.under(self, per_frame, BUDGET_USEC_PER_FRAME)
