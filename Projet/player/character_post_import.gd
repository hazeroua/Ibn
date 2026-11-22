@tool
extends EditorScenePostImport
## Finalise l'import d'un personnage préparé par outils/blender/preparer_personnage.py.
##
## Lancé par Godot à chaque import de res://generated/personnages/<id>/<id>.glb (réglage import_script/path
## écrit par outils/valider.ps1) :
##   - range les animations du contrat dans la bibliothèque nommée par le manifeste (« locomotion ») ;
##   - règle le bouclage de chaque animation selon le manifeste ;
##   - vérifie qu'aucune animation n'est en trop ou absente ;
##   - fait porter la couleur par les sommets (une seule surface et un seul matériau par personnage :
##     les couleurs de la palette sont dans les sommets, l'importateur glTF ne l'active pas de lui-même).
## Le manifeste est lu directement (sans classe globale) : les classes du projet ne sont pas encore
## connues pendant le tout premier import.

const MANIFEST_PATH: String = "res://data/player/personnage.json"


func _post_import(scene: Node) -> Object:
	var character_id: String = get_source_file().get_file().get_basename()
	var character: Dictionary = _find_character(character_id)
	if character.is_empty():
		return scene
	var players: Array[Node] = scene.find_children("*", "AnimationPlayer", true, false)
	if players.size() != 1:
		push_error("Import de %s : un AnimationPlayer attendu, %d trouvés." % [character_id, players.size()])
		return scene
	var player: AnimationPlayer = players[0]
	var library_name := StringName(str(character.get("animation_library", "")))
	var entries: Variant = character.get("animations")
	if library_name.is_empty() or typeof(entries) != TYPE_ARRAY:
		push_error("Import de %s : « animation_library » ou « animations » invalide dans %s." % [character_id, MANIFEST_PATH])
		return scene
	if not player.has_animation_library(&""):
		push_error("Import de %s : aucune animation importée." % character_id)
		return scene
	var imported: AnimationLibrary = player.get_animation_library(&"")
	var library := AnimationLibrary.new()
	for raw: Variant in entries:
		if typeof(raw) != TYPE_DICTIONARY:
			push_error("Import de %s : chaque animation du manifeste doit être un objet." % character_id)
			continue
		var entry: Dictionary = raw
		var anim_name := StringName(str(entry.get("name", "")))
		if not imported.has_animation(anim_name):
			push_error("Import de %s : animation « %s » absente du fichier GLB." % [character_id, anim_name])
			continue
		var animation: Animation = imported.get_animation(anim_name)
		var loop: bool = entry.get("loop", false) == true
		animation.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
		library.add_animation(anim_name, animation)
	for anim_name: StringName in imported.get_animation_list():
		if not library.has_animation(anim_name):
			push_error("Import de %s : animation « %s » absente du manifeste." % [character_id, anim_name])
	player.remove_animation_library(&"")
	player.add_animation_library(library_name, library)
	_use_vertex_colors(scene, character_id)
	return scene


func _use_vertex_colors(scene: Node, character_id: String) -> void:
	var meshes: Array[Node] = scene.find_children("*", "MeshInstance3D", true, false)
	if meshes.is_empty():
		push_error("Import de %s : aucun maillage." % character_id)
	for node: Node in meshes:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		for surface: int in mesh.get_surface_count():
			var material: BaseMaterial3D = mesh.surface_get_material(surface) as BaseMaterial3D
			if material == null:
				push_error("Import de %s : surface %d sans matériau standard." % [character_id, surface])
				continue
			# Couleurs de sommets en espace linéaire (convention glTF).
			material.vertex_color_use_as_albedo = true
			material.vertex_color_is_srgb = false


func _find_character(character_id: String) -> Dictionary:
	var text: String = FileAccess.get_file_as_string(MANIFEST_PATH)
	var json := JSON.new()
	if text.is_empty() or json.parse(text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		push_error("Import de %s : manifeste %s illisible." % [character_id, MANIFEST_PATH])
		return {}
	var manifest: Dictionary = json.data
	var characters: Variant = manifest.get("characters")
	if typeof(characters) == TYPE_ARRAY:
		for raw: Variant in characters:
			if typeof(raw) == TYPE_DICTIONARY and (raw as Dictionary).get("id") == character_id:
				return raw
	push_error("Import de %s : personnage absent de %s." % [character_id, MANIFEST_PATH])
	return {}
