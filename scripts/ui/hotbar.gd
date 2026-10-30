class_name Hotbar
extends HBoxContainer
## Barre d'outils du HUD : un emplacement par outil possédé (hache, serpette, arc).
## Toucher un emplacement équipe l'outil (le retoucher le range). L'arc affiche le nombre
## de flèches. Raccourcis clavier : 1, 2, 3 (dans l'ordre des emplacements).

const SLOT_SIZE := Vector2(76, 76)
const ACCENT := Color(0.88, 0.64, 0.36, 1.0)

var _inventory: Node
var _slots: Dictionary = {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", 10)
	_inventory = InteractionManager.get_inventory()
	if _inventory != null:
		_inventory.connect("item_added", _on_inventory_changed)
		_inventory.connect("item_removed", _on_inventory_changed)
		_inventory.connect("equipped_changed", _on_inventory_changed)
	refresh()

func _on_inventory_changed(_a = null, _b = null) -> void:
	refresh.call_deferred()

func refresh() -> void:
	for child in get_children():
		child.queue_free()
	_slots.clear()
	if _inventory == null:
		return
	var equipped: String = _inventory.get_equipped()
	var number := 1
	for tool_id in _inventory.get_owned_tools():
		var slot := Button.new()
		slot.custom_minimum_size = SLOT_SIZE
		slot.focus_mode = Control.FOCUS_NONE
		slot.toggle_mode = true
		slot.button_pressed = (tool_id == equipped)
		slot.theme_type_variation = &"RoundButton"
		slot.tooltip_text = tr("ITEM_" + String(tool_id).to_upper())
		slot.pressed.connect(_on_slot_pressed.bind(String(tool_id)))
		var icon := ToolIcon.new()
		icon.tool_id = tool_id
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(icon)
		var key := Label.new()
		key.text = str(number)
		key.add_theme_font_size_override("font_size", 16)
		key.position = Vector2(8, 2)
		key.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(key)
		if tool_id == "tool_hunting_bow":
			var arrows := Label.new()
			arrows.text = "×%d" % int(_inventory.count_of("arrow"))
			arrows.add_theme_font_size_override("font_size", 18)
			arrows.add_theme_color_override("font_color", ACCENT if _inventory.count_of("arrow") > 0 else Color(0.95, 0.4, 0.35))
			arrows.position = Vector2(34, 54)
			arrows.mouse_filter = Control.MOUSE_FILTER_IGNORE
			slot.add_child(arrows)
		add_child(slot)
		_slots[tool_id] = slot
		number += 1

func _on_slot_pressed(tool_id: String) -> void:
	select_tool(tool_id)

## Équipe l'outil, ou le range s'il l'est déjà.
func select_tool(tool_id: String) -> void:
	if _inventory == null:
		return
	if _inventory.is_equipped(tool_id):
		_inventory.unequip()
	else:
		_inventory.equip(tool_id)
		_announce(tool_id)

## Raccourci clavier : emplacement n°index (0 = premier).
func select_index(index: int) -> void:
	if _inventory == null:
		return
	var owned: Array = _inventory.get_owned_tools()
	if index >= 0 and index < owned.size():
		select_tool(String(owned[index]))

func slot_count() -> int:
	return _slots.size()

func _announce(tool_id: String) -> void:
	var hud := get_tree().get_first_node_in_group("hud") if get_tree() != null else null
	if hud != null and hud.has_method("show_toast"):
		hud.show_toast(tr("HINT_" + tool_id.to_upper()), 2.6)
