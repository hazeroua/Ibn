class_name DesertTestTerrain
extends Node3D
## Terrain de la carte de test du désert : construit au chargement un bloc de cellules (section « test_map » de
## desert.json), comme le ferait le streaming. La scène générée ne contient que ce nœud : les maillages sont
## recalculés à chaque chargement, aucun gros fichier n'est versionné.

@export_file("*.json") var data_path: String = DesertHeightfield.DEFAULT_PATH

var provider: DesertTerrainCell


func _ready() -> void:
	var data: Dictionary = JsonData.load_dictionary(data_path)
	provider = DesertTerrainCell.from_data(data)
	if provider == null:
		return
	var context: String = "desert.json > test_map"
	var test_map: Dictionary = JsonData.get_dictionary(data, "test_map", "desert.json")
	var first: Vector2i = _cell_of(JsonData.get_vector2(test_map, "first_cell", context))
	var last: Vector2i = _cell_of(JsonData.get_vector2(test_map, "last_cell", context))
	for z: int in range(first.y, last.y + 1):
		for x: int in range(first.x, last.x + 1):
			var cell: Node3D = provider.build_cell(Vector2i(x, z))
			if cell != null:
				add_child(cell)


static func _cell_of(value: Vector2) -> Vector2i:
	return Vector2i(roundi(value.x), roundi(value.y))
