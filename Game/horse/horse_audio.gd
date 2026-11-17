class_name HorseAudio
extends Node3D
## Audio de Barq : les sabots restent branchés sur Footsteps pour respecter la surface du sol,
## et de petites voix procédurales ajoutent le caractère du cheval (effort, saut, souffle aléatoire).

var _pitch: float = 1.0
var _volume_db: float = 0.0
var _rng := RandomNumberGenerator.new()
var _voices: Array[AudioStreamPlayer3D] = []
var _hoof_stream: AudioStreamWAV
var _effort_stream: AudioStreamWAV
var _jump_stream: AudioStreamWAV
var _last_random_usec: int = 0


func configure(settings: Dictionary) -> void:
	var data: Dictionary = JsonData.get_dictionary(settings, "audio", "horse.json")
	_pitch = JsonData.get_float(data, "hoof_pitch_scale", "horse.json > audio")
	_volume_db = JsonData.get_float(data, "hoof_volume_offset_db", "horse.json > audio")
	_rng.randomize()
	_hoof_stream = _make_stream(0.13, 115.0, 0.18, 0.12)
	_effort_stream = _make_stream(0.38, 220.0, 0.08, 0.32)
	_jump_stream = _make_stream(0.24, 310.0, 0.10, 0.5)


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
		_play(_hoof_stream, world_position, -13.0, _rng.randf_range(0.88, 1.08))
		var now := Time.get_ticks_usec()
		if now - _last_random_usec > 3500000 and _rng.randf() < 0.18:
			_last_random_usec = now
			_play(_effort_stream, world_position, -16.0, _rng.randf_range(0.92, 1.05))


func jump_started(world_position: Vector3) -> void:
	_play(_jump_stream, world_position, -10.0, _rng.randf_range(0.92, 1.08))


func jump_landed(world_position: Vector3) -> void:
	_play(_hoof_stream, world_position, -8.0, _rng.randf_range(0.78, 0.92))


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


func _make_stream(duration: float, frequency: float, noise_amount: float, decay: float) -> AudioStreamWAV:
	const MIX_RATE := 22050
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	var samples := PackedByteArray()
	var count := int(duration * MIX_RATE)
	samples.resize(count * 2)
	for index: int in count:
		var t := float(index) / float(MIX_RATE)
		var envelope := exp(-t / decay)
		var tone := sin(TAU * frequency * t) * 0.55
		var noise := _rng.randf_range(-1.0, 1.0) * noise_amount
		samples.encode_s16(index * 2, int(clampf((tone + noise) * envelope * 26000.0, -32767.0, 32767.0)))
	stream.data = samples
	return stream
