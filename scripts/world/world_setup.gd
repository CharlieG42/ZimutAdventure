extends Node

func _ready() -> void:
	var root := get_parent()
	if root == null:
		return
	var sun := root.get_node_or_null("Sun") as DirectionalLight3D
	var env_node := root.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if sun != null and env_node != null and env_node.environment != null:
		DayNightCycle.bind_world(sun, env_node.environment)
	_place_player_on_ground(root)
	_place_interaction_props(root)
	_add_ambient_dust(root)

## Pose le feu de camp et la pancarte sur le sol, à quelques mètres du départ.
func _place_interaction_props(root: Node) -> void:
	var landscape := root.get_node_or_null("Landscape")
	if landscape == null or not landscape.has_method("terrain_height_at"):
		return
	var player := root.get_node_or_null("Player") as Node3D
	if player == null:
		return
	var base: Vector3 = player.global_position
	var props := {
		"Campfire": Vector3(6.0, 0.0, 2.0),
		"Signpost": Vector3(-5.0, 0.0, 4.0),
		"WaterSource": Vector3(12.0, 0.0, -8.0),
	}
	for node_name in props:
		var node := root.get_node_or_null(node_name) as Node3D
		if node == null:
			continue
		var pos: Vector3 = base + (props[node_name] as Vector3)
		var ground: float = landscape.terrain_height_at(pos.x, pos.z)
		node.global_position = Vector3(pos.x, ground, pos.z)
		if node_name == "Signpost":
			node.look_at(node.global_position + Vector3(0, 0, 1), Vector3.UP)

## Pose le joueur au sol à son point de départ (la scène le place en hauteur).
func _place_player_on_ground(root: Node) -> void:
	var player := root.get_node_or_null("Player") as Node3D
	var landscape := root.get_node_or_null("Landscape")
	if player == null or landscape == null or not landscape.has_method("terrain_height_at"):
		return
	var p := player.global_position
	var h: float = landscape.terrain_height_at(p.x, p.z)
	if h > -50.0:
		player.global_position = Vector3(p.x, h + 1.2, p.z)

## Poussière et pollen portés par le vent autour du joueur : donne de la profondeur à
## l'air et fait « vivre » la lumière rasante. Peu coûteux (quelques dizaines de quads).
func _add_ambient_dust(root: Node) -> void:
	var player := root.get_node_or_null("Player") as Node3D
	if player == null or DisplayServer.get_name() == "headless":
		return
	var particles := GPUParticles3D.new()
	particles.name = "AmbientDust"
	particles.amount = 90
	particles.lifetime = 9.0
	particles.preprocess = 9.0
	particles.local_coords = false
	particles.visibility_aabb = AABB(Vector3(-30, -10, -30), Vector3(60, 25, 60))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(24.0, 5.0, 24.0)
	process.direction = Vector3(1.0, 0.1, 0.35)
	process.spread = 25.0
	process.initial_velocity_min = 0.6
	process.initial_velocity_max = 1.6
	process.gravity = Vector3(0.0, 0.02, 0.0)
	process.scale_min = 0.5
	process.scale_max = 1.3
	particles.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(0.09, 0.09)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.albedo_color = Color(1.0, 0.88, 0.62, 0.35)
	quad.material = material
	particles.draw_pass_1 = quad
	player.add_child(particles)
