class_name CollinesObstacles
extends RefCounted
## Placement déterministe des obstacles de la zone de pire cas de la carte « collines ».
##
## Tirage de fléchettes dans un disque, sans chevauchement (chaque obstacle occupe un cercle d'empreinte),
## avec une grille spatiale à listes chaînées : insertion en O(1), test de voisinage sur 9 cellules, donc
## O(n × essais) au total, quel que soit le nombre d'obstacles. Les plus grands sont placés en premier, ce qui
## garde le tassement possible jusqu'à une forte densité. Même graine et mêmes données : même résultat.

const CONTEXT: String = "collines.json > obstacles > zone"

## Indice du type de chaque obstacle (dans l'ordre de placement).
var type_indices := PackedInt32Array()
## Position (x, z) du centre de chaque obstacle dans le monde.
var positions := PackedVector2Array()
## Rotation autour de l'axe vertical, en radians.
var yaws := PackedFloat32Array()


## Place count obstacles. radii et weights ont une entrée par type. Renvoie null si la zone est trop dense.
static func place(zone: Dictionary, radii: PackedFloat32Array, weights: PackedFloat32Array) -> CollinesObstacles:
	var count: int = JsonData.get_int(zone, "count", CONTEXT)
	var center: Vector2 = JsonData.get_vector2(zone, "center", CONTEXT)
	var radius: float = JsonData.get_float(zone, "radius_m", CONTEXT)
	var gap: float = JsonData.get_float(zone, "gap_m", CONTEXT)
	var seed_value: int = JsonData.get_int(zone, "seed", CONTEXT)
	var max_attempts: int = JsonData.get_int(zone, "max_attempts_per_obstacle", CONTEXT)
	if count <= 0 or radius <= 0.0 or gap < 0.0 or max_attempts <= 0 or radii.is_empty() or radii.size() != weights.size():
		push_error("CollinesObstacles : paramètres de zone invalides (%s)." % CONTEXT)
		return null
	var type_counts: PackedInt32Array = _split_counts(count, weights)
	if type_counts.is_empty():
		return null

	# Ordre de placement : types par rayon décroissant.
	var type_order: Array[int] = []
	for type_index: int in radii.size():
		type_order.append(type_index)
	type_order.sort_custom(func(a: int, b: int) -> bool: return radii[a] > radii[b] or (radii[a] == radii[b] and a < b))

	var max_radius: float = 0.0
	for footprint: float in radii:
		max_radius = maxf(max_radius, footprint)
	var cell_size: float = 2.0 * max_radius + gap
	var cells_per_side: int = int(ceilf(2.0 * radius / cell_size)) + 1
	var cell_head := PackedInt32Array()
	cell_head.resize(cells_per_side * cells_per_side)
	cell_head.fill(-1)
	var next_in_cell := PackedInt32Array()
	next_in_cell.resize(count)
	var placed_radius := PackedFloat32Array()
	placed_radius.resize(count)

	var result := CollinesObstacles.new()
	result.type_indices.resize(count)
	result.positions.resize(count)
	result.yaws.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var placed: int = 0
	for type_index: int in type_order:
		var footprint: float = radii[type_index]
		var room: float = radius - footprint
		if room < 0.0:
			push_error("CollinesObstacles : l'empreinte du type %d dépasse la zone (%s)." % [type_index, CONTEXT])
			return null
		for _n: int in type_counts[type_index]:
			var accepted: bool = false
			for _attempt: int in max_attempts:
				var distance: float = room * sqrt(rng.randf())
				var angle: float = rng.randf() * TAU
				var offset := Vector2(cos(angle), sin(angle)) * distance
				var cell_x: int = int((offset.x + radius) / cell_size)
				var cell_z: int = int((offset.y + radius) / cell_size)
				if _collides(
					offset, footprint, gap, cell_x, cell_z, cells_per_side, cell_head, next_in_cell, result.positions, placed_radius, center
				):
					continue
				var cell: int = cell_z * cells_per_side + cell_x
				next_in_cell[placed] = cell_head[cell]
				cell_head[cell] = placed
				placed_radius[placed] = footprint
				result.positions[placed] = center + offset
				result.type_indices[placed] = type_index
				result.yaws[placed] = rng.randf() * TAU
				placed += 1
				accepted = true
				break
			if not accepted:
				push_error("CollinesObstacles : zone trop dense, %d obstacles sur %d placés (%s)." % [placed, count, CONTEXT])
				return null
	return result


## Nombre d'obstacles par type selon les poids (méthode du plus fort reste : la somme vaut toujours count).
static func _split_counts(count: int, weights: PackedFloat32Array) -> PackedInt32Array:
	var total: float = 0.0
	for weight: float in weights:
		if weight < 0.0:
			push_error("CollinesObstacles : poids négatif (%s)." % CONTEXT)
			return PackedInt32Array()
		total += weight
	if total <= 0.0:
		push_error("CollinesObstacles : la somme des poids doit être strictement positive (%s)." % CONTEXT)
		return PackedInt32Array()
	var counts := PackedInt32Array()
	counts.resize(weights.size())
	var remainders := PackedFloat32Array()
	remainders.resize(weights.size())
	var assigned: int = 0
	for i: int in weights.size():
		var exact: float = float(count) * weights[i] / total
		counts[i] = int(floorf(exact))
		remainders[i] = exact - float(counts[i])
		assigned += counts[i]
	while assigned < count:
		var best: int = 0
		for i: int in weights.size():
			if remainders[i] > remainders[best]:
				best = i
		counts[best] += 1
		remainders[best] = -1.0
		assigned += 1
	return counts


static func _collides(
	offset: Vector2,
	footprint: float,
	gap: float,
	cell_x: int,
	cell_z: int,
	cells_per_side: int,
	cell_head: PackedInt32Array,
	next_in_cell: PackedInt32Array,
	positions: PackedVector2Array,
	placed_radius: PackedFloat32Array,
	center: Vector2
) -> bool:
	var world_position: Vector2 = center + offset
	for neighbor_z: int in range(maxi(cell_z - 1, 0), mini(cell_z + 2, cells_per_side)):
		for neighbor_x: int in range(maxi(cell_x - 1, 0), mini(cell_x + 2, cells_per_side)):
			var other: int = cell_head[neighbor_z * cells_per_side + neighbor_x]
			while other >= 0:
				var min_distance: float = footprint + placed_radius[other] + gap
				if world_position.distance_squared_to(positions[other]) < min_distance * min_distance:
					return true
				other = next_in_cell[other]
	return false
