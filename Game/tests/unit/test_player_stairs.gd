extends PlayerPhysicsCase
## Escaliers : montée à la marche et à la course, descente collée au sol (marches de 20 cm).


func _build_stairs_world() -> Node3D:
	var world: Node3D = _new_world()
	PlayerTestWorld.ground(world)
	PlayerTestWorld.stairs(world, 10, 0.2, 0.4, -2.0)
	PlayerTestWorld.box(world, Vector3(6.0, 2.0, 10.0), Vector3(0.0, 1.0, -11.0))
	return world


func test_climbs_stairs_walking() -> void:
	var player: PlayerCharacter = _spawn(_build_stairs_world())
	await _settle()
	player.input.simulate(Vector2(0.0, 1.0))
	await _simulate(6.0)
	assert_true(player.is_on_floor())
	assert_between(player.global_position.y, 1.97, 2.1, "au sommet de l'escalier")


func test_climbs_stairs_running() -> void:
	var player: PlayerCharacter = _spawn(_build_stairs_world())
	await _settle()
	player.input.simulate(Vector2(0.0, 1.0), true)
	await _simulate(3.0)
	assert_true(player.is_on_floor())
	assert_between(player.global_position.y, 1.97, 2.1, "au sommet de l'escalier, en courant")


func test_descends_stairs_walking_staying_on_the_ground() -> void:
	var world: Node3D = _build_stairs_world()
	var player: PlayerCharacter = _spawn(world, Vector3(0.0, 2.02, -8.0), PI)
	await _settle()
	player.input.simulate(Vector2(0.0, -1.0))
	var airborne: int = 0
	var frames: int = int(7.0 * float(Engine.physics_ticks_per_second))
	for i: int in frames:
		await wait_physics_frames(1)
		if not player.is_grounded() and i > 10:
			airborne += 1
	assert_eq(airborne, 0, "descend les marches à la marche sans décoller")
	assert_lt(player.global_position.y, 0.1, "arrivé en bas")


func test_descends_stairs_running_without_falling_through() -> void:
	var world: Node3D = _build_stairs_world()
	var player: PlayerCharacter = _spawn(world, Vector3(0.0, 2.02, -8.0), PI)
	await _settle()
	player.input.simulate(Vector2(0.0, -1.0), true)
	var airborne: int = 0
	var lowest: float = 10.0
	var frames: int = int(3.0 * float(Engine.physics_ticks_per_second))
	for i: int in frames:
		await wait_physics_frames(1)
		lowest = minf(lowest, player.global_position.y)
		if not player.is_grounded():
			airborne += 1
	gut.p("Descente d'escalier en courant : %d images sur %d sans appui au sol" % [airborne, frames])
	assert_gt(lowest, -0.05, "ne traverse jamais le sol")
	assert_lt(player.global_position.y, 0.1, "arrivé en bas")
