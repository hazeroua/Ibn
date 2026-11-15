class_name Viewpoint
extends RefCounted
## Point de vue nommé (position et orientation de la caméra), utilisé par les captures et les mesures.

var id: String
var transform: Transform3D


func _init(viewpoint_id: String, viewpoint_transform: Transform3D) -> void:
	id = viewpoint_id
	transform = viewpoint_transform
