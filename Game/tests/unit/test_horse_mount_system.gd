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


func test_pipeline_focus_suspends_barq() -> void:
	var session := DesertSession.new()
	var system := HorseMountSystem.new()
	session._horse_mount = system
	session.pipeline_focus_at(Vector3.ZERO)
	assert_eq(system.process_mode, Node.PROCESS_MODE_DISABLED)
	system.free()
	session.free()
