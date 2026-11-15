extends PlayerPhysicsCase
## Pires cas du personnage joueur : pas au sol, images de 2 ms et de 100 ms, changements de
## direction à chaque image, 1 000 obstacles autour du joueur (test de charge, mesures imprimées).

const OBSTACLE_COUNT: int = 1000
const LOAD_FRAMES: int = 480


func _collect_footsteps(player: PlayerCharacter) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	player.footstep.connect(
		func(foot: int, at: Vector3, speed: float, collider: Object) -> void:
			events.append({"foot": foot, "position": at, "speed": speed, "collider": collider})
	)
	return events


func test_footsteps_follow_the_stride_with_alternating_feet_and_ground_collider() -> void:
	var world: Node3D = _new_world()
	var ground: StaticBody3D = PlayerTestWorld.ground(world, "terre")
	var player: PlayerCharacter = _spawn(world)
	await _settle()
	player.input.simulate(Vector2(0.0, 1.0), true)
	await _simulate(3.0)
	var events: Array[Dictionary] = _collect_footsteps(player)
	var start: Vector3 = player.global_position
	await _simulate(3.0)
	var distance: float = _horizontal_distance(start, player.global_position)
	var stride: float = player.get_settings().gait_stride_length[LocomotionSettings.Gait.RUN]
	assert_almost_eq(float(events.size()), distance / stride, 1.01, "un pas par foulée de course")
	for i: int in events.size():
		var event: Dictionary = events[i]
		assert_eq(int(event["foot"]), (int(events[0]["foot"]) + i) % 2, "les pieds alternent")
		assert_same(event["collider"], ground, "le collisionneur sous le pied est le sol")
		assert_almost_eq((event["position"] as Vector3).y, 0.0, 0.01)
		assert_gt(float(event["speed"]), 4.0)
	var surface: Variant = (events[0]["collider"] as Object).get_meta(&"surface")
	assert_eq(surface, "terre", "la surface est lisible par le collisionneur")


func test_no_footsteps_when_standing_or_pushing_against_a_wall() -> void:
	var world: Node3D = _new_world()
	PlayerTestWorld.ground(world)
	PlayerTestWorld.box(world, Vector3(40.0, 5.0, 1.0), Vector3(0.0, 2.5, -6.0))
	var player: PlayerCharacter = _spawn(world)
	await _settle()
	var events: Array[Dictionary] = _collect_footsteps(player)
	await _simulate(1.0)
	assert_eq(events.size(), 0, "immobile : aucun pas")
	player.input.simulate(Vector2(0.0, 1.0), true)
	await _simulate(3.0)
	var count_at_wall: int = events.size()
	await _simulate(2.0)
	assert_eq(events.size(), count_at_wall, "poussé contre un mur : aucun pas")


func _wall_run(ticks: int, wall_thickness: float, seconds: float) -> PlayerCharacter:
	Engine.physics_ticks_per_second = ticks
	var world: Node3D = _new_world()
	PlayerTestWorld.ground(world)
	PlayerTestWorld.box(world, Vector3(40.0, 5.0, wall_thickness), Vector3(0.0, 2.5, -4.0 - wall_thickness * 0.5))
	var player: PlayerCharacter = _spawn(world)
	await _settle()
	player.input.simulate(Vector2(0.0, 1.0), true)
	await _simulate(seconds)
	return player


func test_very_long_frames_do_not_cross_a_thin_wall() -> void:
	# Pire cas : images de 100 ms (10 par seconde) à pleine vitesse contre un mur de 10 cm.
	var player: PlayerCharacter = await _wall_run(10, 0.1, 4.0)
	assert_gt(player.global_position.z, -4.0, "le mur n'est pas traversé à 100 ms")
	assert_true(player.is_on_floor())
	assert_false(is_nan(player.global_position.x))


func test_very_short_frames_are_stable() -> void:
	# Pire cas : images de 2 ms (500 par seconde) : même comportement, aucun tremblement.
	var player: PlayerCharacter = await _wall_run(500, 1.0, 2.0)
	assert_gt(player.global_position.z, -4.0)
	assert_lt(player.global_position.z, -4.0 + player.get_settings().body_radius + 0.05, "arrêté contre le mur")
	assert_lt(player.real_speed, 0.1)


func test_speed_is_independent_of_the_physics_rate() -> void:
	for ticks: int in [20, 60, 240]:
		Engine.physics_ticks_per_second = ticks
		var world: Node3D = _new_world()
		PlayerTestWorld.ground(world)
		var player: PlayerCharacter = _spawn(world)
		await _settle()
		player.input.simulate(Vector2(0.0, 1.0), true)
		await _simulate(2.5)
		assert_almost_eq(player.real_speed, player.get_settings().gait_speed[LocomotionSettings.Gait.RUN], 0.15, "%d i/s" % ticks)
		world.free()


func test_worst_case_direction_flip_every_frame_on_a_slope_and_stairs() -> void:
	# Pire cas : le stick change complètement de direction à chaque image, à pleine vitesse, sur
	# une pente à la limite de l'angle maximal à côté d'un escalier.
	var world: Node3D = _new_world()
	PlayerTestWorld.ground(world)
	PlayerTestWorld.ramp(world, 44.0, -2.0, 0.0, 20.0)
	PlayerTestWorld.stairs(world, 8, 0.25, 0.4, -2.0, 8.0)
	var player: PlayerCharacter = _spawn(world, Vector3(0.0, 0.02, 2.0))
	await _settle()
	var invalid_frames: int = 0
	var below_world: int = 0
	var swing: float = deg_to_rad(70.0)
	for i: int in 480:
		# Moitié du temps vers la pente (-Z), moitié vers l'escalier (+X), avec un écart alterné de ±70° à chaque image.
		var heading: float = 0.0 if i < 240 else deg_to_rad(90.0)
		var angle: float = heading + (swing if i % 2 == 0 else -swing)
		player.input.simulate(Vector2(sin(angle), cos(angle)), true)
		await wait_physics_frames(1)
		var at: Vector3 = player.global_position
		if is_nan(at.x) or is_nan(at.y) or is_nan(at.z) or absf(at.x) > 100.0 or absf(at.z) > 100.0:
			invalid_frames += 1
		if at.y < -0.5:
			below_world += 1
	assert_eq(invalid_frames, 0)
	assert_eq(below_world, 0, "ne passe jamais à travers le sol")


func test_worst_case_one_thousand_obstacles_around_the_player() -> void:
	# Pire cas : 1 000 obstacles avec collision, course dans tous les sens à 120 i/s (images de 8 ms).
	Engine.physics_ticks_per_second = 120
	var world: Node3D = _new_world()
	PlayerTestWorld.ground(world)
	PlayerTestWorld.scatter(world, OBSTACLE_COUNT, 30.0, 2.0, 12345)
	var player: PlayerCharacter = _spawn(world)
	await _settle()
	var generator := RandomNumberGenerator.new()
	generator.seed = 99
	var samples := PackedFloat64Array()
	samples.resize(LOAD_FRAMES)
	var stick := Vector2(0.0, 1.0)
	var most_collisions: int = 0
	for i: int in LOAD_FRAMES:
		if i % 30 == 0:
			var angle: float = generator.randf_range(-PI, PI)
			stick = Vector2(sin(angle), cos(angle))
		player.input.simulate(stick, true)
		await wait_physics_frames(1)
		samples[i] = float(player.last_step_usec) / 1000.0
		most_collisions = maxi(most_collisions, player.get_slide_collision_count())
	var sorted: PackedFloat64Array = samples.duplicate()
	sorted.sort()
	var total: float = 0.0
	for value: float in samples:
		total += value
	var average: float = total / float(LOAD_FRAMES)
	var p95: float = sorted[int(float(LOAD_FRAMES) * 0.95)]
	var worst: float = sorted[LOAD_FRAMES - 1]
	gut.p(
		(
			"Déplacement avec %d obstacles : moyenne %.3f ms, p95 %.3f ms, pire %.3f ms (%d images, jusqu'à %d contacts par image)"
			% [OBSTACLE_COUNT, average, p95, worst, LOAD_FRAMES, most_collisions]
		)
	)
	var settings: LocomotionSettings = player.get_settings()
	PerfCheck.under(self, average, settings.budget_step_average_ms, "moyenne sous le budget")
	PerfCheck.under(self, p95, settings.budget_step_p95_ms, "95e centile sous le budget")
	assert_between(player.global_position.y, -0.01, 0.1, "reste au sol parmi les obstacles")
