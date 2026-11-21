class_name SaharaSettings
extends RefCounted
## Réglages du relief et des sols du Sahara, lus dans data/sahara/sahara.json
## (section « generation »). Toute valeur manquante ou incohérente est une erreur.

const CONTEXT: String = "sahara.json › generation"


## Couche de dunes : crêtes perpendiculaires au vent, face au vent douce, face sous le vent raide.
class DuneLayer:
	extends RefCounted
	var wavelength_meters: float = 240.0
	var amplitude_meters: float = 26.0
	## Direction du vent dans le plan (x, z), normalisée.
	var wind: Vector2 = Vector2.RIGHT
	## Part de la longueur d'onde occupée par la face au vent (pente douce).
	var windward_fraction: float = 0.72
	var warp_meters: float = 90.0
	var warp_wavelength_meters: float = 700.0
	## Variation de hauteur le long des crêtes (0 = crêtes régulières).
	var crest_variation: float = 0.45


## Relief rocheux posé sur le terrain : plateau (« mesa »), crête allongée (« ridge ») ou piton (« inselberg »).
class Massif:
	extends RefCounted
	var name: String = ""
	var kind: String = "mesa"
	var center: Vector2 = Vector2.ZERO
	var radii: Vector2 = Vector2.ONE
	var angle_radians: float = 0.0
	var height_meters: float = 0.0
	var cliff_fraction: float = 0.2
	var terraces: int = 0
	var edge_noise: float = 0.15
	var talus_meters: float = 0.0


## Grande dune étoilée servant de repère dans l'erg.
class StarDune:
	extends RefCounted
	var name: String = ""
	var center: Vector2 = Vector2.ZERO
	var radius_meters: float = 300.0
	var height_meters: float = 100.0
	var arms: int = 3
	var twist: float = 1.2


## Oued sec : lit plat creusé le long d'une ligne brisée, berges en pente douce.
class Wadi:
	extends RefCounted
	var name: String = ""
	var points: PackedVector2Array = PackedVector2Array()
	var floor_half_width_meters: float = 12.0
	var bank_width_meters: float = 30.0
	var depth_meters: float = 7.0


var world_seed: int = 0
var map_size_meters: float = 4096.0
var vertex_spacing_meters: float = 2.0
var region_size: int = 512
## Largeur de la bande où le relief rejoint l'altitude de base au bord de la carte.
var edge_blend_meters: float = 250.0
## Torsion maximale d'une cellule praticable (écart affichage / collision), en mètres.
var max_walkable_twist_meters: float = 0.3
## Pente au-delà de laquelle une cellule n'est plus praticable.
var walkable_slope_degrees: float = 45.0

var base_height_meters: float = 40.0
var tilt_meters: float = 0.0
var tilt_direction: Vector2 = Vector2.RIGHT
var undulation_amplitude_meters: float = 6.0
var undulation_wavelength_meters: float = 900.0
var roughness_amplitude_meters: float = 0.8
var roughness_wavelength_meters: float = 60.0

var erg_wavelength_meters: float = 1800.0
var erg_threshold: float = 0.0
var erg_transition: float = 0.25
var erg_bias_direction: Vector2 = Vector2.RIGHT
var erg_bias_strength: float = 0.3
var erg_sheet_height_meters: float = 8.0
var dune_layers: Array[DuneLayer] = []

var massifs: Array[Massif] = []
var star_dunes: Array[StarDune] = []
var wadis: Array[Wadi] = []

var rock_slope_degrees: Vector2 = Vector2(32.0, 42.0)
var earth_patch_wavelength_meters: float = 260.0
var earth_patch_coverage: float = 0.3
var sand_sheet_wavelength_meters: float = 420.0
var sand_sheet_coverage: float = 0.35

var color_variation_wavelength_meters: float = 700.0
var color_variation_strength: float = 0.1
var erg_tint: Color = Color.WHITE
var reg_tint: Color = Color.WHITE
var wadi_tint: Color = Color.WHITE
var rock_tint: Color = Color.WHITE

var errors: PackedStringArray = PackedStringArray()


static func from_dictionary(data: Dictionary) -> SaharaSettings:
	var settings: SaharaSettings = SaharaSettings.new()
	settings._read(data)
	return settings


func half_extent() -> float:
	return map_size_meters * 0.5


func _read(data: Dictionary) -> void:
	world_seed = int(JsonData.read_number(data, "seed", errors, CONTEXT))
	map_size_meters = JsonData.read_number(data, "map_size_meters", errors, CONTEXT)
	vertex_spacing_meters = JsonData.read_number(data, "vertex_spacing_meters", errors, CONTEXT)
	region_size = int(JsonData.read_number(data, "region_size", errors, CONTEXT))
	max_walkable_twist_meters = _read_positive(data, "max_walkable_twist_meters", CONTEXT)
	edge_blend_meters = _read_positive(data, "edge_blend_meters", CONTEXT)
	walkable_slope_degrees = _read_positive(data, "walkable_slope_degrees", CONTEXT)
	if vertex_spacing_meters <= 0.0 or map_size_meters <= 0.0 or not is_zero_approx(fmod(map_size_meters, vertex_spacing_meters)):
		errors.append(CONTEXT + " : la taille de la carte doit être un multiple positif de l'espacement.")
	if region_size not in [64, 128, 256, 512, 1024, 2048]:
		errors.append(CONTEXT + " : region_size doit être une puissance de 2 entre 64 et 2048.")
	_read_base(JsonData.read_dictionary(data, "base", errors, CONTEXT))
	_read_erg(JsonData.read_dictionary(data, "erg", errors, CONTEXT))
	_read_massifs(data.get("massifs"))
	_read_star_dunes(data.get("star_dunes"))
	_read_wadis(data.get("wadis"))
	_read_surface(JsonData.read_dictionary(data, "surface", errors, CONTEXT))
	_read_color(JsonData.read_dictionary(data, "color", errors, CONTEXT))


func _read_base(base: Dictionary) -> void:
	var context: String = CONTEXT + " › base"
	base_height_meters = JsonData.read_number(base, "height_meters", errors, context)
	tilt_meters = JsonData.read_number(base, "tilt_meters", errors, context)
	tilt_direction = _read_direction(base, "tilt_direction", context)
	var undulation: Dictionary = JsonData.read_dictionary(base, "undulation", errors, context)
	undulation_amplitude_meters = JsonData.read_number(undulation, "amplitude_meters", errors, context + " › undulation")
	undulation_wavelength_meters = _read_positive(undulation, "wavelength_meters", context + " › undulation")
	var roughness: Dictionary = JsonData.read_dictionary(base, "roughness", errors, context)
	roughness_amplitude_meters = JsonData.read_number(roughness, "amplitude_meters", errors, context + " › roughness")
	roughness_wavelength_meters = _read_positive(roughness, "wavelength_meters", context + " › roughness")


func _read_erg(erg: Dictionary) -> void:
	var context: String = CONTEXT + " › erg"
	erg_wavelength_meters = _read_positive(erg, "coverage_wavelength_meters", context)
	erg_threshold = JsonData.read_number(erg, "threshold", errors, context)
	erg_transition = _read_positive(erg, "transition", context)
	erg_bias_direction = _read_direction(erg, "bias_direction", context)
	erg_bias_strength = JsonData.read_number(erg, "bias_strength", errors, context)
	erg_sheet_height_meters = JsonData.read_number(erg, "sheet_height_meters", errors, context)
	var layers: Variant = erg.get("dunes")
	if typeof(layers) != TYPE_ARRAY or (layers as Array).is_empty():
		errors.append(context + " : « dunes » doit être une liste non vide.")
		return
	for layer_data: Variant in layers:
		if typeof(layer_data) != TYPE_DICTIONARY:
			errors.append(context + " › dunes : chaque couche doit être un objet.")
			continue
		var layer: DuneLayer = DuneLayer.new()
		var layer_context: String = context + " › dunes"
		layer.wavelength_meters = _read_positive(layer_data, "wavelength_meters", layer_context)
		layer.amplitude_meters = JsonData.read_number(layer_data, "amplitude_meters", errors, layer_context)
		layer.wind = Vector2.from_angle(deg_to_rad(JsonData.read_number(layer_data, "wind_degrees", errors, layer_context)))
		layer.windward_fraction = JsonData.read_number(layer_data, "windward_fraction", errors, layer_context)
		layer.warp_meters = JsonData.read_number(layer_data, "warp_meters", errors, layer_context)
		layer.warp_wavelength_meters = _read_positive(layer_data, "warp_wavelength_meters", layer_context)
		layer.crest_variation = JsonData.read_number(layer_data, "crest_variation", errors, layer_context)
		if layer.windward_fraction <= 0.05 or layer.windward_fraction >= 0.95:
			errors.append(layer_context + " : windward_fraction doit être entre 0,05 et 0,95.")
		if layer.crest_variation < 0.0 or layer.crest_variation > 1.0:
			errors.append(layer_context + " : crest_variation doit être entre 0 et 1.")
		dune_layers.append(layer)


func _read_massifs(list: Variant) -> void:
	var context: String = CONTEXT + " › massifs"
	if typeof(list) != TYPE_ARRAY:
		errors.append(context + " : liste attendue.")
		return
	for item: Variant in list:
		if typeof(item) != TYPE_DICTIONARY:
			errors.append(context + " : chaque massif doit être un objet.")
			continue
		var massif: Massif = Massif.new()
		massif.name = JsonData.read_string(item, "name", errors, context)
		var item_context: String = context + " › " + massif.name
		massif.kind = JsonData.read_string(item, "kind", errors, item_context)
		if massif.kind not in ["mesa", "ridge", "inselberg"]:
			errors.append("%s : type « %s » inconnu (mesa, ridge, inselberg)." % [item_context, massif.kind])
		massif.center = _read_point(item, "center", item_context)
		massif.radii = _read_point(item, "radii", item_context)
		if massif.radii.x <= 0.0 or massif.radii.y <= 0.0:
			errors.append(item_context + " : les rayons doivent être positifs.")
		massif.angle_radians = deg_to_rad(JsonData.read_number(item, "angle_degrees", errors, item_context))
		massif.height_meters = _read_positive(item, "height_meters", item_context)
		massif.cliff_fraction = JsonData.read_number(item, "cliff_fraction", errors, item_context)
		massif.terraces = int(JsonData.read_number(item, "terraces", errors, item_context))
		massif.edge_noise = JsonData.read_number(item, "edge_noise", errors, item_context)
		massif.talus_meters = JsonData.read_number(item, "talus_meters", errors, item_context)
		if massif.cliff_fraction <= 0.0 or massif.cliff_fraction >= 1.0:
			errors.append(item_context + " : cliff_fraction doit être entre 0 et 1.")
		_check_inside(massif.center, maxf(massif.radii.x, massif.radii.y), item_context)
		massifs.append(massif)


func _read_star_dunes(list: Variant) -> void:
	var context: String = CONTEXT + " › star_dunes"
	if typeof(list) != TYPE_ARRAY:
		errors.append(context + " : liste attendue.")
		return
	for item: Variant in list:
		if typeof(item) != TYPE_DICTIONARY:
			errors.append(context + " : chaque dune doit être un objet.")
			continue
		var dune: StarDune = StarDune.new()
		dune.name = JsonData.read_string(item, "name", errors, context)
		var item_context: String = context + " › " + dune.name
		dune.center = _read_point(item, "center", item_context)
		dune.radius_meters = _read_positive(item, "radius_meters", item_context)
		dune.height_meters = _read_positive(item, "height_meters", item_context)
		dune.arms = int(JsonData.read_number(item, "arms", errors, item_context))
		dune.twist = JsonData.read_number(item, "twist", errors, item_context)
		if dune.arms < 3 or dune.arms > 6:
			errors.append(item_context + " : une dune étoilée a de 3 à 6 bras.")
		_check_inside(dune.center, dune.radius_meters, item_context)
		star_dunes.append(dune)


func _read_wadis(list: Variant) -> void:
	var context: String = CONTEXT + " › wadis"
	if typeof(list) != TYPE_ARRAY or (list as Array).is_empty():
		errors.append(context + " : liste non vide attendue.")
		return
	for item: Variant in list:
		if typeof(item) != TYPE_DICTIONARY:
			errors.append(context + " : chaque oued doit être un objet.")
			continue
		var wadi: Wadi = Wadi.new()
		wadi.name = JsonData.read_string(item, "name", errors, context)
		var item_context: String = context + " › " + wadi.name
		wadi.floor_half_width_meters = _read_positive(item, "floor_half_width_meters", item_context)
		wadi.bank_width_meters = _read_positive(item, "bank_width_meters", item_context)
		wadi.depth_meters = _read_positive(item, "depth_meters", item_context)
		var points: Variant = (item as Dictionary).get("points")
		if typeof(points) != TYPE_ARRAY or (points as Array).size() < 2:
			errors.append(item_context + " : au moins deux points attendus.")
			continue
		for point: Variant in points:
			if typeof(point) != TYPE_ARRAY or (point as Array).size() != 2:
				errors.append(item_context + " : chaque point est une paire [x, z].")
				continue
			var position: Vector2 = Vector2(float(point[0]), float(point[1]))
			if absf(position.x) > half_extent() or absf(position.y) > half_extent():
				errors.append(item_context + " : point hors de la carte " + str(position))
			wadi.points.append(position)
		wadis.append(wadi)


func _read_surface(surface: Dictionary) -> void:
	var context: String = CONTEXT + " › surface"
	rock_slope_degrees = _read_point(surface, "rock_slope_degrees", context)
	if rock_slope_degrees.x >= rock_slope_degrees.y:
		errors.append(context + " : rock_slope_degrees doit être croissant.")
	earth_patch_wavelength_meters = _read_positive(surface, "earth_patch_wavelength_meters", context)
	earth_patch_coverage = JsonData.read_number(surface, "earth_patch_coverage", errors, context)
	sand_sheet_wavelength_meters = _read_positive(surface, "sand_sheet_wavelength_meters", context)
	sand_sheet_coverage = JsonData.read_number(surface, "sand_sheet_coverage", errors, context)


func _read_color(color: Dictionary) -> void:
	var context: String = CONTEXT + " › color"
	color_variation_wavelength_meters = _read_positive(color, "variation_wavelength_meters", context)
	color_variation_strength = JsonData.read_number(color, "variation_strength", errors, context)
	erg_tint = JsonData.read_color(color, "erg_tint", errors, context)
	reg_tint = JsonData.read_color(color, "reg_tint", errors, context)
	wadi_tint = JsonData.read_color(color, "wadi_tint", errors, context)
	rock_tint = JsonData.read_color(color, "rock_tint", errors, context)


func _read_positive(data: Dictionary, key: String, context: String) -> float:
	var value: float = JsonData.read_number(data, key, errors, context)
	if value <= 0.0:
		errors.append("%s : « %s » doit être strictement positif." % [context, key])
		return 1.0
	return value


func _read_point(data: Dictionary, key: String, context: String) -> Vector2:
	var value: Variant = data.get(key)
	if typeof(value) != TYPE_ARRAY or (value as Array).size() != 2:
		errors.append("%s : « %s » doit être une paire de nombres." % [context, key])
		return Vector2.ZERO
	return Vector2(float(value[0]), float(value[1]))


func _read_direction(data: Dictionary, key: String, context: String) -> Vector2:
	var direction: Vector2 = _read_point(data, key, context)
	if direction.length_squared() < 0.0001:
		errors.append("%s : « %s » ne doit pas être nul." % [context, key])
		return Vector2.RIGHT
	return direction.normalized()


func _check_inside(center: Vector2, radius: float, context: String) -> void:
	if absf(center.x) + radius > half_extent() or absf(center.y) + radius > half_extent():
		errors.append(context + " : l'élément dépasse les bords de la carte.")
