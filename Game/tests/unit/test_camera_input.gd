extends GutTest
## Lecture des entrées par la caméra, par le nom des actions du contrat (look_*, camera_zoom_*).
##
## Le test déclare lui-même les actions absentes de la carte des entrées (les actions de zoom sont
## fournies par le ticket des contrôles) et les retire ensuite : il ne dépend d'aucun autre ticket.

var _added_actions: Array[StringName] = []


func before_each() -> void:
	_added_actions.clear()
	for action: StringName in ThirdPersonCamera.REQUIRED_ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			_added_actions.append(action)


func after_each() -> void:
	for action: StringName in ThirdPersonCamera.REQUIRED_ACTIONS:
		Input.action_release(action)
	for action: StringName in _added_actions:
		InputMap.erase_action(action)
	_added_actions.clear()


func _make_camera() -> ThirdPersonCamera:
	var camera := ThirdPersonCamera.new()
	add_child_autofree(camera)
	camera.set_process(false)
	return camera


func test_stick_actions_turn_the_orbit() -> void:
	var camera: ThirdPersonCamera = _make_camera()
	var s: CameraSettings = camera.settings
	camera.snap()
	Input.action_press(ThirdPersonCamera.ACTION_LOOK_RIGHT, 1.0)
	camera._process(0.25)
	Input.action_release(ThirdPersonCamera.ACTION_LOOK_RIGHT)
	var target := Node3D.new()
	add_child_autofree(target)
	camera.target = target
	camera.step(0.0)
	# Stick à fond vers la droite : l'orbite tourne dans le sens horaire vu du dessus.
	assert_almost_eq(camera.get_yaw(), wrapf(s.initial_yaw - s.stick_speed * 0.25, -PI, PI), 0.0001)
	Input.action_press(ThirdPersonCamera.ACTION_LOOK_DOWN, 1.0)
	camera._process(0.1)
	Input.action_release(ThirdPersonCamera.ACTION_LOOK_DOWN)
	camera.snap()
	camera.step(0.0)
	assert_almost_eq(camera.get_pitch(), s.initial_pitch + s.stick_speed * 0.1, 0.0001, "stick vers le bas : la caméra monte")


func test_zoom_actions_change_distance_by_steps() -> void:
	var camera: ThirdPersonCamera = _make_camera()
	var s: CameraSettings = camera.settings
	var zoom_out := InputEventAction.new()
	zoom_out.action = ThirdPersonCamera.ACTION_ZOOM_OUT
	zoom_out.pressed = true
	camera._unhandled_input(zoom_out)
	assert_almost_eq(camera.get_zoom_goal(), minf(s.zoom_initial + s.zoom_step, s.zoom_max), 0.0001)
	var zoom_in := InputEventAction.new()
	zoom_in.action = ThirdPersonCamera.ACTION_ZOOM_IN
	zoom_in.pressed = true
	camera._unhandled_input(zoom_in)
	camera._unhandled_input(zoom_in)
	assert_almost_eq(camera.get_zoom_goal(), maxf(s.zoom_initial - s.zoom_step, s.zoom_min), 0.0001)


func test_mouse_motion_uses_screen_pixels() -> void:
	var camera: ThirdPersonCamera = _make_camera()
	var s: CameraSettings = camera.settings
	var target := Node3D.new()
	add_child_autofree(target)
	camera.target = target
	camera.add_mouse_motion(Vector2(100.0, -50.0))
	camera.snap()
	camera.step(0.0)
	assert_almost_eq(camera.get_yaw(), wrapf(s.initial_yaw - 100.0 * s.mouse_sensitivity, -PI, PI), 0.0001)
	assert_almost_eq(camera.get_pitch(), clampf(s.initial_pitch - 50.0 * s.mouse_sensitivity, s.pitch_min, s.pitch_max), 0.0001)


func test_disabled_input_reads_nothing() -> void:
	var camera := ThirdPersonCamera.new()
	camera.input_enabled = false
	add_child_autofree(camera)
	camera.set_process(false)
	var zoom_out := InputEventAction.new()
	zoom_out.action = ThirdPersonCamera.ACTION_ZOOM_OUT
	zoom_out.pressed = true
	camera._unhandled_input(zoom_out)
	Input.action_press(ThirdPersonCamera.ACTION_LOOK_RIGHT, 1.0)
	camera._process(0.25)
	var target := Node3D.new()
	add_child_autofree(target)
	camera.target = target
	camera.step(0.0)
	assert_almost_eq(camera.get_zoom_goal(), camera.settings.zoom_initial, 0.0001)
	assert_almost_eq(camera.get_yaw(), wrapf(camera.settings.initial_yaw, -PI, PI), 0.0001)
