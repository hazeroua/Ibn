class_name PlayerInput
extends RefCounted
## Lecture des entrées du personnage joueur, isolée pour tester la logique sans clavier ni manette.
##
## Dans le jeu, poll() lit les actions du contrat (Docs/contrats-mvp-1.md) : déplacement
## analogique, course et marche lente. Dans les tests, simulate() fixe les entrées et poll() ne
## lit plus rien. Une action absente de la carte des entrées est une erreur de données : elle est
## signalée une seule fois puis considérée comme relâchée.

const MOVE_LEFT: StringName = &"move_left"
const MOVE_RIGHT: StringName = &"move_right"
const MOVE_FORWARD: StringName = &"move_forward"
const MOVE_BACK: StringName = &"move_back"
const SPRINT: StringName = &"sprint"
const WALK_SLOW: StringName = &"walk_slow"
const JUMP: StringName = &"jump"

## Direction voulue dans le repère de la caméra : x vers la droite, y vers l'avant ; longueur ≤ 1.
var move: Vector2 = Vector2.ZERO
## Course maintenue.
var sprint: bool = false
## Marche lente maintenue.
var walk_slow: bool = false
## Saut demandé à cette image (appui, pas maintien).
var jump: bool = false
## Vrai : les entrées viennent de simulate() et poll() ne lit pas les actions.
var simulated: bool = false

var _checked: bool = false
var _has_move: bool = false
var _has_sprint: bool = false
var _has_walk_slow: bool = false
var _has_jump: bool = false


## Lit les actions d'entrée (une fois par image physique).
func poll() -> void:
	if simulated:
		return
	if not _checked:
		_check_actions()
	if _has_move:
		move = Input.get_vector(MOVE_LEFT, MOVE_RIGHT, MOVE_BACK, MOVE_FORWARD)
	sprint = _has_sprint and Input.is_action_pressed(SPRINT)
	walk_slow = _has_walk_slow and Input.is_action_pressed(WALK_SLOW)
	jump = _has_jump and Input.is_action_just_pressed(JUMP)


## Fixe les entrées (tests, pilotage) : poll() ne lit plus les actions.
func simulate(move_value: Vector2, sprint_value: bool = false, walk_slow_value: bool = false, jump_value: bool = false) -> void:
	simulated = true
	jump = jump_value
	move = move_value.limit_length(1.0)
	sprint = sprint_value
	walk_slow = walk_slow_value


## Revient à la lecture des actions (et revérifie qu'elles existent).
func use_actions() -> void:
	simulated = false
	_checked = false
	move = Vector2.ZERO
	sprint = false
	walk_slow = false
	jump = false


func _check_actions() -> void:
	_checked = true
	_has_move = _require(MOVE_LEFT) and _require(MOVE_RIGHT) and _require(MOVE_FORWARD) and _require(MOVE_BACK)
	_has_sprint = _require(SPRINT)
	_has_walk_slow = _require(WALK_SLOW)
	_has_jump = _require(JUMP)


func _require(action: StringName) -> bool:
	if InputMap.has_action(action):
		return true
	push_error("PlayerInput : l'action d'entrée « %s » n'est pas déclarée (res://data/config/input.json)." % action)
	return false
