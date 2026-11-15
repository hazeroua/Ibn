class_name WindHaze
extends MeshInstance3D
## Brume de chaleur et poussière à l'horizon : un anneau translucide centré sur la caméra.
##
## Un seul maillage et un seul matériau créés à la construction ; ensuite le coût par image se
## réduit au déplacement de l'anneau. Le pire cas (vent maximal, anneau plein écran à l'horizon)
## coûte un passage translucide sans lecture de l'écran.

const SHADER_PATH: String = "res://world/wind/wind_haze.gdshader"


## Construit l'anneau (un maillage fermé, sans couture : la dernière colonne reprend la première).
func build(settings: WindSettings) -> void:
	name = "WindHaze"
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	var segments: int = settings.haze_segments
	var rings: int = settings.haze_rings
	var columns: int = segments + 1
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	vertices.resize(columns * (rings + 1))
	uvs.resize(vertices.size())
	normals.resize(vertices.size())
	for ring: int in rings + 1:
		var t: float = float(ring) / float(rings)
		# Anneaux resserrés près de l'horizon, là où le dégradé varie le plus.
		var y: float = settings.haze_height * t * t
		for column: int in columns:
			var u: float = float(column) / float(segments)
			var angle: float = TAU * u
			var index: int = ring * columns + column
			vertices[index] = Vector3(cos(angle) * settings.haze_radius, y, sin(angle) * settings.haze_radius)
			uvs[index] = Vector2(u, t)
			normals[index] = Vector3(-cos(angle), 0.0, -sin(angle))
	var indices := PackedInt32Array()
	indices.resize(segments * rings * 6)
	var cursor: int = 0
	for ring: int in rings:
		for column: int in segments:
			var a: int = ring * columns + column
			var b: int = a + 1
			var c: int = a + columns
			var d: int = c + 1
			indices[cursor] = a
			indices[cursor + 1] = c
			indices[cursor + 2] = b
			indices[cursor + 3] = b
			indices[cursor + 4] = c
			indices[cursor + 5] = d
			cursor += 6
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var array_mesh := ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# La caméra est toujours au centre : l'anneau ne doit jamais être écarté par le test de visibilité.
	var margin: float = settings.haze_radius
	array_mesh.custom_aabb = AABB(Vector3(-margin, -1.0, -margin), Vector3(margin * 2.0, settings.haze_height + 2.0, margin * 2.0))
	var shader: Shader = load(SHADER_PATH) as Shader
	if shader == null:
		push_error("WindHaze : shader introuvable : %s." % SHADER_PATH)
		return
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter(&"heat_color", settings.haze_heat_color)
	material.set_shader_parameter(&"dust_color", settings.haze_dust_color)
	material.set_shader_parameter(&"heat_alpha", settings.haze_heat_alpha)
	material.set_shader_parameter(&"dust_alpha", settings.haze_dust_alpha)
	material.set_shader_parameter(&"noise_scale", settings.haze_noise_scale)
	material.set_shader_parameter(&"shimmer_speed", settings.haze_shimmer_speed)
	array_mesh.surface_set_material(0, material)
	mesh = array_mesh
