extends Node
## Moniteur de performance en jeu (autoload PerfMonitor) : réglages dans res://data/perf/perf_monitor.json.
##
## Chaque image : une entrée dans PerfRecorder (C++, capacité réservée, aucune allocation) et quelques maxima.
## Toutes les window_s secondes : résumé de la fenêtre écrit dans le journal (ligne « PERF »), puis la fenêtre
## repart à zéro ; à la sortie, le résumé de toute la partie (pire fenêtre, saccades, pics). Pire cas : partie de
## 100 heures : mémoire constante (une fenêtre à la fois), une ligne de journal par minute.
## Affichage F3 (action perf_overlay) : texte refait refresh_s fois par seconde seulement, et seulement s'il est
## visible. Le pipeline (captures, mesures) a ses propres mesures : le moniteur s'y met en veille.

const SETTINGS_PATH: String = "res://data/perf/perf_monitor.json"
const CONTEXT: String = "perf_monitor.json"
const ACTION: StringName = &"perf_overlay"
const WINDOW_LINE: String = (
	"PERF fenêtre %d : %.1f i/s (1 %% bas %.1f), image max %.1f ms, CPU %.2f ms, GPU %.2f ms (p99 %.2f), "
	+ "appels %d (max %d), primitives max %d, mémoire vidéo %.0f Mo, saccades > %.0f ms : %d"
)
const OVERLAY_TEXT: String = (
	"%.0f i/s  image %.1f ms  CPU %.2f  GPU %.2f\nscripts %.2f ms  physique %.2f ms\n"
	+ "appels %d  primitives %d  objets %d\nmémoire vidéo %.0f Mo  saccades %d"
)

var _recorder := PerfRecorder.new()
var _viewport_rid: RID
var _window_s: float = 60.0
var _refresh_s: float = 0.25
var _hitch_ms: float = 25.0
var _window_time: float = 0.0
var _refresh_time: float = 0.0
var _previous_usec: int = 0
var _hitches_window: int = 0
var _hitches_total: int = 0
var _frames_total: int = 0
var _worst_frame_ms: float = 0.0
var _worst_window_low_fps: float = 1.0e9
var _peak_vram_mb: float = 0.0
var _peak_primitives: int = 0
var _peak_draw_calls: int = 0
var _windows: int = 0
var _overlay: CanvasLayer
var _label: Label
var _last_frame_ms: float = 0.0
var _last_cpu_ms: float = 0.0
var _last_gpu_ms: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1000
	var settings: Dictionary = JsonData.load_dictionary(SETTINGS_PATH)
	_window_s = JsonData.get_float(settings, "window_s", CONTEXT)
	_refresh_s = JsonData.get_float(settings, "refresh_s", CONTEXT)
	_hitch_ms = JsonData.get_float(settings, "hitch_ms", CONTEXT)
	_recorder.reserve(JsonData.get_int(settings, "recorder_capacity", CONTEXT))
	_viewport_rid = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_viewport_rid, true)
	_build_overlay()
	_previous_usec = Time.get_ticks_usec()
	# Veille pendant les captures et mesures du pipeline (elles enregistrent leurs propres images).
	set_process(not _pipeline_mode())


func _pipeline_mode() -> bool:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--mode="):
			return true
	return false


func _process(delta: float) -> void:
	var now: int = Time.get_ticks_usec()
	var frame_ms: float = float(now - _previous_usec) / 1000.0
	_previous_usec = now
	_last_frame_ms = frame_ms
	_last_cpu_ms = RenderingServer.viewport_get_measured_render_time_cpu(_viewport_rid) + RenderingServer.get_frame_setup_time_cpu()
	_last_gpu_ms = RenderingServer.viewport_get_measured_render_time_gpu(_viewport_rid)
	var draw_calls: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var primitives: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	if _recorder.get_count() >= _recorder.get_capacity():
		_close_window()
	_recorder.add_frame(frame_ms, _last_cpu_ms, _last_gpu_ms, draw_calls, primitives)
	_frames_total += 1
	_worst_frame_ms = maxf(_worst_frame_ms, frame_ms)
	_peak_draw_calls = maxi(_peak_draw_calls, draw_calls)
	_peak_primitives = maxi(_peak_primitives, primitives)
	if frame_ms > _hitch_ms:
		_hitches_window += 1
		_hitches_total += 1
	_window_time += delta
	if _window_time >= _window_s:
		_close_window()
	if _label.visible:
		_refresh_time += delta
		if _refresh_time >= _refresh_s:
			_refresh_time = 0.0
			_refresh_overlay()


func _unhandled_input(event: InputEvent) -> void:
	if InputMap.has_action(ACTION) and event.is_action_pressed(ACTION):
		_label.visible = not _label.visible
		_refresh_time = _refresh_s


## Résumé de la fenêtre écoulée dans le journal, puis remise à zéro (mémoire constante).
func _close_window() -> void:
	_window_time = 0.0
	if _recorder.get_count() == 0:
		return
	var summary: Dictionary = _recorder.compute_summary()
	var vram_mb: float = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	_peak_vram_mb = maxf(_peak_vram_mb, vram_mb)
	_worst_window_low_fps = minf(_worst_window_low_fps, float(summary["fps_1pct_low"]))
	_windows += 1
	print(
		(
			WINDOW_LINE
			% [
				_windows,
				float(summary["fps_avg"]),
				float(summary["fps_1pct_low"]),
				float(summary["frame_max_ms"]),
				float(summary["cpu_avg_ms"]),
				float(summary["gpu_avg_ms"]),
				float(summary["gpu_p99_ms"]),
				int(summary["draw_calls_avg"]),
				int(summary["draw_calls_max"]),
				int(summary["primitives_max"]),
				vram_mb,
				_hitch_ms,
				_hitches_window,
			]
		)
	)
	_hitches_window = 0
	_recorder.clear()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if _frames_total > 0 and is_processing():
			_close_window()
			print(
				(
					"PERF partie : %d images, pire fenêtre 1 %% bas %.1f i/s, image max %.1f ms, saccades %d, pics : %d appels, %d primitives, %.0f Mo"
					% [
						_frames_total,
						_worst_window_low_fps,
						_worst_frame_ms,
						_hitches_total,
						_peak_draw_calls,
						_peak_primitives,
						_peak_vram_mb
					]
				)
			)
			_frames_total = 0


func _build_overlay() -> void:
	_overlay = CanvasLayer.new()
	_overlay.name = "PerfOverlay"
	_overlay.layer = 128
	add_child(_overlay)
	_label = Label.new()
	_label.name = "Mesures"
	_label.visible = false
	_label.position = Vector2(12.0, 12.0)
	_label.add_theme_color_override(&"font_color", Color(1.0, 1.0, 1.0))
	_label.add_theme_color_override(&"font_outline_color", Color(0.0, 0.0, 0.0))
	_label.add_theme_constant_override(&"outline_size", 4)
	_overlay.add_child(_label)


func _refresh_overlay() -> void:
	var vram_mb: float = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	var scripts_ms: float = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var physics_ms: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	_label.text = (
		OVERLAY_TEXT
		% [
			Performance.get_monitor(Performance.TIME_FPS),
			_last_frame_ms,
			_last_cpu_ms,
			_last_gpu_ms,
			scripts_ms,
			physics_ms,
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
			vram_mb,
			_hitches_total,
		]
	)
