extends GutTest
## Lecture des entrées du personnage : entrées simulées et lecture des actions du contrat.

const ACTIONS: Array[StringName] = [&"move_left", &"move_right", &"move_forward", &"move_back", &"sprint", &"walk_slow"]

var _added: Array[StringName] = []
var _input: PlayerInput


func before_each() -> void:
	_input = PlayerInput.new()
	for action: StringName in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
			_added.append(action)


func after_each() -> void:
	for action: StringName in ACTIONS:
		Input.action_release(action)
	for action: StringName in _added:
		InputMap.erase_action(action)
	_added.clear()


func test_simulated_input_is_kept_and_limited_to_unit_length() -> void:
	_input.simulate(Vector2(3.0, 4.0), true, true)
	assert_almost_eq(_input.move.length(), 1.0, 0.0001)
	assert_true(_input.sprint)
	assert_true(_input.walk_slow)
	Input.action_release(&"sprint")
	_input.poll()
	assert_almost_eq(_input.move.length(), 1.0, 0.0001, "poll() ne lit pas les actions pendant la simulation")
	assert_true(_input.sprint)


func test_poll_reads_the_contract_actions() -> void:
	Input.action_press(&"move_forward", 1.0)
	Input.action_press(&"move_right", 1.0)
	Input.action_press(&"sprint")
	_input.poll()
	assert_gt(_input.move.x, 0.5)
	assert_gt(_input.move.y, 0.5, "avancer = y positif")
	assert_true(_input.sprint)
	assert_false(_input.walk_slow)
	Input.action_release(&"sprint")
	Input.action_press(&"walk_slow")
	_input.poll()
	assert_false(_input.sprint)
	assert_true(_input.walk_slow)


func test_analog_strength_gives_intermediate_move() -> void:
	Input.action_press(&"move_forward", 0.6)
	_input.poll()
	assert_between(_input.move.y, 0.3, 0.7, "stick à moitié : intensité intermédiaire")
	assert_eq(_input.move.x, 0.0)


func test_back_and_left_are_negative() -> void:
	Input.action_press(&"move_back", 1.0)
	Input.action_press(&"move_left", 1.0)
	_input.poll()
	assert_lt(_input.move.x, 0.0)
	assert_lt(_input.move.y, 0.0)


func test_use_actions_returns_to_reading_the_actions() -> void:
	_input.simulate(Vector2(0.0, 1.0), true)
	_input.use_actions()
	_input.poll()
	assert_eq(_input.move, Vector2.ZERO)
	assert_false(_input.sprint)


func test_missing_action_is_reported_once_and_treated_as_released() -> void:
	var events: Array[InputEvent] = []
	var deadzone: float = 0.2
	if InputMap.has_action(&"walk_slow"):
		events.assign(InputMap.action_get_events(&"walk_slow"))
		deadzone = InputMap.action_get_deadzone(&"walk_slow")
		InputMap.erase_action(&"walk_slow")
	elif _added.has(&"walk_slow"):
		InputMap.erase_action(&"walk_slow")
	_input.poll()
	_input.poll()
	assert_push_error_count(1, "l'absence d'action n'est signalée qu'une fois")
	assert_false(_input.walk_slow)
	InputMap.add_action(&"walk_slow", deadzone)
	for event: InputEvent in events:
		InputMap.action_add_event(&"walk_slow", event)
