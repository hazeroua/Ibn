class_name ThirdPersonCamera
extends Node3D
## Caméra à la troisième personne : orbite autour de « target » (n'importe quel Node3D), bras avec
## collisions, suivi lissé, rapprocher et éloigner, champ de vision élargi en course, fondu de la cible
## quand la caméra s'en approche trop. Réglages : res://data/player/camera.json.
##
## Fonctionnement d'une image (step) :
## 1. Le point visé (au-dessus de la cible) est suivi avec un lissage exponentiel et un retard borné.
## 2. Une sphère est balayée de la cible vers ce point (plafond bas, retard qui passerait dans un mur),
##    puis de ce point vers la position voulue de la caméra (bras). La sphère enveloppe le plan proche :
##    l'image ne traverse jamais le décor des couches de collision réglées (1 et 4).
## 3. Le bras raccourcit immédiatement contre un obstacle et ne s'allonge que progressivement ensuite.
##
## Tous les lissages sont de la forme « objectif + écart × exp(-taux × durée) » : le résultat ne dépend
## pas de la fréquence d'images. Aucune allocation par image : seules des valeurs (Vector3, Basis)
## sont manipulées, et le balayage passe par un ShapeCast3D sans résultat de contact (max_results = 0).
##
## Entrées : la lecture des actions et de la souris est isolée dans _process et _unhandled_input ;
## add_mouse_motion, add_stick_input et zoom_by_steps permettent de piloter la caméra sans entrée.
## Mettre input_enabled à false avant l'entrée dans l'arbre pour ne lire aucune action (tests).

const ACTION_LOOK_LEFT: StringName = &"look_left"
const ACTION_LOOK_RIGHT: StringName = &"look_right"
const ACTION_LOOK_UP: StringName = &"look_up"
const ACTION_LOOK_DOWN: StringName = &"look_down"
const ACTION_ZOOM_IN: StringName = &"camera_zoom_in"
const ACTION_ZOOM_OUT: StringName = &"camera_zoom_out"
const REQUIRED_ACTIONS: Array[StringName] = [
	ACTION_LOOK_LEFT, ACTION_LOOK_RIGHT, ACTION_LOOK_UP, ACTION_LOOK_DOWN, ACTION_ZOOM_IN, ACTION_ZOOM_OUT
]
## Ordre de traitement : après les nœuds de jeu, pour suivre la cible dans sa position de l'image.
const PROCESS_ORDER_AFTER_GAMEPLAY: int = 1000

## Lit les actions d'entrée et la souris. À désactiver avant l'entrée dans l'arbre pour les tests.
@export var input_enabled: bool = true

## Nœud suivi par la caméra.
var target: Node3D = null:
	set = set_target

## Caméra rendue (enfant, rendue active à l'entrée dans l'arbre).
var camera: Camera3D = null
## Réglages en vigueur (voir apply_settings).
var settings: CameraSettings = null

var _probe: ShapeCast3D = null
var _probe_shape: SphereShape3D = null
var _fader: CameraTargetFader = CameraTargetFader.new()
var _input_ready: bool = false
var _captured_mouse: bool = false
var _needs_snap: bool = true
var _yaw: float = 0.0
var _pitch: float = 0.0
var _yaw_goal: float = 0.0
var _pitch_goal: float = 0.0
var _zoom_goal: float = 0.0
var _zoom_distance: float = 0.0
var _arm_length: float = 0.0
var _speed: float = 0.0
var _fov: float = 0.0
var _pivot: Vector3 = Vector3.ZERO
var _focus: Vector3 = Vector3.ZERO
var _last_head: Vector3 = Vector3.ZERO


func _init() -> void:
	top_level = true
	process_priority = PROCESS_ORDER_AFTER_GAMEPLAY
	# La caméra est placée dans _process : l'interpolation physique ne doit pas la décaler.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera = Camera3D.new()
	camera.name = "Camera"
	add_child(camera)
	_probe_shape = SphereShape3D.new()
	_probe = ShapeCast3D.new()
	_probe.name = "CollisionProbe"
	_probe.top_level = true
	_probe.enabled = false
	_probe.max_results = 0
	_probe.exclude_parent = false
	_probe.collide_with_areas = false
	_probe.collide_with_bodies = true
	_probe.shape = _probe_shape
	add_child(_probe)
	apply_settings(CameraSettings.load_default())


func _ready() -> void:
	camera.make_current()
	_input_ready = false
	if not input_enabled:
		return
	var missing: PackedStringArray = PackedStringArray()
	for action: StringName in REQUIRED_ACTIONS:
		if not InputMap.has_action(action):
			missing.append(String(action))
	if not missing.is_empty():
		push_error("ThirdPersonCamera : actions d'entrée absentes : %s." % ", ".join(missing))
		return
	_input_ready = true
	if settings.capture_mouse_on_start:
		_capture_mouse()


func _exit_tree() -> void:
	_fader.reset()
	if _captured_mouse:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_captured_mouse = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN and _input_ready and settings.capture_mouse_on_start and is_inside_tree():
		_capture_mouse()


func _unhandled_input(event: InputEvent) -> void:
	if not _input_ready:
		return
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion != null:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			add_mouse_motion(motion.screen_relative)
		return
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button != null and button.pressed and settings.capture_mouse_on_start and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_capture_mouse()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(ACTION_ZOOM_IN):
		zoom_by_steps(-1)
	elif event.is_action_pressed(ACTION_ZOOM_OUT):
		zoom_by_steps(1)


func _process(delta: float) -> void:
	if _input_ready:
		add_stick_input(Input.get_vector(ACTION_LOOK_LEFT, ACTION_LOOK_RIGHT, ACTION_LOOK_UP, ACTION_LOOK_DOWN), delta)
	step(delta)


## Applique de nouveaux réglages et replace la caméra dans son état initial à la prochaine image.
func apply_settings(new_settings: CameraSettings) -> void:
	settings = new_settings
	camera.near = settings.near
	camera.far = settings.far
	camera.fov = settings.fov_base_deg
	_fov = settings.fov_base_deg
	_probe_shape.radius = settings.probe_radius
	_probe.collision_mask = settings.collision_mask
	_yaw_goal = wrapf(settings.initial_yaw, -PI, PI)
	_pitch_goal = settings.initial_pitch
	_zoom_goal = settings.zoom_initial
	_speed = 0.0
	_needs_snap = true


## Change de réglages sans saut (monte, descente) : l'orientation est gardée, le recul et le champ rejoignent
## les nouveaux réglages avec leur lissage habituel. Sans effet si les réglages sont déjà ceux-là.
func blend_to_settings(new_settings: CameraSettings) -> void:
	if new_settings == settings:
		return
	settings = new_settings
	camera.near = settings.near
	camera.far = settings.far
	_probe_shape.radius = settings.probe_radius
	_probe.collision_mask = settings.collision_mask
	_pitch_goal = clampf(_pitch_goal, settings.pitch_min, settings.pitch_max)
	_zoom_goal = settings.zoom_initial


func set_target(value: Node3D) -> void:
	target = value
	_fader.set_target(value)
	_needs_snap = true


## Change de cible en glissant de l'ancienne à la nouvelle (monte et descente de cheval), sans placement direct.
func glide_to_target(value: Node3D) -> void:
	var was_snapping: bool = _needs_snap
	target = value
	_needs_snap = was_snapping


## Place la caméra directement à sa position voulue à la prochaine image (sans lissage).
func snap() -> void:
	_needs_snap = true


## Mouvement de la souris capturée, en pixels d'écran.
func add_mouse_motion(relative: Vector2) -> void:
	var sign_x: float = -1.0 if settings.mouse_invert_x else 1.0
	var sign_y: float = -1.0 if settings.mouse_invert_y else 1.0
	_turn(relative.x * settings.mouse_sensitivity * sign_x, relative.y * settings.mouse_sensitivity * sign_y)


## Stick droit (x vers la droite, y vers le bas, longueur au plus 1) pendant « delta » secondes.
func add_stick_input(stick: Vector2, delta: float) -> void:
	var length: float = stick.length()
	if length <= 0.0:
		return
	var direction: Vector2 = stick / length
	var amount: float = pow(minf(length, 1.0), settings.stick_response_exponent) * settings.stick_speed * delta
	var sign_x: float = -1.0 if settings.stick_invert_x else 1.0
	var sign_y: float = -1.0 if settings.stick_invert_y else 1.0
	_turn(direction.x * amount * sign_x, direction.y * amount * sign_y)


## Rapproche (pas négatifs) ou éloigne (pas positifs) la caméra, entre les deux distances limites.
func zoom_by_steps(steps: int) -> void:
	_zoom_goal = clampf(_zoom_goal + float(steps) * settings.zoom_step, settings.zoom_min, settings.zoom_max)


## Angle horizontal de l'orbite (radians, entre -PI et PI).
func get_yaw() -> float:
	return _yaw


## Angle vertical de l'orbite (radians ; positif : caméra au-dessus, regard vers le bas).
func get_pitch() -> float:
	return _pitch


## Distance voulue par le joueur (rapprocher, éloigner).
func get_zoom_goal() -> float:
	return _zoom_goal


## Longueur actuelle du bras, après collisions.
func get_arm_length() -> float:
	return _arm_length


## Point regardé par la caméra, à l'origine du bras (toujours relié à la cible sans traverser le décor).
func get_focus_point() -> Vector3:
	return _focus


## Vitesse de la cible estimée par la caméra (m/s, lissée).
func get_target_speed() -> float:
	return _speed


## Fondu actuel de la cible (0 : visible, 1 : effacée).
func get_target_fade() -> float:
	return _fader.get_fade()


## Avance la caméra de « delta » secondes : appelée par _process, ou directement par les tests.
func step(delta: float) -> void:
	if target == null or not is_instance_valid(target) or not target.is_inside_tree() or not is_inside_tree():
		return
	var dt: float = maxf(delta, 0.0)
	var origin: Vector3 = _read_target_transform().origin
	var anchor: Vector3 = origin + Vector3.UP * settings.probe_origin_height
	var head: Vector3 = origin + Vector3.UP * settings.pivot_height

	var snapping: bool = _needs_snap
	if snapping:
		_speed = 0.0
		_fov = settings.fov_base_deg
	elif head.distance_squared_to(_last_head) > settings.teleport_distance * settings.teleport_distance:
		# Téléportation : la caméra rejoint la cible sans glisser à travers le monde.
		snapping = true
	elif dt > 0.0:
		var measured: float = head.distance_to(_last_head) / dt
		_speed = measured + (_speed - measured) * exp(-settings.speed_smoothing * dt)
	_last_head = head

	if snapping:
		_needs_snap = false
		_yaw = _yaw_goal
		_pitch = _pitch_goal
		_zoom_distance = _zoom_goal
		_pivot = head
	else:
		var rotation_keep: float = exp(-settings.rotation_smoothing * dt)
		_yaw = wrapf(_yaw_goal - angle_difference(_yaw, _yaw_goal) * rotation_keep, -PI, PI)
		_pitch = _pitch_goal + (_pitch - _pitch_goal) * rotation_keep
		_zoom_distance = _zoom_goal + (_zoom_distance - _zoom_goal) * exp(-settings.zoom_smoothing * dt)
		_pivot = head + (_pivot - head) * exp(-settings.follow_smoothing * dt)
		var lag: Vector3 = _pivot - head
		var max_lag: float = settings.follow_max_lag
		if lag.length_squared() > max_lag * max_lag:
			_pivot = head + lag.normalized() * max_lag

	# Origine du bras : reliée à la cible par un balayage (plafond bas, retard qui longe un mur).
	var reach: Vector3 = _pivot - anchor
	_focus = anchor + reach * _clear_fraction(anchor, reach)

	var orbit: Basis = Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, -_pitch)
	var arm: Vector3 = orbit * Vector3(settings.shoulder_offset, 0.0, _zoom_distance)
	var full_length: float = arm.length()
	var free_length: float = full_length * _clear_fraction(_focus, arm)
	if snapping or free_length < _arm_length:
		# Rapprochement immédiat contre un obstacle.
		_arm_length = free_length
	else:
		# Éloignement progressif une fois l'obstacle dégagé.
		_arm_length = free_length + (_arm_length - free_length) * exp(-settings.return_smoothing * dt)
	var camera_position: Vector3 = _focus + arm * (_arm_length / full_length)
	global_transform = Transform3D(orbit, camera_position)

	var run: float = clampf((_speed - settings.fov_speed_start) / (settings.fov_speed_full - settings.fov_speed_start), 0.0, 1.0)
	var fov_goal: float = settings.fov_base_deg + settings.fov_run_bonus_deg * run * run * (3.0 - 2.0 * run)
	_fov = fov_goal + (_fov - fov_goal) * exp(-settings.fov_smoothing * dt)
	camera.fov = _fov

	var head_distance: float = camera_position.distance_to(head)
	var fade_span: float = settings.fade_start_distance - settings.fade_end_distance
	var fade_goal: float = clampf((settings.fade_start_distance - head_distance) / fade_span, 0.0, 1.0)
	_fader.update(fade_goal, settings.fade_smoothing, dt)


func _turn(yaw_amount: float, pitch_amount: float) -> void:
	# Vers la droite : l'orbite tourne dans le sens horaire vu du dessus ; vers le bas : la caméra monte.
	_yaw_goal = wrapf(_yaw_goal - yaw_amount, -PI, PI)
	_pitch_goal = clampf(_pitch_goal + pitch_amount, settings.pitch_min, settings.pitch_max)


func _read_target_transform() -> Transform3D:
	if target.is_physics_interpolated_and_enabled():
		return target.get_global_transform_interpolated()
	return target.global_transform


## Fraction du déplacement « motion » depuis « from » que la sphère de collision parcourt sans toucher
## le décor, en s'arrêtant à contact_skin de l'obstacle éventuel.
func _clear_fraction(from: Vector3, motion: Vector3) -> float:
	var length: float = motion.length()
	if length <= 0.0:
		return 1.0
	_probe.global_transform = Transform3D(Basis.IDENTITY, from)
	_probe.target_position = motion
	_probe.force_shapecast_update()
	var fraction: float = _probe.get_closest_collision_safe_fraction()
	if fraction >= 1.0:
		return 1.0
	return maxf(0.0, fraction - settings.contact_skin / length)


func _capture_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_captured_mouse = true
