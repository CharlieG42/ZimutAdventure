class_name BreakableRock
extends Interactable

@export var drop_item_id: String = "item_stone"
@export var drops_min: int = 2
@export var drops_max: int = 4
@export var break_sfx_volume_db: float = -4.0
@export var shard_count: int = 6
@export var shard_lifetime: float = 1.2

@onready var mesh_instance: MeshInstance3D = $Mesh
@onready var body: StaticBody3D = $Body
@onready var shape: CollisionShape3D = $Body/Shape

var _broken: bool = false

func _ready() -> void:
	prompt_text = "ACTION_BREAK_ROCK"
	one_shot = true

func break_rock(interactor: Node3D) -> void:
	if _broken:
		return
	_broken = true
	_spawn_shards()
	_drop_stones(interactor)
	var sfx := InteractionManager.get_sfx()
	if sfx != null:
		sfx.play(load("res://assets/audio/pickup/collect.wav"), break_sfx_volume_db, 0.6)
	queue_free()

func _on_interact(interactor: Node3D) -> void:
	break_rock(interactor)

func _drop_stones(interactor: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var count := rng.randi_range(drops_min, drops_max)
	var collectible_scene := load("res://scenes/interaction/collectible_item.tscn") as PackedScene
	if collectible_scene == null:
		return
	for i in count:
		var item := collectible_scene.instantiate() as Node3D
		item.set("item_id", drop_item_id)
		item.set("amount", 1)
		var angle := rng.randf_range(0.0, TAU)
		var distance := rng.randf_range(0.5, 1.6)
		item.position = global_position + Vector3(cos(angle) * distance, 0.5, sin(angle) * distance)
		get_parent().add_child(item)

func _spawn_shards() -> void:
	var parent_node := get_parent()
	if parent_node == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var aabb := mesh_instance.mesh.get_aabb() if mesh_instance != null and mesh_instance.mesh != null else AABB(Vector3(-0.3, 0, -0.3), Vector3(0.6, 0.6, 0.6))
	for i in shard_count:
		var shard := MeshInstance3D.new()
		var box := BoxMesh.new()
		var size := rng.randf_range(0.08, 0.22)
		box.size = Vector3(size, size, size) * 0.5
		shard.mesh = box
		shard.material_override = mesh_instance.get_active_material(0) if mesh_instance != null else null
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.4, 1.0), rng.randf_range(-1, 1)).normalized()
		shard.position = global_position + dir * 0.5 + aabb.size * 0.25
		parent_node.add_child(shard)
		var tween := shard.create_tween()
		tween.set_parallel(true)
		tween.tween_property(shard, "position", shard.position + dir * rng.randf_range(1.0, 2.0), shard_lifetime)
		tween.tween_property(shard, "scale", Vector3.ZERO, shard_lifetime)
		tween.chain().tween_callback(shard.queue_free)
