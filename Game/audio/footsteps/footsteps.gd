class_name FootstepSystem
extends Node
## Singleton « Footsteps » : joue les sons de pas selon le sol et l'allure.
##
## Chaque émetteur (personnage, plus tard PNJ et montures) est branché par connect_emitter() sur son
## signal « footstep(foot, world_position, speed, collider) ». Pour chaque pas :
##   1. pas trop loin de l'auditeur (caméra active), sinon ignoré avant tout autre calcul ;
##   2. surface : métadonnée « surface » du collisionneur, sinon surface_at() du terrain qui le
##      possède (le collisionneur ou l'un de ses parents), sinon la surface par défaut (« sable ») ;
##   3. variante tirée au hasard sans jamais rejouer deux fois de suite la même sur une surface ;
##   4. volume et hauteur selon la surface et l'allure (déduite de la vitesse), avec variation ;
##   5. voix prise dans une réserve de lecteurs 3D créée une fois pour toutes au démarrage : une voix
##      libre, sinon la voix la plus ancienne est volée (le nombre de voix est donc plafonné) ; si
##      cette voix a démarré depuis moins de min_steal_age_ms, le pas est abandonné sans autre calcul
##      (la voler serait inaudible) : au plus « max_voices » pas sont donc joués par fenêtre de
##      min_steal_age_ms, quel que soit le nombre d'émetteurs.
##
## Couvert du sol : si une source est branchée par set_ground_cover() et que le pied est à moins de
## « ground_cover.radius_m » d'une touffe (alfa, drinn), un froissement léger est joué en plus du pas, sur une
## deuxième voix de la même réserve (abandonné si aucune voix n'est volable). La source répond en O(1) par la
## grille de la cellule (aucune requête physique).
##
## Pires cas : 200 émetteurs simultanés (foule), tous audibles, tous les pas dans la même image ;
## collisionneur détruit avant la résolution ; surface inconnue. Aucun objet n'est créé pendant le
## jeu : tableaux compacts dimensionnés par configure(), coût d'un pas borné par le nombre de voix
## (16 par défaut) et la profondeur de recherche du terrain.
##
## Réglages : res://data/audio/footsteps.json ; sons : res://data/assets/sounds.json.

const SETTINGS_PATH: String = "res://data/audio/footsteps.json"
const FOOTSTEP_SIGNAL: StringName = &"footstep"
const SURFACE_META: StringName = &"surface"
const SURFACE_AT_METHOD: StringName = &"surface_at"
## Plafond absolu de la réserve : au-delà, le mixage des pas coûterait plus que le reste du son.
const MAX_VOICES_LIMIT: int = 64
const MAX_TERRAIN_SEARCH_DEPTH: int = 16
const SEMITONES_PER_OCTAVE: float = 12.0
const USEC_PER_SECOND: float = 1000000.0

var _configured: bool = false
var _voices_created: bool = false
var _on_footstep_callable: Callable = _on_footstep
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

# Bus audio dédié.
var _bus_name: StringName = &""
var _bus_send: StringName = &""
var _bus_volume_db: float = 0.0

# Réserve de voix.
var _max_voices: int = 0
var _max_distance: float = 0.0
var _max_distance_squared: float = 0.0
var _unit_size: float = 1.0
var _max_db: float = 0.0
var _min_steal_age_usec: int = 0
var _attenuation: AudioStreamPlayer3D.AttenuationModel = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
var _panning_strength: float = 1.0
var _voices: Array[AudioStreamPlayer3D] = []
var _voice_start_usec: PackedInt64Array = PackedInt64Array()
var _voice_end_usec: PackedInt64Array = PackedInt64Array()

# Surfaces (indices compacts) et variantes (tableau plat, découpé par surface).
var _default_surface: int = 0
var _terrain_search_depth: int = 0
var _surface_ids: Array[StringName] = []
## Identifiant de surface (String et StringName) → indice.
var _surface_index: Dictionary = {}
var _surface_first_variant: PackedInt32Array = PackedInt32Array()
var _surface_variant_count: PackedInt32Array = PackedInt32Array()
var _surface_last_variant: PackedInt32Array = PackedInt32Array()
var _surface_volume_db: PackedFloat32Array = PackedFloat32Array()
var _surface_volume_variation_db: PackedFloat32Array = PackedFloat32Array()
var _surface_pitch_variation: PackedFloat32Array = PackedFloat32Array()
var _variant_streams: Array[AudioStream] = []
var _variant_length_usec: PackedInt64Array = PackedInt64Array()

# Couvert du sol (froissement des touffes) : désactivé tant que le bloc « ground_cover » est absent des réglages.
var _cover_enabled: bool = false
var _cover_radius: float = 0.0
var _cover_volume_db: float = 0.0
var _cover_volume_variation_db: float = 0.0
var _cover_pitch_variation: float = 0.0
var _cover_first_variant: int = 0
var _cover_variant_count: int = 0
var _cover_last_variant: int = -1
## Source branchée : (x, z, rayon) -> carré de la distance à la touffe la plus proche, ou -1.0 s'il n'y en a pas.
var _cover_lookup: Callable = Callable()
var _cover_rustles: int = 0

# Allures, triées par vitesse minimale croissante.
var _gait_ids: Array[StringName] = []
var _gait_min_speed: PackedFloat32Array = PackedFloat32Array()
var _gait_volume_db: PackedFloat32Array = PackedFloat32Array()
var _gait_pitch_scale: PackedFloat32Array = PackedFloat32Array()

# Compteurs (diagnostic et tests).
var _steps_received: int = 0
var _steps_played: int = 0
var _steps_culled: int = 0
var _steps_rejected: int = 0
var _steps_dropped: int = 0
var _voices_stolen: int = 0
var _unknown_surfaces: int = 0


func _init() -> void:
	_rng.randomize()


func _ready() -> void:
	if not _configured:
		var settings: Dictionary = JsonData.load_dictionary(SETTINGS_PATH)
		var manifest: Dictionary = JsonData.load_dictionary(SoundLibrary.MANIFEST_PATH)
		if not configure(settings, SoundLibrary.load_streams(manifest, collect_variant_ids(settings))):
			return
	_ensure_bus()
	_create_voices()


## Identifiants de tous les sons cités par des réglages (pour les charger avant configure()).
static func collect_variant_ids(settings: Dictionary) -> PackedStringArray:
	var ids := PackedStringArray()
	var surfaces: Dictionary = JsonData.get_dictionary(settings, "surfaces", SETTINGS_PATH)
	for surface_id: Variant in surfaces:
		var surface_value: Variant = surfaces[surface_id]
		if typeof(surface_value) != TYPE_DICTIONARY:
			continue
		var surface: Dictionary = surface_value
		if typeof(surface.get("variants")) != TYPE_ARRAY:
			continue
		var variants: Array = surface["variants"]
		for variant: Variant in variants:
			if typeof(variant) != TYPE_STRING:
				continue
			var variant_id: String = variant
			if not ids.has(variant_id):
				ids.append(variant_id)
	var cover: Variant = settings.get("ground_cover")
	if typeof(cover) == TYPE_DICTIONARY and typeof((cover as Dictionary).get("variants")) == TYPE_ARRAY:
		for cover_variant: Variant in (cover as Dictionary)["variants"] as Array:
			if typeof(cover_variant) == TYPE_STRING and not ids.has(cover_variant as String):
				ids.append(cover_variant as String)
	return ids


## Valide les réglages et prépare toutes les structures. À appeler avant l'entrée dans l'arbre
## (sinon _ready() charge les réglages et les sons du jeu). streams : identifiant → son.
func configure(settings: Dictionary, streams: Dictionary[String, AudioStream]) -> bool:
	if _voices_created:
		push_error("Footsteps : configure() doit être appelé avant l'entrée dans l'arbre.")
		return false
	var ok: bool = _parse_bus(settings)
	ok = _parse_voices(settings) and ok
	ok = _parse_gaits(settings) and ok
	ok = _parse_surfaces(settings, streams) and ok
	ok = _parse_ground_cover(settings, streams) and ok
	var depth: int = JsonData.get_int(settings, "terrain_search_depth", SETTINGS_PATH)
	if depth < 0 or depth > MAX_TERRAIN_SEARCH_DEPTH:
		push_error("Footsteps : « terrain_search_depth » doit être compris entre 0 et %d." % MAX_TERRAIN_SEARCH_DEPTH)
		ok = false
	_terrain_search_depth = depth
	_configured = ok
	return ok


## Branche un émetteur : il doit posséder le signal « footstep(foot, world_position, speed, collider) ».
func connect_emitter(emitter: Object) -> bool:
	if emitter == null or not emitter.has_signal(FOOTSTEP_SIGNAL):
		push_error("Footsteps : l'émetteur %s n'a pas de signal « footstep »." % emitter)
		return false
	if emitter.is_connected(FOOTSTEP_SIGNAL, _on_footstep_callable):
		return true
	var err: int = emitter.connect(FOOTSTEP_SIGNAL, _on_footstep_callable)
	if err != OK:
		push_error("Footsteps : branchement impossible (%s)." % error_string(err))
		return false
	return true


func disconnect_emitter(emitter: Object) -> void:
	if emitter != null and is_instance_valid(emitter) and emitter.is_connected(FOOTSTEP_SIGNAL, _on_footstep_callable):
		emitter.disconnect(FOOTSTEP_SIGNAL, _on_footstep_callable)


## Branche la source du couvert du sol : lookup(x, z, rayon) renvoie le carré de la distance à la touffe la plus
## proche dans le rayon, ou -1.0. L'appelant garde l'objet propriétaire de la méthode (il n'est pas retenu ici).
## Un Callable vide débranche.
func set_ground_cover(lookup: Callable) -> void:
	_cover_lookup = lookup


func is_emitter_connected(emitter: Object) -> bool:
	return emitter != null and is_instance_valid(emitter) and emitter.is_connected(FOOTSTEP_SIGNAL, _on_footstep_callable)


## Joue un pas à l'instant now_usec (horloge de Time.get_ticks_usec()). Renvoie l'indice de la voix
## utilisée, ou -1 si le pas est ignoré (trop loin, valeurs invalides, système non prêt).
func play_footstep(world_position: Vector3, speed: float, collider: Variant, now_usec: int) -> int:
	_steps_received += 1
	if not _voices_created or not is_inside_tree() or not world_position.is_finite() or is_nan(speed):
		_steps_rejected += 1
		return -1
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera != null and camera.global_position.distance_squared_to(world_position) > _max_distance_squared:
		_steps_culled += 1
		return -1
	var voice_index: int = _acquire_voice(now_usec)
	if voice_index < 0:
		_steps_dropped += 1
		return -1
	var surface: int = resolve_surface(collider, world_position)
	var variant: int = _pick_variant(surface)
	var gait: int = _gait_for_speed(speed)
	var pitch_variation: float = _surface_pitch_variation[surface]
	var semitones: float = _rng.randf_range(-pitch_variation, pitch_variation)
	var pitch: float = _gait_pitch_scale[gait] * pow(2.0, semitones / SEMITONES_PER_OCTAVE)
	var volume_variation: float = _surface_volume_variation_db[surface]
	var volume: float = _surface_volume_db[surface] + _gait_volume_db[gait] + _rng.randf_range(-volume_variation, volume_variation)
	var voice: AudioStreamPlayer3D = _voices[voice_index]
	voice.stream = _variant_streams[variant]
	voice.pitch_scale = pitch
	voice.volume_db = volume
	voice.position = world_position
	voice.play()
	_voice_start_usec[voice_index] = now_usec
	_voice_end_usec[voice_index] = now_usec + int(float(_variant_length_usec[variant]) / pitch)
	_steps_played += 1
	if _cover_enabled and _cover_lookup.is_valid():
		_play_rustle(world_position, _gait_volume_db[gait], now_usec)
	return voice_index


## Indice de surface d'un pas : métadonnée « surface », sinon surface_at() du terrain propriétaire
## (le collisionneur puis ses parents, jusqu'à terrain_search_depth niveaux), sinon surface par défaut.
## Un collisionneur nul ou détruit donne la surface par défaut.
func resolve_surface(collider: Variant, world_position: Vector3) -> int:
	if typeof(collider) != TYPE_OBJECT or not is_instance_valid(collider):
		return _default_surface
	var object: Object = collider
	if object.has_meta(SURFACE_META):
		return _surface_from_value(object.get_meta(SURFACE_META))
	if object.has_method(SURFACE_AT_METHOD):
		return _surface_from_value(object.call(SURFACE_AT_METHOD, world_position))
	var node: Node = object as Node
	var depth: int = 0
	while node != null and depth < _terrain_search_depth:
		node = node.get_parent()
		depth += 1
		if node != null and node.has_method(SURFACE_AT_METHOD):
			return _surface_from_value(node.call(SURFACE_AT_METHOD, world_position))
	return _default_surface


func get_surface_index(surface_id: StringName) -> int:
	return _surface_index.get(surface_id, -1)


func get_surface_ids() -> Array[StringName]:
	return _surface_ids.duplicate()


func get_variant_count(surface_id: StringName) -> int:
	var surface: int = get_surface_index(surface_id)
	return 0 if surface < 0 else _surface_variant_count[surface]


func get_gait_index(speed: float) -> int:
	return _gait_for_speed(speed)


func get_gait_ids() -> Array[StringName]:
	return _gait_ids.duplicate()


func get_voice_count() -> int:
	return _voices.size()


func get_voice(index: int) -> AudioStreamPlayer3D:
	return _voices[index]


## Nombre de voix encore en train de jouer à l'instant now_usec.
func get_active_voice_count(now_usec: int) -> int:
	var count: int = 0
	for i: int in _voice_end_usec.size():
		if _voice_end_usec[i] > now_usec:
			count += 1
	return count


func get_bus_name() -> StringName:
	return _bus_name


func seed_random(value: int) -> void:
	_rng.seed = value


func get_stats() -> Dictionary[String, int]:
	return {
		"steps_received": _steps_received,
		"steps_played": _steps_played,
		"steps_culled": _steps_culled,
		"steps_rejected": _steps_rejected,
		"steps_dropped": _steps_dropped,
		"voices_stolen": _voices_stolen,
		"unknown_surfaces": _unknown_surfaces,
		"rustles_played": _cover_rustles,
	}


func _on_footstep(_foot: int, world_position: Vector3, speed: float, collider: Variant) -> void:
	@warning_ignore("return_value_discarded")
	play_footstep(world_position, speed, collider, Time.get_ticks_usec())


## Froissement des touffes sous le pied : une voix de plus, seulement s'il y a une touffe à portée. O(1).
func _play_rustle(world_position: Vector3, gait_volume_db: float, now_usec: int) -> void:
	var distance_squared: float = float(_cover_lookup.call(world_position.x, world_position.z, _cover_radius))
	if distance_squared < 0.0:
		return
	var voice_index: int = _acquire_voice(now_usec)
	if voice_index < 0:
		return
	var local: int = 0
	if _cover_variant_count > 1:
		if _cover_last_variant < 0:
			local = _rng.randi_range(0, _cover_variant_count - 1)
		else:
			local = _rng.randi_range(0, _cover_variant_count - 2)
			if local >= _cover_last_variant:
				local += 1
	_cover_last_variant = local
	var variant: int = _cover_first_variant + local
	var pitch: float = pow(2.0, _rng.randf_range(-_cover_pitch_variation, _cover_pitch_variation) / SEMITONES_PER_OCTAVE)
	var voice: AudioStreamPlayer3D = _voices[voice_index]
	voice.stream = _variant_streams[variant]
	voice.pitch_scale = pitch
	voice.volume_db = _cover_volume_db + gait_volume_db + _rng.randf_range(-_cover_volume_variation_db, _cover_volume_variation_db)
	voice.position = world_position
	voice.play()
	_voice_start_usec[voice_index] = now_usec
	_voice_end_usec[voice_index] = now_usec + int(float(_variant_length_usec[variant]) / pitch)
	_cover_rustles += 1


func _surface_from_value(value: Variant) -> int:
	var value_type: int = typeof(value)
	if value_type == TYPE_STRING or value_type == TYPE_STRING_NAME:
		var index: int = _surface_index.get(value, -1)
		if index >= 0:
			return index
	_unknown_surfaces += 1
	return _default_surface


## Variante de la surface, jamais égale à la précédente (s'il y en a au moins deux). O(1).
func _pick_variant(surface: int) -> int:
	var count: int = _surface_variant_count[surface]
	var last: int = _surface_last_variant[surface]
	var local: int = 0
	if count > 1:
		if last < 0:
			local = _rng.randi_range(0, count - 1)
		else:
			local = _rng.randi_range(0, count - 2)
			if local >= last:
				local += 1
	_surface_last_variant[surface] = local
	return _surface_first_variant[surface] + local


func _gait_for_speed(speed: float) -> int:
	var gait: int = _gait_min_speed.size() - 1
	while gait > 0 and speed < _gait_min_speed[gait]:
		gait -= 1
	return gait


## Première voix libre, sinon la plus ancienne (volée), sinon -1 si elle est trop récente pour être
## volée. O(nombre de voix), plafonné.
func _acquire_voice(now_usec: int) -> int:
	var oldest: int = 0
	var oldest_start: int = _voice_start_usec[0]
	for i: int in _max_voices:
		if _voice_end_usec[i] <= now_usec:
			return i
		if _voice_start_usec[i] < oldest_start:
			oldest = i
			oldest_start = _voice_start_usec[i]
	if now_usec - oldest_start < _min_steal_age_usec:
		return -1
	_voices_stolen += 1
	return oldest


func _ensure_bus() -> void:
	var send_index: int = AudioServer.get_bus_index(_bus_send)
	if send_index < 0:
		push_error("Footsteps : bus de destination « %s » introuvable." % _bus_send)
	var index: int = AudioServer.get_bus_index(_bus_name)
	if index < 0:
		AudioServer.add_bus()
		index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, _bus_name)
	AudioServer.set_bus_send(index, _bus_send)
	AudioServer.set_bus_volume_db(index, _bus_volume_db)


func _create_voices() -> void:
	_voices.clear()
	_voice_start_usec.resize(_max_voices)
	_voice_end_usec.resize(_max_voices)
	_voice_start_usec.fill(0)
	_voice_end_usec.fill(0)
	for i: int in _max_voices:
		var voice := AudioStreamPlayer3D.new()
		voice.name = "Voice%02d" % i
		voice.bus = _bus_name
		voice.max_distance = _max_distance
		voice.unit_size = _unit_size
		voice.max_db = _max_db
		voice.attenuation_model = _attenuation
		voice.panning_strength = _panning_strength
		voice.max_polyphony = 1
		voice.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		add_child(voice)
		_voices.append(voice)
	_voices_created = true


func _parse_bus(settings: Dictionary) -> bool:
	var bus: Dictionary = JsonData.get_dictionary(settings, "bus", SETTINGS_PATH)
	var bus_name: String = JsonData.get_string(bus, "name", SETTINGS_PATH)
	var send: String = JsonData.get_string(bus, "send", SETTINGS_PATH)
	_bus_name = StringName(bus_name)
	_bus_send = StringName(send)
	_bus_volume_db = JsonData.get_float(bus, "volume_db", SETTINGS_PATH)
	if bus_name.is_empty() or send.is_empty() or bus_name == send:
		push_error("Footsteps : le bus doit avoir un nom et un bus de destination différents (%s)." % SETTINGS_PATH)
		return false
	return true


func _parse_voices(settings: Dictionary) -> bool:
	var voices: Dictionary = JsonData.get_dictionary(settings, "voices", SETTINGS_PATH)
	var ok: bool = true
	_max_voices = JsonData.get_int(voices, "max_voices", SETTINGS_PATH)
	if _max_voices < 1 or _max_voices > MAX_VOICES_LIMIT:
		push_error("Footsteps : « max_voices » doit être compris entre 1 et %d." % MAX_VOICES_LIMIT)
		_max_voices = 0
		ok = false
	_max_distance = JsonData.get_float(voices, "max_distance", SETTINGS_PATH)
	_unit_size = JsonData.get_float(voices, "unit_size", SETTINGS_PATH)
	if _max_distance <= 0.0 or _unit_size <= 0.0:
		push_error("Footsteps : « max_distance » et « unit_size » doivent être positifs.")
		ok = false
	_max_distance_squared = _max_distance * _max_distance
	_max_db = JsonData.get_float(voices, "max_db", SETTINGS_PATH)
	var steal_age_ms: float = JsonData.get_float(voices, "min_steal_age_ms", SETTINGS_PATH)
	if steal_age_ms < 0.0:
		push_error("Footsteps : « min_steal_age_ms » doit être positif ou nul.")
		ok = false
	_min_steal_age_usec = int(steal_age_ms * 1000.0)
	_panning_strength = JsonData.get_float(voices, "panning_strength", SETTINGS_PATH)
	var model: String = JsonData.get_string(voices, "attenuation", SETTINGS_PATH)
	match model:
		"inverse":
			_attenuation = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		"inverse_square":
			_attenuation = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
		"logarithmic":
			_attenuation = AudioStreamPlayer3D.ATTENUATION_LOGARITHMIC
		_:
			push_error("Footsteps : « attenuation » inconnue « %s » (inverse, inverse_square ou logarithmic)." % model)
			ok = false
	return ok


func _parse_gaits(settings: Dictionary) -> bool:
	_gait_ids.clear()
	_gait_min_speed.clear()
	_gait_volume_db.clear()
	_gait_pitch_scale.clear()
	var ok: bool = true
	for entry: Variant in JsonData.get_array(settings, "gaits", SETTINGS_PATH):
		if typeof(entry) != TYPE_DICTIONARY:
			push_error("Footsteps : chaque allure doit être un objet JSON.")
			ok = false
			continue
		var gait: Dictionary = entry
		var min_speed: float = JsonData.get_float(gait, "min_speed", SETTINGS_PATH)
		var pitch_scale: float = JsonData.get_float(gait, "pitch_scale", SETTINGS_PATH)
		var expected_first: bool = _gait_min_speed.is_empty()
		if (expected_first and min_speed != 0.0) or (not expected_first and min_speed <= _gait_min_speed[_gait_min_speed.size() - 1]):
			push_error("Footsteps : les allures doivent être triées par « min_speed » croissante, la première à 0.")
			ok = false
		if pitch_scale <= 0.0:
			push_error("Footsteps : « pitch_scale » doit être positif.")
			ok = false
		_gait_ids.append(StringName(JsonData.get_string(gait, "id", SETTINGS_PATH)))
		_gait_min_speed.append(min_speed)
		_gait_volume_db.append(JsonData.get_float(gait, "volume_db", SETTINGS_PATH))
		_gait_pitch_scale.append(pitch_scale)
	if _gait_ids.is_empty():
		push_error("Footsteps : aucune allure dans %s." % SETTINGS_PATH)
		ok = false
	return ok


## Bloc facultatif « ground_cover » : absent, le froissement est désactivé.
func _parse_ground_cover(settings: Dictionary, streams: Dictionary[String, AudioStream]) -> bool:
	_cover_enabled = false
	_cover_variant_count = 0
	_cover_last_variant = -1
	if not settings.has("ground_cover"):
		return true
	var context: String = "%s, ground_cover" % SETTINGS_PATH
	var cover: Dictionary = JsonData.get_dictionary(settings, "ground_cover", SETTINGS_PATH)
	_cover_radius = JsonData.get_float(cover, "radius_m", context)
	_cover_volume_db = JsonData.get_float(cover, "volume_db", context)
	_cover_volume_variation_db = JsonData.get_float(cover, "volume_variation_db", context)
	_cover_pitch_variation = JsonData.get_float(cover, "pitch_variation_semitones", context)
	var ok: bool = true
	if _cover_radius <= 0.0 or _cover_volume_variation_db < 0.0 or _cover_pitch_variation < 0.0:
		push_error("Footsteps : rayon positif et variations positives ou nulles attendus (%s)." % context)
		ok = false
	_cover_first_variant = _variant_streams.size()
	for variant: Variant in JsonData.get_array(cover, "variants", context):
		var variant_id: String = str(variant)
		var stream: AudioStream = streams.get(variant_id)
		if stream == null or stream.get_length() <= 0.0:
			push_error("Footsteps : son « %s » absent ou vide (%s)." % [variant_id, context])
			ok = false
			continue
		_variant_streams.append(stream)
		_variant_length_usec.append(int(stream.get_length() * USEC_PER_SECOND))
	_cover_variant_count = _variant_streams.size() - _cover_first_variant
	if _cover_variant_count == 0:
		push_error("Footsteps : aucune variante valide (%s)." % context)
		ok = false
	_cover_enabled = ok
	return ok


func _parse_surfaces(settings: Dictionary, streams: Dictionary[String, AudioStream]) -> bool:
	_surface_ids.clear()
	_surface_index.clear()
	_surface_first_variant.clear()
	_surface_variant_count.clear()
	_surface_last_variant.clear()
	_surface_volume_db.clear()
	_surface_volume_variation_db.clear()
	_surface_pitch_variation.clear()
	_variant_streams.clear()
	_variant_length_usec.clear()
	var ok: bool = true
	var surfaces: Dictionary = JsonData.get_dictionary(settings, "surfaces", SETTINGS_PATH)
	for key: Variant in surfaces:
		var surface_id: String = str(key)
		var context: String = "%s, surface %s" % [SETTINGS_PATH, surface_id]
		if typeof(surfaces[key]) != TYPE_DICTIONARY:
			push_error("Footsteps : la surface doit être un objet JSON (%s)." % context)
			ok = false
			continue
		var surface: Dictionary = surfaces[key]
		var first: int = _variant_streams.size()
		for variant: Variant in JsonData.get_array(surface, "variants", context):
			var variant_id: String = str(variant)
			var stream: AudioStream = streams.get(variant_id)
			if stream == null or stream.get_length() <= 0.0:
				push_error("Footsteps : son « %s » absent ou vide (%s)." % [variant_id, context])
				ok = false
				continue
			_variant_streams.append(stream)
			_variant_length_usec.append(int(stream.get_length() * USEC_PER_SECOND))
		var count: int = _variant_streams.size() - first
		if count == 0:
			push_error("Footsteps : aucune variante valide (%s)." % context)
			ok = false
			continue
		var volume_variation: float = JsonData.get_float(surface, "volume_variation_db", context)
		var pitch_variation: float = JsonData.get_float(surface, "pitch_variation_semitones", context)
		if volume_variation < 0.0 or pitch_variation < 0.0:
			push_error("Footsteps : les variations doivent être positives ou nulles (%s)." % context)
			ok = false
		var index: int = _surface_ids.size()
		_surface_ids.append(StringName(surface_id))
		_surface_index[surface_id] = index
		_surface_index[StringName(surface_id)] = index
		_surface_first_variant.append(first)
		_surface_variant_count.append(count)
		_surface_last_variant.append(-1)
		_surface_volume_db.append(JsonData.get_float(surface, "volume_db", context))
		_surface_volume_variation_db.append(volume_variation)
		_surface_pitch_variation.append(pitch_variation)
	var default_id: String = JsonData.get_string(settings, "default_surface", SETTINGS_PATH)
	_default_surface = _surface_index.get(default_id, -1)
	if _default_surface < 0:
		push_error("Footsteps : surface par défaut « %s » absente des surfaces." % default_id)
		_default_surface = 0
		ok = false
	if _surface_ids.is_empty():
		ok = false
	return ok
