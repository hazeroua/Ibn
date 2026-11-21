class_name FreeCamera
extends Camera3D
## Caméra libre de la scène de test : souris ou stick droit pour regarder,
## déplacements au clavier ou au stick gauche, sprint pour tester le streaming
## à grande vitesse. Elle ne descend jamais sous le relief ni hors de la carte.

const MAX_PITCH_RADIANS: float = deg_to_rad(85.0)

var walk_speed: float = 12.0
var sprint_speed: float = 70.0
var mouse_sensitivity: float = 0.0025
var stick_sensitivity: float = 2.5
var min_height_above_ground: float = 1.8
var map_half_extent: float = 2048.0
## Données Terrain3D utilisées pour ne jamais passer sous le relief.
var terrain_data: Terrain3DData

var _yaw: float = 0.0
var _pitch: float = 0.0


func configure(data: Dictionary, errors: PackedStringArray, context: String) -> void:
	walk_speed = JsonData.read_number(data, "walk_speed", errors, context)
	sprint_speed = JsonData.read_number(data, "sprint_speed", errors, context)
	mouse_sensitivity = JsonData.read_number(data, "mouse_sensitivity", errors, context)
	stick_sensitivity = JsonData.read_number(data, "stick_sensitivity", errors, context)
	min_height_above_ground = JsonData.read_number(data, "min_height_above_ground", errors, context)


func look_toward(target: Vector3) -> void:
	var direction: Vector3 = (target - global_position).normalized()
	_yaw = atan2(-direction.x, -direction.z)
	_pitch = clampf(asin(direction.y), -MAX_PITCH_RADIANS, MAX_PITCH_RADIANS)
	_apply_rotation()


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_mouse_capture"):
		var captured: bool = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if captured else Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
		return
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion != null and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_rotate_view(-motion.screen_relative.x * mouse_sensitivity, -motion.screen_relative.y * mouse_sensitivity)


func _process(delta: float) -> void:
	var look: Vector2 = Input.get_vector(&"look_left", &"look_right", &"look_up", &"look_down")
	if look != Vector2.ZERO:
		_rotate_view(-look.x * stick_sensitivity * delta, -look.y * stick_sensitivity * delta)

	var planar: Vector2 = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var vertical: float = Input.get_axis(&"descend", &"ascend")
	if planar == Vector2.ZERO and vertical == 0.0:
		return
	var speed: float = sprint_speed if Input.is_action_pressed(&"sprint") else walk_speed
	var movement: Vector3 = global_basis * Vector3(planar.x, 0.0, planar.y) + Vector3.UP * vertical
	var target: Vector3 = global_position + movement * speed * delta
	target.x = clampf(target.x, -map_half_extent, map_half_extent)
	target.z = clampf(target.z, -map_half_extent, map_half_extent)
	var ground: float = terrain_data.get_height(target)
	if not is_nan(ground):
		target.y = maxf(target.y, ground + min_height_above_ground)
	global_position = target


func _rotate_view(yaw_delta: float, pitch_delta: float) -> void:
	_yaw = wrapf(_yaw + yaw_delta, -PI, PI)
	_pitch = clampf(_pitch + pitch_delta, -MAX_PITCH_RADIANS, MAX_PITCH_RADIANS)
	_apply_rotation()


func _apply_rotation() -> void:
	basis = Basis.from_euler(Vector3(_pitch, _yaw, 0.0))
