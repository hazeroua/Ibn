class_name FaunaDragonflies
extends Node3D
## Libellules au-dessus des plans d'eau, uniquement le jour. Un seul MultiMeshInstance3D ; trajectoires et battement
## d'ailes sont calculés par le vertex shader (fauna_dragonflies.gdshader). Aucun travail par image : le nœud est
## simplement montré ou caché quand l'heure change (signal time_changed de DayNight).
##
## Pires cas : 16 plans d'eau au plus, 16 libellules par plan d'eau (256 instances de moins de 60 triangles) ;
## la trajectoire dépend du rayon de l'eau : elle reste bornée même après 100 h (le temps du shader est ramené par Godot).

const SHADER_PATH: String = "res://world/fauna/fauna_dragonflies.gdshader"
const CONTEXT: String = "fauna.json > dragonflies"
const SHADER_WATERS: int = 16

var _window: Vector3 = Vector3.ZERO
var _instance: MultiMeshInstance3D = null
var _count: int = 0


## Construit les libellules des plans d'eau assez grands. Renvoie false (avec erreur) si une donnée est invalide ;
## true avec zéro libellule si aucun plan d'eau n'est assez grand.
func build(settings: Dictionary, waters: Array[Dictionary], hour: float, aabb: AABB) -> bool:
	name = "FaunaDragonflies"
	var shader: Shader = load(SHADER_PATH) as Shader
	if shader == null:
		push_error("FaunaDragonflies : shader %s introuvable." % SHADER_PATH)
		return false
	_window = FaunaSchedule.parse(JsonData.get_dictionary(settings, "hours", CONTEXT), CONTEXT + " > hours")
	var min_radius: float = JsonData.get_float(settings, "min_water_radius_m", CONTEXT)
	var per_meter: float = JsonData.get_float(settings, "per_meter_of_radius", CONTEXT)
	var min_count: int = JsonData.get_int(settings, "min_per_water", CONTEXT)
	var max_count: int = JsonData.get_int(settings, "max_per_water", CONTEXT)
	var max_waters: int = JsonData.get_int(settings, "max_waters", CONTEXT)
	if max_waters < 1 or max_waters > SHADER_WATERS or min_count < 1 or max_count < min_count or max_count > 16:
		push_error("FaunaDragonflies : nombres de libellules ou de plans d'eau incohérents (%s)." % CONTEXT)
		return false
	var table := PackedVector4Array()
	table.resize(SHADER_WATERS)
	var counts := PackedInt32Array()
	for water: Dictionary in waters:
		var radius: float = water["radius"]
		if radius < min_radius or counts.size() >= max_waters:
			continue
		var center: Vector2 = water["center"]
		table[counts.size()] = Vector4(center.x, float(water["surface"]), center.y, radius)
		counts.append(clampi(int(round(radius * per_meter)), min_count, max_count))
	for count: int in counts:
		_count += count
	if _count == 0:
		return true
	var mesh: Mesh = FaunaMeshes.model_mesh(JsonData.get_string(settings, "model", CONTEXT))
	if mesh == null:
		return false
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter(&"waters", table)
	material.set_shader_parameter(&"speed", JsonData.get_float(settings, "speed", CONTEXT))
	material.set_shader_parameter(&"body_scale", JsonData.get_float(settings, "scale", CONTEXT))
	material.set_shader_parameter(&"flap_hz", JsonData.get_float(settings, "flap_hz", CONTEXT))
	material.set_shader_parameter(&"flap_amount", JsonData.get_float(settings, "flap_amount", CONTEXT))
	material.set_shader_parameter(&"hover_min_m", JsonData.get_float(settings, "hover_min_m", CONTEXT))
	material.set_shader_parameter(&"hover_max_m", JsonData.get_float(settings, "hover_max_m", CONTEXT))
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = FaunaMeshes.with_material(mesh, material)
	multimesh.instance_count = _count
	multimesh.custom_aabb = aabb
	multimesh.buffer = _instance_buffer(counts)
	_instance = MultiMeshInstance3D.new()
	_instance.name = "Libellules"
	_instance.multimesh = multimesh
	_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_instance)
	apply_hour(hour)
	return true


## Nombre de libellules.
func get_dragonfly_count() -> int:
	return _count


## Montre les libellules le jour, les cache la nuit. Appelé à chaque changement d'heure ; sans allocation.
func apply_hour(hour: float) -> void:
	if _instance != null:
		_instance.visible = FaunaSchedule.weight(hour, _window) > 0.0


static func _instance_buffer(counts: PackedInt32Array) -> PackedFloat32Array:
	var total: int = 0
	for count: int in counts:
		total += count
	var buffer := PackedFloat32Array()
	buffer.resize(total * 16)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var offset: int = 0
	for site: int in counts.size():
		for _fly: int in counts[site]:
			buffer[offset] = 1.0
			buffer[offset + 5] = 1.0
			buffer[offset + 10] = 1.0
			buffer[offset + 12] = rng.randf() * TAU
			buffer[offset + 13] = float(site)
			buffer[offset + 14] = rng.randf()
			buffer[offset + 15] = rng.randf()
			offset += 16
	return buffer
