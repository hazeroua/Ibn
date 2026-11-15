class_name WindSettings
extends RefCounted
## Réglages du vent lus dans res://data/wind/wind.json (validés une fois, jamais relus en jeu).

const SETTINGS_PATH: String = "res://data/wind/wind.json"

var seed_value: int = 0
var time_wrap: float = 4096.0

var direction_base: float = 0.0
var direction_drift: float = 0.0
var direction_drift_period: float = 1.0

var strength_base: float = 0.0
var strength_variation: float = 0.0
var strength_variation_period: float = 1.0

var gust_amplitude: float = 0.0
var gust_periods: PackedFloat64Array = PackedFloat64Array()
var gust_sharpness: float = 1.0

var sand_max_particles: int = 0
var sand_box_size: Vector3 = Vector3.ONE
var sand_height_offset: float = 0.0
var sand_lifetime: float = 1.0
var sand_min_strength: float = 0.0
var sand_speed_min: float = 0.0
var sand_speed_max: float = 0.0
var sand_spread: float = 0.0
var sand_gravity_y: float = 0.0
var sand_particle_size: float = 0.05
var sand_color: Color = Color.WHITE
var sand_update_interval: float = 0.1

var haze_radius: float = 1.0
var haze_height: float = 1.0
var haze_segments: int = 3
var haze_rings: int = 1
var haze_heat_color: Color = Color.WHITE
var haze_heat_alpha: float = 0.0
var haze_dust_color: Color = Color.WHITE
var haze_dust_alpha: float = 0.0
var haze_noise_scale: float = 1.0
var haze_shimmer_speed: float = 0.0

var audio_bus: StringName = &"Wind"
var audio_send: StringName = &"Master"
var audio_mix_rate: int = 22050
var audio_loop_seconds: float = 1.0
var rumble: WindLayer = WindLayer.new()
var gust: WindLayer = WindLayer.new()


## Réglages d'une couche sonore (bruit filtré).
class WindLayer:
	extends RefCounted
	var high_cutoff_hz: float = 0.0
	var low_cutoff_hz: float = 0.0
	var min_db: float = 0.0
	var max_db: float = 0.0
	var min_pitch: float = 1.0
	var max_pitch: float = 1.0


## Lit et valide un dictionnaire de réglages ; renvoie null (après push_error) si une valeur est incohérente.
static func from_dictionary(data: Dictionary, context: String) -> WindSettings:
	var s := WindSettings.new()
	s.seed_value = JsonData.get_int(data, "seed", context)
	s.time_wrap = JsonData.get_float(data, "time_wrap", context)
	var direction: Dictionary = JsonData.get_dictionary(data, "direction", context)
	s.direction_base = deg_to_rad(JsonData.get_float(direction, "base_degrees", context))
	s.direction_drift = deg_to_rad(JsonData.get_float(direction, "drift_degrees", context))
	s.direction_drift_period = JsonData.get_float(direction, "drift_period", context)
	var strength: Dictionary = JsonData.get_dictionary(data, "strength", context)
	s.strength_base = JsonData.get_float(strength, "base", context)
	s.strength_variation = JsonData.get_float(strength, "variation", context)
	s.strength_variation_period = JsonData.get_float(strength, "variation_period", context)
	var gust_data: Dictionary = JsonData.get_dictionary(data, "gust", context)
	s.gust_amplitude = JsonData.get_float(gust_data, "amplitude", context)
	s.gust_sharpness = JsonData.get_float(gust_data, "sharpness", context)
	for period: Variant in JsonData.get_array(gust_data, "periods", context):
		if typeof(period) != TYPE_FLOAT and typeof(period) != TYPE_INT:
			push_error("WindSettings : « gust.periods » ne contient que des nombres (%s)." % context)
			return null
		s.gust_periods.append(float(period))
	var sand: Dictionary = JsonData.get_dictionary(data, "sand", context)
	s.sand_max_particles = JsonData.get_int(sand, "max_particles", context)
	s.sand_box_size = JsonData.get_vector3(sand, "box_size", context)
	s.sand_height_offset = JsonData.get_float(sand, "height_offset", context)
	s.sand_lifetime = JsonData.get_float(sand, "lifetime", context)
	s.sand_min_strength = JsonData.get_float(sand, "min_strength", context)
	s.sand_speed_min = JsonData.get_float(sand, "speed_min", context)
	s.sand_speed_max = JsonData.get_float(sand, "speed_max", context)
	s.sand_spread = deg_to_rad(JsonData.get_float(sand, "spread_degrees", context))
	s.sand_gravity_y = JsonData.get_float(sand, "gravity_y", context)
	s.sand_particle_size = JsonData.get_float(sand, "particle_size", context)
	s.sand_color = JsonData.get_color(sand, "color", context)
	s.sand_update_interval = JsonData.get_float(sand, "update_interval", context)
	var haze: Dictionary = JsonData.get_dictionary(data, "haze", context)
	s.haze_radius = JsonData.get_float(haze, "radius", context)
	s.haze_height = JsonData.get_float(haze, "height", context)
	s.haze_segments = JsonData.get_int(haze, "segments", context)
	s.haze_rings = JsonData.get_int(haze, "rings", context)
	s.haze_heat_color = JsonData.get_color(haze, "heat_color", context)
	s.haze_heat_alpha = JsonData.get_float(haze, "heat_alpha", context)
	s.haze_dust_color = JsonData.get_color(haze, "dust_color", context)
	s.haze_dust_alpha = JsonData.get_float(haze, "dust_alpha", context)
	s.haze_noise_scale = JsonData.get_float(haze, "noise_scale", context)
	s.haze_shimmer_speed = JsonData.get_float(haze, "shimmer_speed", context)
	var audio: Dictionary = JsonData.get_dictionary(data, "audio", context)
	s.audio_bus = StringName(JsonData.get_string(audio, "bus", context))
	s.audio_send = StringName(JsonData.get_string(audio, "send", context))
	s.audio_mix_rate = JsonData.get_int(audio, "mix_rate", context)
	s.audio_loop_seconds = JsonData.get_float(audio, "loop_seconds", context)
	_read_layer(s.rumble, JsonData.get_dictionary(audio, "rumble", context), context)
	_read_layer(s.gust, JsonData.get_dictionary(audio, "gust", context), context)
	if not s._is_valid(context):
		return null
	return s


## Charge res://data/wind/wind.json.
static func load_default() -> WindSettings:
	return from_dictionary(JsonData.load_dictionary(SETTINGS_PATH), SETTINGS_PATH)


static func _read_layer(layer: WindLayer, data: Dictionary, context: String) -> void:
	layer.high_cutoff_hz = JsonData.get_float(data, "high_cutoff_hz", context)
	layer.low_cutoff_hz = JsonData.get_float(data, "low_cutoff_hz", context)
	layer.min_db = JsonData.get_float(data, "min_db", context)
	layer.max_db = JsonData.get_float(data, "max_db", context)
	layer.min_pitch = JsonData.get_float(data, "min_pitch", context)
	layer.max_pitch = JsonData.get_float(data, "max_pitch", context)


func _is_valid(context: String) -> bool:
	var problems: PackedStringArray = PackedStringArray()
	if time_wrap < 60.0:
		problems.append("time_wrap >= 60")
	if direction_drift_period <= 0.0 or strength_variation_period <= 0.0:
		problems.append("périodes > 0")
	if strength_base < 0.0 or strength_base > 1.0 or strength_variation < 0.0 or gust_amplitude < 0.0:
		problems.append("force de base dans [0, 1], variation et amplitude >= 0")
	if gust_periods.is_empty() or gust_sharpness < 1.0:
		problems.append("au moins une période de rafale, netteté >= 1")
	for period: float in gust_periods:
		if period <= 0.0:
			problems.append("périodes de rafale > 0")
	if sand_max_particles < 1 or sand_max_particles > 8192:
		problems.append("sand.max_particles dans [1, 8192]")
	if sand_box_size.x <= 0.0 or sand_box_size.y <= 0.0 or sand_box_size.z <= 0.0 or sand_lifetime <= 0.0:
		problems.append("sand.box_size et lifetime > 0")
	if sand_speed_max < sand_speed_min or sand_speed_min < 0.0 or sand_update_interval <= 0.0 or sand_particle_size <= 0.0:
		problems.append("sand : vitesses croissantes, intervalle et taille > 0")
	if haze_radius <= 0.0 or haze_height <= 0.0 or haze_segments < 3 or haze_rings < 1 or haze_noise_scale <= 0.0:
		problems.append("haze : rayon, hauteur, échelle > 0, segments >= 3, anneaux >= 1")
	if audio_mix_rate < 8000 or audio_loop_seconds < 1.0 or audio_bus.is_empty():
		problems.append("audio : mix_rate >= 8000, loop_seconds >= 1, bus non vide")
	for layer: WindLayer in [rumble, gust]:
		if layer.high_cutoff_hz <= 0.0 or layer.low_cutoff_hz < 0.0 or layer.low_cutoff_hz >= layer.high_cutoff_hz:
			problems.append("audio : 0 <= low_cutoff_hz < high_cutoff_hz")
		if layer.min_db > layer.max_db or layer.min_pitch <= 0.0 or layer.max_pitch < layer.min_pitch:
			problems.append("audio : min_db <= max_db, hauteurs croissantes > 0")
	for problem: String in problems:
		push_error("WindSettings : valeur incohérente (%s) : %s." % [context, problem])
	return problems.is_empty()
