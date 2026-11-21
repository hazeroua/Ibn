class_name SaharaSurface
extends RefCounted
## Sols du Sahara calculés à partir du relief : pour chaque sommet, texture dominante,
## texture secondaire et mélange (carte de contrôle Terrain3D), plus une teinte à grande
## échelle (carte de couleur) qui casse la répétition des textures vue de loin.

## Identifiants de textures : l'ordre doit correspondre à la liste « textures » de sahara.json.
const GROUND_SAND: int = 0
const GROUND_EARTH: int = 1
const GROUND_GRAVEL: int = 2
const GROUND_ROCK: int = 3
const GROUND_NAMES: PackedStringArray = ["sand", "earth", "gravel", "rock"]

## Format de la carte de contrôle Terrain3D 1.1 (entier 32 bits stocké dans un flottant).
const BASE_SHIFT: int = 27
const OVERLAY_SHIFT: int = 22
const BLEND_SHIFT: int = 14
const NEUTRAL_ROUGHNESS: float = 0.5
const PATCH_SOFTNESS: float = 0.15

var size_pixels: int = 0
## Carte de contrôle encodée (bits Terrain3D), une valeur par sommet.
var control_bits: PackedInt32Array = PackedInt32Array()
## Carte de couleur RGBA8 : teinte multipliée à l'albédo, alpha = modificateur de rugosité.
var colors: PackedByteArray = PackedByteArray()


static func encode_control(base: int, overlay: int, blend: int) -> int:
	return (base << BASE_SHIFT) | (overlay << OVERLAY_SHIFT) | (clampi(blend, 0, 255) << BLEND_SHIFT)


static func decode_base(bits: int) -> int:
	return (bits >> BASE_SHIFT) & 0x1F


static func decode_overlay(bits: int) -> int:
	return (bits >> OVERLAY_SHIFT) & 0x1F


static func decode_blend(bits: int) -> int:
	return (bits >> BLEND_SHIFT) & 0xFF


static func generate(field: SaharaHeightfield, settings: SaharaSettings) -> SaharaSurface:
	var surface: SaharaSurface = SaharaSurface.new()
	surface._compute(field, settings)
	return surface


func to_control_image() -> Image:
	return Image.create_from_data(size_pixels, size_pixels, false, Image.FORMAT_RF, control_bits.to_byte_array())


func to_color_image() -> Image:
	return Image.create_from_data(size_pixels, size_pixels, false, Image.FORMAT_RGBA8, colors)


## Texture dominante au pixel (pour les tests et les points de vue).
func base_ground(pixel_x: int, pixel_z: int) -> int:
	return decode_base(control_bits[pixel_z * size_pixels + pixel_x])


func _compute(field: SaharaHeightfield, settings: SaharaSettings) -> void:
	size_pixels = field.size_pixels
	var count: int = size_pixels * size_pixels
	control_bits.resize(count)
	colors.resize(count * 4)
	var earth_noise: FastNoiseLite = SaharaHeightfield.make_noise(settings.world_seed + 201, settings.earth_patch_wavelength_meters, 3)
	var sand_noise: FastNoiseLite = SaharaHeightfield.make_noise(settings.world_seed + 202, settings.sand_sheet_wavelength_meters, 3)
	var tint_noise: FastNoiseLite = SaharaHeightfield.make_noise(settings.world_seed + 203, settings.color_variation_wavelength_meters, 4)
	var earth_threshold: float = 1.0 - 2.0 * settings.earth_patch_coverage
	var sand_threshold: float = 1.0 - 2.0 * settings.sand_sheet_coverage
	var weights: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])

	for pixel_z: int in size_pixels:
		var row: int = pixel_z * size_pixels
		for pixel_x: int in size_pixels:
			var index: int = row + pixel_x
			var point: Vector2 = field.pixel_to_world(pixel_x, pixel_z)
			var erg: float = field.erg_mask[index]
			var reg: float = 1.0 - erg
			var slope: float = field.slope_degrees(pixel_x, pixel_z)
			var rock: float = maxf(
				field.rock_mask[index], smoothstep(settings.rock_slope_degrees.x, settings.rock_slope_degrees.y, slope) * reg
			)
			var wadi_floor: float = 0.0
			var nearest_wadi: int = field.wadi_index[index]
			if nearest_wadi != SaharaHeightfield.NO_WADI:
				var wadi: SaharaSettings.Wadi = settings.wadis[nearest_wadi]
				wadi_floor = (
					1.0
					- smoothstep(
						wadi.floor_half_width_meters * 0.7,
						wadi.floor_half_width_meters + wadi.bank_width_meters * 0.5,
						field.wadi_distance[index]
					)
				)
			var earth_patch: float = smoothstep(
				earth_threshold - PATCH_SOFTNESS, earth_threshold + PATCH_SOFTNESS, earth_noise.get_noise_2dv(point)
			)
			var sand_sheet: float = smoothstep(
				sand_threshold - PATCH_SOFTNESS, sand_threshold + PATCH_SOFTNESS, sand_noise.get_noise_2dv(point)
			)
			var open_ground: float = 1.0 - rock
			weights[GROUND_SAND] = maxf(erg, reg * sand_sheet * 0.95) * (1.0 - wadi_floor) * open_ground
			weights[GROUND_EARTH] = maxf(wadi_floor, reg * earth_patch * 0.9) * open_ground
			weights[GROUND_GRAVEL] = reg * 0.8 * (1.0 - wadi_floor) * open_ground
			weights[GROUND_ROCK] = rock
			control_bits[index] = _encode_two_strongest(weights)

			var tint: Color = settings.reg_tint.lerp(settings.erg_tint, erg)
			tint = tint.lerp(settings.wadi_tint, wadi_floor)
			tint = tint.lerp(settings.rock_tint, rock)
			var variation: float = 1.0 + settings.color_variation_strength * tint_noise.get_noise_2dv(point)
			var byte_index: int = index * 4
			colors[byte_index] = clampi(roundi(tint.r * variation * 255.0), 0, 255)
			colors[byte_index + 1] = clampi(roundi(tint.g * variation * 255.0), 0, 255)
			colors[byte_index + 2] = clampi(roundi(tint.b * variation * 255.0), 0, 255)
			colors[byte_index + 3] = roundi(NEUTRAL_ROUGHNESS * 255.0)


static func _encode_two_strongest(weights: PackedFloat32Array) -> int:
	var first: int = 0
	var second: int = 1
	if weights[1] > weights[0]:
		first = 1
		second = 0
	for ground: int in range(2, weights.size()):
		if weights[ground] > weights[first]:
			second = first
			first = ground
		elif weights[ground] > weights[second]:
			second = ground
	var total: float = weights[first] + weights[second]
	if total <= 0.0001:
		return encode_control(GROUND_GRAVEL, GROUND_GRAVEL, 0)
	return encode_control(first, second, roundi(255.0 * weights[second] / total))
