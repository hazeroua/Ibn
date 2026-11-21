class_name PerformanceProbe
extends Node
## Mesure automatique d'une scène : préchauffage, mesure sur une durée fixe,
## capture 1080p, rapport JSON comparé au budget, puis fermeture du jeu.
## Aucun objet n'est alloué par image pendant la mesure.

const GROUP: StringName = &"performance_probe"
const BYTES_PER_MIB: float = 1024.0 * 1024.0
const PROGRESS_INTERVAL_SECONDS: float = 10.0
const EXIT_OK: int = 0
const EXIT_FAILURE: int = 1
const EXIT_BUDGET_EXCEEDED: int = 2
const FRAMES_SKIPPED_AFTER_CAPTURE: int = 2

var _scene_id: String = ""
var _scene_root: Node
var _budget: PerformanceBudget
var _warmup_seconds: float = 5.0
var _duration_seconds: float = 30.0
var _report_dir: String = ""
var _statistics: FrameStatistics = FrameStatistics.new()
var _elapsed_seconds: float = 0.0
var _measured_seconds: float = 0.0
var _progress_seconds: float = 0.0
var _startup_ms: float = -1.0
var _capture_saved: bool = false
## Images exclues après la capture (la lecture de l'image bloque le GPU).
var _skipped_frames_after_capture: int = 0
var _finished: bool = false
var _peak_draw_calls: int = 0
var _peak_primitives: int = 0
var _peak_video_memory_bytes: int = 0
var _peak_static_memory_bytes: int = 0
var _peak_process_ms: float = 0.0
var _peak_physics_process_ms: float = 0.0
## Mesures propres à la scène (collisions manquées, etc.), fournies par la scène.
var _scene_metrics: Dictionary = {}


func configure(scene_id: String, scene_root: Node, budget: PerformanceBudget, options: LaunchOptions) -> void:
	_scene_id = scene_id
	_scene_root = scene_root
	_budget = budget
	_warmup_seconds = options.warmup_seconds
	_duration_seconds = options.duration_seconds
	_report_dir = options.report_dir


func _ready() -> void:
	name = "PerformanceProbe"
	add_to_group(GROUP)
	process_priority = -1000
	process_mode = Node.PROCESS_MODE_ALWAYS


## Indique si la scène doit rester en mode mesure (parcours automatique).
func is_measuring() -> bool:
	return not _finished


## Enregistre ou met à jour une mesure propre à la scène.
func report_metric(key: String, value: float) -> void:
	_scene_metrics[key] = value


func _process(delta: float) -> void:
	if _finished:
		return
	if _startup_ms < 0.0:
		if not _scene_root.is_inside_tree() or not _scene_root.is_node_ready():
			return
		_startup_ms = float(Time.get_ticks_msec())
		GameLog.info("mesure", "Scène prête après %.0f ms ; préchauffage de %.0f s." % [_startup_ms, _warmup_seconds])
	_elapsed_seconds += delta
	if _elapsed_seconds < _warmup_seconds:
		return
	if not _capture_saved:
		_save_capture()
		return
	if _skipped_frames_after_capture < FRAMES_SKIPPED_AFTER_CAPTURE:
		_skipped_frames_after_capture += 1
		return
	_measured_seconds += delta
	_statistics.record(delta * 1000.0)
	_sample_monitors()
	_progress_seconds += delta
	if _progress_seconds >= PROGRESS_INTERVAL_SECONDS:
		_progress_seconds = 0.0
		GameLog.info("mesure", "%d s mesurées, %d i/s." % [int(_measured_seconds), int(Engine.get_frames_per_second())])
	if _measured_seconds >= _duration_seconds:
		_finish()


func _sample_monitors() -> void:
	_peak_draw_calls = maxi(_peak_draw_calls, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	_peak_primitives = maxi(_peak_primitives, int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
	_peak_video_memory_bytes = maxi(_peak_video_memory_bytes, int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)))
	_peak_static_memory_bytes = maxi(_peak_static_memory_bytes, int(Performance.get_monitor(Performance.MEMORY_STATIC)))
	_peak_process_ms = maxf(_peak_process_ms, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	_peak_physics_process_ms = maxf(_peak_physics_process_ms, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)


func _save_capture() -> void:
	_capture_saved = true
	var capture_path: String = _report_dir.path_join("capture.png")
	DirAccess.make_dir_recursive_absolute(_report_dir)
	var image: Image = get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		_abort("Capture impossible : aucun rendu disponible (mode sans affichage ?).")
		return
	var save_error: Error = image.save_png(capture_path)
	if save_error != OK:
		_abort("Impossible d'écrire la capture %s : %s" % [capture_path, error_string(save_error)])
		return
	GameLog.info("mesure", "Capture %d × %d écrite : %s" % [image.get_width(), image.get_height(), capture_path])


func build_report() -> Dictionary:
	var report: Dictionary = {
		"scene": _scene_id,
		"game_version": ProjectSettings.get_setting("application/config/version"),
		"godot_version": Engine.get_version_info()["string"],
		"rendering_method": RenderingServer.get_current_rendering_method(),
		"rendering_driver": RenderingServer.get_current_rendering_driver_name(),
		"rendering_device": RenderingServer.get_video_adapter_name(),
		"physics_engine": ProjectSettings.get_setting("physics/3d/physics_engine"),
		"viewport_size": [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y],
		"scaling_3d_scale": get_viewport().scaling_3d_scale,
		"warmup_seconds": _warmup_seconds,
		"duration_seconds": _measured_seconds,
		"startup_ms": _startup_ms,
		"frame_count": _statistics.frame_count,
		"average_frame_ms": _statistics.average_ms(),
		"p99_frame_ms": _statistics.percentile_ms(0.99),
		"low_1_percent_fps": _statistics.low_1_percent_fps(),
		"max_frame_ms": _statistics.max_ms,
		"frames_over_16_67_ms": _statistics.frames_over_budget,
		"peak_draw_calls": _peak_draw_calls,
		"peak_primitives": _peak_primitives,
		"peak_video_memory_mib": float(_peak_video_memory_bytes) / BYTES_PER_MIB,
		"peak_static_memory_mib": float(_peak_static_memory_bytes) / BYTES_PER_MIB,
		"peak_process_ms": _peak_process_ms,
		"peak_physics_process_ms": _peak_physics_process_ms,
		"gpu_time_ms": null,
		"gpu_time_note": "Godot 4.7 n'expose pas le temps GPU par image ; le temps d'image total fait référence.",
	}
	report.merge(_scene_metrics, true)
	return report


func _finish() -> void:
	_finished = true
	var report: Dictionary = build_report()
	var failures: PackedStringArray = _budget.evaluate(report)
	report["budget_failures"] = failures
	report["budgets_passed"] = failures.is_empty()
	var report_path: String = _report_dir.path_join("rapport.json")
	var report_file: FileAccess = FileAccess.open(report_path, FileAccess.WRITE)
	if report_file == null:
		_abort("Impossible d'écrire le rapport %s : %s" % [report_path, error_string(FileAccess.get_open_error())])
		return
	report_file.store_string(JSON.stringify(report, "  "))
	report_file.close()
	GameLog.info("mesure", "Rapport écrit : " + report_path)
	if failures.is_empty():
		GameLog.info("mesure", "Budgets respectés.")
		get_tree().quit(EXIT_OK)
		return
	for failure: String in failures:
		GameLog.warning("budget", failure)
	get_tree().quit(EXIT_BUDGET_EXCEEDED)


func _abort(message: String) -> void:
	_finished = true
	GameLog.error("mesure", message)
	get_tree().quit(EXIT_FAILURE)
