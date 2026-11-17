class_name WorldMapOverlay
extends Control
## Médaillon de navigation : les lieux et oueds proviennent du monde, la vue suit le voyageur.

const RADIUS: float = 116.0
const VIEW_RADIUS_M: float = 520.0
const INK := Color("#3b352b")
const PAPER := Color("#d9c39a")
const WATER := Color("#57878a")
const RIVER := Color("#9d704b")
const MARK := Color("#9e3d32")

var _player: Node3D
var _data: Dictionary = {}
var _visible_map: bool = true
var _center: Vector2
var _font: Font


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font


func setup(player: Node3D, data: Dictionary) -> void:
	_player = player
	_data = data
	queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_M:
		_visible_map = not _visible_map
		queue_redraw()


func _process(_delta: float) -> void:
	if _visible_map and _player != null:
		queue_redraw()


func _draw() -> void:
	if not _visible_map or _player == null:
		return
	_center = Vector2(size.x - RADIUS - 32.0, size.y - RADIUS - 55.0)
	var position := Vector2(_player.global_position.x, _player.global_position.z)
	draw_circle(_center + Vector2(2, 5), RADIUS + 10.0, Color(0.08, 0.07, 0.05, 0.38))
	draw_circle(_center, RADIUS + 9.0, INK)
	draw_circle(_center, RADIUS + 5.0, Color("#ad8655"))
	draw_circle(_center, RADIUS, PAPER)
	for ring: int in 3:
		draw_arc(_center + Vector2(28, 30), float(28 + ring * 32), PI * 1.12, PI * 1.95, 32, Color(0.33, 0.27, 0.20, 0.10), 1.0, true)
	_draw_wadis(position)
	_draw_water(position)
	_draw_player()
	draw_arc(_center, RADIUS - 2.0, 0.0, TAU, 96, Color("#6a4b32"), 2.0, true)
	for angle: float in [0.0, PI * 0.5, PI, PI * 1.5]:
		var direction := Vector2(cos(angle), sin(angle))
		draw_line(_center + direction * (RADIUS - 7.0), _center + direction * (RADIUS + 4.0), INK, 2.0)
	draw_string(_font, _center + Vector2(-4, -RADIUS - 15), "N", HORIZONTAL_ALIGNMENT_LEFT, 12, 12, Color("#f1dfb8"))
	draw_string(_font, Vector2(_center.x - RADIUS, size.y - 24), _place_name(position), HORIZONTAL_ALIGNMENT_LEFT, RADIUS * 2.0, 15, Color("#f0dfb8"))


func _draw_wadis(position: Vector2) -> void:
	for raw_wadi: Variant in _data.get("wadis", []):
		if not raw_wadi is Dictionary:
			continue
		var previous := Vector2.INF
		for raw: Variant in raw_wadi.get("points", []):
			var point: Vector2 = _pair(raw)
			if previous != Vector2.INF:
				if Rect2(position - Vector2.ONE * VIEW_RADIUS_M * 1.2, Vector2.ONE * VIEW_RADIUS_M * 2.4).intersects(Rect2(previous, point - previous).abs()):
					for sample: int in 25:
						var a := _world_to_map(previous.lerp(point, float(sample) / 25.0), position)
						var b := _world_to_map(previous.lerp(point, float(sample + 1) / 25.0), position)
						if a.distance_to(_center) < RADIUS - 4.0 and b.distance_to(_center) < RADIUS - 4.0:
							draw_line(a, b, RIVER, 2.0, true)
			previous = point


func _draw_water(position: Vector2) -> void:
	for raw_body: Variant in _data.get("water_bodies", []):
		if not raw_body is Dictionary:
			continue
		var body := raw_body as Dictionary
		var center := _world_to_map(_pair(body.get("center", [])), position)
		var radius: float = float(body.get("radius_m", 0.0)) * RADIUS / VIEW_RADIUS_M
		if center.distance_to(_center) + radius < RADIUS - 3.0:
			draw_circle(center, radius, Color(WATER, 0.76))
			draw_arc(center, radius + 2.0, 0.0, TAU, 40, Color(WATER, 0.65), 1.0, true)


func _draw_player() -> void:
	var direction := Vector2(-sin(_player.global_rotation.y), -cos(_player.global_rotation.y))
	draw_circle(_center, 12.0, Color(MARK, 0.18))
	draw_colored_polygon(PackedVector2Array([_center + direction * 11.0, _center - direction * 5.0 + direction.orthogonal() * 5.0, _center - direction * 5.0 - direction.orthogonal() * 5.0]), MARK)
	draw_circle(_center, 2.3, Color("#fff1cb"))


func _world_to_map(point: Vector2, position: Vector2) -> Vector2:
	return _center + (point - position) * (RADIUS / VIEW_RADIUS_M)


func _place_name(position: Vector2) -> String:
	for raw_body: Variant in _data.get("water_bodies", []):
		if raw_body is Dictionary:
			var body := raw_body as Dictionary
			if position.distance_to(_pair(body.get("center", []))) < float(body.get("radius_m", 0.0)) + 220.0:
				return str(body.get("id", "Oasis")).replace("_", " ").capitalize()
	return "Les terres du désert"


func _pair(raw: Variant) -> Vector2:
	if raw is Array and raw.size() >= 2:
		return Vector2(float(raw[0]), float(raw[1]))
	return Vector2.ZERO
