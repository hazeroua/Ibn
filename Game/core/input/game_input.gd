extends Node
## Singleton « GameInput » : déclare les actions d'entrée au démarrage et gère la sortie du jeu.

const ACTIONS_PATH: String = "res://data/input/actions.json"


func _enter_tree() -> void:
	InputActions.apply(JsonData.load_dictionary(ACTIONS_PATH))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"quit_game"):
		get_tree().quit()
