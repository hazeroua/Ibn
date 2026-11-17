class_name GameSettings
extends Node
## Paramètres utilisateur persistants. Les profils remplissent les valeurs détaillées ; toute
## modification manuelle passe le profil en « custom ». Les réglages de streaming sont injectés
## avant la configuration de WorldStreamer, les réglages de rendu sont appliqués immédiatement.

signal changed(values: Dictionary)

const USER_PATH: String = "user://parametres.json"
const PROFILE_IDS: Array[String] = ["low", "balanced", "high", "ultra", "custom"]
const DEFAULT_PROFILE: String = "balanced"

const PRESETS: Dictionary = {
	"low":
	{
		"render_scale": 0.55,
		"chunk_radius": 1,
		"stream_budget_ms": 1.0,
		"concurrent_builds": 1,
		"shadows": false,
		"shadow_distance_m": 60.0,
		"ssao": false,
		"max_fps": 60
	},
	"balanced":
	{
		"render_scale": 0.67,
		"chunk_radius": 2,
		"stream_budget_ms": 2.0,
		"concurrent_builds": 2,
		"shadows": true,
		"shadow_distance_m": 120.0,
		"ssao": false,
		"max_fps": 60
	},
	"high":
	{
		"render_scale": 0.85,
		"chunk_radius": 3,
		"stream_budget_ms": 3.0,
		"concurrent_builds": 4,
		"shadows": true,
		"shadow_distance_m": 220.0,
		"ssao": true,
		"max_fps": 90
	},
	"ultra":
	{
		"render_scale": 1.0,
		"chunk_radius": 4,
		"stream_budget_ms": 4.5,
		"concurrent_builds": 6,
		"shadows": true,
		"shadow_distance_m": 360.0,
		"ssao": true,
		"max_fps": 0
	},
}

const COMMON_DEFAULTS: Dictionary = {
	"profile": DEFAULT_PROFILE,
	"vsync": true,
	"fullscreen": false,
	"master_volume": 0.85,
}

var values: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	reset_defaults(false)
	_load_user_file()
	apply_runtime()
	get_tree().node_added.connect(_apply_node)


func reset_defaults(save_after: bool = true) -> void:
	values = default_values()
	if save_after:
		apply_runtime()
		save()
		changed.emit(snapshot())


func apply_profile(profile: String, save_after: bool = false) -> void:
	if not PRESETS.has(profile):
		return
	values.merge(PRESETS[profile] as Dictionary, true)
	values["profile"] = profile
	if save_after:
		apply_runtime()
		save()
		changed.emit(snapshot())


func apply_user_values(next: Dictionary, persist: bool = true) -> void:
	var clean := _validated(next)
	values.merge(clean, true)
	apply_runtime()
	if persist:
		save()
	changed.emit(snapshot())


func snapshot() -> Dictionary:
	return values.duplicate(true)


static func default_values() -> Dictionary:
	var result: Dictionary = COMMON_DEFAULTS.duplicate(true)
	result.merge(PRESETS[DEFAULT_PROFILE] as Dictionary, true)
	return result


func save() -> Error:
	var file := FileAccess.open(USER_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("GameSettings : impossible d'écrire %s." % USER_PATH)
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(values, "  "))
	return OK


func apply_runtime() -> void:
	Engine.max_fps = int(values.get("max_fps", 60))
	var root: Window = get_tree().root if get_tree() != null else null
	if root != null:
		root.scaling_3d_scale = float(values.get("render_scale", 0.67))
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(
			DisplayServer.VSYNC_ENABLED if bool(values.get("vsync", true)) else DisplayServer.VSYNC_DISABLED
		)
		DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_FULLSCREEN if bool(values.get("fullscreen", false)) else DisplayServer.WINDOW_MODE_WINDOWED
		)
	var master: int = AudioServer.get_bus_index(&"Master")
	if master >= 0:
		var volume: float = float(values.get("master_volume", 0.85))
		AudioServer.set_bus_volume_db(master, linear_to_db(maxf(volume, 0.0001)))
	if get_tree() != null and get_tree().current_scene != null:
		apply_to_scene(get_tree().current_scene)


func apply_to_scene(root: Node) -> void:
	_apply_node(root)
	for node: Node in root.find_children("*", "", true, false):
		_apply_node(node)


func apply_streaming_overrides(base: Dictionary) -> Dictionary:
	return streaming_config_for(base, values)


static func streaming_config_for(base: Dictionary, settings: Dictionary) -> Dictionary:
	var result := base.duplicate(true)
	var cell_size: float = float(result.get("cell_size_m", 250.0))
	var radius: int = clampi(int(settings.get("chunk_radius", 2)), 1, 6)
	result["load_radius_m"] = cell_size * (float(radius) + 0.45)
	result["unload_hysteresis_m"] = cell_size * 0.85
	result["frame_budget_ms"] = clampf(float(settings.get("stream_budget_ms", 2.0)), 0.5, 8.0)
	result["max_concurrent_builds"] = clampi(int(settings.get("concurrent_builds", 2)), 1, 8)
	return result


static func estimated_chunk_count(radius: int) -> int:
	var r: int = clampi(radius, 1, 6)
	return 1 + 2 * r * (r + 1)


func _apply_node(node: Node) -> void:
	if node is DirectionalLight3D:
		var light := node as DirectionalLight3D
		light.shadow_enabled = bool(values.get("shadows", true))
		light.directional_shadow_max_distance = float(values.get("shadow_distance_m", 120.0))
	elif node is WorldEnvironment:
		var world := node as WorldEnvironment
		if world.environment != null:
			world.environment.ssao_enabled = bool(values.get("ssao", false))


func _load_user_file() -> void:
	if not FileAccess.file_exists(USER_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(USER_PATH))
	if parsed is Dictionary:
		values.merge(_validated(parsed as Dictionary), true)


func _validated(raw: Dictionary) -> Dictionary:
	var profile: String = str(raw.get("profile", DEFAULT_PROFILE))
	if not PROFILE_IDS.has(profile):
		profile = DEFAULT_PROFILE
	return {
		"profile": profile,
		"render_scale": clampf(float(raw.get("render_scale", values.get("render_scale", 0.67))), 0.5, 1.0),
		"chunk_radius": clampi(int(raw.get("chunk_radius", values.get("chunk_radius", 2))), 1, 6),
		"stream_budget_ms": clampf(float(raw.get("stream_budget_ms", values.get("stream_budget_ms", 2.0))), 0.5, 8.0),
		"concurrent_builds": clampi(int(raw.get("concurrent_builds", values.get("concurrent_builds", 2))), 1, 8),
		"shadows": bool(raw.get("shadows", values.get("shadows", true))),
		"shadow_distance_m": clampf(float(raw.get("shadow_distance_m", values.get("shadow_distance_m", 120.0))), 40.0, 400.0),
		"ssao": bool(raw.get("ssao", values.get("ssao", false))),
		"vsync": bool(raw.get("vsync", values.get("vsync", true))),
		"max_fps": _valid_fps(int(raw.get("max_fps", values.get("max_fps", 60)))),
		"fullscreen": bool(raw.get("fullscreen", values.get("fullscreen", false))),
		"master_volume": clampf(float(raw.get("master_volume", values.get("master_volume", 0.85))), 0.0, 1.0),
	}


static func _valid_fps(value: int) -> int:
	return value if [0, 30, 60, 90, 120, 144].has(value) else 60
