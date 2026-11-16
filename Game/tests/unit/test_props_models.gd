extends GutTest
## Modèles du désert : budgets de triangles par niveau de détail et cohérence du manifeste.
## Pire cas de charge : autour du joueur, 30 rochers et palmiers au niveau 0, 100 au niveau 1, 400 au niveau 2 et 400 imposteurs.
## Pire cas de la palmeraie (vue de la crête, palmeraie.json > budget) : 600 palmiers et 850 arbres fruitiers, tous comptés
## au niveau 2 (plus lourd que l'imposteur), dans la part de végétation du budget de triangles de la palmeraie.
## Végétation texturée : un seul atlas partagé (BC3, mipmaps qui conservent la couverture de l'alpha) et cartes découpées.

const MANIFEST_PATH: String = "res://data/assets/desert_props.json"
const LOD_COUNTS: Array[int] = [30, 100, 400]
const IMPOSTER_COUNT: int = 400
## Budget de triangles pour le pire cas ci-dessus (la scène entière dispose de 100 000 primitives).
const WORST_CASE_TRIANGLES_MAX: int = 70000
const PALMERAIE_PATH: String = "res://data/desert/palmeraie.json"
const PALMERAIE_PALMS: int = 600
const PALMERAIE_FRUIT_TREES: int = 850
## Part du budget de triangles de la palmeraie laissée au décor (sol cultivé, séguias, murets : palmeraie.json > budget).
const PALMERAIE_DECOR_TRIANGLES: int = 39000
## Écart toléré entre la couverture de l'alpha du niveau 0 et celle des niveaux réduits de l'atlas.
const COVERAGE_TOLERANCE: float = 0.08


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


func test_bush_and_grass_respect_triangle_budget() -> void:
	var models: Dictionary = JsonData.get_dictionary(_manifest(), "models", MANIFEST_PATH)
	for id: String in ["buisson", "herbe_seche"]:
		var spec: Dictionary = JsonData.get_dictionary(models, id, MANIFEST_PATH)
		for variant: Variant in JsonData.get_array(spec, "variants", MANIFEST_PATH):
			var count: int = _triangles_of("%s_%s" % [id, variant])
			assert_gt(count, 0, "%s %s" % [id, variant])
			assert_lte(count, int(JsonData.get_float(spec, "max_triangles", MANIFEST_PATH)), "%s %s" % [id, variant])


func test_vegetation_models_carry_vertex_colors() -> void:
	# Sans couleurs de sommets, la végétation apparaît blanche (le shader du désert les utilise comme couleur).
	var meshes: Dictionary = DesertFoliageMeshes.build(DesertFoliageMeshes.load_settings())
	for id: StringName in [&"palmier", &"buisson", &"herbe_seche"]:
		assert_true(meshes.has(id), String(id))
		if meshes.has(id):
			var mesh: Mesh = meshes[id]
			assert_ne(mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_COLOR, 0, String(id))


func test_worst_case_palmeraie_from_the_crest_fits_budget() -> void:
	var palm_lod2: int = _triangles_of("palmier_a_lod2")
	var tree_lod2: int = 0
	for id: String in ["grenadier", "figuier", "olivier"]:
		tree_lod2 = maxi(tree_lod2, _triangles_of("%s_a_lod2" % id))
	var total: int = PALMERAIE_PALMS * palm_lod2 + PALMERAIE_FRUIT_TREES * tree_lod2
	var budget: Dictionary = JsonData.get_dictionary(JsonData.load_dictionary(PALMERAIE_PATH), "budget", PALMERAIE_PATH)
	var allowed: int = JsonData.get_int(budget, "estimate_visible_triangles", PALMERAIE_PATH) - PALMERAIE_DECOR_TRIANGLES
	gut.p("Palmeraie vue de la crête : %d triangles de végétation (part autorisée %d)" % [total, allowed])
	assert_lte(total, allowed)


func test_every_lod_of_textured_trees_respects_its_budget_and_is_lighter() -> void:
	var models: Dictionary = JsonData.get_dictionary(_manifest(), "models", MANIFEST_PATH)
	for id: String in ["acacia", "tamaris", "grenadier", "figuier", "olivier"]:
		var spec: Dictionary = JsonData.get_dictionary(models, id, MANIFEST_PATH)
		var budgets: Array = JsonData.get_array(spec, "max_triangles", MANIFEST_PATH)
		for variant: Variant in JsonData.get_array(spec, "variants", MANIFEST_PATH):
			var previous: int = 1 << 30
			for lod: int in budgets.size():
				var count: int = _triangles_of("%s_%s_lod%d" % [id, variant, lod])
				assert_gt(count, 0, "%s %s niveau %d" % [id, variant, lod])
				assert_lte(count, int(budgets[lod]), "%s %s niveau %d" % [id, variant, lod])
				assert_lt(count, previous, "%s : chaque niveau est plus léger que le précédent" % id)
				previous = count
		var imposter: Dictionary = JsonData.get_dictionary(models, "imposteur_%s" % id, MANIFEST_PATH)
		assert_lte(_triangles_of("%s_imposteur" % id), int(JsonData.get_float(imposter, "max_triangles", MANIFEST_PATH)), id)


func test_vegetation_is_textured_and_shares_one_atlas() -> void:
	var levels: Dictionary = DesertFoliageMeshes.build_levels(DesertFoliageMeshes.load_settings())
	assert_false(levels.is_empty())
	var atlas: Texture2D = null
	for id: StringName in [&"palmier", &"acacia", &"tamaris", &"olivier", &"figuier", &"grenadier", &"buisson", &"jujubier"]:
		for level: Dictionary in levels[id]:
			var mesh: Mesh = level["mesh"]
			assert_ne(mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_TEX_UV, 0, "%s : coordonnées d'atlas" % id)
			var material: ShaderMaterial = mesh.surface_get_material(0) as ShaderMaterial
			assert_eq(material.shader.resource_path, DesertFoliageMeshes.SHADER_PATH, String(id))
			var texture: Texture2D = material.get_shader_parameter(&"foliage_atlas") as Texture2D
			assert_not_null(texture, String(id))
			if atlas == null:
				atlas = texture
			assert_same(texture, atlas, "%s : un seul atlas pour toute la végétation" % id)
	for id: StringName in [
		&"herbe_seche", &"alfa_proche", &"drinn_proche", &"fleurs", &"roseau", &"jonc", &"retam", &"orge", &"feve", &"laurier_rose"
	]:
		var mesh2: Mesh = (levels[id][0] as Dictionary)["mesh"]
		assert_ne(mesh2.surface_get_format(0) & Mesh.ARRAY_FORMAT_TEX_UV, 0, "%s : coordonnées d'atlas" % id)
	for id: StringName in [&"caillou_a", &"falaise_a_lod0", &"chadouf"]:
		var mesh3: Mesh = (levels[id][0] as Dictionary)["mesh"]
		var solid: ShaderMaterial = mesh3.surface_get_material(0) as ShaderMaterial
		assert_eq(solid.shader.resource_path, DesertFoliageMeshes.SOLID_SHADER_PATH, "%s : opaque, sans découpe" % id)


func test_atlas_mipmaps_keep_alpha_coverage() -> void:
	var path: String = JsonData.get_string(JsonData.load_dictionary(DesertFoliageMeshes.SETTINGS_PATH), "atlas", "foliage.json")
	var texture: Texture2D = load(path) as Texture2D
	assert_not_null(texture)
	var image: Image = texture.get_image()
	assert_eq(image.get_format(), Image.FORMAT_DXT5, "atlas compressé BC3")
	assert_true(image.has_mipmaps())
	image.decompress()
	var atlas: Dictionary = JsonData.get_dictionary(_manifest(), "atlas", MANIFEST_PATH)
	var unit: int = JsonData.get_int(atlas, "tile_px", MANIFEST_PATH)
	var threshold: float = JsonData.get_float(atlas, "alpha_threshold", MANIFEST_PATH)
	var tiles: Dictionary = JsonData.get_dictionary(atlas, "tiles", MANIFEST_PATH)
	for name: String in ["palme", "grappe_olivier", "touffe_alfa", "touffe_jonc"]:
		var rect: Array = JsonData.get_array(tiles[name], "rect", MANIFEST_PATH)
		var base: float = _coverage(image, 0, rect, unit, threshold)
		assert_gt(base, 0.05, name)
		for level: int in [1, 2, 3, 4]:
			var covered: float = _coverage(image, level, rect, unit, threshold)
			assert_almost_eq(covered, base, COVERAGE_TOLERANCE, "%s : couverture au niveau %d" % [name, level])


## Part des texels d'une tuile dont l'alpha dépasse le seuil, au niveau de mipmap demandé.
func _coverage(image: Image, level: int, rect: Array, unit: int, threshold: float) -> float:
	var size: int = image.get_width() >> level
	var data: PackedByteArray = image.get_data()
	var offset: int = image.get_mipmap_offset(level) if level > 0 else 0
	var x0: int = (int(rect[0]) * unit) >> level
	var y0: int = (int(rect[1]) * unit) >> level
	var x1: int = ((int(rect[0]) + int(rect[2])) * unit) >> level
	var y1: int = ((int(rect[1]) + int(rect[3])) * unit) >> level
	var above: int = 0
	for y: int in range(y0, y1):
		for x: int in range(x0, x1):
			if float(data[offset + (y * size + x) * 4 + 3]) / 255.0 > threshold:
				above += 1
	return float(above) / float((x1 - x0) * (y1 - y0))
