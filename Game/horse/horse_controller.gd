class_name HorseController
extends CharacterBody3D
## Barq : déplacement physique (pesanteur, saut), relief, évitement, animations du modèle calées sur la vitesse au sol
## et point de selle qui suit le dos du cheval (horse.json > rider). Le modèle est préparé par HorseVisual.

## collider : collisionneur sous le sabot (muret, terre de palmeraie, sol), ou Barq lui-même (surface_at du relief).
signal hoofstep(world_position: Vector3, speed: float, surface: StringName, collider: Object)
signal gait_changed(gait: StringName)
signal called
signal jump_started(world_position: Vector3)
signal jump_landed(world_position: Vector3)

const SETTINGS_PATH: String = "res://data/horse/horse.json"
const GROUND_LAYER: int = 1
## Pas de la dichotomie qui réduit un virage refusé par la règle de vitesse de la scène.
const GUARD_TURN_STEPS: int = 4

var locomotion: HorseLocomotion
var settings: Dictionary = {}
var heightfield: DesertHeightfield
var mounted: bool = false
var called_target: Vector3 = Vector3.ZERO
var is_called: bool = false
var last_step_usec: int = 0
## Règles spatiales facultatives imposées par la scène (porte de ville) ; sans effet dans le désert ouvert.
## speed_guard(position, cap) -> vitesse maximale (m/s) permise : freinage progressif devant un obstacle ;
## guard_deceleration (m/s²) borne alors la perte de vitesse par image, et un virage qui exigerait un freinage
## plus fort est limité (Barq ne se jette pas vers le mur).
## movement_guard(position, déplacement) -> faux si le déplacement entre dans une zone interdite.
## jump_guard(position) -> faux si le saut est interdit ici.
var speed_guard: Callable = Callable()
var guard_deceleration: float = 0.0
var movement_guard: Callable = Callable()
var jump_guard: Callable = Callable()
var _call_target_node: Node3D = null

var _visual: HorseVisual
var _animation_player: AnimationPlayer
## Clip et vitesse de référence par allure (indices de HorseLocomotion.Gait), clip d'arrêt et de saut.
var _gait_clips: Array[StringName] = []
var _gait_reference: PackedFloat32Array = PackedFloat32Array()
## Foulée (m) et battues par foulée de chaque allure, côté du dernier sabot.
var _gait_stride: PackedFloat32Array = PackedFloat32Array()
var _gait_beats: PackedFloat32Array = PackedFloat32Array()
var _hoof_side: float = 1.0
var _idle_clip: StringName = &""
var _jump_clip: StringName = &""
var _idle_speed: float = 0.0
var _scale_min: float = 1.0
var _scale_max: float = 1.0
var _blend: float = 0.0
## Saut : vitesse verticale propre, en l'air, temps avant le prochain saut.
var _vertical_speed: float = 0.0
var _airborne: bool = false
var _jump_cooldown: float = 0.0
var _jump_speed: float = 0.0
var _gravity: float = 9.81
var _jump_min_speed: float = 0.0
var _jump_rest: float = 0.0
## Point de selle : os du dos et passage de cet os au point de selle (calculé une fois sur la pose de repos).
var _saddle_bone: int = -1
var _bone_to_seat := Transform3D.IDENTITY
## Point de selle au repos, dans le repère de Barq.
var _seat_local: Vector3 = Vector3.ZERO
var _input_move: Vector2 = Vector2.ZERO
var _input_sprint: bool = false
var _last_position: Vector3 = Vector3.ZERO
var _stride_distance: float = 0.0
var _probe: PhysicsShapeQueryParameters3D
var _probe_shape: SphereShape3D
var _exclude: Array[RID] = []
var _step_collision := KinematicCollision3D.new()
## Rayon du sabot (nœud RayCast3D : aucune allocation, contrairement à intersect_ray qui crée un dictionnaire).
var _hoof_ray := RayCast3D.new()
var _call_path := HorseCallPath.new()
var _waypoint: int = 0
var _path_goal := Vector3.ZERO
var _replan_timer: float = 0.0
var _call: Dictionary = {}
var _step_retry: float = 0.0
var _max_slope_cos: float = 0.0
var _cliff_drop: float = 0.0
var _sample_spacing: float = 1.0
var _look_time: float = 0.0
var _look_min: float = 0.0
var _look_max: float = 0.0
var _probe_clearance: float = 0.0
var _probe_distance: float = 0.0
var _step_max: float = 0.0
var _step_min: float = 0.0
var _step_clearance: float = 0.0
var _step_inset: float = 0.0
var _step_retry_delay: float = 0.0
var _last_gait: StringName = &"walk"


func _init(field: DesertHeightfield = null) -> void:
	settings = JsonData.load_dictionary(SETTINGS_PATH)
	heightfield = field
	locomotion = HorseLocomotion.new(settings)
	var gaits: Dictionary = JsonData.get_dictionary(settings, "gaits", "horse.json")
	for gait_name: StringName in HorseLocomotion.GAIT_NAMES:
		var gait_data: Dictionary = JsonData.get_dictionary(gaits, String(gait_name), "horse.json > gaits")
		_gait_stride.append(JsonData.get_float(gait_data, "stride_m", "horse.json > gaits"))
		_gait_beats.append(JsonData.get_float(gait_data, "beats_per_stride", "horse.json > gaits"))
	var jump_data: Dictionary = JsonData.get_dictionary(settings, "jump", "horse.json")
	_jump_speed = JsonData.get_float(jump_data, "speed_mps", "horse.json > jump")
	_gravity = JsonData.get_float(jump_data, "gravity_mps2", "horse.json > jump")
	_jump_min_speed = JsonData.get_float(jump_data, "min_speed_mps", "horse.json > jump")
	_jump_rest = JsonData.get_float(jump_data, "cooldown_s", "horse.json > jump")
	var terrain: Dictionary = JsonData.get_dictionary(settings, "terrain", "horse.json")
	const T: String = "horse.json > terrain"
	_max_slope_cos = cos(deg_to_rad(JsonData.get_float(terrain, "max_slope_deg", T)))
	_cliff_drop = JsonData.get_float(terrain, "cliff_drop_m", T)
	_sample_spacing = maxf(JsonData.get_float(terrain, "sample_spacing_m", T), 0.25)
	_look_time = JsonData.get_float(terrain, "look_ahead_time_s", T)
	_look_min = JsonData.get_float(terrain, "look_ahead_min_m", T)
	_look_max = maxf(JsonData.get_float(terrain, "look_ahead_max_m", T), _look_min)
	_probe_clearance = JsonData.get_float(terrain, "obstacle_clearance_m", T)
	_probe_distance = JsonData.get_float(terrain, "obstacle_probe_distance_m", T)
	_step_max = JsonData.get_float(terrain, "step_max_height_m", T)
	_step_min = JsonData.get_float(terrain, "step_min_height_m", T)
	_step_clearance = JsonData.get_float(terrain, "step_clearance_m", T)
	_step_inset = JsonData.get_float(terrain, "step_surface_inset_m", T)
	_step_retry_delay = JsonData.get_float(terrain, "step_retry_delay_s", T)
	if _probe_clearance <= _step_max:
		push_error("horse.json > terrain : obstacle_clearance_m doit dépasser step_max_height_m (sinon les marches arrêtent Barq).")
	_probe_shape = SphereShape3D.new()
	_probe_shape.radius = JsonData.get_float(terrain, "obstacle_probe_radius_m", T)
	_probe = PhysicsShapeQueryParameters3D.new()
	_probe.shape = _probe_shape
	_probe.collision_mask = GROUND_LAYER
	_probe.collide_with_areas = false
	_probe.collide_with_bodies = true
	add_to_group(&"horse")


func _ready() -> void:
	var body: Dictionary = settings.get("body", {}) as Dictionary
	var capsule := CapsuleShape3D.new()
	capsule.radius = float(body.get("radius_m", 0.4))
	capsule.height = float(body.get("height_m", 1.5))
	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	collision.shape = capsule
	collision.position = Vector3(0.0, capsule.height * 0.5, 0.0)
	add_child(collision)
	# Corps couché le long de l'axe avant-arrière (z local), au-dessus des marches que Barq enjambe.
	var torso := CapsuleShape3D.new()
	torso.radius = float(body.get("torso_radius_m", 0.42))
	torso.height = maxf(float(body.get("torso_length_m", 2.3)), torso.radius * 2.0)
	var torso_shape := CollisionShape3D.new()
	torso_shape.name = "Torso"
	torso_shape.shape = torso
	torso_shape.transform = Transform3D(
		Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, float(body.get("torso_bottom_m", 0.6)) + torso.radius, 0.0)
	)
	add_child(torso_shape)
	if float(body.get("torso_bottom_m", 0.6)) <= _step_max:
		push_error("horse.json > body : torso_bottom_m doit dépasser terrain > step_max_height_m.")
	collision_layer = _layers_to_mask([body.get("collision_layer", 3)])
	collision_mask = _layers_to_mask(body.get("collision_mask", [1]) as Array)
	up_direction = Vector3.UP
	floor_max_angle = deg_to_rad(float(body.get("floor_max_angle_deg", 38.0)))
	max_slides = int(body.get("max_slides", 6))
	safe_margin = float(body.get("safe_margin_m", 0.01))
	_exclude = [get_rid()]
	_probe.exclude = _exclude
	_call = JsonData.get_dictionary(settings, "call", "horse.json")
	_call_path.prepare(heightfield, settings)
	_hoof_ray.name = "SondeSabot"
	_hoof_ray.enabled = false
	_hoof_ray.top_level = true
	_hoof_ray.collision_mask = GROUND_LAYER
	_hoof_ray.add_exception(self)
	_hoof_ray.target_position = Vector3.DOWN * 0.8
	add_child(_hoof_ray)
	_build_visual()
	_last_position = global_position
	locomotion.reset(rotation.y)


func set_input(move: Vector2, sprint: bool) -> void:
	_input_move = move.limit_length(1.0)
	_input_sprint = sprint


func call_to(position: Vector3) -> void:
	_call_target_node = null
	called_target = position
	_start_call()


## Suit la position actuelle du joueur durant tout l'appel, plutôt que son ancienne position au moment du sifflet.
func call_to_node(target: Node3D) -> void:
	if target == null:
		cancel_call()
		return
	_call_target_node = target
	called_target = target.global_position
	_start_call()


## Zone (x, z du monde) que le chemin de l'appel ne traverse jamais (enceinte d'une ville).
func block_call_area(rect: Rect2) -> void:
	_call_path.block_area(rect)


func cancel_call() -> void:
	is_called = false
	_call_target_node = null
	_call_path.path.clear()


## Chemin de l'appel en cours (vide tant qu'il n'est pas calculé, ou s'il n'y en a pas).
func call_path() -> PackedVector3Array:
	return _call_path.path


## Grille des chemins prête (calculée une fois en arrière-plan).
func is_path_grid_ready() -> bool:
	return _call_path.is_grid_ready()


## Pipeline de mesure : demande un chemin praticable sans activer le comportement de rappel autonome.
func request_pipeline_path(target: Vector3) -> void:
	_call_path.request(global_position, target)


## Pipeline de mesure : vrai quand le chemin demandé est disponible.
func poll_pipeline_path() -> bool:
	return _call_path.poll()


func pipeline_path() -> PackedVector3Array:
	return _call_path.path


func _start_call() -> void:
	if global_position.distance_to(called_target) > JsonData.get_float(_call, "max_distance_m", "horse.json > call"):
		return
	is_called = true
	_request_path()
	called.emit()


func _request_path() -> void:
	_path_goal = called_target
	_replan_timer = float(_call["replan_interval_s"])
	_waypoint = 0
	_call_path.path.clear()
	_call_path.request(global_position, called_target)


## Direction et allure de l'appel : droit vers le joueur s'il est proche ou s'il n'y a pas (encore) de chemin,
## sinon le long du chemin, point après point. Renvoie Vector2.ZERO à l'arrivée (l'appel se termine).
func _call_move(delta: float) -> Vector2:
	if is_instance_valid(_call_target_node):
		called_target = _call_target_node.global_position
	if _call_path.poll():
		_waypoint = 0
	_replan_timer -= delta
	var to_target: Vector3 = called_target - global_position
	to_target.y = 0.0
	var distance: float = to_target.length()
	if distance <= float(_call["arrival_distance_m"]):
		is_called = false
		_call_path.path.clear()
		return Vector2.ZERO
	if _replan_timer <= 0.0 and called_target.distance_to(_path_goal) > float(_call["replan_distance_m"]):
		_request_path()
	var aim: Vector3 = to_target
	var path: PackedVector3Array = _call_path.path
	if distance > float(_call["direct_distance_m"]) and _waypoint < path.size():
		var reach: float = float(_call["waypoint_reach_m"])
		while (
			_waypoint < path.size() - 1
			and ((Vector2(path[_waypoint].x - global_position.x, path[_waypoint].z - global_position.z).length()) < reach)
		):
			_waypoint += 1
		aim = path[_waypoint] - global_position
		aim.y = 0.0
	var amount: float = float(_call["walk_input"])
	if distance > float(_call["gallop_distance_m"]):
		amount = float(_call["gallop_input"])
	elif distance > float(_call["trot_distance_m"]):
		amount = float(_call["trot_input"])
	if aim.length_squared() < 0.0001:
		return Vector2.ZERO
	return Vector2(aim.x, aim.z).normalized() * amount


func _physics_process(delta: float) -> void:
	var started: int = Time.get_ticks_usec()
	var move: Vector2 = _input_move
	var sprint: bool = _input_sprint
	if is_called:
		move = _call_move(delta)
		sprint = false
	var speed_before: float = locomotion.speed
	var yaw_before: float = locomotion.yaw
	locomotion.update(move, sprint, delta)
	if speed_guard.is_valid():
		_apply_speed_guard(speed_before, yaw_before, delta)
	rotation.y = locomotion.yaw
	var next_gait: StringName = locomotion.get_gait_name()
	if next_gait != _last_gait:
		_last_gait = next_gait
		gait_changed.emit(next_gait)
	var heading: Vector3 = Vector3(-sin(locomotion.yaw), 0.0, -cos(locomotion.yaw))
	var intended: Vector3 = heading * locomotion.speed * delta
	if not _safe_to_move(intended):
		locomotion.speed = move_toward(locomotion.speed, 0.0, 10.0 * delta)
		intended = Vector3.ZERO
	velocity = intended / delta if delta > 0.0 else Vector3.ZERO
	_jump_cooldown = maxf(_jump_cooldown - delta, 0.0)
	var grounded: bool = is_on_floor() and not _airborne
	if grounded:
		_vertical_speed = 0.0
	else:
		_vertical_speed -= _gravity * delta
	velocity.y = _vertical_speed
	_step_retry = maxf(_step_retry - delta, 0.0)
	if grounded and intended.length_squared() > 0.0 and _try_step_up(intended):
		velocity.x = 0.0
		velocity.z = 0.0
	# L'accrochage couvre une marche descendante et la descente d'une pente à l'angle maximal.
	floor_snap_length = maxf(_step_max, 0.05 + intended.length() * tan(floor_max_angle))
	move_and_slide()
	if _airborne and is_on_floor() and _vertical_speed <= 0.0:
		_airborne = false
		_jump_cooldown = _jump_rest
		jump_landed.emit(global_position)
	if heightfield != null:
		var ground_y: float = heightfield.height_at(global_position.x, global_position.z)
		if global_position.y < ground_y - 0.5:
			# Cellule pas encore chargée (Barq appelé de loin) : il marche sur le relief, sans chute accumulée.
			global_position.y = ground_y
			velocity.y = 0.0
			_vertical_speed = 0.0
	_update_visual(delta, intended.length())
	_emit_hoofsteps(intended.length())
	last_step_usec = Time.get_ticks_usec() - started


## Règle de vitesse de la scène : au plus guard_deceleration·delta de vitesse perdue par image ; si le nouveau cap
## exige davantage, le virage est réduit (dichotomie, 4 appels au plus) au cap le plus tourné encore tenable.
func _apply_speed_guard(speed_before: float, yaw_before: float, delta: float) -> void:
	var floor_speed: float = maxf(speed_before - guard_deceleration * delta, 0.0)
	var limit: float = _guard_limit(locomotion.yaw)
	if limit < floor_speed and absf(angle_difference(yaw_before, locomotion.yaw)) > 0.0001:
		var wanted: float = locomotion.yaw
		var low: float = 0.0
		var high: float = 1.0
		for step: int in GUARD_TURN_STEPS:
			var middle: float = (low + high) * 0.5
			if _guard_limit(lerp_angle(yaw_before, wanted, middle)) >= floor_speed:
				low = middle
			else:
				high = middle
		locomotion.yaw = lerp_angle(yaw_before, wanted, low)
		limit = _guard_limit(locomotion.yaw)
	locomotion.speed = minf(locomotion.speed, maxf(limit, floor_speed))


func _guard_limit(yaw: float) -> float:
	return float(speed_guard.call(global_position, Vector3(-sin(yaw), 0.0, -cos(yaw))))


## Barq refuse d'avancer vers une pente impraticable, un à-pic ou un obstacle plus haut qu'une marche.
## Relief : au plus ceil(look_ahead_max_m / sample_spacing_m) lectures de la heightfield ; obstacles : un seul
## balayage de sphère qui suit le relief (base au-dessus des marches). Aucune allocation.
func _safe_to_move(motion: Vector3) -> bool:
	if motion.length_squared() < 0.000001:
		return true
	if movement_guard.is_valid() and not bool(movement_guard.call(global_position, motion)):
		return false
	var direction: Vector3 = motion.normalized()
	var origin: Vector3 = global_position
	var ground_here: float = origin.y
	if heightfield != null:
		ground_here = heightfield.height_at(origin.x, origin.z)
		var look_ahead: float = clampf(locomotion.speed * _look_time, _look_min, _look_max)
		var count: int = ceili(look_ahead / _sample_spacing)
		var previous: float = ground_here
		for index: int in range(1, count + 1):
			var distance: float = minf(float(index) * _sample_spacing, look_ahead)
			var x: float = origin.x + direction.x * distance
			var z: float = origin.z + direction.z * distance
			var height: float = heightfield.height_at(x, z)
			if heightfield.normal_at(x, z).y < _max_slope_cos or previous - height > _cliff_drop:
				return false
			previous = height
	if get_world_3d() == null:
		return true
	var reach: float = motion.length() + _probe_distance
	var ahead: Vector3 = origin + direction * reach
	var ground_ahead: float = ground_here if heightfield == null else heightfield.height_at(ahead.x, ahead.z)
	var lift: float = _probe_clearance + _probe_shape.radius
	var start := Vector3(origin.x, ground_here + lift, origin.z)
	_probe.transform = Transform3D(Basis.IDENTITY, start)
	_probe.motion = Vector3(ahead.x, ground_ahead + lift, ahead.z) - start
	var result: PackedFloat32Array = get_world_3d().direct_space_state.cast_motion(_probe)
	if result.is_empty() or result[0] >= 0.9999:
		return true
	# La sonde regarde en avance pour les falaises, mais un mur aperçu dans cette
	# marge ne doit pas arrêter Barq 7 à 15 m avant lui. Seul un impact pendant
	# l'image courante est bloquant ; move_and_slide() résout ensuite le contact.
	var probe_distance: float = _probe.motion.length() * result[0]
	return probe_distance > motion.length() + safe_margin


## Enjambe une marche (rocher bas, muret, bord de séguia) : au plus quatre requêtes, seulement quand le
## mouvement de l'image est bloqué par un mur ; après un échec, aucune tentative avant step_retry_delay_s.
func _try_step_up(motion: Vector3) -> bool:
	if _step_retry > 0.0:
		return false
	var origin: Transform3D = global_transform
	if not test_move(origin, motion, _step_collision, safe_margin, false, 1):
		return false
	if _step_collision.get_normal(0).y > cos(floor_max_angle):
		return false
	var direction: Vector3 = motion.normalized()
	var contact: Vector3 = _step_collision.get_position(0) - origin.origin
	var forward: Vector3 = direction * maxf(contact.dot(direction) + _step_inset, motion.length())
	var raise: float = _step_max
	if test_move(origin, Vector3.UP * (raise + _step_clearance), _step_collision, safe_margin, false, 1):
		raise = _step_collision.get_travel().y
	if raise >= _step_min:
		var raised: Transform3D = origin.translated(Vector3.UP * raise)
		if not test_move(raised, forward, null, safe_margin, false, 1):
			var landing: Transform3D = raised.translated(forward)
			if test_move(landing, Vector3.DOWN * (raise + _step_clearance), _step_collision, safe_margin, false, 1):
				var gained: float = raise + _step_collision.get_travel().y
				if gained >= _step_min and _step_collision.get_normal(0).y >= cos(floor_max_angle):
					global_position = landing.origin + _step_collision.get_travel()
					return true
	_step_retry = _step_retry_delay
	return false


## Saut demandé (monté) : seulement au sol, en mouvement et hors du temps de repos entre deux sauts.
func request_jump() -> bool:
	if _airborne or not is_on_floor() or _jump_cooldown > 0.0 or locomotion.speed < _jump_min_speed:
		return false
	if jump_guard.is_valid() and not bool(jump_guard.call(global_position)):
		return false
	_airborne = true
	_vertical_speed = _jump_speed
	jump_started.emit(global_position)
	if _animation_player != null and _jump_clip != &"":
		# Le clip de saut couvre l'appel, le vol et la réception : il dure le temps passé en l'air.
		var air_time: float = 2.0 * _vertical_speed / _gravity
		_animation_player.play(_jump_clip, _blend)
		_animation_player.speed_scale = (_animation_player.get_animation(_jump_clip).length / maxf(air_time, 0.1))
	return true


func is_airborne() -> bool:
	return _airborne


## Point de selle dans le monde (le bassin du cavalier s'y pose) : suit l'os du dos, axes orthonormés.
func seat_transform() -> Transform3D:
	if _visual == null or _visual.skeleton == null or _saddle_bone < 0:
		return Transform3D(global_basis.orthonormalized(), saddle_position())
	var bone: Transform3D = _visual.skeleton.global_transform * _visual.skeleton.get_bone_global_pose(_saddle_bone)
	var seat: Transform3D = bone * _bone_to_seat
	return Transform3D(seat.basis.orthonormalized(), seat.origin)


func surface_at(world_position: Vector3) -> StringName:
	return &"sable" if heightfield == null else heightfield.surface_at(world_position)


## Point de selle au repos (repère du monde), sans suivre l'animation.
func saddle_position() -> Vector3:
	return global_transform * _seat_local


## Un son de sabot à chaque battue : la foulée de l'allure est partagée en beats_per_stride battues (pas : 4,
## trot : 2, galop : 3). Les sabots alternent de part et d'autre du corps.
func _emit_hoofsteps(distance: float) -> void:
	if distance <= 0.0 or not is_on_floor() or _airborne:
		return
	_stride_distance += distance
	var gait: int = locomotion.gait
	var beat: float = _gait_stride[gait] / maxf(_gait_beats[gait], 1.0)
	if _stride_distance < beat:
		return
	_stride_distance = fmod(_stride_distance, beat)
	_hoof_side = -_hoof_side
	var hoof_position: Vector3 = global_position + global_basis.x * (0.25 * _hoof_side)
	# Un rayon par battue (au plus ~8 par seconde au galop), jamais par image : le collisionneur sous le sabot
	# donne sa surface aux sons et aux traces ; sans collisionneur, le relief (surface_at de Barq).
	var collider: Object = self
	var surface: StringName = surface_at(hoof_position)
	if _hoof_ray.is_inside_tree():
		_hoof_ray.global_position = hoof_position + Vector3.UP * 0.4
		_hoof_ray.force_raycast_update()
		if _hoof_ray.is_colliding():
			var body: Object = _hoof_ray.get_collider()
			if body != null:
				# Le son se résout comme pour les pas du personnage (métadonnée, terrain propriétaire, couvert du sol).
				collider = body
				if body.has_meta(&"surface"):
					surface = StringName(str(body.get_meta(&"surface")))
	hoofstep.emit(hoof_position, locomotion.speed, surface, collider)


func _exit_tree() -> void:
	_call_path.abort()


func _build_visual() -> void:
	_visual = HorseVisual.build(settings)
	if _visual == null:
		return
	add_child(_visual)
	_animation_player = _visual.animation_player
	# Hors de l'écran (et de ses ombres), squelette et animation s'arrêtent : aucun coût pour un Barq invisible.
	var notifier := VisibleOnScreenEnabler3D.new()
	notifier.name = "VisibleAEcran"
	notifier.aabb = AABB(Vector3(-1.5, -0.2, -2.0), Vector3(3.0, 3.0, 4.0))
	notifier.enable_mode = VisibleOnScreenEnabler3D.ENABLE_MODE_ALWAYS
	if _animation_player == null:
		return
	# Chemin fixé avant l'entrée dans l'arbre (sinon la cible par défaut, Barq lui-même, serait désactivée).
	notifier.enable_node_path = NodePath("../" + String(get_path_to(_animation_player)))
	add_child(notifier)
	var context: String = "horse.json > animations"
	var animations: Dictionary = JsonData.get_dictionary(settings, "animations", "horse.json")
	_gait_clips.clear()
	_gait_reference.clear()
	for gait_name: StringName in HorseLocomotion.GAIT_NAMES:
		var entry: Dictionary = JsonData.get_dictionary(animations, String(gait_name), context)
		_gait_clips.append(StringName(JsonData.get_string(entry, "clip", context)))
		_gait_reference.append(JsonData.get_float(entry, "reference_speed_mps", context))
	_idle_clip = StringName(JsonData.get_string(JsonData.get_dictionary(animations, "idle", context), "clip", context))
	_jump_clip = StringName(JsonData.get_string(JsonData.get_dictionary(animations, "jump", context), "clip", context))
	_idle_speed = JsonData.get_float(animations, "idle_speed_mps", context)
	_scale_min = JsonData.get_float(animations, "speed_scale_min", context)
	_scale_max = JsonData.get_float(animations, "speed_scale_max", context)
	_blend = JsonData.get_float(animations, "blend_s", context)
	for clip: StringName in _gait_clips + [_idle_clip, _jump_clip]:
		if _animation_player != null and not _animation_player.has_animation(clip):
			push_error("Barq : animation « %s » absente du modèle (%s)." % [clip, context])
	# Point de selle : passage de l'os du dos (pose de repos) au point de selle, dans le repère de Barq.
	var rider: Dictionary = JsonData.get_dictionary(settings, "rider", "horse.json")
	if _visual.skeleton != null:
		_saddle_bone = _visual.skeleton.find_bone(JsonData.get_string(rider, "saddle_bone", "horse.json > rider"))
		if _saddle_bone < 0:
			push_error("Barq : os de selle introuvable (horse.json > rider > saddle_bone).")
		else:
			var to_skeleton: Transform3D = _relative_transform(_visual.skeleton)
			var bone_rest: Transform3D = to_skeleton * _visual.skeleton.get_bone_global_rest(_saddle_bone)
			var offset: Array = JsonData.get_array(rider, "seat_offset_m", "horse.json > rider")
			# Décalage compté depuis l'os de selle au repos, dans les axes de Barq.
			_seat_local = (bone_rest.origin + Vector3(float(offset[0]), float(offset[1]), float(offset[2])))
			_bone_to_seat = bone_rest.affine_inverse() * Transform3D(Basis.IDENTITY, _seat_local)


## Transformation d'un descendant dans le repère de Barq (sans dépendre de l'arbre de scène).
func _relative_transform(node: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != self:
		if current is Node3D:
			result = (current as Node3D).transform * result
		current = current.get_parent()
	return result


## Clip de l'allure, lu à la vitesse qui fait coller les sabots au sol ; le saut garde son clip jusqu'à la réception.
func _update_visual(_delta: float, distance: float) -> void:
	if _animation_player == null or _airborne:
		return
	var speed: float = locomotion.speed
	var clip: StringName = _idle_clip
	var scale: float = 1.0
	if speed > _idle_speed and distance > 0.0001:
		clip = _gait_clips[locomotion.gait]
		scale = clampf(speed / _gait_reference[locomotion.gait], _scale_min, _scale_max)
	if _animation_player.current_animation != clip:
		_animation_player.play(clip, _blend)
	_animation_player.speed_scale = scale


func _layers_to_mask(layers: Array) -> int:
	var mask: int = 0
	for layer_value: Variant in layers:
		var layer: int = int(layer_value)
		if layer >= 1 and layer <= 32:
			mask |= 1 << (layer - 1)
	return mask
