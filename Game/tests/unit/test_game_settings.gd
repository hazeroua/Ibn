extends GutTest


func test_profiles_are_complete_and_ordered() -> void:
	for profile: String in ["low", "balanced", "high", "ultra"]:
		assert_true(GameSettings.PRESETS.has(profile))
		var values: Dictionary = GameSettings.PRESETS[profile]
		for key: String in [
			"render_scale", "chunk_radius", "stream_budget_ms", "concurrent_builds", "shadows", "shadow_distance_m", "ssao", "max_fps"
		]:
			assert_true(values.has(key), "%s contient %s" % [profile, key])
	assert_lt(float(GameSettings.PRESETS["low"]["render_scale"]), float(GameSettings.PRESETS["ultra"]["render_scale"]))
	assert_lt(int(GameSettings.PRESETS["low"]["chunk_radius"]), int(GameSettings.PRESETS["ultra"]["chunk_radius"]))


func test_streaming_override_changes_real_world_streamer_values() -> void:
	var base: Dictionary = JsonData.load_dictionary("res://data/streaming/streaming.json")
	var low: Dictionary = GameSettings.streaming_config_for(base, GameSettings.PRESETS["low"])
	var ultra: Dictionary = GameSettings.streaming_config_for(base, GameSettings.PRESETS["ultra"])
	assert_lt(float(low["load_radius_m"]), float(ultra["load_radius_m"]))
	assert_lt(float(low["frame_budget_ms"]), float(ultra["frame_budget_ms"]))
	assert_lt(int(low["max_concurrent_builds"]), int(ultra["max_concurrent_builds"]))
	assert_eq(float(base["load_radius_m"]), 600.0, "le dictionnaire source reste immuable")


func test_chunk_estimate_grows_with_radius() -> void:
	var previous: int = 0
	for radius: int in range(1, 7):
		var count: int = GameSettings.estimated_chunk_count(radius)
		assert_gt(count, previous)
		previous = count
