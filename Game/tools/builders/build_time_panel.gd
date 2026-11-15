extends SceneTree
## Construit res://ui/time_panel/time_panel.tscn (racine TimePanel ; l'interface se compose à l'ouverture de la scène).

const OUTPUT_PATH: String = "res://ui/time_panel/time_panel.tscn"


func _init() -> void:
	var root := TimePanel.new()
	root.name = "TimePanel"
	var scene := PackedScene.new()
	var packed: Error = scene.pack(root)
	if packed != OK:
		push_error("build_time_panel : empaquetage impossible (%s)." % error_string(packed))
		quit(1)
		return
	var saved: Error = ResourceSaver.save(scene, OUTPUT_PATH)
	root.free()
	if saved != OK:
		push_error("build_time_panel : écriture impossible (%s)." % error_string(saved))
		quit(1)
		return
	quit(0)
