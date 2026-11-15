extends SceneTree
## Construit res://world/sandbox/sandbox.tscn à partir de res://data/sandbox/sandbox.json.
## Lancé par Scripts/Pipeline/construire.ps1 ; la scène produite n'est jamais modifiée à la main.

const DATA_PATH: String = "res://data/sandbox/sandbox.json"
const OUTPUT_PATH: String = "res://world/sandbox/sandbox.tscn"


func _initialize() -> void:
	quit(_build())


func _build() -> int:
	var data: Dictionary = JsonData.load_dictionary(DATA_PATH)
	if data.is_empty():
		return 1
	var root: Node3D = SandboxBuilder.build(data)
	var packed := PackedScene.new()
	var err: Error = packed.pack(root)
	root.free()
	if err != OK:
		push_error("build_sandbox : échec de l'empaquetage de la scène (%s)." % error_string(err))
		return 1
	err = ResourceSaver.save(packed, OUTPUT_PATH)
	if err != OK:
		push_error("build_sandbox : impossible d'enregistrer %s (%s)." % [OUTPUT_PATH, error_string(err)])
		return 1
	print("Scène construite : %s" % OUTPUT_PATH)
	return 0
