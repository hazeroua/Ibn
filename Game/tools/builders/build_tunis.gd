extends SceneTree
## Construit la racine runtime ; la géométrie reste exclusivement décrite dans les JSON.

const OUTPUT_PATH: String = "res://world/tunis/tunis.tscn"


func _initialize() -> void:
	quit(_build())


func _build() -> int:
	if TunisCellProvider.create() == null:
		return 1
	var root := TunisRuntime.new()
	root.name = "Tunis"
	var packed := PackedScene.new()
	var error: Error = packed.pack(root)
	root.free()
	if error == OK:
		error = ResourceSaver.save(packed, OUTPUT_PATH, ResourceSaver.FLAG_OMIT_EDITOR_PROPERTIES)
	if error == OK:
		error = _remove_ephemeral_node_ids()
	if error != OK:
		push_error("build_tunis: échec : %s." % error_string(error))
		return 1
	print("Scène construite : " + OUTPUT_PATH)
	return 0


func _remove_ephemeral_node_ids() -> Error:
	var input := FileAccess.open(OUTPUT_PATH, FileAccess.READ)
	if input == null:
		return FileAccess.get_open_error()
	var source := input.get_as_text()
	input.close()
	var pattern := RegEx.new()
	var compile_error: Error = pattern.compile(" unique_id=[0-9]+")
	if compile_error != OK:
		return compile_error
	var normalized := pattern.sub(source, "", true)
	var output := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if output == null:
		return FileAccess.get_open_error()
	output.store_string(normalized)
	output.close()
	return OK
