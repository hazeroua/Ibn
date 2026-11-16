class_name LandscapeFeatures
extends RefCounted
## Éléments de paysage du désert : plans d'eau (oasis, lac, guelta, chott) et oueds, décrits par desert.json.
##
## Pire cas : 32 plans d'eau et 16 oueds de 64 points ; height_at() est appelée des millions de fois. Chaque élément est
## donc inscrit à la construction dans une grille de cases carrées (125 m pour 4 km) : une requête ne lit qu'une case
## et ne parcourt que les éléments qui l'influencent (en pratique 4 au plus), sans aucune allocation.
## Les distances ne sont exactes qu'à l'intérieur de la portée de chaque élément (rayon + fondu des berges pour un plan
## d'eau, largeur + influence_m pour un oued) ; au-delà elles valent INF, ce qui est la valeur « loin de tout ».

const CONTEXT: String = "desert.json"
const KINDS: Array[StringName] = [&"oasis", &"lac", &"guelta", &"chott"]
const MAX_WATER_BODIES: int = 32
const MAX_WADIS: int = 16
const MAX_WADI_POINTS: int = 64
const GRID_SIDE: int = 32

var water_count: int = 0
var wadi_count: int = 0
var segment_count: int = 0

var _half_extent: float = 2000.0
var _inverse_cell: float = 0.0
## Plans d'eau (tableaux parallèles, indexés comme la liste « water_bodies »).
var _ids: Array[StringName] = []
var _kinds: Array[StringName] = []
var _x: PackedFloat64Array = PackedFloat64Array()
var _z: PackedFloat64Array = PackedFloat64Array()
var _radius: PackedFloat64Array = PackedFloat64Array()
var _floor: PackedFloat64Array = PackedFloat64Array()
var _surface: PackedFloat64Array = PackedFloat64Array()
var _blend: PackedFloat64Array = PackedFloat64Array()
var _reach: PackedFloat64Array = PackedFloat64Array()
## Segments d'oued : extrémités (ax, az, bx, bz), indice de l'oued, demi-largeur, portée.
var _segment: PackedFloat64Array = PackedFloat64Array()
var _segment_wadi: PackedInt32Array = PackedInt32Array()
var _wadi_ids: Array[StringName] = []
var _wadi_half_width: PackedFloat64Array = PackedFloat64Array()
var _wadi_depth: PackedFloat64Array = PackedFloat64Array()
var _wadi_blend: PackedFloat64Array = PackedFloat64Array()
var _wadi_reach: PackedFloat64Array = PackedFloat64Array()
## Une liste d'indices par case de la grille.
var _water_cells: Array[PackedInt32Array] = []
var _segment_cells: Array[PackedInt32Array] = []


## Construit l'index depuis le contenu de desert.json. extra_reach_m élargit la portée des plans d'eau (marge de la
## terre autour de l'eau, lue par surface_weights). Renvoie null si les données sont invalides.
static func from_data(data: Dictionary, half_extent: float, extra_reach_m: float) -> LandscapeFeatures:
	var features := LandscapeFeatures.new()
	features._half_extent = half_extent
	features._inverse_cell = float(GRID_SIDE) / (2.0 * half_extent)
	for i: int in GRID_SIDE * GRID_SIDE:
		features._water_cells.append(PackedInt32Array())
		features._segment_cells.append(PackedInt32Array())
	if not features._load_water(JsonData.get_array(data, "water_bodies", CONTEXT), extra_reach_m):
		return null
	if not features._load_wadis(JsonData.get_array(data, "wadis", CONTEXT)):
		return null
	return features


func _load_water(bodies: Array, extra_reach_m: float) -> bool:
	if bodies.size() > MAX_WATER_BODIES:
		push_error("LandscapeFeatures : %d plans d'eau (maximum %d)." % [bodies.size(), MAX_WATER_BODIES])
		return false
	for entry: Variant in bodies:
		if not entry is Dictionary:
			push_error("LandscapeFeatures : chaque plan d'eau doit être un objet (%s)." % CONTEXT)
			return false
		var body: Dictionary = entry
		var id: String = JsonData.get_string(body, "id", CONTEXT + " > water_bodies")
		var context: String = "%s > water_bodies > %s" % [CONTEXT, id]
		var kind: StringName = StringName(JsonData.get_string(body, "kind", context))
		var center: Vector2 = JsonData.get_vector2(body, "center", context)
		var radius: float = JsonData.get_float(body, "radius_m", context)
		var surface: float = JsonData.get_float(body, "surface_height_m", context)
		var depth: float = JsonData.get_float(body, "depth_m", context)
		var blend: float = JsonData.get_float(body, "bank_blend_m", context)
		if not KINDS.has(kind) or _ids.has(StringName(id)):
			push_error("LandscapeFeatures : type inconnu ou identifiant en double (%s)." % context)
			return false
		if radius <= 0.0 or blend <= 0.0 or depth < 0.0:
			push_error("LandscapeFeatures : rayon, fondu et profondeur incohérents (%s)." % context)
			return false
		var reach: float = radius + maxf(blend, extra_reach_m)
		if absf(center.x) + radius > _half_extent or absf(center.y) + radius > _half_extent:
			push_error("LandscapeFeatures : le plan d'eau sort du désert (%s)." % context)
			return false
		_ids.append(StringName(id))
		_kinds.append(kind)
		_x.append(center.x)
		_z.append(center.y)
		_radius.append(radius)
		_surface.append(surface)
		_floor.append(surface - depth)
		_blend.append(blend)
		_reach.append(reach)
		_register_water(water_count, center.x - reach, center.y - reach, center.x + reach, center.y + reach)
		water_count += 1
	return true


func _load_wadis(wadis: Array) -> bool:
	if wadis.size() > MAX_WADIS:
		push_error("LandscapeFeatures : %d oueds (maximum %d)." % [wadis.size(), MAX_WADIS])
		return false
	for entry: Variant in wadis:
		if not entry is Dictionary:
			push_error("LandscapeFeatures : chaque oued doit être un objet (%s)." % CONTEXT)
			return false
		var wadi: Dictionary = entry
		var id: String = JsonData.get_string(wadi, "id", CONTEXT + " > wadis")
		var context: String = "%s > wadis > %s" % [CONTEXT, id]
		var points: Array = JsonData.get_array(wadi, "points", context)
		var width: float = JsonData.get_float(wadi, "width_m", context)
		var depth: float = JsonData.get_float(wadi, "depth_m", context)
		var blend: float = JsonData.get_float(wadi, "bank_blend_m", context)
		var influence: float = JsonData.get_float(wadi, "influence_m", context)
		if points.size() < 2 or points.size() > MAX_WADI_POINTS or width <= 0.0 or depth < 0.0 or blend <= 0.0 or influence < 0.0:
			push_error("LandscapeFeatures : points (2 à %d), largeur, profondeur ou fondu incohérents (%s)." % [MAX_WADI_POINTS, context])
			return false
		var reach: float = width * 0.5 + blend + influence
		var wadi_index: int = wadi_count
		_wadi_ids.append(StringName(id))
		_wadi_half_width.append(width * 0.5)
		_wadi_depth.append(depth)
		_wadi_blend.append(blend)
		_wadi_reach.append(reach)
		var previous := Vector2.ZERO
		for k: int in points.size():
			var pair: Variant = points[k]
			if not pair is Array or (pair as Array).size() != 2:
				push_error("LandscapeFeatures : un point d'oued est [x, z] (%s)." % context)
				return false
			var point := Vector2(float((pair as Array)[0]), float((pair as Array)[1]))
			if k > 0:
				var index: int = segment_count
				_segment.append(previous.x)
				_segment.append(previous.y)
				_segment.append(point.x)
				_segment.append(point.y)
				_segment_wadi.append(wadi_index)
				_register_segment(
					index,
					minf(previous.x, point.x) - reach,
					minf(previous.y, point.y) - reach,
					maxf(previous.x, point.x) + reach,
					maxf(previous.y, point.y) + reach
				)
				segment_count += 1
			previous = point
		wadi_count += 1
	return true


func _cell_range(low: float, high: float) -> Vector2i:
	var first: int = clampi(floori((low + _half_extent) * _inverse_cell), 0, GRID_SIDE - 1)
	var last: int = clampi(floori((high + _half_extent) * _inverse_cell), 0, GRID_SIDE - 1)
	return Vector2i(first, last)


func _register_water(index: int, x0: float, z0: float, x1: float, z1: float) -> void:
	var columns: Vector2i = _cell_range(x0, x1)
	var rows: Vector2i = _cell_range(z0, z1)
	for row: int in range(rows.x, rows.y + 1):
		for column: int in range(columns.x, columns.y + 1):
			_water_cells[row * GRID_SIDE + column].append(index)


func _register_segment(index: int, x0: float, z0: float, x1: float, z1: float) -> void:
	var columns: Vector2i = _cell_range(x0, x1)
	var rows: Vector2i = _cell_range(z0, z1)
	for row: int in range(rows.x, rows.y + 1):
		for column: int in range(columns.x, columns.y + 1):
			_segment_cells[row * GRID_SIDE + column].append(index)


func _cell_index(x: float, z: float) -> int:
	var column: int = clampi(floori((x + _half_extent) * _inverse_cell), 0, GRID_SIDE - 1)
	var row: int = clampi(floori((z + _half_extent) * _inverse_cell), 0, GRID_SIDE - 1)
	return row * GRID_SIDE + column


## Applique le relief des plans d'eau à la hauteur naturelle du sol : le fond du plan d'eau au centre, remonté
## en douceur (smoothstep) jusqu'au sol naturel sur bank_blend_m au-delà du rayon. O(éléments de la case).
func carve(x: float, z: float, natural_height: float) -> float:
	var height: float = natural_height
	for index: int in _water_cells[_cell_index(x, z)]:
		var dx: float = x - _x[index]
		var dz: float = z - _z[index]
		var radius: float = _radius[index]
		var away: float = smoothstep(radius, radius + _blend[index], sqrt(dx * dx + dz * dz))
		height = lerpf(_floor[index], height, away)
	return height


## 0 loin de l'eau, 1 dans l'eau (rayon du plan d'eau), décroissance douce sur margin_m au-delà. O(éléments de la case).
func shore_weight(x: float, z: float, margin_m: float) -> float:
	var weight: float = 0.0
	for index: int in _water_cells[_cell_index(x, z)]:
		var dx: float = x - _x[index]
		var dz: float = z - _z[index]
		var radius: float = _radius[index]
		weight = maxf(weight, 1.0 - smoothstep(radius, radius + margin_m, sqrt(dx * dx + dz * dz)))
	return weight


## Influence de l'eau : 0 loin, 1 dans l'eau, décroissance sur le fondu des berges.
func water_influence(x: float, z: float) -> float:
	var weight: float = 0.0
	for index: int in _water_cells[_cell_index(x, z)]:
		var dx: float = x - _x[index]
		var dz: float = z - _z[index]
		var radius: float = _radius[index]
		weight = maxf(weight, 1.0 - smoothstep(radius, radius + _blend[index], sqrt(dx * dx + dz * dz)))
	return weight


## Hauteur du fond du plan d'eau qui influence le plus la position (0.0 si aucun : tester water_influence d'abord).
func water_floor_height(x: float, z: float) -> float:
	var best: float = 0.0
	var best_weight: float = 0.0
	for index: int in _water_cells[_cell_index(x, z)]:
		var dx: float = x - _x[index]
		var dz: float = z - _z[index]
		var radius: float = _radius[index]
		var weight: float = 1.0 - smoothstep(radius, radius + _blend[index], sqrt(dx * dx + dz * dz))
		if weight > best_weight:
			best_weight = weight
			best = _floor[index]
	return best


## Hauteur de la surface de l'eau du plan d'eau le plus proche (0.0 si aucun plan d'eau à portée).
func water_surface_height(x: float, z: float) -> float:
	var best: float = 0.0
	var best_distance: float = INF
	for index: int in _water_cells[_cell_index(x, z)]:
		var dx: float = x - _x[index]
		var dz: float = z - _z[index]
		var distance: float = sqrt(dx * dx + dz * dz) - _radius[index]
		if distance < best_distance:
			best_distance = distance
			best = _surface[index]
	return best


## Distance (mètres) à la rive du plan d'eau le plus proche (0 dans l'eau), INF au-delà de sa portée.
func distance_to_water(x: float, z: float) -> float:
	var best: float = INF
	for index: int in _water_cells[_cell_index(x, z)]:
		var dx: float = x - _x[index]
		var dz: float = z - _z[index]
		var distance: float = sqrt(dx * dx + dz * dz)
		if distance <= _reach[index]:
			best = minf(best, maxf(distance - _radius[index], 0.0))
	return best


## Type du plan d'eau le plus proche à portée (&"" si aucun).
func nearest_water_kind(x: float, z: float) -> StringName:
	var best: StringName = &""
	var best_distance: float = INF
	for index: int in _water_cells[_cell_index(x, z)]:
		var dx: float = x - _x[index]
		var dz: float = z - _z[index]
		var distance: float = sqrt(dx * dx + dz * dz)
		if distance <= _reach[index] and distance - _radius[index] < best_distance:
			best_distance = distance - _radius[index]
			best = _kinds[index]
	return best


## Distance (mètres) à l'axe du tracé d'oued le plus proche, INF au-delà de la portée de cet oued.
func distance_to_wadi(x: float, z: float) -> float:
	var best: float = INF
	for index: int in _segment_cells[_cell_index(x, z)]:
		var base: int = index * 4
		var ax: float = _segment[base]
		var az: float = _segment[base + 1]
		var bx: float = _segment[base + 2]
		var bz: float = _segment[base + 3]
		var sx: float = bx - ax
		var sz: float = bz - az
		var length_squared: float = sx * sx + sz * sz
		var t: float = 0.0
		if length_squared > 0.0:
			t = clampf(((x - ax) * sx + (z - az) * sz) / length_squared, 0.0, 1.0)
		var px: float = x - (ax + sx * t)
		var pz: float = z - (az + sz * t)
		var distance: float = sqrt(px * px + pz * pz)
		if distance <= _wadi_reach[_segment_wadi[index]]:
			best = minf(best, distance)
	return best


## Identifiants des plans d'eau (lecture seule, pour les systèmes qui les rendent).
func water_ids() -> Array[StringName]:
	return _ids


func water_kind(index: int) -> StringName:
	return _kinds[index]


func water_center(index: int) -> Vector2:
	return Vector2(_x[index], _z[index])


func water_radius(index: int) -> float:
	return _radius[index]
