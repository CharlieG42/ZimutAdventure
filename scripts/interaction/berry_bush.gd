class_name BerryBush
extends Interactable
## Buisson de baies sauvages : se cueille à la serpette, puis repousse après un moment.

const TOOL_ID := "tool_sickle"
const BERRIES_MIN := 2
const BERRIES_MAX := 4
const REGROW_SECONDS := 240.0

var ripe: bool = true
var _berries: Node3D
var _bush: MeshInstance3D

func _ready() -> void:
	add_to_group("berries")
	prompt_text = "ACTION_PICK_BERRIES"
	_build()

func _build() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(Time.get_ticks_usec())
	_bush = MeshInstance3D.new()
	# Buisson GLB (variantes Kenney) quand disponible, sphère procédurale sinon.
	var variants := GlbPropLibrary.get_variant_meshes("shrub")
	if not variants.is_empty():
		_bush.mesh = variants[rng.randi() % variants.size()]
		_bush.scale = Vector3.ONE * 1.8
		_bush.position = Vector3(0.0, 0.0, 0.0)
	else:
		var sphere := SphereMesh.new()
		sphere.radius = 0.62
		sphere.height = 0.95
		sphere.radial_segments = 10
		sphere.rings = 6
		var leaf := StandardMaterial3D.new()
		leaf.albedo_color = Color(0.2, 0.38, 0.14)
		leaf.roughness = 0.9
		sphere.material = leaf
		_bush.mesh = sphere
		_bush.position = Vector3(0.0, 0.42, 0.0)
		_bush.scale = Vector3(1.15, 0.8, 1.15)
	_bush.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(_bush)
	_berries = Node3D.new()
	_berries.name = "Berries"
	add_child(_berries)
	var berry_mesh := SphereMesh.new()
	berry_mesh.radius = 0.07
	berry_mesh.height = 0.14
	berry_mesh.radial_segments = 6
	berry_mesh.rings = 3
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.78, 0.08, 0.16)
	red.roughness = 0.35
	red.emission_enabled = true
	red.emission = Color(0.35, 0.0, 0.05)
	berry_mesh.material = red
	# Les 12 baies sont fondues en un seul maillage (couleur par sommet) : un appel de dessin
	# par buisson au lieu de douze.
	var parts: Array = []
	for i in 12:
		var berry := MeshInstance3D.new()
		berry.mesh = berry_mesh
		# Teinte légèrement variée par baie (rouge à orangé).
		var mat := StandardMaterial3D.new()
		var t := rng.randf_range(0.0, 0.25)
		mat.albedo_color = Color(0.78 + t * 0.5, 0.08 + t * 0.3, 0.16)
		berry.material_override = mat
		var angle := rng.randf_range(0.0, TAU)
		var tilt := rng.randf_range(0.2, 1.25)
		var rr := rng.randf_range(0.62, 0.8)
		berry.position = Vector3(cos(angle) * sin(tilt) * rr, 0.5 + cos(tilt) * 0.5, sin(angle) * sin(tilt) * rr)
		berry.scale = Vector3.ONE * rng.randf_range(0.85, 1.2)
		parts.append(berry)
	var cluster := MeshInstance3D.new()
	cluster.name = "Cluster"
	cluster.mesh = MeshBaker.merge(parts)
	cluster.material_override = _berry_material()
	_berries.add_child(cluster)
	for part in parts:
		(part as Node).free()
	var area := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 1.1
	area.shape = shape
	area.position = Vector3(0.0, 0.5, 0.0)
	add_child(area)

static var _shared_berry_material: StandardMaterial3D

static func _berry_material() -> StandardMaterial3D:
	if _shared_berry_material == null:
		_shared_berry_material = StandardMaterial3D.new()
		_shared_berry_material.vertex_color_use_as_albedo = true
		_shared_berry_material.roughness = 0.35
		_shared_berry_material.emission_enabled = true
		_shared_berry_material.emission = Color(0.35, 0.0, 0.05)
	return _shared_berry_material

func can_interact() -> bool:
	return enabled and ripe

func get_prompt() -> String:
	return "ACTION_PICK_BERRIES" if _has_sickle() else "ACTION_NEED_SICKLE"

func _has_sickle() -> bool:
	var inventory := InteractionManager.get_inventory()
	return inventory != null and inventory.is_equipped(TOOL_ID)

func _on_interact(_interactor: Node3D) -> void:
	if not _has_sickle():
		_toast(tr("TOAST_NEED_SICKLE"))
		return
	var progression := InteractionManager.get_progression()
	var amount := randi_range(BERRIES_MIN, BERRIES_MAX)
	if progression != null:
		amount = int(progression.call("roll_loot", amount))
		progression.call("add_xp_for", "harvest")
	var inventory := InteractionManager.get_inventory()
	if inventory != null:
		inventory.call("add_item", "item_berries", amount)
		# Quelques graines au passage : de quoi commencer un potager.
		inventory.call("add_item", "item_seeds", randi_range(1, 2))
	var sfx := InteractionManager.get_sfx()
	if sfx != null:
		sfx.call("play", load("res://assets/audio/pickup/collect.wav"), -8.0, 1.3)
	_set_ripe(false)
	if is_inside_tree():
		get_tree().create_timer(REGROW_SECONDS).timeout.connect(_regrow)

func _regrow() -> void:
	if is_instance_valid(self) and is_inside_tree():
		_set_ripe(true)

func _set_ripe(value: bool) -> void:
	ripe = value
	if _berries != null:
		_berries.visible = value

func _toast(message: String) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var hud := tree.get_first_node_in_group("hud") as Node
	if hud != null and hud.has_method("show_toast"):
		hud.show_toast(message, 1.6)
