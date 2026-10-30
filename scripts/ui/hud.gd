extends CanvasLayer
## HUD : boussole, horloge, endurance, invite d'interaction et contrôles tactiles.

## Quand le futur système de carte / journal sera prêt, il se branche sur ces
## signaux ; en attendant, le HUD affiche « Bientôt disponible ».
signal map_requested
signal journal_requested

const BASE_MARGIN := 16

@onready var action_pad: Control = $Overlay/ActionPad
@onready var interact_button: Button = $Overlay/ActionPad/InteractButton
@onready var attack_button: Button = $Overlay/ActionPad/AttackButton
@onready var jump_button: Button = $Overlay/ActionPad/JumpButton
@onready var sprint_button: Button = $Overlay/ActionPad/SprintButton
@onready var journal_button: Button = $SafeArea/VBox/BottomBar/JournalButton
@onready var view_button: Button = $SafeArea/VBox/BottomBar/ViewButton
@onready var compass_label: Label = $SafeArea/VBox/TopBar/CompassLabel
@onready var clock_label: Label = $SafeArea/VBox/TopBar/ClockLabel
@onready var vitals: Control = $Overlay/Vitals
@onready var minimap: Control = $Overlay/MiniMap
@onready var safe_area: MarginContainer = $SafeArea
@onready var compass_strip: CompassStrip = $Overlay/CompassStrip
@onready var reticle: Control = $Overlay/Reticle
@onready var interact_prompt: Label = $Overlay/CenterPrompt
@onready var toast: Label = $Overlay/Toast
@onready var joystick: Control = $VirtualJoystick
@onready var inventory_center: CenterContainer = $InventoryCenter
@onready var journal_panel: Control = $InventoryCenter/JournalPanel
@onready var map_panel: Control = $MapPanel
@onready var quest_tracker: Label = $Overlay/QuestTracker
@onready var camera_joystick: Control = $CameraJoystick
@onready var touch_look: Control = $TouchLook

var _player: CharacterBody3D
var _toast_tween: Tween
var _pulse_tween: Tween
var _interaction_manager: Node
var _inventory: Node
var _day_night: Node
var _survival: Node
var _camera_joystick_vector: Vector2 = Vector2.ZERO
var _base_offsets: Dictionary = {}
var _last_clock_minute: int = -1
var _last_heading: int = -1
var _focused_interactable: Interactable = null
var _stamina_exhausted: bool = false

func _ready() -> void:
	var is_touch := PlatformInfo.is_touch()
	action_pad.visible = is_touch
	journal_button.visible = is_touch
	view_button.visible = true
	joystick.visible = true
	camera_joystick.visible = true
	touch_look.visible = is_touch

	interact_button.pressed.connect(_on_interact_pressed)
	attack_button.pressed.connect(_on_attack_pressed)
	jump_button.button_down.connect(_on_jump_pressed)
	sprint_button.toggled.connect(_on_sprint_toggled)
	journal_button.pressed.connect(_on_journal_pressed)
	minimap.connect("pressed", _on_map_pressed)
	view_button.pressed.connect(_on_view_pressed)

	_interaction_manager = InteractionManager
	_inventory = Inventory
	_day_night = DayNightCycle

	if _interaction_manager != null:
		_interaction_manager.connect("focus_changed", _on_focus_changed)
	if _inventory != null:
		_inventory.connect("item_added", _on_item_added)
		_inventory.connect("item_removed", _on_item_removed)
	_survival = get_tree().root.get_node_or_null("SurvivalManager") if get_tree() != null else null
	if _survival != null:
		_survival.connect("needs_changed", _on_needs_changed)
		_on_needs_changed(float(_survival.call("get_hunger")), float(_survival.call("get_thirst")))
	if _day_night != null:
		_day_night.connect("time_changed", _on_time_changed)
		_day_night.connect("phase_changed", _on_phase_changed)
		_refresh_clock(float(_day_night.get("hour")))

	interact_prompt.visible = false
	toast.visible = false
	interact_button.disabled = true
	interact_button.visible = false
	_refresh_attack_button()

	_capture_layout()
	_apply_safe_area()
	get_viewport().size_changed.connect(_apply_safe_area)

	_player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	if _player == null:
		var parent := get_parent()
		if parent != null:
			_player = parent.get_node_or_null("Player") as CharacterBody3D
	if map_panel != null:
		# Le paysage est un frère du HUD dans la scène du monde (current_scene peut être
		# nul quand le monde est instancié à la main, par exemple en test).
		var world: Node = get_parent() if get_parent() != null else get_tree().current_scene
		var landscape := world.get_node_or_null("Landscape") if world != null else null
		map_panel.set_context(landscape, _player)
		if minimap != null:
			minimap.set_context(landscape, _player)
	_setup_quest_tracker()
	if _player != null:
		joystick.moved.connect(_player.set_joystick_vector)
		touch_look.look_delta.connect(_player.apply_touch_look)
		camera_joystick.moved.connect(_on_camera_joystick_moved)
		if _player.has_signal("view_changed"):
			_player.connect("view_changed", _on_view_changed)
		if _player.has_signal("stamina_changed"):
			_player.connect("stamina_changed", _on_stamina_changed)
		_on_view_changed(_player.call("is_first_person"))

## Rappel discret de l'objectif en cours (sous le cap), mis à jour par QuestManager.
func _setup_quest_tracker() -> void:
	var quests := get_node_or_null("/root/QuestManager")
	if quests == null or quest_tracker == null:
		return
	quests.connect("quest_state_changed", _on_quest_changed)
	quests.connect("quest_progress_changed", _on_quest_changed)
	_update_quest_tracker.call_deferred()

func _on_quest_changed(_a = null, _b = null, _c = null) -> void:
	_update_quest_tracker.call_deferred()

func _update_quest_tracker() -> void:
	var quests := get_node_or_null("/root/QuestManager")
	if quests == null or quest_tracker == null:
		return
	var quest_id: String = quests.call("get_tracked")
	if quest_id == "":
		quest_tracker.visible = false
		return
	var progress: Vector2i = quests.call("get_progress", quest_id)
	quest_tracker.text = tr("QUEST_TRACKER") % [tr(quests.call("get_title", quest_id)), progress.x, progress.y]
	quest_tracker.visible = true

func _process(delta: float) -> void:
	_hide_stale_prompt()
	# La mini-carte s'efface quand un panneau plein écran est ouvert.
	var panel_open := (map_panel != null and map_panel.visible) or (journal_panel != null and journal_panel.visible)
	minimap.visible = not panel_open
	vitals.visible = not panel_open
	if panel_open and interact_button.visible:
		_on_focus_changed(null)
	if _player == null:
		return
	if _camera_joystick_vector != Vector2.ZERO and _player.has_method("apply_camera_joystick"):
		_player.call("apply_camera_joystick", _camera_joystick_vector, delta)
	if _player.has_method("get_heading_degrees"):
		var heading: float = _player.call("get_heading_degrees")
		compass_strip.heading = heading
		var rounded := int(roundf(heading)) % 360
		if rounded != _last_heading:
			_last_heading = rounded
			compass_label.text = "%s %03d°" % [tr(CompassStrip.cardinal_key(heading)), rounded]

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("open_journal"):
		_on_journal_pressed()
	elif event.is_action_pressed("open_map"):
		_on_map_pressed()

# --- Boutons -------------------------------------------------------------------

func _on_interact_pressed() -> void:
	if _player != null and _player.has_method("try_interact"):
		_player.call("try_interact")

func _on_jump_pressed() -> void:
	if _player != null and _player.has_method("request_jump"):
		_player.call("request_jump")

func _on_sprint_toggled(enabled: bool) -> void:
	if _player != null and _player.has_method("set_sprint_lock"):
		_player.call("set_sprint_lock", enabled)

func _on_view_pressed() -> void:
	if _player != null and _player.has_method("toggle_view"):
		_player.call("toggle_view")

func _on_journal_pressed() -> void:
	if get_signal_connection_list("journal_requested").size() > 0:
		journal_requested.emit()
		return
	if journal_panel != null:
		journal_panel.toggle()
		if journal_panel.visible and map_panel != null and map_panel.visible:
			map_panel.close()
	else:
		show_toast(tr("TOAST_SOON"))

func _on_map_pressed() -> void:
	if get_signal_connection_list("map_requested").size() > 0:
		map_requested.emit()
		return
	if map_panel != null:
		map_panel.toggle()
		if map_panel.visible and journal_panel != null and journal_panel.visible:
			journal_panel.close()
	else:
		show_toast(tr("TOAST_SOON"))

func _on_camera_joystick_moved(vector: Vector2) -> void:
	_camera_joystick_vector = vector

func _on_view_changed(is_first_person: bool) -> void:
	view_button.text = tr("VIEW_FIRST_PERSON") if is_first_person else tr("VIEW_THIRD_PERSON")

# --- Messages ------------------------------------------------------------------

func show_toast(message: String, duration: float = 2.0) -> void:
	toast.text = message
	toast.visible = true
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	toast.modulate.a = 0.0
	_toast_tween = create_tween()
	_toast_tween.tween_property(toast, "modulate:a", 1.0, 0.12)
	_toast_tween.tween_interval(duration)
	_toast_tween.tween_property(toast, "modulate:a", 0.0, 0.3)
	_toast_tween.tween_callback(_hide_toast)

func _hide_toast() -> void:
	toast.visible = false

# --- Interaction ----------------------------------------------------------------

func _on_focus_changed(target: Node3D) -> void:
	var interactable: Interactable = null
	if target != null and is_instance_valid(target) and target is Interactable:
		interactable = target as Interactable
	_focused_interactable = interactable
	if interactable != null:
		var label := tr(interactable.get_prompt())
		interact_prompt.text = label if PlatformInfo.is_touch() else "[%s] %s" % [_interact_key_text(), label]
		interact_prompt.visible = true
		interact_button.disabled = not interactable.can_interact()
		interact_button.visible = true
		reticle.call("set_focused", true)
		_pulse_interact(not interact_button.disabled)
	else:
		interact_prompt.visible = false
		interact_button.disabled = true
		interact_button.visible = false
		reticle.call("set_focused", false)
		_pulse_interact(false)

## Sécurité : si l'objet visé a disparu ou n'est plus interactif (ramassé,
## cassé), l'invite et le bouton doivent s'éteindre même si le signal
## focus_changed n'est pas revenu.
func _hide_stale_prompt() -> void:
	# Un objet libéré compare « égal » à null : on ne se fie qu'à is_instance_valid.
	if not interact_prompt.visible and not interact_button.visible:
		return
	if is_instance_valid(_focused_interactable) and _focused_interactable.can_interact():
		return
	_on_focus_changed(null)

func _interact_key_text() -> String:
	for event in InputMap.action_get_events("interact"):
		if event is InputEventKey:
			return (event as InputEventKey).as_text_physical_keycode()
	return "E"

## Fait « respirer » le bouton d'interaction quand une action est possible.
func _pulse_interact(active: bool) -> void:
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	interact_button.scale = Vector2.ONE
	if not active or not action_pad.visible:
		return
	interact_button.pivot_offset = interact_button.size * 0.5
	_pulse_tween = create_tween().set_loops()
	_pulse_tween.tween_property(interact_button, "scale", Vector2(1.1, 1.1), 0.45).set_trans(Tween.TRANS_SINE)
	_pulse_tween.tween_property(interact_button, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_SINE)

func _on_item_added(item_id: String, amount: int) -> void:
	show_toast(tr("TOAST_COLLECTED") % [amount, tr("ITEM_" + item_id.to_upper())])
	if PlatformInfo.is_touch():
		Input.vibrate_handheld(25)
	_refresh_attack_button()

func _on_item_removed(_item_id: String, _amount: int) -> void:
	_refresh_attack_button()

## Le bouton de tir n'apparaît (tactile) que si le joueur possède l'arc de chasse.
func _refresh_attack_button() -> void:
	if not PlatformInfo.is_touch() or _inventory == null:
		return
	var owned: bool = _inventory.has_item("tool_hunting_bow", 1)
	if attack_button.visible != owned:
		attack_button.visible = owned

func _on_attack_pressed() -> void:
	if _player != null and _player.has_method("try_shoot_arrow"):
		_player.call("try_shoot_arrow")

# --- Endurance ------------------------------------------------------------------

## Jauges latérales : faim et soif suivent SurvivalManager, l'énergie suit le joueur.
func _on_needs_changed(hunger: float, thirst: float) -> void:
	vitals.call("set_value", "hunger", hunger)
	vitals.call("set_value", "thirst", thirst)

func _on_stamina_changed(value: float, exhausted: bool) -> void:
	vitals.call("set_value", "energy", value)
	if exhausted and not _stamina_exhausted:
		show_toast(tr("TOAST_EXHAUSTED"), 1.6)
		# La course verrouillée est relâchée : le bouton reflète l'état réel.
		sprint_button.button_pressed = false
	_stamina_exhausted = exhausted

# --- Horloge --------------------------------------------------------------------

func _on_time_changed(hour: float) -> void:
	var total_minutes := int(hour * 60.0)
	if total_minutes == _last_clock_minute:
		return
	_last_clock_minute = total_minutes
	_refresh_clock(hour)

func _on_phase_changed(_phase: String) -> void:
	if _day_night != null:
		_refresh_clock(float(_day_night.get("hour")))

func _refresh_clock(hour: float) -> void:
	var phase_text := ""
	if _day_night != null and _day_night.has_method("get_phase"):
		phase_text = tr("PHASE_" + String(_day_night.call("get_phase")).to_upper())
	clock_label.text = "%02d:%02d  %s" % [int(hour) % 24, int(fmod(hour, 1.0) * 60.0), phase_text]

# --- Zone sûre (encoches, coins arrondis) ---------------------------------------

func _capture_layout() -> void:
	for node: Control in [joystick, camera_joystick, action_pad]:
		_base_offsets[node] = Vector4(node.offset_left, node.offset_top, node.offset_right, node.offset_bottom)

func _apply_safe_area() -> void:
	var inset := _safe_insets()
	safe_area.add_theme_constant_override("margin_left", BASE_MARGIN + int(inset.x))
	safe_area.add_theme_constant_override("margin_top", BASE_MARGIN + int(inset.y))
	safe_area.add_theme_constant_override("margin_right", BASE_MARGIN + int(inset.z))
	safe_area.add_theme_constant_override("margin_bottom", BASE_MARGIN + int(inset.w))
	_shift(joystick, Vector2(inset.x, -inset.w))
	_shift(camera_joystick, Vector2(-inset.z, -inset.w))
	_shift(action_pad, Vector2(-inset.z, -inset.w))

func _shift(node: Control, offset: Vector2) -> void:
	if not _base_offsets.has(node):
		return
	var base: Vector4 = _base_offsets[node]
	node.offset_left = base.x + offset.x
	node.offset_right = base.z + offset.x
	node.offset_top = base.y + offset.y
	node.offset_bottom = base.w + offset.y

## Marges (gauche, haut, droite, bas) à ménager, en unités du viewport.
func _safe_insets() -> Vector4:
	var window_size := DisplayServer.window_get_size()
	var screen_size := DisplayServer.screen_get_size()
	var safe := DisplayServer.get_display_safe_area()
	if window_size.x <= 0 or window_size.y <= 0 or safe.size.x <= 0 or safe.size.y <= 0:
		return Vector4.ZERO
	var viewport_size := get_viewport().get_visible_rect().size
	var scale_x := viewport_size.x / float(window_size.x)
	var scale_y := viewport_size.y / float(window_size.y)
	return Vector4(
		maxf(0.0, float(safe.position.x)) * scale_x,
		maxf(0.0, float(safe.position.y)) * scale_y,
		maxf(0.0, float(screen_size.x - safe.end.x)) * scale_x,
		maxf(0.0, float(screen_size.y - safe.end.y)) * scale_y)
