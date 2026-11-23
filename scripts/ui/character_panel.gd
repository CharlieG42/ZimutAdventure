class_name CharacterPanel
extends PanelContainer
## Fenêtre « Personnage » : aperçu 3D du héros avec ce qu'il porte, et ses vêtements par
## emplacement (tête, corps, pieds, dos). On y porte ou retire chapeau, cape, bottes et sac
## à dos possédés ; chaque vêtement indique son effet.

const ACCENT := Color(0.88, 0.64, 0.36, 1.0)
const BUTTON_HEIGHT := 52.0
const SLOT_NAMES := {"head": "SLOT_HEAD", "body": "SLOT_BODY", "feet": "SLOT_FEET", "back": "SLOT_BACK"}
## Effet de chaque vêtement (clé de traduction).
const GEAR_EFFECTS := {
	"gear_straw_hat": "GEAR_EFFECT_HAT",
	"armor_fur_cloak": "GEAR_EFFECT_CLOAK",
	"gear_hide_boots": "GEAR_EFFECT_BOOTS",
	"gear_backpack": "GEAR_EFFECT_BACKPACK",
}

var _inventory: Node
var _title: Label
var _slots_box: VBoxContainer
var _viewport: SubViewport
var _preview_root: Node3D
var _preview_hero: Node3D
var _turn: float = 0.6
var _dragging: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_inventory = get_node_or_null("/root/Inventory")
	_build()
	if _inventory != null:
		_inventory.connect("worn_changed", _on_changed)
		_inventory.connect("item_added", func(_id, _n): _on_changed())
		_inventory.connect("item_removed", func(_id, _n): _on_changed())
	get_viewport().size_changed.connect(_fit_to_viewport)
	_fit_to_viewport()
	visible = false

func toggle() -> void:
	if visible:
		close()
	else:
		open()

func open() -> void:
	visible = true
	_fit_to_viewport()
	_rebuild_preview()
	refresh()

func close() -> void:
	visible = false
	if _viewport != null:
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not visible or _preview_root == null:
		return
	if not _dragging:
		_turn += delta * 0.35
	_preview_root.rotation.y = _turn

func _fit_to_viewport() -> void:
	var viewport_size := get_viewport_rect().size
	custom_minimum_size = Vector2(
		clampf(viewport_size.x - 160.0, 360.0, 820.0),
		clampf(viewport_size.y - 150.0, 240.0, 540.0))

# --- Construction ---------------------------------------------------------------------

func _build() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.065, 0.04, 0.94)
	style.border_color = ACCENT
	style.set_border_width_all(3)
	style.set_corner_radius_all(18)
	style.set_content_margin_all(14)
	add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	add_child(column)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 24)
	_title.add_theme_color_override("font_color", ACCENT)
	column.add_child(_title)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 14)
	column.add_child(row)

	# Aperçu 3D : on le fait tourner en le faisant glisser.
	var container := SubViewportContainer.new()
	container.name = "Preview"
	container.stretch = true
	container.custom_minimum_size = Vector2(240, 300)
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.size_flags_stretch_ratio = 0.8
	container.gui_input.connect(_on_preview_input)
	row.add_child(container)
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_2X
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	container.add_child(_viewport)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1.0, 0.92, 0.82)
	env.ambient_light_energy = 0.55
	environment.environment = env
	_viewport.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35.0, 30.0, 0.0)
	sun.light_energy = 1.2
	_viewport.add_child(sun)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 1.0, 2.7)
	camera.rotation_degrees.x = -4.0
	camera.fov = 42.0
	_viewport.add_child(camera)
	_preview_root = Node3D.new()
	_preview_root.name = "PreviewRoot"
	_viewport.add_child(_preview_root)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(scroll)
	_slots_box = VBoxContainer.new()
	_slots_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slots_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_slots_box)

	var close_button := Button.new()
	close_button.text = tr("ACTION_CLOSE")
	close_button.custom_minimum_size = Vector2(0, BUTTON_HEIGHT)
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(close)
	column.add_child(close_button)

func _on_preview_input(event: InputEvent) -> void:
	if event is InputEventMouseButton or event is InputEventScreenTouch:
		_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		_turn += (event as InputEventMouseMotion).relative.x * 0.012
	elif event is InputEventScreenDrag:
		_turn += (event as InputEventScreenDrag).relative.x * 0.012

func _on_changed() -> void:
	if not visible:
		return
	refresh()

# --- Contenu ----------------------------------------------------------------------------------

## Le héros de l'aperçu : même modèle et même apparence que dans le monde.
func _rebuild_preview() -> void:
	if _preview_hero != null and is_instance_valid(_preview_hero):
		_preview_root.remove_child(_preview_hero)
		_preview_hero.queue_free()
		_preview_hero = null
	var hero := Node3D.new()
	hero.name = "PreviewHero"
	var profile := CharacterProfile.load_saved()
	var loaded := false
	for script_path in ["res://scripts/player/glb_hero.gd", "res://scripts/player/lowpoly_hero.gd"]:
		hero.set_script(load(script_path))
		hero.set("profile", profile)
		_preview_root.add_child(hero)
		if bool(hero.call("load_model")):
			loaded = true
			break
		_preview_root.remove_child(hero)
	if not loaded:
		hero.free()
		return
	_preview_hero = hero
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

func preview_hero() -> Node3D:
	return _preview_hero

func refresh() -> void:
	var profile := CharacterProfile.load_saved()
	var progression := get_node_or_null("/root/Progression")
	var level := int(progression.call("get_level")) if progression != null else 1
	_title.text = tr("CHARACTER_TITLE") % [profile.display_name(), level]
	if _preview_hero != null and _inventory != null:
		_preview_hero.call("set_gear", _inventory.call("get_worn"))
		_preview_hero.call("set_held_tool", String(_inventory.call("get_equipped")))
	for child in _slots_box.get_children():
		_slots_box.remove_child(child)
		child.queue_free()
	if _inventory == null:
		return
	for slot in _inventory.get("GEAR_SLOTS"):
		_add_slot(slot)
	var tool_id := String(_inventory.call("get_equipped"))
	var tool_label := Label.new()
	tool_label.text = tr("CHARACTER_TOOL") % (tr("ITEM_" + tool_id.to_upper()) if tool_id != "" else tr("SLOT_EMPTY"))
	tool_label.add_theme_font_size_override("font_size", 17)
	tool_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	_slots_box.add_child(tool_label)

func _add_slot(slot: String) -> void:
	var worn := String(_inventory.call("worn_in", slot))
	var header := Label.new()
	header.text = tr(SLOT_NAMES[slot])
	header.add_theme_font_size_override("font_size", 16)
	header.add_theme_color_override("font_color", ACCENT)
	_slots_box.add_child(header)
	var owned: Array = _inventory.call("owned_gear", slot)
	if owned.is_empty():
		var none := Label.new()
		none.text = tr("SLOT_NOTHING_OWNED")
		none.add_theme_font_size_override("font_size", 16)
		none.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
		_slots_box.add_child(none)
		return
	for item_id in owned:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		var text := Label.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.text = "%s — %s" % [tr("ITEM_" + String(item_id).to_upper()).capitalize(), tr(GEAR_EFFECTS.get(item_id, ""))]
		text.add_theme_font_size_override("font_size", 17)
		line.add_child(text)
		var button := Button.new()
		button.name = "Wear_" + String(item_id)
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(130, BUTTON_HEIGHT * 0.85)
		if worn == item_id:
			button.text = tr("ACTION_TAKE_OFF")
			button.pressed.connect(func(): _inventory.call("take_off", slot))
		else:
			button.text = tr("ACTION_WEAR")
			button.pressed.connect(func(): _inventory.call("wear", item_id))
		line.add_child(button)
		_slots_box.add_child(line)
