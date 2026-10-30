class_name CollectibleItem
extends Interactable

enum Kind { STONE, WOOD }

@export var item_id: String = "item_stone"
@export var amount: int = 1
@export var kind: Kind = Kind.STONE
@export var pickup_sound: AudioStream
@export var float_amplitude: float = 0.15
@export var float_speed: float = 2.0

var _base_y: float = 0.0
var _t: float = 0.0
var _mesh: MeshInstance3D
var _glow: OmniLight3D

func _ready() -> void:
	add_to_group("collectible")
	add_to_group("wood" if item_id == "item_wood" else "stone")
	_base_y = position.y
	prompt_text = "ACTION_COLLECT"
	one_shot = true
	_mesh = get_node_or_null("Mesh") as MeshInstance3D
	_glow = get_node_or_null("Glow") as OmniLight3D
	_apply_kind()

func _process(delta: float) -> void:
	_t += delta * float_speed
	position.y = _base_y + sin(_t) * float_amplitude
	rotation.y += delta * 0.6

func _apply_kind() -> void:
	if _mesh == null:
		return
	match kind:
		Kind.WOOD:
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = 0.07
			cylinder.bottom_radius = 0.09
			cylinder.height = 0.7
			var material := StandardMaterial3D.new()
			material.albedo_color = Color(0.45, 0.28, 0.14, 1)
			material.roughness = 0.9
			_mesh.mesh = cylinder
			_mesh.material_override = material
			if _glow != null:
				_glow.light_color = Color(1.0, 0.8, 0.55, 1)
				_glow.omni_range = 1.8
		_:
			pass

func _on_interact(_interactor: Node3D) -> void:
	var inventory := InteractionManager.get_inventory()
	if inventory != null:
		inventory.call("add_item", item_id, amount)
	var sfx := InteractionManager.get_sfx()
	if sfx != null:
		sfx.call("play", pickup_sound, -6.0)
	queue_free()
