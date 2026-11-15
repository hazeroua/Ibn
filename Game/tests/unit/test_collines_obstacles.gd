extends GutTest
## Placement des obstacles de la carte « collines » : déterminisme, absence de chevauchement, pire cas de 1 000 obstacles.

const DATA_PATH: String = "res://data/collines/collines.json"


func _inputs() -> Dictionary:
	var config: Dictionary = JsonData.get_dictionary(JsonData.load_dictionary(DATA_PATH), "obstacles", DATA_PATH)
	var radii := PackedFloat32Array()
	var weights := PackedFloat32Array()
	for raw: Variant in JsonData.get_array(config, "types", DATA_PATH):
		var entry: Dictionary = raw
		radii.append(JsonData.get_float(entry, "footprint_radius_m", DATA_PATH))
		weights.append(JsonData.get_float(entry, "weight", DATA_PATH))
	return {"zone": JsonData.get_dictionary(config, "zone", DATA_PATH), "radii": radii, "weights": weights}


func _place(inputs: Dictionary) -> CollinesObstacles:
	return CollinesObstacles.place(inputs["zone"], inputs["radii"], inputs["weights"])


func test_same_seed_gives_same_positions() -> void:
	var inputs: Dictionary = _inputs()
	var first: CollinesObstacles = _place(inputs)
	var second: CollinesObstacles = _place(inputs)
	assert_not_null(first)
	assert_eq(hash(first.positions), hash(second.positions))
	assert_eq(first.type_indices, second.type_indices)
	assert_eq(hash(first.yaws), hash(second.yaws))


func test_other_seed_gives_other_positions() -> void:
	var inputs: Dictionary = _inputs()
	var first: CollinesObstacles = _place(inputs)
	var zone: Dictionary = (inputs["zone"] as Dictionary).duplicate()
	zone["seed"] = int(zone["seed"]) + 1
	inputs["zone"] = zone
	var second: CollinesObstacles = _place(inputs)
	assert_ne(hash(first.positions), hash(second.positions))


func test_worst_case_1000_obstacles_inside_radius_without_overlap() -> void:
	var inputs: Dictionary = _inputs()
	var zone: Dictionary = inputs["zone"]
	var radii: PackedFloat32Array = inputs["radii"]
	var start: int = Time.get_ticks_usec()
	var result: CollinesObstacles = _place(inputs)
	var elapsed_ms: float = float(Time.get_ticks_usec() - start) / 1000.0
	assert_not_null(result)
	assert_eq(result.positions.size(), 1000, "le contrat exige 1 000 obstacles")
	var center: Vector2 = JsonData.get_vector2(zone, "center", DATA_PATH)
	var radius: float = JsonData.get_float(zone, "radius_m", DATA_PATH)
	var gap: float = JsonData.get_float(zone, "gap_m", DATA_PATH)
	var outside: int = 0
	var overlaps: int = 0
	for i: int in result.positions.size():
		var footprint: float = radii[result.type_indices[i]]
		if result.positions[i].distance_to(center) + footprint > radius + 0.001:
			outside += 1
		for j: int in range(i + 1, result.positions.size()):
			var min_distance: float = footprint + radii[result.type_indices[j]] + gap - 0.001
			if result.positions[i].distance_squared_to(result.positions[j]) < min_distance * min_distance:
				overlaps += 1
	assert_eq(outside, 0, "tous les obstacles dans le rayon de la zone")
	assert_eq(overlaps, 0, "aucun chevauchement")
	gut.p("Placement de 1 000 obstacles (rayon %.0f m) : %.1f ms" % [radius, elapsed_ms])
