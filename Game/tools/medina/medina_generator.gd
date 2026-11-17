class_name MedinaGenerator
extends RefCounted
## Générateur de la médina de Tunis : description + graine + catalogue → instances, plan et verrou.
##
## Étapes : validation de la description (bornes) → plan topologique validé (graphe) → instanciation
## → retouches déclarées → contrôles géométriques et budgets → fichiers canoniques. Aucune étape ne
## produit de fichier si une étape précédente a signalé une erreur. Même graine + même description +
## même catalogue (et mêmes maillages) = mêmes instances, mêmes identifiants, même ordre, mêmes octets.
##
## La génération est un outil de développement : le jeu ne régénère jamais la ville, il lit les cellules.

const GENERATOR_VERSION: int = 1

var errors: PackedStringArray = PackedStringArray()
var generated: Array[Dictionary] = []
var manual: Array[Dictionary] = []
var layout: Dictionary = {}
var stats: Dictionary = {}
var files: Dictionary = {}
var previous_cells: Array = []
## Vrai si des instances générées ont été modifiées à la main depuis la dernière génération.
var hand_edited: bool = false


## Génère tout en mémoire. « existing » : instances actuellement dans les cellules (manuelles et générées).
static func generate(
	city: Dictionary,
	catalog: Dictionary,
	description_data: Dictionary,
	overrides: Dictionary,
	existing: Array[Dictionary],
	lock: Dictionary
) -> MedinaGenerator:
	var result := MedinaGenerator.new()
	result._run(city, catalog, description_data, overrides, existing, lock)
	return result


## Génère depuis les fichiers du projet.
static func from_project() -> MedinaGenerator:
	var store := MedinaStore.new()
	var city: Dictionary = JsonData.load_dictionary(MedinaStore.CITY_PATH)
	var existing: Array[Dictionary] = store.load_cells(city)
	var lock: Dictionary = {}
	if FileAccess.file_exists(MedinaStore.LOCK_PATH):
		lock = JsonData.load_dictionary(MedinaStore.LOCK_PATH)
	var result: MedinaGenerator = generate(
		city,
		JsonData.load_dictionary(MedinaStore.CATALOG_PATH),
		JsonData.load_dictionary(MedinaStore.DESCRIPTION_PATH),
		JsonData.load_dictionary(MedinaStore.OVERRIDES_PATH),
		existing,
		lock
	)
	result.errors.append_array(store.errors)
	return result


func is_valid() -> bool:
	return errors.is_empty()


func _run(
	city: Dictionary,
	catalog: Dictionary,
	description_data: Dictionary,
	overrides: Dictionary,
	existing: Array[Dictionary],
	lock: Dictionary
) -> void:
	previous_cells = (city.get("cells", []) as Array).duplicate()
	var city_errors: PackedStringArray = TunisDataValidator.validate_documents(
		city, catalog, [], {"schema_version": 1, "interactions": []}, {"schema_version": 1, "zones": []}
	)
	if not city_errors.is_empty():
		errors.append_array(city_errors)
		return
	var description := MedinaDescription.create(description_data, int(city["seed"]))
	if not description.is_valid():
		errors.append_array(description.errors)
		return
	var plan := MedinaPlan.create(description)
	if not description.is_valid():
		errors.append_array(description.errors)
		return
	var builder := MedinaBuilder.create(description, plan, catalog, city)
	if not description.is_valid():
		errors.append_array(description.errors)
		return
	var raw_origin: Array = city["origin"]
	var origin := Vector3(float(raw_origin[0]), float(raw_origin[1]), float(raw_origin[2]))
	var store := MedinaStore.new()
	generated = store.apply_overrides(builder.instances, overrides, origin, float(city["cell_size_m"]))
	errors.append_array(store.errors)
	if not errors.is_empty():
		return
	var generated_ids := {}
	for instance: Dictionary in generated:
		generated_ids[String(instance["id"])] = true
	var previous_generated: Array[Dictionary] = []
	for instance: Dictionary in existing:
		if MedinaStore.is_generated(instance):
			previous_generated.append(instance)
		else:
			if generated_ids.has(String(instance["id"])):
				errors.append("L'instance manuelle « %s » porte un identifiant réservé au générateur." % instance["id"])
			manual.append(instance)
	if not previous_generated.is_empty():
		hand_edited = MedinaStore.fingerprint(previous_generated) != String(lock.get("generated_sha256", ""))
	var all_instances: Array[Dictionary] = generated.duplicate()
	all_instances.append_array(manual)
	var checks := MedinaChecks.new()
	checks.run(description, plan, city, all_instances, MedinaChecks.measure_prefabs(catalog))
	errors.append_array(checks.errors)
	stats = checks.stats
	if not errors.is_empty():
		return
	layout = builder.layout
	layout["stats"] = stats
	var lock_out := {
		"schema_version": MedinaStore.SCHEMA_VERSION,
		"generator_version": GENERATOR_VERSION,
		"seed": int(city["seed"]),
		"generated_sha256": MedinaStore.fingerprint(generated),
		"inputs_sha256": _inputs_fingerprint(city, catalog, description_data, overrides)
	}
	files = store.expected_files(city, all_instances, layout, lock_out)
	# Le contrat MVP 4 doit accepter le résultat tel quel.
	var cells: Array = []
	for path: Variant in files:
		if String(path).begins_with(MedinaStore.DATA_ROOT + MedinaStore.CELLS_DIR):
			var json := JSON.new()
			if json.parse(String(files[path])) != OK:
				errors.append("Cellule générée illisible : %s." % path)
				continue
			cells.append(json.data)
	var json_city := JSON.new()
	if json_city.parse(String(files[MedinaStore.CITY_PATH])) != OK or typeof(json_city.data) != TYPE_DICTIONARY:
		errors.append("city.json généré illisible.")
		return
	var final_city: Dictionary = json_city.data
	errors.append_array(
		TunisDataValidator.validate_documents(
			final_city,
			catalog,
			cells,
			JsonData.load_dictionary(MedinaStore.DATA_ROOT + "interactions.json"),
			JsonData.load_dictionary(MedinaStore.DATA_ROOT + "audio.json")
		)
	)


func _inputs_fingerprint(city: Dictionary, catalog: Dictionary, description_data: Dictionary, overrides: Dictionary) -> String:
	var inputs := {"seed": city["seed"], "catalog": catalog, "description": description_data, "overrides": overrides}
	return TunisDataValidator.canonical_json(MedinaStore.normalized(inputs)).sha256_text()
