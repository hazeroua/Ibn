class_name WaterBody
extends RefCounted
## Plans d'eau du désert : oasis, lac, guelta (eau libre) et chott (croûte de sel qui se couvre d'eau en hiver).
## Réglages par type dans res://data/assets/water_kinds.json ; emplacements dans desert.json (water_bodies).
##
## Pire cas : 32 plans d'eau, trois visibles à la fois depuis vue_crete. Un maillage par (type, rayon, rive) et un
## matériau par type, partagés : reconstruire un plan d'eau de même forme ne coûte qu'un nœud. Seul le chott (un par
## carte en pratique, 8 000 triangles au plus) a un maillage propre, qui suit le sol : il lit height_at() une fois à
## la construction (jamais par image). Aucun traitement par image : vagues et mirage sont calculés par le shader.
##
## Spécification (Dictionary) : id (String), kind (String), center (Vector2), radius_m, surface_height_m, depth_m,
## shore_width_m (facultatif), heightfield (DesertHeightfield, obligatoire pour le chott), barrier_radius_m
## (facultatif : rayon de la limite invisible, voir WaterBarrier).

const SETTINGS_PATH: String = "res://data/assets/water_kinds.json"
const MIDDAY_UNIFORM_KEY: String = "uniform"
## Clés d'un type qui ne sont pas des uniformes du shader.
const RESERVED_KEYS: Array[String] = ["shader", "mesh", "max_triangles", "surface_offset_m"]
const BARRIER_LAYER: int = 1

static var _settings: Dictionary = {}
static var _meshes: Dictionary[String, ArrayMesh] = {}
static var _materials: Dictionary[String, ShaderMaterial] = {}


## Réglages lus une fois (et uniformes globaux déclarés avant tout chargement de shader).
static func settings() -> Dictionary:
	if _settings.is_empty():
		_settings = JsonData.load_dictionary(SETTINGS_PATH)
		var midday: Dictionary = JsonData.get_dictionary(_settings, "midday", SETTINGS_PATH)
		ShaderGlobals.declare(
			StringName(JsonData.get_string(midday, MIDDAY_UNIFORM_KEY, SETTINGS_PATH)), RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0
		)
		ShaderGlobals.declare(&"season_wetness", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0)
	return _settings


## Construit le plan d'eau : un nœud posé à la hauteur de sa surface, avec sa limite invisible si le plan d'eau est
## plus profond que le gué. Renvoie null (et signale l'erreur) si la spécification est invalide.
static func build(spec: Dictionary) -> Node3D:
	var all: Dictionary = settings()
	var kind: String = str(spec.get("kind", ""))
	var kinds: Dictionary = JsonData.get_dictionary(all, "kinds", SETTINGS_PATH)
	if not kinds.has(kind):
		push_error("WaterBody : type de plan d'eau inconnu « %s »." % kind)
		return null
	var config: Dictionary = JsonData.get_dictionary(kinds, kind, SETTINGS_PATH)
	var context: String = "%s > kinds > %s" % [SETTINGS_PATH, kind]
	var center: Vector2 = spec["center"]
	var radius: float = float(spec["radius_m"])
	var surface: float = float(spec["surface_height_m"])
	var shore: float = float(spec.get("shore_width_m", 0.0))
	var mesh: ArrayMesh = _mesh_for(spec, config, context, kind, radius, shore, surface)
	if mesh == null:
		return null
	var root := Node3D.new()
	root.name = "Water_%s" % str(spec.get("id", kind))
	root.position = Vector3(center.x, surface, center.y)
	var instance := MeshInstance3D.new()
	instance.name = "Surface"
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.position.y = JsonData.get_float(config, "surface_offset_m", context)
	root.add_child(instance)
	var ring: float = float(spec.get("barrier_radius_m", -1.0))
	if ring > 0.0:
		var barrier: StaticBody3D = WaterBarrier.build(
			ring, float(spec["depth_m"]), JsonData.get_dictionary(all, "barrier", SETTINGS_PATH), BARRIER_LAYER
		)
		if barrier != null:
			root.add_child(barrier)
	return root


## Nombre de triangles d'un maillage de plan d'eau (pour les budgets).
static func triangle_count(mesh: ArrayMesh) -> int:
	var arrays: Array = mesh.surface_get_arrays(0)
	return (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3


## Maillage d'un plan d'eau de ce type, de ce rayon et de cette rive (partagé entre plans d'eau identiques).
static func mesh_for_shape(kind: String, radius: float, shore: float) -> ArrayMesh:
	var all: Dictionary = settings()
	var config: Dictionary = JsonData.get_dictionary(JsonData.get_dictionary(all, "kinds", SETTINGS_PATH), kind, SETTINGS_PATH)
	return _mesh_for({"kind": kind}, config, "%s > kinds > %s" % [SETTINGS_PATH, kind], kind, radius, shore, 0.0)


## Matériau partagé du type.
static func material_for(kind: String) -> ShaderMaterial:
	var all: Dictionary = settings()
	var config: Dictionary = JsonData.get_dictionary(JsonData.get_dictionary(all, "kinds", SETTINGS_PATH), kind, SETTINGS_PATH)
	return _material(kind, config, "%s > kinds > %s" % [SETTINGS_PATH, kind])


static func _mesh_for(
	spec: Dictionary, config: Dictionary, context: String, kind: String, radius: float, shore: float, surface: float
) -> ArrayMesh:
	var mesh_config: Dictionary = JsonData.get_dictionary(config, "mesh", context)
	var is_flat_following: bool = mesh_config.has("rings")
	var key: String = "%s|%s|%s" % [kind, radius, shore]
	if is_flat_following:
		key = "%s|%s" % [kind, str(spec.get("id", ""))]
	var cached: ArrayMesh = _meshes.get(key)
	if cached != null:
		return cached
	var arrays: Array = []
	if is_flat_following:
		var field: DesertHeightfield = spec.get("heightfield") as DesertHeightfield
		if field == null:
			push_error("WaterBody : le type « %s » suit le sol : « heightfield » est obligatoire." % kind)
			return null
		var center: Vector2 = spec["center"]
		arrays = _flat_following_arrays(
			mesh_config, context, field, center, radius, shore, surface, JsonData.get_float(config, "surface_offset_m", context)
		)
	else:
		arrays = _disc_arrays(mesh_config, context, radius, shore)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var budget: int = JsonData.get_int(config, "max_triangles", context)
	if triangle_count(mesh) > budget:
		push_error("WaterBody : %d triangles pour un budget de %d (%s)." % [triangle_count(mesh), budget, context])
		return null
	mesh.surface_set_material(0, _material(kind, config, context))
	_meshes[key] = mesh
	return mesh


## Fraction de profondeur (1 au plus profond, 0 à la rive) pour une distance normalisée au centre.
static func _depth_fraction(normalized: float, radius: float, shore: float) -> float:
	if shore > 0.0:
		return 1.0 - smoothstep(1.0 - shore / radius, 1.0, normalized)
	return 1.0 - smoothstep(0.0, 0.85, normalized)


## Disque : centre, anneaux intérieurs, anneaux de rive (plus denses près de la rive pour l'écume et les vagues).
static func _disc_arrays(mesh_config: Dictionary, context: String, radius: float, shore: float) -> Array:
	var segments: int = JsonData.get_int(mesh_config, "segments", context)
	var inner_rings: int = JsonData.get_int(mesh_config, "inner_rings", context)
	var shore_rings: int = JsonData.get_int(mesh_config, "shore_rings", context)
	if shore <= 0.0:
		shore_rings = 1
	var inner_edge: float = 1.0 - shore / radius
	var radii := PackedFloat32Array()
	for i: int in range(1, inner_rings + 1):
		radii.append(inner_edge * float(i) / float(inner_rings + 1))
	for j: int in range(1, shore_rings + 1):
		radii.append(inner_edge + (1.0 - inner_edge) * float(j) / float(shore_rings))
	return _polar_arrays(segments, radii, radius, shore, null, Vector2.ZERO, 0.0, 0.0)


static func _flat_following_arrays(
	mesh_config: Dictionary,
	context: String,
	field: DesertHeightfield,
	center: Vector2,
	radius: float,
	shore: float,
	surface: float,
	offset: float
) -> Array:
	var segments: int = JsonData.get_int(mesh_config, "segments", context)
	var rings: int = JsonData.get_int(mesh_config, "rings", context)
	var power: float = JsonData.get_float(mesh_config, "edge_power", context)
	var radii := PackedFloat32Array()
	for k: int in range(1, rings + 1):
		radii.append(pow(float(k) / float(rings), power))
	return _polar_arrays(segments, radii, radius, shore, field, center, surface, offset)


## Maillage polaire : un sommet central puis un anneau par rayon normalisé de radii. Avec un champ de hauteurs, le
## maillage suit le sol (hauteur locale = sol + offset - surface) ; sinon il est plat. UV.x = distance normalisée,
## COULEUR.r = fraction de profondeur.
static func _polar_arrays(
	segments: int,
	radii: PackedFloat32Array,
	radius: float,
	shore: float,
	field: DesertHeightfield,
	center: Vector2,
	surface: float,
	offset: float
) -> Array:
	var count: int = 1 + segments * radii.size()
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	vertices.resize(count)
	normals.resize(count)
	uvs.resize(count)
	colors.resize(count)
	normals.fill(Vector3.UP)
	vertices[0] = Vector3(0.0, _local_height(field, center, Vector2.ZERO, surface, offset), 0.0)
	uvs[0] = Vector2.ZERO
	colors[0] = Color(1.0, 0.0, 0.0, 1.0)
	for ring: int in radii.size():
		var normalized: float = radii[ring]
		var fraction: float = _depth_fraction(normalized, radius, shore)
		for i: int in segments:
			var angle: float = TAU * float(i) / float(segments)
			var planar := Vector2(cos(angle), sin(angle)) * radius * normalized
			var index: int = 1 + ring * segments + i
			vertices[index] = Vector3(planar.x, _local_height(field, center, planar, surface, offset), planar.y)
			uvs[index] = Vector2(normalized, 0.0)
			colors[index] = Color(fraction, 0.0, 0.0, 1.0)
	var indices := PackedInt32Array()
	indices.resize(segments * 3 + (radii.size() - 1) * segments * 6)
	var cursor: int = 0
	for i: int in segments:
		var j: int = (i + 1) % segments
		# Godot dessine les faces dont les sommets tournent dans le sens horaire vu de devant (ici : vu du ciel).
		indices[cursor] = 0
		indices[cursor + 1] = 1 + i
		indices[cursor + 2] = 1 + j
		cursor += 3
	for ring: int in range(radii.size() - 1):
		var inner: int = 1 + ring * segments
		var outer: int = inner + segments
		for i: int in segments:
			var j: int = (i + 1) % segments
			indices[cursor] = inner + i
			indices[cursor + 1] = outer + i
			indices[cursor + 2] = inner + j
			indices[cursor + 3] = inner + j
			indices[cursor + 4] = outer + i
			indices[cursor + 5] = outer + j
			cursor += 6
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays


static func _local_height(field: DesertHeightfield, center: Vector2, planar: Vector2, surface: float, offset: float) -> float:
	if field == null:
		return 0.0
	return field.height_at(center.x + planar.x, center.y + planar.y) + offset - surface


## Matériau partagé par type : chaque clé du type qui n'est pas réservée est un uniforme du shader (tableau de 3 ou 4
## nombres = couleur, nombre = flottant).
static func _material(kind: String, config: Dictionary, context: String) -> ShaderMaterial:
	var cached: ShaderMaterial = _materials.get(kind)
	if cached != null:
		return cached
	var material := ShaderMaterial.new()
	material.shader = load(JsonData.get_string(config, "shader", context)) as Shader
	for key: Variant in config.keys():
		var name: String = str(key)
		if RESERVED_KEYS.has(name):
			continue
		var value: Variant = config[key]
		if value is Array:
			var parts: Array = value
			if parts.size() == 4:
				material.set_shader_parameter(name, Color(float(parts[0]), float(parts[1]), float(parts[2]), float(parts[3])))
			elif parts.size() == 3:
				material.set_shader_parameter(name, Color(float(parts[0]), float(parts[1]), float(parts[2])))
			else:
				push_error("WaterBody : « %s » doit contenir 3 ou 4 composantes (%s)." % [name, context])
		else:
			material.set_shader_parameter(name, JsonData.get_float(config, name, context))
	_materials[kind] = material
	return material
