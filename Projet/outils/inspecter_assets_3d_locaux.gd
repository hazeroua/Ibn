extends SceneTree
## Inspecte des scenes 3D locales deja importees par Godot, sans executer de script tiers.

var _source_root := ""
var _report_path := ""


func _init() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--source-root="):
			_source_root = argument.trim_prefix("--source-root=")
		elif argument.begins_with("--report="):
			_report_path = argument.trim_prefix("--report=")
	if _source_root.is_empty() or _report_path.is_empty():
		push_error("Arguments requis : --source-root=res://... --report=/chemin/rapport.json")
		quit(2)
		return
	var directory := DirAccess.open(_source_root)
	if directory == null:
		push_error("Dossier source inaccessible : " + _source_root)
		quit(2)
		return
	var models: Array[Dictionary] = []
	for file_name: String in directory.get_files():
		if file_name.get_extension().to_lower() not in ["fbx", "glb", "gltf"]:
			continue
		models.append(_inspect_scene(_source_root.path_join(file_name), file_name))
	models.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.name < b.name)
	DirAccess.make_dir_recursive_absolute(_report_path.get_base_dir())
	var output := FileAccess.open(_report_path, FileAccess.WRITE)
	if output == null:
		push_error("Rapport impossible a ecrire : " + _report_path)
		quit(2)
		return
	output.store_string(JSON.stringify({"source_root": _source_root, "models": models}, "  "))
	output.close()
	quit(0)


func _inspect_scene(path: String, file_name: String) -> Dictionary:
	var packed := load(path) as PackedScene
	if packed == null:
		return {"name": file_name, "loadable": false}
	var root := packed.instantiate()
	var mesh_nodes := root.find_children("*", "MeshInstance3D", true, false)
	var triangles := 0
	var vertices := 0
	var surfaces := 0
	var materials: Array[String] = []
	var bounds := AABB()
	var has_bounds := false
	for node_value: Node in mesh_nodes:
		var mesh_node := node_value as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		var relative_transform := mesh_node.transform
		var parent := mesh_node.get_parent()
		while parent != root and parent is Node3D:
			relative_transform = (parent as Node3D).transform * relative_transform
			parent = parent.get_parent()
		var transformed_bounds: AABB = relative_transform * mesh_node.get_aabb()
		bounds = bounds.merge(transformed_bounds) if has_bounds else transformed_bounds
		has_bounds = true
		for surface_index: int in mesh_node.mesh.get_surface_count():
			surfaces += 1
			var arrays := mesh_node.mesh.surface_get_arrays(surface_index)
			var surface_vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
			var indices := arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
			vertices += surface_vertices.size()
			if mesh_node.mesh.surface_get_primitive_type(surface_index) == Mesh.PRIMITIVE_TRIANGLES:
				triangles += (indices.size() / 3 if not indices.is_empty() else surface_vertices.size() / 3)
			var material := mesh_node.mesh.surface_get_material(surface_index)
			materials.append(material.resource_name if material != null else "")
	var animation_count := 0
	for player_value: Node in root.find_children("*", "AnimationPlayer", true, false):
		var player := player_value as AnimationPlayer
		for library_name: StringName in player.get_animation_library_list():
			animation_count += (player.get_animation_library(library_name).get_animation_list().size())
	var report := {
		"name": file_name,
		"loadable": true,
		"mesh_nodes": mesh_nodes.size(),
		"surfaces": surfaces,
		"vertices": vertices,
		"triangles": triangles,
		"materials": materials,
		"animations": animation_count,
	}
	if has_bounds:
		report["aabb_position_m"] = [bounds.position.x, bounds.position.y, bounds.position.z]
		report["aabb_size_m"] = [bounds.size.x, bounds.size.y, bounds.size.z]
	root.free()
	return report
