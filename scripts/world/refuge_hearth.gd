class_name RefugeHearth
extends Node3D
## Âtre de pierre d'un refuge restauré : toujours allumé. Compte comme un feu de camp
## (groupe « campfire ») : il réchauffe et tient les prédateurs à distance.

static func create() -> Node3D:
	var node := Node3D.new()
	node.set_script(load("res://scripts/world/refuge_hearth.gd"))
	node.name = "Hearth"
	return node

func _ready() -> void:
	add_to_group("campfire")
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.45, 0.42, 0.4)
	stone.roughness = 1.0
	var ember := StandardMaterial3D.new()
	ember.albedo_color = Color(1.0, 0.5, 0.15)
	ember.emission_enabled = true
	ember.emission = Color(1.0, 0.45, 0.1)
	ember.emission_energy_multiplier = 2.0
	_box(Vector3(0.9, 0.3, 0.7), Vector3(0.0, 0.15, 0.0), stone)
	_box(Vector3(0.55, 0.12, 0.4), Vector3(0.0, 0.34, 0.0), ember)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.3)
	light.light_energy = 1.6
	light.omni_range = 6.0
	light.position = Vector3(0.0, 0.8, 0.0)
	add_child(light)

func is_lit() -> bool:
	return true

func _box(size: Vector3, at: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	add_child(instance)
