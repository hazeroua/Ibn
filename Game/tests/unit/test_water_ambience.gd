extends GutTest
## Ambiance des plans d'eau : enregistrements en boucle, portée, transitions sans saut, masque du vent, immersion.
## Pire cas : tous les plans d'eau du désert à portée, auditeur qui traverse le monde au galop pendant 10 minutes.

const DESERT_PATH: String = "res://data/desert/desert.json"
const MAX_UPDATES_MS: float = 200.0


func _bodies() -> Array[Dictionary]:
	return FaunaWater.load_bodies(JsonData.load_dictionary(DESERT_PATH), null)


func _build() -> WaterAmbience:
	var ambience := WaterAmbience.new()
	add_child_autofree(ambience)
	assert_true(ambience.build(_bodies()))
	return ambience


func test_ambience_loops_are_looped_recordings() -> void:
	var settings: Dictionary = JsonData.load_dictionary(WaterAmbience.SETTINGS_PATH)
	var ids := PackedStringArray()
	for spec: Variant in (settings["kinds"] as Dictionary).values():
		ids.append(str((spec as Dictionary)["sound"]))
	var streams: Dictionary[String, AudioStream] = SoundLibrary.load_streams(JsonData.load_dictionary(SoundLibrary.MANIFEST_PATH), ids)
	assert_eq(streams.size(), ids.size())
	for id: String in streams:
		var stream := streams[id] as AudioStreamOggVorbis
		assert_not_null(stream, id)
		assert_true(stream.loop, "%s doit boucler" % id)


func test_silent_out_of_range_and_playing_near_shore() -> void:
	var ambience: WaterAmbience = _build()
	assert_eq(ambience.get_body_count(), 3, "oasis, lac et guelta sonores ; le chott reste muet")
	var oasis: Dictionary = FaunaWater.oasis_anchor(_bodies())
	var center: Vector2 = oasis["center"]
	var radius: float = oasis["radius"]
	var player: AudioStreamPlayer3D = ambience.get_player(str(oasis["id"]))
	ambience.update_listener(Vector3(center.x + radius + 5000.0, 0.0, center.y), 0.0, 0.1)
	assert_false(player.playing)
	ambience.update_listener(Vector3(center.x + radius + 20.0, 0.0, center.y), 0.0, 0.1)
	assert_true(player.playing)
	# Source posée sur le rivage, du côté de l'auditeur.
	assert_almost_eq(player.position.x, center.x + radius, 0.01)
	# Fondu d'entrée : jamais de saut de plus de volume_rate × durée.
	var previous: float = player.volume_db
	for index: int in 50:
		ambience.update_listener(Vector3(center.x + radius + 20.0, 0.0, center.y), 0.0, 0.1)
		assert_lte(absf(player.volume_db - previous), 1.8 + 0.001)
		previous = player.volume_db
	var calm: float = player.volume_db
	for index: int in 50:
		ambience.update_listener(Vector3(center.x + radius + 20.0, 0.0, center.y), 1.0, 0.1)
	assert_lt(player.volume_db, calm - 5.0, "le vent fort masque l'eau")
	for index: int in 50:
		ambience.update_listener(Vector3(center.x, 0.0, center.y), 0.0, 0.1)
	assert_gt(player.volume_db, calm, "dans l'eau, le son se rapproche")
	ambience.update_listener(Vector3(center.x + radius + 5000.0, 0.0, center.y), 0.0, 0.1)
	assert_false(player.playing)


func test_ten_minute_gallop_across_all_waters() -> void:
	var ambience: WaterAmbience = _build()
	var updates: int = 6000
	var started: int = Time.get_ticks_usec()
	for index: int in updates:
		var t: float = float(index) / float(updates)
		ambience.update_listener(Vector3(lerpf(-2000.0, 2000.0, t), 0.0, sin(t * 40.0) * 600.0), fmod(t * 7.0, 1.0), 0.1)
	var elapsed_ms: float = float(Time.get_ticks_usec() - started) / 1000.0
	gut.p("Pire cas eau : %d mises à jour (10 min), %d plans d'eau, %.3f ms" % [updates, ambience.get_body_count(), elapsed_ms])
	assert_lt(elapsed_ms, MAX_UPDATES_MS)
