class_name PlayerTestWorld
extends RefCounted
## Scènes de test du personnage joueur : sol, pente, mur, escalier, obstacles. Tout est construit
## par le test lui-même (couche 1 = monde), sans dépendre d'une carte du jeu.

const WORLD_LAYER: int = 1


## Bloc statique de la couche « monde ».
static func box(parent: Node, size: Vector3, position: Vector3, rotation: Vector3 = Vector3.ZERO, shape: BoxShape3D = null) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = WORLD_LAYER
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	if shape == null:
		shape = BoxShape3D.new()
		shape.size = size
	collision.shape = shape
	body.add_child(collision)
	body.position = position
	body.rotation = rotation
	parent.add_child(body)
	return body


## Grand sol plat dont le dessus est à y = 0 ; sa surface est marquée dans la métadonnée « surface ».
static func ground(parent: Node, surface: String = "pierre", half_extent: float = 100.0) -> StaticBody3D:
	var body: StaticBody3D = box(parent, Vector3(half_extent * 2.0, 1.0, half_extent * 2.0), Vector3(0.0, -0.5, 0.0))
	body.set_meta(&"surface", surface)
	return body


## Pente qui part du niveau du sol à z = start_z et monte vers -Z avec l'angle donné.
static func ramp(parent: Node, degrees: float, start_z: float, x: float = 0.0, length: float = 30.0) -> StaticBody3D:
	var angle: float = deg_to_rad(degrees)
	var thickness: float = 1.0
	var normal := Vector3(0.0, cos(angle), sin(angle))
	var surface_point := Vector3(x, 0.0, start_z)
	var center: Vector3 = surface_point - normal * thickness * 0.5
	return box(parent, Vector3(8.0, thickness, length), center, Vector3(angle, 0.0, 0.0))


## Escalier qui monte vers -Z : count marches de hauteur rise et de profondeur run, à partir de z = start_z.
static func stairs(parent: Node, count: int, rise: float, run: float, start_z: float, x: float = 0.0) -> void:
	for i: int in count:
		var height: float = rise * float(i + 1)
		box(parent, Vector3(6.0, height, run), Vector3(x, height * 0.5, start_z - run * (float(i) + 0.5)))


## Obstacles de même forme (un seul BoxShape3D partagé), répartis au hasard sans recouvrir la zone libre du départ.
static func scatter(parent: Node, count: int, half_extent: float, free_radius: float, seed_value: int) -> void:
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.6, 1.4, 0.6)
	var generator := RandomNumberGenerator.new()
	generator.seed = seed_value
	var placed: int = 0
	while placed < count:
		var at := Vector2(generator.randf_range(-half_extent, half_extent), generator.randf_range(-half_extent, half_extent))
		if at.length() < free_radius:
			continue
		box(parent, shape.size, Vector3(at.x, 0.7, at.y), Vector3(0.0, generator.randf_range(0.0, PI), 0.0), shape)
		placed += 1
