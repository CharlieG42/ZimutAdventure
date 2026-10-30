class_name ChoppableTree
extends Interactable
## Arbre qu'on abat à la hache : plusieurs coups, puis l'arbre tombe et laisse du bois.
## Sans hache équipée, l'invite indique l'outil nécessaire (et un coup n'a aucun effet).

const TOOL_ID := "tool_stone_axe"
const HITS_REQUIRED := 4
const WOOD_MIN := 3
const WOOD_MAX := 5

var hits: int = 0
var felled: bool = false
var _visual: Node3D
var _seed: int = 0

func _ready() -> void:
	add_to_group("choppable")
	prompt_text = "ACTION_CHOP"
	_build()

func _build() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed if _seed != 0 else int(Time.get_ticks_usec())
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	var tree_mesh := MeshInstance3D.new()
	tree_mesh.mesh = VegetationGenerator.generate(VegetationGenerator.PlantType.PINE, rng)
	tree_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_visual.add_child(tree_mesh)
	# Zone d'interaction généreuse (aide à la visée) et tronc plein pour bloquer le joueur.
	var area := CollisionShape3D.new()
	var area_shape := CylinderShape3D.new()
	area_shape.radius = 1.3
	area_shape.height = 4.0
	area.shape = area_shape
	area.position = Vector3(0.0, 2.0, 0.0)
	add_child(area)
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = 1
	var trunk := CollisionShape3D.new()
	var trunk_shape := CylinderShape3D.new()
	trunk_shape.radius = 0.4
	trunk_shape.height = 4.0
	trunk.shape = trunk_shape
	trunk.position = Vector3(0.0, 2.0, 0.0)
	body.add_child(trunk)
	add_child(body)

func can_interact() -> bool:
	return enabled and not felled

func get_prompt() -> String:
	return "ACTION_CHOP" if _has_axe() else "ACTION_NEED_AXE"

func _has_axe() -> bool:
	var inventory := InteractionManager.get_inventory()
	return inventory != null and inventory.is_equipped(TOOL_ID)

func _on_interact(interactor: Node3D) -> void:
	if not _has_axe():
		_toast(tr("TOAST_NEED_AXE"))
		return
	hits += 1
	_play_hit_sound()
	if hits >= HITS_REQUIRED:
		_fell(interactor)
	else:
		_shake()

func _shake() -> void:
	if _visual == null or not is_inside_tree():
		return
	var tween := create_tween()
	tween.tween_property(_visual, "rotation:z", 0.05, 0.05)
	tween.tween_property(_visual, "rotation:z", -0.05, 0.08)
	tween.tween_property(_visual, "rotation:z", 0.0, 0.06)

func _fell(interactor: Node3D) -> void:
	felled = true
	var body := get_node_or_null("Body") as StaticBody3D
	if body != null:
		body.collision_layer = 0
	var progression := InteractionManager.get_progression()
	var amount := randi_range(WOOD_MIN, WOOD_MAX)
	if progression != null:
		amount = int(progression.call("roll_loot", amount))
		progression.call("add_stat", "stat_trees", 1)
		progression.call("add_xp_for", "chop")
	_drop_wood(amount)
	_toast(tr("TOAST_TREE_FELLED") % amount)
	if _visual == null or not is_inside_tree():
		queue_free()
		return
	# L'arbre bascule à l'opposé du bûcheron, puis disparaît.
	var away := global_position - interactor.global_position if interactor != null else Vector3.FORWARD
	away.y = 0.0
	var axis := Vector3.UP.cross(away.normalized()) if away.length_squared() > 0.001 else Vector3.RIGHT
	var tween := create_tween()
	tween.tween_method(func(angle: float) -> void:
		_visual.transform.basis = Basis(axis.normalized(), angle), 0.0, deg_to_rad(88.0), 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_interval(0.6)
	tween.tween_property(_visual, "scale", Vector3.ZERO, 0.4)
	tween.tween_callback(queue_free)

func _drop_wood(amount: int) -> void:
	var scene := load("res://scenes/interaction/collectible_item.tscn") as PackedScene
	var parent_node := get_parent()
	if scene == null or parent_node == null:
		return
	for i in amount:
		var item := scene.instantiate() as Node3D
		item.set("item_id", "item_wood")
		item.set("kind", 1)
		item.set("amount", 1)
		var angle := randf_range(0.0, TAU)
		var distance := randf_range(0.8, 2.0)
		item.position = global_position + Vector3(cos(angle) * distance, 0.5, sin(angle) * distance)
		parent_node.add_child(item)

func _play_hit_sound() -> void:
	var sfx := InteractionManager.get_sfx()
	if sfx != null:
		sfx.call("play", load("res://assets/audio/pickup/collect.wav"), -8.0, 0.5 + 0.08 * float(hits))

func _toast(message: String) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var hud := tree.get_first_node_in_group("hud") as Node
	if hud != null and hud.has_method("show_toast"):
		hud.show_toast(message, 1.6)
