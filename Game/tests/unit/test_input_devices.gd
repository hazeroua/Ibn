extends GutTest
## Dernier périphérique utilisé, manettes branchées et débranchées en jeu, capture de la souris.

var _tracker: InputDeviceTracker = null
var _changes: Array[Vector2i] = []


func before_each() -> void:
	_tracker = InputDeviceTracker.new()
	_tracker.configure(0.5, 3.0)
	_changes.clear()
	_tracker.device_changed.connect(_on_device_changed)


func after_each() -> void:
	_release_everything()
	GameInput.set_mouse_capture(false)
	GameInput.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)


func test_starts_on_keyboard_and_mouse() -> void:
	assert_eq(_tracker.kind, InputDeviceTracker.Kind.KEYBOARD_MOUSE)
	assert_eq(_tracker.gamepad_device, -1)


func test_switches_on_deliberate_use_only() -> void:
	_tracker.observe(_joy_button(2, JOY_BUTTON_A, false))
	_tracker.observe(_joy_axis(2, JOY_AXIS_LEFT_X, 0.3))
	assert_eq(_changes.size(), 0, "relâchement et stick au repos ne basculent pas")
	_tracker.observe(_joy_button(2, JOY_BUTTON_A, true))
	assert_eq(_changes.size(), 1)
	assert_eq(_changes[0], Vector2i(InputDeviceTracker.Kind.GAMEPAD, 2))
	_tracker.observe(_joy_axis(3, JOY_AXIS_RIGHT_Y, -0.8))
	assert_eq(_tracker.gamepad_device, 3, "une deuxième manette prend la main")
	_tracker.observe(_mouse_motion(Vector2(1.0, 1.0)))
	assert_eq(_tracker.kind, InputDeviceTracker.Kind.GAMEPAD, "souris à peine effleurée")
	_tracker.observe(_mouse_motion(Vector2(8.0, 0.0)))
	assert_eq(_tracker.kind, InputDeviceTracker.Kind.KEYBOARD_MOUSE)
	_tracker.observe(_joy_button(3, JOY_BUTTON_B, true))
	var echo: InputEventKey = _key(KEY_W, true)
	echo.echo = true
	_tracker.observe(echo)
	assert_eq(_tracker.kind, InputDeviceTracker.Kind.GAMEPAD, "la répétition d'une touche maintenue ne bascule pas")
	var emulated: InputEventKey = _key(KEY_W, true)
	emulated.device = InputEvent.DEVICE_ID_EMULATION
	_tracker.observe(emulated)
	assert_eq(_tracker.kind, InputDeviceTracker.Kind.GAMEPAD, "événement simulé par le moteur")
	_tracker.observe(_key(KEY_W, true))
	assert_eq(_tracker.kind, InputDeviceTracker.Kind.KEYBOARD_MOUSE)
	assert_eq(_changes.size(), 5)


func test_switch_every_event_emits_every_time() -> void:
	for i: int in 10:
		_tracker.observe(_key(KEY_W, true))
		_tracker.observe(_joy_button(0, JOY_BUTTON_A, true))
	assert_eq(_changes.size(), 20)


func test_disconnecting_active_gamepad_falls_back() -> void:
	var connected: Array[int] = [1, 3]
	_tracker.observe(_joy_button(3, JOY_BUTTON_A, true))
	_tracker.on_gamepad_disconnected(1, connected)
	assert_eq(_tracker.gamepad_device, 3, "une manette inutilisée débranchée ne change rien")
	_tracker.on_gamepad_disconnected(3, connected)
	assert_eq(_tracker.gamepad_device, 1, "bascule sur la manette encore branchée")
	var none: Array[int] = []
	_tracker.on_gamepad_disconnected(1, none)
	assert_eq(_tracker.kind, InputDeviceTracker.Kind.KEYBOARD_MOUSE)
	assert_eq(_tracker.gamepad_device, -1)


func test_disconnection_releases_only_that_gamepad() -> void:
	_parse(_key(KEY_W, true))
	_parse(_joy_axis(0, JOY_AXIS_LEFT_Y, -1.0))
	_parse(_joy_axis(1, JOY_AXIS_LEFT_Y, -1.0))
	_parse(_joy_button(1, JOY_BUTTON_LEFT_STICK, true))
	_parse(_joy_axis(1, JOY_AXIS_TRIGGER_LEFT, 1.0))
	assert_true(Input.is_action_pressed(&"move_forward"))
	assert_true(Input.is_action_pressed(&"walk_slow"))
	assert_true(Input.is_action_pressed(&"sprint"))
	_set_connected(1, false)
	assert_false(Input.is_action_pressed(&"walk_slow"), "plus d'action bloquée « appuyée »")
	assert_false(Input.is_action_pressed(&"sprint"))
	assert_false(Input.is_joy_button_pressed(1, JOY_BUTTON_LEFT_STICK))
	assert_true(Input.is_action_pressed(&"move_forward"), "maintenue au clavier et par la manette 0")
	_set_connected(0, false)
	assert_true(Input.is_action_pressed(&"move_forward"), "toujours maintenue au clavier")
	_parse(_key(KEY_W, false))
	assert_false(Input.is_action_pressed(&"move_forward"))


func test_reconnected_gamepad_starts_released() -> void:
	_parse(_joy_button(4, JOY_BUTTON_LEFT_STICK, true))
	_set_connected(4, false)
	_set_connected(4, true)
	assert_false(Input.is_action_pressed(&"walk_slow"))
	_parse(_joy_button(4, JOY_BUTTON_LEFT_STICK, true))
	assert_true(Input.is_action_pressed(&"walk_slow"), "la manette rebranchée fonctionne de nouveau")


func test_game_input_relays_device_changes() -> void:
	var kinds: Array[int] = []
	var record: Callable = func(kind: InputDeviceTracker.Kind, _device: int) -> void: kinds.append(kind)
	GameInput.device_changed.connect(record)
	_parse(_joy_button(5, JOY_BUTTON_LEFT_STICK, true))
	_parse(_key(KEY_W, true))
	GameInput.device_changed.disconnect(record)
	assert_eq(kinds.size(), 2)
	assert_eq(kinds[0], InputDeviceTracker.Kind.GAMEPAD as int)
	assert_eq(kinds[1], InputDeviceTracker.Kind.KEYBOARD_MOUSE as int)


func test_mouse_capture_follows_window_focus() -> void:
	assert_false(GameInput.is_mouse_capture_active(), "pas de capture sans demande")
	GameInput.set_mouse_capture(true)
	assert_true(GameInput.is_mouse_capture_active())
	GameInput.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert_false(GameInput.is_mouse_capture_active(), "libérée quand la fenêtre perd le focus")
	assert_true(GameInput.is_mouse_capture_requested())
	GameInput.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	assert_true(GameInput.is_mouse_capture_active(), "reprise au retour du focus")
	GameInput.set_mouse_capture(false)
	assert_false(GameInput.is_mouse_capture_active())


func _on_device_changed(kind: InputDeviceTracker.Kind, device: int) -> void:
	_changes.append(Vector2i(kind, device))


func _set_connected(device: int, connected: bool) -> void:
	Input.joy_connection_changed.emit(device, connected)
	Input.flush_buffered_events()


func _parse(event: InputEvent) -> void:
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _release_everything() -> void:
	for device: int in 16:
		InputDeviceTracker.release_gamepad(device)
	Input.parse_input_event(_key(KEY_W, false))
	Input.flush_buffered_events()
	for action: StringName in InputMap.get_actions():
		Input.action_release(action)


static func _key(keycode: Key, pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.pressed = pressed
	return event


static func _joy_button(device: int, button: JoyButton, pressed: bool) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.device = device
	event.button_index = button
	event.pressed = pressed
	return event


static func _joy_axis(device: int, axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.device = device
	event.axis = axis
	event.axis_value = value
	return event


static func _mouse_motion(relative: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.relative = relative
	return event
