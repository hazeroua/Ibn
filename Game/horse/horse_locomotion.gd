class_name HorseLocomotion
extends RefCounted
## Moteur déterministe des allures de Barq. Il ne dépend ni de la scène ni de la physique.
## Pire cas : 10 minutes de sprint, 36 000 pas physiques, stick changeant à chaque image.

enum Gait { WALK, TROT, CANTER, SPRINT }
const GAIT_NAMES: Array[StringName] = [&"walk", &"trot", &"canter", &"sprint"]

var gait: int = Gait.WALK
var speed: float = 0.0
var endurance: float = 100.0
var yaw: float = 0.0
var last_step_usec: int = 0

var _speed_limits: PackedFloat32Array = PackedFloat32Array()
var _accelerations: PackedFloat32Array = PackedFloat32Array()
var _decelerations: PackedFloat32Array = PackedFloat32Array()
var _energy: PackedFloat32Array = PackedFloat32Array()
var _maximum_endurance: float = 100.0
var _recovery: float = 0.0
var _sprint_minimum: float = 0.0
var _sprint_recovery_gait: int = Gait.CANTER


func _init(settings: Dictionary) -> void:
	var gaits: Dictionary = settings.get("gaits", {}) as Dictionary
	for gait_name: StringName in GAIT_NAMES:
		var entry: Dictionary = gaits.get(String(gait_name), {}) as Dictionary
		_speed_limits.append(float(entry.get("speed_mps", 0.0)))
		_accelerations.append(float(entry.get("acceleration_mps2", 0.0)))
		_decelerations.append(float(entry.get("deceleration_mps2", 0.0)))
		_energy.append(float(entry.get("energy_per_second", 0.0)))
	var endurance_data: Dictionary = settings.get("endurance", {}) as Dictionary
	_maximum_endurance = float(endurance_data.get("maximum", 100.0))
	_recovery = float(endurance_data.get("recovery_per_second", 0.0))
	_sprint_minimum = float(endurance_data.get("sprint_minimum", 0.0))
	var recovery_name: StringName = StringName(endurance_data.get("sprint_recovery_gait", "canter"))
	_sprint_recovery_gait = GAIT_NAMES.find(recovery_name)
	if _sprint_recovery_gait < 0:
		_sprint_recovery_gait = Gait.CANTER
	endurance = _maximum_endurance


func reset(initial_yaw: float = 0.0) -> void:
	gait = Gait.WALK
	speed = 0.0
	endurance = _maximum_endurance
	yaw = wrapf(initial_yaw, -PI, PI)


func update(move: Vector2, sprint_requested: bool, delta: float) -> void:
	if delta <= 0.0:
		return
	var magnitude: float = clampf(move.length(), 0.0, 1.0)
	var requested: int = Gait.WALK
	if magnitude > 0.05:
		if sprint_requested and endurance > _sprint_minimum:
			requested = Gait.SPRINT
		elif magnitude > 0.72:
			requested = Gait.CANTER
		elif magnitude > 0.38:
			requested = Gait.TROT
	if requested == Gait.SPRINT and endurance <= _sprint_minimum:
		requested = _sprint_recovery_gait
	gait = requested
	var target_speed: float = _speed_limits[gait] * magnitude
	var rate: float = _accelerations[gait] if target_speed > speed else _decelerations[gait]
	speed = move_toward(speed, target_speed, rate * delta)
	if gait == Gait.SPRINT and speed > 0.0:
		endurance = maxf(0.0, endurance - _energy[gait] * delta)
	else:
		endurance = minf(_maximum_endurance, endurance + _recovery * delta)
	if magnitude > 0.05:
		yaw = lerp_angle(yaw, atan2(-move.x, -move.y), minf(1.0, 10.0 * delta))


func get_gait_name() -> StringName:
	return GAIT_NAMES[gait]


func get_gait_speed(index: int) -> float:
	return _speed_limits[index]
