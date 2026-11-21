class_name TerrainHeightmap
extends RefCounted
## Relief déterministe : une même graine et les mêmes réglages donnent toujours
## la même image de hauteurs (valeurs normalisées dans [-1 ; 1], format RF).


## Réglages du bruit lus dans les données de la scène.
class NoiseSettings:
	extends RefCounted
	var seed: int = 0
	var frequency: float = 0.00065
	var octaves: int = 5
	var lacunarity: float = 2.0
	var gain: float = 0.48

	static func from_dictionary(data: Dictionary, errors: PackedStringArray, context: String) -> NoiseSettings:
		var settings: NoiseSettings = NoiseSettings.new()
		settings.seed = int(JsonData.read_number(data, "seed", errors, context))
		settings.frequency = JsonData.read_number(data, "frequency", errors, context)
		settings.octaves = int(JsonData.read_number(data, "octaves", errors, context))
		settings.lacunarity = JsonData.read_number(data, "lacunarity", errors, context)
		settings.gain = JsonData.read_number(data, "gain", errors, context)
		if settings.frequency <= 0.0 or settings.octaves < 1 or settings.octaves > 9:
			errors.append(context + " : fréquence > 0 et octaves entre 1 et 9 attendues.")
		return settings


## Génère une image carrée de `size_pixels` côtés ; un pixel couvre `spacing_meters`.
static func generate(size_pixels: int, spacing_meters: float, settings: NoiseSettings) -> Image:
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = settings.seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.frequency = settings.frequency
	noise.fractal_octaves = settings.octaves
	noise.fractal_lacunarity = settings.lacunarity
	noise.fractal_gain = settings.gain
	var heights: PackedFloat32Array = PackedFloat32Array()
	heights.resize(size_pixels * size_pixels)
	var index: int = 0
	for pixel_z: int in size_pixels:
		var sample_z: float = float(pixel_z) * spacing_meters
		for pixel_x: int in size_pixels:
			heights[index] = noise.get_noise_2d(float(pixel_x) * spacing_meters, sample_z)
			index += 1
	return Image.create_from_data(size_pixels, size_pixels, false, Image.FORMAT_RF, heights.to_byte_array())
