class_name PlacedStructure
extends Interactable
## Construction posée dans le monde (lit de camp, abri). Le modèle, la collision et la
## zone d'interaction sont construits en code. Se crée avec PlacedStructure.create().
##  - camp_bed : se reposer (récupère l'endurance)
##  - shelter  : dormir, uniquement la nuit (la journée repart à 7 h)

const KINDS := ["camp_bed", "shelter"]
const SOLID_LAYER := 1
const WAKE_HOUR := 7.0
const MAX_LEVEL := 3
## Coût pour atteindre chaque niveau (index = niveau visé). Seul l'abri évolue.
const UPGRADE_COSTS := {
	"shelter": {
		2: {"item_wood": 6, "item_pelt": 2},
		3: {"item_wood": 8, "item_stone": 6, "item_pelt": 2},
	},
}
## Part de santé rendue par une nuit dans l'abri, selon son niveau.
const SLEEP_HEAL := {1: 0.0, 2: 0.35, 3: 0.8}

@export var kind: String = "camp_bed"
## Niveau de la construction (1 à MAX_LEVEL).
var level: int = 1

static func create(structure_kind: String) -> Area3D:
	var area := Area3D.new()
	area.set_script(load("res://scripts/world/placed_structure.gd"))
	area.set("kind", structure_kind)
	area.collision_layer = 4
	area.collision_mask = 0
	area.name = structure_kind.to_pascal_case()
	return area

func _ready() -> void:
	add_to_group("structures")
	prompt_text = "ACTION_SLEEP" if kind == "shelter" else "ACTION_REST_BED"
	if kind == "wool_bed" and _is_night():
		prompt_text = "ACTION_SLEEP"
	_build()

func _build() -> void:
	match kind:
		"shelter":
			_build_shelter()
		_:
			_build_bed()

# --- Évolution ------------------------------------------------------------------------

func can_upgrade() -> bool:
	return UPGRADE_COSTS.has(kind) and level < MAX_LEVEL

## Matériaux du prochain niveau ({} si la construction est au maximum).
func next_upgrade_cost() -> Dictionary:
	if not can_upgrade():
		return {}
	return (UPGRADE_COSTS[kind] as Dictionary).get(level + 1, {})

## Matériaux qui manquent dans le sac pour le prochain niveau.
func upgrade_missing() -> Dictionary:
	var missing := {}
	var inventory := InteractionManager.get_inventory()
	for item_id in next_upgrade_cost():
		var have: int = int(inventory.call("count_of", item_id)) if inventory != null else 0
		var need: int = int(next_upgrade_cost()[item_id])
		if have < need:
			missing[item_id] = need - have
	return missing

## Améliore la construction. Renvoie "" si réussi, sinon la clé d'erreur.
func upgrade() -> String:
	if not can_upgrade():
		return "TOAST_MAX_LEVEL"
	if not upgrade_missing().is_empty():
		return "TOAST_UPGRADE_MISSING"
	var inventory := InteractionManager.get_inventory()
	var cost := next_upgrade_cost()
	for item_id in cost:
		inventory.call("remove_item", item_id, int(cost[item_id]))
	level += 1
	_rebuild()
	var progression := InteractionManager.get_progression()
	if progression != null:
		progression.call("add_xp_for", "build")
	var spawner := get_parent()
	if spawner != null and spawner.has_method("save_now"):
		spawner.call("save_now")
	return ""

func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_build()

func get_state() -> Dictionary:
	return {"level": level}

func apply_state(state: Dictionary) -> void:
	var saved := clampi(int(state.get("level", 1)), 1, MAX_LEVEL)
	if saved != level and UPGRADE_COSTS.has(kind):
		level = saved
		# Avant l'entrée dans l'arbre, _ready() construira directement au bon niveau.
		if is_inside_tree():
			_rebuild()

## Il fait nuit (le lit en laine permet de dormir comme l'abri).
func _is_night() -> bool:
	var clock := get_node_or_null("/root/DayNightCycle")
	if clock == null:
		return false
	var hour := float(clock.get("hour"))
	return hour >= 19.0 or hour < 5.0

func get_prompt() -> String:
	if kind == "shelter" and level >= MAX_LEVEL and not _is_night():
		return "ACTION_REST_BED"
	if kind == "wool_bed":
		return "ACTION_SLEEP" if _is_night() else "ACTION_REST_BED"
	return prompt_text

func _on_interact(interactor: Node3D) -> void:
	if kind == "shelter" and level >= MAX_LEVEL and not _is_night():
		# La cabane est assez confortable pour une sieste de jour.
		_rest(interactor)
	elif kind == "wool_bed" and not _is_night():
		_rest(interactor)
	elif kind == "shelter" or kind == "wool_bed":
		_sleep(interactor)
	else:
		_rest(interactor)

## Se reposer ou dormir ici fixe le point de réveil après une défaite.
func _set_wake_point(interactor: Node3D) -> void:
	if interactor != null and interactor.has_method("set_home"):
		interactor.call("set_home", global_position + global_transform.basis.z * 1.6)

func _rest(interactor: Node3D) -> void:
	_set_wake_point(interactor)
	if interactor != null and interactor.has_method("restore_stamina"):
		interactor.restore_stamina()
	var survival := InteractionManager.get_survival()
	if survival != null:
		survival.call("heal", 1.0 if kind == "wool_bed" else 0.5)
	_toast("TOAST_BED_REST")

func _sleep(interactor: Node3D) -> void:
	var clock := get_node_or_null("/root/DayNightCycle")
	var hour := float(clock.get("hour")) if clock != null else 12.0
	var is_night := hour >= 19.0 or hour < 5.0
	if clock == null or not is_night:
		_toast("TOAST_NOT_TIRED")
		return
	_set_wake_point(interactor)
	clock.call("set_hour", WAKE_HOUR)
	if interactor != null and interactor.has_method("restore_stamina"):
		interactor.restore_stamina()
	var heal: float = float(SLEEP_HEAL.get(level, 0.0)) if kind == "shelter" else 0.0
	var survival := InteractionManager.get_survival()
	if heal > 0.0 and survival != null:
		survival.call("heal", heal)
	_toast("TOAST_SLEPT")

func _toast(key: String) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var hud := tree.get_first_node_in_group("hud") as Node
	if hud != null and hud.has_method("show_toast"):
		hud.show_toast(tr(key), 2.5)

# --- Modèles ----------------------------------------------------------------------

func _build_bed() -> void:
	var wood := _material(Color(0.42, 0.27, 0.15))
	var cloth := _material(Color(0.93, 0.9, 0.82) if kind == "wool_bed" else Color(0.62, 0.3, 0.2))
	var pillow := _material(Color(0.9, 0.84, 0.7))
	# Cadre (4 pieds + 2 longerons), matelas, oreiller. Avant du lit : +Z.
	_box(self, Vector3(0.9, 0.12, 2.0), Vector3(0.0, 0.36, 0.0), wood)
	for x in [-0.42, 0.42]:
		for z in [-0.92, 0.92]:
			_box(self, Vector3(0.08, 0.34, 0.08), Vector3(x, 0.17, z), wood)
	_box(self, Vector3(0.82, 0.14, 1.9), Vector3(0.0, 0.5, 0.0), cloth)
	_box(self, Vector3(0.6, 0.1, 0.34), Vector3(0.0, 0.62, -0.68), pillow)
	_add_solid(Vector3(0.9, 0.6, 2.0), Vector3(0.0, 0.3, 0.0))
	_add_trigger(Vector3(1.6, 1.6, 2.6), Vector3(0.0, 0.8, 0.0))

func _build_shelter() -> void:
	var wood := _material(Color(0.4, 0.26, 0.14))
	var hide := _material(Color(0.7, 0.55, 0.36))
	var mat := _material(Color(0.55, 0.22, 0.16))
	# Abri adossé : paroi du fond, deux montants latéraux, toit incliné, tapis. Ouvert en +Z.
	_box(self, Vector3(3.0, 2.0, 0.16), Vector3(0.0, 1.0, -1.4), wood)
	for x in [-1.42, 1.42]:
		_box(self, Vector3(0.16, 2.0, 2.8), Vector3(x, 1.0, 0.0), wood)
	var roof := _box(self, Vector3(3.5, 0.14, 3.2), Vector3(0.0, 2.1, -0.1), hide)
	roof.rotation_degrees.x = 7.0
	_box(self, Vector3(2.4, 0.04, 2.2), Vector3(0.0, 0.03, 0.1), mat)
	_add_solid(Vector3(3.0, 2.0, 0.16), Vector3(0.0, 1.0, -1.4))
	for x in [-1.42, 1.42]:
		_add_solid(Vector3(0.16, 2.0, 2.8), Vector3(x, 1.0, 0.0))
	_add_solid(Vector3(3.5, 0.2, 3.2), Vector3(0.0, 2.15, -0.1))
	if level >= 2:
		_build_shelter_reinforced(wood, hide)
	if level >= 3:
		_build_shelter_cabin(wood, hide)
	_add_trigger(Vector3(2.6, 2.0, 2.6), Vector3(0.0, 1.0, 0.1))

## Niveau 2 : seuil et pieux de façade, peaux tendues sur les côtés, couchage garni.
func _build_shelter_reinforced(wood: Material, hide: Material) -> void:
	var fur := _material(Color(0.82, 0.72, 0.58))
	for x in [-1.42, 1.42]:
		_box(self, Vector3(0.2, 2.3, 0.2), Vector3(x, 1.15, 1.45), wood)
	_box(self, Vector3(3.1, 0.14, 0.16), Vector3(0.0, 2.3, 1.45), wood)
	for x in [-1.1, 1.1]:
		_box(self, Vector3(0.7, 1.3, 0.05), Vector3(x, 1.5, 1.45), hide)
	_box(self, Vector3(1.8, 0.16, 0.9), Vector3(0.0, 0.1, -0.85), fur)
	_box(self, Vector3(0.9, 0.05, 1.4), Vector3(0.0, 0.07, 0.7), fur)

## Niveau 3 : cabane — second toit, foyer de pierre au fond et lanterne.
func _build_shelter_cabin(wood: Material, hide: Material) -> void:
	var stone := _material(Color(0.5, 0.48, 0.46))
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(1.0, 0.78, 0.4)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.62, 0.22)
	glow.emission_energy_multiplier = 1.6
	# Second toit posé sur des chevrons, même pente que le premier (pas d'interpénétration).
	for x in [-1.5, 0.0, 1.5]:
		_box(self, Vector3(0.12, 0.34, 3.2), Vector3(x, 2.33, -0.1), wood).rotation_degrees.x = 7.0
	var upper := _box(self, Vector3(3.9, 0.14, 3.6), Vector3(0.0, 2.58, -0.1), hide)
	upper.rotation_degrees.x = 7.0
	_box(self, Vector3(1.0, 0.5, 0.6), Vector3(1.0, 0.25, -1.0), stone)
	_box(self, Vector3(0.7, 0.16, 0.4), Vector3(1.0, 0.58, -1.0), stone)
	_box(self, Vector3(0.16, 0.22, 0.16), Vector3(-1.0, 1.7, 0.9), glow)
	_box(self, Vector3(0.04, 0.3, 0.04), Vector3(-1.0, 1.95, 0.9), wood)
	_add_solid(Vector3(1.0, 0.5, 0.6), Vector3(1.0, 0.25, -1.0))

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.95
	return material

func _box(parent: Node3D, size: Vector3, position: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = position
	parent.add_child(instance)
	return instance

## Collision pleine sur la couche 1 (celle du terrain), comme tout prop solide.
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

## Zone de visée du rayon d'interaction (couche 4, portée par l'Area3D racine).
func _add_trigger(size: Vector3, position: Vector3) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = position
	add_child(shape)
