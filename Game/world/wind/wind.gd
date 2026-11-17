class_name WindSystem
extends Node
## Autoload « Wind » : direction, force et rafales du vent, et tout ce qui en dépend.
##
## - Variables : direction (plan x, z, vers où souffle le vent), strength (0 à 1), gust (0 à 1).
## - Uniformes globaux de shader (déclarés ici s'ils ne le sont pas déjà) : wind_direction (vec2),
##   wind_strength (float), wind_time (float, secondes, rebouclé à time_wrap pour garder la
##   précision des flottants 32 bits du GPU : un shader qui l'utilise voit un saut toutes les
##   time_wrap secondes, 68 minutes par défaut).
## - Sable qui vole (WindSand), brume de chaleur (WindHaze) et son (WindAudio).
##
## Pires cas : force maximale (sable à pleine émission), partie de 100 heures (le modèle ne dépend que
## du temps, calculé en 64 bits), galop en zone dense (le vent ne coûte que quelques sinus, trois
## écritures d'uniformes, le déplacement de l'anneau de brume et deux réglages de lecteurs par image).
## Aucune allocation par image : tous les nœuds sont créés au démarrage.
## Réglages : res://data/wind/wind.json. Si la force de base est modifiée (météo), le vent suit
## immédiatement ; la variation et les rafales se superposent à elle.

const UNIFORM_DIRECTION: StringName = &"wind_direction"
const UNIFORM_STRENGTH: StringName = &"wind_strength"
const UNIFORM_TIME: StringName = &"wind_time"

## Direction vers laquelle souffle le vent, vecteur unitaire dans le plan (x, z) du monde.
var direction: Vector2 = Vector2.RIGHT
## Force du vent de 0 (calme) à 1 (tempête), rafales comprises.
var strength: float = 0.0
## Intensité de la rafale en cours, de 0 à 1.
var gust: float = 0.0

var _settings: WindSettings = null
var _model: WindModel = null
var _base_strength: float = 0.0
var _model_time: float = 0.0
var _shader_time: float = 0.0
var _sand_timer: float = 0.0
var _haze: WindHaze = null
var _sand: WindSand = null
var _audio: WindAudio = null
var _root_3d: Node3D = null
## Sol sous la caméra (relu à chaque mise à jour du sable, un rayon) : le sable vole au ras du sol, pas autour de la caméra.
var _ground_ray: RayCast3D = null
var _sand_ground_y: float = NAN
var _quitting: bool = false


## Fournit les réglages avant l'entrée dans l'arbre (tests) ; sinon ils sont lus dans wind.json.
func configure(settings: WindSettings) -> void:
	_settings = settings
	_model = WindModel.new(settings)
	_base_strength = settings.strength_base


func _ready() -> void:
	if _settings == null:
		var loaded: WindSettings = WindSettings.load_default()
		if loaded == null:
			set_process(false)
			return
		configure(loaded)
	_declare_globals()
	_root_3d = Node3D.new()
	_root_3d.name = "Visuals"
	add_child(_root_3d)
	_haze = WindHaze.new()
	_root_3d.add_child(_haze)
	_haze.build(_settings)
	_sand = WindSand.new()
	_root_3d.add_child(_sand)
	_sand.build(_settings)
	_audio = WindAudio.new()
	add_child(_audio)
	var has_audio_output: bool = DisplayServer.get_name() != "headless"
	_audio.build(_settings, has_audio_output)
	if has_audio_output:
		get_tree().auto_accept_quit = false
	_update_model()
	_publish()
	_sand.apply_wind(direction, strength)


func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_CLOSE_REQUEST or _quitting:
		return
	_quitting = true
	_shutdown_audio_and_quit()


func _shutdown_audio_and_quit() -> void:
	if _audio != null:
		_audio.shutdown()
	var game_input: Node = get_node_or_null(^"/root/GameInput")
	if game_input != null and game_input.has_method(&"quit_safely"):
		await game_input.call(&"quit_safely")
	else:
		await get_tree().create_timer(0.1).timeout
		get_tree().quit()


func _process(delta: float) -> void:
	if _audio == null or not is_instance_valid(_audio):
		return
	_model_time += delta
	_shader_time = fmod(_shader_time + delta, _settings.time_wrap)
	_update_model()
	_publish()
	_follow_camera()
	_sand_timer += delta
	if _sand_timer >= _settings.sand_update_interval:
		_sand_timer = 0.0
		_sand.apply_wind(direction, strength)
		_probe_ground()


func _exit_tree() -> void:
	set_process(false)
	if _audio != null:
		_audio.shutdown()


## Force de base (0 à 1) autour de laquelle varient la force et les rafales ; sert à la météo.
func set_base_strength(value: float) -> void:
	_base_strength = clampf(value, 0.0, 1.0)
	if _model != null:
		_update_model()
		if is_inside_tree():
			_publish()
			_sand.apply_wind(direction, strength)


func get_base_strength() -> float:
	return _base_strength


## Temps (secondes) du modèle du vent, sans rebouclage.
func get_model_time() -> float:
	return _model_time


## Avance le modèle sans passer par _process (tests de charge et sauvegardes).
func set_model_time(seconds: float) -> void:
	_model_time = maxf(seconds, 0.0)
	if _model != null:
		_update_model()


## Sable, brume et son (accès pour les tests et le mixage).
func get_sand() -> WindSand:
	return _sand


func get_haze() -> WindHaze:
	return _haze


func get_audio() -> WindAudio:
	return _audio


func _update_model() -> void:
	_model.evaluate(_model_time, _base_strength)
	direction = _model.direction
	strength = _model.strength
	gust = _model.gust


func _publish() -> void:
	RenderingServer.global_shader_parameter_set(UNIFORM_DIRECTION, direction)
	RenderingServer.global_shader_parameter_set(UNIFORM_STRENGTH, strength)
	RenderingServer.global_shader_parameter_set(UNIFORM_TIME, _shader_time)
	_audio.apply_wind(strength, gust)


func _follow_camera() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return
	var origin: Vector3 = camera.global_position
	_root_3d.global_position = origin
	var ground: float = origin.y if is_nan(_sand_ground_y) else _sand_ground_y
	_sand.global_position = Vector3(origin.x, ground + _settings.sand_height_offset, origin.z)
	_haze.global_position = origin


## Hauteur du sol sous la caméra (couches sand.ground_mask, jusqu'à sand_ground_probe_m plus bas) ; inchangée si rien n'est touché.
func _probe_ground() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null or not camera.is_inside_tree():
		return
	# Rayon par nœud RayCast3D : aucune allocation (intersect_ray créerait un dictionnaire à chaque sonde).
	if _ground_ray == null:
		_ground_ray = RayCast3D.new()
		_ground_ray.name = "SondeSol"
		_ground_ray.enabled = false
		_ground_ray.top_level = true
		_ground_ray.collision_mask = _settings.sand_ground_mask
		_ground_ray.collide_with_areas = false
		_ground_ray.target_position = Vector3.DOWN * _settings.sand_ground_probe
		add_child(_ground_ray)
	if _ground_ray.get_world_3d() != camera.get_world_3d():
		return
	_ground_ray.global_position = camera.global_position
	_ground_ray.force_raycast_update()
	if _ground_ray.is_colliding():
		_sand_ground_y = _ground_ray.get_collision_point().y


static func _declare_globals() -> void:
	ShaderGlobals.declare(UNIFORM_DIRECTION, RenderingServer.GLOBAL_VAR_TYPE_VEC2, Vector2.RIGHT)
	ShaderGlobals.declare(UNIFORM_STRENGTH, RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0)
	ShaderGlobals.declare(UNIFORM_TIME, RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0)
