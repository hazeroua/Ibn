class_name WaterWading
extends Node
## Le joueur et l'eau peu profonde : ralentissement progressif avec la profondeur et éclaboussure à chaque pas.
##
## Par tick physique : une lecture de la grille des plans d'eau (rejet immédiat hors de l'eau) puis, dans l'eau, un
## calcul de hauteur ; aucune allocation. Une seule instance de particules, réutilisée et replacée sous le pied à
## chaque pas dans l'eau. La profondeur maximale franchissable est tenue par la limite invisible (WaterBarrier).
## Réglages : section « wading » de res://data/player/locomotion.json.

var _player: PlayerCharacter = null
var _field: DesertHeightfield = null
var _max_depth: float = 1.0
var _enter_depth: float = 0.0
var _slowest: float = 1.0
var _smoothing: float = 1.0
var _min_splash_speed: float = 0.0
var _splash: GPUParticles3D = null


## Branche le système au joueur ; à appeler avant l'entrée dans l'arbre.
func setup(player: PlayerCharacter, field: DesertHeightfield) -> void:
	_player = player
	_field = field
	var settings: LocomotionSettings = player.get_settings()
	_max_depth = settings.wading_max_depth
	_enter_depth = settings.wading_enter_depth
	_slowest = settings.wading_speed_multiplier
	_smoothing = settings.wading_smoothing
	_splash = _build_splash(settings.splash)
	_min_splash_speed = JsonData.get_float(settings.splash, "min_speed", "locomotion.json > wading > splash")
	add_child(_splash)
	@warning_ignore("return_value_discarded")
	player.footstep.connect(_on_footstep)


func _physics_process(delta: float) -> void:
	var position: Vector3 = _player.global_position
	var depth: float = _field.water_depth_at(position.x, position.z)
	var target: float = 1.0
	if depth > _enter_depth:
		target = lerpf(1.0, _slowest, clampf(depth / _max_depth, 0.0, 1.0))
	if is_equal_approx(_player.speed_multiplier, target):
		_player.speed_multiplier = target
		return
	_player.speed_multiplier = lerpf(_player.speed_multiplier, target, 1.0 - exp(-_smoothing * delta))


func _on_footstep(_foot: int, world_position: Vector3, speed: float, _collider: Object) -> void:
	if speed < _min_splash_speed or _field.water_depth_at(world_position.x, world_position.z) <= _enter_depth:
		return
	_splash.global_position = world_position
	_splash.restart()


func _build_splash(config: Dictionary) -> GPUParticles3D:
	var context: String = "locomotion.json > wading > splash"
	var material := ParticleProcessMaterial.new()
	material.direction = Vector3.UP
	material.spread = JsonData.get_float(config, "spread_degrees", context)
	material.initial_velocity_min = JsonData.get_float(config, "initial_speed_min", context)
	material.initial_velocity_max = JsonData.get_float(config, "initial_speed_max", context)
	material.gravity = Vector3(0.0, -JsonData.get_float(config, "gravity", context), 0.0)
	material.scale_min = JsonData.get_float(config, "scale_min", context)
	material.scale_max = JsonData.get_float(config, "scale_max", context)
	var quad := QuadMesh.new()
	var size: float = JsonData.get_float(config, "particle_size_m", context)
	quad.size = Vector2(size, size)
	var draw := StandardMaterial3D.new()
	draw.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	draw.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw.albedo_color = JsonData.get_color(config, "color", context)
	quad.material = draw
	var particles := GPUParticles3D.new()
	particles.name = "Splash"
	particles.amount = JsonData.get_int(config, "amount", context)
	particles.lifetime = JsonData.get_float(config, "lifetime_s", context)
	particles.explosiveness = JsonData.get_float(config, "explosiveness", context)
	particles.one_shot = true
	particles.emitting = false
	particles.local_coords = false
	particles.process_material = material
	particles.draw_pass_1 = quad
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.visibility_aabb = AABB(Vector3(-3.0, -1.0, -3.0), Vector3(6.0, 5.0, 6.0))
	return particles
