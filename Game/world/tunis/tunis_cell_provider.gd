class_name TunisCellProvider
extends RefCounted
## Fournisseur immuable pour WorldStreamer. JSON et PackedScene sont chargés avant le streaming.

const DATA_ROOT: String = "res://data/tunis/"
const INSTANCE_ID_META: StringName = TunisCellBuilder.INSTANCE_ID_META

var _cell_size_m: float
var _origin: Vector3
var _min_cell: Vector2i
var _max_cell: Vector2i
var _cells: Dictionary = {}
var _builder: TunisCellBuilder


static func create() -> TunisCellProvider:
	var city: Dictionary = JsonData.load_dictionary(DATA_ROOT + "city.json")
	var catalog: Dictionary = JsonData.load_dictionary(DATA_ROOT + "catalog.json")
	var cells: Array = []
	for raw_path: Variant in JsonData.get_array(city, "cells", "city.json"):
		cells.append(JsonData.load_dictionary(DATA_ROOT + String(raw_path)))
	return from_documents(
		city,
		catalog,
		cells,
		JsonData.load_dictionary(DATA_ROOT + "interactions.json"),
		JsonData.load_dictionary(DATA_ROOT + "audio.json")
	)


static func from_documents(
	city: Dictionary,
	catalog_data: Dictionary,
	cells: Array,
	interactions: Dictionary,
	audio: Dictionary,
	scene_overrides: Dictionary = {}
) -> TunisCellProvider:
	var errors := TunisDataValidator.validate_documents(
		city, catalog_data, cells, interactions, audio
	)
	if not errors.is_empty():
		for message: String in errors:
			push_error("TunisCellProvider: " + message)
		return null
	var catalog := TunisCatalog.create(catalog_data, scene_overrides)
	if catalog == null:
		return null
	var provider := TunisCellProvider.new()
	provider._cell_size_m = float(city["cell_size_m"])
	var raw_origin: Array = city["origin"]
	provider._origin = Vector3(float(raw_origin[0]), float(raw_origin[1]), float(raw_origin[2]))
	var bounds: Dictionary = city["bounds"]
	var raw_min: Array = bounds["min_cell"]
	var raw_max: Array = bounds["max_cell"]
	provider._min_cell = Vector2i(int(raw_min[0]), int(raw_min[1]))
	provider._max_cell = Vector2i(int(raw_max[0]), int(raw_max[1]))
	provider._builder = TunisCellBuilder.create(catalog)
	for raw_cell: Variant in cells:
		var cell_data: Dictionary = raw_cell
		var raw_coordinate: Array = cell_data["cell"]
		var coordinate := Vector2i(int(raw_coordinate[0]), int(raw_coordinate[1]))
		var entries: Array[TunisInstanceData] = []
		for raw_entry: Variant in cell_data["instances"]:
			entries.append(TunisInstanceData.from_dictionary(raw_entry))
		entries.sort_custom(
			func(a: TunisInstanceData, b: TunisInstanceData) -> bool:
				return String(a.id) < String(b.id)
		)
		provider._cells[coordinate] = entries
	return provider


func build_cell(stream_cell: Vector2i) -> Node3D:
	var logical_cell := stream_to_logical(stream_cell)
	if not contains_logical_cell(logical_cell):
		push_error("TunisCellProvider: cellule hors des limites : %s." % logical_cell)
		return null
	var instances: Array[TunisInstanceData] = _cells.get(logical_cell, [])
	return _builder.build(logical_cell, cell_origin(logical_cell), instances)


func stream_to_logical(stream_cell: Vector2i) -> Vector2i:
	return stream_cell + _min_cell


func logical_to_stream(logical_cell: Vector2i) -> Vector2i:
	return logical_cell - _min_cell


func contains_logical_cell(cell: Vector2i) -> bool:
	return (
		cell.x >= _min_cell.x
		and cell.y >= _min_cell.y
		and cell.x <= _max_cell.x
		and cell.y <= _max_cell.y
	)


func cell_origin(logical_cell: Vector2i) -> Vector3:
	return (
		_origin
		+ Vector3(float(logical_cell.x) * _cell_size_m, 0.0, float(logical_cell.y) * _cell_size_m)
	)


func cell_count() -> int:
	return (_max_cell.x - _min_cell.x + 1) * (_max_cell.y - _min_cell.y + 1)
