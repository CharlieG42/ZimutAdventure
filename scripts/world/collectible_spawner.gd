extends Node3D

@export var item_scene: PackedScene
@export var count: int = 12
@export var spawn_radius: float = 180.0
@export var min_terrain_height: float = -5.0
@export var seed_offset: int = 77

var _landscape: Node3D

func _ready() -> void:
	_landscape = get_node_or_null("../Landscape") as Node3D
	_spawn_all()

func _spawn_all() -> void:
	if item_scene == null:
		push_warning("CollectibleSpawner: no item_scene set")
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_offset
	var spawned := 0
	for attempt in range(count * 20):
		if spawned >= count:
			break
		var x := rng.randf_range(-spawn_radius, spawn_radius)
		var z := rng.randf_range(-spawn_radius, spawn_radius)
		var y := _ground_height(x, z)
		if y < min_terrain_height:
			continue
		var item := item_scene.instantiate() as Node3D
		item.position = Vector3(x, y + 0.4, z)
		add_child(item)
		spawned += 1
	print("CollectibleSpawner: placed %d collectibles" % spawned)

func _ground_height(x: float, z: float) -> float:
	if _landscape != null and _landscape.has_method("terrain_height_at"):
		return _landscape.call("terrain_height_at", x, z)
	return 0.0
