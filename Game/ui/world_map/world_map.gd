class_name WorldMapOverlay
extends Control
## Carte du monde en surimpression : un plan parchemin inspiré des mappemondes médiévales,
## centré sur le désert courant et mis à jour depuis la position du joueur.

const MAP_SIZE := 302.0
const HALF_EXTENT := 2000.0
const MAP_MARGIN := 24.0
const PARCHMENT := Color("#ead8ad")
const PARCHMENT_DARK := Color("#b58c57")
const INK := Color("#3d2b1f")
const INK_SOFT := Color("#6f5135")
const WATER := Color("#668d91")
const WADI := Color("#9b7650")
const PLAYER := Color("#a9342c")

var _player: Node3D
var _data: Dictionary = {}
var _visible_map := true
var _font: Font
var _map_rect := Rect2()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	_map_rect = Rect2(MAP_MARGIN, MAP_MARGIN + 34.0, MAP_SIZE, MAP_SIZE)
	queue_redraw()


func setup(player: Node3D, data: Dictionary) -> void:
	_player = player
	_data = data
	queue_redraw()


func _process(_delta: float) -> void:
	if Input.is_key_pressed(KEY_M):
		# Le verrou évite de basculer plusieurs fois pendant l'appui.
		if not bool(get_meta("m_down", false)):
			_visible_map = not _visible_map
			set_meta("m_down", true)
			queue_redraw()
	else:
		set_meta("m_down", false)
	if _visible_map and _player != null:
		queue_redraw()


func _draw() -> void:
	if not _visible_map:
		return
	var panel := Rect2(MAP_MARGIN - 10.0, MAP_MARGIN - 10.0, MAP_SIZE + 20.0, MAP_SIZE + 86.0)
	# Double bordure, comme une carte montée sur bois et cuir.
	draw_style_box(_box(Color("#2b2119"), 0.92, 12.0, 2.0, Color("#8e6a43")), panel)
	draw_style_box(_box(Color("#d8b879"), 0.98, 9.0, 1.0, Color("#523a27")), panel.grow(-6.0))
	draw_style_box(_box(PARCHMENT, 1.0, 5.0, 1.0, PARCHMENT_DARK), _map_rect)

	_draw_header()
	_draw_map_surface()
	_draw_compass(_map_rect.position + Vector2(36.0, 39.0))
	_draw_player()
	_draw_footer()


func _draw_header() -> void:
	draw_string(
		_font,
		Vector2(MAP_MARGIN, 20.0),
		"MAPPAMONDE — MAGHREB",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		16,
		INK
	)
	draw_string(
		_font,
		Vector2(MAP_MARGIN + MAP_SIZE - 6.0, 20.0),
		"M",
		HORIZONTAL_ALIGNMENT_RIGHT,
		20,
		12,
		INK_SOFT
	)
	draw_line(Vector2(MAP_MARGIN, 28.0), Vector2(MAP_MARGIN + MAP_SIZE, 28.0), PARCHMENT_DARK, 1.0)


func _draw_map_surface() -> void:
	# Une trame légère évoque les fibres du parchemin sans charger la lisibilité.
	for i: int in range(1, 12):
		var y := _map_rect.position.y + float(i) * 24.0
		draw_line(
			Vector2(_map_rect.position.x + 3.0, y),
			Vector2(_map_rect.end.x - 3.0, y),
			Color(0.45, 0.32, 0.18, 0.06),
			1.0
		)
	for body: Variant in _data.get("water_bodies", []):
		if not body is Dictionary:
			continue
		var center := _pair_to_vec2(body.get("center", [0.0, 0.0]))
		var radius := float(body.get("radius_m", 20.0))
		var point := _world_to_map(center)
		var r := maxf(radius / (HALF_EXTENT * 2.0) * MAP_SIZE, 2.0)
		draw_circle(point, r + 2.0, Color(WATER, 0.16))
		draw_circle(point, r, Color(WATER, 0.82))
		draw_arc(point, r, 0.0, TAU, 32, Color("#385c61"), 1.0, true)

	for wadi: Variant in _data.get("wadis", []):
		if not wadi is Dictionary:
			continue
		var points := PackedVector2Array()
		for raw: Variant in wadi.get("points", []):
			points.append(_world_to_map(_pair_to_vec2(raw)))
		if points.size() >= 2:
			draw_polyline(points, Color(WADI, 0.8), 1.5, true)
			draw_polyline(points, Color("#d2ae78"), 0.5, true)

	# Échelle et limites : le joueur lit instantanément l'orientation du territoire.
	draw_rect(_map_rect.grow(-8.0), Color("#8b6844"), false, 1.0)
	draw_string(
		_font,
		_map_rect.position + Vector2(10.0, 18.0),
		"NORD",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		9,
		INK_SOFT
	)
	draw_string(
		_font,
		_map_rect.position + Vector2(10.0, MAP_SIZE - 10.0),
		"désert des Banu Hilal",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		9,
		INK_SOFT
	)


func _draw_player() -> void:
	if _player == null:
		return
	var p := _world_to_map(Vector2(_player.global_position.x, _player.global_position.z))
	# Halo et pointe rouge, lisibles même sur un oued ou une oasis.
	draw_circle(p, 8.0, Color(PLAYER, 0.16))
	var direction := Vector2(sin(_player.rotation.y), cos(_player.rotation.y))
	var tip := p + direction * 9.0
	var left := p + Vector2(-direction.y, direction.x) * 4.5 - direction * 5.0
	var right := p + Vector2(direction.y, -direction.x) * 4.5 - direction * 5.0
	draw_colored_polygon(PackedVector2Array([tip, left, right]), PLAYER)
	draw_circle(p, 2.5, Color("#f7e8bb"))


func _draw_compass(center: Vector2) -> void:
	draw_circle(center, 19.0, Color(0.92, 0.84, 0.65, 0.72))
	draw_arc(center, 19.0, 0.0, TAU, 24, PARCHMENT_DARK, 1.0, true)
	var north := PackedVector2Array(
		[center + Vector2(0.0, -15.0), center + Vector2(-4.0, 4.0), center + Vector2(4.0, 4.0)]
	)
	draw_colored_polygon(north, INK)
	draw_string(_font, center + Vector2(-4.0, -21.0), "N", HORIZONTAL_ALIGNMENT_LEFT, 8, 10, INK)


func _draw_footer() -> void:
	var base := Vector2(MAP_MARGIN, MAP_MARGIN + 34.0 + MAP_SIZE + 21.0)
	draw_circle(base + Vector2(6.0, 0.0), 4.0, PLAYER)
	draw_string(
		_font, base + Vector2(16.0, 4.0), "Votre position", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, INK
	)
	draw_line(base + Vector2(136.0, 0.0), base + Vector2(154.0, 0.0), WADI, 2.0)
	draw_string(_font, base + Vector2(162.0, 4.0), "Oued", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, INK)
	draw_circle(base + Vector2(236.0, 0.0), 4.0, WATER)
	draw_string(_font, base + Vector2(246.0, 4.0), "Eau", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, INK)
	draw_string(
		_font,
		Vector2(MAP_MARGIN, panel_bottom()),
		"M pour fermer la carte",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		10,
		INK_SOFT
	)


func panel_bottom() -> float:
	return MAP_MARGIN + MAP_SIZE + 75.0


func _world_to_map(world: Vector2) -> Vector2:
	var normalized := (world + Vector2(HALF_EXTENT, HALF_EXTENT)) / (HALF_EXTENT * 2.0)
	return _map_rect.position + Vector2(normalized.x, normalized.y) * MAP_SIZE


func _pair_to_vec2(raw: Variant) -> Vector2:
	if raw is Vector2:
		return raw
	if raw is Array and raw.size() >= 2:
		return Vector2(float(raw[0]), float(raw[1]))
	return Vector2.ZERO


func _box(
	color: Color, alpha: float, radius: float, border: float, border_color: Color
) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(color, alpha)
	box.border_color = border_color
	box.set_border_width_all(int(border))
	box.set_corner_radius_all(int(radius))
	return box
