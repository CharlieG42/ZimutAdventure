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
@export var mouse_sensitivity: float = 0.0028
@export var touch_sensitivity: float = 0.006
@export var camera_joystick_speed: float = 5.2
@export_range(0.0, 0.5) var camera_stick_deadzone: float = 0.08
@export var camera_stick_curve: float = 1.5
@export var pitch_min: float = -1.45
@export var pitch_max: float = 1.55
@export var eye_height: float = 1.6
@export var head_bob: bool = true
@export var sprint_fov_boost: float = 6.0
## En mode portrait (une main) le champ horizontal rétrécit : on élargit le FOV.
@export var portrait_fov_boost: float = 10.0
## Lissage exponentiel de la visée (yaw/pitch) : mouvements de caméra fluides.
@export var look_smoothing: float = 30.0

@export_group("Visée à l'arc")
@export var aim_fov: float = 42.0
@export var arrow_speed: float = 26.0
## Vitesse de la flèche à pleine tension (la vitesse de base vaut pour un tir sans bander).
@export var full_draw_speed: float = 38.0
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
var _pivot_yaw: float = 0.0
var _aim_override: bool = false  # bouton « Viser » tactile
## Arc : on maintient pour bander, on relâche pour tirer. La cible la plus proche du
## viseur est verrouillée et la flèche compense seule la distance et la chute.
const DRAW_TIME := 0.7
const DRAW_MOVE_FACTOR := 0.45
const BOW_RANGE := 45.0
const BOW_CONE_TOUCH := 0.28
const BOW_CONE_MOUSE := 0.16
const QUICK_SHOT_CHARGE := 0.25
var _drawing: bool = false
var _draw_time: float = 0.0
var _bow_equipped: bool = false
var _bow_target: Node3D
var _last_equipped_tool: String = ""
var _joystick_vector: Vector2 = Vector2.ZERO
var _is_touch: bool = false
var _view_mode: int = ViewMode.FIRST_PERSON

var _coyote_left: float = 0.0
var _jump_buffer_left: float = 0.0
var _sprint_lock: bool = false
var _edge_sprint: bool = false
var _sprinting: bool = false
## Sac plein à plus de 100 % : la course est bloquée et la fatigue monte plus vite.
var _overloaded: bool = false
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
## Temps à cheval accumulé : toutes les 30 s, +1 XP de compétence Équitation.
var _mount_xp_timer: float = 0.0
## Pieds au-dessus du sol en pente : surélévation lissée des visuels quand un pied s'enfoncerait.
var _foot_lift: float = 0.0
var _foot_skeleton: Skeleton3D = null
var _foot_bones: PackedInt32Array = []
const FOOT_LIFT_MAX := 0.45
const FOOT_CLEARANCE := 0.04

## Dans la rivière, on avance moins vite (à pied comme à cheval).
const WADE_SPEED_FACTOR := 0.6
var _wading: bool = false
var _landscape_ref: Node3D

const MOUNT_LIFT := 0.75
const BOOTS_ITEM := "gear_hide_boots"
const BOOTS_SPEED_FACTOR := 1.08
## Surcharge (> 100 % du sac) : la course draine l'endurance 1.8 fois plus vite.
const OVERLOAD_STAMINA_DRAIN := 1.8
## Hauteur (au-dessus du sol) du creux du dos du cheval, où se pose le bassin du cavalier.
const MOUNT_SEAT_HEIGHT := 1.86
## Le bassin s'abaisse de 18 cm dans la pose « à cheval » (voir les modèles du personnage).
const RIDE_HIP_DROP := 0.18
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
## Pour les tests : garde l'ancien personnage Mixamo à la place du personnage low-poly.
var use_legacy_hero: bool = false

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
	_rotate_look(delta * touch_sensitivity * 240.0 * _look_gain())

## Réglage « sensibilité caméra » du joueur (1.0 sans autoload, ex. tests).
func _look_gain() -> float:
	var settings := get_node_or_null("/root/GameSettings")
	return float(settings.get("look_sensitivity")) if settings != null else 1.0

func apply_camera_joystick(vector: Vector2, delta: float) -> void:
	var shaped := shape_stick(vector, camera_stick_deadzone, camera_stick_curve)
	# Le mouvement vertical est un peu plus lent : moins de vertige, visée plus fine.
	shaped.y *= 0.7
	_rotate_look(shaped * camera_joystick_speed * delta * _look_gain())

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
## Cap affiché par la boussole : là où regarde la caméra (en visée, le viseur tourne seul).
func get_heading_degrees() -> float:
	return fposmod(-rad_to_deg(rotation.y + _pivot_yaw), 360.0)

func try_interact() -> void:
	# Pendant le déplacement d'une construction, « interagir » la repose.
	var spawner := get_tree().get_first_node_in_group("structure_spawner") if is_inside_tree() else null
	if spawner != null and bool(spawner.call("is_moving")):
		spawner.call("confirm_move")
		return
	var target := InteractionManager.get_current_target()
	if target != null and target is Interactable:
		(target as Interactable).interact(self)

## Monte un animal (cheval) : le joueur est surélevé, la monture suit ses déplacements.
func mount(animal: Node3D) -> void:
	_mount = animal
	_mount_lift = mount_lift_for_hero()
	_apply_view_mode()

## Surélévation du personnage en selle : son bassin se pose sur le dos du cheval, quelle que
## soit sa taille (homme ou femme).
func mount_lift_for_hero() -> float:
	var hip := hero_hip_height()
	if hip <= 0.0:
		return MOUNT_LIFT
	return clampf(MOUNT_SEAT_HEIGHT - (hip - RIDE_HIP_DROP), 0.6, 1.5)

## Hauteur du bassin du personnage debout (repère des visuels), 0 si inconnue.
func hero_hip_height() -> float:
	if _hero == null:
		return 0.0
	var skeletons := _hero.find_children("*", "Skeleton3D", true, false)
	if not skeletons.is_empty():
		var sk := skeletons[0] as Skeleton3D
		var bone := sk.find_bone("mixamorig_Hips")
		if bone >= 0:
			var world_hip := sk.global_transform * sk.get_bone_global_rest(bone).origin
			return (visuals.global_transform.affine_inverse() * world_hip).y
	var hip_value = _hero.get("_hip_height")
	if hip_value != null:
		return float(hip_value)
	return 0.0

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

## Appui sur le bouton d'attaque : commence à bander l'arc, ou donne un coup de hache.
func begin_attack() -> void:
	var inventory := InteractionManager.get_inventory()
	if inventory == null:
		return
	if inventory.is_equipped(RIFLE):
		fire_rifle()
	elif inventory.is_equipped("tool_hunting_bow"):
		if arrow_count() <= 0:
			_hud_toast(tr("TOAST_NO_ARROWS"))
			return
		_drawing = true
		_draw_time = 0.0
	elif inventory.is_equipped("tool_stone_axe"):
		try_melee()

## Relâchement : la flèche part, d'autant plus vite et droit que l'arc était bandé.
## Un appui bref (bouton « Tirer ») tire quand même une flèche correcte.
func end_attack() -> void:
	if not _drawing:
		return
	var charge := maxf(get_draw_charge(), QUICK_SHOT_CHARGE)
	_drawing = false
	_draw_time = 0.0
	shoot_arrow(charge)

## Bouton « Viser » (tactile) : verrouille la visée à l'arc sans toucher au personnage.
func set_aim_override(value: bool) -> void:
	_aim_override = value

func is_aiming() -> bool:
	return _aiming

## Tension de l'arc, de 0 (à peine bandé) à 1 (pleine tension).
func get_draw_charge() -> float:
	return clampf(_draw_time / DRAW_TIME, 0.0, 1.0) if _drawing else 0.0

## État de l'arc pour l'affichage (viseur, cible verrouillée, flèches restantes).
func get_bow_state() -> Dictionary:
	var inventory := InteractionManager.get_inventory()
	var target: Node3D = _bow_target if _bow_target != null and is_instance_valid(_bow_target) else null
	return {
		"equipped": _bow_equipped,
		"drawing": _drawing,
		"charge": get_draw_charge(),
		"target": target,
		"arrows": (int(inventory.call("count_of", CARTRIDGE)) if inventory.is_equipped(RIFLE) else arrow_count()) if inventory != null else 0,
		"weapon": "rifle" if inventory != null and inventory.is_equipped(RIFLE) else "bow",
	}

## Flèches dans le sac (pointe de fer comprises).
func arrow_count() -> int:
	var inventory := InteractionManager.get_inventory()
	if inventory == null:
		return 0
	return int(inventory.call("count_of", "arrow")) + int(inventory.call("count_of", IRON_ARROW))

## Attaque immédiate (sans maintien) : tir rapide à l'arc ou coup de hache.
func try_attack() -> void:
	var inventory := InteractionManager.get_inventory()
	if inventory == null:
		return
	if inventory.is_equipped(RIFLE):
		fire_rifle()
	elif inventory.is_equipped("tool_hunting_bow"):
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
	var targets: Array = get_tree().get_nodes_in_group("predators") + get_tree().get_nodes_in_group("huntable")
	for target in targets:
		if not is_instance_valid(target) or not (target.has_method("hit") or target.has_method("take_arrow_hit")):
			continue
		var offset: Vector3 = target.global_position - global_position
		offset.y = 0.0
		var distance := offset.length()
		if distance < best_distance and (distance < 0.8 or forward.dot(offset / maxf(distance, 0.001)) > 0.3):
			best = target
			best_distance = distance
	if best != null:
		if best.has_method("take_arrow_hit"):
			best.call("take_arrow_hit", global_position)
		else:
			# Hache en fer : coup deux fois plus fort.
			var iron_axe: bool = bool(InteractionManager.get_inventory().call("is_iron_tool", "tool_stone_axe"))
			best.call("hit", 4 if iron_axe else 2, global_position)
		var sfx := InteractionManager.get_sfx()
		if sfx != null and sfx.has_method("play_event"):
			sfx.call("play_event", "hit", -4.0, randf_range(0.9, 1.1))
		return true
	# Pas de gibier à portée : le coup de hache abat l'arbre visé (même effet que « Action »).
	var tree := _choppable_in_reach(forward)
	if tree != null:
		tree.call("interact", self)
		return true
	return false

## Arbre (ou autre objet « choppable ») à portée et devant le joueur.
func _choppable_in_reach(forward: Vector3) -> Node3D:
	var best: Node3D = null
	var best_distance := MELEE_RANGE + 1.2
	for node in get_tree().get_nodes_in_group("choppable"):
		if not is_instance_valid(node) or not node.has_method("can_interact") or not node.call("can_interact"):
			continue
		var offset: Vector3 = node.global_position - global_position
		offset.y = 0.0
		var distance := offset.length()
		if distance < best_distance and (distance < 1.6 or forward.dot(offset / maxf(distance, 0.001)) > 0.3):
			best = node
			best_distance = distance
	return best

## Siffler : appelle le cheval et le chien apprivoisés les plus proches. Renvoie vrai si au moins un répond.
func whistle() -> bool:
	var horses: Array = []
	var dogs: Array = []
	var busy := 0
	for node in get_tree().get_nodes_in_group("domestic"):
		if not is_instance_valid(node) or not bool(node.get("tamed")) or bool(node.get("mounted")):
			continue
		if node.get("species") != "horse" and node.get("species") != "dog":
			continue
		# En enclos (cheval) ou de garde (chien) : il faut d'abord le libérer.
		if node.has_method("answers_whistle") and not bool(node.call("answers_whistle")):
			busy += 1
			continue
		if node.get("species") == "horse":
			horses.append(node)
		else:
			dogs.append(node)
	if horses.is_empty() and dogs.is_empty():
		_hud_toast(tr("TOAST_WHISTLE_BUSY") if busy > 0 else tr("TOAST_WHISTLE_NONE"))
		return false
	var by_distance := func(a, b): return a.global_position.distance_to(global_position) < b.global_position.distance_to(global_position)
	horses.sort_custom(by_distance)
	dogs.sort_custom(by_distance)
	var horse_came: bool = not horses.is_empty() and bool(horses[0].call("call_to_player", self))
	var dog_came: bool = not dogs.is_empty() and bool(dogs[0].call("call_to_player", self))
	if horse_came and dog_came:
		_hud_toast(tr("TOAST_WHISTLE_BOTH"))
	elif horse_came:
		_hud_toast(tr("TOAST_WHISTLE"))
	elif dog_came:
		_hud_toast(tr("TOAST_WHISTLE_DOG"))
	else:
		_hud_toast(tr("TOAST_WHISTLE_FAR"))
	return horse_came or dog_came

func _swing_arm() -> void:
	_attack_anim = ATTACK_ANIM_TIME
	if _hero != null:
		_hero.call("play_chop")

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

## Tir immédiat : pleine tension si l'on vise, tir rapide sinon.
# --- Carabine à levier (western) --------------------------------------------------------

const RIFLE := "tool_rifle"
const CARTRIDGE := "item_cartridge"
const IRON_ARROW := "arrow_iron"
## Un coup de levier entre deux tirs.
const RIFLE_COOLDOWN := 1.1
const RIFLE_RANGE := 90.0
const RIFLE_DAMAGE := 6
## Tolérance autour de la ligne de mire (m) pour toucher un animal.
const RIFLE_AIM_RADIUS := 1.1
var _rifle_cooldown: float = 0.0

## Tir de carabine : instantané, portée 90 m, une cartouche. Touche la cible verrouillée,
## sinon l'animal le plus proche de la ligne de mire (pas à travers le relief).
## Renvoie l'animal touché (ou null).
func fire_rifle() -> Node3D:
	var inventory := InteractionManager.get_inventory()
	if inventory == null or not inventory.is_equipped(RIFLE) or _rifle_cooldown > 0.0:
		return null
	if not inventory.remove_item(CARTRIDGE, 1):
		_hud_toast(tr("TOAST_NO_CARTRIDGES"))
		return null
	_rifle_cooldown = RIFLE_COOLDOWN
	var camera := get_viewport().get_camera_3d()
	var from := _arrow_origin(camera) if camera != null else global_position + Vector3(0, 1.4, 0)
	var dir := -camera.global_transform.basis.z if camera != null else -global_transform.basis.z
	var target := rifle_target(from, dir)
	_rifle_effects(from, dir)
	if target == null:
		return null
	var origin := global_position
	if target.has_method("hit") and target.is_in_group("predators"):
		target.call("hit", RIFLE_DAMAGE, origin)
	elif target.has_method("take_arrow_hit"):
		target.call("take_arrow_hit", origin)
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("notify_hit"):
		hud.call("notify_hit", target)
	return target

func rifle_target(from: Vector3, dir: Vector3) -> Node3D:
	if _bow_target != null and is_instance_valid(_bow_target) and _bow_target.is_inside_tree() \
			and from.distance_to(_bow_target.global_position) <= RIFLE_RANGE and _clear_shot(from, _target_point(_bow_target)):
		return _bow_target
	var best: Node3D = null
	var best_score := INF
	var targets: Array = get_tree().get_nodes_in_group("predators") + get_tree().get_nodes_in_group("huntable")
	for target in targets:
		if not is_instance_valid(target) or bool(target.get("_dead")):
			continue
		var point := _target_point(target)
		var along := (point - from).dot(dir)
		if along <= 0.5 or along > RIFLE_RANGE:
			continue
		var miss := (point - (from + dir * along)).length()
		var tolerance := RIFLE_AIM_RADIUS + along * 0.02
		if miss > tolerance:
			continue
		var score := miss + along * 0.01
		if score < best_score and _clear_shot(from, point):
			best_score = score
			best = target
	return best

## Le relief (couche 1) ne cache pas la cible.
func _clear_shot(from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or (hit["position"] as Vector3).distance_to(to) < 1.5

## Détonation, éclair au canon et petit nuage de fumée.
func _rifle_effects(from: Vector3, dir: Vector3) -> void:
	var sfx := InteractionManager.get_sfx()
	if sfx != null:
		var stream := load("res://assets/audio/sfx/rifle_shot.wav") as AudioStream
		if stream != null:
			sfx.call("play", stream, -2.0, randf_range(0.95, 1.05))
	var host := get_tree().current_scene if get_tree().current_scene != null else get_parent()
	if host == null:
		return
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.8, 0.45)
	flash.light_energy = 6.0
	flash.omni_range = 5.0
	host.add_child(flash)
	flash.global_position = from + dir * 0.6
	var smoke := MeshInstance3D.new()
	var puff := SphereMesh.new()
	puff.radius = 0.12
	puff.height = 0.24
	smoke.mesh = puff
	var smoke_mat := StandardMaterial3D.new()
	smoke_mat.albedo_color = Color(0.85, 0.85, 0.82, 0.7)
	smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smoke.material_override = smoke_mat
	host.add_child(smoke)
	smoke.global_position = from + dir * 0.7
	var tween := smoke.create_tween()
	tween.set_parallel(true)
	tween.tween_property(flash, "light_energy", 0.0, 0.12)
	tween.tween_property(smoke, "scale", Vector3.ONE * 4.0, 0.9)
	tween.tween_property(smoke, "global_position", smoke.global_position + Vector3(0, 0.5, 0) + dir * 0.6, 0.9)
	tween.tween_property(smoke_mat, "albedo_color:a", 0.0, 0.9)
	tween.chain().tween_callback(func():
		flash.queue_free()
		smoke.queue_free())

func try_shoot_arrow() -> void:
	shoot_arrow(1.0 if _aiming else QUICK_SHOT_CHARGE)

## Tir à l'arc de chasse : nécessite l'arc ET une flèche dans le sac.
## La flèche part du joueur vers la cible verrouillée (ou le point visé au centre de
## l'écran) ; l'angle de tir compense la chute, la tension règle vitesse et précision.
func shoot_arrow(charge: float) -> void:
	var inventory := InteractionManager.get_inventory()
	if inventory == null:
		return
	if not inventory.is_equipped("tool_hunting_bow"):
		return
	var camera := get_viewport().get_camera_3d()
	var arrow_scene := load("res://scenes/interaction/arrow.tscn") as PackedScene
	var host := get_tree().current_scene if get_tree().current_scene != null else get_parent()
	if camera == null or arrow_scene == null or host == null:
		return
	# Les flèches à pointe de fer partent d'abord.
	var ammo := IRON_ARROW if int(inventory.call("count_of", IRON_ARROW)) > 0 else "arrow"
	if not inventory.remove_item(ammo, 1):
		_hud_toast(tr("TOAST_NO_ARROWS"))
		return
	charge = clampf(charge, 0.0, 1.0)
	var speed := lerpf(arrow_speed, full_draw_speed, charge)
	var arrow := arrow_scene.instantiate() as RigidBody3D
	arrow.set("iron", ammo == IRON_ARROW)
	host.add_child(arrow)
	var from := _arrow_origin(camera)
	var dir := ballistic_direction(from, _aim_point(camera, from, speed), speed, gravity * arrow.gravity_scale)
	# Arc peu bandé : la flèche disperse un peu (moins avec la compétence Chasse).
	var spread := hip_spread * (1.0 - charge)
	var progression_spread := InteractionManager.get_progression()
	if progression_spread != null:
		spread *= float(progression_spread.call("chasse_spread_factor"))
	if spread > 0.0:
		dir = dir.rotated(Vector3.UP, randf_range(-spread, spread))
		dir = dir.rotated(camera.global_transform.basis.x.normalized(), randf_range(-spread, spread)).normalized()
	arrow.global_position = from
	arrow.look_at(from + dir, Vector3.UP)
	arrow.linear_velocity = dir * speed
	arrow.angular_velocity = Vector3.ZERO

## Point de départ de la flèche : devant la caméra en vue subjective, à hauteur
## d'épaule du personnage sinon (la flèche ne part plus de derrière son dos).
func _arrow_origin(camera: Camera3D) -> Vector3:
	var forward := -camera.global_transform.basis.z
	if _view_mode == ViewMode.FIRST_PERSON:
		return camera.global_position + forward * 0.4
	var flat := Vector3(forward.x, 0.0, forward.z)
	flat = flat.normalized() if flat.length_squared() > 0.0001 else -global_transform.basis.z
	return global_position + Vector3(0.0, 1.35, 0.0) + flat * 0.6

## Point à atteindre : la cible verrouillée (avec anticipation de sa course), sinon ce
## que montre le centre de l'écran.
func _aim_point(camera: Camera3D, from: Vector3, speed: float) -> Vector3:
	if _bow_target != null and is_instance_valid(_bow_target) and _bow_target.is_inside_tree():
		var point := _target_point(_bow_target)
		var target_velocity: Variant = _bow_target.get("velocity")
		if target_velocity is Vector3:
			var flight := from.distance_to(point) / maxf(speed, 1.0)
			point += Vector3(target_velocity.x, 0.0, target_velocity.z) * flight
		return point
	var forward := -camera.global_transform.basis.z
	var start := camera.global_position + forward * (camera.global_position.distance_to(from) + 0.5)
	var end := camera.global_position + forward * 70.0
	var query := PhysicsRayQueryParameters3D.create(start, end)
	query.collision_mask = 1
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit["position"] if not hit.is_empty() else end

func _target_point(target: Node3D) -> Vector3:
	if target.has_method("get_aim_point"):
		return target.call("get_aim_point")
	return target.global_position + Vector3(0.0, 0.6, 0.0)

## Direction de tir pour atteindre `to` depuis `from` à la vitesse donnée (arc tendu).
## Hors de portée : tir en cloche vers la cible.
static func ballistic_direction(from: Vector3, to: Vector3, speed: float, g: float) -> Vector3:
	var offset := to - from
	var flat := Vector3(offset.x, 0.0, offset.z)
	var x := flat.length()
	if x < 0.05 or g <= 0.0:
		return offset.normalized() if offset.length_squared() > 0.0001 else Vector3.FORWARD
	var v2 := speed * speed
	var disc := v2 * v2 - g * (g * x * x + 2.0 * offset.y * v2)
	var angle := deg_to_rad(40.0)
	if disc >= 0.0:
		angle = atan((v2 - sqrt(disc)) / (g * x))
	return (flat / x * cos(angle) + Vector3.UP * sin(angle)).normalized()

## Verrouille le gibier (ou le prédateur) le plus proche du centre de l'écran,
## à portée et sans obstacle entre lui et le joueur.
func _update_bow_target() -> void:
	var camera := get_viewport().get_camera_3d()
	if not _bow_equipped or camera == null or not is_inside_tree():
		_bow_target = null
		return
	var cone := BOW_CONE_TOUCH if _is_touch else BOW_CONE_MOUSE
	var forward := -camera.global_transform.basis.z
	var eye := camera.global_position
	var chest := global_position + Vector3(0.0, 1.35, 0.0)
	var space := get_world_3d().direct_space_state
	var best: Node3D = null
	var best_score := cone
	for node in get_tree().get_nodes_in_group("huntable"):
		var candidate := node as Node3D
		if candidate == null or not is_instance_valid(candidate) or not candidate.is_inside_tree():
			continue
		var point := _target_point(candidate)
		var distance := point.distance_to(chest)
		if distance > BOW_RANGE or distance < 1.0:
			continue
		var score := forward.angle_to(point - eye)
		# La cible déjà verrouillée garde la priorité : le verrou ne saute pas sans arrêt.
		if candidate == _bow_target:
			score *= 0.6
		if score >= best_score:
			continue
		var query := PhysicsRayQueryParameters3D.create(chest, point)
		query.collision_mask = 1
		var excluded: Array[RID] = [get_rid()]
		if candidate is CollisionObject3D:
			excluded.append((candidate as CollisionObject3D).get_rid())
		query.exclude = excluded
		if not space.intersect_ray(query).is_empty():
			continue
		best = candidate
		best_score = score
	_bow_target = best

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
	# En visée à l'arc, seul le viseur bouge : le yaw part sur le pivot caméra,
	# le corps du personnage reste en place. Sinon yaw immédiat (1:1 souris) sur
	# le personnage ; le pitch est lissé dans _process.
	if _aiming:
		_pivot_yaw = wrapf(_pivot_yaw - delta.x, -PI, PI)
	else:
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
	camera_pivot.rotation.y = _pivot_yaw

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
	var rate := 18.0 if target < _tp_distance else 9.0
	_tp_distance = lerpf(_tp_distance, target, 1.0 - exp(-rate * delta))
	var ratio := _tp_distance / third_person_distance
	camera.position = Vector3(third_person_shoulder * ratio, 0.0, _tp_distance)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not _is_touch:
		_rotate_look(event.relative * Vector2(mouse_sensitivity, mouse_sensitivity))
	elif event.is_action_pressed("attack"):
		begin_attack()
	elif event.is_action_released("attack"):
		end_attack()

# --- Physique ----------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_melee_cooldown = maxf(0.0, _melee_cooldown - delta)
	# Visée à l'arc : bouton droit (PC) ou visée automatique au tactile quand l'arc est équipé.
	var inventory := InteractionManager.get_inventory()
	var bow_equipped: bool = inventory != null and (inventory.is_equipped("tool_hunting_bow") or inventory.is_equipped(RIFLE))
	_bow_equipped = bow_equipped
	_rifle_cooldown = maxf(0.0, _rifle_cooldown - delta)
	if _drawing:
		if bow_equipped:
			_draw_time += delta
		else:
			_drawing = false
			_draw_time = 0.0
	_update_bow_target()
	# Visée (zoom) : bouton droit sur PC, ou tant que l'arc est bandé.
	_aiming = bow_equipped and (Input.is_action_pressed("aim") or _drawing or _aim_override)
	if _aiming != _last_aiming:
		_last_aiming = _aiming
		if not _aiming and absf(_pivot_yaw) > 0.0001:
			# Fin de visée : le personnage se tourne vers l'endroit visé (la caméra ne
			# revient pas en arrière, on garde le cap choisi au viseur).
			rotate_y(_pivot_yaw)
			_facing_yaw = wrapf(_facing_yaw - _pivot_yaw, -PI, PI)
			_pivot_yaw = 0.0
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
	if _aiming:
		wish = Vector2.ZERO  # en visée, on déplace le viseur, pas le personnage
	if wish.length() > 1.0:
		wish = wish.normalized()
	var wish_len := wish.length()
	var moving := wish_len > 0.001

	var inventory_now := InteractionManager.get_inventory()
	_overloaded = inventory_now != null and inventory_now.has_method("is_overloaded") \
		and bool(inventory_now.call("is_overloaded"))
	_sprinting = moving and _wants_sprint() and not _exhausted and not _drawing and not _overloaded
	_update_stamina(delta)

	var top_speed := sprint_speed if _sprinting else walk_speed
	# Bottes de peau : on marche et on court un peu plus vite.
	if inventory_now != null:
		top_speed *= 1.0 + float(inventory_now.call("worn_stat", "speed"))
	# Poids du sac : au-delà de 60 % de la capacité, on ralentit (jusqu'à -50 %).
	if inventory_now != null and inventory_now.has_method("get_speed_factor"):
		top_speed *= float(inventory_now.call("get_speed_factor"))
	if _mount != null:
		# Compétence Équitation : la monture va un peu plus vite.
		var progression_mount := InteractionManager.get_progression()
		var mount_factor := MOUNT_SPEED_MULTIPLIER
		if progression_mount != null:
			mount_factor *= float(progression_mount.call("equitation_speed_factor"))
		top_speed *= mount_factor
	elif _drawing:
		top_speed *= DRAW_MOVE_FACTOR
	_wading = _is_wading()
	if _wading:
		top_speed *= WADE_SPEED_FACTOR
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
	_update_footsteps()
	if global_position.y < respawn_below_y:
		global_position = _safe_position + Vector3(0.0, 1.0, 0.0)
		velocity = Vector3.ZERO

	if _view_mode == ViewMode.THIRD_PERSON:
		_update_third_person_camera(delta)

## Pas : un son par foulée, selon le sol (sable, herbe, neige, eau) ; sabots à cheval.
const STEP_LENGTH := 0.85
const STRIDE_RUN := 1.25
const HOOF_LENGTH := 1.5
var _step_distance: float = 0.0
var _last_step_position: Vector3 = Vector3.INF

func _update_footsteps() -> void:
	var here := global_position
	if _last_step_position == Vector3.INF or not is_on_floor():
		_last_step_position = here
		return
	var flat := Vector2(here.x - _last_step_position.x, here.z - _last_step_position.z).length()
	_last_step_position = here
	if flat > 3.0:
		# Téléportation (voyage rapide, réapparition) : pas de pas.
		return
	_step_distance += flat
	var stride := HOOF_LENGTH if _mount != null else (STRIDE_RUN if _sprinting else STEP_LENGTH)
	if _step_distance < stride:
		return
	_step_distance = 0.0
	var surface := footstep_surface()
	var sfx := InteractionManager.get_sfx()
	if sfx == null or not sfx.has_method("play_event"):
		return
	if _mount != null:
		# Sabots : pas plus graves et plus appuyés.
		sfx.call("play_event", "step_" + surface, -9.0, randf_range(0.62, 0.72))
	else:
		sfx.call("play_event", "step_" + surface, -15.0 if not _sprinting else -12.0, randf_range(0.92, 1.08))

## Nature du sol sous le joueur : water, snow, grass ou sand.
func footstep_surface() -> String:
	if _wading:
		return "water"
	var weather := InteractionManager.get_weather()
	if weather != null and weather.has_method("get_snow_amount") and float(weather.call("get_snow_amount")) > 0.45:
		return "snow"
	if _landscape_ref != null and is_instance_valid(_landscape_ref) and _landscape_ref.has_method("zone_weights"):
		var weights: Array = _landscape_ref.call("zone_weights", global_position.x, global_position.z)
		if float(weights[1]) + float(weights[3]) > 0.5:
			return "grass"
	return "sand"

## Vrai quand le joueur a les pieds dans la rivière ou un lac.
func is_wading() -> bool:
	return _wading

func _is_wading() -> bool:
	if _landscape_ref == null or not is_instance_valid(_landscape_ref):
		_landscape_ref = get_tree().get_first_node_in_group("landscape") as Node3D
		if _landscape_ref == null or not _landscape_ref.has_method("is_water"):
			_landscape_ref = null
			return false
	var p := global_position
	if not bool(_landscape_ref.call("is_water", p.x, p.z)):
		return false
	return p.y - _mount_lift < float(_landscape_ref.call("water_level_at", p.x)) + 0.5

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
		stamina = maxf(0.0, stamina - stamina_drain * delta * (OVERLOAD_STAMINA_DRAIN if _overloaded else 1.0))
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
	if not _aiming:
		# Hors visée, le pivot caméra revient dans l'axe du personnage.
		_pivot_yaw = lerpf(_pivot_yaw, 0.0, 1.0 - exp(-10.0 * delta))
	_update_camera()
	# Compétence Équitation : XP accumulée en restant à cheval.
	if _mount != null:
		_mount_xp_timer += delta
		if _mount_xp_timer >= 30.0:
			_mount_xp_timer = 0.0
			var progression_ride := InteractionManager.get_progression()
			if progression_ride != null:
				progression_ride.call("add_skill_xp", "equitation", 1)
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	if _view_mode == ViewMode.FIRST_PERSON:
		_update_head_bob(delta, horizontal_speed)
	var fov_target := _base_fov + (sprint_fov_boost if _sprinting and horizontal_speed > walk_speed else 0.0)
	# Portrait (téléphone tenu vertical) : on compense le rétrécissement horizontal.
	var vp := get_viewport().get_visible_rect().size
	if vp.x < vp.y:
		fov_target += portrait_fov_boost
	if _aiming:
		fov_target = aim_fov
	camera.fov = lerpf(camera.fov, fov_target, 1.0 - exp(-12.0 * delta))
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
	# Personnage GLB modulaire (V5), sinon personnage procédural, sinon modèle Mixamo.
	var profile := CharacterProfile.load_saved()
	var loaded := false
	if not use_legacy_hero:
		for script_path in ["res://scripts/player/glb_hero.gd", "res://scripts/player/lowpoly_hero.gd"]:
			hero.set_script(load(script_path))
			hero.set("profile", profile)
			if bool(hero.call("load_model")):
				loaded = true
				break
	if not loaded:
		hero.set_script(load("res://scripts/player/hero_model.gd"))
		if not hero.call("load_model"):
			hero.free()
			return
	if hero.has_method("owns_tools"):
		# Le personnage low-poly porte ses propres outils : les anciens accessoires restent cachés.
		for old_tool: Node3D in [_held_bow, _held_axe]:
			if old_tool != null:
				old_tool.visible = false
		_held_bow = null
		_held_axe = null
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

## En montée, le pied avant retombe plus haut que le sol sous le centre du personnage :
## sans correction il s'enfonce dans la pente. On sonde le sol sous les pieds et on relève
## les visuels juste assez (la collision ne bouge pas).
func _update_foot_lift(delta: float) -> void:
	var wanted := 0.0
	if _mount == null and is_on_floor() and _hero != null:
		if _foot_skeleton == null or not is_instance_valid(_foot_skeleton):
			_foot_bones = PackedInt32Array()
			var skeletons := _hero.find_children("*", "Skeleton3D", true, false)
			if not skeletons.is_empty():
				_foot_skeleton = skeletons[0] as Skeleton3D
				for bone_name in ["mixamorig_LeftToeBase", "mixamorig_RightToeBase", "mixamorig_LeftFoot", "mixamorig_RightFoot"]:
					var bone := _foot_skeleton.find_bone(bone_name)
					if bone >= 0:
						_foot_bones.append(bone)
		if _foot_skeleton != null and not _foot_bones.is_empty():
			var space := get_world_3d().direct_space_state
			for bone in _foot_bones:
				var foot := _foot_skeleton.global_transform * _foot_skeleton.get_bone_global_pose(bone).origin
				# Hauteur du pied sans la surélévation actuelle.
				foot.y -= _foot_lift
				var query := PhysicsRayQueryParameters3D.create(foot + Vector3(0.0, 0.8, 0.0), foot + Vector3(0.0, -0.6, 0.0))
				query.collision_mask = 1
				query.exclude = [get_rid()]
				var hit := space.intersect_ray(query)
				if not hit.is_empty():
					wanted = maxf(wanted, float((hit["position"] as Vector3).y) + FOOT_CLEARANCE - foot.y)
	wanted = clampf(wanted, 0.0, FOOT_LIFT_MAX)
	_foot_lift = move_toward(_foot_lift, wanted, delta * (3.0 if wanted > _foot_lift else 1.5))

func foot_lift() -> float:
	return _foot_lift

func _update_hero(delta: float, horizontal_speed: float, moving: bool) -> void:
	_hero.call("set_riding", _mount != null)
	_hero.call("set_bow", _bow_equipped and (_aiming or _drawing), get_draw_charge())
	_hero.call("set_vertical_speed", velocity.y)
	_hero.call("update_motion", horizontal_speed, moving, is_on_floor())
	_hero.call("advance_poses", delta)
	if _hero.has_method("owns_tools"):
		_update_hero_gear()
		if _attack_anim > 0.0:
			_attack_anim = maxf(0.0, _attack_anim - delta)
		return
	var hand: Transform3D = _hero.call("hand_transform")
	if _held_bow != null:
		var bow_transform := hand * held_bow_offset
		var aim_weight: float = _hero.call("get_aim_weight")
		if aim_weight > 0.01:
			# Bras tendu : l'arc se redresse à la verticale, ventre vers la cible.
			var forward := _hero.global_basis.z.normalized()
			var upright := Basis(forward, Vector3.UP, forward.cross(Vector3.UP)).orthonormalized()
			bow_transform.basis = bow_transform.basis.orthonormalized().slerp(upright, aim_weight)
		_held_bow.global_transform = bow_transform
	if _held_axe != null:
		_held_axe.global_transform = hand * held_axe_offset
	if _attack_anim > 0.0:
		_attack_anim = maxf(0.0, _attack_anim - delta)

## Outil tenu et vêtements portés, d'après le sac (le personnage low-poly les dessine lui-même).
func _update_hero_gear() -> void:
	var inventory := InteractionManager.get_inventory()
	if inventory == null:
		return
	_hero.call("set_held_tool", String(inventory.call("get_equipped")))
	_hero.call("set_gear", inventory.call("get_worn"))

## Applique une nouvelle apparence (écran de personnalisation).
func apply_character_profile(profile: CharacterProfile) -> void:
	if _hero != null and _hero.has_method("set_profile"):
		_hero.call("set_profile", profile)

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
	if _drawing or _aiming:
		# Arc bandé ou en visée : le personnage fait face au viseur (qui peut tourner seul).
		_facing_yaw = lerp_angle(_facing_yaw, _pivot_yaw, 1.0 - exp(-14.0 * delta))
	elif moving:
		var local := transform.basis.inverse() * Vector3(velocity.x, 0.0, velocity.z)
		_facing_yaw = lerp_angle(_facing_yaw, atan2(-local.x, -local.z), 1.0 - exp(-12.0 * delta))
	else:
		_facing_yaw = lerp_angle(_facing_yaw, 0.0, 1.0 - exp(-3.0 * delta))
	var lean := clampf(horizontal_speed / sprint_speed, 0.0, 1.0) * (0.14 if _sprinting else 0.05)
	if _hero != null:
		# Le geste du bras est joué par le modèle ; le corps accompagne à peine.
		if _attack_anim > 0.0:
			lean += 0.12 * sin((1.0 - _attack_anim / ATTACK_ANIM_TIME) * PI)
		visuals.rotation = Vector3(lean, _visuals_base_yaw + _facing_yaw, 0.0)
		_update_foot_lift(delta)
		visuals.position.y = _mount_lift + _foot_lift
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
