extends GutTest
## Sons de pas : test de charge du pire cas (200 émetteurs simultanés, tous audibles, même image)
## et lecture des vrais réglages et des vrais sons du jeu.

const EMITTER_COUNT: int = 200
const FRAMES: int = 300
const SETTINGS_PATH: String = "res://data/audio/footsteps.json"
const STREAM_SECONDS: float = 0.3
const MIX_RATE: int = 22050
## Budget du coût moyen par image pour 200 pas simultanés (le jeu dispose de 16,6 ms par image).
const BUDGET_MS_PER_FRAME: float = 1.0


class EmitterDouble:
	extends RefCounted
	signal footstep(foot: int, world_position: Vector3, speed: float, collider: Object)


static func _make_stream() -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	var data := PackedByteArray()
	data.resize(int(STREAM_SECONDS * float(MIX_RATE)) * 2)
	stream.data = data
	return stream


func _system_from_game_settings() -> FootstepSystem:
	var settings: Dictionary = JsonData.load_dictionary(SETTINGS_PATH)
	var streams: Dictionary[String, AudioStream] = {}
	for id: String in FootstepSystem.collect_variant_ids(settings):
		streams[id] = _make_stream()
	var system := FootstepSystem.new()
	assert_true(system.configure(settings, streams), "les réglages du jeu sont valides")
	add_child_autofree(system)
	return system


func test_game_settings_cover_the_four_surfaces() -> void:
	var system: FootstepSystem = _system_from_game_settings()
	for surface_id: StringName in HorseGround.SURFACES:
		assert_gte(system.get_variant_count(surface_id), 2, "variantes de %s" % surface_id)
	assert_eq(system.get_gait_ids(), [&"walk_slow", &"walk", &"run"] as Array[StringName])


func test_manifest_declares_every_variant_with_cc0_source() -> void:
	var manifest: ResourceManifest = ResourceManifest.load_shipped()
	var shipped: Dictionary = JsonData.load_dictionary(ResourceManifest.PATH)
	var settings: Dictionary = JsonData.load_dictionary(SETTINGS_PATH)
	for id: String in FootstepSystem.collect_variant_ids(settings):
		assert_true(manifest.has_file(id), "son %s déclaré dans data/ressources.json" % id)
		if manifest.has_file(id):
			assert_eq(manifest.file_folder(id), ResourceManifest.DOWNLOAD_ROOT.path_join(SoundLibrary.SOUND_FOLDER))
			assert_eq(shipped["fichiers"][id]["licence"], "CC0 1.0", "licence de %s" % id)


func test_real_sounds_load_when_downloaded() -> void:
	var settings: Dictionary = JsonData.load_dictionary(SETTINGS_PATH)
	var ids: PackedStringArray = FootstepSystem.collect_variant_ids(settings)
	var streams: Dictionary[String, AudioStream] = SoundLibrary.load_streams(ids)
	assert_eq(streams.size(), ids.size(), "tous les sons importés par le pipeline sont lisibles")
	for id: String in streams:
		assert_gt(streams[id].get_length(), 0.05, "durée de %s" % id)
		assert_lt(streams[id].get_length(), 1.0, "un pas dure moins d'une seconde : %s" % id)


func test_worst_case_200_emitters_same_frame() -> void:
	var system: FootstepSystem = _system_from_game_settings()
	system.seed_random(7)
	var emitters: Array[EmitterDouble] = []
	var colliders: Array[StaticBody3D] = []
	var surfaces: PackedStringArray = ["sable", "pierre", "terre", "galets"]
	for i: int in EMITTER_COUNT:
		var emitter := EmitterDouble.new()
		assert_true(system.connect_emitter(emitter))
		emitters.append(emitter)
		var body := StaticBody3D.new()
		body.set_meta(&"surface", surfaces[i % 4])
		colliders.append(autofree(body))
	var children_before: int = system.get_child_count()
	var start: int = Time.get_ticks_usec()
	for frame: int in FRAMES:
		for i: int in EMITTER_COUNT:
			emitters[i].footstep.emit(i % 2, Vector3(float(i % 20), 0.0, float(i / 20)), float((i + frame) % 6), colliders[i])
	var elapsed_ms: float = float(Time.get_ticks_usec() - start) / 1000.0
	var per_frame_ms: float = elapsed_ms / float(FRAMES)
	var stats: Dictionary[String, int] = system.get_stats()
	gut.p(
		(
			"200 émetteurs x %d images : %.3f ms par image (%.2f microsecondes par pas), joués %d, abandonnés %d, voix volées %d"
			% [
				FRAMES,
				per_frame_ms,
				per_frame_ms * 1000.0 / float(EMITTER_COUNT),
				stats["steps_played"],
				stats["steps_dropped"],
				stats["voices_stolen"]
			]
		)
	)
	assert_eq(stats["steps_received"], EMITTER_COUNT * FRAMES)
	assert_eq(stats["steps_played"] + stats["steps_dropped"], EMITTER_COUNT * FRAMES, "chaque pas est joué ou abandonné")
	assert_lt(stats["steps_played"], EMITTER_COUNT * FRAMES, "le plafond de voix limite le travail")
	assert_eq(system.get_child_count(), children_before, "aucun lecteur créé pendant la charge")
	assert_lte(system.get_active_voice_count(Time.get_ticks_usec()), system.get_voice_count(), "plafond de voix tenu")
	PerfCheck.under(self, per_frame_ms, BUDGET_MS_PER_FRAME, "200 pas par image sous le budget")


func test_worst_case_200_steps_per_frame_at_60_fps_clock() -> void:
	# Horloge simulée à 60 i/s : 200 pas par image pendant 10 s ; les voix libérées sont réutilisées,
	# les autres sont volées après 40 ms, le reste est abandonné.
	var system: FootstepSystem = _system_from_game_settings()
	system.seed_random(11)
	var frame_usec: int = 16667
	var frames: int = 600
	var start: int = Time.get_ticks_usec()
	for frame: int in frames:
		var now: int = frame * frame_usec + 1000000
		for i: int in EMITTER_COUNT:
			system.play_footstep(Vector3(float(i % 20), 0.0, float(i / 20)), float(i % 6), null, now)
		assert_lte(system.get_active_voice_count(now), system.get_voice_count())
	var per_frame_ms: float = float(Time.get_ticks_usec() - start) / 1000.0 / float(frames)
	var stats: Dictionary[String, int] = system.get_stats()
	gut.p(
		(
			"Horloge 60 i/s, 200 pas par image : %.3f ms par image, joués %d, abandonnés %d, volés %d"
			% [per_frame_ms, stats["steps_played"], stats["steps_dropped"], stats["voices_stolen"]]
		)
	)
	assert_gt(stats["steps_played"], 0)
	PerfCheck.under(self, per_frame_ms, BUDGET_MS_PER_FRAME, "coût par image sous le budget")
