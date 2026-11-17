extends GutTest
## Moniteur de performance en jeu : fenêtres de mesure à mémoire constante (partie de 100 heures), saccades
## comptées, affichage F3 basculé par l'action perf_overlay.

const MONITOR_SCRIPT: GDScript = preload("res://core/perf/perf_monitor.gd")


func test_windows_keep_memory_constant_and_count_hitches() -> void:
	var monitor: Node = MONITOR_SCRIPT.new()
	add_child_autofree(monitor)
	monitor.set_process(false)
	var recorder: PerfRecorder = monitor.get("_recorder")
	var capacity: int = recorder.get_capacity()
	# Équivalent de 5 fenêtres d'une minute à 240 i/s : la capacité n'est jamais dépassée.
	for frame: int in 5 * 60 * 240:
		monitor.set("_previous_usec", Time.get_ticks_usec() - (30000 if frame % 1000 == 0 else 4000))
		monitor._process(1.0 / 240.0)
		assert_lte(recorder.get_count(), capacity)
	assert_gte(int(monitor.get("_windows")), 4)
	assert_eq(int(monitor.get("_hitches_total")), 72, "une saccade de 30 ms toutes les 1 000 images")
	assert_gt(float(monitor.get("_worst_frame_ms")), 25.0)


func test_overlay_toggles_with_action() -> void:
	var monitor: Node = MONITOR_SCRIPT.new()
	add_child_autofree(monitor)
	var label: Label = monitor.get("_label")
	assert_false(label.visible)
	var press := InputEventAction.new()
	press.action = &"perf_overlay"
	press.pressed = true
	monitor._unhandled_input(press)
	assert_true(label.visible)
