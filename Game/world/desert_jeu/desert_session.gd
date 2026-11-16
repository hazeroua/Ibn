class_name DesertSession
extends Node3D
## Racine du jeu du MVP 2 : désert de 4 × 4 km diffusé par cellules (WorldStreamer), végétation, oasis, cycle
## jour/nuit, vent, saisons, panneau de temps (F2), joueur, caméra et sons de pas. Assemblage au chargement ;
## ensuite seul le streaming travaille (le joueur lui donne sa position et sa vitesse à chaque tick physique).

const DATA_PATH: String = "res://data/desert/desert.json"
const STREAMING_PATH: String = "res://data/streaming/streaming.json"
const VEGETATION_PATH: String = "res://data/desert/vegetation.json"
const GROUND_COVER_PATH: String = "res://data/desert/ground_cover.json"
const TIME_PANEL_SCENE: String = "res://ui/time_panel/time_panel.tscn"
const SPAWN_WAIT_FRAMES_MAX: int = 1800

var _streamer: WorldStreamer
## Gardé ici : le streaming l'appelle depuis des fils de fond pendant toute la partie.
var _provider: DesertCellProvider
## Interrogation du couvert du sol branchée sur les pas : gardée ici (Footsteps ne retient que la méthode).
var _ground_cover: GroundCoverQuery
var _player: PlayerCharacter
var _rig: ThirdPersonCamera


func _ready() -> void:
	var data: Dictionary = JsonData.load_dictionary(DATA_PATH)
	var field: DesertHeightfield = DesertHeightfield.from_data(data)
	var terrain: DesertTerrainCell = DesertTerrainCell.from_data(data)
	var foliage: Dictionary = DesertFoliageMeshes.load_settings()
	var meshes: Dictionary = DesertFoliageMeshes.build_levels(foliage)
	if data.is_empty() or field == null or terrain == null or meshes.is_empty():
		return
	var scatter := VegetationScatter.new()
	if not scatter.load_rules(VEGETATION_PATH) or not scatter.load_features(DATA_PATH):
		push_error("DesertSession : règles de végétation invalides : %s" % scatter.get_last_error())
		return
	_provider = DesertCellProvider.new(
		terrain,
		field,
		scatter,
		meshes,
		foliage,
		JsonData.get_int(JsonData.get_dictionary(data, "terrain", "desert.json"), "seed", "desert.json > terrain"),
		JsonData.load_dictionary(GROUND_COVER_PATH)
	)
	_streamer = WorldStreamer.new()
	_streamer.name = "Streaming"
	if not _streamer.load_config(STREAMING_PATH):
		return
	_streamer.register_provider(_provider)
	add_child(_streamer)
	_ground_cover = GroundCoverQuery.new(_streamer)
	(get_node("/root/Footsteps") as FootstepSystem).set_ground_cover(_ground_cover.nearest_cover_distance_squared)
	var day_night: DayNightSystem = get_node("/root/DayNight") as DayNightSystem
	add_child(day_night.build_environment())
	_add_water(field)
	var panel: PackedScene = load(TIME_PANEL_SCENE) as PackedScene
	if panel != null:
		add_child(panel.instantiate())
	var spawn: Dictionary = JsonData.get_dictionary(data, "player_spawn", "desert.json")
	var ground: Vector2 = JsonData.get_vector2(spawn, "position", "desert.json > player_spawn")
	var position := Vector3(ground.x, field.height_at(ground.x, ground.y) + float(spawn.get("height_offset_m", 0.05)), ground.y)
	_streamer.set_focus(position, Vector3.ZERO)
	await _wait_for_cell(_streamer.world_to_cell(position))
	var yaw: float = deg_to_rad(float(spawn.get("yaw_degrees", 0.0)))
	_player = GameSession.spawn_player(self, position, yaw, "ibn_khaldoun_jeune")
	_rig = GameSession.attach_camera(self, _player)


func _physics_process(_delta: float) -> void:
	if _player != null:
		_streamer.set_focus(_player.global_position, _player.velocity)


## Un disque d'eau par plan d'eau de type « oasis » (les autres types sont rendus par leurs propres systèmes).
func _add_water(field: DesertHeightfield) -> void:
	var features: LandscapeFeatures = field.features
	for index: int in features.water_count:
		if features.water_kind(index) != &"oasis":
			continue
		var center: Vector2 = features.water_center(index)
		var water: Node3D = OasisWater.build(center, features.water_radius(index))
		water.position = Vector3(center.x, field.height_at(center.x, center.y), center.y)
		add_child(water)


func _wait_for_cell(cell: Vector2i) -> void:
	var frames: int = 0
	while not _streamer.is_cell_loaded(cell) and frames < SPAWN_WAIT_FRAMES_MAX:
		await get_tree().process_frame
		frames += 1
	if not _streamer.is_cell_loaded(cell):
		push_error("DesertSession : la cellule de départ %s n'a pas été chargée." % cell)
