class_name SoundLibrary
extends RefCounted
## Accès aux sons libres déclarés dans res://data/assets/sounds.json.
##
## Les fichiers sont téléchargés et vérifiés par Scripts/Pipeline/importer-sons.ps1, puis importés
## par Godot : chaque son se trouve dans <destination><id>.ogg. Tout son absent ou illisible est
## signalé par push_error (ce qui fait échouer le pipeline).

const MANIFEST_PATH: String = "res://data/assets/sounds.json"


## Chemin res:// de chaque son du manifeste, indexé par identifiant.
static func get_paths(manifest: Dictionary) -> Dictionary[String, String]:
	var paths: Dictionary[String, String] = {}
	var destination: String = JsonData.get_string(manifest, "destination", MANIFEST_PATH)
	if not destination.begins_with("res://") or not destination.ends_with("/"):
		push_error("SoundLibrary : « destination » doit être un dossier res:// terminé par « / » (%s)." % MANIFEST_PATH)
		return paths
	for entry: Variant in JsonData.get_array(manifest, "sounds", MANIFEST_PATH):
		if typeof(entry) != TYPE_DICTIONARY:
			push_error("SoundLibrary : chaque son doit être un objet JSON (%s)." % MANIFEST_PATH)
			continue
		var sound: Dictionary = entry
		var id: String = JsonData.get_string(sound, "id", MANIFEST_PATH)
		if id.is_empty():
			continue
		if paths.has(id):
			push_error("SoundLibrary : identifiant de son en double « %s » (%s)." % [id, MANIFEST_PATH])
			continue
		paths[id] = "%s%s.ogg" % [destination, id]
	return paths


## Charge les sons demandés. Renvoie un dictionnaire identifiant → AudioStream (sons valides seulement).
## cache_mode : ResourceLoader.CACHE_MODE_IGNORE pour un son lu en continu (ambiance en boucle) qu'un arrêt
## brutal du jeu laisserait sinon au cache des ressources pendant que le serveur audio le lit encore.
static func load_streams(
	manifest: Dictionary, ids: PackedStringArray, cache_mode: ResourceLoader.CacheMode = ResourceLoader.CACHE_MODE_REUSE
) -> Dictionary[String, AudioStream]:
	var streams: Dictionary[String, AudioStream] = {}
	var paths: Dictionary[String, String] = get_paths(manifest)
	for id: String in ids:
		if streams.has(id):
			continue
		if not paths.has(id):
			push_error("SoundLibrary : son « %s » absent du manifeste %s." % [id, MANIFEST_PATH])
			continue
		var path: String = paths[id]
		if not ResourceLoader.exists(path):
			push_error("SoundLibrary : fichier %s introuvable. Lancez Scripts/Pipeline/importer-ressources.ps1 puis importer.ps1." % path)
			continue
		var stream: AudioStream = ResourceLoader.load(path, "", cache_mode) as AudioStream
		if stream == null:
			push_error("SoundLibrary : %s n'est pas un son lisible." % path)
			continue
		streams[id] = stream
	return streams
