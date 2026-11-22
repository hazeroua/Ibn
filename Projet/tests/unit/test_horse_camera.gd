extends GutTest
## Caméra à cheval : cadrage du cavalier, champ qui s'ouvre au galop, comportement identique à 20 et 240 i/s,
## passage à pied ↔ à cheval sans saut. Pire cas : galop de course (11,5 m/s) en ligne droite puis en lacets.

const SPRINT_MPS: float = 11.5


func _rig_following(target: Node3D) -> ThirdPersonCamera:
	var rig := ThirdPersonCamera.new()
	rig.input_enabled = false
	target.get_parent().add_child(rig)
	rig.apply_settings(CameraSettings.load_mounted())
	rig.set_target(target)
	return rig


func _gallop(fps: float) -> Dictionary:
	var world := Node3D.new()
	add_child_autofree(world)
	var target := Node3D.new()
	world.add_child(target)
	var rig: ThirdPersonCamera = _rig_following(target)
	var dt: float = 1.0 / fps
	var steps: int = int(6.0 * fps)
	var worst_jump: float = 0.0
	var previous: Vector3 = Vector3.ZERO
	for index: int in steps:
		var t: float = float(index) * dt
		target.position = Vector3(sin(t * 0.8) * 6.0, 0.0, -SPRINT_MPS * t)
		rig.step(dt)
		if index > 0:
			worst_jump = maxf(worst_jump, rig.global_position.distance_to(previous) - SPRINT_MPS * dt * 1.6)
		previous = rig.global_position
	var offset: Vector3 = rig.global_position - target.position
	return {"offset": offset, "fov": rig.camera.fov, "jump": worst_jump}


func test_gallop_framing_is_frame_rate_independent() -> void:
	var slow: Dictionary = await _gallop(20.0)
	var fast: Dictionary = await _gallop(240.0)
	var settings: CameraSettings = CameraSettings.load_mounted()
	for result: Dictionary in [slow, fast]:
		var offset: Vector3 = result["offset"]
		assert_false(is_nan(offset.x) or is_nan(offset.y) or is_nan(offset.z))
		assert_gt(offset.y, 1.5, "la caméra reste au-dessus du cavalier")
		assert_gt(float(result["fov"]), settings.fov_base_deg + settings.fov_run_bonus_deg * 0.8, "champ ouvert au galop")
		assert_lt(float(result["jump"]), 0.05, "aucun à-coup de la caméra")
	assert_lt((slow["offset"] as Vector3).distance_to(fast["offset"] as Vector3), 0.35, "même cadrage à 20 et 240 i/s")
	assert_almost_eq(float(slow["fov"]), float(fast["fov"]), 0.5)


func test_mounting_blends_without_snap() -> void:
	var world := Node3D.new()
	add_child_autofree(world)
	var walker := Node3D.new()
	world.add_child(walker)
	var horse := Node3D.new()
	world.add_child(horse)
	horse.position = Vector3(1.0, 0.0, 0.0)
	var rig := ThirdPersonCamera.new()
	rig.input_enabled = false
	world.add_child(rig)
	rig.set_target(walker)
	for index: int in 120:
		rig.step(1.0 / 60.0)
	var before: Vector3 = rig.global_position
	rig.glide_to_target(horse)
	rig.blend_to_settings(CameraSettings.load_mounted())
	rig.step(1.0 / 60.0)
	assert_lt(rig.global_position.distance_to(before), 0.3, "pas de saut à la monte")
	for index: int in 300:
		rig.step(1.0 / 60.0)
	assert_gt(rig.global_position.distance_to(horse.position), 5.0, "recul à cheval atteint")
