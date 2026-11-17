class_name MedinaChecks
extends RefCounted
## Contrôles géométriques de la ville générée, avant toute construction de scène.
##
## - Chevauchements : volumes englobants réels des modules (mesurés sur les maillages importés),
##   transformés par l'instance ; seules les paires de couches déclarées dans allowed_overlaps peuvent
##   s'interpénétrer. Recherche par hachage spatial (seaux de BUCKET_M mètres) : coût proportionnel au
##   nombre de paires voisines, pas au carré du nombre d'instances.
## - Remparts : chaque mur est couvert sans trou par ses tronçons, ses tours d'angle et les piles de la
##   porte ; seule l'ouverture de la porte reste libre.
## - Limites : chaque instance est dans une cellule de la ville et dans l'enceinte (porte comprise).
## - Portes : l'espace devant chaque porte est une voie assez large pour le joueur.
## - Budgets : instances (total et par cellule), triangles, matériaux et formes de collision.

const BUCKET_M: float = 8.0
const COVER_TOLERANCE_M: float = 0.01
const PLAYER_SETTINGS_PATH: String = "res://data/player/locomotion.json"

var errors: PackedStringArray = PackedStringArray()
var stats: Dictionary = {}


class PrefabInfo:
	extends RefCounted
	var bounds: AABB = AABB()
	var triangles: int = 0
	var collision_shapes: int = 0
	var materials: Array[Material] = []


## Mesure chaque prefab du catalogue (volume englobant, triangles, matériaux, formes de collision).
static func measure_prefabs(catalog: Dictionary) -> Dictionary:
	var result := {}
	for raw_prefab: Variant in catalog.get("prefabs", []):
		var prefab: Dictionary = raw_prefab
		var scene: PackedScene = load(String(prefab["scene_path"])) as PackedScene
		if scene == null:
			push_error("MedinaChecks : prefab illisible : %s." % prefab["scene_path"])
			continue
		var root: Node3D = scene.instantiate() as Node3D
		var info := PrefabInfo.new()
		var first: bool = true
		for node: Node in root.find_children("*", "", true, false):
			if node is CollisionShape3D:
				info.collision_shapes += 1
			if not node is MeshInstance3D:
				continue
			var mesh_instance := node as MeshInstance3D
			var to_root: Transform3D = _transform_to(mesh_instance, root)
			var box: AABB = to_root * mesh_instance.get_aabb()
			info.bounds = box if first else info.bounds.merge(box)
			first = false
			var mesh: Mesh = mesh_instance.mesh
			for surface: int in mesh.get_surface_count():
				var arrays: Array = mesh.surface_get_arrays(surface)
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				info.triangles += (indices.size() if not indices.is_empty() else vertices.size()) / 3
				var material: Material = mesh_instance.get_active_material(surface)
				if material != null and not info.materials.has(material):
					info.materials.append(material)
		root.free()
		result[String(prefab["id"])] = info
	return result


static func _transform_to(node: Node3D, root: Node3D) -> Transform3D:
	var result: Transform3D = Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != root:
		if current is Node3D:
			result = (current as Node3D).transform * result
		current = current.get_parent()
	return result


## Volume englobant monde d'une instance (rotation autour de Y et échelle de l'instance).
static func instance_bounds(instance: Dictionary, local: AABB) -> AABB:
	var raw_position: Array = instance["position"]
	var raw_scale: Array = instance["scale"]
	var basis := Basis(Vector3.UP, float(instance["rotation_y"])).scaled_local(
		Vector3(float(raw_scale[0]), float(raw_scale[1]), float(raw_scale[2]))
	)
	var transform := Transform3D(basis, Vector3(float(raw_position[0]), float(raw_position[1]), float(raw_position[2])))
	return transform * local


func run(medina: MedinaDescription, plan: MedinaPlan, city: Dictionary, instances: Array[Dictionary], prefabs: Dictionary) -> bool:
	var tolerance: float = medina.parameter_float("overlap_tolerance_m")
	var bounds: Array[AABB] = []
	for instance: Dictionary in instances:
		var info: PrefabInfo = prefabs.get(String(instance["prefab_id"])) as PrefabInfo
		if info == null:
			errors.append("Instance %s : prefab non mesuré %s." % [instance["id"], instance["prefab_id"]])
			bounds.append(AABB())
			continue
		bounds.append(instance_bounds(instance, info.bounds))
	_check_limits(medina, plan, city, instances, bounds)
	_check_overlaps(medina, instances, bounds, tolerance)
	_check_ramparts(medina, plan, instances, bounds)
	_check_doors(plan, instances)
	_check_clearance(medina, plan, instances, bounds)
	_check_budgets(medina, instances, prefabs)
	return errors.is_empty()


func _check_limits(
	medina: MedinaDescription, plan: MedinaPlan, city: Dictionary, instances: Array[Dictionary], bounds: Array[AABB]
) -> void:
	var city_bounds: Dictionary = city["bounds"]
	var raw_min: Array = city_bounds["min_cell"]
	var raw_max: Array = city_bounds["max_cell"]
	var reach: float = maxf(medina.metric("city_gate", "depth_m"), medina.metric("rampart_straight", "thickness_m")) / 2.0
	var enclosure := Rect2(
		Vector2(MedinaDescription.cm_to_m(plan.enclosure.position.x), MedinaDescription.cm_to_m(plan.enclosure.position.y)),
		Vector2(MedinaDescription.cm_to_m(plan.enclosure.size.x), MedinaDescription.cm_to_m(plan.enclosure.size.y))
	)
	enclosure = enclosure.grow(reach + COVER_TOLERANCE_M)
	for index: int in instances.size():
		var instance: Dictionary = instances[index]
		var cell: Array = instance["cell"]
		if (
			int(cell[0]) < int(raw_min[0])
			or int(cell[1]) < int(raw_min[1])
			or int(cell[0]) > int(raw_max[0])
			or int(cell[1]) > int(raw_max[1])
		):
			errors.append("Instance %s hors des cellules de la ville (%s)." % [instance["id"], cell])
		var box: AABB = bounds[index]
		var flat := Rect2(Vector2(box.position.x, box.position.z), Vector2(box.size.x, box.size.z))
		if not enclosure.encloses(flat):
			errors.append("Instance %s sort de l'enceinte." % instance["id"])


func _check_overlaps(medina: MedinaDescription, instances: Array[Dictionary], bounds: Array[AABB], tolerance: float) -> void:
	var allowed := {}
	var overlaps: Dictionary = medina.section("allowed_overlaps")
	for raw_pair: Variant in overlaps.get("pairs", []):
		var pair: Array = raw_pair
		allowed["%s|%s" % [pair[0], pair[1]]] = true
		allowed["%s|%s" % [pair[1], pair[0]]] = true
	var buckets := {}
	for index: int in instances.size():
		var box: AABB = bounds[index]
		var low := Vector2i(floori(box.position.x / BUCKET_M), floori(box.position.z / BUCKET_M))
		var high := Vector2i(floori(box.end.x / BUCKET_M), floori(box.end.z / BUCKET_M))
		for bx: int in range(low.x, high.x + 1):
			for bz: int in range(low.y, high.y + 1):
				var key := Vector2i(bx, bz)
				if not buckets.has(key):
					buckets[key] = PackedInt32Array()
				var bucket: PackedInt32Array = buckets[key]
				bucket.append(index)
				buckets[key] = bucket
	var tested := {}
	var pairs: int = 0
	for key: Variant in buckets:
		var bucket: PackedInt32Array = buckets[key]
		for a: int in bucket.size():
			for b: int in range(a + 1, bucket.size()):
				var first: int = mini(bucket[a], bucket[b])
				var second: int = maxi(bucket[a], bucket[b])
				var pair_key: int = first * instances.size() + second
				if tested.has(pair_key):
					continue
				tested[pair_key] = true
				pairs += 1
				var intersection: AABB = bounds[first].intersection(bounds[second])
				if intersection.size.x <= tolerance or intersection.size.y <= tolerance or intersection.size.z <= tolerance:
					continue
				var layers: String = "%s|%s" % [instances[first]["layer"], instances[second]["layer"]]
				if not allowed.has(layers):
					errors.append(
						(
							"Chevauchement interdit entre %s et %s (%s m)."
							% [instances[first]["id"], instances[second]["id"], intersection.size]
						)
					)
	stats["overlap_pairs_tested"] = pairs


func _check_ramparts(medina: MedinaDescription, plan: MedinaPlan, instances: Array[Dictionary], bounds: Array[AABB]) -> void:
	var box: Rect2i = plan.enclosure
	var opening: float = medina.metric("city_gate", "opening_half_width_m")
	var pillar: float = medina.metric("city_gate", "pillar_outer_m")
	var walls: Dictionary = {
		"south": [true, box.end.y, box.position.x, box.end.x],
		"north": [true, box.position.y, box.position.x, box.end.x],
		"west": [false, box.position.x, box.position.y, box.end.y],
		"east": [false, box.end.x, box.position.y, box.end.y]
	}
	for wall: String in walls:
		var spec: Array = walls[wall]
		var along_x: bool = spec[0]
		var line: float = MedinaDescription.cm_to_m(int(spec[1]))
		var low: float = MedinaDescription.cm_to_m(int(spec[2]))
		var high: float = MedinaDescription.cm_to_m(int(spec[3]))
		var intervals: Array[Vector2] = []
		for index: int in instances.size():
			var layer: String = String(instances[index]["layer"])
			if layer != MedinaBuilder.LAYER_RAMPART and layer != MedinaBuilder.LAYER_GATE:
				continue
			var bound: AABB = bounds[index]
			var across_low: float = bound.position.z if along_x else bound.position.x
			var across_high: float = bound.end.z if along_x else bound.end.x
			if across_low > line + COVER_TOLERANCE_M or across_high < line - COVER_TOLERANCE_M:
				continue
			var a: float = bound.position.x if along_x else bound.position.z
			var b: float = bound.end.x if along_x else bound.end.z
			if layer == MedinaBuilder.LAYER_GATE:
				# Au sol, seules les piles de la porte ferment le mur ; le linteau ne compte pas.
				var center: float = (a + b) / 2.0
				intervals.append(Vector2(center - pillar, center - opening))
				intervals.append(Vector2(center + opening, center + pillar))
			else:
				intervals.append(Vector2(a, b))
		intervals.sort_custom(func(p: Vector2, q: Vector2) -> bool: return p.x < q.x)
		var reached: float = low
		var gate_gap: bool = false
		for interval: Vector2 in intervals:
			if interval.x > reached + COVER_TOLERANCE_M:
				var is_gate: bool = wall == plan.gate_wall and absf(interval.x - reached - 2.0 * opening) <= COVER_TOLERANCE_M
				if is_gate and not gate_gap:
					gate_gap = true
				else:
					errors.append("Trou dans le rempart %s entre %.2f et %.2f m." % [wall, reached, interval.x])
			reached = maxf(reached, interval.y)
		if reached < high - COVER_TOLERANCE_M:
			errors.append("Trou dans le rempart %s entre %.2f et %.2f m." % [wall, reached, high])


func _check_doors(plan: MedinaPlan, instances: Array[Dictionary]) -> void:
	var player: Dictionary = JsonData.load_dictionary(PLAYER_SETTINGS_PATH)
	var radius: float = JsonData.get_float(JsonData.get_dictionary(player, "body", "locomotion"), "radius", "locomotion.body")
	var reach: int = MedinaDescription.m_to_cm(radius) * 2 + 10
	var open: Array[Rect2i] = plan.open_rects()
	for instance: Dictionary in instances:
		if String(instance["layer"]) != MedinaBuilder.LAYER_DOOR:
			continue
		var raw_position: Array = instance["position"]
		var forward: Vector3 = Basis(Vector3.UP, float(instance["rotation_y"])) * Vector3.BACK
		var point := Vector2i(
			MedinaDescription.m_to_cm(float(raw_position[0]) + forward.x * float(reach) / 100.0),
			MedinaDescription.m_to_cm(float(raw_position[2]) + forward.z * float(reach) / 100.0)
		)
		var inside: bool = false
		for rect: Rect2i in open:
			if rect.has_point(point):
				inside = true
				break
		if not inside:
			errors.append("Porte %s inaccessible : pas de voie devant elle." % instance["id"])


## Les voies restent dégagées sur toute leur largeur : seuls les éléments qui enjambent la voie ou
## la meublent (arcs, passage, porte monumentale, fontaine, accessoires) peuvent y entrer.
func _check_clearance(medina: MedinaDescription, plan: MedinaPlan, instances: Array[Dictionary], bounds: Array[AABB]) -> void:
	var tolerance: float = medina.parameter_float("overlap_tolerance_m")
	var exempt: Array = medina.section("clearance").get("exempt_layers", [])
	var open: Array[Rect2] = []
	for rect: Rect2i in plan.open_rects():
		var low := Vector2(MedinaDescription.cm_to_m(rect.position.x), MedinaDescription.cm_to_m(rect.position.y))
		open.append(Rect2(low, Vector2(MedinaDescription.cm_to_m(rect.size.x), MedinaDescription.cm_to_m(rect.size.y))).grow(-tolerance))
	for index: int in instances.size():
		if exempt.has(String(instances[index]["layer"])):
			continue
		var box: AABB = bounds[index]
		var flat := Rect2(Vector2(box.position.x, box.position.z), Vector2(box.size.x, box.size.z))
		for rect: Rect2 in open:
			if rect.intersects(flat):
				errors.append("Instance %s empiète sur une voie ou sur la place." % instances[index]["id"])
				break


func _check_budgets(medina: MedinaDescription, instances: Array[Dictionary], prefabs: Dictionary) -> void:
	var budgets: Dictionary = medina.section("budgets")
	var per_cell := {}
	var triangles: int = 0
	var shapes: int = 0
	var materials: Array[Material] = []
	for instance: Dictionary in instances:
		var key: String = str(instance["cell"])
		per_cell[key] = int(per_cell.get(key, 0)) + 1
		var info: PrefabInfo = prefabs.get(String(instance["prefab_id"])) as PrefabInfo
		if info == null:
			continue
		triangles += info.triangles
		shapes += info.collision_shapes
		for material: Material in info.materials:
			if not materials.has(material):
				materials.append(material)
	var busiest: int = 0
	for key: Variant in per_cell:
		busiest = maxi(busiest, int(per_cell[key]))
	stats["instances"] = instances.size()
	stats["busiest_cell_instances"] = busiest
	stats["triangles"] = triangles
	stats["materials"] = materials.size()
	stats["collision_shapes"] = shapes
	var limits: Array = [
		["instances", "max_instances"],
		["busiest_cell_instances", "max_instances_per_cell"],
		["triangles", "max_triangles"],
		["materials", "max_materials"],
		["collision_shapes", "max_collision_shapes"]
	]
	for limit: Array in limits:
		var value: int = int(stats[limit[0]])
		var budget: int = int(budgets.get(limit[1], -1))
		if budget < 0:
			errors.append("medina.budgets.%s est requis." % limit[1])
		elif value > budget:
			errors.append("Budget dépassé : %s = %d pour %d autorisés." % [limit[0], value, budget])
