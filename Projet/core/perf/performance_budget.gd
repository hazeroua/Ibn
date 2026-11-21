class_name PerformanceBudget
extends RefCounted
## Budget de performance d'une scène, lu dans data/budgets/<scène>.json.
## Chaque limite porte sur une clé du rapport de mesure : { "max": x } ou { "min": x }.

var scene_id: String = ""
var limits: Dictionary = {}
var errors: PackedStringArray = PackedStringArray()


static func from_dictionary(data: Dictionary) -> PerformanceBudget:
	var budget: PerformanceBudget = PerformanceBudget.new()
	var context: String = "budget"
	budget.scene_id = JsonData.read_string(data, "scene", budget.errors, context)
	var limits: Dictionary = JsonData.read_dictionary(data, "limits", budget.errors, context)
	if limits.is_empty():
		budget.errors.append(context + " : aucune limite définie.")
	for key: String in limits:
		var limit: Variant = limits[key]
		if typeof(limit) != TYPE_DICTIONARY:
			budget.errors.append("%s › %s : la limite doit être un objet." % [context, key])
			continue
		var bounds: Dictionary = limit
		var has_bound: bool = false
		for bound_name: String in ["min", "max"]:
			if bounds.has(bound_name):
				has_bound = true
				JsonData.read_number(bounds, bound_name, budget.errors, context + " › " + key)
		if not has_bound:
			budget.errors.append("%s › %s : il faut « min » ou « max »." % [context, key])
	budget.limits = limits
	return budget


## Renvoie la liste des dépassements (vide si le rapport respecte le budget).
func evaluate(report: Dictionary) -> PackedStringArray:
	var failures: PackedStringArray = PackedStringArray()
	for key: String in limits:
		var value: Variant = report.get(key)
		if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
			failures.append("%s : mesure absente du rapport." % key)
			continue
		var measured: float = float(value)
		var bounds: Dictionary = limits[key]
		if bounds.has("max") and measured > float(bounds["max"]):
			failures.append("%s = %s dépasse le maximum %s." % [key, _format(measured), _format(float(bounds["max"]))])
		if bounds.has("min") and measured < float(bounds["min"]):
			failures.append("%s = %s est sous le minimum %s." % [key, _format(measured), _format(float(bounds["min"]))])
	return failures


static func _format(value: float) -> String:
	return str(snappedf(value, 0.01))
