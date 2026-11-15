extends PlayerPhysicsCase
## Déplacement physique du personnage joueur dans des scènes construites par le test :
## sol, pentes, mur, coin rentrant, escalier, bord de falaise, caméra tournée.


func test_contract_group_layers_and_default_collision() -> void:
	var world: Node3D = _new_world()
	var player: PlayerCharacter = _spawn(world)
	assert_true(player.is_in_group(&"player"))
	assert_eq(player.collision_layer, 2, "couche 2")
	assert_eq(player.collision_mask, 1, "masque 1")
	assert_true(player.get_node("Collision") is CollisionShape3D, "capsule sans modèle")
	assert_false(player.is_animating(), "sans AnimationPlayer, aucune animation")
	assert_eq(player.get_gait(), &"idle")


func test_stands_still_on_flat_ground() -> void:
	var world: Node3D = _new_world()
	PlayerTestWorld.ground(world)
	var player: PlayerCharacter = _spawn(world)
	await _settle()
	var start: Vector3 = player.global_position
	await _simulate(1.0)
	assert_true(player.is_on_floor())
	assert_almost_eq(player.global_position.y, 0.0, 0.02)
	assert_lt(player.global_position.distance_to(start), 0.001, "aucune dérive à l'arrêt")
	assert_eq(player.get_gait(), &"idle")


func test_walk_speed_on_flat_ground() -> void:
	var world: Node3D = _new_world()
	PlayerTestWorld.ground(world)
	var player: PlayerCharacter = _spawn(world)
	await _settle()
	player.input.simulate(Vector2(0.0, 1.0))
	await _simulate(3.0)
	assert_eq(player.get_gait(), &"walk")
	assert_almost_eq(player.real_speed, player.get_settings().gait_speed[LocomotionSettings.Gait.WALK], 0.05)
	assert_lt(player.global_position.z, -3.0, "avance vers -Z, devant la caméra par défaut")
	assert_almost_eq(player.global_position.x, 0.0, 0.01)


func test_run_speed_on_flat_ground() -> void:
	var world: Node3D = _new_world()
	PlayerTestWorld.ground(world)
	var player: PlayerCharacter = _spawn(world)
	await _settle()
	player.input.simulate(Vector2(0.0, 1.0), true)
	await _simulate(3.0)
	assert_eq(player.get_gait(), &"run")
	assert_almost_eq(player.real_speed, player.get_settings().gait_speed[LocomotionSettings.Gait.RUN], 0.1)


func test_walk_slow_speed_and_half_stick() -> void:
	var world: Node3D = _new_world()
	PlayerTestWorld.ground(world)
	var player: PlayerCharacter = _spawn(world)
	await _settle()
	var slow: float = player.get_settings().gait_speed[LocomotionSettings.Gait.WALK_SLOW]
	player.input.simulate(Vector2(0.0, 1.0), false, true)
	await _simulate(2.0)
	assert_eq(player.get_gait(), &"walk_slow")
	assert_almost_eq(player.real_speed, slow, 0.05)
	player.input.simulate(Vector2(0.0, 0.5))
	await _simulate(2.0)
	assert_eq(player.get_gait(), &"walk_slow", "stick à moitié : marche lente")
	assert_between(player.real_speed, slow * 0.5, slow)


func test_gait_changed_signal_sequence() -> void:
	var world: Node3D = _new_world()
	PlayerTestWorld.ground(world)
	var player: PlayerCharacter = _spawn(world)
	await _settle()
	var gaits: Array[StringName] = []
	player.gait_changed.connect(func(gait: StringName) -> void: gaits.append(gait))
	player.input.simulate(Vector2(0.0, 1.0), true)
	await _simulate(1.5)
	player.input.simulate(Vector2.ZERO)
	await _simulate(1.5)
	assert_eq(gaits.back(), &"idle")
	assert_true(gaits.has(&"run"))
	for i: int in range(1, gaits.size()):
		assert_ne(gaits[i], gaits[i - 1], "le signal n'est émis qu'au changement")


func test_camera_relative_movement() -> void:
	var world: Node3D = _new_world()
	PlayerTestWorld.ground(world)
	var camera := Camera3D.new()
	camera.rotation.y = PI / 2.0
	camera.position = Vector3(0.0, 3.0, 5.0)
	world.add_child(camera)
	camera.make_current()
	var player: PlayerCharacter = _spawn(world)
	await _settle()
	player.input.simulate(Vector2(0.0, 1.0))
	await _simulate(3.0)
	assert_lt(player.global_position.x, -2.5, "avancer = aller là où regarde la caméra (-X)")
	assert_between(player.global_position.z, -0.5, 0.05, "le quart de tour initial n'écarte que très peu")
	assert_almost_eq(angle_difference(player.rotation.y, PI / 2.0), 0.0, 0.05, "regard vers -X")


func test_climbs_a_30_degree_slope_at_full_speed() -> void:
	var world: Node3D = _new_world()
	PlayerTestWorld.ground(world)
	PlayerTestWorld.ramp(world, 30.0, -4.0)
	var player: PlayerCharacter = _spawn(world, Vector3(0.0, 0.02, -2.0))
	await _settle()
	player.input.simulate(Vector2(0.0, 1.0), true)
	await _simulate(3.0)
	assert_true(player.is_on_floor())
	assert_gt(player.global_position.y, 2.0, "monte la pente")
	assert_almost_eq(player.get_real_velocity().length(), player.get_settings().gait_speed[LocomotionSettings.Gait.RUN], 0.3)


func test_climbs_a_slope_at_the_maximum_angle() -> void:
	var world: Node3D = _new_world()
	PlayerTestWorld.ground(world)
	PlayerTestWorld.ramp(world, 43.0, -4.0)
	var player: PlayerCharacter = _spawn(world, Vector3(0.0, 0.02, -2.0))
	await _settle()
	player.input.simulate(Vector2(0.0, 1.0))
	await _simulate(5.0)
	assert_true(player.is_on_floor())
	assert_gt(player.global_position.y, 2.0, "une pente sous l'angle maximal se gravit")


func test_slope_beyond_the_maximum_angle_is_a_wall() -> void:
	var world: Node3D = _new_world()
	PlayerTestWorld.ground(world)
	PlayerTestWorld.ramp(world, 60.0, -4.0)
	var player: PlayerCharacter = _spawn(world, Vector3(0.0, 0.02, -2.0))
	await _settle()
	player.input.simulate(Vector2(0.0, 1.0), true)
	await _simulate(4.0)
	assert_lt(player.global_position.y, 0.4, "une pente trop raide ne se gravit pas")
	assert_gt(player.global_position.z, -4.5, "arrêté au pied de la pente")


func test_descends_a_slope_staying_on_the_ground() -> void:
	var world: Node3D = _new_world()
	PlayerTestWorld.ground(world)
	PlayerTestWorld.ramp(world, 40.0, -4.0)
	var top: Vector3 = Vector3(0.0, 4.0, -4.0 - 4.0 / tan(deg_to_rad(40.0)))
	var player: PlayerCharacter = _spawn(world, top + Vector3.UP * 0.02, PI)
	await _settle()
	player.input.simulate(Vector2(0.0, -1.0), true)
	var airborne: int = 0
	var frames: int = int(1.5 * float(Engine.physics_ticks_per_second))
	for i: int in frames:
		await wait_physics_frames(1)
		if not player.is_grounded() and i > 10:
			airborne += 1
	assert_eq(airborne, 0, "la descente d'une pente raide reste collée au sol à pleine vitesse")
	assert_lt(player.global_position.y, top.y - 2.0)


func test_wall_blocks_and_never_gets_crossed() -> void:
	var world: Node3D = _new_world()
	PlayerTestWorld.ground(world)
	PlayerTestWorld.box(world, Vector3(40.0, 5.0, 1.0), Vector3(0.0, 2.5, -10.0))
	var player: PlayerCharacter = _spawn(world)
	await _settle()
	player.input.simulate(Vector2(0.0, 1.0), true)
	await _simulate(5.0)
	var radius: float = player.get_settings().body_radius
	assert_gt(player.global_position.z, -9.5 + radius - 0.01, "arrêté contre la face du mur")
	assert_lt(player.global_position.z, -9.5 + radius + 0.1, "pas de recul ni de rebond")
	assert_lt(player.real_speed, 0.05)


func test_slides_along_a_wall() -> void:
	var world: Node3D = _new_world()
	PlayerTestWorld.ground(world)
	PlayerTestWorld.box(world, Vector3(60.0, 5.0, 1.0), Vector3(0.0, 2.5, -10.0))
	var player: PlayerCharacter = _spawn(world)
	await _settle()
	player.input.simulate(Vector2(1.0, 1.0), true)
	await _simulate(6.0)
	assert_gt(player.global_position.x, 8.0, "glisse le long du mur au lieu de s'arrêter")
	assert_gt(player.global_position.z, -9.5 + player.get_settings().body_radius - 0.01)


func test_reentrant_corner_is_stable_without_jitter() -> void:
	# Pire cas : coin rentrant, poussée en diagonale à pleine vitesse, les deux collisions se cumulent.
	var world: Node3D = _new_world()
	PlayerTestWorld.ground(world)
	PlayerTestWorld.box(world, Vector3(40.0, 5.0, 1.0), Vector3(0.0, 2.5, -10.0))
	PlayerTestWorld.box(world, Vector3(1.0, 5.0, 40.0), Vector3(10.0, 2.5, 0.0))
	var player: PlayerCharacter = _spawn(world)
	await _settle()
	player.input.simulate(Vector2(1.0, 1.0), true)
	await _simulate(5.0)
	var rest: Vector3 = player.global_position
	var largest_move: float = 0.0
	for i: int in 60:
		await wait_physics_frames(1)
		largest_move = maxf(largest_move, player.global_position.distance_to(rest))
	var radius: float = player.get_settings().body_radius
	assert_lt(player.global_position.x, 9.5 - radius + 0.01)
	assert_gt(player.global_position.z, -9.5 + radius - 0.01)
	assert_lt(largest_move, 0.005, "aucun tremblement dans le coin")


func test_walks_off_a_cliff_and_falls_at_most_at_terminal_speed() -> void:
	var world: Node3D = _new_world()
	PlayerTestWorld.box(world, Vector3(20.0, 1.0, 20.0), Vector3(0.0, -0.5, 0.0))
	var player: PlayerCharacter = _spawn(world)
	await _settle()
	player.input.simulate(Vector2(0.0, 1.0), true)
	await _simulate(6.0)
	assert_false(player.is_on_floor())
	assert_lt(player.global_position.y, -5.0, "tombe du bord")
	assert_gte(player.velocity.y, -player.get_settings().terminal_fall_speed - 0.01)
	assert_lt(player.velocity.y, 0.0)


func test_u_turn_physically_turns_around() -> void:
	var world: Node3D = _new_world()
	PlayerTestWorld.ground(world)
	var player: PlayerCharacter = _spawn(world)
	await _settle()
	player.input.simulate(Vector2(0.0, 1.0), true)
	await _simulate(2.5)
	var turn_start: Vector3 = player.global_position
	player.input.simulate(Vector2(0.0, -1.0), true)
	await _simulate(3.0)
	assert_gt(player.global_position.z, turn_start.z, "revient sur ses pas")
	assert_almost_eq(absf(angle_difference(player.rotation.y, PI)), 0.0, 0.05)


func test_teleport_resets_without_footsteps_or_turns() -> void:
	var world: Node3D = _new_world()
	PlayerTestWorld.ground(world)
	var player: PlayerCharacter = _spawn(world)
	await _settle()
	player.input.simulate(Vector2(0.0, 1.0), true)
	await _simulate(2.0)
	var steps: Array[int] = [0]
	player.footstep.connect(func(_foot: int, _at: Vector3, _speed: float, _collider: Object) -> void: steps[0] += 1)
	player.input.simulate(Vector2.ZERO)
	player.teleport_to(Vector3(50.0, 0.05, 50.0), 1.0)
	await _simulate(0.1)
	assert_eq(steps[0], 0, "une téléportation n'émet aucun pas")
	assert_eq(player.get_gait(), &"idle")
	assert_almost_eq(player.global_position.x, 50.0, 0.01)
