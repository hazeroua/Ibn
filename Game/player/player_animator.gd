class_name PlayerAnimator
extends RefCounted
## Machine d'animation du personnage joueur, pilotée par l'allure et la vitesse.
##
## Joue directement les animations de la bibliothèque « locomotion » de l'AnimationPlayer du
## modèle (contrat du MVP 1) : boucles d'allure (idle, walk_slow, walk, run) en fondu enchaîné,
## vitesse de lecture proportionnelle à la vitesse réelle (pas de glissement des pieds) ; arrêts
## et virages joués une fois, à la durée de la manœuvre. Une animation n'est relancée qu'au
## changement d'état : par image, seule la vitesse de lecture est mise à jour.

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

var _settings: LocomotionSettings
var _player: AnimationPlayer
var _maneuver_lengths := PackedFloat64Array()
var _current_clip: StringName = &""
var _current_serial: int = -1


func _init(settings: LocomotionSettings) -> void:
	_settings = settings
	_maneuver_lengths.resize(MANEUVER_CLIPS.size())


## Branche l'AnimationPlayer du modèle (null pour fonctionner sans visuel). Si une animation du
## contrat manque, l'erreur est signalée et le personnage fonctionne sans animation (is_bound()).
func bind(player: AnimationPlayer) -> void:
	_player = null
	_current_clip = &""
	_current_serial = -1
	if player == null:
		return
	var complete: bool = true
	for clip: StringName in LOOP_CLIPS:
		complete = _require(player, clip) and complete
	for index: int in range(1, MANEUVER_CLIPS.size()):
		complete = _require(player, MANEUVER_CLIPS[index]) and complete
	if not complete:
		return
	# Les allures bouclent, les manœuvres se jouent une fois.
	for clip: StringName in LOOP_CLIPS:
		player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	for index: int in range(1, MANEUVER_CLIPS.size()):
		var animation: Animation = player.get_animation(MANEUVER_CLIPS[index])
		animation.loop_mode = Animation.LOOP_NONE
		_maneuver_lengths[index] = animation.length
	_player = player


func is_bound() -> bool:
	return _player != null


## Animation jouée en dernier (vide si aucune).
func current_clip() -> StringName:
	return _current_clip


## Met à jour l'animation à partir de l'état du moteur et de la vitesse horizontale réelle (m/s).
func update(motor: LocomotionMotor, real_speed: float) -> void:
	if _player == null:
		return
	if motor.maneuver != LocomotionMotor.Maneuver.NONE:
		if motor.maneuver_serial != _current_serial:
			var clip: StringName = MANEUVER_CLIPS[motor.maneuver]
			var restart: bool = clip == _current_clip
			_player.play(clip, _settings.one_shot_blend_time)
			if restart:
				_player.seek(0.0, true)
			_current_clip = clip
			_current_serial = motor.maneuver_serial
			var length: float = _maneuver_lengths[motor.maneuver]
			_player.speed_scale = length / motor.maneuver_duration if length > 0.0 else 1.0
		return
	_current_serial = -1
	var loop_clip: StringName = LOOP_CLIPS[motor.gait]
	if loop_clip != _current_clip:
		_player.play(loop_clip, _settings.blend_time)
		_current_clip = loop_clip
	if motor.gait == LocomotionSettings.Gait.IDLE:
		_player.speed_scale = 1.0
	else:
		var reference: float = _settings.gait_animation_reference_speed[motor.gait]
		_player.speed_scale = clampf(real_speed / reference, _settings.speed_scale_min, _settings.speed_scale_max)


func _require(player: AnimationPlayer, clip: StringName) -> bool:
	if player.has_animation(clip):
		return true
	push_error("PlayerAnimator : animation « %s » absente de l'AnimationPlayer « %s »." % [clip, player.name])
	return false
