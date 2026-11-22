class_name PlayerAnimator
extends RefCounted
## Machine d'animation du personnage joueur, pilotée par l'allure et la vitesse.
##
## Joue directement les animations de la bibliothèque « locomotion » de l'AnimationPlayer du
## modèle (contrat du MVP 1) : boucles d'allure (idle, walk_slow, walk, run) en fondu enchaîné,
## vitesse de lecture proportionnelle à la vitesse réelle (pas de glissement des pieds) ; arrêts
## et virages joués une fois, à la durée de la manœuvre. Une animation n'est relancée qu'au
## changement d'état : par image, seule la vitesse de lecture est mise à jour.
##
## Pas : si le modèle a un squelette avec les os des pieds (locomotion.json > footsteps > animation_contacts), les
## appuis de chaque animation sont lus une fois au branchement (FootContacts) ; à chaque image, update() relève ceux
## que la lecture vient de franchir. Le bruit des pas tombe ainsi exactement quand le pied touche le sol, quelle que
## soit la vitesse de lecture. Sans squelette, has_contacts() est faux et le personnage compte les pas à la distance.

## Phases d'un saut ou d'une chute.
enum Air { NONE, TAKEOFF, AIRBORNE, LANDING, REACTION }

## Appuis relevés au plus par mise à jour (une image de 100 ms en course en franchit au plus deux).
const MAX_CROSSED: int = 8
## Saut : départ, en l'air, réception (contrat « locomotion » des personnages, characters.json).
const JUMP_START_CLIP: StringName = &"locomotion/jump_start"
const JUMP_AIR_CLIP: StringName = &"locomotion/jump_air"
const JUMP_LAND_CLIP: StringName = &"locomotion/jump_land"
## Monte : assise, assise en avant (galop), montée et descente de cheval.
const BUMP_CLIP: StringName = &"locomotion/bump"
const LAND_ROLL_CLIP: StringName = &"locomotion/land_roll"
const RIDE_CLIP: StringName = &"locomotion/ride_idle"
const RIDE_GALLOP_CLIP: StringName = &"locomotion/ride_gallop"
const MOUNT_CLIP: StringName = &"locomotion/mount"
const DISMOUNT_CLIP: StringName = &"locomotion/dismount"
const EXTRA_CLIPS: Array[StringName] = [
	JUMP_START_CLIP, JUMP_AIR_CLIP, JUMP_LAND_CLIP, BUMP_CLIP, LAND_ROLL_CLIP, RIDE_CLIP, RIDE_GALLOP_CLIP, MOUNT_CLIP, DISMOUNT_CLIP
]
## Boucles indexées par LocomotionSettings.Gait.
const LOOP_CLIPS: Array[StringName] = [&"locomotion/idle", &"locomotion/walk_slow", &"locomotion/walk", &"locomotion/run"]
## Manœuvres indexées par LocomotionMotor.Maneuver (la case NONE est vide).
const MANEUVER_CLIPS: Array[StringName] = [
	&"",
	&"locomotion/stop_walk",
	&"locomotion/stop_run",
	&"locomotion/turn_left_90",
	&"locomotion/turn_right_90",
	&"locomotion/turn_180",
]

## Poussée contre un mur à vitesse réelle presque nulle : pose de repos au lieu de marcher sur place.
var blocked: bool = false

var _settings: LocomotionSettings
var _player: AnimationPlayer
var _maneuver_lengths := PackedFloat64Array()
var _current_clip: StringName = &""
var _current_serial: int = -1
var _air: int = Air.NONE
var _air_timer: float = 0.0
## Clip de la réception ou de la réaction en cours (jump_land, land_roll, bump).
var _one_shot_clip: StringName = &""
var _skeleton: Skeleton3D
var _foot_bones := PackedInt32Array()
## Appuis par animation : nom -> PackedFloat32Array des temps ; pieds correspondants dans _contact_feet.
var _contact_times: Dictionary[StringName, PackedFloat32Array] = {}
var _contact_feet: Dictionary[StringName, PackedInt32Array] = {}
var _contacts_ready: bool = false
var _tracked_clip: StringName = &""
var _tracked_position: float = 0.0
var _tracked_times := PackedFloat32Array()
var _tracked_feet := PackedInt32Array()
var _no_times := PackedFloat32Array()
var _no_feet := PackedInt32Array()
## Pieds des appuis franchis à la dernière mise à jour (au plus 8 ; réutilisé, aucune allocation par image).
var _crossed := PackedInt32Array()
var _crossed_count: int = 0


func _init(settings: LocomotionSettings) -> void:
	_settings = settings
	_maneuver_lengths.resize(MANEUVER_CLIPS.size())
	_crossed.resize(MAX_CROSSED)


## Noms des animations du contrat absentes de l'AnimationPlayer (vide : bibliothèque complète).
static func missing_clips(player: AnimationPlayer) -> PackedStringArray:
	var missing := PackedStringArray()
	for clip: StringName in LOOP_CLIPS:
		if not player.has_animation(clip):
			missing.append(clip)
	for index: int in range(1, MANEUVER_CLIPS.size()):
		if not player.has_animation(MANEUVER_CLIPS[index]):
			missing.append(MANEUVER_CLIPS[index])
	for clip: StringName in EXTRA_CLIPS:
		if not player.has_animation(clip):
			missing.append(clip)
	return missing


## Branche l'AnimationPlayer du modèle (null pour fonctionner sans visuel). Si une animation du
## contrat manque, l'erreur est signalée et le personnage fonctionne sans animation (is_bound()).
func bind(player: AnimationPlayer) -> void:
	_player = null
	_current_clip = &""
	_current_serial = -1
	if player == null:
		return
	var missing: PackedStringArray = missing_clips(player)
	if not missing.is_empty():
		push_error("PlayerAnimator : animations absentes de l'AnimationPlayer « %s » : %s." % [player.name, ", ".join(missing)])
		return
	# Les allures bouclent, les manœuvres se jouent une fois.
	for clip: StringName in LOOP_CLIPS:
		player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	for index: int in range(1, MANEUVER_CLIPS.size()):
		var animation: Animation = player.get_animation(MANEUVER_CLIPS[index])
		animation.loop_mode = Animation.LOOP_NONE
		_maneuver_lengths[index] = animation.length
	_player = player
	_bind_contacts(player)


## Vrai si les appuis des pieds ont été lus dans les animations (les pas suivent alors l'animation).
func has_contacts() -> bool:
	return _player != null and _contacts_ready


## Nombre d'appuis franchis à la dernière mise à jour ; foot_of(i) donne le pied (0 gauche, 1 droit).
func crossed_count() -> int:
	return _crossed_count


func foot_of(index: int) -> int:
	return _crossed[index]


## Position du pied dans le monde (pose actuelle du squelette).
func foot_world_position(foot: int) -> Vector3:
	return _skeleton.global_transform * _skeleton.get_bone_global_pose(_foot_bones[foot]).origin


## Appuis de toutes les animations du contrat (une fois). Sans squelette ni os des pieds : pas d'appuis (aucune erreur,
## le personnage compte alors les pas à la distance). Squelette présent mais une allure sans deux appuis : erreur.
func _bind_contacts(player: AnimationPlayer) -> void:
	_contacts_ready = false
	_contact_times.clear()
	_contact_feet.clear()
	_skeleton = null
	_tracked_clip = &""
	var root: Node = player.get_node_or_null(player.root_node)
	if root == null:
		return
	var skeletons: Array[Node] = root.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return
	var skeleton: Skeleton3D = skeletons[0] as Skeleton3D
	_foot_bones = PackedInt32Array()
	for bone_name: String in _settings.foot_bone_names:
		var bone: int = skeleton.find_bone(bone_name)
		if bone < 0:
			push_error("PlayerAnimator : os « %s » absent du squelette « %s »." % [bone_name, skeleton.name])
			return
		_foot_bones.append(bone)
	var path: String = str(root.get_path_to(skeleton))
	var clips: Array[StringName] = []
	clips.append_array(LOOP_CLIPS)
	for index: int in range(1, MANEUVER_CLIPS.size()):
		clips.append(MANEUVER_CLIPS[index])
	for clip: StringName in clips:
		var result: Dictionary = FootContacts.analyze(
			player.get_animation(clip),
			skeleton,
			path,
			_foot_bones,
			_settings.contact_samples_per_second,
			_settings.contact_height,
			_settings.contact_lift,
			_settings.contact_min_gap
		)
		_contact_times[clip] = result["times"]
		_contact_feet[clip] = result["feet"]
	# Au repos, les petits déplacements des pieds ne sont pas des pas.
	_contact_times[LOOP_CLIPS[LocomotionSettings.Gait.IDLE]] = PackedFloat32Array()
	_contact_feet[LOOP_CLIPS[LocomotionSettings.Gait.IDLE]] = PackedInt32Array()
	for gait: int in [LocomotionSettings.Gait.WALK_SLOW, LocomotionSettings.Gait.WALK, LocomotionSettings.Gait.RUN]:
		if _contact_times[LOOP_CLIPS[gait]].size() < 2:
			push_error("PlayerAnimator : moins de deux appuis trouvés dans « %s »." % LOOP_CLIPS[gait])
			return
	_skeleton = skeleton
	_contacts_ready = true


## Relève les appuis franchis entre la position de lecture précédente et l'actuelle (boucle : passage par la fin).
func _track_contacts() -> void:
	_crossed_count = 0
	if not _contacts_ready:
		return
	var position: float = _player.current_animation_position
	if _current_clip != _tracked_clip:
		# Nouvelle animation : les appuis depuis son début comptent (une manœuvre démarre à 0).
		_tracked_clip = _current_clip
		_tracked_position = -1.0
		# Tableaux de l'animation lus une fois à chaque changement (aucune copie ni allocation par image).
		_tracked_times = _contact_times[_current_clip] if _contact_times.has(_current_clip) else _no_times
		_tracked_feet = _contact_feet[_current_clip] if _contact_feet.has(_current_clip) else _no_feet
	var from: float = _tracked_position
	_tracked_position = position
	if position >= from:
		_collect(from, position)
	else:
		_collect(from, INF)
		_collect(-1.0, position)


func _collect(after: float, until: float) -> void:
	for i: int in _tracked_times.size():
		var time: float = _tracked_times[i]
		if time > after and time <= until and _crossed_count < MAX_CROSSED:
			_crossed[_crossed_count] = _tracked_feet[i]
			_crossed_count += 1


func is_bound() -> bool:
	return _player != null


## Animation jouée en dernier (vide si aucune).
func current_clip() -> StringName:
	return _current_clip


## Met à jour l'animation à partir de l'état du moteur et de la vitesse horizontale réelle (m/s).
## Saut : le personnage quitte le sol (départ joué puis boucle en l'air). jumped = faux pour une simple chute.
func begin_air(jumped: bool) -> void:
	if _player == null or _air == Air.TAKEOFF or _air == Air.AIRBORNE:
		return
	_air = Air.TAKEOFF if jumped else Air.AIRBORNE
	_air_timer = 0.0
	_play_air(JUMP_START_CLIP if jumped else JUMP_AIR_CLIP)


## Le personnage reprend le sol ; land = vrai pour jouer la réception (après une chute assez longue),
## roll = vrai pour une roulade (chute longue en pleine course).
func end_air(land: bool, roll: bool = false) -> void:
	if _player == null or _air == Air.NONE or _air == Air.LANDING:
		return
	if land:
		_air = Air.LANDING
		_air_timer = 0.0
		_one_shot_clip = LAND_ROLL_CLIP if roll else JUMP_LAND_CLIP
		_play_air(_one_shot_clip)
	else:
		_air = Air.NONE
		_current_clip = &""


## Réaction jouée en entier (choc contre un mur) : renvoie sa durée en secondes (0 sans animation).
func play_reaction(clip: StringName) -> float:
	if _player == null or not _player.has_animation(clip):
		return 0.0
	_air = Air.REACTION
	_air_timer = 0.0
	_one_shot_clip = clip
	_play_air(clip)
	return _player.get_animation(clip).length


## Oublie l'animation en cours (après la monte, quand un autre système a piloté le lecteur).
func reset_state() -> void:
	_air = Air.NONE
	_current_clip = &""
	_current_serial = -1
	_tracked_clip = &""


func _play_air(clip: StringName) -> void:
	_player.play(clip, _settings.jump_blend)
	_player.speed_scale = 1.0
	_current_clip = clip
	_current_serial = -1


## Saut en cours : départ puis boucle en l'air ; la réception laisse reprendre la marche dès qu'on bouge.
func _update_air(motor: LocomotionMotor, delta: float) -> bool:
	_air_timer += delta
	match _air:
		Air.TAKEOFF:
			if _air_timer >= _player.get_animation(JUMP_START_CLIP).length:
				_air = Air.AIRBORNE
				_play_air(JUMP_AIR_CLIP)
			return true
		Air.AIRBORNE:
			return true
		Air.LANDING:
			var length: float = _player.get_animation(_one_shot_clip).length
			# La roulade se joue en entier ; la réception simple laisse reprendre la marche dès qu'on bouge.
			if _air_timer < length and (_one_shot_clip == LAND_ROLL_CLIP or motor.gait == LocomotionSettings.Gait.IDLE):
				return true
			_air = Air.NONE
			_current_clip = &""
		Air.REACTION:
			if _air_timer < _player.get_animation(_one_shot_clip).length:
				return true
			_air = Air.NONE
			_current_clip = &""
	return false


func update(motor: LocomotionMotor, real_speed: float, delta: float = 0.0) -> void:
	_crossed_count = 0
	if _player == null:
		return
	if _air != Air.NONE and _update_air(motor, delta):
		return
	if motor.maneuver != LocomotionMotor.Maneuver.NONE:
		if motor.maneuver_serial != _current_serial:
			var clip: StringName = MANEUVER_CLIPS[motor.maneuver]
			var restart: bool = clip == _current_clip
			_player.play(clip, _settings.one_shot_blend_time)
			if restart:
				_player.seek(0.0, true)
				_tracked_clip = &""
			_current_clip = clip
			_current_serial = motor.maneuver_serial
			var length: float = _maneuver_lengths[motor.maneuver]
			_player.speed_scale = length / motor.maneuver_duration if length > 0.0 else 1.0
		_track_contacts()
		return
	_current_serial = -1
	var loop_clip: StringName = LOOP_CLIPS[LocomotionSettings.Gait.IDLE if blocked else motor.gait]
	if loop_clip != _current_clip:
		_player.play(loop_clip, _settings.blend_time)
		_current_clip = loop_clip
	if motor.gait == LocomotionSettings.Gait.IDLE or blocked:
		_player.speed_scale = 1.0
	else:
		var reference: float = _settings.gait_animation_reference_speed[motor.gait]
		_player.speed_scale = clampf(real_speed / reference, _settings.speed_scale_min, _settings.speed_scale_max)
	_track_contacts()
