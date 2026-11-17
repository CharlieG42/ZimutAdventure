extends Node3D
## Personnage animé du joueur (modèle rigué Mixamo, voir assets/characters).
## Une seule animation de marche : elle est lue à une vitesse proportionnelle à
## celle du joueur et, à l'arrêt, elle se fige quand les pieds sont joints.
## Le reste (respiration, course, saut, hache, arc, cheval) est ajouté par des poses
## procédurales : voir HeroPoseLayer.

const MODEL_PATH := "res://assets/characters/hero.glb"
const WALK := "walk"
const HAND_BONE := "mixamorig_RightHand"
## Instants de la boucle où les deux pieds sont à la même hauteur (mesurés sur l'animation).
const REST_TIMES: Array[float] = [0.012, 0.532]
## Vitesse (m/s) à laquelle la marche s'anime à vitesse normale, sans glissement des pieds.
const STRIDE_SPEED := 2.6
const MIN_SPEED_SCALE := 0.5
const MAX_SPEED_SCALE := 2.4
## Vitesses (m/s) entre lesquelles la marche devient une course.
const RUN_START := 4.9
const RUN_FULL := 7.4
## Durée du geste de hache (secondes).
const CHOP_TIME := 0.42

var animation_player: AnimationPlayer
var skeleton: Skeleton3D
var hand_attachment: BoneAttachment3D
var pose_layer: HeroPoseLayer

var _run_target: float = 0.0
var _idle_target: float = 0.0
var _air_target: float = 0.0
var _ride_target: float = 0.0
var _aim_target: float = 0.0
var _draw_target: float = 0.0
var _rise_target: float = 0.0
var _chop_left: float = 0.0

var _prev_pos: float = 0.0
var _settling: bool = false

## Charge le modèle ; renvoie false (rien n'est ajouté) s'il manque ou est invalide.
func load_model() -> bool:
	if not ResourceLoader.exists(MODEL_PATH):
		return false
	var packed := load(MODEL_PATH) as PackedScene
	if packed == null:
		return false
	var model := packed.instantiate() as Node3D
	if model == null:
		return false
	animation_player = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	skeleton = model.find_child("Skeleton3D", true, false) as Skeleton3D
	if animation_player == null or skeleton == null or not animation_player.has_animation(WALK):
		model.free()
		animation_player = null
		skeleton = null
		return false
	add_child(model)
	animation_player.get_animation(WALK).loop_mode = Animation.LOOP_LINEAR
	animation_player.play(WALK)
	animation_player.seek(REST_TIMES[0], true)
	animation_player.pause()
	_prev_pos = REST_TIMES[0]
	if skeleton.find_bone(HAND_BONE) >= 0:
		hand_attachment = BoneAttachment3D.new()
		hand_attachment.bone_name = HAND_BONE
		skeleton.add_child(hand_attachment)
	pose_layer = HeroPoseLayer.new()
	pose_layer.name = "PoseLayer"
	skeleton.add_child(pose_layer)
	return true

## Lance le geste de coup de hache.
func play_chop() -> void:
	_chop_left = CHOP_TIME

func is_chopping() -> bool:
	return _chop_left > 0.0

## Arc : `aiming` lève l'arc, `charge` (0 à 1) tend la corde.
func set_bow(aiming: bool, charge: float) -> void:
	_aim_target = 1.0 if aiming else 0.0
	_draw_target = clampf(charge, 0.0, 1.0)

## Poids de la pose de visée (0 à 1) : sert à redresser l'arc dans la main.
func get_aim_weight() -> float:
	return pose_layer.aim if pose_layer != null else 0.0

func set_riding(riding: bool) -> void:
	_ride_target = 1.0 if riding else 0.0

## Vitesse verticale (m/s) : ouvre la pose de saut à la retombée.
func set_vertical_speed(vy: float) -> void:
	_rise_target = clampf(vy / 5.0, -1.0, 1.0)

## Fait avancer les poses procédurales (fondu entre les couches).
func advance_poses(delta: float) -> void:
	if pose_layer == null:
		return
	var fast := 1.0 - exp(-12.0 * delta)
	var slow := 1.0 - exp(-5.0 * delta)
	pose_layer.time += delta
	pose_layer.run = lerpf(pose_layer.run, _run_target, fast)
	pose_layer.idle = lerpf(pose_layer.idle, _idle_target, slow)
	pose_layer.air = lerpf(pose_layer.air, _air_target, fast)
	pose_layer.air_rise = lerpf(pose_layer.air_rise, _rise_target, fast)
	pose_layer.ride = lerpf(pose_layer.ride, _ride_target, fast)
	pose_layer.aim = lerpf(pose_layer.aim, _aim_target, 1.0 - exp(-16.0 * delta))
	pose_layer.draw = lerpf(pose_layer.draw, _draw_target, 1.0 - exp(-20.0 * delta))
	if _chop_left > 0.0:
		_chop_left = maxf(0.0, _chop_left - delta)
		pose_layer.chop = 1.0 - _chop_left / CHOP_TIME if _chop_left > 0.0 else -1.0
	else:
		pose_layer.chop = -1.0

## Position de la main droite sans l'échelle ×100 du modèle (pour poser un outil).
func hand_transform() -> Transform3D:
	if hand_attachment == null:
		return global_transform
	var t := hand_attachment.global_transform
	t.basis = t.basis.orthonormalized()
	return t

## `speed` : vitesse horizontale en m/s. `grounded` : le joueur touche le sol.
func update_motion(speed: float, moving: bool, grounded: bool) -> void:
	if animation_player == null:
		return
	var riding := _ride_target > 0.5
	_air_target = 0.0 if (grounded or riding) else 1.0
	_run_target = smoothstep(RUN_START, RUN_FULL, speed) if (moving and grounded and not riding) else 0.0
	_idle_target = 1.0 if (grounded and not moving) or riding else 0.0
	if riding:
		# En selle : les jambes ne marchent pas, la pose de repos sert de base.
		if animation_player.is_playing():
			animation_player.seek(REST_TIMES[0], true)
			animation_player.pause()
			_prev_pos = REST_TIMES[0]
		return
	if moving and grounded:
		_settling = false
		animation_player.speed_scale = clampf(speed / STRIDE_SPEED, MIN_SPEED_SCALE, MAX_SPEED_SCALE)
		if not animation_player.is_playing():
			animation_player.play()
		_prev_pos = animation_player.current_animation_position
		return
	if not grounded:
		# En l'air : la pose est figée (pas de pas dans le vide).
		if animation_player.is_playing():
			animation_player.pause()
		return
	# À l'arrêt : on laisse finir le pas jusqu'aux pieds joints, puis on fige.
	if not animation_player.is_playing():
		if is_resting():
			return
		animation_player.speed_scale = 1.2
		animation_player.play()
	var pos := animation_player.current_animation_position
	for rest_time in REST_TIMES:
		if _crossed(_prev_pos, pos, rest_time):
			animation_player.seek(rest_time, true)
			animation_player.pause()
			pos = rest_time
			break
	_prev_pos = pos

## Vrai quand l'animation est figée sur une pose pieds joints.
func is_resting() -> bool:
	if animation_player == null or animation_player.is_playing():
		return false
	var pos := animation_player.current_animation_position
	for rest_time in REST_TIMES:
		if absf(pos - rest_time) < 0.01:
			return true
	return false

static func _crossed(prev: float, now: float, mark: float) -> bool:
	if now >= prev:
		return prev < mark and mark <= now
	# La boucle vient de repartir à zéro.
	return mark > prev or mark <= now
