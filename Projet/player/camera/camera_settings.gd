class_name CameraSettings
extends RefCounted
## Réglages de la caméra à la troisième personne, lus dans res://data/player/camera.json.
##
## Les angles sont convertis en radians et les couches de collision en masque une seule fois, au
## chargement : la caméra ne fait aucune conversion ni lecture de dictionnaire pendant le jeu.
## Toute valeur absente, mal typée ou incohérente est signalée par push_error (échec du pipeline).

const DEFAULT_PATH: String = "res://data/player/camera.json"
const CONTEXT: String = "réglages de la caméra"
## Numéro de couche de physique le plus grand accepté par Godot.
const MAX_PHYSICS_LAYER: int = 32

# Orbite
var initial_yaw: float = 0.0
var initial_pitch: float = 0.0
var pitch_min: float = 0.0
var pitch_max: float = 0.0
var rotation_smoothing: float = 0.0
# Souris (radians par pixel d'écran)
var mouse_sensitivity: float = 0.0
var mouse_invert_x: bool = false
var mouse_invert_y: bool = false
var capture_mouse_on_start: bool = false
# Stick droit (radians par seconde à fond)
var stick_speed: float = 0.0
var stick_response_exponent: float = 1.0
var stick_invert_x: bool = false
var stick_invert_y: bool = false
# Cadrage
var pivot_height: float = 0.0
var probe_origin_height: float = 0.0
var shoulder_offset: float = 0.0
# Suivi
var follow_smoothing: float = 0.0
var follow_max_lag: float = 0.0
var teleport_distance: float = 0.0
# Rapprocher, éloigner
var zoom_min: float = 0.0
var zoom_max: float = 0.0
var zoom_initial: float = 0.0
var zoom_step: float = 0.0
var zoom_smoothing: float = 0.0
# Collisions
var collision_mask: int = 0
var probe_radius: float = 0.0
## Écart gardé avec le décor au bout de chaque balayage : le balayage suivant ne part jamais d'un
## contact (Jolt ignore les corps déjà touchés au départ d'un balayage).
var contact_skin: float = 0.0
var return_smoothing: float = 0.0
# Champ de vision (radians pour les écarts, degrés pour Camera3D.fov)
var fov_base_deg: float = 0.0
var fov_run_bonus_deg: float = 0.0
var fov_speed_start: float = 0.0
var fov_speed_full: float = 0.0
var speed_smoothing: float = 0.0
var fov_smoothing: float = 0.0
# Objectif
var near: float = 0.0
var far: float = 0.0
# Fondu de la cible quand la caméra est trop près
var fade_start_distance: float = 0.0
var fade_end_distance: float = 0.0
var fade_smoothing: float = 0.0


## Charge les réglages du jeu (res://data/player/camera.json).
static func load_default() -> CameraSettings:
	return from_dictionary(JsonData.load_dictionary(DEFAULT_PATH))


## Réglages à cheval : camera.json dont les sections de « mounted » remplacent clé par clé celles du jeu à pied.
static func load_mounted() -> CameraSettings:
	var data: Dictionary = JsonData.load_dictionary(DEFAULT_PATH)
	var mounted: Dictionary = PlayerJsonData.get_dictionary(data, "mounted", CONTEXT)
	var merged: Dictionary = data.duplicate(true)
	for section: Variant in mounted.keys():
		if typeof(mounted[section]) != TYPE_DICTIONARY:
			continue
		var base: Dictionary = PlayerJsonData.get_dictionary(merged, str(section), CONTEXT)
		base.merge(mounted[section] as Dictionary, true)
	return from_dictionary(merged)


## Construit les réglages à partir d'un dictionnaire au format de camera.json.
static func from_dictionary(data: Dictionary) -> CameraSettings:
	var s := CameraSettings.new()
	var orbit: Dictionary = PlayerJsonData.get_dictionary(data, "orbit", CONTEXT)
	s.initial_yaw = deg_to_rad(PlayerJsonData.get_float(orbit, "initial_yaw_deg", "orbit"))
	s.initial_pitch = deg_to_rad(PlayerJsonData.get_float(orbit, "initial_pitch_deg", "orbit"))
	s.pitch_min = deg_to_rad(PlayerJsonData.get_float(orbit, "pitch_min_deg", "orbit"))
	s.pitch_max = deg_to_rad(PlayerJsonData.get_float(orbit, "pitch_max_deg", "orbit"))
	s.rotation_smoothing = PlayerJsonData.get_float(orbit, "rotation_smoothing", "orbit")

	var mouse: Dictionary = PlayerJsonData.get_dictionary(data, "mouse", CONTEXT)
	s.mouse_sensitivity = deg_to_rad(PlayerJsonData.get_float(mouse, "sensitivity_deg_per_pixel", "mouse"))
	s.mouse_invert_x = PlayerJsonData.get_bool(mouse, "invert_x", "mouse")
	s.mouse_invert_y = PlayerJsonData.get_bool(mouse, "invert_y", "mouse")
	s.capture_mouse_on_start = PlayerJsonData.get_bool(mouse, "capture_on_start", "mouse")

	var stick: Dictionary = PlayerJsonData.get_dictionary(data, "stick", CONTEXT)
	s.stick_speed = deg_to_rad(PlayerJsonData.get_float(stick, "speed_deg_per_s", "stick"))
	s.stick_response_exponent = PlayerJsonData.get_float(stick, "response_exponent", "stick")
	s.stick_invert_x = PlayerJsonData.get_bool(stick, "invert_x", "stick")
	s.stick_invert_y = PlayerJsonData.get_bool(stick, "invert_y", "stick")

	var framing: Dictionary = PlayerJsonData.get_dictionary(data, "framing", CONTEXT)
	s.pivot_height = PlayerJsonData.get_float(framing, "pivot_height_m", "framing")
	s.probe_origin_height = PlayerJsonData.get_float(framing, "probe_origin_height_m", "framing")
	s.shoulder_offset = PlayerJsonData.get_float(framing, "shoulder_offset_m", "framing")

	var follow: Dictionary = PlayerJsonData.get_dictionary(data, "follow", CONTEXT)
	s.follow_smoothing = PlayerJsonData.get_float(follow, "position_smoothing", "follow")
	s.follow_max_lag = PlayerJsonData.get_float(follow, "max_lag_m", "follow")
	s.teleport_distance = PlayerJsonData.get_float(follow, "teleport_distance_m", "follow")

	var zoom: Dictionary = PlayerJsonData.get_dictionary(data, "zoom", CONTEXT)
	s.zoom_min = PlayerJsonData.get_float(zoom, "min_distance_m", "zoom")
	s.zoom_max = PlayerJsonData.get_float(zoom, "max_distance_m", "zoom")
	s.zoom_initial = PlayerJsonData.get_float(zoom, "initial_distance_m", "zoom")
	s.zoom_step = PlayerJsonData.get_float(zoom, "step_m", "zoom")
	s.zoom_smoothing = PlayerJsonData.get_float(zoom, "smoothing", "zoom")

	var collision: Dictionary = PlayerJsonData.get_dictionary(data, "collision", CONTEXT)
	s.collision_mask = _layers_to_mask(PlayerJsonData.get_array(collision, "layers", "collision"))
	s.probe_radius = PlayerJsonData.get_float(collision, "probe_radius_m", "collision")
	s.contact_skin = PlayerJsonData.get_float(collision, "contact_skin_m", "collision")
	s.return_smoothing = PlayerJsonData.get_float(collision, "return_smoothing", "collision")

	var fov: Dictionary = PlayerJsonData.get_dictionary(data, "fov", CONTEXT)
	s.fov_base_deg = PlayerJsonData.get_float(fov, "base_deg", "fov")
	s.fov_run_bonus_deg = PlayerJsonData.get_float(fov, "run_bonus_deg", "fov")
	s.fov_speed_start = PlayerJsonData.get_float(fov, "speed_start_mps", "fov")
	s.fov_speed_full = PlayerJsonData.get_float(fov, "speed_full_mps", "fov")
	s.speed_smoothing = PlayerJsonData.get_float(fov, "speed_smoothing", "fov")
	s.fov_smoothing = PlayerJsonData.get_float(fov, "fov_smoothing", "fov")

	var lens: Dictionary = PlayerJsonData.get_dictionary(data, "lens", CONTEXT)
	s.near = PlayerJsonData.get_float(lens, "near_m", "lens")
	s.far = PlayerJsonData.get_float(lens, "far_m", "lens")

	var fade: Dictionary = PlayerJsonData.get_dictionary(data, "target_fade", CONTEXT)
	s.fade_start_distance = PlayerJsonData.get_float(fade, "start_distance_m", "target_fade")
	s.fade_end_distance = PlayerJsonData.get_float(fade, "end_distance_m", "target_fade")
	s.fade_smoothing = PlayerJsonData.get_float(fade, "smoothing", "target_fade")

	s._validate()
	return s


## Masque de collision correspondant à une liste de numéros de couche (1 à 32).
static func _layers_to_mask(layers: Array) -> int:
	var mask: int = 0
	for raw: Variant in layers:
		if typeof(raw) != TYPE_INT and typeof(raw) != TYPE_FLOAT:
			push_error("CameraSettings : les couches de collision doivent être des nombres.")
			continue
		var number: float = float(raw)
		var layer: int = int(roundf(number))
		if not is_equal_approx(number, float(layer)) or layer < 1 or layer > MAX_PHYSICS_LAYER:
			push_error("CameraSettings : couche de collision invalide : %s (1 à %d)." % [str(raw), MAX_PHYSICS_LAYER])
			continue
		mask |= 1 << (layer - 1)
	return mask


func _validate() -> void:
	_check(pitch_min < pitch_max, "pitch_min_deg doit être inférieur à pitch_max_deg")
	_check(pitch_min > -PI * 0.5 and pitch_max < PI * 0.5, "les limites d'angle vertical doivent rester entre -90 et 90 degrés")
	_check(initial_pitch >= pitch_min and initial_pitch <= pitch_max, "initial_pitch_deg doit être entre les limites")
	_check(mouse_sensitivity > 0.0, "la sensibilité de la souris doit être positive")
	_check(stick_speed > 0.0, "la vitesse du stick doit être positive")
	_check(stick_response_exponent >= 1.0, "response_exponent doit être au moins 1")
	_check(probe_origin_height >= 0.0 and probe_origin_height <= pivot_height, "probe_origin_height_m doit être entre 0 et pivot_height_m")
	_check(follow_max_lag >= 0.0, "max_lag_m ne peut pas être négatif")
	_check(teleport_distance > follow_max_lag, "teleport_distance_m doit dépasser max_lag_m")
	_check(zoom_min > probe_radius, "min_distance_m doit dépasser le rayon de la sonde de collision")
	_check(zoom_min <= zoom_initial and zoom_initial <= zoom_max, "initial_distance_m doit être entre les distances limites")
	_check(zoom_step > 0.0, "step_m doit être positif")
	_check(collision_mask != 0, "au moins une couche de collision est nécessaire")
	_check(probe_radius > 0.0, "probe_radius_m doit être positif")
	_check(contact_skin > 0.0 and contact_skin < probe_radius, "contact_skin_m doit être positif et inférieur au rayon de la sonde")
	# La sonde doit envelopper le plan proche de la caméra, sinon l'image pourrait voir à travers un mur.
	var half_height: float = near * tan(deg_to_rad(fov_base_deg + fov_run_bonus_deg) * 0.5)
	var half_width: float = half_height * 16.0 / 9.0
	var near_reach: float = sqrt(near * near + half_height * half_height + half_width * half_width)
	_check(probe_radius > near_reach, "probe_radius_m doit envelopper le plan proche (au moins %.3f m)" % near_reach)
	_check(fov_base_deg > 1.0 and fov_base_deg + fov_run_bonus_deg < 179.0, "champ de vision hors limites")
	_check(fov_run_bonus_deg >= 0.0, "run_bonus_deg ne peut pas être négatif")
	_check(fov_speed_start < fov_speed_full, "speed_start_mps doit être inférieur à speed_full_mps")
	_check(near > 0.0 and near < far, "near_m doit être positif et inférieur à far_m")
	_check(fade_end_distance < fade_start_distance, "end_distance_m doit être inférieur à start_distance_m")
	_check(fade_end_distance >= 0.0, "end_distance_m ne peut pas être négatif")
	var rates: PackedFloat32Array = [
		rotation_smoothing, follow_smoothing, zoom_smoothing, return_smoothing, speed_smoothing, fov_smoothing, fade_smoothing
	]
	for rate: float in rates:
		_check(rate > 0.0, "chaque taux de lissage doit être positif")


func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error("CameraSettings : %s." % message)
