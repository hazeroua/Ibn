extends PlayerPhysicsCase
## Réactions au monde : franchissement d'obstacles bas sans jamais traverser l'obstacle, arrêt net contre un
## mur, refus des obstacles trop épais ou interdits (métadonnée « franchissable »), et 1 000 collisionneurs.


func _run_into(box_size: Vector3, franchissable: bool = true, seconds: float = 3.0) -> Dictionary:
	var world: Node3D = _new_world()
	PlayerTestWorld.ground(world)
	var box: StaticBody3D = PlayerTestWorld.box(world, box_size, Vector3(0.0, box_size.y * 0.5, -4.0 - box_size.z * 0.5))
	if not franchissable:
		box.set_meta(&"franchissable", false)
	var player: PlayerCharacter = _spawn(world)
	await _settle()
	player.input.simulate(Vector2(0.0, 1.0), true)
	var radius: float = player.get_settings().body_radius
	var front: float = -4.0
	var back: float = -4.0 - box_size.z
	var inside: int = 0
	var frames: int = int(seconds * float(Engine.physics_ticks_per_second))
	for index: int in frames:
		await wait_physics_frames(1)
		var p: Vector3 = player.global_position
		# Capsule dans le volume de l'obstacle : bas du corps sous son dessus alors qu'elle le recouvre.
		if p.z - radius < front - 0.03 and p.z + radius > back + 0.03 and p.y < box_size.y - 0.05:
			inside += 1
	return {"z": player.global_position.z, "y": player.global_position.y, "inside": inside, "speed": player.motor.speed}


func test_vaults_over_low_wall_without_clipping() -> void:
	var result: Dictionary = await _run_into(Vector3(4.0, 0.7, 0.4))
	assert_eq(int(result["inside"]), 0, "jamais dans le muret")
	assert_lt(float(result["z"]), -5.0, "de l'autre côté du muret")
	assert_lt(float(result["y"]), 0.1, "reçu au sol")


func test_does_not_vault_thick_or_forbidden_obstacles() -> void:
	var thick: Dictionary = await _run_into(Vector3(4.0, 0.7, 3.0), true, 2.0)
	assert_eq(int(thick["inside"]), 0)
	assert_gt(float(thick["z"]), -4.0, "reste devant un bloc trop épais")
	var forbidden: Dictionary = await _run_into(Vector3(4.0, 0.7, 0.4), false, 2.0)
	assert_eq(int(forbidden["inside"]), 0)
	assert_gt(float(forbidden["z"]), -4.0, "reste devant un muret interdit")


func test_running_into_high_wall_stops_without_penetration() -> void:
	var result: Dictionary = await _run_into(Vector3(4.0, 2.5, 1.0), true, 2.0)
	assert_eq(int(result["inside"]), 0)
	assert_gt(float(result["z"]), -4.0)
	assert_lt(float(result["y"]), 0.1, "pas de franchissement d'un mur haut")


func test_thousand_colliders_running_stays_out_of_obstacles() -> void:
	var world: Node3D = _new_world()
	PlayerTestWorld.ground(world)
	PlayerTestWorld.scatter(world, 1000, 90.0, 3.0, 1406)
	var player: PlayerCharacter = _spawn(world)
	await _settle()
	var worst_us: int = 0
	for leg: int in 8:
		player.input.simulate(Vector2(sin(float(leg) * 2.1), cos(float(leg) * 2.1)), true)
		for index: int in 120:
			await wait_physics_frames(1)
			worst_us = maxi(worst_us, player.last_step_usec)
	gut.p("Pire cas réactions : 1 000 collisionneurs, pas de physique le plus long %.3f ms" % (float(worst_us) / 1000.0))
	assert_lt(player.global_position.y, 3.0)
	assert_lt(worst_us, 4000)
