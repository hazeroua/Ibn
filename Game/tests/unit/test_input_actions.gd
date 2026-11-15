extends GutTest
## Déclaration des actions d'entrée depuis res://data/input/actions.json.

const ACTIONS_PATH: String = "res://data/input/actions.json"
const REQUIRED_ACTIONS: Array[StringName] = [
	&"move_forward",
	&"move_back",
	&"move_left",
	&"move_right",
	&"move_up",
	&"move_down",
	&"sprint",
	&"look_left",
	&"look_right",
	&"look_up",
	&"look_down",
	&"look_hold",
	&"quit_game",
]


func test_all_actions_are_declared_with_events() -> void:
	var count: int = InputActions.apply(JsonData.load_dictionary(ACTIONS_PATH))
	assert_eq(count, REQUIRED_ACTIONS.size())
	for action: StringName in REQUIRED_ACTIONS:
		assert_true(InputMap.has_action(action), "action %s" % action)
		assert_gt(InputMap.action_get_events(action).size(), 0, "événements de %s" % action)


func test_keys_use_physical_positions() -> void:
	InputActions.apply(JsonData.load_dictionary(ACTIONS_PATH))
	var found_physical_key: bool = false
	for event: InputEvent in InputMap.action_get_events(&"move_forward"):
		if event is InputEventKey:
			var key_event: InputEventKey = event
			assert_eq(key_event.physical_keycode, KEY_W)
			assert_eq(key_event.keycode, KEY_NONE, "seule la position physique doit être utilisée")
			found_physical_key = true
	assert_true(found_physical_key)


func test_reapplying_does_not_duplicate_events() -> void:
	var data: Dictionary = JsonData.load_dictionary(ACTIONS_PATH)
	InputActions.apply(data)
	var first: int = InputMap.action_get_events(&"move_forward").size()
	InputActions.apply(data)
	assert_eq(InputMap.action_get_events(&"move_forward").size(), first)
