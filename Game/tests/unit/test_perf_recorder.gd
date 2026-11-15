extends GutTest
## Extension C++ : chargement et calculs de PerfRecorder.


func test_extension_is_loaded() -> void:
	assert_true(ClassDB.class_exists(&"PerfRecorder"), "l'extension C++ doit être chargée")


func test_reserve_rejects_invalid_capacity() -> void:
	var recorder := PerfRecorder.new()
	assert_false(recorder.reserve(0))
	assert_eq(recorder.get_capacity(), 0)


func test_add_frame_refuses_beyond_capacity() -> void:
	var recorder := PerfRecorder.new()
	assert_true(recorder.reserve(2))
	assert_true(recorder.add_frame(1.0, 0.5, 0.5, 1, 10))
	assert_true(recorder.add_frame(2.0, 0.5, 0.5, 1, 10))
	assert_false(recorder.add_frame(3.0, 0.5, 0.5, 1, 10), "la capacité ne doit jamais grandir pendant la mesure")
	assert_eq(recorder.get_count(), 2)


func test_add_frame_refuses_invalid_values() -> void:
	var recorder := PerfRecorder.new()
	assert_true(recorder.reserve(4))
	assert_false(recorder.add_frame(-1.0, 0.0, 0.0, 0, 0))
	assert_false(recorder.add_frame(NAN, 0.0, 0.0, 0, 0))
	assert_false(recorder.add_frame(1.0, 0.0, 0.0, -1, 0))
	assert_eq(recorder.get_count(), 0)


func test_summary_on_known_series() -> void:
	var recorder := PerfRecorder.new()
	assert_true(recorder.reserve(100))
	# Valeurs 100, 99, …, 1 ms : ordre inverse pour vérifier que les centiles ne dépendent pas de l'ordre.
	for i: int in 100:
		assert_true(recorder.add_frame(float(100 - i), 1.0, 2.0, i, i * 10))
	var summary: Dictionary = recorder.compute_summary()
	assert_eq(int(summary["frames"]), 100)
	assert_almost_eq(float(summary["frame_avg_ms"]), 50.5, 0.0001)
	assert_almost_eq(float(summary["frame_p50_ms"]), 50.0, 0.0001)
	assert_almost_eq(float(summary["frame_p95_ms"]), 95.0, 0.0001)
	assert_almost_eq(float(summary["frame_p99_ms"]), 99.0, 0.0001)
	assert_almost_eq(float(summary["frame_max_ms"]), 100.0, 0.0001)
	# Pire 1 % de 100 images = la seule image à 100 ms, soit 10 images par seconde.
	assert_almost_eq(float(summary["fps_1pct_low"]), 10.0, 0.0001)
	assert_almost_eq(float(summary["cpu_avg_ms"]), 1.0, 0.0001)
	assert_almost_eq(float(summary["gpu_p99_ms"]), 2.0, 0.0001)
	assert_eq(int(summary["draw_calls_max"]), 99)
	assert_eq(int(summary["primitives_max"]), 990)


func test_series_are_exported_in_order() -> void:
	var recorder := PerfRecorder.new()
	assert_true(recorder.reserve(3))
	assert_true(recorder.add_frame(3.0, 0.0, 0.0, 7, 70))
	assert_true(recorder.add_frame(1.0, 0.0, 0.0, 8, 80))
	var frames: PackedFloat32Array = recorder.get_frame_ms()
	assert_eq(frames.size(), 2)
	assert_almost_eq(frames[0], 3.0, 0.0001)
	assert_almost_eq(frames[1], 1.0, 0.0001)
	assert_eq(recorder.get_draw_calls(), PackedInt64Array([7, 8]))


func test_empty_summary_is_empty() -> void:
	var recorder := PerfRecorder.new()
	assert_true(recorder.reserve(1))
	assert_true(recorder.compute_summary().is_empty())


func test_worst_case_capacity_and_speed() -> void:
	# Pire cas : 20 s mesurées à 2000 images par seconde (40 000 images).
	var recorder := PerfRecorder.new()
	var count: int = 40000
	assert_true(recorder.reserve(count))
	var start: int = Time.get_ticks_usec()
	for i: int in count:
		recorder.add_frame(float(i % 33) + 0.5, 1.0, 1.0, 10, 1000)
	var summary: Dictionary = recorder.compute_summary()
	var elapsed_ms: float = float(Time.get_ticks_usec() - start) / 1000.0
	assert_eq(int(summary["frames"]), count)
	gut.p("40 000 images enregistrées et résumées en %.2f ms" % elapsed_ms)
	PerfCheck.under(self, elapsed_ms, 1000.0, "l'enregistrement et le résumé du pire cas doivent rester rapides")
