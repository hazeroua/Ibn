extends Node
## Singleton « GameInput » : actions d'entrée (catalogue res://data/input/actions.json et touches du
## joueur), dernier périphérique utilisé, manettes branchées ou débranchées en jeu, capture de la
## souris et sortie du jeu.
##
## Aucun _process : tout passe par les événements (_input) et par les signaux du moteur.

## Le joueur vient d'utiliser un autre périphérique (pour adapter les aides affichées).
signal device_changed(kind: InputDeviceTracker.Kind, device: int)
## Les touches d'une action ont changé (action vide : toutes les actions).
signal bindings_changed(action: StringName)

const ACTIONS_PATH: String = "res://data/input/actions.json"

## Touches du joueur (lecture, reconfiguration, conflits). Pour modifier les touches, passer par
## les fonctions de ce singleton, qui enregistrent le fichier du joueur.
var bindings: InputBindings = InputBindings.new()
var device_tracker: InputDeviceTracker = InputDeviceTracker.new()

var _catalog: Dictionary = {}
var _mouse_capture_requested: bool = false
var _window_focused: bool = true


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_catalog = JsonData.load_dictionary(ACTIONS_PATH)
	device_tracker.configure(
		JsonData.get_float(_catalog, "joy_axis_activation", InputActions.CONTEXT),
		JsonData.get_float(_catalog, "mouse_motion_activation_px", InputActions.CONTEXT)
	)
	_connect(device_tracker.device_changed, device_changed.emit)
	_connect(bindings.bindings_changed, _on_bindings_changed)
	_connect(Input.joy_connection_changed, _on_joy_connection_changed)
	use_user_file("")


func _input(event: InputEvent) -> void:
	device_tracker.observe(event)
	# Certains systèmes refusent la capture tant que le joueur n'a pas cliqué dans la fenêtre.
	if (
		_mouse_capture_requested
		and _window_focused
		and event is InputEventMouseButton
		and event.is_pressed()
		and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED
	):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"quit_game"):
		get_tree().quit()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			_window_focused = false
			_update_mouse_mode()
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_WM_WINDOW_FOCUS_IN:
			_window_focused = true
			_update_mouse_mode()


## Demande (ou non) la capture de la souris pendant le jeu : la souris est cachée et bloquée au
## centre tant que la fenêtre a le focus, libérée dès qu'elle le perd, reprise quand il revient.
func set_mouse_capture(enabled: bool) -> void:
	_mouse_capture_requested = enabled
	_update_mouse_mode()


func is_mouse_capture_requested() -> bool:
	return _mouse_capture_requested


## Vrai si la souris doit être capturée en ce moment (capture demandée et fenêtre active).
func is_mouse_capture_active() -> bool:
	return _mouse_capture_requested and _window_focused


## Change une touche (voir InputBindings.rebind) et enregistre le fichier du joueur si elle est acceptée.
func rebind(action: StringName, event: InputEvent, slot: int = 0, replace_conflicts: bool = false) -> InputBindings.RebindResult:
	var result: InputBindings.RebindResult = bindings.rebind(action, event, slot, replace_conflicts)
	if result == InputBindings.RebindResult.OK:
		_save()
	return result


## Retire une touche d'une action et enregistre le fichier du joueur.
func unbind(action: StringName, family: InputEventCodec.Family, slot: int) -> bool:
	var done: bool = bindings.unbind(action, family, slot)
	if done:
		_save()
	return done


## Change la zone morte d'une action et enregistre le fichier du joueur.
func set_deadzone(action: StringName, deadzone: float) -> bool:
	var done: bool = bindings.set_deadzone(action, deadzone)
	if done:
		_save()
	return done


## Remet une action à ses touches par défaut et enregistre le fichier du joueur.
func reset(action: StringName) -> bool:
	var done: bool = bindings.reset(action)
	if done:
		_save()
	return done


## Remet toutes les actions à leurs touches par défaut et enregistre le fichier du joueur.
func reset_all() -> void:
	bindings.reset_all()
	_save()


## Change le fichier des touches du joueur et le relit ; résultat dans bindings.last_load_status
## (les tests utilisent un fichier jetable pour ne jamais toucher au vrai fichier du joueur ;
## chemin vide = chemin du catalogue).
func use_user_file(path: String) -> void:
	bindings.configure(_catalog, path)
	bindings.load_user_file()


func _save() -> void:
	var error: Error = bindings.save_user_file()
	if error != OK:
		push_warning("GameInput : enregistrement impossible de %s (%s)." % [bindings.get_user_path(), error_string(error)])


func _connect(source: Signal, target: Callable) -> void:
	var error: Error = source.connect(target) as Error
	if error != OK:
		push_error("GameInput : connexion impossible au signal %s (%s)." % [source.get_name(), error_string(error)])


func _update_mouse_mode() -> void:
	if is_mouse_capture_active():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_bindings_changed(action: StringName) -> void:
	if action.is_empty():
		for action_name: StringName in bindings.get_action_names():
			InputActions.apply_binding(bindings.get_binding(action_name))
	else:
		InputActions.apply_binding(bindings.get_binding(action))
	bindings_changed.emit(action)


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if connected:
		return
	InputDeviceTracker.release_gamepad(device)
	device_tracker.on_gamepad_disconnected(device, Input.get_connected_joypads())
