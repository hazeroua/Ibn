extends Node
## Scène de démarrage : charge la scène demandée (« -- --scene=res://… ») ou la scène par défaut
## du projet (réglage ibn/boot/default_scene). Ne fait rien quand le pipeline est actif : c'est
## alors le singleton « Pipeline » qui charge la scène et pilote la caméra.

const DEFAULT_SCENE_SETTING: String = "ibn/boot/default_scene"


func _ready() -> void:
	if Pipeline.is_active():
		return
	var args: Dictionary[String, String] = CommandLine.parse(OS.get_cmdline_user_args())
	var default_scene: String = str(ProjectSettings.get_setting(DEFAULT_SCENE_SETTING, ""))
	var scene_path: String = args.get("scene", default_scene)
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		push_error("Boot : scène introuvable « %s ». Lancez Scripts/Pipeline/construire.ps1." % scene_path)
		get_tree().quit(1)
		return
	get_tree().change_scene_to_file.call_deferred(scene_path)
