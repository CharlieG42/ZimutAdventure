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
@onready var aim_button: Button = $Overlay/ActionPad/AimButton
@onready var jump_button: Button = $Overlay/ActionPad/JumpButton
@onready var sprint_button: Button = $Overlay/ActionPad/SprintButton
@onready var journal_button: Button = $SafeArea/VBox/BottomBar/JournalButton
@onready var view_button: Button = $SafeArea/VBox/BottomBar/ViewButton
@onready var compass_label: Label = $SafeArea/VBox/TopBar/CompassLabel
@onready var clock_label: Label = $SafeArea/VBox/TopBar/ClockLabel
@onready var vitals: Control = $Overlay/Vitals
@onready var minimap: Control = $Overlay/MiniMap
@onready var level_badge: Control = $Overlay/LevelBadge
@onready var hotbar: Control = $Overlay/Hotbar
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
@onready var bottom_bar: HBoxContainer = $SafeArea/VBox/BottomBar
@onready var vbox: VBoxContainer = $SafeArea/VBox
@onready var weight_label: Label = $Overlay/WeightLabel
## Consignes des premières minutes (créées en code, voir TutorialPanel).
var tutorial_panel: TutorialPanel
var build_panel: BuildPanel
var whistle_button: Button
var character_creator: CharacterCreator
var _whistle_check: float = 0.0
@onready var camera_joystick: Control = $CameraJoystick
@onready var touch_look: Control = $TouchLook
@onready var fx_grain: TextureRect = $FxLayer/Grain

var _grain_timer: float = 0.0

var _player: CharacterBody3D
var _toast_tween: Tween
var _pulse_tween: Tween
var _interaction_manager: Node
var _inventory: Node
var _day_night: Node
var _survival: Node
var _camera_joystick_vector: Vector2 = Vector2.ZERO
var _move_fixed: Vector2 = Vector2.ZERO
var _move_float: Vector2 = Vector2.ZERO
var _base_offsets: Dictionary = {}
## Offsets d'ancrage d'origine des contrôles non capturés en absolu (ruban, toast).
var _anchor_base: Dictionary = {}
## (move_zone_width, look_only_top) d'origine du TouchLook, restaurés hors portrait.
var _touch_look_base: Vector2 = Vector2(0.42, 0.28)
## Index d'origine de la barre du bas dans le VBox (dernière rangée en paysage).
var _bottom_bar_home_index: int = -1
var _last_clock_minute: int = -1
## Température ressentie affichée à côté de l'heure (arrondie au degré).
var _shown_temperature: int = 9999
var _last_health: float = 1.0
var _damage_flash: ColorRect
var _last_heading: int = -1
var _focused_interactable: Interactable = null
var _stamina_exhausted: bool = false
## Un panneau plein écran est ouvert : la souris est alors libérée (voir _sync_mouse_mode).
var _panels_open: bool = false
## Le joueur vise à l'arc : le réticule s'affiche même sans objet visé.
var _aiming: bool = false
## Viseur de l'arc (tension, cible verrouillée) et jauge d'action (pêche, confiance).
var _bow_overlay: Control
var _gauge: ProgressBar
var _gauge_label: Label
var _prompt_refresh: float = 0.0
var _load_check: float = 0.0
var _was_overloaded: bool = false

## Qualité réduite (PerformanceGuard) : niveau 1 coupe le grain, niveau 2 aussi la vignette.
func set_fx_level(level: int) -> void:
	if fx_grain != null:
		fx_grain.visible = level < 1
	var vignette := get_node_or_null("FxLayer/Vignette") as CanvasItem
	if vignette != null:
		vignette.visible = level < 2

func _ready() -> void:
	add_to_group("fx_quality")
	# Tous les messages du jeu (animaux, pêche, quêtes...) passent par ce groupe.
	add_to_group("hud")
	var is_touch := PlatformInfo.is_touch()
	action_pad.visible = is_touch
	journal_button.visible = is_touch
	view_button.visible = true
	joystick.visible = true
	camera_joystick.visible = true
	touch_look.visible = is_touch

	interact_button.pressed.connect(_on_interact_pressed)
	# Maintenir pour bander l'arc, relâcher pour tirer (la hache frappe dès l'appui).
	attack_button.button_down.connect(_on_attack_down)
	attack_button.button_up.connect(_on_attack_up)
	aim_button.toggled.connect(_on_aim_toggled)
	aim_button.text = tr("ACTION_AIM")
	_build_bow_overlay()
	_build_gauge()
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
		_inventory.connect("equipped_changed", _on_equipped_changed)
	_survival = get_tree().root.get_node_or_null("SurvivalManager") if get_tree() != null else null
	if _survival != null:
		_survival.connect("needs_changed", _on_needs_changed)
		_survival.connect("health_changed", _on_health_changed)
		_on_health_changed(float(_survival.call("get_health")))
		_on_needs_changed(float(_survival.call("get_hunger")), float(_survival.call("get_thirst")))
		if _survival.has_signal("warmth_changed"):
			_survival.connect("warmth_changed", _on_warmth_changed)
	if _day_night != null:
		_day_night.connect("time_changed", _on_time_changed)
		_day_night.connect("phase_changed", _on_phase_changed)
		var weather_node := InteractionManager.get_weather()
		if weather_node != null:
			weather_node.connect("weather_changed", _on_weather_changed)
			weather_node.connect("season_changed", _on_weather_changed)
		_refresh_clock(float(_day_night.get("hour")))

	interact_prompt.visible = false
	toast.visible = false
	interact_button.disabled = true
	interact_button.visible = false
	_refresh_attack_button()

	_capture_layout.call_deferred()
	_apply_safe_area.call_deferred()
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
	_setup_tutorial()
	_setup_build_panel()
	_setup_whistle_button()
	_setup_character_panel()
	_setup_chest_panel()
	_setup_character_creator()
	if _player != null:
		joystick.moved.connect(_on_fixed_move)
		touch_look.move_changed.connect(_on_float_move)
		touch_look.look_delta.connect(_player.apply_touch_look)
		camera_joystick.moved.connect(_on_camera_joystick_moved)
		if _player.has_signal("view_changed"):
			_player.connect("view_changed", _on_view_changed)
		if _player.has_signal("stamina_changed"):
			_player.connect("stamina_changed", _on_stamina_changed)
		_on_view_changed(_player.call("is_first_person"))

var character_panel: CharacterPanel
var ranch_panel: RanchPanel
var ranch_button: Button
var character_button: Button
var chest_panel: ChestPanel

## Fenêtre Personnage (vêtements portés, aperçu 3D) et son bouton dans la barre du bas.
func _setup_character_panel() -> void:
	character_panel = CharacterPanel.new()
	character_panel.name = "CharacterPanel"
	journal_panel.get_parent().add_child(character_panel)
	character_button = Button.new()
	character_button.name = "CharacterButton"
	character_button.text = tr("ACTION_CHARACTER")
	character_button.custom_minimum_size = Vector2(0.0, 56.0)
	character_button.focus_mode = Control.FOCUS_NONE
	character_button.pressed.connect(open_character_panel)
	view_button.get_parent().add_child(character_button)
	view_button.get_parent().move_child(character_button, journal_button.get_index() + 1)
	ranch_panel = RanchPanel.new()
	ranch_panel.name = "RanchPanel"
	journal_panel.get_parent().add_child(ranch_panel)
	ranch_button = Button.new()
	ranch_button.name = "RanchButton"
	ranch_button.text = tr("ACTION_RANCH")
	ranch_button.custom_minimum_size = Vector2(0.0, 56.0)
	ranch_button.focus_mode = Control.FOCUS_NONE
	ranch_button.visible = false
	ranch_button.pressed.connect(open_ranch_panel)
	view_button.get_parent().add_child(ranch_button)
	view_button.get_parent().move_child(ranch_button, character_button.get_index() + 1)

## Fenêtre Ranch (gestion des enclos) : bouton visible dès qu'un enclos existe.
func open_ranch_panel(pen: Node3D = null) -> void:
	for other: Control in [journal_panel, character_panel]:
		if other != null and other.visible:
			other.call("close")
	if ranch_panel.visible and pen == null:
		ranch_panel.close()
	else:
		ranch_panel.open(pen)

func _refresh_ranch_button() -> void:
	var available := not get_tree().get_nodes_in_group("pens").is_empty()
	if ranch_button != null and ranch_button.visible != available:
		ranch_button.visible = available

## Panneau de transfert du coffre (déposer / reprendre objet par objet).
func _setup_chest_panel() -> void:
	chest_panel = ChestPanel.new()
	chest_panel.name = "ChestPanel"
	journal_panel.get_parent().add_child(chest_panel)

## Ouvert par l'interaction « Ouvrir le coffre » : on ferme les autres panneaux plein écran.
func open_chest_panel(chest: Node) -> void:
	for other: Control in [journal_panel, map_panel, character_panel, ranch_panel]:
		if other != null and other.visible:
			other.call("close")
	if chest_panel != null:
		chest_panel.open(chest)

func open_character_panel() -> void:
	if journal_panel != null and journal_panel.visible:
		journal_panel.close()
	if ranch_panel != null and ranch_panel.visible:
		ranch_panel.close()
	character_panel.toggle()

## Bouton « Siffler » (barre du bas) : visible seulement si un cheval ou un chien apprivoisé existe.
func _setup_whistle_button() -> void:
	whistle_button = Button.new()
	whistle_button.name = "WhistleButton"
	whistle_button.text = tr("ACTION_WHISTLE")
	whistle_button.custom_minimum_size = Vector2(0.0, 56.0)
	whistle_button.focus_mode = Control.FOCUS_NONE
	whistle_button.visible = false
	whistle_button.pressed.connect(_on_whistle_pressed)
	view_button.get_parent().add_child(whistle_button)

func _on_whistle_pressed() -> void:
	if _player != null and _player.has_method("whistle"):
		_player.call("whistle")

func _refresh_whistle_button() -> void:
	var available := false
	for node in get_tree().get_nodes_in_group("domestic"):
		if not is_instance_valid(node) or not bool(node.get("tamed")):
			continue
		# Un chien se siffle même quand on est à cheval ; le cheval, lui, seulement une fois descendu.
		if node.get("species") == "dog" or (node.get("species") == "horse" and not bool(node.get("mounted"))):
			available = true
			break
	if whistle_button.visible != available:
		whistle_button.visible = available

## Écran de personnalisation du personnage (premier lancement, puis journal > réglages).
func _setup_character_creator() -> void:
	character_creator = CharacterCreator.new()
	character_creator.name = "CharacterCreator"
	character_creator.theme = load("res://assets/ui/hud_theme.tres") as Theme
	character_creator.confirmed.connect(_on_character_confirmed)
	add_child(character_creator)
	# Premier lancement : le joueur crée son personnage avant de jouer (jamais en test sans écran).
	if _player != null and not CharacterProfile.exists() and DisplayServer.get_name() != "headless":
		character_creator.open.call_deferred(CharacterProfile.load_saved(), true)

func open_character_creator() -> void:
	if character_creator != null:
		character_creator.open(CharacterProfile.load_saved(), false)

func _on_character_confirmed(profile: CharacterProfile) -> void:
	if _player != null and _player.has_method("apply_character_profile"):
		_player.call("apply_character_profile", profile)

func _setup_build_panel() -> void:
	build_panel = BuildPanel.new()
	build_panel.name = "BuildPanel"
	build_panel.theme = load("res://assets/ui/hud_theme.tres") as Theme
	$Overlay.add_child(build_panel)
	build_panel.set_context(_player)

func _setup_tutorial() -> void:
	tutorial_panel = TutorialPanel.new()
	tutorial_panel.name = "TutorialPanel"
	$Overlay.add_child(tutorial_panel)
	tutorial_panel.set_context(_player, journal_panel, map_panel)
	_layout_tutorial(get_viewport().get_visible_rect().size)

## Consigne en haut au centre, entre les jauges (à gauche) et la mini-carte (à droite).
func _layout_tutorial(vp: Vector2) -> void:
	if tutorial_panel == null:
		return
	var compact := vp.x < 700.0 or vp.y < 800.0
	var left := 180.0 if compact else 340.0
	var right := 150.0 if compact else 220.0
	var width := clampf(vp.x - left - right, 280.0, 640.0)
	var x := clampf((vp.x - width) * 0.5, left, vp.x - right - width)
	var top := 116.0 if compact else 120.0
	_set_offsets(tutorial_panel, Vector4(x, top, x + width, top + 90.0))

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

## Poids du sac affiché sous les jauges quand il dépasse 45 % de la capacité
## (rouge au-delà de 100 % ; toast au passage en surcharge).
func _update_weight_label() -> void:
	if weight_label == null or not is_inside_tree():
		return
	var inventory := InteractionManager.get_inventory()
	if inventory == null or not inventory.has_method("weight_fraction"):
		weight_label.visible = false
		return
	var fraction := float(inventory.call("weight_fraction"))
	var overloaded := fraction > 1.0
	if overloaded and not _was_overloaded:
		show_toast(tr("TOAST_OVERLOADED"), 2.2)
	_was_overloaded = overloaded
	if fraction <= 0.45:
		weight_label.visible = false
		return
	weight_label.visible = true
	weight_label.text = tr("HUD_WEIGHT") % [int(round(float(inventory.call("total_weight")))), int(round(float(inventory.call("capacity"))))]
	weight_label.add_theme_color_override("font_color", Color(0.95, 0.45, 0.4) if overloaded else Color(0.95, 0.85, 0.6))

func _update_quest_tracker() -> void:
	if not is_inside_tree():
		return
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
	_whistle_check -= delta
	if _whistle_check <= 0.0:
		_whistle_check = 0.5
		_refresh_whistle_button()
		_refresh_ranch_button()
	# La mini-carte s'efface quand un panneau plein écran est ouvert.
	var panel_open := (map_panel != null and map_panel.visible) or (journal_panel != null and journal_panel.visible) \
			or (character_creator != null and character_creator.visible) \
			or (character_panel != null and character_panel.visible) or (ranch_panel != null and ranch_panel.visible) \
			or (chest_panel != null and chest_panel.visible)
	if panel_open != _panels_open:
		_panels_open = panel_open
		_sync_mouse_mode()
	var settings := get_tree().root.get_node_or_null("GameSettings")
	minimap.visible = not panel_open and (settings == null or bool(settings.get("minimap")))
	vitals.visible = not panel_open
	if panel_open and interact_button.visible:
		_on_focus_changed(null)
	_prompt_refresh -= delta
	if _prompt_refresh <= 0.0 and is_instance_valid(_focused_interactable):
		_prompt_refresh = 0.15
		_refresh_prompt_text(_focused_interactable)
	_load_check -= delta
	if _load_check <= 0.0:
		_load_check = 0.5
		_update_weight_label()
	if _player == null:
		return
	if _bow_overlay != null and _player.has_method("get_bow_state"):
		_bow_overlay.call("update_state", _player.call("get_bow_state"))
	if _camera_joystick_vector != Vector2.ZERO and _player.has_method("apply_camera_joystick"):
		_player.call("apply_camera_joystick", _camera_joystick_vector, delta)
	if _player.has_method("get_heading_degrees"):
		var heading: float = _player.call("get_heading_degrees")
		compass_strip.heading = heading
		var rounded := int(roundf(heading)) % 360
		if rounded != _last_heading:
			_last_heading = rounded
			compass_label.text = "%s %03d°" % [tr(CompassStrip.cardinal_key(heading)), rounded]
		# Repère suivi : la boussole en montre le cap.
		var exploration := InteractionManager.get_exploration()
		if exploration != null and exploration.has_method("tracked_bearing"):
			compass_strip.marker_bearing = float(exploration.call("tracked_bearing", (_player as Node3D).global_position))
	# Grain film animé : petit décalage aléatoire du tile toutes les ~90 ms.
	_grain_timer += delta
	if _grain_timer >= 0.09 and fx_grain != null:
		_grain_timer = 0.0
		fx_grain.position = Vector2(randf_range(-4.0, 4.0), randf_range(-4.0, 4.0))

func _unhandled_input(event: InputEvent) -> void:
	# Clic sur la mini-carte : en jeu la souris est capturée, le clic n'atteint donc
	# jamais le contrôle ; on l'intercepte ici (marche aussi souris capturée).
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if minimap != null and minimap.visible and minimap.get_global_rect().has_point(event.position):
			_on_map_pressed()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).physical_keycode == KEY_H:
		if whistle_button != null and whistle_button.visible:
			_on_whistle_pressed()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventKey and event.pressed and not event.echo:
		var slot: int = int(event.physical_keycode) - int(KEY_1)
		if slot >= 0 and slot < 4:
			hotbar.call("select_index", slot)
			return
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).physical_keycode == KEY_C:
		open_character_panel()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("open_journal"):
		if character_panel != null and character_panel.visible:
			character_panel.close()
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
		if chest_panel != null and chest_panel.visible:
			chest_panel.close()
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
		if chest_panel != null and chest_panel.visible:
			chest_panel.close()
		map_panel.toggle()
		if map_panel.visible and journal_panel != null and journal_panel.visible:
			journal_panel.close()
	else:
		show_toast(tr("TOAST_SOON"))

## Deux sources de déplacement : le stick fixe et le stick flottant (zone gauche).
## Le plus incliné l'emporte, pour qu'un relâchement de l'un n'annule pas l'autre.
func _on_fixed_move(vector: Vector2) -> void:
	_move_fixed = vector
	_push_move()

func _on_float_move(vector: Vector2) -> void:
	_move_float = vector
	_push_move()

func _push_move() -> void:
	if _player == null:
		return
	_player.set_joystick_vector(_move_float if _move_float.length() > _move_fixed.length() else _move_fixed)

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

## Souris libérée quand un panneau est ouvert (clic carte/journal), recapturée à la fermeture.
func _sync_mouse_mode() -> void:
	if PlatformInfo.is_touch():
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _panels_open else Input.MOUSE_MODE_CAPTURED

## Le joueur vise à l'arc : le réticule reste actif même sans objet interactif visé.
func set_aiming(value: bool) -> void:
	_aiming = value
	reticle.call("set_focused", _aiming or _focused_interactable != null)

func _on_focus_changed(target: Node3D) -> void:
	var interactable: Interactable = null
	if target != null and is_instance_valid(target) and target is Interactable:
		interactable = target as Interactable
	_focused_interactable = interactable
	if interactable != null:
		_refresh_prompt_text(interactable)
		interact_prompt.visible = true
		interact_button.visible = true
		reticle.call("set_focused", true)
		_pulse_interact(not interact_button.disabled)
	else:
		interact_prompt.visible = false
		interact_button.disabled = true
		interact_button.visible = false
		reticle.call("set_focused", _aiming)
		_pulse_interact(false)

## Texte de l'invite : il peut changer pendant que l'objet reste visé (pêche, animal).
func _refresh_prompt_text(interactable: Interactable) -> void:
	var label := tr(interactable.get_prompt())
	if interactable.has_method("get_prompt_args"):
		var args: Array = interactable.call("get_prompt_args")
		if not args.is_empty() and "%" in label:
			label = label % args
	var text := label if PlatformInfo.is_touch() else "[%s] %s" % [_interact_key_text(), label]
	if interact_prompt.text != text:
		interact_prompt.text = text
	interact_button.disabled = not interactable.can_interact()

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

func _on_equipped_changed(_item_id: String) -> void:
	_refresh_attack_button()

func _on_item_removed(_item_id: String, _amount: int) -> void:
	_refresh_attack_button()

## Le bouton de tir n'apparaît (tactile) que lorsque l'arc de chasse est ÉQUIPÉ.
## Le bouton « Viser » n'apparaît que si l'arc est équipé : en visée, déplacer le
## viseur ne fait plus tourner le personnage.
func _refresh_attack_button() -> void:
	if _inventory == null:
		return
	if aim_button.button_pressed and not _inventory.is_equipped("tool_hunting_bow"):
		# Arc rangé : la visée s'arrête (sinon elle reprendrait au prochain équipement).
		aim_button.set_pressed_no_signal(false)
		_on_aim_toggled(false)
	if not PlatformInfo.is_touch():
		return
	var ready_to_shoot: bool = _inventory.is_equipped("tool_hunting_bow") or _inventory.is_equipped("tool_stone_axe")
	if attack_button.visible != ready_to_shoot:
		attack_button.visible = ready_to_shoot
	var bow: bool = _inventory.is_equipped("tool_hunting_bow")
	if aim_button.visible != bow:
		aim_button.visible = bow

	if bow:
		# Libellé sous l'icône (pas par-dessus).
		attack_button.text = tr("ACTION_FIRE")
		attack_button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		attack_button.add_theme_font_size_override("font_size", 15)
	else:
		# Hache : libellé « Frapper » pour ne pas confondre avec le bouton Action.
		attack_button.text = tr("ACTION_STRIKE")
		attack_button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		attack_button.add_theme_font_size_override("font_size", 15)

func _on_aim_toggled(pressed: bool) -> void:
	if _player != null and _player.has_method("set_aim_override"):
		_player.call("set_aim_override", pressed)

func _on_attack_down() -> void:
	if _player != null and _player.has_method("begin_attack"):
		_player.call("begin_attack")

func _on_attack_up() -> void:
	if _player != null and _player.has_method("end_attack"):
		_player.call("end_attack")

func _build_bow_overlay() -> void:
	_bow_overlay = Control.new()
	_bow_overlay.name = "BowOverlay"
	_bow_overlay.set_script(load("res://scripts/ui/bow_overlay.gd"))
	$Overlay.add_child(_bow_overlay)
	$Overlay.move_child(_bow_overlay, 0)

## Flèche au but : croix autour du viseur et petite vibration.
func notify_hit(_body: Node = null) -> void:
	if _bow_overlay != null:
		_bow_overlay.call("flash_hit")
	if PlatformInfo.is_touch():
		Input.vibrate_handheld(40)

func _build_gauge() -> void:
	_gauge = ProgressBar.new()
	_gauge.name = "ActionGauge"
	_gauge.min_value = 0.0
	_gauge.max_value = 1.0
	_gauge.step = 0.0
	_gauge.show_percentage = false
	_gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gauge.custom_minimum_size = Vector2(320.0, 22.0)
	_gauge.set_anchors_preset(Control.PRESET_CENTER)
	_gauge.offset_left = -160.0
	_gauge.offset_right = 160.0
	_gauge.offset_top = 150.0
	_gauge.offset_bottom = 172.0
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.0, 0.0, 0.0, 0.55)
	back.set_corner_radius_all(11)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.98, 0.74, 0.32)
	fill.set_corner_radius_all(11)
	_gauge.add_theme_stylebox_override("background", back)
	_gauge.add_theme_stylebox_override("fill", fill)
	_gauge.visible = false
	$Overlay.add_child(_gauge)
	_gauge_label = Label.new()
	_gauge_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gauge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gauge_label.set_anchors_preset(Control.PRESET_CENTER)
	_gauge_label.offset_left = -260.0
	_gauge_label.offset_right = 260.0
	_gauge_label.offset_top = 114.0
	_gauge_label.offset_bottom = 146.0
	_gauge_label.add_theme_font_size_override("font_size", 24)
	_gauge_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_gauge_label.add_theme_constant_override("outline_size", 6)
	_gauge_label.visible = false
	$Overlay.add_child(_gauge_label)

## Jauge d'action sous le viseur (remontée du poisson, etc.). `ratio` de 0 à 1.
func set_gauge(text: String, ratio: float) -> void:
	if _gauge == null:
		return
	_gauge.value = clampf(ratio, 0.0, 1.0)
	_gauge.visible = true
	_gauge_label.text = text
	_gauge_label.visible = text != ""

func clear_gauge() -> void:
	if _gauge != null:
		_gauge.visible = false
		_gauge_label.visible = false

# --- Endurance ------------------------------------------------------------------

## Jauges latérales : faim et soif suivent SurvivalManager, l'énergie suit le joueur.
func _on_needs_changed(hunger: float, thirst: float) -> void:
	vitals.call("set_value", "hunger", hunger)
	vitals.call("set_value", "thirst", thirst)

func _on_warmth_changed(warmth: float, felt: float) -> void:
	vitals.call("set_value", "warmth", warmth)
	var rounded := int(roundf(felt))
	if rounded != _shown_temperature:
		_shown_temperature = rounded
		if _day_night != null:
			_refresh_clock(float(_day_night.get("hour")))

func _on_health_changed(value: float) -> void:
	vitals.call("set_value", "health", value)
	# Un coup reçu fait flasher l'écran en rouge.
	if value < _last_health - 0.001:
		_flash_damage()
	_last_health = value

func _flash_damage() -> void:
	if _damage_flash == null:
		_damage_flash = ColorRect.new()
		_damage_flash.color = Color(0.8, 0.05, 0.05, 0.0)
		_damage_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_damage_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
		$Overlay.add_child(_damage_flash)
	_damage_flash.color.a = 0.38
	var tween := create_tween()
	tween.tween_property(_damage_flash, "color:a", 0.0, 0.45)

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

func _on_weather_changed(_value: String) -> void:
	if _day_night != null:
		_refresh_clock(float(_day_night.get("hour")))

func _on_phase_changed(_phase: String) -> void:
	if _day_night != null:
		_refresh_clock(float(_day_night.get("hour")))

func _refresh_clock(hour: float) -> void:
	var phase_text := ""
	if _day_night != null and _day_night.has_method("get_phase"):
		phase_text = tr("PHASE_" + String(_day_night.call("get_phase")).to_upper())
	var calendar := ""
	var weather := InteractionManager.get_weather()
	if weather != null and bool(weather.call("effects_active")):
		calendar = "  ·  %s, %s" % [tr("SEASON_" + String(weather.call("get_season")).to_upper()), tr("WEATHER_" + String(weather.call("get_weather")).to_upper())]
	if _shown_temperature != 9999:
		calendar += "  ·  %d °C" % _shown_temperature
		# L'heure suffit à dire jour ou nuit : on garde la place pour la température.
		phase_text = ""
	clock_label.text = "%02d:%02d%s%s" % [int(hour) % 24, int(fmod(hour, 1.0) * 60.0), "  " + phase_text if phase_text != "" else "", calendar]
	_fit_clock()

## Réduit la taille du texte de l'horloge s'il déborderait sur le ruban de boussole.
func _fit_clock() -> void:
	if compass_strip == null or not is_inside_tree():
		return
	var available := get_viewport().get_visible_rect().size.x * 0.5 - compass_strip.size.x * 0.5 - 28.0
	var font := clock_label.get_theme_font("font")
	var font_size := 28
	while font_size > 18 and font.get_string_size(clock_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > available:
		font_size -= 2
	clock_label.add_theme_font_size_override("font_size", font_size)

# --- Zone sûre (encoches, coins arrondis) ---------------------------------------

## Capture la mise en page d'origine en coordonnées ABSOLUES (layout_mode = 0) :
## _fit_to_viewport recalcule ensuite tout explicitement, à n'importe quelle taille.
func _capture_layout() -> void:
	var nodes: Array[Control] = [joystick, camera_joystick, action_pad, minimap, vitals, level_badge, quest_tracker, hotbar,
		weight_label, sprint_button, jump_button, interact_button, attack_button, aim_button]
	for node: Control in nodes:
		var rect := node.get_global_rect()
		node.layout_mode = 0
		node.offset_left = rect.position.x
		node.offset_top = rect.position.y
		node.offset_right = rect.end.x
		node.offset_bottom = rect.end.y
		_base_offsets[node] = Vector4(rect.position.x, rect.position.y, rect.end.x, rect.end.y)
	# Les contrôles restés en ancrage relatif gardent leurs offsets d'origine.
	for node: Control in [compass_strip, toast]:
		_anchor_base[node] = Vector4(node.offset_left, node.offset_top, node.offset_right, node.offset_bottom)
	_touch_look_base = Vector2(touch_look.get("move_zone_width"), touch_look.get("look_only_top"))
	_bottom_bar_home_index = bottom_bar.get_index()

func _apply_safe_area() -> void:
	var inset := _safe_insets()
	safe_area.add_theme_constant_override("margin_left", BASE_MARGIN + int(inset.x))
	safe_area.add_theme_constant_override("margin_top", BASE_MARGIN + int(inset.y))
	safe_area.add_theme_constant_override("margin_right", BASE_MARGIN + int(inset.z))
	safe_area.add_theme_constant_override("margin_bottom", BASE_MARGIN + int(inset.w))
	_shift(joystick, Vector2(inset.x, -inset.w))
	_shift(camera_joystick, Vector2(-inset.z, -inset.w))
	_shift(action_pad, Vector2(-inset.z, -inset.w))
	_fit_to_viewport()

func _shift(node: Control, offset: Vector2) -> void:
	if not _base_offsets.has(node):
		return
	var base: Vector4 = _base_offsets[node]
	node.offset_left = base.x + offset.x
	node.offset_right = base.z + offset.x
	node.offset_top = base.y + offset.y
	node.offset_bottom = base.w + offset.y

# --- Mise en page selon la taille d'écran -----------------------------------------

## Trois modes selon l'aspect de l'écran — la rotation du téléphone change la
## taille du viewport, le mode est donc réappliqué automatiquement (size_changed
## -> _apply_safe_area) :
## - portrait (vp.x < vp.y) : jeu « une main » (bloc portrait ci-dessous) ;
## - compact (petit écran paysage) : stick caméra masqué (glisser sur l'écran
##   suffit), mini-carte, jauges et hotbar réduits/replacés, pad d'actions au-dessus
##   du stick de déplacement, badge de niveau masqué ;
## - roomy (grand écran paysage) : mise en page d'origine de la scène.
## Dans tous les modes, aucun contrôle tactile ne chevauche un autre.
## `vp_override` sert aux tests (sinon taille réelle du viewport).
func _fit_to_viewport(vp_override: Vector2 = Vector2.ZERO) -> void:
	if _base_offsets.is_empty():
		return
	var vp := vp_override if vp_override.x > 0.0 else get_viewport().get_visible_rect().size
	# On restaure d'abord l'état paysage, puis le mode actif réécrit par-dessus.
	if _bottom_bar_home_index >= 0 and bottom_bar.get_index() != _bottom_bar_home_index:
		vbox.move_child(bottom_bar, _bottom_bar_home_index)
	bottom_bar.alignment = HBoxContainer.ALIGNMENT_CENTER
	touch_look.set("move_zone_width", _touch_look_base.x)
	touch_look.set("look_only_top", _touch_look_base.y)
	for node: Control in _anchor_base.keys():
		var a: Vector4 = _anchor_base[node]
		node.offset_left = a.x
		node.offset_top = a.y
		node.offset_right = a.z
		node.offset_bottom = a.w
	var portrait := vp.x < vp.y
	var compact := not portrait and (vp.x < 700.0 or vp.y < 800.0)
	if portrait:
		# Mode « une main » : téléphone tenu d'une main, le pouce joue en bas de
		# l'écran. La barre de menus remonte en haut à droite pour libérer les coins.
		var inset := _safe_insets()
		if bottom_bar.get_index() != 0:
			vbox.move_child(bottom_bar, 0)
		bottom_bar.alignment = HBoxContainer.ALIGNMENT_END
		touch_look.set("move_zone_width", 0.5)
		touch_look.set("look_only_top", 0.24)
		# Stick de déplacement fixe, en bas à gauche.
		var joy := clampf(vp.x * 0.5 - 40.0, 170.0, 220.0)
		_set_offsets(joystick, Vector4(24.0 + inset.x, vp.y - 8.0 - joy - inset.w, 24.0 + joy + inset.x, vp.y - 8.0 - inset.w))
		# Stick caméra masqué : le glisser sur l'écran (TouchLook) fait office de visée.
		camera_joystick.visible = false
		# Colonne d'actions ancrée en bas à droite, dans la portée du pouce :
		# Interagir en bas, puis Saut, Course, Frapper ; « Viser » à gauche de Frapper.
		action_pad.scale = Vector2.ONE
		var bs := clampf(vp.y * 0.09, 56.0, 76.0)
		var pad_w := bs + 16.0
		var pad_h := 4.0 * bs + 3.0 * 8.0 + 16.0
		_set_offsets(action_pad, Vector4(vp.x - 12.0 - pad_w - inset.z, vp.y - 8.0 - pad_h - inset.w, vp.x - 12.0 - inset.z, vp.y - 8.0 - inset.w))
		var pad_buttons: Array[Control] = [interact_button, jump_button, sprint_button, attack_button]
		for i in range(pad_buttons.size()):
			var y := pad_h - 8.0 - bs - float(i) * (bs + 8.0)
			_set_offsets(pad_buttons[i], Vector4(8.0, y, 8.0 + bs, y + bs))
		var fire_y := pad_h - 8.0 - bs - 3.0 * (bs + 8.0)
		_set_offsets(aim_button, Vector4(-bs - 8.0, fire_y, -8.0, fire_y + bs))
		# Haut d'écran : barre de menus (rangée du VBox) puis cap + horloge, d'où
		# l'empilement boussole / quête / jauges / mini-carte en dessous.
		var top := BASE_MARGIN + int(inset.y) + 120.0
		var strip_w := clampf(vp.x - 250.0, 110.0, 460.0)
		compass_strip.offset_left = -strip_w * 0.5
		compass_strip.offset_top = top
		compass_strip.offset_right = strip_w * 0.5
		compass_strip.offset_bottom = top + 52.0
		_set_offsets(quest_tracker, Vector4(16.0 + inset.x, top + 60.0, vp.x - 16.0 - inset.z, top + 104.0))
		# Jauges sous la quête, réduites.
		vitals.scale = Vector2(0.5, 0.5)
		vitals.pivot_offset = Vector2.ZERO
		var vitals_size := VitalsPanel.panel_size()
		_set_offsets(vitals, Vector4(16.0 + inset.x, top + 112.0, 16.0 + inset.x + vitals_size.x, top + 112.0 + vitals_size.y))
		# Mini-carte en haut à droite, réduite.
		_set_offsets(minimap, Vector4(vp.x - 116.0 - inset.z, top + 112.0, vp.x - 16.0 - inset.z, top + 212.0))
		# Hotbar au-dessus du stick de déplacement, à gauche.
		var hb: Vector4 = _base_offsets[hotbar]
		# On laisse aussi la place du bouton « Viser », qui dépasse à gauche du pad.
		var hw := minf(200.0, vp.x - 48.0 - pad_w - bs - 24.0)
		var h_bottom := vp.y - 8.0 - joy - 8.0 - inset.w
		_set_offsets(hotbar, Vector4(24.0 + inset.x, h_bottom - (hb.w - hb.y), 24.0 + inset.x + hw, h_bottom))
		# Badge de niveau masqué (le niveau reste visible dans le journal).
		level_badge.visible = false
		toast.offset_top = top + 112.0
		toast.offset_bottom = top + 112.0
	elif compact:
		var joy := 200.0
		# Stick de déplacement, en bas à gauche.
		_set_offsets(joystick, Vector4(30.0, vp.y - joy, 30.0 + joy, vp.y))
		# Stick caméra masqué : le glisser sur l'écran (TouchLook) fait office de visée.
		camera_joystick.visible = false
		# Pad d'actions en colonne verticale sur le bord droit (boutons 80 px).
		action_pad.scale = Vector2.ONE
		var pad_buttons: Array[Control] = [sprint_button, jump_button, interact_button, attack_button]
		for i in range(pad_buttons.size()):
			var y := 8.0 + i * 88.0
			_set_offsets(pad_buttons[i], Vector4(4.0, y, 84.0, y + 80.0))
		_set_offsets(action_pad, Vector4(vp.x - 96.0, 236.0, vp.x - 16.0, 244.0 + pad_buttons.size() * 88.0))
		# « Viser » à gauche de « Tirer » (la colonne ne tiendrait pas en hauteur).
		var fire_y := 8.0 + 3.0 * 88.0
		_set_offsets(aim_button, Vector4(-84.0, fire_y, -4.0, fire_y + 80.0))
		# Suivi de quête en haut à gauche (sous la boussole).
		_set_offsets(quest_tracker, Vector4(16.0, 64.0, vp.x - 16.0, 108.0))
		# Jauges sous la quête, réduites.
		vitals.scale = Vector2(0.5, 0.5)
		vitals.pivot_offset = Vector2.ZERO
		var vitals_size := VitalsPanel.panel_size()
		_set_offsets(vitals, Vector4(16.0, 116.0, 16.0 + vitals_size.x, 116.0 + vitals_size.y))
		# Poids du sac sous les jauges réduites.
		var wl_top := 116.0 + vitals_size.y * 0.5 + 6.0
		_set_offsets(weight_label, Vector4(16.0, wl_top, 260.0, wl_top + 32.0))
		# Mini-carte en haut à droite, réduite.
		_set_offsets(minimap, Vector4(vp.x - 136.0, 116.0, vp.x - 16.0, 236.0))
		# Hotbar au-dessus du stick de déplacement, à gauche.
		var hb: Vector4 = _base_offsets[hotbar]
		var hw := minf(200.0, vp.x - 62.0)
		var h_bottom := vp.y - joy - 8.0
		_set_offsets(hotbar, Vector4(30.0, h_bottom - (hb.w - hb.y), 30.0 + hw, h_bottom))
		# Badge de niveau masqué (le niveau reste visible dans le journal).
		level_badge.visible = false
	else:
		_set_offsets(joystick, _base_offsets[joystick])
		camera_joystick.visible = true
		_set_offsets(camera_joystick, _base_offsets[camera_joystick])
		# Pad d'actions : boutons restaurés, pad remonté au-dessus du stick caméra.
		action_pad.scale = Vector2.ONE
		for b: Control in [sprint_button, jump_button, interact_button, attack_button, aim_button]:
			_set_offsets(b, _base_offsets[b])
		var pb: Vector4 = _base_offsets[action_pad]
		var pad_bottom := vp.y - 320.0 - 12.0
		_set_offsets(action_pad, Vector4(pb.x, pad_bottom - 224.0, pb.z, pad_bottom))
		_set_offsets(minimap, _base_offsets[minimap])
		vitals.scale = Vector2.ONE
		_set_offsets(vitals, _base_offsets[vitals])
		_set_offsets(hotbar, _base_offsets[hotbar])
		_set_offsets(quest_tracker, _base_offsets[quest_tracker])
		_set_offsets(weight_label, _base_offsets[weight_label])
		level_badge.visible = true
	_layout_tutorial(vp)
	if build_panel != null:
		build_panel.fit(vp)

func _set_offsets(c: Control, v: Vector4) -> void:
	c.offset_left = v.x
	c.offset_top = v.y
	c.offset_right = v.z
	c.offset_bottom = v.w

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
