extends GutTest
## Catalogue des actions d'entrée (res://data/input/actions.json) et déclaration dans l'InputMap.

const ACTIONS_PATH: String = "res://data/input/actions.json"
## Actions du contrat du MVP 1 (Docs/contrats-mvp-1.md), de la caméra libre du bac à sable, du saut et de Barq (MVP 3).
const REQUIRED_ACTIONS: Array[StringName] = [
	&"move_forward",
	&"move_back",
	&"move_left",
	&"move_right",
	&"move_up",
	&"move_down",
	&"sprint",
	&"walk_slow",
	&"look_left",
	&"look_right",
	&"look_up",
	&"look_down",
	&"camera_zoom_in",
	&"camera_zoom_out",
	&"look_hold",
	&"quit_game",
	&"jump",
	&"mount_horse",
	&"horse_whistle",
	&"perf_overlay",
]
## Actions jouables à la manette comme au clavier et à la souris.
const BOTH_FAMILIES: Array[StringName] = [
	&"move_forward",
	&"move_back",
	&"move_left",
	&"move_right",
	&"sprint",
	&"walk_slow",
	&"camera_zoom_in",
	&"camera_zoom_out",
	&"quit_game",
	&"jump",
	&"mount_horse",
	&"horse_whistle",
	&"perf_overlay",
]


func after_all() -> void:
	# Remet l'InputMap dans l'état voulu par le singleton (touches du joueur comprises).
	GameInput.use_user_file("")


func test_all_actions_are_declared_with_events() -> void:
	var count: int = InputActions.apply(JsonData.load_dictionary(ACTIONS_PATH))
	assert_eq(count, REQUIRED_ACTIONS.size())
	for action: StringName in REQUIRED_ACTIONS:
		assert_true(InputMap.has_action(action), "action %s" % action)
		assert_gt(InputMap.action_get_events(action).size(), 0, "événements de %s" % action)


func test_actions_are_available_on_keyboard_mouse_and_gamepad() -> void:
	var catalog: Array[InputActionBinding] = InputActions.parse(JsonData.load_dictionary(ACTIONS_PATH))
	for binding: InputActionBinding in catalog:
		if BOTH_FAMILIES.has(binding.action):
			assert_gt(binding.family_count(InputEventCodec.Family.KEYBOARD_MOUSE), 0, "clavier/souris : %s" % binding.action)
			assert_gt(binding.family_count(InputEventCodec.Family.GAMEPAD), 0, "manette : %s" % binding.action)


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


func test_events_accept_every_device() -> void:
	# Une manette branchée en deuxième (numéro 1 ou plus) doit piloter les actions comme la première.
	InputActions.apply(JsonData.load_dictionary(ACTIONS_PATH))
	for action: StringName in REQUIRED_ACTIONS:
		for event: InputEvent in InputMap.action_get_events(action):
			assert_eq(event.device, InputEventCodec.ALL_DEVICES, "appareil des touches de %s" % action)


func test_deadzones_come_from_data() -> void:
	var data: Dictionary = JsonData.load_dictionary(ACTIONS_PATH)
	InputActions.apply(data)
	for raw: Variant in data["actions"]:
		var entry: Dictionary = raw
		var action := StringName(str(entry["name"]))
		assert_almost_eq(InputMap.action_get_deadzone(action), float(entry["deadzone"]), 0.0001, "zone morte de %s" % action)


func test_default_bindings_have_no_conflict() -> void:
	var bindings := InputBindings.new()
	bindings.configure(JsonData.load_dictionary(ACTIONS_PATH), OS.get_temp_dir().path_join("ibn_inexistant.json"))
	assert_eq(bindings.get_all_conflicts().size(), 0, "aucune touche partagée dans un même contexte")


func test_reapplying_does_not_duplicate_events() -> void:
	var data: Dictionary = JsonData.load_dictionary(ACTIONS_PATH)
	InputActions.apply(data)
	var first: int = InputMap.action_get_events(&"move_forward").size()
	InputActions.apply(data)
	assert_eq(InputMap.action_get_events(&"move_forward").size(), first)


func test_event_codec_round_trip() -> void:
	var samples: Array[Dictionary] = [
		{"type": "key", "physical": "Shift"},
		{"type": "key", "physical": "W"},
		{"type": "mouse_button", "button": 4},
		{"type": "joy_button", "button": 20},
		{"type": "joy_axis", "axis": 5, "value": 1.0},
		{"type": "joy_axis", "axis": 0, "value": -1.0},
	]
	for sample: Dictionary in samples:
		var errors: Array[String] = []
		var event: InputEvent = InputEventCodec.from_data(sample, errors)
		assert_not_null(event, str(sample))
		assert_eq(errors.size(), 0)
		var again: InputEvent = InputEventCodec.from_data(InputEventCodec.to_data(event), errors)
		assert_eq(InputEventCodec.binding_key(again), InputEventCodec.binding_key(event), str(sample))


func test_event_codec_rejects_invalid_descriptions() -> void:
	var samples: Array[Variant] = [
		"W",
		{},
		{"type": "key"},
		{"type": "key", "physical": "TouchePasLa"},
		{"type": "mouse_button", "button": 0},
		{"type": "mouse_button", "button": 2.5},
		{"type": "joy_button", "button": JOY_BUTTON_SDL_MAX},
		{"type": "joy_axis", "axis": 1, "value": 0.5},
		{"type": "joy_axis", "axis": JOY_AXIS_SDL_MAX, "value": 1.0},
		{"type": "gyroscope"},
	]
	for sample: Variant in samples:
		var errors: Array[String] = []
		assert_null(InputEventCodec.from_data(sample, errors), str(sample))
		assert_eq(errors.size(), 1, "une raison pour %s" % str(sample))


func test_normalize_keeps_only_bindable_inputs() -> void:
	var weak_axis := InputEventJoypadMotion.new()
	weak_axis.axis = JOY_AXIS_LEFT_X
	weak_axis.axis_value = 0.2
	assert_null(InputEventCodec.normalize(weak_axis, 0.5), "stick à peine incliné")
	var strong_axis := InputEventJoypadMotion.new()
	strong_axis.axis = JOY_AXIS_LEFT_X
	strong_axis.axis_value = -0.9
	strong_axis.device = 3
	var axis_binding: InputEventJoypadMotion = InputEventCodec.normalize(strong_axis, 0.5)
	assert_eq(axis_binding.axis_value, -1.0)
	assert_eq(axis_binding.device, InputEventCodec.ALL_DEVICES)
	assert_null(InputEventCodec.normalize(InputEventMouseMotion.new(), 0.5), "mouvement de souris")
	var logical_only := InputEventKey.new()
	logical_only.keycode = KEY_W
	assert_null(InputEventCodec.normalize(logical_only, 0.5), "touche sans position physique")
