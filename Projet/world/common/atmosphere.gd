class_name Atmosphere
extends Node3D
## Identité visuelle d'une scène extérieure : lumière, ciel, brume sèche, vent, poussière
## et chaleur, réglés par « moments » de la journée lus dans les données.
## Le ciel, le soleil et les nuages viennent de Sky3D (Tokisan Games, MIT), piloté ici à
## heure fixe. La brume sèche est le brouillard de profondeur de Godot avec perspective
## aérienne, calculé dans le rendu des objets eux-mêmes : il évite la passe plein écran
## supplémentaire (et la copie de la profondeur) qu'exigerait le brouillard de Sky3D.
## Poussière : trois couches de particules GPU qui suivent la caméra. Chaleur : déformation de l'image au lointain près de l'horizon.
## Rien n'est alloué par image : _process ne fait que déplacer trois émetteurs.

const LOG_CATEGORY: String = "atmosphère"
const HEAT_HAZE_SHADER: Shader = preload("res://world/common/heat_haze.gdshader")
const DUST_SHADER: Shader = preload("res://world/common/dust_particle.gdshader")
const HEAT_HAZE_RENDER_PRIORITY: int = -128
const DUST_COLOR_RAMP_POINTS: PackedFloat32Array = [0.0, 0.2, 0.8, 1.0]


## Réglages d'un moment de la journée.
class Moment:
	extends RefCounted
	var id: String = ""
	var label: String = ""
	var hour: float = 12.0
	var sun_energy: float = 1.0
	var tonemap_exposure: float = 1.0
	var ambient_energy: float = 1.0
	var sky_contribution: float = 1.0
	var sun_light_color: Color = Color.WHITE
	var sun_horizon_light_color: Color = Color.WHITE
	var sun_disk_color: Color = Color.WHITE
	var atm_day_tint: Color = Color.WHITE
	var atm_horizon_light_tint: Color = Color.WHITE
	var atm_darkness: float = 0.5
	var cumulus_coverage: float = 0.5
	var cirrus_coverage: float = 0.5
	var cloud_intensity: float = 0.6
	var sun_disk_intensity: float = 30.0
	var fog_color: Color = Color.WHITE
	var fog_max_opacity: float = 0.5
	var fog_start: float = 0.0
	var fog_end: float = 1000.0
	var fog_curve: float = 1.0
	var fog_sun_scatter: float = 0.0
	var fog_aerial_perspective: float = 0.0
	var saturation: float = 1.0
	var contrast: float = 1.0
	var brightness: float = 1.0
	var dust_density: float = 0.5
	var dust_color: Color = Color.WHITE
	var heat_haze_strength: float = 0.0

	static func from_dictionary(moment_id: String, data: Dictionary, errors: PackedStringArray) -> Moment:
		var context: String = "atmosphere.json › moments › " + moment_id
		var moment: Moment = Moment.new()
		moment.id = moment_id
		moment.label = JsonData.read_string(data, "label", errors, context)
		moment.hour = JsonData.read_number(data, "hour", errors, context)
		if moment.hour < 0.0 or moment.hour >= 24.0:
			errors.append(context + " : l'heure doit être entre 0 et 24.")
		moment.sun_energy = JsonData.read_number(data, "sun_energy", errors, context)
		moment.tonemap_exposure = JsonData.read_number(data, "tonemap_exposure", errors, context)
		moment.ambient_energy = JsonData.read_number(data, "ambient_energy", errors, context)
		moment.sky_contribution = JsonData.read_number(data, "sky_contribution", errors, context)
		moment.sun_light_color = JsonData.read_color(data, "sun_light_color", errors, context)
		moment.sun_horizon_light_color = JsonData.read_color(data, "sun_horizon_light_color", errors, context)
		moment.sun_disk_color = JsonData.read_color(data, "sun_disk_color", errors, context)
		moment.atm_day_tint = JsonData.read_color(data, "atm_day_tint", errors, context)
		moment.atm_horizon_light_tint = JsonData.read_color(data, "atm_horizon_light_tint", errors, context)
		moment.atm_darkness = JsonData.read_number(data, "atm_darkness", errors, context)
		moment.cumulus_coverage = JsonData.read_number(data, "cumulus_coverage", errors, context)
		moment.cirrus_coverage = JsonData.read_number(data, "cirrus_coverage", errors, context)
		moment.cloud_intensity = JsonData.read_number(data, "cloud_intensity", errors, context)
		moment.sun_disk_intensity = JsonData.read_number(data, "sun_disk_intensity", errors, context)
		moment.fog_color = JsonData.read_color(data, "fog_color", errors, context)
		moment.fog_max_opacity = JsonData.read_number(data, "fog_max_opacity", errors, context)
		moment.fog_start = JsonData.read_number(data, "fog_start_meters", errors, context)
		moment.fog_end = JsonData.read_number(data, "fog_end_meters", errors, context)
		moment.fog_curve = JsonData.read_number(data, "fog_curve", errors, context)
		moment.fog_sun_scatter = JsonData.read_number(data, "fog_sun_scatter", errors, context)
		moment.fog_aerial_perspective = JsonData.read_number(data, "fog_aerial_perspective", errors, context)
		moment.saturation = JsonData.read_number(data, "saturation", errors, context)
		moment.contrast = JsonData.read_number(data, "contrast", errors, context)
		moment.brightness = JsonData.read_number(data, "brightness", errors, context)
		moment.dust_density = JsonData.read_number(data, "dust_density", errors, context)
		moment.dust_color = JsonData.read_color(data, "dust_color", errors, context)
		moment.heat_haze_strength = JsonData.read_number(data, "heat_haze_strength", errors, context)
		for fraction: float in [
			moment.cumulus_coverage,
			moment.cirrus_coverage,
			moment.dust_density,
			moment.atm_darkness,
			moment.fog_max_opacity,
			moment.fog_aerial_perspective,
		]:
			if fraction < 0.0 or fraction > 1.0:
				errors.append(context + " : couvertures, densités, opacité et perspective aérienne doivent être entre 0 et 1.")
				break
		if moment.fog_end <= moment.fog_start:
			errors.append(context + " : fog_end_meters doit dépasser fog_start_meters.")
		return moment


## Couche de poussière : réglages fixes (le nombre maximal de particules est le pire cas).
class DustLayer:
	extends RefCounted
	var name: String = ""
	var texture_key: String = ""
	var amount: int = 0
	var box: Vector3 = Vector3.ONE
	var size_min: float = 1.0
	var size_max: float = 1.0
	var lifetime: float = 5.0
	var speed_factor: float = 1.0
	var alpha: float = 0.2
	var height_offset: float = 0.0
	var fade_near: float = 1.0
	var fade_far: float = 100.0

	static func from_dictionary(layer_name: String, data: Dictionary, errors: PackedStringArray) -> DustLayer:
		var context: String = "atmosphere.json › dust › layers › " + layer_name
		var layer: DustLayer = DustLayer.new()
		layer.name = layer_name
		layer.texture_key = JsonData.read_string(data, "texture", errors, context)
		layer.amount = int(JsonData.read_number(data, "amount", errors, context))
		layer.box = JsonData.read_vector3(data, "box_meters", errors, context)
		var size: Vector2 = Vector2.ONE
		var size_data: Variant = data.get("size_meters")
		if typeof(size_data) == TYPE_ARRAY and (size_data as Array).size() == 2:
			size = Vector2(float(size_data[0]), float(size_data[1]))
		else:
			errors.append(context + " : « size_meters » doit être une paire [min, max].")
		layer.size_min = size.x
		layer.size_max = size.y
		layer.lifetime = JsonData.read_number(data, "lifetime_seconds", errors, context)
		layer.speed_factor = JsonData.read_number(data, "speed_factor", errors, context)
		layer.alpha = JsonData.read_number(data, "alpha", errors, context)
		layer.height_offset = JsonData.read_number(data, "height_offset_meters", errors, context)
		layer.fade_near = JsonData.read_number(data, "fade_near_meters", errors, context)
		layer.fade_far = JsonData.read_number(data, "fade_far_meters", errors, context)
		if layer.amount < 1 or layer.amount > 4096:
			errors.append(context + " : amount doit être entre 1 et 4096.")
		if layer.fade_near <= 0.0 or layer.fade_far <= layer.fade_near:
			errors.append(context + " : fade_far_meters doit dépasser fade_near_meters, lui-même positif.")
		if layer.lifetime <= 0.0 or layer.size_min <= 0.0 or layer.size_max < layer.size_min:
			errors.append(context + " : durée de vie et tailles doivent être positives et croissantes.")
		return layer


var sky3d: Sky3D
## Ordre des moments (touche de changement, captures, mesure).
var moment_order: PackedStringArray = PackedStringArray()
var default_moment_id: String = ""
var current_moment_id: String = ""

var _moments: Dictionary = {}
var _dust_layers: Array[DustLayer] = []
var _dust_emitters: Array[GPUParticles3D] = []
var _dust_processes: Array[ParticleProcessMaterial] = []
var _haze: MeshInstance3D
var _haze_material: ShaderMaterial
var _camera: Camera3D
var _wind_speed: float = 0.0
var _wind_direction: Vector3 = Vector3.FORWARD


## Lit les données, puis construit ciel, poussière et chaleur. Le nœud doit être dans l'arbre.
## `particle_texture_dir` contient les textures de particules (<clé>.png).
func configure(data: Dictionary, camera: Camera3D, particle_texture_dir: String, errors: PackedStringArray) -> void:
	_camera = camera
	var context: String = "atmosphere.json"
	var location: Dictionary = JsonData.read_dictionary(data, "location", errors, context)
	var moments: Dictionary = JsonData.read_dictionary(data, "moments", errors, context)
	for moment_id: String in moments:
		var moment_data: Variant = moments[moment_id]
		if typeof(moment_data) != TYPE_DICTIONARY:
			errors.append("%s › moments › %s : objet attendu." % [context, moment_id])
			continue
		_moments[moment_id] = Moment.from_dictionary(moment_id, moment_data, errors)
	var order: Variant = data.get("moment_order")
	if typeof(order) != TYPE_ARRAY or (order as Array).size() != _moments.size():
		errors.append(context + " : « moment_order » doit lister chaque moment une fois.")
	else:
		for moment_id: Variant in order:
			if not _moments.has(String(moment_id)) or moment_order.has(String(moment_id)):
				errors.append("%s : moment « %s » inconnu ou répété dans moment_order." % [context, moment_id])
			moment_order.append(String(moment_id))
	default_moment_id = JsonData.read_string(data, "default_moment", errors, context)
	if not _moments.has(default_moment_id):
		errors.append("%s : moment par défaut « %s » inconnu." % [context, default_moment_id])
	var wind: Dictionary = JsonData.read_dictionary(data, "wind", errors, context)
	_wind_speed = JsonData.read_number(wind, "speed_meters_per_second", errors, context + " › wind")
	var wind_angle: float = deg_to_rad(JsonData.read_number(wind, "direction_degrees", errors, context + " › wind"))
	_wind_direction = Vector3(cos(wind_angle), 0.0, sin(wind_angle))
	var dust: Dictionary = JsonData.read_dictionary(data, "dust", errors, context)
	var layers: Dictionary = JsonData.read_dictionary(dust, "layers", errors, context + " › dust")
	for layer_name: String in layers:
		_dust_layers.append(DustLayer.from_dictionary(layer_name, layers[layer_name], errors))
	var heat: Dictionary = JsonData.read_dictionary(data, "heat_haze", errors, context)
	var shadow: Dictionary = JsonData.read_dictionary(data, "sun_shadow", errors, context)
	if not errors.is_empty():
		return

	_create_sky(location, shadow, errors)
	_create_dust(particle_texture_dir, errors)
	_create_heat_haze(heat, errors)
	if errors.is_empty():
		apply_moment(default_moment_id)


func has_moment(moment_id: String) -> bool:
	return _moments.has(moment_id)


func moment_label(moment_id: String) -> String:
	return (_moments[moment_id] as Moment).label


## Applique un moment : heure, soleil, ciel, nuages, brume, étalonnage, poussière, chaleur.
func apply_moment(moment_id: String) -> void:
	var moment: Moment = _moments[moment_id]
	current_moment_id = moment_id
	sky3d.current_time = moment.hour
	sky3d.sun_energy = moment.sun_energy
	sky3d.tonemap_exposure = moment.tonemap_exposure
	sky3d.ambient_energy = moment.ambient_energy
	sky3d.sky_contribution = moment.sky_contribution
	sky3d.cloud_intensity = moment.cloud_intensity
	var dome: SkyDome = sky3d.sky
	dome.sun_light_color = moment.sun_light_color
	dome.sun_horizon_light_color = moment.sun_horizon_light_color
	dome.sun_disk_color = moment.sun_disk_color
	dome.atm_day_tint = moment.atm_day_tint
	dome.atm_horizon_light_tint = moment.atm_horizon_light_tint
	dome.atm_darkness = moment.atm_darkness
	dome.cumulus_coverage = moment.cumulus_coverage
	dome.cirrus_coverage = moment.cirrus_coverage
	dome.sun_disk_intensity = moment.sun_disk_intensity
	# Sous l'horizon, le ciel prend la couleur de la brume : pas de bande sombre entre le sol
	# lointain (noyé dans la brume) et le ciel, vu d'en haut.
	dome.ground_color = moment.fog_color
	var environment: Environment = sky3d.environment
	environment.fog_light_color = moment.fog_color
	environment.fog_density = moment.fog_max_opacity
	environment.fog_depth_begin = moment.fog_start
	environment.fog_depth_end = moment.fog_end
	environment.fog_depth_curve = moment.fog_curve
	environment.fog_sun_scatter = moment.fog_sun_scatter
	environment.fog_aerial_perspective = moment.fog_aerial_perspective
	environment.adjustment_saturation = moment.saturation
	environment.adjustment_contrast = moment.contrast
	environment.adjustment_brightness = moment.brightness
	for index: int in _dust_emitters.size():
		var layer: DustLayer = _dust_layers[index]
		_dust_emitters[index].amount_ratio = moment.dust_density
		_dust_emitters[index].emitting = moment.dust_density > 0.0
		_dust_processes[index].color = Color(moment.dust_color, layer.alpha)
	_haze_material.set_shader_parameter(&"strength", moment.heat_haze_strength)
	_haze.visible = moment.heat_haze_strength > 0.0
	GameLog.info(LOG_CATEGORY, "Moment « %s » (%.2f h)." % [moment.label, moment.hour])


## Passe au moment suivant dans moment_order et renvoie son identifiant.
func cycle_moment() -> String:
	var next_index: int = (moment_order.find(current_moment_id) + 1) % moment_order.size()
	apply_moment(moment_order[next_index])
	return current_moment_id


func _process(_delta: float) -> void:
	var anchor: Vector3 = _camera.global_position
	for index: int in _dust_emitters.size():
		_dust_emitters[index].global_position = anchor + Vector3.UP * _dust_layers[index].height_offset


func _create_sky(location: Dictionary, shadow: Dictionary, errors: PackedStringArray) -> void:
	var context: String = "atmosphere.json › location"
	sky3d = Sky3D.new()
	sky3d.name = "Sky3D"
	add_child(sky3d)
	# Heure figée : le temps ne s'écoule pas, chaque moment est un réglage fixe.
	sky3d.game_time_enabled = false
	sky3d.editor_time_enabled = false
	sky3d.tod.latitude = deg_to_rad(JsonData.read_number(location, "latitude_degrees", errors, context))
	sky3d.tod.longitude = deg_to_rad(JsonData.read_number(location, "longitude_degrees", errors, context))
	sky3d.tod.utc = JsonData.read_number(location, "utc_offset_hours", errors, context)
	sky3d.tod.year = int(JsonData.read_number(location, "year", errors, context))
	sky3d.tod.month = int(JsonData.read_number(location, "month", errors, context))
	sky3d.tod.day = int(JsonData.read_number(location, "day", errors, context))
	sky3d.fog_enabled = false
	# Brume sèche : brouillard de profondeur de Godot, sans effet sur le ciel lui-même.
	var environment: Environment = sky3d.environment
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_sky_affect = 0.0
	# Pas de nuit dans le premier jalon : étoiles et Voie lactée éteintes.
	sky3d.sky.starmap_color = Color(0.0, 0.0, 0.0, 0.0)
	sky3d.sky.star_field_color = Color(0.0, 0.0, 0.0, 0.0)
	sky3d.wind_speed = _wind_speed
	sky3d.wind_direction = atan2(_wind_direction.z, _wind_direction.x)
	# Pas de nuit dans le premier jalon : la lune n'éclaire pas et ne projette pas d'ombre.
	sky3d.moon_energy = 0.0
	sky3d.moon.shadow_enabled = false
	sky3d.moon.visible = false
	sky3d.sun.shadow_enabled = true
	sky3d.sun.directional_shadow_max_distance = JsonData.read_number(shadow, "max_distance_meters", errors, "atmosphere.json › sun_shadow")
	sky3d.sun.directional_shadow_blend_splits = true
	sky3d.environment.adjustment_enabled = true


func _create_dust(particle_texture_dir: String, errors: PackedStringArray) -> void:
	for layer: DustLayer in _dust_layers:
		var texture_path: String = particle_texture_dir.path_join(layer.texture_key + ".png")
		var texture: Texture2D = load(texture_path) as Texture2D
		if texture == null:
			errors.append("Texture de poussière absente : %s (lancez valider.bat)." % texture_path)
			continue
		# Fondu selon la distance à la caméra (dust_particle.gdshader) : rien de collé à l'écran, rien au loin.
		var material: ShaderMaterial = ShaderMaterial.new()
		material.shader = DUST_SHADER
		material.set_shader_parameter(&"albedo_texture", texture)
		material.set_shader_parameter(&"fade_near", layer.fade_near)
		material.set_shader_parameter(&"fade_far", layer.fade_far)
		var quad: QuadMesh = QuadMesh.new()
		quad.material = material

		var process: ParticleProcessMaterial = ParticleProcessMaterial.new()
		process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		process.emission_box_extents = layer.box * 0.5
		process.direction = _wind_direction
		process.spread = 12.0
		process.initial_velocity_min = _wind_speed * layer.speed_factor * 0.7
		process.initial_velocity_max = _wind_speed * layer.speed_factor * 1.3
		process.gravity = Vector3.ZERO
		process.scale_min = layer.size_min
		process.scale_max = layer.size_max
		process.angle_min = -180.0
		process.angle_max = 180.0
		process.angular_velocity_min = -8.0
		process.angular_velocity_max = 8.0
		process.color_ramp = _make_fade_ramp()

		var emitter: GPUParticles3D = GPUParticles3D.new()
		emitter.name = "Poussiere_" + layer.name
		emitter.amount = layer.amount
		emitter.lifetime = layer.lifetime
		emitter.preprocess = layer.lifetime
		emitter.local_coords = false
		emitter.process_material = process
		emitter.draw_pass_1 = quad
		emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var reach: Vector3 = layer.box * 0.5 + Vector3.ONE * (layer.size_max + _wind_speed * layer.speed_factor * layer.lifetime)
		emitter.visibility_aabb = AABB(-reach, reach * 2.0)
		add_child(emitter)
		_dust_emitters.append(emitter)
		_dust_processes.append(process)


## Rampe d'opacité : apparition et disparition progressives de chaque particule.
static func _make_fade_ramp() -> GradientTexture1D:
	var gradient: Gradient = Gradient.new()
	gradient.offsets = DUST_COLOR_RAMP_POINTS
	gradient.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var ramp: GradientTexture1D = GradientTexture1D.new()
	ramp.gradient = gradient
	return ramp


func _create_heat_haze(data: Dictionary, errors: PackedStringArray) -> void:
	var context: String = "atmosphere.json › heat_haze"
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = JsonData.read_number(data, "noise_frequency", errors, context)
	var noise_texture: NoiseTexture2D = NoiseTexture2D.new()
	var size: int = int(JsonData.read_number(data, "noise_size_pixels", errors, context))
	noise_texture.width = size
	noise_texture.height = size
	noise_texture.seamless = true
	noise_texture.as_normal_map = true
	noise_texture.generate_mipmaps = true
	noise_texture.noise = noise
	_haze_material = ShaderMaterial.new()
	_haze_material.shader = HEAT_HAZE_SHADER
	_haze_material.render_priority = HEAT_HAZE_RENDER_PRIORITY
	_haze_material.set_shader_parameter(&"noise_texture", noise_texture)
	_haze_material.set_shader_parameter(&"start_distance", JsonData.read_number(data, "start_distance_meters", errors, context))
	_haze_material.set_shader_parameter(&"full_distance", JsonData.read_number(data, "full_distance_meters", errors, context))
	_haze_material.set_shader_parameter(&"horizon_band", JsonData.read_number(data, "horizon_band", errors, context))
	_haze_material.set_shader_parameter(&"speed", JsonData.read_number(data, "speed", errors, context))
	_haze_material.set_shader_parameter(&"noise_scale", JsonData.read_number(data, "noise_scale", errors, context))
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	quad.material = _haze_material
	_haze = MeshInstance3D.new()
	_haze.name = "Chaleur"
	_haze.mesh = quad
	_haze.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Plein écran : jamais éliminé par le frustum, quelle que soit la caméra.
	_haze.custom_aabb = AABB(Vector3(-1.0e6, -1.0e6, -1.0e6), Vector3(2.0e6, 2.0e6, 2.0e6))
	_camera.add_child(_haze)
