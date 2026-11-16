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
const GRID_SIDE: int = 32
## Types de plans d'eau où l'on peut marcher quand la profondeur le permet (le chott n'a qu'une pellicule d'eau).
const WADEABLE_KINDS: Array[StringName] = [&"oasis", &"lac", &"guelta"]
## Valeur de standing_water_height() hors de tout plan d'eau praticable à gué.
const NO_WATER: float = -1.0e9

var water_count: int = 0
var wadi_count: int = 0
var segment_count: int = 0
## Oueds (tracés lissés, creusement, surfaces, gorge).
var wadis: WadiNetwork = null

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
## Largeur (m) de la rive en pente douce à l'intérieur du rayon : 0 = fond plat jusqu'à la rive (oasis).
var _shore: PackedFloat64Array = PackedFloat64Array()
var _wadeable: PackedByteArray = PackedByteArray()
## Falaise facultative derrière le plan d'eau : direction (vecteur unitaire), cosinus du demi-angle, hauteur,
## montée (wall) et descente (back) en mètres au-delà du rayon. Hauteur nulle = pas de falaise.
var _cliff_x: PackedFloat64Array = PackedFloat64Array()
var _cliff_z: PackedFloat64Array = PackedFloat64Array()
var _cliff_cos: PackedFloat64Array = PackedFloat64Array()
var _cliff_height: PackedFloat64Array = PackedFloat64Array()
var _cliff_wall: PackedFloat64Array = PackedFloat64Array()
var _cliff_back: PackedFloat64Array = PackedFloat64Array()
## Une liste d'indices par case de la grille.
var _water_cells: Array[PackedInt32Array] = []


## Construit l'index depuis le contenu de desert.json. extra_reach_m élargit la portée des plans d'eau (marge de la
## terre autour de l'eau, lue par surface_weights).
## relief(x, z) : hauteur du sol sans dunes (fond des oueds). Renvoie null si les données sont invalides.
static func from_data(data: Dictionary, half_extent: float, extra_reach_m: float, relief: Callable = Callable()) -> LandscapeFeatures:
	var features := LandscapeFeatures.new()
	features._half_extent = half_extent
	features._inverse_cell = float(GRID_SIDE) / (2.0 * half_extent)
	for i: int in GRID_SIDE * GRID_SIDE:
		features._water_cells.append(PackedInt32Array())
	if not features._load_water(JsonData.get_array(data, "water_bodies", CONTEXT), extra_reach_m):
		return null
	if not features._load_wadis(data, relief):
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
		var shore: float = JsonData.get_float_or(body, "shore_width_m", 0.0, context)
		if shore < 0.0 or shore > radius:
			push_error("LandscapeFeatures : shore_width_m doit être compris entre 0 et le rayon (%s)." % context)
			return false
		if not _append_cliff(body, blend, context):
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
		_shore.append(shore)
		_wadeable.append(1 if WADEABLE_KINDS.has(kind) else 0)
		_register_water(water_count, center.x - reach, center.y - reach, center.x + reach, center.y + reach)
		water_count += 1
	return true


## Lit la falaise facultative d'un plan d'eau (clé « cliff ») et l'ajoute aux tableaux parallèles ; sans falaise,
## ajoute une hauteur nulle.
func _append_cliff(body: Dictionary, blend: float, context: String) -> bool:
	var direction := Vector2.RIGHT
	var cos_half: float = 1.0
	var height: float = 0.0
	var wall: float = 1.0
	var back: float = 1.0
	if body.has("cliff"):
		var cliff: Dictionary = JsonData.get_dictionary(body, "cliff", context)
		var cliff_context: String = context + " > cliff"
		var angle: float = deg_to_rad(JsonData.get_float(cliff, "direction_deg", cliff_context))
		var half_angle: float = JsonData.get_float(cliff, "half_angle_deg", cliff_context)
		height = JsonData.get_float(cliff, "height_m", cliff_context)
		wall = JsonData.get_float(cliff, "wall_m", cliff_context)
		back = JsonData.get_float(cliff, "back_m", cliff_context)
		if half_angle <= 0.0 or half_angle >= 180.0 or height < 0.0 or wall <= 0.0 or back <= 0.0 or wall + back > blend:
			push_error(
				"LandscapeFeatures : falaise incohérente (demi-angle, hauteur, montée + descente <= fondu des berges) (%s)." % context
			)
			return false
		direction = Vector2(cos(angle), sin(angle))
		cos_half = cos(deg_to_rad(half_angle))
	_cliff_x.append(direction.x)
	_cliff_z.append(direction.y)
	_cliff_cos.append(cos_half)
	_cliff_height.append(height)
	_cliff_wall.append(wall)
	_cliff_back.append(back)
	return true


func _load_wadis(data: Dictionary, relief: Callable) -> bool:
	var list: Array = JsonData.get_array(data, "wadis", CONTEXT)
	var settings: Dictionary = {}
	if not list.is_empty():
		settings = JsonData.get_dictionary(data, "wadi_settings", CONTEXT)
	wadis = WadiNetwork.from_data(list, settings, _half_extent, relief)
	if wadis == null:
		return false
	wadi_count = wadis.wadi_count
	segment_count = wadis.segment_count
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


func _cell_index(x: float, z: float) -> int:
	var column: int = clampi(floori((x + _half_extent) * _inverse_cell), 0, GRID_SIDE - 1)
	var row: int = clampi(floori((z + _half_extent) * _inverse_cell), 0, GRID_SIDE - 1)
	return row * GRID_SIDE + column


## Applique le relief des plans d'eau à la hauteur naturelle du sol : le fond du plan d'eau au centre, remonté
## en douceur (smoothstep) jusqu'au sol naturel sur bank_blend_m au-delà du rayon. O(éléments de la case).
## Avec shore_width_m > 0, le fond remonte d'abord jusqu'à la surface de l'eau sur la largeur de la rive (à
## l'intérieur du rayon : la profondeur lisible va de depth_m à 0 à la rive), puis le sol naturel est relevé au
## moins au niveau de l'eau : aucun creux ne reste entre la rive et l'eau. Une falaise facultative s'ajoute derrière.
func carve(x: float, z: float, natural_height: float) -> float:
	var height: float = natural_height + wadis.rise_at(x, z)
	for index: int in _water_cells[_cell_index(x, z)]:
		var dx: float = x - _x[index]
		var dz: float = z - _z[index]
		var distance: float = sqrt(dx * dx + dz * dz)
		var radius: float = _radius[index]
		var away: float = smoothstep(radius, radius + _blend[index], distance)
		var shore: float = _shore[index]
		if shore > 0.0:
			var ramp: float = smoothstep(radius - shore, radius, distance)
			var base: float = _floor[index] + (_surface[index] - _floor[index]) * ramp
			height = lerpf(base, maxf(height, _surface[index]), away)
		else:
			height = lerpf(_floor[index], height, away)
		if _cliff_height[index] > 0.0 and distance > radius:
			height += _cliff_bump(index, dx, dz, distance)
	return wadis.carve(x, z, height)


## Relief de la falaise du plan d'eau : fenêtre angulaire (autour de la direction de la falaise) multipliée par un
## profil radial qui monte sur wall m au-delà du rayon puis redescend sur back m.
func _cliff_bump(index: int, dx: float, dz: float, distance: float) -> float:
	var along: float = (dx * _cliff_x[index] + dz * _cliff_z[index]) / distance
	var angular: float = smoothstep(_cliff_cos[index], 1.0, along)
	if angular <= 0.0:
		return 0.0
	var radius: float = _radius[index]
	var wall: float = _cliff_wall[index]
	var rise: float = smoothstep(radius, radius + wall, distance)
	var fall: float = 1.0 - smoothstep(radius + wall, radius + wall + _cliff_back[index], distance)
	return _cliff_height[index] * angular * rise * fall


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


## Hauteur de la surface de l'eau si (x, z) est à l'intérieur du rayon d'un plan d'eau où l'on peut marcher
## (oasis, lac, guelta), NO_WATER sinon. O(éléments de la case), sans allocation.
func standing_water_height(x: float, z: float) -> float:
	for index: int in _water_cells[_cell_index(x, z)]:
		if _wadeable[index] == 0:
			continue
		var dx: float = x - _x[index]
		var dz: float = z - _z[index]
		var radius: float = _radius[index]
		if dx * dx + dz * dz <= radius * radius:
			return _surface[index]
	return NO_WATER


## Rayon (m) du cercle où la profondeur de l'eau vaut max_depth_m, pour un plan d'eau praticable à gué plus profond
## que cela ; -1 si l'on peut marcher partout dans ce plan d'eau (ou s'il n'est pas praticable). La profondeur
## vaut depth_m * (1 - smoothstep(rayon - rive, rayon, d)) : on inverse le smoothstep par dichotomie.
func wading_ring_radius(index: int, max_depth_m: float) -> float:
	var depth: float = _surface[index] - _floor[index]
	if _wadeable[index] == 0 or depth <= max_depth_m:
		return -1.0
	var shore: float = _shore[index]
	if shore <= 0.0:
		return _radius[index]
	var target: float = 1.0 - max_depth_m / depth
	var low: float = 0.0
	var high: float = 1.0
	for _step: int in 32:
		var middle: float = (low + high) * 0.5
		if middle * middle * (3.0 - 2.0 * middle) < target:
			low = middle
		else:
			high = middle
	return _radius[index] - shore + shore * (low + high) * 0.5


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


## Distance (mètres) à l'axe de l'oued le plus proche, INF au-delà de la portée de cet oued.
func distance_to_wadi(x: float, z: float) -> float:
	return wadis.distance_to_axis(x, z)


## Identifiants des plans d'eau (lecture seule, pour les systèmes qui les rendent).
func water_ids() -> Array[StringName]:
	return _ids


func water_kind(index: int) -> StringName:
	return _kinds[index]


func water_center(index: int) -> Vector2:
	return Vector2(_x[index], _z[index])


func water_radius(index: int) -> float:
	return _radius[index]


## Hauteur de la surface de l'eau du plan d'eau d'indice index.
func water_surface(index: int) -> float:
	return _surface[index]


## Profondeur (m) au centre du plan d'eau d'indice index.
func water_depth(index: int) -> float:
	return _surface[index] - _floor[index]


## Largeur (m) de la rive en pente douce du plan d'eau d'indice index (0 = fond plat jusqu'à la rive).
func water_shore_width(index: int) -> float:
	return _shore[index]
