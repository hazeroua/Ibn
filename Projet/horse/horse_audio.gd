class_name HorseAudio
extends Node3D
## Audio du cheval (repris de la première version) : les sabots passent par le système de pas (FootstepSystem)
## pour respecter la surface du sol, plus graves et plus forts ; des prises de son de cheval ajoutent le souffle
## et le hennissement (sources/sons/, CC0).

const BREATH_SOUND: String = "horse_breath"
const NEIGH_SOUND: String = "horse_neigh"

var _pitch: float = 1.0
var _volume_db: float = 0.0
var _rng := RandomNumberGenerator.new()
var _voices: Array[AudioStreamPlayer3D] = []
var _breath_stream: AudioStream
var _neigh_stream: AudioStream
var _last_random_usec: int = 0
var _footsteps: FootstepSystem


func configure(settings: Dictionary) -> void:
	var data: Dictionary = PlayerJsonData.get_dictionary(settings, "audio", "horse.json")
	_pitch = PlayerJsonData.get_float(data, "hoof_pitch_scale", "horse.json > audio")
	_volume_db = PlayerJsonData.get_float(data, "hoof_volume_offset_db", "horse.json > audio")
	_rng.randomize()
	var streams: Dictionary[String, AudioStream] = SoundLibrary.load_streams(PackedStringArray([BREATH_SOUND, NEIGH_SOUND]))
	_breath_stream = streams.get(BREATH_SOUND)
	_neigh_stream = streams.get(NEIGH_SOUND)


func _ready() -> void:
	_footsteps = get_tree().get_first_node_in_group(FootstepSystem.GROUP) as FootstepSystem
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
	if _footsteps != null:
		_footsteps.play_footstep(world_position, speed, collider, Time.get_ticks_usec(), _pitch, _volume_db)
	if speed > 2.2:
		var now := Time.get_ticks_usec()
		if now - _last_random_usec > 5000000 and _rng.randf() < 0.12:
			_last_random_usec = now
			_play(_breath_stream, world_position, -12.0, _rng.randf_range(0.94, 1.04))


func jump_started(world_position: Vector3) -> void:
	neigh(world_position)


## Hennissement (élan d'un saut, réponse au sifflet quand Barq ne peut pas venir).
func neigh(world_position: Vector3) -> void:
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
