extends Control

signal moved(vector: Vector2)

@export var knob_radius: float = 56.0
@export var max_reach: float = 80.0
@export var always_visible: bool = true

var _touch_index: int = -1
var _center: Vector2
var _knob: Control
var _base: Control

func _ready() -> void:
	_base = $Base
	_knob = $Knob
	_center = size * 0.5
	_base.position = _center - _base.size * 0.5
	_knob.position = _center - _knob.size * 0.5
	_base.visible = always_visible or DisplayServer.get_name() == "android"
	visible = DisplayServer.get_name() == "android"

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _touch_index == -1:
			_touch_index = event.index
			_center = event.position
			if not always_visible:
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

func _update_knob(touch_pos: Vector2) -> void:
	var delta: Vector2 = touch_pos - _center
	if delta.length() > max_reach:
		delta = delta.normalized() * max_reach
	_knob.position = _center + delta - _knob.size * 0.5
	moved.emit(delta / max_reach)

func _release() -> void:
	_touch_index = -1
	if not always_visible:
		_base.visible = false
	_center = size * 0.5
	_knob.position = _center - _knob.size * 0.5
	moved.emit(Vector2.ZERO)
