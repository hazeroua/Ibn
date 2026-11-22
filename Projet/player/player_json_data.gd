class_name PlayerJsonData
extends RefCounted
## Accesseurs JSON du personnage repris de la première version du jeu (Game/core/data/json_data.gd),
## gardés tels quels pour que le code copié du personnage reste identique à l'original.
## Le chargement des fichiers passe par JsonData.load_dictionary du socle.
##
## Toute donnée absente ou mal typée est signalée par push_error, ce qui fait échouer le pipeline
## (Projet/outils/valider.ps1 refuse toute sortie de Godot contenant « ERROR: »).
## Les accesseurs renvoient alors une valeur neutre pour que l'appelant puisse continuer à
## signaler les autres erreurs du même fichier en une seule passe.


static func get_dictionary(data: Dictionary, key: String, context: String) -> Dictionary:
	var value: Variant = _require(data, key, TYPE_DICTIONARY, "un objet", context)
	if value == null:
		return {}
	return value


static func get_array(data: Dictionary, key: String, context: String) -> Array:
	var value: Variant = _require(data, key, TYPE_ARRAY, "un tableau", context)
	if value == null:
		return []
	return value


static func get_string(data: Dictionary, key: String, context: String) -> String:
	var value: Variant = _require(data, key, TYPE_STRING, "une chaîne", context)
	if value == null:
		return ""
	return value


static func get_bool(data: Dictionary, key: String, context: String) -> bool:
	var value: Variant = _require(data, key, TYPE_BOOL, "un booléen", context)
	if value == null:
		return false
	return value


static func get_float(data: Dictionary, key: String, context: String) -> float:
	if not data.has(key):
		push_error("PlayerJsonData : clé « %s » manquante (%s)." % [key, context])
		return 0.0
	var value: Variant = data[key]
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		push_error("PlayerJsonData : « %s » doit être un nombre (%s)." % [key, context])
		return 0.0
	return float(value)


static func get_float_or(data: Dictionary, key: String, default_value: float, context: String) -> float:
	if not data.has(key):
		return default_value
	return get_float(data, key, context)


static func get_int(data: Dictionary, key: String, context: String) -> int:
	var number: float = get_float(data, key, context)
	if not is_equal_approx(number, roundf(number)):
		push_error("PlayerJsonData : « %s » doit être un entier (%s)." % [key, context])
	return int(roundf(number))


static func get_vector2(data: Dictionary, key: String, context: String) -> Vector2:
	var numbers: PackedFloat64Array = _get_numbers(data, key, 2, context)
	if numbers.is_empty():
		return Vector2.ZERO
	return Vector2(numbers[0], numbers[1])


static func get_vector3(data: Dictionary, key: String, context: String) -> Vector3:
	var numbers: PackedFloat64Array = _get_numbers(data, key, 3, context)
	if numbers.is_empty():
		return Vector3.ZERO
	return Vector3(numbers[0], numbers[1], numbers[2])


static func get_vector3_or(data: Dictionary, key: String, default_value: Vector3, context: String) -> Vector3:
	if not data.has(key):
		return default_value
	return get_vector3(data, key, context)


## Couleur au format hexadécimal « #rrggbb » ou « #rrggbbaa ».
static func get_color(data: Dictionary, key: String, context: String) -> Color:
	var text: String = get_string(data, key, context)
	if text.is_empty():
		return Color.MAGENTA
	if not Color.html_is_valid(text):
		push_error("PlayerJsonData : « %s » n'est pas une couleur valide : %s (%s)." % [key, text, context])
		return Color.MAGENTA
	return Color.html(text)


static func _require(data: Dictionary, key: String, type: Variant.Type, type_name: String, context: String) -> Variant:
	if not data.has(key):
		push_error("PlayerJsonData : clé « %s » manquante (%s)." % [key, context])
		return null
	var value: Variant = data[key]
	if typeof(value) != type:
		push_error("PlayerJsonData : « %s » doit être %s (%s)." % [key, type_name, context])
		return null
	return value


static func _get_numbers(data: Dictionary, key: String, count: int, context: String) -> PackedFloat64Array:
	var values: Array = get_array(data, key, context)
	var numbers := PackedFloat64Array()
	if values.size() != count:
		if data.has(key):
			push_error("PlayerJsonData : « %s » doit contenir %d nombres (%s)." % [key, count, context])
		return numbers
	numbers.resize(count)
	for i: int in count:
		var value: Variant = values[i]
		if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
			push_error("PlayerJsonData : « %s » doit contenir uniquement des nombres (%s)." % [key, context])
			return PackedFloat64Array()
		numbers[i] = float(value)
	return numbers
