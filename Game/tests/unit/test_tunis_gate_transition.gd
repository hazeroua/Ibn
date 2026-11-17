extends GutTest
## Porte de Tunis (#54) : on entre à pied, Barq attend dehors.
##
## Pires cas, sur le vrai contrôleur de Barq et les vraies collisions de la médina générée (toutes les
## cellules chargées, décalées à leur place dans le désert) :
## - galop maximal droit sur la porte, et en diagonale contre une pile de la porte : freinage progressif
##   (jamais plus brutal que la décélération déclarée), aucun point du corps de Barq dans l'enceinte ;
## - longer le rempart au galop : aucun mur invisible, Barq avance librement ;
## - descente demandée flanc gauche contre un mur : Barq reste stable, cavalier en selle, explication affichée ;
## - sifflet depuis le point de la rue le plus éloigné de la porte : Barq hennit et reste au point d'attache ;
## - vingt allers-retours (descente, entrée à pied, sortie, remontée) avec le streaming de la ville actif :
##   un seul Barq, ville alignée sur la porte.

const TRANSITION_PATH: String = "res://data/tunis/transition.json"
const LAYOUT_PATH: String = "res://data/tunis/generation/medina_layout.json"
const RIDE_FRAMES: int = 900
const PHYSICS_DT: float = 1.0 / 60.0
const CYCLES: int = 20

var _config: Dictionary = {}
var _layout: Dictionary = {}


func before_all() -> void:
	_config = JsonData.load_dictionary(TRANSITION_PATH)
	_layout = JsonData.load_dictionary(LAYOUT_PATH)


## Monde de test sur le vrai relief du désert (raccord compris) : Barq marche sur la heightfield et ses appels
## suivent la grille de chemins ; un sol plat couvre l'esplanade aplanie de la ville pour le joueur.
func _desert_world() -> Dictionary:
	var world := Node3D.new()
	add_child_autofree(world)
	var field: DesertHeightfield = DesertHeightfield.from_data(JsonData.load_dictionary(DesertHeightfield.DEFAULT_PATH))
	assert_true(field.configure_city_transition(_config))
	var player := PlayerCharacter.new()
	world.add_child(player)
	var mount := HorseMountSystem.new()
	world.add_child(mount)
	mount.setup(player, null, field)
	var gate := TunisGateTransition.new()
	world.add_child(gate)
	assert_true(gate.configure(_config, player, mount, null))
	var terrain: Dictionary = _config["terrain"]
	var half := Vector2(float(terrain["half_extent_x_m"]), float(terrain["half_extent_z_m"]))
	PlayerTestWorld.box(world, Vector3(half.x * 2.0, 1.0, half.y * 2.0), gate.global_position + Vector3(0.0, -0.5, 0.0))
	var provider: TunisWorldProvider = TunisWorldProvider.with_offset(TunisCellProvider.create(), gate.global_position)
	var side: int = int(sqrt(float(provider.cell_count())))
	for x: int in side:
		for z: int in side:
			world.add_child(provider.build_cell(Vector2i(x, z)))
	return {"world": world, "player": player, "mount": mount, "gate": gate, "field": field}


func _inside_keep_out(gate: TunisGateTransition, position: Vector3) -> bool:
	return gate.keep_out_rect().has_point(Vector2(position.x - gate.global_position.x, position.z - gate.global_position.z))


## Monde de test : sol plat sous la ville, joueur, Barq (système de monte réel), raccord et ville complète.
func _world(with_city_cells: bool) -> Dictionary:
	var world := Node3D.new()
	add_child_autofree(world)
	var player := PlayerCharacter.new()
	world.add_child(player)
	var mount := HorseMountSystem.new()
	world.add_child(mount)
	mount.setup(player, null, null)
	var city: TunisWorldRuntime = null if with_city_cells else TunisWorldRuntime.new()
	var gate := TunisGateTransition.new()
	world.add_child(gate)
	assert_true(gate.configure(_config, player, mount, city))
	var ground: StaticBody3D = PlayerTestWorld.ground(world, "terre", 400.0)
	ground.position = Vector3(gate.global_position.x, -0.5, gate.global_position.z)
	var provider: TunisWorldProvider = TunisWorldProvider.with_offset(TunisCellProvider.create(), gate.global_position)
	if with_city_cells:
		var side: int = int(sqrt(float(provider.cell_count())))
		for x: int in side:
			for z: int in side:
				world.add_child(provider.build_cell(Vector2i(x, z)))
	else:
		city.prepare(provider)
		gate.add_child(city)
	return {"world": world, "player": player, "mount": mount, "gate": gate, "city": city}


func _horse_body() -> Vector2:
	var settings: Dictionary = JsonData.load_dictionary("res://data/horse/horse.json")
	var body: Dictionary = settings["body"]
	return Vector2(float(body["torso_length_m"]) / 2.0 + float(body["torso_radius_m"]), float(body["torso_radius_m"]))


## Plus petite distance (m) entre le corps de Barq (avant, arrière et flancs) et l'enceinte ; négative si dedans.
func _body_clearance(gate: TunisGateTransition, horse: HorseController) -> float:
	var reach: Vector2 = _horse_body()
	var forward := Vector3(-sin(horse.rotation.y), 0.0, -cos(horse.rotation.y))
	var right := Vector3(-forward.z, 0.0, forward.x)
	var enclosure: Array = _layout["enclosure"]
	var rect := Rect2(
		Vector2(float(enclosure[0]), float(enclosure[1])),
		Vector2(float(enclosure[2]) - float(enclosure[0]), float(enclosure[3]) - float(enclosure[1]))
	)
	var worst: float = INF
	for offset: Vector3 in [
		forward * reach.x,
		-forward * reach.x,
		right * reach.y,
		-right * reach.y,
		forward * reach.x + right * reach.y,
		forward * reach.x - right * reach.y
	]:
		var point: Vector3 = horse.global_position + offset - gate.global_position
		var local := Vector2(point.x, point.z)
		var dx: float = maxf(rect.position.x - local.x, local.x - rect.end.x)
		var dz: float = maxf(rect.position.y - local.y, local.y - rect.end.y)
		worst = minf(worst, maxf(dx, dz))
	return worst


## Lance Barq au galop maximal vers « target » et vérifie freinage et absence de pénétration.
func _gallop_at(scene: Dictionary, target: Vector3, start: Vector3) -> void:
	var gate: TunisGateTransition = scene["gate"]
	var mount: HorseMountSystem = scene["mount"]
	var horse: HorseController = mount.horse
	var direction: Vector3 = (target - start).normalized()
	horse.global_position = start
	horse.locomotion.yaw = atan2(-direction.x, -direction.z)
	horse.rotation.y = horse.locomotion.yaw
	horse.locomotion.speed = TunisGateTransition._gait_speed(horse, "sprint")
	await get_tree().physics_frame
	var brake: float = float((_config["horse"] as Dictionary)["brake_deceleration_mps2"])
	var stop_before: float = float((_config["horse"] as Dictionary)["stop_before_wall_m"])
	var previous: float = horse.locomotion.speed
	var worst_drop: float = 0.0
	var worst_clearance: float = INF
	for frame: int in RIDE_FRAMES:
		horse.set_input(Vector2(direction.x, direction.z), true)
		await get_tree().physics_frame
		# Sous 1 m/s, la dernière image d'arrêt n'a plus d'effet perceptible.
		if previous > 1.0:
			worst_drop = maxf(worst_drop, previous - horse.locomotion.speed)
		previous = horse.locomotion.speed
		worst_clearance = minf(worst_clearance, _body_clearance(gate, horse))
	horse.set_input(Vector2.ZERO, false)
	gut.p(
		(
			"Galop vers %s : freinage max %.3f m/s par image, plus petit écart corps-enceinte %.2f m, vitesse finale %.2f m/s."
			% [target, worst_drop, worst_clearance, horse.locomotion.speed]
		)
	)
	assert_gt(worst_clearance, 0.0, "aucun point du corps de Barq dans l'enceinte")
	assert_lt(worst_drop, brake * PHYSICS_DT * 1.5 + 0.02, "freinage progressif, jamais d'arrêt brutal")
	assert_lt(horse.locomotion.speed, 0.2, "Barq finit arrêté devant le mur")
	assert_lt(worst_clearance, stop_before + 1.0, "il s'arrête près de la marge prévue, pas loin avant")
	assert_false(horse.is_airborne())


func test_city_ground_is_level_blends_into_desert_and_has_a_road() -> void:
	var desert: Dictionary = JsonData.load_dictionary(DesertHeightfield.DEFAULT_PATH)
	var field: DesertHeightfield = DesertHeightfield.from_data(desert)
	assert_not_null(field)
	assert_true(field.configure_city_transition(_config))
	var origin: Array = _config["world_origin_xz_m"]
	var x: float = float(origin[0])
	var z: float = float(origin[1])
	var level: float = field.height_at(x, z)
	var enclosure: Array = _layout["enclosure"]
	for corner: Vector2 in [
		Vector2(enclosure[0], enclosure[1]),
		Vector2(enclosure[2], enclosure[3]),
		Vector2(enclosure[0], enclosure[3]),
		Vector2(enclosure[2], enclosure[1])
	]:
		assert_almost_eq(field.height_at(x + corner.x, z + corner.y), level, 0.01, "la ville est de niveau jusqu'aux remparts")
	var terrain: Dictionary = _config["terrain"]
	var far_x: float = x + float(terrain["half_extent_x_m"]) + float(terrain["blend_width_m"]) + 10.0
	var original: DesertHeightfield = DesertHeightfield.from_data(desert)
	assert_almost_eq(field.height_at(far_x, z), original.height_at(far_x, z), 0.01, "le désert lointain n'est pas modifié")
	var minimum_normal_y: float = 1.0
	var side_x: float = float(terrain["half_extent_x_m"]) + float(terrain["blend_width_m"])
	var side_z: float = float(terrain["half_extent_z_m"]) + float(terrain["blend_width_m"])
	for ix: int in ceili(2.0 * side_x / field.normal_epsilon) + 1:
		for iz: int in ceili(2.0 * side_z / field.normal_epsilon) + 1:
			minimum_normal_y = minf(
				minimum_normal_y,
				field.normal_at(x - side_x + float(ix) * field.normal_epsilon, z - side_z + float(iz) * field.normal_epsilon).y
			)
	gut.p("Raccord : pente maximale %.1f°." % rad_to_deg(acos(minimum_normal_y)))
	assert_gte(minimum_normal_y, cos(deg_to_rad(float(terrain["max_grade_degrees"]))))
	var gate: Dictionary = _layout["gate"]
	var gate_point := Vector2(x + float(gate["position"][0]), z + float(gate["position"][1]))
	var outward := -Vector2(float(gate["inward"][0]), float(gate["inward"][1]))
	var lateral := Vector2(-outward.y, outward.x)
	var road: Dictionary = _config["road"]
	# Au-delà de la zone de raccord de la ville, pour isoler la piste.
	var beyond: float = float(terrain["half_extent_z_m"]) + float(terrain["blend_width_m"]) + 20.0
	var on_road: Vector2 = gate_point + outward * beyond
	var off_road: Vector2 = on_road + lateral * (float(road["half_width_m"]) + float(road["edge_m"]) + 6.0)
	assert_gt(field.surface_mix(on_road.x, on_road.y, 0.0).y, 0.99, "piste de terre devant la porte")
	assert_almost_eq(
		field.surface_mix(off_road.x, off_road.y, 0.0).y,
		original.surface_mix(off_road.x, off_road.y, 0.0).y,
		0.001,
		"le sable reprend à côté de la piste"
	)


func test_sprint_straight_at_the_gate_brakes_without_crossing() -> void:
	var scene: Dictionary = _world(true)
	var gate: TunisGateTransition = scene["gate"]
	var target: Vector3 = gate.gate_world_position()
	await _gallop_at(scene, target, target - gate.inward_direction() * 70.0)


func test_diagonal_charge_at_a_gate_pillar_brakes_without_crossing() -> void:
	var scene: Dictionary = _world(true)
	var gate: TunisGateTransition = scene["gate"]
	var pillar: float = float(
		JsonData.load_dictionary("res://data/tunis/generation/medina.json")["prefab_metrics"]["city_gate"]["pillar_outer_m"]
	)
	var lateral: Vector3 = gate.inward_direction().cross(Vector3.UP)
	var target: Vector3 = gate.gate_world_position() + lateral * pillar
	await _gallop_at(scene, target, target - gate.inward_direction() * 45.0 - lateral * 45.0)


func test_riding_along_the_rampart_is_free() -> void:
	var scene: Dictionary = _world(true)
	var gate: TunisGateTransition = scene["gate"]
	var horse: HorseController = (scene["mount"] as HorseMountSystem).horse
	var lateral: Vector3 = gate.inward_direction().cross(Vector3.UP)
	var stop_before: float = float((_config["horse"] as Dictionary)["stop_before_wall_m"])
	var start: Vector3 = gate.gate_world_position() - gate.inward_direction() * (stop_before + 3.0) - lateral * 30.0
	horse.global_position = start
	horse.locomotion.yaw = atan2(-lateral.x, -lateral.z)
	horse.rotation.y = horse.locomotion.yaw
	await get_tree().physics_frame
	for frame: int in 300:
		horse.set_input(Vector2(lateral.x, lateral.z), true)
		await get_tree().physics_frame
	horse.set_input(Vector2.ZERO, false)
	var travelled: float = (horse.global_position - start).dot(lateral)
	gut.p("Le long du rempart : %.1f m parcourus en 5 s." % travelled)
	assert_gt(travelled, 35.0, "Barq longe le rempart au galop sans mur invisible")


func test_dismount_against_a_wall_is_refused_with_an_explanation() -> void:
	var scene: Dictionary = _world(true)
	var gate: TunisGateTransition = scene["gate"]
	var mount: HorseMountSystem = scene["mount"]
	var player: PlayerCharacter = scene["player"]
	var horse: HorseController = mount.horse
	horse.global_position = gate.gate_world_position() - gate.inward_direction() * 9.0
	horse.locomotion.yaw = atan2(-gate.inward_direction().x, -gate.inward_direction().z)
	horse.rotation.y = horse.locomotion.yaw
	await get_tree().physics_frame
	player.teleport_to(mount._mount_point().origin)
	mount.mount()
	var left: Vector3 = -horse.global_basis.x
	PlayerTestWorld.box(
		scene["world"], Vector3(0.6, 3.0, 4.0), horse.global_position + left * 1.2 + Vector3.UP * 1.5, Vector3(0.0, horse.rotation.y, 0.0)
	)
	await get_tree().physics_frame
	mount._dismount_requested = true
	for frame: int in 30:
		await get_tree().physics_frame
	assert_true(mount.is_riding(), "le cavalier reste en selle")
	assert_eq(gate.current_hint(), String((_config["messages"] as Dictionary)["dismount_blocked"]), "l'explication est affichée")
	assert_lt(horse.velocity.length(), 0.05, "Barq reste immobile et stable")
	assert_false(horse.is_airborne())


func test_whistle_from_the_far_end_of_the_street_keeps_barq_at_the_gate() -> void:
	var scene: Dictionary = _world(true)
	var gate: TunisGateTransition = scene["gate"]
	var mount: HorseMountSystem = scene["mount"]
	var player: PlayerCharacter = scene["player"]
	var original: HorseController = mount.horse
	original.global_position = gate.hitch_world_position()
	var farthest := Vector3.ZERO
	var best: float = -1.0
	for node: Variant in (_layout["graph"] as Dictionary)["nodes"]:
		var position: Array = (node as Dictionary)["position"]
		var world_point: Vector3 = gate.global_position + Vector3(float(position[0]), 0.0, float(position[1]))
		if String((node as Dictionary)["id"]) != "plaza" and world_point.distance_to(gate.gate_world_position()) > best:
			best = world_point.distance_to(gate.gate_world_position())
			farthest = world_point
	player.teleport_to(farthest)
	await get_tree().physics_frame
	assert_true(gate.is_city_side(player.global_position))
	original.call_to_node(player)
	var answered: bool = gate.current_hint() == String((_config["messages"] as Dictionary)["whistle_inside"])
	for frame: int in 240:
		await get_tree().physics_frame
		assert_true(
			(
				gate.keep_out_rect().has_point(
					Vector2(original.global_position.x - gate.global_position.x, original.global_position.z - gate.global_position.z)
				)
				== false
			),
			"Barq n'entre jamais dans la ville"
		)
	gut.p(
		(
			"Sifflet depuis %.0f m de la porte : Barq à %.1f m du point d'attache."
			% [best, original.global_position.distance_to(gate.hitch_world_position())]
		)
	)
	assert_same(mount.horse, original)
	assert_false(original.is_called and original.called_target.distance_to(player.global_position) < 1.0, "il ne vient pas vers le joueur")
	assert_lt(
		original.global_position.distance_to(gate.hitch_world_position()),
		float((_config["horse"] as Dictionary)["hitch_arrival_radius_m"]) + 0.5
	)
	assert_true(answered, "Barq répond depuis la porte (hennissement et indication)")


func test_dismounting_near_the_gate_sends_barq_to_the_hitch_and_he_can_be_mounted_again() -> void:
	var scene: Dictionary = _world(true)
	var gate: TunisGateTransition = scene["gate"]
	var mount: HorseMountSystem = scene["mount"]
	var player: PlayerCharacter = scene["player"]
	var horse: HorseController = mount.horse
	horse.global_position = gate.gate_world_position() - gate.inward_direction() * 10.0 + gate.inward_direction().cross(Vector3.UP) * 4.0
	await get_tree().physics_frame
	player.teleport_to(mount._mount_point().origin)
	mount.mount()
	await get_tree().physics_frame
	mount.dismount()
	var radius: float = float((_config["horse"] as Dictionary)["hitch_arrival_radius_m"])
	for frame: int in 900:
		await get_tree().physics_frame
		if horse.global_position.distance_to(gate.hitch_world_position()) < radius and not horse.is_called:
			break
	gut.p("Barq au point d'attache : %.2f m." % horse.global_position.distance_to(gate.hitch_world_position()))
	assert_lt(horse.global_position.distance_to(gate.hitch_world_position()), radius + 0.5, "Barq attend au point d'attache")
	player.teleport_to(mount._mount_point().origin)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_true(mount.can_mount(), "on retrouve Barq et on peut remonter")


func test_twenty_round_trips_with_streaming_keep_one_barq_and_an_aligned_city() -> void:
	var scene: Dictionary = _world(false)
	var gate: TunisGateTransition = scene["gate"]
	var mount: HorseMountSystem = scene["mount"]
	var player: PlayerCharacter = scene["player"]
	var city: TunisWorldRuntime = scene["city"]
	var original: HorseController = mount.horse
	original.global_position = gate.hitch_world_position()
	var plaza: Array = (_layout["plaza"] as Dictionary)["fountain"]
	var deep: Vector3 = gate.global_position + Vector3(float(plaza[0]) + 4.0, 0.0, float(plaza[1]))
	var worst_ms: float = 0.0
	for cycle: int in CYCLES:
		player.teleport_to(mount._mount_point().origin)
		mount.mount()
		assert_true(mount.is_riding())
		mount.dismount()
		player.teleport_to(deep)
		for frame: int in 6:
			var started: int = Time.get_ticks_usec()
			await get_tree().physics_frame
			worst_ms = maxf(worst_ms, float(Time.get_ticks_usec() - started) / 1000.0)
		player.teleport_to(gate.hitch_world_position() + Vector3(3.0, 0.0, 3.0))
		for frame: int in 6:
			await get_tree().physics_frame
		assert_same(mount.horse, original)
		assert_eq(get_tree().get_nodes_in_group(&"horse").size(), 1, "un seul Barq après le cycle %d" % cycle)
		assert_false(_inside_keep_out(gate, original.global_position), "Barq reste hors de la ville au cycle %d" % cycle)
	# Hors de portée de vue, la ville se décharge ; au retour elle se recharge au même endroit, Barq inchangé.
	var view: float = float(_config["view_distance_m"])
	player.teleport_to(gate.gate_world_position() - gate.inward_direction() * (view + 400.0))
	for frame: int in 240:
		await get_tree().physics_frame
		if city.loaded_cell_count() == 0:
			break
	assert_eq(city.loaded_cell_count(), 0, "la ville se décharge au-delà de la portée de vue")
	assert_same(mount.horse, original)
	player.teleport_to(gate.gate_world_position())
	for frame: int in 240:
		await get_tree().physics_frame
		if city.get_instance_by_id(&"city_gate") != null:
			break
	var gate_instance: Node3D = city.get_instance_by_id(&"city_gate")
	assert_not_null(gate_instance, "la porte est chargée par le streaming")
	if gate_instance != null:
		assert_almost_eq(gate_instance.global_position.x, gate.gate_world_position().x, 0.01)
		assert_almost_eq(gate_instance.global_position.z, gate.gate_world_position().z, 0.01)
	gut.p("Vingt allers-retours : image la plus longue %.1f ms (streaming de la ville actif)." % worst_ms)
	city.force_all_cells_loaded(false)
	city._streamer.clear()


func test_turning_toward_the_wall_at_gallop_brakes_progressively() -> void:
	var scene: Dictionary = _world(true)
	var gate: TunisGateTransition = scene["gate"]
	var horse: HorseController = (scene["mount"] as HorseMountSystem).horse
	var lateral: Vector3 = gate.inward_direction().cross(Vector3.UP)
	var stop_before: float = float((_config["horse"] as Dictionary)["stop_before_wall_m"])
	var brake: float = float((_config["horse"] as Dictionary)["brake_deceleration_mps2"])
	# Au galop le long du rempart, 2 m hors de la zone interdite, puis virage franc vers le mur.
	horse.global_position = gate.gate_world_position() - gate.inward_direction() * (stop_before + 2.0) - lateral * 30.0
	horse.locomotion.yaw = atan2(-lateral.x, -lateral.z)
	horse.rotation.y = horse.locomotion.yaw
	horse.locomotion.speed = TunisGateTransition._gait_speed(horse, "sprint")
	await get_tree().physics_frame
	var previous: float = horse.locomotion.speed
	var worst_drop: float = 0.0
	var worst_clearance: float = INF
	for frame: int in 300:
		var toward: Vector3 = lateral if frame < 20 else gate.inward_direction()
		horse.set_input(Vector2(toward.x, toward.z), true)
		await get_tree().physics_frame
		if previous > 1.0:
			worst_drop = maxf(worst_drop, previous - horse.locomotion.speed)
		previous = horse.locomotion.speed
		worst_clearance = minf(worst_clearance, _body_clearance(gate, horse))
	horse.set_input(Vector2.ZERO, false)
	gut.p("Virage vers le mur au galop : freinage max %.3f m/s par image, écart corps-enceinte %.2f m." % [worst_drop, worst_clearance])
	assert_lt(worst_drop, brake * PHYSICS_DT * 1.5 + 0.02, "pas d'arrêt brutal quand Barq tourne vers le mur")
	assert_gt(worst_clearance, 0.0, "aucun point du corps de Barq dans l'enceinte")


func test_jump_is_refused_near_the_walls_and_allowed_away() -> void:
	var scene: Dictionary = _world(true)
	var gate: TunisGateTransition = scene["gate"]
	var horse: HorseController = (scene["mount"] as HorseMountSystem).horse
	var lateral: Vector3 = gate.inward_direction().cross(Vector3.UP)
	var no_jump: float = float((_config["horse"] as Dictionary)["no_jump_m"])
	for distance: float in [no_jump * 0.5, no_jump + 30.0]:
		horse.global_position = gate.gate_world_position() - gate.inward_direction() * distance - lateral * 20.0
		horse.locomotion.yaw = atan2(-lateral.x, -lateral.z)
		horse.rotation.y = horse.locomotion.yaw
		horse.locomotion.speed = TunisGateTransition._gait_speed(horse, "canter")
		for frame: int in 20:
			horse.set_input(Vector2(lateral.x, lateral.z) * 0.8, false)
			await get_tree().physics_frame
		var jumped: bool = horse.request_jump()
		if distance < no_jump:
			assert_false(jumped, "pas de saut à %.0f m du rempart" % distance)
		else:
			assert_true(jumped, "saut permis à %.0f m du rempart" % distance)
		for frame: int in 90:
			horse.set_input(Vector2.ZERO, false)
			await get_tree().physics_frame


func test_barq_behind_the_city_walks_around_it_to_the_hitch() -> void:
	var scene: Dictionary = _desert_world()
	var gate: TunisGateTransition = scene["gate"]
	var mount: HorseMountSystem = scene["mount"]
	var player: PlayerCharacter = scene["player"]
	var horse: HorseController = mount.horse
	var field: DesertHeightfield = scene["field"]
	var behind: Vector3 = gate.global_position + gate.inward_direction() * 75.0
	horse.global_position = Vector3(behind.x, field.height_at(behind.x, behind.z), behind.z)
	for frame: int in 1200:
		await get_tree().physics_frame
		if horse.is_path_grid_ready():
			break
	assert_true(horse.is_path_grid_ready(), "grille des chemins prête")
	var plaza: Array = (_layout["plaza"] as Dictionary)["fountain"]
	player.teleport_to(gate.global_position + Vector3(float(plaza[0]) + 4.0, 0.0, float(plaza[1])))
	await get_tree().physics_frame
	horse.call_to_node(player)
	var entered: bool = false
	var radius: float = float((_config["horse"] as Dictionary)["hitch_arrival_radius_m"])
	var frames: int = 0
	for frame: int in 4800:
		await get_tree().physics_frame
		frames = frame
		entered = entered or _inside_keep_out(gate, horse.global_position)
		if not horse.is_called and horse.global_position.distance_to(gate.hitch_world_position()) < radius + 0.5:
			break
	gut.p(
		(
			"Barq derrière la ville : au point d'attache en %.1f s (%.1f m)."
			% [float(frames) / 60.0, horse.global_position.distance_to(gate.hitch_world_position())]
		)
	)
	assert_false(entered, "Barq contourne la ville sans entrer dans la zone interdite")
	assert_lt(horse.global_position.distance_to(gate.hitch_world_position()), radius + 0.5, "Barq rejoint le point d'attache")
	assert_false(horse.is_called, "l'appel se termine")
