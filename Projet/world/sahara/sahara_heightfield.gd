class_name SaharaHeightfield
extends RefCounted
## Relief déterministe du Sahara : reg ondulé, erg de dunes orientées par le vent,
## massifs rocheux (plateaux en gradins, crêtes, pitons), dunes étoilées et oueds secs.
## Le calcul se fait hors du jeu (constructeur) ; les mêmes réglages donnent toujours
## le même relief. Chaque élément localisé (oued, massif, dune étoilée) n'est calculé
## que dans sa boîte englobante : coût proportionnel à la surface qu'il couvre.

const FAR_DISTANCE: float = 1.0e6
const NO_WADI: int = 255
const ROCK_DETAIL_METERS: float = 2.5
const BANK_IRREGULARITY_METERS: float = 4.0
const DUNE_SUPPRESSION_RANGE: float = 3.0
const DETAIL_WAVELENGTH_METERS: float = 48.0
const RIDGE_CREST_ROUNDING: float = 0.06
const MASSIF_SMOOTHING_PASSES: int = 3

## Nombre de pixels par côté ; un pixel par sommet Terrain3D.
var size_pixels: int = 0
var spacing_meters: float = 1.0
## Position monde (x, z) du pixel (0, 0).
var origin: Vector2 = Vector2.ZERO
## Hauteurs en mètres, ligne par ligne (index = z * size_pixels + x).
var heights: PackedFloat32Array = PackedFloat32Array()
## Présence de l'erg (0 = reg, 1 = champ de dunes), après effacement par les oueds et massifs.
var erg_mask: PackedFloat32Array = PackedFloat32Array()
## Hauteur relative des dunes (0 à 1), utilisée pour les sols.
var dune_presence: PackedFloat32Array = PackedFloat32Array()
## Emprise rocheuse des massifs (0 à 1).
var rock_mask: PackedFloat32Array = PackedFloat32Array()
## Distance en mètres à l'axe de l'oued le plus proche (FAR_DISTANCE si aucun).
var wadi_distance: PackedFloat32Array = PackedFloat32Array()
## Indice de l'oued le plus proche (NO_WADI si aucun).
var wadi_index: PackedByteArray = PackedByteArray()
## Repères (massifs et dunes étoilées) : nom et position du sommet.
var landmarks: Array[Dictionary] = []

var _massif_height: PackedFloat32Array = PackedFloat32Array()
var _star_height: PackedFloat32Array = PackedFloat32Array()
var _dune_keep: PackedFloat32Array = PackedFloat32Array()
var _edge_noise: FastNoiseLite
var _detail_noise: FastNoiseLite


## Génère le relief complet sur une grille de `pixels` × `pixels` couvrant toute la carte.
static func generate(settings: SaharaSettings, pixels: int) -> SaharaHeightfield:
	var field: SaharaHeightfield = SaharaHeightfield.new()
	field._allocate(settings, pixels)
	field._stamp_wadis(settings)
	field._stamp_massifs(settings)
	field._stamp_star_dunes(settings)
	field._compose(settings)
	field._find_landmarks(settings)
	return field


static func make_noise(noise_seed: int, wavelength_meters: float, octaves: int) -> FastNoiseLite:
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = noise_seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM if octaves > 1 else FastNoiseLite.FRACTAL_NONE
	noise.fractal_octaves = octaves
	noise.frequency = 1.0 / wavelength_meters
	return noise


func pixel_to_world(pixel_x: int, pixel_z: int) -> Vector2:
	return origin + Vector2(float(pixel_x), float(pixel_z)) * spacing_meters


func world_to_pixel(world: Vector2) -> Vector2i:
	var grid: Vector2 = ((world - origin) / spacing_meters).round()
	return Vector2i(clampi(int(grid.x), 0, size_pixels - 1), clampi(int(grid.y), 0, size_pixels - 1))


## Hauteur interpolée en un point du monde (x, z), bornée à la carte.
func height_at(world: Vector2) -> float:
	var grid: Vector2 = (world - origin) / spacing_meters
	var max_index: float = float(size_pixels - 1)
	grid = grid.clamp(Vector2.ZERO, Vector2(max_index, max_index))
	var x0: int = mini(int(grid.x), size_pixels - 2)
	var z0: int = mini(int(grid.y), size_pixels - 2)
	var fx: float = grid.x - float(x0)
	var fz: float = grid.y - float(z0)
	var top: float = lerpf(heights[z0 * size_pixels + x0], heights[z0 * size_pixels + x0 + 1], fx)
	var bottom: float = lerpf(heights[(z0 + 1) * size_pixels + x0], heights[(z0 + 1) * size_pixels + x0 + 1], fx)
	return lerpf(top, bottom, fz)


## Pente en degrés au pixel donné (différences centrées).
func slope_degrees(pixel_x: int, pixel_z: int) -> float:
	var left: int = maxi(pixel_x - 1, 0)
	var right: int = mini(pixel_x + 1, size_pixels - 1)
	var up: int = maxi(pixel_z - 1, 0)
	var down: int = mini(pixel_z + 1, size_pixels - 1)
	var row: int = pixel_z * size_pixels
	var dx: float = (heights[row + right] - heights[row + left]) / (float(right - left) * spacing_meters)
	var dz: float = (heights[down * size_pixels + pixel_x] - heights[up * size_pixels + pixel_x]) / (float(down - up) * spacing_meters)
	return rad_to_deg(atan(sqrt(dx * dx + dz * dz)))


## Plus grande torsion d'une cellule praticable (pente inférieure à `max_slope_degrees`) :
## demi-écart entre les deux diagonales, c'est-à-dire l'écart maximal possible entre la
## surface affichée et la surface de collision, qui ne découpent pas la cellule pareil.
## Renvoie [torsion en mètres, position monde x, position monde z].
func max_walkable_twist(max_slope_degrees: float) -> PackedFloat32Array:
	var worst: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0])
	for pixel_z: int in size_pixels - 1:
		var row: int = pixel_z * size_pixels
		for pixel_x: int in size_pixels - 1:
			var index: int = row + pixel_x
			var twist: float = (
				absf(heights[index] + heights[index + size_pixels + 1] - heights[index + 1] - heights[index + size_pixels]) * 0.5
			)
			if twist <= worst[0]:
				continue
			if (
				slope_degrees(pixel_x, pixel_z) > max_slope_degrees
				or slope_degrees(pixel_x + 1, pixel_z) > max_slope_degrees
				or slope_degrees(pixel_x, pixel_z + 1) > max_slope_degrees
				or slope_degrees(pixel_x + 1, pixel_z + 1) > max_slope_degrees
			):
				continue
			var point: Vector2 = pixel_to_world(pixel_x, pixel_z)
			worst = PackedFloat32Array([twist, point.x, point.y])
	return worst


## Image des hauteurs au format attendu par Terrain3D (FORMAT_RF, mètres).
func to_height_image() -> Image:
	return Image.create_from_data(size_pixels, size_pixels, false, Image.FORMAT_RF, heights.to_byte_array())


func _allocate(settings: SaharaSettings, pixels: int) -> void:
	size_pixels = pixels
	spacing_meters = settings.map_size_meters / float(pixels)
	origin = Vector2(-settings.half_extent(), -settings.half_extent())
	var count: int = pixels * pixels
	heights.resize(count)
	erg_mask.resize(count)
	dune_presence.resize(count)
	rock_mask.resize(count)
	_massif_height.resize(count)
	_star_height.resize(count)
	heights.fill(0.0)
	erg_mask.fill(0.0)
	dune_presence.fill(0.0)
	rock_mask.fill(0.0)
	_massif_height.fill(0.0)
	_star_height.fill(0.0)
	_dune_keep.resize(count)
	_dune_keep.fill(1.0)
	wadi_distance.resize(count)
	wadi_distance.fill(FAR_DISTANCE)
	wadi_index.resize(count)
	wadi_index.fill(NO_WADI)
	_edge_noise = make_noise(settings.world_seed + 101, 160.0, 3)
	# Détail assez large pour rester plan à l'échelle d'une cellule de 2 m (voir max_walkable_twist).
	_detail_noise = make_noise(settings.world_seed + 102, DETAIL_WAVELENGTH_METERS, 1)


## Retourne [x_min, z_min, x_max, z_max] en pixels pour un rectangle monde.
func _pixel_bounds(world_min: Vector2, world_max: Vector2) -> PackedInt32Array:
	var low: Vector2 = ((world_min - origin) / spacing_meters).floor()
	var high: Vector2 = ((world_max - origin) / spacing_meters).ceil()
	return PackedInt32Array(
		[
			clampi(int(low.x), 0, size_pixels - 1),
			clampi(int(low.y), 0, size_pixels - 1),
			clampi(int(high.x), 0, size_pixels - 1),
			clampi(int(high.y), 0, size_pixels - 1),
		]
	)


func _stamp_wadis(settings: SaharaSettings) -> void:
	for index: int in settings.wadis.size():
		var wadi: SaharaSettings.Wadi = settings.wadis[index]
		var reach: float = wadi.floor_half_width_meters + wadi.bank_width_meters * DUNE_SUPPRESSION_RANGE
		for segment: int in wadi.points.size() - 1:
			var start: Vector2 = wadi.points[segment]
			var along: Vector2 = wadi.points[segment + 1] - start
			var length_squared: float = maxf(along.length_squared(), 0.0001)
			var bounds: PackedInt32Array = _pixel_bounds(
				start.min(start + along) - Vector2(reach, reach), start.max(start + along) + Vector2(reach, reach)
			)
			for pixel_z: int in range(bounds[1], bounds[3] + 1):
				var row: int = pixel_z * size_pixels
				for pixel_x: int in range(bounds[0], bounds[2] + 1):
					var point: Vector2 = pixel_to_world(pixel_x, pixel_z)
					var t: float = clampf((point - start).dot(along) / length_squared, 0.0, 1.0)
					var distance: float = point.distance_to(start + along * t)
					if distance < wadi_distance[row + pixel_x]:
						wadi_distance[row + pixel_x] = distance
						wadi_index[row + pixel_x] = index


func _stamp_massifs(settings: SaharaSettings) -> void:
	var all_bounds: Array[PackedInt32Array] = []
	for massif: SaharaSettings.Massif in settings.massifs:
		var reach: float = maxf(massif.radii.x, massif.radii.y) * 1.8
		var bounds: PackedInt32Array = _pixel_bounds(massif.center - Vector2(reach, reach), massif.center + Vector2(reach, reach))
		all_bounds.append(bounds)
		var rotation: Vector2 = Vector2.from_angle(-massif.angle_radians)
		for pixel_z: int in range(bounds[1], bounds[3] + 1):
			var row: int = pixel_z * size_pixels
			for pixel_x: int in range(bounds[0], bounds[2] + 1):
				var point: Vector2 = pixel_to_world(pixel_x, pixel_z)
				var offset: Vector2 = point - massif.center
				var local: Vector2 = Vector2(offset.x * rotation.x - offset.y * rotation.y, offset.x * rotation.y + offset.y * rotation.x)
				var distance: float = (local / massif.radii).length()
				distance *= 1.0 + massif.edge_noise * _edge_noise.get_noise_2dv(point)
				var height: float = _massif_profile(massif, distance)
				var index: int = row + pixel_x
				if height > _massif_height[index]:
					_massif_height[index] = height
				rock_mask[index] = maxf(rock_mask[index], 1.0 - smoothstep(0.92, 1.2, distance))
				_dune_keep[index] = minf(_dune_keep[index], smoothstep(0.95, 1.7, distance))
	# Les arêtes (rebord, gradins) ne doivent pas être plus fines qu'une cellule :
	# un léger flou gaussien efface ce que la grille ne peut pas représenter.
	for bounds: PackedInt32Array in all_bounds:
		for pass_index: int in MASSIF_SMOOTHING_PASSES:
			_blur_bounds(_massif_height, bounds, 1, 0)
			_blur_bounds(_massif_height, bounds, 0, 1)


## Flou gaussien à 5 coefficients (1, 4, 6, 4, 1) le long d'un axe, limité à une boîte.
func _blur_bounds(values: PackedFloat32Array, bounds: PackedInt32Array, step_x: int, step_z: int) -> void:
	var line: PackedFloat32Array = PackedFloat32Array()
	var horizontal: bool = step_x == 1
	var length: int = (bounds[2] - bounds[0] + 1) if horizontal else (bounds[3] - bounds[1] + 1)
	var lines: int = (bounds[3] - bounds[1] + 1) if horizontal else (bounds[2] - bounds[0] + 1)
	line.resize(length)
	var stride: int = step_x + step_z * size_pixels
	for line_index: int in lines:
		var first: int = (
			(bounds[1] + line_index) * size_pixels + bounds[0] if horizontal else bounds[1] * size_pixels + bounds[0] + line_index
		)
		for position: int in length:
			line[position] = values[first + position * stride]
		for position: int in length:
			var far_left: float = line[maxi(position - 2, 0)]
			var left: float = line[maxi(position - 1, 0)]
			var right: float = line[mini(position + 1, length - 1)]
			var far_right: float = line[mini(position + 2, length - 1)]
			values[first + position * stride] = (far_left + 4.0 * left + 6.0 * line[position] + 4.0 * right + far_right) / 16.0


static func _massif_profile(massif: SaharaSettings.Massif, distance: float) -> float:
	var talus: float = massif.talus_meters * (1.0 - smoothstep(0.85, 1.55, distance))
	match massif.kind:
		"mesa":
			var core: float = 1.0 - smoothstep(1.0 - massif.cliff_fraction, 1.0, distance)
			if massif.terraces > 0:
				var steps: float = core * float(massif.terraces)
				var step: float = floorf(steps)
				# Contremarche adoucie sur 65 % du gradin : pas d'arête plus fine qu'une cellule.
				core = (step + smoothstep(0.35, 1.0, steps - step)) / float(massif.terraces)
			return massif.height_meters * core + talus * (1.0 - core)
		"ridge":
			# Faîte arrondi sur quelques mètres : une arête plus fine qu'une cellule ne se représente pas.
			var rounded: float = sqrt(distance * distance + RIDGE_CREST_ROUNDING * RIDGE_CREST_ROUNDING) - RIDGE_CREST_ROUNDING
			var crest: float = pow(maxf(1.0 - rounded, 0.0), 1.3)
			return massif.height_meters * crest + talus * (1.0 - crest)
		_:
			var dome: float = pow(maxf(1.0 - distance * distance, 0.0), 0.55)
			return massif.height_meters * dome + talus * (1.0 - dome)


func _stamp_star_dunes(settings: SaharaSettings) -> void:
	for dune: SaharaSettings.StarDune in settings.star_dunes:
		var reach: float = dune.radius_meters * 1.1
		var bounds: PackedInt32Array = _pixel_bounds(dune.center - Vector2(reach, reach), dune.center + Vector2(reach, reach))
		for pixel_z: int in range(bounds[1], bounds[3] + 1):
			var row: int = pixel_z * size_pixels
			for pixel_x: int in range(bounds[0], bounds[2] + 1):
				var offset: Vector2 = pixel_to_world(pixel_x, pixel_z) - dune.center
				var distance: float = offset.length() / dune.radius_meters
				if distance >= 1.0:
					continue
				# Les bras s'effacent vers le sommet pour éviter une pointe singulière au centre.
				var arm_shape: float = 0.72 + 0.28 * cos(float(dune.arms) * offset.angle() + dune.twist * distance * TAU)
				var arms: float = lerpf(1.0, arm_shape, smoothstep(0.0, 0.35, distance))
				var height: float = dune.height_meters * (1.0 - smoothstep(0.0, 1.0, distance)) * arms
				var index: int = row + pixel_x
				_star_height[index] = maxf(_star_height[index], height)
				_dune_keep[index] = minf(_dune_keep[index], lerpf(0.35, 1.0, smoothstep(0.2, 1.0, distance)))


func _compose(settings: SaharaSettings) -> void:
	var half: float = settings.half_extent()
	var undulation: FastNoiseLite = make_noise(settings.world_seed + 1, settings.undulation_wavelength_meters, 3)
	var roughness: FastNoiseLite = make_noise(settings.world_seed + 2, settings.roughness_wavelength_meters, 2)
	var erg_noise: FastNoiseLite = make_noise(settings.world_seed + 3, settings.erg_wavelength_meters, 3)
	var layer_count: int = settings.dune_layers.size()
	var warps: Array[FastNoiseLite] = []
	var crests: Array[FastNoiseLite] = []
	var winds: PackedVector2Array = PackedVector2Array()
	var parameters: PackedFloat32Array = PackedFloat32Array()
	var amplitude_sum: float = settings.erg_sheet_height_meters
	for layer_index: int in layer_count:
		var layer: SaharaSettings.DuneLayer = settings.dune_layers[layer_index]
		warps.append(make_noise(settings.world_seed + 10 + layer_index * 2, layer.warp_wavelength_meters, 2))
		crests.append(make_noise(settings.world_seed + 11 + layer_index * 2, layer.wavelength_meters * 3.0, 2))
		winds.append(layer.wind)
		parameters.append_array(
			PackedFloat32Array(
				[layer.wavelength_meters, layer.amplitude_meters, layer.windward_fraction, layer.warp_meters, layer.crest_variation]
			)
		)
		amplitude_sum += layer.amplitude_meters
	var erg_low: float = settings.erg_threshold - settings.erg_transition
	var erg_high: float = settings.erg_threshold + settings.erg_transition

	for pixel_z: int in size_pixels:
		var row: int = pixel_z * size_pixels
		for pixel_x: int in size_pixels:
			var index: int = row + pixel_x
			var point: Vector2 = pixel_to_world(pixel_x, pixel_z)
			var detail: float = roughness.get_noise_2dv(point)
			var base: float = (
				settings.base_height_meters
				+ settings.tilt_meters * settings.tilt_direction.dot(point) / half
				+ settings.undulation_amplitude_meters * undulation.get_noise_2dv(point)
				+ settings.roughness_amplitude_meters * detail
			)
			var erg_value: float = (
				erg_noise.get_noise_2dv(point) + settings.erg_bias_strength * settings.erg_bias_direction.dot(point) / half
			)
			var erg: float = smoothstep(erg_low, erg_high, erg_value)

			var dunes: float = settings.erg_sheet_height_meters
			if erg > 0.0:
				for layer_index: int in layer_count:
					var parameter: int = layer_index * 5
					var phase: float = winds[layer_index].dot(point) + parameters[parameter + 3] * warps[layer_index].get_noise_2dv(point)
					var t: float = fposmod(phase / parameters[parameter], 1.0)
					var windward: float = parameters[parameter + 2]
					var profile: float = (
						smoothstep(0.0, 1.0, t / windward) if t < windward else smoothstep(0.0, 1.0, (1.0 - t) / (1.0 - windward))
					)
					var variation: float = parameters[parameter + 4]
					var crest: float = 1.0 - variation + variation * (0.5 + 0.5 * crests[layer_index].get_noise_2dv(point))
					dunes += parameters[parameter + 1] * profile * crest

			var carve: float = 0.0
			var wadi_keep: float = 1.0
			var nearest_wadi: int = wadi_index[index]
			if nearest_wadi != NO_WADI:
				var wadi: SaharaSettings.Wadi = settings.wadis[nearest_wadi]
				var distance: float = wadi_distance[index] + BANK_IRREGULARITY_METERS * _detail_noise.get_noise_2dv(point)
				var bank_end: float = wadi.floor_half_width_meters + wadi.bank_width_meters
				carve = wadi.depth_meters * (1.0 - smoothstep(wadi.floor_half_width_meters, bank_end, distance))
				wadi_keep = smoothstep(
					wadi.floor_half_width_meters, wadi.floor_half_width_meters + wadi.bank_width_meters * DUNE_SUPPRESSION_RANGE, distance
				)

			var keep: float = _dune_keep[index] * wadi_keep
			var star: float = _star_height[index] * wadi_keep
			var dune_height: float = erg * dunes * keep + star
			var height: float = base + dune_height + _massif_height[index] + rock_mask[index] * ROCK_DETAIL_METERS * detail - carve
			# Raccord aux bords : le relief rejoint l'altitude de base, celle du sol plat
			# qui prolonge la carte (fond « FLAT » de Terrain3D).
			var border: float = minf(minf(point.x + half, half - point.x), minf(point.y + half, half - point.y))
			heights[index] = lerpf(settings.base_height_meters, height, smoothstep(0.0, settings.edge_blend_meters, border))
			erg_mask[index] = maxf(erg * keep, smoothstep(0.0, 6.0, star))
			dune_presence[index] = clampf(dune_height / amplitude_sum, 0.0, 1.0)


func _find_landmarks(settings: SaharaSettings) -> void:
	for massif: SaharaSettings.Massif in settings.massifs:
		landmarks.append({"name": massif.name, "kind": massif.kind, "position": _peak_near(massif.center, massif.radii.x)})
	for dune: SaharaSettings.StarDune in settings.star_dunes:
		landmarks.append({"name": dune.name, "kind": "star_dune", "position": _peak_near(dune.center, dune.radius_meters * 0.3)})


## Point le plus haut dans un disque (repère pour les points de vue et les tests).
func _peak_near(center: Vector2, radius: float) -> Vector3:
	var bounds: PackedInt32Array = _pixel_bounds(center - Vector2(radius, radius), center + Vector2(radius, radius))
	var best: Vector3 = Vector3(center.x, height_at(center), center.y)
	for pixel_z: int in range(bounds[1], bounds[3] + 1):
		for pixel_x: int in range(bounds[0], bounds[2] + 1):
			var height: float = heights[pixel_z * size_pixels + pixel_x]
			if height > best.y:
				var point: Vector2 = pixel_to_world(pixel_x, pixel_z)
				best = Vector3(point.x, height, point.y)
	return best
