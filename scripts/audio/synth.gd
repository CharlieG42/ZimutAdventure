extends RefCounted
## Sons de synthèse (aucun fichier audio) : bruits filtrés, notes et trilles, en 16 bits mono.

const RATE := 22050

static func _to_wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = bytes
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	return wav

## Bruit passe-bas bouclable (pluie, vent). `smooth` proche de 1 = plus grave.
static func noise(seconds: float, smooth: float, gain: float, loop: bool = true) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var count := int(seconds * RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var last := 0.0
	for i in count:
		last = last * smooth + rng.randf_range(-1.0, 1.0) * (1.0 - smooth)
		samples[i] = last * gain
	if loop:
		# Fondu aux extrémités pour un raccord sans clic.
		var fade := mini(count / 8, 800)
		for i in fade:
			var t := float(i) / float(fade)
			samples[i] *= t
			samples[count - 1 - i] *= t
	return _to_wav(samples, loop)

## Une note : sinus (+ harmonique) avec attaque et déclin exponentiel.
static func tone(freq: float, seconds: float, attack: float = 0.01, decay: float = 4.0, gain: float = 0.5, glide: float = 0.0) -> AudioStreamWAV:
	var count := int(seconds * RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var phase := 0.0
	for i in count:
		var t := float(i) / float(RATE)
		var f := freq + glide * t / maxf(seconds, 0.001)
		phase += TAU * f / float(RATE)
		var env := minf(t / maxf(attack, 0.001), 1.0) * exp(-decay * t)
		samples[i] = (sin(phase) + 0.25 * sin(phase * 2.0)) * env * gain
	return _to_wav(samples, false)

## Accord (plusieurs notes) : nappe douce pour la musique d'ambiance.
static func chord(freqs: Array, seconds: float, gain: float = 0.3) -> AudioStreamWAV:
	var count := int(seconds * RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for freq in freqs:
		var phase := 0.0
		for i in count:
			var t := float(i) / float(RATE)
			phase += TAU * float(freq) / float(RATE)
			var env := sin(PI * t / seconds)
			samples[i] += sin(phase) * env * env * gain / float(freqs.size())
	return _to_wav(samples, false)

## Trille rapide (grillon) : porteuse aiguë hachée.
static func trill(freq: float, seconds: float, rate: float, gain: float = 0.3) -> AudioStreamWAV:
	var count := int(seconds * RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var phase := 0.0
	for i in count:
		var t := float(i) / float(RATE)
		phase += TAU * freq / float(RATE)
		var gate := maxf(0.0, sin(TAU * rate * t))
		samples[i] = sin(phase) * gate * sin(PI * t / seconds) * gain
	return _to_wav(samples, false)

## Éclaboussure : bruit bref à enveloppe descendante.
static func splash(seconds: float = 0.35, gain: float = 0.6) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var count := int(seconds * RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var last := 0.0
	for i in count:
		var t := float(i) / float(count)
		last = last * 0.55 + rng.randf_range(-1.0, 1.0) * 0.45
		samples[i] = last * pow(1.0 - t, 2.0) * gain
	return _to_wav(samples, false)

## Voix d'animal : contour de hauteur `points` ([[t, f], ...] en secondes et Hz), son riche
## en harmoniques filtré autour d'un formant, vibrato, attaque et relâche douces.
## `breath` ajoute un souffle (bruit) ; utile au hurlement.
static func voice(points: Array, seconds: float, formant: float, vibrato_hz: float, vibrato_depth: float,
		gain: float = 0.5, breath: float = 0.1) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 91
	var count := int(seconds * RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var phase := 0.0
	var noise := 0.0
	for i in count:
		var t := float(i) / float(RATE)
		var f := _contour(points, t)
		f *= 1.0 + vibrato_depth * sin(TAU * vibrato_hz * t)
		phase += TAU * f / float(RATE)
		var value := 0.0
		var harmonics := mini(14, int(5000.0 / maxf(f, 50.0)))
		for h in range(1, harmonics + 1):
			var hf := f * float(h)
			# Résonance autour du formant : les harmoniques proches sonnent plus fort.
			var weight := 1.0 / float(h) * (0.3 + exp(-pow((hf - formant) / (formant * 0.45), 2.0)))
			value += sin(phase * float(h)) * weight
		noise = noise * 0.7 + rng.randf_range(-1.0, 1.0) * 0.3
		value = value * 0.6 + noise * breath
		var env := minf(t / 0.06, 1.0) * minf((seconds - t) / 0.15, 1.0)
		samples[i] = value * env * gain
	return _to_wav(samples, false)

static func _contour(points: Array, t: float) -> float:
	if points.is_empty():
		return 200.0
	if t <= float(points[0][0]):
		return float(points[0][1])
	for k in range(1, points.size()):
		var a: Array = points[k - 1]
		var b: Array = points[k]
		if t <= float(b[0]):
			var u := (t - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.001)
			return lerpf(float(a[1]), float(b[1]), smoothstep(0.0, 1.0, u))
	return float(points[points.size() - 1][1])
