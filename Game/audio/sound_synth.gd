class_name SoundSynth
extends RefCounted
## Sons de pas synthétisés à partir des réglages du manifeste (res://data/assets/sounds.json, section « synthesized »).
## Déterministes (graine du manifeste), calculés une fois au chargement : aucune ressource à télécharger.
##
## Pas dans l'eau : une gerbe de bruit filtré (passe-bas à un pôle) à attaque rapide et décroissance exponentielle,
## plus quelques bulles (sinusoïdes dont la fréquence monte) qui donnent le « plouf ».

const TWO_PI: float = TAU
const CONTEXT: String = "sounds.json > synthesized"


## Son de pas dans l'eau (16 bits, mono) selon les réglages params.
static func water_step(params: Dictionary, id: String) -> AudioStreamWAV:
	var context: String = "%s > %s" % [CONTEXT, id]
	var rate: int = JsonData.get_int(params, "mix_rate", context)
	var duration: float = JsonData.get_float(params, "duration_s", context)
	var cutoff: float = JsonData.get_float(params, "noise_cutoff_hz", context)
	var attack: float = JsonData.get_float(params, "attack_s", context)
	var decay: float = JsonData.get_float(params, "decay_s", context)
	var bubbles: int = JsonData.get_int(params, "bubble_count", context)
	var freq_min: float = JsonData.get_float(params, "bubble_freq_min_hz", context)
	var freq_max: float = JsonData.get_float(params, "bubble_freq_max_hz", context)
	var rise: float = JsonData.get_float(params, "bubble_rise", context)
	var bubble_length: float = JsonData.get_float(params, "bubble_length_s", context)
	var bubble_gain: float = JsonData.get_float(params, "bubble_gain", context)
	var gain: float = JsonData.get_float(params, "gain", context)
	if (
		rate < 8000
		or duration <= 0.0
		or cutoff <= 0.0
		or attack <= 0.0
		or decay <= 0.0
		or bubble_length <= 0.0
		or gain <= 0.0
		or bubbles < 0
	):
		push_error("SoundSynth : réglages incohérents (%s)." % context)
		return null
	var count: int = int(duration * float(rate))
	var rng := RandomNumberGenerator.new()
	rng.seed = JsonData.get_int(params, "seed", context)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var alpha: float = 1.0 - exp(-TWO_PI * cutoff / float(rate))
	var filtered: float = 0.0
	for i: int in count:
		var t: float = float(i) / float(rate)
		filtered += alpha * (rng.randf_range(-1.0, 1.0) - filtered)
		samples[i] = filtered * (1.0 - exp(-t / attack)) * exp(-t / decay)
	for _bubble: int in bubbles:
		var start: int = int(rng.randf_range(0.01, duration * 0.5) * float(rate))
		var base: float = rng.randf_range(freq_min, freq_max)
		var length: int = int(bubble_length * float(rate))
		var phase: float = 0.0
		for k: int in length:
			if start + k >= count:
				break
			var u: float = float(k) / float(length)
			phase += TWO_PI * base * (1.0 + rise * u) / float(rate)
			samples[start + k] += sin(phase) * pow(sin(PI * u), 2.0) * bubble_gain
	var peak: float = 0.0001
	for value: float in samples:
		peak = maxf(peak, absf(value))
	var data := PackedByteArray()
	data.resize(count * 2)
	for i: int in count:
		data.encode_s16(i * 2, int(clampf(samples[i] / peak * gain, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = data
	return stream
