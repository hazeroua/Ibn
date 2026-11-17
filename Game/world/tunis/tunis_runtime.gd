class_name TunisRuntime
extends Node3D
## Coordinateur du runtime urbain, de l'épinglage et du registre des instances chargées.

const STREAMING_PATH: String = "res://data/tunis/streaming.json"

var _provider: TunisCellProvider
var _streamer: WorldStreamer
var _instances: Dictionary = {}
var _cell_instance_ids: Dictionary = {}
var _pin_counts: Dictionary = {}
var _initialized: bool = false


func initialize(provider: TunisCellProvider = null, streamer: WorldStreamer = null) -> bool:
	if _initialized:
		return true
	_provider = provider if provider != null else TunisCellProvider.create()
	if _provider == null:
		return false
	_streamer = streamer if streamer != null else WorldStreamer.new()
	_streamer.name = "Streaming"
	var streaming_config: Dictionary = JsonData.load_dictionary(STREAMING_PATH)
	var user_settings: GameSettings = get_node_or_null("/root/Settings") as GameSettings
	if user_settings != null:
		streaming_config = user_settings.apply_streaming_overrides(streaming_config)
	if not _streamer.configure(streaming_config) or not _streamer.register_provider(_provider):
		_streamer.free()
		_streamer = null
		return false
	_streamer.cell_loaded.connect(_on_cell_loaded)
	_streamer.cell_unloaded.connect(_on_cell_unloaded)
	add_child(_streamer)
	_initialized = true
	return true


func _ready() -> void:
	if not initialize():
		push_error("TunisRuntime: initialisation impossible.")


func set_focus(position: Vector3, velocity: Vector3) -> void:
	if _streamer != null:
		_streamer.set_focus(position, velocity)


func pin_cell(logical_cell: Vector2i) -> bool:
	if _streamer == null or not _provider.contains_logical_cell(logical_cell):
		return false
	var count: int = int(_pin_counts.get(logical_cell, 0)) + 1
	_pin_counts[logical_cell] = count
	return count > 1 or _streamer.set_cell_pinned(_provider.logical_to_stream(logical_cell), true)


func unpin_cell(logical_cell: Vector2i) -> bool:
	if _streamer == null or not _pin_counts.has(logical_cell):
		return false
	var count: int = int(_pin_counts[logical_cell]) - 1
	if count > 0:
		_pin_counts[logical_cell] = count
		return true
	_pin_counts.erase(logical_cell)
	return _streamer.set_cell_pinned(_provider.logical_to_stream(logical_cell), false)


func force_all_cells_loaded(enabled: bool) -> void:
	if _streamer != null:
		_streamer.set_all_cells_pinned(enabled)


func get_instance_by_id(instance_id: StringName) -> Node3D:
	return _instances.get(instance_id) as Node3D


func loaded_instance_count() -> int:
	return _instances.size()


func loaded_cell_count() -> int:
	return _streamer.get_loaded_count() if _streamer != null else 0


func pending_cell_count() -> int:
	return _streamer.get_pending_count() if _streamer != null else 0


func streaming_stats() -> Dictionary:
	return _streamer.get_stats() if _streamer != null else {}


func _on_cell_loaded(stream_cell: Vector2i) -> void:
	var root: Node3D = _streamer.get_cell_node(stream_cell)
	if root == null:
		push_error("TunisRuntime: cellule chargée sans nœud : %s." % stream_cell)
		return
	var ids: Array[StringName] = []
	for child: Node in root.get_children():
		if not child.has_meta(TunisCellProvider.INSTANCE_ID_META):
			continue
		var instance_id := StringName(child.get_meta(TunisCellProvider.INSTANCE_ID_META))
		if _instances.has(instance_id):
			push_error("TunisRuntime: identifiant chargé deux fois : %s." % instance_id)
			continue
		_instances[instance_id] = child
		ids.append(instance_id)
	_cell_instance_ids[stream_cell] = ids


func _on_cell_unloaded(stream_cell: Vector2i) -> void:
	var ids: Array[StringName] = _cell_instance_ids.get(stream_cell, [])
	for instance_id: StringName in ids:
		_instances.erase(instance_id)
	_cell_instance_ids.erase(stream_cell)
