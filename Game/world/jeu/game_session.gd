class_name GameSession
extends Node3D
## Racine du jeu du MVP 1 : assemble la carte « collines », le joueur, son modèle, la caméra à la troisième
## personne et les sons de pas. Tout se fait une seule fois au chargement ; aucun traitement par image.

const CHARACTER_ID: String = "ibn_khaldoun_jeune"
const SPAWN_GROUP: StringName = &"player_spawn"
const MAP_NODE: String = "Carte"

@export var character_id: String = CHARACTER_ID


func _ready() -> void:
	var map: Node = get_node_or_null(MAP_NODE)
	if map == null:
		push_error("GameSession : nœud « %s » absent." % MAP_NODE)
		return
	var spawn: Node3D = get_tree().get_first_node_in_group(SPAWN_GROUP) as Node3D
	if spawn == null:
		push_error("GameSession : aucun point d'apparition (groupe « %s »)." % SPAWN_GROUP)
		return
	for camera: Node in map.find_children("*", "Camera3D", true, false):
		(camera as Camera3D).current = false
	var player := PlayerCharacter.new()
	player.name = "Joueur"
	add_child(player)
	player.teleport_to(spawn.global_position, spawn.global_rotation.y)
	_attach_model(player)
	var rig := ThirdPersonCamera.new()
	rig.name = "Camera"
	add_child(rig)
	rig.set_target(player)
	rig.snap()
	var footsteps: FootstepSystem = get_node("/root/Footsteps") as FootstepSystem
	footsteps.connect_emitter(player)
	var input: GameInput = get_node("/root/GameInput") as GameInput
	input.set_mouse_capture(true)


func _attach_model(player: PlayerCharacter) -> void:
	var scene: PackedScene = CharacterCatalog.load_scene(character_id)
	if scene == null:
		return
	var model: Node3D = scene.instantiate() as Node3D
	model.name = "Modele"
	player.add_child(model)
	player.animation_player = CharacterCatalog.find_animation_player(model)
