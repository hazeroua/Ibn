extends GutTest
## Générateur de la médina (#53) : données du projet à jour, déterminisme, dix graines valides, rejet
## des descriptions invalides (bornes, croisement non déclaré, impasse non déclarée), conservation des
## instances manuelles, retouches déclarées, refus de la régénération après retouche directe, et
## détection des chevauchements et des trous dans les remparts.
##
## Pires cas : description complète (4 voies, place, passage couvert, arcs, 3 emplacements, terrasse),
## dix graines différentes, ville entière contrôlée (plusieurs centaines d'instances, toutes les paires
## voisines testées). Les durées de génération sont imprimées par gut.p.

const SEEDS: Array[int] = [1, 7, 42, 99, 314, 1348, 2024, 4096, 65535, 777777]
## Budget de génération d'une ville complète (outil de développement, hors jeu), en millisecondes.
const GENERATION_BUDGET_MS: float = 15000.0

var _city: Dictionary = {}
var _catalog: Dictionary = {}
var _description: Dictionary = {}
var _overrides: Dictionary = {}


func before_all() -> void:
	_city = JsonData.load_dictionary(MedinaStore.CITY_PATH)
	_catalog = JsonData.load_dictionary(MedinaStore.CATALOG_PATH)
	_description = JsonData.load_dictionary(MedinaStore.DESCRIPTION_PATH)
	_overrides = JsonData.load_dictionary(MedinaStore.OVERRIDES_PATH)


func _generate(
	city: Dictionary, description: Dictionary, overrides: Dictionary = _overrides, existing: Array[Dictionary] = [], lock: Dictionary = {}
) -> MedinaGenerator:
	return MedinaGenerator.generate(city, _catalog, description, overrides, existing, lock)


func _with_seed(seed_value: int) -> Dictionary:
	var city: Dictionary = _city.duplicate(true)
	city["seed"] = seed_value
	city["cells"] = []
	return city


func _errors_contain(generator: MedinaGenerator, fragment: String) -> bool:
	for message: String in generator.errors:
		if message.contains(fragment):
			return true
	return false


func _instance(generator: MedinaGenerator, id: String) -> Dictionary:
	for instance: Dictionary in generator.generated:
		if String(instance["id"]) == id:
			return instance
	return {}


func _first_with_layer(generator: MedinaGenerator, layer: String) -> Dictionary:
	for instance: Dictionary in generator.generated:
		if String(instance["layer"]) == layer:
			return instance
	return {}


func test_project_data_is_up_to_date() -> void:
	var started: int = Time.get_ticks_usec()
	var generator: MedinaGenerator = MedinaGenerator.from_project()
	var elapsed_ms: float = float(Time.get_ticks_usec() - started) / 1000.0
	assert_true(generator.is_valid(), "génération du projet : %s" % "; ".join(generator.errors))
	assert_false(generator.hand_edited, "aucune instance générée ne doit avoir été retouchée à la main")
	assert_eq(
		MedinaStore.stale_files(generator.files),
		PackedStringArray(),
		"les fichiers versionnés doivent être exactement ceux que produit le générateur"
	)
	gut.p("Médina du projet : %s, générée en %.0f ms." % [JSON.stringify(generator.stats), elapsed_ms])
	assert_lt(elapsed_ms, GENERATION_BUDGET_MS)


func test_generation_is_deterministic() -> void:
	var first: MedinaGenerator = _generate(_with_seed(1348), _description)
	var second: MedinaGenerator = _generate(_with_seed(1348), _description)
	assert_true(first.is_valid(), "; ".join(first.errors))
	assert_eq(first.files.keys(), second.files.keys())
	for path: Variant in first.files:
		assert_eq(String(first.files[path]), String(second.files[path]), "contenu identique : %s" % path)
	var ids_first: Array = []
	var ids_second: Array = []
	for instance: Dictionary in first.generated:
		ids_first.append(instance["id"])
	for instance: Dictionary in second.generated:
		ids_second.append(instance["id"])
	assert_eq(ids_first, ids_second, "mêmes identifiants dans le même ordre")


func test_ten_seeds_are_valid() -> void:
	var worst_ms: float = 0.0
	var largest: int = 0
	for seed_value: int in SEEDS:
		var started: int = Time.get_ticks_usec()
		var generator: MedinaGenerator = _generate(_with_seed(seed_value), _description)
		var elapsed_ms: float = float(Time.get_ticks_usec() - started) / 1000.0
		worst_ms = maxf(worst_ms, elapsed_ms)
		assert_true(generator.is_valid(), "graine %d : %s" % [seed_value, "; ".join(generator.errors)])
		if not generator.is_valid():
			continue
		largest = maxi(largest, int(generator.stats["instances"]))
		var kinds: Array = []
		for slot: Variant in generator.layout["slots"]:
			kinds.append(String((slot as Dictionary)["kind"]))
		kinds.sort()
		assert_eq(kinds, ["house", "mosque", "shop"], "graine %d : trois emplacements réservés" % seed_value)
		assert_false((generator.layout["terrace_access"] as Dictionary).is_empty(), "graine %d : accès à la terrasse" % seed_value)
		var passages: int = 0
		for span: Variant in generator.layout["spans"]:
			if String((span as Dictionary)["prefab"]) == MedinaBuilder.PREFAB_PASSAGE:
				passages += 1
		assert_eq(passages, 1, "graine %d : un passage couvert" % seed_value)
	gut.p("Dix graines : génération la plus lente %.0f ms, ville la plus grande %d instances." % [worst_ms, largest])
	assert_lt(worst_ms, GENERATION_BUDGET_MS)


func test_parameter_outside_limits_is_rejected() -> void:
	var description: Dictionary = _description.duplicate(true)
	((description["roles"] as Dictionary)["narrow"] as Dictionary)["width_m"] = {"range": [1.2, 1.4], "limits": [1.6, 2.0]}
	var generator: MedinaGenerator = _generate(_with_seed(1348), description)
	assert_false(generator.is_valid())
	assert_true(_errors_contain(generator, "sort des bornes"), "; ".join(generator.errors))
	assert_true(generator.files.is_empty(), "aucun fichier produit")


func test_undeclared_crossing_is_rejected() -> void:
	var description: Dictionary = _description.duplicate(true)
	var ways: Array = description["ways"]
	ways.append(
		{
			"id": "rogue_lane",
			"role": "alley",
			"start": {"plaza": "west", "offset_m": {"range": [3.0, 3.0], "limits": [-5.0, 5.0]}},
			"legs": [{"axis": "x", "by_m": {"range": [-30.0, -30.0], "limits": [-40.0, 0.0]}}],
			"end": {"dead_end": true}
		}
	)
	var generator: MedinaGenerator = _generate(_with_seed(1348), description)
	assert_false(generator.is_valid())
	assert_true(_errors_contain(generator, "sans carrefour déclaré"), "; ".join(generator.errors))


func test_undeclared_dead_end_is_rejected() -> void:
	var description: Dictionary = _description.duplicate(true)
	for way: Variant in description["ways"]:
		if String((way as Dictionary)["id"]) == "house_derb":
			(way as Dictionary)["end"] = {}
	var generator: MedinaGenerator = _generate(_with_seed(1348), description)
	assert_false(generator.is_valid())
	assert_true(_errors_contain(generator, "impasse déclarée"), "; ".join(generator.errors))


func test_manual_instances_are_preserved() -> void:
	var reference: MedinaGenerator = _generate(_with_seed(1348), _description)
	var fountain: Array = (reference.layout["plaza"] as Dictionary)["fountain"]
	var manual := {
		"id": "manual_jar_test",
		"prefab_id": "clay_jar",
		"cell": [0, 0],
		"position": [float(fountain[0]) + 2.6, 0.0, float(fountain[1])],
		"rotation_y": 0.0,
		"scale": [1.0, 1.0, 1.0],
		"layer": "prop",
		"properties": {}
	}
	var position := Vector3(float(manual["position"][0]), 0.0, float(manual["position"][2]))
	var cell: Vector2i = TunisDataValidator.cell_for_position(position, Vector3.ZERO, float(_city["cell_size_m"]))
	manual["cell"] = [cell.x, cell.y]
	var existing: Array[Dictionary] = [manual]
	var generator: MedinaGenerator = _generate(_with_seed(1348), _description, _overrides, existing)
	assert_true(generator.is_valid(), "; ".join(generator.errors))
	assert_eq(generator.manual.size(), 1)
	var found: bool = false
	for path: Variant in generator.files:
		found = found or String(generator.files[path]).contains(TunisDataValidator.canonical_json(manual))
	assert_true(found, "l'instance manuelle est réécrite à l'identique")


func test_manual_instance_overlapping_a_facade_is_rejected() -> void:
	var reference: MedinaGenerator = _generate(_with_seed(1348), _description)
	var facade: Dictionary = _first_with_layer(reference, MedinaBuilder.LAYER_FACADE)
	var overlapping := {
		"id": "manual_stall_inside_wall",
		"prefab_id": "market_stall",
		"cell": facade["cell"],
		"position": facade["position"],
		"rotation_y": 0.0,
		"scale": [1.0, 1.0, 1.0],
		"layer": "prop",
		"properties": {}
	}
	var existing: Array[Dictionary] = [overlapping]
	var generator: MedinaGenerator = _generate(_with_seed(1348), _description, _overrides, existing)
	assert_false(generator.is_valid())
	assert_true(_errors_contain(generator, "Chevauchement interdit"), "; ".join(generator.errors))


func test_overrides_are_applied_and_orphans_rejected() -> void:
	var reference: MedinaGenerator = _generate(_with_seed(1348), _description)
	var parapet: Dictionary = _first_with_layer(reference, MedinaBuilder.LAYER_PARAPET)
	var door: Dictionary = _first_with_layer(reference, MedinaBuilder.LAYER_DOOR)
	var overrides := {
		"schema_version": 1,
		"overrides": [{"id": parapet["id"], "remove": true}, {"id": door["id"], "set": {"properties": {"interaction_note": "retouche"}}}]
	}
	var generator: MedinaGenerator = _generate(_with_seed(1348), _description, overrides)
	assert_true(generator.is_valid(), "; ".join(generator.errors))
	assert_true(_instance(generator, String(parapet["id"])).is_empty(), "instance retirée par retouche")
	var edited: Dictionary = _instance(generator, String(door["id"]))
	assert_eq(String((edited["properties"] as Dictionary).get("interaction_note", "")), "retouche")
	assert_true(MedinaStore.is_generated(edited), "une instance retouchée reste générée")
	overrides["overrides"] = [{"id": "instance_disparue", "remove": true}]
	var orphan: MedinaGenerator = _generate(_with_seed(1348), _description, overrides)
	assert_false(orphan.is_valid())
	assert_true(_errors_contain(orphan, "instance_disparue"), "; ".join(orphan.errors))


func test_direct_edit_of_generated_instance_is_detected() -> void:
	var reference: MedinaGenerator = _generate(_with_seed(1348), _description)
	var lock: Dictionary = {"generated_sha256": MedinaStore.fingerprint(reference.generated)}
	var untouched: Array[Dictionary] = []
	for instance: Dictionary in reference.generated:
		untouched.append(instance.duplicate(true))
	var clean: MedinaGenerator = _generate(_with_seed(1348), _description, _overrides, untouched, lock)
	assert_false(clean.hand_edited, "instances identiques : pas de retouche détectée")
	var edited: Array[Dictionary] = []
	for instance: Dictionary in untouched:
		edited.append(instance.duplicate(true))
	(edited[0]["scale"] as Array)[1] = 1.7
	var touched: MedinaGenerator = _generate(_with_seed(1348), _description, _overrides, edited, lock)
	assert_true(touched.hand_edited, "une échelle modifiée dans une cellule doit être détectée")


func test_rampart_hole_is_detected() -> void:
	var reference: MedinaGenerator = _generate(_with_seed(1348), _description)
	var description := MedinaDescription.create(_description, 1348)
	var plan := MedinaPlan.create(description)
	var instances: Array[Dictionary] = []
	var removed: bool = false
	for instance: Dictionary in reference.generated:
		if not removed and String(instance["id"]) == "rampart_north_1":
			removed = true
			continue
		instances.append(instance)
	assert_true(removed, "le tronçon de rempart nord existe")
	var checks := MedinaChecks.new()
	checks.run(description, plan, _with_seed(1348), instances, MedinaChecks.measure_prefabs(_catalog))
	var found: bool = false
	for message: String in checks.errors:
		found = found or message.contains("Trou dans le rempart north")
	assert_true(found, "; ".join(checks.errors))


func test_cell_files_respect_the_contract() -> void:
	var generator: MedinaGenerator = MedinaGenerator.from_project()
	assert_true(generator.is_valid(), "; ".join(generator.errors))
	var provider: TunisCellProvider = TunisCellProvider.create()
	assert_not_null(provider, "le runtime de Tunis accepte les cellules générées")


func test_instance_blocking_a_way_is_rejected() -> void:
	var reference: MedinaGenerator = _generate(_with_seed(1348), _description)
	var facade: Dictionary = _instance(reference, "facade_e_xm1385_zm625_0")
	assert_false(facade.is_empty(), "la façade de référence existe")
	var intruder: Dictionary = facade.duplicate(true)
	intruder["id"] = "manual_facade_in_lane"
	intruder["properties"] = {}
	(intruder["position"] as Array)[0] = float((facade["position"] as Array)[0]) + 1.0
	var existing: Array[Dictionary] = [intruder]
	var generator: MedinaGenerator = _generate(_with_seed(1348), _description, _overrides, existing)
	assert_false(generator.is_valid())
	assert_true(_errors_contain(generator, "empiète sur une voie"), "; ".join(generator.errors))


func test_unreachable_door_and_out_of_bounds_instance_are_rejected() -> void:
	var reference: MedinaGenerator = _generate(_with_seed(1348), _description)
	var door: Dictionary = _first_with_layer(reference, MedinaBuilder.LAYER_DOOR).duplicate(true)
	door["id"] = "manual_door_backwards"
	door["rotation_y"] = float(door["rotation_y"]) + PI
	door["properties"] = {}
	var far := {
		"id": "manual_jar_far",
		"prefab_id": "clay_jar",
		"cell": [3, 0],
		"position": [200.0, 0.0, 0.0],
		"rotation_y": 0.0,
		"scale": [1.0, 1.0, 1.0],
		"layer": "prop",
		"properties": {}
	}
	var existing: Array[Dictionary] = [door, far]
	var generator: MedinaGenerator = _generate(_with_seed(1348), _description, _overrides, existing)
	assert_false(generator.is_valid())
	assert_true(_errors_contain(generator, "manual_door_backwards inaccessible"), "; ".join(generator.errors))
	assert_true(_errors_contain(generator, "hors des cellules"), "; ".join(generator.errors))
	assert_true(_errors_contain(generator, "sort de l'enceinte"), "; ".join(generator.errors))
