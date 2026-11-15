extends GutTest
## Test de charge des entrées : pires cas décrits dans res://data/input/charge.json.
##
## - 16 manettes qui envoient chacune tous leurs boutons et axes (32) à chaque image, en alternance avec
##   le clavier (le dernier périphérique utilisé change à chaque événement) : temps par image et
##   aucune allocation d'objet ;
## - 16 manettes qui maintiennent toutes leurs actions, débranchées puis rebranchées en boucle
##   pendant qu'une touche du clavier est maintenue : aucune action bloquée « appuyée » ;
## - fichier des touches de taille maximale, trop gros, et enregistrements répétés (partie de
##   100 heures) : durées et taille du fichier stable.

const ACTIONS_PATH: String = "res://data/input/actions.json"
const LOAD_PATH: String = "res://data/input/charge.json"

var _limits: Dictionary = {}
var _catalog: Dictionary = {}
var _switches: int = 0
var _directory: String = ""
var _path: String = ""


func before_all() -> void:
	_limits = JsonData.load_dictionary(LOAD_PATH)
	_catalog = JsonData.load_dictionary(ACTIONS_PATH)
	_directory = OS.get_temp_dir().path_join("ibn_tests_charge_entrees_%d" % OS.get_process_id())
	_path = _directory.path_join("controles.json")
	assert_eq(DirAccess.make_dir_recursive_absolute(_directory), OK)


func after_all() -> void:
	for suffix: String in ["", InputBindings.TEMP_SUFFIX, InputBindings.BACKUP_SUFFIX]:
		if FileAccess.file_exists(_path + suffix) and DirAccess.remove_absolute(_path + suffix) != OK:
			push_warning("Fichier de test non supprimé : %s" % (_path + suffix))
	if DirAccess.dir_exists_absolute(_directory) and DirAccess.remove_absolute(_directory) != OK:
		push_warning("Dossier de test non supprimé : %s" % _directory)
	GameInput.use_user_file("")


func test_device_switch_every_event_with_all_gamepads() -> void:
	var gamepads: int = JsonData.get_int(_limits, "gamepads", "charge")
	var per_gamepad: int = JsonData.get_int(_limits, "events_per_gamepad_per_frame", "charge")
	var frames: int = JsonData.get_int(_limits, "frames", "charge")
	assert_eq(per_gamepad, JOY_BUTTON_SDL_MAX + JOY_AXIS_SDL_MAX)
	var gamepad_events: Array[InputEvent] = []
	for device: int in gamepads:
		for button: int in int(JOY_BUTTON_SDL_MAX):
			var press := InputEventJoypadButton.new()
			press.device = device
			press.button_index = button as JoyButton
			press.pressed = true
			gamepad_events.append(press)
		for axis: int in int(JOY_AXIS_SDL_MAX):
			var motion := InputEventJoypadMotion.new()
			motion.device = device
			motion.axis = axis as JoyAxis
			motion.axis_value = 1.0
			gamepad_events.append(motion)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_W
	key.pressed = true
	var tracker := InputDeviceTracker.new()
	tracker.configure(
		JsonData.get_float(_catalog, "joy_axis_activation", "catalogue"),
		JsonData.get_float(_catalog, "mouse_motion_activation_px", "catalogue")
	)
	tracker.device_changed.connect(_on_switch)
	_switches = 0
	var objects_before: float = Performance.get_monitor(Performance.OBJECT_COUNT)
	var start: int = Time.get_ticks_usec()
	for _frame: int in frames:
		for event: InputEvent in gamepad_events:
			tracker.observe(event)
			tracker.observe(key)
	var elapsed_ms: float = float(Time.get_ticks_usec() - start) / 1000.0
	var objects_after: float = Performance.get_monitor(Performance.OBJECT_COUNT)
	var per_frame_ms: float = elapsed_ms / float(frames)
	gut.p(
		(
			"MESURE entrees : %d événements par image (%d manettes + clavier, bascule à chaque événement) : %.4f ms par image"
			% [gamepad_events.size() * 2, gamepads, per_frame_ms]
		)
	)
	assert_eq(_switches, frames * gamepad_events.size() * 2, "un signal à chaque changement")
	assert_eq(objects_after, objects_before, "aucune allocation d'objet par événement")
	assert_lt(per_frame_ms, JsonData.get_float(_limits, "max_observe_ms_per_frame", "charge"))


func test_gamepads_unplugged_while_holding_actions() -> void:
	var gamepads: int = JsonData.get_int(_limits, "gamepads", "charge")
	var cycles: int = JsonData.get_int(_limits, "connection_cycles", "charge")
	var held: Array[InputEvent] = []
	var held_actions: Array[StringName] = []
	_collect_gamepad_bindings(held, held_actions)
	assert_gt(held_actions.size(), 5, "le pire cas maintient de nombreuses actions")
	_parse_now(_make_key(KEY_W, true))
	var stuck: int = 0
	var not_pressed: int = 0
	var keyboard_lost: int = 0
	var worst_ms: float = 0.0
	for _cycle: int in cycles:
		for device: int in gamepads:
			for template: InputEvent in held:
				var press: InputEvent = template.duplicate() as InputEvent
				press.device = device
				Input.parse_input_event(press)
		Input.flush_buffered_events()
		for action: StringName in held_actions:
			if not Input.is_action_pressed(action):
				not_pressed += 1
		var start: int = Time.get_ticks_usec()
		for device: int in gamepads:
			Input.joy_connection_changed.emit(device, false)
		Input.flush_buffered_events()
		worst_ms = maxf(worst_ms, float(Time.get_ticks_usec() - start) / 1000.0)
		for action: StringName in held_actions:
			if action != &"move_forward" and Input.is_action_pressed(action):
				stuck += 1
		if not Input.is_action_pressed(&"move_forward"):
			keyboard_lost += 1
		for device: int in gamepads:
			Input.joy_connection_changed.emit(device, true)
	_parse_now(_make_key(KEY_W, false))
	gut.p(
		(
			"MESURE entrees : %d manettes débranchées en maintenant %d actions : %.3f ms au pire (%d cycles)"
			% [gamepads, held_actions.size(), worst_ms, cycles]
		)
	)
	assert_eq(not_pressed, 0, "toutes les actions sont maintenues avant le débranchement")
	assert_eq(stuck, 0, "aucune action bloquée « appuyée »")
	assert_eq(keyboard_lost, 0, "la touche maintenue au clavier reste appuyée")
	assert_false(Input.is_action_pressed(&"move_forward"))
	assert_lt(worst_ms, JsonData.get_float(_limits, "max_disconnect_all_ms", "charge"))


func test_largest_user_file_and_repeated_saves() -> void:
	var bindings := InputBindings.new()
	bindings.configure(_catalog, _path)
	var user_file: Dictionary = _catalog["user_file"]
	var max_bytes: int = int(user_file["max_bytes"])
	var max_per_family: int = int(_catalog["max_events_per_family"])
	# Toutes les actions surchargées avec le nombre maximal de touches, complété par des espaces
	# jusqu'à la taille maximale acceptée.
	var actions: Dictionary = {}
	for action: StringName in bindings.get_action_names():
		var events: Array[Dictionary] = []
		for i: int in max_per_family:
			events.append({"type": "key", "physical": OS.get_keycode_string((KEY_F1 + i) as Key)})
			events.append({"type": "joy_button", "button": 13 + i})
		actions[String(action)] = {"deadzone": 0.35, "events": events}
	var text: String = JSON.stringify({"version": int(user_file["version"]), "actions": actions})
	assert_lt(text.length(), max_bytes)
	_write_text(text + " ".repeat(max_bytes - text.to_utf8_buffer().size()))
	var start: int = Time.get_ticks_usec()
	bindings.load_user_file()
	var full_ms: float = float(Time.get_ticks_usec() - start) / 1000.0
	assert_eq(bindings.last_load_status, InputBindings.LoadStatus.LOADED)
	for action: StringName in bindings.get_action_names():
		assert_eq(bindings.get_binding(action).events.size(), 2 * max_per_family, str(action))
	_write_text(" ".repeat(max_bytes + 1))
	start = Time.get_ticks_usec()
	bindings.load_user_file()
	var oversized_ms: float = float(Time.get_ticks_usec() - start) / 1000.0
	assert_eq(bindings.last_load_status, InputBindings.LoadStatus.CORRUPTED)
	# Enregistrements répétés : la taille du fichier ne grandit pas.
	_write_text(text)
	bindings.load_user_file()
	var cycles: int = JsonData.get_int(_limits, "save_load_cycles", "charge")
	var sizes: Dictionary[int, bool] = {}
	var failures: int = 0
	start = Time.get_ticks_usec()
	for _cycle: int in cycles:
		if bindings.save_user_file() != OK:
			failures += 1
		bindings.load_user_file()
		if bindings.last_load_status != InputBindings.LoadStatus.LOADED:
			failures += 1
		sizes[FileAccess.get_file_as_bytes(_path).size()] = true
	var cycle_ms: float = float(Time.get_ticks_usec() - start) / 1000.0 / float(cycles)
	gut.p("MESURE entrees : fichier des touches de %d octets lu en %.2f ms" % [max_bytes, full_ms])
	gut.p("MESURE entrees : fichier trop gros refusé en %.3f ms" % oversized_ms)
	gut.p("MESURE entrees : enregistrement puis relecture en %.2f ms" % cycle_ms)
	assert_eq(failures, 0)
	assert_eq(sizes.size(), 1, "taille du fichier stable")
	assert_lt(full_ms, JsonData.get_float(_limits, "max_full_file_load_ms", "charge"))
	assert_lt(oversized_ms, JsonData.get_float(_limits, "max_oversized_load_ms", "charge"))
	assert_lt(cycle_ms, JsonData.get_float(_limits, "max_save_load_ms", "charge"))


func _on_switch(_kind: InputDeviceTracker.Kind, _device: int) -> void:
	_switches += 1


## Toutes les touches de manette du catalogue (un seul sens par axe), sauf celles de quit_game, et
## les actions qu'elles maintiennent.
func _collect_gamepad_bindings(events: Array[InputEvent], actions: Array[StringName]) -> void:
	var axes: Dictionary[int, bool] = {}
	for binding: InputActionBinding in InputActions.parse(_catalog):
		if binding.action == &"quit_game":
			continue
		for event: InputEvent in binding.events:
			if InputEventCodec.family_of(event) != InputEventCodec.Family.GAMEPAD:
				continue
			if event is InputEventJoypadMotion:
				var motion: InputEventJoypadMotion = event
				if axes.has(motion.axis):
					continue
				axes[motion.axis] = true
			else:
				var button: InputEventJoypadButton = event
				button.pressed = true
			events.append(event)
			if not actions.has(binding.action):
				actions.append(binding.action)


func _write_text(text: String) -> void:
	var file: FileAccess = FileAccess.open(_path, FileAccess.WRITE)
	assert_not_null(file)
	assert_true(file.store_string(text))
	file.close()


static func _parse_now(event: InputEvent) -> void:
	Input.parse_input_event(event)
	Input.flush_buffered_events()


static func _make_key(keycode: Key, pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.pressed = pressed
	return event
