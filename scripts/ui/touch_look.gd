extends Control

signal look_delta(delta: Vector2)

@export var sensitivity: float = 0.006

var _touch_index: int = -1

func _ready() -> void:
	visible = DisplayServer.get_name() == "android"

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _touch_index == -1:
			_touch_index = event.index
			get_viewport().set_input_as_handled()
		elif not event.pressed and event.index == _touch_index:
			_touch_index = -1
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and event.index == _touch_index:
		look_delta.emit(event.relative * sensitivity)
		get_viewport().set_input_as_handled()
