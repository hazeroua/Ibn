extends GutTest


func test_empty_statistics_are_zero() -> void:
	var statistics: FrameStatistics = FrameStatistics.new()
	assert_eq(statistics.frame_count, 0)
	assert_eq(statistics.average_ms(), 0.0)
	assert_eq(statistics.percentile_ms(0.99), 0.0)


func test_average_max_and_over_budget() -> void:
	var statistics: FrameStatistics = FrameStatistics.new()
	for frame_ms: float in [10.0, 12.0, 20.0, 14.0]:
		statistics.record(frame_ms)
	assert_eq(statistics.frame_count, 4)
	assert_almost_eq(statistics.average_ms(), 14.0, 0.0001)
	assert_eq(statistics.max_ms, 20.0)
	assert_eq(statistics.frames_over_budget, 1)


func test_p99_catches_the_slowest_percent() -> void:
	var statistics: FrameStatistics = FrameStatistics.new()
	for index: int in 990:
		statistics.record(8.0)
	for index: int in 10:
		statistics.record(30.0)
	assert_almost_eq(statistics.percentile_ms(0.99), 8.1, 0.0001)
	assert_almost_eq(statistics.percentile_ms(0.995), 30.1, 0.0001)
	assert_almost_eq(statistics.low_1_percent_fps(), 1000.0 / 8.1, 0.001)


func test_extreme_frame_lands_in_last_bin() -> void:
	var statistics: FrameStatistics = FrameStatistics.new()
	statistics.record(5000.0)
	assert_eq(statistics.max_ms, 5000.0)
	assert_almost_eq(statistics.percentile_ms(1.0), FrameStatistics.BIN_COUNT * FrameStatistics.BIN_MS, 0.0001)
