class_name InputBindings
extends RefCounted
## Actions de jeu lues dans data/config/input.json et enregistrées dans l'InputMap.
## Les touches sont des touches physiques : la même position sur AZERTY et QWERTY.

const MOUSE_BUTTONS: Dictionary = {
	"left": MOUSE_BUTTON_LEFT,
	"right": MOUSE_BUTTON_RIGHT,
	"middle": MOUSE_BUTTON_MIDDLE,
	"wheel_up": MOUSE_BUTTON_WHEEL_UP,
	"wheel_down": MOUSE_BUTTON_WHEEL_DOWN,
}


## Une action et les événements qui la déclenchent.
class Binding:
	extends RefCounted
	var action: StringName
	var deadzone: float = 0.2
	var events: Array[InputEvent] = []


var bindings: Array[Binding] = []
var errors: PackedStringArray = PackedStringArray()


static func from_dictionary(data: Dictionary) -> InputBindings:
	var result: InputBindings = InputBindings.new()
	var actions: Dictionary = JsonData.read_dictionary(data, "actions", result.errors, "input.json")
	for action_name: String in actions:
		var context: String = "input.json › " + action_name
		var description: Variant = actions[action_name]
		if typeof(description) != TYPE_DICTIONARY:
			result.errors.append(context + " : la description doit être un objet.")
			continue
		var binding: Binding = Binding.new()
		binding.action = StringName(action_name)
		binding.deadzone = JsonData.read_number(description, "deadzone", result.errors, context)
		var events: Variant = (description as Dictionary).get("events")
		if typeof(events) != TYPE_ARRAY or (events as Array).is_empty():
			result.errors.append(context + " : « events » doit être une liste non vide.")
			continue
		for event_data: Variant in events:
			var event: InputEvent = result._parse_event(event_data, context)
			if event != null:
				binding.events.append(event)
		result.bindings.append(binding)
	return result


## Remplace les actions concernées dans l'InputMap.
func apply() -> void:
	for binding: Binding in bindings:
		if InputMap.has_action(binding.action):
			InputMap.erase_action(binding.action)
		InputMap.add_action(binding.action, binding.deadzone)
		for event: InputEvent in binding.events:
			InputMap.action_add_event(binding.action, event)


## Retire les actions de l'InputMap (utilisé par les tests).
func remove() -> void:
	for binding: Binding in bindings:
		if InputMap.has_action(binding.action):
			InputMap.erase_action(binding.action)


func _parse_event(event_data: Variant, context: String) -> InputEvent:
	if typeof(event_data) != TYPE_DICTIONARY:
		errors.append(context + " : chaque événement doit être un objet.")
		return null
	var description: Dictionary = event_data
	var event_type: String = JsonData.read_string(description, "type", errors, context)
	match event_type:
		"key":
			var key_name: String = JsonData.read_string(description, "key", errors, context)
			var keycode: Key = OS.find_keycode_from_string(key_name)
			if keycode == KEY_NONE:
				errors.append("%s : touche inconnue « %s »." % [context, key_name])
				return null
			var key_event: InputEventKey = InputEventKey.new()
			key_event.physical_keycode = keycode
			return key_event
		"mouse_button":
			var button_name: String = JsonData.read_string(description, "button", errors, context)
			if not MOUSE_BUTTONS.has(button_name):
				errors.append("%s : bouton de souris inconnu « %s »." % [context, button_name])
				return null
			var mouse_event: InputEventMouseButton = InputEventMouseButton.new()
			mouse_event.button_index = MOUSE_BUTTONS[button_name]
			return mouse_event
		"joypad_button":
			var button_index: int = int(JsonData.read_number(description, "button", errors, context))
			if button_index < 0 or button_index >= JOY_BUTTON_SDL_MAX:
				errors.append("%s : bouton de manette invalide %d." % [context, button_index])
				return null
			var joy_button_event: InputEventJoypadButton = InputEventJoypadButton.new()
			joy_button_event.button_index = button_index as JoyButton
			return joy_button_event
		"joypad_axis":
			var axis: int = int(JsonData.read_number(description, "axis", errors, context))
			var direction: float = JsonData.read_number(description, "direction", errors, context)
			if axis < 0 or axis >= JOY_AXIS_SDL_MAX or absf(direction) != 1.0:
				errors.append("%s : axe de manette invalide (%d, %s)." % [context, axis, direction])
				return null
			var joy_axis_event: InputEventJoypadMotion = InputEventJoypadMotion.new()
			joy_axis_event.axis = axis as JoyAxis
			joy_axis_event.axis_value = direction
			return joy_axis_event
	errors.append("%s : type d'événement inconnu « %s »." % [context, event_type])
	return null
