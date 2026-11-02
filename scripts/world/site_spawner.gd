extends Node3D
## Place les sites à découvrir (ruines et grottes) à des endroits tirés d'une graine fixe, chacun
## gardant un coffre au trésor, et les enregistre auprès de l'Exploration. Le panneau de départ
## est un site déjà connu : point de départ du voyage rapide.

const SITE_COUNT := 6
const MIN_RADIUS := 55.0
const MAX_RADIUS := 200.0
const MIN_SPACING := 55.0
const SOLID_LAYER := 1
const SEED := 4242

var _landscape: Node3D

func _ready() -> void:
	_landscape = get_node_or_null("../Landscape") as Node3D
	var exploration := InteractionManager.get_exploration()
	if exploration == null:
		return
	# Le panneau de départ : toujours connu.
	var sign_node := get_node_or_null("../Signpost") as Node3D
	var start := sign_node.global_position if sign_node != null else Vector3.ZERO
	exploration.call("register_site", "start", "SITE_START", start, "start")
	for site in plan_sites(SEED, SITE_COUNT, start):
		var pos := Vector3(site["x"], _ground_height(site["x"], site["z"]), site["z"])
		var site_id: String = site["id"]
		exploration.call("register_site", site_id, site["name"], pos, site["kind"])
		_build_site(site_id, site["kind"], pos, int(site["index"]))
	exploration.call("apply_saved_discoveries")
	exploration.call("discover", "start", true)

## Plan déterministe des sites (positions plates seulement, jamais dans l'eau, espacées).
func plan_sites(seed_value: int, count: int, start: Vector3) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var result: Array = []
	var taken: Array = [Vector2(start.x, start.z)]
	var attempts := 0
	while result.size() < count and attempts < 400:
		attempts += 1
		var angle := rng.randf() * TAU
		var radius := rng.randf_range(MIN_RADIUS, MAX_RADIUS)
		var x := cos(angle) * radius
		var z := sin(angle) * radius
		if _ground_height(x, z) < -2.0:
			continue
		var ok := true
		for other in taken:
			if (other as Vector2).distance_to(Vector2(x, z)) < MIN_SPACING:
				ok = false
				break
		if not ok:
			continue
		var index := result.size()
		taken.append(Vector2(x, z))
		result.append({
			"id": "site_%d" % index,
			"name": "SITE_NAME_%d" % index,
			"kind": "ruin" if index % 2 == 0 else "cave",
			"x": x,
			"z": z,
			"index": index,
		})
	return result

func loot_for(index: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + index * 31
	var loot := {"item_relic": 1}
	match rng.randi() % 3:
		0: loot["item_grain_seeds"] = 3
		1: loot["item_pelt"] = 2
		_: loot["item_seeds"] = 3
	return loot

func _ground_height(x: float, z: float) -> float:
	if _landscape != null and _landscape.has_method("terrain_height_at"):
		return float(_landscape.call("terrain_height_at", x, z))
	return 0.0

# --- Modèles ---------------------------------------------------------------------------------

func _build_site(site_id: String, kind: String, pos: Vector3, index: int) -> void:
	var root := Node3D.new()
	root.name = "Site_" + site_id
	root.position = pos
	root.rotation.y = float(index) * 1.3
	add_child(root)
	root.add_to_group("sites")
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.58, 0.52, 0.44) if kind == "ruin" else Color(0.38, 0.34, 0.32)
	stone.roughness = 1.0
	var used_glb_ruin := false
	if kind == "ruin":
		var ruin := GlbPropLibrary.instantiate_scene("ruin") if GlbPropLibrary.has_prop("ruin") else null
		if ruin != null:
			used_glb_ruin = true
			root.add_child(ruin)
			_add_scene_colliders(ruin)
		else:
			for i in 5:
				var angle := float(i) / 5.0 * TAU
				var height := 2.2 + float((i * 7 + index) % 4) * 0.7
				_column(root, Vector3(cos(angle) * 4.5, 0.0, sin(angle) * 4.5), height, stone)
			_block(root, Vector3(3.0, 0.8, 0.6), Vector3(0.0, 0.4, 5.6), stone)
			_block(root, Vector3(0.6, 0.6, 2.5), Vector3(-4.3, 0.3, 0.0), stone)
	else:
		_block(root, Vector3(1.6, 4.2, 2.4), Vector3(-2.2, 2.1, 0.0), stone)
		_block(root, Vector3(1.6, 4.2, 2.4), Vector3(2.2, 2.1, 0.0), stone)
		_block(root, Vector3(6.0, 1.4, 2.8), Vector3(0.0, 4.6, 0.0), stone)
		_block(root, Vector3(3.0, 3.6, 0.8), Vector3(0.0, 1.8, -1.6), stone)
		var dark := StandardMaterial3D.new()
		dark.albedo_color = Color(0.05, 0.05, 0.06)
		var inside := MeshInstance3D.new()
		var plane := BoxMesh.new()
		plane.size = Vector3(2.8, 3.4, 0.1)
		inside.mesh = plane
		inside.material_override = dark
		inside.position = Vector3(0.0, 1.7, -1.1)
		root.add_child(inside)
	var chest := TreasureChest.create(site_id, loot_for(index))
	if kind == "cave":
		chest.position = Vector3(0.0, 0.0, 0.6)
	elif used_glb_ruin:
		# Hors de l'empreinte de la ruine GLB (~13 m de large), atteignable à pied.
		chest.position = Vector3(7.0, 0.0, 7.0)
	root.add_child(chest)

## Collision d'une scène GLB : une boîte englobante par MeshInstance3D, en espace
## local du nœud (elle hérite ainsi de sa transformée).
func _add_scene_colliders(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			var aabb := mi.mesh.get_aabb()
			var body := StaticBody3D.new()
			body.collision_layer = SOLID_LAYER
			body.collision_mask = 0
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = aabb.size
			shape.shape = box
			shape.position = aabb.get_center()
			body.add_child(shape)
			mi.add_child(body)
	for child in node.get_children():
		_add_scene_colliders(child)

func _column(parent: Node3D, at: Vector3, height: float, material: Material) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.55
	mesh.bottom_radius = 0.65
	mesh.height = height
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at + Vector3(0.0, height * 0.5, 0.0)
	parent.add_child(instance)
	var body := StaticBody3D.new()
	body.collision_layer = SOLID_LAYER
	body.collision_mask = 0
	body.position = instance.position
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 0.65
	cylinder.height = height
	shape.shape = cylinder
	body.add_child(shape)
	parent.add_child(body)

func _block(parent: Node3D, size: Vector3, at: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	parent.add_child(instance)
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
