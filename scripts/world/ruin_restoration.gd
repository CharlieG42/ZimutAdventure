class_name RuinRestoration
extends Interactable
## Chantier de restauration d'une ruine découverte (contenu de haut niveau) : on relève une
## aile de la ruine en trois étapes — murs de pierre, charpente, toit et ferrures. Restaurée,
## elle devient un refuge : lit, coffre, âtre toujours allumé (abri contre le froid, les
## prédateurs n'approchent pas) et voyage rapide gratuit vers ce site.
## L'avancement et le contenu du coffre sont sauvegardés par l'Exploration.

const SOLID_LAYER := 1
## Étapes, dans l'ordre : coût, niveau de joueur requis, nom affiché.
const STAGES := [
	{"cost": {"item_stone": 20, "item_wood": 6}, "level": 8, "name": "RUIN_STAGE_WALLS"},
	{"cost": {"item_wood": 16, "item_pelt": 2}, "level": 9, "name": "RUIN_STAGE_FRAME"},
	{"cost": {"item_iron_ingot": 6, "item_wood": 10}, "level": 10, "name": "RUIN_STAGE_ROOF"},
]
## Dimensions intérieures du refuge (X largeur, Z profondeur) et hauteur des murs.
const ROOM := Vector2(4.4, 4.4)
const WALL_HEIGHT := 2.3
const WALL := 0.4
const DOOR_WIDTH := 1.3
const SHELTER_RADIUS_M := 3.2

@export var site_id: String = ""
## Lu par la Survie (abri) : "shelter" une fois le refuge terminé.
var kind: String = "ruin_site"
var level: int = 3
var stage: int = 0
var _stage_root: Node3D
var _chest: Node

static func create(for_site: String) -> Area3D:
	var area := Area3D.new()
	area.set_script(load("res://scripts/world/ruin_restoration.gd"))
	area.set("site_id", for_site)
	area.collision_layer = 4
	area.collision_mask = 0
	area.name = "RuinRestoration"
	return area

func _ready() -> void:
	add_to_group("ruin_restorations")
	var exploration := InteractionManager.get_exploration()
	if exploration != null:
		stage = int(exploration.call("ruin_stage", site_id))
	_build_board()
	_rebuild()

# --- Logique ---------------------------------------------------------------------------------

func is_complete() -> bool:
	return stage >= STAGES.size()

func next_stage() -> Dictionary:
	return {} if is_complete() else STAGES[stage]

## "" si l'étape suivante peut être faite, sinon la clé du refus.
func can_advance() -> String:
	if is_complete():
		return "TOAST_RUIN_DONE"
	var step: Dictionary = STAGES[stage]
	var progression := InteractionManager.get_progression()
	if progression != null and not bool(progression.call("meets_level", int(step["level"]))):
		return "TOAST_RUIN_LEVEL"
	var inventory := InteractionManager.get_inventory()
	if inventory == null:
		return "TOAST_RUIN_NEED"
	for item_id in step["cost"]:
		if int(inventory.call("count_of", item_id)) < int(step["cost"][item_id]):
			return "TOAST_RUIN_NEED"
	return ""

## Réalise l'étape suivante (paie le coût). Retourne "" si c'est fait, sinon la clé du refus.
func advance() -> String:
	var error := can_advance()
	if error != "":
		return error
	var step: Dictionary = STAGES[stage]
	var inventory := InteractionManager.get_inventory()
	for item_id in step["cost"]:
		inventory.call("remove_item", item_id, int(step["cost"][item_id]))
	stage += 1
	var exploration := InteractionManager.get_exploration()
	if exploration != null:
		exploration.call("set_ruin_stage", site_id, stage)
	var progression := InteractionManager.get_progression()
	if progression != null:
		progression.call("add_xp", 40 * stage)
		if is_complete():
			progression.call("add_stat", "stat_refuges", 1)
	_rebuild()
	return ""

## Coût restant lisible : "20 Pierre (12/20), 6 Bois (6/6)".
func cost_text() -> String:
	if is_complete():
		return ""
	var inventory := InteractionManager.get_inventory()
	var parts: Array = []
	var cost: Dictionary = STAGES[stage]["cost"]
	for item_id in cost:
		var have := int(inventory.call("count_of", item_id)) if inventory != null else 0
		parts.append("%s %d/%d" % [tr("ITEM_" + String(item_id).to_upper()), have, int(cost[item_id])])
	return ", ".join(parts)

func get_prompt() -> String:
	return "ACTION_RUIN_REFUGE" if is_complete() else "ACTION_RUIN_RESTORE"

func get_prompt_args() -> Array:
	return [] if is_complete() else [tr(String(STAGES[stage]["name"])), stage + 1, STAGES.size()]

func _on_interact(_interactor: Node3D) -> void:
	if is_complete():
		_toast(tr("TOAST_RUIN_REFUGE_INFO"), 3.5)
		return
	var step: Dictionary = STAGES[stage]
	var error := advance()
	match error:
		"":
			_toast(tr("TOAST_RUIN_REFUGE_DONE") if is_complete() else tr("TOAST_RUIN_STAGE_DONE") % tr(String(step["name"])), 3.5)
			var sfx := InteractionManager.get_sfx()
			if sfx != null and sfx.has_method("play_event"):
				sfx.call("play_event", "chime")
		"TOAST_RUIN_LEVEL":
			_toast(tr(error) % int(step["level"]), 3.0)
		_:
			_toast(tr("TOAST_RUIN_NEED") % cost_text(), 3.5)

# --- Abri (lu par la Survie) -------------------------------------------------------------------

func shelter_center() -> Vector3:
	return to_global(Vector3(0.0, 0.0, -ROOM.y * 0.5))

func shelter_radius() -> float:
	return SHELTER_RADIUS_M if is_complete() else 0.0

# --- Coffre du refuge ----------------------------------------------------------------------------

func get_chest() -> Node:
	return _chest

func _on_chest_changed(chest) -> void:
	var exploration := InteractionManager.get_exploration()
	if exploration != null:
		exploration.call("set_refuge_stock", site_id, (chest.get("stock") as Dictionary).duplicate())

# --- Modèles -----------------------------------------------------------------------------------------

func _toast(message: String, seconds: float) -> void:
	var hud := get_tree().get_first_node_in_group("hud") if is_inside_tree() else null
	if hud != null and hud.has_method("show_toast"):
		hud.show_toast(message, seconds)

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.95
	return material

func _box(parent: Node3D, size: Vector3, at: Vector3, material: Material, solid: bool = false) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	parent.add_child(instance)
	if solid:
		var body := StaticBody3D.new()
		body.collision_layer = SOLID_LAYER
		body.collision_mask = 0
		body.position = at
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		body.add_child(shape)
		parent.add_child(body)

## Panneau de chantier devant l'entrée : seule zone d'interaction (le lit et le coffre
## gardent la leur à l'intérieur).
func _build_board() -> void:
	var wood := _material(Color(0.45, 0.3, 0.17))
	var at := Vector3(ROOM.x * 0.5 + 0.9, -0.3, 1.2)
	_box(self, Vector3(0.1, 1.3, 0.1), at + Vector3(-0.35, 0.65, 0.0), wood)
	_box(self, Vector3(0.1, 1.3, 0.1), at + Vector3(0.35, 0.65, 0.0), wood)
	_box(self, Vector3(0.95, 0.55, 0.06), at + Vector3(0.0, 1.05, 0.03), _material(Color(0.62, 0.45, 0.26)))
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.6, 1.8, 1.4)
	shape.shape = box
	shape.position = at + Vector3(0.0, 0.9, 0.0)
	add_child(shape)

func _rebuild() -> void:
	if _stage_root != null:
		_stage_root.queue_free()
	_chest = null
	_stage_root = Node3D.new()
	_stage_root.name = "Stages"
	add_child(_stage_root)
	kind = "shelter" if is_complete() else "ruin_site"
	# Une fois restaurée, l'aile compte comme une construction (abri, repère du camp sur la carte).
	if is_complete() and not is_in_group("structures"):
		add_to_group("structures")
	var stone := _material(Color(0.74, 0.57, 0.4))
	var wood := _material(Color(0.42, 0.27, 0.15))
	var iron := _material(Color(0.22, 0.22, 0.24))
	var half_x := ROOM.x * 0.5
	var depth := ROOM.y
	# Fondations : toujours visibles (la ruine d'origine).
	# Soubassement : descend sous le sol pour combler la pente du terrain.
	_box(_stage_root, Vector3(ROOM.x + WALL * 2.0 + 0.3, 3.25, depth + WALL * 2.0 + 0.3), Vector3(0.0, 0.25 - 1.625, -depth * 0.5), stone, true)
	# Marche devant la porte.
	_box(_stage_root, Vector3(DOOR_WIDTH + 0.4, 1.2, 0.7), Vector3(0.0, -0.45, WALL + 0.45), stone)
	var wall_h := WALL_HEIGHT if stage >= 1 else 0.7
	# Murs (bas et écroulés avant restauration, entiers après) ; porte au milieu de la façade (+Z).
	_box(_stage_root, Vector3(ROOM.x + WALL * 2.0, wall_h, WALL), Vector3(0.0, wall_h * 0.5, -depth - WALL * 0.5), stone, true)
	_box(_stage_root, Vector3(WALL, wall_h, depth), Vector3(-half_x - WALL * 0.5, wall_h * 0.5, -depth * 0.5), stone, true)
	_box(_stage_root, Vector3(WALL, wall_h * (1.0 if stage >= 1 else 0.6), depth), Vector3(half_x + WALL * 0.5, wall_h * (0.5 if stage >= 1 else 0.3), -depth * 0.5), stone, true)
	var side := (ROOM.x + WALL * 2.0 - DOOR_WIDTH) * 0.5
	for sign_x in [-1.0, 1.0]:
		_box(_stage_root, Vector3(side, wall_h, WALL), Vector3(sign_x * (DOOR_WIDTH * 0.5 + side * 0.5), wall_h * 0.5, WALL * 0.5), stone, true)
	if stage == 0:
		# Pierres éboulées autour.
		for i in 5:
			var a := float(i) * 1.7
			_box(_stage_root, Vector3(0.5, 0.35, 0.45), Vector3(cos(a) * (half_x + 1.0), 0.18, -depth * 0.5 + sin(a) * (depth * 0.5 + 1.0)), stone)
	if stage >= 1:
		# Linteau de porte.
		_box(_stage_root, Vector3(DOOR_WIDTH + 0.2, 0.35, WALL), Vector3(0.0, WALL_HEIGHT - 0.17, WALL * 0.5), stone)
	if stage >= 2:
		# Charpente : poutre faîtière, chevrons, poteaux d'angle.
		var ridge_y := WALL_HEIGHT + 1.3
		_box(_stage_root, Vector3(0.18, 0.18, depth + 1.2), Vector3(0.0, ridge_y, -depth * 0.5), wood)
		for i in 5:
			var z := -depth * float(i) / 4.0 + (0.1 if i == 0 else 0.0)
			for sign_x in [-1.0, 1.0]:
				var rafter := MeshInstance3D.new()
				var mesh := BoxMesh.new()
				mesh.size = Vector3(sqrt(pow(half_x + 0.6, 2) + 1.69), 0.14, 0.14)
				rafter.mesh = mesh
				rafter.material_override = wood
				rafter.position = Vector3(sign_x * (half_x + 0.6) * 0.5, WALL_HEIGHT + 0.65, z)
				rafter.rotation.z = -sign_x * atan2(1.3, half_x + 0.6)
				_stage_root.add_child(rafter)
		for corner in [Vector2(-1, 0), Vector2(1, 0), Vector2(-1, -1), Vector2(1, -1)]:
			_box(_stage_root, Vector3(0.2, WALL_HEIGHT + 0.1, 0.2), Vector3(corner.x * (half_x + WALL * 0.5), (WALL_HEIGHT + 0.1) * 0.5, corner.y * (depth + WALL * 0.5) + (WALL * 0.5 if corner.y == 0 else 0.0)), wood)
	if stage >= 3:
		# Toit de planches (deux pans), porte de bois ferrée, lanterne.
		var roof_len := sqrt(pow(half_x + 0.7, 2) + 1.69) + 0.1
		var roof_mat := _material(Color(0.36, 0.23, 0.13))
		for sign_x in [-1.0, 1.0]:
			var pan := MeshInstance3D.new()
			var mesh := BoxMesh.new()
			mesh.size = Vector3(roof_len, 0.12, depth + 1.3)
			pan.mesh = mesh
			pan.material_override = roof_mat
			pan.position = Vector3(sign_x * (half_x + 0.7) * 0.5, WALL_HEIGHT + 0.72, -depth * 0.5)
			pan.rotation.z = -sign_x * atan2(1.3, half_x + 0.7)
			_stage_root.add_child(pan)
		# Pignons de pierre (triangle approché par deux blocs).
		for z in [WALL * 0.5, -depth - WALL * 0.5]:
			_box(_stage_root, Vector3(ROOM.x * 0.7, 0.6, WALL), Vector3(0.0, WALL_HEIGHT + 0.3, z), stone)
			_box(_stage_root, Vector3(ROOM.x * 0.35, 0.6, WALL), Vector3(0.0, WALL_HEIGHT + 0.9, z), stone)
		# Porte ouverte contre le mur, avec ferrures.
		_box(_stage_root, Vector3(0.08, 2.0, DOOR_WIDTH * 0.9), Vector3(-DOOR_WIDTH * 0.5 - 0.05, 1.0, WALL + DOOR_WIDTH * 0.45), wood)
		for y in [0.5, 1.5]:
			_box(_stage_root, Vector3(0.1, 0.07, DOOR_WIDTH * 0.85), Vector3(-DOOR_WIDTH * 0.5 - 0.1, y, WALL + DOOR_WIDTH * 0.45), iron)
		var lamp := OmniLight3D.new()
		lamp.light_color = Color(1.0, 0.72, 0.4)
		lamp.light_energy = 1.4
		lamp.omni_range = 7.0
		lamp.position = Vector3(0.0, WALL_HEIGHT - 0.3, -depth * 0.5)
		_stage_root.add_child(lamp)
		_box(_stage_root, Vector3(0.18, 0.26, 0.18), lamp.position, _material(Color(1.0, 0.8, 0.45)))
		_furnish()

## Mobilier du refuge : lit de laine, coffre (contenu sauvegardé), âtre toujours allumé.
func _furnish() -> void:
	var bed := PlacedStructure.create("wool_bed")
	bed.position = Vector3(-ROOM.x * 0.5 + 0.7, 0.25, -ROOM.y * 0.5 - 0.6)
	_stage_root.add_child(bed)
	var chest := StorageChest.create()
	chest.position = Vector3(ROOM.x * 0.5 - 0.7, 0.25, -ROOM.y + 0.7)
	_stage_root.add_child(chest)
	var exploration := InteractionManager.get_exploration()
	if exploration != null:
		chest.set("stock", (exploration.call("refuge_stock", site_id) as Dictionary).duplicate())
	chest.connect("changed", _on_chest_changed)
	_chest = chest
	var hearth := RefugeHearth.create()
	hearth.position = Vector3(ROOM.x * 0.5 - 0.7, 0.25, -0.9)
	_stage_root.add_child(hearth)
