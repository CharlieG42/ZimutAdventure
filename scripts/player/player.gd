extends CharacterBody3D

@export var walk_speed: float = 4.5
@export var sprint_speed: float = 8.0
@export var jump_velocity: float = 5.5
@export var mouse_sensitivity: float = 0.0022
@export var touch_sensitivity: float = 0.006
@export var pitch_min: float = -1.45
@export var pitch_max: float = 1.55

@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var body_mesh: MeshInstance3D = $BodyMesh
@onready var capsule: CollisionShape3D = $CollisionShape3D

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _pitch: float = 0.0
var _joystick_vector: Vector2 = Vector2.ZERO
var _is_touch: bool = false

func _ready() -> void:
	_is_touch = DisplayServer.get_name() == "android"
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	InteractionManager.set_camera(camera)

func set_joystick_vector(vector: Vector2) -> void:
	_joystick_vector = vector if vector.length() <= 1.0 else vector.normalized()

func apply_touch_look(delta: Vector2) -> void:
	rotate_y(-delta.x)
	_pitch = clamp(_pitch - delta.y, pitch_min, pitch_max)
	camera_pivot.rotation.x = _pitch

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not _is_touch:
		rotate_y(-event.relative.x * mouse_sensitivity)
		_pitch = clamp(_pitch - event.relative.y * mouse_sensitivity, pitch_min, pitch_max)
		camera_pivot.rotation.x = _pitch

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta

	if Input.is_action_just_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED

	if Input.is_action_pressed("ui_accept") and is_on_floor():
		velocity.y = jump_velocity

	if Input.is_action_just_pressed("interact"):
		_try_interact()

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if _is_touch:
		input_dir += _joystick_vector
		input_dir = input_dir if input_dir.length() <= 1.0 else input_dir.normalized()
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	var speed := sprint_speed if Input.is_action_pressed("sprint") else walk_speed
	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed)
		velocity.z = move_toward(velocity.z, 0.0, speed)

	move_and_slide()

func _try_interact() -> void:
	var target := InteractionManager.get_current_target()
	if target != null and target is Interactable:
		(target as Interactable).interact(self)
