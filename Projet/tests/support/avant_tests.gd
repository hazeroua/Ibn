extends GutHookScript
## Avant tous les tests GUT : actions clavier, souris et manette du jeu (data/config/input.json), comme au
## démarrage du jeu (core/boot/boot.gd). Le personnage et le cheval lisent ces actions.


func run() -> void:
	var bindings: InputBindings = InputBindings.from_dictionary(JsonData.load_dictionary("res://data/config/input.json"))
	for message: String in bindings.errors:
		push_error(message)
	bindings.apply()
