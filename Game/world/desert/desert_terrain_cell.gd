class_name DesertTerrainCell
extends RefCounted
## Fournisseur de cellules du désert pour le streaming : build_cell(cell) construit une cellule de 250 m.
##
## Chaque cellule est un DesertCellBody (couche de collision 1) avec une carte de hauteurs de collision et un
## maillage par niveau de détail (4 niveaux, plages de visibilité contiguës : un seul est dessiné à la fois).
## Les sommets portent la normale et le poids des surfaces (couleur : R = pierre, V = terre,
## B = galets, A = proximité du lit d'oued), calculés une seule
## fois sur la grille fine puis sous-échantillonnés : tous les niveaux de détail ont le même éclairage. Une jupe
## verticale cache les fissures entre cellules de niveaux différents. Les gabarits d'indices sont partagés.
## build_cell n'utilise ni l'arbre de scène ni d'état modifié : il s'exécute sans risque dans un fil de chargement.
##
## Pire cas : 256 cellules, chacune à 4 niveaux ; une cellule fine compte 101 × 101 sommets (20 000 triangles) et
## coûte 103 × 103 lectures de hauteur ; tous niveaux confondus, environ 14 000 sommets par cellule.

const CONTEXT: String = "desert.json > terrain > cell"
const SHADING_CONTEXT: String = "desert.json > terrain > shading"
const SHADER_PATH: String = "res://world/desert/desert_terrain.gdshader"
const POLYHAVEN_DIR: String = "res://assets/textures/polyhaven"


## Niveau de détail : pas (en mailles fines), distance de fin (0 = illimité) et gabarits partagés.
class Lod:
	extends RefCounted
	var step: int = 1
	var range_end: float = 0.0
	var vertices_per_side: int = 0
	var ring := PackedInt32Array()
	var indices := PackedInt32Array()


var heightfield: DesertHeightfield
var material: ShaderMaterial

var _spacing: float = 1.0
var _cells: int = 0
var _skirt_depth: float = 0.0
var _collision_mask: int = 1
var _lods: Array[Lod] = []


## Crée le fournisseur depuis desert.json (ou null si les données ou les textures sont invalides).
static func from_data(data: Dictionary, configured_field: DesertHeightfield = null) -> DesertTerrainCell:
	var field: DesertHeightfield = configured_field if configured_field != null else DesertHeightfield.from_data(data)
	if field == null:
		return null
	var terrain: Dictionary = JsonData.get_dictionary(data, "terrain", DesertHeightfield.CONTEXT)
	var config: Dictionary = JsonData.get_dictionary(terrain, "cell", CONTEXT)
	var provider := DesertTerrainCell.new()
	provider.heightfield = field
	provider._spacing = JsonData.get_float(config, "vertex_spacing_m", CONTEXT)
	provider._skirt_depth = JsonData.get_float(config, "skirt_depth_m", CONTEXT)
	provider._collision_mask = JsonData.get_int(terrain, "collision_layer_mask", CONTEXT)
	var cells_float: float = field.cell_size / provider._spacing
	provider._cells = roundi(cells_float)
	if provider._spacing <= 0.0 or not is_equal_approx(cells_float, float(provider._cells)) or provider._skirt_depth < 0.0:
		push_error("DesertTerrainCell : cell_size_m doit être un multiple de vertex_spacing_m (%s)." % CONTEXT)
		return null
	provider._lods = _parse_lods(JsonData.get_array(config, "lods", CONTEXT), provider._cells)
	if provider._lods.is_empty():
		return null
	provider.material = _build_material(JsonData.get_dictionary(terrain, "shading", CONTEXT))
	if provider.material == null:
		return null
	return provider


## Charge desert.json puis crée le fournisseur.
static func load_default() -> DesertTerrainCell:
	return from_data(JsonData.load_dictionary(DesertHeightfield.DEFAULT_PATH))


## Construit la cellule (x, z) de la grille : corps statique positionné à son coin nord-ouest du monde.
## Renvoie null si l'identifiant sort de la grille.
func build_cell(cell: Vector2i) -> Node3D:
	var side: int = heightfield.cells_per_side
	if cell.x < 0 or cell.y < 0 or cell.x >= side or cell.y >= side:
		push_error("DesertTerrainCell : cellule %s hors de la grille %d × %d." % [cell, side, side])
		return null
	var origin := Vector2(
		-heightfield.half_extent + float(cell.x) * heightfield.cell_size, -heightfield.half_extent + float(cell.y) * heightfield.cell_size
	)
	var n: int = _cells + 1
	var padded: int = n + 2
	# Hauteurs de la grille fine avec une rangée de marge : normales et pentes sans lecture supplémentaire.
	var samples := PackedFloat32Array()
	samples.resize(padded * padded)
	var out: int = 0
	for j: int in padded:
		var z: float = origin.y + float(j - 1) * _spacing
		for i: int in padded:
			samples[out] = heightfield.height_at(origin.x + float(i - 1) * _spacing, z)
			out += 1
	var heights := PackedFloat32Array()
	heights.resize(n * n)
	var normals := PackedVector3Array()
	normals.resize(n * n)
	var colors := PackedColorArray()
	colors.resize(n * n)
	var inverse_double: float = 0.5 / _spacing
	out = 0
	for j: int in n:
		var z: float = origin.y + float(j) * _spacing
		for i: int in n:
			var centre: int = (j + 1) * padded + i + 1
			var dx: float = (samples[centre + 1] - samples[centre - 1]) * inverse_double
			var dz: float = (samples[centre + padded] - samples[centre - padded]) * inverse_double
			heights[out] = samples[centre]
			normals[out] = Vector3(-dx, 1.0, -dz).normalized()
			var weights: Vector4 = heightfield.surface_mix(origin.x + float(i) * _spacing, z, sqrt(dx * dx + dz * dz))
			colors[out] = Color(weights.x, weights.y, weights.z, weights.w)
			out += 1

	var body := DesertCellBody.new()
	body.name = "Cellule_%d_%d" % [cell.x, cell.y]
	body.cell = cell
	body.heightfield = heightfield
	body.collision_layer = _collision_mask
	body.collision_mask = 0
	body.position = Vector3(origin.x, 0.0, origin.y)
	body.add_child(_build_collision(heights, n))
	var range_begin: float = 0.0
	for lod_index: int in _lods.size():
		var lod: Lod = _lods[lod_index]
		var instance := MeshInstance3D.new()
		instance.name = "Lod%d" % lod_index
		instance.mesh = _build_mesh(lod, heights, normals, colors, n)
		instance.visibility_range_begin = range_begin
		instance.visibility_range_end = lod.range_end
		instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		body.add_child(instance)
		range_begin = lod.range_end
	return body


## Collision : carte de hauteurs au pas des sommets fins, centrée sur la cellule (l'échelle porte le pas en mètres).
func _build_collision(heights: PackedFloat32Array, n: int) -> CollisionShape3D:
	var shape := HeightMapShape3D.new()
	shape.map_width = n
	shape.map_depth = n
	shape.map_data = heights
	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	collision.shape = shape
	var half: float = heightfield.cell_size * 0.5
	collision.transform = Transform3D(Basis.from_scale(Vector3(_spacing, 1.0, _spacing)), Vector3(half, 0.0, half))
	return collision


func _build_mesh(lod: Lod, heights: PackedFloat32Array, normals: PackedVector3Array, colors: PackedColorArray, n: int) -> ArrayMesh:
	var m: int = lod.vertices_per_side
	var ring_size: int = lod.ring.size()
	var vertices := PackedVector3Array()
	vertices.resize(m * m + ring_size)
	var lod_normals := PackedVector3Array()
	lod_normals.resize(m * m + ring_size)
	var lod_colors := PackedColorArray()
	lod_colors.resize(m * m + ring_size)
	var out: int = 0
	var span: float = float(lod.step) * _spacing
	for j: int in m:
		var row: int = j * lod.step * n
		for i: int in m:
			var source: int = row + i * lod.step
			vertices[out] = Vector3(float(i) * span, heights[source], float(j) * span)
			lod_normals[out] = normals[source]
			lod_colors[out] = colors[source]
			out += 1
	var drop := Vector3(0.0, _skirt_depth, 0.0)
	for k: int in ring_size:
		var edge: int = lod.ring[k]
		vertices[out] = vertices[edge] - drop
		lod_normals[out] = lod_normals[edge]
		lod_colors[out] = lod_colors[edge]
		out += 1
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = lod_normals
	arrays[Mesh.ARRAY_COLOR] = lod_colors
	arrays[Mesh.ARRAY_INDEX] = lod.indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	return mesh


static func _parse_lods(entries: Array, cells: int) -> Array[Lod]:
	var result: Array[Lod] = []
	var previous_end: float = 0.0
	for raw: Variant in entries:
		if typeof(raw) != TYPE_DICTIONARY:
			push_error("DesertTerrainCell : chaque niveau de détail doit être un objet JSON (%s)." % CONTEXT)
			return []
		var entry: Dictionary = raw
		var lod := Lod.new()
		lod.step = JsonData.get_int(entry, "step", CONTEXT)
		lod.range_end = JsonData.get_float(entry, "range_end_m", CONTEXT)
		var is_last: bool = result.size() == entries.size() - 1
		if lod.step <= 0 or cells % lod.step != 0 or (is_last and lod.range_end != 0.0):
			push_error("DesertTerrainCell : niveau de détail invalide (pas %d, fin %.1f) (%s)." % [lod.step, lod.range_end, CONTEXT])
			return []
		if not is_last and lod.range_end <= previous_end:
			push_error("DesertTerrainCell : les distances de fin doivent croître (%s)." % CONTEXT)
			return []
		previous_end = lod.range_end
		@warning_ignore("integer_division")
		lod.vertices_per_side = cells / lod.step + 1
		lod.ring = _perimeter_ring(lod.vertices_per_side)
		lod.indices = _index_template(lod.vertices_per_side, lod.ring)
		result.append(lod)
	return result


## Indices du pourtour d'une grille n × n, dans l'ordre : haut, droite, bas, gauche.
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


## Triangles de la grille (sens horaire vu du dessus), puis ceux de la jupe.
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


static func _build_material(shading: Dictionary) -> ShaderMaterial:
	var context: String = SHADING_CONTEXT
	var material := ShaderMaterial.new()
	material.shader = load(SHADER_PATH)
	var sand: String = JsonData.get_string(shading, "sand_texture", context)
	var rock: String = JsonData.get_string(shading, "rock_texture", context)
	var pebbles: String = JsonData.get_string(shading, "galets_texture", context)
	for map_name: Array in [["albedo", "diff"], ["normal", "nor_gl"], ["roughness", "rough"]]:
		var sand_texture: Texture2D = _load_texture(sand, map_name[1])
		var rock_texture: Texture2D = _load_texture(rock, map_name[1])
		var pebble_texture: Texture2D = _load_texture(pebbles, map_name[1])
		if sand_texture == null or rock_texture == null or pebble_texture == null:
			return null
		material.set_shader_parameter("sand_" + map_name[0], sand_texture)
		material.set_shader_parameter("rock_" + map_name[0], rock_texture)
		material.set_shader_parameter("galets_" + map_name[0], pebble_texture)
	for key: String in [
		"sand_uv_scale",
		"rock_uv_scale",
		"earth_uv_scale",
		"detail_normal_strength",
		"macro_scale",
		"macro_strength",
		"tiling_scale",
		"galets_uv_scale",
		"bed_far_start_m",
		"bed_far_end_m",
		"bed_far_strength"
	]:
		material.set_shader_parameter(key, JsonData.get_float(shading, key, context))
	for key: String in ["sand_tint", "rock_tint", "earth_tint", "galets_tint", "bed_far_tint"]:
		material.set_shader_parameter(key, JsonData.get_color(shading, key, context))
	return material


## Texture du sol (Poly Haven) par identifiant et carte (« diff », « nor_gl », « rough ») ; null et erreur si absente.
static func ground_texture(texture_id: String, map_name: String) -> Texture2D:
	return _load_texture(texture_id, map_name)


static func _load_texture(texture_id: String, map_name: String) -> Texture2D:
	var path: String = "%s/%s/%s_%s.jpg" % [POLYHAVEN_DIR, texture_id, texture_id, map_name]
	if not ResourceLoader.exists(path):
		push_error("DesertTerrainCell : texture absente %s. Lancez Scripts/Pipeline/importer-ressources.ps1." % path)
		return null
	var texture: Texture2D = load(path)
	if texture == null:
		push_error("DesertTerrainCell : %s n'est pas une texture." % path)
	return texture
