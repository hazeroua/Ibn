extends GutTest
## Allures, vitesses, arrêts et réglages : logique du déplacement à partir d'entrées simulées
## (aucune physique, aucun clavier : LocomotionMotor et FootstepTracker seuls).

const FORWARD := Vector2(0.0, -1.0)
const RIGHT := Vector2(1.0, 0.0)
const DT: float = 1.0 / 60.0

var _settings: LocomotionSettings
var _motor: LocomotionMotor


func before_each() -> void:
	_settings = LocomotionSettings.load_file()
	_motor = LocomotionMotor.new(_settings)


func _run(move: Vector2, seconds: float, sprint: bool = false, walk_slow: bool = false, delta: float = DT) -> void:
	var frames: int = int(ceil(seconds / delta))
	for i: int in frames:
		_motor.update(move, sprint, walk_slow, FORWARD, RIGHT, true, delta)


## Fait tourner le moteur et renvoie les manœuvres vues (clé = Maneuver, valeur = nombre de départs).
func _run_collect(move: Vector2, seconds: float, sprint: bool, delta: float = DT) -> Dictionary[int, int]:
	var seen: Dictionary[int, int] = {}
	var serial: int = _motor.maneuver_serial
	var frames: int = int(ceil(seconds / delta))
	for i: int in frames:
		_motor.update(move, sprint, false, FORWARD, RIGHT, true, delta)
		if _motor.maneuver_serial != serial:
			serial = _motor.maneuver_serial
			seen[_motor.maneuver] = seen.get(_motor.maneuver, 0) + 1
	return seen


func test_settings_are_valid_and_complete() -> void:
	assert_eq(_settings.error_count, 0)
	assert_eq(_settings.collision_layer, 2, "le joueur est sur la couche 2")
	assert_eq(_settings.collision_mask, 1 | 4, "le joueur heurte le sol (couche 1) et Barq (couche 3)")
	assert_lt(_settings.gait_speed[LocomotionSettings.Gait.WALK_SLOW], _settings.gait_speed[LocomotionSettings.Gait.WALK])
	assert_lt(_settings.gait_speed[LocomotionSettings.Gait.WALK], _settings.gait_speed[LocomotionSettings.Gait.RUN])


func test_starts_idle_and_still() -> void:
	_run(Vector2.ZERO, 1.0)
	assert_eq(_motor.gait, LocomotionSettings.Gait.IDLE)
	assert_eq(_motor.speed, 0.0)
	assert_eq(_motor.maneuver, LocomotionMotor.Maneuver.NONE)


func test_walk_reaches_walk_speed() -> void:
	_run(FORWARD * -1.0, 3.0)
	assert_eq(_motor.gait, LocomotionSettings.Gait.WALK)
	assert_almost_eq(_motor.speed, _settings.gait_speed[LocomotionSettings.Gait.WALK], 0.001)
	assert_almost_eq(_motor.yaw, 0.0, 0.001, "regard vers -Z quand on pousse vers l'avant")


func test_run_reaches_run_speed() -> void:
	_run(Vector2(0.0, 1.0), 4.0, true)
	assert_eq(_motor.gait, LocomotionSettings.Gait.RUN)
	assert_almost_eq(_motor.speed, _settings.gait_speed[LocomotionSettings.Gait.RUN], 0.001)


func test_walk_slow_button() -> void:
	_run(Vector2(0.0, 1.0), 3.0, false, true)
	assert_eq(_motor.gait, LocomotionSettings.Gait.WALK_SLOW)
	assert_almost_eq(_motor.speed, _settings.gait_speed[LocomotionSettings.Gait.WALK_SLOW], 0.001)


func test_walk_slow_wins_over_sprint() -> void:
	_run(Vector2(0.0, 1.0), 3.0, true, true)
	assert_eq(_motor.gait, LocomotionSettings.Gait.WALK_SLOW)


func test_half_stick_is_walk_slow() -> void:
	_run(Vector2(0.0, 0.5), 3.0)
	assert_eq(_motor.gait, LocomotionSettings.Gait.WALK_SLOW)
	var slow: float = _settings.gait_speed[LocomotionSettings.Gait.WALK_SLOW]
	assert_between(_motor.speed, slow * _settings.analog_min_speed_fraction, slow)


func test_stick_speed_grows_continuously() -> void:
	var previous: float = -1.0
	for strength: float in [0.2, 0.35, 0.5, 0.6, 0.8, 1.0]:
		_motor.reset(0.0)
		_run(Vector2(0.0, strength), 4.0)
		assert_gt(_motor.speed, previous, "vitesse croissante avec le stick à %.2f" % strength)
		previous = _motor.speed
	assert_almost_eq(previous, _settings.gait_speed[LocomotionSettings.Gait.WALK], 0.001)


func test_analog_hysteresis_prevents_gait_flicker() -> void:
	var limit: float = _settings.analog_walk_slow_max
	_run(Vector2(0.0, limit - 0.03), 2.0)
	assert_eq(_motor.gait, LocomotionSettings.Gait.WALK_SLOW)
	var changes: int = 0
	var last: int = _motor.gait
	for i: int in 240:
		var strength: float = limit + 0.03 if i % 40 < 20 else limit - 0.03
		_motor.update(Vector2(0.0, strength), false, false, FORWARD, RIGHT, true, DT)
		if _motor.gait != last:
			changes += 1
			last = _motor.gait
	assert_eq(changes, 0, "le stick qui vibre autour du seuil ne change pas d'allure")


func test_stop_from_run_plays_stop_run_then_idles() -> void:
	_run(Vector2(0.0, 1.0), 4.0, true)
	var seen: Dictionary[int, int] = _run_collect(Vector2.ZERO, 1.5, false)
	assert_eq(seen.get(LocomotionMotor.Maneuver.STOP_RUN, 0), 1)
	assert_eq(_motor.gait, LocomotionSettings.Gait.IDLE)
	assert_eq(_motor.speed, 0.0)
	assert_eq(_motor.maneuver, LocomotionMotor.Maneuver.NONE)


func test_stop_from_walk_plays_stop_walk() -> void:
	_run(Vector2(0.0, 1.0), 3.0)
	var seen: Dictionary[int, int] = _run_collect(Vector2.ZERO, 1.5, false)
	assert_eq(seen.get(LocomotionMotor.Maneuver.STOP_WALK, 0), 1)
	assert_eq(_motor.speed, 0.0)


func test_stop_from_walk_slow_has_no_stop_animation() -> void:
	_run(Vector2(0.0, 1.0), 3.0, false, true)
	var seen: Dictionary[int, int] = _run_collect(Vector2.ZERO, 1.5, false)
	assert_true(seen.is_empty())
	assert_eq(_motor.gait, LocomotionSettings.Gait.IDLE)


func test_worst_case_motor_update_cost() -> void:
	# Pire cas : mise à jour de la logique à chaque image, entrées aléatoires, 100 000 images.
	var generator := RandomNumberGenerator.new()
	generator.seed = 11
	var count: int = 100000
	var sticks := PackedVector2Array()
	sticks.resize(1024)
	for i: int in sticks.size():
		sticks[i] = Vector2(generator.randf_range(-1.0, 1.0), generator.randf_range(-1.0, 1.0))
	var start: int = Time.get_ticks_usec()
	for i: int in count:
		_motor.update(sticks[i & 1023], (i & 64) != 0, (i & 256) != 0, FORWARD, RIGHT, true, DT)
	var elapsed_ms: float = float(Time.get_ticks_usec() - start) / 1000.0
	gut.p("Logique de déplacement : %d images en %.1f ms, soit %.2f µs par image" % [count, elapsed_ms, elapsed_ms * 1000.0 / float(count)])
	PerfCheck.under(self, elapsed_ms / float(count), 0.05, "moins de 50 µs par image")
