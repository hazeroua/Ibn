extends GutTest
## Champ de hauteurs du désert : déterminisme, relief de dunes, oasis, normales, surfaces et cellules.

const DATA_PATH: String = "res://data/desert/desert.json"

var _data: Dictionary
var _field: DesertHeightfield


func before_all() -> void:
	_data = JsonData.load_dictionary(DATA_PATH)
	_field = DesertHeightfield.from_data(_data)


func test_same_seed_gives_same_heights() -> void:
	var other: DesertHeightfield = DesertHeightfield.from_data(_data)
	for i: int in 200:
		var x: float = -1990.0 + float(i) * 19.7
		var z: float = 1900.0 - float(i) * 17.3
		assert_eq(_field.height_at(x, z), other.height_at(x, z))


func test_other_seed_changes_heights() -> void:
	var data: Dictionary = _data.duplicate(true)
	(data["terrain"] as Dictionary)["seed"] = 1406
	var other: DesertHeightfield = DesertHeightfield.from_data(data)
	var differing: int = 0
	for i: int in 100:
		var x: float = -1500.0 + float(i) * 29.0
		if not is_equal_approx(_field.height_at(x, 300.0), other.height_at(x, 300.0)):
			differing += 1
	assert_gt(differing, 90)


func test_dunes_are_elongated_across_the_wind() -> void:
	# Dans le sens du vent le relief varie plus vite qu'en travers : écart moyen de hauteur sur 60 m.
	var wind: float = deg_to_rad((_data["terrain"] as Dictionary)["wind_direction_deg"] as float)
	var along := Vector2(cos(wind), sin(wind))
	var across := Vector2(-along.y, along.x)
	var variation_along: float = 0.0
	var variation_across: float = 0.0
	for i: int in 300:
		var p := Vector2(-1200.0 + float(i) * 7.0, -800.0 + float(i % 17) * 90.0)
		var base: float = _field.height_at(p.x, p.y)
		variation_along += absf(_field.height_at(p.x + along.x * 60.0, p.y + along.y * 60.0) - base)
		variation_across += absf(_field.height_at(p.x + across.x * 60.0, p.y + across.y * 60.0) - base)
	assert_gt(variation_along, variation_across * 1.5, "crêtes perpendiculaires au vent")


func test_relief_has_dunes() -> void:
	var low: float = 1e9
	var high: float = -1e9
	for j: int in 80:
		for i: int in 80:
			var h: float = _field.height_at(-1950.0 + float(i) * 50.0, -1950.0 + float(j) * 50.0)
			low = minf(low, h)
			high = maxf(high, h)
	assert_gt(high - low, 25.0, "un désert de dunes, pas une plaine")


func test_oasis_is_flat_earth() -> void:
	var center: Vector2 = _field.features.water_center(0)
	var radius: float = _field.features.water_radius(0)
	var reference: float = _field.height_at(center.x, center.y)
	for i: int in 36:
		var angle: float = float(i) * TAU / 36.0
		for fraction: float in [0.3, 0.8, 1.0]:
			var p: Vector2 = center + Vector2(cos(angle), sin(angle)) * radius * fraction
			assert_almost_eq(_field.height_at(p.x, p.y), reference, 0.001, "aplani dans le rayon")
			assert_eq(_field.surface_at(Vector3(p.x, 0.0, p.y)), &"terre")


func test_normals_are_unit_and_point_up() -> void:
	for i: int in 100:
		var normal: Vector3 = _field.normal_at(-1800.0 + float(i) * 33.0, 700.0 - float(i) * 11.0)
		assert_almost_eq(normal.length(), 1.0, 0.0001)
		assert_gt(normal.y, 0.0)
	var flat: Vector3 = _field.normal_at(_field.features.water_center(0).x, _field.features.water_center(0).y)
	assert_almost_eq(flat.y, 1.0, 0.0001)


func test_all_surfaces_occur_across_the_desert() -> void:
	var seen: Dictionary[StringName, int] = {}
	for j: int in 60:
		for i: int in 60:
			var surface: StringName = _field.surface_at(Vector3(-1900.0 + float(i) * 63.0, 0.0, -1900.0 + float(j) * 63.0))
			seen[surface] = seen.get(surface, 0) + 1
	seen[_field.surface_at(Vector3(_field.features.water_center(0).x, 0.0, _field.features.water_center(0).y))] = 1
	assert_true(seen.has(&"sable"))
	assert_true(seen.has(&"pierre"))
	assert_true(seen.has(&"terre"))
	assert_gt(seen[&"sable"], seen[&"pierre"], "le sable domine")


func test_cell_lookup_covers_the_grid() -> void:
	assert_eq(_field.cell_at(-2000.0, -2000.0), Vector2i(0, 0))
	assert_eq(_field.cell_at(1999.9, 1999.9), Vector2i(15, 15))
	assert_eq(_field.cell_at(0.0, 0.0), Vector2i(8, 8))
	assert_eq(_field.cell_at(2000.1, 0.0), DesertHeightfield.NO_CELL)
