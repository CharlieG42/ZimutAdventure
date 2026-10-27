extends Node

signal ui_opened
signal ui_closed

var ui_open_count: int = 0
var mouse_captured: bool = true:
	set(value):
		mouse_captured = value
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if value else Input.MOUSE_MODE_VISIBLE

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and mouse_captured:
		pass
	if event.is_action_pressed("ui_cancel"):
		if ui_open_count > 0:
			ui_closed.emit()
			get_viewport().set_input_as_handled()

func open_ui() -> void:
	ui_open_count += 1
	mouse_captured = false
	ui_opened.emit()

func close_ui() -> void:
	ui_open_count = max(0, ui_open_count - 1)
	if ui_open_count == 0:
		mouse_captured = true
		ui_closed.emit()
