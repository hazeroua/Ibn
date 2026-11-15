class_name WindNoise
extends RefCounted
## Synthèse du bruit du vent : bruit blanc filtré, en boucle parfaitement continue.
##
## Le son est produit une seule fois au démarrage (jamais pendant le jeu) à partir d'une graine
## fixe : le résultat est identique à chaque lancement, sans fichier à télécharger ni licence.
## Filtrage : deux passes basses du premier ordre en cascade (12 dB par octave) ; la bande
## [low_cutoff_hz, high_cutoff_hz] est la différence de deux passes basses. Le filtre parcourt la
## boucle deux fois (la première passe ne sert qu'à régler son état) : la jonction fin → début de
## la boucle est donc sans saut.

const PEAK: float = 0.9
const STAGES: int = 2


## Fabrique une boucle mono de 16 bits.
static func build_loop(seed_value: int, seconds: float, mix_rate: int, high_cutoff_hz: float, low_cutoff_hz: float) -> AudioStreamWAV:
	var count: int = int(seconds * float(mix_rate))
	var samples: PackedFloat32Array = build_samples(seed_value, count, mix_rate, high_cutoff_hz, low_cutoff_hz)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	for i: int in count:
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = mix_rate
	stream.stereo = false
	stream.data = bytes
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = count
	return stream


## Échantillons flottants, crête normalisée à PEAK.
static func build_samples(seed_value: int, count: int, mix_rate: int, high_cutoff_hz: float, low_cutoff_hz: float) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var noise := PackedFloat32Array()
	noise.resize(count)
	for i: int in count:
		noise[i] = rng.randf_range(-1.0, 1.0)
	var high_coef: float = _coefficient(high_cutoff_hz, mix_rate)
	var low_coef: float = _coefficient(low_cutoff_hz, mix_rate)
	var use_low: bool = low_cutoff_hz > 0.0
	var high_state: Array[float] = [0.0, 0.0]
	var low_state: Array[float] = [0.0, 0.0]
	var out := PackedFloat32Array()
	out.resize(count)
	var peak: float = 0.0
	for pass_index: int in 2:
		peak = 0.0
		for i: int in count:
			var x: float = noise[i]
			var high: float = x
			var low: float = x
			for stage: int in STAGES:
				high_state[stage] += high_coef * (high - high_state[stage])
				high = high_state[stage]
				if use_low:
					low_state[stage] += low_coef * (low - low_state[stage])
					low = low_state[stage]
			var y: float = high - low if use_low else high
			out[i] = y
			peak = maxf(peak, absf(y))
	if peak > 0.0:
		var gain: float = PEAK / peak
		for i: int in count:
			out[i] *= gain
	return out


static func _coefficient(cutoff_hz: float, mix_rate: int) -> float:
	if cutoff_hz <= 0.0:
		return 0.0
	return 1.0 - exp(-TAU * cutoff_hz / float(mix_rate))
