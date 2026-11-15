class_name Viewpoints
extends RefCounted
## Chargement des points de vue depuis un fichier JSON et parcours interpolé entre eux.
##
## Format : {"viewpoints": [{"id": "vue_generale", "position": [x, y, z], "target": [x, y, z]}, …]}


static func load_file(path: String) -> Array[Viewpoint]:
	var result: Array[Viewpoint] = []
	var data: Dictionary = JsonData.load_dictionary(path)
	var ids: Dictionary[String, bool] = {}
	for raw: Variant in JsonData.get_array(data, "viewpoints", path):
		if typeof(raw) != TYPE_DICTIONARY:
			push_error("Viewpoints : chaque point de vue doit être un objet (%s)." % path)
			continue
		var entry: Dictionary = raw
		var viewpoint_id: String = JsonData.get_string(entry, "id", path)
		if viewpoint_id.is_empty() or viewpoint_id.validate_filename() != viewpoint_id or ids.has(viewpoint_id):
			push_error("Viewpoints : identifiant absent, invalide ou en double « %s » (%s)." % [viewpoint_id, path])
			continue
		ids[viewpoint_id] = true
		var position: Vector3 = JsonData.get_vector3(entry, "position", viewpoint_id)
		var target: Vector3 = JsonData.get_vector3(entry, "target", viewpoint_id)
		var direction: Vector3 = target - position
		if direction.length_squared() < 0.0001 or direction.normalized().cross(Vector3.UP).length_squared() < 0.0001:
			push_error("Viewpoints : « %s » doit regarder une cible distincte et non verticale (%s)." % [viewpoint_id, path])
			continue
		result.append(Viewpoint.new(viewpoint_id, Transform3D(Basis.IDENTITY, position).looking_at(target, Vector3.UP)))
	return result


## Transformation de la caméra au temps normalisé t (0 à 1) d'un parcours qui relie les points dans l'ordre.
static func sample(points: Array[Viewpoint], t: float) -> Transform3D:
	var count: int = points.size()
	if count == 0:
		return Transform3D.IDENTITY
	if count == 1:
		return points[0].transform
	var scaled: float = clampf(t, 0.0, 1.0) * float(count - 1)
	var index: int = mini(int(scaled), count - 2)
	var local_t: float = scaled - float(index)
	return points[index].transform.interpolate_with(points[index + 1].transform, local_t)
