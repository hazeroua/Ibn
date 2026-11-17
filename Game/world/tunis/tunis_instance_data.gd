class_name TunisInstanceData
extends RefCounted
## Représentation typée et immuable d'une instance validée de la ville.

var id: StringName
var prefab_id: StringName
var cell: Vector2i
var transform: Transform3D
var layer: StringName
var properties: Dictionary


static func from_dictionary(data: Dictionary) -> TunisInstanceData:
	var result := TunisInstanceData.new()
	result.id = StringName(data["id"])
	result.prefab_id = StringName(data["prefab_id"])
	var raw_cell: Array = data["cell"]
	result.cell = Vector2i(int(raw_cell[0]), int(raw_cell[1]))
	var raw_position: Array = data["position"]
	var raw_scale: Array = data["scale"]
	# Même convention qu'un Node3D (rotation puis échelle dans les axes locaux du module) : une
	# échelle non uniforme suit le module tourné au lieu de s'appliquer aux axes du monde.
	var basis := Basis(Vector3.UP, float(data["rotation_y"]))
	basis = basis.scaled_local(Vector3(float(raw_scale[0]), float(raw_scale[1]), float(raw_scale[2])))
	result.transform = Transform3D(basis, Vector3(float(raw_position[0]), float(raw_position[1]), float(raw_position[2])))
	result.layer = StringName(data["layer"])
	result.properties = (data["properties"] as Dictionary).duplicate(true)
	result.properties.make_read_only()
	return result
