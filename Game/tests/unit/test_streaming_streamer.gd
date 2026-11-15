extends GutTest
## Streaming du monde (WorldStreamer, C++) : logique, signaux et test de charge du pire cas.

const CONFIG_PATH := "res://data/streaming/streaming.json"


## Fournisseur doublure : construit un Node3D léger par cellule, en simulant un coût de construction.
class FakeProvider:
	extends RefCounted
	var build_delay_us: int = 0
	var built: int = 0
	var fail_cell: Vector2i = Vector2i(-1, -1)
	var mutex := Mutex.new()

	func build_cell(cell: Vector2i) -> Node3D:
		if cell == fail_cell:
			return null
		if build_delay_us > 0:
			OS.delay_usec(build_delay_us)
		var node := Node3D.new()
		node.name = "Cell_%d_%d" % [cell.x, cell.y]
		for i: int in 8:
			var child := Node3D.new()
			node.add_child(child)
		mutex.lock()
		built += 1
		mutex.unlock()
		return node


var _streamer: WorldStreamer
var _provider: FakeProvider


func before_each() -> void:
	_streamer = WorldStreamer.new()
	_streamer.auto_update = false
	add_child(_streamer)
	_provider = FakeProvider.new()
	assert_true(_streamer.load_config(CONFIG_PATH))
	assert_true(_streamer.register_provider(_provider))


func after_each() -> void:
	_streamer.clear()
	_streamer.free()


func _settle(max_steps: int = 2000) -> void:
	for i: int in max_steps:
		_streamer.update(0.016)
		if _streamer.get_pending_count() == 0 and i > 2:
			return
		OS.delay_usec(500)


func test_class_exists() -> void:
	assert_true(ClassDB.class_exists(&"WorldStreamer"))


func test_config_is_in_data_file() -> void:
	var data: Dictionary = JsonData.load_dictionary(CONFIG_PATH)
	assert_eq(float(data["cell_size_m"]), 250.0)
	assert_eq(int(data["grid_size"]), 16)


func test_invalid_config_is_refused() -> void:
	var streamer := WorldStreamer.new()
	assert_false(streamer.configure({"cell_size_m": 250.0}))
	assert_push_error("réglage manquant")
	streamer.free()


func test_provider_without_build_cell_is_refused() -> void:
	var streamer := WorldStreamer.new()
	var bad := RefCounted.new()
	assert_false(streamer.register_provider(bad))
	assert_engine_error("build_cell")
	streamer.free()


func test_world_to_cell() -> void:
	assert_eq(_streamer.world_to_cell(Vector3(-1999.0, 0.0, -1999.0)), Vector2i(0, 0))
	assert_eq(_streamer.world_to_cell(Vector3(0.0, 0.0, 0.0)), Vector2i(8, 8))
	assert_eq(_streamer.world_to_cell(Vector3(1999.0, 0.0, 1999.0)), Vector2i(15, 15))
	assert_eq(_streamer.world_to_cell(Vector3(2500.0, 0.0, 0.0)), Vector2i(-1, -1))


func test_loads_cells_around_focus_and_emits_signals() -> void:
	watch_signals(_streamer)
	_streamer.set_focus(Vector3(10.0, 0.0, 10.0), Vector3.ZERO)
	_settle()
	assert_true(_streamer.is_cell_loaded(Vector2i(8, 8)))
	assert_not_null(_streamer.get_cell_node(Vector2i(8, 8)))
	assert_false(_streamer.is_cell_loaded(Vector2i(0, 0)))
	assert_signal_emitted(_streamer, "cell_loaded")
	assert_eq(_streamer.get_child_count(), _streamer.get_loaded_count())


func test_unloads_with_hysteresis() -> void:
	watch_signals(_streamer)
	_streamer.set_focus(Vector3(-1900.0, 0.0, -1900.0), Vector3.ZERO)
	_settle()
	assert_true(_streamer.is_cell_loaded(Vector2i(0, 0)))
	# Léger déplacement : la cellule d'origine reste (hystérésis), aucun déchargement.
	_streamer.set_focus(Vector3(-1500.0, 0.0, -1900.0), Vector3.ZERO)
	_settle()
	assert_true(_streamer.is_cell_loaded(Vector2i(0, 0)))
	assert_signal_not_emitted(_streamer, "cell_unloaded")
	# Éloignement net : la cellule est déchargée.
	_streamer.set_focus(Vector3(1900.0, 0.0, 1900.0), Vector3.ZERO)
	_settle()
	_settle()
	assert_false(_streamer.is_cell_loaded(Vector2i(0, 0)))
	assert_signal_emitted(_streamer, "cell_unloaded")


func test_velocity_anticipates_cells_ahead() -> void:
	_streamer.set_focus(Vector3(-1000.0, 0.0, 0.0), Vector3(15.0, 0.0, 0.0))
	_settle()
	# 6 s à 15 m/s = 90 m : le chargement s'étend vers l'avant.
	var ahead: Vector2i = _streamer.world_to_cell(Vector3(-1000.0 + 90.0 + 590.0, 0.0, 0.0))
	assert_true(_streamer.is_cell_loaded(ahead), "cellule devant chargée")


func test_failed_provider_is_reported_not_retried() -> void:
	_provider.fail_cell = Vector2i(8, 8)
	_streamer.set_focus(Vector3(10.0, 0.0, 10.0), Vector3.ZERO)
	_settle()
	assert_false(_streamer.is_cell_loaded(Vector2i(8, 8)))
	assert_true(_streamer.is_cell_loaded(Vector2i(8, 7)))
	assert_gt(int(_streamer.get_stats()["failures"]), 0)
	assert_push_error("n'a pas renvoyé de Node3D")


func _run_path(points: Array[Vector3], speed: float, label: String) -> void:
	_provider.build_delay_us = 3000
	_streamer.reset_stats()
	var dt := 1.0 / 20.0
	var pos: Vector3 = points[0]
	_streamer.set_focus(pos, Vector3.ZERO)
	_settle()
	_streamer.reset_stats()
	var missing_frames: int = 0
	var worst_ms: float = 0.0
	var frames: int = 0
	for i: int in range(1, points.size()):
		var target: Vector3 = points[i]
		var dir: Vector3 = (target - pos).normalized()
		var vel: Vector3 = dir * speed
		while pos.distance_to(target) > speed * dt:
			pos += vel * dt
			_streamer.set_focus(pos, vel)
			var t0: int = Time.get_ticks_usec()
			_streamer.update(dt)
			worst_ms = maxf(worst_ms, float(Time.get_ticks_usec() - t0) / 1000.0)
			frames += 1
			if not _streamer.is_cell_loaded(_streamer.world_to_cell(pos)):
				missing_frames += 1
			OS.delay_usec(1000)
	var stats: Dictionary = _streamer.get_stats()
	(
		gut
		. p(
			(
				"%s : %d images, pire update %.3f ms (budget %.1f), chargements %d, déchargements %d, cellule joueur absente %d images"
				% [
					label,
					frames,
					worst_ms,
					float(stats["budget_ms"]),
					int(stats["loads"]),
					int(stats["unloads"]),
					missing_frames,
				]
			)
		)
	)
	# Tolérance : au plus 0,05 % des images, pour absorber une préemption du système sur une machine chargée
	# (le coût typique mesuré est de 0,1 à 0,5 ms pour un budget de 2 ms).
	assert_lte(int(stats["over_budget_frames"]), int(float(frames) * 0.0005), "images au-delà du budget")
	assert_eq(missing_frames, 0, "la cellule du joueur est toujours chargée")
	assert_lte(_streamer.get_loaded_count(), 256)


func test_load_gallop_straight_line() -> void:
	var points: Array[Vector3] = [Vector3(-1900.0, 0.0, -1900.0), Vector3(1900.0, 0.0, -1900.0)]
	_run_path(points, 15.0, "galop en ligne droite (3800 m)")


func test_load_gallop_zigzag() -> void:
	var points: Array[Vector3] = [Vector3(-1900.0, 0.0, -1900.0)]
	for k: int in 6:
		var x: float = -1900.0 + 600.0 * float(k + 1)
		points.append(Vector3(x, 0.0, 1900.0 if k % 2 == 0 else -1900.0))
	_run_path(points, 15.0, "galop en zigzag")
