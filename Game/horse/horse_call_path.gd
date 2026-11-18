class_name HorseCallPath
extends RefCounted
## Chemin de Barq quand on le siffle : A* (AStarGrid2D, C++) sur une grille de tout le désert, calculée une seule
## fois à partir de la heightfield (relief statique) dans un fil de travail, puis chaque chemin dans un fil de
## travail lui aussi : aucun calcul lourd sur le fil principal, aucune apparition artificielle de Barq.
##
## Une case est praticable si le relief y reste sous la pente maximale de Barq (écart d'altitude entre ses coins
## et son centre, ce qui attrape aussi les falaises plus étroites qu'une case) et si l'eau y est guéable.
## Les obstacles posés (rochers, murets) ne sont pas dans la grille : Barq les évite sur place (sonde, marches).
## Les zones interdites déclarées par la scène (enceinte d'une ville, block_area) sont infranchissables : le
## chemin les contourne au lieu de buter dessus.
##
## Pire cas : désert de 4 km de côté, cases de grid_cell_m (8 m : 500 × 500 = 250 000 cases, 251 001 altitudes
## lues une fois), appel depuis l'autre bout du monde. Un seul calcul à la fois ; un appel arrivé pendant un
## calcul remplace le précédent (le dernier sifflet compte). Mémoire : un octet de praticabilité par case.

const CONTEXT: String = "horse.json > call"

var path := PackedVector3Array()

var _field: DesertHeightfield
var _grid := AStarGrid2D.new()
var _cell: float = 8.0
var _side: int = 0
var _origin: float = 0.0
var _max_rise: float = 0.0
var _max_wade: float = 0.0
var _search_radius: int = 0
var _heights := PackedFloat32Array()
var _grid_ready: bool = false
var _task: int = -1
var _pending: bool = false
var _pending_from := Vector3.ZERO
var _pending_to := Vector3.ZERO
var _result := PackedVector3Array()
var _result_ready: bool = false
var _cancelled: bool = false
var _blocked: Array[Rect2] = []
var _blocked_applied: int = 0


## Lance la construction de la grille (fil de travail). settings : horse.json entier.
func prepare(field: DesertHeightfield, settings: Dictionary) -> void:
	_field = field
	var call: Dictionary = JsonData.get_dictionary(settings, "call", "horse.json")
	var terrain: Dictionary = JsonData.get_dictionary(settings, "terrain", "horse.json")
	_cell = JsonData.get_float(call, "grid_cell_m", CONTEXT)
	_max_wade = JsonData.get_float(call, "max_wade_depth_m", CONTEXT)
	_search_radius = JsonData.get_int(call, "nearest_walkable_search_cells", CONTEXT)
	_max_rise = _cell * 0.5 * tan(deg_to_rad(JsonData.get_float(terrain, "max_slope_deg", "horse.json > terrain")))
	if field == null or _cell <= 0.0:
		return
	_origin = -field.half_extent
	_side = ceili(field.half_extent * 2.0 / _cell)
	_task = WorkerThreadPool.add_task(_build_grid, false, "Barq : grille des chemins")


func is_grid_ready() -> bool:
	return _grid_ready


## Rend infranchissable un rectangle horizontal du monde (x, z). Appliqué sur le fil principal, jamais pendant
## un calcul de chemin ; valable pour tous les chemins demandés ensuite.
func block_area(rect: Rect2) -> void:
	_blocked.append(rect)
	if _task < 0:
		_apply_blocked()


func _apply_blocked() -> void:
	if not _grid_ready:
		return
	while _blocked_applied < _blocked.size():
		var rect: Rect2 = _blocked[_blocked_applied]
		_blocked_applied += 1
		var low := Vector2i(floori((rect.position.x - _origin) / _cell), floori((rect.position.y - _origin) / _cell))
		var high := Vector2i(floori((rect.end.x - _origin) / _cell), floori((rect.end.y - _origin) / _cell))
		for row: int in range(maxi(low.y, 0), mini(high.y, _side - 1) + 1):
			for column: int in range(maxi(low.x, 0), mini(high.x, _side - 1) + 1):
				_grid.set_point_solid(Vector2i(column, row), true)


## Demande un chemin (le résultat arrive par poll()).
func request(from: Vector3, to: Vector3) -> void:
	_pending = true
	_pending_from = from
	_pending_to = to


## À appeler à chaque image : vrai quand un nouveau chemin est disponible dans « path » (vide s'il n'y en a
## aucun). Ne fait qu'interroger un fil de travail ; aucune allocation.
func poll() -> bool:
	if _task >= 0:
		if not WorkerThreadPool.is_task_completed(_task):
			return false
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		if _result_ready:
			_result_ready = false
			path = _result
			if not _pending:
				return true
	if _grid_ready and _blocked_applied < _blocked.size():
		_apply_blocked()
	if _pending and _grid_ready:
		_pending = false
		_task = WorkerThreadPool.add_task(_find_path.bind(_pending_from, _pending_to), false, "Barq : chemin")
	return false


## Attend la fin du calcul en cours (tests, mesures).
## Vrai si un nouveau chemin est arrivé pendant l'attente.
func wait() -> bool:
	var arrived: bool = false
	while _task >= 0:
		while not WorkerThreadPool.is_task_completed(_task):
			OS.delay_usec(200)
		if poll():
			arrived = true
	return arrived


## Interrompt le calcul en cours et attend son arrêt (sortie du jeu) : la grille s'arrête à la ligne suivante.
func abort() -> void:
	_cancelled = true
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


func cell_of(world: Vector3) -> Vector2i:
	return Vector2i(clampi(floori((world.x - _origin) / _cell), 0, _side - 1), clampi(floori((world.z - _origin) / _cell), 0, _side - 1))


func is_walkable_cell(cell: Vector2i) -> bool:
	return _grid_ready and _grid.is_in_boundsv(cell) and not _grid.is_point_solid(cell)


func _build_grid() -> void:
	var lattice: int = _side + 1
	_heights.resize(lattice * lattice)
	for row: int in lattice:
		if _cancelled:
			return
		var z: float = _origin + float(row) * _cell
		for column: int in lattice:
			_heights[row * lattice + column] = _field.height_at(_origin + float(column) * _cell, z)
	_grid.region = Rect2i(0, 0, _side, _side)
	_grid.cell_size = Vector2(_cell, _cell)
	_grid.offset = Vector2(_origin + _cell * 0.5, _origin + _cell * 0.5)
	_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_grid.update()
	for row: int in _side:
		if _cancelled:
			return
		for column: int in _side:
			var x: float = _origin + (float(column) + 0.5) * _cell
			var z: float = _origin + (float(row) + 0.5) * _cell
			var center: float = _field.height_at(x, z)
			var a: float = _heights[row * lattice + column]
			var b: float = _heights[row * lattice + column + 1]
			var c: float = _heights[(row + 1) * lattice + column]
			var d: float = _heights[(row + 1) * lattice + column + 1]
			var rise: float = maxf(maxf(absf(a - center), absf(b - center)), maxf(absf(c - center), absf(d - center)))
			var water: float = _field.features.standing_water_height(x, z)
			var deep: bool = water != LandscapeFeatures.NO_WATER and water - center > _max_wade
			if rise > _max_rise or deep:
				_grid.set_point_solid(Vector2i(column, row), true)
	_heights = PackedFloat32Array()
	_grid_ready = true


func _find_path(from: Vector3, to: Vector3) -> void:
	var start: Vector2i = _nearest_walkable(cell_of(from))
	var goal: Vector2i = _nearest_walkable(cell_of(to))
	var points := PackedVector3Array()
	if start.x >= 0 and goal.x >= 0:
		# Chemin partiel accepté : si le joueur est hors d'atteinte, Barq vient au plus près.
		var cells: Array[Vector2i] = _grid.get_id_path(start, goal, true)
		var previous_direction := Vector2i.ZERO
		for index: int in cells.size():
			var direction: Vector2i = cells[index] - cells[index - 1] if index > 0 else Vector2i.ZERO
			# Seuls les changements de direction sont gardés (ligne droite = deux points).
			if index > 1 and direction == previous_direction:
				points[points.size() - 1] = _point(cells[index])
			else:
				points.append(_point(cells[index]))
			previous_direction = direction
	_result = points
	_result_ready = true


func _point(cell: Vector2i) -> Vector3:
	var x: float = _origin + (float(cell.x) + 0.5) * _cell
	var z: float = _origin + (float(cell.y) + 0.5) * _cell
	return Vector3(x, _field.height_at(x, z), z)


## Case praticable la plus proche (anneaux successifs, au plus nearest_walkable_search_cells) ; (-1, -1) sinon.
func _nearest_walkable(cell: Vector2i) -> Vector2i:
	if not _grid.is_point_solid(cell):
		return cell
	for radius: int in range(1, _search_radius + 1):
		for offset: int in range(-radius, radius + 1):
			for candidate: Vector2i in [
				cell + Vector2i(offset, -radius),
				cell + Vector2i(offset, radius),
				cell + Vector2i(-radius, offset),
				cell + Vector2i(radius, offset)
			]:
				if _grid.is_in_boundsv(candidate) and not _grid.is_point_solid(candidate):
					return candidate
	return Vector2i(-1, -1)
