extends GutTest
## Médina générée, construite comme en jeu (TunisCellProvider, toutes les cellules chargées, collisions
## réelles du kit) : parcours d'un agent du gabarit du joueur dans chaque voie, absence de fuite vers
## l'intérieur des îlots, porte seule entrée, aucune ouverture sur le vide depuis le désert, rue qui
## tourne après la porte, et caméra à la troisième personne dans la ruelle la plus étroite.
##
## Pires cas : ville entière chargée ; capsule du joueur (rayon et hauteur de locomotion.json) ;
## remplissage de l'espace praticable au pas de 25 cm sur toute l'enceinte et ses abords ; 3 distances,
## 3 décalages et 2 hauteurs d'œil (à pied, à cheval) depuis le désert ; caméra dans la ruelle la plus
## étroite avec cible au pas de course, regard et zoom aléatoires, 20 à 240 images par seconde.

const LOCOMOTION_PATH: String = "res://data/player/locomotion.json"
const LAYER_WORLD_MASK: int = 1
const CAMERA_BLOCKING_MASK: int = 1 | (1 << 3)
const GRID_STEP_M: float = 0.25
const FLOOD_MARGIN_M: float = 8.0
const FOOT_CLEARANCE_M: float = 0.05
## Écart admis entre une cellule praticable et l'espace libre prévu (renfoncement de porte, moulure).
const OPEN_TOLERANCE_M: float = 0.35
const RING_POINTS: int = 16
const RAYS_X: int = 64
const RAYS_Y: int = 36
const VIEW_FOV_DEG: float = 70.0
const VIEW_ASPECT: float = 16.0 / 9.0
const GATE_LOOK_HEIGHT_M: float = 3.0
const EYE_HEIGHT_M: float = 1.7
const CAMERA_STEPS: int = 1500
const CAMERA_SPEED_MPS: float = 7.0
const CAMERA_CLEARANCE_M: float = 0.1
const CAMERA_AVG_BUDGET_MS: float = 0.25
const CAMERA_P99_BUDGET_MS: float = 1.0
const MOTION_COMPLETE: float = 0.9999

var _world: Node3D = null
var _layout: Dictionary = {}
var _description: Dictionary = {}
var _radius: float = 0.0
var _height: float = 0.0
var _max_floor_angle: float = 0.0


func before_all() -> void:
	_layout = JsonData.load_dictionary(MedinaStore.LAYOUT_PATH)
	_description = JsonData.load_dictionary(MedinaStore.DESCRIPTION_PATH)
	var locomotion: Dictionary = JsonData.load_dictionary(LOCOMOTION_PATH)
	var body: Dictionary = JsonData.get_dictionary(locomotion, "body", "locomotion")
	_radius = JsonData.get_float(body, "radius", "locomotion.body")
	_height = JsonData.get_float(body, "height", "locomotion.body")
	_max_floor_angle = deg_to_rad(
		JsonData.get_float(JsonData.get_dictionary(locomotion, "physics", "locomotion"), "floor_max_angle_degrees", "locomotion.physics")
	)
	_world = Node3D.new()
	_world.name = "MedinaTestWorld"
	add_child(_world)
	var provider: TunisCellProvider = TunisCellProvider.create()
	assert_not_null(provider)
	var worst_ms: float = 0.0
	var side: int = int(sqrt(float(provider.cell_count())))
	for x: int in side:
		for z: int in side:
			var started: int = Time.get_ticks_usec()
			var cell: Node3D = provider.build_cell(Vector2i(x, z))
			worst_ms = maxf(worst_ms, float(Time.get_ticks_usec() - started) / 1000.0)
			_world.add_child(cell)
	gut.p("Construction de la cellule la plus chargée : %.2f ms." % worst_ms)
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1000.0, 1.0, 1000.0)
	shape.shape = box
	ground.position = Vector3(0.0, -0.5, 0.0)
	ground.add_child(shape)
	_world.add_child(ground)
	await get_tree().physics_frame
	await get_tree().physics_frame


func after_all() -> void:
	_world.free()


func _space() -> PhysicsDirectSpaceState3D:
	return _world.get_world_3d().direct_space_state


func _v3(point: Array, height: float = 0.0) -> Vector3:
	return Vector3(float(point[0]), height, float(point[1]))


func _capsule(radius: float) -> PhysicsShapeQueryParameters3D:
	var capsule := CapsuleShape3D.new()
	capsule.radius = radius
	capsule.height = _height
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = LAYER_WORLD_MASK
	return query


func _center(point: Vector3) -> Vector3:
	return Vector3(point.x, FOOT_CLEARANCE_M + _height / 2.0, point.z)


func _gate_point() -> Vector3:
	return _v3((_layout["gate"] as Dictionary)["position"])


func _inward() -> Vector3:
	var inward: Array = (_layout["gate"] as Dictionary)["inward"]
	return Vector3(float(inward[0]), 0.0, float(inward[1]))


# --- Parcours de l'agent ----------------------------------------------------------------------------


## Déplace la capsule du joueur de « from » à « to » ; renvoie la fraction parcourue sans contact.
func _walk(query: PhysicsShapeQueryParameters3D, from: Vector3, to: Vector3) -> float:
	query.transform = Transform3D(Basis.IDENTITY, _center(from))
	query.motion = to - from
	var fractions: PackedFloat32Array = _space().cast_motion(query)
	return fractions[0] if not fractions.is_empty() else 1.0


func _floor_angle(point: Vector3) -> float:
	var hit: Dictionary = _space().intersect_ray(
		PhysicsRayQueryParameters3D.create(point + Vector3.UP, point + Vector3.DOWN, LAYER_WORLD_MASK)
	)
	if hit.is_empty():
		return PI
	return (hit["normal"] as Vector3).angle_to(Vector3.UP)


func test_agent_walks_every_way_and_around_the_fountain() -> void:
	var query: PhysicsShapeQueryParameters3D = _capsule(_radius)
	var paths: Array = []
	var gate: Vector3 = _gate_point()
	paths.append([gate - _inward() * 12.0, gate])
	for raw_way: Variant in _layout["ways"]:
		var points: Array = []
		for point: Variant in (raw_way as Dictionary)["points"]:
			points.append(_v3(point))
		paths.append(points)
	var plaza: Dictionary = _layout["plaza"]
	var fountain: Vector3 = _v3(plaza["fountain"])
	var clearance: float = float(((_description["parameters"] as Dictionary)["fountain_clearance_m"] as Dictionary)["value"])
	var ring_radius: float = float(plaza["fountain_radius_m"]) + clearance / 2.0
	var ring: Array = []
	for index: int in RING_POINTS + 1:
		var angle: float = TAU * float(index) / float(RING_POINTS)
		ring.append(fountain + Vector3(cos(angle), 0.0, sin(angle)) * ring_radius)
	paths.append(ring)
	var segments: int = 0
	var blocked: PackedStringArray = PackedStringArray()
	for path: Variant in paths:
		var points: Array = path
		for index: int in points.size() - 1:
			var from: Vector3 = points[index]
			var to: Vector3 = points[index + 1]
			segments += 1
			var fraction: float = _walk(query, from, to)
			if fraction < MOTION_COMPLETE:
				blocked.append("%s → %s (%.0f %%)" % [from, to, fraction * 100.0])
			var steps: int = maxi(1, ceili(from.distance_to(to) / 1.0))
			for step: int in steps + 1:
				var sample: Vector3 = from.lerp(to, float(step) / float(steps))
				if _floor_angle(sample) > _max_floor_angle:
					blocked.append("pente impraticable en %s" % sample)
	gut.p("Parcours : %d tronçons parcourus par la capsule du joueur (rayon %.2f m, hauteur %.2f m)." % [segments, _radius, _height])
	assert_eq(blocked, PackedStringArray(), "l'agent doit parcourir chaque voie sans obstacle")


# --- Remplissage de l'espace praticable -----------------------------------------------------------


## Cases praticables (1) de la grille ; « origin » = coin bas de la grille, « size » en cases.
func _walkable_grid(origin: Vector2, size: Vector2i) -> PackedByteArray:
	var query: PhysicsShapeQueryParameters3D = _capsule(_radius - GRID_STEP_M * sqrt(2.0) / 2.0)
	var grid := PackedByteArray()
	grid.resize(size.x * size.y)
	var y: float = FOOT_CLEARANCE_M + _height / 2.0
	for j: int in size.y:
		for i: int in size.x:
			query.transform = Transform3D(
				Basis.IDENTITY, Vector3(origin.x + (float(i) + 0.5) * GRID_STEP_M, y, origin.y + (float(j) + 0.5) * GRID_STEP_M)
			)
			grid[j * size.x + i] = 1 if _space().intersect_shape(query, 1).is_empty() else 0
	return grid


func _flood(grid: PackedByteArray, size: Vector2i, start: Vector2i) -> PackedByteArray:
	var reached := PackedByteArray()
	reached.resize(grid.size())
	var queue := PackedInt32Array([start.y * size.x + start.x])
	reached[queue[0]] = 1
	var head: int = 0
	while head < queue.size():
		var current: int = queue[head]
		head += 1
		var ci: int = current % size.x
		var cj: int = current / size.x
		for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var ni: int = ci + offset.x
			var nj: int = cj + offset.y
			if ni < 0 or nj < 0 or ni >= size.x or nj >= size.y:
				continue
			var neighbor: int = nj * size.x + ni
			if grid[neighbor] == 1 and reached[neighbor] == 0:
				reached[neighbor] = 1
				queue.append(neighbor)
	return reached


func _cell_of(point: Vector3, origin: Vector2) -> Vector2i:
	return Vector2i(floori((point.x - origin.x) / GRID_STEP_M), floori((point.z - origin.y) / GRID_STEP_M))


func test_walkable_space_has_no_leak_and_only_the_gate_enters() -> void:
	var enclosure: Array = _layout["enclosure"]
	var origin := Vector2(float(enclosure[0]) - FLOOD_MARGIN_M, float(enclosure[1]) - FLOOD_MARGIN_M)
	var size := Vector2i(
		ceili((float(enclosure[2]) - float(enclosure[0]) + 2.0 * FLOOD_MARGIN_M) / GRID_STEP_M),
		ceili((float(enclosure[3]) - float(enclosure[1]) + 2.0 * FLOOD_MARGIN_M) / GRID_STEP_M)
	)
	var started: int = Time.get_ticks_usec()
	var grid: PackedByteArray = _walkable_grid(origin, size)
	var start: Vector2i = _cell_of(_gate_point() - _inward() * (FLOOD_MARGIN_M / 2.0), origin)
	var reached: PackedByteArray = _flood(grid, size, start)
	gut.p(
		(
			"Espace praticable : %d cases de %.2f m testées en %.0f ms."
			% [grid.size(), GRID_STEP_M, float(Time.get_ticks_usec() - started) / 1000.0]
		)
	)
	var targets: Array[Vector3] = []
	var plaza: Dictionary = _layout["plaza"]
	for node: Variant in (_layout["graph"] as Dictionary)["nodes"]:
		if String((node as Dictionary)["id"]) == MedinaPlan.PLAZA_ELEMENT:
			# Le nœud de la place est au centre de la fontaine : on vise le bord du bassin.
			targets.append(_v3(plaza["fountain"]) + Vector3(float(plaza["fountain_radius_m"]) + 1.0, 0.0, 0.0))
			continue
		targets.append(_v3((node as Dictionary)["position"]))
	for slot: Variant in _layout["slots"]:
		var facing: Array = (slot as Dictionary)["facing"]
		targets.append(_v3((slot as Dictionary)["door_position"]) + Vector3(float(facing[0]), 0.0, float(facing[1])) * (_radius + 0.3))
	var terrace: Array = (_layout["terrace_access"] as Dictionary)["base"]
	targets.append(Vector3(float(terrace[0]), 0.0, float(terrace[2])))
	var unreachable: Array = []
	for target: Vector3 in targets:
		var cell: Vector2i = _cell_of(target, origin)
		if reached[cell.y * size.x + cell.x] == 0:
			unreachable.append(target)
	assert_eq(unreachable, [], "voies, portes réservées et pied de la terrasse accessibles depuis le désert")
	var interior: Array = _layout["interior"]
	var interior_rect := Rect2(
		Vector2(float(interior[0]), float(interior[1])),
		Vector2(float(interior[2]) - float(interior[0]), float(interior[3]) - float(interior[1]))
	)
	var open: Array[Rect2] = []
	for raw: Variant in _layout["open_rects"]:
		var r: Array = raw
		open.append(
			Rect2(Vector2(float(r[0]), float(r[1])), Vector2(float(r[2]) - float(r[0]), float(r[3]) - float(r[1]))).grow(OPEN_TOLERANCE_M)
		)
	var leaks: int = 0
	var first_leak: Vector2 = Vector2.ZERO
	for j: int in size.y:
		for i: int in size.x:
			if reached[j * size.x + i] == 0:
				continue
			var point := Vector2(origin.x + (float(i) + 0.5) * GRID_STEP_M, origin.y + (float(j) + 0.5) * GRID_STEP_M)
			if not interior_rect.has_point(point):
				continue
			var inside_open: bool = false
			for rect: Rect2 in open:
				if rect.has_point(point):
					inside_open = true
					break
			if not inside_open:
				if leaks == 0:
					first_leak = point
				leaks += 1
	assert_eq(leaks, 0, "aucune case praticable dans un îlot (première en %s)" % first_leak)
	await _assert_gate_is_the_only_entrance(origin, size, start)


func _assert_gate_is_the_only_entrance(origin: Vector2, size: Vector2i, start: Vector2i) -> void:
	var gate: Dictionary = _layout["gate"]
	var metrics: Dictionary = (_description["prefab_metrics"] as Dictionary)["city_gate"]
	var plug := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var across: float = 2.0 * float(gate["opening_half_width_m"]) + 0.2
	var depth: float = float(metrics["depth_m"]) + 1.0
	var height: float = float(metrics["clear_height_m"])
	var inward: Vector3 = _inward()
	box.size = Vector3(across, height, depth) if absf(inward.z) > 0.5 else Vector3(depth, height, across)
	shape.shape = box
	plug.add_child(shape)
	plug.position = _gate_point() + Vector3.UP * (height / 2.0)
	_world.add_child(plug)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var grid: PackedByteArray = _walkable_grid(origin, size)
	var reached: PackedByteArray = _flood(grid, size, start)
	plug.free()
	var fountain: Vector3 = (
		_v3((_layout["plaza"] as Dictionary)["fountain"])
		+ Vector3(float((_layout["plaza"] as Dictionary)["fountain_radius_m"]) + 1.0, 0.0, 0.0)
	)
	var cell: Vector2i = _cell_of(fountain, origin)
	assert_eq(reached[cell.y * size.x + cell.x], 0, "porte fermée : la place n'est plus accessible depuis le désert")


# --- Vues depuis le désert -----------------------------------------------------------------------


func test_desert_views_never_show_the_void_behind_the_city() -> void:
	var viewpoints: Dictionary = _description["viewpoints"]
	var enclosure: Array = _layout["enclosure"]
	var rampart_height: float = float(((_description["prefab_metrics"] as Dictionary)["rampart_straight"] as Dictionary)["height_m"])
	var box := AABB(
		Vector3(float(enclosure[0]), 0.0, float(enclosure[1])),
		Vector3(float(enclosure[2]) - float(enclosure[0]), rampart_height, float(enclosure[3]) - float(enclosure[1]))
	)
	var gate: Vector3 = _gate_point()
	var inward: Vector3 = _inward()
	var lateral: Vector3 = inward.cross(Vector3.UP)
	var rays: int = 0
	var violations: PackedStringArray = PackedStringArray()
	for distance: Variant in viewpoints["desert_distances_m"]:
		for offset: Variant in viewpoints["desert_lateral_m"]:
			for eye_height: Variant in viewpoints["desert_eye_heights_m"]:
				var eye: Vector3 = gate - inward * float(distance) + lateral * float(offset) + Vector3.UP * float(eye_height)
				var basis: Basis = Basis.looking_at(gate + Vector3.UP * GATE_LOOK_HEIGHT_M - eye, Vector3.UP)
				var half_x: float = tan(deg_to_rad(VIEW_FOV_DEG) / 2.0)
				var half_y: float = half_x / VIEW_ASPECT
				for iy: int in RAYS_Y:
					for ix: int in RAYS_X:
						var sx: float = (float(ix) + 0.5) / float(RAYS_X) * 2.0 - 1.0
						var sy: float = (float(iy) + 0.5) / float(RAYS_Y) * 2.0 - 1.0
						var direction: Vector3 = (basis * Vector3(sx * half_x, sy * half_y, -1.0)).normalized()
						var problem: String = _ray_sees_void(eye, direction, box)
						rays += 1
						if not problem.is_empty() and violations.size() < 5:
							violations.append(problem)
	gut.p("Vues du désert : %d rayons lancés." % rays)
	assert_eq(violations, PackedStringArray(), "aucun rayon ne traverse la ville sous la ligne des remparts")


## Message si le rayon entre dans le volume bas de la ville et en ressort par un côté sans rien toucher.
func _ray_sees_void(eye: Vector3, direction: Vector3, box: AABB) -> String:
	var t_near: float = -INF
	var t_far: float = INF
	var exit_axis: int = -1
	for axis: int in 3:
		var origin_value: float = eye[axis]
		var direction_value: float = direction[axis]
		if absf(direction_value) < 0.000001:
			if origin_value < box.position[axis] or origin_value > box.end[axis]:
				return ""
			continue
		var t1: float = (box.position[axis] - origin_value) / direction_value
		var t2: float = (box.end[axis] - origin_value) / direction_value
		t_near = maxf(t_near, minf(t1, t2))
		if maxf(t1, t2) < t_far:
			t_far = maxf(t1, t2)
			exit_axis = axis
	if t_near > t_far or t_far <= 0.0:
		return ""
	var exit_point: Vector3 = eye + direction * t_far
	var hit: Dictionary = _space().intersect_ray(PhysicsRayQueryParameters3D.create(eye, exit_point + direction * 0.01, LAYER_WORLD_MASK))
	if not hit.is_empty() or exit_axis == 1:
		return ""
	return "depuis %s, le rayon %s ressort de la ville en %s sans rien toucher" % [eye, direction, exit_point]


func test_street_turns_after_the_gate() -> void:
	var inward: Vector3 = _inward()
	var eye: Vector3 = _gate_point() + inward * 2.0 + Vector3.UP * EYE_HEIGHT_M
	var fountain: Vector3 = _v3((_layout["plaza"] as Dictionary)["fountain"], 1.0)
	var to_plaza: Dictionary = _space().intersect_ray(PhysicsRayQueryParameters3D.create(eye, fountain, LAYER_WORLD_MASK))
	assert_false(to_plaza.is_empty(), "la place n'est pas visible depuis l'entrée de la porte")
	var ways: Array = _layout["ways"]
	var first_leg: float = 0.0
	for raw_way: Variant in ways:
		var way: Dictionary = raw_way
		if String(way["role"]) == "main":
			var points: Array = way["points"]
			first_leg = _v3(points[0]).distance_to(_v3(points[1])) + float(way["width_m"])
	var ahead: Dictionary = _space().intersect_ray(PhysicsRayQueryParameters3D.create(eye, eye + inward * 200.0, LAYER_WORLD_MASK))
	assert_false(ahead.is_empty(), "la vue droit devant est fermée")
	if not ahead.is_empty():
		var seen: float = eye.distance_to(ahead["position"])
		gut.p("Vue droit devant après la porte : %.1f m (premier tronçon %.1f m)." % [seen, first_leg])
		assert_lt(seen, first_leg, "la rue tourne avant de révéler la place")


# --- Caméra dans la ruelle la plus étroite ----------------------------------------------------------


func _check_camera(camera: ThirdPersonCamera, target: Node3D, overlap: PhysicsShapeQueryParameters3D) -> String:
	var anchor: Vector3 = target.global_position + Vector3.UP * camera.settings.probe_origin_height
	var focus: Vector3 = camera.get_focus_point()
	var eye: Vector3 = camera.global_position
	if not _space().intersect_ray(PhysicsRayQueryParameters3D.create(anchor, focus, CAMERA_BLOCKING_MASK)).is_empty():
		return "décor entre la cible %s et le point visé %s" % [anchor, focus]
	if not _space().intersect_ray(PhysicsRayQueryParameters3D.create(focus, eye, CAMERA_BLOCKING_MASK)).is_empty():
		return "décor entre le point visé %s et la caméra %s" % [focus, eye]
	overlap.transform = Transform3D(Basis.IDENTITY, eye)
	if not _space().intersect_shape(overlap, 1).is_empty():
		return "caméra dans le décor en %s" % eye
	return ""


func test_camera_in_the_narrowest_lane() -> void:
	var narrow_id: String = String((_layout["narrowest_way"] as Dictionary)["id"])
	var points: Array[Vector3] = []
	for raw_way: Variant in _layout["ways"]:
		if String((raw_way as Dictionary)["id"]) == narrow_id:
			for point: Variant in (raw_way as Dictionary)["points"]:
				points.append(_v3(point))
	assert_gt(points.size(), 1)
	var target := Node3D.new()
	target.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var body := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.5, _height, 0.3)
	body.mesh = mesh
	body.position = Vector3.UP * (_height / 2.0)
	target.add_child(body)
	target.position = points[0]
	_world.add_child(target)
	var camera := ThirdPersonCamera.new()
	camera.input_enabled = false
	_world.add_child(camera)
	camera.set_process(false)
	camera.target = target
	await get_tree().physics_frame
	var sphere := SphereShape3D.new()
	sphere.radius = CAMERA_CLEARANCE_M
	var overlap := PhysicsShapeQueryParameters3D.new()
	overlap.shape = sphere
	overlap.collision_mask = CAMERA_BLOCKING_MASK
	var rng := RandomNumberGenerator.new()
	rng.seed = 53
	var leg: int = 0
	var forward: bool = true
	var failures: int = 0
	var first_failure: String = ""
	var durations := PackedFloat64Array()
	for frame: int in CAMERA_STEPS:
		var dt: float = 1.0 / rng.randf_range(20.0, 240.0)
		var goal: Vector3 = points[leg + 1] if forward else points[leg]
		var to_goal: Vector3 = goal - target.position
		var travel: float = CAMERA_SPEED_MPS * dt
		if to_goal.length() <= travel:
			target.position = goal
			if forward:
				leg += 1
				if leg >= points.size() - 1:
					leg = points.size() - 2
					forward = false
			else:
				leg -= 1
				if leg < 0:
					leg = 0
					forward = true
		else:
			target.position += to_goal.normalized() * travel
			target.rotation.y = atan2(-to_goal.x, -to_goal.z)
		camera.add_stick_input(Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)), dt)
		if frame % 50 == 0:
			camera.zoom_by_steps(rng.randi_range(-3, 3))
		var started: int = Time.get_ticks_usec()
		camera.step(dt)
		durations.append(float(Time.get_ticks_usec() - started) / 1000.0)
		var problem: String = _check_camera(camera, target, overlap)
		if not problem.is_empty():
			failures += 1
			if first_failure.is_empty():
				first_failure = "image %d : %s" % [frame, problem]
	camera.free()
	target.free()
	var total: float = 0.0
	for duration: float in durations:
		total += duration
	var sorted: PackedFloat64Array = durations.duplicate()
	sorted.sort()
	var average: float = total / float(durations.size())
	var p99: float = sorted[mini(sorted.size() - 1, int(float(sorted.size()) * 0.99))]
	gut.p("Caméra dans « %s » : %d images, moyenne %.3f ms, 99e centile %.3f ms." % [narrow_id, CAMERA_STEPS, average, p99])
	assert_eq(failures, 0, "la caméra ne traverse jamais le décor de la ruelle (%s)" % first_failure)
	assert_lt(average, CAMERA_AVG_BUDGET_MS)
	assert_lt(p99, CAMERA_P99_BUDGET_MS)
