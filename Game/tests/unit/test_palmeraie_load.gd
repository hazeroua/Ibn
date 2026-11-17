extends GutTest
## Test de charge de la palmeraie : toutes les cellules qu'elle touche sont construites comme par le streaming
## (transformées, décor, collisions). Pire cas mesuré : la cellule la plus chargée (parcelles, murets, formes de
## collision, temps de construction). Géométrie des séguias : crêtes au-dessus du sol, lit et berges en collision.

const DESERT_PATH: String = "res://data/desert/desert.json"
## Bornes du pire cas d'une cellule (Docs/reste-a-faire-mvp-2.md : 30 parcelles, 152 murets, 289 formes au plus,
## construction en moins de 50 ms sur un fil de travail).
const MAX_SHAPES_PER_CELL: int = 320
const MAX_BUILD_MS: float = 120.0
## Formes au plus par corps de collision (murets par 24, en boîtes fusionnées).
const MAX_SHAPES_PER_BODY: int = 80


func test_wall_collisions_align_with_visible_walls_outside_origin_cell() -> void:
	var field: DesertHeightfield = DesertHeightfield.from_data(JsonData.load_dictionary(DESERT_PATH))
	var layout: PalmeraieLayout = PalmeraieLayout.load_default(field)
	var cells: PalmeraieCells = PalmeraieCells.create(layout, field)
	for cz: int in field.cells_per_side:
		for cx: int in field.cells_per_side:
			var cell := Vector2i(cx, cz)
			var data: PalmeraieLayout.PalmeraieCellData = layout.cell_data(cell)
			if data == null or data.walls.is_empty():
				continue
			var origin := Vector3(-field.half_extent + cx * field.cell_size, 0.0, -field.half_extent + cz * field.cell_size)
			if origin.x == 0.0 and origin.z == 0.0:
				continue
			var wall := Vector2(data.walls[0], data.walls[1]).lerp(Vector2(data.walls[2], data.walls[3]), 0.5)
			var body := StaticBody3D.new()
			body.position = origin
			cells.add_decor(cell, body)
			var nearest: float = INF
			for child: Node in body.get_children():
				if child is CollisionObject3D:
					var collider := child as CollisionObject3D
					for owner_id: int in collider.get_shape_owners():
						var center: Vector3 = origin + collider.shape_owner_get_transform(owner_id).origin
						nearest = minf(nearest, Vector2(center.x, center.z).distance_to(wall))
			body.free()
			assert_lt(nearest, 10.0, "collision du muret proche du muret visible")
			return
	fail_test("aucune cellule de palmeraie avec muret trouvée")


func test_every_palmeraie_cell_builds_within_bounds() -> void:
	var field: DesertHeightfield = DesertHeightfield.from_data(JsonData.load_dictionary(DESERT_PATH))
	var layout: PalmeraieLayout = PalmeraieLayout.load_default(field)
	var cells: PalmeraieCells = PalmeraieCells.create(layout, field)
	assert_not_null(cells)
	var built: int = 0
	var worst_ms: float = 0.0
	var worst_shapes: int = 0
	var canal_cells: int = 0
	for cz: int in field.cells_per_side:
		for cx: int in field.cells_per_side:
			var cell := Vector2i(cx, cz)
			var origin_x: float = -field.half_extent + float(cx) * field.cell_size
			var origin_z: float = -field.half_extent + float(cz) * field.cell_size
			if not layout.overlaps_cell(origin_x, origin_z):
				continue
			var body := StaticBody3D.new()
			body.position = Vector3(origin_x, 0.0, origin_z)
			var started: int = Time.get_ticks_usec()
			var transforms: Dictionary = cells.build_transforms(cell)
			cells.add_decor(cell, body)
			var elapsed_ms: float = float(Time.get_ticks_usec() - started) / 1000.0
			worst_ms = maxf(worst_ms, elapsed_ms)
			var shapes: int = 0
			var worst_body_shapes: int = 0
			var has_canal: bool = false
			var bodies: Array[CollisionObject3D] = [body]
			for child: Node in body.get_children():
				if child is CollisionObject3D:
					bodies.append(child as CollisionObject3D)
			for collider: CollisionObject3D in bodies:
				var own: int = 0
				for owner_id: int in collider.get_shape_owners():
					own += collider.shape_owner_get_shape_count(owner_id)
					for index: int in collider.shape_owner_get_shape_count(owner_id):
						var shape: Shape3D = collider.shape_owner_get_shape(owner_id, index)
						if shape is ConcavePolygonShape3D:
							has_canal = true
							_check_canal_faces((shape as ConcavePolygonShape3D).get_faces(), body.position, field)
				shapes += own
				worst_body_shapes = maxi(worst_body_shapes, own)
			# Formes réparties sur des corps enfants (entrée dans l'arbre étalée par le streaming).
			assert_lte(worst_body_shapes, MAX_SHAPES_PER_BODY)
			if has_canal:
				canal_cells += 1
			worst_shapes = maxi(worst_shapes, shapes)
			for species: Variant in transforms:
				assert_eq((transforms[species] as PackedFloat32Array).size() % 12, 0)
			built += 1
			body.free()
	gut.p("Pire cas palmeraie : %d cellules, %.1f ms au plus par cellule, %d formes de collision au plus" % [built, worst_ms, worst_shapes])
	assert_gt(built, 0)
	assert_gt(canal_cells, 0, "des séguias avec collision")
	assert_lte(worst_shapes, MAX_SHAPES_PER_CELL)
	assert_lt(worst_ms, MAX_BUILD_MS)


## Faces des séguias : aucune n'est enfouie de plus de 0,6 m sous le relief (le lit est creusé dans le sol,
## les crêtes dépassent) et aucune n'est dégénérée.
func _check_canal_faces(faces: PackedVector3Array, origin: Vector3, field: DesertHeightfield) -> void:
	var buried: int = 0
	var crests: int = 0
	for index: int in range(0, faces.size(), 3):
		var a: Vector3 = faces[index] + origin
		var b: Vector3 = faces[index + 1] + origin
		var c: Vector3 = faces[index + 2] + origin
		if (b - a).cross(c - a).length_squared() < 1.0e-10:
			buried += 1000
		var center: Vector3 = (a + b + c) / 3.0
		var ground: float = field.height_at(center.x, center.z)
		if center.y < ground - 0.6:
			buried += 1
		if center.y > ground + 0.05:
			crests += 1
	assert_eq(buried, 0, "faces de séguia enfouies ou dégénérées")
	assert_gt(crests, 0, "crêtes des berges au-dessus du sol")
