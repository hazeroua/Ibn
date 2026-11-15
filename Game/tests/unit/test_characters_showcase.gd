extends GutTest
## Vitrine du personnage et test de charge du pire cas : la foule animée, toutes copies actives en même temps.

const DATA_PATH: String = "res://data/vitrine_personnage/vitrine_personnage.json"
const CHARACTER_ID: String = "ibn_khaldoun_jeune"
const FRAME_STEP_S: float = 1.0 / 60.0

var _manifest: Dictionary = {}


func before_all() -> void:
	_manifest = CharacterCatalog.load_manifest()


func _load_test_config() -> Dictionary:
	return JsonData.get_dictionary(_manifest, "load_test", "characters.json")


func test_builds_expected_nodes_from_data() -> void:
	var data: Dictionary = JsonData.load_dictionary(DATA_PATH)
	var root: Node3D = VitrinePersonnageBuilder.build(data)
	assert_not_null(root.get_node_or_null("Environment"))
	assert_not_null(root.get_node_or_null("Sun"))
	assert_not_null(root.get_node_or_null("Ground"))
	var camera: Camera3D = root.get_node_or_null("Camera")
	assert_not_null(camera)
	assert_true(camera.current)
	var crowd: Dictionary = data["crowd"]
	var expected: int = (data["characters"] as Array).size() + int(crowd["columns"]) * int(crowd["rows"])
	var characters: Node3D = root.get_node("Characters")
	assert_eq(characters.get_child_count(), expected)
	for child: Node in characters.get_children():
		assert_eq(child.owner, root, "%s doit appartenir à la scène pour être enregistré" % child.name)
		assert_eq(child.scene_file_path, CharacterCatalog.scene_path(CHARACTER_ID))
		assert_eq(child.get_child_count(), 2, "Rig et AnimationPlayer de la copie")
		assert_ne(child.get_child(0).owner, root, "les nœuds internes d'une copie ne sont pas enregistrés dans la scène")
	root.free()


func test_viewpoints_cover_required_angles() -> void:
	var points: Array[Viewpoint] = Viewpoints.load_file("res://data/vitrine_personnage/viewpoints.json")
	var ids := PackedStringArray()
	for point: Viewpoint in points:
		ids.append(point.id)
	for required: String in ["vue_face", "vue_trois_quarts", "vue_profil", "vue_dos", "vue_portrait", "vue_foule"]:
		assert_true(ids.has(required), "point de vue « %s » attendu" % required)


func test_copies_share_one_mesh_material_and_animation_library() -> void:
	var scene: PackedScene = CharacterCatalog.load_scene(CHARACTER_ID)
	var first: Node3D = scene.instantiate() as Node3D
	var second: Node3D = scene.instantiate() as Node3D
	add_child_autofree(first)
	add_child_autofree(second)
	var mesh_a: MeshInstance3D = first.find_children("*", "MeshInstance3D", true, false)[0]
	var mesh_b: MeshInstance3D = second.find_children("*", "MeshInstance3D", true, false)[0]
	assert_same(mesh_a.mesh, mesh_b.mesh)
	assert_same(mesh_a.mesh.surface_get_material(0), mesh_b.mesh.surface_get_material(0))
	var library_a: AnimationLibrary = CharacterCatalog.find_animation_player(first).get_animation_library(&"locomotion")
	var library_b: AnimationLibrary = CharacterCatalog.find_animation_player(second).get_animation_library(&"locomotion")
	assert_same(library_a, library_b)


func test_worst_case_crowd_animation_cost() -> void:
	# Pire cas : la foule maximale prévue du manifeste, toutes en course (l'animation la plus chargée en mouvement),
	# images successives à 60 i/s, sans aucun arrêt ni partage de calcul entre copies.
	var config: Dictionary = _load_test_config()
	var count: int = JsonData.get_int(config, "instances", "load_test")
	var frames: int = JsonData.get_int(config, "frames", "load_test")
	var p50_max: float = JsonData.get_float(config, "advance_ms_p50_max", "load_test")
	var p99_max: float = JsonData.get_float(config, "advance_ms_p99_max", "load_test")
	var memory_growth_max_kb: float = JsonData.get_float(config, "static_memory_growth_kb_max", "load_test")
	var scene: PackedScene = CharacterCatalog.load_scene(CHARACTER_ID)
	var players: Array[AnimationPlayer] = []
	var build_start: int = Time.get_ticks_usec()
	var holder := Node3D.new()
	add_child_autofree(holder)
	for i: int in count:
		var instance: Node3D = scene.instantiate() as Node3D
		holder.add_child(instance)
		instance.position = Vector3(float(i % 10) * 1.2, 0.0, float(i / 10) * 1.5)
		var player: AnimationPlayer = CharacterCatalog.find_animation_player(instance)
		player.play(&"locomotion/run")
		player.seek(float(i) * 0.037, true)
		player.pause()
		players.append(player)
	var build_ms: float = float(Time.get_ticks_usec() - build_start) / 1000.0
	for warmup: int in 10:
		for player: AnimationPlayer in players:
			player.advance(FRAME_STEP_S)
	var memory_before: float = float(OS.get_static_memory_usage())
	var timings := PackedFloat64Array()
	timings.resize(frames)
	for frame: int in frames:
		var start: int = Time.get_ticks_usec()
		for player: AnimationPlayer in players:
			player.advance(FRAME_STEP_S)
		timings[frame] = float(Time.get_ticks_usec() - start) / 1000.0
	var growth_kb: float = (float(OS.get_static_memory_usage()) - memory_before) / 1024.0
	timings.sort()
	var p50: float = timings[frames / 2]
	var p99: float = timings[int(float(frames) * 0.99)]
	gut.p(
		(
			"%d personnages : instanciation %.1f ms ; avance des animations par image p50 %.3f ms, p99 %.3f ms ; mémoire +%.1f Ko"
			% [count, build_ms, p50, p99, growth_kb]
		)
	)
	PerfCheck.under(self, p50, p50_max, "médiane de l'avance des animations")
	PerfCheck.under(self, p99, p99_max, "99e centile de l'avance des animations")
	assert_lt(growth_kb, memory_growth_max_kb, "aucune allocation par image dans l'avance des animations")
