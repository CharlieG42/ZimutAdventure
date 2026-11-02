class_name Palisade
extends Node3D
## Tronçon de palissade (3 m) : pieux pointus et lisses, collision pleine. Se pose bout à bout
## pour fermer un camp ou un jardin ; arrête les prédateurs comme le joueur.

const LENGTH := 3.0
const HEIGHT := 1.9
const SOLID_LAYER := 1

static func create() -> Node3D:
	var node := Node3D.new()
	node.set_script(load("res://scripts/world/palisade.gd"))
	node.name = "Palisade"
	return node

func _ready() -> void:
	add_to_group("structures")
	add_to_group("palisades")
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.43, 0.29, 0.16)
	wood.roughness = 1.0
	var stakes := 7
	for i in stakes:
		var x := -LENGTH * 0.5 + 0.2 + (LENGTH - 0.4) * float(i) / float(stakes - 1)
		var height := HEIGHT - 0.12 * float(i % 2)
		var stake := MeshInstance3D.new()
		var trunk := CylinderMesh.new()
		trunk.top_radius = 0.02
		trunk.bottom_radius = 0.1
		trunk.height = height
		trunk.radial_segments = 6
		trunk.rings = 1
		stake.mesh = trunk
		stake.material_override = wood
		stake.position = Vector3(x, height * 0.5 - 0.1, 0.0)
		add_child(stake)
	for rail_y in [0.5, 1.2]:
		var rail := MeshInstance3D.new()
		var rail_mesh := BoxMesh.new()
		rail_mesh.size = Vector3(LENGTH, 0.12, 0.1)
		rail.mesh = rail_mesh
		rail.material_override = wood
		rail.position = Vector3(0.0, rail_y, 0.1)
		add_child(rail)
	var body := StaticBody3D.new()
	body.collision_layer = SOLID_LAYER
	body.collision_mask = 0
	body.position = Vector3(0.0, HEIGHT * 0.5, 0.0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(LENGTH, HEIGHT, 0.3)
	shape.shape = box
	body.add_child(shape)
	add_child(body)
