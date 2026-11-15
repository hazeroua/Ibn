class_name WindModel
extends RefCounted
## Modèle déterministe du vent : direction, force et rafale en fonction du temps seul.
##
## Aucun état, aucune allocation : evaluate() ne fait que quelques sinus (coût constant, quel que soit
## le temps de jeu, 100 heures comprises, car les flottants de GDScript sont en 64 bits).
## Direction : angle dans le plan (x, z) du monde, vers lequel le vent souffle.

const GUST_PHASE_STEP: float = 1.7

var direction: Vector2 = Vector2.RIGHT
## Force finale du vent, de 0 à 1.
var strength: float = 0.0
## Intensité de la rafale en cours, de 0 à 1.
var gust: float = 0.0

var _settings: WindSettings = null


func _init(settings: WindSettings) -> void:
	_settings = settings


## Calcule direction, force et rafale à l'instant « time » (secondes) pour la force de base « base_strength » (0 à 1).
func evaluate(time: float, base_strength: float) -> void:
	var s: WindSettings = _settings
	var drift: float = 0.7 * sin(TAU * time / s.direction_drift_period) + 0.3 * sin(TAU * time / (s.direction_drift_period * 0.37) + 1.3)
	var angle: float = s.direction_base + s.direction_drift * drift
	direction = Vector2(cos(angle), sin(angle))
	var variation: float = (
		0.6 * sin(TAU * time / s.strength_variation_period) + 0.4 * sin(TAU * time / (s.strength_variation_period * 0.41) + 0.8)
	)
	var sum: float = 0.0
	var index: int = 0
	for period: float in s.gust_periods:
		sum += 0.5 + 0.5 * sin(TAU * time / period + float(index) * GUST_PHASE_STEP)
		index += 1
	gust = pow(sum / float(index), s.gust_sharpness)
	strength = clampf(base_strength + s.strength_variation * variation + s.gust_amplitude * gust, 0.0, 1.0)
