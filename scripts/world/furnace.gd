class_name Furnace
extends Interactable
## Four de pierre : fond le minerai de fer en lingots (2 minerais + 1 bois → 1 lingot).
## Un appui fond tout ce que le sac permet.

const ORE := "item_iron_ore"
const FUEL := "item_wood"
const INGOT := "item_iron_ingot"
const ORE_PER_INGOT := 2
const FUEL_PER_INGOT := 1
const SOLID_LAYER := 1

var _glow: OmniLight3D

static func create() -> Area3D:
	var area := Area3D.new()
	area.set_script(load("res://scripts/world/furnace.gd"))
	area.collision_layer = 4
	area.collision_mask = 0
	area.name = "Furnace"
	return area

func _ready() -> void:
	add_to_group("structures")
	add_to_group("furnaces")
	prompt_text = "ACTION_SMELT"
	_build()

## Combien de lingots le contenu du sac permet de fondre.
func smeltable() -> int:
	var inventory := InteractionManager.get_inventory()
	if inventory == null:
		return 0
	return mini(int(inventory.call("count_of", ORE)) / ORE_PER_INGOT, int(inventory.call("count_of", FUEL)) / FUEL_PER_INGOT)

func get_prompt() -> String:
	return "ACTION_SMELT" if smeltable() > 0 else "ACTION_SMELT_EMPTY"

func get_prompt_args() -> Array:
	return [smeltable()] if smeltable() > 0 else []

## Fond tout ce qui est possible. Renvoie le nombre de lingots obtenus.
func smelt_all() -> int:
	var count := smeltable()
	if count <= 0:
		return 0
	var inventory := InteractionManager.get_inventory()
	inventory.call("remove_item", ORE, count * ORE_PER_INGOT)
	inventory.call("remove_item", FUEL, count * FUEL_PER_INGOT)
	inventory.call("add_item", INGOT, count)
	var progression := InteractionManager.get_progression()
	if progression != null:
		progression.call("add_stat", "stat_iron_ingots", count)
		progression.call("add_xp", 6 * count)
	_flare()
	return count

func _on_interact(_interactor: Node3D) -> void:
	var made := smelt_all()
	var hud := get_tree().get_first_node_in_group("hud")
	if hud == null or not hud.has_method("show_toast"):
		return
	if made > 0:
		hud.show_toast(tr("TOAST_SMELTED") % made, 2.6)
	else:
		hud.show_toast(tr("TOAST_SMELT_NEED") % [ORE_PER_INGOT, FUEL_PER_INGOT], 3.0)

func _flare() -> void:
	if _glow == null:
		return
	var tween := create_tween()
	_glow.light_energy = 4.0
	tween.tween_property(_glow, "light_energy", 1.2, 1.2)

func _build() -> void:
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.5, 0.46, 0.42)
	stone.roughness = 1.0
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.16, 0.13, 0.12)
	var fire := StandardMaterial3D.new()
	fire.albedo_color = Color(1.0, 0.5, 0.15)
	fire.emission_enabled = true
	fire.emission = Color(1.0, 0.45, 0.1)
	fire.emission_energy_multiplier = 2.5
	# Base, dôme, gueule, cheminée.
	_mesh(_cylinder(0.95, 1.05, 0.6), Vector3(0, 0.3, 0), stone)
	var dome := SphereMesh.new()
	dome.radius = 0.9
	dome.height = 1.5
	_mesh(dome, Vector3(0, 0.75, 0), stone)
	_mesh(_box(Vector3(0.6, 0.5, 0.2)), Vector3(0, 0.75, 0.82), dark)
	_mesh(_box(Vector3(0.46, 0.3, 0.06)), Vector3(0, 0.68, 0.9), fire)
	_mesh(_cylinder(0.18, 0.22, 1.1), Vector3(0.0, 1.7, -0.25), stone)
	_glow = OmniLight3D.new()
	_glow.light_color = Color(1.0, 0.55, 0.2)
	_glow.light_energy = 1.2
	_glow.omni_range = 4.0
	_glow.position = Vector3(0, 0.8, 1.2)
	add_child(_glow)
	var body := StaticBody3D.new()
	body.collision_layer = SOLID_LAYER
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 1.0
	cylinder.height = 1.6
	shape.shape = cylinder
	shape.position = Vector3(0, 0.8, 0)
	body.add_child(shape)
	add_child(body)
	var trigger := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.6, 2.0, 2.6)
	trigger.shape = box
	trigger.position = Vector3(0, 1.0, 0.4)
	add_child(trigger)

func _mesh(mesh: Mesh, position: Vector3, material: Material) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = position
	add_child(instance)

func _box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh

func _cylinder(top: float, bottom: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	return mesh
