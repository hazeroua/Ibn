class_name HorseMountSystem
extends Node3D
## Montage, démontage, appel et caméra de monte de Barq.

const SETTINGS_PATH: String = "res://data/horse/horse.json"
const MOUNT_ACTION: StringName = &"mount_horse"
const WHISTLE_ACTION: StringName = &"horse_whistle"

var player: PlayerCharacter
var camera_rig: ThirdPersonCamera
var horse: HorseController
var heightfield: DesertHeightfield
var traces: HorseTraces
var audio: HorseAudio
var mounted: bool = false
var _settings: Dictionary
var _last_hoof_position: Vector3 = Vector3.ZERO


func setup(owner_player: PlayerCharacter, rig: ThirdPersonCamera, field: DesertHeightfield) -> void:
	player = owner_player
	camera_rig = rig
	heightfield = field
	_settings = JsonData.load_dictionary(SETTINGS_PATH)
	_spawn_horse()


func _ready() -> void:
	process_priority = -10


func _physics_process(_delta: float) -> void:
	if horse == null or player == null:
		return
	if Input.is_action_just_pressed(WHISTLE_ACTION) and not mounted:
		horse.call_to(player.global_position)
	if Input.is_action_just_pressed(MOUNT_ACTION):
		if mounted:
			dismount()
		elif (
			player.global_position.distance_to(horse.global_position)
			<= float((_settings.get("call", {}) as Dictionary).get("stop_distance_m", 5.0))
		):
			mount()
	if mounted:
		var move: Vector2 = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
		horse.set_input(move, Input.is_action_pressed(&"sprint"))
		player.global_position = horse.saddle_position()
		player.rotation = horse.rotation


func mount() -> void:
	mounted = true
	horse.mounted = true
	player.process_mode = Node.PROCESS_MODE_DISABLED
	if camera_rig != null:
		camera_rig.set_target(horse)
		camera_rig.snap()


func dismount() -> void:
	mounted = false
	horse.mounted = false
	player.process_mode = Node.PROCESS_MODE_INHERIT
	var side: Vector3 = horse.global_basis.x * 1.5
	player.teleport_to(horse.global_position + side, horse.rotation.y)
	if camera_rig != null:
		camera_rig.set_target(player)
		camera_rig.snap()


func _spawn_horse() -> void:
	horse = HorseController.new(heightfield)
	horse.name = "Barq"
	add_child(horse)
	horse.global_position = player.global_position + Vector3(2.5, 0.0, 1.0)
	if heightfield != null:
		horse.global_position.y = heightfield.height_at(horse.global_position.x, horse.global_position.z)
	traces = HorseTraces.new()
	traces.name = "Traces"
	traces.configure(_settings)
	horse.add_child(traces)
	audio = HorseAudio.new()
	audio.name = "Audio"
	audio.configure(_settings)
	horse.add_child(audio)
	horse.hoofstep.connect(_on_hoofstep)


func _on_hoofstep(world_position: Vector3, speed: float, surface: StringName) -> void:
	if traces != null:
		traces.place(world_position, horse.rotation.y, surface)
	if audio != null:
		audio.hoof(surface, speed)
