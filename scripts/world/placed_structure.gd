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
## Le même terrain doit rester libre quand l'abri s'agrandit.
const UPGRADE_ROOM_ERROR := "TOAST_UPGRADE_NO_ROOM"
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

## Transparence de l'abri quand la caméra s'en approche (sinon un mur remplit tout l'écran).
const FADE_MARGIN := 2.6
const FADE_ALPHA := 0.8
var _fade: float = 0.0
var _fade_meshes: Array = []

func _process(delta: float) -> void:
	if kind != "shelter" or not is_inside_tree():
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var target := FADE_ALPHA if camera_is_near(camera.global_position) else 0.0
	if is_equal_approx(_fade, target):
		return
	_fade = move_toward(_fade, target, delta * 4.0)
	_apply_fade()

## Vrai quand le point (la caméra) est dans ou tout contre l'abri.
func camera_is_near(point: Vector3) -> bool:
	var size := shelter_size()
	var local := to_local(point)
	return absf(local.x) < size.x * 0.5 + FADE_MARGIN \
			and local.z < FRONT_Z + FADE_MARGIN and local.z > FRONT_Z - size.z - FADE_MARGIN \
			and local.y < size.y + FADE_MARGIN and local.y > -1.0

func fade_amount() -> float:
	return _fade

func _apply_fade() -> void:
	if _fade_meshes.is_empty():
		_fade_meshes = find_children("*", "MeshInstance3D", true, false)
	for mesh in _fade_meshes:
		if is_instance_valid(mesh):
			(mesh as MeshInstance3D).transparency = _fade

func _build() -> void:
	_fade_meshes.clear()
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

## Niveau du joueur requis pour chaque niveau de bâtiment.
const UPGRADE_PLAYER_LEVEL := {2: 3, 3: 5}

func upgrade_required_level() -> int:
	return int(UPGRADE_PLAYER_LEVEL.get(level + 1, 1)) if can_upgrade() else 0

## Améliore la construction. Renvoie "" si réussi, sinon la clé d'erreur.
func upgrade() -> String:
	if not can_upgrade():
		return "TOAST_MAX_LEVEL"
	var progression_check := InteractionManager.get_progression()
	if progression_check != null and int(progression_check.call("get_level")) < upgrade_required_level():
		return "TOAST_UPGRADE_LEVEL"
	if not upgrade_missing().is_empty():
		return "TOAST_UPGRADE_MISSING"
	if kind == "shelter" and not _has_room_to_grow():
		return UPGRADE_ROOM_ERROR
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

## L'agrandissement ne doit pas avaler une autre construction (un coffre, un feu...) :
## seuls les objets déjà sous le toit actuel restent permis.
func _has_room_to_grow() -> bool:
	var old_size := shelter_size()
	level += 1
	var new_size := shelter_size()
	level -= 1
	for other in get_tree().get_nodes_in_group("structures") if is_inside_tree() else []:
		if other == self or not (other is Node3D):
			continue
		var local := to_local((other as Node3D).global_position)
		var in_new: bool = absf(local.x) < new_size.x * 0.5 + 0.4 and local.z < FRONT_Z + 0.4 and local.z > FRONT_Z - new_size.z - 0.4
		var in_old: bool = absf(local.x) < old_size.x * 0.5 + 0.4 and local.z < FRONT_Z + 0.4 and local.z > FRONT_Z - old_size.z - 0.4
		if in_new and not in_old:
			return false
	return true

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

## Dimensions de l'abri par niveau : largeur (X), profondeur (Z) et hauteur sous toit.
## L'entrée reste au même endroit (z = FRONT_Z) : en montant de niveau l'abri s'élargit et
## s'enfonce vers l'arrière, pour offrir plus de place à l'intérieur.
const SHELTER_SIZES := {
	1: Vector3(3.0, 2.0, 2.8),
	2: Vector3(4.6, 2.3, 4.0),
	3: Vector3(6.2, 2.6, 5.4),
}
const FRONT_Z := 1.4
const WALL := 0.16

func shelter_size() -> Vector3:
	return SHELTER_SIZES[clampi(level, 1, MAX_LEVEL)]

## Centre de l'intérieur (repère local) : l'abri grandit vers le fond.
func _interior_center_z(size: Vector3) -> float:
	return FRONT_Z - size.z * 0.5

## Centre de l'abri dans le monde (le chauffage et la détection d'abri s'y réfèrent).
func shelter_center() -> Vector3:
	return to_global(Vector3(0.0, 0.0, _interior_center_z(shelter_size())))

## Rayon dans lequel on est « à l'abri » : s'agrandit avec l'abri.
func shelter_radius() -> float:
	var size := shelter_size()
	return maxf(size.x, size.z) * 0.5 + 3.0

## Surface intérieure approximative en m² (affichée dans le détail du niveau).
func interior_area() -> float:
	var size := shelter_size()
	return (size.x - 2.0 * WALL) * (size.z - WALL)

## Un point du monde est-il sous le toit de l'abri ?
func contains_point(point: Vector3) -> bool:
	if kind != "shelter":
		return false
	var size := shelter_size()
	var local := to_local(point)
	return absf(local.x) < size.x * 0.5 - WALL and local.z < FRONT_Z + 0.2 and local.z > FRONT_Z - size.z

## Volume invisible : les animaux (cheval compris) ne peuvent pas entrer dans l'abri, le joueur si.
func _add_animal_block(size: Vector3, position: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = "AnimalBlock"
	body.collision_layer = 128
	body.collision_mask = 0
	body.position = position
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)

func _build_shelter() -> void:
	var size := shelter_size()
	var width := size.x
	var depth := size.z
	var height := size.y
	var center_z := _interior_center_z(size)
	var wood := _material(Color(0.4, 0.26, 0.14))
	var hide := _material(Color(0.7, 0.55, 0.36))
	var mat := _material(Color(0.55, 0.22, 0.16))
	# Abri adossé : paroi du fond, deux montants latéraux, toit incliné, tapis. Ouvert en +Z.
	var back_z := FRONT_Z - depth + WALL * 0.5
	_box(self, Vector3(width, height, WALL), Vector3(0.0, height * 0.5, back_z), wood)
	for x in [-(width * 0.5 - WALL * 0.5), width * 0.5 - WALL * 0.5]:
		_box(self, Vector3(WALL, height, depth), Vector3(x, height * 0.5, center_z), wood)
	var roof := _box(self, Vector3(width + 0.5, 0.14, depth + 0.4), Vector3(0.0, height + 0.1, center_z - 0.1), hide)
	roof.rotation_degrees.x = 7.0
	_box(self, Vector3(width - 0.6, 0.04, depth - 0.6), Vector3(0.0, 0.03, center_z + 0.1), mat)
	_add_solid(Vector3(width, height, WALL), Vector3(0.0, height * 0.5, back_z))
	for x in [-(width * 0.5 - WALL * 0.5), width * 0.5 - WALL * 0.5]:
		_add_solid(Vector3(WALL, height, depth), Vector3(x, height * 0.5, center_z))
	_add_solid(Vector3(width + 0.5, 0.2, depth + 0.4), Vector3(0.0, height + 0.15, center_z - 0.1))
	if level >= 2:
		_build_shelter_reinforced(wood, hide, size)
	if level >= 3:
		_build_shelter_cabin(wood, hide, size)
	_add_trigger(Vector3(width - 0.4, height, depth - 0.2), Vector3(0.0, height * 0.5, center_z + 0.1))
	_add_animal_block(Vector3(width, height, depth + 0.4), Vector3(0.0, height * 0.5, center_z + 0.2))

## Niveau 2 : seuil et pieux de façade, peaux tendues, étagère au fond, couchages garnis.
func _build_shelter_reinforced(wood: Material, hide: Material, size: Vector3) -> void:
	var fur := _material(Color(0.82, 0.72, 0.58))
	var width := size.x
	var depth := size.z
	var center_z := _interior_center_z(size)
	var back_z := FRONT_Z - depth + WALL
	for x in [-width * 0.5, width * 0.5]:
		_box(self, Vector3(0.2, size.y + 0.3, 0.2), Vector3(x, (size.y + 0.3) * 0.5, FRONT_Z + 0.05), wood)
	_box(self, Vector3(width + 0.1, 0.14, 0.16), Vector3(0.0, size.y + 0.3, FRONT_Z + 0.05), wood)
	for x in [-(width * 0.5 - 0.5), width * 0.5 - 0.5]:
		_box(self, Vector3(0.7, 1.3, 0.05), Vector3(x, size.y - 0.8, FRONT_Z + 0.05), hide)
	# Deux couchages de fourrure le long du fond, un tapis à l'entrée.
	for x in [-width * 0.25, width * 0.25]:
		_box(self, Vector3(1.4, 0.16, 0.9), Vector3(x, 0.1, back_z + 0.6), fur)
	_box(self, Vector3(1.0, 0.05, 1.4), Vector3(0.0, 0.07, FRONT_Z - 0.9), fur)
	# Étagère de rangement contre la paroi du fond.
	_box(self, Vector3(width - 1.2, 0.08, 0.35), Vector3(0.0, 1.3, back_z + 0.2), wood)
	_box(self, Vector3(width - 1.2, 0.08, 0.35), Vector3(0.0, 0.85, back_z + 0.2), wood)
	for x in [-(width * 0.5 - 0.65), width * 0.5 - 0.65]:
		_box(self, Vector3(0.08, 1.3, 0.35), Vector3(x, 0.65, back_z + 0.2), wood)
	var jar := _material(Color(0.62, 0.4, 0.24))
	for x in [-0.6, 0.0, 0.7]:
		_box(self, Vector3(0.22, 0.26, 0.22), Vector3(x, 1.47, back_z + 0.2), jar)
	_box(self, Vector3(0.3, 0.2, 0.3), Vector3(-0.3, 0.99, back_z + 0.2), jar)

## Niveau 3 : cabane — second toit, foyer de pierre, table et tabourets, lanternes.
func _build_shelter_cabin(wood: Material, hide: Material, size: Vector3) -> void:
	var stone := _material(Color(0.5, 0.48, 0.46))
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(1.0, 0.78, 0.4)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.62, 0.22)
	glow.emission_energy_multiplier = 1.6
	var width := size.x
	var depth := size.z
	var center_z := _interior_center_z(size)
	var back_z := FRONT_Z - depth + WALL
	# Second toit posé sur des chevrons, même pente que le premier (pas d'interpénétration).
	var rafters := 3 + int(width / 2.0)
	for i in rafters:
		var x := -width * 0.5 + width * (float(i) + 0.5) / float(rafters)
		_box(self, Vector3(0.12, 0.34, depth + 0.4), Vector3(x, size.y + 0.33, center_z - 0.1), wood).rotation_degrees.x = 7.0
	var upper := _box(self, Vector3(width + 0.9, 0.14, depth + 0.8), Vector3(0.0, size.y + 0.58, center_z - 0.1), hide)
	upper.rotation_degrees.x = 7.0
	# Foyer de pierre dans l'angle du fond.
	var hearth_x := width * 0.5 - 0.9
	_box(self, Vector3(1.0, 0.5, 0.6), Vector3(hearth_x, 0.25, back_z + 0.4), stone)
	_box(self, Vector3(0.7, 0.16, 0.4), Vector3(hearth_x, 0.58, back_z + 0.4), stone)
	_box(self, Vector3(0.5, size.y - 0.6, 0.4), Vector3(hearth_x, 0.6 + (size.y - 0.6) * 0.5, back_z + 0.3), stone)
	_add_solid(Vector3(1.0, 0.5, 0.6), Vector3(hearth_x, 0.25, back_z + 0.4))
	# Table et deux tabourets.
	var table_z := center_z + 0.3
	var table_x := -width * 0.5 + 1.3
	_box(self, Vector3(1.3, 0.08, 0.8), Vector3(table_x, 0.78, table_z), wood)
	for dx in [-0.55, 0.55]:
		for dz in [-0.3, 0.3]:
			_box(self, Vector3(0.08, 0.76, 0.08), Vector3(table_x + dx, 0.38, table_z + dz), wood)
	for dz in [-0.75, 0.75]:
		_box(self, Vector3(0.36, 0.4, 0.36), Vector3(table_x, 0.2, table_z + dz), wood)
	_add_solid(Vector3(1.3, 0.8, 0.8), Vector3(table_x, 0.4, table_z))
	# Lanternes de part et d'autre de l'entrée et au-dessus de la table.
	for x in [-(width * 0.5 - 0.5), width * 0.5 - 0.5]:
		_box(self, Vector3(0.16, 0.22, 0.16), Vector3(x, size.y - 0.3, FRONT_Z - 0.5), glow)
		_box(self, Vector3(0.04, 0.3, 0.04), Vector3(x, size.y - 0.05, FRONT_Z - 0.5), wood)
	_box(self, Vector3(0.16, 0.22, 0.16), Vector3(table_x, size.y - 0.5, table_z), glow)
	_box(self, Vector3(0.04, 0.5, 0.04), Vector3(table_x, size.y - 0.15, table_z), wood)

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
