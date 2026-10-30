class_name JournalPanel
extends PanelContainer
## Journal à onglets : Quêtes, Fabrication (construction), Sac.

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
	visible = false

func toggle() -> void:
	if visible:
		close()
	else:
		open()

func open() -> void:
	visible = true
	_refresh()

func close() -> void:
	visible = false

func _build() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_tabs = TabContainer.new()
	_tabs.custom_minimum_size = Vector2(440, 320)
	box.add_child(_tabs)

	_quests_list = VBoxContainer.new()
	_quests_list.add_theme_constant_override("separation", 8)
	_tabs.add_child(_quests_list)
	_tabs.set_tab_title(0, tr("JOURNAL_QUESTS"))

	_craft_list = VBoxContainer.new()
	_craft_list.add_theme_constant_override("separation", 8)
	_tabs.add_child(_craft_list)
	_tabs.set_tab_title(1, tr("JOURNAL_CRAFT"))

	_inventory_list = VBoxContainer.new()
	_inventory_list.add_theme_constant_override("separation", 6)
	_tabs.add_child(_inventory_list)
	_tabs.set_tab_title(2, tr("JOURNAL_INVENTORY_TITLE"))

	_close_button = Button.new()
	_close_button.text = tr("ACTION_CLOSE")
	_close_button.pressed.connect(close)
	box.add_child(_close_button)
	add_child(box)

func _refresh() -> void:
	_refresh_quests()
	_refresh_craft()
	_refresh_inventory()

# --- Quêtes ------------------------------------------------------------------

func _refresh_quests() -> void:
	for child in _quests_list.get_children():
		child.queue_free()
	if _quest_manager == null:
		return
	var active: Array = _quest_manager.call("get_active")
	var completed: Array = _quest_manager.call("get_completed")
	if active.is_empty() and completed.is_empty():
		_add_label(_quests_list, tr("QUEST_NONE"), 18)
		return
	for quest_id in completed:
		_add_quest(quest_id, true)
	for quest_id in active:
		_add_quest(quest_id, false)

func _add_quest(quest_id: String, done: bool) -> void:
	var box := VBoxContainer.new()
	var title := Label.new()
	var title_key: String = _quest_manager.call("get_title", quest_id)
	title.text = ("[✓] " if done else "[ ] ") + tr(title_key)
	title.add_theme_font_size_override("font_size", 22)
	box.add_child(title)
	var desc := Label.new()
	var desc_key: String = _quest_manager.call("get_description", quest_id)
	desc.text = tr(desc_key)
	desc.add_theme_font_size_override("font_size", 17)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(desc)
	var sep := HSeparator.new()
	box.add_child(sep)
	_quests_list.add_child(box)

# --- Fabrication ----------------------------------------------------------------

func _refresh_craft() -> void:
	for child in _craft_list.get_children():
		child.queue_free()
	if _craft_manager == null:
		return
	var recipes: Array = _craft_manager.call("get_recipe_ids")
	for recipe_id in recipes:
		var row := HBoxContainer.new()
		var label := Label.new()
		var name_key: String = _craft_manager.call("get_recipe_name", recipe_id)
		label.text = tr(name_key)
		label.add_theme_font_size_override("font_size", 20)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var button := Button.new()
		var craftable: bool = _craft_manager.call("can_craft", recipe_id)
		button.disabled = not craftable
		button.text = tr("ACTION_CRAFT")
		button.pressed.connect(_on_craft_pressed.bind(recipe_id))
		row.add_child(button)
		var cost := Label.new()
		var cost_text := _ingredients_text(recipe_id)
		cost.text = cost_text
		cost.add_theme_font_size_override("font_size", 15)
		cost.modulate = Color(1, 1, 1, 0.7)
		_craft_list.add_child(row)
		_craft_list.add_child(cost)

func _ingredients_text(recipe_id: String) -> String:
	var parts: PackedStringArray = []
	var ingredients: Dictionary = _craft_manager.call("get_ingredients", recipe_id)
	for item_id in ingredients:
		parts.append("%dx %s" % [int(ingredients[item_id]), tr("ITEM_" + item_id.to_upper())])
	return "  ".join(parts)

func _on_craft_pressed(recipe_id: String) -> void:
	if _craft_manager != null and _craft_manager.call("craft", recipe_id):
		_notify(tr("TOAST_CRAFTED") % tr(_craft_manager.call("get_recipe_name", recipe_id)))
		_refresh()

# --- Sac ------------------------------------------------------------------------

func _refresh_inventory() -> void:
	for child in _inventory_list.get_children():
		child.queue_free()
	if _inventory == null:
		return
	var all: Dictionary = _inventory.get_all()
	if all.is_empty():
		_add_label(_inventory_list, tr("INVENTORY_EMPTY"), 18)
		return
	for item_id in all:
		var label := Label.new()
		label.text = "%s  ×%d" % [tr("ITEM_" + String(item_id).to_upper()), int(all[item_id])]
		label.add_theme_font_size_override("font_size", 20)
		_inventory_list.add_child(label)

func _add_label(parent: Container, text: String, size: int) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	parent.add_child(label)

func _notify(message: String) -> void:
	var hud := get_tree().get_first_node_in_group("hud") as Node
	if hud != null and hud.has_method("show_toast"):
		hud.show_toast(message)
