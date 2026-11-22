extends GutTest


func test_no_argument_opens_default_scene_without_measure() -> void:
	var options: LaunchOptions = LaunchOptions.parse(PackedStringArray())
	assert_true(options.errors.is_empty())
	assert_false(options.measure)
	assert_eq(options.scene_id, "")


func test_full_measure_command_line() -> void:
	var options: LaunchOptions = LaunchOptions.parse(
		PackedStringArray(["--measure", "--scene=terrain_test", "--duration=45", "--warmup=3", '--report-dir="C:/rapports/a b"'])
	)
	assert_true(options.errors.is_empty(), str(options.errors))
	assert_true(options.measure)
	assert_eq(options.scene_id, "terrain_test")
	assert_eq(options.duration_seconds, 45.0)
	assert_eq(options.warmup_seconds, 3.0)
	assert_eq(options.report_dir, "C:/rapports/a b")


func test_measure_requires_report_dir() -> void:
	var options: LaunchOptions = LaunchOptions.parse(PackedStringArray(["--measure"]))
	assert_eq(options.errors.size(), 1)


func test_report_dir_without_measure_is_rejected() -> void:
	var options: LaunchOptions = LaunchOptions.parse(PackedStringArray(["--report-dir=C:/x"]))
	assert_eq(options.errors.size(), 1)


func test_too_short_or_invalid_duration_is_rejected() -> void:
	assert_eq(LaunchOptions.parse(PackedStringArray(["--duration=2"])).errors.size(), 1)
	assert_eq(LaunchOptions.parse(PackedStringArray(["--duration=abc"])).errors.size(), 1)
	assert_eq(LaunchOptions.parse(PackedStringArray(["--warmup=-1"])).errors.size(), 1)


func test_unknown_argument_is_rejected() -> void:
	var options: LaunchOptions = LaunchOptions.parse(PackedStringArray(["--fast"]))
	assert_eq(options.errors.size(), 1)


func test_moment_option() -> void:
	var options: LaunchOptions = LaunchOptions.parse(PackedStringArray(["--moment=midi"]))
	assert_true(options.errors.is_empty())
	assert_eq(options.moment_id, "midi")
