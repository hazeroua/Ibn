class_name HorseMountSystem
extends Node3D
signal dismount_blocked
## Monte de Barq : appel (sifflet), montée par la gauche, conduite, saut, descente, et caméra de monte.
##
## États : à pied → approche (le cavalier glisse vers le point de montée, à gauche de la selle) → montée (animation
## « mount ») → monté (le bassin suit le point de selle, qui suit le dos du cheval ; assise droite au pas et au trot,
## penchée en avant au galop) → descente (animation « dismount ») → à pied. Pendant la monte, le personnage ne fait
## plus de physique (il n'a pas de collision avec Barq) et son lecteur d'animation est piloté ici.
## Par image : quelques lectures de transformations, aucune allocation.

enum State { ON_FOOT, APPROACH, MOUNTING, MOUNTING_ATTACH, MOUNTED, DISMOUNTING }

const SETTINGS_PATH: String = "res://data/horse/horse.json"
const MOUNT_ACTION: StringName = &"mount_horse"
const WHISTLE_ACTION: StringName = &"horse_whistle"
const JUMP_ACTION: StringName = &"jump"
const SPRINT_ACTION: StringName = &"sprint"
const PIPELINE_GROUP: StringName = &"horse_mount"
## Vitesse en dessous de laquelle on peut descendre (m/s).
const DISMOUNT_MAX_SPEED: float = 0.3
const MOUNT_ATTACH_TIME: float = 0.22

var player: PlayerCharacter
var camera_rig: ThirdPersonCamera
var horse: HorseController
var heightfield: DesertHeightfield
var traces: HorseTraces
var audio: HorseAudio
var mounted: bool = false
var state: int = State.ON_FOOT

var _settings: Dictionary
var _rider_animation: AnimationPlayer
var _state_time: float = 0.0
var _approach_from := Transform3D.IDENTITY
var _mount_side: float = 0.0
var _seat_height: float = 0.0
var _approach_time: float = 0.0
var _mount_range: float = 0.0
var _mount_attach_from := Transform3D.IDENTITY
var _rider_blend: float = 0.0
var _lean_gaits: Array[StringName] = []
var _current_rider_clip: StringName = &""
## Descente demandée en mouvement : Barq s'arrête, puis le cavalier descend.
var _dismount_requested: bool = false
## Couches de collision du personnage, retirées pendant la monte (il ne doit pas heurter Barq qui le porte).
var _player_layers: int = 0
var _body_query := PhysicsShapeQueryParameters3D.new()
var _body_shape := CapsuleShape3D.new()
var _camera_walk: CameraSettings
var _camera_ride: CameraSettings


func setup(owner_player: PlayerCharacter, rig: ThirdPersonCamera, field: DesertHeightfield) -> void:
	player = owner_player
	camera_rig = rig
	heightfield = field
	_settings = JsonData.load_dictionary(SETTINGS_PATH)
	var rider: Dictionary = JsonData.get_dictionary(_settings, "rider", "horse.json")
	var context: String = "horse.json > rider"
	_mount_side = JsonData.get_float(rider, "mount_side_m", context)
	_seat_height = JsonData.get_float(rider, "mount_seat_height_m", context)
	_approach_time = JsonData.get_float(rider, "approach_s", context)
	_mount_range = JsonData.get_float(rider, "mount_range_m", context)
	_rider_blend = JsonData.get_float(rider, "blend_s", context)
	for gait: Variant in JsonData.get_array(rider, "gallop_lean_gaits", context):
		_lean_gaits.append(StringName(str(gait)))
	_spawn_horse()
	if camera_rig != null:
		_camera_walk = camera_rig.settings
		_camera_ride = CameraSettings.load_mounted()


func _ready() -> void:
	add_to_group(PIPELINE_GROUP)
	process_priority = -10


func _physics_process(delta: float) -> void:
	if horse == null or player == null:
		return
	_state_time += delta
	match state:
		State.ON_FOOT:
			if Input.is_action_just_pressed(WHISTLE_ACTION):
				horse.call_to_node(player)
			if Input.is_action_just_pressed(MOUNT_ACTION) and player.is_grounded():
				if can_mount():
					_begin_mount()
		State.APPROACH:
			horse.set_input(Vector2.ZERO, false)
			if _state_time >= _approach_time:
				_enter(State.MOUNTING)
				_play_rider(PlayerAnimator.MOUNT_CLIP, 0.1)
		State.MOUNTING:
			horse.set_input(Vector2.ZERO, false)
			if _state_time >= _clip_length(PlayerAnimator.MOUNT_CLIP):
				_mount_attach_from = _mount_point()
				_enter(State.MOUNTING_ATTACH)
				# Le clip de montée finit déjà le cavalier en hauteur. La pose assise
				# compense le déplacement de la racine vers la selle pendant le fondu.
				_play_rider(PlayerAnimator.RIDE_CLIP, MOUNT_ATTACH_TIME)
		State.MOUNTING_ATTACH:
			horse.set_input(Vector2.ZERO, false)
			if _state_time >= MOUNT_ATTACH_TIME:
				_enter(State.MOUNTED)
		State.MOUNTED:
			if Input.is_action_just_pressed(MOUNT_ACTION):
				_dismount_requested = true
			if _dismount_requested:
				# Descente : Barq s'arrête d'abord (et se pose s'il saute), puis le cavalier descend.
				horse.set_input(Vector2.ZERO, false)
				if not horse.is_airborne() and horse.locomotion.speed < DISMOUNT_MAX_SPEED:
					_dismount_requested = false
					if not _mount_point_clear():
						# Mur, rocher ou arbre contre le flanc gauche : on reste en selle.
						dismount_blocked.emit()
						_update_rider_pose()
						return
					_enter(State.DISMOUNTING)
					_play_rider(PlayerAnimator.DISMOUNT_CLIP, 0.1)
					return
			else:
				horse.set_input(_camera_relative_move(), Input.is_action_pressed(SPRINT_ACTION))
				if Input.is_action_just_pressed(JUMP_ACTION):
					horse.request_jump()
			_update_rider_pose()
		State.DISMOUNTING:
			horse.set_input(Vector2.ZERO, false)
			if _state_time >= _clip_length(PlayerAnimator.DISMOUNT_CLIP):
				_finish_dismount()


## Le cavalier est placé après l'animation de l'image (le dos du cheval a bougé) : pas de décalage visible.
func _process(_delta: float) -> void:
	if horse == null or player == null:
		return
	match state:
		State.APPROACH:
			var weight: float = smoothstep(0.0, 1.0, clampf(_state_time / maxf(_approach_time, 0.001), 0.0, 1.0))
			player.global_transform = _approach_from.interpolate_with(_mount_point(), weight)
		State.MOUNTING, State.DISMOUNTING:
			# Les animations de montée et de descente partent du point de montée (au sol, à gauche de la selle).
			player.global_transform = _mount_point()
		State.MOUNTING_ATTACH:
			var weight := smoothstep(0.0, 1.0, _state_time / MOUNT_ATTACH_TIME)
			player.global_transform = _mount_attach_from.interpolate_with(horse.seat_transform(), weight)
		State.MOUNTED:
			player.global_transform = horse.seat_transform()


## Monté : vrai entre le début de la montée et la fin de la descente.
func is_riding() -> bool:
	return state != State.ON_FOOT


## Monte immédiate, sans approche ni animation (chargement d'une partie, scripts, tests).
func mount() -> void:
	if state == State.ON_FOOT:
		_begin_mount()
	_dismount_requested = false
	_current_rider_clip = &""
	_enter(State.MOUNTED)


## Descente immédiate, sans animation (chargement d'une partie, scripts, tests).
func dismount() -> void:
	_dismount_requested = false
	if state != State.ON_FOOT:
		_finish_dismount()


## Monte possible : à portée du point de montée (flanc gauche de Barq), ce point libre de tout obstacle et
## l'approche (glissement du personnage jusqu'à ce point) sans traverser Barq.
func can_mount() -> bool:
	if state != State.ON_FOOT or player == null or horse == null:
		return false
	var target: Transform3D = _mount_point()
	if player.global_position.distance_to(target.origin) > _mount_range or not _mount_point_clear():
		return false
	_prepare_body_query(player.global_position)
	_body_query.collision_mask = horse.collision_layer
	_body_query.motion = target.origin - player.global_position
	var result: PackedFloat32Array = player.get_world_3d().direct_space_state.cast_motion(_body_query)
	return result.is_empty() or result[0] >= 1.0


## Le corps du personnage tient au point de montée sans toucher le décor (ni Barq).
func _mount_point_clear() -> bool:
	if player == null or horse == null or not player.is_inside_tree():
		return false
	_prepare_body_query(_mount_point().origin)
	_body_query.collision_mask = player.get_settings().collision_mask
	_body_query.motion = Vector3.ZERO
	return player.get_world_3d().direct_space_state.intersect_shape(_body_query, 1).is_empty()


## Capsule du personnage posée au point « feet », décollée du sol de quelques centimètres (le sol n'est pas un
## obstacle). Aucune allocation : requête et forme réutilisées.
func _prepare_body_query(feet: Vector3) -> void:
	var settings: LocomotionSettings = player.get_settings()
	_body_shape.radius = settings.body_radius
	_body_shape.height = settings.body_height - 0.1
	_body_query.shape = _body_shape
	_body_query.exclude = [player.get_rid()]
	_body_query.transform = Transform3D(Basis.IDENTITY, feet + Vector3.UP * (0.1 + _body_shape.height * 0.5))


func _begin_mount() -> void:
	mounted = true
	horse.mounted = true
	horse.cancel_call()
	_approach_from = player.global_transform
	player.process_mode = Node.PROCESS_MODE_DISABLED
	_player_layers = player.collision_layer
	player.collision_layer = 0
	_rider_animation = player.animation_player if player.is_animating() else null
	if _rider_animation != null:
		# Le personnage ne fait plus de physique, mais ses animations doivent continuer à jouer.
		_rider_animation.process_mode = Node.PROCESS_MODE_PAUSABLE
		_rider_animation.play(PlayerAnimator.LOOP_CLIPS[LocomotionSettings.Gait.WALK], 0.15)
		_rider_animation.speed_scale = 1.0
	if camera_rig != null:
		camera_rig.glide_to_target(horse)
		camera_rig.blend_to_settings(_camera_ride)
	_enter(State.APPROACH)


func _finish_dismount() -> void:
	mounted = false
	horse.mounted = false
	horse.set_input(Vector2.ZERO, false)
	var ground: Transform3D = _mount_point()
	player.process_mode = Node.PROCESS_MODE_INHERIT
	player.collision_layer = _player_layers
	if _rider_animation != null:
		_rider_animation.process_mode = Node.PROCESS_MODE_INHERIT
	player.reset_animation_state()
	player.teleport_to(ground.origin, horse.rotation.y)
	if camera_rig != null:
		camera_rig.glide_to_target(player)
		camera_rig.blend_to_settings(_camera_walk)
	_enter(State.ON_FOOT)


## Point de montée : au sol, à gauche du point de selle, tourné comme Barq.
func _mount_point() -> Transform3D:
	var seat: Transform3D = Transform3D(horse.global_basis.orthonormalized(), horse.saddle_position())
	var origin: Vector3 = seat.origin - seat.basis.x * _mount_side
	origin.y = seat.origin.y - _seat_height
	if heightfield != null:
		origin.y = heightfield.height_at(origin.x, origin.z)
	return Transform3D(seat.basis, origin)


## Assise droite, ou penchée en avant aux allures rapides ; même vitesse de lecture que le cheval.
func _update_rider_pose() -> void:
	if _rider_animation == null:
		return
	var lean: bool = _lean_gaits.has(horse.locomotion.get_gait_name()) and horse.locomotion.speed > 0.5
	var clip: StringName = PlayerAnimator.RIDE_GALLOP_CLIP if lean or horse.is_airborne() else PlayerAnimator.RIDE_CLIP
	if clip != _current_rider_clip:
		_play_rider(clip, _rider_blend)


func _play_rider(clip: StringName, blend: float) -> void:
	_current_rider_clip = clip
	if _rider_animation == null:
		return
	_rider_animation.play(clip, blend)
	_rider_animation.speed_scale = 1.0


func _clip_length(clip: StringName) -> float:
	if _rider_animation == null or not _rider_animation.has_animation(clip):
		return 0.0
	return _rider_animation.get_animation(clip).length


func _enter(next: int) -> void:
	state = next
	_state_time = 0.0


func _spawn_horse() -> void:
	horse = HorseController.new(heightfield)
	horse.name = "Barq"
	add_child(horse)
	horse.global_position = player.global_position + Vector3(2.5, 0.0, 1.0)
	if heightfield != null:
		horse.global_position.y = heightfield.height_at(horse.global_position.x, horse.global_position.z)
	traces = HorseTraces.new()
	traces.name = "Traces"
	traces.configure(_settings)
	horse.add_child(traces)
	audio = HorseAudio.new()
	audio.name = "Audio"
	audio.configure(_settings)
	horse.add_child(audio)
	horse.hoofstep.connect(_on_hoofstep)
	horse.jump_started.connect(audio.jump_started)
	horse.jump_landed.connect(audio.jump_landed)


func _on_hoofstep(world_position: Vector3, speed: float, surface: StringName, collider: Object) -> void:
	if traces != null:
		var normal: Vector3 = Vector3.UP if heightfield == null else heightfield.normal_at(world_position.x, world_position.z)
		traces.place(world_position, horse.rotation.y, surface, normal)
	if audio != null:
		audio.hoof(world_position, speed, collider)


## Même convention que le déplacement à pied : la poussée avant suit la direction regardée par la caméra.
func _camera_relative_move() -> Vector2:
	var raw: Vector2 = Input.get_vector(&"move_left", &"move_right", &"move_back", &"move_forward")
	if camera_rig == null:
		return raw
	var right := Vector2(camera_rig.global_basis.x.x, camera_rig.global_basis.x.z).normalized()
	var forward := Vector2(-camera_rig.global_basis.z.x, -camera_rig.global_basis.z.z).normalized()
	return (right * raw.x + forward * raw.y).limit_length(1.0)
