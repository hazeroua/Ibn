class_name VitrinePersonnageBuilder
extends RefCounted
## Construit la vitrine du personnage à partir de res://data/vitrine_personnage/vitrine_personnage.json.
##
## Toutes les copies d'un personnage partagent la même scène importée : un seul maillage, un seul matériau et
## les mêmes animations en mémoire, quel que soit leur nombre. Les nœuds internes d'une copie ne sont pas
## enregistrés dans la scène produite : seule la référence au fichier du personnage l'est.

const SCRIPT_PATH: String = "res://world/vitrine_personnage/vitrine_personnage.gd"
const CONTEXT: String = "vitrine_personnage.json"


static func build(data: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "VitrinePersonnage"
	root.set_script(load(SCRIPT_PATH))
	root.add_child(_build_environment(JsonData.get_dictionary(data, "environment", CONTEXT)))
	root.add_child(_build_sun(JsonData.get_dictionary(data, "sun", CONTEXT)))
	root.add_child(_build_ground(JsonData.get_dictionary(data, "ground", CONTEXT)))
	var characters := Node3D.new()
	characters.name = "Characters"
	root.add_child(characters)
	_build_characters(characters, JsonData.get_array(data, "characters", CONTEXT))
	_build_crowd(characters, JsonData.get_dictionary(data, "crowd", CONTEXT))
	root.add_child(_build_camera(JsonData.get_dictionary(data, "camera", CONTEXT)))
	_assign_owner(root, root)
	return root


static func _build_environment(config: Dictionary) -> WorldEnvironment:
	var context: String = CONTEXT + " > environment"
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = JsonData.get_color(config, "sky_top_color", context)
	sky_material.sky_horizon_color = JsonData.get_color(config, "sky_horizon_color", context)
	sky_material.ground_horizon_color = JsonData.get_color(config, "ground_horizon_color", context)
	sky_material.ground_bottom_color = JsonData.get_color(config, "ground_bottom_color", context)
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	environment.tonemap_exposure = JsonData.get_float(config, "exposure", context)
	environment.ssao_enabled = JsonData.get_bool(config, "ssao", context)
	environment.fog_enabled = JsonData.get_bool(config, "fog", context)
	environment.fog_density = JsonData.get_float(config, "fog_density", context)
	environment.fog_light_color = JsonData.get_color(config, "sky_horizon_color", context)
	var node := WorldEnvironment.new()
	node.name = "Environment"
	node.environment = environment
	return node


static func _build_sun(config: Dictionary) -> DirectionalLight3D:
	var context: String = CONTEXT + " > sun"
	var light := DirectionalLight3D.new()
	light.name = "Sun"
	light.rotation_degrees = JsonData.get_vector3(config, "rotation_degrees", context)
	light.light_color = JsonData.get_color(config, "color", context)
	light.light_energy = JsonData.get_float(config, "energy", context)
	light.shadow_enabled = true
	light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	light.directional_shadow_max_distance = JsonData.get_float(config, "shadow_max_distance", context)
	return light


static func _build_ground(config: Dictionary) -> MeshInstance3D:
	var context: String = CONTEXT + " > ground"
	var material := StandardMaterial3D.new()
	material.albedo_color = JsonData.get_color(config, "color", context)
	material.roughness = JsonData.get_float(config, "roughness", context)
	var mesh := PlaneMesh.new()
	mesh.size = JsonData.get_vector2(config, "size", context)
	mesh.material = material
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	ground.mesh = mesh
	return ground


static func _build_characters(parent: Node3D, entries: Array) -> void:
	var ids: Dictionary[String, bool] = {}
	for raw: Variant in entries:
		if typeof(raw) != TYPE_DICTIONARY:
			push_error("VitrinePersonnageBuilder : chaque personnage doit être un objet JSON.")
			continue
		var entry: Dictionary = raw
		var entry_id: String = JsonData.get_string(entry, "id", CONTEXT + " > characters")
		if entry_id.is_empty() or entry_id.validate_node_name() != entry_id or ids.has(entry_id):
			push_error("VitrinePersonnageBuilder : identifiant absent, invalide ou en double « %s »." % entry_id)
			continue
		ids[entry_id] = true
		var context: String = CONTEXT + " > " + entry_id
		_add_character(
			parent,
			entry_id,
			JsonData.get_string(entry, "character", context),
			JsonData.get_string(entry, "animation", context),
			JsonData.get_vector3(entry, "position", context),
			JsonData.get_vector3_or(entry, "rotation_degrees", Vector3.ZERO, context),
			JsonData.get_float(entry, "time_offset_s", context),
		)


## La foule : une grille de copies, animations et décalages de temps répartis de façon déterministe.
static func _build_crowd(parent: Node3D, config: Dictionary) -> void:
	var context: String = CONTEXT + " > crowd"
	var character_id: String = JsonData.get_string(config, "character", context)
	var animations: Array = JsonData.get_array(config, "animations", context)
	var origin: Vector3 = JsonData.get_vector3(config, "origin", context)
	var columns: int = JsonData.get_int(config, "columns", context)
	var rows: int = JsonData.get_int(config, "rows", context)
	var spacing: Vector2 = JsonData.get_vector2(config, "spacing", context)
	var step: float = JsonData.get_float(config, "time_offset_step_s", context)
	if columns < 1 or rows < 1 or animations.is_empty():
		push_error("VitrinePersonnageBuilder : la foule doit avoir au moins une colonne, une rangée et une animation.")
		return
	for row: int in rows:
		for column: int in columns:
			var index: int = row * columns + column
			var position := Vector3(
				origin.x + (float(column) - float(columns - 1) * 0.5) * spacing.x,
				origin.y,
				origin.z + (float(row) - float(rows - 1) * 0.5) * spacing.y,
			)
			_add_character(
				parent,
				"foule_%d" % index,
				character_id,
				str(animations[index % animations.size()]),
				position,
				Vector3.ZERO,
				float(index) * step
			)


static func _add_character(
	parent: Node3D,
	node_name: String,
	character_id: String,
	animation_name: String,
	position: Vector3,
	rotation_degrees: Vector3,
	time_offset_s: float,
) -> void:
	var scene: PackedScene = CharacterCatalog.load_scene(character_id)
	if scene == null:
		return
	var instance: Node3D = scene.instantiate() as Node3D
	if instance == null:
		push_error("VitrinePersonnageBuilder : la scène de « %s » n'a pas de racine Node3D." % character_id)
		return
	instance.name = node_name
	instance.position = position
	instance.rotation_degrees = rotation_degrees
	instance.set_meta(&"animation", animation_name)
	instance.set_meta(&"time_offset_s", time_offset_s)
	parent.add_child(instance)


static func _build_camera(config: Dictionary) -> Camera3D:
	var context: String = CONTEXT + " > camera"
	var camera := Camera3D.new()
	camera.name = "Camera"
	var position: Vector3 = JsonData.get_vector3(config, "position", context)
	var target: Vector3 = JsonData.get_vector3(config, "target", context)
	camera.transform = Transform3D(Basis.IDENTITY, position).looking_at(target, Vector3.UP)
	camera.fov = JsonData.get_float(config, "fov", context)
	camera.far = JsonData.get_float(config, "far", context)
	camera.current = true
	return camera


## Chaque nœud appartient à la racine ; on ne descend pas dans une copie de personnage (scène instanciée).
static func _assign_owner(node: Node, owner: Node) -> void:
	for child: Node in node.get_children():
		child.owner = owner
		if child.scene_file_path.is_empty():
			_assign_owner(child, owner)
