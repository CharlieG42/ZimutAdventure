extends Control

signal moved(vector: Vector2)

@export var knob_radius: float = 56.0
@export var max_reach: float = 90.0
@export var activation_radius: float = 140.0

var _touch_index: int = -1
var _center: Vector2
var _knob: Control
var _base: Control

func _ready() -> void:
	_base = $Base
	_knob = $Knob
	_center = size * 0.5
	visible = DisplayServer.get_name() == "android"

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _touch_index == -1:
			if not _is_in_zone(event.position):
				return
			_touch_index = event.index
			_center = event.position
			_base.position = _center - _base.size * 0.5
			_base.visible = true
			_update_knob(event.position)
			get_viewport().set_input_as_handled()
		elif not event.pressed and event.index == _touch_index:
			_release()
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and event.index == _touch_index:
		_update_knob(event.position)
		get_viewport().set_input_as_handled()

func _is_in_zone(pos: Vector2) -> bool:
	var zone_center: Vector2 = size * 0.5
	return pos.distance_to(zone_center) <= activation_radius

func _update_knob(touch_pos: Vector2) -> void:
	var delta: Vector2 = touch_pos - _center
	if delta.length() > max_reach:
		delta = delta.normalized() * max_reach
	_knob.position = _center + delta - _knob.size * 0.5
	moved.emit(delta / max_reach)

func _release() -> void:
	_touch_index = -1
	_base.visible = false
	_knob.position = _center - _knob.size * 0.5
	moved.emit(Vector2.ZERO)
