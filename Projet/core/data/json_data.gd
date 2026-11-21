class_name JsonData
extends RefCounted
## Lecture des fichiers de données JSON du dossier data/.


## Résultat d'une analyse : `data` est vide et `error` renseigné en cas d'échec.
class ParseResult:
	extends RefCounted
	var data: Dictionary = {}
	var error: String = ""


## Analyse un texte JSON dont la racine doit être un objet.
static func parse_text(text: String, source: String) -> ParseResult:
	var result: ParseResult = ParseResult.new()
	var parser: JSON = JSON.new()
	var parse_error: Error = parser.parse(text)
	if parse_error != OK:
		result.error = "%s, ligne %d : %s" % [source, parser.get_error_line(), parser.get_error_message()]
		return result
	if typeof(parser.data) != TYPE_DICTIONARY:
		result.error = "%s : la racine doit être un objet JSON." % source
		return result
	result.data = parser.data
	return result


## Charge un fichier JSON. Toute erreur est journalisée et fait échouer la validation.
static func load_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		GameLog.error("données", "Fichier absent : " + path)
		return {}
	var result: ParseResult = parse_text(FileAccess.get_file_as_string(path), path)
	if not result.error.is_empty():
		GameLog.error("données", result.error)
	return result.data


## Lit un nombre ; ajoute une erreur à `errors` s'il manque ou n'est pas numérique.
static func read_number(data: Dictionary, key: String, errors: PackedStringArray, context: String) -> float:
	var value: Variant = data.get(key)
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		errors.append("%s : « %s » doit être un nombre." % [context, key])
		return 0.0
	return float(value)


## Lit un texte non vide ; ajoute une erreur à `errors` sinon.
static func read_string(data: Dictionary, key: String, errors: PackedStringArray, context: String) -> String:
	var value: Variant = data.get(key)
	if typeof(value) != TYPE_STRING or String(value).is_empty():
		errors.append("%s : « %s » doit être un texte non vide." % [context, key])
		return ""
	return String(value)


## Lit un objet ; ajoute une erreur à `errors` s'il manque.
static func read_dictionary(data: Dictionary, key: String, errors: PackedStringArray, context: String) -> Dictionary:
	var value: Variant = data.get(key)
	if typeof(value) != TYPE_DICTIONARY:
		errors.append("%s : « %s » doit être un objet." % [context, key])
		return {}
	return value


## Lit un vecteur de trois nombres ; ajoute une erreur à `errors` sinon.
static func read_vector3(data: Dictionary, key: String, errors: PackedStringArray, context: String) -> Vector3:
	var value: Variant = data.get(key)
	if typeof(value) != TYPE_ARRAY or (value as Array).size() != 3:
		errors.append("%s : « %s » doit être une liste de trois nombres." % [context, key])
		return Vector3.ZERO
	var items: Array = value
	for item: Variant in items:
		if typeof(item) != TYPE_FLOAT and typeof(item) != TYPE_INT:
			errors.append("%s : « %s » doit être une liste de trois nombres." % [context, key])
			return Vector3.ZERO
	return Vector3(float(items[0]), float(items[1]), float(items[2]))


## Lit une couleur hexadécimale (« #rrggbb ») ; ajoute une erreur à `errors` sinon.
static func read_color(data: Dictionary, key: String, errors: PackedStringArray, context: String) -> Color:
	var text: String = read_string(data, key, errors, context)
	if text.is_empty():
		return Color.BLACK
	if not Color.html_is_valid(text):
		errors.append("%s : « %s » doit être une couleur hexadécimale." % [context, key])
		return Color.BLACK
	return Color.html(text)
