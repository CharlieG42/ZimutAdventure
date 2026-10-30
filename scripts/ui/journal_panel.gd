class_name JournalPanel
extends PanelContainer
## Journal à onglets : Quêtes (avec progression), Fabrication (par catégorie, avec
## les ingrédients manquants) et Sac. Se met à jour en direct quand l'inventaire ou
## une quête change, et s'adapte à la taille de l'écran (défilement tactile).

const ACCENT := Color(0.88, 0.64, 0.36, 1.0)
const GOOD := Color(0.62, 0.85, 0.5, 1.0)
const BAD := Color(0.95, 0.5, 0.4, 1.0)
const DIM := Color(1, 1, 1, 0.6)
const BUTTON_HEIGHT := 56.0

var _tabs: TabContainer
var _quests_list: VBoxContainer
var _craft_list: VBoxContainer
var _inventory_list: VBoxContainer
var _close_button: Button
var _quest_manager: Node
var _craft_manager: Node
var _inventory: Node

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var tree := get_tree()
	if tree != null and tree.root != null:
		_quest_manager = tree.root.get_node_or_null("QuestManager")
		_craft_manager = tree.root.get_node_or_null("CraftManager")
	_inventory = InteractionManager.get_inventory()
	_build()
	_connect_live_updates()
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
	_refresh()

func close() -> void:
	visible = false

## Numéro de l'onglet affiché (0 quêtes, 1 fabrication, 2 sac).
func show_tab(index: int) -> void:
	if _tabs != null:
		_tabs.current_tab = clampi(index, 0, _tabs.get_tab_count() - 1)

func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

# --- Construction ----------------------------------------------------------------

func _build() -> void:
	add_theme_stylebox_override("panel", _box(Color(0.1, 0.065, 0.04, 0.94), ACCENT, 3, 18, 14))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_theme_font_size_override("font_size", 22)
	box.add_child(_tabs)

	_quests_list = _add_tab(tr("JOURNAL_QUESTS"))
	_craft_list = _add_tab(tr("JOURNAL_CRAFT"))
	_inventory_list = _add_tab(tr("JOURNAL_INVENTORY_TITLE"))

	_close_button = Button.new()
	_close_button.text = tr("ACTION_CLOSE")
	_close_button.custom_minimum_size = Vector2(0, BUTTON_HEIGHT)
	_close_button.focus_mode = Control.FOCUS_NONE
	_close_button.pressed.connect(close)
	box.add_child(_close_button)
	add_child(box)

func _add_tab(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.name = title
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)
	_tabs.add_child(scroll)
	return list

## Taille du journal : confortable sur tablette, tient sur un téléphone en paysage.
func _fit_to_viewport() -> void:
	var viewport_size := get_viewport_rect().size
	custom_minimum_size = Vector2(
		clampf(viewport_size.x - 160.0, 360.0, 780.0),
		clampf(viewport_size.y - 150.0, 240.0, 520.0))

func _connect_live_updates() -> void:
	if _quest_manager != null:
		_quest_manager.connect("quest_state_changed", _on_data_changed)
		_quest_manager.connect("quest_progress_changed", _on_data_changed)
	if _inventory != null:
		_inventory.connect("item_added", _on_data_changed)
		_inventory.connect("item_removed", _on_data_changed)

func _on_data_changed(_a = null, _b = null, _c = null) -> void:
	if visible:
		_refresh.call_deferred()

func _refresh() -> void:
	_refresh_quests()
	_refresh_craft()
	_refresh_inventory()

# --- Quêtes ------------------------------------------------------------------------

func _refresh_quests() -> void:
	_clear(_quests_list)
	if _quest_manager == null:
		return
	var active: Array = _quest_manager.call("get_active")
	var completed: Array = _quest_manager.call("get_completed")
	var locked: Array = _quest_manager.call("get_locked")
	if active.is_empty() and completed.is_empty():
		_add_label(_quests_list, tr("QUEST_NONE"), 18, DIM)
		return
	for quest_id in active:
		_quests_list.add_child(_quest_card(quest_id, false))
	if not locked.is_empty():
		_add_label(_quests_list, tr("QUEST_LOCKED_HINT"), 16, DIM)
	if not completed.is_empty():
		_add_label(_quests_list, tr("JOURNAL_DONE"), 18, ACCENT)
		for quest_id in completed:
			_quests_list.add_child(_quest_card(quest_id, true))

func _quest_card(quest_id: String, done: bool) -> Control:
	var card := PanelContainer.new()
	var fill := Color(0.12, 0.2, 0.1, 0.8) if done else Color(0.18, 0.115, 0.065, 0.85)
	var border := Color(GOOD, 0.7) if done else Color(ACCENT, 0.6)
	card.add_theme_stylebox_override("panel", _box(fill, border, 2, 12, 12))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)

	var title := Label.new()
	title.text = ("✓  " if done else "◆  ") + tr(_quest_manager.call("get_title", quest_id))
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", GOOD if done else Color(1, 0.95, 0.85))
	box.add_child(title)

	var desc := Label.new()
	desc.text = tr(_quest_manager.call("get_description", quest_id))
	desc.add_theme_font_size_override("font_size", 17)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.modulate = Color(1, 1, 1, 0.8)
	box.add_child(desc)

	var progress: Vector2i = _quest_manager.call("get_progress", quest_id)
	var bar := ProgressBar.new()
	bar.theme_type_variation = &"StaminaBar"
	bar.custom_minimum_size = Vector2(0, 14)
	bar.max_value = maxf(1.0, float(progress.y))
	bar.value = float(progress.x)
	bar.show_percentage = false
	box.add_child(bar)

	var count := Label.new()
	count.text = "%d / %d" % [progress.x, progress.y]
	count.add_theme_font_size_override("font_size", 15)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count.modulate = DIM
	box.add_child(count)
	return card

# --- Fabrication --------------------------------------------------------------------

func _refresh_craft() -> void:
	_clear(_craft_list)
	if _craft_manager == null:
		return
	for category in _craft_manager.get("CATEGORIES"):
		var recipes: Array = _craft_manager.call("get_recipes_in_category", category)
		if recipes.is_empty():
			continue
		_add_label(_craft_list, tr("CAT_" + String(category).to_upper()), 18, ACCENT)
		for recipe_id in recipes:
			_craft_list.add_child(_recipe_row(recipe_id))

func _recipe_row(recipe_id: String) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _box(Color(0.18, 0.115, 0.065, 0.85), Color(ACCENT, 0.4), 2, 12, 10))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)
	row.add_child(info)

	var name_label := Label.new()
	var recipe_name: String = _craft_manager.call("get_recipe_name", recipe_id)
	name_label.text = tr(recipe_name)
	name_label.add_theme_font_size_override("font_size", 21)
	info.add_child(name_label)

	var ingredients: Dictionary = _craft_manager.call("get_ingredients", recipe_id)
	var missing: Dictionary = _craft_manager.call("get_missing", recipe_id)
	var cost := RichTextLabel.new()
	cost.bbcode_enabled = true
	cost.fit_content = true
	cost.scroll_active = false
	cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cost.add_theme_font_size_override("normal_font_size", 16)
	var parts: PackedStringArray = []
	for item_id in ingredients:
		var enough := int(missing.get(item_id, 0)) == 0
		var have := int(ingredients[item_id]) - int(missing.get(item_id, 0))
		parts.append("[color=#%s]%d/%d %s[/color]" % [
			(GOOD if enough else BAD).to_html(false), have, int(ingredients[item_id]),
			tr("ITEM_" + String(item_id).to_upper())])
	cost.text = "   ".join(parts)
	info.add_child(cost)

	var owned := _owned_count(recipe_id)
	if owned > 0:
		_add_label(info, tr("CRAFT_OWNED") % owned, 14, DIM)

	var button := Button.new()
	button.text = tr("ACTION_CRAFT")
	button.custom_minimum_size = Vector2(150, BUTTON_HEIGHT)
	button.focus_mode = Control.FOCUS_NONE
	button.disabled = not bool(_craft_manager.call("can_craft", recipe_id))
	button.pressed.connect(_on_craft_pressed.bind(recipe_id))
	row.add_child(button)
	return card

func _owned_count(item_id: String) -> int:
	return int(_inventory.call("count_of", item_id)) if _inventory != null else 0

func _on_craft_pressed(recipe_id: String) -> void:
	if _craft_manager != null and _craft_manager.call("craft", recipe_id):
		var recipe_name: String = _craft_manager.call("get_recipe_name", recipe_id)
		_notify(tr("TOAST_CRAFTED") % tr(recipe_name))
		_refresh()

# --- Sac ---------------------------------------------------------------------------

func _refresh_inventory() -> void:
	_clear(_inventory_list)
	if _inventory == null:
		return
	var all: Dictionary = _inventory.get_all()
	if all.is_empty():
		_add_label(_inventory_list, tr("INVENTORY_EMPTY"), 18, DIM)
		return
	var ids := all.keys()
	ids.sort()
	for item_id in ids:
		var label := Label.new()
		label.text = "%s  ×%d" % [tr("ITEM_" + String(item_id).to_upper()), int(all[item_id])]
		label.add_theme_font_size_override("font_size", 22)
		_inventory_list.add_child(label)

# --- Utilitaires ---------------------------------------------------------------------

func _clear(container: Container) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()

func _add_label(parent: Container, text: String, size: int, color: Color = Color.WHITE) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.modulate = color
	parent.add_child(label)

func _box(fill: Color, border: Color, border_width: int, radius: int, margin: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(margin)
	return style

func _notify(message: String) -> void:
	var hud := get_tree().get_first_node_in_group("hud") as Node
	if hud != null and hud.has_method("show_toast"):
		hud.show_toast(message)
