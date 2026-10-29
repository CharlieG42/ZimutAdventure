extends SceneTree
## Génère assets/ui/hud_theme.tres (thème du HUD, palette canyon sombre/ocre).
##
## Usage (depuis la racine du projet) :
##   godot --headless --path . -s tools/make_hud_theme.gd
##
## Le thème est généré par script pour garantir un fichier valide et pour
## permettre de retoucher la palette ici plutôt qu'à la main dans le .tres.

const OUT := "res://assets/ui/hud_theme.tres"

const INK := Color(0.09, 0.06, 0.035, 0.66)
const INK_HOVER := Color(0.14, 0.09, 0.05, 0.78)
const INK_DISABLED := Color(0.09, 0.06, 0.035, 0.34)
const OCHER := Color(0.88, 0.64, 0.36, 0.95)
const OCHER_DIM := Color(0.88, 0.64, 0.36, 0.35)
const PRESSED := Color(0.80, 0.50, 0.20, 0.94)
const TEXT := Color(0.97, 0.94, 0.88, 1.0)
const TEXT_DIM := Color(0.97, 0.94, 0.88, 0.45)
const OUTLINE := Color(0.10, 0.06, 0.03, 0.95)

func _init() -> void:
	var theme := Theme.new()
	theme.default_font_size = 24

	# --- Label : texte clair avec contour sombre (lisible sur ciel et sable) ---
	theme.set_color("font_color", "Label", TEXT)
	theme.set_color("font_outline_color", "Label", OUTLINE)
	theme.set_constant("outline_size", "Label", 6)
	theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.3))
	theme.set_constant("shadow_offset_y", "Label", 2)

	# Variante « pilule » : étiquette sur fond sombre (invite d'interaction, toast).
	theme.set_type_variation("PillLabel", "Label")
	var pill := _box(INK, 18, 0, OCHER_DIM)
	pill.content_margin_left = 20.0
	pill.content_margin_right = 20.0
	pill.content_margin_top = 8.0
	pill.content_margin_bottom = 8.0
	theme.set_stylebox("normal", "PillLabel", pill)

	# --- Button (pilules : Carte, Journal, Vue) ---
	_button_states(theme, "Button", 16, 12)
	theme.set_font_size("font_size", "Button", 22)
	theme.set_constant("outline_size", "Button", 4)
	theme.set_color("font_outline_color", "Button", OUTLINE)

	# --- Boutons d'action ronds (icône seule) ---
	theme.set_type_variation("RoundButton", "Button")
	_button_states(theme, "RoundButton", 128, 22)
	theme.set_constant("icon_max_width", "RoundButton", 64)

	# --- Barre d'endurance ---
	theme.set_type_variation("StaminaBar", "ProgressBar")
	theme.set_stylebox("background", "StaminaBar", _box(Color(0.09, 0.06, 0.035, 0.55), 7, 0, OCHER_DIM))
	theme.set_stylebox("fill", "StaminaBar", _box(Color(0.92, 0.70, 0.40, 0.95), 7, 0, Color(0, 0, 0, 0)))

	var err := ResourceSaver.save(theme, OUT)
	if err != OK:
		printerr("make_hud_theme: échec de l'écriture de %s (erreur %d)" % [OUT, err])
		quit(1)
		return
	print("make_hud_theme: écrit ", OUT)
	quit(0)

func _button_states(theme: Theme, type: String, radius: int, margin: int) -> void:
	var normal := _box(INK, radius, 3, OCHER)
	var hover := _box(INK_HOVER, radius, 3, OCHER)
	var pressed := _box(PRESSED, radius, 3, Color(1.0, 0.86, 0.6, 1.0))
	var disabled := _box(INK_DISABLED, radius, 3, OCHER_DIM)
	for box in [normal, hover, pressed, disabled]:
		(box as StyleBoxFlat).content_margin_left = margin
		(box as StyleBoxFlat).content_margin_right = margin
		(box as StyleBoxFlat).content_margin_top = margin
		(box as StyleBoxFlat).content_margin_bottom = margin
	theme.set_stylebox("normal", type, normal)
	theme.set_stylebox("hover", type, hover)
	theme.set_stylebox("pressed", type, pressed)
	theme.set_stylebox("hover_pressed", type, pressed)
	theme.set_stylebox("disabled", type, disabled)
	theme.set_stylebox("focus", type, StyleBoxEmpty.new())
	theme.set_color("font_color", type, TEXT)
	theme.set_color("font_hover_color", type, TEXT)
	theme.set_color("font_pressed_color", type, TEXT)
	theme.set_color("font_hover_pressed_color", type, TEXT)
	theme.set_color("font_disabled_color", type, TEXT_DIM)
	theme.set_color("icon_normal_color", type, TEXT)
	theme.set_color("icon_hover_color", type, TEXT)
	theme.set_color("icon_pressed_color", type, Color(1, 1, 1, 1))
	theme.set_color("icon_hover_pressed_color", type, Color(1, 1, 1, 1))
	theme.set_color("icon_disabled_color", type, TEXT_DIM)

func _box(fill: Color, radius: int, border: int, border_color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.set_corner_radius_all(radius)
	box.set_border_width_all(border)
	box.border_color = border_color
	box.anti_aliasing = true
	return box
