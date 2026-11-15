extends SceneTree
## Construit res://world/desert_jeu/desert_jeu.tscn : la scène de jeu du désert (racine DesertSession, qui assemble
## tout au chargement). Jamais modifiée à la main.

const OUTPUT_PATH: String = "res://world/desert_jeu/desert_jeu.tscn"


func _initialize() -> void:
	quit(_build())


func _build() -> int:
	var root := DesertSession.new()
	root.name = "DesertJeu"
	var packed := PackedScene.new()
	var err: Error = packed.pack(root)
	root.free()
	if err != OK:
		push_error("build_desert_jeu : échec de l'empaquetage (%s)." % error_string(err))
		return 1
	err = ResourceSaver.save(packed, OUTPUT_PATH)
	if err != OK:
		push_error("build_desert_jeu : impossible d'enregistrer %s (%s)." % [OUTPUT_PATH, error_string(err)])
		return 1
	print("Scène construite : %s" % OUTPUT_PATH)
	return 0
