class_name HorseTraces
extends Node3D
## Pool borné de traces, sans création pendant la partie. Une trace ne s'affiche que sur le sable.

var _pool: Array[MeshInstance3D] = []
var _expires: PackedFloat32Array = PackedFloat32Array()
var _next: int = 0
var _width: float = 0.18
var _length: float = 0.38
var _lifetime: float = 45.0
var _sand_surface: StringName = &"sable"
var _clock: float = 0.0


func configure(settings: Dictionary) -> void:
	var data: Dictionary = settings.get("traces", {}) as Dictionary
	var pool_size: int = int(data.get("pool_size", 128))
	_width = float(data.get("width_m", 0.18))
	_length = float(data.get("length_m", 0.38))
	_lifetime = float(data.get("lifetime_s", 45.0))
	_sand_surface = StringName(data.get("sand_surface", "sable"))
	_expires.resize(pool_size)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.28, 0.20, 0.12, 0.65)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var mesh := QuadMesh.new()
	mesh.size = Vector2(_width, _length)
	mesh.material = material
	for index: int in pool_size:
		var trace := MeshInstance3D.new()
		trace.name = "Trace%03d" % index
		trace.mesh = mesh
		trace.visible = false
		add_child(trace)
		_pool.append(trace)


func place(world_position: Vector3, yaw: float, surface: StringName) -> bool:
	if surface != _sand_surface or _pool.is_empty():
		return false
	var trace: MeshInstance3D = _pool[_next]
	_next = (_next + 1) % _pool.size()
	if trace.is_inside_tree():
		trace.global_position = world_position + Vector3.UP * 0.012
	else:
		trace.position = world_position + Vector3.UP * 0.012
	trace.rotation = Vector3(0.0, yaw, 0.0)
	trace.visible = true
	_expires[_pool.find(trace)] = _clock + _lifetime
	return true


func active_count() -> int:
	var count: int = 0
	for trace: MeshInstance3D in _pool:
		if trace.visible:
			count += 1
	return count


func _process(delta: float) -> void:
	_clock += delta
	for index: int in _pool.size():
		if _pool[index].visible and _expires[index] <= _clock:
			_pool[index].visible = false
