class_name TimePanel
extends CanvasLayer
## Panneau de temps (touche F2) : heure, vitesse du temps, saison et force du vent.
## Il parle à DayNight, Seasons et Wind uniquement par leurs méthodes publiques, retrouvées par chemin de nœud.
## Les réglages et les textes viennent de res://data/time_panel/time_panel.json.

signal opened
signal closed

const SETTINGS_PATH: String = "res://data/time_panel/time_panel.json"
const PANEL_WIDTH: float = 420.0
const MARGIN: float = 24.0

var _settings: Dictionary = {}
var _action: StringName = &""
var _day_night: Node = null
var _seasons: Node = null
var _wind: Node = null
var _game_input: Node = null

var _panel: PanelContainer = null
var _time_slider: HSlider = null
var _time_label: Label = null
var _wind_slider: HSlider = null
var _wind_label: Label = null
var _speed_buttons: Array[Button] = []
var _speed_values: Array[float] = []
var _season_buttons: Array[Button] = []
var _season_ids: Array[StringName] = []
var _shown_minute: int = -1
var _mouse_capture_before: bool = false
var _open: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	_settings = JsonData.load_dictionary(SETTINGS_PATH)
	if _settings.is_empty():
		return
	_declare_action()
	_find_services()
	_build_interface()
	_connect_services()
	_set_open(false)


## Ouvre ou ferme le panneau.
func toggle() -> void:
	_set_open(not _open)


func is_open() -> bool:
	return _open


func get_action() -> StringName:
	return _action


func _unhandled_input(event: InputEvent) -> void:
	if _action == &"":
		return
	if event.is_action_pressed(_action):
		toggle()
		get_viewport().set_input_as_handled()
	elif _open and event.is_action_pressed(&"ui_cancel"):
		_set_open(false)
		get_viewport().set_input_as_handled()


## Déclare l'action si le catalogue d'entrées ne la connaît pas encore.
func _declare_action() -> void:
	_action = StringName(String(_settings["action"]))
	if InputMap.has_action(_action):
		return
	InputMap.add_action(_action)
	var key := InputEventKey.new()
	key.physical_keycode = OS.find_keycode_from_string(String(_settings["key"]))
	InputMap.action_add_event(_action, key)
	var pad := InputEventJoypadButton.new()
	pad.button_index = int(_settings["joy_button"]) as JoyButton
	InputMap.action_add_event(_action, pad)


func _find_services() -> void:
	var paths: Dictionary = _settings["services"]
	_day_night = get_node_or_null(NodePath(String(paths["day_night"])))
	_seasons = get_node_or_null(NodePath(String(paths["seasons"])))
	_wind = get_node_or_null(NodePath(String(paths["wind"])))
	_game_input = get_node_or_null(NodePath(String(paths["input"])))


func _connect_services() -> void:
	if _day_night != null and _day_night.has_signal(&"time_changed"):
		_day_night.connect(&"time_changed", _on_time_changed)
	if _seasons != null and _seasons.has_signal(&"season_changed"):
		_seasons.connect(&"season_changed", _on_season_changed)


func _build_interface() -> void:
	var texts: Dictionary = _settings["texts"]
	_panel = PanelContainer.new()
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.offset_left = -PANEL_WIDTH - MARGIN
	_panel.offset_right = -MARGIN
	_panel.offset_top = MARGIN
	add_child(_panel)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	var title := Label.new()
	title.text = String(texts["title"])
	title.add_theme_font_size_override("font_size", 22)
	column.add_child(title)

	_time_label = Label.new()
	column.add_child(_time_label)
	_time_slider = _make_slider(0.0, 24.0, float(_settings["time_step_hours"]))
	_time_slider.value_changed.connect(_on_time_slider_changed)
	column.add_child(_time_slider)

	column.add_child(_make_caption(String(texts["speed"])))
	var speed_row := HFlowContainer.new()
	column.add_child(speed_row)
	var speeds: Array = _settings["speeds"]
	for entry: Dictionary in speeds:
		var speed: float = float(entry["value"])
		var button := _make_toggle(String(entry["label"]))
		button.pressed.connect(_on_speed_pressed.bind(speed))
		speed_row.add_child(button)
		_speed_buttons.append(button)
		_speed_values.append(speed)

	column.add_child(_make_caption(String(texts["season"])))
	var season_row := HFlowContainer.new()
	column.add_child(season_row)
	var seasons: Array = _settings["seasons"]
	for entry: Dictionary in seasons:
		var id := StringName(String(entry["id"]))
		var button := _make_toggle(String(entry["label"]))
		button.pressed.connect(_on_season_pressed.bind(id))
		season_row.add_child(button)
		_season_buttons.append(button)
		_season_ids.append(id)

	_wind_label = Label.new()
	column.add_child(_wind_label)
	_wind_slider = _make_slider(0.0, 1.0, float(_settings["wind_step"]))
	_wind_slider.value_changed.connect(_on_wind_slider_changed)
	column.add_child(_wind_slider)

	_time_slider.editable = _day_night != null
	_wind_slider.editable = _wind != null
	for button: Button in _speed_buttons:
		button.disabled = _day_night == null
	for button: Button in _season_buttons:
		button.disabled = _seasons == null
	_chain_focus()


func _make_slider(min_value: float, max_value: float, step: float) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.custom_minimum_size = Vector2(0.0, 28.0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return slider


func _make_caption(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label


func _make_toggle(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.toggle_mode = true
	button.focus_mode = Control.FOCUS_ALL
	return button


## Navigation à la manette : la croix passe d'une ligne à l'autre ; gauche/droite règlent curseurs et boutons.
func _chain_focus() -> void:
	var rows: Array[Control] = [_time_slider, _speed_buttons[0], _season_buttons[0], _wind_slider]
	for i: int in rows.size():
		var above: Control = rows[(i + rows.size() - 1) % rows.size()]
		var below: Control = rows[(i + 1) % rows.size()]
		rows[i].focus_neighbor_top = rows[i].get_path_to(above)
		rows[i].focus_neighbor_bottom = rows[i].get_path_to(below)
	for group: Array[Button] in [_speed_buttons, _season_buttons]:
		var first: Button = group[0]
		var last: Button = group[group.size() - 1]
		first.focus_neighbor_left = first.get_path_to(last)
		last.focus_neighbor_right = last.get_path_to(first)
		for button: Button in group:
			button.focus_neighbor_top = button.get_path_to(_row_above(button, group))
			button.focus_neighbor_bottom = button.get_path_to(_row_below(button, group))


func _row_above(button: Button, group: Array[Button]) -> Control:
	return _time_slider if group == _speed_buttons else _speed_buttons[mini(group.find(button), _speed_buttons.size() - 1)]


func _row_below(button: Button, group: Array[Button]) -> Control:
	return _season_buttons[mini(group.find(button), _season_buttons.size() - 1)] if group == _speed_buttons else _wind_slider


func _set_open(value: bool) -> void:
	_open = value
	_panel.visible = value
	if _game_input != null and _game_input.has_method(&"set_mouse_capture"):
		if value:
			_mouse_capture_before = bool(_game_input.call(&"is_mouse_capture_requested"))
			_game_input.call(&"set_mouse_capture", false)
		elif _mouse_capture_before:
			_game_input.call(&"set_mouse_capture", true)
			_mouse_capture_before = false
	if value:
		_refresh_all()
		_time_slider.grab_focus()
		opened.emit()
	else:
		var focused: Control = _panel.get_viewport().gui_get_focus_owner() if _panel.is_inside_tree() else null
		if focused != null and _panel.is_ancestor_of(focused):
			focused.release_focus()
		closed.emit()


func _refresh_all() -> void:
	_shown_minute = -1
	if _day_night != null:
		_show_time(float(_day_night.get(&"time_of_day")))
		_show_speed(float(_day_night.get(&"time_scale")))
	else:
		_time_label.text = "%s : %s" % [String(_settings["texts"]["time"]), String(_settings["texts"]["missing"])]
	if _seasons != null:
		_show_season(StringName(_seasons.get(&"season")))
	if _wind != null:
		_show_wind(float(_wind.call(&"get_base_strength")))
	else:
		_wind_label.text = "%s : %s" % [String(_settings["texts"]["wind"]), String(_settings["texts"]["missing"])]


func _show_time(hours: float) -> void:
	var minute: int = int(floorf(fposmod(hours, 24.0) * 60.0))
	if minute == _shown_minute:
		return
	_shown_minute = minute
	_time_slider.set_value_no_signal(fposmod(hours, 24.0))
	_time_label.text = "%s : %02d h %02d" % [String(_settings["texts"]["time"]), minute / 60, minute % 60]


func _show_speed(scale_value: float) -> void:
	for i: int in _speed_buttons.size():
		_speed_buttons[i].set_pressed_no_signal(is_equal_approx(_speed_values[i], scale_value))


func _show_season(id: StringName) -> void:
	for i: int in _season_buttons.size():
		_season_buttons[i].set_pressed_no_signal(_season_ids[i] == id)


func _show_wind(value: float) -> void:
	_wind_slider.set_value_no_signal(value)
	_wind_label.text = "%s : %d %%" % [String(_settings["texts"]["wind"]), roundi(value * 100.0)]


func _on_time_changed(hours: float) -> void:
	if _open:
		_show_time(hours)


func _on_season_changed(id: StringName) -> void:
	if _open:
		_show_season(id)


func _on_time_slider_changed(value: float) -> void:
	if _day_night != null:
		_day_night.call(&"set_time", value)
	_show_time(value)


func _on_speed_pressed(speed: float) -> void:
	if _day_night != null:
		_day_night.set(&"time_scale", speed)
		_show_speed(float(_day_night.get(&"time_scale")))


func _on_season_pressed(id: StringName) -> void:
	if _seasons != null:
		_seasons.call(&"set_season", id)
		_show_season(StringName(_seasons.get(&"season")))


func _on_wind_slider_changed(value: float) -> void:
	if _wind != null:
		_wind.call(&"set_base_strength", value)
		_show_wind(float(_wind.call(&"get_base_strength")))
