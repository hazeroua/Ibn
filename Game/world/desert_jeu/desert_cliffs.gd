class_name DesertCliffs
extends RefCounted
## Falaises des gorges d'oued : blocs de roche (modèles falaise_a/b/c, trois niveaux de détail) posés sur les parois, avec
## collision convexe simplifiée. Les positions sont calculées une seule fois au chargement le long du tracé de chaque
## gorge (WadiNetwork.gorge_frames) puis rangées par cellule de streaming : add_to_body() ne fait ensuite que lire.
##
## Pire cas : 16 oueds avec gorge, quelques centaines de blocs par cellule, aucune création d'objet par image.
## Un MultiMesh par modèle et par niveau de détail et par cellule (au plus 9) ; les formes de collision sont créées par
## cellule, une par taille de bloc. add_to_body() est appelée sur un fil de fond : elle ne touche pas à l'arbre de scène
## (les tampons des MultiMesh sont remplis à l'entrée dans l'arbre, voir DesertFoliageInstance).

const CONTEXT: String = "desert.json > wadis > gorge > cliffs"
const FLOATS_PER_INSTANCE: int = 12
const LOD_COUNT: int = 3
## Hauteur de décalage sous le point le plus bas de l'emprise du bloc (le pied enterré du modèle fait le reste).
const SINK_M: float = 0.2

## Par cellule (clé = ligne * côté + colonne) : un dictionnaire indice de modèle -> transformées (12 réels par bloc).
var _per_cell: Dictionary[int, Dictionary] = {}
var _cells_per_side: int = 16
var _cell_size: float = 250.0
var _half_extent: float = 2000.0
## Par gorge : indice de modèle -> maillages des trois niveaux de détail.
var _meshes: Array[Array] = []
var _hulls: Array[PackedVector3Array] = []
var _lod_ranges: PackedFloat64Array = PackedFloat64Array()
var _block_count: int = 0


## Calcule tous les blocs de toutes les gorges. meshes : maillages de foliage.json (« falaise_a_lod0 », …).
## Renvoie null si les données ou les maillages sont invalides.
static func build(field: DesertHeightfield, meshes: Dictionary) -> DesertCliffs:
	var cliffs := DesertCliffs.new()
	cliffs._cells_per_side = field.cells_per_side
	cliffs._cell_size = field.cell_size
	cliffs._half_extent = field.half_extent
	for gorge: int in field.features.wadis.gorge_count():
		if not cliffs._place_gorge(field, meshes, gorge):
			return null
	return cliffs


func block_count() -> int:
	return _block_count


func _place_gorge(field: DesertHeightfield, meshes: Dictionary, gorge: int) -> bool:
	var config: Dictionary = JsonData.get_dictionary(field.features.wadis.gorge_config(gorge), "cliffs", CONTEXT)
	var models: Array = JsonData.get_array(config, "models", CONTEXT)
	var rows: Array = JsonData.get_array(config, "rows", CONTEXT)
	var ranges: Array = JsonData.get_array(config, "lod_ranges_m", CONTEXT)
	var spacing: float = JsonData.get_float(config, "spacing_m", CONTEXT)
	var jitter: float = JsonData.get_float(config, "jitter_m", CONTEXT)
	var scale_min: float = JsonData.get_float(config, "scale_min", CONTEXT)
	var scale_max: float = JsonData.get_float(config, "scale_max", CONTEXT)
	var scale_step: float = JsonData.get_float(config, "scale_step", CONTEXT)
	var footprint: float = JsonData.get_float(config, "footprint_radius_m", CONTEXT)
	if (
		models.is_empty()
		or rows.is_empty()
		or ranges.size() != LOD_COUNT
		or spacing <= 0.0
		or jitter < 0.0
		or scale_min <= 0.0
		or scale_max < scale_min
		or scale_step <= 0.0
		or footprint <= 0.0
	):
		push_error("DesertCliffs : réglages de falaises incohérents (%s)." % CONTEXT)
		return false
	_lod_ranges = PackedFloat64Array()
	for value: Variant in ranges:
		_lod_ranges.append(float(value))
	if not _load_models(models, meshes):
		return false
	var rng := RandomNumberGenerator.new()
	rng.seed = JsonData.get_int(config, "seed", CONTEXT)
	var frames: PackedFloat64Array = field.features.wadis.gorge_frames(gorge, spacing)
	for base: int in range(0, frames.size(), WadiNetwork.FRAME_STRIDE):
		var center := Vector2(frames[base], frames[base + 1])
		var tangent := Vector2(frames[base + 2], frames[base + 3])
		var normal := Vector2(-tangent.y, tangent.x)
		var wall_start: float = frames[base + 4]
		var wall_width: float = frames[base + 5]
		for side: int in [-1, 1]:
			for row: Variant in rows:
				var offset: float = wall_start + wall_width * float(row)
				var position: Vector2 = center + normal * float(side) * offset + tangent * rng.randf_range(-jitter, jitter)
				var size: float = snappedf(rng.randf_range(scale_min, scale_max), scale_step)
				_add_block(field, position, size, footprint, rng.randi_range(0, models.size() - 1), rng.randf() * TAU)
	return true


func _load_models(models: Array, meshes: Dictionary) -> bool:
	_meshes.clear()
	_hulls.clear()
	for model: Variant in models:
		var lods: Array = []
		for lod: int in LOD_COUNT:
			var id := StringName("%s_lod%d" % [str(model), lod])
			if not meshes.has(id):
				push_error("DesertCliffs : maillage « %s » absent de foliage.json." % id)
				return false
			lods.append(meshes[id])
		var shape: ConvexPolygonShape3D = (lods[LOD_COUNT - 1] as Mesh).create_convex_shape(true, true)
		if shape == null or shape.points.is_empty():
			push_error("DesertCliffs : forme convexe impossible pour « %s »." % str(model))
			return false
		_meshes.append(lods)
		_hulls.append(shape.points)
	return true


func _add_block(field: DesertHeightfield, position: Vector2, size: float, footprint: float, model: int, yaw: float) -> void:
	var radius: float = footprint * size
	var low: float = field.height_at(position.x, position.y)
	for corner: Vector2 in [Vector2(radius, 0.0), Vector2(-radius, 0.0), Vector2(0.0, radius), Vector2(0.0, -radius)]:
		low = minf(low, field.height_at(position.x + corner.x, position.y + corner.y))
	var column: int = floori((position.x + _half_extent) / _cell_size)
	var row: int = floori((position.y + _half_extent) / _cell_size)
	if column < 0 or row < 0 or column >= _cells_per_side or row >= _cells_per_side:
		return
	var key: int = row * _cells_per_side + column
	var by_model: Dictionary = _per_cell.get(key, {})
	var transforms: PackedFloat32Array = by_model.get(model, PackedFloat32Array())
	var basis: Basis = Basis(Vector3.UP, yaw).scaled(Vector3(size, size, size))
	transforms.append_array(
		PackedFloat32Array(
			[
				basis.x.x,
				basis.y.x,
				basis.z.x,
				position.x,
				basis.x.y,
				basis.y.y,
				basis.z.y,
				low - SINK_M,
				basis.x.z,
				basis.y.z,
				basis.z.z,
				position.y
			]
		)
	)
	by_model[model] = transforms
	_per_cell[key] = by_model
	_block_count += 1


## Ajoute à la cellule (déjà positionnée) les blocs de falaise : MultiMesh par niveau de détail et collisions convexes.
func add_to_body(body: CollisionObject3D, cell: Vector2i) -> void:
	var by_model: Dictionary = _per_cell.get(cell.y * _cells_per_side + cell.x, {})
	if by_model.is_empty():
		return
	var shapes: Dictionary[int, ConvexPolygonShape3D] = {}
	for model: int in by_model.keys():
		var transforms: PackedFloat32Array = by_model[model]
		var begin: float = 0.0
		for lod: int in LOD_COUNT:
			body.add_child(_build_instance(model, lod, transforms, body.position, begin))
			begin = _lod_ranges[lod]
		for k: int in range(0, transforms.size(), FLOATS_PER_INSTANCE):
			var basis := Basis(
				Vector3(transforms[k], transforms[k + 4], transforms[k + 8]),
				Vector3(transforms[k + 1], transforms[k + 5], transforms[k + 9]),
				Vector3(transforms[k + 2], transforms[k + 6], transforms[k + 10])
			)
			var size: float = basis.x.length()
			var shape_key: int = model * 100000 + roundi(size * 100.0)
			var shape: ConvexPolygonShape3D = shapes.get(shape_key)
			if shape == null:
				shape = ConvexPolygonShape3D.new()
				var scaled := PackedVector3Array()
				for point: Vector3 in _hulls[model]:
					scaled.append(point * size)
				shape.points = scaled
				shapes[shape_key] = shape
			var owner_id: int = body.create_shape_owner(body)
			body.shape_owner_add_shape(owner_id, shape)
			var origin := Vector3(transforms[k + 3], transforms[k + 7], transforms[k + 11]) - body.position
			body.shape_owner_set_transform(owner_id, Transform3D(basis.orthonormalized(), origin))


func _build_instance(model: int, lod: int, transforms: PackedFloat32Array, origin: Vector3, begin: float) -> DesertFoliageInstance:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = _meshes[model][lod]
	var instance := DesertFoliageInstance.new()
	instance.transform_buffer = transforms
	instance.name = "Falaise%d_Lod%d" % [model, lod]
	instance.multimesh = multimesh
	instance.position = -origin
	instance.visibility_range_begin = begin
	instance.visibility_range_end = _lod_ranges[lod]
	instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	instance.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON if lod < LOD_COUNT - 1 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	return instance
