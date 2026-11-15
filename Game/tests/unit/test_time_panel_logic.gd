extends GutTest
## Panneau de temps : ouverture par action, réglages relayés aux services, mise à jour par signaux, manette.

var _day_night: Node = null
var _seasons: Node = null
var _wind: Node = null
var _panel: TimePanel = null


func before_each() -> void:
	_day_night = TimeDoubles.install(get_tree(), TimeDoubles.DAY_NIGHT_SCRIPT, &"DayNight")
	_seasons = TimeDoubles.install(get_tree(), TimeDoubles.SEASONS_SCRIPT, &"Seasons")
	_wind = TimeDoubles.install(get_tree(), TimeDoubles.WIND_SCRIPT, &"Wind")
	_panel = TimePanel.new()
	add_child_autofree(_panel)


func after_each() -> void:
	for node: Node in [_wind, _seasons, _day_night]:
		TimeDoubles.uninstall(get_tree(), node)


func _find(type_name: String, index: int) -> Node:
	var found: Array[Node] = _panel.find_children("*", type_name, true, false)
	return found[index]


func test_action_declared_with_f2_and_gamepad() -> void:
	assert_eq(_panel.get_action(), &"toggle_time_panel")
	assert_true(InputMap.has_action(&"toggle_time_panel"))
	var has_key: bool = false
	var has_pad: bool = false
	for event: InputEvent in InputMap.action_get_events(&"toggle_time_panel"):
		if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_F2:
			has_key = true
		if event is InputEventJoypadButton:
			has_pad = true
	assert_true(has_key, "F2 attendue.")
	assert_true(has_pad, "Un bouton de manette est attendu.")


func test_starts_closed_and_toggles_on_action() -> void:
	assert_false(_panel.is_open())
	var press := InputEventAction.new()
	press.action = &"toggle_time_panel"
	press.pressed = true
	_panel._unhandled_input(press)
	assert_true(_panel.is_open())
	_panel._unhandled_input(press)
	assert_false(_panel.is_open())


func test_time_slider_sets_time() -> void:
	_panel.toggle()
	var slider: HSlider = _find("HSlider", 0) as HSlider
	slider.value = 18.5
	assert_almost_eq(float(_day_night.get(&"time_of_day")), 18.5, 0.001)


func test_time_slider_follows_time_changed_without_feedback() -> void:
	_panel.toggle()
	_day_night.call(&"set_time", 6.0)
	var slider: HSlider = _find("HSlider", 0) as HSlider
	assert_almost_eq(slider.value, 6.0, 0.06)
	assert_almost_eq(float(_day_night.get(&"time_of_day")), 6.0, 0.001)


func test_speed_buttons_set_time_scale() -> void:
	_panel.toggle()
	var expected: Array[float] = [0.0, 1.0, 60.0, 600.0, 3600.0]
	for i: int in expected.size():
		(_panel._speed_buttons[i] as Button).pressed.emit()
		assert_eq(float(_day_night.get(&"time_scale")), expected[i])
		assert_true((_panel._speed_buttons[i] as Button).button_pressed)


func test_season_buttons_and_signal() -> void:
	_panel.toggle()
	(_panel._season_buttons[3] as Button).pressed.emit()
	assert_eq(StringName(_seasons.get(&"season")), &"hiver")
	_seasons.call(&"set_season", &"printemps")
	assert_true((_panel._season_buttons[0] as Button).button_pressed)
	assert_false((_panel._season_buttons[3] as Button).button_pressed)


func test_wind_slider_sets_base_strength() -> void:
	_panel.toggle()
	var slider: HSlider = _find("HSlider", 1) as HSlider
	slider.value = 0.8
	assert_almost_eq(float(_wind.call(&"get_base_strength")), 0.8, 0.001)


func test_open_shows_current_values() -> void:
	_day_night.set(&"time_of_day", 3.5)
	_wind.call(&"set_base_strength", 0.6)
	_seasons.set(&"season", &"automne")
	_panel.toggle()
	assert_almost_eq((_find("HSlider", 0) as HSlider).value, 3.5, 0.06)
	assert_almost_eq((_find("HSlider", 1) as HSlider).value, 0.6, 0.011)
	assert_true((_panel._season_buttons[2] as Button).button_pressed)


func test_gamepad_focus_on_open_and_cancel_closes() -> void:
	_panel.toggle()
	assert_eq(get_viewport().gui_get_focus_owner(), _find("HSlider", 0))
	var cancel := InputEventAction.new()
	cancel.action = &"ui_cancel"
	cancel.pressed = true
	_panel._unhandled_input(cancel)
	assert_false(_panel.is_open())


func test_focus_chain_covers_all_rows() -> void:
	var time_slider: HSlider = _find("HSlider", 0) as HSlider
	var wind_slider: HSlider = _find("HSlider", 1) as HSlider
	assert_eq(time_slider.get_node(time_slider.focus_neighbor_bottom), _panel._speed_buttons[0])
	assert_eq(wind_slider.get_node(wind_slider.focus_neighbor_bottom), time_slider)
	var last_speed: Button = _panel._speed_buttons[4]
	assert_eq(_panel._speed_buttons[0].get_node(_panel._speed_buttons[0].focus_neighbor_left), last_speed)
	assert_eq(last_speed.get_node(last_speed.focus_neighbor_bottom), _panel._season_buttons[3])


func test_missing_services_do_not_crash() -> void:
	var lone := TimePanel.new()
	add_child_autofree(lone)
	lone.toggle()
	assert_true(lone.is_open())
	lone.toggle()
	assert_false(lone.is_open())
