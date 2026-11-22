class_name HorseTraces
extends MultiMeshInstance3D
## Traces de sabots sur le sable : un seul MultiMesh (un appel de dessin pour toutes les traces), anneau borné de
## pool_size empreintes, aucune création pendant la partie. Une trace ne se pose que sur le sable.
##
## Les traces vivent dans le repère du monde (top_level) : elles restent où Barq les a laissées. Elles sont
## opaques (passe opaque, aucun tri) et s'effacent par tramage à la fin de leur vie (horse_trace.gdshader,
## âge calculé dans le shader à partir de l'heure de pose, INSTANCE_CUSTOM.x). Toutes les traces ont la même
## durée de vie : les plus anciennes expirent les premières, l'expiration ne parcourt que les traces expirées.

const CONTEXT: String = "horse.json > traces"
const SHADER_PATH: String = "res://horse/horse_trace.gdshader"
## Trace cachée : échelle nulle (aucun fragment), loin sous le sol.
const HIDDEN := Transform3D(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3(0.0, -10000.0, 0.0))

var _births: PackedFloat32Array = PackedFloat32Array()
var _next: int = 0
var _oldest: int = 0
var _active: int = 0
var _width: float = 0.0
var _length: float = 0.0
var _lift: float = 0.0
var _lifetime: float = 0.0
var _sand_surface: StringName = &""
var _clock: float = 0.0
var _material: ShaderMaterial


func configure(settings: Dictionary) -> void:
	var data: Dictionary = PlayerJsonData.get_dictionary(settings, "traces", "horse.json")
	var pool_size: int = PlayerJsonData.get_int(data, "pool_size", CONTEXT)
	_width = PlayerJsonData.get_float(data, "width_m", CONTEXT)
	_length = PlayerJsonData.get_float(data, "length_m", CONTEXT)
	_lift = PlayerJsonData.get_float(data, "lift_m", CONTEXT)
	_lifetime = PlayerJsonData.get_float(data, "lifetime_s", CONTEXT)
	_sand_surface = StringName(PlayerJsonData.get_string(data, "sand_surface", CONTEXT))
	if pool_size < 1 or _width <= 0.0 or _length <= 0.0 or _lifetime <= 0.0:
		push_error("HorseTraces : réglages incohérents (%s)." % CONTEXT)
		return
	top_level = true
	transform = Transform3D.IDENTITY
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_material = ShaderMaterial.new()
	_material.shader = load(SHADER_PATH) as Shader
	_material.set_shader_parameter(&"imprint_color", PlayerJsonData.get_color(data, "color", CONTEXT))
	_material.set_shader_parameter(&"fade_s", PlayerJsonData.get_float(data, "fade_s", CONTEXT))
	_material.set_shader_parameter(&"lifetime_s", _lifetime)
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(_width, _length)
	mesh.material = _material
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.use_custom_data = true
	instances.mesh = mesh
	instances.instance_count = pool_size
	for index: int in pool_size:
		instances.set_instance_transform(index, HIDDEN)
		instances.set_instance_custom_data(index, Color(-1.0e6, 0.0, 0.0, 0.0))
	# Les traces couvrent tout le terrain parcouru : boîte englobante fixe, jamais recalculée.
	custom_aabb = AABB(Vector3(-1.0e5, -1.0e4, -1.0e5), Vector3(2.0e5, 2.0e4, 2.0e5))
	multimesh = instances
	_births.resize(pool_size)
	_next = 0
	_oldest = 0
	_active = 0


## Pose une empreinte (sable seulement), orientée selon le cap de Barq et couchée sur le sol (normal).
func place(world_position: Vector3, yaw: float, surface: StringName, normal: Vector3 = Vector3.UP) -> bool:
	if surface != _sand_surface or multimesh == null:
		return false
	var count: int = multimesh.instance_count
	var up: Vector3 = normal.normalized() if normal.length_squared() > 0.0001 else Vector3.UP
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right: Vector3 = up.cross(-forward)
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT
	right = right.normalized()
	var back: Vector3 = right.cross(up).normalized()
	multimesh.set_instance_transform(_next, Transform3D(Basis(right, up, back), world_position + up * _lift))
	multimesh.set_instance_custom_data(_next, Color(_clock, 0.0, 0.0, 0.0))
	_births[_next] = _clock
	_next = (_next + 1) % count
	if _active == count:
		_oldest = _next
	else:
		_active += 1
	return true


func active_count() -> int:
	return _active


func _process(delta: float) -> void:
	_clock += delta
	if _material != null:
		_material.set_shader_parameter(&"now_s", _clock)
	if multimesh == null:
		return
	var count: int = multimesh.instance_count
	while _active > 0 and _births[_oldest] + _lifetime <= _clock:
		multimesh.set_instance_transform(_oldest, HIDDEN)
		_oldest = (_oldest + 1) % count
		_active -= 1
