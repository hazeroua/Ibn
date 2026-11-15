extends GutTest
## Synthèse du bruit du vent : boucle continue, déterministe, normalisée.

const RATE: int = 22050


func test_loop_length_and_format() -> void:
	var stream: AudioStreamWAV = WindNoise.build_loop(7, 1.0, RATE, 800.0, 0.0)
	assert_eq(stream.data.size(), RATE * 2)
	assert_eq(stream.loop_mode, AudioStreamWAV.LOOP_FORWARD)
	assert_eq(stream.loop_end, RATE)


func test_deterministic() -> void:
	var a: PackedFloat32Array = WindNoise.build_samples(7, 4000, RATE, 800.0, 100.0)
	var b: PackedFloat32Array = WindNoise.build_samples(7, 4000, RATE, 800.0, 100.0)
	assert_eq(a, b)
	var c: PackedFloat32Array = WindNoise.build_samples(8, 4000, RATE, 800.0, 100.0)
	assert_ne(a, c)


func test_peak_is_normalised() -> void:
	var samples: PackedFloat32Array = WindNoise.build_samples(3, 8000, RATE, 2600.0, 450.0)
	var peak: float = 0.0
	for value: float in samples:
		peak = maxf(peak, absf(value))
	assert_almost_eq(peak, WindNoise.PEAK, 0.0001)


func test_loop_junction_has_no_jump() -> void:
	for cutoffs: Vector2 in [Vector2(180.0, 0.0), Vector2(2600.0, 450.0)]:
		var samples: PackedFloat32Array = WindNoise.build_samples(11, RATE, RATE, cutoffs.x, cutoffs.y)
		var junction: float = absf(samples[0] - samples[samples.size() - 1])
		var typical: float = 0.0
		for i: int in range(1, samples.size()):
			typical = maxf(typical, absf(samples[i] - samples[i - 1]))
		assert_lte(junction, typical, "la jonction ne dépasse pas le plus grand écart ordinaire (%s)" % str(cutoffs))


func test_low_layer_is_darker_than_high_layer() -> void:
	var low: PackedFloat32Array = WindNoise.build_samples(5, RATE, RATE, 180.0, 0.0)
	var high: PackedFloat32Array = WindNoise.build_samples(5, RATE, RATE, 2600.0, 450.0)
	assert_lt(_roughness(low), _roughness(high))


func _roughness(samples: PackedFloat32Array) -> float:
	var total: float = 0.0
	for i: int in range(1, samples.size()):
		total += absf(samples[i] - samples[i - 1])
	return total / float(samples.size())
