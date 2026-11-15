extends GutTest
## Modèle du vent : déterminisme, bornes, continuité, pires cas (100 heures, force maximale).

const HUNDRED_HOURS: float = 360000.0
const FRAME: float = 1.0 / 60.0

var _settings: WindSettings = null


func before_each() -> void:
	_settings = WindSettings.load_default()


func test_settings_load() -> void:
	assert_not_null(_settings, "wind.json doit être valide")


func test_deterministic() -> void:
	var a := WindModel.new(_settings)
	var b := WindModel.new(_settings)
	a.evaluate(123.456, 0.4)
	b.evaluate(123.456, 0.4)
	assert_eq(a.strength, b.strength)
	assert_eq(a.direction, b.direction)
	assert_eq(a.gust, b.gust)


func test_bounds_over_one_hundred_hours() -> void:
	var model := WindModel.new(_settings)
	var t: float = 0.0
	var step: float = 7.3
	while t < HUNDRED_HOURS:
		for base: float in [0.0, 0.5, 1.0]:
			model.evaluate(t, base)
			assert_between(model.strength, 0.0, 1.0)
			assert_between(model.gust, 0.0, 1.0)
			assert_almost_eq(model.direction.length(), 1.0, 0.0001)
		t += step * 1000.0


func test_full_base_strength_is_maximal() -> void:
	var model := WindModel.new(_settings)
	model.evaluate(5.0, 1.0)
	assert_eq(model.strength, 1.0)


func test_calm_base_still_gusts_but_stays_below_storm() -> void:
	var model := WindModel.new(_settings)
	var peak: float = 0.0
	var t: float = 0.0
	while t < 600.0:
		model.evaluate(t, 0.0)
		peak = maxf(peak, model.strength)
		t += 0.25
	assert_gt(peak, 0.1, "les rafales doivent se sentir même par calme")
	assert_lt(peak, 0.9)


func test_strength_is_continuous() -> void:
	var model := WindModel.new(_settings)
	var previous: float = -1.0
	var worst: float = 0.0
	var t: float = 50000.0
	for i: int in 60 * 600:
		model.evaluate(t, 0.5)
		if previous >= 0.0:
			worst = maxf(worst, absf(model.strength - previous))
		previous = model.strength
		t += FRAME
	assert_lt(worst, 0.01, "pas de saut de force d'une image à l'autre (pire écart %f)" % worst)


func test_direction_stays_within_drift() -> void:
	var model := WindModel.new(_settings)
	var base := Vector2.from_angle(_settings.direction_base)
	var t: float = 0.0
	while t < 5000.0:
		model.evaluate(t, 0.5)
		assert_lte(absf(model.direction.angle_to(base)), _settings.direction_drift + 0.0001)
		t += 3.1
