class_name CommandLine
extends RefCounted
## Analyse les arguments utilisateur passés après « -- » sur la ligne de commande de Godot.
##
## « --cle=valeur » donne {"cle": "valeur"} ; « --drapeau » donne {"drapeau": "true"}.


static func parse(args: PackedStringArray) -> Dictionary[String, String]:
	var result: Dictionary[String, String] = {}
	for arg: String in args:
		if not arg.begins_with("--") or arg.length() <= 2:
			push_error("CommandLine : argument invalide « %s » (format attendu : --cle=valeur)." % arg)
			continue
		var body: String = arg.substr(2)
		var separator: int = body.find("=")
		if separator < 0:
			result[body] = "true"
		else:
			result[body.substr(0, separator)] = body.substr(separator + 1)
	return result
