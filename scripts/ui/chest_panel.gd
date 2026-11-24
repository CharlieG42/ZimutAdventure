class_name ChestPanel
extends PanelContainer
## Panneau du coffre : choisir quels objets déposer (sac -> coffre) ou reprendre
## (coffre -> sac), type d'objet par type d'objet ou tout d'un coup. Deux colonnes
## côte à côte en paysage, empilées en portrait. Se met à jour en direct (signaux
## de l'inventaire et du coffre) et se ferme par ui_cancel.

const ACCENT := Color(0.88, 0.64, 0.36, 1.0)
const DIM := Color(1, 1, 1, 0.6)
const BUTTON_HEIGHT := 56.0

var _chest: Node = null
var _inventory: Node
var _wide_box: HBoxContainer
var _tall_box: VBoxContainer
var _bag_col: VBoxContainer
var _stock_col: VBoxContainer
var _bag_list: VBoxContainer
var _stock_list: VBoxContainer

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_inventory = InteractionManager.get_inventory()
	_build()
	if _inventory != null:
		_inventory.connect("item_added", _on_data_changed)
		_inventory.connect("item_removed", _on_data_changed)
	get_viewport().size_changed.connect(_fit_to_viewport)
	_fit_to_viewport()
	visible = false

func toggle(chest: Node) -> void:
	if visible and _chest == chest:
		close()
	else:
		open(chest)

func open(chest: Node) -> void:
	if _chest != null and is_instance_valid(_chest) and _chest != chest \
			and _chest.has_signal("changed") and _chest.is_connected("changed", _on_chest_changed):
		_chest.disconnect("changed", _on_chest_changed)
	_chest = chest
	if _chest != null and _chest.has_signal("changed") and not _chest.is_connected("changed", _on_chest_changed):
		_chest.connect("changed", _on_chest_changed)
	visible = true
	_fit_to_viewport()
	refresh()

func close() -> void:
	visible = false
	_chest = null

func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

func _on_data_changed(_a = null, _b = null) -> void:
	refresh.call_deferred()

func _on_chest_changed(_chest_node = null) -> void:
	refresh.call_deferred()

# --- Construction -----------------------------------------------------------------

func _build() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	add_child(root)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	root.add_child(header)
	var title := Label.new()
	title.text = tr("CRAFT_CHEST")
	title.add_theme_font_size_override("font_size", 26)
	header.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var close_button := Button.new()
	close_button.text = tr("ACTION_CLOSE")
	close_button.custom_minimum_size = Vector2(0, BUTTON_HEIGHT)
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(close)
	header.add_child(close_button)
	# Deux colonnes (Sac / Coffre) : côte à côte en paysage, empilées en portrait.
	_wide_box = HBoxContainer.new()
	_wide_box.add_theme_constant_override("separation", 12)
	_wide_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tall_box = VBoxContainer.new()
	_tall_box.add_theme_constant_override("separation", 12)
	_tall_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_wide_box)
	root.add_child(_tall_box)
	var bag := _make_column(tr("CHEST_PANEL_BAG"), tr("ACTION_STORE_ALL"), _on_store_all)
	var stock := _make_column(tr("CHEST_PANEL_STOCK"), tr("ACTION_TAKE_ALL"), _on_take_all)
	_bag_col = bag[0]
	_bag_list = bag[1]
	_stock_col = stock[0]
	_stock_list = stock[1]
	_tall_box.add_child(_bag_col)
	_tall_box.add_child(_stock_col)

## Colonne titre + bouton « tout » + liste défilable ; renvoie [colonne, liste].
func _make_column(title_text: String, all_text: String, all_handler: Callable) -> Array:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	col.add_child(header)
	var label := Label.new()
	label.text = title_text
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", ACCENT)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(label)
	var all_button := Button.new()
	all_button.text = all_text
	all_button.custom_minimum_size = Vector2(150, BUTTON_HEIGHT)
	all_button.focus_mode = Control.FOCUS_NONE
	all_button.pressed.connect(all_handler)
	header.add_child(all_button)
	var scroll := KineticScroll.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	return [col, list]

## En paysage les deux colonnes sont côte à côte, en portrait empilées.
## `vp_override` sert aux tests (sinon taille réelle du viewport).
func _fit_to_viewport(vp_override: Vector2 = Vector2.ZERO) -> void:
	var viewport_size := vp_override if vp_override.x > 0.0 else get_viewport_rect().size
	custom_minimum_size = Vector2(
		clampf(viewport_size.x - 160.0, 360.0, 880.0),
		clampf(viewport_size.y - 150.0, 300.0, 580.0))
	var wide := viewport_size.x >= viewport_size.y
	_wide_box.visible = wide
	_tall_box.visible = not wide
	var target: Container = _wide_box if wide else _tall_box
	if _bag_col.get_parent() != target:
		_bag_col.reparent(target)
		_stock_col.reparent(target)

# --- Contenu ----------------------------------------------------------------------

func refresh() -> void:
	if not visible or _chest == null or not is_instance_valid(_chest):
		return
	_clear(_bag_list)
	_clear(_stock_list)
	var bag: Dictionary = _chest.call("storable_in_bag")
	var bag_ids: Array = bag.keys()
	bag_ids.sort()
	if bag_ids.is_empty():
		_add_label(_bag_list, tr("CHEST_EMPTY_LIST"), 18, DIM)
	for item_id in bag_ids:
		_bag_list.add_child(_item_row(String(item_id), int(bag[item_id]), true))
	var stock: Dictionary = _chest.get("stock")
	var stock_ids: Array = stock.keys()
	stock_ids.sort()
	if stock_ids.is_empty():
		_add_label(_stock_list, tr("CHEST_EMPTY_LIST"), 18, DIM)
	for item_id in stock_ids:
		if int(stock[item_id]) > 0:
			_stock_list.add_child(_item_row(String(item_id), int(stock[item_id]), false))

## Ligne : icône, « Nom ×N », bouton Déposer (sac) ou Reprendre (coffre).
func _item_row(item_id: String, count: int, to_chest: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(_item_icon(item_id))
	var label := Label.new()
	label.text = "%s  ×%d" % [tr("ITEM_" + item_id.to_upper()), count]
	label.add_theme_font_size_override("font_size", 22)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	var button := Button.new()
	button.text = tr("ACTION_STORE") if to_chest else tr("ACTION_TAKE")
	button.custom_minimum_size = Vector2(140, BUTTON_HEIGHT)
	button.focus_mode = Control.FOCUS_NONE
	if to_chest:
		button.pressed.connect(_on_store.bind(item_id, count))
	else:
		button.pressed.connect(_on_take.bind(item_id, count))
	row.add_child(button)
	return row

func _on_store(item_id: String, amount: int) -> void:
	if _chest == null or not is_instance_valid(_chest):
		return
	var moved := int(_chest.call("store_item", item_id, amount))
	if moved > 0:
		_notify(tr("TOAST_CHEST_STORED") % moved)
	refresh()

func _on_take(item_id: String, amount: int) -> void:
	if _chest == null or not is_instance_valid(_chest):
		return
	var moved := int(_chest.call("take_item", item_id, amount))
	if moved > 0:
		_notify(tr("TOAST_CHEST_TAKEN") % moved)
	refresh()

func _on_store_all() -> void:
	if _chest == null or not is_instance_valid(_chest):
		return
	var moved := int(_chest.call("store_all"))
	if moved > 0:
		_notify(tr("TOAST_CHEST_STORED") % moved)
	refresh()

func _on_take_all() -> void:
	if _chest == null or not is_instance_valid(_chest):
		return
	var moved := int(_chest.call("take_all"))
	if moved > 0:
		_notify(tr("TOAST_CHEST_TAKEN") % moved)
	refresh()

# --- Utilitaires ------------------------------------------------------------------

func _item_icon(item_id: String) -> Control:
	var icon := ItemIcon.new()
	icon.set_item(item_id)
	icon.custom_minimum_size = Vector2(48, 48)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if icon.texture == null:
		var dot := ColorRect.new()
		dot.color = Color(0.88, 0.64, 0.36, 0.9)
		dot.custom_minimum_size = Vector2(48, 48)
		return dot
	return icon

func _clear(container: Container) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()

func _add_label(parent: Container, text: String, size: int, color: Color = Color.WHITE) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.modulate = color
	parent.add_child(label)

func _notify(message: String) -> void:
	var hud := get_tree().get_first_node_in_group("hud") as Node
	if hud != null and hud.has_method("show_toast"):
		hud.show_toast(message)
