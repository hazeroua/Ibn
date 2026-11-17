class_name TunisCellBuilder
extends RefCounted
## Construit une cellule hors de l'arbre de scène à partir des objets déjà typés et préchargés.

const INSTANCE_ID_META: StringName = &"tunis_instance_id"
const INSTANCE_LAYER_META: StringName = &"tunis_layer"

var _catalog: TunisCatalog


static func create(catalog: TunisCatalog) -> TunisCellBuilder:
	var result := TunisCellBuilder.new()
	result._catalog = catalog
	return result


func build(
	logical_cell: Vector2i, cell_origin: Vector3, instances: Array[TunisInstanceData]
) -> Node3D:
	var root := Node3D.new()
	root.name = "TunisCell_%d_%d" % [logical_cell.x, logical_cell.y]
	root.position = cell_origin
	for data: TunisInstanceData in instances:
		var instance: Node3D = _catalog.instantiate(data.prefab_id)
		if instance == null:
			root.free()
			return null
		instance.name = String(data.id)
		instance.set_meta(INSTANCE_ID_META, data.id)
		instance.set_meta(INSTANCE_LAYER_META, data.layer)
		instance.transform = Transform3D(data.transform.basis, data.transform.origin - cell_origin)
		root.add_child(instance)
	return root
