class_name TunisWorldRuntime
extends TunisRuntime
## Initialise le runtime de #50 dans l'arbre avec le fournisseur décalé du désert.

var _world_provider: TunisWorldProvider


func prepare(provider: TunisWorldProvider) -> void:
	_world_provider = provider


func _ready() -> void:
	if _world_provider == null or not initialize(_world_provider):
		push_error("TunisWorldRuntime : impossible de charger la ville dans le désert.")
