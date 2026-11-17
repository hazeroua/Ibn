class_name TunisDataValidator
extends RefCounted
## Valide les données versionnées de Tunis avant toute construction de scène.
## Les fonctions retournent toutes les erreurs rencontrées afin que le pipeline puisse les signaler
## en une exécution, sans jamais générer une ville partielle à partir de données incertaines.

const SCHEMA_VERSION: int = 1


static func validate_documents(
	city: Dictionary, catalog: Dictionary, cells: Array, interactions: Dictionary, audio: Dictionary
) -> PackedStringArray:
	var errors := PackedStringArray()
	_validate_city(city, errors)
	var prefab_ids: Dictionary = _validate_catalog(catalog, errors)
	var interaction_ids: Dictionary = _validate_id_list(
		interactions, "interactions", "interaction", errors
	)
	var audio_ids: Dictionary = _validate_id_list(audio, "zones", "audio zone", errors)
	var instance_ids := {}
	for raw_cell: Variant in cells:
		if typeof(raw_cell) != TYPE_DICTIONARY:
			errors.append("cells: each entry must be an object.")
			continue
		_validate_cell(raw_cell, city, prefab_ids, interaction_ids, audio_ids, instance_ids, errors)
	return errors


static func validate_and_report(
	city: Dictionary, catalog: Dictionary, cells: Array, interactions: Dictionary, audio: Dictionary
) -> bool:
	var errors: PackedStringArray = validate_documents(city, catalog, cells, interactions, audio)
	for message: String in errors:
		push_error("Tunis data: " + message)
	return errors.is_empty()


static func canonical_json(value: Variant) -> String:
	return _canonical_json(value)


static func cell_for_position(position: Vector3, origin: Vector3, cell_size_m: float) -> Vector2i:
	return Vector2i(
		floori((position.x - origin.x) / cell_size_m), floori((position.z - origin.z) / cell_size_m)
	)


static func _validate_city(city: Dictionary, errors: PackedStringArray) -> void:
	var context := "city"
	_validate_schema_version(city, context, errors)
	_require_int(city, "seed", context, errors)
	var origin: Vector3 = _require_vector3(city, "origin", context, errors)
	var cell_size: float = _require_number(city, "cell_size_m", context, errors)
	if cell_size <= 0.0:
		errors.append("%s.cell_size_m must be greater than zero." % context)
	if not origin.is_finite():
		errors.append("%s.origin must contain finite numbers." % context)
	var bounds: Dictionary = _require_dictionary(city, "bounds", context, errors)
	var min_cell: Vector2i = _require_vector2i(bounds, "min_cell", context + ".bounds", errors)
	var max_cell: Vector2i = _require_vector2i(bounds, "max_cell", context + ".bounds", errors)
	if min_cell.x > max_cell.x or min_cell.y > max_cell.y:
		errors.append("%s.bounds min_cell must not exceed max_cell." % context)
	var cell_paths: Array = _require_array(city, "cells", context, errors)
	var seen_paths := {}
	for raw_path: Variant in cell_paths:
		if typeof(raw_path) != TYPE_STRING:
			errors.append("%s.cells entries must be strings." % context)
			continue
		var cell_path: String = raw_path
		if cell_path.is_empty() or cell_path.begins_with("/") or cell_path.contains(".."):
			errors.append("%s.cells contains an invalid relative path: %s." % [context, cell_path])
		if seen_paths.has(cell_path):
			errors.append("%s.cells contains a duplicate path: %s." % [context, cell_path])
		seen_paths[cell_path] = true


static func _validate_catalog(catalog: Dictionary, errors: PackedStringArray) -> Dictionary:
	var context := "catalog"
	_validate_schema_version(catalog, context, errors)
	var prefabs: Array = _require_array(catalog, "prefabs", context, errors)
	var ids := {}
	for raw_prefab: Variant in prefabs:
		if typeof(raw_prefab) != TYPE_DICTIONARY:
			errors.append("%s.prefabs entries must be objects." % context)
			continue
		var prefab: Dictionary = raw_prefab
		var prefab_context := context + ".prefabs"
		var prefab_id: String = _require_id(prefab, "id", prefab_context, errors)
		if not prefab_id.is_empty():
			if ids.has(prefab_id):
				errors.append("%s has a duplicate prefab id: %s." % [prefab_context, prefab_id])
			ids[prefab_id] = true
		var scene_path: String = _require_string(prefab, "scene_path", prefab_context, errors)
		if not scene_path.is_empty() and not scene_path.begins_with("res://"):
			errors.append(
				"%s.scene_path must stay under res://: %s." % [prefab_context, scene_path]
			)
		var footprint: Vector2 = _require_vector2(prefab, "footprint_m", prefab_context, errors)
		if footprint.x <= 0.0 or footprint.y <= 0.0:
			errors.append("%s.footprint_m must contain positive values." % prefab_context)
		_require_array(prefab, "snap_points", prefab_context, errors)
		_require_bool(prefab, "has_collision", prefab_context, errors)
		_require_array(prefab, "lods", prefab_context, errors)
		_require_string(prefab, "category", prefab_context, errors)
	return ids


static func _validate_cell(
	cell_data: Dictionary,
	city: Dictionary,
	prefab_ids: Dictionary,
	interaction_ids: Dictionary,
	audio_ids: Dictionary,
	instance_ids: Dictionary,
	errors: PackedStringArray
) -> void:
	var context := "cell"
	_validate_schema_version(cell_data, context, errors)
	var cell: Vector2i = _require_vector2i(cell_data, "cell", context, errors)
	var instances: Array = _require_array(cell_data, "instances", context, errors)
	var origin: Vector3 = _require_vector3(city, "origin", "city", errors)
	var cell_size: float = _require_number(city, "cell_size_m", "city", errors)
	for raw_instance: Variant in instances:
		if typeof(raw_instance) != TYPE_DICTIONARY:
			errors.append("%s.instances entries must be objects." % context)
			continue
		var instance: Dictionary = raw_instance
		var instance_context := context + ".instances"
		var instance_id: String = _require_id(instance, "id", instance_context, errors)
		if not instance_id.is_empty():
			if instance_ids.has(instance_id):
				errors.append(
					"%s has a duplicate instance id: %s." % [instance_context, instance_id]
				)
			instance_ids[instance_id] = true
		var prefab_id: String = _require_id(instance, "prefab_id", instance_context, errors)
		if not prefab_id.is_empty() and not prefab_ids.has(prefab_id):
			errors.append("%s references unknown prefab_id: %s." % [instance_context, prefab_id])
		var declared_cell: Vector2i = _require_vector2i(instance, "cell", instance_context, errors)
		if declared_cell != cell:
			errors.append("%s.cell must match its containing cell." % instance_context)
		var position: Vector3 = _require_vector3(instance, "position", instance_context, errors)
		if not position.is_finite():
			errors.append("%s.position must contain finite numbers." % instance_context)
		elif cell_size > 0.0:
			var expected_cell: Vector2i = cell_for_position(position, origin, cell_size)
			if expected_cell != cell:
				errors.append(
					(
						"%s.position belongs to cell %s, not %s."
						% [instance_context, expected_cell, cell]
					)
				)
		var rotation_y: float = _require_number(instance, "rotation_y", instance_context, errors)
		if not is_finite(rotation_y):
			errors.append("%s.rotation_y must be finite." % instance_context)
		var scale: Vector3 = _require_vector3(instance, "scale", instance_context, errors)
		if scale.x <= 0.0 or scale.y <= 0.0 or scale.z <= 0.0:
			errors.append("%s.scale must contain positive values." % instance_context)
		_require_string(instance, "layer", instance_context, errors)
		var properties: Dictionary = _require_dictionary(
			instance, "properties", instance_context, errors
		)
		_validate_optional_reference(
			properties, "interaction_id", interaction_ids, "interaction", instance_context, errors
		)
		_validate_optional_reference(
			properties, "audio_id", audio_ids, "audio zone", instance_context, errors
		)


static func _validate_id_list(
	data: Dictionary, array_key: String, item_name: String, errors: PackedStringArray
) -> Dictionary:
	var context := item_name
	_validate_schema_version(data, context, errors)
	var entries: Array = _require_array(data, array_key, context, errors)
	var ids := {}
	for raw_entry: Variant in entries:
		if typeof(raw_entry) != TYPE_DICTIONARY:
			errors.append("%s.%s entries must be objects." % [context, array_key])
			continue
		var entry: Dictionary = raw_entry
		var entry_id: String = _require_id(entry, "id", context + "." + array_key, errors)
		if not entry_id.is_empty():
			if ids.has(entry_id):
				errors.append("%s.%s has a duplicate id: %s." % [context, array_key, entry_id])
			ids[entry_id] = true
	return ids


static func _validate_optional_reference(
	properties: Dictionary,
	key: String,
	ids: Dictionary,
	target_name: String,
	context: String,
	errors: PackedStringArray
) -> void:
	if not properties.has(key):
		return
	if typeof(properties[key]) != TYPE_STRING:
		errors.append("%s.properties.%s must be a string." % [context, key])
		return
	var reference: String = properties[key]
	if not ids.has(reference):
		errors.append("%s references unknown %s: %s." % [context, target_name, reference])


static func _validate_schema_version(
	data: Dictionary, context: String, errors: PackedStringArray
) -> void:
	var version: int = _require_int(data, "schema_version", context, errors)
	if version != SCHEMA_VERSION:
		errors.append(
			"%s.schema_version %d is unsupported; expected %d." % [context, version, SCHEMA_VERSION]
		)


static func _require_dictionary(
	data: Dictionary, key: String, context: String, errors: PackedStringArray
) -> Dictionary:
	if not data.has(key):
		errors.append("%s.%s is required." % [context, key])
		return {}
	if typeof(data[key]) != TYPE_DICTIONARY:
		errors.append("%s.%s must be an object." % [context, key])
		return {}
	return data[key]


static func _require_array(
	data: Dictionary, key: String, context: String, errors: PackedStringArray
) -> Array:
	if not data.has(key):
		errors.append("%s.%s is required." % [context, key])
		return []
	if typeof(data[key]) != TYPE_ARRAY:
		errors.append("%s.%s must be an array." % [context, key])
		return []
	return data[key]


static func _require_string(
	data: Dictionary, key: String, context: String, errors: PackedStringArray
) -> String:
	if not data.has(key):
		errors.append("%s.%s is required." % [context, key])
		return ""
	if typeof(data[key]) != TYPE_STRING:
		errors.append("%s.%s must be a string." % [context, key])
		return ""
	return data[key]


static func _require_id(
	data: Dictionary, key: String, context: String, errors: PackedStringArray
) -> String:
	var value: String = _require_string(data, key, context, errors)
	if not value.is_empty() and not value.is_valid_identifier():
		errors.append("%s.%s must be a stable snake_case identifier." % [context, key])
	return value


static func _require_bool(
	data: Dictionary, key: String, context: String, errors: PackedStringArray
) -> bool:
	if not data.has(key):
		errors.append("%s.%s is required." % [context, key])
		return false
	if typeof(data[key]) != TYPE_BOOL:
		errors.append("%s.%s must be a boolean." % [context, key])
		return false
	return data[key]


static func _require_number(
	data: Dictionary, key: String, context: String, errors: PackedStringArray
) -> float:
	if not data.has(key):
		errors.append("%s.%s is required." % [context, key])
		return 0.0
	var value: Variant = data[key]
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		errors.append("%s.%s must be a number." % [context, key])
		return 0.0
	var number: float = float(value)
	if not is_finite(number):
		errors.append("%s.%s must be finite." % [context, key])
	return number


static func _require_int(
	data: Dictionary, key: String, context: String, errors: PackedStringArray
) -> int:
	var value: float = _require_number(data, key, context, errors)
	if not is_equal_approx(value, roundf(value)):
		errors.append("%s.%s must be an integer." % [context, key])
	return int(roundf(value))


static func _require_vector2(
	data: Dictionary, key: String, context: String, errors: PackedStringArray
) -> Vector2:
	var values: Array = _require_array(data, key, context, errors)
	if values.size() != 2:
		if data.has(key):
			errors.append("%s.%s must contain exactly two numbers." % [context, key])
		return Vector2.ZERO
	var x: float = _number_at(values, 0, context + "." + key, errors)
	var y: float = _number_at(values, 1, context + "." + key, errors)
	return Vector2(x, y)


static func _require_vector2i(
	data: Dictionary, key: String, context: String, errors: PackedStringArray
) -> Vector2i:
	var values: Array = _require_array(data, key, context, errors)
	if values.size() != 2:
		if data.has(key):
			errors.append("%s.%s must contain exactly two integers." % [context, key])
		return Vector2i.ZERO
	var x: float = _number_at(values, 0, context + "." + key, errors)
	var y: float = _number_at(values, 1, context + "." + key, errors)
	if not is_equal_approx(x, roundf(x)) or not is_equal_approx(y, roundf(y)):
		errors.append("%s.%s must contain integers." % [context, key])
	return Vector2i(int(roundf(x)), int(roundf(y)))


static func _require_vector3(
	data: Dictionary, key: String, context: String, errors: PackedStringArray
) -> Vector3:
	var values: Array = _require_array(data, key, context, errors)
	if values.size() != 3:
		if data.has(key):
			errors.append("%s.%s must contain exactly three numbers." % [context, key])
		return Vector3.ZERO
	var x: float = _number_at(values, 0, context + "." + key, errors)
	var y: float = _number_at(values, 1, context + "." + key, errors)
	var z: float = _number_at(values, 2, context + "." + key, errors)
	return Vector3(x, y, z)


static func _number_at(
	values: Array, index: int, context: String, errors: PackedStringArray
) -> float:
	var value: Variant = values[index]
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		errors.append("%s[%d] must be a number." % [context, index])
		return 0.0
	var number: float = float(value)
	if not is_finite(number):
		errors.append("%s[%d] must be finite." % [context, index])
	return number


static func _canonical_json(value: Variant) -> String:
	match typeof(value):
		TYPE_DICTIONARY:
			var dictionary: Dictionary = value
			var keys: Array = dictionary.keys()
			keys.sort()
			var entries := PackedStringArray()
			for raw_key: Variant in keys:
				entries.append(
					JSON.stringify(String(raw_key)) + ":" + _canonical_json(dictionary[raw_key])
				)
			return "{" + ",".join(entries) + "}"
		TYPE_ARRAY:
			var array: Array = value
			var entries := PackedStringArray()
			for entry: Variant in array:
				entries.append(_canonical_json(entry))
			return "[" + ",".join(entries) + "]"
		_:
			return JSON.stringify(value)
