class_name SoundLibrary
extends RefCounted
## Sons du jeu : chaque son est generated/sons/<identifiant>.ogg.
##
## Deux origines, copiées par outils/construire.gd (copy_sources) avant les constructeurs de scènes :
## - les sons téléchargés par valider.bat : data/ressources.json › fichiers rangés dans le dossier « sons »
##   (l'identifiant est la clé du fichier) ;
## - les sons versionnés de sources/sons/ (l'identifiant est le nom du fichier sans « .ogg »).
## Copie seulement si le contenu change ; Godot importe ensuite les .ogg (sans boucle).
## Tout son absent ou illisible au chargement est signalé par push_error (ce qui fait échouer la validation).

const DIRECTORY: String = "res://generated/sons"
const SOUND_FOLDER: String = "sons"
const VERSIONED_DIRECTORY: String = "res://sources/sons"


static func path_of(id: String) -> String:
	return DIRECTORY.path_join(id + ".ogg")


## Charge les sons demandés. Renvoie un dictionnaire identifiant → AudioStream (sons valides seulement).
## cache_mode : ResourceLoader.CACHE_MODE_IGNORE pour un son lu en continu qu'un arrêt brutal du jeu laisserait
## sinon au cache des ressources pendant que le serveur audio le lit encore.
static func load_streams(
	ids: PackedStringArray, cache_mode: ResourceLoader.CacheMode = ResourceLoader.CACHE_MODE_REUSE
) -> Dictionary[String, AudioStream]:
	var streams: Dictionary[String, AudioStream] = {}
	for id: String in ids:
		if streams.has(id):
			continue
		var path: String = path_of(id)
		if not ResourceLoader.exists(path):
			push_error("SoundLibrary : son %s introuvable (lancez valider.bat)." % path)
			continue
		var stream: AudioStream = ResourceLoader.load(path, "", cache_mode) as AudioStream
		if stream == null:
			push_error("SoundLibrary : %s n'est pas un son lisible." % path)
			continue
		streams[id] = stream
	return streams


## Copie les sons téléchargés et versionnés dans generated/sons/. Renvoie les erreurs.
static func copy_sources(manifest: ResourceManifest) -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY))
	for key: String in manifest.file_keys():
		if manifest.file_folder(key) != ResourceManifest.DOWNLOAD_ROOT.path_join(SOUND_FOLDER):
			continue
		_copy(manifest.file_local_path(key), key, errors)
	for file_name: String in DirAccess.get_files_at(VERSIONED_DIRECTORY):
		if file_name.get_extension() == "ogg":
			_copy(VERSIONED_DIRECTORY.path_join(file_name), file_name.get_basename(), errors)
	return errors


static func _copy(source: String, id: String, errors: PackedStringArray) -> void:
	if not id.is_valid_ascii_identifier():
		errors.append("SoundLibrary : identifiant de son invalide « %s »." % id)
		return
	var absolute: String = ProjectSettings.globalize_path(source)
	if not FileAccess.file_exists(absolute):
		errors.append("SoundLibrary : fichier absent %s (lancez valider.bat pour le télécharger)." % absolute)
		return
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(absolute)
	var target: String = ProjectSettings.globalize_path(path_of(id))
	if FileAccess.file_exists(target) and FileAccess.get_file_as_bytes(target) == bytes:
		return
	var file: FileAccess = FileAccess.open(target, FileAccess.WRITE)
	if file == null:
		errors.append("SoundLibrary : impossible d'écrire " + target)
		return
	file.store_buffer(bytes)
	file.close()
	GameLog.info("sons", "Son copié : " + path_of(id))
