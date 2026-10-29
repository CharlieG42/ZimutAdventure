extends Node
## Détecte l'objet interactif visé par le joueur.
##
## 1. Un rayon part des yeux du joueur dans l'axe de visée (la caméra). Il
##    fonctionne aussi en 3ème personne : l'origine est le pivot de la caméra,
##    pas la caméra elle-même, qui est reculée derrière le personnage.
## 2. Si rien n'est pile dans l'axe, une aide à la visée choisit l'objet
##    interactif le mieux orienté à proximité. Indispensable au tactile, où
##    viser une petite sphère avec le viseur est pénible.

signal focus_changed(target)

const INTERACT_RANGE: float = 3.0
## Rayon de recherche de l'aide à la visée.
const ASSIST_RADIUS: float = 2.6
## cos(angle) minimal entre la visée et l'objet pour l'aide à la visée (~63°).
const ASSIST_MIN_ALIGNMENT: float = 0.45
## Sous cette distance, l'objet est toujours accepté (il est « à nos pieds »).
const ASSIST_ALWAYS_DISTANCE: float = 1.2
## Couche physique des objets interactifs.
const INTERACT_MASK: int = 4

var _camera: Camera3D
var _eye: Node3D
var _current: Node3D

func set_camera(camera: Camera3D) -> void:
	_camera = camera

## Origine du rayon d'interaction (les « yeux » du joueur). Par défaut : la caméra.
func set_eye(eye: Node3D) -> void:
	_eye = eye

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
	# La cible a pu être détruite (objet ramassé) : on libère le focus.
	if _current != null and not is_instance_valid(_current):
		_current = null
		focus_changed.emit(null)
	var next: Node3D = _find_target()
	if next != _current:
		_current = next
		focus_changed.emit(_current)

func _find_target() -> Node3D:
	if _camera == null or not is_instance_valid(_camera) or not _camera.is_inside_tree():
		return null
	var space := _camera.get_world_3d().direct_space_state
	var from := _origin()
	var aim := -_camera.global_transform.basis.z

	# 1) Rayon dans l'axe de visée. Les objets interactifs sont des Area3D :
	#    sans collide_with_areas le rayon passerait au travers.
	var query := PhysicsRayQueryParameters3D.create(from, from + aim * INTERACT_RANGE)
	query.collision_mask = INTERACT_MASK
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var hit := space.intersect_ray(query)
	if not hit.is_empty():
		var found := _interactable_from(hit.get("collider"))
		if found != null:
			return found

	# 2) Aide à la visée.
	return _assist_target(space, from, aim)

func _origin() -> Vector3:
	if _eye != null and is_instance_valid(_eye) and _eye.is_inside_tree():
		return _eye.global_position
	return _camera.global_position

func _assist_target(space: PhysicsDirectSpaceState3D, from: Vector3, aim: Vector3) -> Node3D:
	var shape := SphereShape3D.new()
	shape.radius = ASSIST_RADIUS
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis.IDENTITY, from)
	params.collision_mask = INTERACT_MASK
	params.collide_with_areas = true
	params.collide_with_bodies = true
	var best: Node3D = null
	var best_score := -INF
	for result in space.intersect_shape(params, 16):
		var candidate := _interactable_from(result.get("collider"))
		if candidate == null or not candidate.can_interact():
			continue
		var offset := candidate.global_position - from
		var distance := maxf(offset.length(), 0.001)
		var alignment := aim.dot(offset / distance)
		if alignment < ASSIST_MIN_ALIGNMENT and distance > ASSIST_ALWAYS_DISTANCE:
			continue
		var score := alignment - distance * 0.15
		if score > best_score:
			best_score = score
			best = candidate
	return best

func _interactable_from(collider: Object) -> Interactable:
	var node := collider as Node
	while node != null:
		if node is Interactable:
			return node as Interactable
		node = node.get_parent()
	return null
