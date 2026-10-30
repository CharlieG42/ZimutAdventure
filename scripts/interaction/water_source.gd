class_name WaterSource
extends Interactable
## Point d'eau dans le canyon : boire restaure la soif (SurvivalManager).

@export var drink_amount: float = 0.35
@export var refill_seconds: float = 20.0

var _refill_left: float = 0.0

func _ready() -> void:
	prompt_text = "ACTION_DRINK"

func _process(delta: float) -> void:
	if _refill_left > 0.0:
		_refill_left = maxf(0.0, _refill_left - delta)

func can_interact() -> bool:
	return enabled and _refill_left <= 0.0

func get_prompt() -> String:
	return "TOAST_WATER_REFILL" if _refill_left > 0.0 else prompt_text

func _on_interact(_interactor: Node3D) -> void:
	var survival := InteractionManager.get_survival()
	if survival == null or not survival.has_method("drink"):
		return
	survival.call("drink", drink_amount)
	_refill_left = refill_seconds
	var tree := get_tree()
	if tree != null:
		var hud := tree.get_first_node_in_group("hud") as Node
		if hud != null and hud.has_method("show_toast"):
			hud.show_toast(tr("TOAST_DRANK"))
