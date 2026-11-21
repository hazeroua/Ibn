class_name FrameStatistics
extends RefCounted
## Statistiques de temps d'image sans allocation pendant la mesure :
## histogramme préalloué par pas de 0,1 ms jusqu'à 200 ms (au-delà : dernière case).

const BIN_MS: float = 0.1
const BIN_COUNT: int = 2000
const FRAME_BUDGET_MS: float = 1000.0 / 60.0

var frame_count: int = 0
var total_ms: float = 0.0
var max_ms: float = 0.0
var frames_over_budget: int = 0
var _histogram: PackedInt32Array = PackedInt32Array()


func _init() -> void:
	_histogram.resize(BIN_COUNT)


func record(frame_ms: float) -> void:
	frame_count += 1
	total_ms += frame_ms
	max_ms = maxf(max_ms, frame_ms)
	if frame_ms > FRAME_BUDGET_MS:
		frames_over_budget += 1
	_histogram[clampi(int(frame_ms / BIN_MS), 0, BIN_COUNT - 1)] += 1


func average_ms() -> float:
	return total_ms / maxf(float(frame_count), 1.0)


## Borne supérieure de la case contenant le centile demandé (0 < fraction ≤ 1).
func percentile_ms(fraction: float) -> float:
	if frame_count == 0:
		return 0.0
	var target_count: int = maxi(ceili(float(frame_count) * fraction), 1)
	var cumulative_count: int = 0
	for index: int in BIN_COUNT:
		cumulative_count += _histogram[index]
		if cumulative_count >= target_count:
			return float(index + 1) * BIN_MS
	return float(BIN_COUNT) * BIN_MS


## Images par seconde équivalentes au 1 % des images les plus lentes.
func low_1_percent_fps() -> float:
	var slow_ms: float = percentile_ms(0.99)
	return 1000.0 / slow_ms if slow_ms > 0.0 else 0.0
