class_name Pen
extends Node3D
## Enclos de bois : on y rassemble le bétail apprivoisé. Les bêtes y restent (clôture solide,
## ouverte côté +Z pour que le joueur entre) et produisent plus vite.

const HALF := 4.5
const GATE_WIDTH := 2.6
const CAPACITY := 6
const JOIN_DISTANCE := 40.0
const SOLID_LAYER := 1
const WANDER := 3.0

static func create() -> Node3D:
	var pen := Node3D.new()
	pen.set_script(load("res://scripts/world/pen.gd"))
	pen.name = "Pen"
	return pen

func _ready() -> void:
	add_to_group("structures")
	add_to_group("pens")
	_build()

## Position d'un point dans l'enclos (repère monde) : au centre, un peu décalée.
func center() -> Vector3:
	return global_position

func contains(point: Vector3) -> bool:
	var local := to_local(point)
	return absf(local.x) < HALF and absf(local.z) < HALF

func get_occupants() -> Array:
	var occupants: Array = []
	for animal in get_tree().get_nodes_in_group("tamed"):
		if is_instance_valid(animal) and bool(animal.get("penned")) and contains(animal.global_position):
			occupants.append(animal)
	return occupants

func is_full() -> bool:
	return get_occupants().size() >= CAPACITY

## Fait entrer un animal d'élevage apprivoisé. Retourne false s'il est refusé.
func admit(animal: Node3D) -> bool:
	if not animal.has_method("enter_pen") or is_full():
		return false
	var angle := randf() * TAU
	var spot := global_position + Vector3(cos(angle), 0.0, sin(angle)) * randf_range(0.5, 2.2)
	animal.call("enter_pen", spot, WANDER)
	return true

## Rassemble le bétail apprivoisé des environs (à la pose de l'enclos).
func gather_nearby() -> int:
	var count := 0
	for animal in get_tree().get_nodes_in_group("tamed"):
		if not is_instance_valid(animal) or not animal.has_method("enter_pen"):
			continue
		if not bool(animal.get("is_livestock")) or bool(animal.get("penned")):
			continue
		if animal.global_position.distance_to(global_position) > JOIN_DISTANCE:
			continue
		if admit(animal):
			count += 1
	return count

# --- Modèle ---------------------------------------------------------------------------

func _build() -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.45, 0.3, 0.17)
	wood.roughness = 1.0
	var gate_half := GATE_WIDTH * 0.5
	# Quatre côtés ; le côté +Z est coupé par l'ouverture.
	_side(Vector3(-HALF, 0.0, -HALF), Vector3(HALF, 0.0, -HALF), wood)
	_side(Vector3(-HALF, 0.0, -HALF), Vector3(-HALF, 0.0, HALF), wood)
	_side(Vector3(HALF, 0.0, -HALF), Vector3(HALF, 0.0, HALF), wood)
	_side(Vector3(-HALF, 0.0, HALF), Vector3(-gate_half, 0.0, HALF), wood)
	_side(Vector3(gate_half, 0.0, HALF), Vector3(HALF, 0.0, HALF), wood)

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
