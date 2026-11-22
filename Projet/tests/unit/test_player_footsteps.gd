extends GutTest
## Cadence des pas : logique du déplacement à partir d'entrées simulées
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


func test_footsteps_follow_the_stride() -> void:
	var tracker := FootstepTracker.new(_settings)
	var stride: float = _settings.gait_stride_length[LocomotionSettings.Gait.WALK]
	var first: float = stride * _settings.first_step_fraction
	var steps: int = 0
	var feet: Array[int] = []
	for i: int in 1005:
		var count: int = tracker.advance(0.01, stride)
		for j: int in count:
			feet.append(tracker.take_foot())
		steps += count
	var expected: int = 1 + int(floor((10.05 - first) / stride))
	assert_eq(steps, expected)
	for i: int in feet.size():
		assert_eq(feet[i], i % 2, "les pieds alternent, gauche d'abord")


func test_footsteps_change_stride_with_the_gait() -> void:
	var tracker := FootstepTracker.new(_settings)
	var run_stride: float = _settings.gait_stride_length[LocomotionSettings.Gait.RUN]
	var slow_stride: float = _settings.gait_stride_length[LocomotionSettings.Gait.WALK_SLOW]
	var run_steps: int = 0
	for i: int in 200:
		run_steps += tracker.advance(0.05, run_stride)
	var slow_steps: int = 0
	for i: int in 200:
		slow_steps += tracker.advance(0.05, slow_stride)
	assert_gt(slow_steps, run_steps * 2, "la foulée courte donne plus de pas pour la même distance")


func test_footstep_burst_is_bounded_and_teleport_emits_nothing() -> void:
	var tracker := FootstepTracker.new(_settings)
	var stride: float = _settings.gait_stride_length[LocomotionSettings.Gait.WALK_SLOW]
	var burst: int = tracker.advance(_settings.teleport_distance, stride)
	assert_lte(burst, int(ceil(_settings.teleport_distance / stride)) + 1)
	assert_eq(tracker.advance(_settings.teleport_distance + 1.0, stride), 0)
	assert_eq(tracker.advance(0.0, stride), 0)
	assert_eq(tracker.advance(-1.0, stride), 0)


func test_final_step_when_stopping() -> void:
	var stride: float = _settings.gait_stride_length[LocomotionSettings.Gait.WALK]
	var tracker := FootstepTracker.new(_settings)
	tracker.advance(0.1, stride)
	assert_false(tracker.stop(stride), "trop peu parcouru depuis le dernier pas")
	tracker.advance(stride * _settings.stop_step_min_fraction + 0.01, stride * 3.0)
	assert_true(tracker.stop(stride), "assez parcouru : le pied se pose à l'arrêt")
	assert_false(tracker.is_moving())
	assert_false(tracker.stop(stride), "rien à poser quand on est déjà à l'arrêt")
