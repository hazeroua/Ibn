extends GutTest
## Sons de pas : résolution de la surface, choix des variantes, réserve de voix et plafond.
## Sons de synthèse (silence de durée connue) et doublures : le résultat ne dépend ni des fichiers
## téléchargés ni du pilote audio (factice sur la CI).

const STREAM_SECONDS: float = 0.25
const STREAM_USEC: int = 250000
const MIX_RATE: int = 44100


class EmitterDouble:
	extends RefCounted
	signal footstep(foot: int, world_position: Vector3, speed: float, collider: Object)

	func step(world_position: Vector3, speed: float, collider: Object) -> void:
		footstep.emit(0, world_position, speed, collider)


class TerrainDouble:
	extends Node3D
	var answer: StringName = &"pierre"
	var calls: int = 0

	func surface_at(world_position: Vector3) -> StringName:
		calls += 1
		if world_position.x < 0.0:
			return &"terre"
		return answer


static func _make_stream(seconds: float) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	var data := PackedByteArray()
	data.resize(int(seconds * float(MIX_RATE)) * 2)
	stream.data = data
	return stream


static func _make_settings(variant_counts: Dictionary[String, int], max_voices: int, with_variation: bool) -> Dictionary:
	var surfaces: Dictionary = {}
	var volume: float = 0.0
	for surface_id: String in variant_counts:
		var variants: Array = []
		for i: int in variant_counts[surface_id]:
			variants.append("%s_%d" % [surface_id, i])
		surfaces[surface_id] = {
			"volume_db": volume,
			"volume_variation_db": 1.5 if with_variation else 0.0,
			"pitch_variation_semitones": 1.0 if with_variation else 0.0,
			"variants": variants,
		}
		volume -= 1.0
	return {
		"bus": {"name": "Footsteps", "send": "Master", "volume_db": 0.0},
		"voices":
		{
			"max_voices": max_voices,
			"max_distance": 30.0,
			"unit_size": 3.0,
			"max_db": 3.0,
			"attenuation": "inverse_square",
			"panning_strength": 1.0,
		},
		"default_surface": "sable",
		"terrain_search_depth": 3,
		"gaits":
		[
			{"id": "walk_slow", "min_speed": 0.0, "volume_db": -6.0, "pitch_scale": 0.97},
			{"id": "walk", "min_speed": 1.3, "volume_db": -2.0, "pitch_scale": 1.0},
			{"id": "run", "min_speed": 3.0, "volume_db": 1.5, "pitch_scale": 1.04},
		],
		"surfaces": surfaces,
	}


func _make_system(variant_counts: Dictionary[String, int], max_voices: int, with_variation: bool = true) -> FootstepSystem:
	var settings: Dictionary = _make_settings(variant_counts, max_voices, with_variation)
	var streams: Dictionary[String, AudioStream] = {}
	for id: String in FootstepSystem.collect_variant_ids(settings):
		streams[id] = _make_stream(STREAM_SECONDS)
	var system := FootstepSystem.new()
	assert_true(system.configure(settings, streams), "réglages de test valides")
	system.seed_random(20260115)
	add_child_autofree(system)
	return system


func _default_system(max_voices: int = 8) -> FootstepSystem:
	return _make_system({"sable": 4, "pierre": 3, "terre": 5, "bois": 2}, max_voices)


func _body_with_surface(value: Variant) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.set_meta(&"surface", value)
	return autofree(body)


func test_surface_from_metadata() -> void:
	var system: FootstepSystem = _default_system()
	assert_eq(system.resolve_surface(_body_with_surface("pierre"), Vector3.ZERO), system.get_surface_index(&"pierre"))
	assert_eq(system.resolve_surface(_body_with_surface(&"bois"), Vector3.ZERO), system.get_surface_index(&"bois"))
	assert_eq(system.resolve_surface(_body_with_surface("terre"), Vector3.ZERO), system.get_surface_index(&"terre"))


func test_metadata_wins_over_terrain() -> void:
	var system: FootstepSystem = _default_system()
	var terrain := TerrainDouble.new()
	add_child_autofree(terrain)
	var body := StaticBody3D.new()
	body.set_meta(&"surface", "bois")
	terrain.add_child(body)
	assert_eq(system.resolve_surface(body, Vector3(5.0, 0.0, 0.0)), system.get_surface_index(&"bois"))
	assert_eq(terrain.calls, 0, "la métadonnée évite tout appel au terrain")


func test_surface_from_terrain_parent() -> void:
	var system: FootstepSystem = _default_system()
	var terrain := TerrainDouble.new()
	add_child_autofree(terrain)
	var holder := Node3D.new()
	terrain.add_child(holder)
	var body := StaticBody3D.new()
	holder.add_child(body)
	assert_eq(system.resolve_surface(body, Vector3(5.0, 0.0, 0.0)), system.get_surface_index(&"pierre"))
	assert_eq(system.resolve_surface(body, Vector3(-5.0, 0.0, 0.0)), system.get_surface_index(&"terre"))
	assert_eq(terrain.calls, 2)


func test_collider_that_is_the_terrain() -> void:
	var system: FootstepSystem = _default_system()
	var terrain := TerrainDouble.new()
	add_child_autofree(terrain)
	assert_eq(system.resolve_surface(terrain, Vector3(1.0, 0.0, 0.0)), system.get_surface_index(&"pierre"))


func test_terrain_beyond_search_depth_is_ignored() -> void:
	var system: FootstepSystem = _default_system()
	var terrain := TerrainDouble.new()
	add_child_autofree(terrain)
	var node: Node3D = terrain
	for i: int in 4:
		var child := Node3D.new()
		node.add_child(child)
		node = child
	assert_eq(system.resolve_surface(node, Vector3(1.0, 0.0, 0.0)), system.get_surface_index(&"sable"))
	assert_eq(terrain.calls, 0, "recherche bornée à terrain_search_depth niveaux")


func test_default_surface_without_information() -> void:
	var system: FootstepSystem = _default_system()
	var sable: int = system.get_surface_index(&"sable")
	assert_eq(system.resolve_surface(null, Vector3.ZERO), sable)
	assert_eq(system.resolve_surface(autofree(StaticBody3D.new()), Vector3.ZERO), sable)
	assert_eq(system.resolve_surface(RefCounted.new(), Vector3.ZERO), sable)
	assert_eq(system.get_stats()["unknown_surfaces"], 0)


func test_unknown_surface_falls_back_to_default() -> void:
	var system: FootstepSystem = _default_system()
	var sable: int = system.get_surface_index(&"sable")
	assert_eq(system.resolve_surface(_body_with_surface("marbre"), Vector3.ZERO), sable)
	assert_eq(system.resolve_surface(_body_with_surface(42), Vector3.ZERO), sable)
	var terrain := TerrainDouble.new()
	terrain.answer = &"neige"
	add_child_autofree(terrain)
	assert_eq(system.resolve_surface(terrain, Vector3(1.0, 0.0, 0.0)), sable)
	assert_eq(system.get_stats()["unknown_surfaces"], 3)


func test_destroyed_collider_falls_back_to_default() -> void:
	var system: FootstepSystem = _default_system()
	var body := StaticBody3D.new()
	body.set_meta(&"surface", "pierre")
	var collider: Variant = body
	body.free()
	assert_eq(system.resolve_surface(collider, Vector3.ZERO), system.get_surface_index(&"sable"))
	assert_gte(system.play_footstep(Vector3.ZERO, 1.5, collider, 0), 0, "le pas est joué malgré tout")


func test_variants_never_repeat_and_all_are_used() -> void:
	var system: FootstepSystem = _make_system({"sable": 4, "pierre": 2}, 4)
	for surface_id: StringName in [&"sable", &"pierre"]:
		var collider: StaticBody3D = _body_with_surface(String(surface_id))
		var seen: Dictionary = {}
		var previous: AudioStream = null
		for i: int in 2000:
			var voice: int = system.play_footstep(Vector3.ZERO, 1.5, collider, i * STREAM_USEC)
			var stream: AudioStream = system.get_voice(voice).stream
			assert_ne(stream, previous, "%s : variante répétée au pas %d" % [surface_id, i])
			previous = stream
			seen[stream.get_instance_id()] = true
		assert_eq(seen.size(), system.get_variant_count(surface_id), "%s : toutes les variantes servent" % surface_id)


func test_single_variant_surface_plays() -> void:
	var system: FootstepSystem = _make_system({"sable": 1}, 2)
	var first: int = system.play_footstep(Vector3.ZERO, 1.5, null, 0)
	var second: int = system.play_footstep(Vector3.ZERO, 1.5, null, STREAM_USEC)
	assert_same(system.get_voice(first).stream, system.get_voice(second).stream)


func test_voice_cap_steals_oldest() -> void:
	var system: FootstepSystem = _default_system(4)
	var voices: PackedInt32Array = PackedInt32Array()
	for i: int in 4:
		voices.append(system.play_footstep(Vector3.ZERO, 1.5, null, 1000 + i))
	assert_eq(system.get_active_voice_count(2000), 4)
	var stolen: int = system.play_footstep(Vector3.ZERO, 1.5, null, 2000)
	assert_eq(stolen, voices[0], "la voix la plus ancienne est volée")
	assert_eq(system.get_stats()["voices_stolen"], 1)
	var stolen_again: int = system.play_footstep(Vector3.ZERO, 1.5, null, 2001)
	assert_eq(stolen_again, voices[1], "puis la suivante la plus ancienne")
	assert_eq(system.get_active_voice_count(2001), 4, "jamais plus de voix que le plafond")


func test_finished_voice_is_reused_without_stealing() -> void:
	var system: FootstepSystem = _make_system({"sable": 3}, 4, false)
	var first: int = system.play_footstep(Vector3.ZERO, 1.5, null, 0)
	assert_eq(system.get_active_voice_count(1), 1)
	var later: int = system.play_footstep(Vector3.ZERO, 1.5, null, STREAM_USEC + 1)
	assert_eq(later, first, "la voix terminée est réutilisée")
	assert_eq(system.get_stats()["voices_stolen"], 0)
	assert_eq(system.get_active_voice_count(STREAM_USEC + 1), 1)


func test_pool_is_created_once_and_never_grows() -> void:
	var system: FootstepSystem = _default_system(6)
	assert_eq(system.get_voice_count(), 6)
	var players: Array[AudioStreamPlayer3D] = []
	for i: int in 6:
		players.append(system.get_voice(i))
	for i: int in 5000:
		system.play_footstep(Vector3(float(i % 7), 0.0, 0.0), float(i % 5), null, i * 10)
	assert_eq(system.get_child_count(), 6, "aucun lecteur créé pendant le jeu")
	for i: int in 6:
		assert_same(system.get_voice(i), players[i])
	assert_eq(system.get_stats()["steps_played"], 5000)


func test_dedicated_bus_and_voice_settings() -> void:
	var system: FootstepSystem = _default_system(3)
	var bus: int = AudioServer.get_bus_index(system.get_bus_name())
	assert_gte(bus, 0, "bus des pas créé")
	assert_eq(AudioServer.get_bus_send(bus), &"Master")
	for i: int in system.get_voice_count():
		var voice: AudioStreamPlayer3D = system.get_voice(i)
		assert_eq(voice.bus, system.get_bus_name())
		assert_eq(voice.max_polyphony, 1)
		assert_almost_eq(voice.max_distance, 30.0, 0.001)
		assert_eq(voice.attenuation_model, AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE)


func test_gait_sets_volume_and_pitch() -> void:
	var system: FootstepSystem = _make_system({"sable": 2, "pierre": 2}, 4, false)
	assert_eq(system.get_gait_index(0.0), 0)
	assert_eq(system.get_gait_index(1.29), 0)
	assert_eq(system.get_gait_index(1.3), 1)
	assert_eq(system.get_gait_index(2.0), 1)
	assert_eq(system.get_gait_index(6.0), 2)
	assert_eq(system.get_gait_index(-1.0), 0)
	var pierre: StaticBody3D = _body_with_surface("pierre")
	var voice: AudioStreamPlayer3D = system.get_voice(system.play_footstep(Vector3(1.0, 2.0, 3.0), 4.0, pierre, 0))
	# Pierre : -1 dB ; course : +1,5 dB et hauteur 1,04 (variations nulles dans ces réglages).
	assert_almost_eq(voice.volume_db, 0.5, 0.001)
	assert_almost_eq(voice.pitch_scale, 1.04, 0.0001)
	assert_eq(voice.position, Vector3(1.0, 2.0, 3.0))
	voice = system.get_voice(system.play_footstep(Vector3.ZERO, 0.5, null, 1))
	assert_almost_eq(voice.volume_db, -6.0, 0.001)
	assert_almost_eq(voice.pitch_scale, 0.97, 0.0001)


func test_variation_stays_within_bounds() -> void:
	var system: FootstepSystem = _make_system({"sable": 4}, 4, true)
	var min_pitch: float = 1.0 * pow(2.0, -1.0 / 12.0) - 0.0001
	var max_pitch: float = 1.0 * pow(2.0, 1.0 / 12.0) + 0.0001
	var distinct: Dictionary = {}
	for i: int in 500:
		var voice: AudioStreamPlayer3D = system.get_voice(system.play_footstep(Vector3.ZERO, 2.0, null, i * STREAM_USEC))
		assert_between(voice.pitch_scale, min_pitch, max_pitch)
		assert_between(voice.volume_db, -2.0 - 1.5 - 0.001, -2.0 + 1.5 + 0.001)
		distinct[snappedf(voice.pitch_scale, 0.001)] = true
	assert_gt(distinct.size(), 20, "la hauteur varie d'un pas à l'autre")


func test_emitter_signal_plays_steps() -> void:
	var system: FootstepSystem = _default_system(4)
	var emitter := EmitterDouble.new()
	assert_true(system.connect_emitter(emitter))
	assert_true(system.connect_emitter(emitter), "brancher deux fois ne double pas les pas")
	assert_true(system.is_emitter_connected(emitter))
	emitter.step(Vector3.ZERO, 1.5, _body_with_surface("bois"))
	emitter.step(Vector3.ZERO, 1.5, null)
	assert_eq(system.get_stats()["steps_played"], 2)
	system.disconnect_emitter(emitter)
	assert_false(system.is_emitter_connected(emitter))
	emitter.step(Vector3.ZERO, 1.5, null)
	assert_eq(system.get_stats()["steps_received"], 2)


func test_far_steps_are_culled_before_any_work() -> void:
	var system: FootstepSystem = _default_system(4)
	var camera := Camera3D.new()
	add_child_autofree(camera)
	camera.make_current()
	var terrain := TerrainDouble.new()
	add_child_autofree(terrain)
	assert_eq(system.play_footstep(Vector3(100.0, 0.0, 0.0), 1.5, terrain, 0), -1)
	assert_eq(terrain.calls, 0, "aucune résolution de surface pour un pas inaudible")
	assert_gte(system.play_footstep(Vector3(10.0, 0.0, 0.0), 1.5, terrain, 0), 0)
	assert_eq(system.get_stats()["steps_culled"], 1)


func test_invalid_values_are_rejected() -> void:
	var system: FootstepSystem = _default_system(4)
	assert_eq(system.play_footstep(Vector3(NAN, 0.0, 0.0), 1.5, null, 0), -1)
	assert_eq(system.play_footstep(Vector3(INF, 0.0, 0.0), 1.5, null, 0), -1)
	assert_eq(system.play_footstep(Vector3.ZERO, NAN, null, 0), -1)
	assert_eq(system.get_stats()["steps_rejected"], 3)
	assert_eq(system.get_active_voice_count(0), 0)
