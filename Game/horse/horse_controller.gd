class_name HorseController
extends CharacterBody3D
## Barq : déplacement physique (pesanteur, saut), relief, évitement, animations du modèle calées sur la vitesse au sol
## et point de selle qui suit le dos du cheval (horse.json > rider). Le modèle est préparé par HorseVisual.

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
var _call_target_node: Node3D = null

var _visual: HorseVisual
var _animation_player: AnimationPlayer
## Clip et vitesse de référence par allure (indices de HorseLocomotion.Gait), clip d'arrêt et de saut.
var _gait_clips: Array[StringName] = []
var _gait_reference: PackedFloat32Array = PackedFloat32Array()
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
var _last_gait: StringName = &"walk"


func _init(field: DesertHeightfield = null) -> void:
	settings = JsonData.load_dictionary(SETTINGS_PATH)
	heightfield = field
	locomotion = HorseLocomotion.new(settings)
	var jump_data: Dictionary = JsonData.get_dictionary(settings, "jump", "horse.json")
	_jump_speed = JsonData.get_float(jump_data, "speed_mps", "horse.json > jump")
	_gravity = JsonData.get_float(jump_data, "gravity_mps2", "horse.json > jump")
	_jump_min_speed = JsonData.get_float(jump_data, "min_speed_mps", "horse.json > jump")
	_jump_rest = JsonData.get_float(jump_data, "cooldown_s", "horse.json > jump")
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
	_call_target_node = null
	called_target = position
	is_called = true
	called.emit()


## Suit la position actuelle du joueur durant tout l'appel, plutôt que son ancienne position au moment du sifflet.
func call_to_node(target: Node3D) -> void:
	_call_target_node = target
	is_called = target != null
	if is_called:
		called.emit()


func cancel_call() -> void:
	is_called = false
	_call_target_node = null


func _physics_process(delta: float) -> void:
	var started: int = Time.get_ticks_usec()
	var move: Vector2 = _input_move
	var sprint: bool = _input_sprint
	if is_called:
		if is_instance_valid(_call_target_node):
			called_target = _call_target_node.global_position
		var to_target: Vector3 = called_target - global_position
		to_target.y = 0.0
		var call_data: Dictionary = settings.get("call", {}) as Dictionary
		if to_target.length() <= float(call_data.get("arrival_distance_m", 2.6)):
			is_called = false
			move = Vector2.ZERO
		else:
			move = Vector2(to_target.x, to_target.z).normalized()
			sprint = false
	locomotion.update(move, sprint, delta)
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
	if is_on_floor() and not _airborne:
		_vertical_speed = 0.0
	else:
		_vertical_speed -= _gravity * delta
	velocity.y = _vertical_speed
	move_and_slide()
	if _airborne and is_on_floor() and _vertical_speed <= 0.0:
		_airborne = false
		_jump_cooldown = _jump_rest
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


## Saut demandé (monté) : seulement au sol, en mouvement et hors du temps de repos entre deux sauts.
func request_jump() -> bool:
	if _airborne or not is_on_floor() or _jump_cooldown > 0.0 or locomotion.speed < _jump_min_speed:
		return false
	_airborne = true
	_vertical_speed = _jump_speed
	if _animation_player != null and _jump_clip != &"":
		# Le clip de saut couvre l'appel, le vol et la réception : il dure le temps passé en l'air.
		var air_time: float = 2.0 * _vertical_speed / _gravity
		_animation_player.play(_jump_clip, _blend)
		_animation_player.speed_scale = _animation_player.get_animation(_jump_clip).length / maxf(air_time, 0.1)
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
	_visual = HorseVisual.build(settings)
	if _visual == null:
		return
	add_child(_visual)
	_animation_player = _visual.animation_player
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
			_seat_local = bone_rest.origin + Vector3(float(offset[0]), float(offset[1]), float(offset[2]))
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
