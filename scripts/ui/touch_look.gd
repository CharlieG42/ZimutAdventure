extends Control

signal look_delta(delta: Vector2)

@export var sensitivity: float = 0.006
@export var joystick_zone_margin: float = 60.0

var _touch_index: int = -1
var _joystick_zones: Array[Control] = []

func _ready() -> void:
	visible = PlatformInfo.is_touch()
	for name in ["VirtualJoystick", "CameraJoystick"]:
		var zone := get_node_or_null("../" + name) as Control
		if zone != null:
			_joystick_zones.append(zone)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _touch_index == -1:
			if _is_in_joystick_zone(event.position):
				return
			_touch_index = event.index
			get_viewport().set_input_as_handled()
		elif event.index == _touch_index and (not event.pressed or event.canceled):
			_touch_index = -1
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and event.index == _touch_index:
		look_delta.emit(event.relative * sensitivity)
		get_viewport().set_input_as_handled()

func _is_in_joystick_zone(local_pos: Vector2) -> bool:
	var screen_pos: Vector2 = local_pos + global_position
	for zone in _joystick_zones:
		var zone_local: Vector2 = screen_pos - zone.global_position
		var joy_rect := Rect2(Vector2.ZERO, zone.size).grow(joystick_zone_margin)
		if joy_rect.has_point(zone_local):
			return true
	return false
