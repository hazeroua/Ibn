class_name TunisPaving
extends RefCounted
## Dallage visuel de la médina. Le relief et les collisions restent ceux du terrain.

const TEXTURE: Texture2D = preload("res://assets/tunis/tunis_paving.png")


static func create(enclosure: Rect2) -> MeshInstance3D:
	var paving := MeshInstance3D.new()
	paving.name = "MedinaPaving"
	var plane := PlaneMesh.new()
	plane.size = enclosure.size + Vector2(2.0, 2.0)
	paving.mesh = plane
	paving.position = Vector3(enclosure.get_center().x, 0.035, enclosure.get_center().y)
	var finish := StandardMaterial3D.new()
	finish.albedo_texture = TEXTURE
	finish.uv1_scale = Vector3(26.0, 24.0, 1.0)
	finish.roughness = 0.92
	paving.material_override = finish
	return paving
