class_name FreeCamera
extends Camera3D
## Caméra libre du bac à sable : déplacement au clavier ou à la manette, regard à la souris
## (bouton droit maintenu) ou au stick droit. Les actions viennent de res://data/input/actions.json.

const PITCH_LIMIT: float = deg_to_rad(89.0)

@export var move_speed: float = 6.0
@export var sprint_multiplier: float = 4.0
@export var mouse_sensitivity: float = 0.0025
@export var stick_look_speed: float = 2.5

var _yaw: float = 0.0
var _pitch: float = 0.0


func _ready() -> void:
	_yaw = rotation.y
	_pitch = rotation.x


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"look_hold"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_released(&"look_hold"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion: InputEventMouseMotion = event
		_yaw -= motion.relative.x * mouse_sensitivity
		_pitch = clampf(_pitch - motion.relative.y * mouse_sensitivity, -PITCH_LIMIT, PITCH_LIMIT)


func _process(delta: float) -> void:
	var look: Vector2 = Input.get_vector(&"look_left", &"look_right", &"look_up", &"look_down")
	_yaw -= look.x * stick_look_speed * delta
	_pitch = clampf(_pitch - look.y * stick_look_speed * delta, -PITCH_LIMIT, PITCH_LIMIT)
	rotation = Vector3(_pitch, _yaw, 0.0)
	var planar: Vector2 = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var vertical: float = Input.get_axis(&"move_down", &"move_up")
	var direction: Vector3 = global_basis * Vector3(planar.x, 0.0, planar.y) + Vector3.UP * vertical
	if direction.length_squared() > 1.0:
		direction = direction.normalized()
	var speed: float = move_speed * (sprint_multiplier if Input.is_action_pressed(&"sprint") else 1.0)
	global_position += direction * speed * delta
