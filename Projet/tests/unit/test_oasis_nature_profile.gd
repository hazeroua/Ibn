extends GutTest

const PROFILE_PATH := "res://data/assets/oasis_nature_profile.json"
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
