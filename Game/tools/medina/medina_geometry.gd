class_name MedinaGeometry
extends RefCounted
## Géométrie plane de la médina sur une grille compressée (coordonnées en centimètres entiers).
##
## L'espace libre est l'union des rectangles des voies et de la place. La grille compressée n'a pour
## lignes que les bords de ces rectangles et de l'intérieur de l'enceinte : quelques dizaines de lignes
## au lieu de millions de cellules, et toutes les opérations restent exactes (entiers). Les murs bâtis
## (« runs ») sont les frontières maximales entre cellules libres et bâties ; chaque extrémité de mur est
## classée (angle saillant, angle rentrant, rempart) pour que les façades se rejoignent sans trou ni
## chevauchement. La masse des îlots est ce qui reste une fois retirées les bandes des façades.

const ORIENT_X: int = 0
const ORIENT_Z: int = 1


class Run:
	extends RefCounted
	## Mur le long de x (frontière z = line, normale ±z) ou le long de z (frontière x = line, normale ±x).
	var orient: int = 0
	var line: int = 0
	var a: int = 0
	var b: int = 0
	## Direction vers l'espace libre.
	var normal: Vector2i = Vector2i.ZERO
	var convex_a: bool = false
	var convex_b: bool = false
	## Voie ou place bordée (« plaza » ou identifiant de voie) et index du tronçon.
	var zone: String = ""
	var zone_leg: int = -1

	func key() -> String:
		var side: String = "n" if normal == Vector2i(0, -1) else "s" if normal == Vector2i(0, 1) else "w" if normal.x < 0 else "e"
		var axis_name: String = "z" if orient == ORIENT_X else "x"
		var other: String = "x" if orient == ORIENT_X else "z"
		return "%s_%s%s_%s%s" % [side, axis_name, MedinaGeometry.signed_cm(line), other, MedinaGeometry.signed_cm(a)]

	func length() -> int:
		return b - a


var interior: Rect2i = Rect2i()
var rects: Array[Rect2i] = []
var zones: Array[Dictionary] = []
var xs: PackedInt32Array = PackedInt32Array()
var zs: PackedInt32Array = PackedInt32Array()
var runs: Array[Run] = []
var errors: PackedStringArray = PackedStringArray()
var _open: PackedByteArray = PackedByteArray()


## Entier signé lisible dans un identifiant snake_case : -120 → « m120 ».
static func signed_cm(value_cm: int) -> String:
	return ("m%d" % -value_cm) if value_cm < 0 else str(value_cm)


## « zone_list » : un dictionnaire {rect, zone, leg} par rectangle libre, la place en premier.
static func create(interior_rect: Rect2i, zone_list: Array[Dictionary]) -> MedinaGeometry:
	var result := MedinaGeometry.new()
	result.interior = interior_rect
	result.zones = zone_list
	for entry: Dictionary in zone_list:
		result.rects.append(entry["rect"] as Rect2i)
	result._build_grid()
	result._build_runs()
	return result


func is_open_point(point: Vector2i) -> bool:
	for rect: Rect2i in rects:
		if rect.has_point(point):
			return true
	return false


## Vrai si aucun point du segment aligné [from, to] ne se trouve dans l'espace libre.
func is_closed_segment(from: Vector2i, to: Vector2i) -> bool:
	var low := Vector2i(mini(from.x, to.x), mini(from.y, to.y))
	var high := Vector2i(maxi(from.x, to.x), maxi(from.y, to.y))
	var segment := Rect2i(low, high - low + Vector2i.ONE)
	for rect: Rect2i in rects:
		if rect.intersects(segment):
			return false
	return interior.encloses(segment)


## Vrai si le rectangle [rect] ne touche aucun espace libre et reste dans l'enceinte.
func is_closed_rect(rect: Rect2i) -> bool:
	for open_rect: Rect2i in rects:
		if open_rect.intersects(rect):
			return false
	return interior.encloses(rect)


func zone_at(point: Vector2i) -> Dictionary:
	for entry: Dictionary in zones:
		if (entry["rect"] as Rect2i).has_point(point):
			return entry
	return {}


## Rectangles de masse : cellules bâties de la grille raffinée par les bandes de façade, moins ces
## bandes, fusionnées en rectangles de même hauteur. « strip_tops » donne la hauteur de chaque bande
## (cm) ; une cellule de masse adjacente à des bandes prend la plus basse de leurs hauteurs moins
## « roof_below » ; les autres prennent la hauteur de leur parcelle (carré de « parcel » cm aligné sur
## l'origine), donnée par « inner_heights » (fonction de la parcelle) : les toits intérieurs varient
## de maison en maison au lieu de former une seule dalle par îlot.
func mass_rects(
	strips: Array[Rect2i], strip_tops: PackedInt32Array, roof_below: int, parcel: int, inner_heights: Callable
) -> Array[Dictionary]:
	var fine_x: PackedInt32Array = xs.duplicate()
	var fine_z: PackedInt32Array = zs.duplicate()
	for line: int in range(ceili(float(interior.position.x) / parcel) * parcel, interior.end.x, parcel):
		fine_x.append(line)
	for line: int in range(ceili(float(interior.position.y) / parcel) * parcel, interior.end.y, parcel):
		fine_z.append(line)
	for strip: Rect2i in strips:
		fine_x.append_array(PackedInt32Array([strip.position.x, strip.end.x]))
		fine_z.append_array(PackedInt32Array([strip.position.y, strip.end.y]))
	fine_x = _unique_sorted(fine_x, interior.position.x, interior.end.x)
	fine_z = _unique_sorted(fine_z, interior.position.y, interior.end.y)
	var nx: int = fine_x.size() - 1
	var nz: int = fine_z.size() - 1
	# -2 : libre ; -1 : masse ; >= 0 : index de bande.
	var kind := PackedInt32Array()
	kind.resize(nx * nz)
	for j: int in nz:
		for i: int in nx:
			var center := Vector2i((fine_x[i] + fine_x[i + 1]) / 2, (fine_z[j] + fine_z[j + 1]) / 2)
			var value: int = -2 if is_open_point(center) else -1
			for index: int in strips.size():
				if strips[index].has_point(center):
					if value != -1:
						errors.append("Bandes de façade superposées ou sur une voie en %s." % center)
					value = index
			kind[j * nx + i] = value
	var heights := PackedInt32Array()
	heights.resize(nx * nz)
	for j: int in nz:
		for i: int in nx:
			var index: int = j * nx + i
			if kind[index] != -1:
				heights[index] = -1
				continue
			var lowest: int = -1
			for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var ni: int = i + offset.x
				var nj: int = j + offset.y
				if ni < 0 or nj < 0 or ni >= nx or nj >= nz:
					continue
				var neighbor: int = kind[nj * nx + ni]
				if neighbor >= 0:
					var top: int = strip_tops[neighbor] - roof_below
					lowest = top if lowest < 0 else mini(lowest, top)
			var center := Vector2i((fine_x[i] + fine_x[i + 1]) / 2, (fine_z[j] + fine_z[j + 1]) / 2)
			var parcel_cell := Vector2i(floori(float(center.x) / parcel), floori(float(center.y) / parcel))
			heights[index] = lowest if lowest > 0 else int(inner_heights.call(parcel_cell))
	return _merge_cells(fine_x, fine_z, heights)


func _build_grid() -> void:
	var values := PackedInt32Array([interior.position.x, interior.end.x])
	var values_z := PackedInt32Array([interior.position.y, interior.end.y])
	for rect: Rect2i in rects:
		values.append_array(PackedInt32Array([rect.position.x, rect.end.x]))
		values_z.append_array(PackedInt32Array([rect.position.y, rect.end.y]))
	xs = _unique_sorted(values, interior.position.x, interior.end.x)
	zs = _unique_sorted(values_z, interior.position.y, interior.end.y)
	var nx: int = xs.size() - 1
	var nz: int = zs.size() - 1
	_open.resize(nx * nz)
	for j: int in nz:
		for i: int in nx:
			var center := Vector2i((xs[i] + xs[i + 1]) / 2, (zs[j] + zs[j + 1]) / 2)
			_open[j * nx + i] = 1 if is_open_point(center) else 0
	for j: int in range(1, nz):
		for i: int in range(1, nx):
			var a: bool = _is_open(i - 1, j - 1)
			var b: bool = _is_open(i, j - 1)
			var c: bool = _is_open(i - 1, j)
			var d: bool = _is_open(i, j)
			if a == d and b == c and a != b:
				errors.append("Contact en diagonale entre deux espaces libres en (%d, %d) cm." % [xs[i], zs[j]])


func _is_open(i: int, j: int) -> bool:
	var nx: int = xs.size() - 1
	var nz: int = zs.size() - 1
	if i < 0 or j < 0 or i >= nx or j >= nz:
		return false
	return _open[j * nx + i] == 1


func _inside(i: int, j: int) -> bool:
	return i >= 0 and j >= 0 and i < xs.size() - 1 and j < zs.size() - 1


func _build_runs() -> void:
	var nx: int = xs.size() - 1
	var nz: int = zs.size() - 1
	# Murs le long de z : frontière verticale x = xs[i] entre les colonnes i - 1 et i.
	for i: int in range(1, nx):
		for side: int in [-1, 1]:
			var j: int = 0
			while j < nz:
				if not _vertical_edge(i, j, side):
					j += 1
					continue
				var start: int = j
				while j < nz and _vertical_edge(i, j, side):
					j += 1
				var closed_column: int = i - 1 if side > 0 else i
				var run := Run.new()
				run.orient = ORIENT_Z
				run.line = xs[i]
				run.a = zs[start]
				run.b = zs[j]
				run.normal = Vector2i(side, 0)
				run.convex_a = _is_open(closed_column, start - 1)
				run.convex_b = _is_open(closed_column, j)
				_assign_zone(run)
				runs.append(run)
	# Murs le long de x : frontière horizontale z = zs[j] entre les lignes j - 1 et j.
	for j: int in range(1, nz):
		for side: int in [-1, 1]:
			var i: int = 0
			while i < nx:
				if not _horizontal_edge(i, j, side):
					i += 1
					continue
				var start: int = i
				while i < nx and _horizontal_edge(i, j, side):
					i += 1
				var closed_row: int = j - 1 if side > 0 else j
				var run := Run.new()
				run.orient = ORIENT_X
				run.line = zs[j]
				run.a = xs[start]
				run.b = xs[i]
				run.normal = Vector2i(0, side)
				run.convex_a = _is_open(start - 1, closed_row)
				run.convex_b = _is_open(i, closed_row)
				_assign_zone(run)
				runs.append(run)


## Arête verticale bâtie à gauche (side = +1, libre à droite) ou bâtie à droite (side = -1).
func _vertical_edge(i: int, j: int, side: int) -> bool:
	var left: bool = _is_open(i - 1, j)
	var right: bool = _is_open(i, j)
	return (not left and right) if side > 0 else (left and not right)


func _horizontal_edge(i: int, j: int, side: int) -> bool:
	var top: bool = _is_open(i, j - 1)
	var bottom: bool = _is_open(i, j)
	return (not top and bottom) if side > 0 else (top and not bottom)


func _assign_zone(run: Run) -> void:
	var middle: int = (run.a + run.b) / 2
	var probe: Vector2i = Vector2i(run.line, middle) if run.orient == ORIENT_Z else Vector2i(middle, run.line)
	probe += run.normal
	var entry: Dictionary = zone_at(probe)
	if entry.is_empty():
		errors.append("Mur sans voie bordée en %s." % probe)
		return
	run.zone = String(entry["zone"])
	run.zone_leg = int(entry["leg"])


## Fusion gloutonne (lignes puis colonnes) des cellules de même hauteur en rectangles maximaux.
func _merge_cells(fine_x: PackedInt32Array, fine_z: PackedInt32Array, heights: PackedInt32Array) -> Array[Dictionary]:
	var nx: int = fine_x.size() - 1
	var nz: int = fine_z.size() - 1
	var used := PackedByteArray()
	used.resize(nx * nz)
	var result: Array[Dictionary] = []
	for j: int in nz:
		for i: int in nx:
			var height: int = heights[j * nx + i]
			if height < 0 or used[j * nx + i] == 1:
				continue
			var i_end: int = i + 1
			while i_end < nx and heights[j * nx + i_end] == height and used[j * nx + i_end] == 0:
				i_end += 1
			var j_end: int = j + 1
			while j_end < nz:
				var row_ok: bool = true
				for k: int in range(i, i_end):
					if heights[j_end * nx + k] != height or used[j_end * nx + k] == 1:
						row_ok = false
						break
				if not row_ok:
					break
				j_end += 1
			for row: int in range(j, j_end):
				for column: int in range(i, i_end):
					used[row * nx + column] = 1
			var low := Vector2i(fine_x[i], fine_z[j])
			var high := Vector2i(fine_x[i_end], fine_z[j_end])
			result.append({"rect": Rect2i(low, high - low), "height": height})
	return result


static func _unique_sorted(values: PackedInt32Array, low: int, high: int) -> PackedInt32Array:
	var sorted: PackedInt32Array = values.duplicate()
	sorted.sort()
	var result := PackedInt32Array()
	for value: int in sorted:
		var clamped: int = clampi(value, low, high)
		if result.is_empty() or result[result.size() - 1] != clamped:
			result.append(clamped)
	return result
