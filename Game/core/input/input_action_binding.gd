class_name InputActionBinding
extends RefCounted
## Touches d'une action : événements canoniques (voir InputEventCodec), zone morte et contextes
## (masque de bits : deux actions dont les masques se croisent sont actives en même temps).

var action: StringName
var context_mask: int = 0
var deadzone: float = 0.5
var events: Array[InputEvent] = []


func _init(action_name: StringName = &"", contexts: int = 0, action_deadzone: float = 0.5) -> void:
	action = action_name
	context_mask = contexts
	deadzone = action_deadzone


## Copie indépendante (les événements sont recopiés : modifier la copie ne change pas l'original).
func copy() -> InputActionBinding:
	var result := InputActionBinding.new(action, context_mask, deadzone)
	result.events.resize(events.size())
	for i: int in events.size():
		result.events[i] = events[i].duplicate() as InputEvent
	return result


## Vrai si les deux actions ont les mêmes touches, dans le même ordre, et la même zone morte.
func same_as(other: InputActionBinding) -> bool:
	if not is_equal_approx(deadzone, other.deadzone) or events.size() != other.events.size():
		return false
	for i: int in events.size():
		if InputEventCodec.binding_key(events[i]) != InputEventCodec.binding_key(other.events[i]):
			return false
	return true


## Position dans events de la touche liée key, ou -1.
func find_key(key: int) -> int:
	for i: int in events.size():
		if InputEventCodec.binding_key(events[i]) == key:
			return i
	return -1


## Position dans events de la n-ième touche (slot) de la famille donnée, ou -1.
func find_slot(family: InputEventCodec.Family, slot: int) -> int:
	var seen: int = 0
	for i: int in events.size():
		if InputEventCodec.family_of(events[i]) == family:
			if seen == slot:
				return i
			seen += 1
	return -1


## Nombre de touches de la famille donnée.
func family_count(family: InputEventCodec.Family) -> int:
	var count: int = 0
	for event: InputEvent in events:
		if InputEventCodec.family_of(event) == family:
			count += 1
	return count
