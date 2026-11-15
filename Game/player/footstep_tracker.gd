class_name FootstepTracker
extends RefCounted
## Cadence des pas : un pas chaque fois que la distance parcourue au sol atteint la foulée de
## l'allure, en alternant pied gauche (0) et pied droit (1). Un dernier pas pose le pied à l'arrêt
## si le pas précédent est assez loin. Nombre de pas par image borné : la distance d'une image est
## plafonnée par la distance de téléportation (au-delà, le compteur repart sans émettre de pas).

const LEFT: int = 0
const RIGHT: int = 1

var _settings: LocomotionSettings
var _to_next: float = 0.0
var _since_last: float = 0.0
var _next_foot: int = LEFT
var _moving: bool = false


func _init(settings: LocomotionSettings) -> void:
	_settings = settings
	reset(settings.gait_stride_length[LocomotionSettings.Gait.WALK])


## Repart de l'arrêt : le premier pas tombe après une fraction de foulée.
func reset(stride: float) -> void:
	_to_next = stride * _settings.first_step_fraction
	_since_last = 0.0
	_moving = false


## Vrai si le personnage a parcouru de la distance depuis le dernier arrêt.
func is_moving() -> bool:
	return _moving


## Ajoute la distance parcourue au sol ; renvoie le nombre de pas franchis (0 si distance ≤ 0).
## Une distance supérieure à la distance de téléportation n'émet aucun pas et repart de l'arrêt.
func advance(distance: float, stride: float) -> int:
	if distance > _settings.teleport_distance:
		reset(stride)
		return 0
	if not (distance > 0.0):
		return 0
	_moving = true
	_to_next = minf(_to_next, stride) - distance
	_since_last += distance
	var count: int = 0
	while _to_next <= 0.0:
		_to_next += stride
		count += 1
	if count > 0:
		_since_last = stride - _to_next
	return count


## Pied du prochain pas, puis alterne.
func take_foot() -> int:
	var foot: int = _next_foot
	_next_foot = RIGHT if foot == LEFT else LEFT
	return foot


## Le personnage vient de s'arrêter : renvoie vrai s'il faut poser un dernier pas, puis repart de l'arrêt.
func stop(stride: float) -> bool:
	var final_step: bool = _moving and _since_last >= stride * _settings.stop_step_min_fraction
	reset(stride)
	return final_step
