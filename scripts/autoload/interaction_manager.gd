extends Node

signal focus_changed(target)

const INTERACT_RANGE: float = 3.0

var _camera: Camera3D
var _current: Node3D

func set_camera(camera: Camera3D) -> void:
	_camera = camera

func get_current_target() -> Node3D:
	return _current

static func get_instance() -> Node:
	if Engine.has_singleton("InteractionManager"):
		return Engine.get_singleton("InteractionManager")
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		return tree.root.get_node_or_null("InteractionManager")
	return null

static func get_inventory() -> Node:
	if Engine.has_singleton("Inventory"):
		return Engine.get_singleton("Inventory")
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		return tree.root.get_node_or_null("Inventory")
	return null

static func get_sfx() -> Node:
	if Engine.has_singleton("Sfx"):
		return Engine.get_singleton("Sfx")
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		return tree.root.get_node_or_null("Sfx")
	return null

static func get_day_night() -> Node:
	if Engine.has_singleton("DayNightCycle"):
		return Engine.get_singleton("DayNightCycle")
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		return tree.root.get_node_or_null("DayNightCycle")
	return null

func _process(_delta: float) -> void:
	var next: Node3D = _find_target()
	if next != _current:
		_current = next
		focus_changed.emit(_current)

func _find_target() -> Node3D:
	if _camera == null:
		return null
	var space := _camera.get_world_3d().direct_space_state
	var from := _camera.global_position
	var to := from + _camera.global_transform.basis.z * -INTERACT_RANGE
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 4
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return null
	var collider: Node = hit.get("collider")
	if collider == null:
		return null
	var node: Node = collider
	while node != null:
		if node is Interactable:
			return node
		node = node.get_parent()
	return null
