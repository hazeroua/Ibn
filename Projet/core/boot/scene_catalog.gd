class_name SceneCatalog
extends RefCounted
## Catalogue des scènes lançables, lu dans data/config/boot.json.

var default_scene_id: String = ""
var errors: PackedStringArray = PackedStringArray()
var _scenes: Dictionary = {}


static func from_dictionary(data: Dictionary) -> SceneCatalog:
	var catalog: SceneCatalog = SceneCatalog.new()
	var context: String = "boot.json"
	catalog.default_scene_id = JsonData.read_string(data, "default_scene", catalog.errors, context)
	var scenes: Dictionary = JsonData.read_dictionary(data, "scenes", catalog.errors, context)
	for scene_id: String in scenes:
		var entry: Variant = scenes[scene_id]
		if typeof(entry) != TYPE_DICTIONARY:
			catalog.errors.append("%s › %s : l'entrée doit être un objet." % [context, scene_id])
			continue
		var scene_context: String = context + " › " + scene_id
		var path: String = JsonData.read_string(entry, "path", catalog.errors, scene_context)
		var budget: String = JsonData.read_string(entry, "budget", catalog.errors, scene_context)
		# Constructeur facultatif, lancé par outils/construire.gd avant l'import final.
		var builder: String = String((entry as Dictionary).get("builder", ""))
		for resource_path: String in [path, budget, builder]:
			if not resource_path.is_empty() and not ResourceLoader.exists(resource_path) and not FileAccess.file_exists(resource_path):
				catalog.errors.append("%s : fichier introuvable %s." % [scene_context, resource_path])
		catalog._scenes[scene_id] = {"path": path, "budget": budget, "builder": builder}
	if not catalog.default_scene_id.is_empty() and not catalog._scenes.has(catalog.default_scene_id):
		catalog.errors.append("%s : la scène par défaut « %s » n'est pas au catalogue." % [context, catalog.default_scene_id])
	return catalog


func has_scene(scene_id: String) -> bool:
	return _scenes.has(scene_id)


func scene_path(scene_id: String) -> String:
	return String(_scenes[scene_id]["path"])


func budget_path(scene_id: String) -> String:
	return String(_scenes[scene_id]["budget"])


func builder_path(scene_id: String) -> String:
	return String(_scenes[scene_id]["builder"])


func scene_ids() -> PackedStringArray:
	return PackedStringArray(_scenes.keys())
