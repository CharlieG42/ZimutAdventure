extends Node3D
## Place des rochers cassables (avec collision) sur le terrain du canyon.

@export var rock_scene: PackedScene
@export var count: int = 25
@export var spawn_radius: float = 170.0
@export var min_terrain_height: float = -5.0
@export var seed_offset: int = 4242
## Distance minimale au point de départ du joueur.
@export var min_distance_to_player: float = 12.0
## Préférence de zone [désert, pinède, mesas, berges] (0 à 1) ; vide = partout pareil.
@export var zone_affinity: Array[float] = []

var _landscape: Node3D

func _ready() -> void:
	_landscape = get_node_or_null("../Landscape") as Node3D
	_spawn_all()

func _spawn_all() -> void:
	if rock_scene == null:
		push_warning("BreakableRockSpawner: no rock_scene set")
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_offset
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var player_pos: Vector3 = player.global_position if player != null else Vector3(9999, 0, 9999)
	var spawned := 0
	for attempt in range(count * 30):
		if spawned >= count:
			break
		var x := rng.randf_range(-spawn_radius, spawn_radius)
		var z := rng.randf_range(-spawn_radius, spawn_radius)
		if Vector2(x - player_pos.x, z - player_pos.z).length() < min_distance_to_player:
			continue
		var y := _ground_height(x, z)
		if y < min_terrain_height or _in_water(x, z):
			continue
		if not _zone_accepts(rng, x, z):
			continue
		var rock := rock_scene.instantiate() as Node3D
		add_child(rock)
		rock.position = Vector3(x, y, z)
		rock.rotation.y = rng.randf_range(0.0, TAU)
		var s := rng.randf_range(0.8, 1.3)
		rock.scale = Vector3.ONE * s
		spawned += 1
	print("BreakableRockSpawner: placed %d breakable rocks" % spawned)

func _ground_height(x: float, z: float) -> float:
	if _landscape != null and _landscape.has_method("terrain_height_at"):
		return _landscape.call("terrain_height_at", x, z)
	return 0.0

## Vrai si le point tombe dans la rivière ou un lac (avec une marge en mètres).
func _in_water(x: float, z: float, margin: float = 3.0) -> bool:
	return _landscape != null and _landscape.has_method("is_water") and bool(_landscape.call("is_water", x, z, margin))

## Tirage selon la préférence de zone : les arbres poussent surtout en pinède, etc.
func _zone_accepts(rng: RandomNumberGenerator, x: float, z: float) -> bool:
	if zone_affinity.size() < 4 or _landscape == null or not _landscape.has_method("zone_weights"):
		return true
	var weights: Array = _landscape.call("zone_weights", x, z)
	var chance := 0.0
	for i in 4:
		chance += float(weights[i]) * zone_affinity[i]
	return rng.randf() <= chance
