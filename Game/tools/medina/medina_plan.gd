class_name MedinaPlan
extends RefCounted
## Plan topologique de la médina : voies (tronçons alignés sur les axes), place, porte, et leur graphe.
##
## Le plan est entièrement résolu en centimètres entiers à partir de la description, puis validé
## AVANT toute instanciation : tronçons trop courts ou mal enchaînés, croisement non déclaré entre deux
## voies, îlot trop mince entre deux voies voisines, voie qui sort de l'enceinte, impasse non déclarée,
## graphe non connexe, place trop petite pour faire le tour de la fontaine.
## Coordonnées : Vector2i(x, z) ; « north » = -Z.

const DIRECTIONS: Dictionary = {"north": Vector2i(0, -1), "south": Vector2i(0, 1), "east": Vector2i(1, 0), "west": Vector2i(-1, 0)}
const ROLE_MAIN: String = "main"
const GATE_ELEMENT: String = "gate"
const PLAZA_ELEMENT: String = "plaza"


class Leg:
	extends RefCounted
	var way_id: String = ""
	var index: int = 0
	var p0: Vector2i = Vector2i.ZERO
	var p1: Vector2i = Vector2i.ZERO
	var width: int = 0

	func is_x() -> bool:
		return p0.y == p1.y

	func length() -> int:
		return absi(p1.x - p0.x) + absi(p1.y - p0.y)

	func direction() -> Vector2i:
		return (p1 - p0).sign()

	## Rectangle libre : le segment épaissi d'une demi-largeur de chaque côté et à chaque extrémité.
	func rect() -> Rect2i:
		var half: int = width / 2
		var low := Vector2i(mini(p0.x, p1.x), mini(p0.y, p1.y))
		var high := Vector2i(maxi(p0.x, p1.x), maxi(p0.y, p1.y))
		return Rect2i(low - Vector2i(half, half), high - low + Vector2i(width, width))

	func point_at(distance: int) -> Vector2i:
		return p0 + direction() * distance


class Way:
	extends RefCounted
	var id: String = ""
	var role: String = ""
	var width: int = 0
	var points: Array[Vector2i] = []
	var legs: Array[Leg] = []
	var start: Dictionary = {}
	var end: Dictionary = {}
	var data: Dictionary = {}


var description: MedinaDescription
var enclosure: Rect2i = Rect2i()
var interior: Rect2i = Rect2i()
var rampart_thickness: int = 0
var gate_wall: String = ""
var gate_point: Vector2i = Vector2i.ZERO
var gate_inward: Vector2i = Vector2i.ZERO
var plaza: Rect2i = Rect2i()
var plaza_placed: bool = false
var ways: Array[Way] = []
var way_by_id: Dictionary = {}
var min_block: int = 0
var min_leg: int = 0


static func create(medina: MedinaDescription) -> MedinaPlan:
	var plan := MedinaPlan.new()
	plan.description = medina
	plan._build()
	return plan


func errors() -> PackedStringArray:
	return description.errors


func plaza_center() -> Vector2i:
	return plaza.position + plaza.size / 2


## Tous les rectangles libres (voies et place), découpés à l'intérieur de l'enceinte.
func open_rects() -> Array[Rect2i]:
	var rects: Array[Rect2i] = []
	for way: Way in ways:
		for leg: Leg in way.legs:
			var clipped: Rect2i = leg.rect().intersection(interior)
			if clipped.has_area():
				rects.append(clipped)
	if plaza_placed:
		rects.append(plaza)
	return rects


func way(id: String) -> Way:
	return way_by_id.get(id) as Way


## Graphe exporté (nœuds et arêtes) pour les tests de parcours et le plan généré.
func graph() -> Dictionary:
	var nodes: Array = [{"id": GATE_ELEMENT, "position": _point_m(gate_point)}, {"id": PLAZA_ELEMENT, "position": _point_m(plaza_center())}]
	var edges: Array = []
	for current: Way in ways:
		for index: int in current.points.size():
			nodes.append({"id": "%s_p%d" % [current.id, index], "position": _point_m(current.points[index])})
		for leg: Leg in current.legs:
			edges.append(
				{
					"from": "%s_p%d" % [current.id, leg.index],
					"to": "%s_p%d" % [current.id, leg.index + 1],
					"way": current.id,
					"role": current.role,
					"width_m": MedinaDescription.cm_to_m(current.width)
				}
			)
	return {"nodes": nodes, "edges": edges}


func _point_m(point: Vector2i) -> Array:
	return [MedinaDescription.cm_to_m(point.x), MedinaDescription.cm_to_m(point.y)]


func _build() -> void:
	min_block = description.parameter_cm("min_block_m")
	min_leg = description.parameter_cm("min_way_leg_m")
	_build_enclosure()
	_build_gate()
	var seen := {}
	for raw_way: Variant in description.ways():
		if typeof(raw_way) != TYPE_DICTIONARY:
			errors().append("medina.ways : chaque voie doit être un objet.")
			continue
		var built: Way = _build_way(raw_way, seen)
		if built == null:
			return
		ways.append(built)
		way_by_id[built.id] = built
		var plaza_data: Dictionary = description.section("plaza")
		if not plaza_placed and String(plaza_data.get("attach_to", "")) == built.id:
			_place_plaza(built, plaza_data)
		_validate_way_end(built)
	if not plaza_placed:
		errors().append("medina.plaza.attach_to doit nommer une voie qui finit sur la place.")
		return
	_validate_layout()


func _build_enclosure() -> void:
	var data: Dictionary = description.section("enclosure")
	var low := Vector2i(
		MedinaDescription.m_to_cm(float(data.get("min_x_m", 0.0))), MedinaDescription.m_to_cm(float(data.get("min_z_m", 0.0)))
	)
	var high := Vector2i(
		MedinaDescription.m_to_cm(float(data.get("max_x_m", 0.0))), MedinaDescription.m_to_cm(float(data.get("max_z_m", 0.0)))
	)
	enclosure = Rect2i(low, high - low)
	rampart_thickness = description.metric_cm("rampart_straight", "thickness_m")
	var half: int = rampart_thickness / 2
	interior = enclosure.grow(-half)
	if interior.size.x <= 0 or interior.size.y <= 0:
		errors().append("medina.enclosure est trop petite pour l'épaisseur du rempart.")


func _build_gate() -> void:
	var data: Dictionary = description.section("gate")
	gate_wall = String(data.get("wall", ""))
	if not DIRECTIONS.has(gate_wall):
		errors().append("medina.gate.wall doit valoir north, south, east ou west.")
		return
	var along: int = description.draw_cm(data.get("x_m"), "gate", "medina.gate.x_m")
	gate_inward = -(DIRECTIONS[gate_wall] as Vector2i)
	match gate_wall:
		"south":
			gate_point = Vector2i(along, enclosure.end.y)
		"north":
			gate_point = Vector2i(along, enclosure.position.y)
		"east":
			gate_point = Vector2i(enclosure.end.x, along)
		"west":
			gate_point = Vector2i(enclosure.position.x, along)
	var pillar: int = description.metric_cm("city_gate", "pillar_outer_m")
	var corner_arm: int = description.metric_cm("rampart_corner", "arm_m")
	var is_x_wall: bool = gate_wall == "south" or gate_wall == "north"
	var wall_low: int = enclosure.position.x if is_x_wall else enclosure.position.y
	var wall_high: int = enclosure.end.x if is_x_wall else enclosure.end.y
	if along - pillar < wall_low + corner_arm or along + pillar > wall_high - corner_arm:
		errors().append("medina.gate : la porte doit rester entre les deux tours d'angle du mur.")


func _build_way(data: Dictionary, seen: Dictionary) -> Way:
	var result := Way.new()
	result.data = data
	result.id = String(data.get("id", ""))
	var context: String = "medina.ways.%s" % result.id
	if not result.id.is_valid_identifier() or seen.has(result.id):
		errors().append("%s : identifiant absent, invalide ou en double." % context)
		return null
	seen[result.id] = true
	result.role = String(data.get("role", ""))
	var roles: Dictionary = description.section("roles")
	if not roles.has(result.role):
		errors().append("%s.role inconnu : %s." % [context, result.role])
		return null
	result.width = description.draw_cm((roles[result.role] as Dictionary).get("width_m"), "width:" + result.id, context + ".width")
	if result.width % 2 != 0:
		errors().append("%s : la largeur doit être un nombre pair de centimètres." % context)
	if result.width < description.parameter_cm("min_camera_width_m"):
		errors().append("%s : largeur %d cm sous la largeur minimale de la caméra." % [context, result.width])
	result.start = data.get("start", {}) if typeof(data.get("start")) == TYPE_DICTIONARY else {}
	result.end = data.get("end", {}) if typeof(data.get("end")) == TYPE_DICTIONARY else {}
	var start_point: Variant = _resolve_start(result, context)
	if start_point == null:
		return null
	result.points.append(start_point as Vector2i)
	var raw_legs: Variant = data.get("legs")
	if typeof(raw_legs) != TYPE_ARRAY or (raw_legs as Array).is_empty():
		errors().append("%s.legs doit être une liste non vide." % context)
		return null
	var legs_data: Array = raw_legs
	for index: int in legs_data.size():
		var leg_data: Variant = legs_data[index]
		if typeof(leg_data) != TYPE_DICTIONARY:
			errors().append("%s.legs[%d] doit être un objet." % [context, index])
			return null
		var leg: Leg = _resolve_leg(result, index, leg_data, "%s.legs[%d]" % [context, index])
		if leg == null:
			return null
		result.legs.append(leg)
		result.points.append(leg.p1)
	_validate_start_direction(result, context)
	return result


func _resolve_start(target: Way, context: String) -> Variant:
	var start: Dictionary = target.start
	if String(start.get("anchor", "")) == GATE_ELEMENT:
		return gate_point
	if start.has("plaza"):
		if not plaza_placed:
			errors().append("%s.start : la place n'est pas encore placée (voie déclarée trop tôt)." % context)
			return null
		return _plaza_edge_point(String(start["plaza"]), start.get("offset_m"), "start:" + target.id, context)
	if start.has("way"):
		var parent: Way = way(String(start["way"]))
		var leg_index: int = int(start.get("leg", -1))
		if parent == null or leg_index < 0 or leg_index >= parent.legs.size():
			errors().append("%s.start : voie ou tronçon parent inconnu." % context)
			return null
		var parent_leg: Leg = parent.legs[leg_index]
		var t: float = description.draw_fraction(start.get("t"), "start:" + target.id, context + ".start.t")
		var distance: int = _snap(roundi(float(parent_leg.length()) * t))
		return parent_leg.point_at(distance)
	errors().append("%s.start doit être la porte, la place ou une voie." % context)
	return null


func _resolve_leg(target: Way, index: int, data: Dictionary, context: String) -> Leg:
	var axis: String = String(data.get("axis", ""))
	if axis != "x" and axis != "z":
		errors().append("%s.axis doit valoir x ou z." % context)
		return null
	var origin: Vector2i = target.points[target.points.size() - 1]
	var current: int = origin.x if axis == "x" else origin.y
	var goal: int = current
	var stream: String = "leg:%s:%d" % [target.id, index]
	if data.has("to_m"):
		goal = description.draw_cm(data["to_m"], stream, context + ".to_m")
	elif data.has("by_m"):
		goal = current + description.draw_cm(data["by_m"], stream, context + ".by_m")
	elif data.has("to_plaza"):
		if not plaza_placed:
			errors().append("%s.to_plaza : la place n'est pas encore placée." % context)
			return null
		goal = _plaza_coordinate(String(data["to_plaza"]), axis, context)
		if data.has("offset_m"):
			goal += description.draw_cm(data["offset_m"], stream, context + ".offset_m")
	elif data.has("to_way"):
		var other: Way = way(String(data["to_way"]))
		var other_index: int = int(data.get("leg", -1))
		if other == null or other_index < 0 or other_index >= other.legs.size():
			errors().append("%s.to_way : voie ou tronçon inconnu (une voie ne rejoint qu'une voie déclarée avant elle)." % context)
			return null
		var other_leg: Leg = other.legs[other_index]
		if other_leg.is_x() == (axis == "x"):
			errors().append("%s.to_way : le tronçon rejoint doit être perpendiculaire." % context)
			return null
		goal = other_leg.p0.x if axis == "x" else other_leg.p0.y
	else:
		errors().append("%s doit porter to_m, by_m, to_plaza ou to_way." % context)
		return null
	var leg := Leg.new()
	leg.way_id = target.id
	leg.index = index
	leg.width = target.width
	leg.p0 = origin
	leg.p1 = Vector2i(goal, origin.y) if axis == "x" else Vector2i(origin.x, goal)
	if leg.length() < min_leg:
		errors().append("%s : tronçon de %d cm, sous le minimum de %d cm." % [context, leg.length(), min_leg])
		return null
	if index > 0 and target.legs[index - 1].is_x() == leg.is_x():
		errors().append("%s : deux tronçons successifs doivent changer d'axe." % context)
		return null
	return leg


func _validate_start_direction(target: Way, context: String) -> void:
	var first: Leg = target.legs[0]
	if target.start.has("side"):
		var side: String = String(target.start["side"])
		if not DIRECTIONS.has(side) or first.direction() != DIRECTIONS[side]:
			errors().append("%s.start.side : le premier tronçon doit partir vers « %s »." % [context, side])
	if target.start.has("way"):
		var parent_leg: Leg = way(String(target.start["way"])).legs[int(target.start["leg"])]
		if parent_leg.is_x() == first.is_x():
			errors().append("%s.start : le premier tronçon doit être perpendiculaire à la voie parente." % context)
	if String(target.start.get("anchor", "")) == GATE_ELEMENT and first.direction() != gate_inward:
		errors().append("%s.start : la voie de la porte doit entrer dans l'enceinte." % context)
	if target.start.has("plaza"):
		var side_name: String = String(target.start["plaza"])
		if DIRECTIONS.has(side_name) and first.direction() != DIRECTIONS[side_name]:
			errors().append("%s.start : la voie doit quitter la place vers « %s »." % [context, side_name])


func _place_plaza(attached: Way, data: Dictionary) -> void:
	var side: String = String(attached.end.get("plaza", ""))
	if not DIRECTIONS.has(side):
		errors().append("medina.plaza.attach_to : la voie %s doit finir sur un bord de la place." % attached.id)
		return
	var half := Vector2i(
		description.draw_cm(data.get("half_size_x_m"), "plaza:half_x", "medina.plaza.half_size_x_m"),
		description.draw_cm(data.get("half_size_z_m"), "plaza:half_z", "medina.plaza.half_size_z_m")
	)
	var offset: int = description.draw_cm(data.get("center_offset_m"), "plaza:offset", "medina.plaza.center_offset_m")
	var arrival: Vector2i = attached.points[attached.points.size() - 1]
	var inward: Vector2i = -(DIRECTIONS[side] as Vector2i)
	var along := Vector2i(absi(inward.y), absi(inward.x))
	var center: Vector2i = arrival + Vector2i(inward.x * half.x, inward.y * half.y) + along * offset
	plaza = Rect2i(center - half, half * 2)
	plaza_placed = true


func _plaza_coordinate(side: String, axis: String, context: String) -> int:
	var center: Vector2i = plaza_center()
	match side:
		"center":
			return center.x if axis == "x" else center.y
		"west", "east":
			if axis != "x":
				errors().append("%s : un bord est ou ouest se rejoint par un tronçon sur x." % context)
			return plaza.position.x if side == "west" else plaza.end.x
		"north", "south":
			if axis != "z":
				errors().append("%s : un bord nord ou sud se rejoint par un tronçon sur z." % context)
			return plaza.position.y if side == "north" else plaza.end.y
	errors().append("%s : bord de place inconnu : %s." % [context, side])
	return 0


func _plaza_edge_point(side: String, offset_spec: Variant, stream: String, context: String) -> Variant:
	if not DIRECTIONS.has(side):
		errors().append("%s : bord de place inconnu : %s." % [context, side])
		return null
	var center: Vector2i = plaza_center()
	var offset: int = 0
	if offset_spec != null:
		offset = description.draw_cm(offset_spec, stream, context + ".offset_m")
	match side:
		"north":
			return Vector2i(center.x + offset, plaza.position.y)
		"south":
			return Vector2i(center.x + offset, plaza.end.y)
		"west":
			return Vector2i(plaza.position.x, center.y + offset)
	return Vector2i(plaza.end.x, center.y + offset)


func _validate_way_end(target: Way) -> void:
	var context: String = "medina.ways.%s.end" % target.id
	var last: Vector2i = target.points[target.points.size() - 1]
	var half: int = target.width / 2
	if target.end.has("plaza"):
		var side: String = String(target.end["plaza"])
		if not plaza_placed or not DIRECTIONS.has(side):
			errors().append("%s : bord de place inconnu." % context)
			return
		var on_edge: bool = false
		match side:
			"north":
				on_edge = last.y == plaza.position.y and last.x - half >= plaza.position.x and last.x + half <= plaza.end.x
			"south":
				on_edge = last.y == plaza.end.y and last.x - half >= plaza.position.x and last.x + half <= plaza.end.x
			"west":
				on_edge = last.x == plaza.position.x and last.y - half >= plaza.position.y and last.y + half <= plaza.end.y
			"east":
				on_edge = last.x == plaza.end.x and last.y - half >= plaza.position.y and last.y + half <= plaza.end.y
		if not on_edge:
			errors().append("%s : la voie n'arrive pas sur le bord %s de la place." % [context, side])
		return
	if target.end.has("way"):
		var other: Way = way(String(target.end["way"]))
		var leg_index: int = int(target.end.get("leg", -1))
		if other == null or leg_index < 0 or leg_index >= other.legs.size():
			errors().append("%s : voie ou tronçon rejoint inconnu." % context)
			return
		var other_leg: Leg = other.legs[leg_index]
		var low: int = mini(other_leg.p0.y, other_leg.p1.y) if not other_leg.is_x() else mini(other_leg.p0.x, other_leg.p1.x)
		var high: int = maxi(other_leg.p0.y, other_leg.p1.y) if not other_leg.is_x() else maxi(other_leg.p0.x, other_leg.p1.x)
		var along: int = last.x if other_leg.is_x() else last.y
		var across: int = last.y if other_leg.is_x() else last.x
		var fixed: int = other_leg.p0.y if other_leg.is_x() else other_leg.p0.x
		if across != fixed or along - half < low + other.width / 2 or along + half > high - other.width / 2:
			errors().append("%s : la voie ne rejoint pas l'intérieur du tronçon %s[%d]." % [context, other.id, leg_index])
		return
	if bool(target.end.get("dead_end", false)):
		return
	errors().append("%s : une voie finit sur la place, sur une voie, ou est une impasse déclarée (dead_end)." % context)


func _validate_layout() -> void:
	_validate_connectivity()
	var legs: Array[Leg] = []
	for current: Way in ways:
		legs.append_array(current.legs)
	var allowed: Rect2i = interior.grow(-min_block)
	for leg: Leg in legs:
		var rect: Rect2i = _core_rect(leg)
		var touches_gate: bool = way(leg.way_id).start.get("anchor", "") == GATE_ELEMENT and leg.index == 0
		if touches_gate:
			rect = rect.intersection(interior)
		if not allowed.encloses(rect) and not touches_gate:
			errors().append("medina.ways.%s.legs[%d] passe à moins de min_block_m du rempart." % [leg.way_id, leg.index])
		var touches_plaza: bool = _leg_touches_plaza(leg)
		var separation: int = _separation(rect, plaza)
		if touches_plaza and separation != 0:
			errors().append("medina.ways.%s.legs[%d] devrait déboucher sur la place." % [leg.way_id, leg.index])
		elif not touches_plaza and separation < min_block:
			errors().append("medina.ways.%s.legs[%d] touche la place ou en est trop proche." % [leg.way_id, leg.index])
	for a: int in legs.size():
		for b: int in range(a + 1, legs.size()):
			if _legs_connected(legs[a], legs[b]):
				if _separation(legs[a].rect(), legs[b].rect()) >= 0:
					errors().append(
						"medina : %s[%d] et %s[%d] devraient se raccorder." % [legs[a].way_id, legs[a].index, legs[b].way_id, legs[b].index]
					)
				continue
			var separation: int = _separation(_core_rect(legs[a]), _core_rect(legs[b]))
			if separation < min_block:
				errors().append(
					(
						"medina : %s[%d] et %s[%d] se croisent sans carrefour déclaré ou laissent un îlot trop mince (%d cm)."
						% [legs[a].way_id, legs[a].index, legs[b].way_id, legs[b].index, separation]
					)
				)
	if not allowed.encloses(plaza):
		errors().append("medina.plaza passe à moins de min_block_m du rempart.")
	var fountain: int = description.metric_cm("plaza_fountain", "radius_m")
	var clearance: int = description.parameter_cm("fountain_clearance_m")
	if mini(plaza.size.x, plaza.size.y) / 2 - fountain < clearance:
		errors().append("medina.plaza : passage autour de la fontaine sous fountain_clearance_m.")


## Rectangle propre d'un tronçon, sans la partie qui déborde dans la voie parente ou dans la place :
## c'est lui qui borde les îlots et qui sert aux contrôles d'écartement.
func _core_rect(leg: Leg) -> Rect2i:
	var owner: Way = way(leg.way_id)
	var half: int = leg.width / 2
	var start_trim: int = -half
	var end_trim: int = -half
	if leg.index == 0:
		if owner.start.has("way"):
			start_trim = way(String(owner.start["way"])).width / 2
		elif owner.start.has("plaza"):
			start_trim = 0
	if leg.index == owner.legs.size() - 1:
		if owner.end.has("way"):
			end_trim = way(String(owner.end["way"])).width / 2
		elif owner.end.has("plaza"):
			end_trim = 0
	var direction: Vector2i = leg.direction()
	var a: Vector2i = leg.p0 + direction * start_trim
	var b: Vector2i = leg.p1 - direction * end_trim
	var side := Vector2i(absi(direction.y), absi(direction.x)) * half
	var low: Vector2i = Vector2i(mini(a.x, b.x), mini(a.y, b.y)) - side
	var high: Vector2i = Vector2i(maxi(a.x, b.x), maxi(a.y, b.y)) + side
	return Rect2i(low, high - low)


## Écart entre deux rectangles : négatif s'ils se chevauchent, nul s'ils se touchent.
func _separation(a: Rect2i, b: Rect2i) -> int:
	var gap_x: int = maxi(b.position.x - a.end.x, a.position.x - b.end.x)
	var gap_z: int = maxi(b.position.y - a.end.y, a.position.y - b.end.y)
	return maxi(gap_x, gap_z)


func _leg_touches_plaza(leg: Leg) -> bool:
	var owner: Way = way(leg.way_id)
	if leg.index == 0 and owner.start.has("plaza"):
		return true
	return leg.index == owner.legs.size() - 1 and owner.end.has("plaza")


func _legs_connected(a: Leg, b: Leg) -> bool:
	if a.way_id == b.way_id:
		return absi(a.index - b.index) == 1
	return _joins(a, b) or _joins(b, a)


## Vrai si le tronçon « child » est le premier ou le dernier d'une voie raccordée à « parent ».
func _joins(child: Leg, parent: Leg) -> bool:
	var owner: Way = way(child.way_id)
	if child.index == 0 and String(owner.start.get("way", "")) == parent.way_id and int(owner.start.get("leg", -1)) == parent.index:
		return true
	if child.index == owner.legs.size() - 1 and String(owner.end.get("way", "")) == parent.way_id:
		return int(owner.end.get("leg", -1)) == parent.index
	return false


func _validate_connectivity() -> void:
	var parents := {GATE_ELEMENT: GATE_ELEMENT, PLAZA_ELEMENT: PLAZA_ELEMENT}
	for current: Way in ways:
		parents[current.id] = current.id
	for current: Way in ways:
		for anchor: Dictionary in [current.start, current.end]:
			if String(anchor.get("anchor", "")) == GATE_ELEMENT:
				_union(parents, current.id, GATE_ELEMENT)
			elif anchor.has("plaza"):
				_union(parents, current.id, PLAZA_ELEMENT)
			elif anchor.has("way") and parents.has(String(anchor["way"])):
				_union(parents, current.id, String(anchor["way"]))
	var root: String = _find(parents, GATE_ELEMENT)
	for element: Variant in parents.keys():
		if _find(parents, String(element)) != root:
			errors().append("medina : « %s » n'est pas relié à la porte (graphe non connexe)." % element)
	var gate_ways: int = 0
	for current: Way in ways:
		if String(current.start.get("anchor", "")) == GATE_ELEMENT:
			gate_ways += 1
	if gate_ways != 1:
		errors().append("medina : exactement une voie doit partir de la porte (%d trouvée(s))." % gate_ways)


func _find(parents: Dictionary, element: String) -> String:
	var current: String = element
	while String(parents[current]) != current:
		current = String(parents[current])
	return current


func _union(parents: Dictionary, a: String, b: String) -> void:
	parents[_find(parents, a)] = _find(parents, b)


func _snap(value: int) -> int:
	var grid: int = description.grid_cm
	return roundi(float(value) / float(grid)) * grid
