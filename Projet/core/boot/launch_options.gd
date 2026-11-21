class_name LaunchOptions
extends RefCounted
## Options de lancement lues après « -- » sur la ligne de commande.
## Exemple : IbnKhaldoun.exe -- --measure --scene=terrain_test --duration=30 --report-dir=C:/rapports

const MIN_DURATION_SECONDS: float = 5.0
const DEFAULT_DURATION_SECONDS: float = 30.0
const DEFAULT_WARMUP_SECONDS: float = 5.0

## Identifiant de scène du catalogue data/config/boot.json ; vide = scène par défaut.
var scene_id: String = ""
## Mode mesure : parcours automatique, rapport JSON, capture, puis fermeture.
var measure: bool = false
var duration_seconds: float = DEFAULT_DURATION_SECONDS
var warmup_seconds: float = DEFAULT_WARMUP_SECONDS
var report_dir: String = ""
var errors: PackedStringArray = PackedStringArray()


static func parse(arguments: PackedStringArray) -> LaunchOptions:
	var options: LaunchOptions = LaunchOptions.new()
	for argument: String in arguments:
		if argument == "--measure":
			options.measure = true
		elif argument.begins_with("--scene="):
			options.scene_id = argument.trim_prefix("--scene=")
		elif argument.begins_with("--duration="):
			options.duration_seconds = options._parse_seconds(argument, "--duration=", MIN_DURATION_SECONDS)
		elif argument.begins_with("--warmup="):
			options.warmup_seconds = options._parse_seconds(argument, "--warmup=", 0.0)
		elif argument.begins_with("--report-dir="):
			options.report_dir = argument.trim_prefix("--report-dir=").trim_prefix('"').trim_suffix('"')
		else:
			options.errors.append("Argument de lancement inconnu : " + argument)
	if options.measure and options.report_dir.is_empty():
		options.errors.append("Le mode --measure exige --report-dir=<dossier>.")
	if not options.measure and not options.report_dir.is_empty():
		options.errors.append("--report-dir n'a de sens qu'avec --measure.")
	return options


func _parse_seconds(argument: String, prefix: String, minimum: float) -> float:
	var text: String = argument.trim_prefix(prefix)
	if not text.is_valid_float():
		errors.append("Durée invalide : " + argument)
		return minimum
	var seconds: float = text.to_float()
	if seconds < minimum:
		errors.append("%s doit valoir au moins %.0f s." % [prefix.trim_suffix("="), minimum])
		return minimum
	return seconds
