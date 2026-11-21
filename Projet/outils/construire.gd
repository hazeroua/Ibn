extends SceneTree
## Lance les constructeurs des scènes du catalogue (data/config/boot.json, clé « builder »).
## Usage : godot --headless --path Projet -s res://outils/construire.gd
## Code de sortie : 0 si toutes les constructions réussissent, 1 sinon.

const BOOT_CONFIG_PATH: String = "res://data/config/boot.json"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var catalog: SceneCatalog = SceneCatalog.from_dictionary(JsonData.load_dictionary(BOOT_CONFIG_PATH))
	var errors: PackedStringArray = catalog.errors.duplicate()
	if errors.is_empty():
		for scene_id: String in catalog.scene_ids():
			var builder_path: String = catalog.builder_path(scene_id)
			if builder_path.is_empty():
				continue
			GameLog.info("construction", "Construction de « %s »." % scene_id)
			var builder: GDScript = load(builder_path) as GDScript
			if builder == null:
				errors.append("Constructeur illisible : " + builder_path)
				continue
			var builder_errors: PackedStringArray = await builder.call(&"build", self)
			errors.append_array(builder_errors)
	for message: String in errors:
		GameLog.error("construction", message)
	quit(0 if errors.is_empty() else 1)
