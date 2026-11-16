class_name GroundCoverQuery
extends RefCounted
## Interrogation du couvert du sol par le système de pas (Footsteps) : trouve la cellule chargée sous le pied
## puis demande à sa grille (GroundCoverGrid, posée en métadonnée par DesertCellProvider) la touffe la plus
## proche. O(1), aucune requête physique, aucune allocation (un pas ne coûte que la lecture d'une case).

const GRID_META: StringName = &"ground_cover"

var _streamer: WorldStreamer


func _init(streamer: WorldStreamer) -> void:
	_streamer = streamer


## Carré de la distance à la touffe la plus proche à moins de radius mètres de (x, z) ; -1.0 s'il n'y en a pas
## (ou si la cellule n'est pas chargée).
func nearest_cover_distance_squared(x: float, z: float, radius: float) -> float:
	var cell: Vector2i = _streamer.world_to_cell(Vector3(x, 0.0, z))
	var node: Node3D = _streamer.get_cell_node(cell)
	if node == null or not node.has_meta(GRID_META):
		return -1.0
	var grid: GroundCoverGrid = node.get_meta(GRID_META) as GroundCoverGrid
	return -1.0 if grid == null else grid.nearest_distance_squared(x, z, radius)
