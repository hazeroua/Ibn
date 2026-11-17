class_name TunisCatalog
extends RefCounted
## Catalogue immuable de scènes, résolu une seule fois avant le démarrage du streaming.

var _scenes: Dictionary = {}


static func create(catalog: Dictionary, scene_overrides: Dictionary = {}) -> TunisCatalog:
	var result := TunisCatalog.new()
	for raw_prefab: Variant in catalog["prefabs"]:
		var prefab: Dictionary = raw_prefab
		var prefab_id := StringName(prefab["id"])
		var scene: PackedScene = scene_overrides.get(prefab_id)
		if scene == null:
			scene = load(String(prefab["scene_path"])) as PackedScene
		if scene == null:
			push_error("TunisCatalog: prefab introuvable ou non instanciable : %s." % prefab_id)
			return null
		result._scenes[prefab_id] = scene
	return result


func instantiate(prefab_id: StringName) -> Node3D:
	var packed: PackedScene = _scenes.get(prefab_id)
	if packed == null:
		push_error("TunisCatalog: prefab absent après validation : %s." % prefab_id)
		return null
	var instance := packed.instantiate() as Node3D
	if instance == null:
		push_error("TunisCatalog: la racine du prefab %s doit être un Node3D." % prefab_id)
	return instance
