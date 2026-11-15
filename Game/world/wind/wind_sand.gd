class_name WindSand
extends GPUParticles3D
## Sable soulevé par le vent : particules GPU en nombre fixe, autour de la caméra.
##
## Pire cas : force maximale, toutes les particules émises (max_particles, plafonné à 8192 par les
## réglages). Le nombre de particules et le maillage ne changent jamais ; seuls la direction, la
## vitesse et la proportion émise (amount_ratio) suivent le vent, à intervalle fixe.

var _settings: WindSettings = null
var _material: ParticleProcessMaterial = null


## Construit l'émetteur (une fois).
func build(settings: WindSettings) -> void:
	_settings = settings
	name = "WindSand"
	amount = settings.sand_max_particles
	lifetime = settings.sand_lifetime
	preprocess = settings.sand_lifetime
	explosiveness = 0.0
	randomness = 1.0
	local_coords = false
	fixed_fps = 0
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var travel: float = settings.sand_speed_max * settings.sand_lifetime
	var half: Vector3 = settings.sand_box_size * 0.5 + Vector3(travel, travel * 0.5, travel)
	visibility_aabb = AABB(-half, half * 2.0)
	_material = ParticleProcessMaterial.new()
	_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_material.emission_box_extents = settings.sand_box_size * 0.5
	_material.spread = rad_to_deg(settings.sand_spread)
	_material.gravity = Vector3(0.0, settings.sand_gravity_y, 0.0)
	_material.initial_velocity_min = settings.sand_speed_min
	_material.initial_velocity_max = settings.sand_speed_min
	process_material = _material
	var quad := QuadMesh.new()
	quad.size = Vector2(settings.sand_particle_size, settings.sand_particle_size)
	var draw_material := StandardMaterial3D.new()
	draw_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	draw_material.albedo_color = settings.sand_color
	draw_material.disable_fog = false
	quad.material = draw_material
	draw_pass_1 = quad
	emitting = false


## Adapte le sable au vent (direction dans le plan x, z ; force de 0 à 1). Aucune allocation.
func apply_wind(direction: Vector2, strength: float) -> void:
	var s: WindSettings = _settings
	var active: bool = strength > s.sand_min_strength
	if active:
		var ratio: float = clampf((strength - s.sand_min_strength) / (1.0 - s.sand_min_strength), 0.0, 1.0)
		amount_ratio = maxf(ratio, 1.0 / float(s.sand_max_particles))
		var speed: float = lerpf(s.sand_speed_min, s.sand_speed_max, strength)
		_material.direction = Vector3(direction.x, 0.08, direction.y)
		_material.initial_velocity_min = speed * 0.6
		_material.initial_velocity_max = speed
	if emitting != active:
		emitting = active
