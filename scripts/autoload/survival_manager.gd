extends Node
## Survie : faim et soif décroissent avec le temps. Une jauge vide pénalise
## l'endurance (régénération réduite, course impossible si les deux sont vides).
## Chaleur corporelle : la température ressentie dépend de la saison, de l'heure, de la
## météo, de l'altitude et d'être mouillé ; feu, abri et cape réchauffent. Sous 6 °C la
## jauge de chaleur baisse ; vide, elle coûte de la santé. Au-delà de 32 °C on a plus soif.
## Sauvegarde dans user://survival.cfg.

signal needs_changed(hunger: float, thirst: float)
signal health_changed(health: float)
signal died
signal warmth_changed(warmth: float, felt_temperature: float)

const SAVE_NAME := "survival.cfg"
## Plein -> vide, en minutes réelles de jeu.
const HUNGER_EMPTY_MINUTES := 30.0
const THIRST_EMPTY_MINUTES := 20.0
## pénalité d'endurance quand une jauge est vide (0 = aucune régénération).
const STAMINA_REGEN_MIN := 0.25

@export_group("Vitesses (par seconde)")
@export var hunger_drain: float = 1.0 / (HUNGER_EMPTY_MINUTES * 60.0)
@export var thirst_drain: float = 1.0 / (THIRST_EMPTY_MINUTES * 60.0)
## La course accélère la faim et la soif.
@export var sprint_multiplier: float = 2.5

## Régénération de santé (par seconde) quand la faim et la soif sont correctes.
const HEALTH_REGEN := 0.004
## Une cape de fourrure réduit les dégâts reçus.
const CLOAK_ITEM := "armor_fur_cloak"
const CLOAK_REDUCTION := 0.35

# --- Température -------------------------------------------------------------------------
const BASE_TEMPERATURE := {"spring": 16.0, "summer": 27.0, "autumn": 12.0, "winter": 1.0}
## Écart jour / nuit : le plus chaud à 15 h, le plus froid à 3 h.
const DAY_SWING := 7.0
const WEATHER_TEMPERATURE := {"clear": 0.0, "cloudy": -2.0, "rain": -5.0, "snow": -6.0}
## Sous ce ressenti on se refroidit ; au-dessus de WARM_AT on se réchauffe.
const COLD_AT := 6.0
const WARM_AT := 12.0
const HOT_AT := 32.0
## Ressenti très froid (COLD_AT - 14 °C) : chaleur pleine -> vide en 3 minutes.
const CHILL_SECONDS := 180.0
## Près d'un feu, on se réchauffe complètement en 20 s ; ailleurs en 90 s.
const FIRE_WARM_SECONDS := 20.0
const WARM_SECONDS := 90.0
const FIRE_HEAT := 16.0
const FIRE_RADIUS := 7.0
const SHELTER_HEAT := 9.0
const SHELTER_RADIUS := 4.5
const CLOAK_HEAT := 7.0
const WET_CHILL := 6.0
## Mouillé : sèche en une minute (quatre fois plus vite près d'un feu).
const DRY_SECONDS := 60.0
const COLD_DAMAGE := 0.004
const HOT_THIRST := 1.4

var _warmth: float = 1.0
var _wet: float = 0.0
var _felt: float = 18.0
var _cold_hint_shown: bool = false

var _health: float = 1.0
var _hunger: float = 1.0
var _thirst: float = 1.0
var _autosave: bool = DisplayServer.get_name() != "headless"
var _sprinting: bool = false
var _elapsed_save: float = 0.0

func _ready() -> void:
	_load()
	var player := get_tree().get_first_node_in_group("player")
	if player != null and player.has_signal("stamina_changed"):
		_connect_player(player)
	_reemit()
	health_changed.emit(_health)

func reload_from_disk() -> void:
	_hunger = 1.0
	_thirst = 1.0
	_health = 1.0
	_warmth = 1.0
	_wet = 0.0
	_cold_hint_shown = false
	_load()
	_reemit()
	health_changed.emit(_health)

func _connect_player(player: Node) -> void:
	if player.has_method("is_sprinting"):
		player.call_deferred("set_meta", "survival_bound", true)
	if player.has_signal("stamina_changed"):
		player.connect("stamina_changed", _on_stamina)

func _process(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player")
	var sprinting: bool = player != null and player.has_method("is_sprinting") and bool(player.call("is_sprinting"))
	var rate := sprint_multiplier if sprinting else 1.0
	var weather := InteractionManager.get_weather()
	var hunger_weather := float(weather.call("hunger_factor")) if weather != null else 1.0
	var thirst_weather := float(weather.call("thirst_factor")) if weather != null else 1.0
	var exploration := InteractionManager.get_exploration()
	var blessed := float(exploration.call("drain_factor")) if exploration != null else 1.0
	update_temperature(delta, _gather_context(player as Node3D))
	var heat := HOT_THIRST if is_hot() else 1.0
	_hunger = maxf(0.0, _hunger - hunger_drain * rate * hunger_weather * blessed * delta)
	_thirst = maxf(0.0, _thirst - thirst_drain * rate * thirst_weather * blessed * heat * delta)
	_reemit()
	if _warmth <= 0.0 and _health > 0.0:
		damage(COLD_DAMAGE * delta)
	elif _health < 1.0 and _health > 0.0 and _hunger > 0.25 and _thirst > 0.25 and _warmth > 0.25:
		heal(HEALTH_REGEN * delta)
	_elapsed_save += delta
	if _elapsed_save > 5.0:
		_elapsed_save = 0.0
		_save()

func _reemit() -> void:
	needs_changed.emit(_hunger, _thirst)

# --- Température ------------------------------------------------------------------------

## Température de l'air (°C) : saison, heure, météo et altitude (-1 °C tous les 4 m au-dessus
## de la plaine).
static func air_temperature(season: String, hour: float, weather: String, altitude: float) -> float:
	var t := float(BASE_TEMPERATURE.get(season, 16.0))
	t += DAY_SWING * cos((hour - 15.0) / 24.0 * TAU)
	t += float(WEATHER_TEMPERATURE.get(weather, 0.0))
	# Nuit claire : la chaleur s'échappe.
	if weather == "clear" and (hour < 6.0 or hour > 21.0):
		t -= 2.0
	return t - maxf(0.0, altitude - 4.0) * 0.25

## Ressenti à partir du contexte : {season, hour, weather, altitude, fire_distance (-1 =
## aucun feu allumé), sheltered, cloak, in_water, rain_exposed}.
func felt_temperature(context: Dictionary) -> float:
	var t := air_temperature(String(context.get("season", "spring")), float(context.get("hour", 12.0)),
			String(context.get("weather", "clear")), float(context.get("altitude", 0.0)))
	var fire := float(context.get("fire_distance", -1.0))
	if fire >= 0.0 and fire < FIRE_RADIUS:
		t += FIRE_HEAT * (1.0 - smoothstep(FIRE_RADIUS * 0.4, FIRE_RADIUS, fire))
	if bool(context.get("sheltered", false)):
		# Un abri amélioré garde mieux la chaleur : +40 % par niveau au-dessus du premier.
		t += SHELTER_HEAT * (1.0 + 0.4 * float(maxi(int(context.get("shelter_level", 1)) - 1, 0)))
	if bool(context.get("cloak", false)):
		t += CLOAK_HEAT
	return t - WET_CHILL * _wet

## Fait évoluer l'humidité et la chaleur corporelle pendant `delta` secondes.
func update_temperature(delta: float, context: Dictionary) -> void:
	var near_fire := float(context.get("fire_distance", -1.0)) >= 0.0 and float(context.get("fire_distance", -1.0)) < FIRE_RADIUS
	if bool(context.get("in_water", false)):
		_wet = 1.0
	elif bool(context.get("rain_exposed", false)) and not bool(context.get("sheltered", false)):
		# Sous la pluie on est trempé à 60 % en une vingtaine de secondes, sans sécher.
		if _wet < 0.6:
			_wet = minf(0.6, _wet + delta / 40.0)
	else:
		_wet = maxf(0.0, _wet - delta / DRY_SECONDS * (4.0 if near_fire else 1.0))
	_felt = felt_temperature(context)
	var before := _warmth
	if _felt < COLD_AT:
		var chill := clampf((COLD_AT - _felt) / 14.0, 0.15, 1.5)
		_warmth = maxf(0.0, _warmth - chill * delta / CHILL_SECONDS)
	elif _felt >= WARM_AT or near_fire:
		_warmth = minf(1.0, _warmth + delta / (FIRE_WARM_SECONDS if near_fire else WARM_SECONDS))
	if before >= 0.6 and _warmth < 0.6 and not _cold_hint_shown:
		_cold_hint_shown = true
		_hint("TOAST_COLD_HINT")
	warmth_changed.emit(_warmth, _felt)

func get_warmth() -> float:
	return _warmth

func get_felt_temperature() -> float:
	return _felt

func get_wetness() -> float:
	return _wet

func is_hot() -> bool:
	return _felt >= HOT_AT

func is_cold() -> bool:
	return _felt < COLD_AT

## Lit le monde autour du joueur : saison, heure, météo, feu, abri, cape, eau.
func _gather_context(player: Node3D) -> Dictionary:
	var context := {"season": "spring", "hour": 12.0, "weather": "clear"}
	var weather := InteractionManager.get_weather()
	if weather != null:
		context["season"] = String(weather.call("get_season"))
		context["weather"] = String(weather.call("get_weather")) if bool(weather.call("effects_active")) else "clear"
		if not bool(weather.call("effects_active")):
			context["season"] = "spring"
	var day_night := get_tree().root.get_node_or_null("DayNightCycle")
	if day_night != null:
		context["hour"] = float(day_night.get("hour"))
	if player == null:
		return context
	var p := player.global_position
	context["altitude"] = p.y
	var best := -1.0
	for fire in get_tree().get_nodes_in_group("campfire"):
		if fire is Node3D and fire.has_method("is_lit") and bool(fire.call("is_lit")):
			var d := (fire as Node3D).global_position.distance_to(p)
			if best < 0.0 or d < best:
				best = d
	context["fire_distance"] = best
	for structure in get_tree().get_nodes_in_group("structures"):
		if structure is Node3D and str(structure.get("kind")) == "shelter" \
				and (structure as Node3D).global_position.distance_to(p) < SHELTER_RADIUS:
			context["sheltered"] = true
			context["shelter_level"] = maxi(int(context.get("shelter_level", 1)), int(structure.get("level")))
	var inventory := InteractionManager.get_inventory()
	context["cloak"] = inventory != null and bool(inventory.call("has_item", CLOAK_ITEM, 1))
	context["in_water"] = player.has_method("is_wading") and bool(player.call("is_wading"))
	context["rain_exposed"] = context["weather"] == "rain" or context["weather"] == "snow"
	return context

func _hint(key: String) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var hud := tree.get_first_node_in_group("hud")
	if hud != null and hud.has_method("show_toast"):
		hud.call("show_toast", tr(key), 5.0)

# --- Accesseurs -----------------------------------------------------------------

## Dépense directe de faim et de soif (voyage rapide, efforts).
func consume(hunger_cost: float, thirst_cost: float) -> void:
	_hunger = maxf(0.0, _hunger - hunger_cost)
	_thirst = maxf(0.0, _thirst - thirst_cost)
	_reemit()

func get_health() -> float:
	return _health

## Inflige des dégâts (0 à 1 = toute la santé). Retourne true si le joueur est à terre.
func damage(amount: float) -> bool:
	var inventory := InteractionManager.get_inventory()
	if inventory != null and inventory.has_item(CLOAK_ITEM, 1):
		amount *= 1.0 - CLOAK_REDUCTION
	_health = maxf(0.0, _health - amount)
	health_changed.emit(_health)
	if _health <= 0.0:
		died.emit()
		return true
	return false

func heal(amount: float) -> void:
	var next := clampf(_health + amount, 0.0, 1.0)
	if is_equal_approx(next, _health):
		return
	_health = next
	health_changed.emit(_health)

## Après une défaite : on se relève à moitié de santé, ni affamé ni assoiffé.
func revive() -> void:
	_health = 0.5
	_hunger = maxf(_hunger, 0.4)
	_thirst = maxf(_thirst, 0.4)
	_warmth = maxf(_warmth, 0.6)
	_wet = 0.0
	health_changed.emit(_health)

func get_hunger() -> float:
	return _hunger

func get_thirst() -> float:
	return _thirst

## Multiplicateur de régénération d'endurance selon l'état (1 = normal).
func stamina_regen_factor() -> float:
	var factor := 1.0
	if _hunger <= 0.0:
		factor -= 0.4
	if _thirst <= 0.0:
		factor -= 0.4
	if _warmth < 0.25:
		factor -= 0.3
	return maxf(factor, STAMINA_REGEN_MIN)

## La course est bloquée si faim ET soif sont vides.
func can_sprint() -> bool:
	return _hunger > 0.0 or _thirst > 0.0

func eat(amount: float) -> void:
	_hunger = minf(1.0, _hunger + amount)
	_reemit()
	_save()

func drink(amount: float) -> void:
	_thirst = minf(1.0, _thirst + amount)
	_reemit()
	_save()

func _on_stamina(_value: float, _exhausted: bool) -> void:
	pass

# --- Sauvegarde -------------------------------------------------------------------

func _load() -> void:
	var config := ConfigFile.new()
	if config.load(SaveSlots.file(SAVE_NAME)) != OK:
		return
	_hunger = clampf(float(config.get_value("needs", "hunger", 1.0)), 0.0, 1.0)
	_thirst = clampf(float(config.get_value("needs", "thirst", 1.0)), 0.0, 1.0)
	_health = clampf(float(config.get_value("needs", "health", 1.0)), 0.1, 1.0)
	_warmth = clampf(float(config.get_value("needs", "warmth", 1.0)), 0.2, 1.0)
	_cold_hint_shown = bool(config.get_value("hints", "cold", false))

func _save() -> void:
	if not _autosave:
		return
	var config := ConfigFile.new()
	config.set_value("needs", "hunger", _hunger)
	config.set_value("needs", "thirst", _thirst)
	config.set_value("needs", "health", _health)
	config.set_value("needs", "warmth", _warmth)
	config.set_value("hints", "cold", _cold_hint_shown)
	config.save(SaveSlots.file(SAVE_NAME))

## API de test : repart de zéro, sans écrire sur le disque.
func clear_for_test() -> void:
	_autosave = false
	_hunger = 1.0
	_thirst = 1.0
	_health = 1.0
	_warmth = 1.0
	_wet = 0.0
	_felt = 18.0
	_cold_hint_shown = false
