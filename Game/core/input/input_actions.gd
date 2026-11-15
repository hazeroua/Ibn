class_name InputActions
extends RefCounted
## Lecture du catalogue des actions d'entrée (res://data/input/actions.json) et déclaration des
## actions dans l'InputMap de Godot.
##
## Les touches du clavier sont désignées par leur position physique (« W » est la touche Z d'un
## clavier AZERTY) : les contrôles sont les mêmes quelle que soit la disposition du clavier.
## Une erreur dans le catalogue est une erreur du jeu (push_error, le pipeline échoue).

const CONTEXT: String = "actions d'entrée"
## Nombre maximal de contextes (un bit chacun dans InputActionBinding.context_mask).
const MAX_CONTEXTS: int = 62


## Lit les actions du catalogue, dans l'ordre du fichier.
static func parse(data: Dictionary) -> Array[InputActionBinding]:
	var result: Array[InputActionBinding] = []
	var context_bits: Dictionary[String, int] = _parse_contexts(data)
	var names: Dictionary[StringName, bool] = {}
	for raw: Variant in JsonData.get_array(data, "actions", CONTEXT):
		if typeof(raw) != TYPE_DICTIONARY:
			push_error("InputActions : chaque action doit être un objet.")
			continue
		var entry: Dictionary = raw
		var action_name: String = JsonData.get_string(entry, "name", CONTEXT)
		if action_name.is_empty():
			continue
		var id := StringName(action_name)
		if names.has(id):
			push_error("InputActions : action « %s » déclarée deux fois." % action_name)
			continue
		names[id] = true
		var deadzone: float = JsonData.get_float(entry, "deadzone", action_name)
		if deadzone < 0.0 or deadzone > 1.0:
			push_error("InputActions : zone morte de « %s » hors de [0, 1]." % action_name)
			deadzone = clampf(deadzone, 0.0, 1.0)
		var binding := InputActionBinding.new(id, _parse_mask(entry, context_bits, action_name), deadzone)
		var keys: Dictionary[int, bool] = {}
		for event_data: Variant in JsonData.get_array(entry, "events", action_name):
			var errors: Array[String] = []
			var event: InputEvent = InputEventCodec.from_data(event_data, errors)
			if event == null:
				push_error("InputActions : « %s » : %s." % [action_name, ", ".join(errors)])
				continue
			var key: int = InputEventCodec.binding_key(event)
			if keys.has(key):
				push_error("InputActions : « %s » : même touche déclarée deux fois." % action_name)
				continue
			keys[key] = true
			binding.events.append(event)
		result.append(binding)
	return result


## Déclare (ou remplace) l'action dans l'InputMap et relâche son état : une action redéfinie
## alors qu'elle était maintenue ne reste jamais « appuyée ».
static func apply_binding(binding: InputActionBinding) -> void:
	if InputMap.has_action(binding.action):
		Input.action_release(binding.action)
		InputMap.erase_action(binding.action)
	InputMap.add_action(binding.action, binding.deadzone)
	for event: InputEvent in binding.events:
		InputMap.action_add_event(binding.action, event)
	Input.action_release(binding.action)


## Lit le catalogue et déclare toutes ses actions ; renvoie le nombre d'actions déclarées.
static func apply(data: Dictionary) -> int:
	var bindings: Array[InputActionBinding] = parse(data)
	for binding: InputActionBinding in bindings:
		apply_binding(binding)
	return bindings.size()


static func _parse_contexts(data: Dictionary) -> Dictionary[String, int]:
	var bits: Dictionary[String, int] = {}
	for raw: Variant in JsonData.get_array(data, "contexts", CONTEXT):
		if typeof(raw) != TYPE_STRING or bits.has(raw):
			push_error("InputActions : « contexts » doit contenir des noms uniques.")
			continue
		if bits.size() >= MAX_CONTEXTS:
			push_error("InputActions : plus de %d contextes." % MAX_CONTEXTS)
			break
		var context_name: String = raw
		bits[context_name] = 1 << bits.size()
	return bits


static func _parse_mask(entry: Dictionary, context_bits: Dictionary[String, int], action_name: String) -> int:
	var mask: int = 0
	for raw: Variant in JsonData.get_array(entry, "contexts", action_name):
		if typeof(raw) != TYPE_STRING or not context_bits.has(raw):
			push_error("InputActions : « %s » : contexte inconnu « %s »." % [action_name, str(raw)])
			continue
		var context_name: String = raw
		mask |= context_bits[context_name]
	if mask == 0:
		push_error("InputActions : « %s » doit appartenir à au moins un contexte." % action_name)
	return mask
