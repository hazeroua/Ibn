class_name GraphicsSettings
extends RefCounted
## Configuration graphique lue dans data/config/graphics.json et appliquée à la fenêtre.

const SCALING_MODES: Dictionary = {
	"bilinear": Viewport.SCALING_3D_MODE_BILINEAR,
	"fsr1": Viewport.SCALING_3D_MODE_FSR,
	"fsr2": Viewport.SCALING_3D_MODE_FSR2,
}
const VSYNC_MODES: Dictionary = {
	"disabled": DisplayServer.VSYNC_DISABLED,
	"enabled": DisplayServer.VSYNC_ENABLED,
	"adaptive": DisplayServer.VSYNC_ADAPTIVE,
}
const VSYNC_LABELS: Dictionary = {
	DisplayServer.VSYNC_DISABLED: "coupée",
	DisplayServer.VSYNC_ENABLED: "activée",
	DisplayServer.VSYNC_ADAPTIVE: "adaptative",
}
const MIN_WINDOW_SIZE: Vector2i = Vector2i(640, 360)
const MIN_SCALING_SCALE: float = 0.5
const MAX_SCALING_SCALE: float = 1.0

var window_size: Vector2i = Vector2i(1920, 1080)
var fullscreen: bool = false
var scaling_mode: Viewport.Scaling3DMode = Viewport.SCALING_3D_MODE_FSR2
var scaling_scale: float = 0.67
var vsync_mode: DisplayServer.VSyncMode = DisplayServer.VSYNC_ENABLED
var max_fps: int = 0
var errors: PackedStringArray = PackedStringArray()


static func from_dictionary(data: Dictionary) -> GraphicsSettings:
	var settings: GraphicsSettings = GraphicsSettings.new()
	var context: String = "graphics.json"
	var window: Dictionary = JsonData.read_dictionary(data, "window", settings.errors, context)
	if not window.is_empty():
		var width: int = int(JsonData.read_number(window, "width", settings.errors, context + " › window"))
		var height: int = int(JsonData.read_number(window, "height", settings.errors, context + " › window"))
		if width < MIN_WINDOW_SIZE.x or height < MIN_WINDOW_SIZE.y:
			settings.errors.append("%s : fenêtre trop petite (%d × %d)." % [context, width, height])
		else:
			settings.window_size = Vector2i(width, height)
		var mode: String = JsonData.read_string(window, "mode", settings.errors, context + " › window")
		if mode == "fullscreen":
			settings.fullscreen = true
		elif mode != "windowed":
			settings.errors.append("%s : mode de fenêtre inconnu « %s »." % [context, mode])

	var scaling: Dictionary = JsonData.read_dictionary(data, "scaling_3d", settings.errors, context)
	if not scaling.is_empty():
		var mode_name: String = JsonData.read_string(scaling, "mode", settings.errors, context + " › scaling_3d")
		if SCALING_MODES.has(mode_name):
			settings.scaling_mode = SCALING_MODES[mode_name]
		else:
			settings.errors.append("%s : mise à l'échelle inconnue « %s »." % [context, mode_name])
		var scale: float = JsonData.read_number(scaling, "scale", settings.errors, context + " › scaling_3d")
		if scale < MIN_SCALING_SCALE or scale > MAX_SCALING_SCALE:
			settings.errors.append("%s : échelle de rendu hors de [0,5 ; 1]." % context)
		else:
			settings.scaling_scale = scale

	var vsync_name: String = JsonData.read_string(data, "vsync", settings.errors, context)
	if VSYNC_MODES.has(vsync_name):
		settings.vsync_mode = VSYNC_MODES[vsync_name]
	else:
		settings.errors.append("%s : synchronisation verticale inconnue « %s »." % [context, vsync_name])

	var fps_limit: int = int(JsonData.read_number(data, "max_fps", settings.errors, context))
	if fps_limit < 0:
		settings.errors.append("%s : max_fps doit être positif ou nul." % context)
	else:
		settings.max_fps = fps_limit
	return settings


## Applique la configuration à la fenêtre principale.
func apply(window: Window) -> void:
	window.scaling_3d_mode = scaling_mode
	window.scaling_3d_scale = scaling_scale
	if fullscreen:
		window.mode = Window.MODE_FULLSCREEN
	else:
		window.mode = Window.MODE_WINDOWED
		window.size = window_size
		window.move_to_center()
	DisplayServer.window_set_vsync_mode(vsync_mode)
	Engine.max_fps = max_fps


func describe() -> String:
	var mode_name: String = SCALING_MODES.find_key(scaling_mode)
	return (
		"%d × %d %s, %s à %d %%, synchronisation %s, limite %s i/s"
		% [
			window_size.x,
			window_size.y,
			"plein écran" if fullscreen else "fenêtré",
			mode_name.to_upper(),
			roundi(scaling_scale * 100.0),
			VSYNC_LABELS[vsync_mode],
			"aucune" if max_fps == 0 else str(max_fps),
		]
	)
