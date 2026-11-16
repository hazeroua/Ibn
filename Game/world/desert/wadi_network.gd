class_name WadiNetwork
extends RefCounted
## Oueds du désert (lits de rivières sèches) et gorge : tracés lissés, creusement du relief, surfaces et sites de falaises.
##
## Chaque oued est décrit par des points de contrôle (desert.json > wadis). Au chargement, une courbe de Catmull-Rom les
## relie et la découpe en segments fins (au plus max_segment_m, 10 m) ; le long du tracé, la hauteur du fond est calculée
## depuis le relief d'origine sans dunes (relief), puis forcée à descendre régulièrement de l'amont à l'aval (pente
## minimale bed_min_slope). Un affluent (« joins ») est raccordé au fond de l'oued principal.
## Une gorge est une portion de tracé autour de laquelle le sol est surélevé (plateau) : le creusement du lit y forme
## des parois de 20 à 40 m ; les falaises (modèles Blender) sont posées sur ces parois (gorge_frames).
##
## Pire cas : 16 oueds de 64 points, des centaines de segments fins ; height_at() est appelée des millions de fois.
## Les segments sont inscrits dans une grille de cases de 16 m (réseau de lits) et une grille de 125 m (plateaux de
## gorge), en format compact (indices de début + liste d'éléments) : une requête lit une seule case et ne parcourt que les
## segments qui l'influencent (une dizaine au plus), sans aucune allocation, et rien du tout loin des oueds.
## Le creusement est le minimum des creusements de chaque segment proche : il est continu partout, donc sans marche entre
## deux cellules du terrain, et ne dépend que de (x, z), donc de l'ordre ou du fil des appels.

const CONTEXT: String = "desert.json > wadis"
const SETTINGS_CONTEXT: String = "desert.json > wadi_settings"
const MAX_WADIS: int = 16
const MAX_CONTROL_POINTS: int = 64
const MAX_SCATTER_POINTS: int = 64
## Segments du réseau de lits : extrémités (4), inverse du carré de la longueur, fond (2), demi-largeur (2), fondu (2), portée².
const SEGMENT_STRIDE: int = 12
## Segments de plateau de gorge : extrémités (4), inverse du carré de la longueur, surélévation (2), plateau, fondu, portée².
const RISE_STRIDE: int = 10
## Images de gorge : x, z, tangente x, tangente z, demi-largeur, fondu, abscisse curviligne.
const FRAME_STRIDE: int = 7


## Grille de cases carrées au format compact : les éléments de la case c sont items[start[c] .. start[c + 1] - 1].
class Grid:
	extends RefCounted
	var side: int = 1
	var inverse: float = 1.0
	var start: PackedInt32Array = PackedInt32Array()
	var items: PackedInt32Array = PackedInt32Array()

	## boxes : (x0, z0, x1, z1) par élément, en mètres du monde.
	static func build(boxes: PackedFloat64Array, half_extent: float, cell_size: float) -> Grid:
		var grid := Grid.new()
		grid.side = maxi(1, ceili(2.0 * half_extent / cell_size))
		grid.inverse = 1.0 / cell_size
		grid.start.resize(grid.side * grid.side + 1)
		grid.start.fill(0)
		@warning_ignore("integer_division")
		var count: int = boxes.size() / 4
		for item: int in count:
			var span: Vector4i = grid._span(boxes, item, half_extent)
			for row: int in range(span.y, span.w + 1):
				for column: int in range(span.x, span.z + 1):
					grid.start[row * grid.side + column + 1] += 1
		for cell: int in grid.side * grid.side:
			grid.start[cell + 1] += grid.start[cell]
		grid.items.resize(grid.start[grid.side * grid.side])
		var cursor: PackedInt32Array = grid.start.duplicate()
		for item: int in count:
			var span: Vector4i = grid._span(boxes, item, half_extent)
			for row: int in range(span.y, span.w + 1):
				for column: int in range(span.x, span.z + 1):
					var cell: int = row * grid.side + column
					grid.items[cursor[cell]] = item
					cursor[cell] += 1
		return grid

	func _span(boxes: PackedFloat64Array, item: int, half_extent: float) -> Vector4i:
		var base: int = item * 4
		return Vector4i(
			clampi(floori((boxes[base] + half_extent) * inverse), 0, side - 1),
			clampi(floori((boxes[base + 1] + half_extent) * inverse), 0, side - 1),
			clampi(floori((boxes[base + 2] + half_extent) * inverse), 0, side - 1),
			clampi(floori((boxes[base + 3] + half_extent) * inverse), 0, side - 1)
		)


var wadi_count: int = 0
var segment_count: int = 0

var _active: bool = false
var _half_extent: float = 2000.0
var _ids: Array[StringName] = []
var _gorges: Array[Dictionary] = []
## Réglages (desert.json > wadi_settings).
var _step: float = 8.0
var _max_segment: float = 10.0
var _arc_allowance: float = 1.25
var _rise_node_step: float = 20.0
var _pebble_fade: float = 0.35
var _earth_margin: float = 8.0
var _proximity_inner: float = 0.5
var _join_tolerance: float = 2.0
var _carve_cell: float = 16.0
var _rise_cell: float = 125.0
var _axis_cell: float = 125.0
## Points fins de tous les oueds (tableaux parallèles) ; _first et _count délimitent chaque oued.
var _first: PackedInt32Array = PackedInt32Array()
var _count: PackedInt32Array = PackedInt32Array()
var _px: PackedFloat64Array = PackedFloat64Array()
var _pz: PackedFloat64Array = PackedFloat64Array()
var _ps: PackedFloat64Array = PackedFloat64Array()
var _phw: PackedFloat64Array = PackedFloat64Array()
var _pblend: PackedFloat64Array = PackedFloat64Array()
var _prise: PackedFloat64Array = PackedFloat64Array()
var _pbed: PackedFloat64Array = PackedFloat64Array()
## Influence sur la végétation de chaque oued (portée de la distance à l'axe).
var _influence: PackedFloat64Array = PackedFloat64Array()
## Segments et index.
var _segments: PackedFloat64Array = PackedFloat64Array()
var _segment_wadi: PackedInt32Array = PackedInt32Array()
var _axis_reach_squared: PackedFloat64Array = PackedFloat64Array()
var _rise: PackedFloat64Array = PackedFloat64Array()
var _carve_grid: Grid = null
var _rise_grid: Grid = null
var _axis_grid: Grid = null


## Construit le réseau depuis la liste « wadis » de desert.json et ses réglages « wadi_settings ». relief(x, z) donne la
## hauteur du sol sans dunes. Renvoie un réseau inactif si la liste est vide, null si les données sont invalides.
static func from_data(wadis: Array, settings: Dictionary, half_extent: float, relief: Callable) -> WadiNetwork:
	var network := WadiNetwork.new()
	network._half_extent = half_extent
	if wadis.is_empty():
		return network
	if wadis.size() > MAX_WADIS:
		push_error("WadiNetwork : %d oueds (maximum %d)." % [wadis.size(), MAX_WADIS])
		return null
	if not relief.is_valid():
		push_error("WadiNetwork : la fonction de relief est obligatoire pour calculer le fond des oueds.")
		return null
	if not network._read_settings(settings):
		return null
	for entry: Variant in wadis:
		if not entry is Dictionary:
			push_error("WadiNetwork : chaque oued doit être un objet (%s)." % CONTEXT)
			return null
		if not network._add_wadi(entry, relief):
			return null
	network._build_indexes()
	network._active = true
	return network


func _read_settings(settings: Dictionary) -> bool:
	_step = JsonData.get_float(settings, "segment_step_m", SETTINGS_CONTEXT)
	_max_segment = JsonData.get_float(settings, "max_segment_m", SETTINGS_CONTEXT)
	_arc_allowance = JsonData.get_float(settings, "arc_allowance", SETTINGS_CONTEXT)
	_rise_node_step = JsonData.get_float(settings, "rise_node_step_m", SETTINGS_CONTEXT)
	_pebble_fade = JsonData.get_float(settings, "pebble_fade_fraction", SETTINGS_CONTEXT)
	_earth_margin = JsonData.get_float(settings, "bank_earth_margin_m", SETTINGS_CONTEXT)
	_proximity_inner = JsonData.get_float(settings, "proximity_inner_fraction", SETTINGS_CONTEXT)
	_join_tolerance = JsonData.get_float(settings, "join_tolerance_m", SETTINGS_CONTEXT)
	_carve_cell = JsonData.get_float(settings, "carve_cell_m", SETTINGS_CONTEXT)
	_rise_cell = JsonData.get_float(settings, "rise_cell_m", SETTINGS_CONTEXT)
	_axis_cell = JsonData.get_float(settings, "axis_cell_m", SETTINGS_CONTEXT)
	if (
		_step <= 0.0
		or _max_segment < _step
		or _arc_allowance < 1.0
		or _rise_node_step <= 0.0
		or _pebble_fade <= 0.0
		or _pebble_fade >= 1.0
		or _earth_margin < 0.0
		or _proximity_inner < 0.0
		or _proximity_inner >= 1.0
		or _join_tolerance < 0.0
		or _carve_cell <= 0.0
		or _rise_cell <= 0.0
		or _axis_cell <= 0.0
	):
		push_error("WadiNetwork : réglages incohérents (%s)." % SETTINGS_CONTEXT)
		return false
	return true


func _add_wadi(wadi: Dictionary, relief: Callable) -> bool:
	var id: String = JsonData.get_string(wadi, "id", CONTEXT)
	var context: String = "%s > %s" % [CONTEXT, id]
	if _ids.has(StringName(id)):
		push_error("WadiNetwork : identifiant en double (%s)." % context)
		return false
	var raw_points: Array = JsonData.get_array(wadi, "points", context)
	var width: float = JsonData.get_float(wadi, "width_m", context)
	var depth: float = JsonData.get_float(wadi, "depth_m", context)
	var blend: float = JsonData.get_float(wadi, "bank_blend_m", context)
	var influence: float = JsonData.get_float(wadi, "influence_m", context)
	var slope: float = JsonData.get_float(wadi, "bed_min_slope", context)
	var count: int = raw_points.size()
	if count < 2 or count > MAX_CONTROL_POINTS or width <= 0.0 or depth < 0.0 or blend <= 0.0 or influence < 0.0 or slope <= 0.0:
		push_error("WadiNetwork : points (2 à %d), largeur, profondeur, fondu ou pente incohérents (%s)." % [MAX_CONTROL_POINTS, context])
		return false
	var control := PackedVector2Array()
	var widths := PackedFloat64Array()
	var custom_widths: Array = []
	if wadi.has("widths"):
		custom_widths = JsonData.get_array(wadi, "widths", context)
		if custom_widths.size() != count:
			push_error("WadiNetwork : « widths » doit avoir un élément par point (%s)." % context)
			return false
	for k: int in count:
		var pair: Variant = raw_points[k]
		if not pair is Array or (pair as Array).size() != 2:
			push_error("WadiNetwork : un point d'oued est [x, z] (%s)." % context)
			return false
		var point := Vector2(float((pair as Array)[0]), float((pair as Array)[1]))
		if absf(point.x) > _half_extent or absf(point.y) > _half_extent:
			push_error("WadiNetwork : le point %d sort du désert (%s)." % [k, context])
			return false
		control.append(point)
		var point_width: float = width if custom_widths.is_empty() else float(custom_widths[k])
		if point_width <= 0.0:
			push_error("WadiNetwork : largeur de lit invalide au point %d (%s)." % [k, context])
			return false
		widths.append(point_width)
	var wadi_index: int = wadi_count
	var first: int = _px.size()
	if not _trace(control, widths, blend):
		push_error("WadiNetwork : segment plus long que %.1f m (%s)." % [_max_segment, context])
		return false
	var total: int = _px.size() - first
	_first.append(first)
	_count.append(total)
	_ids.append(StringName(id))
	_influence.append(influence)
	if wadi.has("gorge") and not _apply_gorge(JsonData.get_dictionary(wadi, "gorge", context), wadi_index, blend, context):
		return false
	var join_floor: float = -INF
	if wadi.has("joins"):
		join_floor = _junction_floor(JsonData.get_string(wadi, "joins", context), first, total, context)
		if is_inf(join_floor):
			return false
	_compute_bed(first, total, depth, slope, join_floor, relief)
	wadi_count += 1
	return true


## Courbe de Catmull-Rom entre les points de contrôle, en segments fins ; renvoie false si un segment dépasse max_segment_m.
func _trace(control: PackedVector2Array, widths: PackedFloat64Array, blend: float) -> bool:
	var last: int = control.size() - 1
	var start: int = _px.size()
	for k: int in last:
		var p0: Vector2 = control[maxi(k - 1, 0)]
		var p1: Vector2 = control[k]
		var p2: Vector2 = control[k + 1]
		var p3: Vector2 = control[mini(k + 2, last)]
		var steps: int = maxi(1, ceili(p1.distance_to(p2) * _arc_allowance / _step))
		for j: int in steps:
			var t: float = float(j) / float(steps)
			_append_point(_catmull_rom(p0, p1, p2, p3, t), lerpf(widths[k], widths[k + 1], t), blend, k == 0 and j == 0)
	_append_point(control[last], widths[last], blend, false)
	for i: int in range(start, _px.size() - 1):
		if _ps[i + 1] - _ps[i] > _max_segment:
			return false
	return true


func _append_point(position: Vector2, width: float, blend: float, starts_wadi: bool) -> void:
	var length: float = 0.0
	var size: int = _px.size()
	if size > 0 and not starts_wadi:
		length = _ps[size - 1] + Vector2(_px[size - 1], _pz[size - 1]).distance_to(position)
	_px.append(position.x)
	_pz.append(position.y)
	_ps.append(length)
	_phw.append(width * 0.5)
	_pblend.append(blend)
	_prise.append(0.0)
	_pbed.append(0.0)


## Surélévation et fondu resserré autour d'une gorge : portion [from_m, to_m] de l'abscisse curviligne, avec des rampes.
func _apply_gorge(gorge: Dictionary, wadi_index: int, blend: float, context: String) -> bool:
	var gorge_context: String = context + " > gorge"
	var from_m: float = JsonData.get_float(gorge, "from_m", gorge_context)
	var to_m: float = JsonData.get_float(gorge, "to_m", gorge_context)
	var rise_m: float = JsonData.get_float(gorge, "rise_m", gorge_context)
	var ramp_m: float = JsonData.get_float(gorge, "ramp_m", gorge_context)
	var plateau: float = JsonData.get_float(gorge, "plateau_half_width_m", gorge_context)
	var plateau_blend: float = JsonData.get_float(gorge, "plateau_blend_m", gorge_context)
	var wall_blend: float = JsonData.get_float(gorge, "wall_blend_m", gorge_context)
	var first: int = _first[wadi_index]
	var total: int = _count[wadi_index]
	var length: float = _ps[first + total - 1]
	if from_m < 0.0 or to_m <= from_m or to_m > length or rise_m <= 0.0 or ramp_m <= 0.0:
		push_error("WadiNetwork : tronçon ou surélévation de gorge incohérents (%s)." % gorge_context)
		return false
	if plateau <= 0.0 or plateau_blend <= 0.0 or wall_blend <= 0.0 or wall_blend > blend:
		push_error("WadiNetwork : plateau ou parois de gorge incohérents (%s)." % gorge_context)
		return false
	for i: int in range(first, first + total):
		var s: float = _ps[i]
		var factor: float = smoothstep(from_m - ramp_m, from_m, s) * (1.0 - smoothstep(to_m, to_m + ramp_m, s))
		_pblend[i] = lerpf(blend, wall_blend, factor)
		_prise[i] = rise_m * factor
	var entry: Dictionary = {
		"wadi": wadi_index, "from": from_m, "to": to_m, "ramp": ramp_m, "plateau": plateau, "plateau_blend": plateau_blend
	}
	entry["config"] = gorge
	_gorges.append(entry)
	return true


## Hauteur du fond de l'oued principal au point le plus proche de la fin de l'affluent, ou INF si le raccord est impossible.
func _junction_floor(target: String, first: int, total: int, context: String) -> float:
	var index: int = _ids.find(StringName(target))
	if index < 0:
		push_error("WadiNetwork : « joins » doit désigner un oued défini plus haut (%s)." % context)
		return INF
	var end_x: float = _px[first + total - 1]
	var end_z: float = _pz[first + total - 1]
	var best_distance: float = INF
	var best_floor: float = 0.0
	for i: int in range(_first[index], _first[index] + _count[index]):
		var distance: float = Vector2(_px[i] - end_x, _pz[i] - end_z).length()
		if distance < best_distance:
			best_distance = distance
			best_floor = _pbed[i]
	if best_distance > _join_tolerance:
		push_error(
			(
				"WadiNetwork : l'affluent doit finir sur l'oued principal (à %.1f m, tolérance %.1f m) (%s)."
				% [best_distance, _join_tolerance, context]
			)
		)
		return INF
	return best_floor


## Fond du lit : relief sans dunes moins la profondeur, puis suite strictement décroissante de l'amont à l'aval.
func _compute_bed(first: int, total: int, depth: float, slope: float, join_floor: float, relief: Callable) -> void:
	var last: int = first + total - 1
	_pbed[first] = float(relief.call(_px[first], _pz[first])) - depth
	for i: int in range(first + 1, last + 1):
		var raw: float = float(relief.call(_px[i], _pz[i])) - depth
		_pbed[i] = minf(raw, _pbed[i - 1] - slope * (_ps[i] - _ps[i - 1]))
	if is_inf(join_floor):
		return
	# Affluent : le fond ne descend pas sous celui de l'oued principal au raccord (sinon une fosse se formerait).
	_pbed[last] = maxf(_pbed[last], join_floor)
	for i: int in range(last - 1, first - 1, -1):
		_pbed[i] = maxf(_pbed[i], _pbed[i + 1] + slope * (_ps[i + 1] - _ps[i]))


func _build_indexes() -> void:
	var carve_boxes := PackedFloat64Array()
	var axis_boxes := PackedFloat64Array()
	for wadi_index: int in wadi_count:
		var first: int = _first[wadi_index]
		var max_half: float = 0.0
		var max_blend: float = 0.0
		for i: int in range(first, first + _count[wadi_index]):
			max_half = maxf(max_half, _phw[i])
			max_blend = maxf(max_blend, _pblend[i])
		var carve_reach: float = max_half + max_blend + _earth_margin
		var axis_reach: float = max_half + max_blend + _influence[wadi_index]
		for i: int in range(first, first + _count[wadi_index] - 1):
			var ax: float = _px[i]
			var az: float = _pz[i]
			var bx: float = _px[i + 1]
			var bz: float = _pz[i + 1]
			var sx: float = bx - ax
			var sz: float = bz - az
			_segments.append_array(
				PackedFloat64Array(
					[
						ax,
						az,
						bx,
						bz,
						1.0 / (sx * sx + sz * sz),
						_pbed[i],
						_pbed[i + 1],
						_phw[i],
						_phw[i + 1],
						_pblend[i],
						_pblend[i + 1],
						carve_reach * carve_reach
					]
				)
			)
			_segment_wadi.append(wadi_index)
			_axis_reach_squared.append(axis_reach * axis_reach)
			carve_boxes.append_array(
				PackedFloat64Array(
					[minf(ax, bx) - carve_reach, minf(az, bz) - carve_reach, maxf(ax, bx) + carve_reach, maxf(az, bz) + carve_reach]
				)
			)
			axis_boxes.append_array(
				PackedFloat64Array(
					[minf(ax, bx) - axis_reach, minf(az, bz) - axis_reach, maxf(ax, bx) + axis_reach, maxf(az, bz) + axis_reach]
				)
			)
	segment_count = _segment_wadi.size()
	_carve_grid = Grid.build(carve_boxes, _half_extent, _carve_cell)
	_axis_grid = Grid.build(axis_boxes, _half_extent, _axis_cell)
	_build_rise()


## Plateaux de gorge : segments de pas rise_node_step_m le long de la portion surélevée (rampes comprises).
func _build_rise() -> void:
	var boxes := PackedFloat64Array()
	for gorge: Dictionary in _gorges:
		var wadi_index: int = gorge["wadi"]
		var reach: float = float(gorge["plateau"]) + float(gorge["plateau_blend"])
		var first: int = _first[wadi_index]
		var last: int = first + _count[wadi_index] - 1
		var previous: int = -1
		for i: int in range(first, last + 1):
			if not _in_rise_zone(i, first, last):
				previous = -1
				continue
			if previous < 0:
				previous = i
				continue
			var ends_zone: bool = i == last or not _in_rise_zone(i + 1, first, last)
			if _ps[i] - _ps[previous] < _rise_node_step and not ends_zone:
				continue
			var ax: float = _px[previous]
			var az: float = _pz[previous]
			var bx: float = _px[i]
			var bz: float = _pz[i]
			var sx: float = bx - ax
			var sz: float = bz - az
			_rise.append_array(
				PackedFloat64Array(
					[
						ax,
						az,
						bx,
						bz,
						1.0 / (sx * sx + sz * sz),
						_prise[previous],
						_prise[i],
						gorge["plateau"],
						gorge["plateau_blend"],
						reach * reach
					]
				)
			)
			boxes.append_array(PackedFloat64Array([minf(ax, bx) - reach, minf(az, bz) - reach, maxf(ax, bx) + reach, maxf(az, bz) + reach]))
			previous = i
	_rise_grid = Grid.build(boxes, _half_extent, _rise_cell)


## Vrai si le point i est surélevé ou voisin d'un point surélevé (les extrémités nulles des rampes en font partie).
func _in_rise_zone(i: int, first: int, last: int) -> bool:
	return _prise[i] > 0.0 or (i > first and _prise[i - 1] > 0.0) or (i < last and _prise[i + 1] > 0.0)


## Surélévation du sol (mètres) autour d'une gorge : plateau plein sur plateau_half_width_m, fondu au-delà. O(segments de la case).
func rise_at(x: float, z: float) -> float:
	if not _active or _rise.is_empty():
		return 0.0
	var grid: Grid = _rise_grid
	var column: int = clampi(floori((x + _half_extent) * grid.inverse), 0, grid.side - 1)
	var row: int = clampi(floori((z + _half_extent) * grid.inverse), 0, grid.side - 1)
	var cell: int = row * grid.side + column
	var best: float = 0.0
	for k: int in range(grid.start[cell], grid.start[cell + 1]):
		var base: int = grid.items[k] * RISE_STRIDE
		var ax: float = _rise[base]
		var az: float = _rise[base + 1]
		var sx: float = _rise[base + 2] - ax
		var sz: float = _rise[base + 3] - az
		var t: float = clampf(((x - ax) * sx + (z - az) * sz) * _rise[base + 4], 0.0, 1.0)
		var px: float = x - (ax + sx * t)
		var pz: float = z - (az + sz * t)
		var distance_squared: float = px * px + pz * pz
		if distance_squared >= _rise[base + 9]:
			continue
		var plateau: float = _rise[base + 7]
		var weight: float = 1.0 - smoothstep(plateau, plateau + _rise[base + 8], sqrt(distance_squared))
		best = maxf(best, lerpf(_rise[base + 5], _rise[base + 6], t) * weight)
	return best


## Creuse le lit : profil en U (fond plat sur la largeur, berges lissées sur le fondu) vers le fond de l'oued. O(segments de la case).
func carve(x: float, z: float, height: float) -> float:
	if not _active:
		return height
	var grid: Grid = _carve_grid
	var column: int = clampi(floori((x + _half_extent) * grid.inverse), 0, grid.side - 1)
	var row: int = clampi(floori((z + _half_extent) * grid.inverse), 0, grid.side - 1)
	var cell: int = row * grid.side + column
	var result: float = height
	for k: int in range(grid.start[cell], grid.start[cell + 1]):
		var base: int = grid.items[k] * SEGMENT_STRIDE
		var ax: float = _segments[base]
		var az: float = _segments[base + 1]
		var sx: float = _segments[base + 2] - ax
		var sz: float = _segments[base + 3] - az
		var t: float = clampf(((x - ax) * sx + (z - az) * sz) * _segments[base + 4], 0.0, 1.0)
		var px: float = x - (ax + sx * t)
		var pz: float = z - (az + sz * t)
		var distance_squared: float = px * px + pz * pz
		if distance_squared >= _segments[base + 11]:
			continue
		var half_width: float = lerpf(_segments[base + 7], _segments[base + 8], t)
		var away: float = smoothstep(half_width, half_width + lerpf(_segments[base + 9], _segments[base + 10], t), sqrt(distance_squared))
		result = minf(result, lerpf(lerpf(_segments[base + 5], _segments[base + 6], t), height, away))
	return result


## Surfaces liées aux oueds à (x, z) : x = galets (lit), y = terre des berges, z = proximité du lit (0 loin, 1 au centre),
## utilisée par le shader pour teinter le lit vu de loin. O(segments de la case).
func surface_mix(x: float, z: float) -> Vector3:
	if not _active:
		return Vector3.ZERO
	var grid: Grid = _carve_grid
	var column: int = clampi(floori((x + _half_extent) * grid.inverse), 0, grid.side - 1)
	var row: int = clampi(floori((z + _half_extent) * grid.inverse), 0, grid.side - 1)
	var cell: int = row * grid.side + column
	var pebbles: float = 0.0
	var earth: float = 0.0
	var proximity: float = 0.0
	for k: int in range(grid.start[cell], grid.start[cell + 1]):
		var base: int = grid.items[k] * SEGMENT_STRIDE
		var ax: float = _segments[base]
		var az: float = _segments[base + 1]
		var sx: float = _segments[base + 2] - ax
		var sz: float = _segments[base + 3] - az
		var t: float = clampf(((x - ax) * sx + (z - az) * sz) * _segments[base + 4], 0.0, 1.0)
		var px: float = x - (ax + sx * t)
		var pz: float = z - (az + sz * t)
		var distance_squared: float = px * px + pz * pz
		if distance_squared >= _segments[base + 11]:
			continue
		var distance: float = sqrt(distance_squared)
		var half_width: float = lerpf(_segments[base + 7], _segments[base + 8], t)
		var blend: float = lerpf(_segments[base + 9], _segments[base + 10], t)
		pebbles = maxf(pebbles, 1.0 - smoothstep(half_width, half_width + blend * _pebble_fade, distance))
		earth = maxf(earth, 1.0 - smoothstep(half_width + blend, half_width + blend + _earth_margin, distance))
		proximity = maxf(proximity, 1.0 - smoothstep(half_width * _proximity_inner, half_width + blend, distance))
	return Vector3(pebbles, earth, proximity)


## Distance (mètres) à l'axe de l'oued le plus proche, INF au-delà de la portée de cet oued (largeur + berges + influence_m).
func distance_to_axis(x: float, z: float) -> float:
	if not _active:
		return INF
	var grid: Grid = _axis_grid
	var column: int = clampi(floori((x + _half_extent) * grid.inverse), 0, grid.side - 1)
	var row: int = clampi(floori((z + _half_extent) * grid.inverse), 0, grid.side - 1)
	var cell: int = row * grid.side + column
	var best: float = INF
	for k: int in range(grid.start[cell], grid.start[cell + 1]):
		var item: int = grid.items[k]
		var base: int = item * SEGMENT_STRIDE
		var ax: float = _segments[base]
		var az: float = _segments[base + 1]
		var sx: float = _segments[base + 2] - ax
		var sz: float = _segments[base + 3] - az
		var t: float = clampf(((x - ax) * sx + (z - az) * sz) * _segments[base + 4], 0.0, 1.0)
		var px: float = x - (ax + sx * t)
		var pz: float = z - (az + sz * t)
		var distance_squared: float = px * px + pz * pz
		if distance_squared <= _axis_reach_squared[item]:
			best = minf(best, sqrt(distance_squared))
	return best


## Tracés pour la végétation (VegetationScatter.set_features) : chaque oued rééchantillonné tous les step_m mètres et coupé
## en morceaux de 64 points au plus (le dernier point d'un morceau est le premier du suivant). Le nombre total de morceaux
## est limité à MAX_WADIS : le pas est augmenté au besoin ; renvoie un tableau vide (et une erreur) si c'est impossible.
func scatter_polylines(step_m: float) -> Array:
	var pieces: Array = []
	var step: float = step_m
	for attempt: int in 8:
		pieces = _split_polylines(step)
		if pieces.size() <= MAX_WADIS:
			return pieces
		step *= 1.5
	push_error("WadiNetwork : les oueds ne tiennent pas dans %d morceaux de %d points." % [MAX_WADIS, MAX_SCATTER_POINTS])
	return []


func _split_polylines(step: float) -> Array:
	var pieces: Array = []
	for wadi_index: int in wadi_count:
		var first: int = _first[wadi_index]
		var last: int = first + _count[wadi_index] - 1
		var points: Array = []
		var next_s: float = 0.0
		for i: int in range(first, last + 1):
			if _ps[i] >= next_s or i == last:
				points.append([_px[i], _pz[i]])
				next_s = _ps[i] + step
			if points.size() == MAX_SCATTER_POINTS and i != last:
				pieces.append({"points": points})
				points = [points[points.size() - 1]]
		if points.size() >= 2:
			pieces.append({"points": points})
	return pieces


func gorge_count() -> int:
	return _gorges.size()


## Données de la gorge (desert.json > wadis > gorge), dont le bloc « cliffs » des falaises.
func gorge_config(index: int) -> Dictionary:
	var config: Dictionary = _gorges[index]["config"]
	return config


## Images le long de la gorge, une tous les spacing_m mètres entre from_m et to_m : FRAME_STRIDE réels chacune
## (x, z, tangente x, tangente z, demi-largeur du lit, fondu des parois, abscisse curviligne).
func gorge_frames(index: int, spacing_m: float) -> PackedFloat64Array:
	var frames := PackedFloat64Array()
	if spacing_m <= 0.0:
		push_error("WadiNetwork : l'espacement des images de gorge doit être positif.")
		return frames
	var gorge: Dictionary = _gorges[index]
	var first: int = _first[int(gorge["wadi"])]
	var last: int = first + _count[int(gorge["wadi"])] - 1
	var segment: int = first
	var s: float = float(gorge["from"])
	while s <= float(gorge["to"]):
		while segment < last - 1 and _ps[segment + 1] < s:
			segment += 1
		var length: float = _ps[segment + 1] - _ps[segment]
		var t: float = clampf((s - _ps[segment]) / length, 0.0, 1.0)
		var tangent := Vector2(_px[segment + 1] - _px[segment], _pz[segment + 1] - _pz[segment]).normalized()
		frames.append(lerpf(_px[segment], _px[segment + 1], t))
		frames.append(lerpf(_pz[segment], _pz[segment + 1], t))
		frames.append(tangent.x)
		frames.append(tangent.y)
		frames.append(lerpf(_phw[segment], _phw[segment + 1], t))
		frames.append(lerpf(_pblend[segment], _pblend[segment + 1], t))
		frames.append(s)
		s += spacing_m
	return frames


static func _catmull_rom(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2: float = t * t
	var t3: float = t2 * t
	return (p1 * 2.0 + (p2 - p0) * t + (p0 * 2.0 - p1 * 5.0 + p2 * 4.0 - p3) * t2 + (p1 * 3.0 - p0 - p2 * 3.0 + p3) * t3) * 0.5
