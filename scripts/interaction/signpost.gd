class_name SignpostInteractable
extends Interactable

@export_multiline var message_key: String = "SIGN_CANYON_1"
@export var body_id: String = "Wood"
@export var reading_time: float = 4.5

func _ready() -> void:
	prompt_text = "ACTION_READ"
	one_shot = false

func _on_interact(interactor: Node3D) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var hud := tree.get_first_node_in_group("hud") as Node
	if hud != null and hud.has_method("show_toast"):
		hud.show_toast(tr(message_key), reading_time)
