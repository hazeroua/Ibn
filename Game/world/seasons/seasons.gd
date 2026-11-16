class_name SeasonsSystem
extends Node
## Autoload « Seasons » : saison courante, transition douce et réglages publiés pour le reste du jeu.
##
## - Variables : season (printemps, ete, automne, hiver), transitioning.
## - Uniformes globaux de shader (déclarés ici s'ils ne le sont pas déjà) : season_sun_color (vec3),
##   season_sun_intensity, season_sun_max_height (degrés), season_day_length (heures), season_fog_density,
##   season_grass_color (vec3), season_palm_color (vec3), season_wind_strength, season_dust,
##   season_bloom (floats ; bloom : 1 en pleine saison des fleurs éphémères, 0 hors saison), season_flowering
##   (floraison des arbustes, de 0 à 1, facultative dans le fichier : 0 par défaut), season_fruit (maturité des fruits des
##   arbres fruitiers, de 0 à 1), season_crop_growth (croissance des cultures basses : 0 sol nu, 1 pleine végétation) et
##   season_crop_ripe (maturité des cultures : 0 vert, 1 doré), facultatifs dans le fichier (0 par défaut).
## - Lecture sans dépendance de code : get_value(name), get_multiplier(name), get_color(name), ou les uniformes.
##   DayNight, Wind et la végétation les lisent par get_node_or_null ou par les uniformes.
##
## Pires cas : partie de 100 heures (aucun état ne dérive : tout est recalculé depuis deux saisons figées),
## changements de saison répétés en pleine transition (la transition repart de l'état affiché, sans saut),
## galop en zone dense (hors transition le nœud ne traite rien ; pendant une transition : 16 mélanges
## flottants et 10 écritures d'uniformes par image, aucune allocation, tableaux créés au démarrage).
## Réglages : res://data/seasons/seasons.json.

signal season_changed(id: StringName)

const SETTINGS_PATH: String = "res://data/seasons/seasons.json"

## Cases du tableau de valeurs d'une saison (ordre fixe, une case par flottant).
const SUN_R: int = 0
const SUN_G: int = 1
const SUN_B: int = 2
const SUN_INTENSITY: int = 3
const SUN_MAX_HEIGHT: int = 4
const DAY_LENGTH: int = 5
const FOG_DENSITY: int = 6
const GRASS_R: int = 7
const GRASS_G: int = 8
const GRASS_B: int = 9
const PALM_R: int = 10
const PALM_G: int = 11
const PALM_B: int = 12
const WIND_STRENGTH: int = 13
const DUST: int = 14
const BLOOM: int = 15
const FLOWERING: int = 16
const FRUIT: int = 17
const CROP_GROWTH: int = 18
const CROP_RIPE: int = 19
const VALUE_COUNT: int = 20

## Saison courante (la cible quand une transition est en cours).
var season: StringName = &"ete"
## Vrai tant que le mélange entre deux saisons n'est pas terminé.
var transitioning: bool = false

var _ids: Array[StringName] = []
var _values: Dictionary = {}
var _reference: PackedFloat32Array = PackedFloat32Array()
var _prefix: String = "season_"
var _duration: float = 1.0
var _elapsed: float = 0.0
var _from: PackedFloat32Array = PackedFloat32Array()
var _to: PackedFloat32Array = PackedFloat32Array()
var _current: PackedFloat32Array = PackedFloat32Array()
var _scalar_names: Dictionary = {}
var _uniform_names: Array[StringName] = []
var _ready_ok: bool = false


func _ready() -> void:
	var data: Dictionary = JsonData.load_dictionary(SETTINGS_PATH)
	if data.is_empty():
		set_process(false)
		return
	configure(data)


## Fournit les réglages (tests) ou les lit déjà validés depuis seasons.json.
func configure(data: Dictionary) -> void:
	var context: String = SETTINGS_PATH
	_prefix = JsonData.get_string(data, "uniform_prefix", context)
	_duration = maxf(JsonData.get_float(data, "transition_seconds", context), 0.001)
	var seasons: Dictionary = JsonData.get_dictionary(data, "seasons", context)
	_ids.clear()
	_values.clear()
	for key: String in seasons:
		var entry: Dictionary = JsonData.get_dictionary(seasons, key, context)
		_ids.append(StringName(key))
		_values[StringName(key)] = _read_season(entry, "%s : %s" % [context, key])
	var reference_id := StringName(JsonData.get_string(data, "reference_season", context))
	var default_id := StringName(JsonData.get_string(data, "default_season", context))
	if not _values.has(reference_id) or not _values.has(default_id):
		push_error("Seasons : saison de référence ou par défaut inconnue (%s)." % context)
		set_process(false)
		return
	_reference = _values[reference_id]
	_scalar_names = {
		&"sun_intensity": SUN_INTENSITY,
		&"sun_max_height": SUN_MAX_HEIGHT,
		&"day_length": DAY_LENGTH,
		&"fog_density": FOG_DENSITY,
		&"wind_strength": WIND_STRENGTH,
		&"dust": DUST,
		&"bloom": BLOOM,
		&"flowering": FLOWERING,
		&"fruit": FRUIT,
		&"crop_growth": CROP_GROWTH,
		&"crop_ripe": CROP_RIPE,
	}
	_from = (_values[default_id] as PackedFloat32Array).duplicate()
	_to = _from.duplicate()
	_current = _from.duplicate()
	season = default_id
	transitioning = false
	_elapsed = 0.0
	_declare_globals()
	_ready_ok = true
	_publish()
	set_process(false)


func _process(delta: float) -> void:
	_elapsed += delta
	var t: float = clampf(_elapsed / _duration, 0.0, 1.0)
	blend_into(_current, _from, _to, t)
	if t >= 1.0:
		transitioning = false
		set_process(false)
	_publish()


## Identifiants des saisons connues, dans l'ordre du fichier.
func get_season_ids() -> Array[StringName]:
	return _ids


## Change de saison avec une transition douce ; une saison inconnue est refusée. Ré-appeler pendant une transition
## repart de l'état affiché (aucun saut). Avec instant = true le changement est immédiat.
func set_season(id: StringName, instant: bool = false) -> void:
	if not _ready_ok or not _values.has(id):
		push_error("Seasons : saison inconnue ou système non configuré : %s" % id)
		return
	if id == season and not transitioning:
		return
	_copy_into(_from, _current)
	_copy_into(_to, _values[id] as PackedFloat32Array)
	_elapsed = 0.0
	season = id
	if instant:
		_copy_into(_current, _to)
		transitioning = false
		set_process(false)
		_publish()
	else:
		transitioning = true
		set_process(true)
	season_changed.emit(id)


## Mélange deux saisons (t de 0 à 1, adouci) et renvoie un nouveau tableau de VALUE_COUNT flottants.
## Hors chemin par image : à l'intérieur du jeu, blend_into n'alloue rien.
func blend(from_id: StringName, to_id: StringName, t: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(VALUE_COUNT)
	if not _values.has(from_id) or not _values.has(to_id):
		push_error("Seasons : blend avec une saison inconnue : %s -> %s" % [from_id, to_id])
		return out
	blend_into(out, _values[from_id], _values[to_id], t)
	return out


## Version sans allocation de blend : écrit dans out (taille VALUE_COUNT), t est adouci (smoothstep).
static func blend_into(out: PackedFloat32Array, a: PackedFloat32Array, b: PackedFloat32Array, t: float) -> void:
	var w: float = smoothstep(0.0, 1.0, clampf(t, 0.0, 1.0))
	for i: int in VALUE_COUNT:
		out[i] = lerpf(a[i], b[i], w)


## Valeur courante (transition comprise) d'un réglage scalaire : sun_intensity, sun_max_height, day_length,
## fog_density, wind_strength, dust, bloom. Renvoie 0 pour un nom inconnu.
func get_value(value_name: StringName) -> float:
	if not _scalar_names.has(value_name):
		push_error("Seasons : réglage inconnu : %s" % value_name)
		return 0.0
	return _current[int(_scalar_names[value_name])]


## Multiplicateur courant d'un réglage scalaire par rapport à la saison de référence (1 = comme en référence).
func get_multiplier(value_name: StringName) -> float:
	if not _scalar_names.has(value_name):
		push_error("Seasons : réglage inconnu : %s" % value_name)
		return 1.0
	var index: int = int(_scalar_names[value_name])
	var base: float = _reference[index]
	return _current[index] / base if absf(base) > 0.000001 else 1.0


## Couleur courante : sun, grass ou palm.
func get_color(color_name: StringName) -> Color:
	var first: int
	match color_name:
		&"sun":
			first = SUN_R
		&"grass":
			first = GRASS_R
		&"palm":
			first = PALM_R
		_:
			push_error("Seasons : couleur inconnue : %s" % color_name)
			return Color.MAGENTA
	return Color(_current[first], _current[first + 1], _current[first + 2])


## Copie sans allocation (les tableaux compactés n'ont pas d'assign).
static func _copy_into(out: PackedFloat32Array, source: PackedFloat32Array) -> void:
	for i: int in VALUE_COUNT:
		out[i] = source[i]


func _read_season(entry: Dictionary, context: String) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(VALUE_COUNT)
	var sun: Color = JsonData.get_color(entry, "sun_color", context)
	var grass: Color = JsonData.get_color(entry, "grass_color", context)
	var palm: Color = JsonData.get_color(entry, "palm_color", context)
	out[SUN_R] = sun.r
	out[SUN_G] = sun.g
	out[SUN_B] = sun.b
	out[GRASS_R] = grass.r
	out[GRASS_G] = grass.g
	out[GRASS_B] = grass.b
	out[PALM_R] = palm.r
	out[PALM_G] = palm.g
	out[PALM_B] = palm.b
	out[SUN_INTENSITY] = JsonData.get_float(entry, "sun_intensity", context)
	out[SUN_MAX_HEIGHT] = JsonData.get_float(entry, "sun_max_height", context)
	out[DAY_LENGTH] = JsonData.get_float(entry, "day_length_hours", context)
	out[FOG_DENSITY] = JsonData.get_float(entry, "fog_density", context)
	out[WIND_STRENGTH] = JsonData.get_float(entry, "wind_strength", context)
	out[DUST] = JsonData.get_float(entry, "dust", context)
	out[BLOOM] = JsonData.get_float(entry, "bloom", context)
	out[FLOWERING] = clampf(JsonData.get_float_or(entry, "flowering", 0.0, context), 0.0, 1.0)
	out[FRUIT] = clampf(JsonData.get_float_or(entry, "fruit", 0.0, context), 0.0, 1.0)
	out[CROP_GROWTH] = clampf(JsonData.get_float_or(entry, "crop_growth", 0.0, context), 0.0, 1.0)
	out[CROP_RIPE] = clampf(JsonData.get_float_or(entry, "crop_ripe", 0.0, context), 0.0, 1.0)
	return out


func _declare_globals() -> void:
	var specs: Array = [
		["sun_color", RenderingServer.GLOBAL_VAR_TYPE_VEC3, Vector3.ONE],
		["sun_intensity", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 1.0],
		["sun_max_height", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 60.0],
		["day_length", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 12.0],
		["fog_density", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0],
		["grass_color", RenderingServer.GLOBAL_VAR_TYPE_VEC3, Vector3.ONE],
		["palm_color", RenderingServer.GLOBAL_VAR_TYPE_VEC3, Vector3.ONE],
		["wind_strength", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0],
		["dust", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0],
		["bloom", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0],
		["flowering", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0],
		["fruit", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0],
		["crop_growth", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0],
		["crop_ripe", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0],
	]
	_uniform_names.clear()
	for spec: Array in specs:
		var uniform := StringName(_prefix + String(spec[0]))
		_uniform_names.append(uniform)
		ShaderGlobals.declare(uniform, spec[1] as RenderingServer.GlobalShaderParameterType, spec[2])


## Écrit les quatorze uniformes (ordre de _declare_globals) ; aucune allocation de tableau.
func _publish() -> void:
	var c: PackedFloat32Array = _current
	RenderingServer.global_shader_parameter_set(_uniform_names[0], Vector3(c[SUN_R], c[SUN_G], c[SUN_B]))
	RenderingServer.global_shader_parameter_set(_uniform_names[1], c[SUN_INTENSITY])
	RenderingServer.global_shader_parameter_set(_uniform_names[2], c[SUN_MAX_HEIGHT])
	RenderingServer.global_shader_parameter_set(_uniform_names[3], c[DAY_LENGTH])
	RenderingServer.global_shader_parameter_set(_uniform_names[4], c[FOG_DENSITY])
	RenderingServer.global_shader_parameter_set(_uniform_names[5], Vector3(c[GRASS_R], c[GRASS_G], c[GRASS_B]))
	RenderingServer.global_shader_parameter_set(_uniform_names[6], Vector3(c[PALM_R], c[PALM_G], c[PALM_B]))
	RenderingServer.global_shader_parameter_set(_uniform_names[7], c[WIND_STRENGTH])
	RenderingServer.global_shader_parameter_set(_uniform_names[8], c[DUST])
	RenderingServer.global_shader_parameter_set(_uniform_names[9], c[BLOOM])
	RenderingServer.global_shader_parameter_set(_uniform_names[10], c[FLOWERING])
	RenderingServer.global_shader_parameter_set(_uniform_names[11], c[FRUIT])
	RenderingServer.global_shader_parameter_set(_uniform_names[12], c[CROP_GROWTH])
	RenderingServer.global_shader_parameter_set(_uniform_names[13], c[CROP_RIPE])
