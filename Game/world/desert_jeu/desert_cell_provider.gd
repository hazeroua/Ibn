class_name DesertCellProvider
extends RefCounted
## Fournisseur de cellules du désert pour le streaming : terrain (DesertTerrainCell) et végétation (MultiMesh par
## espèce). build_cell() est appelée depuis un fil de travail : elle ne touche jamais à l'arbre de scène, et
## les maillages et matériaux partagés sont préparés une fois, avant le premier chargement.

const SPECIES_SEED_SALT: int = 7919

var _terrain: DesertTerrainCell
var _field: DesertHeightfield
var _scatter: VegetationScatter
var _seed: int
var _meshes: Dictionary = {}  # id d'espèce -> Mesh
var _settings: Dictionary = {}  # id d'espèce -> réglages d'affichage


func _init(terrain: DesertTerrainCell, field: DesertHeightfield, scatter: VegetationScatter, meshes: Dictionary, world_seed: int) -> void:
	_terrain = terrain
	_field = field
	_scatter = scatter
	_meshes = meshes
	_seed = world_seed
	var all: Dictionary = _scatter.get_species_settings()
	for species: Variant in all.keys():
		_settings[StringName(str(species))] = all[species]


func build_cell(cell: Vector2i) -> Node3D:
	var body: Node3D = _terrain.build_cell(cell)
	if body == null:
		return null
	var result: Dictionary = _scatter.scatter(cell, _field, _seed)
	for species: Variant in result.keys():
		var transforms: PackedFloat32Array = result[species]
		var id := StringName(str(species))
		if transforms.is_empty() or not _meshes.has(id):
			continue
		body.add_child(_build_multimesh(id, transforms, body.position))
	return body


func _build_multimesh(id: StringName, transforms: PackedFloat32Array, origin: Vector3) -> DesertFoliageInstance:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = _meshes[id]
	var instance := DesertFoliageInstance.new()
	instance.transform_buffer = transforms
	instance.name = String(id)
	instance.multimesh = multimesh
	# Les transformées sont en coordonnées du monde ; la cellule est posée à son coin : on compense.
	instance.position = -origin
	var settings: Dictionary = _settings.get(id, {})
	instance.visibility_range_end = float(settings.get("visibility_range_end", 0.0))
	instance.visibility_range_end_margin = float(settings.get("visibility_fade_margin", 0.0))
	instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	instance.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if bool(settings.get("cast_shadows", false))
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	return instance
