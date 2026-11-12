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
## Lissage exponentiel de la visée (yaw/pitch) : mouvements de caméra fluides.
@export var look_smoothing: float = 18.0

@export_group("Visée à l'arc")
@export var aim_fov: float = 42.0
@export var arrow_speed: float = 26.0
@export var aim_arrow_speed: float = 30.0
## Dispersion angulaire (radians) d'un tir sans visée.
@export var hip_spread: float = 0.03

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
var _pitch_smooth: float = -0.25
## Visée à l'arc active (bouton droit maintenu, ou automatique au tactile).
var _aiming: bool = false
var _last_aiming: bool = false
var _last_equipped_tool: String = ""
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
## Monture actuelle (cheval apprivoisé) : le joueur est surélevé et va plus vite.
var _mount: Node3D
var _mount_lift: float = 0.0

const MOUNT_LIFT := 0.75
const MOUNT_SPEED_MULTIPLIER := 1.7
var _safe_timer: float = 0.0

# Animation procédurale du personnage (vue 3ème personne).
var _visuals_base_yaw: float = 0.0
var _facing_yaw: float = 0.0
var _walk_phase: float = 0.0
var _gait: float = 0.0
var _air_blend: float = 0.0
var _rest: Dictionary = {}
## Personnage animé (Mixamo) ; null = on garde l'ancien corps en pièces rigides.
var _hero: Node3D
var _held_bow: Node3D
var _held_axe: Node3D

# Placement de l'arc et de la hache dans la main du personnage rigué.
# L'os de la main pointe vers les doigts (vers le bas, bras ballant) : demi-tour autour
# de X pour que le haut de l'outil pointe vers le haut.
var held_bow_offset := Transform3D(Basis(Vector3.RIGHT, PI), Vector3.ZERO)
var held_axe_offset := Transform3D(Basis(Vector3.RIGHT, PI), Vector3.ZERO)

const LEG_HIP_Y := 0.86
const ARM_SHOULDER_Y := 0.375

func _ready() -> void:
	# Le groupe est la façon dont HUD, animaux, spawners et météo retrouvent le joueur.
	add_to_group("player")
	_home_position = global_position
	_build_dust()
	var survival := InteractionManager.get_survival()
	if survival != null and survival.has_signal("died"):
		survival.connect("died", _on_died)
	_is_touch = PlatformInfo.is_touch()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	floor_snap_length = 0.6
	floor_max_angle = deg_to_rad(50.0)
	floor_stop_on_slope = true
	floor_constant_speed = true
	_base_fov = camera.fov
	_tp_distance = third_person_distance
	_pitch_smooth = _pitch
	_safe_position = global_position
	_visuals_base_yaw = visuals.rotation.y
	_cache_rest_pose()
	_setup_hero()
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

## Monte un animal (cheval) : le joueur est surélevé, la monture suit ses déplacements.
func mount(animal: Node3D) -> void:
	_mount = animal
	_mount_lift = MOUNT_LIFT
	_apply_view_mode()

func dismount() -> void:
	_mount = null
	_mount_lift = 0.0
	InteractionManager.set_forced_target(null)
	_apply_view_mode()

func is_mounted() -> bool:
	return _mount != null

# --- Poussière de course ------------------------------------------------------------------

var _dust: CPUParticles3D

## Nuage de poussière (ou de poudreuse l'hiver) soulevé aux pieds quand on court ou qu'on galope.
func _build_dust() -> void:
	_dust = CPUParticles3D.new()
	_dust.name = "Dust"
	_dust.emitting = false
	_dust.amount = 28
	_dust.lifetime = 0.7
	_dust.local_coords = false
	_dust.direction = Vector3.UP
	_dust.spread = 50.0
	_dust.initial_velocity_min = 0.4
	_dust.initial_velocity_max = 1.2
	_dust.gravity = Vector3(0.0, 0.3, 0.0)
	_dust.scale_amount_min = 0.5
	_dust.scale_amount_max = 1.2
	_dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_dust.emission_sphere_radius = 0.25
	var puff := QuadMesh.new()
	puff.size = Vector2(0.3, 0.3)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Nuage de poussière texturé (Kenney CC0) ; repli sur la couleur unie si absent.
	var dust_tex := VfxParticles.tex("circle_02")
	if dust_tex != null:
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		material.albedo_texture = dust_tex
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.74, 0.6, 0.42, 0.4)
	puff.material = material
	_dust.mesh = puff
	var fade := Curve.new()
	fade.add_point(Vector2(0.0, 0.4))
	fade.add_point(Vector2(0.4, 1.0))
	fade.add_point(Vector2(1.0, 0.0))
	_dust.scale_amount_curve = fade
	add_child(_dust)

func _update_dust() -> void:
	if _dust == null:
		return
	var horizontal := Vector2(velocity.x, velocity.z).length()
	_dust.emitting = is_on_floor() and horizontal > 5.2
	_dust.position = Vector3(0.0, 0.05, 0.0)
	var weather := InteractionManager.get_weather()
	var snowy: bool = weather != null and float(weather.call("get_snow_amount")) > 0.4
	(_dust.mesh.material as StandardMaterial3D).albedo_color = Color(0.95, 0.97, 1.0, 0.5) if snowy else Color(0.74, 0.6, 0.42, 0.4)

## Attaque : tir à l'arc si l'arc est équipé, sinon coup de hache sur un prédateur proche.
func try_attack() -> void:
	var inventory := InteractionManager.get_inventory()
	if inventory == null:
		return
	if inventory.is_equipped("tool_hunting_bow"):
		try_shoot_arrow()
	elif inventory.is_equipped("tool_stone_axe"):
		try_melee()

const ATTACK_ANIM_TIME := 0.28
const MELEE_RANGE := 2.6
var _attack_anim: float = 0.0
const MELEE_COOLDOWN := 0.6
var _melee_cooldown: float = 0.0
var _home_position: Vector3

## Coup de hache : touche le prédateur le mieux placé devant le joueur.
func try_melee() -> bool:
	if _melee_cooldown > 0.0:
		return false
	_melee_cooldown = MELEE_COOLDOWN
	_swing_arm()
	var forward := -global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var best: Node3D = null
	var best_distance := MELEE_RANGE
	for target in get_tree().get_nodes_in_group("predators"):
		if not is_instance_valid(target) or not target.has_method("hit"):
			continue
		var offset: Vector3 = target.global_position - global_position
		offset.y = 0.0
		var distance := offset.length()
		if distance < best_distance and (distance < 0.8 or forward.dot(offset / maxf(distance, 0.001)) > 0.3):
			best = target
			best_distance = distance
	if best != null:
		best.call("hit", 2, global_position)
		return true
	return false

func _swing_arm() -> void:
	_attack_anim = ATTACK_ANIM_TIME

## Le lit ou l'abri où l'on se repose devient le nouveau point de réveil.
func set_home(point: Vector3) -> void:
	_home_position = point

## Terrassé : on se réveille au camp de départ, à moitié rétabli.
func _on_died() -> void:
	if _mount != null:
		dismount()
	global_position = _home_position + Vector3(0.0, 1.0, 0.0)
	velocity = Vector3.ZERO
	var survival := InteractionManager.get_survival()
	if survival != null:
		survival.call("revive")
	_hud_toast(tr("TOAST_DIED"))

func _try_interact() -> void:
	try_interact()

## Tir à l'arc de chasse : nécessite l'arc ET une flèche dans le sac.
## La flèche part de la caméra vers le point visé, avec une balistique légère.
func try_shoot_arrow() -> void:
	var inventory := InteractionManager.get_inventory()
	if inventory == null:
		return
	if not inventory.is_equipped("tool_hunting_bow"):
		return
	if not inventory.remove_item("arrow", 1):
		_hud_toast(tr("TOAST_NO_ARROWS"))
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		inventory.add_item("arrow", 1)
		return
	var arrow_scene := load("res://scenes/interaction/arrow.tscn") as PackedScene
	if arrow_scene == null:
		inventory.add_item("arrow", 1)
		return
	var arrow := arrow_scene.instantiate() as RigidBody3D
	var host := get_tree().current_scene if get_tree().current_scene != null else get_parent()
	if host == null:
		inventory.add_item("arrow", 1)
		return
	host.add_child(arrow)
	var from := camera.global_position + camera.global_transform.basis.z * -0.4
	var aim := -camera.global_transform.basis.z
	# Sans visée, la flèche disperse un peu ; en visée, tir tendu et plus rapide.
	var dir := aim
	if not _aiming and hip_spread > 0.0:
		dir = dir.rotated(Vector3.UP, randf_range(-hip_spread, hip_spread))
		dir = dir.rotated(Vector3.RIGHT, randf_range(-hip_spread, hip_spread)).normalized()
	arrow.global_position = from
	arrow.look_at(from + dir, Vector3.UP)
	arrow.linear_velocity = dir * (aim_arrow_speed if _aiming else arrow_speed)
	arrow.angular_velocity = Vector3.ZERO

func _hud_toast(message: String) -> void:
	var hud := get_tree().get_first_node_in_group("hud") if get_tree() != null else null
	if hud != null and hud.has_method("show_toast"):
		hud.show_toast(message, 1.6)

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
	# Yaw immédiat (1:1 avec la souris), pitch lissé dans _process : la caméra
	# monte/descend sans saccade, le cap reste fidèle au mouvement.
	rotate_y(-delta.x)
	_pitch = clampf(_pitch - delta.y, _pitch_lo(), _pitch_hi())

func _pitch_lo() -> float:
	return pitch_min if _view_mode == ViewMode.FIRST_PERSON else third_person_pitch_min

func _pitch_hi() -> float:
	return pitch_max if _view_mode == ViewMode.FIRST_PERSON else third_person_pitch_max

func _apply_view_mode() -> void:
	var first := _view_mode == ViewMode.FIRST_PERSON
	visuals.visible = not first
	if first:
		camera_pivot.position = Vector3(0.0, eye_height + _mount_lift, 0.0)
		camera.position = Vector3.ZERO
	else:
		camera_pivot.position = Vector3(0.0, third_person_height + _mount_lift, 0.0)
		_tp_distance = third_person_distance
		camera.position = Vector3(third_person_shoulder, 0.0, third_person_distance)
	_pitch = clampf(_pitch, _pitch_lo(), _pitch_hi())
	_update_camera()

func _update_camera() -> void:
	# Même rotation dans les deux modes : le pivot s'incline, et en 3ème
	# personne la caméra orbite autour de lui (la visée = l'axe de la caméra).
	camera.rotation = Vector3.ZERO
	camera_pivot.rotation.x = _pitch_smooth

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
	elif event.is_action_pressed("attack"):
		try_attack()

# --- Physique ----------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_melee_cooldown = maxf(0.0, _melee_cooldown - delta)
	# Visée à l'arc : bouton droit (PC) ou visée automatique au tactile quand l'arc est équipé.
	var inventory := InteractionManager.get_inventory()
	var bow_equipped: bool = inventory != null and inventory.is_equipped("tool_hunting_bow")
	_aiming = bow_equipped and (Input.is_action_pressed("aim") or _is_touch)
	if _aiming != _last_aiming:
		_last_aiming = _aiming
		var hud := get_tree().get_first_node_in_group("hud") if get_tree() != null else null
		if hud != null and hud.has_method("set_aiming"):
			hud.call("set_aiming", _aiming)
	_update_held_tool()
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
	if _mount != null:
		top_speed *= MOUNT_SPEED_MULTIPLIER
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
	_update_dust()
	if global_position.y < respawn_below_y:
		global_position = _safe_position + Vector3(0.0, 1.0, 0.0)
		velocity = Vector3.ZERO

	if _view_mode == ViewMode.THIRD_PERSON:
		_update_third_person_camera(delta)

func _wants_sprint() -> bool:
	# Faim et soif vides : le corps ne suit plus (SurvivalManager).
	var survival := get_tree().root.get_node_or_null("SurvivalManager")
	if survival != null and survival.has_method("can_sprint") and not survival.call("can_sprint"):
		return false
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
			# La faim/soif vide ralentit la récupération (SurvivalManager).
			var regen_factor := 1.0
			var survival := get_tree().root.get_node_or_null("SurvivalManager")
			if survival != null and survival.has_method("stamina_regen_factor"):
				regen_factor = float(survival.call("stamina_regen_factor"))
			var progression := InteractionManager.get_progression()
			if progression != null:
				regen_factor *= float(progression.call("stamina_regen_multiplier"))
			stamina = minf(1.0, stamina + stamina_regen * regen_factor * delta)
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
	# Lissage de la visée verticale : le pivot suit le pitch cible en douceur.
	var k := 1.0 - exp(-look_smoothing * delta)
	_pitch_smooth = lerpf(_pitch_smooth, _pitch, k)
	_update_camera()
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	if _view_mode == ViewMode.FIRST_PERSON:
		_update_head_bob(delta, horizontal_speed)
	var fov_target := _base_fov + (sprint_fov_boost if _sprinting and horizontal_speed > walk_speed else 0.0)
	if _aiming:
		fov_target = aim_fov
	camera.fov = lerpf(camera.fov, fov_target, 1.0 - exp(-8.0 * delta))
	if _view_mode == ViewMode.THIRD_PERSON:
		_update_character(delta, horizontal_speed)

## Affiche l'outil équipé dans la main droite (arc ou hache), sinon rien.
func _update_held_tool() -> void:
	var inventory := InteractionManager.get_inventory()
	var equipped := "" if inventory == null else String(inventory.call("get_equipped"))
	if equipped == _last_equipped_tool:
		return
	_last_equipped_tool = equipped
	var bow_node := _held_bow
	var axe_node := _held_axe
	if bow_node != null:
		bow_node.visible = equipped == "tool_hunting_bow"
	if axe_node != null:
		axe_node.visible = equipped == "tool_stone_axe"

func _update_head_bob(delta: float, horizontal_speed: float) -> void:
	_land_dip = move_toward(_land_dip, 0.0, delta * 0.6)
	var grounded := is_on_floor()
	var strength := clampf(horizontal_speed / sprint_speed, 0.0, 1.0) if (head_bob and grounded) else 0.0
	if strength > 0.0:
		_bob_phase += delta * horizontal_speed * 2.1
	var target_y := eye_height + _mount_lift + sin(_bob_phase * 2.0) * 0.032 * strength + _land_dip
	camera_pivot.position.y = lerpf(camera_pivot.position.y, target_y, 1.0 - exp(-22.0 * delta))

## Remplace le corps en boîtes par le personnage rigué s'il est disponible.
## Les anciennes pièces restent dans la scène (invisibles) : l'arc et la hache
## y sont accrochés et sont replacés dans la main du modèle à chaque image.
func _setup_hero() -> void:
	_held_bow = visuals.get_node_or_null("Torso/ArmR/HeldBow") as Node3D
	_held_axe = visuals.get_node_or_null("Torso/ArmR/HeldAxe") as Node3D
	var hero := Node3D.new()
	hero.name = "Hero"
	hero.set_script(load("res://scripts/player/hero_model.gd"))
	if not hero.call("load_model"):
		hero.free()
		return
	_hide_rigid_body(visuals)
	visuals.add_child(hero)
	_hero = hero

func _hide_rigid_body(node: Node) -> void:
	if node == _held_bow or node == _held_axe:
		return
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		# Calque 0 : plus rendu par aucune caméra, mais le nœud (et ses enfants) reste actif.
		mesh_node.layers = 0
		mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_hide_rigid_body(child)

func _update_hero(delta: float, horizontal_speed: float, moving: bool) -> void:
	_hero.call("update_motion", horizontal_speed, moving, is_on_floor())
	var hand: Transform3D = _hero.call("hand_transform")
	if _held_bow != null:
		_held_bow.global_transform = hand * held_bow_offset
	if _held_axe != null:
		_held_axe.global_transform = hand * held_axe_offset
	if _attack_anim > 0.0:
		_attack_anim = maxf(0.0, _attack_anim - delta)

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
	if _hero != null:
		# Pas d'animation de coup : le buste plonge vers l'avant le temps du geste.
		if _attack_anim > 0.0:
			lean += 0.45 * sin((1.0 - _attack_anim / ATTACK_ANIM_TIME) * PI)
		visuals.rotation = Vector3(lean, _visuals_base_yaw + _facing_yaw, 0.0)
		visuals.position.y = _mount_lift
		_update_hero(delta, horizontal_speed, moving)
		return
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
	# Coup porté : le bras droit se lève puis s'abat.
	if _attack_anim > 0.0:
		_attack_anim = maxf(0.0, _attack_anim - delta)
		arm_r = -2.4 * sin((1.0 - _attack_anim / ATTACK_ANIM_TIME) * PI)
	_swing("LegL", Vector3(-0.11, LEG_HIP_Y, 0.0), leg_l)
	_swing("LegR", Vector3(0.11, LEG_HIP_Y, 0.0), leg_r)
	_swing("Torso/ArmL", Vector3(0.24, ARM_SHOULDER_Y, 0.0), arm_l)
	_swing("Torso/ArmR", Vector3(-0.24, ARM_SHOULDER_Y, 0.0), arm_r)
	visuals.position.y = absf(sin(_walk_phase)) * 0.04 * _gait + _mount_lift
