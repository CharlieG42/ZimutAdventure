class_name PassiveAnimal
extends CharacterBody3D
## Animal inoffensif : erre autour de son point d'apparition, broute par moments,
## et fuit si le joueur s'approche trop. Le modèle (cerf ou lièvre) est construit en
## code et animé (trot, balancement de la tête, broutage).

const FLEE_SPEED := 5.0
const WANDER_SPEED := 1.3
const FLEE_DISTANCE := 5.0
const TURN_SPEED := 6.0
const GRAVITY := 18.0
const STUCK_SECONDS := 1.2

enum Mode { WALK, GRAZE }

## Paramètres par espèce : échelle, couleurs, oreilles, démarche.
const SPECIES := {
	"deer": {
		"scale": 1.0, "fur": Color(0.5, 0.31, 0.18), "belly": Color(0.86, 0.74, 0.56),
		"ear": 0.2, "neck": 0.38, "hop": 0.0, "speed": 1.0,
	},
	"rabbit": {
		"scale": 0.36, "fur": Color(0.58, 0.5, 0.4), "belly": Color(0.9, 0.86, 0.78),
		"ear": 0.42, "neck": 0.18, "hop": 0.22, "speed": 1.4,
	},
}

@export var wander_radius: float = 20.0
@export var species: String = "deer"

var _center: Vector3
var _target: Vector3
var _mode: Mode = Mode.WALK
var _mode_left: float = 0.0
var _stuck_time: float = 0.0
var _player: Node3D
var _gait: float = 0.0
var _fleeing: bool = false
var _legs: Array[Node3D] = []
var _neck: Node3D
var _head: Node3D
var _model: Node3D
var _config: Dictionary
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	_config = SPECIES.get(species, SPECIES["deer"])
	_center = global_position
	_player = get_tree().get_first_node_in_group("player") as Node3D
	_build_model()
	_resize_collision()
	_start_walk()

func _physics_process(delta: float) -> void:
	_update_behavior(delta)
	if not is_on_floor():
		velocity.y = maxf(velocity.y - GRAVITY * delta, -30.0)
	else:
		velocity.y = 0.0
	move_and_slide()
	if global_position.y < -80.0:
		global_position = _center + Vector3(0.0, 2.0, 0.0)
		velocity = Vector3.ZERO
	_animate(delta)

# --- Comportement ----------------------------------------------------------------

func _update_behavior(delta: float) -> void:
	var flat_velocity := Vector3.ZERO
	var scare := _scare_direction()
	_fleeing = scare != Vector3.ZERO
	var speed_scale: float = _config["speed"]
	if _fleeing:
		# Fuite : s'écarte du joueur, sans quitter trop loin de son territoire.
		var away := scare
		var home := _center - global_position
		home.y = 0.0
		if home.length() > wander_radius * 1.6:
			away = (away + home.normalized() * 1.2).normalized()
		flat_velocity = away * FLEE_SPEED * speed_scale
		_mode = Mode.WALK
		_mode_left = 1.0
	else:
		_mode_left -= delta
		if _mode == Mode.GRAZE:
			if _mode_left <= 0.0:
				_start_walk()
		else:
			var to_target := _target - global_position
			to_target.y = 0.0
			if to_target.length() < 1.0 or _mode_left <= 0.0 or _stuck_time > STUCK_SECONDS:
				_start_graze()
			else:
				flat_velocity = to_target.normalized() * WANDER_SPEED * speed_scale
	_track_stuck(flat_velocity, delta)
	velocity.x = move_toward(velocity.x, flat_velocity.x, 30.0 * delta)
	velocity.z = move_toward(velocity.z, flat_velocity.z, 30.0 * delta)
	if flat_velocity.length_squared() > 0.01:
		_face_direction(flat_velocity.normalized(), delta)

## Direction opposée au joueur s'il est trop proche (vecteur nul sinon).
func _scare_direction() -> Vector3:
	if _player == null or not is_instance_valid(_player):
		return Vector3.ZERO
	var away := global_position - _player.global_position
	away.y = 0.0
	var distance := away.length()
	if distance >= FLEE_DISTANCE * float(_config["scale"] + 0.4) or distance < 0.001:
		return Vector3.ZERO
	return away / distance

## Bloqué (rocher, falaise) : on abandonne la cible et on en choisit une autre.
func _track_stuck(wanted: Vector3, delta: float) -> void:
	var real := get_real_velocity()
	real.y = 0.0
	if wanted.length() > 0.5 and real.length() < wanted.length() * 0.2:
		_stuck_time += delta
	else:
		_stuck_time = 0.0

func _start_walk() -> void:
	_mode = Mode.WALK
	_mode_left = _rng.randf_range(5.0, 11.0)
	_stuck_time = 0.0
	var angle := _rng.randf_range(0.0, TAU)
	var distance := _rng.randf_range(wander_radius * 0.2, wander_radius)
	_target = _center + Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)

func _start_graze() -> void:
	_mode = Mode.GRAZE
	_mode_left = _rng.randf_range(2.0, 5.0)
	_stuck_time = 0.0

func _face_direction(direction: Vector3, delta: float) -> void:
	var yaw := atan2(direction.x, direction.z)
	rotation.y = lerp_angle(rotation.y, yaw, TURN_SPEED * delta)

# --- Modèle ----------------------------------------------------------------------

func _resize_collision() -> void:
	var s: float = _config["scale"]
	var shape_node := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node == null:
		return
	var capsule := CapsuleShape3D.new()
	capsule.radius = maxf(0.16, 0.35 * s)
	capsule.height = maxf(0.4, 1.2 * s)
	shape_node.shape = capsule
	shape_node.position.y = capsule.height * 0.5

func _build_model() -> void:
	var s: float = _config["scale"]
	var fur := _material(_config["fur"])
	var belly := _material(_config["belly"])
	var dark := _material(Color(0.14, 0.1, 0.08))
	_model = Node3D.new()
	_model.name = "Model"
	_model.scale = Vector3.ONE * s
	add_child(_model)

	# Corps : capsule couchée le long de l'axe Z (l'avant de l'animal est +Z).
	_add_mesh(_model, _capsule(0.29, 1.1), fur, Vector3(0.0, 0.86, 0.0), Vector3(90.0, 0.0, 0.0))
	_add_mesh(_model, _capsule(0.2, 0.8), belly, Vector3(0.0, 0.76, 0.02), Vector3(90.0, 0.0, 0.0))
	# Queue claire.
	_add_mesh(_model, _sphere(0.08), belly, Vector3(0.0, 0.98, -0.52), Vector3.ZERO)

	# Cou et tête (pivots : le broutage et le trot les font bouger).
	_neck = Node3D.new()
	_neck.name = "Neck"
	_neck.position = Vector3(0.0, 0.98, 0.4)
	_neck.rotation_degrees = Vector3(32.0, 0.0, 0.0)
	_model.add_child(_neck)
	var neck_len: float = _config["neck"]
	_add_mesh(_neck, _capsule(0.115, neck_len + 0.25), fur, Vector3(0.0, neck_len * 0.5, 0.0), Vector3.ZERO)
	_head = Node3D.new()
	_head.name = "Head"
	_head.position = Vector3(0.0, neck_len, 0.0)
	_head.rotation_degrees = Vector3(-22.0, 0.0, 0.0)
	_neck.add_child(_head)
	_add_mesh(_head, _sphere(0.12), fur, Vector3(0.0, 0.03, 0.06), Vector3.ZERO, Vector3(0.95, 0.95, 1.25))
	_add_mesh(_head, _sphere(0.06), belly, Vector3(0.0, -0.02, 0.2), Vector3.ZERO, Vector3(0.9, 0.8, 1.1))
	_add_mesh(_head, _sphere(0.03), dark, Vector3(0.0, 0.0, 0.27), Vector3.ZERO)
	for side in [-1.0, 1.0]:
		var ear_len: float = _config["ear"]
		var ear := _cone(0.045, ear_len)
		_add_mesh(_head, ear, fur, Vector3(0.07 * side, 0.15 + ear_len * 0.25, -0.02), Vector3(-10.0, 0.0, -18.0 * side))
		_add_mesh(_head, _sphere(0.016), dark, Vector3(0.085 * side, 0.06, 0.12), Vector3.ZERO)

	# Pattes : un pivot à la hanche par patte pour pouvoir les balancer.
	for z in [0.32, -0.32]:
		for x in [-0.13, 0.13]:
			var hip := Node3D.new()
			hip.position = Vector3(x, 0.8, z)
			_model.add_child(hip)
			_add_mesh(hip, _cylinder(0.03, 0.045, 0.78), fur, Vector3(0.0, -0.39, 0.0), Vector3.ZERO)
			_add_mesh(hip, _cylinder(0.04, 0.04, 0.06), dark, Vector3(0.0, -0.76, 0.0), Vector3.ZERO)
			_legs.append(hip)

func _animate(delta: float) -> void:
	if _model == null:
		return
	var horizontal := Vector2(velocity.x, velocity.z).length()
	var moving := horizontal > 0.15
	var rate := horizontal * (2.4 if _fleeing else 3.2) / maxf(0.5, float(_config["scale"]) + 0.3)
	_gait += delta * rate
	var amplitude := 0.0
	if moving:
		amplitude = (0.75 if _fleeing else 0.45)
	var hop: float = _config["hop"]
	# Diagonales synchronisées : avant-gauche + arrière-droit, puis l'inverse.
	var phases := [0.0, PI, PI, 0.0]
	for i in _legs.size():
		var swing := sin(_gait + phases[i]) * amplitude
		_legs[i].rotation.x = lerpf(_legs[i].rotation.x, swing, minf(1.0, 14.0 * delta))
	var bob := 0.0
	if moving:
		bob = absf(sin(_gait)) * (hop if hop > 0.0 else 0.04) * (1.4 if _fleeing else 1.0)
	_model.position.y = lerpf(_model.position.y, bob, minf(1.0, 12.0 * delta))
	var grazing := _mode == Mode.GRAZE and not moving
	var neck_target := 32.0 + (sin(_gait) * 4.0 if moving else 0.0)
	var head_target := -22.0
	if grazing:
		neck_target = 105.0 if _config["neck"] > 0.3 else 70.0
		head_target = -50.0
	elif _fleeing:
		neck_target = 18.0
	_neck.rotation_degrees.x = lerpf(_neck.rotation_degrees.x, neck_target, minf(1.0, 4.0 * delta))
	_head.rotation_degrees.x = lerpf(_head.rotation_degrees.x, head_target, minf(1.0, 4.0 * delta))

# --- Fabrique de maillages ------------------------------------------------------------

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	return material

func _capsule(radius: float, height: float) -> CapsuleMesh:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = maxf(height, radius * 2.0)
	mesh.radial_segments = 10
	mesh.rings = 4
	return mesh

func _sphere(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 10
	mesh.rings = 5
	return mesh

func _cylinder(top: float, bottom: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = 8
	mesh.rings = 1
	return mesh

## Pointe (oreille) : CylinderMesh à sommet quasi nul — pas de ConeMesh en Godot 4.7.
func _cone(radius: float, height: float) -> CylinderMesh:
	return _cylinder(0.004, radius, height)

func _add_mesh(parent: Node3D, mesh: Mesh, material: Material, position: Vector3,
		rotation_deg: Vector3, mesh_scale: Vector3 = Vector3.ONE) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = position
	instance.rotation_degrees = rotation_deg
	instance.scale = mesh_scale
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(instance)
