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
