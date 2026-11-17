class_name PlayerRoute
extends RefCounted
## Parcours du joueur suivi par le pipeline (mesures et vidéos « comme un vrai joueur »).
##
## Fichier : res://data/<carte>/route_joueur.json ; format décrit dans Docs/05-technologies.md,
## section « Parcours du joueur ». Exemple :
##   {
##     "description": "…",
##     "start_position": [0.0, 0.0, 0.0],
##     "arrival_radius_m": 0.6, "stall_time_s": 2.0, "stall_min_progress_m": 0.25, "max_duration_s": 120.0,
##     "waypoints": [{"id": "fontaine", "position": [12.0, -4.0], "gait": "walk"}, …]
##   }
## La position d'un point de passage est horizontale ([x, z]) : la hauteur est celle du sol sous le joueur.
## L'allure d'un point de passage s'applique au segment qui y mène.
##
## La validation ne signale rien elle-même : parse() renvoie la liste des problèmes, load_file() les
## signale par push_error (ce qui fait échouer le pipeline). Les tests peuvent ainsi vérifier les refus.

enum Gait { WALK_SLOW, WALK, RUN }

## Noms des allures dans les données (contrat du personnage : walk_slow, walk, run).
const GAIT_NAMES: Array[String] = ["walk_slow", "walk", "run"]
const CARRIER_PLAYER: StringName = &"player"
const CARRIER_HORSE: StringName = &"horse"
const CARRIER_NAMES: Array[StringName] = [CARRIER_PLAYER, CARRIER_HORSE]
## Plus grand nombre de points de passage : la validation et le suivi restent linéaires.
const MAX_WAYPOINTS: int = 10000
## Durée maximale d'un parcours : dimensionne la mémoire des mesures (900 s à 2 000 i/s = 1,8 million d'images).
const MAX_DURATION_S: float = 900.0
const MIN_ARRIVAL_RADIUS_M: float = 0.05
const MAX_ARRIVAL_RADIUS_M: float = 20.0
const MIN_STALL_TIME_S: float = 0.1
const MAX_STALL_TIME_S: float = 60.0
const MIN_STALL_PROGRESS_M: float = 0.01
const MAX_STALL_PROGRESS_M: float = 20.0
const MAX_COORDINATE_M: float = 1000000.0

var source: String = ""
var description: String = ""
var carrier: StringName = CARRIER_PLAYER
var has_start: bool = false
var start_position: Vector3 = Vector3.ZERO
var arrival_radius: float = 0.0
var stall_time: float = 0.0
var stall_min_progress: float = 0.0
var max_duration: float = 0.0
var ids := PackedStringArray()
var points := PackedVector2Array()
var gaits := PackedInt32Array()


## Charge et valide un parcours ; renvoie null (après avoir signalé chaque problème) s'il est invalide.
static func load_file(path: String) -> PlayerRoute:
	if not FileAccess.file_exists(path):
		push_error("PlayerRoute : parcours introuvable : %s" % path)
		return null
	var json := JSON.new()
	var err: Error = json.parse(FileAccess.get_file_as_string(path))
	if err != OK:
		push_error("PlayerRoute : %s, ligne %d : %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	if typeof(json.data) != TYPE_DICTIONARY:
		push_error("PlayerRoute : la racine de %s doit être un objet JSON." % path)
		return null
	var route := PlayerRoute.new()
	var data: Dictionary = json.data
	var problems: PackedStringArray = route.parse(data, path)
	for problem: String in problems:
		push_error("PlayerRoute : %s" % problem)
	return null if not problems.is_empty() else route


## Remplit le parcours depuis des données JSON et renvoie la liste des problèmes (vide si tout est valide).
func parse(data: Dictionary, context: String) -> PackedStringArray:
	var problems := PackedStringArray()
	source = context
	description = _read_string(data, "description", context, problems)
	carrier = StringName(str(data.get("carrier", CARRIER_PLAYER)))
	if not CARRIER_NAMES.has(carrier):
		problems.append("« carrier » doit valoir player ou horse (%s)." % context)
		carrier = CARRIER_PLAYER
	has_start = data.has("start_position")
	if has_start:
		start_position = _read_vector3(data, "start_position", context, problems)
	arrival_radius = _read_number(data, "arrival_radius_m", MIN_ARRIVAL_RADIUS_M, MAX_ARRIVAL_RADIUS_M, context, problems)
	stall_time = _read_number(data, "stall_time_s", MIN_STALL_TIME_S, MAX_STALL_TIME_S, context, problems)
	stall_min_progress = _read_number(data, "stall_min_progress_m", MIN_STALL_PROGRESS_M, MAX_STALL_PROGRESS_M, context, problems)
	max_duration = _read_number(data, "max_duration_s", MIN_STALL_TIME_S, MAX_DURATION_S, context, problems)
	ids.clear()
	points.clear()
	gaits.clear()
	if not data.has("waypoints") or typeof(data["waypoints"]) != TYPE_ARRAY:
		problems.append("« waypoints » doit être un tableau (%s)." % context)
		return problems
	var raw_waypoints: Array = data["waypoints"]
	if raw_waypoints.is_empty() or raw_waypoints.size() > MAX_WAYPOINTS:
		problems.append("« waypoints » doit contenir de 1 à %d points (%d trouvés, %s)." % [MAX_WAYPOINTS, raw_waypoints.size(), context])
		return problems
	ids.resize(raw_waypoints.size())
	points.resize(raw_waypoints.size())
	gaits.resize(raw_waypoints.size())
	var seen: Dictionary[String, bool] = {}
	for i: int in raw_waypoints.size():
		var raw: Variant = raw_waypoints[i]
		var where: String = "point de passage n° %d de %s" % [i + 1, context]
		if typeof(raw) != TYPE_DICTIONARY:
			problems.append("le %s doit être un objet." % where)
			continue
		var entry: Dictionary = raw
		var waypoint_id: String = _read_string(entry, "id", where, problems)
		if waypoint_id.is_empty() or waypoint_id.validate_filename() != waypoint_id or seen.has(waypoint_id):
			problems.append("identifiant absent, invalide ou en double « %s » (%s)." % [waypoint_id, where])
		seen[waypoint_id] = true
		ids[i] = waypoint_id
		points[i] = _read_vector2(entry, "position", where, problems)
		var gait_name: String = _read_string(entry, "gait", where, problems)
		var gait: int = GAIT_NAMES.find(gait_name)
		if gait < 0:
			problems.append("allure inconnue « %s » (walk_slow, walk ou run attendu, %s)." % [gait_name, where])
			gait = Gait.WALK
		gaits[i] = gait
	return problems


## Vrai si au moins un segment du parcours se fait à cette allure.
func uses_gait(gait: Gait) -> bool:
	return gaits.has(gait)


## Longueur horizontale du parcours (depuis la position de départ si elle est donnée).
func get_length() -> float:
	var length: float = 0.0
	var previous: Vector2 = Vector2(start_position.x, start_position.z) if has_start else points[0]
	for point: Vector2 in points:
		length += previous.distance_to(point)
		previous = point
	return length


static func _read_string(data: Dictionary, key: String, context: String, problems: PackedStringArray) -> String:
	if not data.has(key) or typeof(data[key]) != TYPE_STRING:
		problems.append("« %s » doit être une chaîne (%s)." % [key, context])
		return ""
	return data[key]


static func _read_number(
	data: Dictionary, key: String, min_value: float, max_value: float, context: String, problems: PackedStringArray
) -> float:
	if not data.has(key) or (typeof(data[key]) != TYPE_FLOAT and typeof(data[key]) != TYPE_INT):
		problems.append("« %s » doit être un nombre (%s)." % [key, context])
		return min_value
	var value: float = float(data[key])
	if not (value >= min_value and value <= max_value):
		problems.append("« %s » = %s doit être compris entre %s et %s (%s)." % [key, str(value), str(min_value), str(max_value), context])
		return clampf(value, min_value, max_value) if is_finite(value) else min_value
	return value


static func _read_numbers(data: Dictionary, key: String, count: int, context: String, problems: PackedStringArray) -> PackedFloat64Array:
	var numbers := PackedFloat64Array()
	if not data.has(key) or typeof(data[key]) != TYPE_ARRAY or (data[key] as Array).size() != count:
		problems.append("« %s » doit être un tableau de %d nombres (%s)." % [key, count, context])
		return numbers
	var values: Array = data[key]
	numbers.resize(count)
	for i: int in count:
		var value: Variant = values[i]
		if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
			problems.append("« %s » doit contenir uniquement des nombres (%s)." % [key, context])
			return PackedFloat64Array()
		var number: float = float(value)
		if not (absf(number) <= MAX_COORDINATE_M):
			problems.append("« %s » contient une coordonnée hors limites : %s (%s)." % [key, str(number), context])
			return PackedFloat64Array()
		numbers[i] = number
	return numbers


static func _read_vector2(data: Dictionary, key: String, context: String, problems: PackedStringArray) -> Vector2:
	var numbers: PackedFloat64Array = _read_numbers(data, key, 2, context, problems)
	return Vector2.ZERO if numbers.is_empty() else Vector2(numbers[0], numbers[1])


static func _read_vector3(data: Dictionary, key: String, context: String, problems: PackedStringArray) -> Vector3:
	var numbers: PackedFloat64Array = _read_numbers(data, key, 3, context, problems)
	return Vector3.ZERO if numbers.is_empty() else Vector3(numbers[0], numbers[1], numbers[2])
