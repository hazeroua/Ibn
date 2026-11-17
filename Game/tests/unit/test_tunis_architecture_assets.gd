extends GutTest

const MANIFEST_PATH: String = "res://data/assets/tunis_architecture.json"
const CATALOG_PATH: String = "res://data/tunis/catalog.json"
const ASSET_ROOT: String = "res://assets/tunis/"


func test_every_manifest_module_has_a_catalog_entry_and_a_generated_asset() -> void:
	var manifest: Dictionary = JsonData.load_dictionary(MANIFEST_PATH)
	var catalog: Dictionary = JsonData.load_dictionary(CATALOG_PATH)
	var prefabs: Array = JsonData.get_array(catalog, "prefabs", "catalog")
	var catalog_ids := {}
	for raw_prefab: Variant in prefabs:
		var prefab: Dictionary = raw_prefab
		catalog_ids[JsonData.get_string(prefab, "id", "catalog.prefabs")] = prefab
	for raw_module: Variant in JsonData.get_array(manifest, "modules", "manifest"):
		var module: Dictionary = raw_module
		var module_id: String = JsonData.get_string(module, "id", "manifest.modules")
		assert_true(catalog_ids.has(module_id), "catalogue entry missing for %s" % module_id)
		assert_true(
			FileAccess.file_exists(ASSET_ROOT + module_id + ".glb"),
			"generated GLB missing for %s" % module_id
		)


func test_triangle_budgets_are_positive_and_assets_are_under_res() -> void:
	var manifest: Dictionary = JsonData.load_dictionary(MANIFEST_PATH)
	for raw_module: Variant in JsonData.get_array(manifest, "modules", "manifest"):
		var module: Dictionary = raw_module
		assert_gt(JsonData.get_int(module, "max_triangles", "manifest.modules"), 0)
	var catalog: Dictionary = JsonData.load_dictionary(CATALOG_PATH)
	for raw_prefab: Variant in JsonData.get_array(catalog, "prefabs", "catalog"):
		var prefab: Dictionary = raw_prefab
		assert_true(
			JsonData.get_string(prefab, "scene_path", "catalog.prefabs").begins_with(
				"res://assets/tunis/"
			)
		)
