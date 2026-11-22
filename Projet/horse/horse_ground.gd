class_name HorseGround
extends RefCounted
## Relief et sols lus par le cheval (prudence, chemin du sifflet, empreintes, sons de sabots) et par les
## sons de pas : hauteur, normale et surface du terrain Terrain3D. Remplace la heightfield de la première
## version du jeu (même interface : half_extent, height_at, normal_at, surface_at, water_depth_at).
##
## Lectures directes des cartes de Terrain3D (aucune requête physique, aucune allocation), sûres depuis le fil de
## travail qui construit la grille du sifflet : elles ne font que lire des images qui ne changent plus en jeu.

## Surface sonore de chaque sol du Sahara (indices de SaharaSurface.GROUND_NAMES : sand, earth, gravel, rock).
const SURFACES: Array[StringName] = [&"sable", &"terre", &"galets", &"pierre"]
## Au-delà de ce mélange, la surface d'appoint (overlay) l'emporte sur la surface de base.
const OVERLAY_THRESHOLD: float = 0.5

## Demi-côté de la carte (m) : la carte va de -half_extent à +half_extent en x et en z.
var half_extent: float = 0.0
var _data: Terrain3DData
var _base_height: float = 0.0


func _init(terrain: Terrain3D, map_half_extent: float, base_height: float) -> void:
	_data = terrain.data
	half_extent = map_half_extent
	_base_height = base_height


## Hauteur du sol ; hors carte (ou dans un trou), le sol plat à l'altitude de base qui prolonge l'horizon.
func height_at(x: float, z: float) -> float:
	var height: float = _data.get_height(Vector3(x, 0.0, z))
	return _base_height if is_nan(height) else height


func normal_at(x: float, z: float) -> Vector3:
	var normal: Vector3 = _data.get_normal(Vector3(x, 0.0, z))
	return Vector3.UP if not normal.is_finite() or normal.is_zero_approx() else normal


## Surface sonore sous un point (sable, terre, galets, pierre), d'après la carte de contrôle de Terrain3D.
func surface_at(world_position: Vector3) -> StringName:
	var ground: int = _data.get_control_base_id(world_position)
	if _data.get_control_blend(world_position) > OVERLAY_THRESHOLD:
		ground = _data.get_control_overlay_id(world_position)
	return SURFACES[ground] if ground >= 0 and ground < SURFACES.size() else SURFACES[0]


## Profondeur d'eau stagnante. Le Sahara n'en a pas : 0 partout. Une carte avec de l'eau (oasis, #67) fournira
## la sienne ici ; le chemin du sifflet évite déjà toute case plus profonde que call > max_wade_depth_m.
func water_depth_at(_x: float, _z: float) -> float:
	return 0.0
