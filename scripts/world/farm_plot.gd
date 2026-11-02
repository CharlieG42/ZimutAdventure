class_name FarmPlot
extends Interactable
## Parcelle de culture posée par le joueur : on la bêche (houe équipée) en y semant des graines,
## la récolte pousse en quelques minutes (même hors ligne : on garde l'heure du semis) puis
## donne des légumes et quelques graines.

signal changed(plot)

const TOOL_ID := "tool_hoe"
const GROW_SECONDS := 180.0
const WATER_TOOL_ID := "tool_watering_can"
## Un arrosage fait gagner cette part de la durée de pousse.
const WATER_BONUS := 0.35
## Cultures : graines -> {récolte, durée de pousse (s), couleur du fruit}.
const CROP_TYPES := {
	"item_seeds": {"yield": "item_vegetables", "seconds": 180.0, "fruit": Color(0.95, 0.55, 0.12)},
	"item_grain_seeds": {"yield": "item_wheat", "seconds": 120.0, "fruit": Color(0.9, 0.78, 0.25)},
}
## Chance de trouver des graines de céréales en récoltant des légumes.
const GRAIN_SEED_CHANCE := 0.3
const VEGETABLES_MIN := 2
const VEGETABLES_MAX := 4
const CROPS := 6
const SIZE := 2.4

enum Stage { EMPTY, GROWING, RIPE }

var planted_at: float = -1.0
var crop_seed: String = "item_seeds"
var watered: bool = false
var _time_offset: float = 0.0
var _crops: Node3D
var _soil: MeshInstance3D

static func create() -> Area3D:
	var area := Area3D.new()
	area.set_script(load("res://scripts/world/farm_plot.gd"))
	area.collision_layer = 4
	area.collision_mask = 0
	area.name = "FarmPlot"
	return area

func _ready() -> void:
	add_to_group("structures")
	add_to_group("farm_plots")
	prompt_text = "ACTION_PLANT"
	_build()
	_refresh_visuals()

func _process(delta: float) -> void:
	if get_stage() != Stage.GROWING:
		return
	var weather := InteractionManager.get_weather()
	if weather != null:
		# Saison : la pousse accélère ou ralentit en décalant l'horloge de la parcelle.
		_time_offset += (float(weather.call("crop_factor")) - 1.0) * delta
		# La pluie arrose les cultures toute seule, une fois.
		if not watered and bool(weather.call("is_raining")):
			_water(false)
	_refresh_visuals()

# --- Temps et état -----------------------------------------------------------------------

func _now() -> float:
	return Time.get_unix_time_from_system() + _time_offset

## API de test : fait avancer l'horloge de croissance.
func advance_time(seconds: float) -> void:
	_time_offset += seconds
	_refresh_visuals()

func get_stage() -> int:
	if planted_at < 0.0:
		return Stage.EMPTY
	return Stage.RIPE if _now() - planted_at >= grow_seconds() else Stage.GROWING

func grow_seconds() -> float:
	return float(CROP_TYPES[crop_seed]["seconds"])

func get_growth() -> float:
	if planted_at < 0.0:
		return 0.0
	return clampf((_now() - planted_at) / grow_seconds(), 0.0, 1.0)

func get_state() -> Dictionary:
	return {"planted_at": planted_at, "crop": crop_seed, "watered": watered}

func apply_state(state: Dictionary) -> void:
	planted_at = float(state.get("planted_at", -1.0))
	crop_seed = String(state.get("crop", "item_seeds"))
	if not CROP_TYPES.has(crop_seed):
		crop_seed = "item_seeds"
	watered = bool(state.get("watered", false))
	_refresh_visuals()

# --- Interaction ----------------------------------------------------------------------------

func can_interact() -> bool:
	if not enabled:
		return false
	if get_stage() == Stage.GROWING:
		return _can_water()
	return true

## Une plante qui pousse peut être arrosée une fois, arrosoir équipé.
func _can_water() -> bool:
	var inventory := InteractionManager.get_inventory()
	return not watered and inventory != null and inventory.is_equipped(WATER_TOOL_ID)

## Graines à semer : les céréales d'abord (plus rares), sinon les graines de légumes.
func _seed_in_bag(inventory: Node) -> String:
	for seed_id in ["item_grain_seeds", "item_seeds"]:
		if inventory.has_item(seed_id, 1):
			return seed_id
	return ""

func get_prompt() -> String:
	if get_stage() == Stage.RIPE:
		return "ACTION_HARVEST"
	if get_stage() == Stage.GROWING:
		return "ACTION_WATER"
	var inventory := InteractionManager.get_inventory()
	if inventory == null or not inventory.is_equipped(TOOL_ID):
		return "ACTION_NEED_HOE"
	if _seed_in_bag(inventory) == "":
		return "ACTION_NEED_SEEDS"
	return "ACTION_PLANT"

func _on_interact(_interactor: Node3D) -> void:
	var inventory := InteractionManager.get_inventory()
	if inventory == null:
		return
	if get_stage() == Stage.RIPE:
		_harvest(inventory)
		return
	if get_stage() == Stage.GROWING:
		_water()
		return
	var seed_id := _seed_in_bag(inventory)
	if not inventory.is_equipped(TOOL_ID):
		_toast(tr("TOAST_NEED_HOE"))
	elif seed_id == "":
		_toast(tr("TOAST_NEED_SEEDS"))
	else:
		inventory.call("remove_item", seed_id, 1)
		crop_seed = seed_id
		watered = false
		planted_at = _now()
		_toast(tr("TOAST_PLANTED"))
		_refresh_visuals()
		changed.emit(self)

func _water(by_player: bool = true) -> void:
	watered = true
	# L'eau avance la pousse : on recule la date de semis.
	planted_at -= grow_seconds() * WATER_BONUS
	if by_player:
		var progression := InteractionManager.get_progression()
		if progression != null:
			progression.call("add_stat", "stat_watered", 1)
			progression.call("add_xp_for", "water")
		_toast(tr("TOAST_WATERED"))
	_refresh_visuals()
	changed.emit(self)

func _harvest(inventory: Node) -> void:
	var is_grain := crop_seed == "item_grain_seeds"
	var amount := randi_range(VEGETABLES_MIN, VEGETABLES_MAX) + (1 if is_grain else 0)
	var progression := InteractionManager.get_progression()
	if progression != null:
		amount = int(progression.call("roll_loot", amount))
		progression.call("add_stat", "stat_harvests", 1)
		progression.call("add_xp_for", "farm")
	inventory.call("add_item", String(CROP_TYPES[crop_seed]["yield"]), amount)
	inventory.call("add_item", crop_seed, randi_range(1, 2))
	if is_grain:
		if progression != null:
			progression.call("add_stat", "stat_grain", 1)
	elif randf() < GRAIN_SEED_CHANCE:
		inventory.call("add_item", "item_grain_seeds", 1)
		_toast(tr("TOAST_FOUND_GRAIN"))
	planted_at = -1.0
	watered = false
	_refresh_visuals()
	changed.emit(self)

func _toast(message: String) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var hud := tree.get_first_node_in_group("hud") as Node
	if hud != null and hud.has_method("show_toast"):
		hud.show_toast(message, 1.8)

# --- Modèle ---------------------------------------------------------------------------------

func _build() -> void:
	_soil = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(SIZE, 0.14, SIZE)
	var soil := StandardMaterial3D.new()
	soil.albedo_color = Color(0.3, 0.19, 0.11)
	soil.roughness = 1.0
	box.material = soil
	_soil.mesh = box
	_soil.position = Vector3(0.0, 0.05, 0.0)
	add_child(_soil)
	# Sillons.
	var furrow := StandardMaterial3D.new()
	furrow.albedo_color = Color(0.2, 0.12, 0.07)
	for i in 3:
		var row := MeshInstance3D.new()
		var strip := BoxMesh.new()
		strip.size = Vector3(SIZE * 0.92, 0.04, 0.16)
		strip.material = furrow
		row.mesh = strip
		row.position = Vector3(0.0, 0.14, (float(i) - 1.0) * 0.75)
		add_child(row)
	# Bordure de bois.
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.45, 0.3, 0.17)
	for side in 4:
		var plank := MeshInstance3D.new()
		var plank_mesh := BoxMesh.new()
		plank_mesh.size = Vector3(SIZE + 0.2, 0.2, 0.1)
		plank_mesh.material = wood
		plank.mesh = plank_mesh
		var angle := float(side) * PI * 0.5
		plank.position = Vector3(sin(angle), 0.0, cos(angle)) * (SIZE * 0.5 + 0.05) + Vector3(0.0, 0.1, 0.0)
		plank.rotation.y = angle
		add_child(plank)
	_crops = Node3D.new()
	_crops.name = "Crops"
	add_child(_crops)
	var leaf := StandardMaterial3D.new()
	leaf.albedo_color = Color(0.3, 0.6, 0.2)
	var fruit := StandardMaterial3D.new()
	fruit.albedo_color = Color(0.95, 0.55, 0.12)
	for i in CROPS:
		var plant := Node3D.new()
		plant.position = Vector3((float(i % 3) - 1.0) * 0.75, 0.15, (floorf(float(i) / 3.0) - 0.5) * 1.1)
		var stem := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.01
		cone.bottom_radius = 0.2
		cone.height = 0.5
		cone.radial_segments = 6
		cone.rings = 1
		cone.material = leaf
		stem.mesh = cone
		stem.position = Vector3(0.0, 0.25, 0.0)
		plant.add_child(stem)
		var crop := MeshInstance3D.new()
		crop.name = "Fruit"
		var ball := SphereMesh.new()
		ball.radius = 0.1
		ball.height = 0.2
		ball.radial_segments = 6
		ball.rings = 3
		ball.material = fruit
		crop.mesh = ball
		crop.position = Vector3(0.0, 0.42, 0.0)
		plant.add_child(crop)
		_crops.add_child(plant)
	var area := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(SIZE + 0.6, 1.4, SIZE + 0.6)
	area.shape = shape
	area.position = Vector3(0.0, 0.6, 0.0)
	add_child(area)

func _refresh_visuals() -> void:
	if _crops == null:
		return
	var stage := get_stage()
	var growth := get_growth()
	_crops.visible = stage != Stage.EMPTY
	var fruit_color: Color = CROP_TYPES[crop_seed]["fruit"]
	for plant in _crops.get_children():
		plant.scale = Vector3.ONE * lerpf(0.25, 1.0, growth)
		var fruit := plant.get_node_or_null("Fruit") as Node3D
		if fruit != null:
			fruit.visible = stage == Stage.RIPE
			((fruit as MeshInstance3D).mesh as SphereMesh).material.set("albedo_color", fruit_color)
