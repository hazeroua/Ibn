extends GutTest
## Modèles du désert : budgets de triangles par niveau de détail et cohérence du manifeste.
## Pire cas de charge : autour du joueur, 30 rochers et palmiers au niveau 0, 100 au niveau 1, 400 au niveau 2 et 400 imposteurs.

const MANIFEST_PATH: String = "res://data/assets/desert_props.json"
const LOD_COUNTS: Array[int] = [30, 100, 400]
const IMPOSTER_COUNT: int = 400
## Budget de triangles pour le pire cas ci-dessus (la scène entière dispose de 100 000 primitives).
const WORST_CASE_TRIANGLES_MAX: int = 70000


func _manifest() -> Dictionary:
	return JsonData.load_dictionary(MANIFEST_PATH)


func _triangles_of(file_name: String) -> int:
	var directory: String = JsonData.get_string(_manifest(), "directory", MANIFEST_PATH)
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var err: Error = document.append_from_file(ProjectSettings.globalize_path(directory + file_name + ".glb"), state)
	assert_eq(err, OK, "lecture de %s" % file_name)
	var total: int = 0
	for mesh: GLTFMesh in state.get_meshes():
		var array_mesh: ArrayMesh = mesh.mesh.get_mesh()
		for surface: int in array_mesh.get_surface_count():
			var arrays: Array = array_mesh.surface_get_arrays(surface)
			total += (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return total


func test_rocks_respect_triangle_budget_per_lod() -> void:
	var rock: Dictionary = JsonData.get_dictionary(JsonData.get_dictionary(_manifest(), "models", MANIFEST_PATH), "rocher", MANIFEST_PATH)
	var budgets: Array = JsonData.get_array(rock, "max_triangles", MANIFEST_PATH)
	var variants: Array = JsonData.get_array(rock, "variants", MANIFEST_PATH)
	assert_eq(variants.size(), 3)
	for variant: String in variants:
		var previous: int = 1 << 30
		for lod: int in budgets.size():
			var count: int = _triangles_of("rocher_%s_lod%d" % [variant, lod])
			assert_gt(count, 0)
			assert_lte(count, int(budgets[lod]), "rocher %s niveau %d" % [variant, lod])
			assert_lt(count, previous, "chaque niveau est plus léger que le précédent")
			previous = count


func test_palms_respect_triangle_budget_per_lod() -> void:
	var palm: Dictionary = JsonData.get_dictionary(JsonData.get_dictionary(_manifest(), "models", MANIFEST_PATH), "palmier", MANIFEST_PATH)
	var budgets: Array = JsonData.get_array(palm, "max_triangles", MANIFEST_PATH)
	var variants: Array = JsonData.get_array(palm, "variants", MANIFEST_PATH)
	assert_eq(variants.size(), 2)
	for variant: String in variants:
		var previous: int = 1 << 30
		for lod: int in budgets.size():
			var count: int = _triangles_of("palmier_%s_lod%d" % [variant, lod])
			assert_gt(count, 0)
			assert_lte(count, int(budgets[lod]), "palmier %s niveau %d" % [variant, lod])
			assert_lt(count, previous)
			previous = count


func test_imposter_is_lighter_than_the_lightest_palm() -> void:
	var models: Dictionary = JsonData.get_dictionary(_manifest(), "models", MANIFEST_PATH)
	var imposter: Dictionary = JsonData.get_dictionary(models, "imposteur_palmier", MANIFEST_PATH)
	var count: int = _triangles_of("palmier_imposteur")
	assert_lte(count, int(JsonData.get_float(imposter, "max_triangles", MANIFEST_PATH)))
	assert_lt(count, _triangles_of("palmier_a_lod2"))


func test_lod_distances_are_increasing() -> void:
	var manifest: Dictionary = _manifest()
	var distances: Array = JsonData.get_array(manifest, "lod_distances_m", MANIFEST_PATH)
	for i: int in range(1, distances.size()):
		assert_gt(float(distances[i]), float(distances[i - 1]))
	assert_gt(JsonData.get_float(manifest, "imposter_distance_m", MANIFEST_PATH), float(distances[distances.size() - 1]))


func test_worst_case_instances_around_the_player_fit_budget() -> void:
	var rock_counts: Array[int] = []
	var palm_counts: Array[int] = []
	for lod: int in LOD_COUNTS.size():
		rock_counts.append(_triangles_of("rocher_c_lod%d" % lod))
		palm_counts.append(_triangles_of("palmier_b_lod%d" % lod))
	var total: int = IMPOSTER_COUNT * _triangles_of("palmier_imposteur")
	for lod: int in LOD_COUNTS.size():
		total += LOD_COUNTS[lod] * (rock_counts[lod] + palm_counts[lod])
	gut.p("Pire cas (30 + 100 + 400 rochers et palmiers, %d imposteurs) : %d triangles" % [IMPOSTER_COUNT, total])
	assert_lte(total, WORST_CASE_TRIANGLES_MAX)
