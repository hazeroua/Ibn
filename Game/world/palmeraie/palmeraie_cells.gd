class_name PalmeraieCells
extends RefCounted
## Construction des cellules de la palmeraie à partir du plan (PalmeraieLayout) : transformées des arbres, palmiers et
## touffes de culture, filtrage de la végétation générale dans les cultures, maillages de décor (murets, séguias, eau,
## sol cultivé) et collisions des murets. Les méthodes publiques s'exécutent sur le fil de travail du streaming : elles ne
## touchent ni à l'arbre de scène ni à un état partagé modifiable (matériaux créés une fois, avant le premier chargement).
## Pire cas par cellule : 20 parcelles, 6 000 touffes, 100 pièces de muret, 40 tronçons de séguia, environ 12 000 lectures de hauteur.

const CONTEXT: String = "palmeraie.json"
const FLOATS_PER_INSTANCE: int = 12
const TUFT_SEED_SALT: int = 7919
const UP: Vector3 = Vector3.UP

var layout: PalmeraieLayout

var _field: DesertHeightfield
var _settings: Dictionary = {}
var _earth_material: StandardMaterial3D
var _ground_material: ShaderMaterial
var _water_material: ShaderMaterial
var _seed: int = 0
var _tree_offset: float = -0.05


## Surface de triangles à sommets non partagés (normale plate ou imposée), couleurs et UV.
class Surface:
	extends RefCounted
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var colors: PackedColorArray = PackedColorArray()
	var uvs: PackedVector2Array = PackedVector2Array()
	var uv2s: PackedVector2Array = PackedVector2Array()
	var indices: PackedInt32Array = PackedInt32Array()

	## Quadrilatère a, b, c, d (dans l'ordre du contour), visible du côté de `out` ; `normal` impose la normale (sinon plate).
	func quad(
		a: Vector3,
		b: Vector3,
		c: Vector3,
		d: Vector3,
		out: Vector3,
		color: Color,
		uv_values: PackedVector2Array = PackedVector2Array(),
		uv2: Vector2 = Vector2.ZERO,
		normal: Vector3 = Vector3.ZERO
	) -> void:
		var flat: Vector3 = (b - a).cross(d - a).normalized()
		var facing_out: bool = flat.dot(out) < 0.0
		if facing_out:
			flat = -flat
		var base: int = vertices.size()
		vertices.append_array(PackedVector3Array([a, b, c, d]))
		var used: Vector3 = normal if normal != Vector3.ZERO else flat
		normals.append_array(PackedVector3Array([used, used, used, used]))
		colors.append_array(PackedColorArray([color, color, color, color]))
		if uv_values.size() == 4:
			uvs.append_array(uv_values)
		else:
			uvs.append_array(PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]))
		uv2s.append_array(PackedVector2Array([uv2, uv2, uv2, uv2]))
		if facing_out:
			indices.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
		else:
			indices.append_array(PackedInt32Array([base, base + 3, base + 2, base, base + 2, base + 1]))

	func is_empty() -> bool:
		return indices.is_empty()

	func to_mesh(material: Material) -> ArrayMesh:
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_TEX_UV2] = uv2s
		arrays[Mesh.ARRAY_INDEX] = indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, material)
		return mesh


## Crée le constructeur de cellules ; null si les données ou les shaders sont invalides.
static func create(layout_value: PalmeraieLayout, field: DesertHeightfield) -> PalmeraieCells:
	if layout_value == null or field == null:
		return null
	var cells := PalmeraieCells.new()
	cells.layout = layout_value
	cells._field = field
	cells._settings = layout_value.settings
	cells._seed = JsonData.get_int(cells._settings, "seed", CONTEXT)
	cells._tree_offset = JsonData.get_float_or(cells._settings, "tree_ground_offset_m", -0.05, CONTEXT)
	if not cells._make_materials():
		return null
	return cells


## Réglages d'affichage des espèces propres à la palmeraie (StringName -> Dictionary), fusionnés avec ceux de vegetation.json.
func species_display() -> Dictionary:
	var out: Dictionary = {}
	var source: Dictionary = JsonData.get_dictionary(_settings, "species_display", CONTEXT)
	for id: Variant in source.keys():
		out[StringName(str(id))] = source[id]
	return out


## Retire de la végétation générale (palmiers, buissons, herbes…) ce qui tombe dans les cultures : tout point du contour
## à plus de shore_keep_m de la rive. Les rives gardent leur végétation naturelle.
func filter_scatter(cell: Vector2i, result: Dictionary) -> void:
	var origin_x: float = -_field.half_extent + float(cell.x) * _field.cell_size
	var origin_z: float = -_field.half_extent + float(cell.y) * _field.cell_size
	if not layout.overlaps_cell(origin_x, origin_z):
		return
	var keep: float = JsonData.get_float(JsonData.get_dictionary(_settings, "scatter_exclusion", CONTEXT), "shore_keep_m", CONTEXT)
	var features: LandscapeFeatures = _field.features
	for species: Variant in result.keys():
		var source: PackedFloat32Array = result[species]
		var kept := PackedFloat32Array()
		var count: int = source.size() / FLOATS_PER_INSTANCE
		for i: int in count:
			var k: int = i * FLOATS_PER_INSTANCE
			var x: float = source[k + 3]
			var z: float = source[k + 11]
			if layout.inside_contour(x, z) and features.distance_to_water(x, z) >= keep:
				continue
			kept.append_array(source.slice(k, k + FLOATS_PER_INSTANCE))
		if kept.size() != source.size():
			result[species] = kept


## Transformées (12 réels par instance, coordonnées du monde) par espèce : arbres, palmiers, chadouf et touffes de culture.
func build_transforms(cell: Vector2i) -> Dictionary:
	var out: Dictionary = {}
	var data: PalmeraieLayout.PalmeraieCellData = layout.cell_data(cell)
	if data == null:
		return out
	for id: StringName in data.points.keys():
		var list: PackedFloat32Array = data.points[id]
		var transforms := PackedFloat32Array()
		for i: int in list.size() / PalmeraieLayout.POINT_STRIDE:
			var k: int = i * PalmeraieLayout.POINT_STRIDE
			var y: float = _field.height_at(list[k], list[k + 1]) + _tree_offset
			_append_transform(transforms, list[k], y, list[k + 1], list[k + 2], list[k + 3])
		out[String(id)] = transforms
	var kinds: Array = JsonData.get_array(_settings, "kinds", CONTEXT)
	var rng := RandomNumberGenerator.new()
	var wall_half: float = JsonData.get_float(JsonData.get_dictionary(_settings, "walls", CONTEXT), "thickness_m", CONTEXT) * 0.5
	for parcel: int in data.parcels:
		var kind: Dictionary = kinds[_kind_index(parcel)]
		if not kind.has("tufts"):
			continue
		var tufts: Dictionary = JsonData.get_dictionary(kind, "tufts", CONTEXT)
		var species: String = JsonData.get_string(tufts, "species", CONTEXT)
		var transforms: PackedFloat32Array = out.get(species, PackedFloat32Array())
		rng.seed = _seed * TUFT_SEED_SALT + parcel
		_append_tufts(transforms, parcel, tufts, wall_half, rng)
		out[species] = transforms
	return out


func _kind_index(parcel: int) -> int:
	return layout.kind_ids.find(layout.parcel_kind(parcel))


func _append_tufts(transforms: PackedFloat32Array, parcel: int, tufts: Dictionary, wall_half: float, rng: RandomNumberGenerator) -> void:
	var bounds: PackedFloat64Array = layout.parcel_bounds(parcel)
	var margin: float = JsonData.get_float(tufts, "edge_margin_m", CONTEXT) + wall_half
	var row_spacing: float = JsonData.get_float(tufts, "row_spacing_m", CONTEXT)
	var along: float = JsonData.get_float(tufts, "along_spacing_m", CONTEXT)
	var jitter: float = JsonData.get_float(tufts, "jitter_m", CONTEXT)
	var v: float = bounds[1] + margin
	while v <= bounds[3] - margin:
		var u: float = bounds[0] + margin
		while u <= bounds[2] - margin:
			var world: Vector2 = layout.to_world(u + rng.randf_range(-jitter, jitter), v + rng.randf_range(-jitter, jitter))
			var y: float = _field.height_at(world.x, world.y) - 0.02
			_append_transform(transforms, world.x, y, world.y, rng.randf_range(0.85, 1.15), rng.randf_range(0.0, TAU))
			u += along
		v += row_spacing


## Transformée verticale : échelle uniforme, rotation autour de Y, rangée par rangée du tampon d'un MultiMesh.
func _append_transform(out: PackedFloat32Array, x: float, y: float, z: float, scale: float, yaw: float) -> void:
	var c: float = cos(yaw) * scale
	var s: float = sin(yaw) * scale
	out.append_array(PackedFloat32Array([c, 0.0, s, x, 0.0, scale, 0.0, y, -s, 0.0, c, z]))


# --- Décor : murets, séguias, eau, sol cultivé ----------------------------------------------------------------------------


## Ajoute à la cellule les maillages de décor (un par matériau) et les collisions des murets.
func add_decor(cell: Vector2i, body: Node3D) -> void:
	var data: PalmeraieLayout.PalmeraieCellData = layout.cell_data(cell)
	if data == null:
		return
	var earth := Surface.new()
	var ground := Surface.new()
	var water := Surface.new()
	var walls: Dictionary = JsonData.get_dictionary(_settings, "walls", CONTEXT)
	var basin: Dictionary = JsonData.get_dictionary(_settings, "basin", CONTEXT)
	for i: int in data.walls.size() / PalmeraieLayout.WALL_STRIDE:
		var k: int = i * PalmeraieLayout.WALL_STRIDE
		var solid: bool = data.walls[k + 4] > 0.5
		var height: float = JsonData.get_float(walls, "height_m", CONTEXT) if solid else JsonData.get_float(basin, "rim_height_m", CONTEXT)
		var thickness: float = JsonData.get_float(walls if solid else basin, "thickness_m" if solid else "rim_thickness_m", CONTEXT)
		_add_wall(
			earth,
			body as CollisionObject3D if solid else null,
			Vector2(data.walls[k], data.walls[k + 1]),
			Vector2(data.walls[k + 2], data.walls[k + 3]),
			height,
			thickness
		)
	for i: int in data.canals.size() / PalmeraieLayout.CANAL_STRIDE:
		var k: int = i * PalmeraieLayout.CANAL_STRIDE
		_add_canal(earth, water, Vector2(data.canals[k], data.canals[k + 1]), Vector2(data.canals[k + 2], data.canals[k + 3]))
	for i: int in data.basins.size() / PalmeraieLayout.BASIN_STRIDE:
		var k: int = i * PalmeraieLayout.BASIN_STRIDE
		_add_basin(water, Vector2(data.basins[k], data.basins[k + 1]), data.basins[k + 2], data.basins[k + 3])
	for parcel: int in data.parcels:
		_add_ground(ground, parcel)
	var materials: Dictionary = JsonData.get_dictionary(_settings, "materials", CONTEXT)
	var decor_end: float = JsonData.get_float(materials, "decor_visibility_range_end_m", CONTEXT)
	var decor_margin: float = JsonData.get_float(materials, "decor_visibility_fade_margin_m", CONTEXT)
	var ground_settings: Dictionary = JsonData.get_dictionary(_settings, "ground", CONTEXT)
	var water_end: float = JsonData.get_float(JsonData.get_dictionary(_settings, "water", CONTEXT), "visibility_range_end_m", CONTEXT)
	_attach(body, earth, _earth_material, "palmeraie_terre", decor_end, decor_margin)
	_attach(
		body,
		ground,
		_ground_material,
		"palmeraie_cultures",
		JsonData.get_float(ground_settings, "visibility_range_end_m", CONTEXT),
		JsonData.get_float(ground_settings, "visibility_fade_margin_m", CONTEXT)
	)
	_attach(body, water, _water_material, "palmeraie_eau", water_end, decor_margin)


func _attach(body: Node3D, surface: Surface, material: Material, node_name: String, range_end: float, margin: float) -> void:
	if surface.is_empty():
		return
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = surface.to_mesh(material)
	# Sommets en coordonnées du monde : la cellule est posée à son coin, on compense.
	instance.position = -body.position
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.visibility_range_end = range_end
	instance.visibility_range_end_margin = margin
	instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	body.add_child(instance)


## Variation déterministe de 0 à 1 d'après une position (aucune table, aucun état).
func _hash(x: float, z: float) -> float:
	return fposmod(sin(x * 12.9898 + z * 78.233) * 43758.5453, 1.0)


## Muret en pisé : section trapézoïdale suivant le relief tous les step_m, bouts fermés. Si `body` n'est pas nul, des boîtes de
## collision fusionnées (tant que le sol varie de moins de la tolérance) sont ajoutées au corps de la cellule.
func _add_wall(surface: Surface, body: CollisionObject3D, from: Vector2, to: Vector2, height: float, thickness: float) -> void:
	var walls: Dictionary = JsonData.get_dictionary(_settings, "walls", CONTEXT)
	var step: float = JsonData.get_float(walls, "step_m", CONTEXT)
	var sink: float = JsonData.get_float(walls, "sink_m", CONTEXT)
	var low_color: Color = JsonData.get_color(walls, "color_low", CONTEXT)
	var high_color: Color = JsonData.get_color(walls, "color_high", CONTEXT)
	var variation: float = JsonData.get_float(walls, "height_variation_m", CONTEXT)
	var length: float = from.distance_to(to)
	if length < 0.05:
		return
	var direction: Vector2 = (to - from) / length
	var side := Vector2(-direction.y, direction.x)
	var top_height: float = height + (_hash(from.x, from.y) - 0.5) * 2.0 * variation
	var count: int = maxi(1, ceili(length / step))
	var half: float = thickness * 0.5
	var flare: float = 0.15
	var heights := PackedFloat32Array()
	var rings: Array[PackedVector3Array] = []
	for i: int in count + 1:
		var q: Vector2 = from.lerp(to, float(i) / float(count))
		var g: float = _field.height_at(q.x, q.y)
		heights.append(g)
		var bl: Vector2 = q - side * (half + flare)
		var tl: Vector2 = q - side * (half * 0.7)
		var tr: Vector2 = q + side * (half * 0.7)
		var br: Vector2 = q + side * (half + flare)
		rings.append(
			PackedVector3Array(
				[
					Vector3(bl.x, g - sink, bl.y),
					Vector3(tl.x, g + top_height, tl.y),
					Vector3(tr.x, g + top_height, tr.y),
					Vector3(br.x, g - sink, br.y)
				]
			)
		)
	var side3 := Vector3(side.x, 0.0, side.y)
	var dir3 := Vector3(direction.x, 0.0, direction.y)
	for i: int in count:
		var a: PackedVector3Array = rings[i]
		var b: PackedVector3Array = rings[i + 1]
		var shade: float = _hash(a[1].x, a[1].z)
		var base_color: Color = low_color.lerp(high_color, shade)
		var top_color: Color = base_color.lerp(high_color, 0.5)
		surface.quad(a[0], b[0], b[1], a[1], -side3 + UP * 0.5, base_color)
		surface.quad(a[1], b[1], b[2], a[2], UP, top_color)
		surface.quad(a[2], b[2], b[3], a[3], side3 + UP * 0.5, base_color)
	var first: PackedVector3Array = rings[0]
	var last: PackedVector3Array = rings[count]
	surface.quad(first[0], first[3], first[2], first[1], -dir3, low_color)
	surface.quad(last[0], last[3], last[2], last[1], dir3, low_color)
	if body != null:
		_add_wall_collisions(body, from, direction, length, count, heights, top_height, sink, thickness, walls)


func _add_wall_collisions(
	body: CollisionObject3D,
	from: Vector2,
	direction: Vector2,
	length: float,
	count: int,
	heights: PackedFloat32Array,
	top_height: float,
	sink: float,
	thickness: float,
	walls: Dictionary
) -> void:
	var tolerance: float = JsonData.get_float(walls, "collision_height_tolerance_m", CONTEXT)
	var max_piece: float = JsonData.get_float(walls, "collision_piece_max_m", CONTEXT)
	var origin: Vector3 = (body as Node3D).position
	var step: float = length / float(count)
	var yaw: float = atan2(-direction.y, direction.x)
	var first: int = 0
	while first < count:
		var last: int = first + 1
		var low: float = minf(heights[first], heights[last])
		var high: float = maxf(heights[first], heights[last])
		while last < count:
			var next_low: float = minf(low, heights[last + 1])
			var next_high: float = maxf(high, heights[last + 1])
			if next_high - next_low > tolerance or float(last + 1 - first) * step > max_piece:
				break
			low = next_low
			high = next_high
			last += 1
		var span: float = float(last - first) * step
		var middle: Vector2 = from + direction * (float(first) * step + span * 0.5)
		var box_height: float = (high - low) + top_height + sink
		var shape := BoxShape3D.new()
		shape.size = Vector3(span, box_height, thickness)
		var owner_id: int = body.create_shape_owner(body)
		body.shape_owner_add_shape(owner_id, shape)
		var center := Vector3(middle.x, low - sink + box_height * 0.5, middle.y) - origin
		body.shape_owner_set_transform(owner_id, Transform3D(Basis(UP, yaw), center))
		first = last


## Séguia : berges en terre de part et d'autre d'un lit, creux de depth_m sous la crête, et filet d'eau étroit.
func _add_canal(earth: Surface, water: Surface, from: Vector2, to: Vector2) -> void:
	var canal: Dictionary = JsonData.get_dictionary(_settings, "canal", CONTEXT)
	var half_water: float = JsonData.get_float(canal, "water_half_width_m", CONTEXT)
	var bank: float = JsonData.get_float(canal, "bank_width_m", CONTEXT)
	var slope: float = JsonData.get_float(canal, "bank_slope_m", CONTEXT)
	var depth: float = JsonData.get_float(canal, "depth_m", CONTEXT)
	var lift: float = JsonData.get_float(canal, "water_lift_m", CONTEXT)
	var step: float = JsonData.get_float(canal, "step_m", CONTEXT)
	var bank_color: Color = JsonData.get_color(canal, "bank_color", CONTEXT)
	var bed_color: Color = JsonData.get_color(canal, "bed_color", CONTEXT)
	var length: float = from.distance_to(to)
	if length < 0.05:
		return
	var direction: Vector2 = (to - from) / length
	var side := Vector2(-direction.y, direction.x)
	var count: int = maxi(1, ceili(length / step))
	var laterals: Array[float] = [
		-(half_water + bank + slope),
		-(half_water + bank * 0.5),
		-(half_water + 0.08),
		-half_water,
		half_water,
		half_water + 0.08,
		half_water + bank * 0.5,
		half_water + bank + slope
	]
	var rises: Array[float] = [0.0, depth, depth * 0.85, 0.0, 0.0, depth * 0.85, depth, 0.0]
	var colors: Array[Color] = [
		bank_color,
		bank_color,
		bank_color.lerp(bed_color, 0.5),
		bed_color,
		bed_color,
		bank_color.lerp(bed_color, 0.5),
		bank_color,
		bank_color
	]
	var previous: PackedVector3Array = PackedVector3Array()
	var previous_water: PackedVector3Array = PackedVector3Array()
	for i: int in count + 1:
		var q: Vector2 = from.lerp(to, float(i) / float(count))
		var g: float = _field.height_at(q.x, q.y)
		var ring := PackedVector3Array()
		for p: int in laterals.size():
			var at: Vector2 = q + side * laterals[p]
			ring.append(Vector3(at.x, g + rises[p], at.y))
		var wet := PackedVector3Array(
			[
				Vector3(q.x - side.x * half_water, g + lift, q.y - side.y * half_water),
				Vector3(q.x + side.x * half_water, g + lift, q.y + side.y * half_water)
			]
		)
		if i > 0:
			for p: int in laterals.size() - 1:
				var run: float = laterals[p + 1] - laterals[p]
				var rise: float = rises[p + 1] - rises[p]
				var out: Vector3 = Vector3(side.x, 0.0, side.y) * (-rise) + UP * run
				earth.quad(previous[p], ring[p], ring[p + 1], previous[p + 1], out, colors[p].lerp(colors[p + 1], 0.5))
			var along0: float = length * float(i - 1) / float(count)
			var along1: float = length * float(i) / float(count)
			water.quad(
				previous_water[0],
				wet[0],
				wet[1],
				previous_water[1],
				UP,
				Color.WHITE,
				PackedVector2Array([Vector2(0.0, along0), Vector2(0.0, along1), Vector2(1.0, along1), Vector2(1.0, along0)]),
				Vector2.ZERO,
				UP
			)
		previous = ring
		previous_water = wet


## Bassin de répartition : surface d'eau carrée à plat (le rebord est dessiné par les murets bas du plan).
func _add_basin(water: Surface, center: Vector2, yaw: float, size: float) -> void:
	var lift: float = JsonData.get_float(JsonData.get_dictionary(_settings, "canal", CONTEXT), "water_lift_m", CONTEXT)
	var g: float = _field.height_at(center.x, center.y) + lift
	var half: float = size * 0.5
	var cs: float = cos(yaw)
	var sn: float = sin(yaw)
	var corners := PackedVector3Array()
	for local: Vector2 in [Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)]:
		corners.append(Vector3(center.x + local.x * cs - local.y * sn, g, center.y + local.x * sn + local.y * cs))
	water.quad(
		corners[0],
		corners[1],
		corners[2],
		corners[3],
		UP,
		Color.WHITE,
		PackedVector2Array([Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, size), Vector2(0.0, size)]),
		Vector2.ZERO,
		UP
	)


## Sol cultivé d'une parcelle : grille de grid_step_m épousant le relief, un peu au-dessus du terrain. Couleur = teinte de la
## culture et alpha = croissance minimale ; UV = repère local en mètres ; UV2 = style du semis et écart des rangs.
func _add_ground(surface: Surface, parcel: int) -> void:
	var ground: Dictionary = JsonData.get_dictionary(_settings, "ground", CONTEXT)
	var step: float = JsonData.get_float(ground, "grid_step_m", CONTEXT)
	var lift: float = JsonData.get_float(ground, "lift_m", CONTEXT)
	var inset: float = (
		JsonData.get_float(ground, "inset_m", CONTEXT)
		+ JsonData.get_float(JsonData.get_dictionary(_settings, "walls", CONTEXT), "thickness_m", CONTEXT)
	)
	var kinds: Array = JsonData.get_array(_settings, "kinds", CONTEXT)
	var kind: Dictionary = kinds[_kind_index(parcel)]
	var cover: Dictionary = JsonData.get_dictionary(kind, "ground", CONTEXT)
	var tint: Color = JsonData.get_color(cover, "color", CONTEXT)
	tint.a = JsonData.get_float(cover, "min_growth", CONTEXT)
	var style: int = JsonData.get_int(cover, "style", CONTEXT)
	var spacing: float = float(JsonData.get_array(ground, "row_spacing_m", CONTEXT)[style])
	var uv2 := Vector2(float(style), spacing)
	var bounds: PackedFloat64Array = layout.parcel_bounds(parcel)
	var u0: float = bounds[0] + inset
	var v0: float = bounds[1] + inset
	var u1: float = bounds[2] - inset
	var v1: float = bounds[3] - inset
	var columns: int = maxi(1, ceili((u1 - u0) / step))
	var rows: int = maxi(1, ceili((v1 - v0) / step))
	var grid := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	for j: int in rows + 1:
		for i: int in columns + 1:
			var u: float = lerpf(u0, u1, float(i) / float(columns))
			var v: float = lerpf(v0, v1, float(j) / float(rows))
			var world: Vector2 = layout.to_world(u, v)
			grid.append(Vector3(world.x, _field.height_at(world.x, world.y) + lift, world.y))
			normals.append(_field.normal_at(world.x, world.y))
			uvs.append(Vector2(u, v))
	var stride: int = columns + 1
	for j: int in rows:
		for i: int in columns:
			var a: int = j * stride + i
			var b: int = a + 1
			var c: int = a + stride + 1
			var d: int = a + stride
			surface.quad(
				grid[a],
				grid[b],
				grid[c],
				grid[d],
				UP,
				tint,
				PackedVector2Array([uvs[a], uvs[b], uvs[c], uvs[d]]),
				uv2,
				(normals[a] + normals[b] + normals[c] + normals[d]).normalized()
			)


func _make_materials() -> bool:
	var materials: Dictionary = JsonData.get_dictionary(_settings, "materials", CONTEXT)
	_earth_material = StandardMaterial3D.new()
	_earth_material.vertex_color_use_as_albedo = true
	_earth_material.roughness = JsonData.get_float(materials, "earth_roughness", CONTEXT)
	var ground_shader: Shader = load(JsonData.get_string(materials, "ground_shader", CONTEXT)) as Shader
	var water: Dictionary = JsonData.get_dictionary(_settings, "water", CONTEXT)
	var water_shader: Shader = load(JsonData.get_string(water, "shader", CONTEXT)) as Shader
	if ground_shader == null or water_shader == null:
		push_error("PalmeraieCells : shader introuvable (%s)." % CONTEXT)
		return false
	_ground_material = ShaderMaterial.new()
	_ground_material.shader = ground_shader
	_ground_material.set_shader_parameter(&"soil_color", JsonData.get_color(materials, "soil_color", CONTEXT))
	_ground_material.set_shader_parameter(&"soil_wet_color", JsonData.get_color(materials, "soil_wet_color", CONTEXT))
	_ground_material.set_shader_parameter(&"ripe_color", JsonData.get_color(materials, "ripe_color", CONTEXT))
	_water_material = ShaderMaterial.new()
	_water_material.shader = water_shader
	_water_material.set_shader_parameter(&"shallow_color", JsonData.get_color(water, "shallow_color", CONTEXT))
	_water_material.set_shader_parameter(&"deep_color", JsonData.get_color(water, "deep_color", CONTEXT))
	_water_material.set_shader_parameter(&"flow_speed", JsonData.get_float(water, "flow_speed", CONTEXT))
	_water_material.set_shader_parameter(&"ripple_scale", JsonData.get_float(water, "ripple_scale", CONTEXT))
	_water_material.set_shader_parameter(&"roughness_value", JsonData.get_float(water, "roughness", CONTEXT))
	return true
