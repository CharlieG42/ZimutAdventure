class_name InventoryPanel
extends PanelContainer

const CLOSE_KEY := "ACTION_CLOSE"

var _list: VBoxContainer
var _title: Label
var _close_button: Button
var _inventory: Node

func _ready() -> void:
	_inventory = InteractionManager.get_inventory()
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	visible = false

func toggle() -> void:
	if visible:
		close()
	else:
		open()

func open() -> void:
	_refresh()
	visible = true

func close() -> void:
	visible = false

func _build() -> void:
	var margin := VBoxContainer.new()
	margin.add_theme_constant_override("separation", 10)
	_title = Label.new()
	_title.text = tr("JOURNAL_INVENTORY_TITLE")
	_title.add_theme_font_size_override("font_size", 26)
	margin.add_child(_title)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(360, 260)
	margin.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

	_close_button = Button.new()
	_close_button.text = tr(CLOSE_KEY)
	_close_button.pressed.connect(close)
	margin.add_child(_close_button)
	add_child(margin)

func _refresh() -> void:
	for child in _list.get_children():
		child.queue_free()
	if _inventory == null:
		return
	var all: Dictionary = _inventory.get_all()
	if all.is_empty():
		_add_row(tr("INVENTORY_EMPTY"))
		return
	for item_id in all.keys():
		var count: int = int(all[item_id])
		_add_row("%s  ×%d" % [tr("ITEM_" + String(item_id).to_upper()), count])

func _add_row(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 22)
	_list.add_child(label)
