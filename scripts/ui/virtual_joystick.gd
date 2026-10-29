class_name TouchStick
extends Control
## Joystick virtuel analogique (déplacement ou caméra).
##
## - always_visible = true  : base fixe au centre de la zone (mode du GDD).
##   Le vecteur est toujours calculé par rapport au centre de la base, et le
##   knob reste visuellement collé au doigt (borné à l'anneau).
## - always_visible = false : base flottante, qui apparaît sous le doigt.
##
## Le signal `moved` émet un vecteur analogique brut, borné à 1. La zone morte
## et la courbe de réponse sont appliquées par le consommateur (voir Player),
## ce qui garde ce contrôle générique.

signal moved(vector: Vector2)
signal pressed_changed(is_pressed: bool)

## Index "touche" utilisé pour la souris (PC) — distinct des index tactiles.
const MOUSE_INDEX := 1000

## Débattement du doigt (en unités du viewport) pour une inclinaison de 1.0.
@export var max_reach: float = 80.0
@export var always_visible: bool = true
## Accepte la souris (utile sur PC quand le curseur est libéré avec Échap).
@export var accept_mouse: bool = true
## Petit retour haptique à la prise du stick (mobile uniquement).
@export var haptics: bool = true
@export_range(0.0, 1.0) var idle_base_alpha: float = 0.6
@export_range(0.0, 1.0) var active_base_alpha: float = 0.95
@export_range(0.0, 1.0) var idle_knob_alpha: float = 0.8
@export_range(0.0, 1.0) var active_knob_alpha: float = 1.0

var _touch_index: int = -1
var _center: Vector2 = Vector2.ZERO
var _value: Vector2 = Vector2.ZERO
var _base: Control
var _knob: Control
var _fade: Tween

func _ready() -> void:
	_base = $Base
	_knob = $Knob
	resized.connect(_on_resized)
	_rest()
	_base.visible = always_visible
	_knob.visible = always_visible
	_base.modulate.a = idle_base_alpha
	_knob.modulate.a = idle_knob_alpha
	visible = true

## Vecteur courant (brut, borné à 1).
func get_value() -> Vector2:
	return _value

func is_pressed() -> bool:
	return _touch_index != -1

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed and _touch_index == -1:
			_begin(touch.index, touch.position)
			get_viewport().set_input_as_handled()
		elif touch.index == _touch_index and (not touch.pressed or touch.canceled):
			_release()
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _touch_index:
			_update_knob(drag.position)
			get_viewport().set_input_as_handled()
	elif accept_mouse and event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		# Les clics émulés depuis un toucher sont déjà traités ci-dessus.
		if button.device == InputEvent.DEVICE_ID_EMULATION or button.button_index != MOUSE_BUTTON_LEFT:
			return
		if button.pressed and _touch_index == -1:
			_begin(MOUSE_INDEX, button.position)
			get_viewport().set_input_as_handled()
		elif not button.pressed and _touch_index == MOUSE_INDEX:
			_release()
			get_viewport().set_input_as_handled()
	elif accept_mouse and event is InputEventMouseMotion and _touch_index == MOUSE_INDEX:
		var motion := event as InputEventMouseMotion
		if motion.device != InputEvent.DEVICE_ID_EMULATION:
			_update_knob(motion.position)
			get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	# Évite un stick « coincé » (le perso continue de courir) quand le toucher
	# est interrompu par le système : bascule en arrière-plan, volet de
	# notifications, perte de focus, masquage du contrôle...
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			if _touch_index != -1:
				_release()
		NOTIFICATION_VISIBILITY_CHANGED:
			if _touch_index != -1 and not is_visible_in_tree():
				_release()

func _begin(index: int, local_pos: Vector2) -> void:
	_touch_index = index
	if always_visible:
		_center = size * 0.5
	else:
		_center = _clamp_inside(local_pos)
		_base.visible = true
		_knob.visible = true
	_place(_base, _center)
	_fade_to(active_base_alpha, active_knob_alpha)
	_update_knob(local_pos)
	pressed_changed.emit(true)
	if haptics and PlatformInfo.is_touch():
		Input.vibrate_handheld(12)

func _update_knob(local_pos: Vector2) -> void:
	var delta := local_pos - _center
	if delta.length() > max_reach:
		delta = delta.normalized() * max_reach
	_place(_knob, _center + delta)
	_value = delta / max_reach
	moved.emit(_value)

func _release() -> void:
	_touch_index = -1
	_value = Vector2.ZERO
	_rest()
	if not always_visible:
		_base.visible = false
		_knob.visible = false
	_fade_to(idle_base_alpha, idle_knob_alpha)
	moved.emit(Vector2.ZERO)
	pressed_changed.emit(false)

## Replace base et knob au centre de la zone (état de repos).
func _rest() -> void:
	_center = size * 0.5
	_place(_base, _center)
	_place(_knob, _center)

func _on_resized() -> void:
	if _touch_index == -1 and _base != null:
		_rest()

## Pose un enfant de façon à ce que son centre soit en `center`.
func _place(item: Control, center: Vector2) -> void:
	item.position = center - item.size * 0.5

## En mode flottant, garde la base entièrement dans la zone de toucher.
func _clamp_inside(pos: Vector2) -> Vector2:
	var half := _base.size * 0.5
	return Vector2(
		clampf(pos.x, half.x, maxf(half.x, size.x - half.x)),
		clampf(pos.y, half.y, maxf(half.y, size.y - half.y)))

func _fade_to(base_alpha: float, knob_alpha: float) -> void:
	if not is_inside_tree():
		return
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = create_tween().set_parallel(true)
	_fade.tween_property(_base, "modulate:a", base_alpha, 0.12)
	_fade.tween_property(_knob, "modulate:a", knob_alpha, 0.12)
