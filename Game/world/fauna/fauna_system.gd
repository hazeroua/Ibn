class_name FaunaSystem
extends Node3D
## Faune d'ambiance du désert, sans interaction de jeu : vols d'oiseaux (FaunaBirds), gazelles (FaunaGazelles, C++),
## libellules (FaunaDragonflies) et sons par heure (FaunaAmbience). Réglages : res://data/desert/fauna.json.
##
## Pires cas : 200 animaux visibles au plus (réglage budget.max_animals, vérifié au démarrage : oiseaux + gazelles
## + libellules) ; 100 h de jeu sans fuite ni dérive (aucun nœud, ressource ni tableau créé après le démarrage ;
## troupeaux bornés par leur zone) ; joueur au galop au milieu d'un troupeau (la simulation des gazelles est bornée
## par la taille des troupeaux). Un seul _process pour tout le système ; l'heure vient du signal time_changed.

const SETTINGS_PATH: String = "res://data/desert/fauna.json"
const CONTEXT: String = "fauna.json"
const WORLD_AABB_HEIGHT_M: float = 800.0
const WORLD_AABB_FLOOR_M: float = -100.0

var _birds: FaunaBirds = null
var _gazelles: FaunaGazelles = null
var _dragonflies: FaunaDragonflies = null
var _ambience: FaunaAmbience = null
var _hour: float = 12.0
var _focus: Vector3 = Vector3.ZERO
var _velocity: Vector3 = Vector3.ZERO


## Construit la faune. data : contenu de desert.json ; day_night : le système de jour et nuit (propriété time_of_day,
## signal time_changed). Renvoie null (avec erreur) si une donnée est invalide.
static func create(data: Dictionary, field: DesertHeightfield, day_night: Node, settings_path: String = SETTINGS_PATH) -> FaunaSystem:
	var settings: Dictionary = JsonData.load_dictionary(settings_path)
	if settings.is_empty() or field == null or day_night == null:
		return null
	var system := FaunaSystem.new()
	system.name = "Fauna"
	if not system._build(settings, data, field, day_night):
		system.free()
		return null
	return system


## Position et vitesse du joueur (mètres du monde) : à fournir à chaque tick physique.
func set_focus(position: Vector3, velocity: Vector3) -> void:
	_focus = position
	_velocity = velocity


## Gazelles (pour les tests et les captures).
func get_gazelles() -> FaunaGazelles:
	return _gazelles


## Oiseaux (pour les tests et les captures).
func get_birds() -> FaunaBirds:
	return _birds


## Libellules (pour les tests et les captures).
func get_dragonflies() -> FaunaDragonflies:
	return _dragonflies


## Ambiance sonore (pour les tests et les captures).
func get_ambience() -> FaunaAmbience:
	return _ambience


func _process(delta: float) -> void:
	_birds.update(delta, _hour, _focus)
	_gazelles.update(delta, _focus)
	_ambience.poll()


func _on_time_changed(hours: float) -> void:
	_hour = hours
	_dragonflies.apply_hour(hours)
	_ambience.apply_hour(hours)


func _build(settings: Dictionary, data: Dictionary, field: DesertHeightfield, day_night: Node) -> bool:
	var waters: Array[Dictionary] = FaunaWater.load_bodies(data, field)
	if waters.is_empty():
		push_error("FaunaSystem : aucun plan d'eau dans desert.json (ancrage de la faune).")
		return false
	_hour = float(day_night.get(&"time_of_day"))
	var half: float = field.half_extent
	var world_box := AABB(Vector3(-half, WORLD_AABB_FLOOR_M, -half), Vector3(half * 2.0, WORLD_AABB_HEIGHT_M, half * 2.0))
	var gazelle_settings: Dictionary = JsonData.get_dictionary(settings, "gazelles", CONTEXT)
	_birds = FaunaBirds.new()
	if not _birds.build(JsonData.get_dictionary(settings, "birds", CONTEXT), field, waters, _hour, world_box):
		return false
	add_child(_birds)
	_dragonflies = FaunaDragonflies.new()
	if not _dragonflies.build(JsonData.get_dictionary(settings, "dragonflies", CONTEXT), waters, _hour, world_box):
		return false
	add_child(_dragonflies)
	var gazelle_total: int = _gazelle_capacity(gazelle_settings)
	var budget: int = JsonData.get_int(JsonData.get_dictionary(settings, "budget", CONTEXT), "max_animals", CONTEXT + " > budget")
	var total: int = _birds.get_bird_count() + _dragonflies.get_dragonfly_count() + gazelle_total
	if total > budget:
		push_error("FaunaSystem : %d animaux pour un budget de %d (%s)." % [total, budget, CONTEXT])
		return false
	_gazelles = FaunaGazelles.new()
	var world_seed: int = JsonData.get_int(JsonData.get_dictionary(data, "terrain", "desert.json"), "seed", "desert.json > terrain")
	if not _gazelles.build(gazelle_settings, field, world_seed):
		return false
	add_child(_gazelles)
	_ambience = FaunaAmbience.new()
	var bus: Dictionary = JsonData.get_dictionary(settings, "bus", CONTEXT)
	for key: String in ["name", "send"]:
		JsonData.get_string(bus, key, CONTEXT + " > bus")
	JsonData.get_float(bus, "volume_db", CONTEXT + " > bus")
	if not _ambience.build(JsonData.get_dictionary(settings, "ambience", CONTEXT), bus, waters, _hour):
		return false
	add_child(_ambience)
	day_night.connect(&"time_changed", _on_time_changed)
	# Les fils de travail ne partent qu'une fois toutes les données validées.
	_gazelles.begin()
	_ambience.begin()
	return true


## Nombre maximal de gazelles : somme, par zone, des troupeaux × taille maximale.
static func _gazelle_capacity(gazelle_settings: Dictionary) -> int:
	var total: int = 0
	for zone: Variant in JsonData.get_array(gazelle_settings, "zones", CONTEXT + " > gazelles"):
		var entry: Dictionary = zone
		total += (
			JsonData.get_int(entry, "herds", CONTEXT + " > gazelles > zones")
			* JsonData.get_int(entry, "size_max", CONTEXT + " > gazelles > zones")
		)
	return total
