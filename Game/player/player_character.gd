class_name PlayerCharacter
extends CharacterBody3D
## Personnage joueur : marche lente, marche, course, arrêts et virages (contrat du MVP 1).
##
## Fonctionne sans modèle (capsule de collision seule). Les entrées sont lues par PlayerInput,
## la logique d'allure par LocomotionMotor, la cadence des pas par FootstepTracker et les
## animations par PlayerAnimator (active seulement si animation_player est renseigné).
## Tous les réglages viennent de res://data/player/locomotion.json.
##
## Pires cas : changements de direction à chaque image à pleine vitesse, pente à l'angle
## maximal, coins rentrants, 1 000 obstacles autour du joueur, images de 2 ms à 100 ms.
## Par image : une seule requête de test de mouvement (marche), un seul déplacement physique,
## aucune allocation (objets de requête créés une fois) ; un rayon vers le bas par pas émis.

## Changement d'allure : &"idle", &"walk_slow", &"walk" ou &"run".
signal gait_changed(gait: StringName)
## Pas : foot 0 = gauche, 1 = droit ; collider = objet sous le pied ou null.
signal footstep(foot: int, world_position: Vector3, speed: float, collider: Object)

## AnimationPlayer du modèle (facultatif) : sans lui, le personnage n'a pas de visuel animé.
@export var animation_player: AnimationPlayer:
	set(value):
		animation_player = value
		if _animator != null:
			_animator.bind(value)

## Entrées (remplaçables par des entrées simulées dans les tests).
var input := PlayerInput.new()
## Logique d'allure (créée avec les réglages).
var motor: LocomotionMotor
## Vitesse horizontale réelle de la dernière image (m/s).
var real_speed: float = 0.0
## Multiplicateur de la vitesse de déplacement (1 = normal) : posé par les systèmes de terrain, par exemple l'eau.
var speed_multiplier: float = 1.0
## Durée de calcul de la dernière image physique (microsecondes), pour les mesures.
var last_step_usec: int = 0

var _settings: LocomotionSettings
var _animator: PlayerAnimator
var _tracker: FootstepTracker
var _ray: PhysicsRayQueryParameters3D
var _exclude: Array[RID] = []
var _step_collision := KinematicCollision3D.new()
var _step_retry_timer: float = 0.0
var _last_position: Vector3 = Vector3.ZERO
var _last_gait: int = LocomotionSettings.Gait.IDLE
var _last_gait_name: StringName = &"idle"
var _grounded: bool = false
var _ready_done: bool = false
## Distance parcourue au sol depuis le dernier appui de pied de l'animation.
var _contact_travel: float = 0.0


func _init(settings: LocomotionSettings = null) -> void:
	_settings = settings if settings != null else LocomotionSettings.load_file()
	motor = LocomotionMotor.new(_settings)
	_tracker = FootstepTracker.new(_settings)
	_animator = PlayerAnimator.new(_settings)
	collision_layer = _settings.collision_layer
	collision_mask = _settings.collision_mask
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	up_direction = Vector3.UP
	floor_max_angle = _settings.floor_max_angle
	floor_stop_on_slope = true
	floor_constant_speed = true
	floor_block_on_wall = true
	floor_snap_length = _settings.floor_snap_base_length
	wall_min_slide_angle = _settings.wall_min_slide_angle
	max_slides = _settings.max_slides
	safe_margin = _settings.safe_margin
	add_to_group(&"player")
	_ray = PhysicsRayQueryParameters3D.new()
	_ray.collision_mask = _settings.foot_ray_mask
	_ray.collide_with_areas = false
	_ray.collide_with_bodies = true


func _ready() -> void:
	if get_node_or_null("Collision") == null:
		var capsule := CapsuleShape3D.new()
		capsule.radius = _settings.body_radius
		capsule.height = _settings.body_height
		var shape := CollisionShape3D.new()
		shape.name = "Collision"
		shape.shape = capsule
		shape.position = Vector3(0.0, _settings.body_height * 0.5, 0.0)
		add_child(shape)
	_exclude = [get_rid()]
	_ray.exclude = _exclude
	_animator.bind(animation_player)
	_last_position = global_position
	motor.reset(rotation.y)
	_ready_done = true


func _physics_process(delta: float) -> void:
	step(delta)


## Réglages utilisés (lecture seule).
func get_settings() -> LocomotionSettings:
	return _settings


## Vrai quand une animation_player complète (contrat « locomotion ») est branchée.
func is_animating() -> bool:
	return _animator.is_bound()


## Vrai quand le personnage est posé au sol, y compris juste après la descente d'une marche.
func is_grounded() -> bool:
	return _grounded


## Allure actuelle : &"idle", &"walk_slow", &"walk" ou &"run".
func get_gait() -> StringName:
	return LocomotionSettings.GAIT_NAMES[motor.gait]


## Place le personnage sans déclencher de pas ni de virage.
func teleport_to(world_position: Vector3, yaw: float = 0.0) -> void:
	global_position = world_position
	rotation = Vector3(0.0, yaw, 0.0)
	velocity = Vector3.ZERO
	_grounded = false
	motor.reset(yaw)
	_tracker.reset(_settings.gait_stride_length[LocomotionSettings.Gait.WALK])
	_last_position = world_position
	real_speed = 0.0
	_step_retry_timer = 0.0


## Une image de déplacement (appelée par la physique ; publique pour les tests).
func step(delta: float) -> void:
	if not _ready_done or not (delta > 0.0):
		return
	var started: int = Time.get_ticks_usec()
	input.poll()
	var right: Vector2 = _view_right()
	var forward := Vector2(right.y, -right.x)
	var was_grounded: bool = _grounded
	motor.update(input.move, input.sprint, input.walk_slow, forward, right, was_grounded, delta)
	rotation.y = motor.yaw
	var heading: Vector2 = motor.forward_xz() * motor.speed * speed_multiplier
	velocity.x = heading.x
	velocity.z = heading.y
	if was_grounded:
		velocity.y = 0.0
	else:
		velocity.y = maxf(velocity.y - _settings.gravity * delta, -_settings.terminal_fall_speed)
	_step_retry_timer = maxf(_step_retry_timer - delta, 0.0)
	var stepped: bool = false
	if was_grounded and motor.speed > 0.0:
		stepped = _try_step_up(Vector3(heading.x, 0.0, heading.y) * delta)
	if stepped:
		velocity.x = 0.0
		velocity.z = 0.0
	# L'accrochage au sol couvre une marche descendante et la descente d'une pente à l'angle maximal.
	floor_snap_length = maxf(_settings.step_max_height, _settings.floor_snap_base_length + motor.speed * delta * tan(floor_max_angle))
	move_and_slide()
	_grounded = is_on_floor() or (was_grounded and _regain_ground())
	_update_outputs(delta, was_grounded)
	last_step_usec = Time.get_ticks_usec() - started


## Descente d'une marche : la capsule qui quitte le bord d'une marche ne touche plus que l'arête, dont la
## normale est trop inclinée pour l'accrochage au sol. Un rayon vertical sous le centre du corps lit la vraie
## surface ; si elle est praticable et à moins d'une marche, le personnage y est reposé sans chute.
## Un seul rayon, seulement à la perte du sol (une fois par marche descendue).
func _regain_ground() -> bool:
	var origin: Vector3 = global_position
	_ray.from = origin + Vector3.UP * _settings.step_clearance
	_ray.to = origin + Vector3.DOWN * _settings.step_max_height
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(_ray)
	if hit.is_empty() or (hit["normal"] as Vector3).y < cos(floor_max_angle):
		return false
	var ground: Vector3 = hit["position"]
	if ground.y > origin.y + _settings.step_clearance:
		return false
	global_position.y = minf(ground.y, origin.y)
	velocity.y = 0.0
	return true


## Axe « droite » horizontal de la caméra active (x, z du monde) ; (1, 0) sans caméra.
func _view_right() -> Vector2:
	var camera: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null:
		return Vector2.RIGHT
	var axis := Vector2(camera.global_basis.x.x, camera.global_basis.x.z)
	if axis.length_squared() < 0.0001:
		return Vector2.RIGHT
	return axis.normalized()


## Franchit une marche devant le personnage. Au plus quatre requêtes, seulement quand le
## mouvement de l'image est bloqué ; après un échec, aucune nouvelle tentative avant retry_delay.
func _try_step_up(motion: Vector3) -> bool:
	if _step_retry_timer > 0.0:
		return false
	var origin: Transform3D = global_transform
	if not test_move(origin, motion, _step_collision, safe_margin, false, 1):
		return false
	# Seul un mur (pas une pente praticable) est une marche potentielle.
	if _step_collision.get_normal(0).y > cos(floor_max_angle):
		return false
	var direction: Vector3 = motion.normalized()
	var contact: Vector3 = _step_collision.get_position(0) - origin.origin
	var forward_length: float = maxf(contact.dot(direction) + _settings.step_surface_inset, motion.length())
	var forward: Vector3 = direction * forward_length
	var raise: float = _settings.step_max_height
	if test_move(origin, Vector3.UP * (raise + _settings.step_clearance), _step_collision, safe_margin, false, 1):
		raise = _step_collision.get_travel().y
	if raise >= _settings.step_min_height:
		var raised: Transform3D = origin.translated(Vector3.UP * raise)
		var probe: Vector3 = forward + direction * _settings.step_headroom_probe_distance
		if not test_move(raised, probe, null, safe_margin, false, 1):
			var landing: Transform3D = raised.translated(forward)
			var drop: Vector3 = Vector3.DOWN * (raise + _settings.step_clearance)
			if test_move(landing, drop, _step_collision, safe_margin, false, 1):
				var gained: float = raise + _step_collision.get_travel().y
				if gained >= _settings.step_min_height and _step_collision.get_normal(0).y >= cos(floor_max_angle):
					global_position = landing.origin + _step_collision.get_travel()
					return true
	_step_retry_timer = _settings.climb_retry_delay
	return false


func _update_outputs(delta: float, was_grounded: bool) -> void:
	var travelled: Vector3 = global_position - _last_position
	_last_position = global_position
	var grounded: bool = _grounded
	var distance: float = travelled.length()
	real_speed = Vector2(travelled.x, travelled.z).length() / delta
	var gait_value: int = motor.gait
	if gait_value != _last_gait:
		var previous: int = _last_gait
		_last_gait = gait_value
		_last_gait_name = LocomotionSettings.GAIT_NAMES[gait_value]
		if gait_value == LocomotionSettings.Gait.IDLE and previous != LocomotionSettings.Gait.IDLE:
			if _tracker.stop(_settings.stride_for(previous)) and not _animator.has_contacts():
				_emit_footstep(real_speed, -1)
		gait_changed.emit(_last_gait_name)
	_animator.update(motor, real_speed)
	if _animator.has_contacts():
		# Pas calés sur l'animation : un pas par appui de pied franchi par la lecture, au sol, et seulement si le
		# personnage a réellement avancé depuis l'appui précédent (poussé contre un mur, l'animation tourne : silence).
		if grounded and was_grounded and distance < _settings.teleport_distance:
			_contact_travel += distance
		for i: int in _animator.crossed_count():
			if grounded and _contact_travel >= _settings.contact_min_travel:
				_emit_footstep(real_speed, _animator.foot_of(i))
			_contact_travel = 0.0
	elif grounded and was_grounded and distance > 0.0:
		var stride: float = _settings.stride_for(motor.motion_gait)
		var count: int = _tracker.advance(distance, stride)
		for i: int in count:
			_emit_footstep(real_speed, -1)
	elif distance > _settings.teleport_distance:
		_tracker.reset(_settings.stride_for(motor.motion_gait))


## Émet un pas. foot = pied posé d'après l'animation (position lue sur le squelette), ou -1 : pied suivant de
## l'alternance, posé à côté du centre du corps (personnage sans modèle animé).
func _emit_footstep(speed_value: float, animated_foot: int) -> void:
	var foot: int = animated_foot
	var position_on_ground: Vector3
	if foot >= 0:
		position_on_ground = _animator.foot_world_position(foot)
	else:
		foot = _tracker.take_foot()
		var lateral: float = _settings.foot_lateral_offset if foot == FootstepTracker.RIGHT else -_settings.foot_lateral_offset
		position_on_ground = global_position + global_basis.x * lateral
	var collider: Object = null
	_ray.from = position_on_ground + Vector3.UP * _settings.foot_ray_start_height
	_ray.to = position_on_ground + Vector3.DOWN * _settings.foot_ray_depth
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(_ray)
	if not hit.is_empty():
		position_on_ground = hit["position"]
		collider = hit["collider"]
	footstep.emit(foot, position_on_ground, speed_value, collider)
