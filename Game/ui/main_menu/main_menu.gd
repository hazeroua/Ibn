class_name MainMenu
extends Control
## Accueil et paramètres. Interface construite en code pour rester indépendante des ressources
## externes et conserver une esthétique de manuscrit maghrébin sur toutes les résolutions.

const DEFAULT_SCENE_SETTING: String = "ibn/boot/default_scene"
const GOLD := Color("#c5a35b")
const PARCHMENT := Color("#e6d3a1")
const INK := Color("#30251c")
const PANEL := Color("#42362c")
const PROFILE_IDS: Array[String] = ["low", "balanced", "high", "ultra", "custom"]
const PROFILE_LABELS: Array[String] = ["Faible", "Équilibré", "Élevé", "Ultra", "Personnalisé"]
const FPS_VALUES: Array[int] = [30, 60, 90, 120, 144, 0]

var in_game: bool = false

var _home: Control
var _settings_panel: Control
var _controls: Dictionary = {}
var _value_labels: Dictionary = {}
var _draft: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var input_service: Node = get_node_or_null("/root/GameInput")
	if input_service != null:
		input_service.call(&"set_mouse_capture", false)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_home()
	_build_settings()
	_show_settings(false)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#d5bd8d"))
	# Gravure de désert : plans irréguliers, soleil et chemin, sans motif répété.
	draw_circle(Vector2(size.x * 0.72, size.y * 0.34), size.y * 0.115, Color("#b66d43"))
	draw_colored_polygon(PackedVector2Array([Vector2(0, size.y * 0.56), Vector2(size.x * 0.35, size.y * 0.42), Vector2(size.x * 0.67, size.y * 0.58), Vector2(size.x, size.y * 0.43), Vector2(size.x, size.y), Vector2(0, size.y)]), Color("#ac8057"))
	draw_colored_polygon(PackedVector2Array([Vector2(0, size.y * 0.72), Vector2(size.x * 0.25, size.y * 0.58), Vector2(size.x * 0.54, size.y * 0.75), Vector2(size.x, size.y * 0.61), Vector2(size.x, size.y), Vector2(0, size.y)]), Color("#805b43"))
	draw_colored_polygon(PackedVector2Array([Vector2(0, size.y * 0.84), Vector2(size.x * 0.36, size.y * 0.71), Vector2(size.x * 0.7, size.y * 0.88), Vector2(size.x, size.y * 0.77), Vector2(size.x, size.y), Vector2(0, size.y)]), Color("#4d473c"))
	var path := PackedVector2Array([Vector2(size.x * 0.57, size.y), Vector2(size.x * 0.61, size.y * 0.86), Vector2(size.x * 0.72, size.y * 0.78), Vector2(size.x * 0.68, size.y * 0.65)])
	draw_polyline(path, Color("#d2ae75"), 5.0, true)
	draw_rect(Rect2(0, 0, size.x * 0.48, size.y), Color("#1d302dca"))
	draw_line(Vector2(43, 42), Vector2(43, size.y - 42), Color("#c8a879"), 2.0)
	draw_line(Vector2(size.x * 0.48, 0), Vector2(size.x * 0.48, size.y), Color("#e1c79366"), 2.0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		if _home != null:
			_home.add_theme_constant_override("margin_right", int(size.x * 0.54))
		queue_redraw()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") and _settings_panel.visible:
		_show_settings(false)
		get_viewport().set_input_as_handled()
	elif in_game and event.is_action_pressed(&"ui_cancel"):
		_resume_game()
		get_viewport().set_input_as_handled()


func _build_home() -> void:
	_home = MarginContainer.new()
	_home.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_home.add_theme_constant_override("margin_left", 100)
	_home.add_theme_constant_override("margin_right", int(size.x * 0.54))
	_home.add_theme_constant_override("margin_top", 95)
	_home.add_theme_constant_override("margin_bottom", 85)
	add_child(_home)
	var text_column := VBoxContainer.new()
	_home.add_child(text_column)
	var era := Label.new()
	era.text = "CARNET DE VOYAGE     /     AN 732 DE L'HÉGIRE"
	era.add_theme_color_override("font_color", GOLD)
	era.add_theme_font_size_override("font_size", 15)
	text_column.add_child(era)
	var title := Label.new()
	title.text = "Ibn Khaldoun" if in_game else "Les chemins\nd'Ibn Khaldoun"
	title.add_theme_color_override("font_color", PARCHMENT)
	title.add_theme_font_size_override("font_size", 58)
	text_column.add_child(title)
	var rule := HSeparator.new()
	rule.add_theme_constant_override("separation", 36)
	text_column.add_child(rule)
	var quote := Label.new()
	quote.text = "Une halte dans le voyage." if in_game else "Du sable aux cités, un monde à parcourir.\nL'histoire commence ici."
	quote.add_theme_color_override("font_color", Color("#d8c99e"))
	quote.add_theme_font_size_override("font_size", 19)
	text_column.add_child(quote)
	text_column.add_spacer(false)
	var menu := VBoxContainer.new()
	menu.add_theme_constant_override("separation", 8)
	text_column.add_child(menu)
	var start := _menu_button("Reprendre le voyage" if in_game else "Commencer le voyage")
	start.pressed.connect(_resume_game if in_game else _start_game)
	menu.add_child(start)
	var settings_button := _menu_button("Paramètres")
	settings_button.pressed.connect(func() -> void: _show_settings(true))
	menu.add_child(settings_button)
	var quit := _menu_button("Retour à l'accueil" if in_game else "Quitter le jeu")
	quit.pressed.connect(_return_to_title if in_game else _quit_game)
	menu.add_child(quit)
	start.grab_focus.call_deferred()


func _build_settings() -> void:
	var overlay := CenterContainer.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	_settings_panel = PanelContainer.new()
	_settings_panel.custom_minimum_size = Vector2(820.0, 760.0)
	_settings_panel.add_theme_stylebox_override("panel", _panel_style())
	overlay.add_child(_settings_panel)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	_settings_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	var title := Label.new()
	title.text = "PARAMÈTRES"
	title.add_theme_color_override("font_color", GOLD)
	title.add_theme_font_size_override("font_size", 30)
	column.add_child(title)
	var help := Label.new()
	help.text = "Réglages fins de l'image et du monde. Le rayon et le budget des chunks prennent effet au prochain chargement." if in_game else "Choisissez un profil, puis ajustez chaque détail à votre façon."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.add_theme_color_override("font_color", Color("#d8c99e"))
	column.add_child(help)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 28)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)
	_add_profile_control(grid)
	_add_slider(grid, "render_scale", "Résolution 3D", 0.5, 1.0, 0.05, "La résolution interne : principal levier pour le GPU.")
	_add_spin(grid, "chunk_radius", "Rayon de chunks", 1, 6, "Étendue du monde maintenue autour du joueur.")
	_add_slider(
		grid, "stream_budget_ms", "Budget streaming / image", 0.5, 8.0, 0.5, "Temps CPU maximal consacré aux entrées et sorties de chunks."
	)
	_add_spin(grid, "concurrent_builds", "Constructions simultanées", 1, 8, "Nombre maximal de chunks préparés en arrière-plan.")
	_add_check(grid, "shadows", "Ombres dynamiques", "Désactiver améliore fortement les petites cartes graphiques.")
	_add_slider(grid, "shadow_distance_m", "Distance des ombres", 40.0, 400.0, 20.0, "Portée des ombres du soleil, en mètres.")
	_add_check(grid, "ssao", "Occlusion ambiante", "Renforce les creux et les contacts, avec un coût GPU.")
	_add_check(grid, "vsync", "Synchronisation verticale", "Évite le déchirement de l'image.")
	_add_fps_control(grid)
	_add_check(grid, "fullscreen", "Plein écran", "Bascule entre fenêtre et plein écran.")
	_add_slider(grid, "master_volume", "Volume général", 0.0, 1.0, 0.05, "Volume de tous les sons du jeu.")
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 10)
	column.add_child(actions)
	var reset := _small_button("Valeurs par défaut")
	reset.pressed.connect(_reset_settings)
	actions.add_child(reset)
	var back := _small_button("Retour")
	back.pressed.connect(func() -> void: _show_settings(false))
	actions.add_child(back)
	var apply := _small_button("Appliquer")
	apply.pressed.connect(_apply_settings)
	actions.add_child(apply)


func _add_profile_control(grid: GridContainer) -> void:
	grid.add_child(_setting_label("Niveau de performance", "Préréglage global conseillé pour votre machine."))
	var option := OptionButton.new()
	for label: String in PROFILE_LABELS:
		option.add_item(label)
	option.item_selected.connect(_on_profile_selected)
	grid.add_child(option)
	_controls["profile"] = option


func _add_slider(grid: GridContainer, key: String, title: String, minimum: float, maximum: float, step: float, hint: String) -> void:
	grid.add_child(_setting_label(title, hint))
	var box := VBoxContainer.new()
	var value_label := Label.new()
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(value_label)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(_on_detail_changed.bind(key))
	box.add_child(slider)
	grid.add_child(box)
	_controls[key] = slider
	_value_labels[key] = value_label


func _add_spin(grid: GridContainer, key: String, title: String, minimum: int, maximum: int, hint: String) -> void:
	grid.add_child(_setting_label(title, hint))
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = 1.0
	spin.value_changed.connect(_on_detail_changed.bind(key))
	grid.add_child(spin)
	_controls[key] = spin


func _add_check(grid: GridContainer, key: String, title: String, hint: String) -> void:
	grid.add_child(_setting_label(title, hint))
	var check := CheckButton.new()
	check.text = "Activé"
	check.toggled.connect(_on_detail_changed.bind(key))
	grid.add_child(check)
	_controls[key] = check


func _add_fps_control(grid: GridContainer) -> void:
	grid.add_child(_setting_label("Limite d'images / seconde", "0 signifie sans limite ; la VSync peut rester prioritaire."))
	var option := OptionButton.new()
	for fps: int in FPS_VALUES:
		option.add_item("Sans limite" if fps == 0 else "%d FPS" % fps)
	option.item_selected.connect(_on_fps_selected)
	grid.add_child(option)
	_controls["max_fps"] = option


func _show_settings(show: bool) -> void:
	_home.visible = not show
	_settings_panel.visible = show
	if show:
		var settings_service: GameSettings = get_node_or_null("/root/Settings") as GameSettings
		_draft = settings_service.snapshot() if settings_service != null else GameSettings.default_values()
		_refresh_controls()
		(_controls["profile"] as OptionButton).grab_focus.call_deferred()


func _refresh_controls() -> void:
	var profile: String = str(_draft.get("profile", "balanced"))
	(_controls["profile"] as OptionButton).select(maxi(PROFILE_IDS.find(profile), 0))
	for key: String in ["render_scale", "stream_budget_ms", "shadow_distance_m", "master_volume"]:
		(_controls[key] as HSlider).set_value_no_signal(float(_draft[key]))
	for key: String in ["chunk_radius", "concurrent_builds"]:
		(_controls[key] as SpinBox).set_value_no_signal(float(_draft[key]))
	for key: String in ["shadows", "ssao", "vsync", "fullscreen"]:
		(_controls[key] as CheckButton).set_pressed_no_signal(bool(_draft[key]))
	var fps_index: int = FPS_VALUES.find(int(_draft["max_fps"]))
	(_controls["max_fps"] as OptionButton).select(maxi(fps_index, 0))
	_refresh_value_labels()


func _refresh_value_labels() -> void:
	(_value_labels["render_scale"] as Label).text = "%d %%" % roundi(float(_draft["render_scale"]) * 100.0)
	(_value_labels["stream_budget_ms"] as Label).text = "%.1f ms" % float(_draft["stream_budget_ms"])
	(_value_labels["shadow_distance_m"] as Label).text = "%d m" % roundi(float(_draft["shadow_distance_m"]))
	(_value_labels["master_volume"] as Label).text = "%d %%" % roundi(float(_draft["master_volume"]) * 100.0)
	var chunks: int = GameSettings.estimated_chunk_count(int(_draft["chunk_radius"]))
	(_controls["chunk_radius"] as SpinBox).suffix = "  (≈ %d chunks)" % chunks


func _on_profile_selected(index: int) -> void:
	if index < 0 or index >= PROFILE_IDS.size():
		return
	var profile: String = PROFILE_IDS[index]
	if profile != "custom":
		_draft.merge(GameSettings.PRESETS[profile] as Dictionary, true)
	_draft["profile"] = profile
	_refresh_controls()


func _on_detail_changed(value: Variant, key: String) -> void:
	_draft[key] = value
	_mark_custom()
	_refresh_value_labels()


func _on_fps_selected(index: int) -> void:
	if index >= 0 and index < FPS_VALUES.size():
		_draft["max_fps"] = FPS_VALUES[index]
		_mark_custom()


func _mark_custom() -> void:
	_draft["profile"] = "custom"
	(_controls["profile"] as OptionButton).select(PROFILE_IDS.find("custom"))


func _apply_settings() -> void:
	var settings_service: GameSettings = get_node_or_null("/root/Settings") as GameSettings
	if settings_service == null:
		return
	settings_service.apply_user_values(_draft)
	_draft = settings_service.snapshot()
	_refresh_controls()


func _reset_settings() -> void:
	_draft = GameSettings.default_values()
	_refresh_controls()


func _start_game() -> void:
	var scene_path: String = str(ProjectSettings.get_setting(DEFAULT_SCENE_SETTING, ""))
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		push_error("MainMenu : scène de jeu introuvable « %s »." % scene_path)
		return
	get_tree().change_scene_to_file(scene_path)


func _resume_game() -> void:
	get_tree().paused = false
	var input_service: Node = get_node_or_null("/root/GameInput")
	if input_service != null:
		input_service.call(&"set_mouse_capture", true)
	if in_game:
		get_parent().queue_free()


func _return_to_title() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://ui/main_menu/main_menu.tscn")


func _quit_game() -> void:
	var input_service: Node = get_node_or_null("/root/GameInput")
	if input_service != null:
		input_service.call(&"quit_safely")


func _menu_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0.0, 54.0)
	button.flat = true
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_size_override("font_size", 19)
	button.add_theme_color_override("font_color", PARCHMENT)
	button.add_theme_stylebox_override("normal", _button_style(Color("#29403a", 0.3), Color.TRANSPARENT, 0))
	button.add_theme_stylebox_override("hover", _button_style(Color("#38514a"), GOLD, 1))
	button.add_theme_stylebox_override("focus", _button_style(Color("#38514a"), GOLD, 1))
	return button


func _small_button(text: String) -> Button:
	var button := _menu_button(text)
	button.custom_minimum_size = Vector2(170.0, 44.0)
	button.add_theme_font_size_override("font_size", 15)
	return button


func _setting_label(title: String, hint: String) -> Control:
	var box := VBoxContainer.new()
	var label := Label.new()
	label.text = title
	label.add_theme_color_override("font_color", PARCHMENT)
	label.add_theme_font_size_override("font_size", 16)
	box.add_child(label)
	var description := Label.new()
	description.text = hint
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.add_theme_color_override("font_color", Color("#9fb2a8"))
	description.add_theme_font_size_override("font_size", 12)
	box.add_child(description)
	return box


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(PANEL, 0.98)
	style.border_color = GOLD
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	return style


func _button_style(color: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(5)
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	return style


func _draw_star(center: Vector2, radius: float, color: Color) -> void:
	var points := PackedVector2Array()
	for index: int in 16:
		var angle := -PI * 0.5 + float(index) * PI / 8.0
		var length := radius if index % 2 == 0 else radius * 0.42
		points.append(center + Vector2(cos(angle), sin(angle)) * length)
	draw_colored_polygon(points, color)
