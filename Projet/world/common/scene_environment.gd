class_name SceneEnvironment
extends RefCounted
## Ciel uni, lumière ambiante et soleil d'une scène, lus dans sa section « environment ».
## Les scènes extérieures à identité visuelle (Sahara) utilisent Atmosphere à la place.


static func build(parent: Node3D, data: Dictionary, errors: PackedStringArray, context: String) -> DirectionalLight3D:
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = JsonData.read_color(data, "sky_color", errors, context)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = JsonData.read_color(data, "ambient_color", errors, context)
	environment.ambient_light_energy = JsonData.read_number(data, "ambient_energy", errors, context)
	var world_environment: WorldEnvironment = WorldEnvironment.new()
	world_environment.environment = environment
	parent.add_child(world_environment)

	var sun_context: String = context + " › sun"
	var sun_data: Dictionary = JsonData.read_dictionary(data, "sun", errors, context)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = JsonData.read_vector3(sun_data, "rotation_degrees", errors, sun_context)
	sun.light_energy = JsonData.read_number(sun_data, "energy", errors, sun_context)
	sun.shadow_enabled = true
	sun.shadow_bias = JsonData.read_number(sun_data, "shadow_bias", errors, sun_context)
	sun.shadow_normal_bias = JsonData.read_number(sun_data, "shadow_normal_bias", errors, sun_context)
	parent.add_child(sun)
	return sun


## Aide discrète en bas à gauche (caméra libre uniquement).
static func add_help(parent: Node, text: String) -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = "Help"
	var label: Label = Label.new()
	label.text = text
	label.add_theme_color_override(&"font_color", Color(1.0, 1.0, 1.0, 0.85))
	label.add_theme_color_override(&"font_shadow_color", Color(0.0, 0.0, 0.0, 0.6))
	label.add_theme_constant_override(&"shadow_offset_x", 1)
	label.add_theme_constant_override(&"shadow_offset_y", 1)
	label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 24)
	label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	layer.add_child(label)
	parent.add_child(layer)
