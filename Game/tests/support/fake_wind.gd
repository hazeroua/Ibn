extends Node
## Doublure de Wind : force de base réglable.

var _base_strength: float = 0.3


func set_base_strength(value: float) -> void:
	_base_strength = clampf(value, 0.0, 1.0)


func get_base_strength() -> float:
	return _base_strength
