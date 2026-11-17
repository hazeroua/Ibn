extends GutTest

const GRID_SIZE: int = 5
const CELL_SIZE: float = 64.0
const MIN_CELL: int = -2
const CYCLES: int = 200


func test_provider_builds_twenty_five_cells_in_deterministic_order() -> void:
	var provider := _provider()
	assert_not_null(provider)
	assert_eq(provider.cell_count(), 25)
	for stream_x: int in GRID_SIZE:
		for stream_z: int in GRID_SIZE:
			var stream_cell := Vector2i(stream_x, stream_z)
			var logical_cell := stream_cell + Vector2i(MIN_CELL, MIN_CELL)
			var cell: Node3D = provider.build_cell(stream_cell)
			assert_eq(cell.name, "TunisCell_%d_%d" % [logical_cell.x, logical_cell.y])
			assert_eq(cell.get_child_count(), 2)
			assert_lt(String(cell.get_child(0).name), String(cell.get_child(1).name))
			assert_true(cell.get_child(0).has_meta(&"franchissable"), "les remparts sont explicitement bloquants")
			assert_false(bool(cell.get_child(0).get_meta(&"franchissable")))
			assert_eq(
				cell.position,
				Vector3(float(logical_cell.x) * CELL_SIZE, 0.0, float(logical_cell.y) * CELL_SIZE)
			)
			cell.free()


func test_real_streamer_has_deterministic_loading_order() -> void:
	var first: Array[Vector2i] = await _loading_order()
	var second: Array[Vector2i] = await _loading_order()
	assert_gt(first.size(), 0)
	assert_eq(first, second)


func test_real_streamer_cycles_without_duplicates_or_growth() -> void:
	var baseline_nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var streamer := _streamer()
	streamer.reset_stats()
	var maximum_loaded: int = 0
	for cycle: int in CYCLES:
		var stream_cell := Vector2i.ZERO if cycle % 2 == 0 else Vector2i(4, 4)
		streamer.set_focus(_stream_cell_center(stream_cell), Vector3.ZERO)
		await _settle(streamer)
		maximum_loaded = maxi(maximum_loaded, streamer.get_loaded_count())
		var names: Dictionary = {}
		for raw_loaded: Vector2 in streamer.get_loaded_cells():
			var node: Node3D = streamer.get_cell_node(Vector2i(raw_loaded))
			assert_not_null(node)
			assert_false(names.has(node.name), "aucune cellule dupliquée")
			names[node.name] = true
	var stats: Dictionary = streamer.get_stats()
	(
		gut
		. p(
			(
				"Tunis %d cycles : pic %.3f ms, %d dépassements, %d chargements, %d déchargements"
				% [
					CYCLES,
					float(stats["max_update_ms"]),
					int(stats["over_budget_frames"]),
					int(stats["loads"]),
					int(stats["unloads"]),
				]
			)
		)
	)
	assert_lte(maximum_loaded, 25)
	assert_eq(int(stats["failures"]), 0)
	assert_lt(float(stats["over_budget_frames"]) / maxf(1.0, float(stats["updates"])), 0.02)
	streamer.clear()
	streamer.free()
	await get_tree().process_frame
	await get_tree().process_frame
	var final_nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	assert_lte(final_nodes, baseline_nodes + 2, "le compteur de nœuds revient à son niveau initial")


func test_pinned_cell_survives_distance_and_force_load_covers_grid() -> void:
	var streamer := _streamer()
	streamer.set_focus(_stream_cell_center(Vector2i.ZERO), Vector3.ZERO)
	assert_true(streamer.set_cell_pinned(Vector2i(4, 4), true))
	await _settle(streamer)
	assert_true(streamer.is_cell_loaded(Vector2i(4, 4)))
	streamer.set_all_cells_pinned(true)
	await _settle(streamer)
	assert_eq(streamer.get_loaded_count(), 25)
	streamer.set_all_cells_pinned(false)
	await _settle(streamer)
	assert_true(
		streamer.is_cell_loaded(Vector2i(4, 4)),
		"le forçage ne supprime pas un épinglage individuel"
	)
	assert_true(streamer.set_cell_pinned(Vector2i(4, 4), false))
	await _settle(streamer)
	assert_false(streamer.is_cell_loaded(Vector2i(4, 4)))
	streamer.clear()
	streamer.free()


func test_runtime_registry_tracks_instances_and_logical_pins() -> void:
	var streamer := WorldStreamer.new()
	streamer.auto_update = false
	var runtime := TunisRuntime.new()
	assert_true(runtime.initialize(_provider(), streamer))
	add_child(runtime)
	runtime.set_focus(_stream_cell_center(Vector2i.ZERO), Vector3.ZERO)
	assert_true(runtime.pin_cell(Vector2i(2, 2)))
	assert_true(runtime.pin_cell(Vector2i(2, 2)))
	await _settle(streamer)
	assert_true(streamer.is_cell_loaded(Vector2i(4, 4)))
	assert_gt(runtime.loaded_instance_count(), 0)
	assert_not_null(runtime.get_instance_by_id(&"object_p2_p2_a"))
	assert_true(runtime.unpin_cell(Vector2i(2, 2)))
	await _settle(streamer)
	assert_not_null(
		runtime.get_instance_by_id(&"object_p2_p2_a"), "un second utilisateur conserve l'intérieur"
	)
	assert_true(runtime.unpin_cell(Vector2i(2, 2)))
	await _settle(streamer)
	assert_null(runtime.get_instance_by_id(&"object_p2_p2_a"))
	streamer.clear()
	runtime.free()


func _loading_order() -> Array[Vector2i]:
	var streamer := _streamer()
	var order: Array[Vector2i] = []
	streamer.cell_loaded.connect(func(cell: Vector2i) -> void: order.append(cell))
	streamer.set_focus(Vector3.ZERO, Vector3.ZERO)
	await _settle(streamer)
	streamer.clear()
	streamer.free()
	return order


func _streamer() -> WorldStreamer:
	var streamer := WorldStreamer.new()
	streamer.auto_update = false
	add_child(streamer)
	assert_true(streamer.load_config("res://data/tunis/streaming.json"))
	assert_true(streamer.register_provider(_provider()))
	return streamer


func _settle(streamer: WorldStreamer) -> void:
	for step: int in 4000:
		streamer.update(0.016)
		if (
			streamer.get_pending_count() == 0
			and int(streamer.get_stats()["doomed"]) == 0
			and step > 2
		):
			return
		await get_tree().process_frame
	fail_test("streaming de Tunis non stabilisé")


func _stream_cell_center(stream_cell: Vector2i) -> Vector3:
	return Vector3(
		(float(stream_cell.x) + 0.5) * CELL_SIZE - 128.0,
		0.0,
		(float(stream_cell.y) + 0.5) * CELL_SIZE - 128.0
	)


func _provider() -> TunisCellProvider:
	var packed := PackedScene.new()
	var template := Node3D.new()
	template.name = "Architecture"
	assert_eq(packed.pack(template), OK)
	template.free()
	var catalog := {
		"schema_version": 1,
		"prefabs":
		[
			{
				"id": "test_arch",
				"scene_path": "res://test.tscn",
				"footprint_m": [1.0, 1.0],
				"snap_points": [],
				"has_collision": true,
				"lods": [],
				"category": "test"
			}
		]
	}
	var cells: Array = []
	var paths: Array = []
	for logical_x: int in range(MIN_CELL, MIN_CELL + GRID_SIZE):
		for logical_z: int in range(MIN_CELL, MIN_CELL + GRID_SIZE):
			paths.append("cells/cell_%d_%d.json" % [logical_x, logical_z])
			var instances: Array = []
			for suffix: String in ["b", "a"]:
				instances.append(_instance(logical_x, logical_z, suffix))
			cells.append(
				{"schema_version": 1, "cell": [logical_x, logical_z], "instances": instances}
			)
	var city := {
		"schema_version": 1,
		"seed": 1348,
		"origin": [0.0, 0.0, 0.0],
		"cell_size_m": CELL_SIZE,
		"bounds": {"min_cell": [MIN_CELL, MIN_CELL], "max_cell": [2, 2]},
		"cells": paths
	}
	return TunisCellProvider.from_documents(
		city,
		catalog,
		cells,
		{"schema_version": 1, "interactions": []},
		{"schema_version": 1, "zones": []},
		{&"test_arch": packed}
	)


func _instance(x: int, z: int, suffix: String) -> Dictionary:
	return {
		"id": "object_%s_%s_%s" % [_coordinate_token(x), _coordinate_token(z), suffix],
		"prefab_id": "test_arch",
		"cell": [x, z],
		"position":
		[float(x) * CELL_SIZE + 2.0, 0.0, float(z) * CELL_SIZE + (2.0 if suffix == "a" else 4.0)],
		"rotation_y": 0.0,
		"scale": [1.0, 1.0, 1.0],
		"layer": "rampart" if suffix == "a" else "structure",
		"properties": {}
	}


func _coordinate_token(value: int) -> String:
	if value < 0:
		return "m%d" % absi(value)
	if value > 0:
		return "p%d" % value
	return "z0"
