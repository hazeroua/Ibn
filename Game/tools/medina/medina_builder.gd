class_name MedinaBuilder
extends RefCounted
## Instancie la médina à partir du plan validé : remparts et porte, façades continues le long de chaque
## mur, masse des îlots (toits-terrasses), arcs, passage couvert, portes (dont celles des emplacements
## réservés), parapets, fontaine et étals. Produit les instances au format du contrat MVP 4 et le plan
## généré (graphe, emplacements, accès à la terrasse, points de vue).
##
## Ordre : les murs (runs) reçoivent d'abord leur module (maison ou boutique) pour que les angles
## saillants soient raccordés à la profondeur réelle du module voisin ; arcs et passage sont placés
## avant les hauteurs de façades, qui sont relevées là où un arc s'appuie ; la masse vient en dernier,
## juste sous les façades qui la bordent.

const GENERATOR_TAG: String = "medina"
const LAYER_RAMPART: String = "rampart"
const LAYER_GATE: String = "gate"
const LAYER_FACADE: String = "facade"
const LAYER_BLOCK: String = "block"
const LAYER_ARCH: String = "arch"
const LAYER_PASSAGE: String = "passage"
const LAYER_DOOR: String = "door"
const LAYER_PARAPET: String = "parapet"
const LAYER_FOUNTAIN: String = "fountain"
const LAYER_PROP: String = "prop"
const LAYER_LANDMARK: String = "landmark"
const PREFAB_GATE: String = "city_gate"
const PREFAB_RAMPART: String = "rampart_straight"
const PREFAB_CORNER: String = "rampart_corner"
const PREFAB_ARCH: String = "medina_arch"
const PREFAB_PASSAGE: String = "covered_passage"
const PREFAB_DOOR: String = "wooden_door"
const PREFAB_PARAPET: String = "terrace_parapet"
const PREFAB_FOUNTAIN: String = "plaza_fountain"
const PREFAB_STALL: String = "market_stall"
const PREFAB_HOUSE: String = "facade_house"
const PREFAB_HOUSE_LOGGIA: String = "facade_house_loggia"
const PREFAB_SHOP: String = "facade_shop"
const PREFAB_MINARET: String = "mosque_minaret"
const SLOT_KINDS: Array[String] = ["house", "shop", "mosque"]
const PLAZA_ZONE: String = "plaza"
const SCALE_STEP: float = 0.0001


class Unit:
	extends RefCounted
	var run: MedinaGeometry.Run
	var run_index: int = 0
	var index: int = 0
	var u0: int = 0
	var u1: int = 0
	var prefab: String = ""
	var depth: int = 0
	var base_height: int = 0
	var scale_y: float = 1.0
	var top: int = 0
	var id: String = ""
	var reserved: String = ""
	var has_door: bool = false

	func width() -> int:
		return u1 - u0

	func middle() -> int:
		return (u0 + u1) / 2

	## Point (cm) sur la face avant, au milieu du module.
	func front_point() -> Vector2i:
		return Vector2i(run.line, middle()) if run.orient == MedinaGeometry.ORIENT_Z else Vector2i(middle(), run.line)

	func strip() -> Rect2i:
		var back: int = run.line - (run.normal.x + run.normal.y) * depth
		var low_across: int = mini(back, run.line)
		if run.orient == MedinaGeometry.ORIENT_Z:
			return Rect2i(Vector2i(low_across, u0), Vector2i(depth, width()))
		return Rect2i(Vector2i(u0, low_across), Vector2i(width(), depth))


var description: MedinaDescription
var plan: MedinaPlan
var geometry: MedinaGeometry
var catalog: Dictionary = {}
var city: Dictionary = {}
var instances: Array[Dictionary] = []
var layout: Dictionary = {}
var units: Array[Unit] = []
var spans: Array[Dictionary] = []
var _run_prefab: Dictionary = {}
var _run_reserved: Dictionary = {}
var _slot_points: Dictionary = {}
var _origin: Vector3 = Vector3.ZERO
var _cell_size: float = 1.0


static func create(medina: MedinaDescription, medina_plan: MedinaPlan, catalog_data: Dictionary, city_data: Dictionary) -> MedinaBuilder:
	var builder := MedinaBuilder.new()
	builder.description = medina
	builder.plan = medina_plan
	builder.city = city_data
	for raw_prefab: Variant in catalog_data.get("prefabs", []):
		var prefab: Dictionary = raw_prefab
		builder.catalog[String(prefab["id"])] = prefab
	var raw_origin: Array = city_data.get("origin", [0.0, 0.0, 0.0])
	builder._origin = Vector3(float(raw_origin[0]), float(raw_origin[1]), float(raw_origin[2]))
	builder._cell_size = float(city_data.get("cell_size_m", 1.0))
	builder._build()
	return builder


func errors() -> PackedStringArray:
	return description.errors


func _build() -> void:
	var zone_list: Array[Dictionary] = [{"rect": plan.plaza, "zone": PLAZA_ZONE, "leg": -1}]
	for way: MedinaPlan.Way in plan.ways:
		for leg: MedinaPlan.Leg in way.legs:
			var clipped: Rect2i = leg.rect().intersection(plan.interior)
			zone_list.append({"rect": clipped, "zone": way.id, "leg": leg.index})
	geometry = MedinaGeometry.create(plan.interior, zone_list)
	errors().append_array(geometry.errors)
	if not errors().is_empty():
		return
	_reserve_runs()
	_choose_run_prefabs()
	_build_units()
	_plan_spans()
	_assign_heights()
	if not errors().is_empty():
		return
	_emit_ramparts()
	_emit_gate()
	_emit_facades()
	_emit_spans()
	_emit_mass()
	_emit_fountain_and_stalls()
	_build_layout()


# --- Murs réservés (emplacements, terrasse) -------------------------------------------------------


func _reserve_runs() -> void:
	var slots: Dictionary = description.section("slots")
	for kind: String in SLOT_KINDS:
		var slot: Dictionary = slots.get(kind, {})
		var context: String = "medina.slots." + kind
		if slot.is_empty():
			errors().append("%s est requis." % context)
			continue
		var found: Array = _slot_run(kind, slot, context)
		if found.is_empty():
			errors().append("%s : aucun mur ne peut recevoir l'emplacement." % context)
			continue
		var run_index: int = found[0]
		if _run_reserved.has(run_index):
			errors().append("%s : le mur est déjà réservé par « %s »." % [context, _run_reserved[run_index]])
			continue
		_run_reserved[run_index] = kind
		_run_prefab[run_index] = String(slot.get("facade", ""))
		_slot_points[kind] = found[1]
	var terrace: Dictionary = description.section("terrace_access")
	var terrace_index: int = _longest_plaza_run(String(terrace.get("plaza_side", "")))
	if terrace_index < 0 or _run_reserved.has(terrace_index):
		errors().append("medina.terrace_access : aucun mur libre de ce côté de la place.")
		return
	_run_reserved[terrace_index] = "terrace"
	_run_prefab[terrace_index] = String(terrace.get("facade", ""))


## [index du mur, coordonnée le long du mur] de l'emplacement, ou [] s'il n'existe pas.
func _slot_run(kind: String, slot: Dictionary, context: String) -> Array:
	match String(slot.get("location", "")):
		"way":
			var way: MedinaPlan.Way = plan.way(String(slot.get("way", "")))
			var leg_index: int = int(slot.get("leg", -1))
			if way == null or leg_index < 0 or leg_index >= way.legs.size():
				errors().append("%s : voie ou tronçon inconnu." % context)
				return []
			var leg: MedinaPlan.Leg = way.legs[leg_index]
			var t: float = description.draw_fraction(slot.get("t"), "slot:" + kind, context + ".t")
			var along_point: Vector2i = leg.point_at(roundi(float(leg.length()) * t))
			var facing: Vector2i = -(MedinaPlan.DIRECTIONS.get(String(slot.get("side", "")), Vector2i.ZERO) as Vector2i)
			return _run_at(way.id, leg_index, facing, along_point)
		"plaza":
			var side: String = String(slot.get("side", ""))
			var facing_plaza: Vector2i = -(MedinaPlan.DIRECTIONS.get(side, Vector2i.ZERO) as Vector2i)
			return _run_at(PLAZA_ZONE, -1, facing_plaza, plan.plaza_center())
		"way_end":
			for way: MedinaPlan.Way in plan.ways:
				if String(way.end.get("slot", "")) != kind:
					continue
				var last: MedinaPlan.Leg = way.legs[way.legs.size() - 1]
				var direction: Vector2i = last.direction()
				return _run_at(way.id, last.index, -direction, last.p1)
			errors().append("%s : aucune impasse ne déclare cet emplacement." % context)
			return []
	errors().append("%s.location doit valoir way, plaza ou way_end." % context)
	return []


## Mur de la zone, tourné vers « facing », qui contient la projection de « point ».
func _run_at(zone: String, leg_index: int, facing: Vector2i, point: Vector2i) -> Array:
	for index: int in geometry.runs.size():
		var run: MedinaGeometry.Run = geometry.runs[index]
		if run.zone != zone or run.normal != facing or (leg_index >= 0 and run.zone_leg != leg_index):
			continue
		var along: int = point.y if run.orient == MedinaGeometry.ORIENT_Z else point.x
		if along > run.a and along < run.b:
			return [index, along]
	return []


func _longest_plaza_run(side: String) -> int:
	if not MedinaPlan.DIRECTIONS.has(side):
		return -1
	var facing: Vector2i = -(MedinaPlan.DIRECTIONS[side] as Vector2i)
	var best: int = -1
	var best_length: int = 0
	for index: int in geometry.runs.size():
		var run: MedinaGeometry.Run = geometry.runs[index]
		if run.zone == PLAZA_ZONE and run.normal == facing and not _run_reserved.has(index) and run.length() > best_length:
			best = index
			best_length = run.length()
	return best


# --- Modules de façade ----------------------------------------------------------------------------


func _choose_run_prefabs() -> void:
	var fraction: float = description.parameter_float("shop_facade_fraction")
	for index: int in geometry.runs.size():
		if _run_prefab.has(index):
			continue
		var run: MedinaGeometry.Run = geometry.runs[index]
		var prefab: String = PREFAB_HOUSE
		if run.zone == PLAZA_ZONE or plan.way(run.zone).role == MedinaPlan.ROLE_MAIN:
			if description.rng("run:" + run.key()).randf() < fraction:
				prefab = PREFAB_SHOP
		_run_prefab[index] = prefab
	for index: int in _run_prefab:
		if not catalog.has(_run_prefab[index]):
			errors().append("medina : module de façade inconnu du catalogue : %s." % _run_prefab[index])


func _prefab_depth(prefab: String) -> int:
	var footprint: Array = (catalog.get(prefab, {}) as Dictionary).get("footprint_m", [0.0, 0.0])
	return MedinaDescription.m_to_cm(float(footprint[1]))


func _prefab_width(prefab: String) -> int:
	var footprint: Array = (catalog.get(prefab, {}) as Dictionary).get("footprint_m", [0.0, 0.0])
	return MedinaDescription.m_to_cm(float(footprint[0]))


## Profondeur du mur le long de x qui couvre l'angle saillant à l'extrémité « at_b » d'un mur le long de z.
func _corner_depth(run: MedinaGeometry.Run, at_b: bool) -> int:
	var line: int = run.b if at_b else run.a
	var wanted_normal := Vector2i(0, 1 if at_b else -1)
	for index: int in geometry.runs.size():
		var other: MedinaGeometry.Run = geometry.runs[index]
		if other.orient != MedinaGeometry.ORIENT_X or other.line != line or other.normal != wanted_normal:
			continue
		var touching: bool = other.b == run.line if run.normal.x > 0 else other.a == run.line
		if touching:
			return _prefab_depth(String(_run_prefab[index]))
	errors().append("medina : angle saillant sans mur voisin en (%d, %d) cm." % [run.line, line])
	return 0


func _build_units() -> void:
	var scale_limits: Vector2 = description.parameter_pair("facade_scale_x_limits")
	for run_index: int in geometry.runs.size():
		var run: MedinaGeometry.Run = geometry.runs[run_index]
		var prefab: String = String(_run_prefab[run_index])
		var a: int = run.a
		var b: int = run.b
		if run.orient == MedinaGeometry.ORIENT_Z:
			if run.convex_a:
				a += _corner_depth(run, false)
			if run.convex_b:
				b -= _corner_depth(run, true)
		var length: int = b - a
		var unit_width: int = _prefab_width(prefab)
		if length <= 0 or unit_width <= 0:
			errors().append("medina : mur %s vide après raccord des angles." % run.key())
			continue
		var count: int = maxi(1, roundi(float(length) / float(unit_width)))
		while float(length) / float(count * unit_width) > scale_limits.y:
			count += 1
		if float(length) / float(count * unit_width) < scale_limits.x - MedinaDescription.FLOAT_EPSILON:
			errors().append("medina : mur %s trop court (%d cm) pour un module de façade." % [run.key(), length])
			continue
		for k: int in count:
			var unit := Unit.new()
			unit.run = run
			unit.run_index = run_index
			unit.index = k
			unit.u0 = a + (length * k) / count
			unit.u1 = a + (length * (k + 1)) / count
			unit.prefab = prefab
			unit.depth = _prefab_depth(prefab)
			unit.base_height = description.metric_cm(prefab, "height_m")
			unit.id = "facade_%s_%d" % [run.key(), k]
			units.append(unit)
	for kind: String in _slot_points:
		var unit: Unit = _unit_at(_slot_run_index(kind), int(_slot_points[kind]))
		if unit == null:
			errors().append("medina.slots.%s : l'emplacement tombe dans un raccord d'angle." % kind)
			continue
		unit.reserved = kind
		unit.has_door = true


func _slot_run_index(kind: String) -> int:
	for run_index: int in _run_reserved:
		if String(_run_reserved[run_index]) == kind:
			return run_index
	return -1


func _unit_at(run_index: int, along: int) -> Unit:
	for unit: Unit in units:
		if unit.run_index == run_index and along >= unit.u0 and along < unit.u1:
			return unit
	return null


# --- Arcs et passage couvert ----------------------------------------------------------------------


## Chaque « span » : voie, tronçon, prefab, intervalle le long du tronçon (cm) et hauteur à dépasser.
func _plan_spans() -> void:
	var clearance: int = description.parameter_cm("junction_clearance_m")
	for way: MedinaPlan.Way in plan.ways:
		var covered: Variant = way.data.get("covered")
		if typeof(covered) == TYPE_DICTIONARY:
			_plan_passage(way, covered, clearance)
	var spacing: int = description.parameter_cm("arch_spacing_m")
	var max_width: int = description.parameter_cm("arch_max_way_width_m")
	var arch_depth: int = _prefab_depth(PREFAB_ARCH)
	for way: MedinaPlan.Way in plan.ways:
		if way.role == MedinaPlan.ROLE_MAIN or way.width > max_width:
			continue
		for leg: MedinaPlan.Leg in way.legs:
			var count: int = leg.length() / spacing
			for k: int in count:
				var center: int = _snap(leg.length() * (2 * k + 1) / (2 * count))
				var low: int = center - arch_depth / 2
				var high: int = center + arch_depth / 2
				if (
					_span_conflicts(way.id, leg.index, low - clearance, high + clearance)
					or not _sides_closed(leg, low - clearance, high + clearance)
				):
					continue
				spans.append(
					{
						"way": way.id,
						"leg": leg.index,
						"prefab": PREFAB_ARCH,
						"low": low,
						"high": high,
						"top": description.metric_cm(PREFAB_ARCH, "height_m"),
						"id": "arch_%s_%d_%d" % [way.id, leg.index, k]
					}
				)


func _plan_passage(way: MedinaPlan.Way, covered: Dictionary, clearance: int) -> void:
	var context: String = "medina.ways.%s.covered" % way.id
	var leg_index: int = int(covered.get("leg", -1))
	if leg_index < 0 or leg_index >= way.legs.size():
		errors().append("%s.leg inconnu." % context)
		return
	var leg: MedinaPlan.Leg = way.legs[leg_index]
	var length: int = description.draw_cm(covered.get("length_m"), "covered:" + way.id, context + ".length_m")
	var candidates := PackedInt32Array()
	var position: int = length / 2 + clearance
	while position + length / 2 + clearance <= leg.length():
		if _sides_closed(leg, position - length / 2 - clearance, position + length / 2 + clearance):
			candidates.append(position)
		position += description.grid_cm
	if candidates.is_empty():
		errors().append("%s : aucun tronçon bâti des deux côtés sur %d cm." % [context, length])
		return
	var chosen: int = candidates[description.rng("covered_at:" + way.id).randi_range(0, candidates.size() - 1)]
	spans.append(
		{
			"way": way.id,
			"leg": leg_index,
			"prefab": PREFAB_PASSAGE,
			"low": chosen - length / 2,
			"high": chosen + length / 2,
			"top": description.metric_cm(PREFAB_PASSAGE, "height_m"),
			"id": "covered_passage_%s" % way.id
		}
	)


func _span_conflicts(way_id: String, leg_index: int, low: int, high: int) -> bool:
	for span: Dictionary in spans:
		if String(span["way"]) == way_id and int(span["leg"]) == leg_index and low < int(span["high"]) and high > int(span["low"]):
			return true
	return false


## Vrai si les deux côtés du tronçon sont bâtis entre les distances « low » et « high » de son départ.
func _sides_closed(leg: MedinaPlan.Leg, low: int, high: int) -> bool:
	if low < 0 or high > leg.length():
		return false
	var direction: Vector2i = leg.direction()
	var side := Vector2i(absi(direction.y), absi(direction.x)) * (leg.width / 2 + 1)
	var from: Vector2i = leg.point_at(low)
	var to: Vector2i = leg.point_at(high)
	return geometry.is_closed_segment(from + side, to + side) and geometry.is_closed_segment(from - side, to - side)


# --- Hauteurs ---------------------------------------------------------------------------------------


func _assign_heights() -> void:
	var height_spec: Variant = description.parameter("facade_height_scale")
	var step: float = description.parameter_float("facade_height_step")
	var roof_below: int = description.parameter_cm("roof_below_facade_m")
	var terrace_height: int = MedinaDescription.m_to_cm(float(description.section("terrace_access").get("height_m", 0.0)))
	for unit: Unit in units:
		var required: int = 0
		for span: Dictionary in spans:
			if _unit_borders_span(unit, span):
				required = maxi(required, int(span["top"]) + roof_below)
		if String(_run_reserved.get(unit.run_index, "")) == "terrace":
			unit.scale_y = float(terrace_height) / float(unit.base_height)
			if required > terrace_height:
				errors().append("medina.terrace_access : la façade basse borde un arc ou le passage couvert.")
		else:
			var minimum: float = float(required) / float(unit.base_height)
			unit.scale_y = description.draw_stepped(height_spec, step, minimum, description.rng("height:" + unit.id), unit.id)
		unit.top = roundi(float(unit.base_height) * unit.scale_y)


func _borders_any_span(unit: Unit) -> bool:
	for span: Dictionary in spans:
		if _unit_borders_span(unit, span):
			return true
	return false


func _unit_borders_span(unit: Unit, span: Dictionary) -> bool:
	if unit.run.zone != String(span["way"]) or unit.run.zone_leg != int(span["leg"]):
		return false
	var leg: MedinaPlan.Leg = plan.way(String(span["way"])).legs[int(span["leg"])]
	if (unit.run.orient == MedinaGeometry.ORIENT_X) != leg.is_x():
		return false
	var a: Vector2i = leg.point_at(int(span["low"]))
	var b: Vector2i = leg.point_at(int(span["high"]))
	var low: int = mini(a.x, b.x) if leg.is_x() else mini(a.y, b.y)
	var high: int = maxi(a.x, b.x) if leg.is_x() else maxi(a.y, b.y)
	return unit.u0 < high and unit.u1 > low


# --- Émission des instances -------------------------------------------------------------------------


func _add(
	id: String, prefab: String, position_cm: Vector3i, rotation_y: float, scale: Vector3, layer: String, extra: Dictionary = {}
) -> void:
	if not catalog.has(prefab):
		errors().append("medina : prefab inconnu du catalogue : %s." % prefab)
		return
	# Coordonnées en double précision (les Vector3 sont en simple précision) : 12,35 m reste 12.35.
	var position: Array = [
		MedinaDescription.cm_to_m(position_cm.x), MedinaDescription.cm_to_m(position_cm.y), MedinaDescription.cm_to_m(position_cm.z)
	]
	var cell: Vector2i = TunisDataValidator.cell_for_position(Vector3(position[0], position[1], position[2]), _origin, _cell_size)
	var properties := {"generator": GENERATOR_TAG}
	properties.merge(extra)
	instances.append(
		{
			"id": id,
			"prefab_id": prefab,
			"cell": [cell.x, cell.y],
			"position": position,
			"rotation_y": rotation_y,
			"scale": [_round_scale(scale.x), _round_scale(scale.y), _round_scale(scale.z)],
			"layer": layer,
			"properties": properties
		}
	)


## Échelle arrondie au dix-millième : valeur stable à l'écriture, écart inférieur à 0,1 mm par mètre.
static func _round_scale(value: float) -> float:
	return snappedf(value, SCALE_STEP)


## Rotation qui tourne la face avant (+Z local) vers « normal ».
static func facing_rotation(normal: Vector2i) -> float:
	if normal == Vector2i(1, 0):
		return PI / 2.0
	if normal == Vector2i(-1, 0):
		return -PI / 2.0
	if normal == Vector2i(0, -1):
		return PI
	return 0.0


func _emit_ramparts() -> void:
	var length: int = description.metric_cm(PREFAB_RAMPART, "length_m")
	var arm: int = description.metric_cm(PREFAB_CORNER, "arm_m")
	var pillar: int = description.metric_cm(PREFAB_GATE, "pillar_outer_m")
	var box: Rect2i = plan.enclosure
	var corners: Array = [
		["sw", Vector2i(box.position.x, box.end.y), 0.0],
		["se", Vector2i(box.end.x, box.end.y), PI / 2.0],
		["ne", Vector2i(box.end.x, box.position.y), PI],
		["nw", Vector2i(box.position.x, box.position.y), -PI / 2.0]
	]
	for corner: Array in corners:
		var point: Vector2i = corner[1]
		_add(
			"rampart_corner_" + String(corner[0]),
			PREFAB_CORNER,
			Vector3i(point.x, 0, point.y),
			float(corner[2]),
			Vector3.ONE,
			LAYER_RAMPART
		)
	var walls: Dictionary = {
		"south": [true, box.end.y, box.position.x, box.end.x],
		"north": [true, box.position.y, box.position.x, box.end.x],
		"west": [false, box.position.x, box.position.y, box.end.y],
		"east": [false, box.end.x, box.position.y, box.end.y]
	}
	for wall: String in ["south", "north", "west", "east"]:
		var spec: Array = walls[wall]
		var along_x: bool = spec[0]
		var line: int = spec[1]
		var pieces: Array[Vector2i] = []
		var low: int = int(spec[2]) + arm
		var high: int = int(spec[3]) - arm
		if wall == plan.gate_wall:
			var gate_along: int = plan.gate_point.x if along_x else plan.gate_point.y
			pieces.append(Vector2i(low, gate_along - pillar))
			pieces.append(Vector2i(gate_along + pillar, high))
		else:
			pieces.append(Vector2i(low, high))
		var number: int = 0
		for piece: Vector2i in pieces:
			var span: int = piece.y - piece.x
			if span <= 0:
				continue
			var count: int = ceili(float(span) / float(length))
			for k: int in count:
				var a: int = piece.x + (span * k) / count
				var b: int = piece.x + (span * (k + 1)) / count
				var middle: int = (a + b) / 2
				var position := Vector3i(middle, 0, line) if along_x else Vector3i(line, 0, middle)
				var scale := Vector3(float(b - a) / float(length), 1.0, 1.0)
				_add("rampart_%s_%d" % [wall, number], PREFAB_RAMPART, position, 0.0 if along_x else PI / 2.0, scale, LAYER_RAMPART)
				number += 1


func _emit_gate() -> void:
	var along_x: bool = plan.gate_wall == "south" or plan.gate_wall == "north"
	var point: Vector2i = plan.gate_point
	_add("city_gate", PREFAB_GATE, Vector3i(point.x, 0, point.y), 0.0 if along_x else PI / 2.0, Vector3.ONE, LAYER_GATE, {"role": "gate"})


func _emit_facades() -> void:
	var door_frequency: float = description.parameter_float("door_frequency")
	var parapet_frequency: float = description.parameter_float("parapet_frequency")
	var door_width: int = _prefab_width(PREFAB_DOOR)
	var parapet_length: int = _prefab_width(PREFAB_PARAPET)
	var parapet_depth: int = _prefab_depth(PREFAB_PARAPET)
	for unit: Unit in units:
		var run: MedinaGeometry.Run = unit.run
		var rotation: float = facing_rotation(run.normal)
		var inward: int = run.normal.x + run.normal.y
		var across: int = run.line - inward * (unit.depth / 2)
		var position: Vector3i = _unit_position(unit, across, 0)
		var extra := {"role": "facade"}
		var reserved: String = String(_run_reserved.get(unit.run_index, ""))
		if reserved == "terrace":
			extra["terrace_access"] = true
		var visual_prefab: String = unit.prefab
		if unit.prefab == PREFAB_HOUSE and unit.reserved.is_empty():
			var variant_rng: RandomNumberGenerator = description.rng("facade_variant:" + unit.id)
			if variant_rng.randf() < 0.34:
				visual_prefab = PREFAB_HOUSE_LOGGIA
		_add(
			unit.id,
			visual_prefab,
			position,
			rotation,
			Vector3(float(unit.width()) / float(_prefab_width(unit.prefab)), unit.scale_y, 1.0),
			LAYER_FACADE,
			extra
		)
		if unit.reserved == "mosque":
			var normal: Vector2i = run.normal
			var roof_point := Vector3i(
				position.x - normal.x * 200, unit.top,
				position.z - normal.y * 200
			)
			_add("mosque_minaret", PREFAB_MINARET, roof_point, rotation,
				Vector3.ONE, LAYER_LANDMARK, {"role": "landmark"})
		var generator: RandomNumberGenerator = description.rng("decor:" + unit.id)
		var wants_door: bool = generator.randf() < door_frequency
		var wants_parapet: bool = generator.randf() < parapet_frequency
		if not unit.has_door and wants_door and unit.prefab == PREFAB_HOUSE and reserved.is_empty() and not _borders_any_span(unit):
			unit.has_door = unit.width() >= door_width + 2 * description.parameter_cm("door_side_margin_m")
		if unit.has_door and not unit.reserved.is_empty() and _borders_any_span(unit):
			errors().append("medina.slots.%s : la porte réservée tombe sous un arc ou le passage couvert." % unit.reserved)
		if unit.has_door:
			var door_extra := {"role": "door"}
			if not unit.reserved.is_empty():
				door_extra["slot"] = unit.reserved
			_add(
				"door_%s_%d" % [run.key(), unit.index],
				PREFAB_DOOR,
				_unit_position(unit, run.line, 0),
				rotation,
				Vector3.ONE,
				LAYER_DOOR,
				door_extra
			)
		if wants_parapet and reserved != "terrace" and not unit.strip().intersects(_gate_rect()):
			var count: int = maxi(1, roundi(float(unit.width()) / float(parapet_length)))
			for p: int in count:
				var a: int = unit.u0 + (unit.width() * p) / count
				var b: int = unit.u0 + (unit.width() * (p + 1)) / count
				var middle: int = (a + b) / 2
				var parapet_across: int = run.line - inward * (parapet_depth / 2)
				var parapet_position := (
					Vector3i(parapet_across, unit.top, middle)
					if run.orient == MedinaGeometry.ORIENT_Z
					else Vector3i(middle, unit.top, parapet_across)
				)
				var scale := Vector3(float(b - a) / float(parapet_length), 1.0, 1.0)
				_add(
					"parapet_%s_%d_%d" % [run.key(), unit.index, p],
					PREFAB_PARAPET,
					parapet_position,
					rotation,
					scale,
					LAYER_PARAPET,
					{"role": "parapet"}
				)


## Emprise au sol de la porte monumentale (cm) : aucun décor de toit ne s'y pose.
func _gate_rect() -> Rect2i:
	var half_width: int = MedinaDescription.m_to_cm(float((catalog[PREFAB_GATE] as Dictionary)["footprint_m"][0])) / 2
	var half_depth: int = description.metric_cm(PREFAB_GATE, "depth_m") / 2
	var along_x: bool = plan.gate_wall == "south" or plan.gate_wall == "north"
	var half := Vector2i(half_width, half_depth) if along_x else Vector2i(half_depth, half_width)
	return Rect2i(plan.gate_point - half, half * 2)


func _unit_position(unit: Unit, across: int, height: int) -> Vector3i:
	if unit.run.orient == MedinaGeometry.ORIENT_Z:
		return Vector3i(across, height, unit.middle())
	return Vector3i(unit.middle(), height, across)


func _emit_spans() -> void:
	for span: Dictionary in spans:
		var way: MedinaPlan.Way = plan.way(String(span["way"]))
		var leg: MedinaPlan.Leg = way.legs[int(span["leg"])]
		var prefab: String = String(span["prefab"])
		var middle: Vector2i = leg.point_at((int(span["low"]) + int(span["high"])) / 2)
		var opening: float = description.metric(prefab, "opening_half_width_m")
		var scale_x: float = (float(way.width) / 2.0 / MedinaDescription.CM_PER_M) / opening
		var scale_z: float = 1.0
		var layer: String = LAYER_ARCH
		if prefab == PREFAB_PASSAGE:
			scale_z = float(int(span["high"]) - int(span["low"])) / float(description.metric_cm(PREFAB_PASSAGE, "roof_length_m"))
			layer = LAYER_PASSAGE
		# L'ouverture du module est le long de son X local : il faut qu'elle traverse la voie.
		var rotation: float = PI / 2.0 if leg.is_x() else 0.0
		_add(
			String(span["id"]),
			prefab,
			Vector3i(middle.x, 0, middle.y),
			rotation,
			Vector3(scale_x, 1.0, scale_z),
			layer,
			{"role": layer, "way": way.id}
		)


func _emit_mass() -> void:
	var strips: Array[Rect2i] = []
	var tops := PackedInt32Array()
	for unit: Unit in units:
		strips.append(unit.strip())
		tops.append(unit.top)
	var inner_spec: Variant = description.parameter("inner_block_height_m")
	var inner_cache := {}
	var inner := func(parcel: Vector2i) -> int:
		if not inner_cache.has(parcel):
			inner_cache[parcel] = description.draw_cm(inner_spec, "parcel:%d:%d" % [parcel.x, parcel.y], "inner_block_height_m")
		return int(inner_cache[parcel])
	var prefab: String = String(description.parameter_value("block_mass_prefab"))
	var length: int = description.metric_cm(prefab, "length_m")
	var thickness: int = description.metric_cm(prefab, "thickness_m")
	var height: int = description.metric_cm(prefab, "height_m")
	var rects: Array[Dictionary] = geometry.mass_rects(
		strips, tops, description.parameter_cm("roof_below_facade_m"), description.parameter_cm("inner_parcel_m"), inner
	)
	errors().append_array(geometry.errors)
	for entry: Dictionary in rects:
		var rect: Rect2i = entry["rect"]
		var top: int = int(entry["height"])
		var center: Vector2i = rect.position + rect.size / 2
		var long_x: bool = rect.size.x >= rect.size.y
		var along: int = rect.size.x if long_x else rect.size.y
		var across: int = rect.size.y if long_x else rect.size.x
		var scale := Vector3(float(along) / float(length), float(top) / float(height), float(across) / float(thickness))
		var id: String = "block_x%s_z%s" % [MedinaGeometry.signed_cm(rect.position.x), MedinaGeometry.signed_cm(rect.position.y)]
		_add(id, prefab, Vector3i(center.x, 0, center.y), 0.0 if long_x else PI / 2.0, scale, LAYER_BLOCK, {"role": "block"})


func _emit_fountain_and_stalls() -> void:
	var center: Vector2i = plan.plaza_center()
	_add("plaza_fountain", PREFAB_FOUNTAIN, Vector3i(center.x, 0, center.y), 0.0, Vector3.ONE, LAYER_FOUNTAIN, {"role": "fountain"})
	var wanted: int = description.draw_int(description.parameter("plaza_stalls"), "stalls", "plaza_stalls")
	var stall_width: int = description.metric_cm(PREFAB_STALL, "width_m")
	var stall_depth: int = description.metric_cm(PREFAB_STALL, "depth_m")
	var clearance: int = description.parameter_cm("stall_clearance_m")
	var fountain_reach: int = description.metric_cm(PREFAB_FOUNTAIN, "radius_m") + clearance
	var candidates: Array[Unit] = []
	for unit: Unit in units:
		if unit.run.zone == PLAZA_ZONE and not unit.has_door and String(_run_reserved.get(unit.run_index, "")) != "terrace":
			if unit.width() >= stall_width + 2 * description.parameter_cm("door_side_margin_m"):
				candidates.append(unit)
	var generator: RandomNumberGenerator = description.rng("stalls_order")
	for index: int in range(candidates.size() - 1, 0, -1):
		var swap: int = generator.randi_range(0, index)
		var held: Unit = candidates[index]
		candidates[index] = candidates[swap]
		candidates[swap] = held
	var placed: int = 0
	var taken: Array[Rect2i] = []
	for unit: Unit in candidates:
		if placed >= wanted:
			break
		var normal: Vector2i = unit.run.normal
		var front: Vector2i = unit.front_point() + normal * (stall_depth / 2)
		var half := (
			Vector2i(stall_width / 2, stall_depth / 2)
			if unit.run.orient == MedinaGeometry.ORIENT_X
			else Vector2i(stall_depth / 2, stall_width / 2)
		)
		var rect := Rect2i(front - half, half * 2)
		if not plan.plaza.encloses(rect) or _blocks_way_mouth(rect.grow(clearance)):
			continue
		var crowded: bool = false
		for other: Rect2i in taken:
			crowded = crowded or other.grow(clearance).intersects(rect)
		if crowded:
			continue
		var to_fountain: Vector2i = (rect.get_center() - center).abs() - half
		if maxi(to_fountain.x, to_fountain.y) < fountain_reach:
			continue
		taken.append(rect)
		_add(
			"stall_%s_%d" % [unit.run.key(), unit.index],
			PREFAB_STALL,
			Vector3i(front.x, 0, front.y),
			facing_rotation(normal),
			Vector3.ONE,
			LAYER_PROP,
			{"role": "stall"}
		)
		placed += 1
	if placed < wanted:
		errors().append("medina.plaza_stalls : %d étal(s) placé(s) sur %d demandés." % [placed, wanted])


func _blocks_way_mouth(rect: Rect2i) -> bool:
	for way: MedinaPlan.Way in plan.ways:
		for leg: MedinaPlan.Leg in way.legs:
			if leg.rect().intersects(rect):
				return true
	return false


func _snap(value: int) -> int:
	return roundi(float(value) / float(description.grid_cm)) * description.grid_cm


# --- Plan généré ------------------------------------------------------------------------------------


func _build_layout() -> void:
	var m := func(point: Vector2i) -> Array: return [MedinaDescription.cm_to_m(point.x), MedinaDescription.cm_to_m(point.y)]
	var rect_m := func(rect: Rect2i) -> Array:
		return [
			MedinaDescription.cm_to_m(rect.position.x),
			MedinaDescription.cm_to_m(rect.position.y),
			MedinaDescription.cm_to_m(rect.end.x),
			MedinaDescription.cm_to_m(rect.end.y)
		]
	var ways: Array = []
	var narrowest: MedinaPlan.Way = null
	for way: MedinaPlan.Way in plan.ways:
		var points: Array = []
		for point: Vector2i in way.points:
			points.append(m.call(point))
		ways.append({"id": way.id, "role": way.role, "width_m": MedinaDescription.cm_to_m(way.width), "points": points})
		if narrowest == null or way.width < narrowest.width:
			narrowest = way
	var open: Array = []
	for rect: Rect2i in plan.open_rects():
		open.append(rect_m.call(rect))
	var slots: Array = []
	var slot_data: Dictionary = description.section("slots")
	for unit: Unit in units:
		if unit.reserved.is_empty():
			continue
		var footprint: Array = (slot_data[unit.reserved] as Dictionary).get("footprint_m", [0.0, 0.0])
		var footprint_rect: Rect2i = _footprint(
			unit, MedinaDescription.m_to_cm(float(footprint[0])), MedinaDescription.m_to_cm(float(footprint[1]))
		)
		if not geometry.is_closed_rect(footprint_rect):
			errors().append("medina.slots.%s : l'emprise réservée déborde sur une voie ou hors de l'enceinte." % unit.reserved)
		slots.append(
			{
				"kind": unit.reserved,
				"facade_id": unit.id,
				"door_id": "door_%s_%d" % [unit.run.key(), unit.index],
				"door_position": m.call(unit.front_point()),
				"facing": [unit.run.normal.x, unit.run.normal.y],
				"footprint": rect_m.call(footprint_rect)
			}
		)
	layout = {
		"schema_version": MedinaDescription.SCHEMA_VERSION,
		"generator": GENERATOR_TAG,
		"enclosure": rect_m.call(plan.enclosure),
		"interior": rect_m.call(plan.interior),
		"gate":
		{
			"position": m.call(plan.gate_point),
			"inward": [plan.gate_inward.x, plan.gate_inward.y],
			"opening_half_width_m": description.metric(PREFAB_GATE, "opening_half_width_m")
		},
		"plaza":
		{
			"rect": rect_m.call(plan.plaza),
			"fountain": m.call(plan.plaza_center()),
			"fountain_radius_m": description.metric(PREFAB_FOUNTAIN, "radius_m")
		},
		"ways": ways,
		"graph": plan.graph(),
		"open_rects": open,
		"slots": slots,
		"terrace_access": _terrace_layout(m),
		"narrowest_way": {"id": narrowest.id, "width_m": MedinaDescription.cm_to_m(narrowest.width)},
		"spans": _spans_layout(m)
	}


## Emprise réservée derrière la porte d'un module : largeur le long du mur, profondeur vers l'intérieur.
func _footprint(unit: Unit, width: int, depth: int) -> Rect2i:
	var inward: int = unit.run.normal.x + unit.run.normal.y
	var back: int = unit.run.line - inward * depth
	var low_across: int = mini(back, unit.run.line)
	var low_along: int = unit.middle() - width / 2
	if unit.run.orient == MedinaGeometry.ORIENT_Z:
		return Rect2i(Vector2i(low_across, low_along), Vector2i(depth, width))
	return Rect2i(Vector2i(low_along, low_across), Vector2i(width, depth))


func _terrace_layout(m: Callable) -> Dictionary:
	for unit: Unit in units:
		if String(_run_reserved.get(unit.run_index, "")) != "terrace":
			continue
		var front: Vector2i = unit.front_point()
		var base: Array = m.call(front + unit.run.normal * 100)
		var roof: Array = m.call(front - unit.run.normal * (unit.depth + 100))
		return {
			"facade_id": unit.id,
			"base": [base[0], 0.0, base[1]],
			"roof": [roof[0], MedinaDescription.cm_to_m(unit.top - description.parameter_cm("roof_below_facade_m")), roof[1]],
			"parapet_top_m": MedinaDescription.cm_to_m(unit.top)
		}
	return {}


func _spans_layout(m: Callable) -> Array:
	var result: Array = []
	for span: Dictionary in spans:
		var leg: MedinaPlan.Leg = plan.way(String(span["way"])).legs[int(span["leg"])]
		result.append(
			{
				"id": span["id"],
				"prefab": span["prefab"],
				"from": m.call(leg.point_at(int(span["low"]))),
				"to": m.call(leg.point_at(int(span["high"]))),
				"clear_height_m": description.metric(String(span["prefab"]), "clear_height_m")
			}
		)
	return result
