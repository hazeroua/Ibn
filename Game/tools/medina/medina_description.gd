class_name MedinaDescription
extends RefCounted
## Description validée de la médina (Game/data/tunis/generation/medina.json) et tirages déterministes.
##
## Toutes les longueurs sont converties en centimètres entiers dès la lecture : la géométrie de la
## médina ne fait ensuite que des additions et des comparaisons d'entiers, ce qui rend le résultat
## identique d'une machine à l'autre. Chaque tirage aléatoire passe par un flux nommé (graine de la
## ville + nom du flux, haché en FNV-1a 32 bits) : changer un paramètre ne modifie que les éléments
## qui dépendent de ce flux.
##
## Une spécification de valeur est un objet portant « limits » (bornes dures) et soit « range »
## (intervalle de tirage, inclus dans les bornes), soit « value » (valeur fixe dans les bornes).
## Les clés terminées par « _m » sont des longueurs, qui doivent être des multiples de grid_step_m.

const SCHEMA_VERSION: int = 1
const CM_PER_M: float = 100.0
const FRACTION_STEPS: int = 100
const FNV_OFFSET: int = 2166136261
const FNV_PRIME: int = 16777619
const MASK_32: int = 0xFFFFFFFF
const LENGTH_SUFFIX: String = "_m"
const FLOAT_EPSILON: float = 0.000001
## Tolérance (cm) d'arrondi au pas de grille : les paires de bornes sont lues en simple précision.
const CM_TOLERANCE: float = 0.001

var data: Dictionary = {}
var seed_value: int = 0
var grid_cm: int = 0
var errors: PackedStringArray = PackedStringArray()


static func create(description: Dictionary, city_seed: int) -> MedinaDescription:
	var result := MedinaDescription.new()
	result.data = description
	result.seed_value = city_seed
	result._validate()
	return result


static func fnv1a(text: String) -> int:
	var hash_value: int = FNV_OFFSET
	for byte: int in text.to_utf8_buffer():
		hash_value = ((hash_value ^ byte) * FNV_PRIME) & MASK_32
	return hash_value


static func m_to_cm(value: float) -> int:
	return roundi(value * CM_PER_M)


static func cm_to_m(value: int) -> float:
	return float(value) / CM_PER_M


func is_valid() -> bool:
	return errors.is_empty()


func section(key: String) -> Dictionary:
	var value: Variant = data.get(key)
	if typeof(value) != TYPE_DICTIONARY:
		errors.append("medina.%s doit être un objet." % key)
		return {}
	return value


func ways() -> Array:
	var value: Variant = data.get("ways")
	if typeof(value) != TYPE_ARRAY:
		errors.append("medina.ways doit être une liste.")
		return []
	return value


func rng(stream: String) -> RandomNumberGenerator:
	var generator := RandomNumberGenerator.new()
	generator.seed = fnv1a("%d:%s" % [seed_value, stream])
	return generator


## Longueur (cm) d'une spécification « range » tirée dans le flux, ou « value » fixe.
func draw_cm(spec: Variant, stream: String, context: String) -> int:
	if typeof(spec) != TYPE_DICTIONARY:
		errors.append("%s doit être une spécification de valeur." % context)
		return 0
	var dictionary: Dictionary = spec
	if dictionary.has("value"):
		return m_to_cm(float(dictionary["value"]))
	var bounds: Vector2 = _pair(dictionary, "range", context)
	var low: int = m_to_cm(bounds.x)
	var high: int = m_to_cm(bounds.y)
	var steps: int = (high - low) / grid_cm
	return low + rng(stream).randi_range(0, steps) * grid_cm


## Fraction (au centième) d'une spécification « range ».
func draw_fraction(spec: Variant, stream: String, context: String) -> float:
	if typeof(spec) != TYPE_DICTIONARY:
		errors.append("%s doit être une spécification de valeur." % context)
		return 0.0
	var bounds: Vector2 = _pair(spec, "range", context)
	var low: int = roundi(bounds.x * FRACTION_STEPS)
	var high: int = roundi(bounds.y * FRACTION_STEPS)
	return float(rng(stream).randi_range(low, high)) / float(FRACTION_STEPS)


## Entier tiré dans « range ».
func draw_int(spec: Variant, stream: String, context: String) -> int:
	if typeof(spec) != TYPE_DICTIONARY:
		errors.append("%s doit être une spécification de valeur." % context)
		return 0
	var bounds: Vector2 = _pair(spec, "range", context)
	return rng(stream).randi_range(roundi(bounds.x), roundi(bounds.y))


## Nombre tiré dans « range » par pas « step » (au moins « minimum ») avec le générateur fourni.
func draw_stepped(spec: Variant, step: float, minimum: float, generator: RandomNumberGenerator, context: String) -> float:
	var bounds: Vector2 = _pair(spec, "range", context)
	var low: int = maxi(ceili(bounds.x / step - FLOAT_EPSILON), ceili(minimum / step - FLOAT_EPSILON))
	var high: int = floori(bounds.y / step + FLOAT_EPSILON)
	if low > high:
		errors.append("%s : aucune valeur de %s ne dépasse le minimum exigé %.3f." % [context, bounds, minimum])
		return bounds.y
	return float(generator.randi_range(low, high)) * step


func parameter(name: String) -> Variant:
	var parameters: Dictionary = section("parameters")
	if not parameters.has(name) or typeof(parameters[name]) != TYPE_DICTIONARY:
		errors.append("medina.parameters.%s est requis." % name)
		return null
	return parameters[name]


func parameter_value(name: String) -> Variant:
	var spec: Variant = parameter(name)
	if spec == null:
		return null
	if not (spec as Dictionary).has("value"):
		errors.append("medina.parameters.%s.value est requis." % name)
		return null
	return (spec as Dictionary)["value"]


func parameter_float(name: String) -> float:
	var value: Variant = parameter_value(name)
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		errors.append("medina.parameters.%s.value doit être un nombre." % name)
		return 0.0
	return float(value)


func parameter_cm(name: String) -> int:
	return m_to_cm(parameter_float(name))


func parameter_pair(name: String) -> Vector2:
	return _pair(parameter(name), "value", "medina.parameters." + name)


func metric(prefab_id: String, key: String) -> float:
	var metrics: Dictionary = section("prefab_metrics")
	var entry: Variant = metrics.get(prefab_id)
	if typeof(entry) != TYPE_DICTIONARY or not (entry as Dictionary).has(key):
		errors.append("medina.prefab_metrics.%s.%s est requis." % [prefab_id, key])
		return 0.0
	return float((entry as Dictionary)[key])


func metric_cm(prefab_id: String, key: String) -> int:
	return m_to_cm(metric(prefab_id, key))


func _pair(spec: Variant, key: String, context: String) -> Vector2:
	if typeof(spec) != TYPE_DICTIONARY:
		errors.append("%s doit être un objet." % context)
		return Vector2.ZERO
	var value: Variant = (spec as Dictionary).get(key)
	if typeof(value) != TYPE_ARRAY or (value as Array).size() != 2:
		errors.append("%s.%s doit contenir deux nombres." % [context, key])
		return Vector2.ZERO
	var values: Array = value
	for entry: Variant in values:
		if typeof(entry) != TYPE_FLOAT and typeof(entry) != TYPE_INT:
			errors.append("%s.%s doit contenir deux nombres." % [context, key])
			return Vector2.ZERO
	return Vector2(float(values[0]), float(values[1]))


func _validate() -> void:
	if int(data.get("schema_version", -1)) != SCHEMA_VERSION:
		errors.append("medina.schema_version doit valoir %d." % SCHEMA_VERSION)
	var step: Variant = data.get("grid_step_m")
	var step_is_number: bool = typeof(step) == TYPE_FLOAT or typeof(step) == TYPE_INT
	if not step_is_number or float(step) <= 0.0:
		errors.append("medina.grid_step_m doit être un nombre positif.")
		grid_cm = 1
	else:
		grid_cm = m_to_cm(float(step))
		if grid_cm <= 0 or absf(float(step) * CM_PER_M - float(grid_cm)) > FLOAT_EPSILON:
			errors.append("medina.grid_step_m doit être un nombre entier de centimètres.")
			grid_cm = maxi(grid_cm, 1)
	_validate_node(data, "medina", "")
	var enclosure: Dictionary = section("enclosure")
	for key: String in ["min_x_m", "max_x_m", "min_z_m", "max_z_m"]:
		var value: Variant = enclosure.get(key)
		if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
			errors.append("medina.enclosure.%s doit être un nombre." % key)
		else:
			_check_grid(float(value), "medina.enclosure." + key)


## Parcourt tout le document : chaque objet qui porte « limits » est une spécification de valeur.
func _validate_node(node: Variant, context: String, key: String) -> void:
	match typeof(node):
		TYPE_DICTIONARY:
			var dictionary: Dictionary = node
			if dictionary.has("limits"):
				_validate_spec(dictionary, context, key.ends_with(LENGTH_SUFFIX))
				return
			var keys: Array = dictionary.keys()
			keys.sort()
			for child_key: Variant in keys:
				_validate_node(dictionary[child_key], context + "." + String(child_key), String(child_key))
		TYPE_ARRAY:
			var array: Array = node
			for index: int in array.size():
				_validate_node(array[index], "%s[%d]" % [context, index], key)


func _validate_spec(spec: Dictionary, context: String, is_length: bool) -> void:
	var limits_value: Variant = spec.get("limits")
	if typeof(limits_value) != TYPE_ARRAY or (limits_value as Array).size() != 2:
		errors.append("%s.limits doit contenir deux nombres." % context)
		return
	var limits: Vector2 = _pair(spec, "limits", context)
	if limits.x > limits.y:
		errors.append("%s.limits : la borne basse dépasse la borne haute." % context)
	var has_range: bool = spec.has("range")
	var has_value: bool = spec.has("value")
	if has_range == has_value:
		errors.append("%s doit porter exactement une clé « range » ou « value »." % context)
		return
	if has_range:
		var bounds: Vector2 = _pair(spec, "range", context)
		if bounds.x > bounds.y:
			errors.append("%s.range : la borne basse dépasse la borne haute." % context)
		if bounds.x < limits.x - FLOAT_EPSILON or bounds.y > limits.y + FLOAT_EPSILON:
			errors.append("%s.range %s sort des bornes %s." % [context, bounds, limits])
		if is_length:
			_check_grid(bounds.x, context + ".range")
			_check_grid(bounds.y, context + ".range")
		return
	var value: Variant = spec["value"]
	var numbers: Array = []
	if typeof(value) == TYPE_ARRAY:
		numbers = value
	else:
		numbers = [value]
	for entry: Variant in numbers:
		if typeof(entry) != TYPE_FLOAT and typeof(entry) != TYPE_INT:
			errors.append("%s.value doit être numérique." % context)
			continue
		if float(entry) < limits.x - FLOAT_EPSILON or float(entry) > limits.y + FLOAT_EPSILON:
			errors.append("%s.value %s sort des bornes %s." % [context, entry, limits])
		if is_length:
			_check_grid(float(entry), context + ".value")


func _check_grid(value_m: float, context: String) -> void:
	var cm: float = value_m * CM_PER_M
	if absf(cm - roundf(cm)) > CM_TOLERANCE or roundi(cm) % grid_cm != 0:
		errors.append("%s (%.3f m) doit être un multiple de grid_step_m." % [context, value_m])
