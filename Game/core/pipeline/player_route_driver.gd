class_name PlayerRouteDriver
extends Node
## Fait suivre un parcours (PlayerRoute) au joueur en pressant les actions d'entrée, comme un vrai joueur.
##
## - Le joueur est le seul nœud du groupe « player » ; seul un Node3D est supposé (contrat du MVP 1).
## - Les actions move_* reçoivent une intensité (comme un stick analogique) calculée par rapport à la
##   caméra active du joueur, recalculée à chaque pas de physique : le pilotage est en boucle fermée et
##   reste juste quelle que soit la façon dont la caméra suit ou tourne avec le joueur.
## - Allure du segment : walk_slow maintient l'action « walk_slow », run maintient « sprint ».
## - Blocage : si la distance au prochain point de passage ne diminue pas d'au moins stall_min_progress_m
##   pendant stall_time_s, le parcours échoue avec la position du joueur.
## - Toutes les actions pressées par le pilote sont relâchées à la fin, en cas d'échec et à la sortie de l'arbre.
##
## Coût par pas de physique : constant (quelques opérations vectorielles et au plus six appels à Input),
## sans allocation. Seul le passage d'un point au suivant boucle, et chaque point n'est franchi qu'une fois.

enum Status { IDLE, RUNNING, FINISHED, STOPPED, BLOCKED, TIMED_OUT, PLAYER_LOST, NO_CAMERA }

const PLAYER_GROUP: StringName = &"player"
const HORSE_GROUP: StringName = &"horse"
const MOVE_FORWARD: StringName = &"move_forward"
const MOVE_BACK: StringName = &"move_back"
const MOVE_LEFT: StringName = &"move_left"
const MOVE_RIGHT: StringName = &"move_right"
const SPRINT: StringName = &"sprint"
const WALK_SLOW: StringName = &"walk_slow"
## Actions que le pilote peut presser ; les indices ci-dessous s'y réfèrent.
const ACTIONS: Array[StringName] = [MOVE_FORWARD, MOVE_BACK, MOVE_LEFT, MOVE_RIGHT, SPRINT, WALK_SLOW]
const INDEX_FORWARD: int = 0
const INDEX_BACK: int = 1
const INDEX_LEFT: int = 2
const INDEX_RIGHT: int = 3
const INDEX_SPRINT: int = 4
const INDEX_WALK_SLOW: int = 5
## Exécuté avant les autres nœuds à chaque pas de physique : le joueur lit les actions de ce pas.
const PHYSICS_PRIORITY: int = -100000
## En dessous de cette intensité, une action de déplacement est relâchée plutôt que pressée à zéro.
const MIN_STRENGTH: float = 0.0001
const FLAT_EPSILON: float = 0.000001
const HORSE_PATH_REACH_M: float = 6.0

var _route: PlayerRoute
var _player: Node3D
var _points := PackedVector2Array()
var _gaits := PackedInt32Array()
var _status: Status = Status.IDLE
var _automatic: bool = false
var _index: int = 0
var _elapsed: float = 0.0
var _stall_timer: float = 0.0
var _best_distance: float = 0.0
var _distance_walked: float = 0.0
var _last_position: Vector2 = Vector2.ZERO
var _failure_message: String = ""
var _pressed := PackedByteArray()
var _horse: HorseController = null
var _horse_path := PackedVector3Array()
var _horse_path_index: int = 0
var _horse_path_route_index: int = -1
var _waiting_horse_path: bool = false


func _init() -> void:
	_pressed.resize(ACTIONS.size())
	process_physics_priority = PHYSICS_PRIORITY
	# Le pilote continue même si le jeu est en pause : un joueur immobilisé est alors signalé comme bloqué.
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	set_physics_process(_status == Status.RUNNING and _automatic)


func _physics_process(delta: float) -> void:
	tick(delta)


func _exit_tree() -> void:
	release_all()


## Renvoie un message décrivant pourquoi le joueur ne peut pas être piloté (vide si un seul Node3D est dans le groupe).
static func player_problem(tree: SceneTree) -> String:
	var players: Array[Node] = tree.get_nodes_in_group(PLAYER_GROUP)
	if players.is_empty():
		return "aucun joueur dans la scène (aucun nœud du groupe « player »)"
	if players.size() > 1:
		return "%d nœuds dans le groupe « player » : le joueur doit être unique" % players.size()
	if not players[0] is Node3D:
		return "le nœud %s du groupe « player » n'est pas un Node3D" % players[0].get_path()
	return ""


## Le joueur de la scène, ou null (voir player_problem() pour la raison).
static func find_player(tree: SceneTree) -> Node3D:
	if not player_problem(tree).is_empty():
		return null
	return tree.get_first_node_in_group(PLAYER_GROUP) as Node3D


static func actor_problem(tree: SceneTree, carrier: StringName) -> String:
	var actors: Array[Node] = tree.get_nodes_in_group(carrier)
	if actors.is_empty():
		return "aucun porteur dans la scène (groupe « %s » vide)" % carrier
	if actors.size() > 1:
		return "%d nœuds dans le groupe « %s » : le porteur doit être unique" % [actors.size(), carrier]
	if not actors[0] is Node3D:
		return "le nœud %s du groupe « %s » n'est pas un Node3D" % [actors[0].get_path(), carrier]
	return ""


static func find_actor(tree: SceneTree, carrier: StringName) -> Node3D:
	if not actor_problem(tree, carrier).is_empty():
		return null
	return tree.get_first_node_in_group(carrier) as Node3D


## Actions d'entrée dont le parcours a besoin (les allures absentes du parcours ne sont pas exigées).
static func required_actions(route: PlayerRoute) -> Array[StringName]:
	var actions: Array[StringName] = [MOVE_FORWARD, MOVE_BACK, MOVE_LEFT, MOVE_RIGHT]
	if route.uses_gait(PlayerRoute.Gait.RUN):
		actions.append(SPRINT)
	if route.uses_gait(PlayerRoute.Gait.WALK_SLOW):
		actions.append(WALK_SLOW)
	return actions


## Actions nécessaires au parcours mais absentes de la carte des entrées.
static func missing_actions(route: PlayerRoute) -> PackedStringArray:
	var missing := PackedStringArray()
	for action: StringName in required_actions(route):
		if not InputMap.has_action(action):
			missing.append(str(action))
	return missing


func setup(route: PlayerRoute, player: Node3D) -> void:
	release_all()
	_route = route
	_player = player
	_horse = player as HorseController
	_horse_path_route_index = -1
	_waiting_horse_path = false
	_horse_path = PackedVector3Array()
	_points = route.points
	_gaits = route.gaits
	_status = Status.IDLE
	_failure_message = ""
	set_physics_process(false)


## Place le joueur au départ du parcours, s'il en a un (le joueur est immobilisé).
func place_at_start() -> void:
	if not _route.has_start:
		return
	_player.global_position = _route.start_position
	var body: CharacterBody3D = _player as CharacterBody3D
	if body != null:
		body.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()


## Démarre le parcours. automatic = false : le pas est appelé par l'appelant (tick), sans _physics_process.
func begin(automatic: bool = true) -> void:
	_index = 0
	_elapsed = 0.0
	_distance_walked = 0.0
	_failure_message = ""
	var position3: Vector3 = _player.global_position
	_last_position = Vector2(position3.x, position3.z)
	_status = Status.RUNNING
	_apply_gait(_gaits[0])
	_reset_stall(_last_position.distance_to(_points[0]))
	_request_horse_path()
	_automatic = automatic
	set_physics_process(automatic)


## Un pas de pilotage : progression, blocage, durée maximale, puis intensités des actions.
func tick(delta: float) -> void:
	if _status != Status.RUNNING:
		return
	if not is_instance_valid(_player) or not _player.is_inside_tree():
		_player = null
		_fail(Status.PLAYER_LOST, "le joueur a quitté la scène pendant le parcours")
		return
	var position3: Vector3 = _player.global_position
	var position := Vector2(position3.x, position3.z)
	_distance_walked += position.distance_to(_last_position)
	_last_position = position
	_elapsed += delta
	var to_target: Vector2 = _points[_index] - position
	var distance: float = to_target.length()
	while distance <= _route.arrival_radius:
		_index += 1
		if _index >= _points.size():
			_status = Status.FINISHED
			_stop_driving()
			return
		_apply_gait(_gaits[_index])
		_request_horse_path()
		to_target = _points[_index] - position
		distance = to_target.length()
		_reset_stall(distance)
	if _horse != null:
		if _waiting_horse_path:
			if not _horse.poll_pipeline_path():
				_release_movement()
				return
			_waiting_horse_path = false
			_horse_path = _horse.pipeline_path()
			_horse_path_index = 0
		if not _horse_path.is_empty():
			while _horse_path_index < _horse_path.size() - 1:
				var path_point := Vector2(_horse_path[_horse_path_index].x, _horse_path[_horse_path_index].z)
				if position.distance_to(path_point) >= HORSE_PATH_REACH_M:
					break
				_horse_path_index += 1
				_reset_stall(INF)
			var path_target: Vector3 = _horse_path[_horse_path_index]
			to_target = Vector2(path_target.x, path_target.z) - position
			distance = to_target.length()
	if distance < _best_distance - _route.stall_min_progress:
		_best_distance = distance
		_stall_timer = 0.0
	else:
		_stall_timer += delta
		if _stall_timer >= _route.stall_time:
			_fail(Status.BLOCKED, "joueur bloqué depuis %.1f s" % _stall_timer)
			return
	if _elapsed >= _route.max_duration:
		_fail(Status.TIMED_OUT, "durée maximale du parcours (%.0f s) atteinte" % _route.max_duration)
		return
	var camera: Camera3D = _player.get_viewport().get_camera_3d()
	if camera == null:
		_fail(Status.NO_CAMERA, "aucune caméra active : les déplacements sont relatifs à la caméra")
		return
	_steer(to_target / distance, camera.global_basis)


## Arrête le parcours avant son terme (vidéo plus courte que le parcours) et relâche les actions.
func stop() -> void:
	if _status == Status.RUNNING:
		_status = Status.STOPPED
	_stop_driving()


## Relâche toutes les actions pressées par le pilote (et seulement celles-là).
func release_all() -> void:
	for i: int in ACTIONS.size():
		if _pressed[i] != 0:
			_pressed[i] = 0
			if InputMap.has_action(ACTIONS[i]):
				Input.action_release(ACTIONS[i])


func is_running() -> bool:
	return _status == Status.RUNNING


func has_failed() -> bool:
	return _status >= Status.BLOCKED


func get_status() -> Status:
	return _status


func get_status_name() -> String:
	return str(Status.keys()[_status]).to_lower()


func get_route() -> PlayerRoute:
	return _route


func get_elapsed() -> float:
	return _elapsed


func get_distance_walked() -> float:
	return _distance_walked


## Nombre de points de passage atteints.
func get_reached_count() -> int:
	return _points.size() if _status == Status.FINISHED else _index


func get_failure_message() -> String:
	return _failure_message


func _steer(direction: Vector2, camera_basis: Basis) -> void:
	# Avant de la caméra projeté au sol (x, z) ; caméra verticale : le haut de l'écran.
	var forward := Vector2(-camera_basis.z.x, -camera_basis.z.z)
	if forward.length_squared() < FLAT_EPSILON:
		forward = Vector2(camera_basis.y.x, camera_basis.y.z)
	forward = forward.normalized()
	var right := Vector2(-forward.y, forward.x)
	var side: float = direction.dot(right)
	var ahead: float = direction.dot(forward)
	_set_action(INDEX_RIGHT, side)
	_set_action(INDEX_LEFT, -side)
	_set_action(INDEX_FORWARD, ahead)
	_set_action(INDEX_BACK, -ahead)


func _set_action(index: int, strength: float) -> void:
	if strength > MIN_STRENGTH:
		Input.action_press(ACTIONS[index], minf(strength, 1.0))
		_pressed[index] = 1
	elif _pressed[index] != 0:
		Input.action_release(ACTIONS[index])
		_pressed[index] = 0


func _apply_gait(gait: int) -> void:
	_set_action(INDEX_SPRINT, 1.0 if gait == PlayerRoute.Gait.RUN else 0.0)
	_set_action(INDEX_WALK_SLOW, 1.0 if gait == PlayerRoute.Gait.WALK_SLOW else 0.0)


func _reset_stall(distance: float) -> void:
	_best_distance = distance
	_stall_timer = 0.0


func _stop_driving() -> void:
	set_physics_process(false)
	release_all()


func _request_horse_path() -> void:
	if _horse == null or _horse_path_route_index == _index:
		return
	_horse_path_route_index = _index
	_horse_path = PackedVector3Array()
	_horse_path_index = 0
	_waiting_horse_path = true
	var target := Vector3(_points[_index].x, _horse.global_position.y, _points[_index].y)
	_horse.request_pipeline_path(target)


func _release_movement() -> void:
	for index: int in 4:
		_set_action(index, 0.0)


func _fail(status: Status, reason: String) -> void:
	_status = status
	_stop_driving()
	var where: String = "position inconnue"
	if _player != null:
		var position3: Vector3 = _player.global_position
		where = "position (%.2f, %.2f, %.2f)" % [position3.x, position3.y, position3.z]
	var target: String = _route.ids[mini(_index, _route.ids.size() - 1)]
	_failure_message = (
		"Parcours %s : %s, %s, en allant vers « %s » (point %d sur %d, après %.1f s et %.1f m)."
		% [_route.source, reason, where, target, _index + 1, _points.size(), _elapsed, _distance_walked]
	)
