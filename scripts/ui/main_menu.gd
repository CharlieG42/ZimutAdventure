class_name MainMenu
extends Control
## Écran de démarrage : 3 parties au maximum. Une partie existante se joue ou se supprime ;
## un emplacement libre ouvre la création du personnage (homme ou femme, nom, apparence),
## puis l'aventure démarre. Les parties de l'ancienne version sont reprises dans la partie 1.

const GAME_SCENE := "res://scenes/world/canyon_playground.tscn"
const ACCENT := Color(0.96, 0.78, 0.45)
const DIM := Color(1, 1, 1, 0.65)
const CARD_HEIGHT := 112.0

var _list: VBoxContainer
var _margin: MarginContainer
var _confirm_layer: Control
var _creator: CharacterCreator
var _new_slot: int = 0
## Pour les tests : ne change pas de scène.
var change_scene_enabled: bool = true
var started_slot: int = 0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = load("res://assets/ui/hud_theme.tres") as Theme
	SaveSlots.migrate_legacy()
	_build()
	get_viewport().size_changed.connect(_fit)
	_fit()

func _build() -> void:
	for child in get_children():
		child.queue_free()
	var background := ColorRect.new()
	background.color = Color(0.1, 0.07, 0.05)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(0.55, 0.28, 0.12, 0.4), Color(0.55, 0.28, 0.12, 0.0)])
	var glow_texture := GradientTexture2D.new()
	glow_texture.gradient = gradient
	glow_texture.fill_from = Vector2(0.5, 0.0)
	glow_texture.fill_to = Vector2(0.5, 1.0)
	var glow := TextureRect.new()
	glow.texture = glow_texture
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glow)
	_margin = MarginContainer.new()
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_margin.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 14)
	scroll.add_child(column)
	var title := Label.new()
	title.text = tr("MENU_TITLE")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", ACCENT)
	column.add_child(title)
	var subtitle := Label.new()
	subtitle.text = tr("MENU_SUBTITLE")
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 20)
	subtitle.add_theme_color_override("font_color", DIM)
	column.add_child(subtitle)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 16)
	column.add_child(spacer)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 12)
	column.add_child(_list)
	_creator = CharacterCreator.new()
	_creator.name = "CharacterCreator"
	_creator.theme = theme
	_creator.save_on_confirm = false
	_creator.allow_cancel = true
	_creator.confirmed.connect(_on_new_character)
	add_child(_creator)
	_refresh()

func _fit() -> void:
	if _margin == null:
		return
	var width := get_viewport_rect().size.x
	var side := int(maxf(16.0, (width - 760.0) * 0.5))
	_margin.add_theme_constant_override("margin_left", side)
	_margin.add_theme_constant_override("margin_right", side)
	_margin.add_theme_constant_override("margin_top", 28)
	_margin.add_theme_constant_override("margin_bottom", 20)

func _refresh() -> void:
	for child in _list.get_children():
		# Retiré tout de suite : le nom « SlotN » doit être libre pour les nouvelles cartes.
		_list.remove_child(child)
		child.queue_free()
	for slot in range(1, SaveSlots.MAX_SLOTS + 1):
		_list.add_child(_card(slot))

func _card(slot: int) -> Control:
	var data := SaveSlots.info(slot)
	var card := PanelContainer.new()
	card.name = "Slot%d" % slot
	card.custom_minimum_size = Vector2(0, CARD_HEIGHT)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.2, 0.14, 0.1, 0.92)
	box.set_corner_radius_all(14)
	box.set_border_width_all(2)
	box.border_color = ACCENT if bool(data["exists"]) else Color(1, 1, 1, 0.18)
	box.set_content_margin_all(14)
	card.add_theme_stylebox_override("panel", box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(texts)
	var heading := Label.new()
	heading.add_theme_font_size_override("font_size", 16)
	heading.add_theme_color_override("font_color", DIM)
	heading.text = tr("MENU_SLOT") % slot
	texts.add_child(heading)
	var main := Label.new()
	main.add_theme_font_size_override("font_size", 28)
	main.clip_text = true
	texts.add_child(main)
	var detail := Label.new()
	detail.add_theme_font_size_override("font_size", 16)
	detail.add_theme_color_override("font_color", DIM)
	texts.add_child(detail)
	if bool(data["exists"]):
		var hero_name := String(data["name"])
		main.text = hero_name if hero_name != "" else tr("CHAR_DEFAULT_NAME")
		detail.text = "%s · %s" % [tr("CHAR_" + String(data["gender"]).to_upper()),
				tr("MENU_LAST_PLAYED") % _date_text(int(data["last_played"]))]
		var play := _button(tr("MENU_PLAY"), true)
		play.name = "Play"
		play.pressed.connect(func(): _play(slot))
		row.add_child(play)
		var remove := _button(tr("MENU_DELETE"), false)
		remove.name = "Delete"
		remove.pressed.connect(func(): _ask_delete(slot))
		row.add_child(remove)
	else:
		main.text = tr("MENU_EMPTY")
		main.add_theme_color_override("font_color", DIM)
		detail.text = ""
		var create := _button(tr("MENU_NEW"), true)
		create.name = "New"
		create.pressed.connect(func(): _new_game(slot))
		row.add_child(create)
	return card

func _button(text: String, primary: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(150 if primary else 120, 56)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 20)
	return b

## Date locale « jj/mm/aaaa ».
func _date_text(unix: int) -> String:
	if unix <= 0:
		return "-"
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var d := Time.get_datetime_dict_from_unix_time(unix + bias)
	return "%02d/%02d/%04d" % [d["day"], d["month"], d["year"]]

# --- Actions ---------------------------------------------------------------------------------

func _play(slot: int) -> void:
	if not SaveSlots.activate(slot, get_tree()):
		return
	_start(slot)

func _new_game(slot: int) -> void:
	_new_slot = slot
	_creator.open(CharacterProfile.default_for("male"), true)

func _on_new_character(profile: CharacterProfile) -> void:
	if _new_slot < 1 or not SaveSlots.create(_new_slot, profile):
		return
	SaveSlots.reload_autoloads(get_tree())
	_start(_new_slot)

func _start(slot: int) -> void:
	started_slot = slot
	if change_scene_enabled:
		get_tree().change_scene_to_file(GAME_SCENE)

func _ask_delete(slot: int) -> void:
	_close_confirm()
	var data := SaveSlots.info(slot)
	var shown_name := String(data.get("name", ""))
	if shown_name == "":
		shown_name = tr("CHAR_DEFAULT_NAME")
	_confirm_layer = Control.new()
	_confirm_layer.name = "ConfirmDelete"
	_confirm_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_confirm_layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_confirm_layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_confirm_layer.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(minf(520.0, get_viewport_rect().size.x - 40.0), 0)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.2, 0.12, 0.1)
	box.set_corner_radius_all(14)
	box.set_border_width_all(2)
	box.border_color = Color(0.95, 0.5, 0.4)
	box.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", box)
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	panel.add_child(column)
	var question := Label.new()
	question.text = tr("MENU_DELETE_CONFIRM") % shown_name
	question.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	question.add_theme_font_size_override("font_size", 22)
	column.add_child(question)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	column.add_child(buttons)
	var cancel := _button(tr("MENU_CANCEL"), true)
	cancel.name = "Cancel"
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.pressed.connect(func(): _close_confirm())
	buttons.add_child(cancel)
	var confirm := _button(tr("MENU_DELETE"), false)
	confirm.name = "Confirm"
	confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm.pressed.connect(func():
		SaveSlots.delete(slot)
		_close_confirm()
		_refresh())
	buttons.add_child(confirm)

func _close_confirm() -> void:
	if _confirm_layer != null:
		remove_child(_confirm_layer)
		_confirm_layer.queue_free()
		_confirm_layer = null
