class_name PerfBudget
extends RefCounted
## Compare un résumé de mesures à des budgets de performance.
##
## Format des budgets : {"frame_p99_ms": {"max": 16.6}, "fps_1pct_low": {"min": 55}, …}.
## Chaque clé doit exister dans le résumé produit par PerfRecorder.compute_summary() et le pipeline.


## Renvoie la liste des dépassements (vide si tous les budgets sont respectés).
static func check(summary: Dictionary, budgets: Dictionary) -> PackedStringArray:
	var violations := PackedStringArray()
	if budgets.is_empty():
		violations.append("aucun budget défini")
		return violations
	for key: Variant in budgets:
		var metric: String = str(key)
		var rule_raw: Variant = budgets[key]
		if typeof(rule_raw) != TYPE_DICTIONARY:
			violations.append("%s : règle invalide (objet attendu)" % metric)
			continue
		var rule: Dictionary = rule_raw
		if not rule.has("max") and not rule.has("min"):
			violations.append("%s : règle sans « max » ni « min »" % metric)
			continue
		if not summary.has(metric):
			violations.append("%s : métrique absente des mesures" % metric)
			continue
		var value: float = float(summary[metric])
		if rule.has("max") and value > float(rule["max"]):
			violations.append("%s = %.3f dépasse le maximum %.3f" % [metric, value, float(rule["max"])])
		if rule.has("min") and value < float(rule["min"]):
			violations.append("%s = %.3f est sous le minimum %.3f" % [metric, value, float(rule["min"])])
	return violations
