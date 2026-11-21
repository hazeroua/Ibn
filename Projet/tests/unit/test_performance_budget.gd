extends GutTest

const BUDGET_DATA: Dictionary = {
	"scene": "demo",
	"limits":
	{
		"p99_frame_ms": {"max": 16.6},
		"collision_checks": {"min": 1},
	},
}


func test_valid_budget_has_no_error() -> void:
	assert_true(PerformanceBudget.from_dictionary(BUDGET_DATA).errors.is_empty())


func test_report_within_budget_passes() -> void:
	var budget: PerformanceBudget = PerformanceBudget.from_dictionary(BUDGET_DATA)
	assert_true(budget.evaluate({"p99_frame_ms": 8.3, "collision_checks": 30}).is_empty())


func test_each_violation_is_reported() -> void:
	var budget: PerformanceBudget = PerformanceBudget.from_dictionary(BUDGET_DATA)
	assert_eq(budget.evaluate({"p99_frame_ms": 17.0, "collision_checks": 0}).size(), 2)


func test_missing_measure_fails() -> void:
	var budget: PerformanceBudget = PerformanceBudget.from_dictionary(BUDGET_DATA)
	assert_eq(budget.evaluate({"p99_frame_ms": 8.0}).size(), 1)


func test_malformed_budget_is_rejected() -> void:
	assert_false(PerformanceBudget.from_dictionary({"scene": "demo", "limits": {}}).errors.is_empty())
	assert_false(PerformanceBudget.from_dictionary({"scene": "demo", "limits": {"x": {}}}).errors.is_empty())


func test_shipped_budgets_are_valid() -> void:
	var catalog: SceneCatalog = SceneCatalog.from_dictionary(JsonData.load_dictionary("res://data/config/boot.json"))
	for scene_id: String in catalog.scene_ids():
		var budget: PerformanceBudget = PerformanceBudget.from_dictionary(JsonData.load_dictionary(catalog.budget_path(scene_id)))
		assert_true(budget.errors.is_empty(), "%s : %s" % [scene_id, budget.errors])
		assert_eq(budget.scene_id, scene_id)
