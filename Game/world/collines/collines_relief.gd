class_name CollinesRelief
extends RefCounted
## Relief et répartition des surfaces de la carte « collines », calculés à partir des données.
##
## Calcul pur, sans nœud : la même graine et les mêmes réglages donnent exactement le même résultat.
## La grille compte size_px × size_px sommets espacés de spacing mètres (size_px = mailles + 1), rangés ligne par
## ligne (index = z * size_px + x) ; le sommet (0, 0) est au coin (origin.x, origin.y) du monde (axes X et Z).
## Coût : O(size_px²) en temps et en mémoire (1 050 625 sommets pour 1 024 m au mètre, moins d'une seconde).

const CONTEXT: String = "collines.json > terrain"
const BLEND_LEVELS: int = 255

var size_px: int = 0
var spacing: float = 1.0
var origin: Vector2 = Vector2.ZERO
var heights := PackedFloat32Array()


## Génère le relief décrit par la section « terrain » des données. Renvoie null si les données sont invalides.
static func generate(terrain: Dictionary) -> CollinesRelief:
	var size_m: float = JsonData.get_float(terrain, "size_m", CONTEXT)
	var vertex_spacing: float = JsonData.get_float(terrain, "vertex_spacing_m", CONTEXT)
	if size_m <= 0.0 or vertex_spacing <= 0.0:
		push_error("CollinesRelief : size_m et vertex_spacing_m doivent être strictement positifs (%s)." % CONTEXT)
		return null
	var cells: int = int(roundf(size_m / vertex_spacing))
	if not is_equal_approx(float(cells) * vertex_spacing, size_m) or cells < 2:
		push_error("CollinesRelief : size_m doit être un multiple de vertex_spacing_m (%s)." % CONTEXT)
		return null
	var count: int = cells + 1
	var relief_config: Dictionary = JsonData.get_dictionary(terrain, "relief", CONTEXT)
	var context: String = CONTEXT + " > relief"
	var amplitude: float = JsonData.get_float(relief_config, "amplitude_m", context)
	var noise_range: float = JsonData.get_float(relief_config, "noise_range", context)
	var exponent: float = JsonData.get_float(relief_config, "shape_exponent", context)
	var edge_margin: float = JsonData.get_float(relief_config, "edge_margin_m", context)
	var edge_height: float = JsonData.get_float(relief_config, "edge_height_m", context)
	if amplitude <= 0.0 or noise_range <= 0.0 or exponent <= 0.0 or edge_margin <= 0.0:
		push_error("CollinesRelief : amplitude_m, noise_range, shape_exponent et edge_margin_m doivent être positifs (%s)." % context)
		return null
	var noise: FastNoiseLite = _make_noise(relief_config, context)

	var relief := CollinesRelief.new()
	relief.size_px = count
	relief.spacing = vertex_spacing
	relief.origin = Vector2(-size_m * 0.5, -size_m * 0.5)
	relief.heights.resize(count * count)
	var last: float = float(count - 1) * vertex_spacing
	var index: int = 0
	for z: int in count:
		var local_z: float = float(z) * vertex_spacing
		var edge_z: float = minf(local_z, last - local_z)
		for x: int in count:
			var local_x: float = float(x) * vertex_spacing
			# Les coordonnées du bruit sont celles du monde : le relief ne dépend pas de la taille de la grille.
			var value: float = noise.get_noise_2d(relief.origin.x + local_x, relief.origin.y + local_z)
			var t: float = clampf(value / noise_range * 0.5 + 0.5, 0.0, 1.0)
			var height: float = amplitude * pow(t, exponent)
			# Bord adouci : le relief rejoint la plaine qui entoure la carte (fond plat de Terrain3D).
			var edge: float = smoothstep(0.0, edge_margin, minf(minf(local_x, last - local_x), edge_z))
			relief.heights[index] = lerpf(edge_height, height, edge)
			index += 1
	return relief


static func _make_noise(config: Dictionary, context: String) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = JsonData.get_int(config, "seed", context)
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = JsonData.get_float(config, "frequency", context)
	if config.has("octaves"):
		noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		noise.fractal_octaves = JsonData.get_int(config, "octaves", context)
		noise.fractal_lacunarity = JsonData.get_float(config, "lacunarity", context)
		noise.fractal_gain = JsonData.get_float(config, "gain", context)
	else:
		noise.fractal_type = FastNoiseLite.FRACTAL_NONE
	return noise


## Hauteur interpolée (bilinéaire) à la position du monde (x, z), bornée à la grille.
func height_at(world_x: float, world_z: float) -> float:
	var fx: float = clampf((world_x - origin.x) / spacing, 0.0, float(size_px - 1))
	var fz: float = clampf((world_z - origin.y) / spacing, 0.0, float(size_px - 1))
	var x0: int = mini(int(fx), size_px - 2)
	var z0: int = mini(int(fz), size_px - 2)
	var tx: float = fx - float(x0)
	var tz: float = fz - float(z0)
	var i: int = z0 * size_px + x0
	var top: float = lerpf(heights[i], heights[i + 1], tx)
	var bottom: float = lerpf(heights[i + size_px], heights[i + size_px + 1], tx)
	return lerpf(top, bottom, tz)


## Pente (tangente de l'angle avec l'horizontale) au sommet (x, z), par différences centrées.
func slope_tangent(x: int, z: int) -> float:
	var x_prev: int = maxi(x - 1, 0)
	var x_next: int = mini(x + 1, size_px - 1)
	var z_prev: int = maxi(z - 1, 0)
	var z_next: int = mini(z + 1, size_px - 1)
	var row: int = z * size_px
	var dx: float = (heights[row + x_next] - heights[row + x_prev]) / (float(x_next - x_prev) * spacing)
	var dz: float = (heights[z_next * size_px + x] - heights[z_prev * size_px + x]) / (float(z_next - z_prev) * spacing)
	return sqrt(dx * dx + dz * dz)


## Proportion (0 à 255) de la texture de recouvrement (pierre) sur chaque sommet : pentes fortes et
## hauteurs, légèrement variée par un bruit pour casser les lisières régulières. Null si données invalides.
func overlay_blend(rules: Dictionary) -> PackedByteArray:
	var context: String = CONTEXT + " > overlay_rules"
	var slope_start: float = tan(deg_to_rad(JsonData.get_float(rules, "slope_start_deg", context)))
	var slope_full: float = tan(deg_to_rad(JsonData.get_float(rules, "slope_full_deg", context)))
	var altitude_start: float = JsonData.get_float(rules, "altitude_start_m", context)
	var altitude_full: float = JsonData.get_float(rules, "altitude_full_m", context)
	var variation: float = JsonData.get_float(rules, "variation_amplitude", context)
	var result := PackedByteArray()
	if slope_full <= slope_start or altitude_full <= altitude_start or variation < 0.0:
		push_error("CollinesRelief : seuils de pente ou d'altitude incohérents (%s)." % context)
		return result
	var noise: FastNoiseLite = _make_noise(JsonData.get_dictionary(rules, "variation_noise", context), context + " > variation_noise")
	result.resize(size_px * size_px)
	var index: int = 0
	for z: int in size_px:
		var world_z: float = origin.y + float(z) * spacing
		for x: int in size_px:
			var weight: float = maxf(
				smoothstep(slope_start, slope_full, slope_tangent(x, z)), smoothstep(altitude_start, altitude_full, heights[index])
			)
			weight = clampf(weight + variation * noise.get_noise_2d(origin.x + float(x) * spacing, world_z), 0.0, 1.0)
			result[index] = int(roundf(weight * float(BLEND_LEVELS)))
			index += 1
	return result


## Carte des normales au sol (RG8) : composantes monde X et Z de la normale unitaire, codées de 0 à 255.
## La composante Y se reconstruit dans le shader. Lue par le shader du terrain : les normales sont donc
## identiques quel que soit le niveau de détail du maillage.
func normal_image() -> Image:
	var bytes := PackedByteArray()
	bytes.resize(size_px * size_px * 2)
	var index: int = 0
	for z: int in size_px:
		var z_prev: int = maxi(z - 1, 0)
		var z_next: int = mini(z + 1, size_px - 1)
		var row: int = z * size_px
		for x: int in size_px:
			var x_prev: int = maxi(x - 1, 0)
			var x_next: int = mini(x + 1, size_px - 1)
			var dx: float = (heights[row + x_next] - heights[row + x_prev]) / (float(x_next - x_prev) * spacing)
			var dz: float = (heights[z_next * size_px + x] - heights[z_prev * size_px + x]) / (float(z_next - z_prev) * spacing)
			var inverse_length: float = 1.0 / sqrt(dx * dx + dz * dz + 1.0)
			bytes[index] = int(roundf((-dx * inverse_length * 0.5 + 0.5) * 255.0))
			bytes[index + 1] = int(roundf((-dz * inverse_length * 0.5 + 0.5) * 255.0))
			index += 2
	return Image.create_from_data(size_px, size_px, false, Image.FORMAT_RG8, bytes)


## Indice de grille du sommet le plus haut (point de vue du pire cas : tout le terrain visible).
func highest_index() -> int:
	var best: int = 0
	for i: int in heights.size():
		if heights[i] > heights[best]:
			best = i
	return best


func world_position_of(index: int) -> Vector3:
	var x: int = index % size_px
	var z: int = floori(float(index) / float(size_px))
	return Vector3(origin.x + float(x) * spacing, heights[index], origin.y + float(z) * spacing)
