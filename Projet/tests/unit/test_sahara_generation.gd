extends GutTest
## Relief et sols du Sahara, générés à basse résolution (256 × 256, 16 m par pixel)
## à partir des données livrées : mêmes règles qu'en pleine résolution, test rapide.

const DATA_PATH: String = "res://data/sahara/sahara.json"
const TEST_PIXELS: int = 256

var _settings: SaharaSettings
var _field: SaharaHeightfield
var _surface: SaharaSurface


func before_all() -> void:
	var data: Dictionary = JsonData.load_dictionary(DATA_PATH)
	_settings = SaharaSettings.from_dictionary(data.get("generation", {}))
	_field = SaharaHeightfield.generate(_settings, TEST_PIXELS)
	_surface = SaharaSurface.generate(_field, _settings)


func test_shipped_settings_are_valid() -> void:
	assert_true(_settings.errors.is_empty(), str(_settings.errors))
	assert_eq(_settings.massifs.size(), 4)
	assert_eq(_settings.wadis.size(), 2)
	assert_eq(_settings.star_dunes.size(), 1)


func test_generation_is_deterministic() -> void:
	var again: SaharaHeightfield = SaharaHeightfield.generate(_settings, TEST_PIXELS)
	assert_eq(again.heights, _field.heights)
	assert_eq(SaharaSurface.generate(again, _settings).control_bits, _surface.control_bits)


func test_heights_are_finite_and_in_a_plausible_range() -> void:
	var lowest: float = INF
	var highest: float = -INF
	for height: float in _field.heights:
		assert_false(is_nan(height) or is_inf(height))
		lowest = minf(lowest, height)
		highest = maxf(highest, height)
	assert_between(lowest, -10.0, 60.0)
	assert_between(highest, 120.0, 260.0)


func test_erg_and_reg_share_the_map() -> void:
	var erg_pixels: int = 0
	for value: float in _field.erg_mask:
		if value > 0.5:
			erg_pixels += 1
	var fraction: float = float(erg_pixels) / float(_field.erg_mask.size())
	assert_between(fraction, 0.25, 0.75, "part de l'erg : %.2f" % fraction)


func test_every_landmark_stands_out() -> void:
	assert_eq(_field.landmarks.size(), _settings.massifs.size() + _settings.star_dunes.size())
	for massif: SaharaSettings.Massif in _settings.massifs:
		var peak: Vector3 = _landmark(massif.name)
		var surroundings: float = _field.height_at(massif.center + Vector2(maxf(massif.radii.x, massif.radii.y) * 2.2, 0.0))
		assert_gt(peak.y - surroundings, massif.height_meters * 0.6, massif.name)
	for dune: SaharaSettings.StarDune in _settings.star_dunes:
		var top: Vector3 = _landmark(dune.name)
		assert_gt(top.y - _field.height_at(dune.center + Vector2(dune.radius_meters * 1.5, 0.0)), dune.height_meters * 0.5, dune.name)


func test_wadis_are_carved_below_their_banks() -> void:
	for wadi: SaharaSettings.Wadi in _settings.wadis:
		for segment: int in wadi.points.size() - 1:
			var start: Vector2 = wadi.points[segment]
			var end: Vector2 = wadi.points[segment + 1]
			var middle: Vector2 = (start + end) * 0.5
			var across: Vector2 = (end - start).normalized().orthogonal()
			var bank_distance: float = wadi.floor_half_width_meters + wadi.bank_width_meters + 16.0
			var bank: float = minf(_field.height_at(middle + across * bank_distance), _field.height_at(middle - across * bank_distance))
			assert_lt(_field.height_at(middle), bank - wadi.depth_meters * 0.4, "%s, segment %d" % [wadi.name, segment])


func test_grounds_follow_the_landscape() -> void:
	var mesa: SaharaSettings.Massif = _settings.massifs[0]
	assert_eq(_ground_at(mesa.center), SaharaSurface.GROUND_ROCK, "sommet de la gara")
	var main_wadi: SaharaSettings.Wadi = _settings.wadis[0]
	assert_eq(_ground_at((main_wadi.points[4] + main_wadi.points[5]) * 0.5), SaharaSurface.GROUND_EARTH, "lit de l'oued")
	assert_eq(_ground_at(_settings.star_dunes[0].center), SaharaSurface.GROUND_SAND, "Grande Dune")
	var seen: Dictionary = {}
	for bits: int in _surface.control_bits:
		seen[SaharaSurface.decode_base(bits)] = true
	assert_eq(seen.size(), SaharaSurface.GROUND_NAMES.size(), "les quatre sols sont présents")


func test_control_encoding_matches_terrain3d() -> void:
	var bits: int = SaharaSurface.encode_control(3, 2, 200)
	assert_eq(bits & 0xFFFFFFFF, Terrain3DUtil.enc_base(3) | Terrain3DUtil.enc_overlay(2) | Terrain3DUtil.enc_blend(200))
	assert_eq(Terrain3DUtil.get_base(bits & 0xFFFFFFFF), 3)
	assert_eq(Terrain3DUtil.get_overlay(bits & 0xFFFFFFFF), 2)
	assert_eq(Terrain3DUtil.get_blend(bits & 0xFFFFFFFF), 200)
	var image: Image = _surface.to_control_image()
	assert_eq(Terrain3DUtil.as_uint(image.get_pixel(0, 0).r), _surface.control_bits[0] & 0xFFFFFFFF)


func test_images_have_the_terrain3d_formats() -> void:
	assert_eq(_field.to_height_image().get_format(), Image.FORMAT_RF)
	assert_eq(_surface.to_control_image().get_format(), Image.FORMAT_RF)
	var color: Image = _surface.to_color_image()
	assert_eq(color.get_format(), Image.FORMAT_RGBA8)
	assert_eq(color.get_size(), Vector2i(TEST_PIXELS, TEST_PIXELS))


func test_invalid_generation_data_is_rejected() -> void:
	var data: Dictionary = JsonData.load_dictionary(DATA_PATH)["generation"].duplicate(true)
	data["region_size"] = 300
	data["massifs"][0]["kind"] = "volcan"
	data["wadis"][0]["points"] = [[0.0, 0.0]]
	data["erg"]["dunes"][0]["windward_fraction"] = 1.0
	assert_eq(SaharaSettings.from_dictionary(data).errors.size(), 4)


func _landmark(landmark_name: String) -> Vector3:
	for landmark: Dictionary in _field.landmarks:
		if landmark["name"] == landmark_name:
			return landmark["position"]
	fail_test("repère absent : " + landmark_name)
	return Vector3.ZERO


func _ground_at(world: Vector2) -> int:
	var pixel: Vector2i = _field.world_to_pixel(world)
	return _surface.base_ground(pixel.x, pixel.y)


func test_map_edges_meet_the_flat_background() -> void:
	var half: float = _settings.half_extent()
	for corner: Vector2 in [Vector2(-half, -half), Vector2(half, half), Vector2(-half, 0.0), Vector2(0.0, half)]:
		assert_almost_eq(_field.height_at(corner * 0.999), _settings.base_height_meters, 0.5, str(corner))
