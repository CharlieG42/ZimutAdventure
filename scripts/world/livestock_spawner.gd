extends Node3D
## Place les animaux domestiques (poules, moutons, vaches, chèvres, chevaux, chiens) en petits
## groupes sur le terrain, et sauvegarde ceux que le joueur a apprivoisés
## (user://livestock.cfg) : au rechargement ils reprennent leur place, sans doublon sauvage.

const SAVE_NAME := "livestock.cfg"

@export var animal_scene: PackedScene
@export var seed_offset: int = 31337
@export var spawn_radius: float = 150.0
@export var min_terrain_height: float = -5.0
## [espèce, nombre, groupe près du départ ?]
const GROUPS := [
	["chicken", 5, true],
	["sheep", 4, true],
	["cow", 3, false],
	["goat", 3, false],
	["dog", 2, true],
	["horse", 2, false],
]

var _landscape: Node3D
var _autosave: bool = DisplayServer.get_name() != "headless"
var _saved: Dictionary = {}
var _animals: Array = []
## Repeuplement : animaux sauvages (non apprivoisés) visés par espèce. Quand le joueur en a
## apprivoisé assez, de nouveaux groupes arrivent au loin, hors de vue.
const WILD_TARGET := {"chicken": 3, "sheep": 3, "cow": 2, "goat": 2, "dog": 1, "horse": 1}
const REPOPULATE_SECONDS := 120.0
const ARRIVAL_MIN_DISTANCE := 45.0
const ARRIVAL_MAX_DISTANCE := 110.0
var _repopulate_left: float = REPOPULATE_SECONDS
var _next_id: int = 100
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	add_to_group("livestock_spawner")
	_landscape = get_node_or_null("../Landscape") as Node3D
	_load()
	_spawn_all()

func _spawn_all() -> void:
	if animal_scene == null:
		push_warning("LivestockSpawner: no animal_scene set")
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_offset
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var origin: Vector3 = player.global_position if player != null else Vector3.ZERO
	var spawned := 0
	for group in GROUPS:
		var species: String = group[0]
		var count: int = group[1]
		var center := _pick_center(rng, origin, bool(group[2]))
		for i in count:
			var key := "%s#%d" % [species, i]
			if _saved.has(key):
				_spawn_animal(species, key, _saved[key].get("pos", center), _saved[key])
			else:
				var offset := Vector2(rng.randf_range(-4.5, 4.5), rng.randf_range(-4.5, 4.5))
				var x := center.x + offset.x
				var z := center.z + offset.y
				_spawn_animal(species, key, Vector3(x, _ground_height(x, z), z), {})
			spawned += 1
	# Bêtes apprivoisées venues d'un repeuplement (clés hors des groupes de départ).
	var known := {}
	for animal in _animals:
		known[String(animal.get("spawn_key"))] = true
	for key in _saved:
		if known.has(key):
			continue
		var species := String(key).get_slice("#", 0)
		if not WILD_TARGET.has(species):
			continue
		_spawn_animal(species, key, _saved[key].get("pos", origin), _saved[key])
		_next_id = maxi(_next_id, int(String(key).get_slice("#", 1)) + 1)
		spawned += 1
	_rng.randomize()
	print("LivestockSpawner: placed %d domestic animals" % spawned)

func _process(delta: float) -> void:
	_repopulate_left -= delta
	if _repopulate_left > 0.0:
		return
	_repopulate_left = REPOPULATE_SECONDS
	repopulate()

## Nombre d'animaux sauvages (non apprivoisés) d'une espèce.
func wild_count(species: String) -> int:
	var count := 0
	for animal in get_animals():
		if animal.get("species") == species and not bool(animal.get("tamed")):
			count += 1
	return count

## Fait arriver, pour UNE espèce en manque, un petit groupe sauvage au loin. Renvoie l'espèce
## (ou "" si aucune ne manque).
func repopulate() -> String:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null or animal_scene == null:
		return ""
	var missing: Array = []
	for species in WILD_TARGET:
		if wild_count(species) < int(WILD_TARGET[species]):
			missing.append(species)
	if missing.is_empty():
		return ""
	var species: String = missing[_rng.randi() % missing.size()]
	var center := _arrival_point(player.global_position)
	if center == Vector3.INF:
		return ""
	var count := int(WILD_TARGET[species]) - wild_count(species)
	for i in count:
		var x := center.x + _rng.randf_range(-3.5, 3.5)
		var z := center.z + _rng.randf_range(-3.5, 3.5)
		_spawn_animal(species, "%s#%d" % [species, _next_id], Vector3(x, _ground_height(x, z), z), {})
		_next_id += 1
	_announce(species, center - player.global_position)
	return species

func _arrival_point(origin: Vector3) -> Vector3:
	for attempt in 40:
		var angle := _rng.randf_range(0.0, TAU)
		var distance := _rng.randf_range(ARRIVAL_MIN_DISTANCE, ARRIVAL_MAX_DISTANCE)
		var x := origin.x + cos(angle) * distance
		var z := origin.z + sin(angle) * distance
		var y := _ground_height(x, z)
		if y < min_terrain_height or _in_water(x, z, 6.0):
			continue
		var flat := true
		for offset in [Vector2(4, 0), Vector2(-4, 0), Vector2(0, 4), Vector2(0, -4)]:
			if absf(_ground_height(x + offset.x, z + offset.y) - y) > 1.8:
				flat = false
		if flat:
			return Vector3(x, y, z)
	return Vector3.INF

## « Des chèvres ont été aperçues au nord-est. »
func _announce(species: String, offset: Vector3) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud == null or not hud.has_method("show_toast"):
		return
	var bearing := fposmod(rad_to_deg(atan2(offset.x, -offset.z)), 360.0)
	var directions := ["DIR_N", "DIR_NE", "DIR_E", "DIR_SE", "DIR_S", "DIR_SW", "DIR_W", "DIR_NW"]
	var direction: String = directions[int(round(bearing / 45.0)) % 8]
	hud.show_toast(tr("TOAST_WILD_ARRIVED") % [tr("HERD_" + species.to_upper()), tr(direction)], 4.0)

func _pick_center(rng: RandomNumberGenerator, origin: Vector3, near_start: bool) -> Vector3:
	for attempt in 60:
		var x: float
		var z: float
		if near_start:
			var angle := rng.randf_range(0.0, TAU)
			var distance := rng.randf_range(22.0, 42.0)
			x = origin.x + cos(angle) * distance
			z = origin.z + sin(angle) * distance
		else:
			x = rng.randf_range(-spawn_radius, spawn_radius)
			z = rng.randf_range(-spawn_radius, spawn_radius)
			if Vector2(x - origin.x, z - origin.z).length() < 55.0:
				continue
		var y := _ground_height(x, z)
		if y < min_terrain_height or _in_water(x, z, 8.0):
			continue
		# Terrain à peu près plat autour du groupe.
		var flat := true
		for offset in [Vector2(5, 0), Vector2(-5, 0), Vector2(0, 5), Vector2(0, -5)]:
			if absf(_ground_height(x + offset.x, z + offset.y) - y) > 1.8:
				flat = false
		if flat:
			return Vector3(x, y, z)
	return Vector3(origin.x + 25.0, _ground_height(origin.x + 25.0, origin.z), origin.z)

func _spawn_animal(species: String, key: String, position: Vector3, state: Dictionary) -> void:
	var animal := animal_scene.instantiate() as DomesticAnimal
	animal.species = species
	animal.spawn_key = key
	# Position AVANT add_child : l'animal prend son point d'apparition comme territoire dans _ready.
	animal.position = Vector3(position.x, position.y + 1.0, position.z)
	add_child(animal)
	if not state.is_empty():
		animal.apply_state(state)
	animal.state_changed.connect(_on_animal_changed)
	_animals.append(animal)

func _on_animal_changed(_animal: Node) -> void:
	_save()

func get_animals() -> Array:
	return _animals.filter(func(a): return is_instance_valid(a))

func _ground_height(x: float, z: float) -> float:
	if _landscape != null and _landscape.has_method("terrain_height_at"):
		return float(_landscape.call("terrain_height_at", x, z))
	return 0.0

# --- Sauvegarde ----------------------------------------------------------------------

func _load() -> void:
	if not _autosave:
		return
	var config := ConfigFile.new()
	if config.load(SaveSlots.file(SAVE_NAME)) != OK:
		return
	for entry in config.get_value("livestock", "list", []):
		if entry is Dictionary and entry.has("key"):
			_saved[String(entry["key"])] = entry

## Sauvegarde immédiate (retour au menu principal).
func save_now() -> void:
	_save()

func _save() -> void:
	if not _autosave:
		return
	var records: Array = []
	for animal in get_animals():
		if bool(animal.get("tamed")):
			records.append(animal.call("get_state"))
	var config := ConfigFile.new()
	config.set_value("livestock", "list", records)
	config.save(SaveSlots.file(SAVE_NAME))

## API de test : ne touche pas au disque.
func disable_saving_for_test() -> void:
	_autosave = false

## Vrai si le point tombe dans la rivière ou un lac (avec une marge en mètres).
func _in_water(x: float, z: float, margin: float = 3.0) -> bool:
	return _landscape != null and _landscape.has_method("is_water") and bool(_landscape.call("is_water", x, z, margin))
