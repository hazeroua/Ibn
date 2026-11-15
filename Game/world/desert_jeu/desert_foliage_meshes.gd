class_name DesertFoliageMeshes
extends RefCounted
## Maillages partagés de la végétation du désert : palmier (modèle du ticket props, niveau de détail moyen),
## buisson et herbe sèche (étoiles de plans croisés, quelques triangles). Chaque maillage reçoit un matériau
## partagé (desert_foliage.gdshader). Construits une seule fois au chargement.

const SHADER_PATH: String = "res://world/desert_jeu/desert_foliage.gdshader"
const PALM_SCENE: String = "res://assets/desert/palmier_a_lod1.glb"
const TINT_NONE: int = 0
const TINT_GRASS: int = 1
const TINT_PALM: int = 2


static func build() -> Dictionary:
	var shader: Shader = load(SHADER_PATH) as Shader
	if shader == null:
		push_error("DesertFoliageMeshes : shader %s introuvable." % SHADER_PATH)
		return {}
	var meshes: Dictionary = {}
	var palm: Mesh = _palm_mesh()
	if palm == null:
		return {}
	meshes[&"palmier"] = _with_material(palm, shader, TINT_PALM, 9.0, 1.2)
	meshes[&"buisson"] = _with_material(_star_mesh(5, 1.1, 0.9, Color(0.42, 0.5, 0.25)), shader, TINT_GRASS, 0.9, 0.12)
	meshes[&"herbe_seche"] = _with_material(_star_mesh(3, 0.5, 0.55, Color(0.62, 0.56, 0.32)), shader, TINT_GRASS, 0.55, 0.1)
	return meshes


static func _palm_mesh() -> Mesh:
	var scene: PackedScene = load(PALM_SCENE) as PackedScene
	if scene == null:
		push_error("DesertFoliageMeshes : %s absent (lancer Scripts/Pipeline/generer-props-desert.ps1)." % PALM_SCENE)
		return null
	var root: Node = scene.instantiate()
	var found: Array[Node] = root.find_children("*", "MeshInstance3D", true, false)
	var mesh: Mesh = null
	if not found.is_empty():
		mesh = (found[0] as MeshInstance3D).mesh
	root.free()
	if mesh == null:
		push_error("DesertFoliageMeshes : aucun maillage dans %s." % PALM_SCENE)
	return mesh


static func _with_material(mesh: Mesh, shader: Shader, tint_kind: int, sway_height: float, sway_amount: float) -> Mesh:
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter(&"tint_kind", tint_kind)
	material.set_shader_parameter(&"sway_height_m", sway_height)
	material.set_shader_parameter(&"sway_amount_m", sway_amount)
	var copy: Mesh = mesh.duplicate() as Mesh
	for surface: int in copy.get_surface_count():
		copy.surface_set_material(surface, material)
	return copy


## Étoile de plans verticaux croisés : base sombre, sommet clair (couleurs de sommet).
static func _star_mesh(planes: int, width: float, height: float, color: Color) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for plane: int in planes:
		var angle: float = PI * float(plane) / float(planes)
		var direction := Vector3(cos(angle), 0.0, sin(angle)) * (width * 0.5)
		var base: int = vertices.size()
		vertices.append_array([-direction, direction, direction * 0.4 + Vector3.UP * height, -direction * 0.4 + Vector3.UP * height])
		colors.append_array([color * 0.6, color * 0.6, color * 1.15, color * 1.15])
		normals.append_array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
		indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
