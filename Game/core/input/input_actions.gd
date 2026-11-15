class_name InputActions
extends RefCounted
## Déclare les actions d'entrée du jeu à partir d'un fichier de données.
##
## Les touches du clavier sont désignées par leur position physique (« W » est la touche Z d'un
## clavier AZERTY) : les contrôles sont les mêmes quelle que soit la disposition du clavier.

const CONTEXT: String = "actions d'entrée"


## Remplace les actions décrites dans data et renvoie le nombre d'actions déclarées.
static func apply(data: Dictionary) -> int:
	var count: int = 0
	var names: Dictionary[String, bool] = {}
	for raw: Variant in JsonData.get_array(data, "actions", CONTEXT):
		if typeof(raw) != TYPE_DICTIONARY:
			push_error("InputActions : chaque action doit être un objet.")
			continue
		var action: Dictionary = raw
		var action_name: String = JsonData.get_string(action, "name", CONTEXT)
		if action_name.is_empty():
			continue
		if names.has(action_name):
			push_error("InputActions : action « %s » déclarée deux fois." % action_name)
			continue
		names[action_name] = true
		var id := StringName(action_name)
		if InputMap.has_action(id):
			InputMap.erase_action(id)
		InputMap.add_action(id, JsonData.get_float_or(action, "deadzone", 0.2, action_name))
		for event_data: Variant in JsonData.get_array(action, "events", action_name):
			var event: InputEvent = _make_event(event_data, action_name)
			if event != null:
				InputMap.action_add_event(id, event)
		count += 1
	return count


static func _make_event(raw: Variant, action_name: String) -> InputEvent:
	if typeof(raw) != TYPE_DICTIONARY:
		push_error("InputActions : événement invalide pour « %s »." % action_name)
		return null
	var data: Dictionary = raw
	var kind: String = JsonData.get_string(data, "type", action_name)
	match kind:
		"key":
			var key_name: String = JsonData.get_string(data, "physical", action_name)
			var keycode: Key = OS.find_keycode_from_string(key_name)
			if keycode == KEY_NONE:
				push_error("InputActions : touche inconnue « %s » pour « %s »." % [key_name, action_name])
				return null
			var key_event := InputEventKey.new()
			key_event.physical_keycode = keycode
			return key_event
		"mouse_button":
			var mouse_event := InputEventMouseButton.new()
			mouse_event.button_index = JsonData.get_int(data, "button", action_name) as MouseButton
			return mouse_event
		"joy_button":
			var button_event := InputEventJoypadButton.new()
			button_event.button_index = JsonData.get_int(data, "button", action_name) as JoyButton
			return button_event
		"joy_axis":
			var axis_event := InputEventJoypadMotion.new()
			axis_event.axis = JsonData.get_int(data, "axis", action_name) as JoyAxis
			axis_event.axis_value = JsonData.get_float(data, "value", action_name)
			return axis_event
		_:
			push_error("InputActions : type d'événement inconnu « %s » pour « %s »." % [kind, action_name])
			return null
