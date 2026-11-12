class_name Arrow
extends RigidBody3D
## Flèche de chasse : physique balistique, se plante dans le sol, blesse les animaux.
## Une flèche plantée se ramasse toute seule quand le joueur passe à côté.

const LIFETIME := 8.0
const STICK_VELOCITY := 3.0
const STUCK_LIFETIME := 120.0
const PICKUP_DISTANCE := 1.8

var _stuck: bool = false
var _timer: float = 0.0
var _stuck_time: float = 0.0
var _pickup_check: float = 0.0
var _hit_shape: CollisionShape3D

func _ready() -> void:
	contact_monitor = true
	max_contacts_reported = 4
	continuous_cd = true
	collision_layer = 0
	collision_mask = 1
	# Pas de frottement de l'air : la trajectoire calculée au tir reste exacte.
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	set_process(false)
	body_entered.connect(_on_body_entered)
	_build_shape()
	_build_visual()

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _stuck:
		return
	_timer += state.get_step()
	if _timer >= LIFETIME:
		queue_free()
		return
	# Oriente la flèche dans la direction du mouvement (tangente de la trajectoire).
	var velocity := state.get_linear_velocity()
	if velocity.length_squared() > 0.5:
		var forward := -global_transform.basis.z
		var axis := forward.cross(velocity.normalized())
		if axis.length_squared() > 0.0001:
			var angle := forward.angle_to(velocity.normalized())
			state.set_angular_velocity(axis.normalized() * 20.0)
			look_at(global_position + velocity.normalized(), Vector3.UP)

func _on_body_entered(body: Node) -> void:
	if _stuck:
		return
	var velocity := linear_velocity
	# Animal touché (gibier ou prédateur) : blessure et retour visuel au tireur.
	if body.has_method("take_arrow_hit"):
		_stick()
		var origin := global_position - velocity.normalized() * 4.0 if velocity.length_squared() > 0.01 else global_position
		body.call("take_arrow_hit", origin)
		_notify_hit(body)
		queue_free()
		return
	# Sol ou décor : la flèche se plante et devient ramassable.
	if velocity.length() > STICK_VELOCITY:
		_stick()
		freeze = true
		add_to_group("arrow_stuck")
		set_process(true)

func _notify_hit(body: Node) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var hud := tree.get_first_node_in_group("hud") as Node
	if hud != null and hud.has_method("notify_hit"):
		hud.call("notify_hit", body)
	var sfx := InteractionManager.get_sfx()
	if sfx != null and sfx.has_method("play_event"):
		sfx.call("play_event", "hit")

## Flèche plantée : ramassage automatique à proximité, disparition au bout d'un moment.
func _process(delta: float) -> void:
	_stuck_time += delta
	if _stuck_time >= STUCK_LIFETIME:
		queue_free()
		return
	_pickup_check -= delta
	if _pickup_check > 0.0:
		return
	_pickup_check = 0.2
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player != null and player.global_position.distance_to(global_position) <= PICKUP_DISTANCE:
		pickup()

## Récupère la flèche plantée dans le sac.
func pickup() -> void:
	var inventory := InteractionManager.get_inventory()
	if inventory != null:
		inventory.add_item("arrow", 1)
	queue_free()

func _stick() -> void:
	_stuck = true
	freeze = true

func _build_shape() -> void:
	_hit_shape = CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.12
	_hit_shape.shape = sphere
	add_child(_hit_shape)

func _build_visual() -> void:
	var mesh := MeshInstance3D.new()
	var shaft := CylinderMesh.new()
	shaft.top_radius = 0.012
	shaft.bottom_radius = 0.012
	shaft.height = 0.6
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.55, 0.4, 0.22)
	wood.roughness = 0.85
	shaft.material = wood
	mesh.mesh = shaft
	mesh.rotation_degrees = Vector3(90, 0, 0)
	add_child(mesh)
	var head := MeshInstance3D.new()
	var tip := CylinderMesh.new()
	tip.top_radius = 0.002
	tip.bottom_radius = 0.02
	tip.height = 0.1
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.45, 0.45, 0.5)
	stone.roughness = 0.6
	tip.material = stone
	head.mesh = tip
	head.rotation_degrees = Vector3(-90, 0, 0)
	head.position = Vector3(0, 0, -0.32)
	add_child(head)
