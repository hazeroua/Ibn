extends GutTest
## Touches du joueur : surcharge utilisateur, fichiers corrompus, partiels ou d'une autre version,
## reconfiguration par code et conflits. Tous les fichiers sont jetables (dans OS.get_temp_dir()) : le vrai fichier du
## joueur (user://controles.json) n'est jamais lu ni écrit.

const ACTIONS_PATH: String = "res://data/input/actions.json"

var _directory: String = ""
var _path: String = ""
var _catalog: Dictionary = {}
var _bindings: InputBindings = null


func before_all() -> void:
	_catalog = JsonData.load_dictionary(ACTIONS_PATH)
	_directory = OS.get_temp_dir().path_join("ibn_tests_entrees_%d" % OS.get_process_id())
	_path = _directory.path_join("controles.json")


func before_each() -> void:
	_remove_files()
	_bindings = InputBindings.new()
	_bindings.configure(_catalog, _path)


func after_all() -> void:
	_remove_files()
	if DirAccess.dir_exists_absolute(_directory) and DirAccess.remove_absolute(_directory) != OK:
		push_warning("Dossier de test non supprimé : %s" % _directory)
	GameInput.use_user_file("")


func test_missing_file_gives_defaults() -> void:
	assert_eq(_load(_bindings), InputBindings.LoadStatus.NO_FILE)
	for action: StringName in _bindings.get_action_names():
		assert_false(_bindings.is_customized(action), str(action))


func test_override_is_merged_with_defaults() -> void:
	_write({"version": 1, "actions": {"sprint": {"events": [{"type": "key", "physical": "C"}], "deadzone": 0.4}}})
	assert_eq(_load(_bindings), InputBindings.LoadStatus.LOADED)
	var sprint: InputActionBinding = _bindings.get_binding(&"sprint")
	assert_eq(sprint.events.size(), 1)
	var sprint_key: InputEventKey = sprint.events[0]
	assert_eq(sprint_key.physical_keycode, KEY_C)
	assert_almost_eq(sprint.deadzone, 0.4, 0.0001)
	assert_true(_bindings.is_customized(&"sprint"))
	assert_false(_bindings.is_customized(&"move_forward"), "les actions absentes du fichier gardent leurs valeurs par défaut")


func test_corrupted_files_fall_back_to_defaults() -> void:
	var contents: Array[String] = [
		"",
		"{ ceci n'est pas du JSON",
		'{"version": 1, "actions": {"sprint": {"events": [{"type": "key", "phys',
		"[1, 2, 3]",
		'{"actions": {}}',
		'{"version": "un", "actions": {}}',
		'{"version": 1.5, "actions": {}}',
		'{"version": 0, "actions": {}}',
		'{"version": 1, "actions": []}',
		"\u0001\u0002binaire",
	]
	for content: String in contents:
		_write_text(content)
		assert_eq(_load(_bindings), InputBindings.LoadStatus.CORRUPTED, content)
		assert_false(_bindings.is_customized(&"sprint"), content)


func test_oversized_file_is_rejected_without_reading() -> void:
	var user_file: Dictionary = _catalog["user_file"]
	var max_bytes: int = int(user_file["max_bytes"])
	_write_text(" ".repeat(max_bytes + 1))
	assert_eq(_load(_bindings), InputBindings.LoadStatus.CORRUPTED)


func test_partial_file_keeps_valid_parts_only() -> void:
	var actions: Dictionary = {
		"sprint": {"events": [{"type": "key", "physical": "C"}]},
		"walk_slow": {"events": [{"type": "key", "physical": "C"}, {"type": "joy_button", "button": 999}]},
		"move_left": {"deadzone": 7.0},
		"move_right": "pas un objet",
		"action_disparue": {"events": []},
	}
	_write({"version": 1, "actions": actions})
	assert_eq(_load(_bindings), InputBindings.LoadStatus.LOADED_WITH_REJECTIONS)
	assert_true(_bindings.is_customized(&"sprint"))
	assert_false(_bindings.is_customized(&"walk_slow"), "une liste de touches invalide est ignorée en entier")
	assert_false(_bindings.is_customized(&"move_left"))
	assert_false(_bindings.is_customized(&"move_right"))
	assert_eq(_bindings.last_load_warnings.size(), 4)


func test_newer_version_is_ignored_then_backed_up_on_save() -> void:
	_write({"version": 99, "actions": {"sprint": {"events": []}}})
	assert_eq(_load(_bindings), InputBindings.LoadStatus.NEWER_VERSION)
	assert_false(_bindings.is_customized(&"sprint"))
	assert_eq(_bindings.save_user_file(), OK)
	assert_true(FileAccess.file_exists(_path + InputBindings.BACKUP_SUFFIX), "le fichier d'origine est conservé à part")
	assert_string_contains(FileAccess.get_file_as_string(_path + InputBindings.BACKUP_SUFFIX), "99")
	assert_eq(_load(_bindings), InputBindings.LoadStatus.LOADED)


func test_older_version_follows_renamed_actions() -> void:
	var catalog: Dictionary = _catalog.duplicate(true)
	var user_file: Dictionary = catalog["user_file"]
	user_file["version"] = 2
	catalog["renamed_actions"] = {"courir": "sprint"}
	_bindings.configure(catalog, _path)
	_write({"version": 1, "actions": {"courir": {"events": [{"type": "key", "physical": "C"}]}}})
	assert_eq(_load(_bindings), InputBindings.LoadStatus.LOADED)
	assert_true(_bindings.is_customized(&"sprint"))
	assert_false(_bindings.is_customized(&"walk_slow"), "action absente de l'ancien fichier : valeur par défaut")


func test_save_then_load_round_trip() -> void:
	assert_eq(_bindings.rebind(&"sprint", _key(KEY_C)), InputBindings.RebindResult.OK)
	assert_eq(_bindings.rebind(&"sprint", _joy_button(JOY_BUTTON_RIGHT_STICK), 1), InputBindings.RebindResult.OK)
	assert_true(_bindings.set_deadzone(&"look_left", 0.25))
	assert_eq(_bindings.save_user_file(), OK)
	assert_false(FileAccess.file_exists(_path + InputBindings.TEMP_SUFFIX), "le fichier intermédiaire est renommé")
	var reloaded := InputBindings.new()
	reloaded.configure(_catalog, _path)
	assert_eq(_load(reloaded), InputBindings.LoadStatus.LOADED)
	assert_true(reloaded.get_binding(&"sprint").same_as(_bindings.get_binding(&"sprint")))
	assert_almost_eq(reloaded.get_binding(&"look_left").deadzone, 0.25, 0.0001)
	assert_false(reloaded.is_customized(&"move_forward"))
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_path))
	var saved_actions: Dictionary = saved["actions"]
	assert_eq(saved_actions.size(), 2, "seules les actions modifiées sont enregistrées")


func test_interrupted_save_is_recovered_from_temporary_file() -> void:
	_write_text('{"version": 1, "actions": {"sprint": {"events": [{"type": "key", "physical": "C"}]}}}', InputBindings.TEMP_SUFFIX)
	assert_eq(_load(_bindings), InputBindings.LoadStatus.LOADED)
	assert_true(_bindings.is_customized(&"sprint"))


func test_rebind_replaces_slot_of_same_family() -> void:
	assert_eq(_bindings.rebind(&"walk_slow", _key(KEY_C)), InputBindings.RebindResult.OK)
	var walk: InputActionBinding = _bindings.get_binding(&"walk_slow")
	assert_eq(walk.family_count(InputEventCodec.Family.KEYBOARD_MOUSE), 1)
	assert_eq(walk.family_count(InputEventCodec.Family.GAMEPAD), 1, "la touche de la manette ne change pas")
	assert_ne(walk.find_key(InputEventCodec.binding_key(_key(KEY_C))), -1)


func test_rebind_validation() -> void:
	assert_eq(_bindings.rebind(&"inconnue", _key(KEY_C)), InputBindings.RebindResult.UNKNOWN_ACTION)
	assert_eq(_bindings.rebind(&"sprint", InputEventMouseMotion.new()), InputBindings.RebindResult.INVALID_EVENT)
	assert_eq(_bindings.rebind(&"sprint", _key(KEY_C), -1), InputBindings.RebindResult.INVALID_SLOT)
	assert_eq(_bindings.rebind(&"sprint", _key(KEY_C), 5), InputBindings.RebindResult.INVALID_SLOT)
	var max_per_family: int = int(_catalog["max_events_per_family"])
	for slot: int in range(1, max_per_family):
		assert_eq(_bindings.rebind(&"sprint", _key((KEY_F1 + slot) as Key), slot), InputBindings.RebindResult.OK)
	assert_eq(_bindings.rebind(&"sprint", _key(KEY_F12), max_per_family), InputBindings.RebindResult.INVALID_SLOT)


func test_conflicts_are_detected_within_shared_contexts() -> void:
	# W sert déjà à move_forward, actif dans le jeu comme sprint.
	var conflicts: Array[StringName] = _bindings.find_conflicts(&"sprint", _key(KEY_W))
	assert_eq(conflicts.size(), 1)
	assert_eq(conflicts[0], &"move_forward")
	assert_eq(_bindings.rebind(&"sprint", _key(KEY_W)), InputBindings.RebindResult.CONFLICT)
	assert_false(_bindings.is_customized(&"sprint"), "un refus ne change rien")
	# E sert à move_up, qui n'existe que pour la caméra libre : pas de conflit avec walk_slow (jeu).
	assert_eq(_bindings.find_conflicts(&"walk_slow", _key(KEY_E)).size(), 0)
	assert_eq(_bindings.rebind(&"walk_slow", _key(KEY_E)), InputBindings.RebindResult.OK)
	assert_eq(_bindings.get_all_conflicts().size(), 0)


func test_rebind_with_replacement_removes_key_from_other_action() -> void:
	assert_eq(_bindings.rebind(&"sprint", _key(KEY_W), 0, true), InputBindings.RebindResult.OK)
	assert_eq(_bindings.get_binding(&"move_forward").family_count(InputEventCodec.Family.KEYBOARD_MOUSE), 0)
	assert_eq(_bindings.get_all_conflicts().size(), 0)


func test_reset_restores_defaults_and_reports_conflicts() -> void:
	assert_eq(_bindings.rebind(&"sprint", _key(KEY_W), 0, true), InputBindings.RebindResult.OK)
	assert_true(_bindings.reset(&"move_forward"))
	var conflicts: Array[Dictionary] = _bindings.get_all_conflicts()
	assert_eq(conflicts.size(), 1, "W est de nouveau partagé par move_forward et sprint")
	var involved: Array[StringName] = conflicts[0]["actions"]
	assert_true(involved.has(&"sprint") and involved.has(&"move_forward"))
	_bindings.reset_all()
	assert_eq(_bindings.get_all_conflicts().size(), 0)
	assert_false(_bindings.reset(&"inconnue"))


func test_unbind_and_deadzone_validation() -> void:
	assert_true(_bindings.unbind(&"sprint", InputEventCodec.Family.GAMEPAD, 0))
	assert_false(_bindings.unbind(&"sprint", InputEventCodec.Family.GAMEPAD, 0), "plus de touche de manette")
	assert_false(_bindings.set_deadzone(&"sprint", 1.5))
	assert_false(_bindings.set_deadzone(&"sprint", -0.1))
	assert_false(_bindings.set_deadzone(&"sprint", NAN))
	assert_true(_bindings.set_deadzone(&"sprint", 0.0))


func test_game_input_applies_rebind_to_input_map() -> void:
	GameInput.use_user_file(_path)
	assert_eq(GameInput.bindings.last_load_status, InputBindings.LoadStatus.NO_FILE)
	assert_eq(GameInput.rebind(&"sprint", _key(KEY_C)), InputBindings.RebindResult.OK)
	assert_true(InputMap.action_has_event(&"sprint", InputEventCodec.make_key(KEY_C)))
	assert_false(InputMap.action_has_event(&"sprint", InputEventCodec.make_key(KEY_SHIFT)))
	assert_true(FileAccess.file_exists(_path), "la reconfiguration est enregistrée")
	assert_true(GameInput.set_deadzone(&"look_left", 0.3))
	assert_almost_eq(InputMap.action_get_deadzone(&"look_left"), 0.3, 0.0001)
	GameInput.reset_all()
	assert_true(InputMap.action_has_event(&"sprint", InputEventCodec.make_key(KEY_SHIFT)))


func _write(data: Dictionary) -> void:
	_write_text(JSON.stringify(data))


func _write_text(text: String, suffix: String = "") -> void:
	assert_eq(DirAccess.make_dir_recursive_absolute(_directory), OK)
	var file: FileAccess = FileAccess.open(_path + suffix, FileAccess.WRITE)
	assert_true(file.store_string(text))
	file.close()


func _remove_files() -> void:
	for suffix: String in ["", InputBindings.TEMP_SUFFIX, InputBindings.BACKUP_SUFFIX]:
		if FileAccess.file_exists(_path + suffix) and DirAccess.remove_absolute(_path + suffix) != OK:
			push_warning("Fichier de test non supprimé : %s" % (_path + suffix))


static func _load(bindings: InputBindings) -> InputBindings.LoadStatus:
	bindings.load_user_file()
	return bindings.last_load_status


static func _key(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.pressed = true
	return event


static func _joy_button(button: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = true
	return event
