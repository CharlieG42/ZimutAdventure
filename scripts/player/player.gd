extends CharacterBody3D
## Contrôleur du joueur : déplacement analogique, saut, endurance, caméra
## 1ère / 3ème personne.
##
## Convention d'orientation : le Nord du monde est l'axe -Z. Le cap (azimut)
## augmente dans le sens horaire (voir get_heading_degrees()).

signal view_changed(is_first_person: bool)
signal stamina_changed(value: float, exhausted: bool)
signal jumped

enum ViewMode { FIRST_PERSON, THIRD_PERSON }

@export_group("Déplacement")
@export var walk_speed: float = 4.5
@export var sprint_speed: float = 8.0
## Vitesse minimale dès que le stick est incliné (évite l'effet « ramper »).
@export var min_move_speed: float = 1.1
@export var acceleration: float = 24.0
@export var deceleration: float = 32.0
## Part de l'accélération conservée en l'air (0 = aucun contrôle).
@export_range(0.0, 1.0) var air_control: float = 0.35
@export var jump_velocity: float = 5.5
@export var fall_gravity_scale: float = 1.35
## Délai de grâce pour sauter juste après avoir quitté un rebord.
@export var coyote_time: float = 0.12
## Un appui sur « saut » un peu avant l'atterrissage est mémorisé.
@export var jump_buffer_time: float = 0.12
## Altitude en dessous de laquelle le joueur est ramené au dernier point sûr.
@export var respawn_below_y: float = -80.0

@export_group("Stick de déplacement")
@export_range(0.0, 0.5) var stick_deadzone: float = 0.12
## > 1 : plus de précision près du centre, vitesse maximale en bout de course.
@export var stick_curve: float = 1.5
## Pousser le stick à fond fait courir (avec hystérésis).
@export var sprint_at_full_tilt: bool = true
@export_range(0.5, 1.0) var sprint_stick_threshold: float = 0.94

@export_group("Endurance")
## Fraction d'endurance perdue par seconde en courant (0.12 ≈ 8 s).
@export var stamina_drain: float = 0.12
@export var stamina_regen: float = 0.2
@export var stamina_regen_delay: float = 0.9
## Une fois épuisé, il faut regagner cette fraction avant de courir à nouveau.
@export_range(0.0, 1.0) var exhausted_recovery: float = 0.3

@export_group("Caméra")
@export var mouse_sensitivity: float = 0.0022
@export var touch_sensitivity: float = 0.006
@export var camera_joystick_speed: float = 3.2
@export_range(0.0, 0.5) var camera_stick_deadzone: float = 0.1
@export var camera_stick_curve: float = 2.0
@export var pitch_min: float = -1.45
@export var pitch_max: float = 1.55
@export var eye_height: float = 1.6
@export var head_bob: bool = true
@export var sprint_fov_boost: float = 6.0

@export_group("Caméra 3ème personne")
@export var third_person_distance: float = 4.5
## Hauteur du pivot de la caméra (épaules).
@export var third_person_height: float = 1.7
## Décalage latéral (par-dessus l'épaule) pour dégager le viseur.
@export var third_person_shoulder: float = 0.45
@export var third_person_pitch_min: float = -1.2
@export var third_person_pitch_max: float = 0.6
@export var third_person_min_distance: float = 1.2

@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var body_mesh: MeshInstance3D = $BodyMesh
@onready var capsule: CollisionShape3D = $CollisionShape3D
@onready var visuals: Node3D = $Visuals

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var stamina: float = 1.0

var _pitch: float = -0.25
var _joystick_vector: Vector2 = Vector2.ZERO
var _is_touch: bool = false
var _view_mode: int = ViewMode.FIRST_PERSON

var _coyote_left: float = 0.0
var _jump_buffer_left: float = 0.0
var _sprint_lock: bool = false
var _edge_sprint: bool = false
var _sprinting: bool = false
var _exhausted: bool = false
var _regen_delay_left: float = 0.0
var _last_emitted_stamina: float = 1.0
var _last_emitted_exhausted: bool = false

var _was_on_floor: bool = true
var _prev_vy: float = 0.0
var _land_dip: float = 0.0
var _bob_phase: float = 0.0
var _base_fov: float = 70.0
var _tp_distance: float = 4.5
var _safe_position: Vector3 = Vector3.ZERO
var _safe_timer: float = 0.0

# Animation procédurale du personnage (vue 3ème personne).
var _visuals_base_yaw: float = 0.0
var _facing_yaw: float = 0.0
var _walk_phase: float = 0.0
var _gait: float = 0.0
var _air_blend: float = 0.0
var _rest: Dictionary = {}

const LEG_HIP_Y := 0.86
const ARM_SHOULDER_Y := 0.375

func _ready() -> void:
	_is_touch = PlatformInfo.is_touch()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	floor_snap_length = 0.6
	floor_max_angle = deg_to_rad(50.0)
	floor_stop_on_slope = true
	floor_constant_speed = true
	_base_fov = camera.fov
	_tp_distance = third_person_distance
	_safe_position = global_position
	_visuals_base_yaw = visuals.rotation.y
	_cache_rest_pose()
	InteractionManager.set_camera(camera)
	InteractionManager.set_eye(camera_pivot)
	_apply_view_mode()

# --- API publique (HUD, tests) ----------------------------------------------

func set_joystick_vector(vector: Vector2) -> void:
	_joystick_vector = vector if vector.length() <= 1.0 else vector.normalized()

func apply_touch_look(delta: Vector2) -> void:
	_rotate_look(delta * touch_sensitivity * 160.0)

func apply_camera_joystick(vector: Vector2, delta: float) -> void:
	var shaped := shape_stick(vector, camera_stick_deadzone, camera_stick_curve)
	# Le mouvement vertical est un peu plus lent : moins de vertige, visée plus fine.
	shaped.y *= 0.7
	_rotate_look(shaped * camera_joystick_speed * delta)

func is_first_person() -> bool:
	return _view_mode == ViewMode.FIRST_PERSON

func toggle_view() -> void:
	_view_mode = ViewMode.THIRD_PERSON if _view_mode == ViewMode.FIRST_PERSON else ViewMode.FIRST_PERSON
	_apply_view_mode()
	view_changed.emit(_view_mode == ViewMode.FIRST_PERSON)

## Mémorise une demande de saut (bouton tactile ou touche).
func request_jump() -> void:
	_jump_buffer_left = jump_buffer_time

## Verrouille la course (bouton « courir » tactile en mode bascule).
func set_sprint_lock(enabled: bool) -> void:
	_sprint_lock = enabled

func is_sprinting() -> bool:
	return _sprinting

func get_stamina() -> float:
	return stamina

func is_exhausted() -> bool:
	return _exhausted

## Recouvrement immédiat (repos au feu de camp).
func restore_stamina() -> void:
	stamina = 1.0
	_exhausted = false
	_regen_delay_left = 0.0
	stamina_changed.emit(stamina, _exhausted)

## Cap en degrés, 0 = Nord (-Z), sens horaire (90 = Est).
func get_heading_degrees() -> float:
	return fposmod(-rad_to_deg(rotation.y), 360.0)

func try_interact() -> void:
	var target := InteractionManager.get_current_target()
	if target != null and target is Interactable:
		(target as Interactable).interact(self)

func _try_interact() -> void:
	try_interact()

## Zone morte + courbe de réponse d'un stick analogique.
## Renvoie un vecteur de longueur 0..1 (0 sous la zone morte).
static func shape_stick(raw: Vector2, deadzone: float, curve: float) -> Vector2:
	var length := raw.length()
	if length <= deadzone:
		return Vector2.ZERO
	var t := clampf((length - deadzone) / (1.0 - deadzone), 0.0, 1.0)
	return raw / length * pow(t, curve)

# --- Caméra ------------------------------------------------------------------

func _rotate_look(delta: Vector2) -> void:
	rotate_y(-delta.x)
	_pitch = clampf(_pitch - delta.y, _pitch_lo(), _pitch_hi())
	_update_camera()

func _pitch_lo() -> float:
	return pitch_min if _view_mode == ViewMode.FIRST_PERSON else third_person_pitch_min

func _pitch_hi() -> float:
	return pitch_max if _view_mode == ViewMode.FIRST_PERSON else third_person_pitch_max

func _apply_view_mode() -> void:
	var first := _view_mode == ViewMode.FIRST_PERSON
	visuals.visible = not first
	if first:
		camera_pivot.position = Vector3(0.0, eye_height, 0.0)
		camera.position = Vector3.ZERO
	else:
		camera_pivot.position = Vector3(0.0, third_person_height, 0.0)
		_tp_distance = third_person_distance
		camera.position = Vector3(third_person_shoulder, 0.0, third_person_distance)
	_pitch = clampf(_pitch, _pitch_lo(), _pitch_hi())
	_update_camera()

func _update_camera() -> void:
	# Même rotation dans les deux modes : le pivot s'incline, et en 3ème
	# personne la caméra orbite autour de lui (la visée = l'axe de la caméra).
	camera.rotation = Vector3.ZERO
	camera_pivot.rotation.x = _pitch

## Rapproche la caméra 3ème personne quand le décor (falaise, rocher) la gêne.
func _update_third_person_camera(delta: float) -> void:
	var from := camera_pivot.global_position
	var wanted := camera_pivot.global_transform * Vector3(third_person_shoulder, 0.0, third_person_distance)
	var query := PhysicsRayQueryParameters3D.create(from, wanted, 1)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var target := third_person_distance
	if not hit.is_empty():
		target = maxf(third_person_min_distance, from.distance_to(hit.get("position")) - 0.3)
	# Se rapproche vite (pas de traversée du décor), s'éloigne doucement.
	var rate := 18.0 if target < _tp_distance else 4.0
	_tp_distance = lerpf(_tp_distance, target, 1.0 - exp(-rate * delta))
	var ratio := _tp_distance / third_person_distance
	camera.position = Vector3(third_person_shoulder * ratio, 0.0, _tp_distance)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not _is_touch:
		_rotate_look(event.relative * Vector2(mouse_sensitivity, mouse_sensitivity))

# --- Physique ----------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
	if Input.is_action_just_pressed("toggle_view"):
		toggle_view()
	if Input.is_action_just_pressed("interact"):
		try_interact()
	if Input.is_action_just_pressed("jump"):
		request_jump()

	var on_floor := is_on_floor()
	_track_landing(on_floor)

	# Gravité (chute un peu plus vive que la montée : saut plus « net »).
	if not on_floor:
		var gravity_scale := fall_gravity_scale if velocity.y < 0.0 else 1.0
		velocity.y = maxf(velocity.y - gravity * gravity_scale * delta, -40.0)

	# Saut : tampon d'appui + délai de grâce au bord des rebords.
	_coyote_left = coyote_time if on_floor else maxf(0.0, _coyote_left - delta)
	_jump_buffer_left = maxf(0.0, _jump_buffer_left - delta)
	if _jump_buffer_left > 0.0 and _coyote_left > 0.0:
		velocity.y = jump_velocity
		_jump_buffer_left = 0.0
		_coyote_left = 0.0
		jumped.emit()

	# Intention de déplacement (clavier / manette + stick virtuel).
	var wish := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	wish += shape_stick(_joystick_vector, stick_deadzone, stick_curve)
	if wish.length() > 1.0:
		wish = wish.normalized()
	var wish_len := wish.length()
	var moving := wish_len > 0.001

	_sprinting = moving and _wants_sprint() and not _exhausted
	_update_stamina(delta)

	var top_speed := sprint_speed if _sprinting else walk_speed
	var speed := 0.0
	if moving:
		speed = clampf(top_speed * wish_len, min_move_speed, top_speed)
	var direction := transform.basis * Vector3(wish.x, 0.0, wish.y)
	var target := direction.normalized() * speed

	var accel := acceleration if moving else deceleration
	if not on_floor:
		accel *= air_control
	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(target, accel * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	move_and_slide()

	if is_on_floor():
		_safe_timer += delta
		if _safe_timer >= 0.5:
			_safe_timer = 0.0
			_safe_position = global_position
	if global_position.y < respawn_below_y:
		global_position = _safe_position + Vector3(0.0, 1.0, 0.0)
		velocity = Vector3.ZERO

	if _view_mode == ViewMode.THIRD_PERSON:
		_update_third_person_camera(delta)

func _wants_sprint() -> bool:
	if Input.is_action_pressed("sprint") or _sprint_lock:
		return true
	if not sprint_at_full_tilt:
		return false
	var tilt := _joystick_vector.length()
	_edge_sprint = tilt >= (sprint_stick_threshold - 0.08 if _edge_sprint else sprint_stick_threshold)
	return _edge_sprint

func _update_stamina(delta: float) -> void:
	if _sprinting:
		stamina = maxf(0.0, stamina - stamina_drain * delta)
		_regen_delay_left = stamina_regen_delay
		if stamina <= 0.0:
			_exhausted = true
			_sprinting = false
	else:
		_regen_delay_left = maxf(0.0, _regen_delay_left - delta)
		if _regen_delay_left <= 0.0:
			stamina = minf(1.0, stamina + stamina_regen * delta)
		if _exhausted and stamina >= exhausted_recovery:
			_exhausted = false
	if absf(stamina - _last_emitted_stamina) > 0.002 or _exhausted != _last_emitted_exhausted:
		_last_emitted_stamina = stamina
		_last_emitted_exhausted = _exhausted
		stamina_changed.emit(stamina, _exhausted)

func _track_landing(on_floor: bool) -> void:
	if on_floor and not _was_on_floor and _prev_vy < -3.0:
		_land_dip = -clampf(-_prev_vy * 0.012, 0.0, 0.14)
	_was_on_floor = on_floor
	_prev_vy = velocity.y

# --- Rendu : bob de caméra, FOV, animation du personnage ------------------------

func _process(delta: float) -> void:
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	if _view_mode == ViewMode.FIRST_PERSON:
		_update_head_bob(delta, horizontal_speed)
	var fov_target := _base_fov + (sprint_fov_boost if _sprinting and horizontal_speed > walk_speed else 0.0)
	camera.fov = lerpf(camera.fov, fov_target, 1.0 - exp(-8.0 * delta))
	if _view_mode == ViewMode.THIRD_PERSON:
		_update_character(delta, horizontal_speed)

func _update_head_bob(delta: float, horizontal_speed: float) -> void:
	_land_dip = move_toward(_land_dip, 0.0, delta * 0.6)
	var grounded := is_on_floor()
	var strength := clampf(horizontal_speed / sprint_speed, 0.0, 1.0) if (head_bob and grounded) else 0.0
	if strength > 0.0:
		_bob_phase += delta * horizontal_speed * 2.1
	var target_y := eye_height + sin(_bob_phase * 2.0) * 0.032 * strength + _land_dip
	camera_pivot.position.y = lerpf(camera_pivot.position.y, target_y, 1.0 - exp(-22.0 * delta))

func _cache_rest_pose() -> void:
	for part in ["LegL", "LegR", "Torso/ArmL", "Torso/ArmR"]:
		var node := visuals.get_node_or_null(part) as Node3D
		if node != null:
			_rest[part] = node.transform

## Fait pivoter une partie du corps autour d'un point (hanche / épaule).
func _swing(part: String, pivot: Vector3, angle: float) -> void:
	var node := visuals.get_node_or_null(part) as Node3D
	if node == null or not _rest.has(part):
		return
	var rotation_basis := Basis(Vector3.RIGHT, angle)
	node.transform = Transform3D(rotation_basis, pivot - rotation_basis * pivot) * (_rest[part] as Transform3D)

func _update_character(delta: float, horizontal_speed: float) -> void:
	var moving := horizontal_speed > 0.3
	# Le personnage se tourne vers sa direction de déplacement (repère du joueur).
	if moving:
		var local := transform.basis.inverse() * Vector3(velocity.x, 0.0, velocity.z)
		_facing_yaw = lerp_angle(_facing_yaw, atan2(-local.x, -local.z), 1.0 - exp(-12.0 * delta))
	else:
		_facing_yaw = lerp_angle(_facing_yaw, 0.0, 1.0 - exp(-3.0 * delta))
	var lean := clampf(horizontal_speed / sprint_speed, 0.0, 1.0) * (0.14 if _sprinting else 0.05)
	visuals.rotation = Vector3(lean, _visuals_base_yaw + _facing_yaw, 0.0)

	var airborne := not is_on_floor()
	var amount := clampf(horizontal_speed / sprint_speed, 0.0, 1.0)
	if moving and not airborne:
		_walk_phase += delta * lerpf(7.0, 13.0, amount)
	# Amplitude de marche et pose « en l'air » lissées : pas de saccade à l'arrêt.
	var gait_target := (0.35 + 0.65 * amount) if (moving and not airborne) else 0.0
	_gait = lerpf(_gait, gait_target, 1.0 - exp(-10.0 * delta))
	_air_blend = lerpf(_air_blend, 1.0 if airborne else 0.0, 1.0 - exp(-14.0 * delta))

	var stride := sin(_walk_phase) * _gait * 0.85
	# ArmL est du côté +X comme LegR : bras et jambe du même côté vont en opposition.
	var leg_l := lerpf(stride, 0.5, _air_blend)
	var leg_r := lerpf(-stride, -0.25, _air_blend)
	var arm_l := lerpf(stride * 0.8, -0.9, _air_blend)
	var arm_r := lerpf(-stride * 0.8, -0.9, _air_blend)
	_swing("LegL", Vector3(-0.11, LEG_HIP_Y, 0.0), leg_l)
	_swing("LegR", Vector3(0.11, LEG_HIP_Y, 0.0), leg_r)
	_swing("Torso/ArmL", Vector3(0.24, ARM_SHOULDER_Y, 0.0), arm_l)
	_swing("Torso/ArmR", Vector3(-0.24, ARM_SHOULDER_Y, 0.0), arm_r)
	visuals.position.y = absf(sin(_walk_phase)) * 0.04 * _gait
