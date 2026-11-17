class_name HorseAudio
extends Node3D
## Audio de Barq : les sabots restent branchés sur Footsteps pour respecter la surface du sol,
## et des prises de son de cheval ajoutent le souffle et le hennissement.

const BREATH_PATH: String = "res://assets/horse/audio/breath.ogg"
const NEIGH_PATH: String = "res://assets/horse/audio/neigh.ogg"

var _pitch: float = 1.0
var _volume_db: float = 0.0
var _rng := RandomNumberGenerator.new()
var _voices: Array[AudioStreamPlayer3D] = []
var _breath_stream: AudioStream
var _neigh_stream: AudioStream
var _last_random_usec: int = 0


func configure(settings: Dictionary) -> void:
	var data: Dictionary = JsonData.get_dictionary(settings, "audio", "horse.json")
	_pitch = JsonData.get_float(data, "hoof_pitch_scale", "horse.json > audio")
	_volume_db = JsonData.get_float(data, "hoof_volume_offset_db", "horse.json > audio")
	_rng.randomize()
	_breath_stream = load(BREATH_PATH) as AudioStream
	_neigh_stream = load(NEIGH_PATH) as AudioStream


func _ready() -> void:
	for index: int in 4:
		var voice := AudioStreamPlayer3D.new()
		voice.name = "HorseVoice%02d" % index
		voice.max_distance = 40.0
		voice.unit_size = 8.0
		voice.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		voice.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		add_child(voice)
		_voices.append(voice)


## Un sabot posé : collider = Barq (sa méthode surface_at donne la surface du sol sous lui).
func hoof(world_position: Vector3, speed: float, collider: Object) -> void:
	var footsteps: Node = get_node_or_null(^"/root/Footsteps")
	if footsteps != null:
		footsteps.call(&"play_footstep", world_position, speed, collider, Time.get_ticks_usec(), _pitch, _volume_db)
	if speed > 2.2:
		var now := Time.get_ticks_usec()
		if now - _last_random_usec > 5000000 and _rng.randf() < 0.12:
			_last_random_usec = now
			_play(_breath_stream, world_position, -12.0, _rng.randf_range(0.94, 1.04))


func jump_started(world_position: Vector3) -> void:
	_play(_neigh_stream, world_position, -7.0, _rng.randf_range(0.96, 1.03))


func jump_landed(world_position: Vector3) -> void:
	_play(_breath_stream, world_position, -10.0, _rng.randf_range(0.94, 1.04))


func _play(stream: AudioStream, world_position: Vector3, volume_db: float, pitch: float) -> void:
	if stream == null or _voices.is_empty():
		return
	var voice: AudioStreamPlayer3D = _voices[0]
	for candidate: AudioStreamPlayer3D in _voices:
		if not candidate.playing:
			voice = candidate
			break
	voice.stream = stream
	voice.global_position = world_position
	voice.volume_db = volume_db
	voice.pitch_scale = pitch
	voice.play()
