class_name TutorialPanel
extends PanelContainer
## Premiers pas : une consigne à la fois, validée dès que le joueur l'a faite (se déplacer,
## regarder autour, ramasser, ouvrir le journal puis la carte, suivre le cap). Textes adaptés
## au tactile ou au clavier. « Passer » arrête tout ; Réglages → « Revoir le tutoriel ».
## Sauvegarde dans user://tutorial.cfg.

signal finished

const SAVE_NAME := "tutorial.cfg"
const STEPS := ["move", "look", "pickup", "journal", "map", "compass"]
## Seuils de validation.
const MOVE_METERS := 5.0
const LOOK_RADIANS := 1.4
const COMPASS_SECONDS := 9.0
## Délai avant la première consigne (le joueur découvre le décor).
const START_DELAY := 2.5
const ACCENT := Color(0.88, 0.64, 0.36, 1.0)

var step: int = -1
var done: bool = false
var _autosave: bool = DisplayServer.get_name() != "headless"
var _touch: bool = false
var _moved: float = 0.0
var _looked: float = 0.0
var _picked: bool = false
var _step_time: float = 0.0
var _last_position: Vector3 = Vector3.INF
var _last_yaw: float = INF
var _delay: float = START_DELAY
var _label: RichTextLabel
var _counter: Label
var _skip: Button
var _player: Node3D
var _journal: Control
var _map: Control

func _ready() -> void:
	add_to_group("tutorial")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_touch = PlatformInfo.is_touch()
	_build()
	visible = false
	var inventory := InteractionManager.get_inventory()
	if inventory != null and inventory.has_signal("item_added"):
		inventory.connect("item_added", _on_item_added)
	_load()
	if done:
		set_process(false)

## Branche le tutoriel sur le joueur et les panneaux du HUD.
func set_context(player: Node3D, journal: Control, map: Control) -> void:
	_player = player
	_journal = journal
	_map = map

func _build() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.065, 0.04, 0.88)
	style.border_color = ACCENT
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	add_child(row)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 2)
	row.add_child(column)
	_counter = Label.new()
	_counter.add_theme_font_size_override("font_size", 15)
	_counter.add_theme_color_override("font_color", ACCENT)
	column.add_child(_counter)
	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.scroll_active = false
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("normal_font_size", 20)
	_label.add_theme_font_size_override("bold_font_size", 20)
	column.add_child(_label)
	_skip = Button.new()
	_skip.text = tr("TUTO_SKIP")
	_skip.focus_mode = Control.FOCUS_NONE
	_skip.custom_minimum_size = Vector2(110, 56)
	_skip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_skip.mouse_filter = Control.MOUSE_FILTER_STOP
	_skip.pressed.connect(skip)
	row.add_child(_skip)

# --- Déroulé ----------------------------------------------------------------------------

## (Re)commence depuis la première consigne.
func restart() -> void:
	done = false
	step = -1
	_delay = 0.4
	_moved = 0.0
	_looked = 0.0
	_picked = false
	set_process(true)
	_save()

func skip() -> void:
	_finish()

func is_active() -> bool:
	return not done and step >= 0

func current_step() -> String:
	return STEPS[step] if step >= 0 and step < STEPS.size() else ""

func _process(delta: float) -> void:
	if done:
		return
	if step < 0:
		_delay -= delta
		if _delay <= 0.0:
			_go_to(0)
		return
	_step_time += delta
	_track_player()
	if is_step_done():
		_go_to(step + 1)

## Vrai si la consigne en cours est accomplie.
func is_step_done() -> bool:
	match current_step():
		"move":
			return _moved >= MOVE_METERS
		"look":
			return _looked >= LOOK_RADIANS
		"pickup":
			return _picked
		"journal":
			return _journal != null and _journal.visible
		"map":
			return _map != null and _map.visible
		"compass":
			return _step_time >= COMPASS_SECONDS
	return false

## Signale un déplacement ou une rotation (aussi appelé par les tests).
func add_progress(meters: float, radians: float) -> void:
	_moved += meters
	_looked += radians

func _track_player() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var here := _player.global_position
	if _last_position != Vector3.INF:
		var flat := Vector2(here.x - _last_position.x, here.z - _last_position.z).length()
		if flat < 3.0:
			_moved += flat
	_last_position = here
	var yaw := _player.global_rotation.y
	if _last_yaw != INF:
		_looked += absf(wrapf(yaw - _last_yaw, -PI, PI))
	_last_yaw = yaw

func _on_item_added(_item_id: String, _amount: int) -> void:
	if current_step() == "pickup":
		_picked = true

func _go_to(index: int) -> void:
	if index >= STEPS.size():
		_finish()
		return
	step = index
	_step_time = 0.0
	# La consigne suivante ne doit pas être validée par ce qui précède.
	if current_step() == "look":
		_looked = 0.0
	elif current_step() == "pickup":
		_picked = false
	_refresh()
	visible = true
	if index > 0:
		var sfx := InteractionManager.get_sfx()
		if sfx != null and sfx.has_method("play_event"):
			sfx.call("play_event", "chime", -14.0, 1.3)
	_save()

func _finish() -> void:
	var was_active := not done
	done = true
	step = STEPS.size()
	visible = false
	set_process(false)
	_save()
	if was_active:
		var hud := get_tree().get_first_node_in_group("hud") if get_tree() != null else null
		if hud != null and hud.has_method("show_toast"):
			hud.call("show_toast", tr("TUTO_DONE"), 3.5)
		finished.emit()

## Texte de la consigne (variante tactile ou clavier).
func step_text(step_name: String) -> String:
	var key := "TUTO_" + step_name.to_upper()
	if step_name in ["move", "look", "pickup", "journal", "map"]:
		key += "_TOUCH" if _touch else "_KEYS"
	return tr(key)

func _refresh() -> void:
	_counter.text = tr("TUTO_TITLE") % [step + 1, STEPS.size()]
	_label.text = step_text(current_step())
	_skip.text = tr("TUTO_SKIP")

# --- Sauvegarde ------------------------------------------------------------------------------

func _load() -> void:
	if not _autosave:
		return
	var config := ConfigFile.new()
	if config.load(SaveSlots.file(SAVE_NAME)) != OK:
		return
	done = bool(config.get_value("tutorial", "done", false))

func _save() -> void:
	if not _autosave:
		return
	var config := ConfigFile.new()
	config.set_value("tutorial", "done", done)
	config.save(SaveSlots.file(SAVE_NAME))

## API de test : tutoriel neuf, sans disque.
func clear_for_test(touch: bool = false) -> void:
	_autosave = false
	_touch = touch
	done = false
	step = -1
	_delay = 0.0
	_moved = 0.0
	_looked = 0.0
	_picked = false
	set_process(true)
