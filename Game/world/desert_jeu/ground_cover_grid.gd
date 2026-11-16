class_name GroundCoverGrid
extends RefCounted
## Grille de recherche des touffes (alfa, drinn) d'une cellule du désert, pour les sons de pas.
##
## Construite une seule fois, sur le fil de travail du streaming, à partir des positions déjà connues des
## instances (aucune requête physique) : tri par comptage sur une grille régulière (cases de cell_m mètres),
## puis tableau plat des positions rangées case par case. La recherche visite au plus 3 × 3 cases (rayon
## inférieur à une case) : coût borné par la densité maximale d'une case, sans aucune allocation.
##
## Pires cas : cellule la plus dense (max_instances des espèces de la grille) : construction en O(instances +
## cases) ; recherche au sprint (un pas toutes les 0,3 s) : au plus 9 cases, soit quelques dizaines de
## comparaisons, car l'écart minimal entre deux touffes borne le contenu d'une case.

var _origin_x: float = 0.0
var _origin_z: float = 0.0
var _cell_m: float = 1.0
var _inverse_cell: float = 1.0
var _side: int = 0
var _starts: PackedInt32Array = PackedInt32Array()
## Positions rangées case par case : x puis z de chaque touffe.
var _positions: PackedFloat32Array = PackedFloat32Array()
var _count: int = 0


## Construit la grille d'une cellule carrée (coin origin_x/origin_z, côté size_m) depuis des transformées de
## MultiMesh (12 réels par instance, coordonnées du monde ; la translation est aux rangs 3 et 11).
static func build(origin_x: float, origin_z: float, size_m: float, cell_m: float, sources: Array[PackedFloat32Array]) -> GroundCoverGrid:
	var grid := GroundCoverGrid.new()
	grid._origin_x = origin_x
	grid._origin_z = origin_z
	grid._cell_m = cell_m
	grid._inverse_cell = 1.0 / cell_m
	grid._side = maxi(ceili(size_m / cell_m), 1)
	var cells: int = grid._side * grid._side
	var total: int = 0
	for source: PackedFloat32Array in sources:
		total += source.size() / DesertFoliageInstance.FLOATS_PER_INSTANCE
	grid._count = total
	var starts := PackedInt32Array()
	starts.resize(cells + 1)
	var owner_of := PackedInt32Array()
	owner_of.resize(total)
	var slot: int = 0
	for source: PackedFloat32Array in sources:
		var n: int = source.size() / DesertFoliageInstance.FLOATS_PER_INSTANCE
		for i: int in n:
			var k: int = i * DesertFoliageInstance.FLOATS_PER_INSTANCE
			var index: int = grid._cell_index(source[k + 3], source[k + 11])
			owner_of[slot] = index
			starts[index + 1] += 1
			slot += 1
	for c: int in cells:
		starts[c + 1] += starts[c]
	var fill := starts.duplicate()
	var positions := PackedFloat32Array()
	positions.resize(total * 2)
	slot = 0
	for source: PackedFloat32Array in sources:
		var n2: int = source.size() / DesertFoliageInstance.FLOATS_PER_INSTANCE
		for i: int in n2:
			var k2: int = i * DesertFoliageInstance.FLOATS_PER_INSTANCE
			var target: int = fill[owner_of[slot]]
			fill[owner_of[slot]] = target + 1
			positions[target * 2] = source[k2 + 3]
			positions[target * 2 + 1] = source[k2 + 11]
			slot += 1
	grid._starts = starts
	grid._positions = positions
	return grid


## Nombre de touffes de la grille.
func get_count() -> int:
	return _count


## Carré de la distance à la touffe la plus proche de (x, z) si elle est à moins de radius mètres ; -1.0 sinon.
## Le rayon doit être inférieur à la taille d'une case. Aucune allocation.
func nearest_distance_squared(x: float, z: float, radius: float) -> float:
	if _count == 0:
		return -1.0
	var first_x: int = clampi(floori((x - radius - _origin_x) * _inverse_cell), 0, _side - 1)
	var last_x: int = clampi(floori((x + radius - _origin_x) * _inverse_cell), 0, _side - 1)
	var first_z: int = clampi(floori((z - radius - _origin_z) * _inverse_cell), 0, _side - 1)
	var last_z: int = clampi(floori((z + radius - _origin_z) * _inverse_cell), 0, _side - 1)
	var best: float = radius * radius
	var found: bool = false
	for cz: int in range(first_z, last_z + 1):
		for cx: int in range(first_x, last_x + 1):
			var cell: int = cz * _side + cx
			for p: int in range(_starts[cell], _starts[cell + 1]):
				var dx: float = _positions[p * 2] - x
				var dz: float = _positions[p * 2 + 1] - z
				var d2: float = dx * dx + dz * dz
				if d2 <= best:
					best = d2
					found = true
	return best if found else -1.0


func _cell_index(x: float, z: float) -> int:
	var cx: int = clampi(floori((x - _origin_x) * _inverse_cell), 0, _side - 1)
	var cz: int = clampi(floori((z - _origin_z) * _inverse_cell), 0, _side - 1)
	return cz * _side + cx
