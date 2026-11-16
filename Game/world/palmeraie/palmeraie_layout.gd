class_name PalmeraieLayout
extends RefCounted
## Plan de la palmeraie, calculé une seule fois au chargement depuis res://data/desert/palmeraie.json : contour, parcelles
## (subdivision récursive déterministe d'un rectangle tourné, voies de 3 à 6 m entre les parcelles), séguias sur les voies
## principales, bassin de répartition, chadouf, murets (tabia), palmiers le long des séguias et arbres fruitiers des vergers.
## Tout est rangé par cellule de 250 m (clé entière) : la construction d'une cellule ne fait ensuite que lire.
## Pire cas : contour de 16 points, une centaine de parcelles ; chargement en O(parcelles + pièces de voie), sans récursion.
## Les tableaux sont en lecture seule après le chargement : plusieurs fils de streaming peuvent les lire sans verrou.

const CONTEXT: String = "palmeraie.json"
const SETTINGS_PATH: String = "res://data/desert/palmeraie.json"
const WALL_STRIDE: int = 5  # x0, z0, x1, z1, collision (1) ou décor seul (0)
const CANAL_STRIDE: int = 4  # x0, z0, x1, z1
const POINT_STRIDE: int = 4  # x, z, échelle, lacet
const BASIN_STRIDE: int = 4  # x, z, lacet, côté
const KEY_SIDE: int = 64

## Réglages lus dans le fichier (dictionnaires conservés pour la construction des cellules).
var settings: Dictionary = {}
var parcel_count: int = 0
var kind_ids: Array[StringName] = []

var _half_extent: float = 2000.0
var _cell_size: float = 250.0
var _cos: float = 1.0
var _sin: float = 0.0
var _poly: PackedVector2Array = PackedVector2Array()
var _field: DesertHeightfield
var _rng := RandomNumberGenerator.new()

var _pu0: PackedFloat64Array = PackedFloat64Array()
var _pv0: PackedFloat64Array = PackedFloat64Array()
var _pu1: PackedFloat64Array = PackedFloat64Array()
var _pv1: PackedFloat64Array = PackedFloat64Array()
var _pkind: PackedInt32Array = PackedInt32Array()
var _parcel_grid: Dictionary[int, PackedInt32Array] = {}
var _index_cell: float = 16.0

# Nœuds de la subdivision (parents avant enfants).
var _n_u0: PackedFloat64Array = PackedFloat64Array()
var _n_v0: PackedFloat64Array = PackedFloat64Array()
var _n_u1: PackedFloat64Array = PackedFloat64Array()
var _n_v1: PackedFloat64Array = PackedFloat64Array()
var _n_depth: PackedInt32Array = PackedInt32Array()
var _n_axis: PackedInt32Array = PackedInt32Array()  # -1 : feuille ; 0 : coupe en u ; 1 : coupe en v
var _n_cut: PackedFloat64Array = PackedFloat64Array()
var _n_gap: PackedFloat64Array = PackedFloat64Array()

# Voies : segment le long d'un axe local à coordonnée fixe.
var _l_axis: PackedInt32Array = PackedInt32Array()  # axe de la coordonnée fixe : 0 = u fixe, 1 = v fixe
var _l_fixed: PackedFloat64Array = PackedFloat64Array()
var _l_a: PackedFloat64Array = PackedFloat64Array()
var _l_b: PackedFloat64Array = PackedFloat64Array()
var _l_gap: PackedFloat64Array = PackedFloat64Array()
var _l_canal: PackedInt32Array = PackedInt32Array()

# Pièces à répartir par cellule (tableaux plats + cellule de chaque enregistrement).
var _wall_data: PackedFloat32Array = PackedFloat32Array()
var _wall_cell: PackedInt32Array = PackedInt32Array()
var _canal_data: PackedFloat32Array = PackedFloat32Array()
var _canal_cell: PackedInt32Array = PackedInt32Array()
var _point_data: PackedFloat32Array = PackedFloat32Array()
var _point_cell: PackedInt32Array = PackedInt32Array()
var _point_species: PackedInt32Array = PackedInt32Array()
var _species_ids: Array[StringName] = []
var _basin_data: PackedFloat32Array = PackedFloat32Array()
var _basin_cell: PackedInt32Array = PackedInt32Array()
var _parcel_cell: PackedInt32Array = PackedInt32Array()

var _cells: Dictionary[int, PalmeraieCellData] = {}
var _canal_all: PackedFloat32Array = PackedFloat32Array()
var _palm_all: PackedFloat32Array = PackedFloat32Array()
var _contour_min: Vector2 = Vector2.ZERO
var _contour_max: Vector2 = Vector2.ZERO
var _chadouf_clear: Vector2 = Vector2(INF, INF)
var _basin_center: Vector2 = Vector2(INF, INF)


## Données d'une cellule de la palmeraie (lecture seule).
class PalmeraieCellData:
	extends RefCounted
	var parcels: PackedInt32Array = PackedInt32Array()
	var walls: PackedFloat32Array = PackedFloat32Array()
	var canals: PackedFloat32Array = PackedFloat32Array()
	var basins: PackedFloat32Array = PackedFloat32Array()
	var points: Dictionary[StringName, PackedFloat32Array] = {}


## Construit le plan ; null si les données sont invalides. Le relief sert aux tests de pente et d'eau.
static func from_data(data: Dictionary, field: DesertHeightfield) -> PalmeraieLayout:
	var layout := PalmeraieLayout.new()
	if not layout._setup(data, field):
		return null
	layout._build()
	return layout


static func load_default(field: DesertHeightfield) -> PalmeraieLayout:
	return from_data(JsonData.load_dictionary(SETTINGS_PATH), field)


static func cell_key(cell: Vector2i) -> int:
	return cell.y * KEY_SIDE + cell.x


## Données de la cellule, ou null si la palmeraie n'y a rien.
func cell_data(cell: Vector2i) -> PalmeraieCellData:
	return _cells.get(cell_key(cell))


## Vrai si la palmeraie touche la cellule (rectangle englobant du contour, test rapide).
func overlaps_cell(origin_x: float, origin_z: float) -> bool:
	return (
		origin_x + _cell_size >= _contour_min.x
		and origin_x <= _contour_max.x
		and origin_z + _cell_size >= _contour_min.y
		and origin_z <= _contour_max.y
	)


## Limites locales (u0, v0, u1, v1) d'une parcelle.
func parcel_bounds(index: int) -> PackedFloat64Array:
	return PackedFloat64Array([_pu0[index], _pv0[index], _pu1[index], _pv1[index]])


## Repère local de la palmeraie vers le monde.
func to_world(u: float, v: float) -> Vector2:
	return _to_world(u, v)


## Dans le contour de la palmeraie ?
func inside_contour(x: float, z: float) -> bool:
	return Geometry2D.is_point_in_polygon(Vector2(x, z), _poly)


## Coins monde d'une parcelle, dans l'ordre (u0,v0), (u1,v0), (u1,v1), (u0,v1).
func parcel_corners(index: int) -> PackedVector2Array:
	return _rect_world(_pu0[index], _pv0[index], _pu1[index], _pv1[index])


func parcel_kind(index: int) -> StringName:
	return kind_ids[_pkind[index]]


## Indice de la parcelle qui contient le point du monde, -1 si aucun.
func parcel_at(x: float, z: float) -> int:
	return _parcel_at_local(x * _cos + z * _sin, -x * _sin + z * _cos)


## Distance en mètres à la séguia la plus proche (INF s'il n'y en a pas). Recherche linéaire : réservé aux tests et aux outils.
func distance_to_canal(x: float, z: float) -> float:
	var best: float = INF
	var point := Vector2(x, z)
	for i: int in _canal_all.size() / CANAL_STRIDE:
		var k: int = i * CANAL_STRIDE
		var a := Vector2(_canal_all[k], _canal_all[k + 1])
		var b := Vector2(_canal_all[k + 2], _canal_all[k + 3])
		best = minf(best, point.distance_to(Geometry2D.get_closest_point_to_segment(point, a, b)))
	return best


## Positions des palmiers (x, z, échelle, lacet) de toute la palmeraie.
func palm_points() -> PackedFloat32Array:
	return _palm_all


func _setup(data: Dictionary, field: DesertHeightfield) -> bool:
	if data.is_empty() or field == null:
		return false
	settings = data
	_field = field
	_half_extent = field.half_extent
	_cell_size = field.cell_size
	var angle: float = deg_to_rad(JsonData.get_float(data, "frame_angle_deg", CONTEXT))
	_cos = cos(angle)
	_sin = sin(angle)
	var contour: Array = JsonData.get_array(data, "contour", CONTEXT)
	if contour.size() < 3:
		push_error("PalmeraieLayout : le contour doit avoir au moins 3 points (%s)." % CONTEXT)
		return false
	_contour_min = Vector2(INF, INF)
	_contour_max = Vector2(-INF, -INF)
	for entry: Variant in contour:
		if not entry is Array or (entry as Array).size() != 2:
			push_error("PalmeraieLayout : point de contour invalide (%s)." % CONTEXT)
			return false
		var pair: Array = entry
		var point := Vector2(float(pair[0]), float(pair[1]))
		_poly.append(point)
		_contour_min = _contour_min.min(point)
		_contour_max = _contour_max.max(point)
	var kinds: Array = JsonData.get_array(data, "kinds", CONTEXT)
	if kinds.is_empty():
		push_error("PalmeraieLayout : aucune culture (%s)." % CONTEXT)
		return false
	for entry: Variant in kinds:
		kind_ids.append(StringName(JsonData.get_string(entry as Dictionary, "id", CONTEXT)))
	var parcel: Dictionary = JsonData.get_dictionary(data, "parcel", CONTEXT)
	_index_cell = JsonData.get_float(parcel, "index_cell_m", CONTEXT)
	_rng.seed = JsonData.get_int(data, "seed", CONTEXT)
	return true


func _build() -> void:
	_subdivide()
	_assign_kinds()
	_index_parcels()
	_build_lanes()
	_place_basin_and_feeder()
	_build_walls()
	_place_palms()
	_place_orchards()
	_distribute()


# --- Repères ---------------------------------------------------------------------------------------------------------


func _to_world(u: float, v: float) -> Vector2:
	return Vector2(u * _cos - v * _sin, u * _sin + v * _cos)


func _rect_world(u0: float, v0: float, u1: float, v1: float) -> PackedVector2Array:
	return PackedVector2Array([_to_world(u0, v0), _to_world(u1, v0), _to_world(u1, v1), _to_world(u0, v1)])


func _cell_of(x: float, z: float) -> int:
	var cx: int = clampi(floori((x + _half_extent) / _cell_size), 0, _field.cells_per_side - 1)
	var cz: int = clampi(floori((z + _half_extent) / _cell_size), 0, _field.cells_per_side - 1)
	return cz * KEY_SIDE + cx


# --- Subdivision en parcelles ------------------------------------------------------------------------------------------


func _subdivide() -> void:
	var parcel: Dictionary = JsonData.get_dictionary(settings, "parcel", CONTEXT)
	var lanes: Dictionary = JsonData.get_dictionary(settings, "lanes", CONTEXT)
	var min_m: float = JsonData.get_float(parcel, "min_m", CONTEXT)
	var max_m: float = JsonData.get_float(parcel, "max_m", CONTEXT)
	var jitter: float = JsonData.get_float(parcel, "split_jitter", CONTEXT)
	var root_fraction: float = JsonData.get_float(parcel, "root_split_fraction", CONTEXT)
	var canal_levels: int = JsonData.get_int(lanes, "canal_levels", CONTEXT)
	var canal_gap: float = JsonData.get_float(lanes, "canal_lane_m", CONTEXT)
	var path_gap: float = JsonData.get_float(lanes, "path_m", CONTEXT)
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for point: Vector2 in _poly:
		var u: float = point.x * _cos + point.y * _sin
		var v: float = -point.x * _sin + point.y * _cos
		low = low.min(Vector2(u, v))
		high = high.max(Vector2(u, v))
	_add_node(low.x, low.y, high.x, high.y, 0)
	var stack: Array[int] = [0]
	while not stack.is_empty():
		var node: int = stack.pop_back()
		var u0: float = _n_u0[node]
		var v0: float = _n_v0[node]
		var u1: float = _n_u1[node]
		var v1: float = _n_v1[node]
		var width: float = u1 - u0
		var height: float = v1 - v0
		var axis: int = 0 if width >= height else 1
		var length: float = maxf(width, height)
		var depth: int = _n_depth[node]
		var gap: float = canal_gap if depth < canal_levels else path_gap
		if length <= max_m or length < 2.0 * min_m + gap:
			continue
		var margin: float = min_m + gap * 0.5
		var fraction: float = root_fraction if depth == 0 else 0.5 + _rng.randf_range(-jitter, jitter)
		var cut: float = clampf(length * fraction, margin, length - margin)
		_n_axis[node] = axis
		_n_gap[node] = gap
		var start: float = u0 if axis == 0 else v0
		_n_cut[node] = start + cut
		var first: int
		var second: int
		if axis == 0:
			first = _add_node(u0, v0, start + cut - gap * 0.5, v1, depth + 1)
			second = _add_node(start + cut + gap * 0.5, v0, u1, v1, depth + 1)
		else:
			first = _add_node(u0, v0, u1, start + cut - gap * 0.5, depth + 1)
			second = _add_node(u0, start + cut + gap * 0.5, u1, v1, depth + 1)
		stack.append(second)
		stack.append(first)
	for node: int in _n_axis.size():
		if _n_axis[node] == -1:
			_try_add_parcel(_n_u0[node], _n_v0[node], _n_u1[node], _n_v1[node])
	parcel_count = _pu0.size()


func _add_node(u0: float, v0: float, u1: float, v1: float, depth: int) -> int:
	_n_u0.append(u0)
	_n_v0.append(v0)
	_n_u1.append(u1)
	_n_v1.append(v1)
	_n_depth.append(depth)
	_n_axis.append(-1)
	_n_cut.append(0.0)
	_n_gap.append(0.0)
	return _n_u0.size() - 1


func _try_add_parcel(u0: float, v0: float, u1: float, v1: float) -> void:
	var corners: PackedVector2Array = _rect_world(u0, v0, u1, v1)
	if not _rect_inside_contour(corners):
		return
	var parcel: Dictionary = JsonData.get_dictionary(settings, "parcel", CONTEXT)
	var water_clear: float = JsonData.get_float(parcel, "water_clearance_m", CONTEXT)
	var features: LandscapeFeatures = _field.features
	for index: int in features.water_count:
		var center: Vector2 = features.water_center(index)
		var lu: float = center.x * _cos + center.y * _sin
		var lv: float = -center.x * _sin + center.y * _cos
		var dx: float = lu - clampf(lu, u0, u1)
		var dz: float = lv - clampf(lv, v0, v1)
		if sqrt(dx * dx + dz * dz) < features.water_radius(index) + water_clear:
			return
	var side: int = JsonData.get_int(parcel, "sample_side", CONTEXT)
	var wadi_clear: float = JsonData.get_float(parcel, "wadi_clearance_m", CONTEXT)
	var margin: float = JsonData.get_float(parcel, "water_surface_margin_m", CONTEXT)
	var low: float = INF
	var high: float = -INF
	for i: int in side:
		for j: int in side:
			var world: Vector2 = _to_world(lerpf(u0, u1, float(i) / float(side - 1)), lerpf(v0, v1, float(j) / float(side - 1)))
			var h: float = _field.height_at(world.x, world.y)
			low = minf(low, h)
			high = maxf(high, h)
			if features.distance_to_wadi(world.x, world.y) < wadi_clear:
				return
			if features.distance_to_water(world.x, world.y) < INF and h < features.water_surface_height(world.x, world.y) + margin:
				return
	if high - low > JsonData.get_float(parcel, "max_height_range_m", CONTEXT):
		return
	# Oueds : échantillonnage serré (pas de wadi_sample_m) pour ne pas laisser passer un lit étroit entre deux points.
	var wadi_step: float = JsonData.get_float(parcel, "wadi_sample_m", CONTEXT)
	var columns: int = maxi(1, ceili((u1 - u0) / wadi_step))
	var rows: int = maxi(1, ceili((v1 - v0) / wadi_step))
	for i: int in columns + 1:
		for j: int in rows + 1:
			var point: Vector2 = _to_world(lerpf(u0, u1, float(i) / float(columns)), lerpf(v0, v1, float(j) / float(rows)))
			if features.distance_to_wadi(point.x, point.y) < wadi_clear:
				return
	_pu0.append(u0)
	_pv0.append(v0)
	_pu1.append(u1)
	_pv1.append(v1)


func _rect_inside_contour(corners: PackedVector2Array) -> bool:
	for corner: Vector2 in corners:
		if not Geometry2D.is_point_in_polygon(corner, _poly):
			return false
	for i: int in 4:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		for j: int in _poly.size():
			if Geometry2D.segment_intersects_segment(a, b, _poly[j], _poly[(j + 1) % _poly.size()]) != null:
				return false
	return true


## Répartit les cultures selon leurs proportions (quotas exacts, plus fort reste), dans un ordre mélangé par la graine.
func _assign_kinds() -> void:
	var kinds: Array = JsonData.get_array(settings, "kinds", CONTEXT)
	var count: int = parcel_count
	var quotas: PackedInt32Array = PackedInt32Array()
	var remainders: PackedFloat64Array = PackedFloat64Array()
	var total: float = 0.0
	for entry: Variant in kinds:
		total += JsonData.get_float(entry as Dictionary, "proportion", CONTEXT)
	var assigned: int = 0
	for entry: Variant in kinds:
		var exact: float = JsonData.get_float(entry as Dictionary, "proportion", CONTEXT) / total * float(count)
		quotas.append(floori(exact))
		remainders.append(exact - floorf(exact))
		assigned += floori(exact)
	while assigned < count:
		var best: int = 0
		for k: int in remainders.size():
			if remainders[k] > remainders[best]:
				best = k
		quotas[best] += 1
		remainders[best] = -1.0
		assigned += 1
	var order: PackedInt32Array = PackedInt32Array()
	for k: int in quotas.size():
		for _n: int in quotas[k]:
			order.append(k)
	for i: int in range(order.size() - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var swap: int = order[i]
		order[i] = order[j]
		order[j] = swap
	_pkind = order
	_parcel_cell.resize(count)
	for i: int in count:
		var center: Vector2 = _to_world((_pu0[i] + _pu1[i]) * 0.5, (_pv0[i] + _pv1[i]) * 0.5)
		_parcel_cell[i] = _cell_of(center.x, center.y)


func _grid_key(ix: int, iz: int) -> int:
	return (ix + 4096) * 8192 + (iz + 4096)


func _index_parcels() -> void:
	for i: int in parcel_count:
		var x0: int = floori(_pu0[i] / _index_cell)
		var x1: int = floori(_pu1[i] / _index_cell)
		var z0: int = floori(_pv0[i] / _index_cell)
		var z1: int = floori(_pv1[i] / _index_cell)
		for ix: int in range(x0, x1 + 1):
			for iz: int in range(z0, z1 + 1):
				var key: int = _grid_key(ix, iz)
				var list: PackedInt32Array = _parcel_grid.get(key, PackedInt32Array())
				list.append(i)
				_parcel_grid[key] = list


func _parcel_at_local(u: float, v: float) -> int:
	var list: PackedInt32Array = _parcel_grid.get(_grid_key(floori(u / _index_cell), floori(v / _index_cell)), PackedInt32Array())
	for i: int in list:
		if u >= _pu0[i] and u <= _pu1[i] and v >= _pv0[i] and v <= _pv1[i]:
			return i
	return -1


# --- Voies et séguias ------------------------------------------------------------------------------------------------


func _build_lanes() -> void:
	var lanes: Dictionary = JsonData.get_dictionary(settings, "lanes", CONTEXT)
	var piece: float = JsonData.get_float(lanes, "piece_m", CONTEXT)
	var probe: float = JsonData.get_float(lanes, "probe_m", CONTEXT)
	var canal_levels: int = JsonData.get_int(lanes, "canal_levels", CONTEXT)
	for node: int in _n_axis.size():
		var axis: int = _n_axis[node]
		if axis == -1:
			continue
		var cut: float = _n_cut[node]
		var gap: float = _n_gap[node]
		var start: float = _n_v0[node] if axis == 0 else _n_u0[node]
		var stop: float = _n_v1[node] if axis == 0 else _n_u1[node]
		var count: int = ceili((stop - start) / piece)
		var run_start: float = NAN
		var run_end: float = NAN
		for k: int in count:
			var a: float = start + float(k) * piece
			var b: float = minf(a + piece, stop)
			var mid: float = (a + b) * 0.5
			var offset: float = gap * 0.5 + probe
			var kept: bool = false
			if axis == 0:
				kept = _parcel_at_local(cut - offset, mid) >= 0 or _parcel_at_local(cut + offset, mid) >= 0
			else:
				kept = _parcel_at_local(mid, cut - offset) >= 0 or _parcel_at_local(mid, cut + offset) >= 0
			if kept:
				if is_nan(run_start):
					run_start = a
				run_end = b
			elif not is_nan(run_start):
				_add_lane(axis, cut, run_start, run_end, gap, _n_depth[node] < canal_levels)
				run_start = NAN
		if not is_nan(run_start):
			_add_lane(axis, cut, run_start, run_end, gap, _n_depth[node] < canal_levels)


func _add_lane(axis: int, fixed: float, a: float, b: float, gap: float, canal: bool) -> void:
	_l_axis.append(axis)
	_l_fixed.append(fixed)
	_l_a.append(a)
	_l_b.append(b)
	_l_gap.append(gap)
	_l_canal.append(1 if canal else 0)


## Point local d'une voie : coordonnée t le long de la voie, d de décalage latéral.
func _lane_point(lane: int, t: float, d: float) -> Vector2:
	var fixed: float = _l_fixed[lane] + d
	return _to_world(fixed, t) if _l_axis[lane] == 0 else _to_world(t, fixed)


## Le point (monde) est-il dans le rectangle d'une voie à séguia autre que `except` ?
func _in_canal_lane(world: Vector2, except: int) -> bool:
	var u: float = world.x * _cos + world.y * _sin
	var v: float = -world.x * _sin + world.y * _cos
	for lane: int in _l_axis.size():
		if lane == except or _l_canal[lane] == 0:
			continue
		var along: float = v if _l_axis[lane] == 0 else u
		var across: float = u if _l_axis[lane] == 0 else v
		if absf(across - _l_fixed[lane]) <= _l_gap[lane] * 0.5 and along >= _l_a[lane] and along <= _l_b[lane]:
			return true
	return false


## Bassin de répartition au bout de la voie à séguia la plus proche de l'eau, séguia d'amenée jusqu'à la rive, séguias des voies.
func _place_basin_and_feeder() -> void:
	var canal: Dictionary = JsonData.get_dictionary(settings, "canal", CONTEXT)
	var basin: Dictionary = JsonData.get_dictionary(settings, "basin", CONTEXT)
	var size: float = JsonData.get_float(basin, "size_m", CONTEXT)
	var chunk: float = JsonData.get_float(canal, "chunk_m", CONTEXT)
	var probe: float = JsonData.get_float(canal, "extension_probe_m", CONTEXT)
	var features: LandscapeFeatures = _field.features
	# Eau d'alimentation : le plan d'eau de type oasis le plus proche du centre du contour.
	var source: int = -1
	var contour_center: Vector2 = (_contour_min + _contour_max) * 0.5
	var best_source: float = INF
	for index: int in features.water_count:
		if features.water_kind(index) != &"oasis":
			continue
		var d: float = features.water_center(index).distance_to(contour_center)
		if d < best_source:
			best_source = d
			source = index
	var best_lane: int = -1
	var best_end: int = 0
	var best_distance: float = INF
	if source >= 0:
		var water_center: Vector2 = features.water_center(source)
		for lane: int in _l_axis.size():
			if _l_canal[lane] == 0:
				continue
			for end: int in 2:
				var t: float = _l_a[lane] if end == 0 else _l_b[lane]
				var d: float = _lane_point(lane, t, 0.0).distance_to(water_center)
				if d < best_distance:
					best_distance = d
					best_lane = lane
					best_end = end
	var basin_half: float = size * 0.5
	var cut_a: PackedFloat64Array = PackedFloat64Array()
	var cut_b: PackedFloat64Array = PackedFloat64Array()
	cut_a.resize(_l_axis.size())
	cut_b.resize(_l_axis.size())
	cut_a.fill(NAN)
	cut_b.fill(NAN)
	if best_lane >= 0:
		var end_t: float = _l_a[best_lane] if best_end == 0 else _l_b[best_lane]
		var inward: float = 1.0 if best_end == 0 else -1.0
		var center_t: float = end_t + inward * basin_half
		var center: Vector2 = _lane_point(best_lane, center_t, 0.0)
		var yaw: float = atan2(_sin, _cos) + (0.0 if _l_axis[best_lane] == 1 else PI * 0.5)
		_basin_data.append_array(PackedFloat32Array([center.x, center.y, yaw, size]))
		_basin_cell.append(_cell_of(center.x, center.y))
		# La séguia de la voie s'arrête au bord du bassin côté eau.
		if best_end == 0:
			cut_a[best_lane] = end_t + size
		else:
			cut_b[best_lane] = end_t - size
		var water_center: Vector2 = features.water_center(source)
		var shore: Vector2 = water_center + (center - water_center).normalized() * features.water_radius(source)
		var edge: Vector2 = center + (shore - center).normalized() * basin_half
		_add_canal_chunks(edge, shore, chunk)
		_place_chadouf(best_lane, end_t, inward, center)
		_basin_rim(center, yaw, size)
	for lane: int in _l_axis.size():
		if _l_canal[lane] == 0:
			continue
		var gap: float = _l_gap[lane]
		var a: float = _l_a[lane]
		var b: float = _l_b[lane]
		if not is_nan(cut_a[lane]):
			a = cut_a[lane]
		if not is_nan(cut_b[lane]):
			b = cut_b[lane]
		if b - a < 0.5:
			continue
		# Prolongement jusqu'à la séguia de la voie voisine quand le bout touche une autre voie à séguia.
		var start_t: float = a
		var end_t2: float = b
		if is_nan(cut_a[lane]) and _in_canal_lane(_lane_point(lane, a - gap * 0.5 - probe, 0.0), lane):
			start_t = a - gap * 0.5
		if is_nan(cut_b[lane]) and _in_canal_lane(_lane_point(lane, b + gap * 0.5 + probe, 0.0), lane):
			end_t2 = b + gap * 0.5
		_add_canal_chunks(_lane_point(lane, start_t, 0.0), _lane_point(lane, end_t2, 0.0), chunk)


func _add_canal_chunks(from: Vector2, to: Vector2, chunk: float) -> void:
	var count: int = maxi(1, ceili(from.distance_to(to) / chunk))
	for i: int in count:
		var p0: Vector2 = from.lerp(to, float(i) / float(count))
		var p1: Vector2 = from.lerp(to, float(i + 1) / float(count))
		_canal_data.append_array(PackedFloat32Array([p0.x, p0.y, p1.x, p1.y]))
		var mid: Vector2 = (p0 + p1) * 0.5
		_canal_cell.append(_cell_of(mid.x, mid.y))


func _place_chadouf(lane: int, end_t: float, inward: float, basin_center: Vector2) -> void:
	var chadouf: Dictionary = JsonData.get_dictionary(settings, "chadouf", CONTEXT)
	var basin: Dictionary = JsonData.get_dictionary(settings, "basin", CONTEXT)
	var distance: float = JsonData.get_float(chadouf, "distance_m", CONTEXT) + JsonData.get_float(basin, "size_m", CONTEXT)
	var side: float = JsonData.get_float(chadouf, "side_offset_m", CONTEXT)
	var along: float = clampf(end_t + inward * distance, _l_a[lane] + 0.5, _l_b[lane] - 0.5)
	var position: Vector2 = _lane_point(lane, along, side)
	var toward: Vector2 = (basin_center - position).normalized()
	var yaw: float = atan2(-toward.y, toward.x)
	_add_point(&"chadouf", position.x, position.y, 1.0, yaw)
	_chadouf_clear = position
	_basin_center = basin_center


## Rebord du bassin : quatre murets bas sans collision.
func _basin_rim(center: Vector2, yaw: float, size: float) -> void:
	var half: float = size * 0.5
	var cs: float = cos(yaw)
	var sn: float = sin(yaw)
	var corners: Array[Vector2] = []
	for corner_sign: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var local: Vector2 = corner_sign * half
		corners.append(center + Vector2(local.x * cs - local.y * sn, local.x * sn + local.y * cs))
	for i: int in 4:
		_add_wall(corners[i], corners[(i + 1) % 4], 0.0)


func _add_wall(a: Vector2, b: Vector2, collides: float) -> void:
	_wall_data.append_array(PackedFloat32Array([a.x, a.y, b.x, b.y, collides]))
	var mid: Vector2 = (a + b) * 0.5
	_wall_cell.append(_cell_of(mid.x, mid.y))


func _add_point(species: StringName, x: float, z: float, scale: float, yaw: float) -> void:
	var index: int = _species_ids.find(species)
	if index < 0:
		_species_ids.append(species)
		index = _species_ids.size() - 1
	_point_data.append_array(PackedFloat32Array([x, z, scale, yaw]))
	_point_cell.append(_cell_of(x, z))
	_point_species.append(index)


# --- Murets ----------------------------------------------------------------------------------------------------------


## Quatre côtés par parcelle, posés à l'intérieur du rectangle ; une ouverture (porte) sur un côté tiré au sort.
func _build_walls() -> void:
	var walls: Dictionary = JsonData.get_dictionary(settings, "walls", CONTEXT)
	var thickness: float = JsonData.get_float(walls, "thickness_m", CONTEXT)
	var gate: float = JsonData.get_float(walls, "gate_m", CONTEXT)
	var min_piece: float = JsonData.get_float(walls, "min_piece_m", CONTEXT)
	var half: float = thickness * 0.5
	for i: int in parcel_count:
		var u0: float = _pu0[i] + half
		var v0: float = _pv0[i] + half
		var u1: float = _pu1[i] - half
		var v1: float = _pv1[i] - half
		var corners: Array[Vector2] = [Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1)]
		var gate_side: int = _rng.randi_range(0, 3)
		for side: int in 4:
			var a: Vector2 = corners[side]
			var b: Vector2 = corners[(side + 1) % 4]
			var length: float = a.distance_to(b)
			var direction: Vector2 = (b - a) / length
			# Les côtés se prolongent d'une demi-épaisseur : les angles sont fermés.
			var start: Vector2 = a - direction * half
			var stop: Vector2 = b + direction * half
			if side != gate_side or length < gate * 2.0 + min_piece * 2.0:
				_add_wall(_to_world(start.x, start.y), _to_world(stop.x, stop.y), 1.0)
				continue
			var gate_start: float = _rng.randf_range(min_piece, length - gate - min_piece)
			var first_end: Vector2 = a + direction * gate_start
			var second_start: Vector2 = a + direction * (gate_start + gate)
			_add_wall(_to_world(start.x, start.y), _to_world(first_end.x, first_end.y), 1.0)
			_add_wall(_to_world(second_start.x, second_start.y), _to_world(stop.x, stop.y), 1.0)


# --- Palmiers et arbres fruitiers ---------------------------------------------------------------------------------------


## Palmiers en rangées irrégulières de part et d'autre de chaque séguia de voie : décalage latéral borné, donc toujours près de l'eau.
func _place_palms() -> void:
	var palms: Dictionary = JsonData.get_dictionary(settings, "palms", CONTEXT)
	var species := StringName(JsonData.get_string(palms, "species", CONTEXT))
	var spacing: float = JsonData.get_float(palms, "spacing_m", CONTEXT)
	var spacing_jitter: float = JsonData.get_float(palms, "spacing_jitter_m", CONTEXT)
	var offset: float = JsonData.get_float(palms, "side_offset_m", CONTEXT)
	var side_jitter: float = JsonData.get_float(palms, "side_jitter_m", CONTEXT)
	var skip: float = JsonData.get_float(palms, "skip_probability", CONTEXT)
	var scale_min: float = JsonData.get_float(palms, "scale_min", CONTEXT)
	var scale_max: float = JsonData.get_float(palms, "scale_max", CONTEXT)
	var clearance: float = JsonData.get_float(JsonData.get_dictionary(settings, "chadouf", CONTEXT), "palm_clearance_m", CONTEXT)
	for lane: int in _l_axis.size():
		if _l_canal[lane] == 0:
			continue
		for side_sign: float in [-1.0, 1.0]:
			var t: float = _l_a[lane] + spacing * (0.5 if side_sign < 0.0 else 1.0)
			while t < _l_b[lane] - 1.0:
				var jitter_t: float = _rng.randf_range(-spacing_jitter, spacing_jitter)
				var lateral: float = side_sign * (offset + _rng.randf_range(-side_jitter, side_jitter))
				var world: Vector2 = _lane_point(lane, t + jitter_t, lateral)
				var near_basin: bool = world.distance_to(_basin_center) < clearance or world.distance_to(_chadouf_clear) < clearance
				var scale: float = _rng.randf_range(scale_min, scale_max)
				var yaw: float = _rng.randf_range(0.0, TAU)
				if _rng.randf() >= skip and not near_basin and t + jitter_t >= _l_a[lane] and t + jitter_t <= _l_b[lane]:
					_add_point(species, world.x, world.y, scale, yaw)
					_palm_all.append_array(PackedFloat32Array([world.x, world.y, scale, yaw]))
				t += spacing
	for i: int in _canal_data.size() / CANAL_STRIDE:
		_canal_all.append_array(_canal_data.slice(i * CANAL_STRIDE, (i + 1) * CANAL_STRIDE))


## Grenadiers, figuiers et oliviers sur une grille irrégulière à l'intérieur des vergers.
func _place_orchards() -> void:
	var kinds: Array = JsonData.get_array(settings, "kinds", CONTEXT)
	var scales: Dictionary = JsonData.get_dictionary(settings, "tree_scale", CONTEXT)
	var scale_min: float = JsonData.get_float(scales, "scale_min", CONTEXT)
	var scale_max: float = JsonData.get_float(scales, "scale_max", CONTEXT)
	var wall_half: float = JsonData.get_float(JsonData.get_dictionary(settings, "walls", CONTEXT), "thickness_m", CONTEXT) * 0.5
	for i: int in parcel_count:
		var kind: Dictionary = kinds[_pkind[i]]
		if not kind.has("trees"):
			continue
		var trees: Dictionary = JsonData.get_dictionary(kind, "trees", CONTEXT)
		var spacing: float = JsonData.get_float(trees, "spacing_m", CONTEXT)
		var jitter: float = JsonData.get_float(trees, "jitter_m", CONTEXT)
		var margin: float = JsonData.get_float(trees, "edge_margin_m", CONTEXT) + wall_half
		var weights: Dictionary = JsonData.get_dictionary(trees, "species", CONTEXT)
		var total: float = 0.0
		for id: Variant in weights.keys():
			total += float(weights[id])
		var columns: int = maxi(1, floori((_pu1[i] - _pu0[i] - 2.0 * margin) / spacing) + 1)
		var rows: int = maxi(1, floori((_pv1[i] - _pv0[i] - 2.0 * margin) / spacing) + 1)
		var span_u: float = float(columns - 1) * spacing
		var span_v: float = float(rows - 1) * spacing
		var origin_u: float = (_pu0[i] + _pu1[i]) * 0.5 - span_u * 0.5
		var origin_v: float = (_pv0[i] + _pv1[i]) * 0.5 - span_v * 0.5
		for column: int in columns:
			for row: int in rows:
				var u: float = origin_u + float(column) * spacing + _rng.randf_range(-jitter, jitter)
				var v: float = origin_v + float(row) * spacing + _rng.randf_range(-jitter, jitter)
				u = clampf(u, _pu0[i] + margin, _pu1[i] - margin)
				v = clampf(v, _pv0[i] + margin, _pv1[i] - margin)
				var pick: float = _rng.randf() * total
				var chosen: StringName = &""
				for id: Variant in weights.keys():
					pick -= float(weights[id])
					chosen = StringName(str(id))
					if pick <= 0.0:
						break
				var world: Vector2 = _to_world(u, v)
				_add_point(chosen, world.x, world.y, _rng.randf_range(scale_min, scale_max), _rng.randf_range(0.0, TAU))


# --- Répartition par cellule -------------------------------------------------------------------------------------------


func _distribute() -> void:
	for i: int in parcel_count:
		_data_for(_parcel_cell[i]).parcels.append(i)
	for i: int in _wall_cell.size():
		_data_for(_wall_cell[i]).walls.append_array(_wall_data.slice(i * WALL_STRIDE, (i + 1) * WALL_STRIDE))
	for i: int in _canal_cell.size():
		_data_for(_canal_cell[i]).canals.append_array(_canal_data.slice(i * CANAL_STRIDE, (i + 1) * CANAL_STRIDE))
	for i: int in _basin_cell.size():
		_data_for(_basin_cell[i]).basins.append_array(_basin_data.slice(i * BASIN_STRIDE, (i + 1) * BASIN_STRIDE))
	for i: int in _point_cell.size():
		var data: PalmeraieCellData = _data_for(_point_cell[i])
		var id: StringName = _species_ids[_point_species[i]]
		var list: PackedFloat32Array = data.points.get(id, PackedFloat32Array())
		list.append_array(_point_data.slice(i * POINT_STRIDE, (i + 1) * POINT_STRIDE))
		data.points[id] = list


func _data_for(key: int) -> PalmeraieCellData:
	var data: PalmeraieCellData = _cells.get(key)
	if data == null:
		data = PalmeraieCellData.new()
		_cells[key] = data
	return data
