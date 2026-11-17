class_name MedinaStore
extends RefCounted
## Lecture et écriture canoniques des données de Tunis touchées par le générateur de médina.
##
## Format canonique : clés triées, une instance par ligne, instances triées par identifiant ; deux
## écritures des mêmes données donnent exactement les mêmes octets UTF-8 (contrat MVP 4).
##
## Retouches : une instance sans « properties.generator = medina » est une donnée ordinaire, conservée
## telle quelle à chaque génération. Les modifications d'instances générées passent par
## generation/medina_overrides.json (appliquées après chaque génération). Le verrou
## generation/medina_lock.json garde l'empreinte des instances générées écrites : si quelqu'un les a
## modifiées directement dans une cellule, la régénération est refusée sans confirmation explicite.

const DATA_ROOT: String = "res://data/tunis/"
const CITY_PATH: String = DATA_ROOT + "city.json"
const CATALOG_PATH: String = DATA_ROOT + "catalog.json"
const DESCRIPTION_PATH: String = DATA_ROOT + "generation/medina.json"
const OVERRIDES_PATH: String = DATA_ROOT + "generation/medina_overrides.json"
const LAYOUT_PATH: String = DATA_ROOT + "generation/medina_layout.json"
const LOCK_PATH: String = DATA_ROOT + "generation/medina_lock.json"
const CELLS_DIR: String = "cells/"
const SCHEMA_VERSION: int = 1
const GENERATOR_TAG: String = MedinaBuilder.GENERATOR_TAG
const INDENT: String = "  "

var errors: PackedStringArray = PackedStringArray()


static func cell_path(cell: Vector2i) -> String:
	return "%scell_%d_%d.json" % [CELLS_DIR, cell.x, cell.y]


static func is_generated(instance: Dictionary) -> bool:
	var properties: Variant = instance.get("properties")
	return typeof(properties) == TYPE_DICTIONARY and String((properties as Dictionary).get("generator", "")) == GENERATOR_TAG


## Valeur JSON où tous les nombres sont des flottants : les empreintes ne dépendent pas du fait
## qu'un nombre ait été relu comme entier ou comme flottant.
static func normalized(value: Variant) -> Variant:
	match typeof(value):
		TYPE_INT:
			return float(value)
		TYPE_DICTIONARY:
			var result := {}
			for key: Variant in value:
				result[String(key)] = normalized(value[key])
			return result
		TYPE_ARRAY:
			var result: Array = []
			for entry: Variant in value:
				result.append(normalized(entry))
			return result
	return value


static func fingerprint(instances: Array) -> String:
	var sorted: Array = instances.duplicate()
	sorted.sort_custom(func(a: Variant, b: Variant) -> bool: return String(a["id"]) < String(b["id"]))
	var lines := PackedStringArray()
	for instance: Variant in sorted:
		lines.append(TunisDataValidator.canonical_json(normalized(instance)))
	return "\n".join(lines).sha256_text()


## Objet JSON canonique sur plusieurs lignes : une clé par ligne ; une liste d'objets ou de chaînes
## s'écrit un élément par ligne. Le reste est compact (TunisDataValidator.canonical_json).
static func pretty(document: Dictionary) -> String:
	var keys: Array = document.keys()
	keys.sort()
	var lines := PackedStringArray()
	for index: int in keys.size():
		var key: String = String(keys[index])
		var value: Variant = document[key]
		var text: String = TunisDataValidator.canonical_json(value)
		if _is_list_of_records(value):
			var items := PackedStringArray()
			for entry: Variant in value:
				items.append(INDENT + INDENT + TunisDataValidator.canonical_json(entry))
			text = "[\n" + ",\n".join(items) + "\n" + INDENT + "]"
		lines.append("%s%s: %s%s" % [INDENT, JSON.stringify(key), text, "," if index < keys.size() - 1 else ""])
	return "{\n" + "\n".join(lines) + "\n}\n"


static func _is_list_of_records(value: Variant) -> bool:
	if typeof(value) != TYPE_ARRAY or (value as Array).is_empty():
		return false
	var first: int = typeof((value as Array)[0])
	return first == TYPE_DICTIONARY or first == TYPE_STRING or first == TYPE_ARRAY


## city.json réécrit avec ses entiers en entiers (le lecteur JSON rend tous les nombres en flottants).
static func typed_city(city: Dictionary, cells: Array) -> Dictionary:
	var result: Dictionary = city.duplicate(true)
	var bounds: Dictionary = city["bounds"]
	var raw_min: Array = bounds["min_cell"]
	var raw_max: Array = bounds["max_cell"]
	result["schema_version"] = int(city["schema_version"])
	result["seed"] = int(city["seed"])
	result["bounds"] = {"min_cell": [int(raw_min[0]), int(raw_min[1])], "max_cell": [int(raw_max[0]), int(raw_max[1])]}
	result["cell_size_m"] = float(city["cell_size_m"])
	var raw_origin: Array = city["origin"]
	result["origin"] = [float(raw_origin[0]), float(raw_origin[1]), float(raw_origin[2])]
	result["cells"] = cells
	return result


static func read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


## Instances des cellules actuellement listées dans city.json.
func load_cells(city: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_path: Variant in city.get("cells", []):
		var document: Dictionary = JsonData.load_dictionary(DATA_ROOT + String(raw_path))
		for raw_instance: Variant in document.get("instances", []):
			if typeof(raw_instance) != TYPE_DICTIONARY:
				errors.append("%s : instance qui n'est pas un objet." % raw_path)
				continue
			result.append(raw_instance)
	return result


## Applique les retouches déclarées aux instances générées ; toute retouche orpheline est une erreur.
func apply_overrides(generated: Array[Dictionary], overrides: Dictionary, origin: Vector3, cell_size: float) -> Array[Dictionary]:
	if int(overrides.get("schema_version", -1)) != SCHEMA_VERSION:
		errors.append("medina_overrides.schema_version doit valoir %d." % SCHEMA_VERSION)
		return generated
	var by_id := {}
	for instance: Dictionary in generated:
		by_id[String(instance["id"])] = instance
	var removed := {}
	for raw_override: Variant in overrides.get("overrides", []):
		if typeof(raw_override) != TYPE_DICTIONARY:
			errors.append("medina_overrides : chaque retouche doit être un objet.")
			continue
		var override: Dictionary = raw_override
		var id: String = String(override.get("id", ""))
		if not by_id.has(id):
			errors.append("medina_overrides : la retouche vise une instance générée inconnue : « %s »." % id)
			continue
		if bool(override.get("remove", false)):
			removed[id] = true
			continue
		var target: Dictionary = by_id[id]
		var changes: Variant = override.get("set")
		if typeof(changes) != TYPE_DICTIONARY:
			errors.append("medina_overrides.%s : « set » ou « remove » est requis." % id)
			continue
		for key: Variant in changes:
			match String(key):
				"position", "rotation_y", "scale", "prefab_id", "layer":
					target[String(key)] = changes[key]
				"properties":
					var properties: Dictionary = (target["properties"] as Dictionary).duplicate()
					properties.merge(changes[key] as Dictionary, true)
					properties["generator"] = GENERATOR_TAG
					target["properties"] = properties
				_:
					errors.append("medina_overrides.%s : champ non retouchable : %s." % [id, key])
		var raw_position: Array = target["position"]
		var position := Vector3(float(raw_position[0]), float(raw_position[1]), float(raw_position[2]))
		var cell: Vector2i = TunisDataValidator.cell_for_position(position, origin, cell_size)
		target["cell"] = [cell.x, cell.y]
	var result: Array[Dictionary] = []
	for instance: Dictionary in generated:
		if not removed.has(String(instance["id"])):
			result.append(instance)
	return result


## Contenu attendu de chaque fichier écrit par le générateur (chemin res:// → texte).
func expected_files(city: Dictionary, instances: Array[Dictionary], layout: Dictionary, lock: Dictionary) -> Dictionary:
	var by_cell := {}
	for instance: Dictionary in instances:
		var raw_cell: Array = instance["cell"]
		var cell := Vector2i(int(raw_cell[0]), int(raw_cell[1]))
		if not by_cell.has(cell):
			by_cell[cell] = []
		(by_cell[cell] as Array).append(instance)
	var cells: Array = by_cell.keys()
	cells.sort()
	var files := {}
	var paths: Array = []
	for cell: Vector2i in cells:
		var entries: Array = by_cell[cell]
		entries.sort_custom(func(a: Variant, b: Variant) -> bool: return String(a["id"]) < String(b["id"]))
		var path: String = cell_path(cell)
		paths.append(path)
		files[DATA_ROOT + path] = pretty({"schema_version": SCHEMA_VERSION, "cell": [cell.x, cell.y], "instances": entries})
	files[CITY_PATH] = pretty(typed_city(city, paths))
	files[LAYOUT_PATH] = pretty(layout)
	files[LOCK_PATH] = pretty(lock)
	return files


func write_files(files: Dictionary, previous_cells: Array) -> bool:
	for path: Variant in files:
		var output := FileAccess.open(String(path), FileAccess.WRITE)
		if output == null:
			errors.append("Écriture impossible : %s (%s)." % [path, error_string(FileAccess.get_open_error())])
			return false
		output.store_string(String(files[path]))
		output.close()
	var stale: Array = []
	for raw_path: Variant in previous_cells:
		stale.append(DATA_ROOT + String(raw_path))
	for name: String in DirAccess.get_files_at(DATA_ROOT + CELLS_DIR):
		if name.ends_with(".json"):
			stale.append(DATA_ROOT + CELLS_DIR + name)
	for path: String in stale:
		if files.has(path) or not FileAccess.file_exists(path):
			continue
		var error: Error = DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		if error != OK:
			errors.append("Suppression impossible de la cellule vidée %s (%s)." % [path, error_string(error)])
			return false
	return true


## Fichiers dont le contenu sur disque diffère du contenu attendu.
static func stale_files(files: Dictionary) -> PackedStringArray:
	var stale := PackedStringArray()
	for path: Variant in files:
		if read_text(String(path)) != String(files[path]):
			stale.append(String(path))
	return stale
