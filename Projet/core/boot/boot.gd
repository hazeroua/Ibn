extends Node
## Point d'entrée du jeu : lit les options de lancement, applique la configuration
## graphique et les commandes, puis ouvre la scène demandée (avec la sonde de mesure
## en mode --measure). Toute erreur de configuration ferme le jeu avec le code 1.

const BOOT_CONFIG_PATH: String = "res://data/config/boot.json"
const GRAPHICS_CONFIG_PATH: String = "res://data/config/graphics.json"
const INPUT_CONFIG_PATH: String = "res://data/config/input.json"


func _ready() -> void:
	(
		GameLog
		. info(
			"démarrage",
			(
				"%s %s, Godot %s"
				% [
					ProjectSettings.get_setting("application/config/name"),
					ProjectSettings.get_setting("application/config/version"),
					Engine.get_version_info()["string"],
				]
			)
		)
	)
	(
		GameLog
		. info(
			"démarrage",
			(
				"GPU %s, rendu %s (%s), physique %s"
				% [
					RenderingServer.get_video_adapter_name(),
					RenderingServer.get_current_rendering_method(),
					RenderingServer.get_current_rendering_driver_name(),
					ProjectSettings.get_setting("physics/3d/physics_engine"),
				]
			)
		)
	)

	var options: LaunchOptions = LaunchOptions.parse(OS.get_cmdline_user_args())
	if not _check_errors(options.errors):
		return

	var graphics: GraphicsSettings = GraphicsSettings.from_dictionary(JsonData.load_dictionary(GRAPHICS_CONFIG_PATH))
	if not _check_errors(graphics.errors):
		return
	graphics.apply(get_window())
	if options.measure:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
	GameLog.info("graphismes", graphics.describe() + (" ; mesure : synchronisation coupée" if options.measure else ""))

	var bindings: InputBindings = InputBindings.from_dictionary(JsonData.load_dictionary(INPUT_CONFIG_PATH))
	if not _check_errors(bindings.errors):
		return
	bindings.apply()
	GameLog.info("commandes", "%d actions enregistrées." % bindings.bindings.size())

	var catalog: SceneCatalog = SceneCatalog.from_dictionary(JsonData.load_dictionary(BOOT_CONFIG_PATH))
	if not _check_errors(catalog.errors):
		return
	var scene_id: String = options.scene_id if not options.scene_id.is_empty() else catalog.default_scene_id
	if not catalog.has_scene(scene_id):
		_check_errors(PackedStringArray(["Scène inconnue : " + scene_id]))
		return
	var packed_scene: PackedScene = load(catalog.scene_path(scene_id)) as PackedScene
	if packed_scene == null:
		_check_errors(PackedStringArray(["Scène illisible : " + catalog.scene_path(scene_id)]))
		return
	var scene_root: Node = packed_scene.instantiate()

	if options.measure:
		var budget: PerformanceBudget = PerformanceBudget.from_dictionary(JsonData.load_dictionary(catalog.budget_path(scene_id)))
		if not _check_errors(budget.errors):
			scene_root.free()
			return
		var probe: PerformanceProbe = PerformanceProbe.new()
		probe.configure(scene_id, scene_root, budget, options)
		get_tree().root.add_child.call_deferred(probe)
		GameLog.info(
			"démarrage",
			"Mesure de « %s » : %.0f s après %.0f s de préchauffage." % [scene_id, options.duration_seconds, options.warmup_seconds]
		)

	GameLog.info("démarrage", "Ouverture de la scène « %s »." % scene_id)
	get_tree().change_scene_to_node.call_deferred(scene_root)


## Journalise les erreurs et ferme le jeu ; renvoie true s'il n'y en a aucune.
func _check_errors(errors: PackedStringArray) -> bool:
	if errors.is_empty():
		return true
	for message: String in errors:
		GameLog.error("démarrage", message)
	get_tree().quit(PerformanceProbe.EXIT_FAILURE)
	return false
