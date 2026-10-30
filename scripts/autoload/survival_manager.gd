extends Node
## Survie : faim et soif décroissent avec le temps. Une jauge vide pénalise
## l'endurance (régénération réduite, course impossible si les deux sont vides).
## Sauvegarde dans user://survival.cfg.

signal needs_changed(hunger: float, thirst: float)

const SAVE_PATH := "user://survival.cfg"
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

func _connect_player(player: Node) -> void:
	if player.has_method("is_sprinting"):
		player.call_deferred("set_meta", "survival_bound", true)
	if player.has_signal("stamina_changed"):
		player.connect("stamina_changed", _on_stamina)

func _process(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player")
	var sprinting: bool = player != null and player.has_method("is_sprinting") and bool(player.call("is_sprinting"))
	var rate := sprint_multiplier if sprinting else 1.0
	_hunger = maxf(0.0, _hunger - hunger_drain * rate * delta)
	_thirst = maxf(0.0, _thirst - thirst_drain * rate * delta)
	_reemit()
	_elapsed_save += delta
	if _elapsed_save > 5.0:
		_elapsed_save = 0.0
		_save()

func _reemit() -> void:
	needs_changed.emit(_hunger, _thirst)

# --- Accesseurs -----------------------------------------------------------------

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
	if config.load(SAVE_PATH) != OK:
		return
	_hunger = clampf(float(config.get_value("needs", "hunger", 1.0)), 0.0, 1.0)
	_thirst = clampf(float(config.get_value("needs", "thirst", 1.0)), 0.0, 1.0)

func _save() -> void:
	if not _autosave:
		return
	var config := ConfigFile.new()
	config.set_value("needs", "hunger", _hunger)
	config.set_value("needs", "thirst", _thirst)
	config.save(SAVE_PATH)

## API de test : repart de zéro, sans écrire sur le disque.
func clear_for_test() -> void:
	_autosave = false
	_hunger = 1.0
	_thirst = 1.0
