class_name HorseAudio
extends Node3D
## Audio procédural borné : impulsions de sabots et souffle, sans dépendance externe ni travail par image.

const SAMPLE_RATE: int = 22050
const HOOF_DURATION_S: float = 0.14
const BREATH_DURATION_S: float = 0.6

var _hoof: AudioStreamPlayer3D
var _breath: AudioStreamPlayer3D
var _hoof_frequency: float = 110.0
var _breath_frequency: float = 75.0
var _breath_started: bool = false


func _ready() -> void:
	_start_breath()


func configure(settings: Dictionary) -> void:
	var data: Dictionary = settings.get("audio", {}) as Dictionary
	_hoof_frequency = float(data.get("hoof_frequency_hz", 110.0))
	_breath_frequency = float(data.get("breath_frequency_hz", 75.0))
	var max_distance: float = float(data.get("max_distance_m", 42.0))
	_hoof = _make_player("Sabots", max_distance)
	_breath = _make_player("Souffle", max_distance)
	_hoof.stream = _make_tone(_hoof_frequency, HOOF_DURATION_S, true)
	_breath.stream = _make_tone(_breath_frequency, BREATH_DURATION_S, false)
	_start_breath()


func hoof(surface: StringName, speed: float) -> void:
	if _hoof == null:
		return
	_hoof.pitch_scale = 0.82 if surface == &"sable" else 1.05
	_hoof.volume_db = clampf(-18.0 + speed * 0.6, -18.0, -7.0)
	_hoof.play()


func _start_breath() -> void:
	if _breath_started or _breath == null or not is_inside_tree():
		return
	_breath.play()
	_breath_started = true


## Les échantillons sont préparés une fois au chargement ; aucun tampon ni objet n'est créé pendant la partie.
func _make_tone(frequency: float, duration: float, percussive: bool) -> AudioStreamWAV:
	var frame_count: int = maxi(1, ceili(float(SAMPLE_RATE) * duration))
	var samples := PackedByteArray()
	samples.resize(frame_count * 2)
	for index: int in frame_count:
		var progress: float = float(index) / float(frame_count)
		var envelope: float = exp(-progress * 8.0) if percussive else 0.35 + 0.65 * sin(progress * PI)
		var sample: int = roundi(sin(TAU * frequency * float(index) / float(SAMPLE_RATE)) * envelope * 32767.0 * 0.18)
		samples.encode_s16(index * 2, sample)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.data = samples
	if not percussive:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	return stream


func _make_player(player_name: String, max_distance: float) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.name = player_name
	player.max_distance = max_distance
	player.unit_size = 4.0
	add_child(player)
	return player
