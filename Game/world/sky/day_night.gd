class_name DayNightSystem
extends Node
## Autoload « DayNight » : cycle jour/nuit sur 24 h (aube, heure dorée, plein jour, crépuscule, nuit
## étoilée avec lune).
##
## À chaque mise à jour, les courbes de res://data/sky/day_night.json pilotent : le soleil (lumière
## directionnelle avec ombres, éteinte la nuit), la lune (lumière sans ombre), le ciel (shader
## procédural : dégradé, halo et disque du soleil, lune à phase, étoiles), le brouillard, la lumière
## ambiante et l'exposition du rendu (AgX).
##
## Pires cas : mises à jour à chaque image au temps accéléré maximal sur la puce Intel Arc intégrée ;
## partie de 100 heures (l'heure est toujours ramenée dans [0, 24[, aucune dérive) ; saut d'heure
## arbitraire. Les courbes sont échantillonnées dans une table précalculée (DayNightCurves) ; la mise à
## jour n'a lieu que lorsque l'heure a avancé d'au moins « update_step_hours » (le rendu du ciel et des
## reflets n'est donc pas recalculé à chaque image), ne crée aucun objet et se borne à une
## interpolation, quelques transformations et une vingtaine de réglages. Le processus n'est actif que
## si time_scale n'est pas nul.
##
## Utilisation : ajouter le nœud renvoyé par build_environment() à la scène du monde ; sans lui, l'heure
## avance quand même et time_changed est émis.

## Émis à chaque mise à jour effective (heure en [0, 24[) et à chaque set_time().
signal time_changed(hours: float)

const SETTINGS_PATH: String = "res://data/sky/day_night.json"
const SKY_SHADER_PATH: String = "res://world/sky/day_night_sky.gdshader"
const CONTEXT: String = "day_night.json"
const HOURS_PER_DAY: float = DayNightCurves.HOURS_PER_DAY

const P_SKY_TOP: StringName = &"sky_top"
const P_SKY_HORIZON: StringName = &"sky_horizon"
const P_GROUND_HORIZON: StringName = &"ground_horizon"
const P_GROUND_BOTTOM: StringName = &"ground_bottom"
const P_SUN_COLOR: StringName = &"sun_color"
const P_SUN_DIRECTION: StringName = &"sun_direction"
const P_MOON_DIRECTION: StringName = &"moon_direction"
const P_SUN_GLOW: StringName = &"sun_glow"
const P_SUN_VISIBILITY: StringName = &"sun_visibility"
const P_MOON_VISIBILITY: StringName = &"moon_visibility"
const P_STAR_ALPHA: StringName = &"star_alpha"
## Énergie lunaire (courbe) à partir de laquelle le disque de la lune est pleinement visible.
const MOON_FULL_VISIBILITY_ENERGY: float = 0.12
## Plage d'élévation (sinus) sur laquelle une lumière apparaît / disparaît à l'horizon.
const HORIZON_FADE: float = 0.1

## Heure du jour en [0, 24[. L'affecter revient à appeler set_time().
var time_of_day: float:
	get = get_time,
	set = set_time
## Heures de jeu écoulées par seconde réelle (0 : temps arrêté ; négatif : temps inversé).
var time_scale: float = 0.0:
	set = set_time_scale

var _curves: DayNightCurves = null
var _samples: PackedFloat32Array = PackedFloat32Array()
var _time: float = 0.0
var _ready_ok: bool = false
var _settings: Dictionary = {}
var _applied_time: float = -1.0e9
var _update_step: float = 0.0

# Géométrie du soleil.
var _sunrise_hour: float = 6.0
var _sunset_hour: float = 18.0
var _tilt_radians: float = 0.0
var _azimuth_radians: float = 0.0

# Réglages des lumières.
var _shadow_min_energy: float = 0.0
var _moon_min_energy: float = 0.0
var _moon_energy_scale: float = 1.0
var _moon_phase: float = 0.5

# Nœuds construits par build_environment().
var _environment: Environment = null
var _sky_material: ShaderMaterial = null
var _sun: DirectionalLight3D = null
var _moon: DirectionalLight3D = null
var _rig: Node3D = null


func _ready() -> void:
	var settings: Dictionary = JsonData.load_dictionary(SETTINGS_PATH)
	_curves = DayNightCurves.from_settings(settings, CONTEXT)
	_samples.resize(DayNightCurves.CHANNEL_COUNT)
	if not _curves.is_valid():
		return
	var time: Dictionary = JsonData.get_dictionary(settings, "time", CONTEXT)
	_update_step = maxf(JsonData.get_float(time, "update_step_hours", CONTEXT + " > time"), 0.0)
	var sun: Dictionary = JsonData.get_dictionary(settings, "sun", CONTEXT)
	var sun_context: String = CONTEXT + " > sun"
	_sunrise_hour = JsonData.get_float(sun, "sunrise_hour", sun_context)
	_sunset_hour = JsonData.get_float(sun, "sunset_hour", sun_context)
	_tilt_radians = deg_to_rad(90.0 - JsonData.get_float(sun, "max_elevation_deg", sun_context))
	_azimuth_radians = deg_to_rad(JsonData.get_float(sun, "azimuth_deg", sun_context))
	_shadow_min_energy = JsonData.get_float(sun, "shadow_min_energy", sun_context)
	var moon: Dictionary = JsonData.get_dictionary(settings, "moon", CONTEXT)
	var moon_context: String = CONTEXT + " > moon"
	_moon_min_energy = JsonData.get_float(moon, "min_energy", moon_context)
	_moon_energy_scale = JsonData.get_float(moon, "light_energy_scale", moon_context)
	_moon_phase = JsonData.get_float(moon, "phase", moon_context)
	_settings = settings
	_ready_ok = true
	time_scale = JsonData.get_float(time, "time_scale", CONTEXT + " > time")
	set_time(JsonData.get_float(time, "start_hour", CONTEXT + " > time"))


func _process(delta: float) -> void:
	_time_advance(delta * time_scale)


## Fixe l'heure (en heures, ramenée dans [0, 24[) et met tout à jour immédiatement.
func set_time(hours: float) -> void:
	_time = fposmod(hours, HOURS_PER_DAY)
	if not _ready_ok:
		return
	_apply()
	time_changed.emit(_time)


func get_time() -> float:
	return _time


func set_time_scale(scale: float) -> void:
	time_scale = scale
	set_process(not is_zero_approx(scale))


## Courbes échantillonnables (lecture seule), pour les tests et les systèmes qui suivent le cycle.
func get_curves() -> DayNightCurves:
	return _curves


## Direction du soleil vers le ciel (vecteur unitaire) à l'heure donnée ; y < 0 : sous l'horizon.
func get_sun_direction(hours: float) -> Vector3:
	var angle: float = _sun_angle(fposmod(hours, HOURS_PER_DAY))
	var direction := Vector3(cos(angle), sin(angle), 0.0)
	direction = direction.rotated(Vector3.RIGHT, _tilt_radians)
	return direction.rotated(Vector3.UP, _azimuth_radians)


## Construit le ciel : un nœud contenant WorldEnvironment, soleil et lune, piloté ensuite par DayNight.
## Un nouvel appel remplace le précédent (l'appelant libère l'ancien nœud avec sa scène).
func build_environment() -> Node:
	var root := Node3D.new()
	root.name = "DayNightRig"
	var sky_material := ShaderMaterial.new()
	sky_material.shader = load(SKY_SHADER_PATH)
	var settings: Dictionary = _settings
	var sky_config: Dictionary = JsonData.get_dictionary(settings, "sky", CONTEXT)
	var sky_context: String = CONTEXT + " > sky"
	var sun_config: Dictionary = JsonData.get_dictionary(settings, "sun", CONTEXT)
	var moon_config: Dictionary = JsonData.get_dictionary(settings, "moon", CONTEXT)
	sky_material.set_shader_parameter(&"horizon_curve", JsonData.get_float(sky_config, "horizon_curve", sky_context))
	sky_material.set_shader_parameter(&"ground_curve", JsonData.get_float(sky_config, "ground_curve", sky_context))
	sky_material.set_shader_parameter(&"glow_power", JsonData.get_float(sky_config, "glow_power", sky_context))
	sky_material.set_shader_parameter(&"star_density", JsonData.get_float(sky_config, "star_density", sky_context))
	sky_material.set_shader_parameter(&"star_scale", JsonData.get_float(sky_config, "star_scale", sky_context))
	sky_material.set_shader_parameter(&"moon_phase", _moon_phase)
	sky_material.set_shader_parameter(&"moon_color", JsonData.get_color(moon_config, "color", CONTEXT + " > moon"))
	sky_material.set_shader_parameter(
		&"sun_cos_size", cos(deg_to_rad(JsonData.get_float(sun_config, "angular_size_deg", CONTEXT + " > sun")) * 0.5)
	)
	sky_material.set_shader_parameter(
		&"moon_cos_size", cos(deg_to_rad(JsonData.get_float(moon_config, "angular_size_deg", CONTEXT + " > moon")) * 0.5)
	)
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	match JsonData.get_int(sky_config, "radiance_size", sky_context):
		32:
			sky.radiance_size = Sky.RADIANCE_SIZE_32
		128:
			sky.radiance_size = Sky.RADIANCE_SIZE_128
		_:
			sky.radiance_size = Sky.RADIANCE_SIZE_64
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	environment.fog_enabled = true
	environment.fog_sky_affect = JsonData.get_float(sky_config, "fog_sky_affect", sky_context)
	environment.fog_sun_scatter = JsonData.get_float(sky_config, "fog_sun_scatter", sky_context)
	var world_environment := WorldEnvironment.new()
	world_environment.name = "Environment"
	world_environment.environment = environment
	root.add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = JsonData.get_float(sun_config, "shadow_max_distance", CONTEXT + " > sun")
	root.add_child(sun)
	var moon := DirectionalLight3D.new()
	moon.name = "Moon"
	moon.shadow_enabled = false
	moon.light_color = JsonData.get_color(moon_config, "light_color", CONTEXT + " > moon")
	root.add_child(moon)

	_environment = environment
	_sky_material = sky_material
	_sun = sun
	_moon = moon
	_rig = root
	root.tree_exited.connect(_on_rig_exited.bind(root))
	if _ready_ok:
		_apply()
	return root


func _on_rig_exited(root: Node3D) -> void:
	if root != _rig:
		return
	_environment = null
	_sky_material = null
	_sun = null
	_moon = null
	_rig = null


func _time_advance(hours_delta: float) -> void:
	_time = fposmod(_time + hours_delta, HOURS_PER_DAY)
	var gap: float = absf(_time - _applied_time)
	gap = minf(gap, HOURS_PER_DAY - gap)
	if gap >= _update_step:
		_apply()
		time_changed.emit(_time)


## Angle du soleil sur son cercle : 0 au lever, PI au coucher, puis de PI à 2 PI pendant la nuit.
func _sun_angle(hours: float) -> float:
	var day_length: float = _sunset_hour - _sunrise_hour
	if hours >= _sunrise_hour and hours <= _sunset_hour:
		return (hours - _sunrise_hour) / day_length * PI
	var night_length: float = HOURS_PER_DAY - day_length
	var since_sunset: float = hours - _sunset_hour
	if since_sunset < 0.0:
		since_sunset += HOURS_PER_DAY
	return PI + since_sunset / night_length * PI


func _apply() -> void:
	_applied_time = _time
	_curves.sample(_time, _samples)
	var sun_up: Vector3 = get_sun_direction(_time)
	var moon_up: Vector3 = -sun_up
	if _rig == null:
		return
	var s: PackedFloat32Array = _samples
	var sun_fade: float = clampf((sun_up.y + 0.02) / HORIZON_FADE, 0.0, 1.0)
	var moon_fade: float = clampf(moon_up.y / HORIZON_FADE, 0.0, 1.0)
	var sun_energy: float = s[DayNightCurves.CH_SUN_ENERGY] * sun_fade
	var moon_energy: float = s[DayNightCurves.CH_MOON_ENERGY]
	var sun_color := Color(s[DayNightCurves.CH_SUN_COLOR], s[DayNightCurves.CH_SUN_COLOR + 1], s[DayNightCurves.CH_SUN_COLOR + 2])

	_sun.visible = sun_energy > _shadow_min_energy
	_sun.light_energy = sun_energy
	_sun.light_color = sun_color
	_sun.transform = Transform3D(_light_basis(sun_up), Vector3.ZERO)
	var moon_light: float = moon_energy * _moon_energy_scale * moon_fade
	_moon.visible = moon_light > _moon_min_energy
	_moon.light_energy = moon_light
	_moon.transform = Transform3D(_light_basis(moon_up), Vector3.ZERO)

	_environment.ambient_light_color = Color(
		s[DayNightCurves.CH_AMBIENT_COLOR], s[DayNightCurves.CH_AMBIENT_COLOR + 1], s[DayNightCurves.CH_AMBIENT_COLOR + 2]
	)
	_environment.ambient_light_energy = s[DayNightCurves.CH_AMBIENT_ENERGY]
	_environment.fog_light_color = Color(
		s[DayNightCurves.CH_FOG_COLOR], s[DayNightCurves.CH_FOG_COLOR + 1], s[DayNightCurves.CH_FOG_COLOR + 2]
	)
	_environment.fog_density = s[DayNightCurves.CH_FOG_DENSITY]
	_environment.tonemap_exposure = s[DayNightCurves.CH_EXPOSURE]

	var m: ShaderMaterial = _sky_material
	m.set_shader_parameter(
		P_SKY_TOP, Color(s[DayNightCurves.CH_SKY_TOP], s[DayNightCurves.CH_SKY_TOP + 1], s[DayNightCurves.CH_SKY_TOP + 2])
	)
	m.set_shader_parameter(
		P_SKY_HORIZON, Color(s[DayNightCurves.CH_SKY_HORIZON], s[DayNightCurves.CH_SKY_HORIZON + 1], s[DayNightCurves.CH_SKY_HORIZON + 2])
	)
	m.set_shader_parameter(
		P_GROUND_HORIZON,
		Color(s[DayNightCurves.CH_GROUND_HORIZON], s[DayNightCurves.CH_GROUND_HORIZON + 1], s[DayNightCurves.CH_GROUND_HORIZON + 2])
	)
	m.set_shader_parameter(
		P_GROUND_BOTTOM,
		Color(s[DayNightCurves.CH_GROUND_BOTTOM], s[DayNightCurves.CH_GROUND_BOTTOM + 1], s[DayNightCurves.CH_GROUND_BOTTOM + 2])
	)
	m.set_shader_parameter(P_SUN_COLOR, sun_color)
	m.set_shader_parameter(P_SUN_DIRECTION, sun_up)
	m.set_shader_parameter(P_MOON_DIRECTION, moon_up)
	m.set_shader_parameter(P_SUN_GLOW, s[DayNightCurves.CH_SUN_GLOW])
	m.set_shader_parameter(P_SUN_VISIBILITY, sun_fade)
	m.set_shader_parameter(P_MOON_VISIBILITY, moon_energy / MOON_FULL_VISIBILITY_ENERGY)
	m.set_shader_parameter(P_STAR_ALPHA, s[DayNightCurves.CH_STAR_ALPHA])


## Base orientée pour qu'une lumière directionnelle éclaire depuis « to_light » (vers le ciel).
static func _light_basis(to_light: Vector3) -> Basis:
	var up: Vector3 = Vector3.UP
	if absf(to_light.y) > 0.9:
		up = Vector3.FORWARD
	return Basis.looking_at(-to_light, up)
