class_name FaunaMeshes
extends RefCounted
## Maillage d'un modèle de faune généré par Scripts/Blender/generer_faune.py (couleurs de sommets, alpha = poids d'animation).


## Maillage du premier MeshInstance3D du modèle, ou null (avec erreur) s'il manque ou n'a pas de couleurs de sommets.
static func model_mesh(path: String) -> Mesh:
	var scene: PackedScene = load(path) as PackedScene
	if scene == null:
		push_error("FaunaMeshes : %s absent (lancer Scripts/Pipeline/generer-faune.ps1)." % path)
		return null
	var root: Node = scene.instantiate()
	var found: Array[Node] = root.find_children("*", "MeshInstance3D", true, false)
	var mesh: Mesh = null
	if not found.is_empty():
		mesh = (found[0] as MeshInstance3D).mesh
	root.free()
	if mesh == null:
		push_error("FaunaMeshes : aucun maillage dans %s." % path)
		return null
	for surface: int in mesh.get_surface_count():
		if (mesh.surface_get_format(surface) & Mesh.ARRAY_FORMAT_COLOR) == 0:
			push_error("FaunaMeshes : %s n'a pas de couleurs de sommets (régénérer les modèles)." % path)
			return null
	return mesh


## Copie du maillage avec le matériau donné sur toutes ses surfaces.
static func with_material(mesh: Mesh, material: Material) -> Mesh:
	var copy: Mesh = mesh.duplicate() as Mesh
	for surface: int in copy.get_surface_count():
		copy.surface_set_material(surface, material)
	return copy
