class_name DesertHeightfield
extends RefCounted
## Champ de hauteurs du désert : dunes transversales au vent, grandes ondulations, plans d'eau et oueds (LandscapeFeatures).
##
## Pur calcul, sans nœud ni allocation : la même graine et les mêmes réglages donnent toujours les mêmes valeurs,
## quel que soit l'ordre ou le fil d'exécution des appels (les bruits ne sont que lus). Chaque requête est en O(1) :
## height_at = 3 lectures de bruit, normal_at = 4 hauteurs, surface_at = 4 hauteurs + 1 bruit.
## Les dunes sont allongées perpendiculairement au vent : le bruit est lu dans un repère tourné de l'angle du vent,
## étiré (grande longueur d'onde en travers, petite dans le sens du vent), puis plié en crêtes par |bruit|.
## La classification des surfaces dépend de la pente prise sur la même distance que le maillage des cellules :
## les sommets d'une cellule et surface_at() donnent donc exactement les mêmes poids.

const CONTEXT: String = "desert.json"
const DEFAULT_PATH: String = "res://data/desert/desert.json"
const SURFACE_SABLE: StringName = &"sable"
const SURFACE_PIERRE: StringName = &"pierre"
const SURFACE_TERRE: StringName = &"terre"
const SURFACE_GALETS: StringName = &"galets"
const SURFACE_EAU: StringName = &"eau"
const NO_CELL: Vector2i = Vector2i(-1, -1)

## Plans d'eau et oueds (index spatial lu dans desert.json), en lecture seule pour les autres systèmes.
var features: LandscapeFeatures = null
## Moitié du côté du désert, taille d'une cellule de streaming et nombre de cellules par côté.
var half_extent: float = 2000.0
var cell_size: float = 250.0
var cells_per_side: int = 16
## Distance de différence finie des normales et des pentes (égale au pas des sommets des cellules).
var normal_epsilon: float = 2.5

var _dunes: FastNoiseLite
var _macro: FastNoiseLite
var _rock: FastNoiseLite
var _water_min_depth: float = 0.03
var _wind_cos: float = 1.0
var _wind_sin: float = 0.0
var _inverse_along: float = 0.0
var _inverse_across: float = 0.0
var _base_height: float = 0.0
var _dune_amplitude: float = 0.0
var _dune_range: float = 1.0
var _ridge_exponent: float = 1.0
var _modulation: float = 0.0
var _macro_amplitude: float = 0.0
var _macro_range: float = 1.0
var _slope_start: float = 0.0
var _slope_full: float = 1.0
var _terre_margin: float = 1.0
var _rock_threshold: float = 0.0
var _rock_band: float = 1.0
var _city_enabled: bool = false
var _city_center: Vector2 = Vector2.ZERO
var _city_half_size: Vector2 = Vector2.ZERO
var _city_blend_width: float = 0.0
var _city_level: float = 0.0
var _road_start: Vector2 = Vector2.ZERO
var _road_direction: Vector2 = Vector2.ZERO
var _road_half_width: float = 0.0
var _road_length: float = 0.0
var _road_edge: float = 1.0
var _road_fade: float = 1.0
var _road_grade_blend: float = 1.0
var _road_end_height: float = 0.0


## Charge desert.json (réglages par défaut). Renvoie null si les données sont invalides.
static func load_default() -> DesertHeightfield:
	return from_data(JsonData.load_dictionary(DEFAULT_PATH))


## Construit le champ de hauteurs depuis le contenu de desert.json. Renvoie null si les données sont invalides.
static func from_data(data: Dictionary) -> DesertHeightfield:
	if data.is_empty():
		return null
	var field := DesertHeightfield.new()
	var terrain: Dictionary = JsonData.get_dictionary(data, "terrain", CONTEXT)
	var context: String = CONTEXT + " > terrain"
	field.half_extent = JsonData.get_float(terrain, "half_extent_m", context)
	field.cell_size = JsonData.get_float(terrain, "cell_size_m", context)
	field.cells_per_side = JsonData.get_int(terrain, "cells_per_side", context)
	field.normal_epsilon = JsonData.get_float(JsonData.get_dictionary(terrain, "cell", context), "vertex_spacing_m", context + " > cell")
	if (
		field.cell_size <= 0.0
		or field.normal_epsilon <= 0.0
		or field.cells_per_side <= 0
		or not is_equal_approx(field.cell_size * float(field.cells_per_side), field.half_extent * 2.0)
	):
		push_error("DesertHeightfield : taille du désert, cellules incohérents (%s)." % context)
		return null
	var seed_value: int = JsonData.get_int(terrain, "seed", context)
	field._base_height = JsonData.get_float(terrain, "base_height_m", context)
	if not field._setup_dunes(
		JsonData.get_dictionary(terrain, "dunes", context), seed_value, JsonData.get_float(terrain, "wind_direction_deg", context)
	):
		return null
	if not field._setup_macro(JsonData.get_dictionary(terrain, "macro", context), seed_value):
		return null
	if not field._setup_surfaces(JsonData.get_dictionary(terrain, "surfaces", context), seed_value):
		return null
	field.features = LandscapeFeatures.from_data(data, field.half_extent, field._terre_margin, field.base_relief_at)
	if field.features == null:
		return null
	return field


func _setup_dunes(config: Dictionary, seed_value: int, wind_degrees: float) -> bool:
	var context: String = CONTEXT + " > terrain > dunes"
	var along: float = JsonData.get_float(config, "wavelength_along_m", context)
	var across: float = JsonData.get_float(config, "wavelength_across_m", context)
	_dune_amplitude = JsonData.get_float(config, "amplitude_m", context)
	_dune_range = JsonData.get_float(config, "noise_range", context)
	_ridge_exponent = JsonData.get_float(config, "ridge_exponent", context)
	_modulation = JsonData.get_float(config, "modulation_amplitude", context)
	if (
		along <= 0.0
		or across <= 0.0
		or _dune_amplitude <= 0.0
		or _dune_range <= 0.0
		or _ridge_exponent <= 0.0
		or _modulation < 0.0
		or _modulation > 1.0
	):
		push_error("DesertHeightfield : réglages des dunes invalides (%s)." % context)
		return false
	_inverse_along = 1.0 / along
	_inverse_across = 1.0 / across
	_wind_cos = cos(deg_to_rad(wind_degrees))
	_wind_sin = sin(deg_to_rad(wind_degrees))
	_dunes = FastNoiseLite.new()
	_dunes.seed = seed_value
	_dunes.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_dunes.frequency = 1.0
	_dunes.fractal_type = FastNoiseLite.FRACTAL_FBM
	_dunes.fractal_octaves = JsonData.get_int(config, "octaves", context)
	_dunes.fractal_lacunarity = JsonData.get_float(config, "lacunarity", context)
	_dunes.fractal_gain = JsonData.get_float(config, "gain", context)
	# Les crêtes ne sont pas rectilignes : le repère est déformé par un bruit lent (exprimé en longueurs d'onde).
	_dunes.domain_warp_enabled = true
	_dunes.domain_warp_type = FastNoiseLite.DOMAIN_WARP_SIMPLEX_REDUCED
	_dunes.domain_warp_amplitude = JsonData.get_float(config, "warp_amplitude", context)
	_dunes.domain_warp_frequency = JsonData.get_float(config, "warp_frequency", context)
	_dunes.domain_warp_fractal_type = FastNoiseLite.DOMAIN_WARP_FRACTAL_NONE
	return true


func _setup_macro(config: Dictionary, seed_value: int) -> bool:
	var context: String = CONTEXT + " > terrain > macro"
	var wavelength: float = JsonData.get_float(config, "wavelength_m", context)
	_macro_amplitude = JsonData.get_float(config, "amplitude_m", context)
	_macro_range = JsonData.get_float(config, "noise_range", context)
	if wavelength <= 0.0 or _macro_amplitude < 0.0 or _macro_range <= 0.0:
		push_error("DesertHeightfield : réglages des grandes ondulations invalides (%s)." % context)
		return false
	_macro = FastNoiseLite.new()
	_macro.seed = seed_value + 101
	_macro.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_macro.frequency = 1.0 / wavelength
	_macro.fractal_type = FastNoiseLite.FRACTAL_FBM
	_macro.fractal_octaves = JsonData.get_int(config, "octaves", context)
	return true


func _setup_surfaces(config: Dictionary, seed_value: int) -> bool:
	var context: String = CONTEXT + " > terrain > surfaces"
	_slope_start = tan(deg_to_rad(JsonData.get_float(config, "slope_start_deg", context)))
	_slope_full = tan(deg_to_rad(JsonData.get_float(config, "slope_full_deg", context)))
	_terre_margin = JsonData.get_float(config, "terre_margin_m", context)
	_rock_threshold = JsonData.get_float(config, "rock_threshold", context)
	_rock_band = JsonData.get_float(config, "rock_band", context)
	_water_min_depth = JsonData.get_float(config, "water_min_depth_m", context)
	var rock_wavelength: float = JsonData.get_float(config, "rock_wavelength_m", context)
	if _slope_full <= _slope_start or _terre_margin <= 0.0 or _rock_band <= 0.0 or rock_wavelength <= 0.0 or _water_min_depth < 0.0:
		push_error("DesertHeightfield : seuils des surfaces incohérents (%s)." % context)
		return false
	_rock = FastNoiseLite.new()
	_rock.seed = seed_value + 202
	_rock.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_rock.frequency = 1.0 / rock_wavelength
	_rock.fractal_type = FastNoiseLite.FRACTAL_FBM
	_rock.fractal_octaves = JsonData.get_int(config, "rock_octaves", context)
	return true


## Raccord de Tunis (data/tunis/transition.json) : le relief est aplani au niveau de la ville sur son emprise,
## rejoint les dunes sur une bande de raccord, et une piste de terre part de la porte vers le désert.
## Renvoie faux (et signale l'erreur) si les données sont incomplètes ou si la ville sort du désert.
func configure_city_transition(config: Dictionary) -> bool:
	var context: String = "tunis/transition.json"
	if JsonData.get_int(config, "schema_version", context) != 1:
		push_error("%s : version de schéma inconnue." % context)
		return false
	var raw_center: Array = JsonData.get_array(config, "world_origin_xz_m", context)
	var terrain: Dictionary = JsonData.get_dictionary(config, "terrain", context)
	var road: Dictionary = JsonData.get_dictionary(config, "road", context)
	var layout: Dictionary = JsonData.load_dictionary(JsonData.get_string(config, "layout_path", context))
	var gate: Dictionary = JsonData.get_dictionary(layout, "gate", "medina_layout.json")
	var raw_gate: Array = JsonData.get_array(gate, "position", "medina_layout.json > gate")
	var raw_inward: Array = JsonData.get_array(gate, "inward", "medina_layout.json > gate")
	if raw_center.size() != 2 or raw_gate.size() != 2 or raw_inward.size() != 2:
		push_error("%s : origine de la ville ou porte du plan invalide." % context)
		return false
	var center := Vector2(float(raw_center[0]), float(raw_center[1]))
	var half_x: float = JsonData.get_float(terrain, "half_extent_x_m", context)
	var half_z: float = JsonData.get_float(terrain, "half_extent_z_m", context)
	var blend: float = JsonData.get_float(terrain, "blend_width_m", context)
	var road_half: float = JsonData.get_float(road, "half_width_m", context)
	var road_length: float = JsonData.get_float(road, "length_m", context)
	var road_edge: float = JsonData.get_float(road, "edge_m", context)
	var road_fade: float = JsonData.get_float(road, "fade_m", context)
	var road_grade_blend: float = JsonData.get_float(road, "grade_blend_m", context)
	if (
		half_x <= 0.0
		or half_z <= 0.0
		or blend <= 0.0
		or absf(center.x) + half_x + blend >= half_extent
		or absf(center.y) + half_z + blend >= half_extent
	):
		push_error("%s : emprise de Tunis invalide ou hors du désert." % context)
		return false
	if road_half <= 0.0 or road_length <= 0.0 or road_edge <= 0.0 or road_fade <= 0.0 or road_fade > road_length or road_grade_blend <= 0.0:
		push_error("%s : piste de la porte invalide." % context)
		return false
	_city_center = center
	_city_half_size = Vector2(half_x, half_z)
	_city_blend_width = blend
	_city_level = _raw_height_at(center.x, center.y)
	_road_start = center + Vector2(float(raw_gate[0]), float(raw_gate[1]))
	_road_direction = -Vector2(float(raw_inward[0]), float(raw_inward[1])).normalized()
	_road_half_width = road_half
	_road_length = road_length
	_road_edge = road_edge
	_road_fade = road_fade
	_road_grade_blend = road_grade_blend
	var road_end: Vector2 = _road_start + _road_direction * _road_length
	_road_end_height = _raw_height_at(road_end.x, road_end.y)
	_city_enabled = true
	return true


func city_ground_level() -> float:
	return _city_level


## Poids de la piste de terre (0 hors piste, 1 sur la piste), fondu sur le bord et à son extrémité. O(1).
func _road_weight(x: float, z: float) -> float:
	if not _city_enabled:
		return 0.0
	var offset := Vector2(x, z) - _road_start
	var along: float = offset.dot(_road_direction)
	if along < 0.0 or along > _road_length:
		return 0.0
	var across: float = absf(offset.cross(_road_direction))
	var side: float = 1.0 - smoothstep(_road_half_width, _road_half_width + _road_edge, across)
	return side * (1.0 - smoothstep(_road_length - _road_fade, _road_length, along))


func _city_weight(x: float, z: float) -> float:
	if not _city_enabled:
		return 0.0
	var outside: float = maxf(absf(x - _city_center.x) - _city_half_size.x, absf(z - _city_center.y) - _city_half_size.y)
	return 1.0 - smoothstep(0.0, _city_blend_width, maxf(outside, 0.0))


## Altitude du sol (mètres) à la position (x, z) du monde. O(1).
func height_at(x: float, z: float) -> float:
	var raw: float = _raw_height_at(x, z)
	var height: float = lerpf(raw, _city_level, _city_weight(x, z))
	if not _city_enabled:
		return height
	# Piste : pente régulière de la porte à son extrémité, taillée dans les dunes (bords adoucis sur grade_blend_m).
	var offset := Vector2(x, z) - _road_start
	var along: float = offset.dot(_road_direction)
	if along < 0.0 or along > _road_length:
		return height
	var across: float = absf(offset.cross(_road_direction))
	var side: float = 1.0 - smoothstep(_road_half_width, _road_half_width + _road_grade_blend, across)
	var end_fade: float = 1.0 - smoothstep(_road_length - _road_fade, _road_length, along)
	var graded: float = lerpf(_city_level, _road_end_height, along / _road_length)
	return lerpf(height, graded, side * end_fade)


func _raw_height_at(x: float, z: float) -> float:
	var along: float = (x * _wind_cos + z * _wind_sin) * _inverse_along
	var across: float = (z * _wind_cos - x * _wind_sin) * _inverse_across
	var ridge: float = pow(1.0 - clampf(absf(_dunes.get_noise_2d(along, across)) / _dune_range, 0.0, 1.0), _ridge_exponent)
	var macro: float = clampf(_macro.get_noise_2d(x, z) / _macro_range * 0.5 + 0.5, 0.0, 1.0)
	var height: float = _base_height + _macro_amplitude * macro + _dune_amplitude * ridge * (1.0 - _modulation + _modulation * macro)
	return features.carve(x, z, height)


## Hauteur du sol sans dunes (base et grandes ondulations) : sert à calculer le fond des oueds. O(1).
func base_relief_at(x: float, z: float) -> float:
	var macro: float = clampf(_macro.get_noise_2d(x, z) / _macro_range * 0.5 + 0.5, 0.0, 1.0)
	return _base_height + _macro_amplitude * macro


## Normale unitaire du sol à (x, z), par différences centrées sur normal_epsilon mètres. O(1).
func normal_at(x: float, z: float) -> Vector3:
	var dx: float = (height_at(x + normal_epsilon, z) - height_at(x - normal_epsilon, z)) / (2.0 * normal_epsilon)
	var dz: float = (height_at(x, z + normal_epsilon) - height_at(x, z - normal_epsilon)) / (2.0 * normal_epsilon)
	return Vector3(-dx, 1.0, -dz).normalized()


## Poids des surfaces à (x, z) : x = pierre (0 à 1), y = terre (0 à 1) ; le reste est du sable.
## slope_tangent : tangente de la pente au point, mesurée sur normal_epsilon mètres. O(1).
func surface_weights(x: float, z: float, slope_tangent: float) -> Vector2:
	var mix: Vector4 = surface_mix(x, z, slope_tangent)
	return Vector2(mix.x, mix.y)


## Poids complets des surfaces : x = pierre, y = terre, z = galets (lit des oueds), w = proximité du lit (0 loin, 1 au centre ;
## teinte du lit vu de loin). Les berges des oueds sont de terre, puis de pierre quand la pente est forte. O(1).
func surface_mix(x: float, z: float, slope_tangent: float) -> Vector4:
	var wadi: Vector3 = features.wadis.surface_mix(x, z)
	var rock_noise: float = _rock.get_noise_2d(x, z)
	var slope_term: float = smoothstep(_slope_start, _slope_full, slope_tangent)
	var terre: float = maxf(features.shore_weight(x, z, _terre_margin), wadi.y * (1.0 - slope_term))
	var pierre: float = maxf(slope_term, smoothstep(_rock_threshold, _rock_threshold + _rock_band, rock_noise))
	var city_weight: float = _city_weight(x, z)
	var settled: float = maxf(city_weight, _road_weight(x, z))
	return Vector4(pierre * (1.0 - terre) * (1.0 - settled), maxf(terre, settled), wadi.x * (1.0 - settled), wadi.z * (1.0 - settled))


## Tangente de la pente à (x, z) (mêmes différences centrées que normal_at).
func slope_tangent_at(x: float, z: float) -> float:
	var dx: float = (height_at(x + normal_epsilon, z) - height_at(x - normal_epsilon, z)) / (2.0 * normal_epsilon)
	var dz: float = (height_at(x, z + normal_epsilon) - height_at(x, z - normal_epsilon)) / (2.0 * normal_epsilon)
	return sqrt(dx * dx + dz * dz)


## Profondeur (m) de l'eau en (x, z) : hauteur de la surface du plan d'eau praticable à gué (oasis, lac, guelta)
## qui contient le point moins la hauteur du sol ; 0 hors de l'eau. O(1).
func water_depth_at(x: float, z: float) -> float:
	var surface: float = features.standing_water_height(x, z)
	if surface == LandscapeFeatures.NO_WATER:
		return 0.0
	return maxf(surface - height_at(x, z), 0.0)


## Surface du sol : « eau » sous l'eau peu profonde, sinon « sable », « pierre », « terre » ou « galets » (lit d'oued). O(1).
func surface_at(world_position: Vector3) -> StringName:
	if water_depth_at(world_position.x, world_position.z) > _water_min_depth:
		return SURFACE_EAU
	var mix: Vector4 = surface_mix(world_position.x, world_position.z, slope_tangent_at(world_position.x, world_position.z))
	if mix.z >= 0.5:
		return SURFACE_GALETS
	return surface_from_weights(Vector2(mix.x, mix.y))


## Surface dominante pour des poids (pierre, terre) : la terre et la pierre l'emportent à partir de 0,5.
static func surface_from_weights(weights: Vector2) -> StringName:
	if weights.y >= 0.5:
		return SURFACE_TERRE
	if weights.x >= 0.5:
		return SURFACE_PIERRE
	return SURFACE_SABLE


## Identifiant de la cellule de streaming qui contient (x, z), ou NO_CELL hors du désert.
func cell_at(x: float, z: float) -> Vector2i:
	var cell := Vector2i(floori((x + half_extent) / cell_size), floori((z + half_extent) / cell_size))
	if cell.x < 0 or cell.y < 0 or cell.x >= cells_per_side or cell.y >= cells_per_side:
		return NO_CELL
	return cell
