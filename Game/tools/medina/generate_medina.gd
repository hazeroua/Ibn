extends SceneTree
## Génère la médina de Tunis dans Game/data/tunis/ (Scripts/Pipeline/generer-medina.ps1).
##
## Arguments après « -- » :
##   --check    vérifie seulement que les fichiers du projet sont à jour (aucune écriture) ;
##   --confirm  autorise le remplacement d'instances générées modifiées à la main dans les cellules
##              (les retouches durables vont dans generation/medina_overrides.json).
## Les instances ajoutées à la main (sans « properties.generator ») sont toujours conservées.

const ARG_CHECK: String = "--check"
const ARG_CONFIRM: String = "--confirm"


func _initialize() -> void:
	quit(_run())


func _run() -> int:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var check_only: bool = arguments.has(ARG_CHECK)
	var confirmed: bool = arguments.has(ARG_CONFIRM)
	var generator: MedinaGenerator = MedinaGenerator.from_project()
	if not generator.is_valid():
		for message: String in generator.errors:
			push_error("Médina : " + message)
		return 1
	var stale: PackedStringArray = MedinaStore.stale_files(generator.files)
	for orphan: String in _orphan_cells(generator.files):
		stale.append(orphan)
	print("Médina : %s" % JSON.stringify(generator.stats))
	if check_only:
		if not stale.is_empty():
			push_error("Médina : données générées à régénérer (generer-medina.ps1) : %s." % ", ".join(stale))
			return 1
		print("Médina : données à jour.")
		return 0
	if stale.is_empty():
		print("Médina : rien à écrire, les données sont déjà à jour.")
		return 0
	if generator.hand_edited and not confirmed:
		push_error(
			(
				"Médina : des instances générées ont été modifiées directement dans les cellules. "
				+ "Déplacez ces retouches dans generation/medina_overrides.json, ou relancez avec -Confirmer pour les remplacer."
			)
		)
		return 1
	var store := MedinaStore.new()
	if not store.write_files(generator.files, generator.previous_cells):
		for message: String in store.errors:
			push_error("Médina : " + message)
		return 1
	print("Médina : %d fichier(s) écrit(s), %d instance(s) manuelle(s) conservée(s)." % [stale.size(), generator.manual.size()])
	return 0


func _orphan_cells(files: Dictionary) -> PackedStringArray:
	var orphans := PackedStringArray()
	var folder: String = MedinaStore.DATA_ROOT + MedinaStore.CELLS_DIR
	if not DirAccess.dir_exists_absolute(folder):
		return orphans
	for name: String in DirAccess.get_files_at(folder):
		if name.ends_with(".json") and not files.has(folder + name):
			orphans.append(folder + name)
	return orphans
