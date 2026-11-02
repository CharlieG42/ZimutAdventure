extends Node3D
## Fait rôder des prédateurs la nuit (coyotes dès le niveau 2, loups dès le niveau 4), en nombre
## croissant avec le niveau du joueur, et les renvoie au lever du jour. Ils n'apparaissent pas
## près d'un feu allumé ni d'une construction.

const CHECK_SECONDS := 5.0
const SPAWN_MIN := 36.0
const SPAWN_MAX := 54.0
const DESPAWN_DISTANCE := 130.0
const SAFE_DISTANCE := 16.0
const MAX_PREDATORS := 3

# Les tests headless ne voient rôder personne, sauf demande explicite.
var enabled: bool = DisplayServer.get_name() != "headless"
var _landscape: Node3D
var _timer: float = 0.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	_landscape = get_node_or_null("../Landscape") as Node3D

func enable_for_test() -> void:
	enabled = true

## Nombre et espèce voulus à ce moment de la journée pour ce niveau (espèce "" : aucun).
static func plan(phase: String, level: int) -> Dictionary:
	if phase == "night":
		if level >= 4:
			return {"species": "wolf", "count": mini(MAX_PREDATORS, 1 + level / 6)}
		if level >= 2:
			return {"species": "coyote", "count": mini(MAX_PREDATORS, 1 + level / 4)}
	elif phase == "dusk" or phase == "dawn":
		if level >= 2:
			return {"species": "coyote", "count": 1}
	return {"species": "", "count": 0}

func _process(delta: float) -> void:
	if not enabled:
		return
	_timer += delta
	if _timer < CHECK_SECONDS:
		return
	_timer = 0.0
	update_population()

func update_population() -> void:
	var clock := InteractionManager.get_day_night()
	var progression := InteractionManager.get_progression()
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if clock == null or player == null:
		return
	var level := int(progression.call("get_level")) if progression != null else 1
	var wanted := plan(String(clock.call("get_phase")), level)
	var present := get_tree().get_nodes_in_group("predators")
	if String(wanted["species"]) == "":
		for predator in present:
			predator.call("retreat")
		return
	for predator in present:
		if predator.global_position.distance_to(player.global_position) > DESPAWN_DISTANCE:
			predator.queue_free()
	if present.size() < int(wanted["count"]):
		spawn(String(wanted["species"]), player.global_position)

func spawn(species: String, around: Vector3) -> Node3D:
	for attempt in 12:
		var angle := _rng.randf() * TAU
		var distance := _rng.randf_range(SPAWN_MIN, SPAWN_MAX)
		var x := around.x + cos(angle) * distance
		var z := around.z + sin(angle) * distance
		var y := _ground_height(x, z)
		if y < -5.0 or _near_camp(Vector3(x, y, z)):
			continue
		var predator := Predator.new_for(species)
		predator.position = Vector3(x, y + 1.0, z)
		add_child(predator)
		return predator
	return null

func _near_camp(point: Vector3) -> bool:
	for group_name in ["campfire", "structures"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if is_instance_valid(node) and (node as Node3D).global_position.distance_to(point) < SAFE_DISTANCE:
				return true
	return false

func _ground_height(x: float, z: float) -> float:
	if _landscape != null and _landscape.has_method("terrain_height_at"):
		return float(_landscape.call("terrain_height_at", x, z))
	return 0.0
