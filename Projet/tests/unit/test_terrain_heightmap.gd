extends GutTest

const SIZE_PIXELS: int = 64
const SPACING_METERS: float = 2.0


func _settings(seed: int) -> TerrainHeightmap.NoiseSettings:
	var errors: PackedStringArray = PackedStringArray()
	var settings: TerrainHeightmap.NoiseSettings = TerrainHeightmap.NoiseSettings.from_dictionary(
		{"seed": seed, "frequency": 0.00065, "octaves": 5, "lacunarity": 2.0, "gain": 0.48}, errors, "test"
	)
	assert_true(errors.is_empty(), str(errors))
	return settings


func test_same_seed_gives_identical_heightmap() -> void:
	var first: Image = TerrainHeightmap.generate(SIZE_PIXELS, SPACING_METERS, _settings(1332))
	var second: Image = TerrainHeightmap.generate(SIZE_PIXELS, SPACING_METERS, _settings(1332))
	assert_eq(first.get_data(), second.get_data())


func test_other_seed_gives_other_heightmap() -> void:
	var first: Image = TerrainHeightmap.generate(SIZE_PIXELS, SPACING_METERS, _settings(1332))
	var second: Image = TerrainHeightmap.generate(SIZE_PIXELS, SPACING_METERS, _settings(1406))
	assert_ne(first.get_data(), second.get_data())


func test_format_size_and_range() -> void:
	var image: Image = TerrainHeightmap.generate(SIZE_PIXELS, SPACING_METERS, _settings(1332))
	assert_eq(image.get_format(), Image.FORMAT_RF)
	assert_eq(image.get_size(), Vector2i(SIZE_PIXELS, SIZE_PIXELS))
	for pixel_index: int in [0, 17, 1000, SIZE_PIXELS * SIZE_PIXELS - 1]:
		var height: float = image.get_pixel(pixel_index % SIZE_PIXELS, pixel_index / SIZE_PIXELS).r
		assert_between(height, -1.0, 1.0)


func test_invalid_noise_settings_are_rejected() -> void:
	var errors: PackedStringArray = PackedStringArray()
	TerrainHeightmap.NoiseSettings.from_dictionary(
		{"seed": 1, "frequency": 0.0, "octaves": 12, "lacunarity": 2.0, "gain": 0.5}, errors, "test"
	)
	assert_eq(errors.size(), 1)


func test_shipped_terrain_data_is_complete() -> void:
	var data: Dictionary = JsonData.load_dictionary("res://data/terrain_test/terrain_test.json")
	for section: String in ["terrain", "environment", "camera", "measure_route", "help_text"]:
		assert_true(data.has(section), section)
