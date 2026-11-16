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
static func load_streams(manifest: Dictionary, ids: PackedStringArray) -> Dictionary[String, AudioStream]:
	var streams: Dictionary[String, AudioStream] = {}
	var paths: Dictionary[String, String] = get_paths(manifest)
	for id: String in ids:
		if streams.has(id):
			continue
		var synthesized: Dictionary = manifest.get("synthesized", {})
		if synthesized.has(id):
			var made: AudioStream = _synthesize(id, synthesized[id])
			if made != null:
				streams[id] = made
			continue
		if not paths.has(id):
			push_error("SoundLibrary : son « %s » absent du manifeste %s." % [id, MANIFEST_PATH])
			continue
		var path: String = paths[id]
		if not ResourceLoader.exists(path):
			push_error("SoundLibrary : fichier %s introuvable. Lancez Scripts/Pipeline/importer-ressources.ps1 puis importer.ps1." % path)
			continue
		var stream: AudioStream = load(path) as AudioStream
		if stream == null:
			push_error("SoundLibrary : %s n'est pas un son lisible." % path)
			continue
		streams[id] = stream
	return streams


## Son calculé (section « synthesized » du manifeste) ; null (avec erreur) si son type est inconnu.
static func _synthesize(id: String, params: Variant) -> AudioStream:
	if typeof(params) != TYPE_DICTIONARY:
		push_error("SoundLibrary : le son synthétisé « %s » doit être un objet JSON (%s)." % [id, MANIFEST_PATH])
		return null
	var settings: Dictionary = params
	var kind: String = JsonData.get_string(settings, "kind", MANIFEST_PATH)
	if kind == "water_step":
		return SoundSynth.water_step(settings, id)
	push_error("SoundLibrary : type de son synthétisé inconnu « %s » (%s)." % [kind, id])
	return null
