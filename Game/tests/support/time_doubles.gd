class_name TimeDoubles
extends RefCounted
## Doublures des autoloads DayNight, Seasons et Wind : elles exposent les méthodes publiques du contrat (Docs/contrats-mvp-2.md).

const DAY_NIGHT_SCRIPT: GDScript = preload("res://tests/support/fake_day_night.gd")
const SEASONS_SCRIPT: GDScript = preload("res://tests/support/fake_seasons.gd")
const WIND_SCRIPT: GDScript = preload("res://tests/support/fake_wind.gd")


## Ajoute une doublure sous /root avec le nom d'un autoload ; renvoie null si un vrai autoload porte déjà ce nom.
static func install(tree: SceneTree, script: GDScript, node_name: StringName) -> Node:
	if tree.root.has_node(NodePath(node_name)):
		return null
	var node: Node = script.new()
	node.name = node_name
	tree.root.add_child(node)
	return node
