class_name DialoguePanel
extends PanelContainer
## Dialogue avec un PNJ : nom, répliques (clés de traduction) et bouton pour accepter
## la quête offerte (si verrouillée). Fermeture par ui_cancel ou « Au revoir ».

const ACCENT := Color(0.88, 0.64, 0.36, 1.0)
const DIM := Color(1, 1, 1, 0.65)
const BUTTON_HEIGHT := 56.0

var _npc: Node = null
var _name_label: Label
var _lines_label: Label
var _accept_button: Button

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	get_viewport().size_changed.connect(_fit_to_viewport)
	_fit_to_viewport()
	visible = false

func toggle(npc: Node) -> void:
	if visible and _npc == npc:
		close()
	else:
		open(npc)

func open(npc: Node) -> void:
	_npc = npc
	visible = true
	_fit_to_viewport()
	refresh()

func close() -> void:
	visible = false
	_npc = null

func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

func _build() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	add_child(root)
	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 28)
	_name_label.add_theme_color_override("font_color", ACCENT)
	root.add_child(_name_label)
	_lines_label = Label.new()
	_lines_label.add_theme_font_size_override("font_size", 22)
	_lines_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lines_label.modulate = Color(1, 1, 1, 0.92)
	root.add_child(_lines_label)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	buttons.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(buttons)
	_accept_button = Button.new()
	_accept_button.text = tr("ACTION_ACCEPT_QUEST")
	_accept_button.custom_minimum_size = Vector2(0, BUTTON_HEIGHT)
	_accept_button.focus_mode = Control.FOCUS_NONE
	_accept_button.pressed.connect(_on_accept)
	buttons.add_child(_accept_button)
	var bye := Button.new()
	bye.text = tr("ACTION_BYE")
	bye.custom_minimum_size = Vector2(0, BUTTON_HEIGHT)
	bye.focus_mode = Control.FOCUS_NONE
	bye.pressed.connect(close)
	buttons.add_child(bye)

func refresh() -> void:
	if not visible or _npc == null or not is_instance_valid(_npc):
		return
	_name_label.text = tr(String(_npc.call("get_name_key")))
	var text := ""
	for key in _npc.call("get_lines"):
		text += tr(String(key)) + "\n"
	_lines_label.text = text.strip_edges()
	var offered: String = _npc.call("offered_quest")
	_accept_button.visible = offered != ""

func _fit_to_viewport() -> void:
	var viewport_size := get_viewport_rect().size
	custom_minimum_size = Vector2(
		clampf(viewport_size.x - 200.0, 320.0, 640.0),
		clampf(viewport_size.y - 320.0, 200.0, 420.0))

## Accepte la quête offerte par le PNJ.
func _on_accept() -> void:
	if _npc == null or not is_instance_valid(_npc):
		return
	if bool(_npc.call("accept_quest")):
		var quests := get_tree().root.get_node_or_null("QuestManager")
		var title := ""
		if quests != null:
			title = tr(String(quests.call("get_title", String(_npc.call("get_quest")))))
		var hud := get_tree().get_first_node_in_group("hud") as Node
		if hud != null and hud.has_method("show_toast"):
			hud.show_toast(tr("TOAST_QUEST_ACCEPTED") % title, 3.0)
	refresh()
