class_name RelicAltar
extends Interactable
## Autel des reliques (près du départ) : chaque relique offerte accorde une bénédiction
## permanente — endurance, chemins anciens (voyage gratuit), fortune (butin).

const SOLID_LAYER := 1
const NAMES := ["", "BLESSING_ENDURANCE", "BLESSING_PATHS", "BLESSING_FORTUNE"]

var _gems: Array = []

static func create() -> Area3D:
	var area := Area3D.new()
	area.set_script(load("res://scripts/interaction/relic_altar.gd"))
	area.collision_layer = 4
	area.collision_mask = 0
	area.name = "RelicAltar"
	return area

func _ready() -> void:
	add_to_group("altar")
	_build()
	_refresh()
	var exploration := InteractionManager.get_exploration()
	if exploration != null:
		exploration.connect("blessing_gained", func(_count): _refresh())

func _count() -> int:
	var exploration := InteractionManager.get_exploration()
	return int(exploration.get("blessings")) if exploration != null else 0

func get_prompt() -> String:
	var exploration := InteractionManager.get_exploration()
	if exploration != null and _count() >= int(exploration.get("MAX_BLESSINGS")):
		return "ACTION_ALTAR_FULL"
	return "ACTION_ALTAR_OFFER"

func _on_interact(_interactor: Node3D) -> void:
	var exploration := InteractionManager.get_exploration()
	if exploration == null:
		return
	if _count() >= int(exploration.get("MAX_BLESSINGS")):
		_toast(tr("TOAST_ALTAR_FULL"))
		return
	var gained := int(exploration.call("offer_relic"))
	if gained == 0:
		_toast(tr("TOAST_ALTAR_NEED_RELIC"))
		return
	var progression := InteractionManager.get_progression()
	if progression != null:
		progression.call("add_stat", "stat_blessings", 1)
		progression.call("add_xp_for", "treasure")
	var sfx := InteractionManager.get_sfx()
	if sfx != null and sfx.has_method("play_event"):
		sfx.call("play_event", "treasure")
	_toast(tr("TOAST_BLESSING") % tr(NAMES[gained]))

func _refresh() -> void:
	for i in _gems.size():
		(_gems[i] as MeshInstance3D).visible = i < _count()

func _toast(message: String) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var hud := tree.get_first_node_in_group("hud") as Node
	if hud != null and hud.has_method("show_toast"):
		hud.show_toast(message, 3.2)

func _build() -> void:
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.6, 0.5, 0.4)
	stone.roughness = 1.0
	_block(Vector3(1.8, 0.3, 1.8), Vector3(0.0, 0.15, 0.0), stone)
	_block(Vector3(1.2, 0.3, 1.2), Vector3(0.0, 0.45, 0.0), stone)
	_block(Vector3(0.7, 0.6, 0.7), Vector3(0.0, 0.9, 0.0), stone)
	_block(Vector3(1.0, 0.14, 1.0), Vector3(0.0, 1.27, 0.0), stone)
	# Trois gemmes : une par bénédiction reçue.
	var colors := [Color(0.3, 0.9, 0.5), Color(0.35, 0.65, 1.0), Color(1.0, 0.8, 0.25)]
	for i in 3:
		var gem := MeshInstance3D.new()
		var prism := PrismMesh.new()
		prism.size = Vector3(0.16, 0.26, 0.16)
		gem.mesh = prism
		var glow := StandardMaterial3D.new()
		glow.albedo_color = colors[i]
		glow.emission_enabled = true
		glow.emission = colors[i]
		glow.emission_energy_multiplier = 1.4
		gem.material_override = glow
		gem.position = Vector3(-0.3 + 0.3 * float(i), 1.47, 0.0)
		add_child(gem)
		_gems.append(gem)
	var body := StaticBody3D.new()
	body.collision_layer = SOLID_LAYER
	body.collision_mask = 0
	body.position = Vector3(0.0, 0.65, 0.0)
	var solid := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.4, 1.3, 1.4)
	solid.shape = shape
	body.add_child(solid)
	add_child(body)
	var trigger := CollisionShape3D.new()
	var trigger_shape := BoxShape3D.new()
	trigger_shape.size = Vector3(3.0, 2.2, 3.0)
	trigger.shape = trigger_shape
	trigger.position = Vector3(0.0, 1.0, 0.0)
	add_child(trigger)

func _block(size: Vector3, at: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	add_child(instance)
