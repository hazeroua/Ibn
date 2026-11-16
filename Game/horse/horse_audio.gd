class_name HorseAudio
extends Node3D
## Audio procédural borné : impulsions de sabots et souffle, sans dépendance externe.

var _hoof: AudioStreamPlayer3D
var _breath: AudioStreamPlayer3D
var _hoof_generator: AudioStreamGenerator
var _breath_generator: AudioStreamGenerator
var _hoof_frequency: float = 110.0
var _breath_frequency: float = 75.0
var _breath_clock: float = 0.0


func configure(settings: Dictionary) -> void:
	var data: Dictionary = settings.get("audio", {}) as Dictionary
	_hoof_frequency = float(data.get("hoof_frequency_hz", 110.0))
	_breath_frequency = float(data.get("breath_frequency_hz", 75.0))
	var max_distance: float = float(data.get("max_distance_m", 42.0))
	_hoof = _make_player("Sabots", max_distance)
	_breath = _make_player("Souffle", max_distance)
	_hoof_generator = AudioStreamGenerator.new()
	_hoof_generator.mix_rate = 22050.0
	_hoof_generator.buffer_length = 0.12
	_hoof.stream = _hoof_generator
	_breath_generator = AudioStreamGenerator.new()
	_breath_generator.mix_rate = 22050.0
	_breath_generator.buffer_length = 0.3
	_breath.stream = _breath_generator
	_breath.play()


func hoof(surface: StringName, speed: float) -> void:
	if _hoof == null:
		return
	_hoof.pitch_scale = 0.82 if surface == &"sable" else 1.05
	_hoof.volume_db = clampf(-18.0 + speed * 0.6, -18.0, -7.0)
	var playback_value: Variant = _hoof.get_stream_playback()
	var playback: AudioStreamGeneratorPlayback = playback_value as AudioStreamGeneratorPlayback
	if playback == null:
		_hoof.play()
		playback = _hoof.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback != null:
		var frames: int = 900
		for index: int in frames:
			var envelope: float = exp(-float(index) / 125.0)
			var sample: float = sin(TAU * _hoof_frequency * float(index) / 22050.0) * envelope * 0.28
			playback.push_frame(Vector2(sample, sample))


func _process(delta: float) -> void:
	_breath_clock += delta
	if _breath == null or _breath_generator == null:
		return
	var playback_value: Variant = _breath.get_stream_playback()
	var playback: AudioStreamGeneratorPlayback = playback_value as AudioStreamGeneratorPlayback
	if playback == null:
		return
	var count: int = mini(playback.get_frames_available(), 1024)
	for index: int in count:
		var time: float = _breath_clock + float(index) / 22050.0
		var sample: float = sin(TAU * _breath_frequency * time) * 0.018
		playback.push_frame(Vector2(sample, sample))


func _make_player(player_name: String, max_distance: float) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.name = player_name
	player.max_distance = max_distance
	player.unit_size = 4.0
	add_child(player)
	return player
