class_name PipelineRunner
extends Node
## Singleton « Pipeline » : exécute les tâches automatisées demandées après « -- » sur la ligne de commande.
##
## Modes :
##   --mode=capture    --scene=<res://…> --viewpoints=<res://…> --out=<dossier absolu> [--settle-frames=30]
##   --mode=benchmark  --scene=<res://…> --viewpoints=<res://…> --out=<dossier absolu>
##                     --budgets=<res://…> [--warmup=3] [--duration=20] [--no-budgets] [--budgets-advisory]
##   --mode=flythrough --scene=<res://…> --viewpoints=<res://…> [--duration=10]   (avec --write-movie)
##   --mode=walk       --scene=<res://…> --route=<res://…/route_joueur.json> --out=<dossier absolu>
##                     --budgets=<res://…> [--warmup=3] [--no-budgets] [--budgets-advisory]
##   --mode=flythrough --scene=<res://…> --route=<res://…/route_joueur.json> [--duration=<maximum>]
##
## Avec --route, le joueur (groupe « player ») marche le long du parcours, piloté par les actions
## d'entrée (PlayerRouteDriver) ; la caméra de la scène n'est pas touchée (elle suit le joueur).
## En mode walk, la mesure dure exactement le parcours ; en vidéo, --duration l'écourte s'il est donné.
##
## Codes de sortie : 0 succès, 2 arguments invalides, 3 budget dépassé, 4 erreur d'exécution.
## Ces modes sont lancés par les scripts de Scripts/Pipeline/, jamais à la main.

const EXIT_OK: int = 0
const EXIT_BAD_ARGS: int = 2
const EXIT_BUDGET: int = 3
const EXIT_RUNTIME: int = 4

## Plafond d'images par seconde servant à dimensionner la mémoire des mesures avant de commencer.
const MAX_MEASURED_FPS: float = 2000.0
## Groupe des scènes qui chargent le monde autour d'un point : elles reçoivent pipeline_focus_at(position).
const FOCUS_GROUP: StringName = &"pipeline_focus"
## Images attendues au plus pour le chargement du monde autour d'un point de vue.
const STREAM_WAIT_FRAMES: int = 3000
## Images laissées au chargeur avant de le croire à jour (il recalcule ses cellules au plus tard à la suivante).
const STREAM_MIN_FRAMES: int = 5
## Images attendues au plus, après le changement de scène, pour que la scène installe sa caméra active.
const CAMERA_WAIT_FRAMES: int = 600
const BYTES_PER_MEBIBYTE: float = 1048576.0

var _args: Dictionary[String, String] = {}
var _mode: String = ""


func is_active() -> bool:
	return not _mode.is_empty()


## Remplace les arguments lus sur la ligne de commande (tests du pipeline).
func configure(args: Dictionary[String, String]) -> void:
	_args = args
	_mode = args.get("mode", "")


func _ready() -> void:
	_args = CommandLine.parse(OS.get_cmdline_user_args())
	_mode = _args.get("mode", "")
	if _mode.is_empty():
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	var code: int = await _execute()
	get_tree().quit(code)


func _execute() -> int:
	if _mode == "walk" or (_mode == "flythrough" and _args.has("route")):
		return await _execute_route()
	var scene_path: String = _require_arg("scene")
	var viewpoints_path: String = _require_arg("viewpoints")
	if scene_path.is_empty() or viewpoints_path.is_empty():
		return EXIT_BAD_ARGS
	var viewpoints: Array[Viewpoint] = Viewpoints.load_file(viewpoints_path)
	if viewpoints.is_empty():
		push_error("Pipeline : aucun point de vue valide dans %s." % viewpoints_path)
		return EXIT_BAD_ARGS
	var err: Error = get_tree().change_scene_to_file(scene_path)
	if err != OK:
		push_error("Pipeline : impossible de charger %s (%s)." % [scene_path, error_string(err)])
		return EXIT_RUNTIME
	# Les scènes de jeu assemblent leur monde au chargement (caméra comprise) : on attend la caméra active.
	var camera: Camera3D = null
	for frame: int in CAMERA_WAIT_FRAMES:
		await get_tree().process_frame
		camera = get_viewport().get_camera_3d()
		if camera != null:
			break
	if camera == null:
		push_error("Pipeline : la scène %s ne contient aucune caméra active." % scene_path)
		return EXIT_RUNTIME
	# La caméra est pilotée par le pipeline : ses propres scripts (caméra libre) sont suspendus.
	camera.process_mode = Node.PROCESS_MODE_DISABLED
	match _mode:
		"capture":
			return await _capture(camera, viewpoints)
		"benchmark":
			return await _benchmark(camera, viewpoints, scene_path)
		"flythrough":
			return await _flythrough(camera, viewpoints)
		_:
			push_error("Pipeline : mode inconnu « %s » (capture, benchmark, flythrough, walk)." % _mode)
			return EXIT_BAD_ARGS


## Attend que les scènes du groupe FOCUS_GROUP aient chargé le monde autour du point de vue (au plus STREAM_WAIT_FRAMES).
func _wait_for_streaming() -> void:
	for frame: int in STREAM_WAIT_FRAMES:
		await get_tree().process_frame
		var settled: bool = frame >= STREAM_MIN_FRAMES
		for node: Node in get_tree().get_nodes_in_group(FOCUS_GROUP):
			if node.has_method(&"pipeline_is_settled") and not bool(node.call(&"pipeline_is_settled")):
				settled = false
		if settled:
			return
	push_error("Pipeline : le monde ne s'est pas chargé autour du point de vue en %d images." % STREAM_WAIT_FRAMES)


func _capture(camera: Camera3D, viewpoints: Array[Viewpoint]) -> int:
	var out_dir: String = _require_arg("out")
	if out_dir.is_empty():
		return EXIT_BAD_ARGS
	var settle_frames: int = _int_arg("settle-frames", 30)
	if settle_frames < 1:
		push_error("Pipeline : --settle-frames doit être au moins 1.")
		return EXIT_BAD_ARGS
	var err: Error = DirAccess.make_dir_recursive_absolute(out_dir)
	if err != OK:
		push_error("Pipeline : impossible de créer %s (%s)." % [out_dir, error_string(err)])
		return EXIT_RUNTIME
	var failures: int = 0
	for viewpoint: Viewpoint in viewpoints:
		camera.global_transform = viewpoint.transform
		# Les mondes en cellules chargent autour du point de vue (et non autour du personnage).
		get_tree().call_group(FOCUS_GROUP, &"pipeline_focus_at", viewpoint.transform.origin)
		await _wait_for_streaming()
		# Laisse l'image se stabiliser (mise à l'échelle temporelle, exposition, ombres).
		for i: int in settle_frames:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image: Image = get_viewport().get_texture().get_image()
		var path: String = out_dir.path_join("%s.png" % viewpoint.id)
		err = image.save_png(path)
		if err != OK:
			push_error("Pipeline : impossible d'écrire %s (%s)." % [path, error_string(err)])
			return EXIT_RUNTIME
		var stats: Dictionary = CaptureCheck.analyze(image)
		print("CAPTURE %s %s" % [path, JSON.stringify(stats)])
		for problem: String in CaptureCheck.problems(stats):
			push_error("Capture %s : %s" % [viewpoint.id, problem])
			failures += 1
	return EXIT_RUNTIME if failures > 0 else EXIT_OK


## Mesure image par image. Sans pilote : la caméra parcourt les points de vue pendant --duration.
## Avec un pilote : le joueur marche le long de son parcours et la mesure dure exactement ce parcours.
func _benchmark(camera: Camera3D, viewpoints: Array[Viewpoint], scene_path: String, driver: PlayerRouteDriver = null) -> int:
	var walking: bool = driver != null
	var out_dir: String = _require_arg("out")
	var check_budgets: bool = not _args.has("no-budgets")
	var budgets_path: String = _require_arg("budgets") if check_budgets else ""
	if out_dir.is_empty() or (check_budgets and budgets_path.is_empty()):
		return EXIT_BAD_ARGS
	var warmup: float = _float_arg("warmup", 3.0)
	# En mode walk, la durée maximale du parcours dimensionne la mémoire des mesures.
	var duration: float = driver.get_route().max_duration if walking else _float_arg("duration", 20.0)
	if warmup < 0.0 or duration <= 0.0:
		push_error("Pipeline : --warmup doit être positif et --duration strictement positif.")
		return EXIT_BAD_ARGS
	var budgets: Dictionary = {}
	if check_budgets:
		budgets = JsonData.get_dictionary(JsonData.load_dictionary(budgets_path), "budgets", budgets_path)
		if budgets.is_empty():
			return EXIT_BAD_ARGS
	var err: Error = DirAccess.make_dir_recursive_absolute(out_dir)
	if err != OK:
		push_error("Pipeline : impossible de créer %s (%s)." % [out_dir, error_string(err)])
		return EXIT_RUNTIME

	# Mesure du coût réel d'une image : pas de synchronisation verticale ni de limite d'images.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var viewport_rid: RID = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport_rid, true)

	var recorder := PerfRecorder.new()
	var capacity: int = int(ceilf(duration * MAX_MEASURED_FPS)) + 1
	if not recorder.reserve(capacity):
		push_error("Pipeline : impossible de réserver %d mesures (durée trop longue ?)." % capacity)
		return EXIT_RUNTIME

	if not walking:
		camera.global_transform = viewpoints[0].transform
	# Pendant le préchauffage, le joueur attend au départ sans aucune action pressée.
	var warmup_end: int = Time.get_ticks_usec() + int(warmup * 1000000.0)
	while Time.get_ticks_usec() < warmup_end:
		await get_tree().process_frame

	var duration_usec: int = int(duration * 1000000.0)
	var start: int = Time.get_ticks_usec()
	var previous: int = start
	var video_mem_max: float = 0.0
	var static_mem_max: float = 0.0
	if walking:
		driver.begin()
	while true:
		await get_tree().process_frame
		var now: int = Time.get_ticks_usec()
		var elapsed: int = now - start
		if walking:
			if not driver.is_running():
				break
		elif elapsed >= duration_usec:
			break
		else:
			camera.global_transform = Viewpoints.sample(viewpoints, float(elapsed) / float(duration_usec))
		var frame_ms: float = float(now - previous) / 1000.0
		previous = now
		var cpu_ms: float = RenderingServer.viewport_get_measured_render_time_cpu(viewport_rid) + RenderingServer.get_frame_setup_time_cpu()
		var gpu_ms: float = RenderingServer.viewport_get_measured_render_time_gpu(viewport_rid)
		var draw_calls: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		var primitives: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		if not recorder.add_frame(frame_ms, cpu_ms, gpu_ms, draw_calls, primitives):
			if walking:
				driver.stop()
			push_error("Pipeline : mesure refusée (capacité atteinte ou valeur invalide) à l'image %d." % recorder.get_count())
			return EXIT_RUNTIME
		video_mem_max = maxf(video_mem_max, Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED))
		static_mem_max = maxf(static_mem_max, Performance.get_monitor(Performance.MEMORY_STATIC))

	var route_failed: bool = walking and driver.has_failed()
	if route_failed:
		push_error(driver.get_failure_message())
	var summary: Dictionary = recorder.compute_summary()
	if summary.is_empty():
		push_error("Pipeline : aucune image mesurée.")
		return EXIT_RUNTIME
	var size := Vector2i(get_viewport().get_visible_rect().size)
	summary["video_mem_mb_max"] = video_mem_max / BYTES_PER_MEBIBYTE
	summary["static_mem_mb_max"] = static_mem_max / BYTES_PER_MEBIBYTE
	summary["scene"] = scene_path
	summary["mode"] = _mode
	summary["warmup_s"] = warmup
	if walking:
		var route: PlayerRoute = driver.get_route()
		summary["route"] = route.source
		summary["route_status"] = driver.get_status_name()
		summary["route_waypoints"] = route.points.size()
		summary["route_waypoints_reached"] = driver.get_reached_count()
		summary["route_length_m"] = route.get_length()
		summary["route_walked_m"] = driver.get_distance_walked()
		summary["route_time_s"] = driver.get_elapsed()
		summary["duration_s"] = float(previous - start) / 1000000.0
	else:
		summary["route"] = _args.get("viewpoints", "")
		summary["duration_s"] = duration
	summary["window"] = "%dx%d" % [size.x, size.y]
	summary["scaling_3d_mode"] = int(ProjectSettings.get_setting("rendering/scaling_3d/mode"))
	summary["scaling_3d_scale"] = float(ProjectSettings.get_setting("rendering/scaling_3d/scale"))
	summary["rendering_method"] = str(ProjectSettings.get_setting("rendering/renderer/rendering_method"))
	summary["adapter"] = RenderingServer.get_video_adapter_name()
	summary["adapter_vendor"] = RenderingServer.get_video_adapter_vendor()
	summary["godot"] = Engine.get_version_info()["string"]

	var violations := PackedStringArray()
	if check_budgets:
		violations = PerfBudget.check(summary, budgets)
	summary["budgets_checked"] = check_budgets
	# Sur batterie (signalé par Scripts/Pipeline/mesurer.ps1), la machine est bridée : les dépassements
	# sont enregistrés et affichés, sans faire échouer la mesure.
	var blocking: bool = not _args.has("budgets-advisory")
	summary["budgets_blocking"] = blocking
	summary["budget_violations"] = violations

	if not _write_text(out_dir.path_join("resume.json"), JSON.stringify(summary, "\t", true)):
		return EXIT_RUNTIME
	if not _write_csv(out_dir.path_join("images.csv"), recorder):
		return EXIT_RUNTIME
	print("MESURE %s" % JSON.stringify(summary))
	if route_failed:
		return EXIT_RUNTIME
	if not violations.is_empty():
		for violation: String in violations:
			if blocking:
				push_error("Budget dépassé : %s" % violation)
			else:
				push_warning("Budget dépassé sur batterie (non bloquant) : %s" % violation)
		if blocking:
			return EXIT_BUDGET
	return EXIT_OK


func _flythrough(camera: Camera3D, viewpoints: Array[Viewpoint]) -> int:
	var duration: float = _float_arg("duration", 10.0)
	if duration <= 0.0:
		push_error("Pipeline : --duration doit être strictement positif.")
		return EXIT_BAD_ARGS
	var elapsed: float = 0.0
	camera.global_transform = viewpoints[0].transform
	while elapsed < duration:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		camera.global_transform = Viewpoints.sample(viewpoints, minf(elapsed / duration, 1.0))
	return EXIT_OK


func _execute_route() -> int:
	var scene_path: String = _require_arg("scene")
	var route_path: String = _require_arg("route")
	if scene_path.is_empty() or route_path.is_empty():
		return EXIT_BAD_ARGS
	if _mode == "walk" and _args.has("duration"):
		push_error("Pipeline : --duration ne s'applique pas au mode walk (la mesure dure le parcours du joueur).")
		return EXIT_BAD_ARGS
	var route: PlayerRoute = PlayerRoute.load_file(route_path)
	if route == null:
		return EXIT_BAD_ARGS
	var missing: PackedStringArray = PlayerRouteDriver.missing_actions(route)
	if not missing.is_empty():
		push_error("Pipeline : actions d'entrée absentes pour le parcours %s : %s." % [route_path, ", ".join(missing)])
		return EXIT_RUNTIME
	var err: Error = get_tree().change_scene_to_file(scene_path)
	if err != OK:
		push_error("Pipeline : impossible de charger %s (%s)." % [scene_path, error_string(err)])
		return EXIT_RUNTIME
	await get_tree().process_frame
	await get_tree().process_frame
	return await run_route(route, scene_path)


## Fait marcher le joueur de la scène courante le long du parcours, selon le mode (walk : mesure ;
## flythrough : vidéo). Appelé après le chargement de la scène ; appelé directement par les tests.
func run_route(route: PlayerRoute, scene_path: String) -> int:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		push_error("Pipeline : la scène %s ne contient aucune caméra active." % scene_path)
		return EXIT_RUNTIME
	var problem: String = PlayerRouteDriver.player_problem(get_tree())
	if not problem.is_empty():
		push_error("Pipeline : %s (%s)." % [problem, scene_path])
		return EXIT_RUNTIME
	var driver := PlayerRouteDriver.new()
	driver.setup(route, PlayerRouteDriver.find_player(get_tree()))
	add_child(driver)
	driver.place_at_start()
	var code: int = EXIT_RUNTIME
	if _mode == "walk":
		var no_viewpoints: Array[Viewpoint] = []
		code = await _benchmark(camera, no_viewpoints, scene_path, driver)
	else:
		code = await _flythrough_route(driver)
	driver.stop()
	remove_child(driver)
	driver.free()
	return code


## Vidéo du joueur qui marche le long de son parcours (jusqu'au bout, ou pendant --duration au plus).
func _flythrough_route(driver: PlayerRouteDriver) -> int:
	var limit: float = _float_arg("duration", 0.0)
	if _args.has("duration") and limit <= 0.0:
		push_error("Pipeline : --duration doit être strictement positif.")
		return EXIT_BAD_ARGS
	var elapsed: float = 0.0
	driver.begin()
	while driver.is_running():
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		if limit > 0.0 and elapsed >= limit:
			driver.stop()
	if driver.has_failed():
		push_error(driver.get_failure_message())
		return EXIT_RUNTIME
	return EXIT_OK


func _write_text(path: String, text: String) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Pipeline : impossible d'écrire %s (%s)." % [path, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(text)
	file.close()
	return true


func _write_csv(path: String, recorder: PerfRecorder) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Pipeline : impossible d'écrire %s (%s)." % [path, error_string(FileAccess.get_open_error())])
		return false
	var frame_ms: PackedFloat32Array = recorder.get_frame_ms()
	var cpu_ms: PackedFloat32Array = recorder.get_cpu_ms()
	var gpu_ms: PackedFloat32Array = recorder.get_gpu_ms()
	var draw_calls: PackedInt64Array = recorder.get_draw_calls()
	var primitives: PackedInt64Array = recorder.get_primitives()
	file.store_line("image,image_ms,cpu_ms,gpu_ms,appels_dessin,primitives")
	for i: int in frame_ms.size():
		file.store_line("%d,%.4f,%.4f,%.4f,%d,%d" % [i, frame_ms[i], cpu_ms[i], gpu_ms[i], draw_calls[i], primitives[i]])
	file.close()
	return true


func _require_arg(key: String) -> String:
	var value: String = _args.get(key, "")
	if value.is_empty():
		push_error("Pipeline : argument --%s manquant pour le mode « %s »." % [key, _mode])
	return value


func _int_arg(key: String, default_value: int) -> int:
	if not _args.has(key):
		return default_value
	var text: String = _args[key]
	if not text.is_valid_int():
		push_error("Pipeline : --%s doit être un entier (reçu « %s »)." % [key, text])
		return -1
	return text.to_int()


func _float_arg(key: String, default_value: float) -> float:
	if not _args.has(key):
		return default_value
	var text: String = _args[key]
	if not text.is_valid_float():
		push_error("Pipeline : --%s doit être un nombre (reçu « %s »)." % [key, text])
		return -1.0
	return text.to_float()
