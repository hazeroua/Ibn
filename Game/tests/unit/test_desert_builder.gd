extends GutTest
## Carte de test du désert : nœuds de la scène, bloc de cellules chargé, point d'apparition posé sur le sol.

const DATA_PATH: String = "res://data/desert/desert.json"


func test_scene_has_expected_nodes_and_loads_the_cell_block() -> void:
	var data: Dictionary = JsonData.load_dictionary(DATA_PATH)
	var world: Node3D = DesertBuilder.build(data)
	for node_name: String in ["Environment", "Sun", "Camera", "Terrain", "PlayerSpawn"]:
		assert_not_null(world.get_node_or_null(node_name), node_name)
	assert_true(world.get_node("PlayerSpawn").is_in_group(&"player_spawn"))
	add_child(world)
	var terrain: Node = world.get_node("Terrain")
	assert_eq(terrain.get_child_count(), 49, "7 × 7 cellules")
	var field: DesertHeightfield = DesertHeightfield.from_data(data)
	var spawn: Vector3 = (world.get_node("PlayerSpawn") as Node3D).position
	assert_almost_eq(spawn.y, field.height_at(spawn.x, spawn.z) + 0.05, 0.001)
	world.free()
