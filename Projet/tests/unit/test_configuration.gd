extends GutTest
## Vérifie les fichiers de configuration livrés et leur analyse.


func test_shipped_graphics_target_1080p_fsr2() -> void:
	var settings: GraphicsSettings = GraphicsSettings.from_dictionary(JsonData.load_dictionary("res://data/config/graphics.json"))
	assert_true(settings.errors.is_empty(), str(settings.errors))
	assert_eq(settings.window_size, Vector2i(1920, 1080))
	assert_eq(settings.scaling_mode, Viewport.SCALING_3D_MODE_FSR2)
	assert_almost_eq(settings.scaling_scale, 0.67, 0.0001)


func test_project_settings_match_the_target_platform() -> void:
	assert_eq(ProjectSettings.get_setting("rendering/renderer/rendering_method"), "forward_plus")
	assert_eq(ProjectSettings.get_setting("rendering/rendering_device/driver.windows"), "vulkan")
	assert_eq(ProjectSettings.get_setting("physics/3d/physics_engine"), "Jolt Physics")
	assert_eq(ProjectSettings.get_setting("rendering/scaling_3d/mode"), Viewport.SCALING_3D_MODE_FSR2)


func test_invalid_graphics_values_are_rejected() -> void:
	var data: Dictionary = {
		"window": {"width": 100, "height": 100, "mode": "borderless"},
		"scaling_3d": {"mode": "dlss", "scale": 2.0},
		"vsync": "sometimes",
		"max_fps": -5,
	}
	assert_eq(GraphicsSettings.from_dictionary(data).errors.size(), 6)


func test_shipped_scene_catalog_is_valid() -> void:
	var catalog: SceneCatalog = SceneCatalog.from_dictionary(JsonData.load_dictionary("res://data/config/boot.json"))
	assert_true(catalog.errors.is_empty(), str(catalog.errors))
	assert_true(catalog.has_scene(catalog.default_scene_id))


func test_shipped_input_bindings_register_every_action() -> void:
	var bindings: InputBindings = InputBindings.from_dictionary(JsonData.load_dictionary("res://data/config/input.json"))
	assert_true(bindings.errors.is_empty(), str(bindings.errors))
	bindings.apply()
	for action: StringName in [&"move_forward", &"move_back", &"move_left", &"move_right", &"sprint", &"toggle_mouse_capture"]:
		assert_true(InputMap.has_action(action), String(action))
	var forward_key: InputEventKey = InputEventKey.new()
	forward_key.physical_keycode = KEY_W
	assert_true(InputMap.event_is_action(forward_key, &"move_forward"))
	var stick_left: InputEventJoypadMotion = InputEventJoypadMotion.new()
	stick_left.axis = JOY_AXIS_LEFT_X
	stick_left.axis_value = -1.0
	assert_true(InputMap.event_is_action(stick_left, &"move_left"))
	bindings.remove()


func test_invalid_input_events_are_rejected() -> void:
	var data: Dictionary = {
		"actions":
		{
			"broken":
			{
				"deadzone": 0.2,
				"events":
				[
					{"type": "key", "key": "NotAKey"},
					{"type": "mouse_button", "button": "thumb"},
					{"type": "joypad_axis", "axis": 1, "direction": 0.5},
					{"type": "gesture"},
				],
			},
		},
	}
	assert_eq(InputBindings.from_dictionary(data).errors.size(), 4)


func test_json_parse_errors_are_reported() -> void:
	assert_false(JsonData.parse_text("{ broken", "test").error.is_empty())
	assert_false(JsonData.parse_text("[1, 2]", "test").error.is_empty())
	assert_eq(JsonData.parse_text('{"a": 1}', "test").data, {"a": 1.0})


func test_shipped_resource_manifest_is_valid_and_covers_the_sahara() -> void:
	var manifest: ResourceManifest = ResourceManifest.load_shipped()
	assert_true(manifest.errors.is_empty(), str(manifest.errors))
	var scene: Dictionary = JsonData.load_dictionary("res://data/sahara/sahara.json")["scene"]
	for texture: Dictionary in scene["textures"]:
		assert_true(manifest.has_texture(texture["resource"]), texture["resource"])
	assert_eq(manifest.local_path("sable", "albedo"), "res://ressources/telechargees/sable/sandy_gravel_02_diff_2k.jpg")


func test_resource_lock_holds_sha256_fingerprints() -> void:
	var lock: Dictionary = JsonData.load_dictionary(ResourceManifest.LOCK_PATH)
	assert_true(lock.has("files"))
	var manifest: ResourceManifest = ResourceManifest.load_shipped()
	var known_urls: Dictionary = {}
	for key: String in manifest.texture_keys():
		for map_name: String in ResourceManifest.TEXTURE_MAPS:
			known_urls[manifest.url(key, map_name)] = true
	for url: String in lock["files"]:
		assert_true(known_urls.has(url), "empreinte orpheline : " + url)
		var fingerprint: String = lock["files"][url]
		assert_eq(fingerprint.length(), 64, url)
		assert_true(fingerprint.is_valid_hex_number(), url)


func test_rejected_licence_and_insecure_urls() -> void:
	var data: Dictionary = {
		"textures":
		{
			"x":
			{
				"source": "Ailleurs",
				"page": "http://exemple",
				"licence": "Tous droits réservés",
				"files": {"albedo": "http://a", "normal": "https://b", "roughness": "https://c", "height": "https://d"},
			},
		},
	}
	assert_eq(ResourceManifest.from_dictionary(data).errors.size(), 2)


func test_catalog_declares_the_sahara_builder() -> void:
	var catalog: SceneCatalog = SceneCatalog.from_dictionary(JsonData.load_dictionary("res://data/config/boot.json"))
	assert_eq(catalog.default_scene_id, "sahara")
	assert_eq(catalog.builder_path("sahara"), "res://world/sahara/sahara_builder.gd")
	assert_eq(catalog.builder_path("terrain_test"), "")
