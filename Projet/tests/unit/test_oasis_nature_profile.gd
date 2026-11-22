extends GutTest

const PROFILE_PATH := "res://data/assets/oasis_nature_profile.json"
const GAME_DESIGN_PROFILE_PATH := "res://data/assets/sahara_game_design_profile.json"
const ULTIMATE_PROFILE_PATH := "res://data/assets/ultimate_nature_profile.json"
const EXPECTED_SHA256 := "298f6732b872e4cf7b30e6e7abf9641c7f6dc6b326df37ac089533ed7e3d58c9"


func test_profile_is_metadata_only_and_bound_to_reviewed_archive() -> void:
	var profile := JsonData.load_dictionary(PROFILE_PATH)
	assert_eq(profile.get("archive_sha256"), EXPECTED_SHA256)
	assert_eq(profile.get("distribution"), "metadata_only_sources_excluded_from_git")
	assert_true(String(profile.get("source_root", "")).begins_with("res://assets_local/"))


func test_profile_contains_only_reviewed_oasis_families() -> void:
	var profile := JsonData.load_dictionary(PROFILE_PATH)
	var families := profile.get("families", {}) as Dictionary
	assert_eq(families.size(), 5)
	assert_true(families.has("large_rocks"))
	assert_true(families.has("round_pebbles"))
	assert_true(families.has("irrigated_grasses"))
	assert_true(families.has("dry_grasses"))
	assert_true(families.has("generic_shrub"))


func test_required_date_palm_is_explicitly_missing() -> void:
	var profile := JsonData.load_dictionary(PROFILE_PATH)
	var missing := profile.get("missing_required_assets", []) as Array
	assert_has(missing, "phoenix_dactylifera_date_palm")


func test_game_design_profile_keeps_route_clear_and_stress_budget_explicit() -> void:
	var profile := JsonData.load_dictionary(GAME_DESIGN_PROFILE_PATH)
	var gameplay := profile.get("gameplay", {}) as Dictionary
	var stress := profile.get("stress_test", {}) as Dictionary
	assert_eq(float(gameplay.get("clear_route_half_width_m", 0.0)) * 2.0, 10.0)
	assert_eq(int(stress.get("expected_instances", 0)), 1250)
	assert_eq(int(stress.get("grass_instances", 0)) + int(stress.get("pebble_instances", 0)) + int(stress.get("rock_instances", 0)), 1250)


func test_game_design_profile_has_three_distinct_lighting_states() -> void:
	var profile := JsonData.load_dictionary(GAME_DESIGN_PROFILE_PATH)
	var lighting := profile.get("lighting", {}) as Dictionary
	assert_eq(lighting.size(), 3)
	assert_true(lighting.has("dawn"))
	assert_true(lighting.has("day"))
	assert_true(lighting.has("sunset"))


func test_ultimate_complement_fills_landmark_gaps_without_publishing_sources() -> void:
	var profile := JsonData.load_dictionary(ULTIMATE_PROFILE_PATH)
	var selected := profile.get("selected_models", {}) as Dictionary
	var performance := profile.get("performance_budget", {}) as Dictionary
	assert_eq(profile.get("distribution"), "metadata_only_sources_excluded_from_git")
	assert_true(selected.has("adult_date_palm_landmarks"))
	assert_true(selected.has("dark_rock_landmark"))
	assert_eq(int(performance.get("normal_total_instances", 0)), 800)
	assert_eq(int(performance.get("stress_total_instances", 0)), 1262)
	assert_true(performance.get("intel_arc_validation_required"))


func test_export_excludes_local_asset_sources_and_review_laboratory() -> void:
	var export_presets := ConfigFile.new()
	assert_eq(export_presets.load("res://export_presets.cfg"), OK)
	var excluded := String(export_presets.get_value("preset.0", "exclude_filter", ""))
	assert_string_contains(excluded, "assets_local/*")
	assert_string_contains(excluded, "world/asset_lab/*")
	assert_string_contains(excluded, "outils/inspecter_assets_3d_locaux.gd")
