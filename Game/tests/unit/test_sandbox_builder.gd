extends GutTest
## Construction du bac à sable à partir des données (textures Poly Haven importées au préalable par le pipeline).

const DATA_PATH: String = "res://data/sandbox/sandbox.json"


func _load_data() -> Dictionary:
	return JsonData.load_dictionary(DATA_PATH)


func test_builds_expected_nodes_from_data() -> void:
	var data: Dictionary = _load_data()
	var root: Node3D = SandboxBuilder.build(data)
	assert_not_null(root.get_node_or_null("Environment"))
	assert_not_null(root.get_node_or_null("Sun"))
	assert_not_null(root.get_node_or_null("Ground"))
	var camera: Camera3D = root.get_node_or_null("Camera")
	assert_not_null(camera)
	assert_true(camera is FreeCamera)
	var objects: Node3D = root.get_node("Objects")
	assert_eq(objects.get_child_count(), (data["objects"] as Array).size())
	for child: Node in root.get_children():
		assert_eq(child.owner, root, "%s doit appartenir à la scène pour être enregistré" % child.name)
	root.free()


func test_identical_objects_share_mesh_and_material() -> void:
	var data: Dictionary = _load_data()
	data["objects"] = [
		{"id": "a", "shape": "box", "size": [1.0, 1.0, 1.0], "position": [0.0, 0.5, 0.0], "color": "#b8322a"},
		{"id": "b", "shape": "box", "size": [1.0, 1.0, 1.0], "position": [2.0, 0.5, 0.0], "color": "#b8322a"},
		{"id": "c", "shape": "box", "size": [1.0, 2.0, 1.0], "position": [4.0, 1.0, 0.0], "color": "#2a6bb8"},
	]
	var root: Node3D = SandboxBuilder.build(data)
	var a: MeshInstance3D = root.get_node("Objects/a")
	var b: MeshInstance3D = root.get_node("Objects/b")
	var c: MeshInstance3D = root.get_node("Objects/c")
	assert_same(a.mesh, b.mesh)
	assert_same(a.material_override, b.material_override)
	assert_ne(a.mesh, c.mesh)
	assert_ne(a.material_override, c.material_override)
	root.free()


func test_worst_case_many_objects_share_resources() -> void:
	# Pire cas : 2 000 objets de 4 tailles et 4 couleurs → 4 maillages et 4 matériaux seulement.
	var data: Dictionary = _load_data()
	var colors: PackedStringArray = ["#b8322a", "#2a6bb8", "#c69c5d", "#3f8f4a"]
	var objects: Array = []
	for i: int in 2000:
		var side: float = 0.5 + float(i % 4) * 0.5
		(
			objects
			. append(
				{
					"id": "objet_%d" % i,
					"shape": "box",
					"size": [side, side, side],
					"position": [float(i % 50) * 2.0, side * 0.5, float(i / 50) * 2.0],
					"color": colors[(i / 4) % 4],
				}
			)
		)
	data["objects"] = objects
	var start: int = Time.get_ticks_usec()
	var root: Node3D = SandboxBuilder.build(data)
	var elapsed_ms: float = float(Time.get_ticks_usec() - start) / 1000.0
	var meshes: Dictionary = {}
	var materials: Dictionary = {}
	for child: Node in root.get_node("Objects").get_children():
		var instance: MeshInstance3D = child
		meshes[instance.mesh.get_instance_id()] = true
		materials[instance.material_override.get_instance_id()] = true
	assert_eq(root.get_node("Objects").get_child_count(), 2000)
	assert_eq(meshes.size(), 4)
	assert_eq(materials.size(), 4)
	gut.p("2 000 objets construits en %.1f ms" % elapsed_ms)
	root.free()


func test_project_sandbox_has_the_red_cube() -> void:
	# Critère de fin du MVP 0 : le deuxième cube rouge, ajouté uniquement par les données.
	var root: Node3D = SandboxBuilder.build(_load_data())
	var cube: MeshInstance3D = root.get_node_or_null("Objects/cube_rouge")
	assert_not_null(cube)
	var material: StandardMaterial3D = cube.material_override
	assert_eq(material.albedo_color.to_html(false), "b8322a")
	var ocre: MeshInstance3D = root.get_node("Objects/cube_ocre")
	assert_same(cube.mesh, ocre.mesh, "même taille : même maillage partagé")
	root.free()
