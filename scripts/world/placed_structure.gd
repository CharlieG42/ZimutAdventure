class_name PlacedStructure
extends Interactable
## Construction posée dans le monde (lit de camp, abri). Le modèle, la collision et la
## zone d'interaction sont construits en code. Se crée avec PlacedStructure.create().
##  - camp_bed : se reposer (récupère l'endurance)
##  - shelter  : dormir, uniquement la nuit (la journée repart à 7 h)

const KINDS := ["camp_bed", "shelter"]
const SOLID_LAYER := 1
const WAKE_HOUR := 7.0

@export var kind: String = "camp_bed"

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
	match kind:
		"shelter":
			_build_shelter()
		_:
			_build_bed()

func _on_interact(interactor: Node3D) -> void:
	if kind == "shelter":
		_sleep(interactor)
	else:
		_rest(interactor)

func _rest(interactor: Node3D) -> void:
	if interactor != null and interactor.has_method("restore_stamina"):
		interactor.restore_stamina()
	_toast("TOAST_BED_REST")

func _sleep(interactor: Node3D) -> void:
	var clock := get_node_or_null("/root/DayNightCycle")
	var hour := float(clock.get("hour")) if clock != null else 12.0
	var is_night := hour >= 19.0 or hour < 5.0
	if clock == null or not is_night:
		_toast("TOAST_NOT_TIRED")
		return
	clock.call("set_hour", WAKE_HOUR)
	if interactor != null and interactor.has_method("restore_stamina"):
		interactor.restore_stamina()
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
	var cloth := _material(Color(0.62, 0.3, 0.2))
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
	_add_trigger(Vector3(2.6, 2.0, 2.6), Vector3(0.0, 1.0, 0.1))

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
