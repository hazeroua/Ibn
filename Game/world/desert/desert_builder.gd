class_name DesertBuilder
extends RefCounted
## Construit la carte de test du désert à partir de res://data/desert/desert.json : ciel, soleil, caméra,
## point d'apparition et nœud « Terrain » (DesertTestTerrain) qui bâtit les cellules au chargement.
## Aucun fichier annexe : la scène générée est petite et ne référence que des scripts et des données.
## Pire cas de construction de la scène : quelques nœuds ; les cellules sont mesurées par test_desert_terrain_load.gd.

const CONTEXT: String = "desert.json"
const SPAWN_GROUP: StringName = &"player_spawn"
const TERRAIN_NODE: String = "Terrain"


static func build(data: Dictionary) -> Node3D:
	var world := Node3D.new()
	world.name = "Desert"
	var field: DesertHeightfield = DesertHeightfield.from_data(data)
	if field == null:
		return world
	world.add_child(_build_environment(JsonData.get_dictionary(data, "environment", CONTEXT)))
	world.add_child(_build_sun(JsonData.get_dictionary(data, "sun", CONTEXT)))
	world.add_child(_build_camera(JsonData.get_dictionary(data, "camera", CONTEXT)))
	var terrain := DesertTestTerrain.new()
	terrain.name = TERRAIN_NODE
	world.add_child(terrain)
	world.add_child(_build_spawn(JsonData.get_dictionary(data, "player_spawn", CONTEXT), field))
	_assign_owner(world, world)
	return world


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


static func _build_spawn(config: Dictionary, field: DesertHeightfield) -> Marker3D:
	var context: String = CONTEXT + " > player_spawn"
	var ground: Vector2 = JsonData.get_vector2(config, "position", context)
	var spawn := Marker3D.new()
	spawn.name = "PlayerSpawn"
	var height: float = field.height_at(ground.x, ground.y) + JsonData.get_float(config, "height_offset_m", context)
	spawn.transform = Transform3D(
		Basis(Vector3.UP, deg_to_rad(JsonData.get_float(config, "yaw_degrees", context))), Vector3(ground.x, height, ground.y)
	)
	spawn.add_to_group(SPAWN_GROUP, true)
	return spawn


static func _assign_owner(node: Node, owner_node: Node) -> void:
	for child: Node in node.get_children():
		child.owner = owner_node
		_assign_owner(child, owner_node)
