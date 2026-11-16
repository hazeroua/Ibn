extends GutTest
## Tests MVP3 : allures, endurance, relief dangereux, traces bornées et pire cas de sprint.

const SETTINGS_PATH: String = "res://data/horse/horse.json"
const SPRINT_SECONDS: float = 600.0
const DT: float = 1.0 / 60.0


func _settings() -> Dictionary:
	return JsonData.load_dictionary(SETTINGS_PATH)


func test_four_gaits_are_data_driven_and_ordered() -> void:
	var motor := HorseLocomotion.new(_settings())
	assert_eq(motor.GAIT_NAMES.size(), 4)
	motor.update(Vector2(0.2, 0.0), false, 1.0)
	assert_eq(motor.get_gait_name(), &"walk")
	motor.update(Vector2(0.6, 0.0), false, 1.0)
	assert_eq(motor.get_gait_name(), &"trot")
	motor.update(Vector2(0.8, 0.0), false, 1.0)
	assert_eq(motor.get_gait_name(), &"canter")
	motor.update(Vector2(1.0, 0.0), true, 1.0)
	assert_eq(motor.get_gait_name(), &"sprint")


func test_sprint_endurance_depletes_and_recovers_without_nan() -> void:
	var motor := HorseLocomotion.new(_settings())
	var frames: int = int(SPRINT_SECONDS / DT)
	var worst_speed: float = 0.0
	var invalid: int = 0
	var started: int = Time.get_ticks_usec()
	for index: int in frames:
		motor.update(Vector2(0.0, 1.0), true, DT)
		worst_speed = maxf(worst_speed, motor.speed)
		var invalid_state: bool = is_nan(motor.speed) or is_nan(motor.endurance)
		invalid_state = invalid_state or motor.endurance < 0.0
		invalid_state = invalid_state or motor.endurance > 100.0
		if invalid_state:
			invalid += 1
	var elapsed_ms: float = float(Time.get_ticks_usec() - started) / 1000.0
	gut.p(
		(
			"Pire cas Barq : sprint %.0f s, %d images, %.3f ms, vitesse max %.2f m/s, endurance %.2f"
			% [SPRINT_SECONDS, frames, elapsed_ms, worst_speed, motor.endurance]
		)
	)
	assert_eq(invalid, 0)
	assert_lte(motor.endurance, 100.0)
	assert_gt(motor.endurance, 0.0)


func test_endurance_recovers_at_walk() -> void:
	var motor := HorseLocomotion.new(_settings())
	motor.endurance = 10.0
	for index: int in 30:
		motor.update(Vector2(0.2, 0.0), false, 1.0)
	assert_gt(motor.endurance, 10.0)


func test_trace_pool_is_bounded_and_sand_only() -> void:
	var traces := HorseTraces.new()
	traces.configure(_settings())
	for index: int in 512:
		traces.place(Vector3(float(index), 0.0, 0.0), 0.0, &"sable")
	assert_eq(traces.active_count(), 128)
	assert_false(traces.place(Vector3.ZERO, 0.0, &"pierre"))
	traces.free()


func test_gait_speed_data_is_positive() -> void:
	var motor := HorseLocomotion.new(_settings())
	for gait: int in motor.GAIT_NAMES.size():
		assert_gt(motor.get_gait_speed(gait), 0.0)
