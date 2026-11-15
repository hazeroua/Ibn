extends GutTest
## Réglages de la caméra à la troisième personne (res://data/player/camera.json).


func test_project_settings_load_and_are_consistent() -> void:
	var s: CameraSettings = CameraSettings.load_default()
	assert_eq(s.collision_mask, (1 << 0) | (1 << 3), "la caméra bute contre les couches 1 et 4 seulement")
	assert_lt(s.pitch_min, 0.0, "la caméra peut descendre sous le point visé")
	assert_gt(s.pitch_max, 0.0, "la caméra peut monter au-dessus du point visé")
	assert_true(s.zoom_min <= s.zoom_initial and s.zoom_initial <= s.zoom_max)
	assert_gt(s.zoom_min, s.probe_radius)
	assert_lt(s.contact_skin, s.probe_radius)
	assert_lt(s.follow_max_lag, s.teleport_distance)
	assert_lt(s.fade_end_distance, s.fade_start_distance)
	assert_lt(s.fov_speed_start, s.fov_speed_full)
	# Galop futur à 15 m/s : une image à 20 i/s déplace la cible de 0,75 m, jamais prise pour une téléportation.
	assert_gt(s.teleport_distance, 15.0 / 20.0)


func test_probe_encloses_near_plane() -> void:
	var s: CameraSettings = CameraSettings.load_default()
	var half_height: float = s.near * tan(deg_to_rad(s.fov_base_deg + s.fov_run_bonus_deg) * 0.5)
	var half_width: float = half_height * 16.0 / 9.0
	var reach: float = Vector3(half_width, half_height, s.near).length()
	assert_gt(s.probe_radius - s.contact_skin, reach, "l'image ne doit jamais voir à travers un mur")


func test_units_are_converted_once() -> void:
	var data: Dictionary = JsonData.load_dictionary(CameraSettings.DEFAULT_PATH)
	var s: CameraSettings = CameraSettings.from_dictionary(data)
	var orbit: Dictionary = data["orbit"]
	var stick: Dictionary = data["stick"]
	assert_almost_eq(s.pitch_max, deg_to_rad(float(orbit["pitch_max_deg"])), 0.00001)
	assert_almost_eq(s.stick_speed, deg_to_rad(float(stick["speed_deg_per_s"])), 0.00001)


func test_layers_are_read_from_data() -> void:
	var data: Dictionary = JsonData.load_dictionary(CameraSettings.DEFAULT_PATH)
	(data["collision"] as Dictionary)["layers"] = [1, 4, 32]
	var s: CameraSettings = CameraSettings.from_dictionary(data)
	assert_eq(s.collision_mask, (1 << 0) | (1 << 3) | (1 << 31))
