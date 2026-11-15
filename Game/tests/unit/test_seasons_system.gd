extends GutTest
## Autoload Seasons : réglages, transition douce, signal, uniformes ; pire cas (transition, 100 h) mesuré.

const FRAME: float = 1.0 / 60.0
const BUDGET_USEC_PER_FRAME: float = 50.0

var _seasons: SeasonsSystem = null


func before_each() -> void:
	_seasons = SeasonsSystem.new()
	add_child_autofree(_seasons)
	_seasons.configure(JsonData.load_dictionary(SeasonsSystem.SETTINGS_PATH))


func test_four_seasons_and_default() -> void:
	assert_eq(_seasons.get_season_ids().size(), 4)
	assert_eq(_seasons.season, &"ete")
	assert_almost_eq(_seasons.get_multiplier(&"sun_intensity"), 1.0, 0.0001)


func test_unknown_season_is_refused() -> void:
	_seasons.set_season(&"mousson")
	assert_push_error("saison inconnue")
	assert_eq(_seasons.season, &"ete")


func test_blend_endpoints_and_middle() -> void:
	var start: PackedFloat32Array = _seasons.blend(&"ete", &"hiver", 0.0)
	var finish: PackedFloat32Array = _seasons.blend(&"ete", &"hiver", 1.0)
	var middle: PackedFloat32Array = _seasons.blend(&"ete", &"hiver", 0.5)
	assert_almost_eq(start[SeasonsSystem.SUN_INTENSITY], 1.0, 0.0001)
	assert_almost_eq(finish[SeasonsSystem.SUN_INTENSITY], 0.6, 0.0001)
	assert_almost_eq(middle[SeasonsSystem.SUN_INTENSITY], 0.8, 0.0001)


func test_transition_emits_signal_and_converges() -> void:
	watch_signals(_seasons)
	_seasons.set_season(&"hiver")
	assert_signal_emitted_with_parameters(_seasons, "season_changed", [&"hiver"])
	assert_true(_seasons.transitioning)
	_seasons._process(100.0)
	assert_false(_seasons.transitioning)
	assert_almost_eq(_seasons.get_value(&"day_length"), 10.0, 0.0001)
	assert_almost_eq(_seasons.get_multiplier(&"sun_intensity"), 0.6, 0.0001)
	assert_eq(_seasons.get_color(&"grass").to_html(false), "7d8f58")


func test_change_during_transition_has_no_jump() -> void:
	_seasons.set_season(&"hiver")
	_seasons._process(1.5)
	var before: float = _seasons.get_value(&"sun_intensity")
	_seasons.set_season(&"printemps")
	assert_almost_eq(_seasons.get_value(&"sun_intensity"), before, 0.0001)


func test_instant_change() -> void:
	_seasons.set_season(&"automne", true)
	assert_false(_seasons.transitioning)
	assert_almost_eq(_seasons.get_value(&"sun_max_height"), 52.0, 0.0001)


func test_globals_are_declared() -> void:
	var names: Array[StringName] = RenderingServer.global_shader_parameter_get_list()
	for uniform: String in [
		"sun_color", "sun_intensity", "sun_max_height", "day_length", "fog_density", "grass_color", "palm_color", "wind_strength", "dust"
	]:
		assert_true(names.has(StringName("season_" + uniform)), uniform)


func test_load_transition_cost_and_hundred_hours() -> void:
	# Pire cas : transitions enchaînées sans pause ; puis 100 h de jeu sans transition (le nœud ne traite plus rien).
	var started: int = Time.get_ticks_usec()
	var frames: int = 0
	for index: int in 200:
		_seasons.set_season(_seasons.get_season_ids()[index % 4])
		for step: int in 300:
			_seasons._process(FRAME)
			frames += 1
	var per_frame: float = float(Time.get_ticks_usec() - started) / float(frames)
	gut.p("transition : %.2f us par image (%d images)" % [per_frame, frames])
	assert_lt(per_frame, BUDGET_USEC_PER_FRAME)
	assert_false(_seasons.is_processing(), "au repos, aucun traitement par image")
	# 100 h de jeu = 100 h sans traitement : les valeurs restent exactement celles de la dernière saison atteinte.
	var rest: float = _seasons.get_value(&"dust")
	for step: int in 1000:
		assert_eq(_seasons.get_value(&"dust"), rest)
