class_name RouteRunner
extends CharacterBody3D
## Corps de test des collisions : une capsule de la taille d'un personnage parcourt
## une boucle de points de passage à vitesse de marche, de course puis à pleine
## vitesse, avec la gravité et move_and_slide, comme le futur joueur. Il compte :
## - les passages sous la surface de collision (rayon lancé d'en haut, dix fois par seconde) ;
## - les blocages (aucune progression pendant deux secondes).
## Aucun objet n'est alloué par image.

const BELOW_GROUND_TOLERANCE_METERS: float = 0.35
const STUCK_WINDOW_SECONDS: float = 1.0
const STUCK_PROGRESS_RATIO: float = 0.15
const STUCK_WINDOWS_BEFORE_EVENT: int = 2
const EVENT_COOLDOWN_SECONDS: float = 1.0
const GROUND_CHECK_INTERVAL_SECONDS: float = 0.1
const GROUND_RAY_HEIGHT_METERS: float = 60.0

var terrain_data: Terrain3DData
var below_ground_events: int = 0
var stuck_events: int = 0
var distance_meters: float = 0.0

var _waypoints: PackedVector2Array = PackedVector2Array()
var _phase_names: PackedStringArray = PackedStringArray()
var _phase_speeds: PackedFloat32Array = PackedFloat32Array()
## Fin de chaque phase, en part cumulée de la durée de mesure.
var _phase_ends: PackedFloat32Array = PackedFloat32Array()
var _target_index: int = 1
var _phase_index: int = -1
var _gravity: float = 9.8
var _heading: Vector3 = Vector3.FORWARD
var _window_seconds: float = 0.0
var _window_progress: float = 0.0
var _slow_windows: int = 0
var _below_cooldown: float = 0.0
var _ground_check_timer: float = 0.0
var _ground_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()


func configure(data: Dictionary, errors: PackedStringArray, context: String) -> void:
	var loop: Variant = data.get("loop")
	if typeof(loop) != TYPE_ARRAY or (loop as Array).size() < 3:
		errors.append(context + " : « loop » doit contenir au moins trois points.")
	else:
		for point: Variant in loop:
			if typeof(point) != TYPE_ARRAY or (point as Array).size() != 2:
				errors.append(context + " : chaque point de « loop » est une paire [x, z].")
				return
			_waypoints.append(Vector2(float(point[0]), float(point[1])))
	var phases: Variant = data.get("phases")
	if typeof(phases) != TYPE_ARRAY or (phases as Array).is_empty():
		errors.append(context + " : « phases » doit être une liste non vide.")
		return
	var cumulative: float = 0.0
	for phase: Variant in phases:
		if typeof(phase) != TYPE_DICTIONARY:
			errors.append(context + " : chaque phase est un objet.")
			return
		_phase_names.append(JsonData.read_string(phase, "name", errors, context + " › phases"))
		_phase_speeds.append(JsonData.read_number(phase, "speed_meters_per_second", errors, context + " › phases"))
		cumulative += JsonData.read_number(phase, "duration_fraction", errors, context + " › phases")
		_phase_ends.append(cumulative)
	if not is_equal_approx(cumulative, 1.0):
		errors.append(context + " : la somme des « duration_fraction » doit valoir 1.")

	var body: Dictionary = JsonData.read_dictionary(data, "body", errors, context)
	var radius: float = JsonData.read_number(body, "radius_meters", errors, context + " › body")
	var height: float = JsonData.read_number(body, "height_meters", errors, context + " › body")
	floor_max_angle = deg_to_rad(JsonData.read_number(body, "max_slope_degrees", errors, context + " › body"))
	var shape: CapsuleShape3D = CapsuleShape3D.new()
	shape.radius = radius
	shape.height = height
	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.shape = shape
	collision.position = Vector3.UP * height * 0.5
	add_child(collision)
	_ground_query.exclude = [get_rid()]
	_ground_query.collide_with_areas = false
	floor_constant_speed = true
	floor_snap_length = 0.6
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity"))


## Pose le corps au premier point de passage, sur le sol.
func place_at_start() -> void:
	var start: Vector2 = _waypoints[0]
	global_position = Vector3(start.x, terrain_data.get_height(Vector3(start.x, 0.0, start.y)) + 0.1, start.y)
	velocity = Vector3.ZERO
	_target_index = 1


## Direction horizontale de déplacement (pour la caméra de poursuite).
func heading() -> Vector3:
	return _heading


## Avance d'un pas physique ; `fraction` est la part écoulée de la mesure.
func step(delta: float, fraction: float) -> void:
	_update_phase(fraction)
	var speed: float = _phase_speeds[_phase_index]
	var position_2d: Vector2 = Vector2(global_position.x, global_position.z)
	var target: Vector2 = _waypoints[_target_index]
	if position_2d.distance_to(target) <= maxf(2.0, speed * delta * 2.0):
		_advance_target()
		target = _waypoints[_target_index]
	var direction: Vector2 = (target - position_2d).normalized()
	_heading = Vector3(direction.x, 0.0, direction.y)
	velocity.x = direction.x * speed
	velocity.z = direction.y * speed
	velocity.y = 0.0 if is_on_floor() else velocity.y - _gravity * delta
	floor_snap_length = 0.6 + speed * 0.02
	var before: Vector3 = global_position
	move_and_slide()
	var moved: float = Vector2(global_position.x - before.x, global_position.z - before.z).length()
	distance_meters += moved
	_check_below_ground(delta)
	_check_stuck(delta, moved, speed)


func _update_phase(fraction: float) -> void:
	var phase: int = 0
	while phase < _phase_ends.size() - 1 and fraction >= _phase_ends[phase]:
		phase += 1
	if phase != _phase_index:
		_phase_index = phase
		GameLog.info("parcours", "Phase « %s » à %.1f m/s." % [_phase_names[phase], _phase_speeds[phase]])


func _advance_target() -> void:
	_target_index = (_target_index + 1) % _waypoints.size()


func _check_below_ground(delta: float) -> void:
	_below_cooldown = maxf(_below_cooldown - delta, 0.0)
	_ground_check_timer += delta
	if _ground_check_timer < GROUND_CHECK_INTERVAL_SECONDS:
		return
	_ground_check_timer = 0.0
	# Première surface rencontrée en descendant de haut : si elle est au-dessus des pieds,
	# le corps a traversé la collision.
	_ground_query.from = global_position + Vector3.UP * GROUND_RAY_HEIGHT_METERS
	_ground_query.to = global_position + Vector3.DOWN * GROUND_RAY_HEIGHT_METERS
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(_ground_query)
	if hit.is_empty():
		return
	var surface: float = (hit["position"] as Vector3).y
	if global_position.y >= surface - BELOW_GROUND_TOLERANCE_METERS:
		return
	if _below_cooldown <= 0.0:
		below_ground_events += 1
		_below_cooldown = EVENT_COOLDOWN_SECONDS
		GameLog.warning("parcours", "Corps sous la collision en %s (surface à %.2f m)." % [str(global_position), surface])
	global_position.y = surface + 0.1
	velocity.y = 0.0


func _check_stuck(delta: float, moved: float, speed: float) -> void:
	_window_seconds += delta
	_window_progress += moved
	if _window_seconds < STUCK_WINDOW_SECONDS:
		return
	if _window_progress < speed * _window_seconds * STUCK_PROGRESS_RATIO:
		_slow_windows += 1
	else:
		_slow_windows = 0
	_window_seconds = 0.0
	_window_progress = 0.0
	if _slow_windows < STUCK_WINDOWS_BEFORE_EVENT:
		return
	stuck_events += 1
	_slow_windows = 0
	GameLog.warning("parcours", "Corps bloqué en %s : passage au point suivant." % str(global_position))
	_advance_target()
	var target: Vector2 = _waypoints[_target_index]
	global_position = Vector3(target.x, terrain_data.get_height(Vector3(target.x, 0.0, target.y)) + 0.1, target.y)
	velocity = Vector3.ZERO
