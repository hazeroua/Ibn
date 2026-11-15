extends SceneTree
## Construit res://world/jeu/jeu.tscn : la scène de jeu qui contient la carte « collines » (construite avant
## par build_collines.gd) sous la racine GameSession. Jamais modifiée à la main.

const MAP_PATH: String = "res://world/collines/collines.tscn"
const OUTPUT_PATH: String = "res://world/jeu/jeu.tscn"


func _initialize() -> void:
	quit(_build())


func _build() -> int:
	var map_scene: PackedScene = load(MAP_PATH) as PackedScene
	if map_scene == null:
		push_error("build_jeu : %s absente (lancer build_collines.gd d'abord)." % MAP_PATH)
		return 1
	var root := GameSession.new()
	root.name = "Jeu"
	var map: Node = map_scene.instantiate()
	map.name = GameSession.MAP_NODE
	root.add_child(map)
	map.owner = root
	var packed := PackedScene.new()
	var err: Error = packed.pack(root)
	root.free()
	if err != OK:
		push_error("build_jeu : échec de l'empaquetage (%s)." % error_string(err))
		return 1
	err = ResourceSaver.save(packed, OUTPUT_PATH)
	if err != OK:
		push_error("build_jeu : impossible d'enregistrer %s (%s)." % [OUTPUT_PATH, error_string(err)])
		return 1
	print("Scène construite : %s" % OUTPUT_PATH)
	return 0
