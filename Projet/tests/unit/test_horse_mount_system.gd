extends GutTest
## Intégration de Barq : le désert lui fournit le joueur et la caméra, sans création à chaque image.
## Pire cas : une partie de 100 h alterne très souvent monte et démontage ; une seule instance de Barq, ses traces
## bornées et ses sons restent attachés à la session.

const MAX_MOUNT_CYCLES_MS: float = 250.0


func test_mount_system_spawns_barq_and_restores_player_camera() -> void:
	var world := Node3D.new()
	add_child_autofree(world)
	var player := PlayerCharacter.new()
	world.add_child(player)
	player.teleport_to(Vector3(12.0, 0.0, -8.0))
	var rig := ThirdPersonCamera.new()
	rig.input_enabled = false
	world.add_child(rig)
	rig.set_target(player)
	var system := HorseMountSystem.new()
	world.add_child(system)
	system.setup(player, rig, null)
	await get_tree().process_frame

	assert_not_null(system.horse)
	assert_eq(system.horse.name, "Barq")
	assert_lte(player.global_position.distance_to(system.horse.global_position), 5.0)
	assert_false(system.mounted)
	assert_not_null(system.audio._breath_stream)
	assert_not_null(system.audio._neigh_stream)
	assert_eq(system.audio._voices.size(), 4, "réserve audio bornée")

	system.mount()
	assert_true(system.mounted)
	assert_true(system.horse.mounted)
	assert_eq(player.process_mode, Node.PROCESS_MODE_DISABLED)
	assert_eq(rig.target, system.horse)

	system.dismount()
	assert_false(system.mounted)
	assert_false(system.horse.mounted)
	assert_eq(player.process_mode, Node.PROCESS_MODE_INHERIT)
	assert_eq(rig.target, player)


func test_six_thousand_mount_cycles_stay_bounded() -> void:
	var world := Node3D.new()
	add_child_autofree(world)
	var player := PlayerCharacter.new()
	world.add_child(player)
	var rig := ThirdPersonCamera.new()
	rig.input_enabled = false
	world.add_child(rig)
	var system := HorseMountSystem.new()
	world.add_child(system)
	system.setup(player, rig, null)
	var cycles: int = 6000  # 100 heures avec une monte/démontage chaque minute.
	var started_usec: int = Time.get_ticks_usec()
	for index: int in cycles:
		system.mount()
		system.dismount()
	var elapsed_ms: float = float(Time.get_ticks_usec() - started_usec) / 1000.0
	gut.p("Pire cas Barq : %d montes/démontages en %.3f ms" % [cycles, elapsed_ms])
	assert_lt(elapsed_ms, MAX_MOUNT_CYCLES_MS)
	assert_false(system.mounted)
	assert_false(system.horse.mounted)
	assert_eq(rig.target, player)
	assert_eq(player.process_mode, Node.PROCESS_MODE_INHERIT)


## Côté et distance : monte permise sur le flanc gauche dégagé, refusée contre un mur, depuis le flanc droit
## (l'approche traverserait Barq) ou trop loin ; descente refusée tant que le flanc gauche est bouché.
func test_mount_requires_clear_left_side_and_reachable_approach() -> void:
	var world := Node3D.new()
	add_child_autofree(world)
	PlayerTestWorld.ground(world)
	var player := PlayerCharacter.new()
	world.add_child(player)
	var system := HorseMountSystem.new()
	world.add_child(system)
	system.setup(player, null, null)
	var horse: HorseController = system.horse
	horse.global_position = Vector3.ZERO
	horse.rotation = Vector3.ZERO
	for index: int in 10:
		await get_tree().physics_frame
	var left: Vector3 = system._mount_point().origin
	player.teleport_to(left + horse.global_basis.x * -0.6)
	await get_tree().physics_frame
	assert_true(system.can_mount(), "flanc gauche dégagé, à portée")
	player.teleport_to(horse.global_position + horse.global_basis.x * 1.4)
	await get_tree().physics_frame
	assert_false(system.can_mount(), "depuis le flanc droit, l'approche traverserait Barq")
	player.teleport_to(left + horse.global_basis.x * -6.0)
	await get_tree().physics_frame
	assert_false(system.can_mount(), "trop loin")
	var wall: StaticBody3D = PlayerTestWorld.box(world, Vector3(0.3, 2.0, 4.0), left + Vector3.UP)
	await get_tree().physics_frame
	player.teleport_to(left + horse.global_basis.x * -0.2 + Vector3(0.0, 0.0, 2.5))
	await get_tree().physics_frame
	assert_false(system.can_mount(), "mur contre le flanc gauche")
	assert_false(system._mount_point_clear())
	wall.free()
	await get_tree().physics_frame
	assert_true(system._mount_point_clear())
