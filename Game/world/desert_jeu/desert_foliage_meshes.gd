class_name DesertFoliageMeshes
extends RefCounted
## Maillages partagés de la végétation du désert, lus dans les modèles générés par Blender (couleurs de
## sommets) selon data/desert/foliage.json. Chaque maillage reçoit un matériau partagé
## (desert_foliage.gdshader : vent et saisons). Construits une seule fois au chargement.

const SHADER_PATH: String = "res://world/desert_jeu/desert_foliage.gdshader"
const SETTINGS_PATH: String = "res://data/desert/foliage.json"
const TINTS: Dictionary[String, int] = {"none": 0, "grass": 1, "palm": 2}


## Réglages par espèce (StringName -> Dictionary), tels que dans foliage.json.
static func load_settings() -> Dictionary:
	var root: Dictionary = JsonData.load_dictionary(SETTINGS_PATH)
	var species: Dictionary = JsonData.get_dictionary(root, "species", SETTINGS_PATH)
	var result: Dictionary = {}
	for id: Variant in species.keys():
		result[StringName(str(id))] = species[id]
	return result


## Maillages par espèce (StringName -> Mesh) ; vide si un modèle manque ou n'a pas de couleurs.
static func build(settings: Dictionary) -> Dictionary:
	var shader: Shader = load(SHADER_PATH) as Shader
	if shader == null:
		push_error("DesertFoliageMeshes : shader %s introuvable." % SHADER_PATH)
		return {}
	var meshes: Dictionary = {}
	for id: StringName in settings.keys():
		var spec: Dictionary = settings[id]
		var context: String = "%s > %s" % [SETTINGS_PATH, id]
		var mesh: Mesh = _model_mesh(JsonData.get_string(spec, "model", context))
		if mesh == null:
			return {}
		var tint_name: String = JsonData.get_string(spec, "tint", context)
		if not TINTS.has(tint_name):
			push_error("DesertFoliageMeshes : teinte inconnue « %s » (%s)." % [tint_name, context])
			return {}
		var material := ShaderMaterial.new()
		material.shader = shader
		material.set_shader_parameter(&"tint_kind", TINTS[tint_name])
		material.set_shader_parameter(&"sway_height_m", JsonData.get_float(spec, "sway_height_m", context))
		material.set_shader_parameter(&"sway_amount_m", JsonData.get_float(spec, "sway_amount_m", context))
		var copy: Mesh = mesh.duplicate() as Mesh
		for surface: int in copy.get_surface_count():
			copy.surface_set_material(surface, material)
		meshes[id] = copy
	return meshes


static func _model_mesh(path: String) -> Mesh:
	var scene: PackedScene = load(path) as PackedScene
	if scene == null:
		push_error("DesertFoliageMeshes : %s absent (lancer Scripts/Pipeline/generer-props-desert.ps1)." % path)
		return null
	var root: Node = scene.instantiate()
	var found: Array[Node] = root.find_children("*", "MeshInstance3D", true, false)
	var mesh: Mesh = null
	if not found.is_empty():
		mesh = (found[0] as MeshInstance3D).mesh
	root.free()
	if mesh == null:
		push_error("DesertFoliageMeshes : aucun maillage dans %s." % path)
		return null
	for surface: int in mesh.get_surface_count():
		if (mesh.surface_get_format(surface) & Mesh.ARRAY_FORMAT_COLOR) == 0:
			push_error("DesertFoliageMeshes : %s n'a pas de couleurs de sommets (régénérer les modèles)." % path)
			return null
	return mesh
