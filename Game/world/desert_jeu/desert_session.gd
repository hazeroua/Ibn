class_name DesertSession
extends Node3D
## Racine du jeu du MVP 2 : désert de 4 × 4 km diffusé par cellules (WorldStreamer), végétation, oasis, cycle
## jour/nuit, vent, saisons, panneau de temps (F2), joueur, caméra et sons de pas. Assemblage au chargement ;
## ensuite seul le streaming travaille (le joueur lui donne sa position et sa vitesse à chaque tick physique).

const DATA_PATH: String = "res://data/desert/desert.json"
const STREAMING_PATH: String = "res://data/streaming/streaming.json"
const VEGETATION_PATH: String = "res://data/desert/vegetation.json"
const TIME_PANEL_SCENE: String = "res://ui/time_panel/time_panel.tscn"
const SPAWN_WAIT_FRAMES_MAX: int = 1800

var _streamer: WorldStreamer
## Gardé ici : le streaming l'appelle depuis des fils de fond pendant toute la partie.
var _provider: DesertCellProvider
var _player: PlayerCharacter
var _rig: ThirdPersonCamera


func _ready() -> void:
	var data: Dictionary = JsonData.load_dictionary(DATA_PATH)
	var field: DesertHeightfield = DesertHeightfield.from_data(data)
	var terrain: DesertTerrainCell = DesertTerrainCell.from_data(data)
	var foliage: Dictionary = DesertFoliageMeshes.load_settings()
	var meshes: Dictionary = DesertFoliageMeshes.build(foliage)
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
		JsonData.get_int(JsonData.get_dictionary(data, "terrain", "desert.json"), "seed", "desert.json > terrain")
	)
	_streamer = WorldStreamer.new()
	_streamer.name = "Streaming"
	if not _streamer.load_config(STREAMING_PATH):
		return
	_streamer.register_provider(_provider)
	add_child(_streamer)
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
	var wading := WaterWading.new()
	wading.name = "WaterWading"
	wading.setup(_player, field)
	add_child(wading)


func _physics_process(_delta: float) -> void:
	if _player != null:
		_streamer.set_focus(_player.global_position, _player.velocity)


## Un plan d'eau par entrée de water_bodies (oasis, lac, guelta, chott), avec sa limite invisible quand il est plus
## profond que le gué, et l'ambiance commune (midi du mirage).
func _add_water(field: DesertHeightfield) -> void:
	var features: LandscapeFeatures = field.features
	var max_depth: float = LocomotionSettings.load_file().wading_max_depth
	var ids: Array[StringName] = features.water_ids()
	for index: int in features.water_count:
		var spec: Dictionary = {
			"id": String(ids[index]),
			"kind": String(features.water_kind(index)),
			"center": features.water_center(index),
			"radius_m": features.water_radius(index),
			"surface_height_m": features.water_surface(index),
			"depth_m": features.water_depth(index),
			"shore_width_m": features.water_shore_width(index),
			"heightfield": field,
			"barrier_radius_m": features.wading_ring_radius(index, max_depth),
		}
		var water: Node3D = WaterBody.build(spec)
		if water != null:
			add_child(water)
	add_child(WaterAtmosphere.new())


func _wait_for_cell(cell: Vector2i) -> void:
	var frames: int = 0
	while not _streamer.is_cell_loaded(cell) and frames < SPAWN_WAIT_FRAMES_MAX:
		await get_tree().process_frame
		frames += 1
	if not _streamer.is_cell_loaded(cell):
		push_error("DesertSession : la cellule de départ %s n'a pas été chargée." % cell)
