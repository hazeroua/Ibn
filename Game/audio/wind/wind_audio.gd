class_name WindAudio
extends Node
## Son du vent : deux couches de bruit filtré en boucle (grondement grave, souffle des rafales).
##
## Les boucles sont synthétisées une fois au démarrage (WindNoise) ; ensuite seuls le volume et la
## hauteur de deux lecteurs changent, selon la force et la rafale. Un bus « Wind » dédié est créé
## s'il n'existe pas.

var _settings: WindSettings = null
var _rumble: AudioStreamPlayer = null
var _gust: AudioStreamPlayer = null


## Construit le bus et les deux lecteurs (une fois).
func build(settings: WindSettings) -> void:
	_settings = settings
	name = "WindAudio"
	_ensure_bus(settings.audio_bus, settings.audio_send)
	_rumble = _make_player("Rumble", settings.rumble, settings.seed_value)
	_gust = _make_player("Gust", settings.gust, settings.seed_value + 1)
	apply_wind(0.0, 0.0)


## Volume et hauteur selon la force du vent et la rafale (0 à 1). Aucune allocation.
func apply_wind(strength: float, gust: float) -> void:
	_set_layer(_rumble, _settings.rumble, strength)
	var gust_strength: float = maxf(strength - 0.15, 0.0) / 0.85 * (0.4 + 0.6 * gust)
	_set_layer(_gust, _settings.gust, gust_strength)


## Lecteur de la couche grave (pour les tests et le mixage).
func get_rumble_player() -> AudioStreamPlayer:
	return _rumble


## Lecteur de la couche des rafales.
func get_gust_player() -> AudioStreamPlayer:
	return _gust


func _make_player(player_name: String, layer: WindSettings.WindLayer, seed_value: int) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = player_name
	player.bus = _settings.audio_bus
	player.stream = WindNoise.build_loop(
		seed_value, _settings.audio_loop_seconds, _settings.audio_mix_rate, layer.high_cutoff_hz, layer.low_cutoff_hz
	)
	add_child(player)
	player.play()
	return player


static func _set_layer(player: AudioStreamPlayer, layer: WindSettings.WindLayer, level: float) -> void:
	var t: float = clampf(level, 0.0, 1.0)
	player.volume_db = lerpf(layer.min_db, layer.max_db, t)
	player.pitch_scale = lerpf(layer.min_pitch, layer.max_pitch, t)


static func _ensure_bus(bus_name: StringName, send: StringName) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	AudioServer.add_bus()
	var index: int = AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, bus_name)
	if AudioServer.get_bus_index(send) != -1:
		AudioServer.set_bus_send(index, send)
