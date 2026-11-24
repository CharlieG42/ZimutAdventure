extends Node
## Événements aléatoires du monde (GDD §4.6) : toutes les ~2-3 minutes de jeu, un
## événement tiré au sort selon les conditions (nuit, météo en cours, feu de camp
## proche...). En headless la boucle ne tourne pas (déterminisme des tests) :
## les tests appellent force_event(id) directement.

signal event_fired(event_id: String)

const MIN_DELAY := 90.0
const MAX_DELAY := 200.0
## id -> poids relatif (plus c'est grand, plus c'est fréquent).
const EVENTS := {
	"wolves_night": 3.0,
	"storm": 2.0,
	"hidden_source": 2.0,
}
## Distance min/max d'apparition de la meute (m).
const WOLF_DISTANCE := Vector2(25.0, 40.0)
## Un feu de camp allumé dans ce rayon protège des loups (m).
const CAMPFIRE_SAFE_RADIUS := 20.0

var _timer: float = 0.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	_timer = _rng.randf_range(MIN_DELAY, MAX_DELAY)

func _process(delta: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = _rng.randf_range(MIN_DELAY, MAX_DELAY)
		try_fire()

## Tente un événement au hasard parmi ceux dont les conditions sont réunies ;
## renvoie l'id de l'événement déclenché, "" sinon.
func try_fire() -> String:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return ""
	var candidates := {}
	for id in EVENTS.keys():
		if _can_fire(String(id), player):
			candidates[id] = float(EVENTS[id])
	if candidates.is_empty():
		return ""
	var total := 0.0
	for w in candidates.values():
		total += w
	var roll := _rng.randf() * total
	var chosen := ""
	for id in candidates.keys():
		roll -= float(candidates[id])
		if roll <= 0.0:
			chosen = String(id)
			break
	if chosen == "":
		chosen = String(candidates.keys()[-1])
	return chosen if force_event(chosen, player) else ""

## Conditions de chaque événement.
func _can_fire(event_id: String, player: Node3D) -> bool:
	match event_id:
		"wolves_night":
			var clock := get_tree().root.get_node_or_null("DayNightCycle")
			if clock == null or String(clock.call("get_phase")) != "night":
				return false
			for fire in get_tree().get_nodes_in_group("campfire"):
				if is_instance_valid(fire) and bool(fire.call("is_lit")) \
						and fire.global_position.distance_to(player.global_position) < CAMPFIRE_SAFE_RADIUS:
					return false
			return true
		"storm":
			var weather := InteractionManager.get_weather()
			if weather == null or not bool(weather.call("effects_active")):
				return false
			var current := String(weather.call("get_weather"))
			return current != "rain" and current != "snow"
		"hidden_source":
			return true
	return false

## Déclenche un événement s'il est possible ; renvoie true s'il a eu lieu.
func force_event(event_id: String, player: Node3D = null) -> bool:
	if player == null:
		player = get_tree().get_first_node_in_group("player") as Node3D
	if player == null or not _can_fire(event_id, player):
		return false
	match event_id:
		"wolves_night":
			_event_wolves(player)
		"storm":
			_event_storm(player)
		"hidden_source":
			_event_hidden_source(player)
		_:
			return false
	event_fired.emit(event_id)
	return true

# --- Événements -------------------------------------------------------------------

## Meute de loups à 25-40 m (la nuit, hors d'un feu de camp allumé).
func _event_wolves(player: Node3D) -> void:
	var spawner := get_tree().get_first_node_in_group("predator_spawner")
	if spawner == null:
		return
	var angle := _rng.randf_range(0.0, TAU)
	var dist := _rng.randf_range(WOLF_DISTANCE.x, WOLF_DISTANCE.y)
	var pos := player.global_position + Vector3(cos(angle), 0.0, sin(angle)) * dist
	spawner.call("spawn", "wolf", pos)
	spawner.call("spawn", "wolf", pos + Vector3(_rng.randf_range(-6.0, 6.0), 0.0, _rng.randf_range(-6.0, 6.0)))
	var sfx := InteractionManager.get_sfx()
	if sfx != null:
		sfx.call("play_event_at", "howl", pos, 0.0, 1.0, 80.0)
	_toast(tr("EVENT_WOLVES"))

## Tempête (ou neige en hiver) soudaine, pendant ~2 h de jeu.
func _event_storm(_player: Node3D) -> void:
	var weather := InteractionManager.get_weather()
	if weather == null:
		return
	var clock := get_tree().root.get_node_or_null("DayNightCycle")
	var hour := float(clock.get("hour")) if clock != null else 12.0
	var kind := "snow" if String(weather.call("get_season")) == "winter" else "rain"
	weather.call("force_weather", kind, fposmod(hour + 2.0, 24.0))
	var sfx := InteractionManager.get_sfx()
	if sfx != null:
		sfx.call("play_event", "wind", -4.0)
	_toast(tr("EVENT_STORM"))

## Une source d'eau inconnue est révélée sur la carte, avec son cap et sa distance.
func _event_hidden_source(player: Node3D) -> void:
	var world := player.get_parent()
	var landscape := world.get_node_or_null("Landscape") if world != null else null
	var exploration := InteractionManager.get_exploration()
	if landscape == null or exploration == null:
		return
	var water: Vector3 = landscape.call("nearest_water_point", player.global_position)
	exploration.call("reveal", water.x, water.z, 80.0)
	var from := Vector2(player.global_position.x, player.global_position.z)
	var bearing: float = (load("res://scripts/autoload/exploration_manager.gd") as GDScript).bearing(from, Vector2(water.x, water.z))
	var dist := int(round(from.distance_to(Vector2(water.x, water.z))))
	_toast(tr("EVENT_SOURCE") % [tr(CompassStrip.cardinal_key(bearing)), dist])

func _toast(message: String) -> void:
	var hud := get_tree().get_first_node_in_group("hud") as Node
	if hud != null and hud.has_method("show_toast"):
		hud.show_toast(message, 3.0)
