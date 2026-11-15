extends GutTest
## VegetationScatter (C++) : règles, déterminisme, absence de chevauchement, pire cas.
## Le champ de hauteurs du terrain n'existe pas dans cette branche : on utilise une doublure.

const RULES_PATH: String = "res://data/desert/vegetation.json"
const CELL_SIZE: float = 250.0
const ORIGIN: float = -2000.0
const OASIS_CENTER: Vector2 = Vector2(125.0, 125.0)
const OASIS_RADIUS: float = 90.0
const OASIS_CELL: Vector2i = Vector2i(8, 8)
const SEED: int = 1332


## Doublure du champ de hauteurs : dunes douces, falaise abrupte à partir de x = 700 m.
class FakeHeightfield:
	extends RefCounted

	var height_calls: int = 0
	var surface_calls: int = 0

	func height_at(x: float, z: float) -> float:
		height_calls += 1
		var h: float = 3.0 * sin(x * 0.01) * cos(z * 0.013) + 1.5 * sin(x * 0.05 + z * 0.03)
		if x > 700.0:
			h += (x - 700.0) * 0.8
		return h

	func surface_at(position: Vector3) -> StringName:
		surface_calls += 1
		if position.y > 3.0:
			return &"pierre"
		if position.y < -2.0:
			return &"terre"
		return &"sable"


func _new_scatter() -> VegetationScatter:
	var scatter := VegetationScatter.new()
	assert_true(scatter.load_rules(RULES_PATH), scatter.get_last_error())
	assert_true(scatter.set_oasis(OASIS_CENTER, OASIS_RADIUS))
	return scatter


func _instances(transforms: PackedFloat32Array) -> int:
	return transforms.size() / 12


func _origin_of(transforms: PackedFloat32Array, index: int) -> Vector3:
	return Vector3(transforms[index * 12 + 3], transforms[index * 12 + 7], transforms[index * 12 + 11])


func _write_json(name: String, content: Dictionary) -> String:
	var path: String = "user://%s.json" % name
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(content))
	file.close()
	return path


func test_class_is_registered_and_rules_are_valid() -> void:
	assert_true(ClassDB.class_exists(&"VegetationScatter"))
	var scatter: VegetationScatter = _new_scatter()
	var ids: PackedStringArray = scatter.get_species_ids()
	assert_eq(ids, PackedStringArray(["palmier", "buisson", "herbe_seche"]))
	var settings: Dictionary = scatter.get_species_settings()
	assert_true(float((settings[&"herbe_seche"] as Dictionary)["visibility_range_end"]) > 0.0)


func test_invalid_rules_are_refused_without_crashing() -> void:
	var scatter := VegetationScatter.new()
	assert_false(scatter.load_rules("res://data/desert/n_existe_pas.json"))
	assert_ne(scatter.get_last_error(), "")
	var data: Dictionary = JsonData.load_dictionary(RULES_PATH)
	((data["species"] as Array)[0] as Dictionary)["surfaces"] = ["glace"]
	assert_false(scatter.load_rules(_write_json("veg_bad_surface", data)))
	assert_true(scatter.get_last_error().contains("glace"))
	data = JsonData.load_dictionary(RULES_PATH)
	((data["species"] as Array)[0] as Dictionary)["oasis_density_curve"] = [[2.0, 1.0], [1.0, 1.0]]
	assert_false(scatter.load_rules(_write_json("veg_bad_curve", data)))


func test_scatter_refuses_missing_context() -> void:
	var scatter := VegetationScatter.new()
	var field := FakeHeightfield.new()
	assert_true(scatter.scatter(OASIS_CELL, field, SEED).is_empty())
	assert_true(scatter.load_rules(RULES_PATH))
	assert_true(scatter.scatter(OASIS_CELL, field, SEED).is_empty(), "sans oasis")
	assert_true(scatter.set_oasis(OASIS_CENTER, OASIS_RADIUS))
	assert_true(scatter.scatter(Vector2i(16, 0), field, SEED).is_empty(), "cellule hors du monde")
	assert_true(scatter.scatter(OASIS_CELL, null, SEED).is_empty(), "sans champ de hauteurs")
	assert_false(scatter.scatter(OASIS_CELL, field, SEED).is_empty())
	assert_eq(scatter.get_last_error(), "")


func test_output_is_multimesh_ready_and_inside_the_cell() -> void:
	var scatter: VegetationScatter = _new_scatter()
	var field := FakeHeightfield.new()
	var cell := Vector2i(7, 8)
	var result: Dictionary = scatter.scatter(cell, field, SEED)
	var x0: float = ORIGIN + cell.x * CELL_SIZE
	var z0: float = ORIGIN + cell.y * CELL_SIZE
	var total: int = 0
	for species: StringName in [&"palmier", &"buisson", &"herbe_seche"]:
		var transforms: PackedFloat32Array = result[species]
		assert_eq(transforms.size() % 12, 0, "12 réels par instance")
		total += _instances(transforms)
		for i: int in _instances(transforms):
			var p: Vector3 = _origin_of(transforms, i)
			assert_between(p.x, x0, x0 + CELL_SIZE)
			assert_between(p.z, z0, z0 + CELL_SIZE)
			# Base orthogonale avec échelle : colonnes non nulles.
			var basis := Basis(
				Vector3(transforms[i * 12], transforms[i * 12 + 4], transforms[i * 12 + 8]),
				Vector3(transforms[i * 12 + 1], transforms[i * 12 + 5], transforms[i * 12 + 9]),
				Vector3(transforms[i * 12 + 2], transforms[i * 12 + 6], transforms[i * 12 + 10])
			)
			assert_true(basis.determinant() > 0.01, "base directe et non dégénérée")
			assert_almost_eq(p.y, field.height_at(p.x, p.z), 4.0, "posé près du sol")
	assert_gt(total, 0)


func test_scatter_is_deterministic_and_seed_dependent() -> void:
	var scatter: VegetationScatter = _new_scatter()
	var field := FakeHeightfield.new()
	var first: Dictionary = scatter.scatter(OASIS_CELL, field, SEED)
	var second: Dictionary = scatter.scatter(OASIS_CELL, field, SEED)
	var other: Dictionary = scatter.scatter(OASIS_CELL, field, SEED + 1)
	var other_cell: Dictionary = scatter.scatter(Vector2i(8, 7), field, SEED)
	assert_eq(hash(first), hash(second))
	assert_ne(hash(first), hash(other))
	assert_ne(hash(first), hash(other_cell))
	# Une autre instance, des règles rechargées : même résultat.
	var fresh: VegetationScatter = _new_scatter()
	assert_eq(hash(first), hash(fresh.scatter(OASIS_CELL, field, SEED)))


func _collect_points(scatter: VegetationScatter, field: FakeHeightfield, cell: Vector2i) -> Array[Dictionary]:
	var radii: Dictionary = {}
	var settings: Dictionary = scatter.get_species_settings()
	for species: StringName in settings:
		radii[species] = float((settings[species] as Dictionary)["radius"])
	var result: Dictionary = scatter.scatter(cell, field, SEED)
	var points: Array[Dictionary] = []
	for species: StringName in result:
		var transforms: PackedFloat32Array = result[species]
		for i: int in _instances(transforms):
			var p: Vector3 = _origin_of(transforms, i)
			points.append({"species": species, "x": p.x, "z": p.z, "r": radii[species]})
	return points


## Vérifie sans O(n²) : compartiments de 6 m, voisinage 3 x 3 (le plus grand écart minimal vaut 4,4 m).
func _count_overlaps(points: Array[Dictionary]) -> int:
	var buckets: Dictionary = {}
	for p: Dictionary in points:
		var key := Vector2i(floori(float(p["x"]) / 6.0), floori(float(p["z"]) / 6.0))
		if not buckets.has(key):
			buckets[key] = []
		(buckets[key] as Array).append(p)
	var overlaps: int = 0
	for p: Dictionary in points:
		var base := Vector2i(floori(float(p["x"]) / 6.0), floori(float(p["z"]) / 6.0))
		for dx: int in range(-1, 2):
			for dz: int in range(-1, 2):
				var bucket: Array = buckets.get(base + Vector2i(dx, dz), [])
				for q: Dictionary in bucket:
					if q == p:
						continue
					var dist: float = Vector2(float(p["x"]) - float(q["x"]), float(p["z"]) - float(q["z"])).length()
					if dist < float(p["r"]) + float(q["r"]) - 0.0001:
						overlaps += 1
	return overlaps


func test_no_overlap_in_the_densest_cell() -> void:
	var scatter: VegetationScatter = _new_scatter()
	var points: Array[Dictionary] = _collect_points(scatter, FakeHeightfield.new(), OASIS_CELL)
	assert_gt(points.size(), 1000, "la cellule d'oasis est dense")
	assert_eq(_count_overlaps(points), 0)


func test_no_overlap_across_cell_borders() -> void:
	var scatter: VegetationScatter = _new_scatter()
	var field := FakeHeightfield.new()
	var all_points: Array[Dictionary] = []
	for cell: Vector2i in [Vector2i(7, 7), Vector2i(8, 7), Vector2i(7, 8), Vector2i(8, 8)]:
		all_points.append_array(_collect_points(scatter, field, cell))
	assert_eq(_count_overlaps(all_points), 0, "quatre cellules voisines autour de l'oasis")


func test_rules_are_respected() -> void:
	var scatter: VegetationScatter = _new_scatter()
	var field := FakeHeightfield.new()
	var rules: Dictionary = JsonData.load_dictionary(RULES_PATH)
	var by_id: Dictionary = {}
	for entry: Variant in rules["species"] as Array:
		by_id[(entry as Dictionary)["id"]] = entry
	# Cellule (10, 8) : x de 500 à 750, avec la falaise qui commence à 700 m.
	for cell: Vector2i in [OASIS_CELL, Vector2i(10, 8)]:
		var cell_x0: float = ORIGIN + cell.x * CELL_SIZE
		var cell_z0: float = ORIGIN + cell.y * CELL_SIZE
		var result: Dictionary = scatter.scatter(cell, field, SEED)
		for species: StringName in result:
			var rule: Dictionary = by_id[String(species)]
			var max_slope: float = deg_to_rad(float(rule["max_slope_deg"]))
			var transforms: PackedFloat32Array = result[species]
			for i: int in _instances(transforms):
				var p: Vector3 = _origin_of(transforms, i)
				var norm: float = Vector2(p.x, p.z).distance_to(OASIS_CENTER) / OASIS_RADIUS
				assert_between(norm, float(rule["oasis_distance_min"]) - 0.0001, float(rule["oasis_distance_max"]) + 0.0001)
				assert_between(p.y, float(rule["altitude_min"]) - 1.0, float(rule["altitude_max"]) + 1.0)
				# Pente vraie du terrain (différences finies), tolérance pour la grille de 5 m.
				var gx: float = (field.height_at(p.x + 1.0, p.z) - field.height_at(p.x - 1.0, p.z)) / 2.0
				var gz: float = (field.height_at(p.x, p.z + 1.0) - field.height_at(p.x, p.z - 1.0)) / 2.0
				assert_lt(atan(sqrt(gx * gx + gz * gz)), max_slope + deg_to_rad(6.0), "pente de %s" % species)
				# Surface du nœud de grille (5 m) le plus proche, comme dans le C++.
				var node_x: float = cell_x0 + roundf((p.x - cell_x0) / 5.0) * 5.0
				var node_z: float = cell_z0 + roundf((p.z - cell_z0) / 5.0) * 5.0
				var node := Vector3(node_x, field.height_at(node_x, node_z), node_z)
				var allowed: Array = rule["surfaces"]
				assert_true(allowed.has(String(field.surface_at(node))), "surface de %s" % species)
	# Sur la falaise (x > 760 m, pente ~39°), aucune plante : cellule (11, 8).
	var cliff: Dictionary = scatter.scatter(Vector2i(11, 8), field, SEED)
	for species: StringName in cliff:
		assert_eq(_instances(cliff[species]), 0, "falaise : %s" % species)


func test_density_follows_the_oasis_curve() -> void:
	var scatter: VegetationScatter = _new_scatter()
	var field := FakeHeightfield.new()
	var near: Dictionary = scatter.scatter(OASIS_CELL, field, SEED)
	var far: Dictionary = scatter.scatter(Vector2i(2, 2), field, SEED)
	assert_gt(_instances(near[&"palmier"]), 20, "palmeraie autour de l'oasis")
	assert_eq(_instances(far[&"palmier"]), 0, "pas de palmier loin de l'oasis")
	assert_eq(_instances(far[&"herbe_seche"]), 0)


func test_height_field_calls_do_not_depend_on_density() -> void:
	var scatter: VegetationScatter = _new_scatter()
	var field := FakeHeightfield.new()
	scatter.scatter(OASIS_CELL, field, SEED)
	var dense: Dictionary = scatter.get_last_stats()
	scatter.scatter(Vector2i(2, 2), field, SEED)
	var sparse: Dictionary = scatter.get_last_stats()
	assert_eq(int(dense["heightfield_calls"]), int(sparse["heightfield_calls"]), "appels fixes par cellule")
	assert_lt(int(dense["heightfield_calls"]), 6000)


## Pire cas : cellule d'oasis à densité maximale, puis 16 cellules visibles (anneau autour de l'oasis).
func test_worst_case_load() -> void:
	var scatter: VegetationScatter = _new_scatter()
	var field := FakeHeightfield.new()
	scatter.scatter(OASIS_CELL, field, SEED)
	var worst_ms: float = 0.0
	var instances: int = 0
	for _round: int in 5:
		var start: int = Time.get_ticks_usec()
		var result: Dictionary = scatter.scatter(OASIS_CELL, field, SEED)
		worst_ms = maxf(worst_ms, float(Time.get_ticks_usec() - start) / 1000.0)
		instances = 0
		for species: StringName in result:
			instances += _instances(result[species])
	var stats: Dictionary = scatter.get_last_stats()
	gut.p(
		(
			"Cellule d'oasis : %d instances, %d candidats, %d appels au terrain, pire temps %.2f ms (C++ %.2f ms)"
			% [instances, int(stats["attempts"]), int(stats["heightfield_calls"]), worst_ms, float(stats["duration_ms"])]
		)
	)

	var start_all: int = Time.get_ticks_usec()
	var cells: int = 0
	var total: int = 0
	for dz: int in range(6, 10):
		for dx: int in range(6, 10):
			var result: Dictionary = scatter.scatter(Vector2i(dx, dz), field, SEED)
			cells += 1
			for species: StringName in result:
				total += _instances(result[species])
	var all_ms: float = float(Time.get_ticks_usec() - start_all) / 1000.0
	gut.p("%d cellules visibles : %d instances, %.1f ms au total, %.2f ms par cellule" % [cells, total, all_ms, all_ms / cells])
	assert_eq(cells, 16)
	assert_lt(worst_ms, 40.0, "une cellule d'oasis en moins de 40 ms (tâche de fond, hors du fil de rendu)")
	assert_lt(all_ms, 400.0, "16 cellules en moins de 400 ms")
