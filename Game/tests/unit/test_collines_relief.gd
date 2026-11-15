extends GutTest
## Relief et répartition des surfaces de la carte « collines ».

const DATA_PATH: String = "res://data/collines/collines.json"


func _terrain_config() -> Dictionary:
	return JsonData.get_dictionary(JsonData.load_dictionary(DATA_PATH), "terrain", DATA_PATH)


func test_relief_is_deterministic_for_a_fixed_seed() -> void:
	var config: Dictionary = _terrain_config()
	var start: int = Time.get_ticks_usec()
	var first: CollinesRelief = CollinesRelief.generate(config)
	var elapsed_ms: float = float(Time.get_ticks_usec() - start) / 1000.0
	var second: CollinesRelief = CollinesRelief.generate(config)
	assert_eq(hash(first.heights), hash(second.heights))
	gut.p("Relief de %d sommets : %.0f ms" % [first.heights.size(), elapsed_ms])


func test_other_seed_changes_the_relief() -> void:
	var config: Dictionary = _terrain_config().duplicate(true)
	var first: CollinesRelief = CollinesRelief.generate(config)
	(config["relief"] as Dictionary)["seed"] = 1406
	var second: CollinesRelief = CollinesRelief.generate(config)
	assert_ne(hash(first.heights), hash(second.heights))


func test_relief_covers_one_square_kilometer_with_hills() -> void:
	var relief: CollinesRelief = CollinesRelief.generate(_terrain_config())
	assert_eq(relief.size_px, 1025)
	assert_gte(float(relief.size_px - 1) * relief.spacing, 1000.0, "au moins 1 km de côté")
	var low: float = 1e9
	var high: float = -1e9
	for height: float in relief.heights:
		low = minf(low, height)
		high = maxf(high, height)
	assert_gt(high - low, 25.0, "un terrain vallonné, pas une plaine")
	assert_almost_eq(relief.heights[0], 0.0, 0.001, "le bord rejoint la plaine qui entoure la carte")


func test_surfaces_follow_slope_and_altitude() -> void:
	var config: Dictionary = _terrain_config()
	var relief: CollinesRelief = CollinesRelief.generate(config)
	var blend: PackedByteArray = relief.overlay_blend(JsonData.get_dictionary(config, "overlay_rules", DATA_PATH))
	assert_eq(blend.size(), relief.heights.size())
	var stone: int = 0
	for level: int in blend:
		if level >= 128:
			stone += 1
	var ratio: float = float(stone) / float(blend.size())
	assert_between(ratio, 0.05, 0.5, "la pierre couvre une part notable mais minoritaire du terrain")
	var steepest: int = 0
	for z: int in range(1, relief.size_px - 1, 4):
		for x: int in range(1, relief.size_px - 1, 4):
			if (
				relief.slope_tangent(x, z)
				> relief.slope_tangent(steepest % relief.size_px, floori(float(steepest) / float(relief.size_px)))
			):
				steepest = z * relief.size_px + x
	assert_gte(blend[steepest], 128, "la pente la plus forte est en pierre")
