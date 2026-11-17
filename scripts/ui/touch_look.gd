extends Control
## Zone tactile « libre » : tout ce qui n'est pas un bouton ni un stick.
##
## - Un doigt posé dans la partie gauche de l'écran déclenche un stick de
##   déplacement flottant (apparaît sous le pouce, n'importe où dans la zone).
## - Un doigt posé ailleurs fait tourner la caméra (glisser).
## Les deux gestes sont indépendants et simultanés : pouce gauche = marcher,
## pouce droit = regarder. Les boutons et sticks fixes, placés au-dessus de ce
## contrôle, gardent la priorité : aucune zone « morte » ne subsiste.

signal look_delta(delta: Vector2)
## Vecteur de déplacement flottant (borné à 1) ; (0, 0) au relâchement.
signal move_changed(vector: Vector2)

const BASE_TEXTURE := preload("res://assets/ui/joystick_base.png")
const KNOB_TEXTURE := preload("res://assets/ui/joystick_knob.png")

@export var sensitivity: float = 0.006
## Part gauche de la largeur où un toucher devient un stick de déplacement.
@export_range(0.0, 0.7) var move_zone_width: float = 0.42
## Part haute de l'écran réservée à la caméra, même à gauche.
@export_range(0.0, 0.6) var look_only_top: float = 0.28
@export var move_reach: float = 90.0

var _touch_index: int = -1
var _move_index: int = -1
var _move_center: Vector2 = Vector2.ZERO
var _base: TextureRect
var _knob: TextureRect

func _ready() -> void:
	visible = PlatformInfo.is_touch()
	_base = _make_marker(BASE_TEXTURE, 0.85)
	_knob = _make_marker(KNOB_TEXTURE, 1.0)

func _make_marker(texture: Texture2D, alpha: float) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = texture
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.modulate.a = alpha
	rect.visible = false
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	var side := 200.0 if texture == BASE_TEXTURE else 96.0
	rect.custom_minimum_size = Vector2(side, side)
	rect.size = Vector2(side, side)
	add_child(rect)
	return rect

## Vrai si un toucher en `local_pos` démarre le déplacement (sinon : caméra).
func is_move_zone(local_pos: Vector2) -> bool:
	return local_pos.x < size.x * move_zone_width and local_pos.y > size.y * look_only_top

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			if is_move_zone(event.position) and _move_index == -1:
				_begin_move(event.index, event.position)
				get_viewport().set_input_as_handled()
			elif not is_move_zone(event.position) and _touch_index == -1:
				_touch_index = event.index
				get_viewport().set_input_as_handled()
		elif event.index == _move_index:
			_end_move()
			get_viewport().set_input_as_handled()
		elif event.index == _touch_index:
			_touch_index = -1
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		if event.index == _move_index:
			_update_move(event.position)
			get_viewport().set_input_as_handled()
		elif event.index == _touch_index:
			look_delta.emit(event.relative * sensitivity)
			get_viewport().set_input_as_handled()

func _begin_move(index: int, pos: Vector2) -> void:
	_move_index = index
	# La base reste dans l'écran même si le pouce est collé au bord.
	var half := _base.size * 0.5
	_move_center = Vector2(clampf(pos.x, half.x, maxf(half.x, size.x - half.x)),
		clampf(pos.y, half.y, maxf(half.y, size.y - half.y)))
	_base.visible = true
	_knob.visible = true
	_base.position = _move_center - half
	_update_move(pos)
	if PlatformInfo.is_touch():
		Input.vibrate_handheld(10)

func _update_move(pos: Vector2) -> void:
	var offset := pos - _move_center
	if offset.length() > move_reach:
		offset = offset.normalized() * move_reach
	_knob.position = _move_center + offset - _knob.size * 0.5
	move_changed.emit(offset / move_reach)

func _end_move() -> void:
	_move_index = -1
	_base.visible = false
	_knob.visible = false
	move_changed.emit(Vector2.ZERO)

func is_moving() -> bool:
	return _move_index != -1

func _notification(what: int) -> void:
	# Évite un stick « coincé » si le toucher est interrompu par le système.
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			if _move_index != -1:
				_end_move()
			_touch_index = -1
		NOTIFICATION_VISIBILITY_CHANGED:
			if not is_visible_in_tree():
				if _move_index != -1:
					_end_move()
				_touch_index = -1
