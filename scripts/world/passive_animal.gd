class_name PassiveAnimal
extends CharacterBody3D
## Animal inoffensif : erre autour de son point d'apparition, fuit si le joueur s'approche trop.

const FLEE_SPEED := 4.5
const WANDER_SPEED := 1.2
const FLEE_DISTANCE := 4.0
const TURN_SPEED := 6.0

@export var wander_radius: float = 20.0
@export var species: String = "deer"

var _center: Vector3
var _target: Vector3
var _velocity: Vector3 = Vector3.ZERO
var _next_pick: float = 0.0
var _player: Node3D

func _ready() -> void:
	_center = global_position
	_pick_wander_target()
	_player = get_tree().get_first_node_in_group("player") as Node3D

func _physics_process(delta: float) -> void:
	var target := _target
	var speed := WANDER_SPEED
	if _player != null and is_instance_valid(_player):
		var to_player := global_position - _player.global_position
		if to_player.length() < FLEE_DISTANCE:
			target = _center + (to_player.normalized() * wander_radius * 0.5)
			speed = FLEE_SPEED
	var to_target := target - global_position
	if Vector2(to_target.x, to_target.z).length() < 1.0 or _next_pick < Time.get_ticks_msec():
		_pick_wander_target()
	var direction := Vector3(to_target.x, 0, to_target.z).normalized()
	velocity = direction * speed
	if not is_on_floor():
		velocity.y -= 9.8 * delta
	move_and_slide()
	_face_direction(direction, delta)

func _pick_wander_target() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var angle := rng.randf_range(0.0, TAU)
	var distance := rng.randf_range(wander_radius * 0.2, wander_radius)
	_target = _center + Vector3(cos(angle) * distance, 0, sin(angle) * distance)
	_next_pick = Time.get_ticks_msec() + rng.randi_range(4000, 10000)

func _face_direction(direction: Vector3, delta: float) -> void:
	if direction.length_squared() < 0.001:
		return
	var yaw := atan2(direction.x, direction.z)
	rotation.y = lerp_angle(rotation.y, yaw, TURN_SPEED * delta)
