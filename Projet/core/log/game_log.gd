class_name GameLog
extends RefCounted
## Journal du jeu : une ligne par événement, horodatée depuis le lancement.
## Les lignes sont écrites dans la sortie standard et dans user://logs/ibn.log
## (journalisation de Godot activée dans project.godot). Les erreurs passent par
## push_error pour faire échouer le pipeline de validation.


static func info(category: String, message: String) -> void:
	print(format_line("INFO", category, message))


static func warning(category: String, message: String) -> void:
	push_warning(format_line("AVERTISSEMENT", category, message))


static func error(category: String, message: String) -> void:
	push_error(format_line("ERREUR", category, message))


static func format_line(level: String, category: String, message: String) -> String:
	var seconds: float = float(Time.get_ticks_msec()) / 1000.0
	return "[%9.3f] [%s] [%s] %s" % [seconds, level, category, message]
