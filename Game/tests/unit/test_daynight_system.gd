extends GutTest
## Autoload DayNight : heure, vitesse, signal, soleil et lune, ciel construit. Le script est
## instancié directement (l'autoload est déclaré par l'intégration).

const SYSTEM_SCRIPT: String = "res://world/sky/day_night.gd"

var _system: DayNightSystem = null
var _rig: Node = null


func before_each() -> void:
	_system = load(SYSTEM_SCRIPT).new()
	add_child_autofree(_system)
	_system.time_scale = 0.0
	_rig = _system.build_environment()
	add_child_autofree(_rig)


func test_set_time_wraps_and_signals() -> void:
	watch_signals(_system)
	_system.set_time(26.5)
	assert_almost_eq(_system.time_of_day, 2.5, 0.0001)
	_system.set_time(-1.0)
	assert_almost_eq(_system.time_of_day, 23.0, 0.0001)
	_system.time_of_day = 100.0 * 24.0 + 7.0
	assert_almost_eq(_system.time_of_day, 7.0, 0.001)
	assert_signal_emit_count(_system, "time_changed", 3)
	assert_signal_emitted_with_parameters(_system, "time_changed", [_system.time_of_day])


func test_time_scale_advances_time_and_enables_process() -> void:
	_system.set_time(10.0)
	_system.time_scale = 0.0
	assert_false(_system.is_processing())
	_system.time_scale = 1.0
	assert_true(_system.is_processing())
	_system._process(0.5)
	assert_almost_eq(_system.time_of_day, 10.5, 0.0001)
	_system.time_scale = 2.0
	_system.set_time(23.75)
	_system._process(0.25)
	assert_almost_eq(_system.time_of_day, 0.25, 0.0001)


func test_small_advances_are_throttled() -> void:
	_system.set_time(10.0)
	_system.time_scale = 1.0
	watch_signals(_system)
	_system._process(0.001)
	assert_signal_not_emitted(_system, "time_changed")
	_system._process(0.01)
	assert_signal_emit_count(_system, "time_changed", 1)


func test_rig_contains_environment_sun_and_moon() -> void:
	assert_not_null(_rig.get_node_or_null("Environment"))
	assert_not_null(_rig.get_node_or_null("Sun"))
	assert_not_null(_rig.get_node_or_null("Moon"))
	var world_environment: WorldEnvironment = _rig.get_node("Environment")
	assert_eq(world_environment.environment.tonemap_mode, Environment.TONE_MAPPER_AGX)
	assert_not_null(world_environment.environment.sky)


func test_sun_and_moon_follow_the_clock() -> void:
	var sun: DirectionalLight3D = _rig.get_node("Sun")
	var moon: DirectionalLight3D = _rig.get_node("Moon")
	_system.set_time(12.0)
	assert_true(sun.visible)
	assert_gt(sun.light_energy, 1.0)
	assert_false(moon.visible)
	assert_lt(-sun.global_transform.basis.z.y, -0.5, "le soleil de midi éclaire vers le bas")
	_system.set_time(0.0)
	assert_false(sun.visible)
	assert_true(moon.visible)
	assert_gt(moon.light_energy, 0.0)
	assert_lt(-moon.global_transform.basis.z.y, -0.5, "la lune de minuit éclaire vers le bas")


func test_sun_direction_crosses_the_horizon_at_sunrise_and_sunset() -> void:
	assert_almost_eq(_system.get_sun_direction(6.25).y, 0.0, 0.001)
	assert_almost_eq(_system.get_sun_direction(18.75).y, 0.0, 0.001)
	assert_gt(_system.get_sun_direction(12.5).y, 0.9)
	assert_lt(_system.get_sun_direction(0.0).y, -0.9)
	for hour: int in 24:
		assert_almost_eq(_system.get_sun_direction(float(hour)).length(), 1.0, 0.0001)


func test_sun_direction_is_continuous() -> void:
	var previous: Vector3 = _system.get_sun_direction(0.0)
	var worst: float = 0.0
	for minute: int in range(1, 1441):
		var current: Vector3 = _system.get_sun_direction(float(minute) / 60.0)
		worst = maxf(worst, current.distance_to(previous))
		previous = current
	assert_lt(worst, 0.01, "saut du soleil entre deux minutes")


func test_rig_freed_clears_references() -> void:
	var rig: Node = _system.build_environment()
	add_child(rig)
	remove_child(rig)
	rig.free()
	_system.set_time(8.0)
	assert_almost_eq(_system.time_of_day, 8.0, 0.0001)


func test_exposure_follows_curve_without_jump() -> void:
	var environment: Environment = (_rig.get_node("Environment") as WorldEnvironment).environment
	var previous: float = -1.0
	var worst: float = 0.0
	for minute: int in range(0, 1441, 5):
		_system.set_time(float(minute) / 60.0)
		if previous >= 0.0:
			worst = maxf(worst, absf(environment.tonemap_exposure - previous))
		previous = environment.tonemap_exposure
	assert_lt(worst, 0.05, "saut d'exposition sur 5 minutes")
