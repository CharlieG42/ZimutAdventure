class_name SoundBank
extends RefCounted
## Banque de sons : chaque événement a un ou plusieurs enregistrements (CC0, voir
## assets/audio/CREDITS.md) tirés au hasard, ou un son de synthèse quand aucun
## enregistrement libre n'existe (vache, cheval, loup, poule, grillons).

const Synth := preload("res://scripts/audio/synth.gd")

const FILES := {
	"step_sand": ["steps/sand_0", "steps/sand_1", "steps/sand_2", "steps/sand_3", "steps/sand_4"],
	"step_grass": ["steps/grass_0", "steps/grass_1", "steps/grass_2", "steps/grass_3", "steps/grass_4"],
	"step_snow": ["steps/snow_0", "steps/snow_1", "steps/snow_2", "steps/snow_3", "steps/snow_4"],
	"step_water": ["steps/water_0", "steps/water_1", "steps/water_2"],
	"chop": ["actions/chop"],
	"hit": ["actions/hit_0", "actions/hit_1", "actions/hit_2"],
	"splash": ["actions/splash"],
	"bark": ["animals/dog_bark"],
	"baa": ["animals/sheep_baa"],
	"bird": ["animals/bird_chirp"],
}
## Boucles d'ambiance.
const LOOPS := {
	"wind": "ambience/wind",
	"rain": "ambience/rain",
	"river": "ambience/river",
}

static var _cache: Dictionary = {}
static var _synth: Dictionary = {}

## Un son pour l'événement (au hasard parmi ses enregistrements), ou null.
static func pick(event_name: String) -> AudioStream:
	var files: Array = FILES.get(event_name, [])
	if not files.is_empty():
		var stream := _load(String(files[randi() % files.size()]))
		if stream != null:
			return stream
	return synth(event_name)

## Nombre d'enregistrements disponibles pour l'événement (0 = synthèse).
static func recording_count(event_name: String) -> int:
	var count := 0
	for path in FILES.get(event_name, []):
		if _load(String(path)) != null:
			count += 1
	return count

## Boucle d'ambiance prête à jouer en continu.
static func loop(loop_name: String) -> AudioStream:
	if not LOOPS.has(loop_name):
		return null
	var stream := _load(String(LOOPS[loop_name]))
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	return stream

static func _load(path: String) -> AudioStream:
	if _cache.has(path):
		return _cache[path]
	var full := "res://assets/audio/%s.ogg" % path
	var stream: AudioStream = load(full) as AudioStream if ResourceLoader.exists(full) else null
	_cache[path] = stream
	return stream

## Sons de synthèse (mis en cache).
static func synth(event_name: String) -> AudioStream:
	if _synth.has(event_name):
		return _synth[event_name]
	var stream: AudioStream = null
	match event_name:
		"splash": stream = Synth.splash()
		"bite": stream = Synth.tone(520.0, 0.25, 0.005, 9.0, 0.6, -240.0)
		"harvest": stream = Synth.splash(0.18, 0.45)
		"chime": stream = Synth.tone(880.0, 0.9, 0.005, 3.5, 0.5)
		"treasure": stream = Synth.chord([523.0, 659.0, 784.0, 1046.0], 1.4, 1.2)
		"hit": stream = Synth.splash(0.12, 0.8)
		"chop": stream = Synth.splash(0.1, 0.9)
		"bark": stream = Synth.tone(300.0, 0.16, 0.004, 12.0, 0.7, -120.0)
		# Voix : contour de hauteur + timbre (formant) proche de l'animal.
		"moo": stream = Synth.voice([[0.0, 105.0], [0.35, 138.0], [0.9, 120.0], [1.25, 92.0]], 1.3, 650.0, 4.5, 0.012, 0.55)
		"baa": stream = Synth.voice([[0.0, 330.0], [0.2, 360.0], [0.7, 300.0]], 0.75, 1100.0, 9.0, 0.06, 0.45)
		"neigh": stream = Synth.voice([[0.0, 620.0], [0.15, 980.0], [0.75, 760.0], [1.1, 420.0]], 1.15, 1500.0, 17.0, 0.07, 0.4)
		"howl": stream = Synth.voice([[0.0, 330.0], [0.8, 590.0], [2.0, 540.0], [2.8, 300.0]], 2.9, 900.0, 4.8, 0.015, 0.45, 0.3)
		"cluck": stream = Synth.voice([[0.0, 520.0], [0.08, 610.0], [0.14, 480.0]], 0.15, 1800.0, 0.0, 0.0, 0.5)
		"bird": stream = Synth.tone(2700.0, 0.18, 0.004, 10.0, 0.5, 700.0)
	_synth[event_name] = stream
	return stream
