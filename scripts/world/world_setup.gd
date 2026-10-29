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
