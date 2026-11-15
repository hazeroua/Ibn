class_name OasisWater
extends RefCounted
## Eau de l'oasis : un disque maillé unique et un shader léger (pas de lecture de profondeur).
## Tous les réglages viennent de res://data/assets/oasis_water.json.

const SETTINGS_PATH: String = "res://data/assets/desert_props.json"

static var _settings: Dictionary = {}
static var _height: float = 0.0
## Un maillage par rayon d'oasis (les oasis viennent des données : leur nombre est borné).
static var _meshes: Dictionary[float, ArrayMesh] = {}
static var _shared_material: ShaderMaterial = null


static func _load_settings() -> Dictionary:
	if _settings.is_empty():
		var props: Dictionary = JsonData.load_dictionary(SETTINGS_PATH)
		var water: Dictionary = JsonData.get_dictionary(props, "water", SETTINGS_PATH)
		var path: String = JsonData.get_string(water, "settings", SETTINGS_PATH)
		_settings = JsonData.load_dictionary(path)
		_height = JsonData.get_float(_settings, "surface_height_m", SETTINGS_PATH)
	return _settings


static func _color(data: Dictionary, key: String) -> Color:
	var parts: Array = JsonData.get_array(data, key, SETTINGS_PATH)
	if parts.size() != 4:
		push_error("OasisWater : « %s » doit contenir 4 composantes." % key)
		return Color.MAGENTA
	return Color(float(parts[0]), float(parts[1]), float(parts[2]), float(parts[3]))


## Construit la surface d'eau centrée en (center.x, hauteur, center.y) ; UV.x vaut 0 au centre et 1 au bord.
## Le matériau est unique et le maillage est partagé par rayon : reconstruire une oasis ne coûte
## qu'un nœud.
static func build(center: Vector2, radius: float) -> Node3D:
	_load_settings()
	var instance := MeshInstance3D.new()
	instance.name = "OasisWater"
	instance.mesh = _mesh_for(radius)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.position = Vector3(center.x, _height, center.y)
	return instance


static func _mesh_for(radius: float) -> ArrayMesh:
	var cached: ArrayMesh = _meshes.get(radius)
	if cached != null:
		return cached
	var settings: Dictionary = _settings
	var segments: int = int(JsonData.get_float(settings, "segments", SETTINGS_PATH))
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	# Anneau interne à mi-rayon : assez de sommets pour les vagues, deux anneaux au total.
	var inner: float = 0.5
	vertices.resize(1 + segments * 2)
	normals.resize(vertices.size())
	uvs.resize(vertices.size())
	indices.resize(segments * 9)
	vertices[0] = Vector3.ZERO
	uvs[0] = Vector2.ZERO
	for i: int in segments:
		var angle: float = TAU * float(i) / float(segments)
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		vertices[1 + i] = direction * radius * inner
		uvs[1 + i] = Vector2(inner, 0.0)
		vertices[1 + segments + i] = direction * radius
		uvs[1 + segments + i] = Vector2(1.0, 0.0)
	normals.fill(Vector3.UP)
	for i: int in segments:
		var j: int = (i + 1) % segments
		var k: int = i * 9
		indices[k] = 0
		indices[k + 1] = 1 + j
		indices[k + 2] = 1 + i
		indices[k + 3] = 1 + i
		indices[k + 4] = 1 + j
		indices[k + 5] = 1 + segments + i
		indices[k + 6] = 1 + j
		indices[k + 7] = 1 + segments + j
		indices[k + 8] = 1 + segments + i
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _material())
	_meshes[radius] = mesh
	return mesh


static func _material() -> ShaderMaterial:
	if _shared_material != null:
		return _shared_material
	var settings: Dictionary = _settings
	var material := ShaderMaterial.new()
	material.shader = load(JsonData.get_string(settings, "shader", SETTINGS_PATH)) as Shader
	material.set_shader_parameter("shallow_color", _color(settings, "shallow_color"))
	material.set_shader_parameter("deep_color", _color(settings, "deep_color"))
	material.set_shader_parameter("foam_color", _color(settings, "foam_color"))
	for key: String in ["wave_speed", "wave_scale", "normal_strength", "edge_width"]:
		material.set_shader_parameter(key, JsonData.get_float(settings, key, SETTINGS_PATH))
	material.set_shader_parameter("wave_height", JsonData.get_float(settings, "wave_height_m", SETTINGS_PATH))
	material.set_shader_parameter("roughness_value", JsonData.get_float(settings, "roughness", SETTINGS_PATH))
	_shared_material = material
	return material
