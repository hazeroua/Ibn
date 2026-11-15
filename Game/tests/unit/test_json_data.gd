extends GutTest
## Lecture et validation des données JSON.


func test_reads_typed_values() -> void:
	var data: Dictionary = {
		"text": "abc",
		"flag": true,
		"number": 2.5,
		"integer": 3.0,
		"vec2": [1.0, 2.0],
		"vec3": [1.0, 2.0, 3.0],
		"color": "#ff0000",
		"object": {"a": 1.0},
		"list": [1.0],
	}
	assert_eq(JsonData.get_string(data, "text", "test"), "abc")
	assert_true(JsonData.get_bool(data, "flag", "test"))
	assert_almost_eq(JsonData.get_float(data, "number", "test"), 2.5, 0.0001)
	assert_eq(JsonData.get_int(data, "integer", "test"), 3)
	assert_eq(JsonData.get_vector2(data, "vec2", "test"), Vector2(1.0, 2.0))
	assert_eq(JsonData.get_vector3(data, "vec3", "test"), Vector3(1.0, 2.0, 3.0))
	assert_eq(JsonData.get_color(data, "color", "test"), Color(1.0, 0.0, 0.0))
	assert_eq(JsonData.get_dictionary(data, "object", "test").size(), 1)
	assert_eq(JsonData.get_array(data, "list", "test").size(), 1)


func test_defaults_when_optional_key_missing() -> void:
	var data: Dictionary = {}
	assert_almost_eq(JsonData.get_float_or(data, "absent", 4.0, "test"), 4.0, 0.0001)
	assert_eq(JsonData.get_vector3_or(data, "absent", Vector3.ONE, "test"), Vector3.ONE)


func test_project_data_files_are_valid() -> void:
	for path: String in [
		"res://data/input/actions.json",
		"res://data/sandbox/sandbox.json",
		"res://data/sandbox/viewpoints.json",
		"res://data/assets/polyhaven.json",
		"res://tests/perf/budgets/sandbox.json",
	]:
		assert_false(JsonData.load_dictionary(path).is_empty(), "%s doit être un objet JSON valide" % path)
