class_name TunisWorldProvider
extends TunisCellProvider
## Le streamer attache les cellules sous un Node sans transform 3D : applique l'origine
## du monde aux racines détachées, une fois par chargement, sans changer les JSON.

var _source: TunisCellProvider
var _world_offset: Vector3


static func with_offset(source: TunisCellProvider, world_offset: Vector3) -> TunisWorldProvider:
	if source == null:
		push_error("TunisWorldProvider : fournisseur absent.")
		return null
	var result := TunisWorldProvider.new()
	result._source = source
	result._world_offset = world_offset
	return result


func build_cell(stream_cell: Vector2i) -> Node3D:
	var cell: Node3D = _source.build_cell(stream_cell)
	if cell != null:
		cell.position += _world_offset
	return cell


func stream_to_logical(stream_cell: Vector2i) -> Vector2i:
	return _source.stream_to_logical(stream_cell)


func logical_to_stream(logical_cell: Vector2i) -> Vector2i:
	return _source.logical_to_stream(logical_cell)


func contains_logical_cell(cell: Vector2i) -> bool:
	return _source.contains_logical_cell(cell)


func cell_origin(logical_cell: Vector2i) -> Vector3:
	return _source.cell_origin(logical_cell) + _world_offset


func cell_count() -> int:
	return _source.cell_count()
