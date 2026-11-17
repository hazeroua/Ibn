extends GutTest
## Les mesures des modules utilisées par le générateur de médina (medina.json, « prefab_metrics »)
## correspondent aux maillages et aux collisions réels du kit : lancers de rayons à travers les
## ouvertures de la porte, des arcs et du passage couvert, et volumes englobants des autres modules.

const DESCRIPTION_PATH: String = "res://data/tunis/generation/medina.json"
const CATALOG_PATH: String = "res://data/tunis/catalog.json"
const PROBE_MARGIN_M: float = 0.05
const LOW_PROBE_M: float = 0.3
const RAY_REACH_M: float = 30.0
const SIZE_TOLERANCE_M: float = 0.002

var _metrics: Dictionary = {}
var _world: Node3D = null


func before_all() -> void:
	_metrics = JsonData.get_dictionary(JsonData.load_dictionary(DESCRIPTION_PATH), "prefab_metrics", "medina")


func before_each() -> void:
	_world = Node3D.new()
	add_child_autofree(_world)


func _place(prefab_id: String) -> void:
	var scene: PackedScene = load("res://assets/tunis/%s.glb" % prefab_id) as PackedScene
	_world.add_child(scene.instantiate())
	await get_tree().physics_frame
	await get_tree().physics_frame


## Vrai si un rayon parallèle à Z, à l'abscisse x et à la hauteur y, traverse le module sans le toucher.
func _passes(x: float, y: float) -> bool:
	var space: PhysicsDirectSpaceState3D = _world.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(Vector3(x, y, -RAY_REACH_M), Vector3(x, y, RAY_REACH_M))
	query.hit_back_faces = true
	return space.intersect_ray(query).is_empty()


func _check_opening(prefab_id: String) -> void:
	await _place(prefab_id)
	var metric: Dictionary = _metrics[prefab_id]
	var opening: float = float(metric["opening_half_width_m"])
	var pillar: float = float(metric["pillar_outer_m"])
	var clear: float = float(metric["clear_height_m"])
	for side: float in [-1.0, 1.0]:
		assert_true(_passes(side * (opening - PROBE_MARGIN_M), LOW_PROBE_M), "%s : ouverture libre au sol" % prefab_id)
		assert_true(_passes(side * (opening - PROBE_MARGIN_M), clear - PROBE_MARGIN_M), "%s : ouverture libre sous le linteau" % prefab_id)
		assert_false(_passes(side * (opening + PROBE_MARGIN_M), LOW_PROBE_M), "%s : pile au bord de l'ouverture" % prefab_id)
		assert_false(_passes(side * (pillar - PROBE_MARGIN_M), LOW_PROBE_M), "%s : pile jusqu'à son bord extérieur" % prefab_id)
		assert_true(_passes(side * (pillar + PROBE_MARGIN_M), LOW_PROBE_M), "%s : rien au sol au-delà de la pile" % prefab_id)
	assert_true(_passes(0.0, clear - PROBE_MARGIN_M), "%s : hauteur libre" % prefab_id)
	assert_false(_passes(0.0, clear + PROBE_MARGIN_M), "%s : linteau au-dessus de la hauteur libre" % prefab_id)


func test_gate_opening() -> void:
	await _check_opening("city_gate")


func test_arch_opening() -> void:
	await _check_opening("medina_arch")


func test_covered_passage_opening() -> void:
	await _check_opening("covered_passage")


func test_bounds_match_metrics() -> void:
	var prefabs: Dictionary = MedinaChecks.measure_prefabs(JsonData.load_dictionary(CATALOG_PATH))
	var expectations: Array = [
		["rampart_straight", "length_m", "x"],
		["rampart_straight", "thickness_m", "z"],
		["rampart_straight", "height_m", "y"],
		["city_gate", "depth_m", "z"],
		["medina_arch", "width_m", "x"],
		["medina_arch", "height_m", "y"],
		["covered_passage", "width_m", "x"],
		["covered_passage", "height_m", "y"],
		["covered_passage", "roof_length_m", "z"],
		["wooden_door", "width_m", "x"],
		["wooden_door", "depth_m", "z"],
		["terrace_parapet", "length_m", "x"],
		["terrace_parapet", "depth_m", "z"],
		["market_stall", "width_m", "x"],
		["market_stall", "depth_m", "z"],
		["facade_house", "height_m", "y"],
		["facade_shop", "height_m", "y"]
	]
	for expectation: Array in expectations:
		var info: MedinaChecks.PrefabInfo = prefabs[expectation[0]]
		var size: Vector3 = info.bounds.size
		var measured: float = size.x if expectation[2] == "x" else size.y if expectation[2] == "y" else size.z
		var expected: float = float((_metrics[expectation[0]] as Dictionary)[expectation[1]])
		assert_almost_eq(measured, expected, SIZE_TOLERANCE_M, "%s.%s" % [expectation[0], expectation[1]])
	var fountain: MedinaChecks.PrefabInfo = prefabs["plaza_fountain"]
	assert_almost_eq(fountain.bounds.size.x / 2.0, float((_metrics["plaza_fountain"] as Dictionary)["radius_m"]), SIZE_TOLERANCE_M)
	var corner: MedinaChecks.PrefabInfo = prefabs["rampart_corner"]
	var arm: float = float((_metrics["rampart_corner"] as Dictionary)["arm_m"])
	assert_almost_eq(corner.bounds.end.x, arm, SIZE_TOLERANCE_M, "bras est de la tour d'angle")
	assert_almost_eq(-corner.bounds.position.z, arm, SIZE_TOLERANCE_M, "bras nord de la tour d'angle")
	for prefab_id: String in prefabs:
		var measured_prefab: MedinaChecks.PrefabInfo = prefabs[prefab_id]
		assert_almost_eq(measured_prefab.bounds.position.y, 0.0, SIZE_TOLERANCE_M, "%s : origine au sol" % prefab_id)
		assert_gt(measured_prefab.collision_shapes, 0, "%s : le module a une collision" % prefab_id)
