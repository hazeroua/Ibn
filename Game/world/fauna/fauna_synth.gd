class_name FaunaSynth
extends RefCounted
## Synthèse des sons d'ambiance de la faune (chants d'oiseaux, criquets, appel de rapace) à partir des réglages de
## fauna.json : aucune ressource à télécharger, résultat déterministe (graine des données). Les sons sont fabriqués
## une seule fois, au démarrage, dans un fil de travail ; ensuite seul le volume des lecteurs change.
## Les boucles de criquets sont exactement périodiques (toutes les fréquences contiennent un nombre entier de cycles
## par boucle) : aucun clic au rebouclage. Les phrases d'oiseaux restent dans la boucle : aucun chevauchement.

const SILENCE_MARGIN_S: float = 0.5


## Son de la source (kind : birdsong, crickets, raptor_call). Renvoie null (avec erreur) si le type ou un réglage est invalide.
static func build(kind: String, synth: Dictionary, mix_rate: int, context: String) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = JsonData.get_int(synth, "seed", context)
	var samples: PackedFloat32Array
	var looped: bool = true
	match kind:
		"birdsong":
			samples = _birdsong(rng, synth, mix_rate, context)
		"crickets":
			samples = _crickets(rng, synth, mix_rate, context)
		"raptor_call":
			samples = _raptor_call(synth, mix_rate, context)
			looped = false
		_:
			push_error("FaunaSynth : type de son inconnu « %s » (%s)." % [kind, context])
			return null
	if samples.is_empty():
		return null
	return _to_stream(samples, mix_rate, looped)


static func _to_stream(samples: PackedFloat32Array, mix_rate: int, looped: bool) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for index: int in samples.size():
		data.encode_s16(index * 2, int(clampf(samples[index], -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = mix_rate
	stream.stereo = false
	stream.data = data
	if looped:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = samples.size()
	return stream


## Une note : sifflement dont la fréquence glisse de start_hz à end_hz, avec un harmonique, enveloppe en arche.
static func _write_note(
	samples: PackedFloat32Array, begin: int, length: int, start_hz: float, end_hz: float, harmonic: float, amplitude: float, mix_rate: int
) -> void:
	var phase: float = 0.0
	var last: int = mini(begin + length, samples.size())
	for index: int in range(begin, last):
		var t: float = float(index - begin) / float(length)
		var frequency: float = lerpf(start_hz, end_hz, t)
		phase += TAU * frequency / float(mix_rate)
		var envelope: float = pow(sin(PI * t), 0.7)
		samples[index] += (sin(phase) + harmonic * sin(2.0 * phase)) * envelope * amplitude / (1.0 + harmonic)


static func _birdsong(rng: RandomNumberGenerator, synth: Dictionary, mix_rate: int, context: String) -> PackedFloat32Array:
	var loop_s: float = JsonData.get_float(synth, "loop_s", context)
	var phrases: int = JsonData.get_int(synth, "phrases", context)
	var notes_min: int = JsonData.get_int(synth, "notes_min", context)
	var notes_max: int = JsonData.get_int(synth, "notes_max", context)
	var note_min: float = JsonData.get_float(synth, "note_s_min", context)
	var note_max: float = JsonData.get_float(synth, "note_s_max", context)
	var gap: float = JsonData.get_float(synth, "gap_s", context)
	var freq_min: float = JsonData.get_float(synth, "freq_hz_min", context)
	var freq_max: float = JsonData.get_float(synth, "freq_hz_max", context)
	var sweep: float = JsonData.get_float(synth, "sweep_max_hz", context)
	var harmonic: float = JsonData.get_float(synth, "harmonic", context)
	var amplitude: float = JsonData.get_float(synth, "amplitude", context)
	var longest_phrase: float = float(notes_max) * (note_max + gap)
	if loop_s <= 0.0 or phrases < 1 or notes_min < 1 or notes_max < notes_min or note_max < note_min or freq_max <= freq_min:
		push_error("FaunaSynth : réglages de chant invalides (%s)." % context)
		return PackedFloat32Array()
	if float(phrases) * longest_phrase + SILENCE_MARGIN_S > loop_s:
		push_error("FaunaSynth : les phrases ne tiennent pas dans la boucle de %.1f s (%s)." % [loop_s, context])
		return PackedFloat32Array()
	var samples := PackedFloat32Array()
	samples.resize(int(loop_s * float(mix_rate)))
	# Chaque phrase dispose de sa propre tranche de la boucle : jamais de chevauchement ni de débordement.
	var slot: float = loop_s / float(phrases)
	for phrase: int in phrases:
		var cursor: float = float(phrase) * slot + rng.randf() * maxf(slot - longest_phrase - SILENCE_MARGIN_S / float(phrases), 0.0)
		var base: float = rng.randf_range(freq_min, freq_max)
		for _note: int in rng.randi_range(notes_min, notes_max):
			var length_s: float = rng.randf_range(note_min, note_max)
			var start_hz: float = clampf(base + rng.randf_range(-sweep, sweep) * 0.5, freq_min, freq_max)
			var end_hz: float = clampf(start_hz + rng.randf_range(-sweep, sweep), freq_min, freq_max)
			_write_note(
				samples, int(cursor * float(mix_rate)), int(length_s * float(mix_rate)), start_hz, end_hz, harmonic, amplitude, mix_rate
			)
			cursor += length_s + gap
	return samples


static func _crickets(rng: RandomNumberGenerator, synth: Dictionary, mix_rate: int, context: String) -> PackedFloat32Array:
	var loop_s: float = JsonData.get_float(synth, "loop_s", context)
	var voices: int = JsonData.get_int(synth, "voices", context)
	var carrier_min: float = JsonData.get_float(synth, "carrier_hz_min", context)
	var carrier_max: float = JsonData.get_float(synth, "carrier_hz_max", context)
	var pulse_min: float = JsonData.get_float(synth, "pulse_hz_min", context)
	var pulse_max: float = JsonData.get_float(synth, "pulse_hz_max", context)
	var chirp_min: float = JsonData.get_float(synth, "chirp_hz_min", context)
	var chirp_max: float = JsonData.get_float(synth, "chirp_hz_max", context)
	var duty: float = JsonData.get_float(synth, "chirp_duty", context)
	var amplitude: float = JsonData.get_float(synth, "amplitude", context)
	if (
		loop_s <= 0.0
		or voices < 1
		or carrier_max <= carrier_min
		or pulse_max <= pulse_min
		or chirp_max <= chirp_min
		or duty <= 0.0
		or duty >= 1.0
	):
		push_error("FaunaSynth : réglages de criquets invalides (%s)." % context)
		return PackedFloat32Array()
	var length: int = int(loop_s * float(mix_rate))
	var samples := PackedFloat32Array()
	samples.resize(length)
	for _voice: int in voices:
		# Fréquences arrondies à un nombre entier de cycles par boucle : la boucle est parfaitement périodique.
		var carrier: float = roundf(rng.randf_range(carrier_min, carrier_max) * loop_s) / loop_s
		var pulse: float = roundf(rng.randf_range(pulse_min, pulse_max) * loop_s) / loop_s
		var chirp: float = maxf(roundf(rng.randf_range(chirp_min, chirp_max) * loop_s), 1.0) / loop_s
		var offset: float = rng.randf()
		for index: int in length:
			var t: float = float(index) / float(mix_rate)
			var burst_phase: float = fposmod(t * chirp + offset, 1.0)
			if burst_phase >= duty:
				continue
			var gate: float = sin(PI * burst_phase / duty)
			var pulse_wave: float = maxf(sin(TAU * pulse * t), 0.0)
			samples[index] += sin(TAU * carrier * t) * pulse_wave * pulse_wave * gate * amplitude / float(voices)
	return samples


static func _raptor_call(synth: Dictionary, mix_rate: int, context: String) -> PackedFloat32Array:
	var notes: int = JsonData.get_int(synth, "notes", context)
	var note_s: float = JsonData.get_float(synth, "note_s", context)
	var gap: float = JsonData.get_float(synth, "gap_s", context)
	var start_hz: float = JsonData.get_float(synth, "freq_hz_start", context)
	var end_hz: float = JsonData.get_float(synth, "freq_hz_end", context)
	var harmonic: float = JsonData.get_float(synth, "harmonic", context)
	var amplitude: float = JsonData.get_float(synth, "amplitude", context)
	if notes < 1 or note_s <= 0.0 or gap < 0.0 or start_hz <= 0.0 or end_hz <= 0.0:
		push_error("FaunaSynth : réglages d'appel de rapace invalides (%s)." % context)
		return PackedFloat32Array()
	var samples := PackedFloat32Array()
	samples.resize(int((float(notes) * (note_s + gap) + SILENCE_MARGIN_S) * float(mix_rate)))
	var cursor: float = 0.0
	for _note: int in notes:
		_write_note(samples, int(cursor * float(mix_rate)), int(note_s * float(mix_rate)), start_hz, end_hz, harmonic, amplitude, mix_rate)
		cursor += note_s + gap
	return samples
