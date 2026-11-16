class_name DesertCellProvider
extends RefCounted
## Fournisseur de cellules du désert pour le streaming : terrain (DesertTerrainCell) et végétation (MultiMesh par
## espèce). build_cell() est appelée depuis un fil de travail : elle ne touche jamais à l'arbre de scène, et
## les maillages et matériaux partagés sont préparés une fois, avant le premier chargement.

const SPECIES_SEED_SALT: int = 7919
const COVER_PATH: String = "res://data/desert/ground_cover.json"

var _terrain: DesertTerrainCell
var _field: DesertHeightfield
var _scatter: VegetationScatter
var _seed: int
var _meshes: Dictionary = {}  # id d'espèce -> Array de { "mesh": Mesh, "end_m": float } (niveaux de détail)
var _settings: Dictionary = {}  # id d'espèce -> réglages d'affichage
## Cylindre partagé et dimensions par espèce qui bloque le joueur (palmier) ; échelle appliquée par instance.
var _collision_radius: Dictionary = {}  # id d'espèce -> rayon (m)
var _collision_height: Dictionary = {}  # id d'espèce -> hauteur (m)
## Début d'affichage (m) et marge de fondu par espèce : couches lointaines du couvert du sol (absent = dès 0 m).
var _begin_range: Dictionary = {}  # id d'espèce -> distance (m)
var _begin_margin: Dictionary = {}  # id d'espèce -> marge (m)
## Grille des touffes pour les sons de pas : taille des cases (0 = désactivée) et espèces versées dans la grille.
var _cover_cell_m: float = 0.0
var _cover_species: Array[StringName] = []
## Palmeraie de l'oasis (nulle si la carte n'en a pas) : parcelles, murets, séguias, arbres et cultures de la cellule.
var _palmeraie: PalmeraieCells


func _init(
	terrain: DesertTerrainCell,
	field: DesertHeightfield,
	scatter: VegetationScatter,
	meshes: Dictionary,
	foliage: Dictionary,
	world_seed: int,
	cover_settings: Dictionary = {},
	palmeraie: PalmeraieCells = null
) -> void:
	_terrain = terrain
	_field = field
	_scatter = scatter
	_meshes = meshes
	_seed = world_seed
	for id: StringName in foliage.keys():
		var spec: Dictionary = foliage[id]
		if spec.has("collision"):
			var collision: Dictionary = JsonData.get_dictionary(spec, "collision", "foliage.json > %s" % id)
			_collision_radius[id] = JsonData.get_float(collision, "radius_m", "foliage.json > %s > collision" % id)
			_collision_height[id] = JsonData.get_float(collision, "height_m", "foliage.json > %s > collision" % id)
		if spec.has("visibility_range_begin_m"):
			_begin_range[id] = JsonData.get_float(spec, "visibility_range_begin_m", "foliage.json > %s" % id)
			_begin_margin[id] = JsonData.get_float(spec, "visibility_begin_margin_m", "foliage.json > %s" % id)
	if not cover_settings.is_empty():
		var grid: Dictionary = JsonData.get_dictionary(cover_settings, "grid", COVER_PATH)
		_cover_cell_m = JsonData.get_float(grid, "cell_m", COVER_PATH)
		for species_id: Variant in JsonData.get_array(grid, "species", COVER_PATH):
			_cover_species.append(StringName(str(species_id)))
	var all: Dictionary = _scatter.get_species_settings()
	for species: Variant in all.keys():
		_settings[StringName(str(species))] = all[species]
	_palmeraie = palmeraie
	if _palmeraie != null:
		var display: Dictionary = _palmeraie.species_display()
		for species_id: Variant in display.keys():
			_settings[species_id] = display[species_id]


func build_cell(cell: Vector2i) -> Node3D:
	var body: Node3D = _terrain.build_cell(cell)
	if body == null:
		return null
	var result: Dictionary = _scatter.scatter(cell, _field, _seed)
	if _palmeraie != null:
		_merge_palmeraie(body, cell, result)
	_attach_cover_grid(body, cell, result)
	for species: Variant in result.keys():
		var transforms: PackedFloat32Array = result[species]
		var id := StringName(str(species))
		if transforms.is_empty() or not _meshes.has(id):
			continue
		for instance: DesertFoliageInstance in _build_instances(id, transforms, body.position):
			body.add_child(instance)
		if _collision_radius.has(id):
			_add_trunk_collisions(body as CollisionObject3D, id, transforms)
	return body


## Palmeraie : la végétation générale est retirée des cultures, puis les arbres, palmiers et touffes du plan s'ajoutent aux
## transformées de la cellule (mêmes espèces et mêmes niveaux de détail) ; murets, séguias, eau et sol cultivé sont du décor.
func _merge_palmeraie(body: Node3D, cell: Vector2i, result: Dictionary) -> void:
	_palmeraie.filter_scatter(cell, result)
	var added: Dictionary = _palmeraie.build_transforms(cell)
	for species: Variant in added.keys():
		var extra: PackedFloat32Array = added[species]
		var current: PackedFloat32Array = result.get(species, PackedFloat32Array())
		current.append_array(extra)
		result[species] = current
	_palmeraie.add_decor(cell, body)


## Grille des touffes de la cellule (sons de pas), construite ici sur le fil de travail et gardée en métadonnée.
func _attach_cover_grid(body: Node3D, cell: Vector2i, result: Dictionary) -> void:
	if _cover_cell_m <= 0.0:
		return
	var sources: Array[PackedFloat32Array] = []
	for id: StringName in _cover_species:
		var transforms: PackedFloat32Array = result.get(String(id), PackedFloat32Array())
		if not transforms.is_empty():
			sources.append(transforms)
	if sources.is_empty():
		return
	var origin_x: float = -_field.half_extent + float(cell.x) * _field.cell_size
	var origin_z: float = -_field.half_extent + float(cell.y) * _field.cell_size
	body.set_meta(GroundCoverQuery.GRID_META, GroundCoverGrid.build(origin_x, origin_z, _field.cell_size, _cover_cell_m, sources))


## Un MultiMesh par niveau de détail de l'espèce, tous alimentés par les mêmes transformées (tableau partagé, copié à
## l'écriture). Chaque niveau n'est dessiné que dans sa plage de distance, avec un fondu de part et d'autre.
func _build_instances(id: StringName, transforms: PackedFloat32Array, origin: Vector3) -> Array[DesertFoliageInstance]:
	var settings: Dictionary = _settings.get(id, {})
	var margin: float = float(settings.get("visibility_fade_margin", 0.0))
	var casts_shadows: bool = bool(settings.get("cast_shadows", false))
	var levels: Array = _meshes[id]
	var instances: Array[DesertFoliageInstance] = []
	var previous_end: float = 0.0
	for k: int in levels.size():
		var level: Dictionary = levels[k]
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = level["mesh"]
		var instance := DesertFoliageInstance.new()
		instance.transform_buffer = transforms
		instance.name = String(id) if levels.size() == 1 else "%s_lod%d" % [id, k]
		instance.multimesh = multimesh
		# Les transformées sont en coordonnées du monde ; la cellule est posée à son coin : on compense.
		instance.position = -origin
		var end_m: float = float(level["end_m"])
		instance.visibility_range_end = end_m if end_m > 0.0 else float(settings.get("visibility_range_end", 0.0))
		instance.visibility_range_end_margin = margin
		if k > 0:
			instance.visibility_range_begin = maxf(previous_end - margin, 0.0)
			instance.visibility_range_begin_margin = margin
		elif _begin_range.has(id):
			# Couche lointaine du couvert du sol : n'apparaît qu'au-delà de la couche proche.
			instance.visibility_range_begin = float(_begin_range[id])
			instance.visibility_range_begin_margin = float(_begin_margin.get(id, 0.0))
		instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		# Le dernier niveau d'une espèce à plusieurs niveaux est l'imposteur : il ne projette pas d'ombre.
		var is_imposter: bool = levels.size() > 1 and k == levels.size() - 1
		instance.cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			if casts_shadows and not is_imposter
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		)
		previous_end = end_m
		instances.append(instance)
	return instances


## Un cylindre par instance, sur le corps statique de la cellule (sans nœud supplémentaire). Les formes
## sont créées sur ce fil de travail, comme la collision du terrain, avant l'entrée dans l'arbre.
func _add_trunk_collisions(body: CollisionObject3D, id: StringName, transforms: PackedFloat32Array) -> void:
	var radius: float = _collision_radius[id]
	var height: float = _collision_height[id]
	var shapes: Dictionary[int, CylinderShape3D] = {}  # échelle arrondie au centième -> forme partagée
	var origin: Vector3 = (body as Node3D).position
	var count: int = transforms.size() / DesertFoliageInstance.FLOATS_PER_INSTANCE
	for i: int in count:
		var k: int = i * DesertFoliageInstance.FLOATS_PER_INSTANCE
		# Échelle : longueur de l'axe X de la base (colonne 0 : éléments 0, 4, 8).
		var scale: float = Vector3(transforms[k], transforms[k + 4], transforms[k + 8]).length()
		var key: int = roundi(scale * 100.0)
		var shape: CylinderShape3D = shapes.get(key)
		if shape == null:
			shape = CylinderShape3D.new()
			shape.radius = radius * float(key) / 100.0
			shape.height = height * float(key) / 100.0
			shapes[key] = shape
		var position := Vector3(transforms[k + 3], transforms[k + 7] + shape.height * 0.5, transforms[k + 11]) - origin
		var owner_id: int = body.create_shape_owner(body)
		body.shape_owner_add_shape(owner_id, shape)
		body.shape_owner_set_transform(owner_id, Transform3D(Basis.IDENTITY, position))
