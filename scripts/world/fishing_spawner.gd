extends Node3D
## Creuse trois étangs de pêche : le premier près du départ, les autres tirés d'une graine.

const POND_COUNT := 3
const FIRST_POND := Vector2(24.0, -16.0)
const SEED := 9191

var _landscape: Node3D

func _ready() -> void:
	_landscape = get_node_or_null("../Landscape") as Node3D
	for spot in plan(POND_COUNT):
		var pond := FishingSpot.create()
		pond.position = Vector3(spot.x, _ground_height(spot.x, spot.y), spot.y)
		add_child(pond)

func plan(count: int) -> Array:
	var result: Array = [FIRST_POND]
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var attempts := 0
	while result.size() < count and attempts < 300:
		attempts += 1
		var angle := rng.randf() * TAU
		var radius := rng.randf_range(60.0, 170.0)
		var point := Vector2(cos(angle), sin(angle)) * radius
		if _ground_height(point.x, point.y) < -2.0:
			continue
		var far := true
		for other in result:
			if (other as Vector2).distance_to(point) < 50.0:
				far = false
		if far:
			result.append(point)
	return result

func _ground_height(x: float, z: float) -> float:
	if _landscape != null and _landscape.has_method("terrain_height_at"):
		return float(_landscape.call("terrain_height_at", x, z))
	return 0.0
