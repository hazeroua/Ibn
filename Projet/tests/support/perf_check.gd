class_name PerfCheck
extends RefCounted
## Durées mesurées par les tests de charge. Elles dépendent de l'état de la machine (sur batterie, un
## portable peut être deux à trois fois plus lent) : par décision du porteur du projet, elles sont
## affichées mais ne font pas échouer les tests, sauf si le réglage BLOCKING_SETTING vaut true.
## Les contrôles qui ne dépendent pas de la machine (allocations, nombre de nœuds, triangles,
## résultats) restent des assertions normales. Le budget des cartes (60 i/s) reste vérifié par
## outils/valider.ps1.

const BLOCKING_SETTING: String = "ibn/tests/budgets_de_temps_bloquants"


static func is_blocking() -> bool:
	return bool(ProjectSettings.get_setting(BLOCKING_SETTING, false))


## Durée strictement sous le budget.
static func under(test: GutTest, value: float, budget: float, label: String = "") -> void:
	if is_blocking():
		test.assert_lt(value, budget, label)
		return
	test.assert_true(is_finite(value) and value >= 0.0, "mesure prise : %s" % label)
	_report(test, value, budget, label, value < budget)


## Valeur inférieure ou égale au plafond.
static func at_most(test: GutTest, value: float, budget: float, label: String = "") -> void:
	if is_blocking():
		test.assert_lte(value, budget, label)
		return
	test.assert_true(is_finite(value) and value >= 0.0, "mesure prise : %s" % label)
	_report(test, value, budget, label, value <= budget)


static func _report(test: GutTest, value: float, budget: float, label: String, ok: bool) -> void:
	var name: String = label if not label.is_empty() else "durée"
	var state: String = "sous le budget" if ok else "DÉPASSEMENT (non bloquant)"
	test.gut.p("BUDGET %s : %.4f pour %.4f, %s" % [name, value, budget, state])
