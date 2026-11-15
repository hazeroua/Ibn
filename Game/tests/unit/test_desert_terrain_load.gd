extends GutTest
## Test de charge du terrain du désert : pire cas = 256 cellules, appels massifs à height_at, surface_at.
## Les durées sont mesurées sur la machine d'exécution ; les seuils sont des garde-fous larges (le budget par image
## du streaming est vérifié par le ticket du streaming avec ces durées de construction).

const DATA_PATH: String = "res://data/desert/desert.json"
## Pire cellule (ms), pointes de collecte de mémoire comprises : le streaming la charge hors du fil principal.
const MAX_CELL_BUILD_MS: float = 1000.0
## Moyenne sur les 256 cellules.
const MAX_MEAN_CELL_BUILD_MS: float = 80.0
const MAX_HEIGHT_NS: float = 4000.0


func test_height_at_cost() -> void:
	var field: DesertHeightfield = DesertHeightfield.from_data(JsonData.load_dictionary(DATA_PATH))
	var count: int = 200000
	var sum: float = 0.0
	var start: int = Time.get_ticks_usec()
	for i: int in count:
		sum += field.height_at(float(i % 4000) - 2000.0, float(i / 4000) * 80.0 - 2000.0)
	var ns: float = float(Time.get_ticks_usec() - start) * 1000.0 / float(count)
	gut.p("height_at : %.0f ns par appel (%d appels, somme %.0f)" % [ns, count, sum])
	assert_lt(ns, MAX_HEIGHT_NS)


func test_surface_at_cost() -> void:
	var field: DesertHeightfield = DesertHeightfield.from_data(JsonData.load_dictionary(DATA_PATH))
	var count: int = 50000
	var start: int = Time.get_ticks_usec()
	for i: int in count:
		field.surface_at(Vector3(float(i % 4000) - 2000.0, 0.0, float(i / 4000) * 300.0 - 2000.0))
	var ns: float = float(Time.get_ticks_usec() - start) * 1000.0 / float(count)
	gut.p("surface_at : %.0f ns par appel" % ns)
	assert_lt(ns, MAX_HEIGHT_NS * 6.0)


func test_worst_case_all_cells() -> void:
	var provider: DesertTerrainCell = DesertTerrainCell.from_data(JsonData.load_dictionary(DATA_PATH))
	var worst: float = 0.0
	var total: float = 0.0
	var vertices: int = 0
	var count: int = 0
	for z: int in 16:
		for x: int in 16:
			var start: int = Time.get_ticks_usec()
			var cell: Node3D = provider.build_cell(Vector2i(x, z))
			var elapsed: float = float(Time.get_ticks_usec() - start) / 1000.0
			worst = maxf(worst, elapsed)
			total += elapsed
			count += 1
			for lod: Node in cell.get_children():
				if lod is MeshInstance3D:
					vertices += ((lod as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			cell.free()
	gut.p("256 cellules : moyenne %.0f ms, pire %.0f ms, %d sommets au total (tous niveaux)" % [total / float(count), worst, vertices])
	PerfCheck.under(self, worst, MAX_CELL_BUILD_MS)
	PerfCheck.under(self, total / float(count), MAX_MEAN_CELL_BUILD_MS)
