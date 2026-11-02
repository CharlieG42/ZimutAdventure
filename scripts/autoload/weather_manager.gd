extends Node
## Saisons et météo. Une saison dure SEASON_DAYS jours de jeu ; la météo change toutes les
## six heures de jeu, de façon déterministe (même jour et même créneau = même temps), ce qui
## la rend testable et identique d'une session à l'autre. Elle assombrit la lumière, ajoute de
## la brume, fait tomber pluie ou neige autour du joueur, arrose les cultures et pèse sur la
## faim et la soif. Le jour courant est sauvegardé dans user://weather.cfg.

signal weather_changed(weather: String)
signal season_changed(season: String)

const SAVE_PATH := "user://weather.cfg"
const SEASON_DAYS := 6
const SEASONS := ["spring", "summer", "autumn", "winter"]
const CLEAR := "clear"
const CLOUDY := "cloudy"
const RAIN := "rain"
const SNOW := "snow"

## Probabilités cumulées par saison : [clair, nuageux, précipitations].
const ODDS := {
	"spring": [0.45, 0.70],
	"summer": [0.72, 0.90],
	"autumn": [0.30, 0.60],
	"winter": [0.40, 0.70],
}
## Aspect du ciel : assombrissement et brume visés selon le temps.
const LOOK := {
	CLEAR: [0.0, 0.0],
	CLOUDY: [0.25, 0.25],
	RAIN: [0.55, 0.8],
	SNOW: [0.4, 0.7],
}
## Teinte appliquée à la lumière selon la saison.
const SEASON_TINT := {
	"spring": Color(1.0, 1.0, 1.0),
	"summer": Color(1.05, 1.0, 0.92),
	"autumn": Color(1.04, 0.93, 0.82),
	"winter": Color(0.86, 0.93, 1.05),
}
## Vitesse de pousse des cultures selon la saison.
## Teinte du feuillage et intensité selon la saison : [couleur, force].
const FOLIAGE := {
	"spring": [Color(0.5, 0.85, 0.3), 0.18],
	"summer": [Color(0.4, 0.6, 0.2), 0.0],
	"autumn": [Color(0.88, 0.5, 0.14), 0.7],
	"winter": [Color(0.55, 0.5, 0.42), 0.45],
}
## Neige au sol visée selon la saison (la neige qui tombe l'épaissit).
const SNOW_GROUND := {"spring": 0.0, "summer": 0.0, "autumn": 0.0, "winter": 0.8}

const CROP_FACTOR := {"spring": 1.15, "summer": 1.0, "autumn": 0.9, "winter": 0.5}
const THIRST_FACTOR := {"spring": 1.0, "summer": 1.3, "autumn": 1.0, "winter": 0.85}
const HUNGER_FACTOR := {"spring": 1.0, "summer": 1.0, "autumn": 1.0, "winter": 1.25}

var _day: int = 0
var _weather: String = CLEAR
var _season: String = "spring"
var _snow: float = 0.0
var _wet: float = 0.0
var _tint: Color = Color(0.4, 0.6, 0.2)
var _tint_amount: float = 0.0
var _dim: float = 0.0
var _fog: float = 0.0
var _autosave: bool = DisplayServer.get_name() != "headless"
# Les tests headless doivent rester déterministes : pas d'effets de saison ni de météo.
var _effects: bool = DisplayServer.get_name() != "headless"
var _particles: CPUParticles3D
## Qualité réduite (appareil lent) : moitié moins de gouttes et de flocons.
var low_quality: bool = false
var _particles_kind: String = ""
var _elapsed_save: float = 0.0

func _ready() -> void:
	_load()
	var clock := _clock()
	if clock != null:
		clock.connect("day_changed", _on_day_changed)
		_day = maxi(_day, int(clock.get("day")))
		clock.set("day", _day)
	_season = season_for(_day)
	_weather = _current_target()
	_dim = float(LOOK[_weather][0])
	_fog = float(LOOK[_weather][1])
	_build_particles()
	_refresh_particles()
	if _effects:
		snap_surfaces()

func _clock() -> Node:
	return get_node_or_null("/root/DayNightCycle")

# --- Calendrier ---------------------------------------------------------------------------

func season_for(day: int) -> String:
	return SEASONS[(maxi(day, 0) / SEASON_DAYS) % SEASONS.size()]

func get_day() -> int:
	return _day

func get_season() -> String:
	return _season

## Jour dans la saison (1 à SEASON_DAYS).
func get_day_in_season() -> int:
	return (maxi(_day, 0) % SEASON_DAYS) + 1

func get_weather() -> String:
	return _weather

## Les saisons et la météo sont actives (désactivées dans les tests headless).
func effects_active() -> bool:
	return _effects

func is_raining() -> bool:
	return _effects and _weather == RAIN

# --- Météo déterministe ----------------------------------------------------------------------

## Temps prévu pour un jour et un créneau de six heures (0 à 3).
func weather_for(day: int, slot: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("weather:%d:%d" % [day, slot])
	var roll := rng.randf()
	var season := season_for(day)
	var odds: Array = ODDS[season]
	if roll < float(odds[0]):
		return CLEAR
	if roll < float(odds[1]):
		return CLOUDY
	return SNOW if season == "winter" else RAIN

func _current_target() -> String:
	var clock := _clock()
	var hour := float(clock.get("hour")) if clock != null else 12.0
	return weather_for(_day, clampi(int(hour / 6.0), 0, 3))

# --- Effets ---------------------------------------------------------------------------------------

func crop_factor() -> float:
	return float(CROP_FACTOR[_season]) if _effects else 1.0

func thirst_factor() -> float:
	if not _effects:
		return 1.0
	var factor: float = THIRST_FACTOR[_season]
	return factor * (0.8 if _weather == RAIN else 1.0)

func hunger_factor() -> float:
	return float(HUNGER_FACTOR[_season]) if _effects else 1.0

## API de test : active les effets de saison et de météo malgré le mode headless.
func enable_effects_for_test(day: int) -> void:
	_effects = true
	_snow = 0.0
	_wet = 0.0
	_tint_amount = 0.0
	_autosave = false
	_day = day
	_season = season_for(day)
	_weather = _current_target()

func clear_for_test() -> void:
	_effects = false
	_autosave = false
	_day = 0
	_season = "spring"
	_weather = CLEAR

# --- Boucle -----------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	var clock := _clock()
	if clock == null:
		return
	if not _effects:
		return
	var target := _current_target()
	if target != _weather:
		_weather = target
		_refresh_particles()
		weather_changed.emit(_weather)
		_announce_weather()
	var look: Array = LOOK[_weather]
	_dim = move_toward(_dim, float(look[0]), 0.25 * delta)
	_fog = move_toward(_fog, float(look[1]), 0.25 * delta)
	clock.set("weather_dim", _dim)
	clock.set("weather_fog", _fog)
	clock.set("season_tint", SEASON_TINT[_season])
	_update_surfaces(delta)
	_follow_player()
	_elapsed_save += delta
	if _elapsed_save > 10.0:
		_elapsed_save = 0.0
		_save()

## Neige, humidité et teinte du feuillage rejoignent doucement leur cible (variables globales des shaders).
func _update_surfaces(delta: float) -> void:
	var snow_target: float = SNOW_GROUND[_season] + (0.2 if _weather == SNOW else 0.0)
	var wet_target := 1.0 if _weather == RAIN else (0.35 if _weather == CLOUDY and _wet > 0.35 else 0.0)
	var foliage: Array = FOLIAGE[_season]
	_snow = move_toward(_snow, snow_target, 0.06 * delta)
	_wet = move_toward(_wet, wet_target, 0.12 * delta)
	_tint = _tint.lerp(foliage[0], clampf(0.5 * delta, 0.0, 1.0))
	_tint_amount = move_toward(_tint_amount, float(foliage[1]), 0.05 * delta)
	_push_surfaces()

func _push_surfaces() -> void:
	RenderingServer.global_shader_parameter_set("snow_amount", _snow)
	RenderingServer.global_shader_parameter_set("wetness", _wet)
	RenderingServer.global_shader_parameter_set("foliage_tint", _tint)
	RenderingServer.global_shader_parameter_set("foliage_tint_amount", _tint_amount)

## Apparence immédiate des surfaces pour la saison et le temps courants (chargement, tests, captures).
func snap_surfaces() -> void:
	_snow = float(SNOW_GROUND[_season]) + (0.2 if _weather == SNOW else 0.0)
	_wet = 1.0 if _weather == RAIN else 0.0
	_tint = FOLIAGE[_season][0]
	_tint_amount = float(FOLIAGE[_season][1])
	_push_surfaces()

func get_snow_amount() -> float:
	return _snow

func get_wetness() -> float:
	return _wet

func get_foliage_tint_amount() -> float:
	return _tint_amount

func _on_day_changed(day: int) -> void:
	_day = day
	var season := season_for(day)
	if season != _season:
		_season = season
		season_changed.emit(season)
		_toast(tr("TOAST_SEASON") % tr("SEASON_" + season.to_upper()))
		var progression := InteractionManager.get_progression()
		if progression != null and _effects:
			progression.call("add_stat", "stat_seasons", 1)
	_save()

func _announce_weather() -> void:
	if _weather == RAIN:
		_toast(tr("TOAST_RAIN"))
	elif _weather == SNOW:
		_toast(tr("TOAST_SNOW"))

func _toast(message: String) -> void:
	var tree := get_tree()
	if tree == null or not _effects:
		return
	var hud := tree.get_first_node_in_group("hud") as Node
	if hud != null and hud.has_method("show_toast"):
		hud.show_toast(message, 2.4)

# --- Précipitations -------------------------------------------------------------------------------------

func _build_particles() -> void:
	_particles = CPUParticles3D.new()
	_particles.name = "Precipitation"
	_particles.emitting = false
	_particles.local_coords = false
	_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_particles.emission_box_extents = Vector3(13.0, 0.5, 13.0)
	_particles.direction = Vector3.DOWN
	_particles.spread = 0.0
	_particles.visibility_aabb = AABB(Vector3(-25, -20, -25), Vector3(50, 40, 50))
	add_child(_particles)

func set_low_quality(value: bool) -> void:
	if low_quality == value:
		return
	low_quality = value
	_particles_kind = "-"
	_refresh_particles()

func _refresh_particles() -> void:
	if _particles == null:
		return
	var kind := _weather if (_effects and (_weather == RAIN or _weather == SNOW)) else ""
	if kind == _particles_kind:
		return
	_particles_kind = kind
	_particles.emitting = kind != ""
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if kind == RAIN:
		var streak := BoxMesh.new()
		streak.size = Vector3(0.016, 0.7, 0.016)
		material.albedo_color = Color(0.8, 0.88, 1.0, 0.65)
		streak.material = material
		_particles.mesh = streak
		_particles.amount = 600 if low_quality else 1200
		_particles.lifetime = 0.9
		_particles.initial_velocity_min = 18.0
		_particles.initial_velocity_max = 22.0
		_particles.gravity = Vector3(0.0, -10.0, 0.0)
	elif kind == SNOW:
		var flake := SphereMesh.new()
		flake.radius = 0.07
		flake.height = 0.14
		flake.radial_segments = 4
		flake.rings = 2
		material.albedo_color = Color(1.0, 1.0, 1.0, 0.9)
		flake.material = material
		_particles.mesh = flake
		_particles.amount = 320 if low_quality else 650
		_particles.lifetime = 5.0
		_particles.initial_velocity_min = 1.0
		_particles.initial_velocity_max = 2.0
		_particles.gravity = Vector3(0.4, -0.6, 0.2)

func _follow_player() -> void:
	if _particles == null or not _particles.emitting:
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player != null:
		_particles.global_position = player.global_position + Vector3(0.0, 12.0, 0.0)

# --- Sauvegarde ------------------------------------------------------------------------------------------

func _load() -> void:
	if not _autosave:
		return
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) == OK:
		_day = maxi(0, int(config.get_value("calendar", "day", 0)))

func _save() -> void:
	if not _autosave:
		return
	var config := ConfigFile.new()
	config.set_value("calendar", "day", _day)
	config.save(SAVE_PATH)
