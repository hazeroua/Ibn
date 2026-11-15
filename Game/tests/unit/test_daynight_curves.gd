extends GutTest
## Courbes du cycle jour/nuit : continuité sur 24 h (aucun saut d'exposition ni de lumière), bouclage
## minuit, valeurs aux images clés et cohérence jour/nuit, avec les vraies données du jeu.

const SETTINGS_PATH: String = "res://data/sky/day_night.json"
## Écart maximal toléré entre deux minutes consécutives, par canal (lissage : très en dessous).
const MAX_STEP_EXPOSURE: float = 0.01
const MAX_STEP_COLOR: float = 0.02
const MAX_STEP_ENERGY: float = 0.03
const MINUTES_PER_DAY: int = 1440

var _curves: DayNightCurves = null
var _settings: Dictionary = {}


func before_each() -> void:
	_settings = JsonData.load_dictionary(SETTINGS_PATH)
	_curves = DayNightCurves.from_settings(_settings, "test")


func _sample(hours: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(DayNightCurves.CHANNEL_COUNT)
	_curves.sample(hours, out)
	return out


func test_data_valid() -> void:
	assert_true(_curves.is_valid())
	assert_eq(_curves.get_resolution(), 1440)


func test_no_exposure_jump_over_24_hours() -> void:
	var previous: PackedFloat32Array = _sample(0.0)
	var worst_exposure: float = 0.0
	var worst_color: float = 0.0
	var worst_energy: float = 0.0
	for minute: int in range(1, MINUTES_PER_DAY + 1):
		var current: PackedFloat32Array = _sample(float(minute) / 60.0)
		worst_exposure = maxf(worst_exposure, absf(current[DayNightCurves.CH_EXPOSURE] - previous[DayNightCurves.CH_EXPOSURE]))
		for channel: int in DayNightCurves.CHANNEL_COUNT:
			var step: float = absf(current[channel] - previous[channel])
			if channel == DayNightCurves.CH_SUN_ENERGY or channel == DayNightCurves.CH_AMBIENT_ENERGY:
				worst_energy = maxf(worst_energy, step)
			elif channel < DayNightCurves.CH_AMBIENT_ENERGY or channel == DayNightCurves.CH_AMBIENT_ENERGY + 1:
				worst_color = maxf(worst_color, step)
		previous = current
	gut.p("Plus grand écart par minute : exposition %.5f, couleur %.5f, énergie %.5f" % [worst_exposure, worst_color, worst_energy])
	assert_lt(worst_exposure, MAX_STEP_EXPOSURE, "saut d'exposition")
	assert_lt(worst_color, MAX_STEP_COLOR, "saut de couleur")
	assert_lt(worst_energy, MAX_STEP_ENERGY, "saut de lumière")


func test_wraps_at_midnight() -> void:
	var before: PackedFloat32Array = _sample(23.999)
	var after: PackedFloat32Array = _sample(0.0)
	var wrapped: PackedFloat32Array = _sample(24.0)
	var far: PackedFloat32Array = _sample(2400.0 + 12.0)
	var noon: PackedFloat32Array = _sample(12.0)
	for channel: int in DayNightCurves.CHANNEL_COUNT:
		assert_almost_eq(before[channel], after[channel], 0.01, "bouclage canal %d" % channel)
		assert_almost_eq(wrapped[channel], after[channel], 0.0001)
		assert_almost_eq(far[channel], noon[channel], 0.0001, "partie de 100 jours")


func test_negative_hours_wrap() -> void:
	var a: PackedFloat32Array = _sample(-1.0)
	var b: PackedFloat32Array = _sample(23.0)
	for channel: int in DayNightCurves.CHANNEL_COUNT:
		assert_almost_eq(a[channel], b[channel], 0.0001)


func test_key_values_are_reached() -> void:
	var keys: Array = _settings["keys"]
	for key_variant: Variant in keys:
		var key: Dictionary = key_variant
		var out: PackedFloat32Array = _sample(float(key["hour"]))
		assert_almost_eq(out[DayNightCurves.CH_EXPOSURE], float(key["exposure"]), 0.001, "exposition à %s h" % key["hour"])
		assert_almost_eq(out[DayNightCurves.CH_SUN_ENERGY], float(key["sun_energy"]), 0.001)
		assert_almost_eq(out[DayNightCurves.CH_STAR_ALPHA], float(key["star_alpha"]), 0.001)


func test_day_and_night_are_coherent() -> void:
	var noon: PackedFloat32Array = _sample(12.0)
	var midnight: PackedFloat32Array = _sample(0.0)
	assert_gt(noon[DayNightCurves.CH_SUN_ENERGY], 1.0)
	assert_eq(midnight[DayNightCurves.CH_SUN_ENERGY], 0.0)
	assert_eq(noon[DayNightCurves.CH_STAR_ALPHA], 0.0)
	assert_gt(midnight[DayNightCurves.CH_STAR_ALPHA], 0.9)
	assert_eq(noon[DayNightCurves.CH_MOON_ENERGY], 0.0)
	assert_gt(midnight[DayNightCurves.CH_MOON_ENERGY], 0.1)
	assert_gt(noon[DayNightCurves.CH_SKY_TOP + 2], midnight[DayNightCurves.CH_SKY_TOP + 2])


func test_all_values_finite_and_non_negative() -> void:
	for minute: int in MINUTES_PER_DAY:
		var out: PackedFloat32Array = _sample(float(minute) / 60.0 + 0.0123)
		for channel: int in DayNightCurves.CHANNEL_COUNT:
			assert_true(is_finite(out[channel]) and out[channel] >= 0.0, "canal %d à la minute %d" % [channel, minute])
