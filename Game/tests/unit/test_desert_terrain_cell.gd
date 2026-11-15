extends GutTest
## Cellules du désert : maillage à 4 niveaux, jupes, collision réelle (rayon physique), cohérence avec le champ de hauteurs.

const DATA_PATH: String = "res://data/desert/desert.json"

var _provider: DesertTerrainCell
var _cell: Node3D


func before_all() -> void:
	_provider = DesertTerrainCell.from_data(JsonData.load_dictionary(DATA_PATH))


func before_each() -> void:
	_cell = _provider.build_cell(Vector2i(9, 7))
	add_child(_cell)


func after_each() -> void:
	_cell.free()


func test_cell_has_collision_and_four_contiguous_lods() -> void:
	var body: DesertCellBody = _cell
	assert_eq(body.collision_layer, 1)
	assert_eq(body.cell, Vector2i(9, 7))
	assert_eq(body.position, Vector3(250.0, 0.0, -250.0))
	assert_eq(body.name, &"Cellule_9_7")
	var previous_end: float = 0.0
	var triangles: Array[int] = []
	for i: int in 4:
		var lod: MeshInstance3D = body.get_node("Lod%d" % i)
		assert_almost_eq(lod.visibility_range_begin, previous_end, 0.001)
		previous_end = lod.visibility_range_end
		triangles.append(lod.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size() / 3)
	assert_eq(previous_end, 0.0, "le dernier niveau est illimité")
	for i: int in range(1, 4):
		assert_lt(triangles[i], triangles[i - 1])
	gut.p("Triangles par niveau : %s" % [triangles])


func test_lods_share_one_material_and_normals_match() -> void:
	var finest: ArrayMesh = (_cell.get_node("Lod0") as MeshInstance3D).mesh
	var coarsest: ArrayMesh = (_cell.get_node("Lod3") as MeshInstance3D).mesh
	assert_same(finest.surface_get_material(0), coarsest.surface_get_material(0))
	var fine_arrays: Array = finest.surface_get_arrays(0)
	var coarse_arrays: Array = coarsest.surface_get_arrays(0)
	var fine_normals: PackedVector3Array = fine_arrays[Mesh.ARRAY_NORMAL]
	var coarse_normals: PackedVector3Array = coarse_arrays[Mesh.ARRAY_NORMAL]
	# Le sommet (1, 0) du niveau 10 est le sommet (10, 0) du niveau fin : mêmes normales, même hauteur.
	assert_eq(coarse_normals[1], fine_normals[10])
	assert_eq((coarse_arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array)[1].y, (fine_arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array)[10].y)


func test_vertices_match_the_heightfield_and_surface_at() -> void:
	var field: DesertHeightfield = _provider.heightfield
	var arrays: Array = (_cell.get_node("Lod0") as MeshInstance3D).mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for index: int in [0, 5, 1717, 4040, 7777, 10200]:
		var world: Vector3 = vertices[index] + _cell.position
		assert_almost_eq(vertices[index].y, field.height_at(world.x, world.z), 0.0001)
		assert_almost_eq(normals[index].dot(field.normal_at(world.x, world.z)), 1.0, 0.0001)
		var weights := Vector2(colors[index].r, colors[index].g)
		assert_eq(DesertHeightfield.surface_from_weights(weights), field.surface_at(world))


func test_skirt_hangs_below_the_border() -> void:
	var vertices: PackedVector3Array = (_cell.get_node("Lod0") as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var grid: int = 101 * 101
	assert_eq(vertices.size(), grid + 400)
	assert_almost_eq(vertices[grid].y, vertices[0].y - 3.0, 0.0001)


func test_physics_ray_hits_the_visible_ground() -> void:
	var field: DesertHeightfield = _provider.heightfield
	await wait_physics_frames(2)
	var space: PhysicsDirectSpaceState3D = (_cell as Node3D).get_world_3d().direct_space_state
	for point: Vector2 in [
		Vector2(300.0, -200.0), Vector2(420.0, -240.0), Vector2(471.3, -31.9), Vector2(260.0, -180.0), Vector2(480.0, -10.0)
	]:
		var query := PhysicsRayQueryParameters3D.create(Vector3(point.x, 500.0, point.y), Vector3(point.x, -100.0, point.y), 1)
		var hit: Dictionary = space.intersect_ray(query)
		assert_false(hit.is_empty(), "le rayon touche la cellule")
		if hit.is_empty():
			continue
		# Maille de 2,5 m : la collision suit les sommets, l'écart avec le champ exact reste faible.
		assert_almost_eq((hit["position"] as Vector3).y, field.height_at(point.x, point.y), 0.8)
		assert_eq((hit["collider"] as Node).name, &"Cellule_9_7")


func test_cells_are_continuous_across_borders() -> void:
	var neighbour: Node3D = _provider.build_cell(Vector2i(10, 7))
	var mine: PackedVector3Array = (_cell.get_node("Lod0") as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var theirs: PackedVector3Array = (neighbour.get_node("Lod0") as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for row: int in [0, 17, 60, 100]:
		assert_eq(mine[row * 101 + 100].y, theirs[row * 101].y, "bord partagé sans fissure")
	neighbour.free()


func test_cell_outside_the_grid_is_refused() -> void:
	assert_null(_provider.build_cell(Vector2i(16, 0)))
	assert_push_error("hors de la grille")
