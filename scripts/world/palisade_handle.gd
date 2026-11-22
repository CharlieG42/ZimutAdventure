extends Interactable
## Poignée de visée d'un tronçon de palissade : l'invite rappelle qu'on peut le déplacer.

func _ready() -> void:
	prompt_text = "ACTION_FENCE"

func _on_interact(_interactor: Node3D) -> void:
	var tree := get_tree()
	var hud := tree.get_first_node_in_group("hud") as Node if tree != null else null
	if hud != null and hud.has_method("show_toast"):
		hud.show_toast(tr("TOAST_FENCE_HINT"), 2.4)
