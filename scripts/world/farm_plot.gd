class_name FarmPlot
extends Interactable
## Parcelle de culture posée par le joueur : on la bêche (houe équipée) en y semant des graines,
## la récolte pousse en quelques minutes (même hors ligne : on garde l'heure du semis) puis
## donne des légumes et quelques graines.

signal changed(plot)

const TOOL_ID := "tool_hoe"
const GROW_SECONDS := 180.0
const VEGETABLES_MIN := 2
const VEGETABLES_MAX := 4
const CROPS := 6
const SIZE := 2.4

enum Stage { EMPTY, GROWING, RIPE }

var planted_at: float = -1.0
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

func _process(_delta: float) -> void:
	if get_stage() == Stage.GROWING:
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
	return Stage.RIPE if _now() - planted_at >= GROW_SECONDS else Stage.GROWING

func get_growth() -> float:
	if planted_at < 0.0:
		return 0.0
	return clampf((_now() - planted_at) / GROW_SECONDS, 0.0, 1.0)

func get_state() -> Dictionary:
	return {"planted_at": planted_at}

func apply_state(state: Dictionary) -> void:
	planted_at = float(state.get("planted_at", -1.0))
	_refresh_visuals()

# --- Interaction ----------------------------------------------------------------------------

func can_interact() -> bool:
	return enabled and get_stage() != Stage.GROWING

func get_prompt() -> String:
	if get_stage() == Stage.RIPE:
		return "ACTION_HARVEST"
	var inventory := InteractionManager.get_inventory()
	if inventory == null or not inventory.is_equipped(TOOL_ID):
		return "ACTION_NEED_HOE"
	if not inventory.has_item("item_seeds", 1):
		return "ACTION_NEED_SEEDS"
	return "ACTION_PLANT"

func _on_interact(_interactor: Node3D) -> void:
	var inventory := InteractionManager.get_inventory()
	if inventory == null:
		return
	if get_stage() == Stage.RIPE:
		_harvest(inventory)
		return
	if not inventory.is_equipped(TOOL_ID):
		_toast(tr("TOAST_NEED_HOE"))
	elif not inventory.has_item("item_seeds", 1):
		_toast(tr("TOAST_NEED_SEEDS"))
	else:
		inventory.call("remove_item", "item_seeds", 1)
		planted_at = _now()
		_toast(tr("TOAST_PLANTED"))
		_refresh_visuals()
		changed.emit(self)

func _harvest(inventory: Node) -> void:
	var amount := randi_range(VEGETABLES_MIN, VEGETABLES_MAX)
	var progression := InteractionManager.get_progression()
	if progression != null:
		amount = int(progression.call("roll_loot", amount))
		progression.call("add_stat", "stat_harvests", 1)
		progression.call("add_xp_for", "farm")
	inventory.call("add_item", "item_vegetables", amount)
	inventory.call("add_item", "item_seeds", randi_range(1, 2))
	planted_at = -1.0
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
	for plant in _crops.get_children():
		plant.scale = Vector3.ONE * lerpf(0.25, 1.0, growth)
		var fruit := plant.get_node_or_null("Fruit") as Node3D
		if fruit != null:
			fruit.visible = stage == Stage.RIPE
