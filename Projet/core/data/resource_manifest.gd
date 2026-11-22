class_name ResourceManifest
extends RefCounted
## Manifeste des ressources libres (data/ressources.json) : pour chaque texture,
## l'origine, la licence et les fichiers à télécharger. Le pipeline télécharge les
## fichiers dans ressources/telechargees/<clé>/ et vérifie leurs empreintes.

const PATH: String = "res://data/ressources.json"
const LOCK_PATH: String = "res://data/ressources.lock.json"
const DOWNLOAD_ROOT: String = "res://ressources/telechargees"
const TEXTURE_MAPS: PackedStringArray = ["albedo", "normal", "roughness", "height"]
const ACCEPTED_LICENCES: PackedStringArray = ["CC0 1.0"]

var errors: PackedStringArray = PackedStringArray()
var _textures: Dictionary = {}
## Fichiers isolés : clé -> adresse.
var _files: Dictionary = {}


static func load_shipped() -> ResourceManifest:
	return from_dictionary(JsonData.load_dictionary(PATH))


static func from_dictionary(data: Dictionary) -> ResourceManifest:
	var manifest: ResourceManifest = ResourceManifest.new()
	var textures: Dictionary = JsonData.read_dictionary(data, "textures", manifest.errors, "ressources.json")
	for key: String in textures:
		var context: String = "ressources.json › " + key
		var entry: Variant = textures[key]
		if typeof(entry) != TYPE_DICTIONARY:
			manifest.errors.append(context + " : objet attendu.")
			continue
		manifest._check_origin(entry, context)
		var files: Dictionary = JsonData.read_dictionary(entry, "files", manifest.errors, context)
		for map_name: String in TEXTURE_MAPS:
			var url: String = JsonData.read_string(files, map_name, manifest.errors, context + " › files")
			if not url.is_empty() and not url.begins_with("https://"):
				manifest.errors.append("%s : l'adresse de « %s » doit être en https." % [context, map_name])
		manifest._textures[key] = files
	var single_files: Dictionary = data.get("fichiers", {}) if typeof(data.get("fichiers", {})) == TYPE_DICTIONARY else {}
	for key: String in single_files:
		var context: String = "ressources.json › fichiers › " + key
		var entry: Variant = single_files[key]
		if typeof(entry) != TYPE_DICTIONARY:
			manifest.errors.append(context + " : objet attendu.")
			continue
		manifest._check_origin(entry, context)
		JsonData.read_string(entry, "usage", manifest.errors, context)
		var url: String = JsonData.read_string(entry, "url", manifest.errors, context)
		if not url.is_empty() and not url.begins_with("https://"):
			manifest.errors.append(context + " : l'adresse doit être en https.")
		if manifest._textures.has(key):
			manifest.errors.append(context + " : clé déjà utilisée par une texture.")
		manifest._files[key] = url
	return manifest


func _check_origin(entry: Dictionary, context: String) -> void:
	JsonData.read_string(entry, "source", errors, context)
	JsonData.read_string(entry, "page", errors, context)
	var licence: String = JsonData.read_string(entry, "licence", errors, context)
	if not licence.is_empty() and licence not in ACCEPTED_LICENCES:
		errors.append("%s : licence « %s » non acceptée." % [context, licence])


func has_texture(key: String) -> bool:
	return _textures.has(key)


func texture_keys() -> PackedStringArray:
	return PackedStringArray(_textures.keys())


func url(key: String, map_name: String) -> String:
	return String(_textures[key][map_name])


func has_file(key: String) -> bool:
	return _files.has(key)


func file_keys() -> PackedStringArray:
	return PackedStringArray(_files.keys())


func file_url(key: String) -> String:
	return String(_files[key])


## Chemin res:// d'un fichier isolé téléchargé.
func file_local_path(key: String) -> String:
	return DOWNLOAD_ROOT.path_join(key).path_join(file_url(key).get_file())


## Chemin res:// du fichier téléchargé pour une carte d'une texture.
func local_path(key: String, map_name: String) -> String:
	return DOWNLOAD_ROOT.path_join(key).path_join(url(key, map_name).get_file())
