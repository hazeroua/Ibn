class_name CollinesBuilder
extends RefCounted
## Construit la carte « collines » à partir de res://data/collines/collines.json.
##
## Terrain : un corps statique (couche 1) avec une forme de collision en carte de hauteurs et des tuiles visibles
## à niveaux de détail (voir CollinesTiles), texturé par un shader à deux surfaces. Obstacles : un
## MultiMeshInstance3D par type (un seul appel de dessin par type, quel que soit leur nombre), un seul StaticBody3D
## par type dont les CollisionShape3D partagent la même forme : la mémoire reste constante quand on ajoute des
## obstacles identiques.
##
## Pire cas de construction : 1 050 625 sommets de relief, 256 maillages de terrain et 1 000 obstacles
## (mesuré par tests/unit/test_collines_builder.gd).

const POLYHAVEN_DIR: String = "res://assets/textures/polyhaven"
const TERRAIN_SHADER: String = "res://world/collines/collines_terrain.gdshader"
const CONTEXT: String = "collines.json"
const SURFACE_IDS: PackedStringArray = ["sable", "pierre", "terre", "bois"]
const OBSTACLE_KINDS: PackedStringArray = ["rock", "wall"]
const SPAWN_GROUP: StringName = &"player_spawn"
const TERRAIN_NODE: String = "Terrain"
## Couche de collision du décor statique (contrat du MVP 1 : couche 1 = bit 0 = valeur 1).
const WORLD_LAYER_MASK: int = 1
## Résolution angulaire des rochers : sommets en longitude et en latitude (peu de triangles, aspect taillé).
const ROCK_RADIAL_SEGMENTS: int = 9
const ROCK_RINGS: int = 5
const ROCK_NOISE_FREQUENCY: float = 2.2


## Construit la scène complète (sans rien écrire sur le disque : voir persist_terrain).
static func build(data: Dictionary) -> Node3D:
	var world := Node3D.new()
	world.name = "Collines"
	var terrain_config: Dictionary = JsonData.get_dictionary(data, "terrain", CONTEXT)
	var relief: CollinesRelief = CollinesRelief.generate(terrain_config)
	if relief == null:
		return world
	world.add_child(_build_environment(JsonData.get_dictionary(data, "environment", CONTEXT)))
	world.add_child(_build_sun(JsonData.get_dictionary(data, "sun", CONTEXT)))
	world.add_child(_build_camera(JsonData.get_dictionary(data, "camera", CONTEXT)))
	var terrain: CollinesTerrain = _build_terrain(terrain_config, relief)
	if terrain == null:
		return world
	world.add_child(terrain)
	var obstacles := Node3D.new()
	obstacles.name = "Obstacles"
	world.add_child(obstacles)
	_build_obstacles(obstacles, JsonData.get_dictionary(data, "obstacles", CONTEXT), relief)
	world.add_child(_build_spawn(JsonData.get_dictionary(data, "player_spawn", CONTEXT), relief))
	_assign_owner(world, world)
	return world


## Enregistre les gros éléments du terrain (maillages, carte de hauteurs, cartes de contrôle) dans des fichiers
## binaires à côté de la scène, que la scène référencera au lieu de les embarquer en texte.
## À appeler par le script de construction avant l'empaquetage de la scène.
static func persist_terrain(world: Node3D, data: Dictionary) -> bool:
	var terrain: CollinesTerrain = world.get_node_or_null(TERRAIN_NODE)
	if terrain == null:
		push_error("CollinesBuilder : nœud « %s » absent, rien à enregistrer." % TERRAIN_NODE)
		return false
	var directory: String = JsonData.get_string(JsonData.get_dictionary(data, "terrain", CONTEXT), "data_directory", CONTEXT + " > terrain")
	var err: Error = DirAccess.make_dir_recursive_absolute(directory)
	if err != OK:
		push_error("CollinesBuilder : impossible de créer %s (%s)." % [directory, error_string(err)])
		return false
	# Les anciens fichiers sont supprimés : un maillage retiré des données ne doit pas survivre.
	for file_name: String in DirAccess.get_files_at(directory):
		if file_name.ends_with(".res"):
			DirAccess.remove_absolute(directory.path_join(file_name))
	var collision: CollisionShape3D = terrain.get_node("Collision")
	var saved: bool = _save_resource(collision.shape, directory.path_join("hauteurs.res"))
	saved = _save_resource(terrain.control_image, directory.path_join("controle_image.res")) and saved
	var material: ShaderMaterial = terrain.get_node("Tuiles").get_child(0).get_child(0).material_override
	for parameter: String in ["relief_normal", "control_map"]:
		saved = _save_resource(material.get_shader_parameter(parameter), directory.path_join("%s.res" % parameter)) and saved
	for tile: Node in terrain.get_node("Tuiles").get_children():
		for lod: Node in tile.get_children():
			var instance: MeshInstance3D = lod
			saved = _save_resource(instance.mesh, directory.path_join("%s_%s.res" % [tile.name, lod.name])) and saved
	return saved


static func _save_resource(resource: Resource, path: String) -> bool:
	var err: Error = ResourceSaver.save(resource, path)
	if err != OK:
		push_error("CollinesBuilder : impossible d'enregistrer %s (%s)." % [path, error_string(err)])
		return false
	# La scène référencera le fichier au lieu d'embarquer la ressource.
	resource.take_over_path(path)
	return true


# ---------------------------------------------------------------------------
# Ciel, soleil, caméra, point d'apparition
# ---------------------------------------------------------------------------


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


static func _build_spawn(config: Dictionary, relief: CollinesRelief) -> Marker3D:
	var context: String = CONTEXT + " > player_spawn"
	var ground: Vector2 = JsonData.get_vector2(config, "position", context)
	var spawn := Marker3D.new()
	spawn.name = "PlayerSpawn"
	var height: float = relief.height_at(ground.x, ground.y) + JsonData.get_float(config, "height_offset_m", context)
	spawn.transform = Transform3D(
		Basis(Vector3.UP, deg_to_rad(JsonData.get_float(config, "yaw_degrees", context))), Vector3(ground.x, height, ground.y)
	)
	spawn.add_to_group(SPAWN_GROUP, true)
	return spawn


# ---------------------------------------------------------------------------
# Terrain
# ---------------------------------------------------------------------------


static func _build_terrain(config: Dictionary, relief: CollinesRelief) -> CollinesTerrain:
	var context: String = CONTEXT + " > terrain"
	if not is_equal_approx(relief.spacing, 1.0):
		push_error("CollinesBuilder : vertex_spacing_m doit valoir 1 (carte de hauteurs Jolt au pas d'un mètre) (%s)." % context)
		return null
	var layers: Array = JsonData.get_array(config, "layers", context)
	if layers.size() != 2 or typeof(layers[0]) != TYPE_DICTIONARY or typeof(layers[1]) != TYPE_DICTIONARY:
		push_error("CollinesBuilder : le terrain exige exactement deux couches (base et recouvrement) (%s)." % context)
		return null
	var blend: PackedByteArray = relief.overlay_blend(JsonData.get_dictionary(config, "overlay_rules", context))
	if blend.is_empty():
		return null

	var terrain := CollinesTerrain.new()
	terrain.name = TERRAIN_NODE
	terrain.collision_layer = JsonData.get_int(config, "collision_layer_mask", context)
	terrain.collision_mask = 0
	var surfaces := PackedStringArray()
	for raw: Variant in layers:
		var layer: Dictionary = raw
		surfaces.append(JsonData.get_string(layer, "surface", context + " > layers"))
	terrain.layer_surfaces = surfaces
	terrain.grid_origin = relief.origin
	terrain.grid_spacing = relief.spacing
	terrain.control_image = Image.create_from_data(relief.size_px, relief.size_px, false, Image.FORMAT_R8, blend)

	# Collision : une seule carte de hauteurs au pas d'un mètre, centrée sur l'origine du corps.
	var shape := HeightMapShape3D.new()
	shape.map_width = relief.size_px
	shape.map_depth = relief.size_px
	shape.map_data = relief.heights
	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	collision.shape = shape
	terrain.add_child(collision)

	var material: ShaderMaterial = _terrain_material(config, relief, terrain.control_image, layers)
	var tiles: Node3D = CollinesTiles.build(relief, JsonData.get_dictionary(config, "tiles", context), material)
	if tiles == null:
		terrain.free()
		return null
	terrain.add_child(tiles)
	return terrain


static func _terrain_material(config: Dictionary, relief: CollinesRelief, control_image: Image, layers: Array) -> ShaderMaterial:
	var context: String = CONTEXT + " > terrain"
	var shading: Dictionary = JsonData.get_dictionary(config, "shading", context)
	var material := ShaderMaterial.new()
	material.shader = load(TERRAIN_SHADER)
	var base: Dictionary = layers[0]
	var overlay: Dictionary = layers[1]
	for map_name: Array in [["albedo", "diff"], ["normal", "nor_gl"], ["roughness", "rough"]]:
		material.set_shader_parameter("base_" + map_name[0], _load_texture(JsonData.get_string(base, "texture", context), map_name[1]))
		material.set_shader_parameter(
			"overlay_" + map_name[0], _load_texture(JsonData.get_string(overlay, "texture", context), map_name[1])
		)
	material.set_shader_parameter("base_uv_scale", JsonData.get_float(base, "uv_scale", context))
	material.set_shader_parameter("overlay_uv_scale", JsonData.get_float(overlay, "uv_scale", context))
	material.set_shader_parameter("base_tint", JsonData.get_color(base, "tint", context))
	material.set_shader_parameter("overlay_tint", JsonData.get_color(overlay, "tint", context))
	for key: String in ["detail_normal_strength", "macro_scale", "macro_strength"]:
		material.set_shader_parameter(key, JsonData.get_float(shading, key, context + " > shading"))
	material.set_shader_parameter("map_origin", relief.origin)
	material.set_shader_parameter("map_size", float(relief.size_px - 1) * relief.spacing)
	material.set_shader_parameter("relief_normal", _mipmapped_texture(relief.normal_image()))
	# La carte de contrôle de la scène garde un seul niveau (lecture par surface_at) : la texture reçoit sa propre copie.
	material.set_shader_parameter("control_map", _mipmapped_texture(control_image.duplicate()))
	return material


static func _mipmapped_texture(image: Image) -> ImageTexture:
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


# ---------------------------------------------------------------------------
# Obstacles
# ---------------------------------------------------------------------------


static func _build_obstacles(parent: Node3D, config: Dictionary, relief: CollinesRelief) -> void:
	var context: String = CONTEXT + " > obstacles"
	var type_entries: Array = JsonData.get_array(config, "types", context)
	var types: Array[Dictionary] = []
	var radii := PackedFloat32Array()
	var weights := PackedFloat32Array()
	var ids: Dictionary[String, bool] = {}
	for raw: Variant in type_entries:
		if typeof(raw) != TYPE_DICTIONARY:
			push_error("CollinesBuilder : chaque type d'obstacle doit être un objet JSON (%s)." % context)
			return
		var entry: Dictionary = raw
		var type_id: String = JsonData.get_string(entry, "id", context)
		if type_id.is_empty() or type_id.validate_node_name() != type_id or ids.has(type_id):
			push_error("CollinesBuilder : identifiant de type absent, invalide ou en double « %s »." % type_id)
			return
		ids[type_id] = true
		var type_context: String = context + " > " + type_id
		var kind: String = JsonData.get_string(entry, "kind", type_context)
		var surface: String = JsonData.get_string(entry, "surface", type_context)
		if not OBSTACLE_KINDS.has(kind) or not SURFACE_IDS.has(surface):
			push_error("CollinesBuilder : genre « %s » ou surface « %s » inconnu pour %s." % [kind, surface, type_id])
			return
		var size: Vector3 = JsonData.get_vector3(entry, "size", type_context)
		if size.x <= 0.0 or size.y <= 0.0 or size.z <= 0.0:
			push_error("CollinesBuilder : taille invalide pour « %s »." % type_id)
			return
		types.append(entry)
		radii.append(JsonData.get_float(entry, "footprint_radius_m", type_context))
		weights.append(JsonData.get_float(entry, "weight", type_context))

	var zone: Dictionary = JsonData.get_dictionary(config, "zone", context)
	var placement: CollinesObstacles = CollinesObstacles.place(zone, radii, weights)
	if placement == null:
		return
	var sink: float = JsonData.get_float(zone, "sink_m", context + " > zone")
	var transforms_by_type: Array[Array] = []
	for _i: int in types.size():
		transforms_by_type.append([])
	for i: int in placement.type_indices.size():
		var type_index: int = placement.type_indices[i]
		var size: Vector3 = JsonData.get_vector3(types[type_index], "size", context)
		var ground: Vector2 = placement.positions[i]
		var base: float = _lowest_ground(relief, ground, radii[type_index])
		var origin := Vector3(ground.x, base + size.y * 0.5 - sink, ground.y)
		transforms_by_type[type_index].append(Transform3D(Basis(Vector3.UP, placement.yaws[i]), origin))

	var materials: Dictionary[String, StandardMaterial3D] = {}
	for type_index: int in types.size():
		var transforms: Array = transforms_by_type[type_index]
		if transforms.is_empty():
			continue
		var entry: Dictionary = types[type_index]
		var type_id: String = JsonData.get_string(entry, "id", context)
		var type_context: String = context + " > " + type_id
		var size: Vector3 = JsonData.get_vector3(entry, "size", type_context)
		var material: StandardMaterial3D = _obstacle_material(entry, materials, type_context)
		var mesh: ArrayMesh
		var shape: Shape3D
		if JsonData.get_string(entry, "kind", type_context) == "rock":
			mesh = _build_rock_mesh(size, entry, type_context)
			shape = mesh.create_convex_shape(true, true)
		else:
			var box := BoxMesh.new()
			box.size = size
			mesh = _box_to_array_mesh(box)
			var box_shape := BoxShape3D.new()
			box_shape.size = size
			shape = box_shape
		mesh.surface_set_material(0, material)
		parent.add_child(_build_multimesh(type_id, mesh, transforms))
		parent.add_child(_build_colliders(type_id, shape, transforms, JsonData.get_string(entry, "surface", type_context)))


## Altitude du sol sous l'empreinte d'un obstacle : le plus bas de cinq points, pour que l'obstacle ne flotte jamais.
static func _lowest_ground(relief: CollinesRelief, ground: Vector2, footprint: float) -> float:
	var lowest: float = relief.height_at(ground.x, ground.y)
	var reach: float = footprint * 0.7
	lowest = minf(lowest, relief.height_at(ground.x + reach, ground.y))
	lowest = minf(lowest, relief.height_at(ground.x - reach, ground.y))
	lowest = minf(lowest, relief.height_at(ground.x, ground.y + reach))
	lowest = minf(lowest, relief.height_at(ground.x, ground.y - reach))
	return lowest


static func _obstacle_material(entry: Dictionary, cache: Dictionary[String, StandardMaterial3D], context: String) -> StandardMaterial3D:
	var texture_id: String = JsonData.get_string(entry, "texture", context)
	var tint: Color = JsonData.get_color(entry, "tint", context)
	var uv_scale: float = JsonData.get_float(entry, "uv_scale", context)
	var key: String = "%s|%s|%.3f" % [texture_id, tint.to_html(true), uv_scale]
	if cache.has(key):
		return cache[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.albedo_texture = _load_texture(texture_id, "diff")
	material.normal_enabled = true
	material.normal_texture = _load_texture(texture_id, "nor_gl")
	material.roughness_texture = _load_texture(texture_id, "rough")
	# Projection triplanaire dans le repère de l'objet : pas de coordonnées de texture à déformer sur les rochers.
	material.uv1_triplanar = true
	material.uv1_scale = Vector3(uv_scale, uv_scale, uv_scale)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	cache[key] = material
	return material


static func _load_texture(texture_id: String, map_name: String) -> Texture2D:
	var path: String = "%s/%s/%s_%s.jpg" % [POLYHAVEN_DIR, texture_id, texture_id, map_name]
	if not ResourceLoader.exists(path):
		push_error("CollinesBuilder : texture absente %s. Lancez Scripts/Pipeline/importer-ressources.ps1." % path)
		return null
	var texture: Texture2D = load(path)
	if texture == null:
		push_error("CollinesBuilder : %s n'est pas une texture." % path)
	return texture


## Rocher taillé : sphère à peu de facettes, déformée par un bruit 3D de graine fixe, fond aplati pour poser au sol.
static func _build_rock_mesh(size: Vector3, entry: Dictionary, context: String) -> ArrayMesh:
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = ROCK_RADIAL_SEGMENTS
	sphere.rings = ROCK_RINGS
	var arrays: Array = sphere.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var noise := FastNoiseLite.new()
	noise.seed = JsonData.get_int(entry, "seed", context)
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	var amount: float = JsonData.get_float(entry, "roughness_amount", context)
	var floor_y: float = -size.y * 0.5
	for i: int in vertices.size():
		var unit: Vector3 = vertices[i] * 2.0
		var scale_factor: float = 1.0 + amount * noise.get_noise_3dv(unit * ROCK_NOISE_FREQUENCY)
		var displaced: Vector3 = unit * size * 0.5 * scale_factor
		displaced.y = maxf(displaced.y, floor_y)
		vertices[i] = displaced
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var surface := SurfaceTool.new()
	surface.create_from_arrays(arrays)
	surface.deindex()
	surface.generate_normals()
	surface.generate_tangents()
	return surface.commit()


static func _box_to_array_mesh(box: BoxMesh) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, box.get_mesh_arrays())
	return mesh


static func _build_multimesh(type_id: String, mesh: Mesh, transforms: Array) -> CollinesInstances:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	var buffer := PackedFloat32Array()
	buffer.resize(transforms.size() * CollinesInstances.FLOATS_PER_INSTANCE)
	for i: int in transforms.size():
		CollinesInstances.write_transform(buffer, i, transforms[i])
	var instance := CollinesInstances.new()
	instance.name = "Visuel_" + type_id
	instance.multimesh = multimesh
	instance.transform_buffer = buffer
	return instance


## Un seul corps statique par type (couche 1) : toutes ses formes de collision partagent la même ressource.
static func _build_colliders(type_id: String, shape: Shape3D, transforms: Array, surface: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Collisions_" + type_id
	body.collision_layer = WORLD_LAYER_MASK
	body.collision_mask = 0
	body.set_meta(&"surface", surface)
	for i: int in transforms.size():
		var collision := CollisionShape3D.new()
		collision.name = "c%d" % i
		collision.shape = shape
		collision.transform = transforms[i]
		body.add_child(collision)
	return body


static func _assign_owner(node: Node, owner: Node) -> void:
	for child: Node in node.get_children():
		child.owner = owner
		_assign_owner(child, owner)
