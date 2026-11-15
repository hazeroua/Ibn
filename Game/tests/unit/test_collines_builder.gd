extends GutTest
## Construction de la carte « collines » : nœuds, terrain, surfaces, collisions et partage des ressources des obstacles.

const DATA_PATH: String = "res://data/collines/collines.json"

var _world: Node3D
var _build_ms: float = 0.0


func before_all() -> void:
	var data: Dictionary = JsonData.load_dictionary(DATA_PATH)
	var start: int = Time.get_ticks_usec()
	_world = CollinesBuilder.build(data)
	_build_ms = float(Time.get_ticks_usec() - start) / 1000.0


func after_all() -> void:
	if is_instance_valid(_world):
		_world.free()


func test_builds_expected_nodes_with_owner() -> void:
	for node_name: String in ["Environment", "Sun", "Camera", "Terrain", "Obstacles", "PlayerSpawn"]:
		assert_not_null(_world.get_node_or_null(node_name), node_name)
	var terrain: CollinesTerrain = _world.get_node("Terrain")
	assert_eq(terrain.owner, _world)
	assert_true(_world.get_node("PlayerSpawn").is_in_group(&"player_spawn"))
	gut.p("Carte construite en %.0f ms (%d nœuds de terrain et d'obstacles)" % [_build_ms, _count_nodes(_world)])


func test_terrain_collides_on_layer_one_and_tiles_have_lods() -> void:
	var terrain: CollinesTerrain = _world.get_node("Terrain")
	assert_eq(terrain.collision_layer, 1)
	var tiles: Node = terrain.get_node("Tuiles")
	assert_eq(tiles.get_child_count(), 64, "8 × 8 tuiles de 128 m")
	var tile: Node = tiles.get_child(0)
	assert_eq(tile.get_child_count(), 4, "quatre niveaux de détail")
	var previous_end: float = 0.0
	var triangles: Array[int] = []
	for lod: Node in tile.get_children():
		var instance: MeshInstance3D = lod
		assert_almost_eq(instance.visibility_range_begin, previous_end, 0.001, "plages de visibilité contiguës")
		previous_end = instance.visibility_range_end
		triangles.append(instance.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size() / 3)
	assert_eq(previous_end, 0.0, "le dernier niveau est illimité")
	for i: int in range(1, triangles.size()):
		assert_lt(triangles[i], triangles[i - 1], "chaque niveau a moins de triangles que le précédent")
	var shared: Dictionary = {}
	for t: Node in tiles.get_children():
		for lod: Node in t.get_children():
			shared[(lod as MeshInstance3D).material_override.get_instance_id()] = true
	assert_eq(shared.size(), 1, "un seul matériau pour tout le terrain")


func test_heightmap_collision_matches_relief() -> void:
	var data: Dictionary = JsonData.load_dictionary(DATA_PATH)
	var relief: CollinesRelief = CollinesRelief.generate(JsonData.get_dictionary(data, "terrain", DATA_PATH))
	var shape: HeightMapShape3D = (_world.get_node("Terrain/Collision") as CollisionShape3D).shape
	assert_eq(shape.map_width, relief.size_px)
	assert_eq(hash(shape.map_data), hash(relief.heights))


func test_ray_hits_terrain_at_relief_height() -> void:
	add_child(_world)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var data: Dictionary = JsonData.load_dictionary(DATA_PATH)
	var relief: CollinesRelief = CollinesRelief.generate(JsonData.get_dictionary(data, "terrain", DATA_PATH))
	var x: float = -100.0
	var z: float = 150.0
	var query := PhysicsRayQueryParameters3D.create(Vector3(x, 200.0, z), Vector3(x, -50.0, z), 1)
	var hit: Dictionary = _world.get_world_3d().direct_space_state.intersect_ray(query)
	assert_false(hit.is_empty(), "le rayon touche le terrain sur la couche 1")
	assert_almost_eq((hit["position"] as Vector3).y, relief.height_at(x, z), 0.05)
	assert_eq(hit["collider"], _world.get_node("Terrain"))
	remove_child(_world)


func test_surface_at_known_points() -> void:
	var data: Dictionary = JsonData.load_dictionary(DATA_PATH)
	var config: Dictionary = JsonData.get_dictionary(data, "terrain", DATA_PATH)
	var relief: CollinesRelief = CollinesRelief.generate(config)
	var blend: PackedByteArray = relief.overlay_blend(JsonData.get_dictionary(config, "overlay_rules", DATA_PATH))
	var terrain: CollinesTerrain = _world.get_node("Terrain")
	var spawn: Vector3 = (_world.get_node("PlayerSpawn") as Marker3D).position
	assert_eq(terrain.surface_at(spawn), &"sable", "sable en bas, près du point d'apparition")
	var steepest: int = 0
	var steepest_slope: float = 0.0
	for z: int in range(1, relief.size_px - 1, 2):
		for x: int in range(1, relief.size_px - 1, 2):
			var slope: float = relief.slope_tangent(x, z)
			if slope > steepest_slope:
				steepest_slope = slope
				steepest = z * relief.size_px + x
	assert_eq(terrain.surface_at(relief.world_position_of(steepest)), &"pierre", "pierre sur la pente la plus forte")
	var stone_count: int = 0
	var sand_count: int = 0
	for index: int in range(0, relief.heights.size(), 997):
		var expected: StringName = &"pierre" if blend[index] >= 128 else &"sable"
		assert_eq(terrain.surface_at(relief.world_position_of(index)), expected)
		if expected == &"pierre":
			stone_count += 1
		else:
			sand_count += 1
	assert_gt(stone_count, 0)
	assert_gt(sand_count, 0)
	assert_eq(terrain.surface_at(Vector3(5000.0, 0.0, 5000.0)), &"sable", "hors de la carte : surface de base")


func test_obstacles_share_resources_and_carry_surface_metadata() -> void:
	var obstacles: Node = _world.get_node("Obstacles")
	var total: int = 0
	var shapes: Dictionary = {}
	var meshes: Dictionary = {}
	var surfaces: Dictionary = {}
	var shape_nodes: int = 0
	for child: Node in obstacles.get_children():
		if child is StaticBody3D:
			var body: StaticBody3D = child
			assert_eq(body.collision_layer, 1)
			assert_true(body.has_meta(&"surface"), "métadonnée surface sur %s" % body.name)
			surfaces[str(body.get_meta(&"surface"))] = true
			for collision: Node in body.get_children():
				shapes[(collision as CollisionShape3D).shape.get_instance_id()] = true
				shape_nodes += 1
		elif child is MultiMeshInstance3D:
			var instance: MultiMeshInstance3D = child
			total += instance.multimesh.instance_count
			meshes[instance.multimesh.mesh.get_instance_id()] = true
	assert_eq(total, 1000, "1 000 obstacles affichés")
	assert_eq(shape_nodes, 1000, "1 000 obstacles avec collision")
	assert_eq(shapes.size(), 5, "une forme de collision partagée par type")
	assert_eq(meshes.size(), 5, "un maillage partagé par type")
	assert_true(surfaces.has("pierre") and surfaces.has("terre"))


func test_instances_buffer_matches_collision_transforms() -> void:
	var obstacles: Node = _world.get_node("Obstacles")
	var instance: CollinesInstances = obstacles.get_node("Visuel_rocher_petit")
	var body: StaticBody3D = obstacles.get_node("Collisions_rocher_petit")
	assert_eq(instance.transform_buffer.size(), body.get_child_count() * CollinesInstances.FLOATS_PER_INSTANCE)
	var collision: CollisionShape3D = body.get_child(7)
	var buffer: PackedFloat32Array = PackedFloat32Array()
	buffer.resize(CollinesInstances.FLOATS_PER_INSTANCE)
	CollinesInstances.write_transform(buffer, 0, collision.transform)
	for i: int in CollinesInstances.FLOATS_PER_INSTANCE:
		assert_almost_eq(instance.transform_buffer[7 * CollinesInstances.FLOATS_PER_INSTANCE + i], buffer[i], 0.0001)


func test_obstacles_rest_on_the_ground() -> void:
	var data: Dictionary = JsonData.load_dictionary(DATA_PATH)
	var relief: CollinesRelief = CollinesRelief.generate(JsonData.get_dictionary(data, "terrain", DATA_PATH))
	var body: StaticBody3D = _world.get_node("Obstacles/Collisions_rocher_moyen")
	var floating: int = 0
	for collision: Node in body.get_children():
		var origin: Vector3 = (collision as CollisionShape3D).position
		# Le centre du rocher (hauteur 0,8 m) ne peut pas être sous le sol ni à plus de 1,5 m au-dessus.
		var above: float = origin.y - relief.height_at(origin.x, origin.z)
		if above < 0.0 or above > 1.5:
			floating += 1
	assert_eq(floating, 0)


func _count_nodes(node: Node) -> int:
	var count: int = 1
	for child: Node in node.get_children():
		count += _count_nodes(child)
	return count
