class_name HorseController
extends CharacterBody3D
## Barq : déplacement physique, relief, évitement et animation procédurale bornée.
## Le modèle équin libre est injecté par HorseMountSystem lorsqu'il est disponible ; la géométrie
## de la selle et des volumes de référence reste générée ici pour garder la scène recréable.

signal hoofstep(world_position: Vector3, speed: float, surface: StringName)
signal gait_changed(gait: StringName)
signal called

const SETTINGS_PATH: String = "res://data/horse/horse.json"
const GROUND_LAYER: int = 1

var locomotion: HorseLocomotion
var settings: Dictionary = {}
var heightfield: DesertHeightfield
var mounted: bool = false
var called_target: Vector3 = Vector3.ZERO
var is_called: bool = false
var last_step_usec: int = 0

var _visual_root: Node3D
var _legs: Array[MeshInstance3D] = []
var _input_move: Vector2 = Vector2.ZERO
var _input_sprint: bool = false
var _last_position: Vector3 = Vector3.ZERO
var _stride_distance: float = 0.0
var _phase: float = 0.0
var _probe: PhysicsShapeQueryParameters3D
var _probe_shape: SphereShape3D
var _exclude: Array[RID] = []
var _last_gait: StringName = &"walk"


func _init(field: DesertHeightfield = null) -> void:
	settings = JsonData.load_dictionary(SETTINGS_PATH)
	heightfield = field
	locomotion = HorseLocomotion.new(settings)
	_probe_shape = SphereShape3D.new()
	var terrain: Dictionary = settings.get("terrain", {}) as Dictionary
	_probe_shape.radius = float(terrain.get("obstacle_probe_radius_m", 0.82))
	_probe = PhysicsShapeQueryParameters3D.new()
	_probe.shape = _probe_shape
	_probe.collision_mask = GROUND_LAYER
	_probe.collide_with_areas = false
	_probe.collide_with_bodies = true
	add_to_group(&"horse")


func _ready() -> void:
	var body: Dictionary = settings.get("body", {}) as Dictionary
	var capsule := CapsuleShape3D.new()
	capsule.radius = float(body.get("radius_m", 0.72))
	capsule.height = float(body.get("height_m", 1.9))
	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	collision.shape = capsule
	collision.position = Vector3(0.0, capsule.height * 0.5, 0.0)
	add_child(collision)
	collision_layer = int(body.get("collision_layer", 2))
	collision_mask = _layers_to_mask(body.get("collision_mask", [1]) as Array)
	up_direction = Vector3.UP
	floor_max_angle = deg_to_rad(float(body.get("floor_max_angle_deg", 38.0)))
	max_slides = int(body.get("max_slides", 6))
	safe_margin = float(body.get("safe_margin_m", 0.01))
	floor_snap_length = 0.5
	_exclude = [get_rid()]
	_probe.exclude = _exclude
	_build_visual()
	_last_position = global_position
	locomotion.reset(rotation.y)


func set_input(move: Vector2, sprint: bool) -> void:
	_input_move = move.limit_length(1.0)
	_input_sprint = sprint


func call_to(position: Vector3) -> void:
	called_target = position
	is_called = true
	called.emit()


func cancel_call() -> void:
	is_called = false


func _physics_process(delta: float) -> void:
	var started: int = Time.get_ticks_usec()
	var move: Vector2 = _input_move
	var sprint: bool = _input_sprint
	if is_called:
		var to_target: Vector3 = called_target - global_position
		to_target.y = 0.0
		var call_data: Dictionary = settings.get("call", {}) as Dictionary
		if to_target.length() <= float(call_data.get("arrival_distance_m", 2.6)):
			is_called = false
			move = Vector2.ZERO
		else:
			var local: Vector3 = global_basis.inverse() * to_target.normalized()
			move = Vector2(local.x, -local.z).limit_length(1.0)
			sprint = false
	locomotion.update(move, sprint, delta)
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
	if not is_on_floor():
		velocity.y = -9.81
	move_and_slide()
	if heightfield != null:
		var ground_y: float = heightfield.height_at(global_position.x, global_position.z)
		if global_position.y < ground_y - 0.5:
			global_position.y = ground_y
			velocity.y = 0.0
	_update_visual(delta, intended.length())
	_emit_hoofsteps(intended.length())
	last_step_usec = Time.get_ticks_usec() - started


func _safe_to_move(motion: Vector3) -> bool:
	if motion.length_squared() < 0.000001:
		return true
	var terrain: Dictionary = settings.get("terrain", {}) as Dictionary
	var look_ahead: float = maxf(float(terrain.get("look_ahead_m", 7.0)), motion.length())
	var direction: Vector3 = motion.normalized()
	if heightfield != null:
		var now: float = heightfield.height_at(global_position.x, global_position.z)
		var ahead: Vector3 = global_position + direction * look_ahead
		var ahead_height: float = heightfield.height_at(ahead.x, ahead.z)
		var slope: Vector3 = heightfield.normal_at(ahead.x, ahead.z)
		var max_slope: float = deg_to_rad(float(terrain.get("max_slope_deg", 34.0)))
		if acos(clampf(slope.y, -1.0, 1.0)) > max_slope:
			return false
		if now - ahead_height > float(terrain.get("dangerous_drop_m", 1.15)):
			return false
	if get_world_3d() == null:
		return true
	var probe_height: float = float(terrain.get("obstacle_probe_height_m", 1.1))
	_probe.transform = Transform3D(Basis.IDENTITY, global_position + Vector3.UP * probe_height)
	_probe.motion = motion.normalized() * float(terrain.get("obstacle_probe_distance_m", 2.2))
	var result: PackedFloat32Array = get_world_3d().direct_space_state.cast_motion(_probe)
	return result.is_empty() or result[0] >= 0.9999


func surface_at(world_position: Vector3) -> StringName:
	return &"sable" if heightfield == null else heightfield.surface_at(world_position)


func saddle_position() -> Vector3:
	var visual: Dictionary = settings.get("visual", {}) as Dictionary
	var saddle_height: float = float(visual.get("saddle_height_m", 1.72))
	return global_position + Vector3.UP * saddle_height


func _emit_hoofsteps(distance: float) -> void:
	if distance <= 0.0 or not is_on_floor():
		return
	_stride_distance += distance
	var gaits: Dictionary = settings.get("gaits", {}) as Dictionary
	var gait_data: Dictionary = gaits.get(String(locomotion.get_gait_name()), {}) as Dictionary
	var stride: float = float(gait_data.get("stride_m", 1.4))
	if _stride_distance < stride * 0.5:
		return
	_stride_distance = fmod(_stride_distance, stride * 0.5)
	var hoof_position: Vector3 = global_position + global_basis.x * 0.35
	hoofstep.emit(hoof_position, locomotion.speed, surface_at(global_position))


func _build_visual() -> void:
	_visual_root = Node3D.new()
	_visual_root.name = "BarqVisuel"
	add_child(_visual_root)
	var visual: Dictionary = settings.get("visual", {}) as Dictionary
	var body_length: float = float(visual.get("body_length_m", 2.15))
	var body_height: float = float(visual.get("body_height_m", 1.25))
	var body_size := Vector3(body_length, 0.85, body_height)
	_add_box("Corps", body_size, Vector3(0.0, 1.25, 0.0), Color(0.28, 0.13, 0.06))
	var neck_size := Vector3(0.55, 1.2, 0.55)
	var neck_position := Vector3(0.0, 1.75, -0.78)
	_add_box("Encolure", neck_size, neck_position, Color(0.32, 0.16, 0.08))
	var head_size := Vector3(0.48, 0.7, 0.65)
	var head_position := Vector3(0.0, 2.25, -1.05)
	_add_box("Tête", head_size, head_position, Color(0.34, 0.18, 0.09))
	var saddle_size := Vector3(0.85, 0.16, 0.72)
	var saddle_position := Vector3(0.0, 1.75, 0.12)
	_add_box("Selle", saddle_size, saddle_position, Color(0.12, 0.06, 0.03))
	var leg_radius: float = float(visual.get("leg_radius_m", 0.09))
	var leg_length: float = float(visual.get("leg_length_m", 1.05))
	var leg_size := Vector3(leg_radius, leg_length, leg_radius)
	for index: int in 4:
		var side: float = -0.42 if index % 2 == 0 else 0.42
		var front: float = -0.62 if index < 2 else 0.62
		var leg_name: String = "Jambe%d" % index
		var leg_position := Vector3(side, 0.65, front)
		var leg := _add_box(leg_name, leg_size, leg_position, Color(0.22, 0.1, 0.05))
		_legs.append(leg)


func _add_box(node_name: String, size: Vector3, position: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.position = position
	_visual_root.add_child(instance)
	return instance


func _update_visual(delta: float, distance: float) -> void:
	_phase += delta * (1.0 + locomotion.speed * 0.18)
	_visual_root.position.y = sin(_phase * 2.0) * minf(distance * 0.08, 0.035)
	for index: int in _legs.size():
		var leg_phase: float = _phase * 2.0 + float(index % 2) * PI
		_legs[index].rotation.x = sin(leg_phase) * minf(0.34, locomotion.speed * 0.035)


func _layers_to_mask(layers: Array) -> int:
	var mask: int = 0
	for layer_value: Variant in layers:
		var layer: int = int(layer_value)
		if layer >= 1 and layer <= 32:
			mask |= 1 << (layer - 1)
	return mask
