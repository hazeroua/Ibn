class_name LocomotionMotor
extends RefCounted
## Logique de déplacement du personnage joueur, indépendante de la physique et du rendu.
##
## À chaque image physique, update() transforme les entrées (direction dans le repère de la
## caméra, course, marche lente) en allure, vitesse voulue le long du regard et orientation.
## Il décide aussi des manœuvres marquées : arrêts (stop_walk, stop_run), quarts de tour et
## demi-tour. Aucune allocation : uniquement des nombres et des vecteurs.
##
## Stabilité dans le pire cas :
## - stick qui va et vient à chaque image : l'entrée est lissée (moyenne exponentielle
##   indépendante de la durée d'image), le va-et-vient s'annule et le personnage s'arrête ;
## - pendant un virage marqué, le sens de rotation est verrouillé : jamais de tremblement ;
## - images de 2 ms à 100 ms : accélérations et rotations bornées par (taux × durée), sans
##   dépassement de la cible.

enum Maneuver { NONE, STOP_WALK, STOP_RUN, TURN_LEFT_90, TURN_RIGHT_90, TURN_180 }

const GAIT_IDLE: int = LocomotionSettings.Gait.IDLE
const GAIT_WALK_SLOW: int = LocomotionSettings.Gait.WALK_SLOW
const GAIT_WALK: int = LocomotionSettings.Gait.WALK
const GAIT_RUN: int = LocomotionSettings.Gait.RUN
## Près de 180°, le côté de la cible est ambigu : on garde le sens verrouillé du virage (radians).
const HALF_TURN_AMBIGUITY: float = 0.001

## Allure actuelle (LocomotionSettings.Gait).
var gait: int = GAIT_IDLE
## Dernière allure en mouvement : foulée et décélération quand l'allure revient à idle.
var motion_gait: int = GAIT_WALK
## Vitesse horizontale voulue le long du regard (m/s).
var speed: float = 0.0
## Orientation du personnage (radians autour de +Y ; 0 = regard vers -Z).
var yaw: float = 0.0
## Orientation voulue, valable quand has_direction est vrai.
var desired_yaw: float = 0.0
## Vrai quand l'entrée lissée dépasse le seuil de déplacement.
var has_direction: bool = false
## Manœuvre en cours (Maneuver) et son avancement.
var maneuver: int = Maneuver.NONE
var maneuver_elapsed: float = 0.0
var maneuver_duration: float = 0.0
## Incrémenté à chaque nouvelle manœuvre (relance l'animation même si elle est identique).
var maneuver_serial: int = 0

var _settings: LocomotionSettings
var _smoothed: Vector2 = Vector2.ZERO
var _magnitude: float = 0.0
var _idle_timer: float = 0.0
var _release_speed: float = 0.0
var _had_direction: bool = false
var _cooldown: float = 0.0
var _turn_sign: float = 1.0
var _turn_rate: float = 0.0
var _turn_target_yaw: float = 0.0
var _turn_speed_factor: float = 1.0
var _stop_deceleration: float = 0.0


func _init(settings: LocomotionSettings, initial_yaw: float = 0.0) -> void:
	_settings = settings
	reset(initial_yaw)


## Remet le personnage à l'arrêt, tourné vers initial_yaw.
func reset(initial_yaw: float) -> void:
	gait = GAIT_IDLE
	motion_gait = GAIT_WALK
	speed = 0.0
	yaw = wrapf(initial_yaw, -PI, PI)
	desired_yaw = yaw
	has_direction = false
	maneuver = Maneuver.NONE
	maneuver_elapsed = 0.0
	maneuver_duration = 0.0
	_smoothed = Vector2.ZERO
	_magnitude = 0.0
	_idle_timer = 0.0
	_release_speed = 0.0
	_had_direction = false
	_cooldown = 0.0


## Vrai pendant un quart de tour ou un demi-tour.
func is_turning() -> bool:
	return maneuver == Maneuver.TURN_LEFT_90 or maneuver == Maneuver.TURN_RIGHT_90 or maneuver == Maneuver.TURN_180


## Vrai pendant un arrêt marqué.
func is_stopping() -> bool:
	return maneuver == Maneuver.STOP_WALK or maneuver == Maneuver.STOP_RUN


## Direction du regard dans le plan horizontal (x, z du monde).
func forward_xz() -> Vector2:
	return Vector2(-sin(yaw), -cos(yaw))


## Avance la logique d'une image.
## move : entrée (x à droite, y en avant, longueur ≤ 1) ; view_forward et view_right : axes
## horizontaux normalisés de la caméra (x, z du monde) ; grounded : appui au sol ou sur une marche.
func update(move: Vector2, sprint: bool, walk_slow: bool, view_forward: Vector2, view_right: Vector2, grounded: bool, delta: float) -> void:
	if not (delta > 0.0):
		return
	_smooth_input(move.limit_length(1.0), delta)
	has_direction = _magnitude >= _settings.move_threshold
	if _had_direction and not has_direction:
		_release_speed = speed
	_had_direction = has_direction
	if has_direction:
		var world: Vector2 = view_right * _smoothed.x + view_forward * _smoothed.y
		desired_yaw = atan2(-world.x, -world.y)
		_idle_timer = 0.0
	else:
		_idle_timer += delta
	_update_gait(sprint, walk_slow)
	_update_maneuver(grounded, delta)
	_update_rotation(grounded, delta)
	_update_speed(walk_slow, grounded, delta)


func _smooth_input(move: Vector2, delta: float) -> void:
	if _settings.input_smoothing_time > 0.0:
		_smoothed += (move - _smoothed) * (1.0 - exp(-delta / _settings.input_smoothing_time))
	else:
		_smoothed = move
	_magnitude = minf(_smoothed.length(), 1.0)


func _update_gait(sprint: bool, walk_slow: bool) -> void:
	var next: int = gait
	if not has_direction:
		if _idle_timer >= _settings.idle_confirm_time:
			next = GAIT_IDLE
	elif walk_slow:
		next = GAIT_WALK_SLOW
	elif sprint:
		next = GAIT_RUN
	else:
		var limit: float = _settings.analog_walk_slow_max
		if gait == GAIT_WALK_SLOW:
			limit += _settings.analog_hysteresis
		elif gait == GAIT_WALK:
			limit -= _settings.analog_hysteresis
		next = GAIT_WALK_SLOW if _magnitude <= limit else GAIT_WALK
	if next == gait:
		return
	var previous: int = gait
	gait = next
	if next != GAIT_IDLE:
		motion_gait = next
		if is_stopping():
			maneuver = Maneuver.NONE
	else:
		_begin_stop(previous)


func _begin_stop(previous: int) -> void:
	if is_turning():
		return
	if previous != GAIT_WALK and previous != GAIT_RUN:
		return
	# La vitesse au moment du relâchement compte : le lissage de l'entrée retarde la décision d'arrêt.
	if maxf(speed, _release_speed) < _settings.stop_min_speed_fraction * _settings.gait_speed[previous]:
		return
	maneuver = Maneuver.STOP_RUN if previous == GAIT_RUN else Maneuver.STOP_WALK
	maneuver_elapsed = 0.0
	maneuver_duration = clampf(speed / _settings.gait_deceleration[previous], _settings.stop_min_duration, _settings.stop_max_duration)
	_stop_deceleration = speed / maneuver_duration
	maneuver_serial += 1


func _update_maneuver(grounded: bool, delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	if maneuver != Maneuver.NONE:
		maneuver_elapsed += delta
		if maneuver_elapsed >= maneuver_duration:
			if is_turning():
				_cooldown = _settings.turn_cooldown
			maneuver = Maneuver.NONE
	if maneuver != Maneuver.NONE or not has_direction or not grounded or _cooldown > 0.0:
		return
	var diff: float = angle_difference(yaw, desired_yaw)
	var abs_diff: float = absf(diff)
	if abs_diff >= _settings.turn_180_min_angle:
		_begin_turn(Maneuver.TURN_180, diff, _settings.turn_180_duration, _settings.turn_180_speed_factor)
	elif abs_diff >= _settings.turn_90_min_angle:
		var kind: int = Maneuver.TURN_LEFT_90 if diff > 0.0 else Maneuver.TURN_RIGHT_90
		_begin_turn(kind, diff, _settings.turn_90_duration, _settings.turn_90_speed_factor)


func _begin_turn(kind: int, diff: float, duration: float, speed_factor: float) -> void:
	maneuver = kind
	maneuver_elapsed = 0.0
	maneuver_duration = duration
	maneuver_serial += 1
	_turn_sign = 1.0 if diff >= 0.0 else -1.0
	_turn_rate = absf(diff) / duration
	_turn_target_yaw = desired_yaw
	_turn_speed_factor = speed_factor


func _update_rotation(grounded: bool, delta: float) -> void:
	if is_turning():
		if has_direction:
			_turn_target_yaw = desired_yaw
		var diff: float = angle_difference(yaw, _turn_target_yaw)
		if absf(diff) > PI - HALF_TURN_AMBIGUITY:
			diff = absf(diff) * _turn_sign
		# Sens verrouillé : une cible passée de l'autre côté immobilise la rotation, sans l'inverser.
		if diff * _turn_sign > 0.0:
			yaw = wrapf(yaw + _turn_sign * minf(absf(diff), _turn_rate * delta), -PI, PI)
		return
	if not has_direction:
		return
	var rate: float = _settings.gait_turn_rate[gait if gait != GAIT_IDLE else motion_gait]
	if not grounded:
		rate *= _settings.air_control
	yaw = wrapf(rotate_toward(yaw, desired_yaw, rate * delta), -PI, PI)


func _update_speed(walk_slow: bool, grounded: bool, delta: float) -> void:
	var target: float = 0.0
	if has_direction:
		target = _input_speed(walk_slow)
		if is_turning():
			target *= _turn_speed_factor
		else:
			# Ralentir dans les virages serrés : vitesse proportionnelle à l'alignement avec la direction voulue.
			target *= maxf(cos(angle_difference(yaw, desired_yaw)), 0.0)
	var rate: float
	if is_stopping():
		rate = _stop_deceleration
	elif target > speed:
		rate = _settings.gait_acceleration[gait if gait != GAIT_IDLE else motion_gait]
	elif is_turning():
		rate = _settings.turn_deceleration
	else:
		rate = _settings.gait_deceleration[gait if gait != GAIT_IDLE else motion_gait]
	if not grounded:
		rate *= _settings.air_control
	speed = move_toward(speed, target, rate * delta)


## Vitesse voulue pour l'allure et l'intensité de l'entrée (stick analogique : vitesse continue).
func _input_speed(walk_slow: bool) -> float:
	var speeds: PackedFloat64Array = _settings.gait_speed
	if gait == GAIT_RUN:
		return speeds[GAIT_RUN]
	if gait == GAIT_WALK:
		var walk_t: float = clampf(inverse_lerp(_settings.analog_walk_slow_max, 1.0, _magnitude), 0.0, 1.0)
		return lerpf(speeds[GAIT_WALK_SLOW], speeds[GAIT_WALK], walk_t)
	if gait == GAIT_WALK_SLOW:
		if walk_slow:
			return speeds[GAIT_WALK_SLOW]
		var slow_t: float = clampf(inverse_lerp(_settings.move_threshold, _settings.analog_walk_slow_max, _magnitude), 0.0, 1.0)
		return speeds[GAIT_WALK_SLOW] * lerpf(_settings.analog_min_speed_fraction, 1.0, slow_t)
	return 0.0
