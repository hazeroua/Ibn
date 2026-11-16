class_name FaunaAmbience
extends Node3D
## Ambiance sonore de la faune par heure : chants d'oiseaux à l'aube près de l'oasis, criquets la nuit, appel lointain
## d'un rapace l'après-midi. Un seul lecteur 3D par source, réutilisé pendant toute la partie (jamais de lecteur créé
## en jeu) ; le volume suit l'heure (fondus) et la distance à l'ancrage vient de l'atténuation 3D du moteur.
## Les sons sont synthétisés au démarrage dans un fil de travail (FaunaSynth) ; en jeu, un changement d'heure ne
## coûte que quelques réglages de volume, et l'appel du rapace un minuteur.
## Pires cas : 16 sources au plus ; 100 h de jeu : aucune ressource ni nœud créé après le démarrage.

const CONTEXT: String = "fauna.json > ambience"
const MAX_SOURCES: int = 16
const SILENT_DB: float = -80.0
const MIN_AUDIBLE_WEIGHT: float = 0.002
const VOLUME_EPSILON_DB: float = 0.05


## Une source sonore : son, lecteur et plage horaire.
class Source:
	extends RefCounted
	var id: StringName = &""
	var kind: String = ""
	var synth: Dictionary = {}
	var context: String = ""
	var window: Vector3 = Vector3.ZERO
	var base_db: float = 0.0
	var anchor: Vector3 = Vector3.ZERO
	var ring_min: float = 0.0
	var ring_max: float = 0.0
	var interval_min: float = 0.0
	var interval_max: float = 0.0
	var stream: AudioStreamWAV = null
	var player: AudioStreamPlayer3D = null
	var timer: Timer = null
	var applied_db: float = SILENT_DB


var _sources: Array[Source] = []
var _mix_rate: int = 16000
var _task_id: int = -1
var _hour: float = 12.0
var _started: bool = false
var _rng := RandomNumberGenerator.new()


## Lit les sources de fauna.json (clé « ambience ») ; la synthèse démarre avec begin(), dans un fil de travail.
## anchors : plans d'eau. Renvoie false (avec erreur) si une donnée est invalide.
func build(ambience: Dictionary, bus: Dictionary, anchors: Array[Dictionary], hour: float) -> bool:
	name = "FaunaAmbience"
	_hour = hour
	_rng.seed = 90210
	_mix_rate = JsonData.get_int(ambience, "mix_rate", CONTEXT)
	var anchor: Dictionary = FaunaWater.oasis_anchor(anchors)
	if anchor.is_empty() or _mix_rate < 8000:
		push_error("FaunaAmbience : plan d'eau d'ancrage ou fréquence d'échantillonnage invalide (%s)." % CONTEXT)
		return false
	_ensure_bus(bus)
	var all: Dictionary = JsonData.get_dictionary(ambience, "sources", CONTEXT)
	if all.is_empty() or all.size() > MAX_SOURCES:
		push_error("FaunaAmbience : entre 1 et %d sources attendues (%s)." % [MAX_SOURCES, CONTEXT])
		return false
	for id: Variant in all.keys():
		var spec: Dictionary = JsonData.get_dictionary(all, str(id), CONTEXT + " > sources")
		var source: Source = _build_source(StringName(str(id)), spec, anchor, String(bus["name"]))
		if source == null:
			return false
		_sources.append(source)
	return true


## Lance la synthèse dans un fil de travail (à appeler une fois, quand tout le reste de la faune est valide).
func begin() -> void:
	if _task_id < 0 and not _started:
		_task_id = WorkerThreadPool.add_task(_synthesize, false, "Faune : synthèse des sons d'ambiance")


## Une image : termine la préparation (une seule fois) puis ne fait plus rien. Aucune allocation une fois démarré.
func poll() -> void:
	if _started or _task_id < 0 or not WorkerThreadPool.is_task_completed(_task_id):
		return
	WorkerThreadPool.wait_for_task_completion(_task_id)
	_task_id = -1
	for source: Source in _sources:
		if source.stream == null:
			push_error("FaunaAmbience : son « %s » non synthétisé." % source.id)
			continue
		source.player.stream = source.stream
		if source.timer != null:
			source.timer.start(_next_interval(source))
	_started = true
	apply_hour(_hour)


## Règle le volume de chaque source selon l'heure. Appelé à chaque changement d'heure ; sans allocation.
func apply_hour(hour: float) -> void:
	_hour = hour
	if not _started:
		return
	for source: Source in _sources:
		if source.stream == null or source.timer != null:
			continue
		var weight: float = FaunaSchedule.weight(hour, source.window)
		var player: AudioStreamPlayer3D = source.player
		if weight < MIN_AUDIBLE_WEIGHT:
			if player.playing:
				player.stop()
			source.applied_db = SILENT_DB
			continue
		var volume: float = source.base_db + linear_to_db(weight)
		if absf(volume - source.applied_db) > VOLUME_EPSILON_DB:
			player.volume_db = volume
			source.applied_db = volume
		if not player.playing:
			player.play(_rng.randf() * source.stream.get_length())


## Nombre de sources (pour les tests et les mesures).
func get_source_count() -> int:
	return _sources.size()


## Lecteur d'une source par identifiant ; null s'il n'existe pas.
func get_player(id: StringName) -> AudioStreamPlayer3D:
	for source: Source in _sources:
		if source.id == id:
			return source.player
	return null


func _exit_tree() -> void:
	if _task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1


func _build_source(id: StringName, spec: Dictionary, anchor: Dictionary, bus_name: String) -> Source:
	var context: String = "%s > sources > %s" % [CONTEXT, id]
	var source := Source.new()
	source.id = id
	source.context = context
	source.kind = JsonData.get_string(spec, "kind", context)
	source.synth = JsonData.get_dictionary(spec, "synth", context)
	source.window = FaunaSchedule.parse(JsonData.get_dictionary(spec, "hours", context), context + " > hours")
	source.base_db = JsonData.get_float(spec, "volume_db", context)
	var center: Vector2 = anchor["center"]
	center += JsonData.get_vector2(spec, "offset_m", context)
	source.anchor = Vector3(center.x, float(anchor["surface"]) + 1.5, center.y)
	var player := AudioStreamPlayer3D.new()
	player.name = String(id)
	player.bus = bus_name
	player.position = source.anchor
	player.volume_db = SILENT_DB
	player.unit_size = JsonData.get_float(spec, "unit_size_m", context)
	player.max_distance = JsonData.get_float(spec, "max_distance_m", context)
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	player.panning_strength = 1.0
	add_child(player)
	source.player = player
	if source.kind == "raptor_call":
		# Appel ponctuel : un minuteur le déclenche à intervalles irréguliers, depuis un point de l'anneau autour de l'ancrage.
		source.ring_min = JsonData.get_float(spec, "ring_min_m", context)
		source.ring_max = JsonData.get_float(spec, "ring_max_m", context)
		source.interval_min = JsonData.get_float(spec, "interval_s_min", context)
		source.interval_max = JsonData.get_float(spec, "interval_s_max", context)
		if source.ring_max < source.ring_min or source.interval_min <= 0.0 or source.interval_max < source.interval_min:
			push_error("FaunaAmbience : anneau ou intervalles invalides (%s)." % context)
			return null
		var timer := Timer.new()
		timer.name = "Intervalle"
		timer.one_shot = true
		timer.timeout.connect(_on_call_timer.bind(source))
		add_child(timer)
		source.timer = timer
		player.volume_db = source.base_db
	return source


func _synthesize() -> void:
	for source: Source in _sources:
		source.stream = FaunaSynth.build(source.kind, source.synth, _mix_rate, source.context)


func _next_interval(source: Source) -> float:
	return _rng.randf_range(source.interval_min, source.interval_max)


func _on_call_timer(source: Source) -> void:
	if FaunaSchedule.weight(_hour, source.window) > 0.0 and not source.player.playing:
		var angle: float = _rng.randf() * TAU
		var distance: float = _rng.randf_range(source.ring_min, source.ring_max)
		source.player.position = source.anchor + Vector3(cos(angle) * distance, 25.0, sin(angle) * distance)
		source.player.volume_db = source.base_db + linear_to_db(FaunaSchedule.weight(_hour, source.window))
		source.player.play()
	source.timer.start(_next_interval(source))


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
