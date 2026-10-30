extends Node3D
## Place des animaux inoffensifs sur le terrain du canyon.

@export var animal_scene: PackedScene
@export var count: int = 6
@export var spawn_radius: float = 150.0
@export var min_terrain_height: float = -5.0
@export var seed_offset: int = 999

var _landscape: Node3D

func _ready() -> void:
	_landscape = get_node_or_null("../Landscape") as Node3D
	_spawn_all()

func _spawn_all() -> void:
	if animal_scene == null:
		push_warning("AnimalSpawner: no animal_scene set")
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_offset
	var spawned := 0
	for attempt in range(count * 30):
		if spawned >= count:
			break
		var x := rng.randf_range(-spawn_radius, spawn_radius)
		var z := rng.randf_range(-spawn_radius, spawn_radius)
		var y := _ground_height(x, z)
		if y < min_terrain_height:
			continue
		var animal := animal_scene.instantiate() as Node3D
		# Un lièvre sur trois, le reste des cerfs (l'espèce se choisit avant _ready).
		animal.set("species", "rabbit" if spawned % 3 == 2 else "deer")
		add_child(animal)
		animal.position = Vector3(x, y + 1.0, z)
		spawned += 1
	print("AnimalSpawner: placed %d animals" % spawned)

func _ground_height(x: float, z: float) -> float:
	if _landscape != null and _landscape.has_method("terrain_height_at"):
		return _landscape.call("terrain_height_at", x, z)
	return 0.0
