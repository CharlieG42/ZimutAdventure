extends Node

func _ready() -> void:
	var root := get_parent()
	if root == null:
		return
	var sun := root.get_node_or_null("Sun") as DirectionalLight3D
	var env_node := root.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if sun != null and env_node != null and env_node.environment != null:
		DayNightCycle.bind_world(sun, env_node.environment)
