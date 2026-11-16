class_name HorseAudio
extends Node3D
## Sabots de Barq : les sons de pas enregistrés du jeu (autoload Footsteps, choisis selon la surface du sol), joués
## plus graves et plus forts (horse.json > audio). Aucune voix propre, aucun travail par image.

var _pitch: float = 1.0
var _volume_db: float = 0.0


func configure(settings: Dictionary) -> void:
	var data: Dictionary = JsonData.get_dictionary(settings, "audio", "horse.json")
	_pitch = JsonData.get_float(data, "hoof_pitch_scale", "horse.json > audio")
	_volume_db = JsonData.get_float(data, "hoof_volume_offset_db", "horse.json > audio")


## Un sabot posé : collider = Barq (sa méthode surface_at donne la surface du sol sous lui).
func hoof(world_position: Vector3, speed: float, collider: Object) -> void:
	var footsteps: Node = get_node_or_null(^"/root/Footsteps")
	if footsteps == null:
		return
	footsteps.call(&"play_footstep", world_position, speed, collider, Time.get_ticks_usec(), _pitch, _volume_db)
