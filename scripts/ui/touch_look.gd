extends Control

signal look_delta(delta: Vector2)

@export var sensitivity: float = 0.006
@export var joystick_zone_margin: float = 60.0

var _touch_index: int = -1
var _joystick_zone: Control

func _ready() -> void:
	visible = DisplayServer.get_name() == "android"
	_joystick_zone = get_node_or_null("../VirtualJoystick") as Control

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _touch_index == -1:
			if _is_in_joystick_zone(event.position):
				return
			_touch_index = event.index
			get_viewport().set_input_as_handled()
		elif not event.pressed and event.index == _touch_index:
			_touch_index = -1
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and event.index == _touch_index:
		look_delta.emit(event.relative * sensitivity)
		get_viewport().set_input_as_handled()

func _is_in_joystick_zone(local_pos: Vector2) -> bool:
	if _joystick_zone == null:
		return false
	var screen_pos: Vector2 = local_pos + global_position
	var joystick_local: Vector2 = screen_pos - _joystick_zone.global_position
	var joy_rect := Rect2(Vector2.ZERO, _joystick_zone.size)
	joy_rect = joy_rect.grow(joystick_zone_margin)
	return joy_rect.has_point(joystick_local)
