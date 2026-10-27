class_name Interactable
extends Node3D

signal interacted(interactor: Node3D)

@export var prompt_text: String = "ACTION_INTERACT"
@export var one_shot: bool = false
@export var enabled: bool = true

var _use_count: int = 0

func can_interact() -> bool:
	return enabled and not (one_shot and _use_count > 0)

func get_prompt() -> String:
	return prompt_text

func interact(interactor: Node3D) -> bool:
	if not can_interact():
		return false
	_use_count += 1
	interacted.emit(interactor)
	_on_interact(interactor)
	return true

func _on_interact(_interactor: Node3D) -> void:
	pass
