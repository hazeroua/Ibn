extends GutTest
## Outils du pipeline : ligne de commande, points de vue, budgets.


func test_command_line_parsing() -> void:
	var args: Dictionary[String, String] = CommandLine.parse(PackedStringArray(["--mode=capture", "--no-budgets", "--out=C:/a=b"]))
	assert_eq(args["mode"], "capture")
	assert_eq(args["no-budgets"], "true")
	assert_eq(args["out"], "C:/a=b", "seul le premier « = » sépare la clé de la valeur")


func test_project_viewpoints_are_valid() -> void:
	var points: Array[Viewpoint] = Viewpoints.load_file("res://data/sandbox/viewpoints.json")
	assert_eq(points.size(), 4)
	assert_eq(points[0].id, "vue_generale")


func test_viewpoint_sampling_hits_endpoints() -> void:
	var a := Viewpoint.new("a", Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 0.0)))
	var b := Viewpoint.new("b", Transform3D(Basis.IDENTITY, Vector3(10.0, 0.0, 0.0)))
	var points: Array[Viewpoint] = [a, b]
	assert_eq(Viewpoints.sample(points, 0.0).origin, Vector3.ZERO)
	assert_eq(Viewpoints.sample(points, 1.0).origin, Vector3(10.0, 0.0, 0.0))
	assert_almost_eq(Viewpoints.sample(points, 0.5).origin.x, 5.0, 0.0001)
	assert_eq(Viewpoints.sample(points, 7.0).origin, Vector3(10.0, 0.0, 0.0), "t est borné à 1")


func test_budget_check_passes_and_fails() -> void:
	var budgets: Dictionary = {"frame_p99_ms": {"max": 16.6}, "fps_1pct_low": {"min": 60.0}}
	assert_eq(PerfBudget.check({"frame_p99_ms": 10.0, "fps_1pct_low": 90.0}, budgets).size(), 0)
	assert_eq(PerfBudget.check({"frame_p99_ms": 20.0, "fps_1pct_low": 90.0}, budgets).size(), 1)
	assert_eq(PerfBudget.check({"frame_p99_ms": 20.0, "fps_1pct_low": 30.0}, budgets).size(), 2)
	assert_eq(PerfBudget.check({"frame_p99_ms": 10.0}, budgets).size(), 1, "une métrique absente est un échec")
	assert_eq(PerfBudget.check({}, {}).size(), 1, "l'absence de budget est un échec")


func test_project_budgets_reference_known_metrics() -> void:
	var budgets: Dictionary = JsonData.get_dictionary(JsonData.load_dictionary("res://tests/perf/budgets/sandbox.json"), "budgets", "test")
	var known: PackedStringArray = [
		"frames",
		"frame_avg_ms",
		"frame_p50_ms",
		"frame_p95_ms",
		"frame_p99_ms",
		"frame_max_ms",
		"fps_avg",
		"fps_1pct_low",
		"cpu_avg_ms",
		"cpu_p99_ms",
		"gpu_avg_ms",
		"gpu_p99_ms",
		"draw_calls_avg",
		"draw_calls_max",
		"primitives_max",
		"video_mem_mb_max",
		"static_mem_mb_max",
	]
	for key: Variant in budgets:
		assert_true(known.has(str(key)), "métrique de budget inconnue : %s" % key)
