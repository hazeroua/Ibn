extends GutTest
## Virages, stabilité dans les pires cas et durées d'image : logique du déplacement à partir d'entrées simulées
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


func test_stop_is_cancelled_when_moving_again() -> void:
	_run(Vector2(0.0, 1.0), 4.0, true)
	var seen: Dictionary[int, int] = _run_collect(Vector2.ZERO, 0.4, false)
	assert_eq(seen.get(LocomotionMotor.Maneuver.STOP_RUN, 0), 1)
	_run(Vector2(0.0, 1.0), 0.5)
	assert_ne(_motor.maneuver, LocomotionMotor.Maneuver.STOP_RUN)
	assert_ne(_motor.gait, LocomotionSettings.Gait.IDLE)


func test_u_turn_plays_turn_180_and_ends_facing_the_new_way() -> void:
	_run(Vector2(0.0, 1.0), 4.0, true)
	var seen: Dictionary[int, int] = _run_collect(Vector2(0.0, -1.0), 2.5, true)
	assert_eq(seen.get(LocomotionMotor.Maneuver.TURN_180, 0), 1)
	assert_almost_eq(absf(angle_difference(_motor.yaw, PI)), 0.0, 0.01)
	assert_almost_eq(_motor.speed, _settings.gait_speed[LocomotionSettings.Gait.RUN], 0.05, "la course reprend après le demi-tour")


func test_turn_180_rotation_never_reverses() -> void:
	_run(Vector2(0.0, 1.0), 4.0, true)
	var previous: float = -1.0
	var serial: int = _motor.maneuver_serial
	var checked: int = 0
	var reversals: int = 0
	for i: int in 150:
		_motor.update(Vector2(0.0, -1.0), true, false, FORWARD, RIGHT, true, DT)
		if _motor.maneuver == LocomotionMotor.Maneuver.TURN_180 and _motor.maneuver_serial != serial:
			previous = absf(angle_difference(_motor.yaw, _motor.turn_target_yaw))
			serial = _motor.maneuver_serial
		elif _motor.maneuver == LocomotionMotor.Maneuver.TURN_180:
			var current: float = absf(angle_difference(_motor.yaw, _motor.turn_target_yaw))
			if current > previous + 0.0001:
				reversals += 1
			previous = current
			checked += 1
	assert_gt(checked, 10)
	assert_eq(reversals, 0, "le demi-tour ne repart jamais en arrière")


func test_right_angle_turns_pick_the_right_side() -> void:
	_run(Vector2(0.0, 1.0), 3.0)
	var right_seen: Dictionary[int, int] = _run_collect(Vector2(1.0, 0.0), 1.5, false)
	assert_eq(right_seen.get(LocomotionMotor.Maneuver.TURN_RIGHT_90, 0), 1)
	assert_almost_eq(angle_difference(_motor.yaw, -PI / 2.0), 0.0, 0.01)
	_motor.reset(0.0)
	_run(Vector2(0.0, 1.0), 3.0)
	var left_seen: Dictionary[int, int] = _run_collect(Vector2(-1.0, 0.0), 1.5, false)
	assert_eq(left_seen.get(LocomotionMotor.Maneuver.TURN_LEFT_90, 0), 1)
	assert_almost_eq(angle_difference(_motor.yaw, PI / 2.0), 0.0, 0.01)


func test_gentle_direction_change_turns_progressively() -> void:
	_run(Vector2(0.0, 1.0), 3.0)
	var direction: Vector2 = Vector2(sin(deg_to_rad(35.0)), cos(deg_to_rad(35.0)))
	var seen: Dictionary[int, int] = _run_collect(direction, 1.5, false)
	assert_true(seen.is_empty(), "35° se prennent en tournant, sans manœuvre marquée")
	assert_almost_eq(angle_difference(_motor.yaw, deg_to_rad(-35.0)), 0.0, 0.01)


func test_turning_is_bounded_by_the_turn_rate() -> void:
	_run(Vector2(0.0, 1.0), 3.0)
	var direction: Vector2 = Vector2(sin(deg_to_rad(40.0)), cos(deg_to_rad(40.0)))
	var limit: float = _settings.gait_turn_rate[LocomotionSettings.Gait.WALK] * DT + 0.0001
	var worst: float = 0.0
	for i: int in 60:
		var before: float = _motor.yaw
		_motor.update(direction, false, false, FORWARD, RIGHT, true, DT)
		worst = maxf(worst, absf(angle_difference(before, _motor.yaw)))
	assert_lte(worst, limit)


func test_worst_case_stick_flipping_every_frame_stays_stable() -> void:
	# Pire cas : le stick va et vient à pleine amplitude à chaque image, à pleine vitesse.
	_run(Vector2(0.0, 1.0), 4.0, true)
	var maneuvers: int = 0
	var invalid_frames: int = 0
	var serial: int = _motor.maneuver_serial
	var run_speed: float = _settings.gait_speed[LocomotionSettings.Gait.RUN]
	for i: int in 600:
		var side: float = 1.0 if i % 2 == 0 else -1.0
		_motor.update(Vector2(side, 0.0), true, false, FORWARD, RIGHT, true, DT)
		if is_nan(_motor.yaw) or is_nan(_motor.speed) or _motor.speed > run_speed + 0.0001 or _motor.speed < 0.0:
			invalid_frames += 1
		if _motor.maneuver_serial != serial:
			serial = _motor.maneuver_serial
			maneuvers += 1
	assert_eq(invalid_frames, 0)
	assert_lt(maneuvers, 4, "le va-et-vient du stick ne déclenche pas de virages en rafale")
	assert_lt(_motor.speed, 0.5, "un stick qui s'annule d'une image à l'autre immobilise le personnage")


func test_worst_case_random_stick_every_frame_stays_finite() -> void:
	var generator := RandomNumberGenerator.new()
	generator.seed = 7
	var run_speed: float = _settings.gait_speed[LocomotionSettings.Gait.RUN]
	var invalid_frames: int = 0
	_run(Vector2(0.0, 1.0), 4.0, true)
	for i: int in 3000:
		var stick := Vector2(generator.randf_range(-1.0, 1.0), generator.randf_range(-1.0, 1.0))
		_motor.update(stick, i % 7 < 4, i % 11 == 0, FORWARD, RIGHT, i % 5 != 0, DT)
		var finite: bool = not (is_nan(_motor.yaw) or is_nan(_motor.speed))
		if not (finite and _motor.speed >= 0.0 and _motor.speed <= run_speed + 0.0001 and absf(_motor.yaw) <= PI + 0.0001):
			invalid_frames += 1
	assert_eq(invalid_frames, 0)


func test_frame_duration_does_not_change_the_outcome() -> void:
	# Images très courtes (2 ms) et très longues (100 ms) : mêmes vitesses et mêmes virages.
	for delta: float in [0.002, 0.016, 0.1]:
		_motor.reset(0.0)
		_run(Vector2(0.0, 1.0), 4.0, true, false, delta)
		assert_almost_eq(_motor.speed, _settings.gait_speed[LocomotionSettings.Gait.RUN], 0.001, "course à %.0f ms" % (delta * 1000.0))
		var seen: Dictionary[int, int] = _run_collect(Vector2(0.0, -1.0), 3.0, true, delta)
		assert_eq(seen.get(LocomotionMotor.Maneuver.TURN_180, 0), 1, "demi-tour à %.0f ms" % (delta * 1000.0))
		assert_almost_eq(absf(angle_difference(_motor.yaw, PI)), 0.0, 0.01, "cap final à %.0f ms" % (delta * 1000.0))


func test_acceleration_is_bounded_per_frame() -> void:
	var limit: float = _settings.gait_acceleration[LocomotionSettings.Gait.WALK] * 0.1 + 0.0001
	var worst: float = 0.0
	for i: int in 30:
		var before: float = _motor.speed
		_motor.update(Vector2(0.0, 1.0), false, false, FORWARD, RIGHT, true, 0.1)
		worst = maxf(worst, _motor.speed - before)
	assert_lte(worst, limit)


func test_zero_or_negative_delta_changes_nothing() -> void:
	_run(Vector2(0.0, 1.0), 2.0)
	var speed: float = _motor.speed
	var yaw: float = _motor.yaw
	_motor.update(Vector2(1.0, 0.0), true, false, FORWARD, RIGHT, true, 0.0)
	_motor.update(Vector2(1.0, 0.0), true, false, FORWARD, RIGHT, true, -0.5)
	assert_eq(_motor.speed, speed)
	assert_eq(_motor.yaw, yaw)


func test_movement_follows_the_camera_axes() -> void:
	# Caméra tournée de 90° : « avant » devient -X du monde.
	var camera_right := Vector2(0.0, -1.0)
	var camera_forward := Vector2(-1.0, 0.0)
	for i: int in 180:
		_motor.update(Vector2(0.0, 1.0), false, false, camera_forward, camera_right, true, DT)
	assert_almost_eq(_motor.forward_xz().x, -1.0, 0.01)
	assert_almost_eq(_motor.forward_xz().y, 0.0, 0.01)


func test_airborne_motor_has_reduced_control() -> void:
	_run(Vector2(0.0, 1.0), 3.0)
	var speed: float = _motor.speed
	for i: int in 30:
		_motor.update(Vector2.ZERO, false, false, FORWARD, RIGHT, false, DT)
	assert_gt(_motor.speed, speed * 0.7, "en l'air, le personnage ralentit peu")


func test_no_turn_starts_in_the_air() -> void:
	_run(Vector2(0.0, 1.0), 3.0)
	var serial: int = _motor.maneuver_serial
	for i: int in 60:
		_motor.update(Vector2(0.0, -1.0), false, false, FORWARD, RIGHT, false, DT)
	assert_eq(_motor.maneuver_serial, serial)
