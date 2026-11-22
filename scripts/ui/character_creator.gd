class_name CharacterCreator
extends Control
## Écran de personnalisation : genre, teint, coiffure, couleurs, avec aperçu 3D qui tourne.
## Affiché au premier lancement puis depuis le journal (réglages > Apparence).
## Le jeu est en pause pendant qu'il est ouvert.

signal confirmed(profile: CharacterProfile)

const ACCENT := Color(0.96, 0.78, 0.45)
const HERO_SCRIPT := "res://scripts/player/lowpoly_hero.gd"

var profile: CharacterProfile = CharacterProfile.default_for("male")
var _first_time: bool = false
var _preview: Node3D
var _hero: Node3D
var _options: VBoxContainer
var _done_button: Button
var _was_paused: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false

## Ouvre l'écran avec `current` comme point de départ.
func open(current: CharacterProfile, first_time: bool = false) -> void:
	profile = CharacterProfile.from_dict(current.to_dict())
	_first_time = first_time
	_build()
	_apply_to_preview()
	visible = true
	_was_paused = get_tree().paused
	get_tree().paused = true

func close() -> void:
	visible = false
	get_tree().paused = _was_paused

func _build() -> void:
	for child in get_children():
		child.queue_free()
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.03, 0.02, 0.94)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)
	var wide := get_viewport_rect().size.x >= get_viewport_rect().size.y
	var layout: BoxContainer = HBoxContainer.new() if wide else VBoxContainer.new()
	layout.add_theme_constant_override("separation", 16)
	margin.add_child(layout)
	# Aperçu 3D.
	var container := SubViewportContainer.new()
	container.stretch = true
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.size_flags_stretch_ratio = 0.8 if wide else 0.9
	container.custom_minimum_size = Vector2(240, 260)
	layout.add_child(container)
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.handle_input_locally = false
	viewport.msaa_3d = Viewport.MSAA_2X
	container.add_child(viewport)
	_build_preview(viewport)
	# Options.
	var panel := VBoxContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 1.2
	panel.add_theme_constant_override("separation", 10)
	layout.add_child(panel)
	var title := Label.new()
	title.text = tr("CHAR_TITLE")
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", ACCENT)
	panel.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	_options = VBoxContainer.new()
	_options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_options.add_theme_constant_override("separation", 8)
	scroll.add_child(_options)
	_fill_options()
	_done_button = Button.new()
	_done_button.text = tr("CHAR_START") if _first_time else tr("CHAR_DONE")
	_done_button.custom_minimum_size = Vector2(0, 64)
	_done_button.focus_mode = Control.FOCUS_NONE
	_done_button.add_theme_font_size_override("font_size", 26)
	_done_button.pressed.connect(_on_done)
	panel.add_child(_done_button)

func _build_preview(viewport: SubViewport) -> void:
	_preview = Node3D.new()
	viewport.add_child(_preview)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.78, 0.8, 0.88)
	environment.ambient_light_energy = 0.85
	var world_env := WorldEnvironment.new()
	world_env.environment = environment
	_preview.add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40.0, -30.0, 0.0)
	sun.light_color = Color(1.0, 0.93, 0.8)
	_preview.add_child(sun)
	var camera := Camera3D.new()
	camera.fov = 34.0
	camera.position = Vector3(0.0, 1.0, 4.4)
	_preview.add_child(camera)
	camera.look_at(Vector3(0.0, 0.9, 0.0))
	camera.current = true
	_hero = Node3D.new()
	_hero.set_script(load(HERO_SCRIPT))
	_hero.set("profile", profile)
	_hero.call("load_model")
	_preview.add_child(_hero)

func _apply_to_preview() -> void:
	if _hero != null and is_instance_valid(_hero):
		_hero.call("set_profile", profile)

func _process(delta: float) -> void:
	if visible and _hero != null and is_instance_valid(_hero):
		_hero.rotation.y += delta * 0.6
		_hero.call("advance_poses", delta)

func _fill_options() -> void:
	for child in _options.get_children():
		child.queue_free()
	_section("CHAR_GENDER")
	var genders := HBoxContainer.new()
	genders.add_theme_constant_override("separation", 10)
	for g in CharacterProfile.GENDERS:
		var b := _button(tr("CHAR_" + String(g).to_upper()), profile.gender == g)
		b.pressed.connect(func(): _set_gender(g))
		genders.add_child(b)
	_options.add_child(genders)
	_section("CHAR_SKIN")
	_swatches(CharacterProfile.SKIN_TONES, profile.skin, func(i): profile.skin = i)
	_section("CHAR_HAIR_STYLE")
	var styles := HFlowContainer.new()
	styles.add_theme_constant_override("h_separation", 8)
	styles.add_theme_constant_override("v_separation", 8)
	for i in CharacterProfile.HAIR_STYLES.size():
		var b := _button(tr("CHAR_HAIR_" + String(CharacterProfile.HAIR_STYLES[i]).to_upper()), profile.hair_style == i)
		b.pressed.connect(func():
			profile.hair_style = i
			_changed())
		styles.add_child(b)
	_options.add_child(styles)
	_section("CHAR_HAIR_COLOR")
	_swatches(CharacterProfile.HAIR_COLORS, profile.hair_color, func(i): profile.hair_color = i)
	_section("CHAR_TUNIC")
	_swatches(CharacterProfile.TUNIC_COLORS, profile.tunic, func(i): profile.tunic = i)
	_section("CHAR_PANTS")
	_swatches(CharacterProfile.PANTS_COLORS, profile.pants, func(i): profile.pants = i)

func _set_gender(g: String) -> void:
	if profile.gender == g:
		return
	# Changer de genre propose la coiffure et la tunique par défaut du nouveau genre.
	var fresh := CharacterProfile.default_for(g)
	profile.gender = g
	profile.hair_style = fresh.hair_style
	profile.tunic = fresh.tunic
	_changed()

func _changed() -> void:
	_apply_to_preview()
	_fill_options()

func _section(key: String) -> void:
	var label := Label.new()
	label.text = tr(key)
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", ACCENT)
	_options.add_child(label)

func _button(text: String, selected: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_pressed = selected
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(120, 52)
	b.add_theme_font_size_override("font_size", 20)
	return b

func _swatches(colors: Array[Color], selected: int, setter: Callable) -> void:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 8)
	for i in colors.size():
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(56, 56)
		for state in ["normal", "hover", "pressed", "focus"]:
			var box := StyleBoxFlat.new()
			box.bg_color = colors[i]
			box.set_corner_radius_all(10)
			box.set_border_width_all(4 if i == selected else 1)
			box.border_color = Color.WHITE if i == selected else Color(0, 0, 0, 0.5)
			b.add_theme_stylebox_override(state, box)
		b.pressed.connect(func():
			setter.call(i)
			_changed())
		row.add_child(b)
	_options.add_child(row)

func _on_done() -> void:
	profile.save()
	close()
	confirmed.emit(profile)
