extends GutTest
## Sifflet : chemin A* sur tout le Sahara (4 km, vrai terrain construit), sans traverser falaises ni pentes
## trop raides, Barq qui vient et s'arrête à portée de monte. Pire cas : appel depuis l'autre bout du monde.

const SAHARA_PATH: String = "res://data/sahara/sahara.json"
const HORSE_PATH: String = "res://data/horse/horse.json"


## Relief du Sahara construit (generated/sahara/terrain), lu par Terrain3D comme en jeu.
func _field() -> HorseGround:
	var data: Dictionary = JsonData.load_dictionary(SAHARA_PATH)
	var settings: SaharaSettings = SaharaSettings.from_dictionary(data["generation"])
	var terrain := Terrain3D.new()
	terrain.free_editor_textures = false
	terrain.vertex_spacing = settings.vertex_spacing_meters
	terrain.data_directory = SaharaBuilder.TERRAIN_DIR
	add_child_autofree(terrain)
	return HorseGround.new(terrain, settings.half_extent(), settings.base_height_meters)


func test_grid_and_cross_map_path_avoid_cliffs_and_deep_water() -> void:
	var field: HorseGround = _field()
	var settings: Dictionary = JsonData.load_dictionary(HORSE_PATH)
	var finder := HorseCallPath.new()
	var started: int = Time.get_ticks_usec()
	finder.prepare(field, settings)
	finder.request(Vector3(-1900.0, 0.0, -1900.0), Vector3(1900.0, 0.0, 1900.0))
	assert_true(finder.wait())
	var elapsed_ms: float = float(Time.get_ticks_usec() - started) / 1000.0
	gut.p(
		(
			"Pire cas sifflet : grille 4 km + chemin d'un coin à l'autre en %.0f ms (fil de travail), %d points"
			% [elapsed_ms, finder.path.size()]
		)
	)
	assert_true(finder.is_grid_ready())
	assert_gt(finder.path.size(), 1)
	var call: Dictionary = settings["call"]
	var max_wade: float = float(call["max_wade_depth_m"])
	var cell: float = float(call["grid_cell_m"])
	# Chaque segment, échantillonné à la case, reste praticable : pas d'eau profonde, pas de case exclue.
	for index: int in range(1, finder.path.size()):
		var a: Vector3 = finder.path[index - 1]
		var b: Vector3 = finder.path[index]
		var samples: int = maxi(ceili(a.distance_to(b) / cell), 1)
		for k: int in samples + 1:
			var p: Vector3 = a.lerp(b, float(k) / float(samples))
			assert_lte(field.water_depth_at(p.x, p.z), max_wade + 0.05)
			assert_true(finder.is_walkable_cell(finder.cell_of(p)), "segment %d praticable" % index)
	var end: Vector3 = finder.path[finder.path.size() - 1]
	assert_lt(Vector2(end.x - 1900.0, end.z - 1900.0).length(), cell * 8.0)


func test_called_horse_comes_and_stops_at_mount_range() -> void:
	var world := Node3D.new()
	add_child_autofree(world)
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400.0, 1.0, 400.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	ground.add_child(shape)
	world.add_child(ground)
	var horse := HorseController.new(null)
	world.add_child(horse)
	var player := Node3D.new()
	world.add_child(player)
	player.position = Vector3(60.0, 0.0, 40.0)
	await get_tree().physics_frame
	horse.call_to_node(player)
	for index: int in 2400:
		if not horse.is_called:
			break
		await get_tree().physics_frame
	var settings: Dictionary = JsonData.load_dictionary(HORSE_PATH)
	var gap: float = Vector2(horse.global_position.x - 60.0, horse.global_position.z - 40.0).length()
	assert_false(horse.is_called, "Barq est arrivé")
	assert_lte(gap, float(settings["call"]["arrival_distance_m"]) + 0.6)
	assert_lte(gap, float(settings["rider"]["mount_range_m"]), "à portée de monte")
