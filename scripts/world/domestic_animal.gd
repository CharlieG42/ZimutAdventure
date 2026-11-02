class_name DomesticAnimal
extends PassiveAnimal
## Animal domestique : vache, mouton, chèvre, poule, cheval, chien.
## On les apprivoise en les nourrissant (quelques fois). Ensuite :
##  - bétail (vache, mouton, chèvre, poule) : reste près de son enclos et produit du lait,
##    de la laine ou des œufs, à récolter ;
##  - cheval : se monte (déplacement bien plus rapide) ;
##  - chien : suit le joueur (ou reste sur place) et améliore la chasse.

signal state_changed(animal)

const DOMESTIC := {
	"cow": {"scale": 1.3, "fur": Color(0.94, 0.92, 0.88), "belly": Color(0.86, 0.8, 0.74),
			"ear": 0.12, "neck": 0.2, "hop": 0.0, "speed": 0.7},
	"sheep": {"scale": 0.8, "fur": Color(0.93, 0.92, 0.86), "belly": Color(0.22, 0.18, 0.16),
			"ear": 0.1, "neck": 0.2, "hop": 0.0, "speed": 0.8},
	"goat": {"scale": 0.8, "fur": Color(0.58, 0.52, 0.45), "belly": Color(0.86, 0.82, 0.74),
			"ear": 0.14, "neck": 0.26, "hop": 0.05, "speed": 1.0},
	"chicken": {"scale": 0.3, "fur": Color(0.96, 0.95, 0.9), "belly": Color(0.85, 0.5, 0.2),
			"ear": 0.0, "neck": 0.12, "hop": 0.02, "speed": 0.8},
	"horse": {"scale": 1.5, "fur": Color(0.47, 0.29, 0.15), "belly": Color(0.3, 0.19, 0.1),
			"ear": 0.14, "neck": 0.52, "hop": 0.0, "speed": 1.6},
	"dog": {"scale": 0.62, "fur": Color(0.62, 0.45, 0.27), "belly": Color(0.92, 0.86, 0.74),
			"ear": 0.13, "neck": 0.22, "hop": 0.04, "speed": 1.8},
}

const LIVESTOCK := ["cow", "sheep", "goat", "chicken"]
## Nourriture acceptée (la première disponible dans le sac est utilisée).
const FOOD := {
	"cow": ["item_wheat", "item_vegetables", "item_berries"],
	"sheep": ["item_wheat", "item_vegetables", "item_berries"],
	"goat": ["item_wheat", "item_vegetables", "item_berries"],
	"chicken": ["item_grain_seeds", "item_seeds"],
	"horse": ["item_vegetables", "item_berries"],
	"dog": ["item_cooked_meat", "item_raw_meat"],
}
## Nombre de repas pour gagner la confiance de l'animal.
const TRUST_NEEDED := {"cow": 3, "sheep": 3, "goat": 3, "chicken": 2, "horse": 4, "dog": 2}
## Niveau du personnage requis pour apprivoiser.
const TAME_LEVEL := {"cow": 1, "sheep": 1, "goat": 1, "chicken": 1, "horse": 5, "dog": 3}
## Production : objet, délai (s), quantité, invite, outil équipé éventuel.
const PRODUCTS := {
	"cow": {"item": "item_milk", "seconds": 150.0, "amount": 2, "prompt": "ACTION_MILK", "tool": ""},
	"goat": {"item": "item_milk", "seconds": 120.0, "amount": 1, "prompt": "ACTION_MILK", "tool": ""},
	"sheep": {"item": "item_wool", "seconds": 180.0, "amount": 2, "prompt": "ACTION_SHEAR", "tool": "tool_sickle"},
	"chicken": {"item": "item_egg", "seconds": 90.0, "amount": 1, "prompt": "ACTION_EGGS", "tool": ""},
}

## En enclos : l'animal reste dans la clôture et produit plus vite.
const PEN_PRODUCTION_FACTOR := 0.6

var tamed: bool = false
var penned: bool = false
var is_livestock: bool = false
var trust: int = 0
var spawn_key: String = ""
var following: bool = true
var mounted: bool = false
var ready_at: float = 0.0

var _interaction: Area3D
var _indicator: MeshInstance3D
var _time_offset: float = 0.0
var _indicator_time: float = 0.0

func _species_config() -> Dictionary:
	return DOMESTIC.get(species, DOMESTIC["cow"])

func _ready() -> void:
	super._ready()
	add_to_group("domestic")
	wander_radius = 12.0 if species == "horse" else 8.0
	_interaction = AnimalInteraction.create(self)
	add_child(_interaction)
	_build_indicator()
	_refresh_tamed_state()

# --- Temps ------------------------------------------------------------------------

func _now() -> float:
	return Time.get_unix_time_from_system() + _time_offset

## API de test : fait avancer l'horloge de production.
func advance_time(seconds: float) -> void:
	_time_offset += seconds
	_update_indicator()

func is_product_ready() -> bool:
	return tamed and PRODUCTS.has(species) and _now() >= ready_at

# --- Interaction --------------------------------------------------------------------

func can_interact_now() -> bool:
	if mounted or not tamed:
		return true
	if species == "horse" or species == "dog":
		return true
	return is_product_ready()

func get_prompt_key() -> String:
	if mounted:
		return "ACTION_DISMOUNT"
	if not tamed:
		return "ACTION_TAME" if _food_item() != "" else "ACTION_NEED_FOOD"
	match species:
		"horse":
			return "ACTION_MOUNT"
		"dog":
			return "ACTION_DOG_STAY" if following else "ACTION_DOG_FOLLOW"
	return String(PRODUCTS[species]["prompt"]) if PRODUCTS.has(species) else "ACTION_INTERACT"

func interact_with(interactor: Node3D) -> void:
	if mounted:
		dismount(interactor)
	elif not tamed:
		_feed()
	elif species == "horse":
		mount(interactor)
	elif species == "dog":
		following = not following
		_toast(tr("TOAST_DOG_FOLLOW") if following else tr("TOAST_DOG_STAY"))
		state_changed.emit(self)
	else:
		_collect_product()

func _food_item() -> String:
	var inventory := InteractionManager.get_inventory()
	if inventory == null:
		return ""
	for item_id in FOOD.get(species, []):
		if inventory.has_item(item_id, 1):
			return item_id
	return ""

func _feed() -> void:
	var progression := InteractionManager.get_progression()
	var required: int = TAME_LEVEL.get(species, 1)
	if progression != null and not bool(progression.call("meets_level", required)):
		_toast(tr("TOAST_TAME_LEVEL") % [tr("ANIMAL_" + species.to_upper()), required])
		return
	var food := _food_item()
	if food == "":
		var names: PackedStringArray = []
		for item_id in FOOD.get(species, []):
			names.append(tr("ITEM_" + String(item_id).to_upper()))
		_toast(tr("TOAST_NEED_FOOD") % [tr("ANIMAL_" + species.to_upper()), " / ".join(names)])
		return
	InteractionManager.get_inventory().call("remove_item", food, 1)
	trust += 1
	var needed: int = TRUST_NEEDED.get(species, 3)
	if trust >= needed:
		tame()
	else:
		_toast(tr("TOAST_TRUST") % [tr("ANIMAL_" + species.to_upper()), trust, needed])

## L'animal est apprivoisé : il adopte son emplacement actuel comme territoire.
func tame() -> void:
	tamed = true
	trust = int(TRUST_NEEDED.get(species, 3))
	_center = global_position
	ready_at = _now() + float(PRODUCTS[species]["seconds"]) if PRODUCTS.has(species) else 0.0
	_refresh_tamed_state()
	_try_join_pen()
	var progression := InteractionManager.get_progression()
	if progression != null:
		progression.call("add_stat", "stat_tamed", 1)
		if LIVESTOCK.has(species):
			progression.call("add_stat", "stat_tamed_livestock", 1)
		elif species == "dog":
			progression.call("add_stat", "stat_dog", 1)
		elif species == "horse":
			progression.call("add_stat", "stat_horse", 1)
		progression.call("add_xp_for", "tame")
	_toast(tr("TOAST_TAMED") % tr("ANIMAL_" + species.to_upper()))
	state_changed.emit(self)

func _collect_product() -> void:
	var product: Dictionary = PRODUCTS[species]
	var tool_id := String(product["tool"])
	var inventory := InteractionManager.get_inventory()
	if inventory == null:
		return
	if tool_id != "" and not inventory.is_equipped(tool_id):
		_toast(tr("TOAST_NEED_SICKLE_SHEAR"))
		return
	var amount := int(product["amount"])
	var progression := InteractionManager.get_progression()
	if progression != null:
		amount = int(progression.call("roll_loot", amount))
		progression.call("add_stat", "stat_products", 1)
		progression.call("add_xp_for", "product")
	inventory.call("add_item", String(product["item"]), amount)
	ready_at = _now() + _production_seconds()
	_update_indicator()
	state_changed.emit(self)

## Un prédateur est passé : la bête, effrayée, produit avec retard.
func scare_by_predator() -> void:
	if not tamed:
		return
	if PRODUCTS.has(species):
		ready_at = maxf(ready_at, _now()) + 120.0
		_update_indicator()
	_toast(tr("TOAST_RAIDED") % tr("ANIMAL_" + species.to_upper()))
	state_changed.emit(self)

func _production_seconds() -> float:
	var seconds := float(PRODUCTS[species]["seconds"])
	return seconds * (PEN_PRODUCTION_FACTOR if penned else 1.0)

## Entre dans un enclos : l'animal s'y installe et ne quitte plus ses abords.
func enter_pen(spot: Vector3, radius: float) -> void:
	penned = true
	global_position = spot + Vector3(0.0, 0.5, 0.0)
	velocity = Vector3.ZERO
	_center = spot
	wander_radius = radius
	_start_walk()
	state_changed.emit(self)

## Cherche un enclos de la région pour y installer l'animal qui vient d'être apprivoisé.
func _try_join_pen() -> void:
	if not is_inside_tree() or not is_livestock or penned:
		return
	for pen in get_tree().get_nodes_in_group("pens"):
		if pen.global_position.distance_to(global_position) <= 40.0 and pen.admit(self):
			_toast(tr("TOAST_PENNED"))
			return

func _refresh_tamed_state() -> void:
	is_livestock = LIVESTOCK.has(species)
	if tamed:
		add_to_group("tamed")
	wander_radius = (12.0 if species == "horse" else 8.0)

# --- Monture ----------------------------------------------------------------------------

func mount(rider: Node3D) -> void:
	if rider == null or not rider.has_method("mount"):
		return
	mounted = true
	_player = rider
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	rider.call("mount", self)
	InteractionManager.set_forced_target(_interaction)
	_toast(tr("TOAST_MOUNTED"))

func dismount(rider: Node3D) -> void:
	mounted = false
	collision_layer = 1
	collision_mask = 1
	if rider != null:
		var side := rider.global_transform.basis.x.normalized()
		global_position = rider.global_position + side * 1.4
		if rider.has_method("dismount"):
			rider.call("dismount")
	_center = global_position
	velocity = Vector3.ZERO
	state_changed.emit(self)

func _physics_process(delta: float) -> void:
	if mounted and _player != null and is_instance_valid(_player):
		global_position = _player.global_position
		var rider_velocity: Vector3 = _player.get("velocity") if _player.get("velocity") != null else Vector3.ZERO
		var flat := Vector3(rider_velocity.x, 0.0, rider_velocity.z)
		if flat.length() > 0.4:
			rotation.y = lerp_angle(rotation.y, atan2(flat.x, flat.z), minf(1.0, 10.0 * delta))
		velocity = flat
		_fleeing = flat.length() > 6.5
		_animate(delta)
		return
	super._physics_process(delta)
	_indicator_time += delta
	if _indicator_time > 0.5:
		_indicator_time = 0.0
		_update_indicator()

# --- Comportement ---------------------------------------------------------------------

## Un animal sauvage de ferme se laisse approcher ; cheval et chien restent un peu plus craintifs.
func _scare_direction() -> Vector3:
	if tamed or _player == null or not is_instance_valid(_player):
		return Vector3.ZERO
	var away := global_position - _player.global_position
	away.y = 0.0
	var limit := 2.2 if (species == "horse" or species == "dog") else 1.0
	var distance := away.length()
	if distance >= limit or distance < 0.001:
		return Vector3.ZERO
	return away / distance

func _update_behavior(delta: float) -> void:
	if (_player == null or not is_instance_valid(_player)) and is_inside_tree():
		_player = get_tree().get_first_node_in_group("player") as Node3D
	if species == "dog" and tamed and following and _player != null and is_instance_valid(_player):
		_follow_player(delta)
		return
	super._update_behavior(delta)

func _follow_player(delta: float) -> void:
	var to_player := _player.global_position - global_position
	to_player.y = 0.0
	var distance := to_player.length()
	if distance > 45.0:
		global_position = _player.global_position + Vector3(2.0, 1.0, 2.0)
		return
	var wanted := Vector3.ZERO
	var speed_scale: float = _config["speed"]
	if distance > 3.0:
		wanted = to_player / distance * (WANDER_SPEED if distance < 7.0 else FLEE_SPEED * 0.9) * speed_scale
	_fleeing = distance > 7.0
	_track_stuck(wanted, delta)
	velocity.x = move_toward(velocity.x, wanted.x, 30.0 * delta)
	velocity.z = move_toward(velocity.z, wanted.z, 30.0 * delta)
	if wanted.length_squared() > 0.01:
		_face_direction(wanted.normalized(), delta)

## Les animaux domestiques ne se chassent pas : la flèche les effraie, sans les blesser.
func take_arrow_hit(from_position: Vector3) -> void:
	var away := global_position - from_position
	away.y = 0.0
	if away.length_squared() > 0.001:
		_target = global_position + away.normalized() * wander_radius
	_mode = Mode.WALK
	_mode_left = 4.0

# --- Persistance --------------------------------------------------------------------------

func get_state() -> Dictionary:
	return {"key": spawn_key, "species": species, "pos": _center if not mounted else global_position,
			"ready_at": ready_at, "following": following, "penned": penned}

func apply_state(state: Dictionary) -> void:
	tamed = true
	trust = int(TRUST_NEEDED.get(species, 3))
	ready_at = float(state.get("ready_at", 0.0))
	following = bool(state.get("following", true))
	penned = bool(state.get("penned", false))
	if penned:
		wander_radius = 3.0
	spawn_key = String(state.get("key", spawn_key))
	if is_inside_tree():
		_center = global_position
		_refresh_tamed_state()
		_update_indicator()

# --- Indicateur de production ----------------------------------------------------------------

func _build_indicator() -> void:
	_indicator = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.1
	sphere.height = 0.2
	sphere.radial_segments = 8
	sphere.rings = 4
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.92, 0.35)
	sphere.material = material
	_indicator.mesh = sphere
	_indicator.position = Vector3(0.0, 1.3 * float(_config["scale"]) + 0.5, 0.0)
	_indicator.visible = false
	add_child(_indicator)

func _update_indicator() -> void:
	if _indicator != null:
		_indicator.visible = is_product_ready()

func _toast(message: String) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var hud := tree.get_first_node_in_group("hud") as Node
	if hud != null and hud.has_method("show_toast"):
		hud.show_toast(message, 2.2)

# --- Modèle ---------------------------------------------------------------------------------

func _build_model() -> void:
	if species == "chicken":
		_build_chicken()
		return
	super._build_model()
	_decorate()

## Détails propres à chaque espèce, ajoutés au modèle de base à quatre pattes.
func _decorate() -> void:
	var dark := _material(Color(0.14, 0.1, 0.08))
	match species:
		"cow":
			var patch := _material(Color(0.16, 0.13, 0.12))
			for spot in [Vector3(0.22, 0.95, 0.15), Vector3(-0.2, 0.88, -0.2), Vector3(0.18, 0.82, -0.3), Vector3(-0.24, 1.0, 0.3)]:
				_add_mesh(_model, _sphere(0.13), patch, spot, Vector3.ZERO, Vector3(0.8, 1.0, 1.1))
			var horn := _material(Color(0.9, 0.86, 0.75))
			for side in [-1.0, 1.0]:
				_add_mesh(_head, _cone(0.03, 0.16), horn, Vector3(0.09 * side, 0.17, 0.0), Vector3(0.0, 0.0, -50.0 * side))
			_add_mesh(_model, _sphere(0.12), _material(Color(0.95, 0.7, 0.68)), Vector3(0.0, 0.62, -0.18), Vector3.ZERO, Vector3(1.2, 0.8, 1.0))
		"sheep":
			var wool := _material(Color(0.95, 0.94, 0.9))
			for puff in [Vector3(0, 1.0, 0.18), Vector3(0, 1.02, -0.2), Vector3(0.2, 0.92, 0.0), Vector3(-0.2, 0.92, 0.0),
					Vector3(0.12, 1.06, 0.0), Vector3(-0.12, 1.06, 0.0), Vector3(0, 0.82, 0.3), Vector3(0, 0.82, -0.32)]:
				_add_mesh(_model, _sphere(0.2), wool, puff, Vector3.ZERO)
			_add_mesh(_head, _sphere(0.1), dark, Vector3(0.0, 0.02, 0.1), Vector3.ZERO, Vector3(0.95, 0.9, 1.2))
		"goat":
			var horn := _material(Color(0.25, 0.2, 0.16))
			for side in [-1.0, 1.0]:
				_add_mesh(_head, _cone(0.025, 0.24), horn, Vector3(0.06 * side, 0.2, -0.05), Vector3(-35.0, 0.0, -12.0 * side))
			_add_mesh(_head, _cone(0.03, 0.12), _material(Color(0.88, 0.84, 0.76)), Vector3(0.0, -0.1, 0.18), Vector3(160.0, 0.0, 0.0))
		"horse":
			var mane := _material(Color(0.12, 0.08, 0.05))
			_add_mesh(_neck, _capsule(0.07, 0.6), mane, Vector3(0.0, 0.3, -0.1), Vector3.ZERO)
			_add_mesh(_model, _capsule(0.07, 0.8), mane, Vector3(0.0, 0.62, -0.62), Vector3(20.0, 0.0, 0.0))
			_add_mesh(_head, _sphere(0.1), mane, Vector3(0.0, 0.0, 0.16), Vector3.ZERO, Vector3(0.9, 0.9, 1.5))
			_add_mesh(_model, _sphere(0.2), _material(Color(0.45, 0.3, 0.18)), Vector3(0.0, 1.17, -0.02), Vector3.ZERO, Vector3(1.4, 0.3, 1.8))
		"dog":
			_add_mesh(_model, _capsule(0.04, 0.4), _material(_config["fur"]), Vector3(0.0, 1.08, -0.62), Vector3(-50.0, 0.0, 0.0))
			_add_mesh(_head, _sphere(0.05), dark, Vector3(0.0, 0.0, 0.3), Vector3.ZERO)

func _build_chicken() -> void:
	var s: float = _config["scale"]
	var white := _material(_config["fur"])
	var red := _material(Color(0.8, 0.12, 0.1))
	var orange := _material(Color(0.95, 0.65, 0.15))
	var dark := _material(Color(0.1, 0.08, 0.06))
	_model = Node3D.new()
	_model.name = "Model"
	_model.scale = Vector3.ONE * s * 2.2
	add_child(_model)
	_add_mesh(_model, _sphere(0.28), white, Vector3(0.0, 0.52, 0.0), Vector3.ZERO, Vector3(0.85, 0.95, 1.25))
	_add_mesh(_model, _sphere(0.14), white, Vector3(0.0, 0.72, -0.3), Vector3(-30.0, 0.0, 0.0), Vector3(0.5, 1.4, 1.0))
	_neck = Node3D.new()
	_neck.position = Vector3(0.0, 0.62, 0.22)
	_neck.rotation_degrees = Vector3(20.0, 0.0, 0.0)
	_model.add_child(_neck)
	_add_mesh(_neck, _capsule(0.07, 0.3), white, Vector3(0.0, 0.14, 0.0), Vector3.ZERO)
	_head = Node3D.new()
	_head.position = Vector3(0.0, 0.3, 0.0)
	_head.rotation_degrees = Vector3(-20.0, 0.0, 0.0)
	_neck.add_child(_head)
	_add_mesh(_head, _sphere(0.09), white, Vector3(0.0, 0.0, 0.03), Vector3.ZERO)
	_add_mesh(_head, _cone(0.04, 0.12), orange, Vector3(0.0, -0.01, 0.13), Vector3(90.0, 0.0, 0.0))
	_add_mesh(_head, _sphere(0.04), red, Vector3(0.0, 0.09, 0.03), Vector3.ZERO, Vector3(0.4, 1.0, 1.2))
	_add_mesh(_head, _sphere(0.02), dark, Vector3(0.06, 0.02, 0.07), Vector3.ZERO)
	_add_mesh(_head, _sphere(0.02), dark, Vector3(-0.06, 0.02, 0.07), Vector3.ZERO)
	for x in [-0.09, 0.09]:
		var hip := Node3D.new()
		hip.position = Vector3(x, 0.3, 0.0)
		_model.add_child(hip)
		_add_mesh(hip, _cylinder(0.014, 0.018, 0.3), orange, Vector3(0.0, -0.15, 0.0), Vector3.ZERO)
		_add_mesh(hip, _sphere(0.04), orange, Vector3(0.0, -0.3, 0.04), Vector3.ZERO, Vector3(1.0, 0.4, 1.6))
		_legs.append(hip)
