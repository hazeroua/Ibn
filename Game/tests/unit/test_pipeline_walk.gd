extends GutTest
## Pipeline : parcours du joueur piloté par les actions d'entrée (PlayerRoute, PlayerRouteDriver).
##
## Le personnage du jeu est fourni par un autre ticket : ces tests utilisent une doublure
## (CharacterBody3D du groupe « player » qui se déplace selon les actions move_* relatives à la caméra
## active) et déclarent eux-mêmes les actions dont ils ont besoin.
##
## Pires cas couverts : parcours de 10 minutes (36 000 pas de physique, mémoire des mesures réservée
## pour 900 s à 2 000 i/s), joueur bloqué contre un mur, joueur absent, en double ou disparu, caméra
## verticale ou tournant avec le joueur, durée maximale dépassée, données invalides.

const ROUTE_PATH: String = "res://tests/data/route_joueur_test.json"
const DRIVEN_ACTIONS: Array[StringName] = [&"move_forward", &"move_back", &"move_left", &"move_right", &"sprint", &"walk_slow"]
const MAX_WAIT_MSEC: int = 20000
const PHYSICS_DT: float = 1.0 / 60.0

var _added_actions: Array[StringName] = []


## Doublure du personnage : contrat du MVP 1 (groupe « player », déplacement relatif à la caméra active).
class PlayerDouble:
	extends CharacterBody3D

	const GRAVITY: float = 9.8
	const WALK_SLOW_SPEED: float = 1.5
	const WALK_SPEED: float = 3.0
	const RUN_SPEED: float = 6.0
	const TURN_RATE: float = 6.0

	var turns_with_movement: bool = false
	var seen_walk_slow: bool = false
	var seen_walk: bool = false
	var seen_run: bool = false

	## Direction horizontale demandée par les actions move_*, relative à la caméra (comme le contrat du joueur).
	static func input_direction(camera: Camera3D) -> Vector3:
		var stick: Vector2 = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
		if camera == null or stick.length_squared() < 0.000001:
			return Vector3.ZERO
		var basis: Basis = camera.global_basis
		var forward := Vector3(-basis.z.x, 0.0, -basis.z.z)
		if forward.length_squared() < 0.000001:
			forward = Vector3(basis.y.x, 0.0, basis.y.z)
		forward = forward.normalized()
		var right := Vector3(-forward.z, 0.0, forward.x)
		var direction: Vector3 = right * stick.x - forward * stick.y
		return direction.normalized() if direction.length_squared() > 1.0 else direction

	static func gait_speed() -> float:
		if Input.is_action_pressed(&"sprint"):
			return RUN_SPEED
		if Input.is_action_pressed(&"walk_slow"):
			return WALK_SLOW_SPEED
		return WALK_SPEED

	func _physics_process(delta: float) -> void:
		var direction: Vector3 = PlayerDouble.input_direction(get_viewport().get_camera_3d())
		var speed: float = PlayerDouble.gait_speed()
		if direction.length_squared() > 0.0:
			seen_run = seen_run or speed == RUN_SPEED
			seen_walk_slow = seen_walk_slow or speed == WALK_SLOW_SPEED
			seen_walk = seen_walk or speed == WALK_SPEED
		var vertical: float = 0.0 if is_on_floor() else velocity.y - GRAVITY * delta
		velocity = Vector3(direction.x * speed, vertical, direction.z * speed)
		move_and_slide()
		if turns_with_movement and direction.length_squared() > 0.01:
			rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), minf(1.0, TURN_RATE * delta))


func before_all() -> void:
	for action: StringName in DRIVEN_ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
			_added_actions.append(action)


func after_each() -> void:
	for node: Node in get_tree().get_nodes_in_group(PlayerRouteDriver.PLAYER_GROUP):
		node.remove_from_group(PlayerRouteDriver.PLAYER_GROUP)


func after_all() -> void:
	for action: StringName in _added_actions:
		Input.action_release(action)
		InputMap.erase_action(action)
	_added_actions.clear()


func _route_data(waypoints: Array, stall_time: float, max_duration: float) -> Dictionary:
	return {
		"description": "parcours de test",
		"start_position": [0.0, 0.05, 0.0],
		"arrival_radius_m": 0.3,
		"stall_time_s": stall_time,
		"stall_min_progress_m": 0.1,
		"max_duration_s": max_duration,
		"waypoints": waypoints,
	}


func _make_route(data: Dictionary) -> PlayerRoute:
	var route := PlayerRoute.new()
	var problems: PackedStringArray = route.parse(data, "test")
	assert_eq(problems.size(), 0, "parcours de test valide : %s" % ", ".join(problems))
	return route


## Sol de 60 m de côté (couche 1), et un mur perpendiculaire à l'axe x (face à x = 1,8 m) si demandé.
func _build_world(with_wall: bool) -> Node3D:
	var world := Node3D.new()
	add_child_autofree(world)
	world.add_child(_static_box(Vector3(60.0, 1.0, 60.0), Vector3(0.0, -0.5, 0.0)))
	if with_wall:
		world.add_child(_static_box(Vector3(0.4, 3.0, 12.0), Vector3(2.0, 1.5, 0.0)))
	return world


func _static_box(size: Vector3, position: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = position
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	return body


func _add_player(world: Node3D, camera_attached: bool) -> PlayerDouble:
	var player := PlayerDouble.new()
	player.collision_layer = 2
	player.collision_mask = 1
	player.turns_with_movement = camera_attached
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.75
	shape.shape = capsule
	shape.position = Vector3(0.0, 0.875, 0.0)
	player.add_child(shape)
	player.add_to_group(PlayerRouteDriver.PLAYER_GROUP)
	world.add_child(player)
	var camera := Camera3D.new()
	if camera_attached:
		# Caméra accrochée derrière le joueur : elle tourne avec lui, comme une caméra à la troisième personne.
		player.add_child(camera)
		camera.position = Vector3(0.0, 2.5, 4.0)
		camera.rotation_degrees = Vector3(-25.0, 0.0, 0.0)
	else:
		# Caméra fixe en biais : les actions ne coïncident avec aucun axe du monde.
		world.add_child(camera)
		camera.position = Vector3(9.0, 7.0, -3.0)
		camera.look_at(Vector3(2.0, 0.0, 2.0), Vector3.UP)
	camera.make_current()
	return player


func _start_driver(route: PlayerRoute, player: Node3D, automatic: bool) -> PlayerRouteDriver:
	var driver := PlayerRouteDriver.new()
	add_child_autofree(driver)
	driver.setup(route, player)
	driver.place_at_start()
	driver.begin(automatic)
	return driver


func _wait_until_done(driver: PlayerRouteDriver) -> void:
	var deadline: int = Time.get_ticks_msec() + MAX_WAIT_MSEC
	while driver.is_running() and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame


func _assert_actions_released() -> void:
	for action: StringName in DRIVEN_ACTIONS:
		assert_false(Input.is_action_pressed(action), "l'action %s doit être relâchée" % action)
		assert_eq(Input.get_action_strength(action), 0.0, "intensité de %s" % action)


func test_absent_duplicate_or_invalid_player_is_reported() -> void:
	assert_string_contains(PlayerRouteDriver.player_problem(get_tree()), "aucun joueur")
	assert_null(PlayerRouteDriver.find_player(get_tree()))
	var not_spatial := Node.new()
	not_spatial.add_to_group(PlayerRouteDriver.PLAYER_GROUP)
	add_child_autofree(not_spatial)
	assert_string_contains(PlayerRouteDriver.player_problem(get_tree()), "n'est pas un Node3D")
	var first := Node3D.new()
	first.add_to_group(PlayerRouteDriver.PLAYER_GROUP)
	add_child_autofree(first)
	assert_string_contains(PlayerRouteDriver.player_problem(get_tree()), "doit être unique")
	not_spatial.remove_from_group(PlayerRouteDriver.PLAYER_GROUP)
	assert_eq(PlayerRouteDriver.player_problem(get_tree()), "")
	assert_same(PlayerRouteDriver.find_player(get_tree()), first)


func test_route_file_is_valid() -> void:
	var route: PlayerRoute = PlayerRoute.load_file(ROUTE_PATH)
	assert_not_null(route)
	assert_eq(route.points.size(), 4)
	assert_eq(route.ids[1], "coin_sud_est")
	assert_eq(
		route.gaits, PackedInt32Array([PlayerRoute.Gait.WALK, PlayerRoute.Gait.RUN, PlayerRoute.Gait.WALK_SLOW, PlayerRoute.Gait.WALK])
	)
	assert_true(route.has_start)
	assert_almost_eq(route.get_length(), 16.0, 0.0001)


func test_invalid_routes_are_refused() -> void:
	var good: Array = [{"id": "a", "position": [1.0, 0.0], "gait": "walk"}]
	var cases: Array[Dictionary] = [
		{},
		_route_data([], 1.0, 10.0),
		_route_data([{"id": "a", "position": [1.0, 0.0], "gait": "trot"}], 1.0, 10.0),
		_route_data([{"id": "a", "position": [1.0, 0.0, 2.0], "gait": "walk"}], 1.0, 10.0),
		_route_data([{"id": "a", "position": [1.0, 0.0], "gait": "walk"}, {"id": "a", "position": [2.0, 0.0], "gait": "walk"}], 1.0, 10.0),
		_route_data([{"id": "a/b", "position": [1.0, 0.0], "gait": "walk"}], 1.0, 10.0),
		_route_data(good, 1.0, PlayerRoute.MAX_DURATION_S + 1.0),
		_route_data(good, 0.0, 10.0),
		_route_data(good, 1.0, 10.0).merged({"arrival_radius_m": "0.5"}, true),
		_route_data(good, 1.0, 10.0).merged({"start_position": [0.0, 1.0]}, true),
	]
	for i: int in cases.size():
		var route := PlayerRoute.new()
		assert_gt(route.parse(cases[i], "cas %d" % i).size(), 0, "le cas invalide n° %d doit être refusé" % i)
	assert_eq(PlayerRoute.new().parse(_route_data(good, 1.0, 10.0), "valide").size(), 0)


func test_required_actions_follow_gaits() -> void:
	var walk_only: PlayerRoute = _make_route(_route_data([{"id": "a", "position": [1.0, 0.0], "gait": "walk"}], 1.0, 10.0))
	assert_eq(PlayerRouteDriver.required_actions(walk_only).size(), 4, "marche seule : les quatre actions move_*")
	var route: PlayerRoute = PlayerRoute.load_file(ROUTE_PATH)
	var actions: Array[StringName] = PlayerRouteDriver.required_actions(route)
	assert_true(actions.has(&"sprint"))
	assert_true(actions.has(&"walk_slow"))
	assert_eq(PlayerRouteDriver.missing_actions(route).size(), 0)


func test_steering_is_relative_to_any_camera_orientation() -> void:
	# Caméra regardant à l'horizontale, en plongée ou à la verticale, dans toutes les directions.
	var player := Node3D.new()
	add_child_autofree(player)
	var camera := Camera3D.new()
	add_child_autofree(camera)
	camera.make_current()
	var targets: Array[Vector2] = [Vector2(10.0, 0.0), Vector2(-3.0, 7.0), Vector2(0.0, -5.0)]
	for pitch: float in [0.0, -35.0, -75.0, -90.0]:
		for yaw_step: int in 12:
			camera.rotation_degrees = Vector3(pitch, float(yaw_step) * 30.0 + 7.0, 0.0)
			for target: Vector2 in targets:
				var route: PlayerRoute = _make_route(
					_route_data([{"id": "cible", "position": [target.x, target.y], "gait": "walk"}], 1.0, 10.0)
				)
				var driver := PlayerRouteDriver.new()
				add_child(driver)
				driver.setup(route, player)
				driver.place_at_start()
				driver.begin(false)
				driver.tick(PHYSICS_DT)
				var direction: Vector3 = PlayerDouble.input_direction(camera)
				var expected: Vector3 = Vector3(target.x, 0.0, target.y).normalized()
				assert_almost_eq(direction.length(), 1.0, 0.001, "pleine inclinaison du stick")
				assert_gt(direction.dot(expected), 0.999, "tangage %.0f°, lacet %d" % [pitch, yaw_step * 30 + 7])
				remove_child(driver)
				driver.free()
				_assert_actions_released()


func test_route_is_followed_with_fixed_camera() -> void:
	var world: Node3D = _build_world(false)
	var player: PlayerDouble = _add_player(world, false)
	var route: PlayerRoute = PlayerRoute.load_file(ROUTE_PATH)
	var driver: PlayerRouteDriver = _start_driver(route, player, true)
	await _wait_until_done(driver)
	assert_eq(driver.get_status(), PlayerRouteDriver.Status.FINISHED, driver.get_failure_message())
	assert_eq(driver.get_reached_count(), 4)
	assert_lt(Vector2(player.global_position.x, player.global_position.z).length(), route.arrival_radius + 0.15)
	assert_true(player.seen_walk and player.seen_run and player.seen_walk_slow, "les trois allures doivent être demandées")
	assert_gt(driver.get_distance_walked(), 14.0)
	gut.p("Parcours de 16 m suivi en %.2f s (caméra fixe), %.2f m parcourus." % [driver.get_elapsed(), driver.get_distance_walked()])
	_assert_actions_released()


func test_route_is_followed_with_camera_turning_with_player() -> void:
	var world: Node3D = _build_world(false)
	var player: PlayerDouble = _add_player(world, true)
	var route: PlayerRoute = PlayerRoute.load_file(ROUTE_PATH)
	var driver: PlayerRouteDriver = _start_driver(route, player, true)
	await _wait_until_done(driver)
	assert_eq(driver.get_status(), PlayerRouteDriver.Status.FINISHED, driver.get_failure_message())
	assert_eq(driver.get_reached_count(), 4)
	gut.p("Parcours de 16 m suivi en %.2f s (caméra tournant avec le joueur)." % driver.get_elapsed())
	_assert_actions_released()


func test_blocked_player_is_detected_with_position() -> void:
	var world: Node3D = _build_world(true)
	var player: PlayerDouble = _add_player(world, false)
	var route: PlayerRoute = _make_route(_route_data([{"id": "derriere_le_mur", "position": [5.0, 0.0], "gait": "walk"}], 0.5, 30.0))
	var driver: PlayerRouteDriver = _start_driver(route, player, true)
	await _wait_until_done(driver)
	assert_eq(driver.get_status(), PlayerRouteDriver.Status.BLOCKED)
	assert_true(driver.has_failed())
	assert_lt(player.global_position.x, 1.8, "le mur arrête le joueur")
	var message: String = driver.get_failure_message()
	assert_string_contains(message, "bloqué")
	assert_string_contains(message, "position (")
	assert_string_contains(message, "derriere_le_mur")
	gut.p(message)
	_assert_actions_released()


func test_player_leaving_the_scene_fails_and_releases_actions() -> void:
	var camera := Camera3D.new()
	add_child_autofree(camera)
	camera.make_current()
	var player := Node3D.new()
	add_child(player)
	var route: PlayerRoute = _make_route(_route_data([{"id": "loin", "position": [50.0, 0.0], "gait": "run"}], 1.0, 30.0))
	var driver: PlayerRouteDriver = _start_driver(route, player, false)
	driver.tick(PHYSICS_DT)
	assert_true(driver.is_running())
	assert_true(Input.is_action_pressed(&"sprint"), "allure run : sprint maintenu")
	player.free()
	driver.tick(PHYSICS_DT)
	assert_eq(driver.get_status(), PlayerRouteDriver.Status.PLAYER_LOST)
	assert_string_contains(driver.get_failure_message(), "quitté la scène")
	_assert_actions_released()


func test_maximum_duration_fails_explicitly() -> void:
	var camera := Camera3D.new()
	add_child_autofree(camera)
	camera.make_current()
	var player := Node3D.new()
	add_child_autofree(player)
	var route: PlayerRoute = _make_route(_route_data([{"id": "loin", "position": [100.0, 0.0], "gait": "walk"}], 5.0, 0.5))
	var driver: PlayerRouteDriver = _start_driver(route, player, false)
	var ticks: int = 0
	while driver.is_running() and ticks < 1000:
		driver.tick(PHYSICS_DT)
		player.global_position += PlayerDouble.input_direction(camera) * PlayerDouble.WALK_SPEED * PHYSICS_DT
		ticks += 1
	assert_eq(driver.get_status(), PlayerRouteDriver.Status.TIMED_OUT)
	assert_between(driver.get_elapsed(), 0.5, 0.5 + 2.0 * PHYSICS_DT)
	_assert_actions_released()


func test_stop_releases_actions() -> void:
	var camera := Camera3D.new()
	add_child_autofree(camera)
	camera.make_current()
	var player := Node3D.new()
	add_child_autofree(player)
	var route: PlayerRoute = _make_route(_route_data([{"id": "loin", "position": [0.0, 30.0], "gait": "walk_slow"}], 1.0, 30.0))
	var driver: PlayerRouteDriver = _start_driver(route, player, false)
	driver.tick(PHYSICS_DT)
	assert_true(Input.is_action_pressed(&"walk_slow"))
	driver.stop()
	assert_eq(driver.get_status(), PlayerRouteDriver.Status.STOPPED)
	assert_false(driver.has_failed())
	_assert_actions_released()


func test_worst_case_ten_minute_route() -> void:
	# Pire cas : parcours de 10 minutes à 60 pas de physique par seconde (36 000 pas), 240 points de
	# passage dans toutes les directions et aux trois allures ; coût par pas, objets créés, et mémoire
	# des mesures réservée pour la durée maximale d'un parcours (900 s à 2 000 i/s).
	var camera := Camera3D.new()
	add_child_autofree(camera)
	camera.rotation_degrees = Vector3(-30.0, 37.0, 0.0)
	camera.make_current()
	var player := Node3D.new()
	add_child_autofree(player)
	var gait_names: Array[String] = ["walk_slow", "walk", "run"]
	var waypoints: Array = []
	for i: int in 240:
		var angle: float = float(i + 1) * PI / 4.0
		var gait: String = gait_names[i % 3]
		waypoints.append({"id": "p%d" % i, "position": [5.0 * cos(angle) - 5.0, 5.0 * sin(angle)], "gait": gait})
	var data: Dictionary = _route_data(waypoints, 2.0, PlayerRoute.MAX_DURATION_S)
	data.erase("start_position")
	var route: PlayerRoute = _make_route(data)
	var driver: PlayerRouteDriver = _start_driver(route, player, false)
	var speeds: Dictionary[int, float] = {}
	speeds[PlayerRoute.Gait.WALK_SLOW] = 0.8
	speeds[PlayerRoute.Gait.WALK] = 1.4
	speeds[PlayerRoute.Gait.RUN] = 4.0
	var objects_before: float = Performance.get_monitor(Performance.OBJECT_COUNT)
	var ticks: int = 0
	var driver_usec: int = 0
	var driver_max_usec: int = 0
	var start: int = Time.get_ticks_usec()
	while driver.is_running() and ticks < 60000:
		var before: int = Time.get_ticks_usec()
		driver.tick(PHYSICS_DT)
		var cost: int = Time.get_ticks_usec() - before
		driver_usec += cost
		driver_max_usec = maxi(driver_max_usec, cost)
		var speed: float = PlayerDouble.RUN_SPEED
		if Input.is_action_pressed(&"sprint"):
			speed = speeds[PlayerRoute.Gait.RUN]
		elif Input.is_action_pressed(&"walk_slow"):
			speed = speeds[PlayerRoute.Gait.WALK_SLOW]
		else:
			speed = speeds[PlayerRoute.Gait.WALK]
		player.global_position += PlayerDouble.input_direction(camera) * speed * PHYSICS_DT
		ticks += 1
	var total_ms: float = float(Time.get_ticks_usec() - start) / 1000.0
	var objects_after: float = Performance.get_monitor(Performance.OBJECT_COUNT)
	assert_eq(driver.get_status(), PlayerRouteDriver.Status.FINISHED, driver.get_failure_message())
	assert_eq(driver.get_reached_count(), 240)
	assert_between(driver.get_elapsed(), 480.0, 780.0, "le parcours de test doit durer environ 10 minutes")
	assert_eq(objects_after, objects_before, "aucun objet créé pendant le parcours")
	var average_usec: float = float(driver_usec) / float(ticks)
	assert_lt(average_usec, 50.0, "le pilotage doit rester négligeable devant 16,7 ms par image")
	_assert_actions_released()

	var recorder := PerfRecorder.new()
	var capacity: int = int(ceilf(PlayerRoute.MAX_DURATION_S * 2000.0)) + 1
	assert_true(recorder.reserve(capacity), "la mémoire des mesures du plus long parcours doit pouvoir être réservée")
	var memory_mb: float = float(capacity) * 28.0 / 1048576.0
	gut.p("Parcours de %.0f s (%d pas, %.0f m) simulé en %.0f ms." % [driver.get_elapsed(), ticks, driver.get_distance_walked(), total_ms])
	gut.p("Pilote : %.2f µs par pas en moyenne, %d µs au pire." % [average_usec, driver_max_usec])
	gut.p("Mémoire des mesures réservée pour le plus long parcours : %d images (%.1f Mo)." % [capacity, memory_mb])


func _make_runner(args: Dictionary[String, String]) -> PipelineRunner:
	var runner := PipelineRunner.new()
	add_child_autofree(runner)
	runner.configure(args)
	return runner


func test_walk_mode_measures_the_whole_route() -> void:
	var world: Node3D = _build_world(false)
	_add_player(world, false)
	var out_dir: String = OS.get_user_data_dir().path_join("tests/pipeline_walk")
	var runner: PipelineRunner = _make_runner({"mode": "walk", "out": out_dir, "no-budgets": "true", "warmup": "0"})
	# Sans rendu, les images s'enchaînent bien au-delà de 2 000 i/s : la durée maximale du parcours est
	# allongée pour que la mémoire réservée des mesures suffise.
	var data: Dictionary = JsonData.load_dictionary(ROUTE_PATH)
	data["max_duration_s"] = PlayerRoute.MAX_DURATION_S
	var max_fps: int = Engine.max_fps
	var code: int = await runner.run_route(_make_route(data), "scène de test")
	Engine.max_fps = max_fps
	assert_eq(code, PipelineRunner.EXIT_OK)
	var summary: Dictionary = JsonData.load_dictionary(out_dir.path_join("resume.json"))
	assert_eq(str(summary.get("mode", "")), "walk")
	assert_eq(str(summary.get("route", "")), "test")
	assert_eq(str(summary.get("route_status", "")), "finished")
	assert_eq(int(summary.get("route_waypoints_reached", 0)), 4)
	assert_false(bool(summary.get("budgets_checked", true)))
	var frames: int = int(summary.get("frames", 0))
	assert_gt(frames, 0)
	var csv: PackedStringArray = FileAccess.get_file_as_string(out_dir.path_join("images.csv")).strip_edges().split("\n")
	assert_eq(csv.size(), frames + 1, "une ligne d'en-tête puis une ligne par image mesurée")
	gut.p("Mode walk : %d images mesurées en %.2f s de parcours." % [frames, float(summary.get("route_time_s", 0.0))])
	_assert_actions_released()


func test_route_video_mode_can_be_shortened() -> void:
	var world: Node3D = _build_world(false)
	var player: PlayerDouble = _add_player(world, false)
	var runner: PipelineRunner = _make_runner({"mode": "flythrough", "duration": "0.5"})
	var code: int = await runner.run_route(PlayerRoute.load_file(ROUTE_PATH), "scène de test")
	assert_eq(code, PipelineRunner.EXIT_OK)
	assert_gt(player.global_position.x, 0.2, "le joueur a commencé à marcher")
	_assert_actions_released()
