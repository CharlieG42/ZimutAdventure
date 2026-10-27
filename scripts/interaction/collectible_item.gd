class_name CollectibleItem
extends Interactable

@export var item_id: String = "item_stone"
@export var amount: int = 1
@export var pickup_sound: AudioStream
@export var float_amplitude: float = 0.15
@export var float_speed: float = 2.0

var _base_y: float = 0.0
var _t: float = 0.0

func _ready() -> void:
	_base_y = position.y
	prompt_text = "ACTION_COLLECT"
	one_shot = true

func _process(delta: float) -> void:
	_t += delta * float_speed
	position.y = _base_y + sin(_t) * float_amplitude
	rotation.y += delta * 0.6

func _on_interact(_interactor: Node3D) -> void:
	var inventory := InteractionManager.get_inventory()
	if inventory != null:
		inventory.call("add_item", item_id, amount)
	var sfx := InteractionManager.get_sfx()
	if sfx != null:
		sfx.call("play", pickup_sound, -6.0)
	queue_free()
