extends GutTest
## Caméra à la troisième personne : placement, collisions, suivi, fondu de la cible et test de charge.
##
## Chaque test construit sa propre scène (sol, couloir, recoin, plafond bas) et pilote une cible
## doublure (Node3D portant un maillage). La caméra est avancée image par image avec des durées
## d'image choisies par le test (20 à 240 images par seconde), sans lire aucune action d'entrée.
##
## Pires cas couverts : recoin (angle rentrant de deux murs sous un plafond bas) avec une cible qui
## tourne sur elle-même ; plafond plus bas que la tête ; cible au galop (15 m/s) et téléportée ;
## fréquence d'images variable de 20 à 240 i/s ; 1 000 objets avec collision autour de la cible.

const LAYER_WORLD: int = 1
const LAYER_PLAYER: int = 2
const LAYER_CAMERA_OBSTACLE: int = 4
## Couches que la caméra ne doit jamais traverser (1 et 4).
const BLOCKING_MASK: int = (1 << (LAYER_WORLD - 1)) | (1 << (LAYER_CAMERA_OBSTACLE - 1))
## Rayon du contrôle « caméra dans le décor » : plus grand que le plan proche, plus petit que la sonde.
const CAMERA_CLEARANCE: float = 0.1
const GALLOP_SPEED: float = 15.0
## Budget du test de charge : coût moyen d'une image de caméra (millisecondes), soit 1,5 % d'une
## image à 60 i/s, et 99e centile (les pics isolés du système d'exploitation ne sont pas comptés).
const LOAD_AVG_BUDGET_MS: float = 0.25
const LOAD_P99_BUDGET_MS: float = 1.0

var _world: Node3D = null
var _overlap_query: PhysicsShapeQueryParameters3D = null


func before_each() -> void:
	_world = Node3D.new()
	_world.name = "CameraTestWorld"
	add_child_autofree(_world)
	var sphere := SphereShape3D.new()
	sphere.radius = CAMERA_CLEARANCE
	_overlap_query = PhysicsShapeQueryParameters3D.new()
	_overlap_query.shape = sphere
	_overlap_query.collision_mask = BLOCKING_MASK


# --- Construction des scènes de test -------------------------------------------------------------


func _add_box(center: Vector3, size: Vector3, layer: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1 << (layer - 1)
	body.collision_mask = 0
	body.position = center
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	_world.add_child(body)
	return body


func _build_ground() -> void:
	_add_box(Vector3(0.0, -0.5, 0.0), Vector3(400.0, 1.0, 400.0), LAYER_WORLD)


## Couloir de 2 m de large (faces intérieures en x = ±1), 3 m sous plafond, le long de z.
func _build_corridor() -> void:
	_build_ground()
	_add_box(Vector3(-1.2, 1.5, 0.0), Vector3(0.4, 3.0, 80.0), LAYER_WORLD)
	_add_box(Vector3(1.2, 1.5, 0.0), Vector3(0.4, 3.0, 80.0), LAYER_WORLD)
	_add_box(Vector3(0.0, 3.15, 0.0), Vector3(2.8, 0.3, 80.0), LAYER_WORLD)


## Recoin : deux murs en angle rentrant (faces en z = 1 et x = -1) sous un plafond à 2,2 m.
func _build_corner() -> void:
	_build_ground()
	_add_box(Vector3(0.0, 1.5, 1.2), Vector3(6.0, 3.0, 0.4), LAYER_WORLD)
	_add_box(Vector3(-1.2, 1.5, 0.0), Vector3(0.4, 3.0, 6.0), LAYER_WORLD)
	_add_box(Vector3(0.0, 2.35, 0.0), Vector3(6.0, 0.3, 6.0), LAYER_WORLD)


## Plafond bas sur toute la zone (face inférieure à « height » mètres).
func _build_low_ceiling(height: float) -> void:
	_build_ground()
	_add_box(Vector3(0.0, height + 0.15, 0.0), Vector3(60.0, 0.3, 60.0), LAYER_WORLD)


func _make_target(position: Vector3) -> Node3D:
	var target := Node3D.new()
	target.name = "Target"
	target.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	target.position = position
	var body := MeshInstance3D.new()
	body.name = "Body"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.5, 1.75, 0.3)
	body.mesh = mesh
	body.position = Vector3(0.0, 0.875, 0.0)
	target.add_child(body)
	_world.add_child(target)
	return target


func _make_camera(target: Node3D) -> ThirdPersonCamera:
	var camera := ThirdPersonCamera.new()
	camera.input_enabled = false
	_world.add_child(camera)
	camera.set_process(false)
	camera.target = target
	return camera


func _settle_physics() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame


func _settings_dictionary() -> Dictionary:
	return JsonData.load_dictionary(CameraSettings.DEFAULT_PATH)


## Avance la caméra pendant « duration » secondes à « fps » images par seconde (durée exacte).
func _run(camera: ThirdPersonCamera, duration: float, fps: float) -> void:
	var frames: int = maxi(1, ceili(duration * fps))
	var dt: float = duration / float(frames)
	for i: int in frames:
		camera.step(dt)


func _expected_arm(camera: ThirdPersonCamera, distance: float) -> float:
	return Vector2(camera.settings.shoulder_offset, distance).length()


# --- Contrôles ------------------------------------------------------------------------------------


## Vide si la caméra respecte ses invariants : cible → point visé → caméra sans traverser le décor,
## et caméra hors du décor. Sinon, description de la première faute.
func _check_clear(camera: ThirdPersonCamera, target: Node3D) -> String:
	var space: PhysicsDirectSpaceState3D = _world.get_world_3d().direct_space_state
	var anchor: Vector3 = target.global_position + Vector3.UP * camera.settings.probe_origin_height
	var focus: Vector3 = camera.get_focus_point()
	var eye: Vector3 = camera.global_position
	if not space.intersect_ray(PhysicsRayQueryParameters3D.create(anchor, focus, BLOCKING_MASK)).is_empty():
		return "décor entre la cible %s et le point visé %s" % [anchor, focus]
	if not space.intersect_ray(PhysicsRayQueryParameters3D.create(focus, eye, BLOCKING_MASK)).is_empty():
		return "décor entre le point visé %s et la caméra %s" % [focus, eye]
	_overlap_query.transform = Transform3D(Basis.IDENTITY, eye)
	if not space.intersect_shape(_overlap_query, 1).is_empty():
		return "caméra dans le décor en %s" % eye
	return ""


## Fait vivre la cible et la caméra pendant « steps » images de durée aléatoire (20 à 240 i/s),
## avec regard et zoom aléatoires, et vérifie les invariants à chaque image.
func _stress(camera: ThirdPersonCamera, target: Node3D, steps: int, area_min: Vector3, area_max: Vector3, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var failures: int = 0
	var first_failure: String = ""
	var velocity: Vector3 = Vector3.ZERO
	for i: int in steps:
		var dt: float = 1.0 / rng.randf_range(20.0, 240.0)
		if i % 30 == 0:
			var heading: float = rng.randf_range(-PI, PI)
			velocity = Vector3(cos(heading), 0.0, sin(heading)) * rng.randf_range(0.0, GALLOP_SPEED)
		var next: Vector3 = target.position + velocity * dt
		target.position = next.clamp(area_min, area_max)
		target.rotation.y = wrapf(target.rotation.y + 9.0 * dt, -PI, PI)
		camera.add_stick_input(Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)), dt)
		if i % 50 == 0:
			camera.zoom_by_steps(rng.randi_range(-3, 3))
		camera.step(dt)
		var problem: String = _check_clear(camera, target)
		if not problem.is_empty():
			failures += 1
			if first_failure.is_empty():
				first_failure = "image %d : %s" % [i, problem]
	assert_eq(failures, 0, "la caméra ne doit jamais passer derrière le décor (%s)" % first_failure)


# --- Tests -----------------------------------------------------------------------------------------


func test_initial_placement_behind_target() -> void:
	_build_ground()
	var target: Node3D = _make_target(Vector3(3.0, 0.0, -2.0))
	var camera: ThirdPersonCamera = _make_camera(target)
	await _settle_physics()
	camera.step(1.0 / 60.0)
	var s: CameraSettings = camera.settings
	var head: Vector3 = target.position + Vector3.UP * s.pivot_height
	var orbit: Basis = Basis(Vector3.UP, s.initial_yaw) * Basis(Vector3.RIGHT, -s.initial_pitch)
	var expected: Vector3 = head + orbit * Vector3(s.shoulder_offset, 0.0, s.zoom_initial)
	assert_almost_eq(camera.global_position, expected, Vector3.ONE * 0.001)
	assert_almost_eq(camera.get_arm_length(), _expected_arm(camera, s.zoom_initial), 0.001)
	assert_true(camera.camera.current, "la Camera3D enfant doit être active")
	assert_almost_eq(camera.camera.fov, s.fov_base_deg, 0.001)
	assert_eq(camera.get_target_fade(), 0.0)
	assert_eq(_check_clear(camera, target), "")


func test_wall_pulls_in_immediately_then_returns_progressively() -> void:
	_build_corridor()
	var target: Node3D = _make_target(Vector3.ZERO)
	var camera: ThirdPersonCamera = _make_camera(target)
	await _settle_physics()
	var full: float = _expected_arm(camera, camera.settings.zoom_initial)
	var quarter_turn_pixels: float = (PI * 0.5) / camera.settings.mouse_sensitivity
	# Orbite tournée d'un quart de tour : le bras vise le mur du couloir, la caméra s'y colle aussitôt.
	camera.add_mouse_motion(Vector2(-quarter_turn_pixels, 0.0))
	camera.snap()
	camera.step(1.0 / 60.0)
	assert_almost_eq(camera.get_yaw(), PI * 0.5, 0.0001)
	assert_lt(camera.get_arm_length(), 1.2, "le bras doit raccourcir dès la première image")
	assert_lt(camera.global_position.x, 1.0 - camera.settings.probe_radius + 0.01)
	assert_eq(_check_clear(camera, target), "")
	# Retour dans l'axe du couloir : éloignement progressif, jamais d'un coup.
	camera.add_mouse_motion(Vector2(quarter_turn_pixels, 0.0))
	var previous: float = camera.get_arm_length()
	var never_shrinks: bool = true
	for i: int in 15:
		camera.step(1.0 / 60.0)
		never_shrinks = never_shrinks and camera.get_arm_length() >= previous - 0.0001
		previous = camera.get_arm_length()
	assert_lt(camera.get_arm_length(), full * 0.9, "le bras ne doit pas revenir en un quart de seconde")
	_run(camera, 4.0, 60.0)
	assert_true(never_shrinks, "une fois l'obstacle dégagé, le bras ne doit plus raccourcir")
	assert_almost_eq(camera.get_arm_length(), full, 0.01)


func test_only_layers_one_and_four_block_the_camera() -> void:
	_build_ground()
	var target: Node3D = _make_target(Vector3.ZERO)
	var camera: ThirdPersonCamera = _make_camera(target)
	# Un corps de la couche du joueur juste derrière la cible : ignoré.
	var player_like: StaticBody3D = _add_box(Vector3(0.0, 1.5, 2.0), Vector3(4.0, 3.0, 0.4), LAYER_PLAYER)
	await _settle_physics()
	camera.step(1.0 / 60.0)
	var full: float = _expected_arm(camera, camera.settings.zoom_initial)
	assert_almost_eq(camera.get_arm_length(), full, 0.001, "la couche 2 ne doit pas arrêter la caméra")
	player_like.queue_free()
	# Un obstacle réservé à la caméra (couche 4) au même endroit : la caméra s'arrête devant.
	_add_box(Vector3(0.0, 1.5, 2.0), Vector3(4.0, 3.0, 0.4), LAYER_CAMERA_OBSTACLE)
	await _settle_physics()
	camera.step(1.0 / 60.0)
	assert_lt(camera.get_arm_length(), full * 0.7, "la couche 4 doit arrêter la caméra")
	assert_eq(_check_clear(camera, target), "")


func test_never_behind_wall_in_corridor() -> void:
	_build_corridor()
	var target: Node3D = _make_target(Vector3.ZERO)
	var camera: ThirdPersonCamera = _make_camera(target)
	await _settle_physics()
	_stress(camera, target, 3000, Vector3(-0.6, 0.0, -30.0), Vector3(0.6, 0.0, 30.0), 11)


func test_never_behind_wall_in_corner_with_spinning_target() -> void:
	_build_corner()
	var target: Node3D = _make_target(Vector3(-0.6, 0.0, 0.6))
	var camera: ThirdPersonCamera = _make_camera(target)
	await _settle_physics()
	_stress(camera, target, 3000, Vector3(-0.65, 0.0, 0.4), Vector3(-0.4, 0.0, 0.65), 23)


func test_never_behind_wall_under_low_ceilings() -> void:
	# Plafond juste au-dessus de la tête, puis plafond plus bas que le point visé.
	for height: float in [1.95, 1.5]:
		for child: Node in _world.get_children():
			child.free()
		_build_low_ceiling(height)
		var target: Node3D = _make_target(Vector3.ZERO)
		var camera: ThirdPersonCamera = _make_camera(target)
		await _settle_physics()
		_stress(camera, target, 2000, Vector3(-20.0, 0.0, -20.0), Vector3(20.0, 0.0, 20.0), 37)
		assert_lt(camera.global_position.y, height - camera.settings.probe_radius + 0.01)


func test_corner_fades_target_without_flicker() -> void:
	_build_corner()
	var target: Node3D = _make_target(Vector3(-0.6, 0.0, 0.6))
	var body: MeshInstance3D = target.get_node("Body")
	var camera: ThirdPersonCamera = _make_camera(target)
	await _settle_physics()
	var previous: float = 0.0
	var monotonic: bool = true
	# La cible tourne sur elle-même dans le recoin pendant 2 s à 144 i/s.
	for i: int in 288:
		target.rotation.y = wrapf(target.rotation.y + 0.2, -PI, PI)
		camera.step(1.0 / 144.0)
		monotonic = monotonic and camera.get_target_fade() >= previous
		previous = camera.get_target_fade()
	assert_true(monotonic, "le fondu ne doit jamais revenir en arrière dans le recoin (pas de clignotement)")
	assert_eq(camera.get_target_fade(), 1.0, "la caméra collée à la cible doit l'effacer entièrement")
	assert_eq(body.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY, "l'ombre de la cible reste portée")
	assert_eq(body.transparency, 0.0, "effacée, la cible quitte le rendu transparent")
	# Un objet ajouté à la cible pendant qu'elle est effacée est effacé lui aussi.
	var item := MeshInstance3D.new()
	item.mesh = body.mesh
	target.add_child(item)
	assert_eq(item.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY)
	# La cible sort du recoin : elle réapparaît progressivement et retrouve son apparence d'origine.
	target.position = Vector3(-0.6, 0.0, -1.5)
	camera.step(1.0 / 144.0)
	assert_gt(camera.get_target_fade(), 0.0, "pas de réapparition brutale")
	_run(camera, 3.0, 144.0)
	assert_eq(camera.get_target_fade(), 0.0)
	assert_eq(body.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
	assert_eq(body.transparency, 0.0)
	assert_eq(item.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_ON)


func test_same_final_position_at_any_frame_rate() -> void:
	_build_corridor()
	var finals: Array[Transform3D] = []
	var fovs: PackedFloat32Array = PackedFloat32Array()
	for fps: float in [30.0, 144.0, 0.0]:
		var target: Node3D = _make_target(Vector3.ZERO)
		var camera: ThirdPersonCamera = _make_camera(target)
		await _settle_physics()
		var rng := RandomNumberGenerator.new()
		rng.seed = 5
		var time: float = 0.0
		# 1 s : la cible accélère dans le couloir pendant que le joueur tourne au stick.
		# 2 s : course à 6 m/s après un cran d'éloignement ; 3 s : arrêt.
		var durations: PackedFloat32Array = [1.0, 2.0, 3.0]
		for phase: int in durations.size():
			var duration: float = durations[phase]
			if phase == 1:
				camera.zoom_by_steps(1)
			var steps: PackedFloat32Array = _frame_durations(duration, fps, rng)
			for dt: float in steps:
				time += dt
				target.position = Vector3(0.0, 0.0, -_corridor_path(time))
				if phase == 0:
					camera.add_stick_input(Vector2(0.6, -0.2), dt)
				camera.step(dt)
		finals.append(camera.global_transform)
		fovs.append(camera.camera.fov)
		camera.free()
		target.free()
	for i: int in [1, 2]:
		assert_almost_eq(finals[i].origin, finals[0].origin, Vector3.ONE * 0.01, "position finale (série %d)" % i)
		assert_true(finals[i].basis.is_equal_approx(finals[0].basis), "orientation finale (série %d)" % i)
		assert_almost_eq(fovs[i], fovs[0], 0.01)


## Durées d'image couvrant exactement « duration » : fixes à « fps », ou aléatoires de 20 à 240 i/s si fps vaut 0.
func _frame_durations(duration: float, fps: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	if fps > 0.0:
		var frames: int = ceili(duration * fps)
		for i: int in frames:
			result.append(duration / float(frames))
		return result
	var remaining: float = duration
	while remaining > 0.0:
		var dt: float = minf(1.0 / rng.randf_range(20.0, 240.0), remaining)
		result.append(dt)
		remaining -= dt
	return result


## Distance parcourue dans le couloir au temps « time » : accélération à 6 m/s en 1 s, course, arrêt à 3 s.
func _corridor_path(time: float) -> float:
	if time <= 1.0:
		return 3.0 * time * time
	if time <= 3.0:
		return 3.0 + 6.0 * (time - 1.0)
	return 15.0


func test_teleport_snaps_without_sliding() -> void:
	_build_ground()
	var target: Node3D = _make_target(Vector3.ZERO)
	var camera: ThirdPersonCamera = _make_camera(target)
	await _settle_physics()
	_run(camera, 1.0, 60.0)
	target.position = Vector3(120.0, 0.0, -80.0)
	camera.step(1.0 / 60.0)
	var s: CameraSettings = camera.settings
	var head: Vector3 = target.position + Vector3.UP * s.pivot_height
	var orbit: Basis = Basis(Vector3.UP, camera.get_yaw()) * Basis(Vector3.RIGHT, -camera.get_pitch())
	var expected: Vector3 = head + orbit * Vector3(s.shoulder_offset, 0.0, s.zoom_initial)
	assert_almost_eq(camera.get_focus_point(), head, Vector3.ONE * 0.001)
	assert_almost_eq(camera.global_position, expected, Vector3.ONE * 0.001)
	assert_lt(camera.get_target_speed(), 1.0, "une téléportation n'est pas une vitesse")


func test_gallop_lag_is_bounded_and_fov_widens() -> void:
	_build_ground()
	for fps: float in [20.0, 240.0]:
		var target: Node3D = _make_target(Vector3(0.0, 0.0, 150.0))
		var camera: ThirdPersonCamera = _make_camera(target)
		await _settle_physics()
		var s: CameraSettings = camera.settings
		var frames: int = int(3.0 * fps)
		var dt: float = 1.0 / fps
		var worst_lag: float = 0.0
		for i: int in frames:
			target.position += Vector3(0.0, 0.0, -GALLOP_SPEED * dt)
			camera.step(dt)
			var head: Vector3 = target.position + Vector3.UP * s.pivot_height
			worst_lag = maxf(worst_lag, camera.get_focus_point().distance_to(head))
		gut.p("galop à %d i/s : retard maximal du point visé %.3f m" % [int(fps), worst_lag])
		assert_lt(worst_lag, s.follow_max_lag + 0.001, "retard borné au galop (%d i/s)" % int(fps))
		assert_almost_eq(camera.get_target_speed(), GALLOP_SPEED, 0.1)
		assert_almost_eq(camera.camera.fov, s.fov_base_deg + s.fov_run_bonus_deg, 0.1, "champ de vision élargi")
		_run(camera, 4.0, fps)
		assert_almost_eq(camera.camera.fov, s.fov_base_deg, 0.05, "champ de vision normal à l'arrêt")
		camera.free()
		target.free()


func test_pitch_limits_and_inversion() -> void:
	_build_ground()
	var target: Node3D = _make_target(Vector3.ZERO)
	var camera: ThirdPersonCamera = _make_camera(target)
	await _settle_physics()
	var s: CameraSettings = camera.settings
	camera.add_mouse_motion(Vector2(0.0, 100000.0))
	_run(camera, 1.0, 60.0)
	assert_almost_eq(camera.get_pitch(), s.pitch_max, 0.0001)
	camera.add_mouse_motion(Vector2(0.0, -100000.0))
	_run(camera, 1.0, 60.0)
	assert_almost_eq(camera.get_pitch(), s.pitch_min, 0.0001)
	assert_eq(_check_clear(camera, target), "", "regard vers le haut : la caméra reste au-dessus du sol")
	# Axes inversés par les données : la souris vers le bas fait alors descendre la caméra.
	var data: Dictionary = _settings_dictionary()
	(data["mouse"] as Dictionary)["invert_y"] = true
	(data["stick"] as Dictionary)["invert_x"] = true
	camera.apply_settings(CameraSettings.from_dictionary(data))
	camera.step(1.0 / 60.0)
	var pitch_before: float = camera.get_pitch()
	camera.add_mouse_motion(Vector2(0.0, 10.0))
	camera.snap()
	camera.step(1.0 / 60.0)
	assert_lt(camera.get_pitch(), pitch_before)
	var yaw_before: float = camera.get_yaw()
	camera.add_stick_input(Vector2(1.0, 0.0), 0.1)
	camera.snap()
	camera.step(1.0 / 60.0)
	assert_almost_eq(angle_difference(yaw_before, camera.get_yaw()), s.stick_speed * 0.1, 0.0001)


func test_zoom_stays_between_limits() -> void:
	_build_ground()
	var target: Node3D = _make_target(Vector3.ZERO)
	var camera: ThirdPersonCamera = _make_camera(target)
	await _settle_physics()
	var s: CameraSettings = camera.settings
	camera.zoom_by_steps(1000)
	assert_eq(camera.get_zoom_goal(), s.zoom_max)
	_run(camera, 3.0, 60.0)
	assert_almost_eq(camera.get_arm_length(), _expected_arm(camera, s.zoom_max), 0.01)
	camera.zoom_by_steps(-1000)
	assert_eq(camera.get_zoom_goal(), s.zoom_min)
	camera.step(1.0 / 60.0)
	assert_gt(camera.get_arm_length(), _expected_arm(camera, s.zoom_min) + 1.0, "le rapprochement est progressif")
	_run(camera, 3.0, 60.0)
	assert_almost_eq(camera.get_arm_length(), _expected_arm(camera, s.zoom_min), 0.01)
	camera.zoom_by_steps(1)
	assert_almost_eq(camera.get_zoom_goal(), s.zoom_min + s.zoom_step, 0.0001)


func test_freed_target_is_ignored() -> void:
	_build_ground()
	var target: Node3D = _make_target(Vector3.ZERO)
	var camera: ThirdPersonCamera = _make_camera(target)
	await _settle_physics()
	camera.step(1.0 / 60.0)
	var before: Vector3 = camera.global_position
	target.free()
	camera.step(1.0 / 60.0)
	assert_eq(camera.global_position, before, "sans cible, la caméra reste en place")


func test_load_worst_case_cost_per_frame() -> void:
	# Pire cas du MVP 1 : 1 000 objets avec collision autour de la cible, recoin sous plafond bas,
	# cible au galop (15 m/s) qui change de direction et tourne sur elle-même, téléportations,
	# regard et zoom en continu, fréquence d'images aléatoire de 20 à 240 i/s.
	_build_corner()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1332
	for i: int in 1000:
		var angle: float = rng.randf_range(-PI, PI)
		var radius: float = rng.randf_range(4.0, 40.0)
		var size: Vector3 = Vector3(rng.randf_range(0.3, 3.0), rng.randf_range(0.3, 4.0), rng.randf_range(0.3, 3.0))
		var layer: int = LAYER_CAMERA_OBSTACLE if i % 10 == 0 else LAYER_WORLD
		_add_box(Vector3(cos(angle) * radius, size.y * 0.5, sin(angle) * radius), size, layer)
	var target: Node3D = _make_target(Vector3(-0.6, 0.0, 0.6))
	var camera: ThirdPersonCamera = _make_camera(target)
	await _settle_physics()
	var frames: int = 20000
	var costs := PackedFloat32Array()
	costs.resize(frames)
	var velocity: Vector3 = Vector3.ZERO
	var total_usec: int = 0
	for i: int in frames:
		var dt: float = 1.0 / rng.randf_range(20.0, 240.0)
		if i % 40 == 0:
			var heading: float = rng.randf_range(-PI, PI)
			velocity = Vector3(cos(heading), 0.0, sin(heading)) * GALLOP_SPEED
		if i % 2500 == 0:
			target.position = Vector3(-0.6, 0.0, 0.6)
		else:
			target.position = (target.position + velocity * dt).clamp(Vector3(-40.0, 0.0, -40.0), Vector3(40.0, 0.0, 40.0))
		target.rotation.y = wrapf(target.rotation.y + 9.0 * dt, -PI, PI)
		camera.add_stick_input(Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)), dt)
		if i % 60 == 0:
			camera.zoom_by_steps(rng.randi_range(-2, 2))
		var start: int = Time.get_ticks_usec()
		camera.step(dt)
		var elapsed: int = Time.get_ticks_usec() - start
		total_usec += elapsed
		costs[i] = float(elapsed) / 1000.0
	costs.sort()
	var average_ms: float = float(total_usec) / 1000.0 / float(frames)
	var p99_ms: float = costs[int(float(frames) * 0.99)]
	var max_ms: float = costs[frames - 1]
	gut.p(
		(
			"MESURE camera : %d images, 1 000 objets, coût par image moyen %.4f ms, 99e centile %.4f ms, maximum %.4f ms"
			% [frames, average_ms, p99_ms, max_ms]
		)
	)
	PerfCheck.under(self, average_ms, LOAD_AVG_BUDGET_MS, "coût moyen par image de la caméra")
	PerfCheck.under(self, p99_ms, LOAD_P99_BUDGET_MS, "99e centile du coût par image de la caméra")
