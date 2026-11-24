class_name Npc
extends Interactable
## PNJ statique (GDD §4.6) : figure simple au camp de départ, interaction « Parler »
## qui ouvre le panneau de dialogue (HUD) avec éventuellement une quête offerte.
## En headless (sans HUD) : simple toast avec les répliques.

const SOLID_LAYER := 1

## id -> nom, répliques (clés de traduction) et quête offerte (QuestManager).
const NPCS := {
	"npc_trapper": {
		"name_key": "NPC_TRAPPER_NAME",
		"lines": ["NPC_TRAPPER_LINE1", "NPC_TRAPPER_LINE2", "NPC_TRAPPER_LINE3"],
		"quest": "quest_trapper",
	},
}

var npc_id: String = "npc_trapper"

static func create(id: String) -> Area3D:
	var area := Area3D.new()
	area.set_script(load("res://scripts/interaction/npc.gd"))
	area.collision_layer = 4
	area.collision_mask = 0
	area.name = "Npc"
	area.set("npc_id", id)
	return area

func _ready() -> void:
	add_to_group("npcs")
	prompt_text = "ACTION_TALK"
	_build()

func get_name_key() -> String:
	return String(NPCS.get(npc_id, {}).get("name_key", "NPC_NAME"))

func get_lines() -> Array:
	return NPCS.get(npc_id, {}).get("lines", [])

func get_quest() -> String:
	return String(NPCS.get(npc_id, {}).get("quest", ""))

## Quête encore verrouillée proposée par ce PNJ ("" si aucune).
func offered_quest() -> String:
	var q := get_quest()
	if q == "":
		return ""
	var quests := get_tree().root.get_node_or_null("QuestManager")
	if quests != null and String(quests.call("state_name", quests.call("state_of", q))) == "locked":
		return q
	return ""

## Le PNJ remet sa quête (verrouillée -> active) ; false si déjà acceptée.
func accept_quest() -> bool:
	var q := get_quest()
	if q == "" or offered_quest() == "":
		return false
	var quests := get_tree().root.get_node_or_null("QuestManager")
	if quests == null:
		return false
	quests.call("activate", q)
	return true

func _on_interact(_interactor: Node3D) -> void:
	var tree := get_tree()
	var hud := tree.get_first_node_in_group("hud") if tree != null else null
	if hud != null and hud.has_method("open_dialogue_panel"):
		hud.call("open_dialogue_panel", self)
		return
	# Sans HUD (tests headless) : simple toast avec les répliques.
	var text := ""
	for key in get_lines():
		text += tr(String(key)) + "\n"
	if hud != null and hud.has_method("show_toast"):
		hud.show_toast(text.strip_edges(), 6.0)

# --- Modèle -------------------------------------------------------------------------

func _build() -> void:
	var coat := StandardMaterial3D.new()
	coat.albedo_color = Color(0.32, 0.24, 0.16)
	coat.roughness = 0.9
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.85, 0.66, 0.5)
	skin.roughness = 0.8
	var hat := StandardMaterial3D.new()
	hat.albedo_color = Color(0.25, 0.17, 0.1)
	hat.roughness = 0.95
	# Corps, tête, chapeau.
	_capsule(Vector3(0.34, 0.85, 0.3), Vector3(0.0, 0.75, 0.0), coat)
	_sphere(0.19, Vector3(0.0, 1.42, 0.0), skin)
	_cylinder(0.34, 0.1, Vector3(0.0, 1.58, 0.0), hat)
	_cylinder(0.16, 0.22, Vector3(0.0, 1.5, 0.0), hat)
	# Nom au-dessus de la tête.
	var label := Label3D.new()
	label.text = tr(get_name_key())
	label.position = Vector3(0.0, 1.95, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 48
	label.outline_size = 8
	label.modulate = Color(1.0, 0.95, 0.85)
	add_child(label)
	# Collision pleine (couche 1) et zone de visée (couche 4, portée par l'Area3D).
	var body := StaticBody3D.new()
	body.collision_layer = SOLID_LAYER
	body.collision_mask = 0
	body.position = Vector3(0.0, 0.9, 0.0)
	var solid := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.8
	solid.shape = shape
	body.add_child(solid)
	add_child(body)
	var trigger := CollisionShape3D.new()
	var trigger_shape := BoxShape3D.new()
	trigger_shape.size = Vector3(1.6, 2.2, 1.6)
	trigger.shape = trigger_shape
	trigger.position = Vector3(0.0, 1.0, 0.0)
	add_child(trigger)

func _capsule(size: Vector3, pos: Vector3, material: Material) -> MeshInstance3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = size.x * 0.5
	mesh.height = size.y
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = pos
	add_child(instance)
	return instance

func _sphere(radius: float, pos: Vector3, material: Material) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = pos
	add_child(instance)
	return instance

func _cylinder(radius: float, height: float, pos: Vector3, material: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = pos
	add_child(instance)
	return instance
