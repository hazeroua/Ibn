class_name InputEventCodec
extends RefCounted
## Conversion entre les événements d'entrée de Godot et leur description JSON, et forme canonique
## d'une touche liée à une action.
##
## Forme canonique : touche du clavier par sa position physique, bouton de souris, bouton de
## manette, ou demi-axe de manette (axe et sens). Tous les événements liés portent l'appareil
## ALL_DEVICES : n'importe quelle manette branchée pilote les actions, quel que soit son numéro.

enum Family { NONE = -1, KEYBOARD_MOUSE = 0, GAMEPAD = 1 }

## Valeur de InputMap.ALL_DEVICES (non exposée au GDScript).
const ALL_DEVICES: int = -1

const _KIND_KEY: int = 1
const _KIND_MOUSE_BUTTON: int = 2
const _KIND_JOY_BUTTON: int = 3
const _KIND_JOY_AXIS: int = 4
const _KIND_SHIFT: int = 40


## Construit l'événement canonique décrit par raw. Renvoie null et ajoute la raison à errors si la
## description est invalide (aucun message n'est affiché : l'appelant choisit erreur ou avertissement).
static func from_data(raw: Variant, errors: Array[String]) -> InputEvent:
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("un événement doit être un objet")
		return null
	var data: Dictionary = raw
	if typeof(data.get("type")) != TYPE_STRING:
		errors.append("« type » manquant ou invalide")
		return null
	var kind: String = data["type"]
	match kind:
		"key":
			if typeof(data.get("physical")) != TYPE_STRING:
				errors.append("« physical » manquant ou invalide")
				return null
			var key_name: String = data["physical"]
			var keycode: Key = OS.find_keycode_from_string(key_name)
			if keycode == KEY_NONE:
				errors.append("touche inconnue « %s »" % key_name)
				return null
			return make_key(keycode)
		"mouse_button":
			var mouse_button: int = _read_index(data, "button", MOUSE_BUTTON_LEFT, MOUSE_BUTTON_XBUTTON2, errors)
			if mouse_button < 0:
				return null
			return make_mouse_button(mouse_button as MouseButton)
		"joy_button":
			var joy_button: int = _read_index(data, "button", 0, JOY_BUTTON_SDL_MAX - 1, errors)
			if joy_button < 0:
				return null
			return make_joy_button(joy_button as JoyButton)
		"joy_axis":
			var axis: int = _read_index(data, "axis", 0, JOY_AXIS_SDL_MAX - 1, errors)
			if axis < 0:
				return null
			var value: Variant = data.get("value")
			if (typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT) or absf(float(value)) != 1.0:
				errors.append("« value » d'un axe doit valoir -1 ou 1")
				return null
			return make_joy_axis(axis as JoyAxis, float(value))
		_:
			errors.append("type d'événement inconnu « %s »" % kind)
			return null


## Description JSON d'un événement canonique (inverse de from_data).
static func to_data(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		return {"type": "key", "physical": OS.get_keycode_string((event as InputEventKey).physical_keycode)}
	if event is InputEventMouseButton:
		return {"type": "mouse_button", "button": int((event as InputEventMouseButton).button_index)}
	if event is InputEventJoypadButton:
		return {"type": "joy_button", "button": int((event as InputEventJoypadButton).button_index)}
	if event is InputEventJoypadMotion:
		var motion: InputEventJoypadMotion = event
		return {"type": "joy_axis", "axis": int(motion.axis), "value": 1.0 if motion.axis_value > 0.0 else -1.0}
	return {}


## Forme canonique d'un événement capturé (par exemple pendant une reconfiguration), ou null s'il ne
## peut pas être lié à une action : touche sans position physique, mouvement de souris, axe trop peu
## incliné (moins de axis_activation), bouton ou axe hors de la numérotation SDL.
static func normalize(event: InputEvent, axis_activation: float) -> InputEvent:
	if event is InputEventKey:
		var keycode: Key = (event as InputEventKey).physical_keycode
		if keycode == KEY_NONE or OS.find_keycode_from_string(OS.get_keycode_string(keycode)) != keycode:
			return null
		return make_key(keycode)
	if event is InputEventMouseButton:
		var mouse_button: MouseButton = (event as InputEventMouseButton).button_index
		if mouse_button < MOUSE_BUTTON_LEFT or mouse_button > MOUSE_BUTTON_XBUTTON2:
			return null
		return make_mouse_button(mouse_button)
	if event is InputEventJoypadButton:
		var joy_button: JoyButton = (event as InputEventJoypadButton).button_index
		if joy_button < 0 or joy_button >= JOY_BUTTON_SDL_MAX:
			return null
		return make_joy_button(joy_button)
	if event is InputEventJoypadMotion:
		var motion: InputEventJoypadMotion = event
		if motion.axis < 0 or motion.axis >= JOY_AXIS_SDL_MAX or absf(motion.axis_value) < axis_activation:
			return null
		return make_joy_axis(motion.axis, signf(motion.axis_value))
	return null


## Identifiant entier unique d'un événement canonique (sert à détecter les conflits en temps
## constant), ou -1 pour un événement non liable.
static func binding_key(event: InputEvent) -> int:
	if event is InputEventKey:
		return (_KIND_KEY << _KIND_SHIFT) | int((event as InputEventKey).physical_keycode)
	if event is InputEventMouseButton:
		return (_KIND_MOUSE_BUTTON << _KIND_SHIFT) | int((event as InputEventMouseButton).button_index)
	if event is InputEventJoypadButton:
		return (_KIND_JOY_BUTTON << _KIND_SHIFT) | int((event as InputEventJoypadButton).button_index)
	if event is InputEventJoypadMotion:
		var motion: InputEventJoypadMotion = event
		return (_KIND_JOY_AXIS << _KIND_SHIFT) | (int(motion.axis) << 1) | (1 if motion.axis_value > 0.0 else 0)
	return -1


## Famille d'appareil d'un événement : clavier et souris, ou manette.
static func family_of(event: InputEvent) -> Family:
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventMouseMotion:
		return Family.KEYBOARD_MOUSE
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		return Family.GAMEPAD
	return Family.NONE


static func make_key(physical_keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = physical_keycode
	event.device = ALL_DEVICES
	return event


static func make_mouse_button(button: MouseButton) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.device = ALL_DEVICES
	return event


static func make_joy_button(button: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.device = ALL_DEVICES
	return event


static func make_joy_axis(axis: JoyAxis, direction: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = 1.0 if direction > 0.0 else -1.0
	event.device = ALL_DEVICES
	return event


static func _read_index(data: Dictionary, key: String, min_value: int, max_value: int, errors: Array[String]) -> int:
	var value: Variant = data.get(key)
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		errors.append("« %s » manquant ou non numérique" % key)
		return -1
	var number: float = float(value)
	if number != roundf(number) or number < min_value or number > max_value:
		errors.append("« %s » doit être un entier entre %d et %d" % [key, min_value, max_value])
		return -1
	return int(number)
