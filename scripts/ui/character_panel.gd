class_name CharacterPanel
extends PanelContainer
## Fenêtre « Personnage », façon poupée : l'aperçu 3D du héros au centre, entouré des
## emplacements de vêtements à leur place (chapeau en haut, bottes en bas, chemise / gants /
## pantalon à gauche, cape / sac à dos à droite). Toucher un emplacement affiche, à droite,
## les vêtements possédés pour cet emplacement (Porter / Retirer) et leur effet.

const ACCENT := Color(0.88, 0.64, 0.36, 1.0)
const BUTTON_HEIGHT := 52.0
const SLOT_NAMES := {"head": "SLOT_HEAD", "torso": "SLOT_TORSO", "body": "SLOT_BODY", "hands": "SLOT_HANDS",
		"legs": "SLOT_LEGS", "feet": "SLOT_FEET", "back": "SLOT_BACK"}
## Icône montrée (estompée) quand l'emplacement est vide.
const SLOT_ICONS := {"head": "gear_straw_hat", "torso": "gear_wool_shirt", "body": "armor_fur_cloak",
		"hands": "gear_leather_gloves", "legs": "gear_wool_trousers", "feet": "gear_hide_boots", "back": "gear_backpack"}
const LEFT_SLOTS := ["torso", "hands", "legs"]
const RIGHT_SLOTS := ["body", "back"]
const SLOT_SIZE := 78.0
## Effet de chaque vêtement (clé de traduction).
const GEAR_EFFECTS := {
	"gear_straw_hat": "GEAR_EFFECT_HAT",
	"armor_fur_cloak": "GEAR_EFFECT_CLOAK",
	"gear_hide_boots": "GEAR_EFFECT_BOOTS",
	"gear_backpack": "GEAR_EFFECT_BACKPACK",
	"gear_wool_shirt": "GEAR_EFFECT_SHIRT",
	"gear_wool_trousers": "GEAR_EFFECT_TROUSERS",
	"gear_leather_gloves": "GEAR_EFFECT_GLOVES",
}

var _inventory: Node
var _title: Label
var _slots_box: VBoxContainer
var _slot_buttons: Dictionary = {}
var _selected_slot: String = "head"
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
	# On ouvre sur le premier emplacement occupé.
	if _inventory != null:
		for slot in _inventory.get("GEAR_SLOTS"):
			if String(_inventory.call("worn_in", slot)) != "":
				_selected_slot = slot
				break
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
	row.add_theme_constant_override("separation", 10)
	column.add_child(row)

	row.add_child(_slot_column(LEFT_SLOTS))
	var middle := VBoxContainer.new()
	middle.add_theme_constant_override("separation", 4)
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.size_flags_stretch_ratio = 0.9
	row.add_child(middle)
	middle.add_child(_centered(_slot_button("head")))
	# Aperçu 3D : on le fait tourner en le faisant glisser.
	var container := SubViewportContainer.new()
	container.name = "Preview"
	container.stretch = true
	container.custom_minimum_size = Vector2(170, 170)
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.gui_input.connect(_on_preview_input)
	middle.add_child(container)
	middle.add_child(_centered(_slot_button("feet")))
	row.add_child(_slot_column(RIGHT_SLOTS))
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
	camera.position = Vector3(0.0, 0.9, 2.15)
	camera.rotation_degrees.x = -3.0
	camera.fov = 42.0
	_viewport.add_child(camera)
	_preview_root = Node3D.new()
	_preview_root.name = "PreviewRoot"
	_viewport.add_child(_preview_root)

	# Détail de l'emplacement choisi.
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_stretch_ratio = 1.3
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

func _slot_column(slots: Array) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 10)
	for slot in slots:
		column.add_child(_slot_button(slot))
	return column

func _centered(control: Control) -> CenterContainer:
	var center := CenterContainer.new()
	center.add_child(control)
	return center

## Case d'emplacement : icône du vêtement porté (ou icône estompée si vide) et son nom.
func _slot_button(slot: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	var button := Button.new()
	button.name = "Slot_" + slot
	button.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	button.focus_mode = Control.FOCUS_NONE
	button.toggle_mode = true
	button.pressed.connect(func():
		_selected_slot = slot
		refresh())
	var icon := ItemIcon.new()
	icon.name = "Icon"
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 10
	icon.offset_top = 10
	icon.offset_right = -10
	icon.offset_bottom = -10
	button.add_child(icon)
	box.add_child(button)
	var label := Label.new()
	label.text = tr(SLOT_NAMES[slot])
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	box.add_child(label)
	_slot_buttons[slot] = button
	return box

func selected_slot() -> String:
	return _selected_slot

func _refresh_slot_buttons() -> void:
	for slot in _slot_buttons:
		var button := _slot_buttons[slot] as Button
		var worn := String(_inventory.call("worn_in", slot)) if _inventory != null else ""
		var icon := button.get_node("Icon") as ItemIcon
		icon.set_item(worn if worn != "" else String(SLOT_ICONS[slot]))
		icon.modulate = Color(1, 1, 1, 1.0) if worn != "" else Color(1, 1, 1, 0.18)
		button.button_pressed = slot == _selected_slot
		button.tooltip_text = tr("ITEM_" + worn.to_upper()) if worn != "" else tr(SLOT_NAMES[slot])

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
	_refresh_slot_buttons()
	_add_slot(_selected_slot)
	var worn_now := String(_inventory.call("worn_in", _selected_slot))
	if worn_now != "":
		_add_effects_summary()
	var tool_id := String(_inventory.call("get_equipped"))
	var tool_label := Label.new()
	var tool_name := tr("ITEM_" + tool_id.to_upper()) if tool_id != "" else tr("SLOT_EMPTY")
	if tool_id != "" and bool(_inventory.call("is_iron_tool", tool_id)):
		tool_name = tr("TOOL_IRON_NAME") % tool_name
	tool_label.text = tr("CHARACTER_TOOL") % tool_name
	tool_label.add_theme_font_size_override("font_size", 17)
	tool_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	_slots_box.add_child(tool_label)
	_add_forge_row(tool_id)

static func _cap(text: String) -> String:
	return text.substr(0, 1).to_upper() + text.substr(1) if text != "" else text

## « Chemise de laine : 3 laine, niveau 3 » (recette de fabrication).
func _recipe_hint(item_id: String) -> String:
	var craft := get_node_or_null("/root/CraftManager")
	if craft == null:
		return ""
	var recipes: Dictionary = craft.get("RECIPES")
	if not recipes.has(item_id):
		return ""
	var recipe: Dictionary = recipes[item_id]
	var parts: PackedStringArray = []
	for ingredient in recipe["ingredients"]:
		parts.append("%d %s" % [int(recipe["ingredients"][ingredient]), tr("ITEM_" + String(ingredient).to_upper())])
	return tr("SLOT_RECIPE") % [tr(String(recipe["name"])), ", ".join(parts), int(recipe.get("level", 1))]

## Rappel de tous les effets actifs (vêtements portés).
func _add_effects_summary() -> void:
	var effects: PackedStringArray = []
	for item_id in _inventory.call("get_worn"):
		effects.append(tr("GEAR_EFFECT_LINE") % [_cap(tr("ITEM_" + String(item_id).to_upper())), int(_inventory.call("gear_level", item_id)), effect_text(item_id, int(_inventory.call("gear_level", item_id)))])
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = tr("CHARACTER_EFFECTS") + "\n" + "\n".join(effects)
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(1, 0.95, 0.85, 0.8))
	_slots_box.add_child(label)

func _add_slot(slot: String) -> void:
	var worn := String(_inventory.call("worn_in", slot))
	var header := Label.new()
	header.text = tr(SLOT_NAMES[slot])
	header.add_theme_font_size_override("font_size", 19)
	header.add_theme_color_override("font_color", ACCENT)
	_slots_box.add_child(header)
	var owned: Array = _inventory.call("owned_gear", slot)
	if owned.is_empty():
		var none := Label.new()
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		none.text = tr("SLOT_NOTHING_OWNED") + "\n" + _recipe_hint(String(SLOT_ICONS[slot]))
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
		var level := int(_inventory.call("gear_level", item_id))
		text.text = "%s — %s\n%s" % [_cap(tr("ITEM_" + String(item_id).to_upper())), tr("GEAR_LEVEL") % [level, 3], effect_text(item_id, level)]
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
		_add_upgrade_row(item_id)


## « chaleur +3 °C, dégâts reçus −45 % » : effets d'un vêtement à un niveau donné.
func effect_text(item_id: String, level: int) -> String:
	var parts: PackedStringArray = []
	var stats: Dictionary = _inventory.get("GEAR_STATS").get(item_id, {})
	for stat in stats:
		var value: float = _inventory.call("gear_stat_value", item_id, stat, level)
		match String(stat):
			"heat":
				parts.append(tr("GEAR_STAT_HEAT") % _num(value))
			"damage":
				parts.append(tr("GEAR_STAT_DAMAGE") % int(round(value * 100.0)))
			"thirst":
				parts.append(tr("GEAR_STAT_THIRST") % int(round(value * 100.0)))
			"speed":
				parts.append(tr("GEAR_STAT_SPEED") % int(round(value * 100.0)))
			"capacity":
				parts.append(tr("GEAR_STAT_CAPACITY") % int(value))
	return ", ".join(parts)

static func _num(value: float) -> String:
	return str(int(value)) if is_equal_approx(value, round(value)) else ("%.1f" % value).replace(".", ",")

## Amélioration d'un vêtement : coût (vert / rouge), niveau de joueur requis, bouton.
func _add_upgrade_row(item_id: String) -> void:
	var level := int(_inventory.call("gear_level", item_id))
	if level >= int(_inventory.get("GEAR_MAX_LEVEL")):
		return
	var cost: Dictionary = _inventory.call("gear_upgrade_cost", item_id)
	var required := int(_inventory.call("gear_upgrade_required_level", item_id))
	var progression := get_node_or_null("/root/Progression")
	var player_level := int(progression.call("get_level")) if progression != null else 1
	var parts: PackedStringArray = []
	var enough := true
	for ingredient in cost:
		var have := int(_inventory.call("count_of", ingredient))
		var need := int(cost[ingredient])
		enough = enough and have >= need
		parts.append("[color=%s]%d/%d %s[/color]" % ["#8fe08f" if have >= need else "#ff8a7a", have, need, tr("ITEM_" + String(ingredient).to_upper())])
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var info := RichTextLabel.new()
	info.bbcode_enabled = true
	info.fit_content = true
	info.scroll_active = false
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_font_size_override("normal_font_size", 15)
	info.text = tr("GEAR_UPGRADE_INFO") % [level + 1, effect_text(item_id, level + 1), ", ".join(parts),
			"#8fe08f" if player_level >= required else "#ff8a7a", required]
	row.add_child(info)
	var button := Button.new()
	button.name = "Upgrade_" + item_id
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(130, BUTTON_HEIGHT * 0.85)
	button.text = tr("ACTION_UPGRADE_SHORT")
	button.disabled = not enough or player_level < required
	button.pressed.connect(func():
		var error: String = _inventory.call("upgrade_gear", item_id)
		var hud := get_tree().get_first_node_in_group("hud")
		if hud != null and hud.has_method("show_toast"):
			if error == "":
				hud.show_toast(tr("TOAST_UPGRADED") % int(_inventory.call("gear_level", item_id)))
			elif error == "TOAST_UPGRADE_LEVEL":
				hud.show_toast(tr(error) % required)
			elif error != "TOAST_UPGRADE_MISSING":
				hud.show_toast(tr(error))
		refresh())
	row.add_child(button)
	_slots_box.add_child(row)


## Forger l'outil en main en fer : coût (vert / rouge), niveau requis, effet, bouton.
func _add_forge_row(tool_id: String) -> void:
	var iron_tools: Dictionary = _inventory.get("IRON_TOOLS")
	if tool_id == "" or not iron_tools.has(tool_id) or bool(_inventory.call("is_iron_tool", tool_id)):
		return
	var cost: Dictionary = iron_tools[tool_id]
	var required := int(_inventory.get("IRON_TOOL_PLAYER_LEVEL"))
	var progression := get_node_or_null("/root/Progression")
	var player_level := int(progression.call("get_level")) if progression != null else 1
	var parts: PackedStringArray = []
	var enough := true
	for ingredient in cost:
		var have := int(_inventory.call("count_of", ingredient))
		var need := int(cost[ingredient])
		enough = enough and have >= need
		parts.append("[color=%s]%d/%d %s[/color]" % ["#8fe08f" if have >= need else "#ff8a7a", have, need, tr("ITEM_" + String(ingredient).to_upper())])
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var info := RichTextLabel.new()
	info.bbcode_enabled = true
	info.fit_content = true
	info.scroll_active = false
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_font_size_override("normal_font_size", 15)
	info.text = tr("TOOL_FORGE_INFO") % [tr("TOOL_IRON_EFFECT_" + tool_id.to_upper()), ", ".join(parts),
			"#8fe08f" if player_level >= required else "#ff8a7a", required]
	row.add_child(info)
	var button := Button.new()
	button.name = "Forge_" + tool_id
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(130, BUTTON_HEIGHT * 0.85)
	button.text = tr("ACTION_FORGE")
	button.disabled = not enough or player_level < required
	button.pressed.connect(func():
		var error: String = _inventory.call("forge_iron_tool", tool_id)
		var hud := get_tree().get_first_node_in_group("hud")
		if hud != null and hud.has_method("show_toast"):
			if error == "":
				hud.show_toast(tr("TOAST_FORGED") % tr("ITEM_" + tool_id.to_upper()))
			elif error == "TOAST_UPGRADE_LEVEL":
				hud.show_toast(tr(error) % required)
			elif error != "TOAST_UPGRADE_MISSING":
				hud.show_toast(tr(error))
		refresh())
	row.add_child(button)
	_slots_box.add_child(row)
