extends SceneTree
## Construit res://world/desert/desert.tscn à partir de res://data/desert/desert.json.
## Lancé par Scripts/Pipeline/construire.ps1 ; la scène produite n'est jamais modifiée à la main.
## Les cellules de terrain sont construites au chargement de la scène (voir DesertTestTerrain) : aucun fichier annexe.

const DATA_PATH: String = "res://data/desert/desert.json"
const OUTPUT_PATH: String = "res://world/desert/desert.tscn"


func _initialize() -> void:
	quit(_build())


func _build() -> int:
	var start: int = Time.get_ticks_usec()
	var data: Dictionary = JsonData.load_dictionary(DATA_PATH)
	if data.is_empty():
		return 1
	var world: Node3D = DesertBuilder.build(data)
	if world.get_node_or_null("Terrain") == null:
		world.free()
		push_error("build_desert : la carte n'a pas pu être assemblée (voir les erreurs ci-dessus).")
		return 1
	var packed := PackedScene.new()
	var err: Error = packed.pack(world)
	world.free()
	if err != OK:
		push_error("build_desert : échec de l'empaquetage de la scène (%s)." % error_string(err))
		return 1
	err = ResourceSaver.save(packed, OUTPUT_PATH)
	if err != OK:
		push_error("build_desert : impossible d'enregistrer %s (%s)." % [OUTPUT_PATH, error_string(err)])
		return 1
	print("Scène construite : %s en %.1f s" % [OUTPUT_PATH, float(Time.get_ticks_usec() - start) / 1000000.0])
	return 0
