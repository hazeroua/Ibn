class_name DesertFoliageMeshes
extends RefCounted
## Maillages partagés de la végétation du désert, lus dans les modèles générés par Blender (couleurs de
## sommets) selon data/desert/foliage.json. Chaque maillage reçoit un matériau partagé
## (desert_foliage.gdshader : vent et saisons). Construits une seule fois au chargement.
## Une espèce a soit un modèle unique (« model »), soit des niveaux de détail (« lods », du plus précis au plus lointain,
## avec la distance de fin de chacun) : tous les niveaux d'une espèce partagent le même matériau.

const SHADER_PATH: String = "res://world/desert_jeu/desert_foliage.gdshader"
const SETTINGS_PATH: String = "res://data/desert/foliage.json"
const TINTS: Dictionary[String, int] = {"none": 0, "grass": 1, "palm": 2, "bloom": 3, "flowering": 4, "fruit": 5, "crop": 6}


## Réglages par espèce (StringName -> Dictionary), tels que dans foliage.json.
static func load_settings() -> Dictionary:
	var root: Dictionary = JsonData.load_dictionary(SETTINGS_PATH)
	var species: Dictionary = JsonData.get_dictionary(root, "species", SETTINGS_PATH)
	var result: Dictionary = {}
	for id: Variant in species.keys():
		result[StringName(str(id))] = species[id]
	return result


## Maillages par espèce (StringName -> Mesh, niveau le plus précis) ; vide si un modèle manque ou n'a pas de couleurs.
static func build(settings: Dictionary) -> Dictionary:
	var levels: Dictionary = build_levels(settings)
	var meshes: Dictionary = {}
	for id: StringName in levels.keys():
		var species_levels: Array = levels[id]
		meshes[id] = (species_levels[0] as Dictionary)["mesh"]
	return meshes


## Niveaux de détail par espèce (StringName -> Array de Dictionary { "mesh": Mesh, "end_m": float }), du plus précis au
## plus lointain. end_m vaut 0 pour une espèce à modèle unique (la distance d'affichage vient alors de vegetation.json).
## Vide si un modèle manque, n'a pas de couleurs de sommets ou si un réglage est invalide.
static func build_levels(settings: Dictionary) -> Dictionary:
	var shader: Shader = load(SHADER_PATH) as Shader
	if shader == null:
		push_error("DesertFoliageMeshes : shader %s introuvable." % SHADER_PATH)
		return {}
	var result: Dictionary = {}
	for id: StringName in settings.keys():
		var spec: Dictionary = settings[id]
		var context: String = "%s > %s" % [SETTINGS_PATH, id]
		var tint_name: String = JsonData.get_string(spec, "tint", context)
		if not TINTS.has(tint_name):
			push_error("DesertFoliageMeshes : teinte inconnue « %s » (%s)." % [tint_name, context])
			return {}
		var material := ShaderMaterial.new()
		material.shader = shader
		material.set_shader_parameter(&"tint_kind", TINTS[tint_name])
		material.set_shader_parameter(&"sway_height_m", JsonData.get_float(spec, "sway_height_m", context))
		material.set_shader_parameter(&"sway_amount_m", JsonData.get_float(spec, "sway_amount_m", context))
		if tint_name == "flowering":
			material.set_shader_parameter(&"bloom_leaf_color", JsonData.get_vector3(spec, "bloom_leaf_color", context))
		if tint_name == "fruit":
			material.set_shader_parameter(&"fruit_leaf_color", JsonData.get_vector3(spec, "fruit_leaf_color", context))
			material.set_shader_parameter(&"fruit_ripe_color", JsonData.get_vector3(spec, "fruit_ripe_color", context))
		elif tint_name == "crop":
			material.set_shader_parameter(&"crop_min_growth", JsonData.get_float(spec, "crop_min_growth", context))
			material.set_shader_parameter(&"crop_ripe_color", JsonData.get_vector3(spec, "crop_ripe_color", context))
		var levels: Array[Dictionary] = []
		if spec.has("lods"):
			var previous_end: float = 0.0
			for entry: Variant in JsonData.get_array(spec, "lods", context):
				if not entry is Dictionary:
					push_error("DesertFoliageMeshes : niveau de détail invalide (%s)." % context)
					return {}
				var lod: Dictionary = entry
				var end_m: float = JsonData.get_float(lod, "end_m", context)
				if end_m <= previous_end:
					push_error("DesertFoliageMeshes : les distances de fin des niveaux doivent croître (%s)." % context)
					return {}
				previous_end = end_m
				levels.append({"path": JsonData.get_string(lod, "model", context), "end_m": end_m})
		else:
			levels.append({"path": JsonData.get_string(spec, "model", context), "end_m": 0.0})
		if levels.is_empty():
			push_error("DesertFoliageMeshes : aucun niveau de détail (%s)." % context)
			return {}
		var built: Array[Dictionary] = []
		for level: Dictionary in levels:
			var mesh: Mesh = _model_mesh(str(level["path"]))
			if mesh == null:
				return {}
			var copy: Mesh = mesh.duplicate() as Mesh
			for surface: int in copy.get_surface_count():
				copy.surface_set_material(surface, material)
			built.append({"mesh": copy, "end_m": level["end_m"]})
		result[id] = built
	return result


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
