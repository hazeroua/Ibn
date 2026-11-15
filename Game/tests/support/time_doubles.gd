class_name TimeDoubles
extends RefCounted
## Doublures des autoloads DayNight, Seasons et Wind : elles exposent les méthodes publiques du contrat (Docs/contrats-mvp-2.md).

const DAY_NIGHT_SCRIPT: GDScript = preload("res://tests/support/fake_day_night.gd")
const SEASONS_SCRIPT: GDScript = preload("res://tests/support/fake_seasons.gd")
const WIND_SCRIPT: GDScript = preload("res://tests/support/fake_wind.gd")


## Ajoute une doublure sous /root avec le nom d'un autoload ; renvoie null si un vrai autoload porte déjà ce nom.
static func install(tree: SceneTree, script: GDScript, node_name: StringName) -> Node:
	var replaced: Node = tree.root.get_node_or_null(NodePath(node_name))
	if replaced != null:
		tree.root.remove_child(replaced)
	var node: Node = script.new()
	node.name = node_name
	node.set_meta(&"replaced", replaced)
	tree.root.add_child(node)
	return node


## Retire la doublure et remet en place le vrai service qu'elle avait remplacé (autoload du jeu).
static func uninstall(tree: SceneTree, node: Node) -> void:
	if node == null:
		return
	var replaced: Node = node.get_meta(&"replaced", null)
	tree.root.remove_child(node)
	node.free()
	if replaced != null:
		tree.root.add_child(replaced)
