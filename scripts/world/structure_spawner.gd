extends Node3D
## Gère les constructions posées par le joueur : placement sur le terrain, sauvegarde
## dans user://structures.cfg et rechargement au lancement.

const SAVE_NAME := "structures.cfg"
const MAX_SLOPE := 1.2
const MAX_STRUCTURES := 40
## Constructions que l'on peut déplacer (pas le potager, qui porte des cultures). L'enclos emmène ses bêtes.
const MOVABLE_KINDS := ["camp_bed", "wool_bed", "chest", "campfire", "shelter", "palisade", "pen"]
const MOVE_MIN_SPACING := 1.4
const MOVE_TINT_OK := Color(0.3, 1.0, 0.4, 0.38)
const MOVE_TINT_BAD := Color(1.0, 0.25, 0.2, 0.42)

## Une construction est soulevée (true) ou reposée / annulée (false).
signal move_changed(active: bool)
## Fin d'un déplacement : clé de message à afficher (TOAST_MOVED, ou l'erreur).
signal move_finished(ok: bool, message_key: String)

## id d'objet de l'inventaire -> type de construction.
const PLACEABLE := {
	"furniture_camp_bed": "camp_bed",
	"building_campfire": "campfire",
	"furniture_chest": "chest",
	"building_palisade": "palisade",
	"building_shelter": "shelter",
	"building_farm_plot": "farm_plot",
	"building_pen": "pen",
	"furniture_wool_bed": "wool_bed",
	"building_furnace": "furnace",
}

var _landscape: Node3D
# Les tests headless ne lisent ni n'écrivent la sauvegarde du joueur.
var _autosave: bool = DisplayServer.get_name() != "headless"
var _records: Array = []
# Déplacement en cours
var _moving: Node3D
var _move_record: Dictionary = {}
var _move_from: Dictionary = {}
var _move_yaw: float = 0.0
var _move_valid: bool = false
var _move_layers: Array = []
var _move_meshes: Array = []
## Bêtes d'un enclos soulevé : position relative à l'enclos, pour les suivre à la repose.
var _move_animals: Array = []

func _ready() -> void:
	add_to_group("structure_spawner")
	_landscape = get_node_or_null("../Landscape") as Node3D
	_load()

func is_placeable(item_id: String) -> bool:
	return PLACEABLE.has(item_id)

## Pose une construction devant `origin`. Retourne "" si réussi, sinon la clé de
## traduction de l'erreur. `yaw` : orientation (l'avant de la construction est +Z).
func place(item_id: String, origin: Vector3, yaw: float) -> String:
	if not PLACEABLE.has(item_id):
		return "TOAST_CANNOT_PLACE"
	if get_child_count() >= MAX_STRUCTURES:
		return "TOAST_TOO_MANY"
	if PLACEABLE[item_id] == "palisade":
		var snapped := snap_palisade(origin, yaw)
		origin = snapped["pos"]
		yaw = snapped["yaw"]
	var site_error := _site_error(PLACEABLE[item_id], origin)
	if site_error != "":
		return site_error
	var ground := _ground_height(origin.x, origin.z)
	var position := Vector3(origin.x, ground, origin.z)
	var node := _spawn(PLACEABLE[item_id], position, yaw)
	_records.append({"item": item_id, "pos": position, "yaw": yaw, "node": node})
	_save()
	var progression := InteractionManager.get_progression()
	if progression != null:
		progression.call("add_xp_for", "build")
		if PLACEABLE[item_id] == "pen":
			progression.call("add_stat", "stat_pens", 1)
	if node is Pen:
		(node as Pen).gather_nearby()
	return ""

## Distance max entre l'extrémité visée et celle d'une palissade existante pour s'y raccorder.
const PALISADE_SNAP_DISTANCE := 2.4

## Raccorde une palissade aux palissades déjà posées : son extrémité vient se coller à
## l'extrémité libre la plus proche, alignée (même direction) ou en angle droit, du côté
## le plus proche de l'endroit visé. Renvoie {"pos", "yaw", "snapped"}.
func snap_palisade(origin: Vector3, yaw: float, exclude: Node = null) -> Dictionary:
	var half := Palisade.LENGTH * 0.5
	var best := {"pos": origin, "yaw": yaw, "snapped": false}
	var best_score := INF
	for record in _records:
		var other := record.get("node") as Node3D
		if other == null or other == exclude or not is_instance_valid(other) or not (other is Palisade):
			continue
		var other_axis := other.global_transform.basis.x.normalized()
		var other_yaw := other.rotation.y
		for end_sign in [-1.0, 1.0]:
			var end_point: Vector3 = other.global_position + other_axis * half * end_sign
			var flat_gap := Vector2(end_point.x - origin.x, end_point.z - origin.z).length()
			if flat_gap > PALISADE_SNAP_DISTANCE + half:
				continue
			for quarter in 4:
				var candidate_yaw := other_yaw + float(quarter) * PI * 0.5
				var axis := Vector3(cos(candidate_yaw), 0.0, -sin(candidate_yaw))
				for side in [-1.0, 1.0]:
					var center: Vector3 = end_point + axis * half * side
					# Pas par-dessus la palissade existante (ni sur une autre).
					if _palisade_overlaps(center, exclude):
						continue
					var score := Vector2(center.x - origin.x, center.z - origin.z).length() \
							+ 0.6 * absf(angle_difference(candidate_yaw, yaw))
					if score < best_score and Vector2(center.x - origin.x, center.z - origin.z).length() < PALISADE_SNAP_DISTANCE + half:
						best_score = score
						best = {"pos": Vector3(center.x, origin.y, center.z), "yaw": wrapf(candidate_yaw, -PI, PI), "snapped": true}
	return best

func _palisade_overlaps(center: Vector3, exclude: Node) -> bool:
	for record in _records:
		var other := record.get("node") as Node3D
		if other == null or other == exclude or not is_instance_valid(other) or not (other is Palisade):
			continue
		if Vector2(other.global_position.x - center.x, other.global_position.z - center.z).length() < 1.0:
			return true
	return false

## Le terrain permet-il d'installer `kind` en `origin` ? "" si oui, sinon la clé de l'erreur.
func _site_error(kind: String, origin: Vector3) -> String:
	var ground := _ground_height(origin.x, origin.z)
	if ground < -50.0:
		return "TOAST_CANNOT_PLACE"
	if _landscape != null and _landscape.has_method("is_water") and bool(_landscape.call("is_water", origin.x, origin.z, 2.5)):
		return "TOAST_CANNOT_PLACE"
	for offset in [Vector2(1.5, 0), Vector2(-1.5, 0), Vector2(0, 1.5), Vector2(0, -1.5)]:
		var h := _ground_height(origin.x + offset.x, origin.z + offset.y)
		if absf(h - ground) > MAX_SLOPE:
			return "TOAST_TOO_STEEP"
	if kind == "pen":
		for offset in [Vector2(4.5, 4.5), Vector2(-4.5, 4.5), Vector2(4.5, -4.5), Vector2(-4.5, -4.5)]:
			if absf(_ground_height(origin.x + offset.x, origin.z + offset.y) - ground) > MAX_SLOPE * 1.6:
				return "TOAST_TOO_STEEP"
	return ""

# --- Déplacement ----------------------------------------------------------------------

## La construction déplaçable qui correspond à `target` (cible d'interaction), ou null.
func movable_for(target: Node) -> Node3D:
	if _moving != null or target == null:
		return null
	for record in _records:
		var node := record.get("node") as Node3D
		if node == null or not is_instance_valid(node):
			continue
		if node != target and not node.is_ancestor_of(target):
			continue
		if MOVABLE_KINDS.has(PLACEABLE.get(String(record["item"]), "")):
			return node
	return null

func is_moving() -> bool:
	return _moving != null

func is_move_valid() -> bool:
	return _moving != null and _move_valid

## Soulève la construction : elle devient un fantôme sans collision que l'on repose ailleurs.
func begin_move(node: Node3D) -> bool:
	if _moving != null or node == null:
		return false
	for record in _records:
		if record.get("node") == node:
			_move_record = record
	if _move_record.is_empty():
		return false
	_moving = node
	_move_from = {"pos": node.position, "yaw": node.rotation.y}
	_move_yaw = node.rotation.y
	_move_animals.clear()
	if node is Pen:
		for animal in (node as Pen).get_occupants():
			_move_animals.append([animal, node.to_local(animal.global_position)])
	_move_layers.clear()
	_move_meshes.clear()
	_collect_for_ghost(node)
	for entry in _move_layers:
		(entry[0] as CollisionObject3D).collision_layer = 0
	move_changed.emit(true)
	_tint_ghost(true)
	return true

func _collect_for_ghost(node: Node) -> void:
	if node is CollisionObject3D:
		_move_layers.append([node, (node as CollisionObject3D).collision_layer])
	if node is MeshInstance3D:
		_move_meshes.append(node)
	for child in node.get_children():
		_collect_for_ghost(child)

## Place le fantôme sous `origin` (le sol suit le relief) et met à jour sa validité.
func update_move(origin: Vector3, player_position: Vector3 = Vector3.INF) -> void:
	if _moving == null:
		return
	var kind: String = PLACEABLE.get(String(_move_record["item"]), "")
	var yaw := _move_yaw
	if kind == "palisade":
		var snapped := snap_palisade(origin, _move_yaw, _moving)
		origin = snapped["pos"]
		yaw = snapped["yaw"]
	var ground := _ground_height(origin.x, origin.z)
	_moving.position = Vector3(origin.x, ground, origin.z)
	_moving.rotation.y = yaw
	var valid := _site_error(kind, origin) == ""
	if valid and _moving is Pen:
		var half := (_moving as Pen).half()
		for corner in [Vector2(half, half), Vector2(-half, half), Vector2(half, -half), Vector2(-half, -half)]:
			if absf(_ground_height(origin.x + corner.x, origin.z + corner.y) - ground) > MAX_SLOPE * 1.6:
				valid = false
	if valid:
		for record in _records:
			var other := record.get("node") as Node3D
			if other == null or other == _moving or not is_instance_valid(other):
				continue
			# Les palissades se raccordent bout à bout : elles peuvent être proches.
			if other is Palisade and _moving is Palisade:
				continue
			if other.global_position.distance_to(_moving.global_position) < MOVE_MIN_SPACING:
				valid = false
				break
	if valid and player_position != Vector3.INF:
		var flat := Vector2(origin.x - player_position.x, origin.z - player_position.z)
		valid = flat.length() > 1.8
	if valid != _move_valid:
		_move_valid = valid
		_tint_ghost(false)

func rotate_move(step_degrees: float = 45.0) -> void:
	if _moving == null:
		return
	_move_yaw = wrapf(_move_yaw + deg_to_rad(step_degrees), -PI, PI)
	_moving.rotation.y = _move_yaw

## Repose la construction. Renvoie "" si réussi, sinon la clé de l'erreur (elle reste soulevée).
func confirm_move() -> String:
	if _moving == null:
		return ""
	if not _move_valid:
		move_finished.emit(false, "TOAST_CANNOT_PLACE")
		return "TOAST_CANNOT_PLACE"
	_move_record["pos"] = _moving.position
	_move_record["yaw"] = _moving.rotation.y
	_carry_animals()
	_end_move()
	_save()
	move_finished.emit(true, "TOAST_MOVED")
	return ""

## Remet la construction à son emplacement d'origine.
func cancel_move() -> void:
	if _moving == null:
		return
	_moving.position = _move_from["pos"]
	_moving.rotation.y = _move_from["yaw"]
	_end_move()
	move_finished.emit(true, "TOAST_MOVE_CANCELLED")

## Les bêtes de l'enclos déplacé le suivent : même place, dans le nouvel enclos.
func _carry_animals() -> void:
	for entry in _move_animals:
		var animal := entry[0] as Node3D
		if animal == null or not is_instance_valid(animal):
			continue
		var spot: Vector3 = _moving.to_global(entry[1])
		animal.global_position = spot + Vector3(0.0, 0.3, 0.0)
		animal.set("_center", spot)
		if animal is CharacterBody3D:
			(animal as CharacterBody3D).velocity = Vector3.ZERO
	_move_animals.clear()

func _end_move() -> void:
	for entry in _move_layers:
		if is_instance_valid(entry[0]):
			(entry[0] as CollisionObject3D).collision_layer = int(entry[1])
	for mesh in _move_meshes:
		if is_instance_valid(mesh):
			(mesh as MeshInstance3D).material_overlay = null
	_moving = null
	_move_record = {}
	_move_valid = false
	_move_layers.clear()
	_move_meshes.clear()
	move_changed.emit(false)

func _tint_ghost(reset_validity: bool) -> void:
	if reset_validity:
		_move_valid = false
	var material := StandardMaterial3D.new()
	material.albedo_color = MOVE_TINT_OK if _move_valid else MOVE_TINT_BAD
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for mesh in _move_meshes:
		if is_instance_valid(mesh):
			(mesh as MeshInstance3D).material_overlay = material

func _spawn(kind: String, position: Vector3, yaw: float) -> Node3D:
	var structure: Node3D
	match kind:
		"farm_plot":
			structure = FarmPlot.create()
		"pen":
			structure = Pen.create()
		"chest":
			structure = StorageChest.create()
		"palisade":
			structure = Palisade.create()
		"campfire":
			structure = (load("res://scenes/interaction/campfire.tscn") as PackedScene).instantiate()
		"furnace":
			structure = Furnace.create()
		_:
			structure = PlacedStructure.create(kind)
	structure.position = position
	structure.rotation.y = yaw
	add_child(structure)
	if structure.has_signal("changed"):
		structure.connect("changed", _on_plot_changed)
	return structure

func _on_plot_changed(_plot: Node) -> void:
	_save()

func _ground_height(x: float, z: float) -> float:
	if _landscape != null and _landscape.has_method("terrain_height_at"):
		return float(_landscape.call("terrain_height_at", x, z))
	return 0.0

func _load() -> void:
	if not _autosave:
		return
	var config := ConfigFile.new()
	if config.load(SaveSlots.file(SAVE_NAME)) != OK:
		return
	for entry in config.get_value("structures", "list", []):
		if not (entry is Dictionary) or not PLACEABLE.has(String(entry.get("item", ""))):
			continue
		var position: Vector3 = entry.get("pos", Vector3.ZERO)
		var yaw := float(entry.get("yaw", 0.0))
		# Le relief a pu changer depuis la sauvegarde : la construction suit le sol.
		if _landscape != null and _landscape.has_method("terrain_height_at"):
			position.y = _ground_height(position.x, position.z)
		var node := _spawn(PLACEABLE[entry["item"]], position, yaw)
		if node.has_method("apply_state"):
			node.call("apply_state", entry)
		_records.append({"item": entry["item"], "pos": position, "yaw": yaw, "node": node})

func _save() -> void:
	if not _autosave:
		return
	var saved: Array = []
	for record in _records:
		var entry := {"item": record["item"], "pos": record["pos"], "yaw": record["yaw"]}
		var node: Object = record.get("node")
		if node != null and is_instance_valid(node) and node.has_method("get_state"):
			entry.merge(node.call("get_state"))
		saved.append(entry)
	var config := ConfigFile.new()
	config.set_value("structures", "list", saved)
	config.save(SaveSlots.file(SAVE_NAME))

## Sauvegarde immédiate (une construction a changé d'état).
func save_now() -> void:
	_save()

## API de test : ne touche pas au disque.
func disable_saving_for_test() -> void:
	_autosave = false
