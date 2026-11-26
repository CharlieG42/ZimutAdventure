class_name Pen
extends Interactable
## Enclos de bois : le cœur du ranch. On y rassemble le bétail apprivoisé (vaches, moutons,
## chèvres, poules) ; les bêtes y restent (clôture solide, ouverte côté +Z pour que le joueur
## entre) et produisent plus vite.
##  - « Rassembler le bétail » : les bêtes des environs viennent d'elles-mêmes jusqu'à l'enclos ;
##  - « Libérer le bétail » : elles sortent et reprennent leur vie dehors ;
##  - Améliorer : l'enclos s'agrandit (niveaux 1 à 3) et accueille plus de bêtes ; on peut
##    construire plusieurs enclos pour un vrai ranch.

const MAX_LEVEL := 3
## Demi-côté de l'enclos par niveau (mètres).
const HALFS := {1: 4.5, 2: 6.5, 3: 8.5}
## Nombre de bêtes par niveau.
const CAPACITIES := {1: 6, 2: 10, 3: 16}
const WANDERS := {1: 3.0, 2: 4.2, 3: 5.6}
const UPGRADE_COSTS := {
	2: {"item_wood": 10, "item_stone": 2},
	3: {"item_wood": 16, "item_stone": 6, "item_pelt": 2},
}
const GATE_WIDTH := 2.6
const JOIN_DISTANCE := 40.0
## Distance max (depuis l'enclos) des bêtes qui répondent à « Rassembler ».
const HERD_RADIUS := 90.0
const SOLID_LAYER := 1
const UPGRADE_ROOM_ERROR := "TOAST_UPGRADE_NO_ROOM"

var level: int = 1
## Nom donné par le joueur (vide = « Enclos n ») et identifiant stable (chiens de garde affectés).
var pen_name: String = ""
var pen_id: String = ""
const MAX_GUARDS := 2
const NAME_MAX_LENGTH := 24

static func create() -> Area3D:
	var area := Area3D.new()
	area.set_script(load("res://scripts/world/pen.gd"))
	area.collision_layer = 4
	area.collision_mask = 0
	area.name = "Pen"
	return area

## Routine du ranch : à la tombée de la nuit le bétail libre rentre à l'enclos (à l'abri des
## prédateurs), à l'aube celui qui est rentré ainsi ressort. Les bêtes mises en enclos à la
## main y restent.
const NIGHT_START := 18.5
const NIGHT_END := 5.5
const ROUTINE_SECONDS := 2.0
var _routine_left: float = 0.0
var _was_night: int = -1

func _process(delta: float) -> void:
	_routine_left -= delta
	if _routine_left > 0.0:
		return
	_routine_left = ROUTINE_SECONDS
	routine_tick()

func is_night_now() -> bool:
	var clock := get_node_or_null("/root/DayNightCycle")
	if clock == null:
		return false
	var hour := float(clock.get("hour"))
	return hour >= NIGHT_START or hour < NIGHT_END

## Détecte le passage jour/nuit. Renvoie "dusk", "dawn" ou "" (rien à faire).
func routine_tick() -> String:
	var night := 1 if is_night_now() else 0
	if night == _was_night:
		return ""
	var first := _was_night == -1
	_was_night = night
	if night == 1:
		var sent := start_herd(true)
		if sent > 0 and not first:
			_toast(tr("TOAST_HERD_NIGHT") % sent)
		return "dusk"
	var out := release_auto()
	if out > 0 and not first:
		_toast(tr("TOAST_HERD_DAWN") % out)
	return "dawn"

## À l'aube : seules les bêtes rentrées automatiquement ressortent.
func release_auto() -> int:
	var released := 0
	for animal in get_occupants():
		if bool(animal.get("auto_penned")):
			animal.call("leave_pen", to_global(Vector3(0.0, 0.0, half() + 2.0)))
			released += 1
	return released

func _ready() -> void:
	if pen_id == "":
		pen_id = "pen_%d_%d" % [Time.get_ticks_usec(), randi() % 100000]
	add_to_group("structures")
	add_to_group("pens")
	prompt_text = "ACTION_HERD"
	_build()

# --- Dimensions ---------------------------------------------------------------------------

func half() -> float:
	return float(HALFS[clampi(level, 1, MAX_LEVEL)])

func capacity() -> int:
	return int(CAPACITIES[clampi(level, 1, MAX_LEVEL)])

func wander() -> float:
	return float(WANDERS[clampi(level, 1, MAX_LEVEL)])

## Position d'un point dans l'enclos (repère monde) : au centre, un peu décalée.
func center() -> Vector3:
	return global_position

func contains(point: Vector3) -> bool:
	var local := to_local(point)
	var limit := half()
	return absf(local.x) < limit and absf(local.z) < limit

## Devant la barrière, à l'extérieur : le point de passage des bêtes qui entrent.
func gate_outside() -> Vector3:
	return to_global(Vector3(0.0, 0.0, half() + 3.0))

## Juste derrière la barrière, à l'intérieur.
func gate_inside() -> Vector3:
	return to_global(Vector3(0.0, 0.0, half() - 1.6))

func get_occupants() -> Array:
	var occupants: Array = []
	for animal in get_tree().get_nodes_in_group("tamed"):
		if is_instance_valid(animal) and bool(animal.get("penned")) and contains(animal.global_position):
			occupants.append(animal)
	return occupants

func is_full() -> bool:
	return get_occupants().size() + _heading_here().size() >= capacity()

## Places libres, en comptant les bêtes déjà en route.
func free_slots() -> int:
	return maxi(0, capacity() - get_occupants().size() - _heading_here().size())

func _heading_here() -> Array:
	var heading: Array = []
	for animal in get_tree().get_nodes_in_group("tamed"):
		if is_instance_valid(animal) and animal.get("herd_pen") == self and not bool(animal.get("penned")):
			heading.append(animal)
	return heading

## Fait entrer un animal d'élevage apprivoisé. Retourne false s'il est refusé.
func admit(animal: Node3D) -> bool:
	if not animal.has_method("enter_pen"):
		return false
	var occupants := get_occupants()
	if not occupants.has(animal) and occupants.size() >= capacity():
		return false
	var angle := randf() * TAU
	var spot := global_position + Vector3(cos(angle), 0.0, sin(angle)) * randf_range(0.5, maxf(1.0, half() * 0.4))
	animal.set("_home_pen", self)
	animal.call("enter_pen", spot, wander())
	return true

## Rassemble le bétail apprivoisé des environs (à la pose de l'enclos) : sans marcher.
func gather_nearby() -> int:
	var count := 0
	for animal in herdable():
		if animal.global_position.distance_to(global_position) > JOIN_DISTANCE:
			continue
		if admit(animal):
			count += 1
	return count

# --- Ranch : rassembler et libérer --------------------------------------------------------------

## Bétail apprivoisé, libre (ni en enclos ni monté), à portée d'appel, du plus proche au plus loin.
func herdable() -> Array:
	var animals: Array = []
	for animal in get_tree().get_nodes_in_group("tamed"):
		if not is_instance_valid(animal) or not animal.has_method("herd_to"):
			continue
		if not bool(animal.get("is_livestock")) or bool(animal.get("penned")) or bool(animal.get("mounted")):
			continue
		if animal.get("herd_pen") != null:
			continue
		if animal.global_position.distance_to(global_position) > HERD_RADIUS:
			continue
		animals.append(animal)
	animals.sort_custom(func(a, b): return a.global_position.distance_to(global_position) < b.global_position.distance_to(global_position))
	return animals

## Envoie les bêtes libres vers l'enclos (autant que de places). Renvoie le nombre de bêtes parties.
func start_herd(automatic: bool = false) -> int:
	var sent := 0
	var slots := free_slots()
	for animal in herdable():
		if sent >= slots:
			break
		if bool(animal.call("herd_to", self, automatic)):
			sent += 1
	return sent

## Ouvre la barrière : toutes les bêtes de l'enclos sortent. Renvoie leur nombre.
func release_all() -> int:
	var released := 0
	for animal in get_occupants():
		animal.call("leave_pen", to_global(Vector3(0.0, 0.0, half() + 2.0)))
		released += 1
	for animal in _heading_here():
		animal.set("herd_pen", null)
	return released

## Bêtes de l'enclos dont le produit est prêt (la laine exige la faucille en main).
func collectable() -> Array:
	var ready: Array = []
	for animal in get_occupants():
		if bool(animal.call("is_product_ready")) and not bool(animal.call("needs_missing_tool")):
			ready.append(animal)
	return ready

## Collecte tout en un clic : lait, œufs et laine de toutes les bêtes prêtes.
## Renvoie les totaux par objet, ex. {"item_milk": 4, "item_egg": 2}.
func collect_all() -> Dictionary:
	var totals := {}
	for animal in collectable():
		var result: Dictionary = animal.call("harvest")
		if not result.is_empty():
			totals[result["item"]] = int(totals.get(result["item"], 0)) + int(result["amount"])
	return totals

func _blocked_by_tool() -> int:
	var count := 0
	for animal in get_occupants():
		if bool(animal.call("needs_missing_tool")):
			count += 1
	return count

func get_prompt() -> String:
	if not collectable().is_empty():
		return "ACTION_COLLECT_ALL"
	if free_slots() > 0 and not herdable().is_empty():
		return "ACTION_HERD"
	if not get_occupants().is_empty():
		return "ACTION_RELEASE"
	return "ACTION_PEN_EMPTY"

func get_prompt_args() -> Array:
	var prompt := get_prompt()
	if prompt == "ACTION_COLLECT_ALL":
		return [collectable().size()]
	if prompt == "ACTION_HERD":
		return [mini(free_slots(), herdable().size())]
	if prompt == "ACTION_RELEASE":
		return [get_occupants().size()]
	return []

func _on_interact(_interactor: Node3D) -> void:
	match get_prompt():
		"ACTION_COLLECT_ALL":
			var totals := collect_all()
			var parts: PackedStringArray = []
			for item_id in totals:
				parts.append("%d %s" % [int(totals[item_id]), tr("ITEM_" + String(item_id).to_upper())])
			var message := tr("TOAST_PEN_COLLECTED") % ", ".join(parts)
			if _blocked_by_tool() > 0:
				message += " " + tr("TOAST_COLLECT_NEED_SICKLE")
			_toast(message)
		"ACTION_HERD":
			var sent := start_herd()
			var left := herdable().size()
			if left > 0:
				_toast(tr("TOAST_HERD_PARTIAL") % [sent, capacity()])
			else:
				_toast(tr("TOAST_HERD") % sent)
		"ACTION_RELEASE":
			_toast(tr("TOAST_RELEASED") % release_all())
		_:
			_toast(tr("TOAST_PEN_EMPTY"))

func _toast(message: String) -> void:
	var tree := get_tree()
	var hud := tree.get_first_node_in_group("hud") as Node if tree != null else null
	if hud != null and hud.has_method("show_toast"):
		hud.show_toast(message, 2.6)

# --- Évolution --------------------------------------------------------------------------------

## Les autoloads ne sont pas encore connus à la compilation des tests : on passe par l'arbre.
func _manager() -> Node:
	return get_tree().root.get_node_or_null("InteractionManager")

func can_upgrade() -> bool:
	return level < MAX_LEVEL

func next_upgrade_cost() -> Dictionary:
	if not can_upgrade():
		return {}
	return (UPGRADE_COSTS[level + 1] as Dictionary).duplicate()

func upgrade_missing() -> Dictionary:
	var missing := {}
	var inventory = _manager().call("get_inventory")
	var cost := next_upgrade_cost()
	for item_id in cost:
		var have: int = int(inventory.call("count_of", item_id)) if inventory != null else 0
		if have < int(cost[item_id]):
			missing[item_id] = int(cost[item_id]) - have
	return missing

## Niveau du joueur requis pour chaque niveau d'enclos.
const UPGRADE_PLAYER_LEVEL := {2: 3, 3: 5}

func upgrade_required_level() -> int:
	return int(UPGRADE_PLAYER_LEVEL.get(level + 1, 1)) if can_upgrade() else 0

## Améliore l'enclos. Renvoie "" si réussi, sinon la clé d'erreur.
func upgrade() -> String:
	if not can_upgrade():
		return "TOAST_MAX_LEVEL"
	var progression_check = _manager().call("get_progression")
	if progression_check != null and int(progression_check.call("get_level")) < upgrade_required_level():
		return "TOAST_UPGRADE_LEVEL"
	if not upgrade_missing().is_empty():
		return "TOAST_UPGRADE_MISSING"
	if not _has_room_to_grow():
		return UPGRADE_ROOM_ERROR
	var inventory = _manager().call("get_inventory")
	var cost := next_upgrade_cost()
	for item_id in cost:
		inventory.call("remove_item", item_id, int(cost[item_id]))
	level += 1
	_rebuild()
	for animal in get_occupants():
		animal.set("wander_radius", wander())
	var progression = _manager().call("get_progression")
	if progression != null:
		progression.call("add_xp_for", "build")
	var spawner := get_parent()
	if spawner != null and spawner.has_method("save_now"):
		spawner.call("save_now")
	return ""

## L'agrandissement ne doit pas avaler une autre construction (hors de l'enclos actuel).
func _has_room_to_grow() -> bool:
	var old_half := half()
	level += 1
	var new_half := half()
	level -= 1
	for other in get_tree().get_nodes_in_group("structures") if is_inside_tree() else []:
		if other == self or not (other is Node3D):
			continue
		var local := to_local((other as Node3D).global_position)
		var in_new: bool = absf(local.x) < new_half + 0.6 and absf(local.z) < new_half + 0.6
		var in_old: bool = absf(local.x) < old_half + 0.6 and absf(local.z) < old_half + 0.6
		if in_new and not in_old:
			return false
	return true

func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_build()

func get_state() -> Dictionary:
	return {"level": level, "name": pen_name, "id": pen_id}

# --- Gestion du ranch (fenêtre Ranch) ---------------------------------------------------------

func display_name() -> String:
	if pen_name != "":
		return pen_name
	var index := 1
	if is_inside_tree():
		index = get_tree().get_nodes_in_group("pens").find(self) + 1
	return tr("PEN_DEFAULT_NAME") % maxi(index, 1)

func rename(new_name: String) -> void:
	pen_name = new_name.strip_edges().substr(0, NAME_MAX_LENGTH)
	_save_spawner()

## Chiens de garde affectés à cet enclos.
func guard_dogs() -> Array:
	var dogs: Array = []
	for animal in get_tree().get_nodes_in_group("tamed"):
		if is_instance_valid(animal) and animal.get("species") == "dog" and bool(animal.get("guarding")) \
				and animal.get("guard_pen_id") == pen_id:
			dogs.append(animal)
	return dogs

## Affecte un chien à la garde de l'enclos (2 au plus). Renvoie "" ou la clé d'erreur.
func assign_guard(dog: Node) -> String:
	if dog == null or dog.get("species") != "dog" or not bool(dog.get("tamed")):
		return "TOAST_CANNOT_ASSIGN"
	var dogs := guard_dogs()
	if dogs.has(dog):
		return ""
	if dogs.size() >= MAX_GUARDS:
		return "TOAST_PEN_GUARDS_FULL"
	dog.call("order_guard", self)
	return ""

func unassign_guard(dog: Node) -> void:
	if dog != null and dog.get("guard_pen_id") == pen_id:
		dog.call("stay_here")

## Met une bête d'élevage dans cet enclos : elle quitte son enclos actuel et vient à pied
## (de très loin, elle est ramenée devant la barrière). Renvoie "" ou la clé d'erreur.
func assign_animal(animal: Node) -> String:
	if animal == null or not bool(animal.get("tamed")) or not animal.has_method("can_be_penned") or not bool(animal.call("can_be_penned")):
		return "TOAST_CANNOT_ASSIGN"
	if get_occupants().has(animal) or animal.get("herd_pen") == self:
		return ""
	if free_slots() <= 0:
		return "TOAST_PEN_FULL"
	if bool(animal.get("mounted")):
		return "TOAST_CANNOT_ASSIGN"
	# Une bête dans un autre enclos en sort d'abord par sa barrière.
	var via: Array = []
	for other in get_tree().get_nodes_in_group("pens"):
		if other != self and bool(other.call("contains", animal.global_position)):
			via = [other.call("gate_inside"), other.call("gate_outside")]
			break
	if bool(animal.get("penned")):
		animal.call("leave_pen", animal.global_position)
	animal.set("herd_pen", null)
	if animal.global_position.distance_to(global_position) > HERD_RADIUS * 1.5:
		animal.global_position = gate_outside() + Vector3(0.0, 0.5, 0.0)
		via.clear()
	if not bool(animal.call("herd_to", self, false, via)):
		return "TOAST_CANNOT_ASSIGN"
	return ""

## Fait sortir une bête de cet enclos.
func release_animal(animal: Node) -> void:
	if get_occupants().has(animal):
		animal.call("leave_pen", to_global(Vector3(0.0, 0.0, half() + 2.0)))
	elif animal.get("herd_pen") == self:
		animal.set("herd_pen", null)

func _save_spawner() -> void:
	var spawner := get_parent()
	if spawner != null and spawner.has_method("save_now"):
		spawner.call("save_now")

func apply_state(state: Dictionary) -> void:
	pen_name = String(state.get("name", ""))
	if String(state.get("id", "")) != "":
		pen_id = String(state.get("id"))
	var saved := clampi(int(state.get("level", 1)), 1, MAX_LEVEL)
	if saved != level:
		level = saved
		if is_inside_tree():
			_rebuild()

# --- Modèle ---------------------------------------------------------------------------

func _build() -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.45, 0.3, 0.17)
	wood.roughness = 1.0
	var size := half()
	var gate_half := GATE_WIDTH * 0.5
	# Quatre côtés ; le côté +Z est coupé par l'ouverture.
	_side(Vector3(-size, 0.0, -size), Vector3(size, 0.0, -size), wood)
	_side(Vector3(-size, 0.0, -size), Vector3(-size, 0.0, size), wood)
	_side(Vector3(size, 0.0, -size), Vector3(size, 0.0, size), wood)
	_side(Vector3(-size, 0.0, size), Vector3(-gate_half, 0.0, size), wood)
	_side(Vector3(gate_half, 0.0, size), Vector3(size, 0.0, size), wood)
	_add_trigger(Vector3(GATE_WIDTH + 2.4, 2.0, 4.0), Vector3(0.0, 1.0, size + 0.6))
	if level >= 2:
		_build_trough(wood, size)
	if level >= 3:
		_build_hay_and_shed(wood, size)

## Niveau 2 : abreuvoir et mangeoire le long du fond.
func _build_trough(wood: Material, size: float) -> void:
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.3, 0.5, 0.65)
	water.roughness = 0.2
	_box(Vector3(2.4, 0.4, 0.7), Vector3(-size * 0.4, 0.2, -size + 1.0), wood)
	_box(Vector3(2.2, 0.06, 0.5), Vector3(-size * 0.4, 0.38, -size + 1.0), water)
	_box(Vector3(2.0, 0.45, 0.6), Vector3(size * 0.35, 0.22, -size + 1.0), wood)
	_add_solid(Vector3(2.4, 0.4, 0.7), Vector3(-size * 0.4, 0.2, -size + 1.0))
	_add_solid(Vector3(2.0, 0.45, 0.6), Vector3(size * 0.35, 0.22, -size + 1.0))

## Niveau 3 : bottes de foin et petit abri couvert pour les bêtes.
func _build_hay_and_shed(wood: Material, size: float) -> void:
	var hay := StandardMaterial3D.new()
	hay.albedo_color = Color(0.85, 0.72, 0.35)
	hay.roughness = 1.0
	var roof := StandardMaterial3D.new()
	roof.albedo_color = Color(0.7, 0.55, 0.36)
	roof.roughness = 1.0
	for i in 3:
		_box(Vector3(0.9, 0.6, 0.6), Vector3(size - 1.2, 0.3 + 0.6 * float(i == 2), -size + 1.0 + 0.7 * float(mini(i, 1))), hay)
	_add_solid(Vector3(1.0, 0.6, 1.4), Vector3(size - 1.2, 0.3, -size + 1.4))
	# Appentis dans l'angle arrière gauche : quatre poteaux et un toit.
	var shed_x := -size + 2.4
	var shed_z := -size + 2.2
	for dx in [-1.8, 1.8]:
		for dz in [-1.4, 1.4]:
			_box(Vector3(0.18, 2.1, 0.18), Vector3(shed_x + dx, 1.05, shed_z + dz), wood)
	var top := _box(Vector3(4.2, 0.14, 3.4), Vector3(shed_x, 2.15, shed_z), roof)
	top.rotation_degrees.x = 6.0

func _box(size: Vector3, position: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = position
	add_child(instance)
	return instance

func _add_solid(size: Vector3, position: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = SOLID_LAYER
	body.collision_mask = 0
	body.position = position
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)

## Zone de visée du rayon d'interaction (couche 4) : devant la barrière.
func _add_trigger(size: Vector3, position: Vector3) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = position
	add_child(shape)

## Une section de clôture : poteaux tous les ~1,5 m, deux lisses, un corps solide.
func _side(a: Vector3, b: Vector3, material: Material) -> void:
	var length := a.distance_to(b)
	var direction := (b - a) / length
	var posts := maxi(2, int(round(length / 1.5)) + 1)
	for i in posts:
		var post := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.18, 1.7, 0.18)
		post.mesh = mesh
		post.material_override = material
		post.position = a + direction * (length * float(i) / float(posts - 1)) + Vector3(0.0, 0.45, 0.0)
		add_child(post)
	var yaw := atan2(-direction.z, direction.x)
	for height in [0.55, 1.05]:
		var rail := MeshInstance3D.new()
		var rail_mesh := BoxMesh.new()
		rail_mesh.size = Vector3(length, 0.12, 0.08)
		rail.mesh = rail_mesh
		rail.material_override = material
		rail.position = (a + b) * 0.5 + Vector3(0.0, height, 0.0)
		rail.rotation.y = yaw
		add_child(rail)
	var body := StaticBody3D.new()
	body.collision_layer = SOLID_LAYER
	body.collision_mask = 0
	body.position = (a + b) * 0.5 + Vector3(0.0, 0.6, 0.0)
	body.rotation.y = yaw
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(length, 1.8, 0.25)
	shape.shape = box
	body.add_child(shape)
	add_child(body)
