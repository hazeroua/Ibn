class_name WaterAmbience
extends Node3D
## Ambiance sonore des plans d'eau (oasis, lac, guelta) : enregistrements CC0 en boucle, réglages dans
## res://data/audio/water_ambience.json.
##
## Un lecteur 3D par plan d'eau sonore, créé une fois. Tous les poll_interval_s (minuteur, pas de _process) :
## la source est posée au point du rivage le plus proche de l'auditeur (sous lui s'il est dans l'eau), jouée
## seulement à portée (arrêtée au-delà, avec hystérésis), et son volume suit sans saut la cible
## base + masque du vent + immersion. Pire cas : tous les plans d'eau à portée en même temps (quatre dans le
## désert, borné à MAX_BODIES), auditeur qui galope d'un rivage à l'autre. Aucune allocation par mise à jour.

const SETTINGS_PATH: String = "res://data/audio/water_ambience.json"
const CONTEXT: String = "water_ambience.json"
const MAX_BODIES: int = 32


class Body:
	extends RefCounted
	var id: String = ""
	var center := Vector2.ZERO
	var radius: float = 0.0
	var surface: float = 0.0
	var base_db: float = 0.0
	var max_distance: float = 0.0
	var wind_mask_db: float = 0.0
	var immersion_db: float = 0.0
	var current_db: float = 0.0
	var player: AudioStreamPlayer3D


var _bodies: Array[Body] = []
var _interval: float = 0.1
var _hysteresis: float = 0.0
var _rate: float = 0.0
var _start_db: float = -40.0
var _timer: Timer


## Crée un lecteur par plan d'eau dont le type a un son. bodies : FaunaWater.load_bodies(). Renvoie false (avec
## erreur) si une donnée est invalide ou si un son manque.
func build(bodies: Array[Dictionary], settings: Dictionary = {}) -> bool:
	name = "WaterAmbience"
	var data: Dictionary = settings if not settings.is_empty() else JsonData.load_dictionary(SETTINGS_PATH)
	_interval = JsonData.get_float(data, "poll_interval_s", CONTEXT)
	_hysteresis = JsonData.get_float(data, "stop_hysteresis_m", CONTEXT)
	_rate = JsonData.get_float(data, "volume_rate_db_per_s", CONTEXT)
	_start_db = JsonData.get_float(data, "start_volume_db", CONTEXT)
	if _interval <= 0.0 or _hysteresis < 0.0 or _rate <= 0.0 or bodies.size() > MAX_BODIES:
		push_error("WaterAmbience : réglages incohérents ou trop de plans d'eau (%s)." % CONTEXT)
		return false
	var bus: Dictionary = JsonData.get_dictionary(data, "bus", CONTEXT)
	_ensure_bus(bus)
	var kinds: Dictionary = JsonData.get_dictionary(data, "kinds", CONTEXT)
	var ids := PackedStringArray()
	for spec: Variant in kinds.values():
		ids.append(JsonData.get_string(spec as Dictionary, "sound", CONTEXT + " > kinds"))
	var streams: Dictionary[String, AudioStream] = SoundLibrary.load_streams(
		JsonData.load_dictionary(SoundLibrary.MANIFEST_PATH), ids, ResourceLoader.CACHE_MODE_IGNORE
	)
	for water: Dictionary in bodies:
		var kind: String = str(water.get("kind", ""))
		if not kinds.has(kind):
			continue
		var spec: Dictionary = kinds[kind]
		var context: String = "%s > kinds > %s" % [CONTEXT, kind]
		var sound: String = JsonData.get_string(spec, "sound", context)
		if not streams.has(sound):
			push_error("WaterAmbience : son « %s » indisponible (%s)." % [sound, context])
			return false
		var body := Body.new()
		body.id = str(water.get("id", kind))
		body.center = water["center"]
		body.radius = float(water["radius"])
		body.surface = float(water["surface"])
		body.base_db = JsonData.get_float(spec, "volume_db", context)
		body.max_distance = JsonData.get_float(spec, "max_distance_m", context)
		body.wind_mask_db = JsonData.get_float(spec, "wind_mask_db", context)
		body.immersion_db = JsonData.get_float(spec, "immersion_db", context)
		body.current_db = _start_db
		var player := AudioStreamPlayer3D.new()
		player.name = "Eau_" + body.id
		player.stream = streams[sound]
		player.bus = StringName(String(bus["name"]))
		player.unit_size = JsonData.get_float(spec, "unit_size_m", context)
		player.max_distance = body.max_distance
		player.volume_db = _start_db
		player.position = Vector3(body.center.x, body.surface, body.center.y)
		add_child(player)
		body.player = player
		_bodies.append(body)
	_timer = Timer.new()
	_timer.name = "Poll"
	_timer.wait_time = _interval
	_timer.timeout.connect(_poll)
	add_child(_timer)
	return true


func _ready() -> void:
	if _timer != null:
		_timer.start()


## Met à jour toutes les sources pour un auditeur (position du monde) et une force de vent (0 à 1), elapsed
## secondes après la mise à jour précédente. Sans allocation.
func update_listener(listener: Vector3, wind_strength: float, elapsed: float) -> void:
	var step: float = _rate * elapsed
	for body: Body in _bodies:
		var flat := Vector2(listener.x - body.center.x, listener.z - body.center.y)
		var from_center: float = flat.length()
		var inside: bool = from_center <= body.radius
		var to_shore: float = 0.0 if inside else from_center - body.radius
		var player: AudioStreamPlayer3D = body.player
		if not player.playing:
			if to_shore > body.max_distance:
				continue
			body.current_db = _start_db
			player.volume_db = _start_db
			player.play(randf() * player.stream.get_length())
		elif to_shore > body.max_distance + _hysteresis:
			player.stop()
			continue
		var anchor: Vector2 = Vector2(listener.x, listener.z)
		if not inside:
			anchor = body.center + flat * (body.radius / from_center)
		player.position = Vector3(anchor.x, body.surface, anchor.y)
		var target: float = body.base_db - body.wind_mask_db * clampf(wind_strength, 0.0, 1.0)
		if inside:
			target += body.immersion_db
		body.current_db = move_toward(body.current_db, target, step)
		player.volume_db = body.current_db


## À la sortie, les lectures en cours sont arrêtées : le serveur audio ne garde aucun son chargé.
func _exit_tree() -> void:
	for body: Body in _bodies:
		body.player.stop()
		body.player.stream = null


func get_body_count() -> int:
	return _bodies.size()


## Lecteur d'un plan d'eau par identifiant ; null s'il n'existe pas.
func get_player(id: String) -> AudioStreamPlayer3D:
	for body: Body in _bodies:
		if body.id == id:
			return body.player
	return null


func _poll() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return
	var wind: Node = get_node_or_null(^"/root/Wind")
	var strength: float = 0.0 if wind == null else float(wind.get(&"strength"))
	update_listener(camera.global_position, strength, _interval)


static func _ensure_bus(bus: Dictionary) -> void:
	var bus_name: StringName = StringName(String(bus["name"]))
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	AudioServer.add_bus()
	var index: int = AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_volume_db(index, float(bus["volume_db"]))
	var send: StringName = StringName(String(bus["send"]))
	if AudioServer.get_bus_index(send) != -1:
		AudioServer.set_bus_send(index, send)
