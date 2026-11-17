extends GutTest

const VALIDATOR_SCRIPT: String = "res://world/tunis/data/tunis_data_validator.gd"
const DATA_ROOT: String = "res://data/tunis/"


func test_initial_tunis_data_files_are_schema_valid() -> void:
	var errors: PackedStringArray = TunisDataValidator.validate_documents(
		JsonData.load_dictionary(DATA_ROOT + "city.json"),
		JsonData.load_dictionary(DATA_ROOT + "catalog.json"),
		[],
		JsonData.load_dictionary(DATA_ROOT + "interactions.json"),
		JsonData.load_dictionary(DATA_ROOT + "audio.json")
	)
	assert_eq(errors.size(), 0, "the versioned Tunis data must satisfy its own schema: %s" % errors)


func test_valid_documents_have_no_errors() -> void:
	var errors: PackedStringArray = TunisDataValidator.validate_documents(
		_city(), _catalog(), [_cell()], _interactions(), _audio()
	)
	assert_eq(errors.size(), 0, "valid Tunis documents must be accepted: %s" % errors)


func test_reports_missing_wrong_type_and_non_finite_values() -> void:
	var city: Dictionary = _city()
	city.erase("seed")
	city["cell_size_m"] = "64"
	var cell: Dictionary = _cell()
	var instance: Dictionary = cell["instances"][0]
	instance["position"] = [NAN, 0.0, 0.0]
	var errors: PackedStringArray = TunisDataValidator.validate_documents(
		city, _catalog(), [cell], _interactions(), _audio()
	)
	assert_true(_contains(errors, "city.seed is required."))
	assert_true(_contains(errors, "city.cell_size_m must be a number."))
	assert_true(_contains(errors, "cell.instances.position must contain finite numbers."))


func test_reports_invalid_scale_unknown_references_and_duplicate_ids() -> void:
	var first: Dictionary = _cell()
	var first_instance: Dictionary = first["instances"][0]
	first_instance["scale"] = [1.0, 0.0, 1.0]
	first_instance["prefab_id"] = "missing_prefab"
	first_instance["properties"] = {
		"interaction_id": "missing_interaction", "audio_id": "missing_audio"
	}
	var second: Dictionary = _cell()
	var errors: PackedStringArray = TunisDataValidator.validate_documents(
		_city(), _catalog(), [first, second], _interactions(), _audio()
	)
	assert_true(_contains(errors, "cell.instances.scale must contain positive values."))
	assert_true(_contains(errors, "cell.instances references unknown prefab_id: missing_prefab."))
	assert_true(
		_contains(errors, "cell.instances references unknown interaction: missing_interaction.")
	)
	assert_true(_contains(errors, "cell.instances references unknown audio zone: missing_audio."))
	assert_true(_contains(errors, "cell.instances has a duplicate instance id: gate_arch."))


func test_reports_cell_mismatch_catalog_asset_and_schema_version() -> void:
	var catalog: Dictionary = _catalog()
	var prefab: Dictionary = catalog["prefabs"][0]
	prefab["scene_path"] = "user://outside.tscn"
	var cell: Dictionary = _cell()
	var instance: Dictionary = cell["instances"][0]
	instance["cell"] = [1, 0]
	cell["schema_version"] = 2
	var errors: PackedStringArray = TunisDataValidator.validate_documents(
		_city(), catalog, [cell], _interactions(), _audio()
	)
	assert_true(
		_contains(errors, "catalog.prefabs.scene_path must stay under res://: user://outside.tscn.")
	)
	assert_true(_contains(errors, "cell.schema_version 2 is unsupported; expected 1."))
	assert_true(_contains(errors, "cell.instances.cell must match its containing cell."))


func test_cell_coordinates_handle_negative_boundaries() -> void:
	assert_eq(
		TunisDataValidator.cell_for_position(Vector3(-0.01, 0.0, -64.0), Vector3.ZERO, 64.0),
		Vector2i(-1, -1)
	)
	assert_eq(
		TunisDataValidator.cell_for_position(Vector3(-64.0, 0.0, 63.99), Vector3.ZERO, 64.0),
		Vector2i(-1, 0)
	)
	assert_eq(
		TunisDataValidator.cell_for_position(Vector3(64.0, 0.0, 64.0), Vector3.ZERO, 64.0),
		Vector2i(1, 1)
	)


func test_canonical_json_is_sorted_and_stable() -> void:
	var first := {"z": [3, {"b": true, "a": "é"}], "a": 1}
	var second := {"a": 1, "z": [3, {"a": "é", "b": true}]}
	var expected := '{"a":1,"z":[3,{"a":"é","b":true}]}'
	assert_eq(TunisDataValidator.canonical_json(first), expected)
	assert_eq(TunisDataValidator.canonical_json(first), TunisDataValidator.canonical_json(second))


func _city() -> Dictionary:
	return {
		"schema_version": 1,
		"seed": 1348,
		"origin": [0.0, 0.0, 0.0],
		"cell_size_m": 64.0,
		"bounds": {"min_cell": [-2, -2], "max_cell": [2, 2]},
		"cells": ["cells/cell_0_0.json"]
	}


func _catalog() -> Dictionary:
	return {
		"schema_version": 1,
		"prefabs":
		[
			{
				"id": "gate_arch",
				"scene_path": "res://assets/tunis/gate_arch.tscn",
				"footprint_m": [8.0, 4.0],
				"snap_points": [],
				"has_collision": true,
				"lods": [],
				"category": "gate"
			}
		]
	}


func _cell() -> Dictionary:
	return {
		"schema_version": 1,
		"cell": [0, 0],
		"instances":
		[
			{
				"id": "gate_arch",
				"prefab_id": "gate_arch",
				"cell": [0, 0],
				"position": [1.0, 0.0, 1.0],
				"rotation_y": 0.0,
				"scale": [1.0, 1.0, 1.0],
				"layer": "structure",
				"properties": {"interaction_id": "open_gate", "audio_id": "gate_zone"}
			}
		]
	}


func _interactions() -> Dictionary:
	return {"schema_version": 1, "interactions": [{"id": "open_gate"}]}


func _audio() -> Dictionary:
	return {"schema_version": 1, "zones": [{"id": "gate_zone"}]}


func _contains(errors: PackedStringArray, expected: String) -> bool:
	for message: String in errors:
		if message == expected:
			return true
	return false
