class_name CharacterCatalog
extends RefCounted
## Accès au manifeste des personnages (res://data/player/personnage.json) et à leurs scènes importées.
##
## Chaque personnage est un fichier res://generated/personnages/<id>/<id>.glb produit par le pipeline
## (outils/valider.ps1, Blender). La scène importée est chargée une seule fois par Godot
## (cache des ressources) : toutes les instances partagent maillage, squelette de liaison, matériau et
## animations, la mémoire ne croît donc que des données de pose de chaque instance.

const MANIFEST_PATH: String = "res://data/player/personnage.json"
const CHARACTERS_DIR: String = "res://generated/personnages"
const CONTEXT: String = "personnage.json"


static func load_manifest() -> Dictionary:
	return JsonData.load_dictionary(MANIFEST_PATH)


## Entrée du manifeste d'un personnage, ou dictionnaire vide (erreur signalée) s'il est inconnu.
static func get_character(manifest: Dictionary, character_id: String) -> Dictionary:
	for raw: Variant in PlayerJsonData.get_array(manifest, "characters", CONTEXT):
		if typeof(raw) == TYPE_DICTIONARY and (raw as Dictionary).get("id") == character_id:
			return raw
	push_error("CharacterCatalog : personnage « %s » absent de %s." % [character_id, MANIFEST_PATH])
	return {}


static func scene_path(character_id: String) -> String:
	return "%s/%s/%s.glb" % [CHARACTERS_DIR, character_id, character_id]


## Scène importée d'un personnage, ou null (erreur signalée) si le pipeline ne l'a pas produite.
static func load_scene(character_id: String) -> PackedScene:
	var path: String = scene_path(character_id)
	if not ResourceLoader.exists(path):
		push_error("CharacterCatalog : %s absent. Lancez valider.bat." % path)
		return null
	var scene: PackedScene = load(path) as PackedScene
	if scene == null:
		push_error("CharacterCatalog : %s n'est pas une scène." % path)
	return scene


## Noms des animations du personnage, dans l'ordre du manifeste.
static func animation_names(character: Dictionary) -> PackedStringArray:
	var names := PackedStringArray()
	for raw: Variant in PlayerJsonData.get_array(character, "animations", CONTEXT):
		if typeof(raw) == TYPE_DICTIONARY:
			names.append(PlayerJsonData.get_string(raw, "name", CONTEXT))
	return names


## Premier AnimationPlayer d'une instance de personnage.
static func find_animation_player(instance: Node) -> AnimationPlayer:
	var players: Array[Node] = instance.find_children("*", "AnimationPlayer", true, false)
	return null if players.is_empty() else players[0] as AnimationPlayer


## Premier Skeleton3D d'une instance de personnage.
static func find_skeleton(instance: Node) -> Skeleton3D:
	var skeletons: Array[Node] = instance.find_children("*", "Skeleton3D", true, false)
	return null if skeletons.is_empty() else skeletons[0] as Skeleton3D
