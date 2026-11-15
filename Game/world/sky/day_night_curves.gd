class_name DayNightCurves
extends RefCounted
## Courbes du cycle jour/nuit : images clés (res://data/sky/day_night.json) échantillonnées une fois
## pour toutes dans une table de « resolution » entrées couvrant 24 h (cycle fermé).
##
## Pire cas : une lecture par image à n'importe quelle heure, depuis plusieurs systèmes. sample() ne
## fait qu'une interpolation linéaire entre deux entrées voisines de la table (CHANNEL_COUNT
## nombres), sans allocation ni recherche ; le lissage entre images clés est calculé à la
## construction. La table est continue, y compris au passage de 24 h à 0 h.

const HOURS_PER_DAY: float = 24.0

## Disposition des canaux (couleurs : 3 nombres r, g, b ; les autres : 1 nombre).
const CH_SUN_COLOR: int = 0
const CH_SUN_ENERGY: int = 3
const CH_SKY_TOP: int = 4
const CH_SKY_HORIZON: int = 7
const CH_GROUND_HORIZON: int = 10
const CH_GROUND_BOTTOM: int = 13
const CH_AMBIENT_COLOR: int = 16
const CH_AMBIENT_ENERGY: int = 19
const CH_FOG_COLOR: int = 20
const CH_FOG_DENSITY: int = 23
const CH_EXPOSURE: int = 24
const CH_STAR_ALPHA: int = 25
const CH_MOON_ENERGY: int = 26
const CH_SUN_GLOW: int = 27
const CHANNEL_COUNT: int = 28

const MIN_RESOLUTION: int = 24
const COLOR_FIELDS: Array[StringName] = [
	&"sun_color", &"sky_top", &"sky_horizon", &"ground_horizon", &"ground_bottom", &"ambient_color", &"fog_color"
]
const COLOR_CHANNELS: Array[int] = [
	CH_SUN_COLOR, CH_SKY_TOP, CH_SKY_HORIZON, CH_GROUND_HORIZON, CH_GROUND_BOTTOM, CH_AMBIENT_COLOR, CH_FOG_COLOR
]
const SCALAR_FIELDS: Array[StringName] = [
	&"sun_energy", &"ambient_energy", &"fog_density", &"exposure", &"star_alpha", &"moon_energy", &"sun_glow"
]
const SCALAR_CHANNELS: Array[int] = [
	CH_SUN_ENERGY, CH_AMBIENT_ENERGY, CH_FOG_DENSITY, CH_EXPOSURE, CH_STAR_ALPHA, CH_MOON_ENERGY, CH_SUN_GLOW
]

var _resolution: int = 0
var _table: PackedFloat32Array = PackedFloat32Array()
var _valid: bool = false


## Construit les courbes depuis le dictionnaire du fichier (clés « time » et « keys »).
static func from_settings(settings: Dictionary, context: String) -> DayNightCurves:
	var curves := DayNightCurves.new()
	var time: Dictionary = JsonData.get_dictionary(settings, "time", context)
	var resolution: int = JsonData.get_int(time, "resolution", context + " > time")
	var keys: Array = JsonData.get_array(settings, "keys", context)
	curves._build(keys, resolution, context + " > keys")
	return curves


func is_valid() -> bool:
	return _valid


func get_resolution() -> int:
	return _resolution


## Écrit dans « out » (taille CHANNEL_COUNT, fournie par l'appelant) les valeurs à l'heure donnée.
func sample(hours: float, out: PackedFloat32Array) -> void:
	var position: float = fposmod(hours, HOURS_PER_DAY) / HOURS_PER_DAY * float(_resolution)
	var index: int = int(position)
	var blend: float = position - float(index)
	if index >= _resolution:
		index = 0
		blend = 0.0
	var next_index: int = index + 1
	if next_index >= _resolution:
		next_index = 0
	var base_a: int = index * CHANNEL_COUNT
	var base_b: int = next_index * CHANNEL_COUNT
	for channel: int in CHANNEL_COUNT:
		var a: float = _table[base_a + channel]
		out[channel] = a + (_table[base_b + channel] - a) * blend


func _build(keys: Array, resolution: int, context: String) -> void:
	if resolution < MIN_RESOLUTION:
		push_error("DayNightCurves : « resolution » doit valoir au moins %d (%s)." % [MIN_RESOLUTION, context])
		return
	if keys.size() < 2:
		push_error("DayNightCurves : au moins deux images clés sont nécessaires (%s)." % context)
		return
	var count: int = keys.size()
	var hours := PackedFloat32Array()
	var values := PackedFloat32Array()
	hours.resize(count)
	values.resize(count * CHANNEL_COUNT)
	var previous_hour: float = -1.0
	for i: int in count:
		var key: Variant = keys[i]
		if typeof(key) != TYPE_DICTIONARY:
			push_error("DayNightCurves : l'image clé %d doit être un objet (%s)." % [i, context])
			return
		var entry: Dictionary = key
		var key_context: String = "%s[%d]" % [context, i]
		var hour: float = JsonData.get_float(entry, "hour", key_context)
		if hour <= previous_hour or hour < 0.0 or hour >= HOURS_PER_DAY:
			push_error("DayNightCurves : les heures doivent croître strictement dans [0, 24[ (%s)." % key_context)
			return
		previous_hour = hour
		hours[i] = hour
		_read_key(entry, values, i * CHANNEL_COUNT, key_context)
	_resolution = resolution
	_table.resize(resolution * CHANNEL_COUNT)
	var segment: int = count - 1
	for step: int in resolution:
		var hour: float = float(step) / float(resolution) * HOURS_PER_DAY
		# Segment contenant l'heure (le dernier relie la dernière image clé à la première, 24 h plus tard).
		while segment > 0 and hours[segment] > hour:
			segment -= 1
		while segment < count - 1 and hours[segment + 1] <= hour:
			segment += 1
		if hour < hours[0]:
			segment = count - 1
		var from_hour: float = hours[segment]
		var next_segment: int = (segment + 1) % count
		var to_hour: float = hours[next_segment]
		if next_segment <= segment:
			to_hour += HOURS_PER_DAY
		var local_hour: float = hour
		if local_hour < from_hour:
			local_hour += HOURS_PER_DAY
		var t: float = clampf((local_hour - from_hour) / (to_hour - from_hour), 0.0, 1.0)
		t = t * t * (3.0 - 2.0 * t)
		var base: int = step * CHANNEL_COUNT
		var base_a: int = segment * CHANNEL_COUNT
		var base_b: int = next_segment * CHANNEL_COUNT
		for channel: int in CHANNEL_COUNT:
			_table[base + channel] = lerpf(values[base_a + channel], values[base_b + channel], t)
	_valid = true


static func _read_key(entry: Dictionary, values: PackedFloat32Array, base: int, context: String) -> void:
	for i: int in COLOR_FIELDS.size():
		var color: Color = JsonData.get_color(entry, String(COLOR_FIELDS[i]), context)
		var channel: int = base + COLOR_CHANNELS[i]
		values[channel] = color.r
		values[channel + 1] = color.g
		values[channel + 2] = color.b
	for i: int in SCALAR_FIELDS.size():
		values[base + SCALAR_CHANNELS[i]] = JsonData.get_float(entry, String(SCALAR_FIELDS[i]), context)
