class_name PlayerPhysicsCase
extends GutTest
## Base des tests physiques du personnage joueur : monde construit par le test, personnage à entrées
## simulées, durées exprimées en secondes de simulation. La cadence physique est remise à sa valeur
## d'origine après chaque test.

const SETTLE_FRAMES: int = 12

var _saved_ticks: int = 60


func before_each() -> void:
	_saved_ticks = Engine.physics_ticks_per_second


func after_each() -> void:
	Engine.physics_ticks_per_second = _saved_ticks


## Racine du monde de test, libérée automatiquement à la fin du test.
func _new_world() -> Node3D:
	var world := Node3D.new()
	world.name = "MondeDeTest"
	add_child_autofree(world)
	return world


## Personnage posé juste au-dessus de position, regard vers yaw, entrées simulées à zéro.
func _spawn(world: Node3D, position: Vector3 = Vector3(0.0, 0.02, 0.0), yaw: float = 0.0) -> PlayerCharacter:
	var player := PlayerCharacter.new()
	world.add_child(player)
	player.teleport_to(position, yaw)
	player.input.simulate(Vector2.ZERO)
	return player


## Attend l'équivalent de seconds secondes de simulation (images physiques).
func _simulate(seconds: float) -> void:
	await wait_physics_frames(int(ceil(seconds * float(Engine.physics_ticks_per_second))))


## Laisse le personnage se poser sur le sol.
func _settle() -> void:
	await wait_physics_frames(SETTLE_FRAMES)


func _horizontal_distance(from: Vector3, to: Vector3) -> float:
	return Vector2(to.x - from.x, to.z - from.z).length()
