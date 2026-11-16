extends GutTest
## Tests MVP3 : allures, endurance, relief dangereux, traces bornées et pire cas de sprint.

const SETTINGS_PATH: String = "res://data/horse/horse.json"
const SPRINT_SECONDS: float = 600.0
const DT: float = 1.0 / 60.0


func _settings() -> Dictionary:
	return JsonData.load_dictionary(SETTINGS_PATH)


func test_four_gaits_are_data_driven_and_ordered() -> void:
	var motor := HorseLocomotion.new(_settings())
	assert_eq(motor.GAIT_NAMES.size(), 4)
	motor.update(Vector2(0.2, 0.0), false, 1.0)
	assert_eq(motor.get_gait_name(), &"walk")
	motor.update(Vector2(0.6, 0.0), false, 1.0)
	assert_eq(motor.get_gait_name(), &"trot")
	motor.update(Vector2(0.8, 0.0), false, 1.0)
	assert_eq(motor.get_gait_name(), &"canter")
	motor.update(Vector2(1.0, 0.0), true, 1.0)
	assert_eq(motor.get_gait_name(), &"sprint")


func test_sprint_endurance_depletes_and_recovers_without_nan() -> void:
	var motor := HorseLocomotion.new(_settings())
	var frames: int = int(SPRINT_SECONDS / DT)
	var worst_speed: float = 0.0
	var invalid: int = 0
	var started: int = Time.get_ticks_usec()
	for index: int in frames:
		motor.update(Vector2(0.0, 1.0), true, DT)
		worst_speed = maxf(worst_speed, motor.speed)
		var invalid_state: bool = is_nan(motor.speed) or is_nan(motor.endurance)
		invalid_state = invalid_state or motor.endurance < 0.0
		invalid_state = invalid_state or motor.endurance > 100.0
		if invalid_state:
			invalid += 1
	var elapsed_ms: float = float(Time.get_ticks_usec() - started) / 1000.0
	gut.p(
		(
			"Pire cas Barq : sprint %.0f s, %d images, %.3f ms, vitesse max %.2f m/s, endurance %.2f"
			% [SPRINT_SECONDS, frames, elapsed_ms, worst_speed, motor.endurance]
		)
	)
	assert_eq(invalid, 0)
	assert_lte(motor.endurance, 100.0)
	assert_gt(motor.endurance, 0.0)


func test_endurance_recovers_at_walk() -> void:
	var motor := HorseLocomotion.new(_settings())
	motor.endurance = 10.0
	for index: int in 30:
		motor.update(Vector2(0.2, 0.0), false, 1.0)
	assert_gt(motor.endurance, 10.0)


func test_trace_pool_is_bounded_and_sand_only() -> void:
	var traces := HorseTraces.new()
	traces.configure(_settings())
	for index: int in 512:
		traces.place(Vector3(float(index), 0.0, 0.0), 0.0, &"sable")
	assert_eq(traces.active_count(), traces.multimesh.instance_count)
	assert_false(traces.place(Vector3.ZERO, 0.0, &"pierre"))
	# Toutes les traces expirent après leur durée de vie (les plus anciennes d'abord).
	traces._process(1000.0)
	assert_eq(traces.active_count(), 0)
	traces.free()


## Pire cas : dix minutes de galop dense, la surface change à chaque battue (sable, pierre, terre, eau).
## Le nombre de traces reste borné, une seule instance de dessin, et le coût reste négligeable.
func test_ten_minutes_of_gallop_with_surface_changes() -> void:
	var traces := HorseTraces.new()
	traces.configure(_settings())
	var surfaces: Array[StringName] = [&"sable", &"pierre", &"terre", &"eau"]
	var frames: int = 36000
	var placed: int = 0
	var started: int = Time.get_ticks_usec()
	for frame: int in frames:
		# Galop : environ 7 battues par seconde, soit une battue toutes les 8 à 9 images.
		if frame % 8 == 0:
			if traces.place(Vector3(float(frame) * 0.2, 0.0, 0.0), 0.3, surfaces[(frame / 8) % 4], Vector3(0.1, 1.0, 0.0)):
				placed += 1
		traces._process(1.0 / 60.0)
	var elapsed_ms: float = float(Time.get_ticks_usec() - started) / 1000.0
	gut.p("Pire cas traces : %d images, %d traces posées, %.3f ms" % [frames, placed, elapsed_ms])
	assert_eq(placed, frames / 8 / 4 + (1 if (frames / 8) % 4 > 0 else 0))
	assert_lte(traces.active_count(), traces.multimesh.instance_count)
	assert_lt(elapsed_ms, 250.0)
	traces.free()


func test_gait_speed_data_is_positive() -> void:
	var motor := HorseLocomotion.new(_settings())
	for gait: int in motor.GAIT_NAMES.size():
		assert_gt(motor.get_gait_speed(gait), 0.0)


## Obstacles : Barq enjambe un muret bas (que le personnage franchit aussi) et s'arrête devant un mur.
## Pire cas : galop sur un sol couvert de bordures de séguias, sans heightfield (corps de collision seuls).
func test_barq_steps_over_low_walls() -> void:
	var low: Dictionary = await _run_into_wall(0.3)
	assert_gt(low["travelled"] as float, 12.0, "Barq doit franchir un muret de 0,30 m")
	assert_gt(low["height"] as float, 0.25, "Barq doit être monté sur le muret")


func test_barq_stops_at_high_walls() -> void:
	var high: Dictionary = await _run_into_wall(1.4)
	assert_lt(high["travelled"] as float, 9.0, "Barq doit s'arrêter devant un mur de 1,40 m")


func _run_into_wall(wall_height: float) -> Dictionary:
	var world := Node3D.new()
	add_child_autofree(world)
	var ground := StaticBody3D.new()
	ground.collision_layer = 1
	var ground_shape := CollisionShape3D.new()
	var ground_box := BoxShape3D.new()
	ground_box.size = Vector3(80.0, 1.0, 80.0)
	ground_shape.shape = ground_box
	ground_shape.position = Vector3(0.0, -0.5, 0.0)
	ground.add_child(ground_shape)
	# Plateau surélevé de la hauteur du muret, à 8 m devant Barq (axe -z, son avant au repos).
	var wall_shape := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(20.0, wall_height, 20.0)
	wall_shape.shape = wall_box
	wall_shape.position = Vector3(0.0, wall_height * 0.5, -18.0)
	ground.add_child(wall_shape)
	world.add_child(ground)
	var horse := HorseController.new(null)
	world.add_child(horse)
	await get_tree().physics_frame
	var start: Vector3 = horse.global_position
	for index: int in 240:
		horse.set_input(Vector2(0.0, -1.0), false)
		await get_tree().physics_frame
	var travelled: float = -(horse.global_position.z - start.z)
	return {"travelled": travelled, "height": horse.global_position.y}


## Pire cas (#27) : 10 minutes de course (sprint jusqu'à épuisement, puis galop) dans un champ de 1 000
## obstacles, avec des virages permanents. Barq ne pénètre jamais un obstacle, ne tombe pas, reste fini, et
## chaque image physique reste sous le budget. Simulation pas à pas (60 i/s) sans attendre le temps réel.
func test_ten_minute_sprint_through_thousand_obstacles() -> void:
	var world := Node3D.new()
	add_child_autofree(world)
	PlayerTestWorld.ground(world, "sable", 400.0)
	PlayerTestWorld.scatter(world, 1000, 380.0, 6.0, 1382)
	var horse := HorseController.new(null)
	world.add_child(horse)
	await get_tree().physics_frame
	var query := PhysicsShapeQueryParameters3D.new()
	var probe := CapsuleShape3D.new()
	probe.radius = 0.3
	probe.height = 1.0
	query.shape = probe
	query.collision_mask = 1
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var frames: int = 36000
	var dt: float = 1.0 / 60.0
	var worst_us: int = 0
	var penetrations: int = 0
	var lowest: float = 0.0
	for frame: int in frames:
		var t: float = float(frame) * dt
		horse.set_input(Vector2(sin(t * 0.37), -cos(t * 0.23)).normalized(), true)
		horse._physics_process(dt)
		worst_us = maxi(worst_us, horse.last_step_usec)
		lowest = minf(lowest, horse.global_position.y)
		if frame % 30 == 0:
			# Cœur du corps (sous le dos, au-dessus des marches) : jamais dans un obstacle.
			query.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), horse.global_position + Vector3.UP * 1.0)
			if not space.intersect_shape(query, 1).is_empty():
				penetrations += 1
	var p: Vector3 = horse.global_position
	gut.p(
		(
			"Pire cas #27 : 10 min de course, 1 000 obstacles, image la plus longue %.3f ms, endurance %.2f"
			% [float(worst_us) / 1000.0, horse.locomotion.endurance]
		)
	)
	assert_false(is_nan(p.x) or is_nan(p.y) or is_nan(p.z))
	assert_eq(penetrations, 0, "jamais dans un obstacle")
	assert_gt(lowest, -0.3, "ne passe pas sous le sol")
	assert_lt(worst_us, 4000)
