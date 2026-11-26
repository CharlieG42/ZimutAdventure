class_name RanchPanel
extends PanelContainer
## Fenêtre « Ranch » : gérer ses enclos à distance.
##  - choisir un enclos, le renommer ;
##  - affecter jusqu'à deux chiens de garde ;
##  - choisir quelles bêtes apprivoisées y vivent (elles s'y rendent à pied) ;
##  - rassembler, libérer, tout collecter d'un bouton.

const ACCENT := Color(0.88, 0.64, 0.36, 1.0)
const BUTTON_HEIGHT := 52.0
const REFRESH_PERIOD := 0.5

var _pen_list: VBoxContainer
var _detail: VBoxContainer
var _name_edit: LineEdit
var _selected: Node3D = null
var _refresh_left: float = 0.0
## Filtre : n'afficher que les bêtes hors enclos (et les chiens sans garde).
var only_free: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	get_viewport().size_changed.connect(_fit_to_viewport)
	_fit_to_viewport()
	visible = false

func toggle() -> void:
	if visible:
		close()
	else:
		open()

func open(pen: Node3D = null) -> void:
	visible = true
	_fit_to_viewport()
	var pens := _pens()
	if pen != null:
		_selected = pen
	elif _selected == null or not is_instance_valid(_selected):
		_selected = _nearest_pen(pens)
	refresh()

func close() -> void:
	visible = false
	if _name_edit != null and _name_edit.has_focus():
		_name_edit.release_focus()

func selected_pen() -> Node3D:
	return _selected

func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

## Les bêtes bougent : on rafraîchit régulièrement (pas pendant la saisie du nom).
func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_left -= delta
	if _refresh_left <= 0.0 and not (_name_edit != null and _name_edit.has_focus()):
		_refresh_left = REFRESH_PERIOD
		refresh()

func _fit_to_viewport() -> void:
	var viewport_size := get_viewport_rect().size
	custom_minimum_size = Vector2(
		clampf(viewport_size.x - 160.0, 360.0, 860.0),
		clampf(viewport_size.y - 150.0, 240.0, 540.0))

func _pens() -> Array:
	return get_tree().get_nodes_in_group("pens") if is_inside_tree() else []

func _nearest_pen(pens: Array) -> Node3D:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var best: Node3D = null
	var best_distance := INF
	for pen in pens:
		var distance: float = 0.0 if player == null else player.global_position.distance_to(pen.global_position)
		if distance < best_distance:
			best_distance = distance
			best = pen
	return best

# --- Construction ---------------------------------------------------------------------

func _build() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.065, 0.04, 0.95)
	style.border_color = ACCENT
	style.set_border_width_all(3)
	style.set_corner_radius_all(18)
	style.set_content_margin_all(14)
	add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	add_child(column)
	var title := Label.new()
	title.text = tr("RANCH_TITLE")
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", ACCENT)
	column.add_child(title)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 12)
	column.add_child(row)
	var pens_scroll := ScrollContainer.new()
	pens_scroll.custom_minimum_size = Vector2(190, 0)
	pens_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(pens_scroll)
	_pen_list = VBoxContainer.new()
	_pen_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pen_list.add_theme_constant_override("separation", 6)
	pens_scroll.add_child(_pen_list)
	var detail_scroll := ScrollContainer.new()
	detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(detail_scroll)
	_detail = VBoxContainer.new()
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.add_theme_constant_override("separation", 8)
	detail_scroll.add_child(_detail)
	var close_button := Button.new()
	close_button.text = tr("ACTION_CLOSE")
	close_button.custom_minimum_size = Vector2(0, BUTTON_HEIGHT)
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(close)
	column.add_child(close_button)

# --- Contenu ----------------------------------------------------------------------------------

func refresh() -> void:
	_clear(_pen_list)
	_clear(_detail)
	_name_edit = null
	var pens := _pens()
	if _selected != null and (not is_instance_valid(_selected) or not pens.has(_selected)):
		_selected = null
	if _selected == null and not pens.is_empty():
		_selected = _nearest_pen(pens)
	if pens.is_empty():
		_add_text(_detail, tr("RANCH_NO_PEN"), 18, Color(1, 1, 1, 0.75))
		return
	for pen in pens:
		var button := Button.new()
		button.name = "PenButton%d" % pens.find(pen)
		button.focus_mode = Control.FOCUS_NONE
		button.toggle_mode = true
		button.button_pressed = pen == _selected
		button.custom_minimum_size = Vector2(0, BUTTON_HEIGHT)
		button.text = "%s  %d/%d" % [pen.call("display_name"), (pen.call("get_occupants") as Array).size(), int(pen.call("capacity"))]
		button.clip_text = true
		button.pressed.connect(func():
			_selected = pen
			refresh())
		_pen_list.add_child(button)
	_build_detail(_selected)

func _build_detail(pen: Node3D) -> void:
	var name_row := HBoxContainer.new()
	_name_edit = LineEdit.new()
	_name_edit.name = "PenName"
	_name_edit.text = String(pen.get("pen_name"))
	_name_edit.placeholder_text = pen.call("display_name")
	_name_edit.max_length = Pen.NAME_MAX_LENGTH
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.custom_minimum_size = Vector2(0, BUTTON_HEIGHT * 0.85)
	_name_edit.text_submitted.connect(func(text: String):
		pen.call("rename", text)
		_name_edit.release_focus()
		refresh())
	_name_edit.focus_exited.connect(func():
		if is_instance_valid(pen) and _name_edit != null and _name_edit.text != String(pen.get("pen_name")):
			pen.call("rename", _name_edit.text))
	name_row.add_child(_name_edit)
	_detail.add_child(name_row)
	var occupants: Array = pen.call("get_occupants")
	_add_text(_detail, tr("RANCH_PEN_STATS") % [int(pen.get("level")), occupants.size(), int(pen.call("capacity")),
			(pen.call("guard_dogs") as Array).size(), Pen.MAX_GUARDS], 17, Color(1, 0.95, 0.85))
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	_detail.add_child(actions)
	_action(actions, "RanchHerd", tr("RANCH_HERD"), func(): pen.call("start_herd"))
	_action(actions, "RanchRelease", tr("RANCH_RELEASE"), func(): pen.call("release_all"))
	_action(actions, "RanchCollect", tr("RANCH_COLLECT"), func(): _collect(pen))

	var filter := CheckButton.new()
	filter.name = "OnlyFreeFilter"
	filter.text = tr("RANCH_FILTER_FREE")
	filter.focus_mode = Control.FOCUS_NONE
	filter.button_pressed = only_free
	filter.custom_minimum_size = Vector2(0, BUTTON_HEIGHT * 0.8)
	filter.toggled.connect(func(on: bool):
		only_free = on
		refresh())
	_detail.add_child(filter)

	_add_header(tr("RANCH_GUARDS"))
	var dogs: Array = []
	for animal in get_tree().get_nodes_in_group("tamed"):
		if is_instance_valid(animal) and animal.get("species") == "dog":
			dogs.append(animal)
	if dogs.is_empty():
		_add_text(_detail, tr("RANCH_NO_DOG"), 16, Color(1, 1, 1, 0.55))
	var guards: Array = pen.call("guard_dogs")
	if only_free:
		dogs = dogs.filter(func(d): return not bool(d.get("guarding")))
		if dogs.is_empty():
			_add_text(_detail, tr("RANCH_FILTER_NONE"), 16, Color(1, 1, 1, 0.55))
	for i in dogs.size():
		var dog: Node = dogs[i]
		var here := guards.has(dog)
		var status := tr("RANCH_DOG_HERE") if here else _dog_status(dog)
		_animal_row(tr("RANCH_DOG_NAME") % (i + 1), status, "Guard%d" % i,
				tr("ACTION_UNASSIGN") if here else tr("ACTION_ASSIGN_GUARD"),
				func():
					if here:
						pen.call("unassign_guard", dog)
					else:
						_report(pen.call("assign_guard", dog))
					refresh(),
				here or guards.size() < Pen.MAX_GUARDS)

	_add_header(tr("RANCH_LIVESTOCK"))
	var livestock: Array = []
	for animal in get_tree().get_nodes_in_group("tamed"):
		if is_instance_valid(animal) and animal.has_method("can_be_penned") and bool(animal.call("can_be_penned")):
			livestock.append(animal)
	if livestock.is_empty():
		_add_text(_detail, tr("RANCH_NO_LIVESTOCK"), 16, Color(1, 1, 1, 0.55))
	elif only_free:
		livestock = livestock.filter(func(a): return not bool(a.get("penned")) and a.get("herd_pen") == null)
		if livestock.is_empty():
			_add_text(_detail, tr("RANCH_FILTER_NONE"), 16, Color(1, 1, 1, 0.55))
	livestock.sort_custom(func(a, b): return String(a.get("species")) < String(b.get("species")))
	for i in livestock.size():
		var animal: Node = livestock[i]
		var inside: bool = occupants.has(animal) or animal.get("herd_pen") == pen
		_animal_row(tr("SPECIES_" + String(animal.get("species")).to_upper()), _livestock_status(animal, pen),
				"Animal%d" % i, tr("ACTION_TAKE_OUT") if inside else tr("ACTION_PUT_HERE"),
				func():
					if inside:
						pen.call("release_animal", animal)
					else:
						_report(pen.call("assign_animal", animal))
					refresh(),
				inside or (int(pen.call("free_slots")) > 0 and not bool(animal.get("mounted"))))

func _dog_status(dog: Node) -> String:
	if bool(dog.get("following")):
		return tr("ANIMALS_FOLLOWING")
	if bool(dog.get("guarding")):
		for other in _pens():
			if other.get("pen_id") == dog.get("guard_pen_id"):
				return tr("RANCH_GUARDS_OTHER") % other.call("display_name")
		return tr("ANIMALS_GUARDING")
	return tr("ANIMALS_STAYING")

func _livestock_status(animal: Node, pen: Node3D) -> String:
	if animal.get("herd_pen") == pen:
		return tr("RANCH_ON_THE_WAY")
	if bool(animal.get("penned")):
		for other in _pens():
			if other.call("contains", animal.global_position):
				return tr("RANCH_HERE") if other == pen else tr("RANCH_IN_PEN") % other.call("display_name")
	if animal.get("herd_pen") != null:
		return tr("RANCH_ON_THE_WAY")
	return tr("RANCH_FREE")

func _collect(pen: Node3D) -> void:
	var totals: Dictionary = pen.call("collect_all")
	if totals.is_empty():
		_notify(tr("RANCH_NOTHING_READY"))
		return
	var parts: PackedStringArray = []
	for item_id in totals:
		parts.append("%d %s" % [int(totals[item_id]), tr("ITEM_" + String(item_id).to_upper())])
	_notify(tr("TOAST_PEN_COLLECTED") % ", ".join(parts))

func _report(error: String) -> void:
	if error != "":
		_notify(tr(error))

func _notify(message: String) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("show_toast"):
		hud.show_toast(message)

# --- Petits éléments --------------------------------------------------------------------------

func _action(parent: Container, node_name: String, text: String, callback: Callable) -> void:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(0, BUTTON_HEIGHT)
	button.pressed.connect(func():
		callback.call()
		refresh())
	parent.add_child(button)

func _animal_row(label: String, status: String, node_name: String, action: String, callback: Callable, enabled: bool) -> void:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.scroll_active = false
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_theme_font_size_override("normal_font_size", 17)
	text.add_theme_font_size_override("bold_font_size", 17)
	text.text = "[b][color=#e8c690]%s[/color][/b]  [color=#ffffffb0]%s[/color]" % [label, status]
	line.add_child(text)
	var button := Button.new()
	button.name = node_name
	button.text = action
	button.disabled = not enabled
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(150, BUTTON_HEIGHT * 0.85)
	button.pressed.connect(callback)
	line.add_child(button)
	_detail.add_child(line)

func _add_header(text: String) -> void:
	_add_text(_detail, text, 18, ACCENT)

func _add_text(parent: Container, text: String, size: int, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)

func _clear(container: Container) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
