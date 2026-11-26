class_name IronVein
extends BreakableRock
## Filon de fer : un rocher veiné de rouille, surtout au pied des mesas. Il ne se casse qu'à
## la pioche et donne du minerai de fer (2 à 3), à fondre au four en lingots.

const PICKAXE := "tool_pickaxe"
const ORE_COLOR := Color(0.55, 0.3, 0.2)
const SPECK_COLOR := Color(0.9, 0.42, 0.16)

func _ready() -> void:
	super._ready()
	remove_from_group("breakable")
	add_to_group("iron_veins")
	prompt_text = "ACTION_MINE_IRON"
	drop_item_id = "item_iron_ore"
	drops_min = 2
	drops_max = 3
	_dress()

## Rocher plus sombre, taché de rouille, avec quelques éclats de minerai en relief.
func _dress() -> void:
	if mesh_instance == null:
		return
	var rock := StandardMaterial3D.new()
	rock.albedo_color = Color(0.22, 0.18, 0.17)
	rock.roughness = 0.9
	mesh_instance.material_override = rock
	var ore := StandardMaterial3D.new()
	ore.albedo_color = SPECK_COLOR
	ore.roughness = 0.5
	ore.metallic = 0.35
	ore.emission_enabled = true
	ore.emission = SPECK_COLOR
	ore.emission_energy_multiplier = 0.35
	var rng := RandomNumberGenerator.new()
	rng.seed = int(absf(global_position.x * 13.0 + global_position.z * 7.0))
	for i in 12:
		var speck := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3.ONE * rng.randf_range(0.15, 0.26)
		speck.mesh = box
		speck.material_override = ore
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.0, 1.0), rng.randf_range(-1, 1)).normalized()
		speck.position = Vector3(0, 0.55, 0) + dir * 0.52
		speck.rotation = Vector3(rng.randf(), rng.randf(), rng.randf()) * TAU
		add_child(speck)

func get_prompt() -> String:
	var inventory := InteractionManager.get_inventory()
	if inventory != null and not bool(inventory.call("is_equipped", PICKAXE)):
		return "ACTION_MINE_IRON_NEED_PICKAXE"
	return "ACTION_MINE_IRON"

func _on_interact(interactor: Node3D) -> void:
	var inventory := InteractionManager.get_inventory()
	if inventory != null and not bool(inventory.call("is_equipped", PICKAXE)):
		var hud := get_tree().get_first_node_in_group("hud")
		if hud != null and hud.has_method("show_toast"):
			hud.show_toast(tr("TOAST_NEED_PICKAXE"), 2.6)
		return
	var progression := InteractionManager.get_progression()
	if progression != null:
		progression.call("add_stat", "stat_iron_ore", 1)
	# Pioche en fer : un minerai de plus.
	if bool(inventory.call("is_iron_tool", PICKAXE)):
		drops_min += 1
		drops_max += 1
	break_rock(interactor)
