extends GutTest
## Test de charge du cycle jour/nuit : coût d'une mise à jour complète (échantillonnage, lumières,
## environnement, paramètres du ciel) à chacune des 24 heures, nombre d'objets constant (aucune
## allocation entretenue) et partie de 100 heures de jeu sans dérive.

const SYSTEM_SCRIPT: String = "res://world/sky/day_night.gd"
const UPDATES_PER_HOUR: int = 2000
## Pire cas visé : une mise à jour par image à 60 i/s laisse 16,6 ms ; le cycle ne doit pas dépasser 1 %.
const MAX_MEAN_UPDATE_USEC: float = 160.0

var _system: DayNightSystem = null


func before_each() -> void:
	_system = load(SYSTEM_SCRIPT).new()
	add_child_autofree(_system)
	_system.time_scale = 0.0
	add_child_autofree(_system.build_environment())


func test_update_cost_at_every_hour() -> void:
	var worst: float = 0.0
	var report: PackedStringArray = PackedStringArray()
	for hour: int in 24:
		_system.set_time(float(hour))
		var start: int = Time.get_ticks_usec()
		for step: int in UPDATES_PER_HOUR:
			_system.set_time(float(hour) + float(step % 7) * 0.001)
		var mean: float = float(Time.get_ticks_usec() - start) / float(UPDATES_PER_HOUR)
		worst = maxf(worst, mean)
		report.append("%dh : %.1f us" % [hour, mean])
	gut.p("Coût moyen d'une mise à jour complète : " + ", ".join(report))
	gut.p("Pire heure : %.1f us (budget %.0f us)" % [worst, MAX_MEAN_UPDATE_USEC])
	assert_lt(worst, MAX_MEAN_UPDATE_USEC)


func test_no_object_growth_over_many_updates() -> void:
	_system.set_time(5.0)
	var before: float = Performance.get_monitor(Performance.OBJECT_COUNT)
	for step: int in 20000:
		_system.set_time(float(step % 2400) * 0.01)
	var after: float = Performance.get_monitor(Performance.OBJECT_COUNT)
	assert_eq(after, before, "aucun objet créé par les mises à jour")


func test_hundred_hour_session_has_no_drift() -> void:
	_system.set_time(0.0)
	_system.time_scale = 0.5
	var frames: int = 100 * 3600 * 2
	for frame: int in frames:
		_system._process(0.5)
	assert_between(_system.time_of_day, 0.0, 24.0)
	assert_almost_eq(_system.time_of_day, fposmod(0.5 * 0.5 * float(frames), 24.0), 0.01)
