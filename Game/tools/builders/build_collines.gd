extends SceneTree
## Construit res://world/collines/collines.tscn à partir de res://data/collines/collines.json.
## Lancé par Scripts/Pipeline/construire.ps1 ; la scène produite n'est jamais modifiée à la main.
## Les maillages, la carte de hauteurs et les cartes de contrôle du terrain sont écrits à côté, dans world/collines/.

const DATA_PATH: String = "res://data/collines/collines.json"
const OUTPUT_PATH: String = "res://world/collines/collines.tscn"


func _initialize() -> void:
	quit(_build())


func _build() -> int:
	var start: int = Time.get_ticks_usec()
	var data: Dictionary = JsonData.load_dictionary(DATA_PATH)
	if data.is_empty():
		return 1
	var world: Node3D = CollinesBuilder.build(data)
	if world.get_node_or_null("Terrain") == null or world.get_node_or_null("Obstacles") == null:
		world.free()
		push_error("build_collines : la carte n'a pas pu être assemblée (voir les erreurs ci-dessus).")
		return 1
	if not CollinesBuilder.persist_terrain(world, data):
		world.free()
		return 1
	var packed := PackedScene.new()
	var err: Error = packed.pack(world)
	world.free()
	if err != OK:
		push_error("build_collines : échec de l'empaquetage de la scène (%s)." % error_string(err))
		return 1
	err = ResourceSaver.save(packed, OUTPUT_PATH)
	if err != OK:
		push_error("build_collines : impossible d'enregistrer %s (%s)." % [OUTPUT_PATH, error_string(err)])
		return 1
	print("Scène construite : %s en %.1f s" % [OUTPUT_PATH, float(Time.get_ticks_usec() - start) / 1000000.0])
	return 0
