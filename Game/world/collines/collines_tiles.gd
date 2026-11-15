class_name CollinesTiles
extends RefCounted
## Maillage du terrain de la carte « collines » : tuiles carrées, chacune en plusieurs niveaux de détail.
##
## Chaque tuile possède un MeshInstance3D par niveau de détail ; le moteur choisit le niveau d'après la distance à
## la caméra (plages de visibilité, évaluées par le rendu sans script par image). Les plages ne se chevauchent pas :
## un seul niveau est dessiné par tuile. Une jupe verticale en bordure de chaque niveau cache les fissures entre
## tuiles de niveaux différents. Les gabarits d'indices sont calculés une fois par niveau et partagés par toutes
## les tuiles : seule la hauteur des sommets change d'une tuile à l'autre.
##
## Pire cas : 64 tuiles × 4 niveaux, environ 1,4 million de sommets au total, tous niveaux confondus.

const CONTEXT: String = "collines.json > terrain > tiles"


## Niveau de détail : pas de la grille (en mailles du relief), distance de fin (0 = illimité) et gabarits partagés.
class Lod:
	extends RefCounted
	var step: int = 1
	var range_end: float = 0.0
	var vertices_per_side: int = 0
	var ring := PackedInt32Array()
	var indices := PackedInt32Array()


## Construit le nœud « Tuiles » (une tuile par case, un maillage par niveau). Renvoie null si les données sont invalides.
static func build(relief: CollinesRelief, config: Dictionary, material: Material) -> Node3D:
	var tile_cells: int = JsonData.get_int(config, "tile_cells", CONTEXT)
	var skirt_depth: float = JsonData.get_float(config, "skirt_depth_m", CONTEXT)
	var lods: Array[Lod] = _parse_lods(JsonData.get_array(config, "lods", CONTEXT), tile_cells)
	var cells: int = relief.size_px - 1
	if lods.is_empty() or tile_cells <= 0 or skirt_depth < 0.0 or cells % tile_cells != 0:
		push_error("CollinesTiles : tuiles invalides : tile_cells doit diviser les %d mailles du relief (%s)." % [cells, CONTEXT])
		return null
	@warning_ignore("integer_division")
	var tiles_per_side: int = cells / tile_cells
	var parent := Node3D.new()
	parent.name = "Tuiles"
	var tile_size: float = float(tile_cells) * relief.spacing
	for tile_z: int in tiles_per_side:
		for tile_x: int in tiles_per_side:
			var tile := Node3D.new()
			tile.name = "Tuile_%d_%d" % [tile_x, tile_z]
			tile.position = Vector3(relief.origin.x + float(tile_x) * tile_size, 0.0, relief.origin.y + float(tile_z) * tile_size)
			parent.add_child(tile)
			var range_begin: float = 0.0
			for lod_index: int in lods.size():
				var lod: Lod = lods[lod_index]
				var instance := MeshInstance3D.new()
				instance.name = "Lod%d" % lod_index
				instance.mesh = _build_mesh(relief, lod, tile_cells, tile_x, tile_z, skirt_depth)
				instance.material_override = material
				instance.visibility_range_begin = range_begin
				instance.visibility_range_end = lod.range_end
				instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
				tile.add_child(instance)
				range_begin = lod.range_end
	return parent


static func _parse_lods(entries: Array, tile_cells: int) -> Array[Lod]:
	var result: Array[Lod] = []
	var previous_end: float = 0.0
	for raw: Variant in entries:
		if typeof(raw) != TYPE_DICTIONARY:
			push_error("CollinesTiles : chaque niveau de détail doit être un objet JSON (%s)." % CONTEXT)
			return []
		var entry: Dictionary = raw
		var lod := Lod.new()
		lod.step = JsonData.get_int(entry, "step", CONTEXT)
		lod.range_end = JsonData.get_float(entry, "range_end_m", CONTEXT)
		var is_last: bool = result.size() == entries.size() - 1
		if lod.step <= 0 or tile_cells % lod.step != 0 or (is_last and lod.range_end != 0.0):
			push_error("CollinesTiles : niveau de détail invalide (pas %d, fin %.1f) (%s)." % [lod.step, lod.range_end, CONTEXT])
			return []
		if not is_last and lod.range_end <= previous_end:
			push_error("CollinesTiles : les distances de fin doivent croître (%s)." % CONTEXT)
			return []
		previous_end = lod.range_end
		@warning_ignore("integer_division")
		var cells_per_side: int = tile_cells / lod.step
		lod.vertices_per_side = cells_per_side + 1
		lod.ring = _perimeter_ring(lod.vertices_per_side)
		lod.indices = _index_template(lod.vertices_per_side, lod.ring)
		result.append(lod)
	return result


## Indices des sommets du pourtour d'une grille n × n, dans l'ordre : haut, droite, bas, gauche.
static func _perimeter_ring(n: int) -> PackedInt32Array:
	var ring := PackedInt32Array()
	for i: int in n:
		ring.append(i)
	for j: int in range(1, n):
		ring.append(j * n + n - 1)
	for i: int in range(n - 2, -1, -1):
		ring.append((n - 1) * n + i)
	for j: int in range(n - 2, 0, -1):
		ring.append(j * n)
	return ring


## Triangles de la grille (sens horaire vu du dessus, face avant de Godot), puis ceux de la jupe.
static func _index_template(n: int, ring: PackedInt32Array) -> PackedInt32Array:
	var indices := PackedInt32Array()
	indices.resize((n - 1) * (n - 1) * 6 + ring.size() * 6)
	var cursor: int = 0
	for j: int in n - 1:
		for i: int in n - 1:
			var a: int = j * n + i
			var c: int = a + n
			indices[cursor] = a
			indices[cursor + 1] = a + 1
			indices[cursor + 2] = c
			indices[cursor + 3] = a + 1
			indices[cursor + 4] = c + 1
			indices[cursor + 5] = c
			cursor += 6
	var skirt_base: int = n * n
	for k: int in ring.size():
		var next: int = (k + 1) % ring.size()
		indices[cursor] = ring[k]
		indices[cursor + 1] = ring[next]
		indices[cursor + 2] = skirt_base + k
		indices[cursor + 3] = ring[next]
		indices[cursor + 4] = skirt_base + next
		indices[cursor + 5] = skirt_base + k
		cursor += 6
	return indices


static func _build_mesh(relief: CollinesRelief, lod: Lod, tile_cells: int, tile_x: int, tile_z: int, skirt_depth: float) -> ArrayMesh:
	var n: int = lod.vertices_per_side
	var vertices := PackedVector3Array()
	vertices.resize(n * n + lod.ring.size())
	var first_row: int = tile_z * tile_cells
	var first_column: int = tile_x * tile_cells
	var spacing: float = relief.spacing
	var out: int = 0
	for j: int in n:
		var row: int = (first_row + j * lod.step) * relief.size_px + first_column
		var z: float = float(j * lod.step) * spacing
		for i: int in n:
			vertices[out] = Vector3(float(i * lod.step) * spacing, relief.heights[row + i * lod.step], z)
			out += 1
	var drop := Vector3(0.0, skirt_depth, 0.0)
	for k: int in lod.ring.size():
		vertices[out] = vertices[lod.ring[k]] - drop
		out += 1
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = lod.indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
