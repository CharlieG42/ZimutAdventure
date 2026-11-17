class_name HeroPoseLayer
extends SkeletonModifier3D
## Poses procédurales superposées à l'animation de marche du personnage rigué (Mixamo) :
## respiration au repos, course, saut, coup de hache, tir à l'arc, monte à cheval.
## Le modèle ne contient qu'une boucle de marche ; ces couches évitent d'attendre d'autres
## fichiers d'animation. Toutes les rotations sont exprimées dans le repère du squelette
## (X = gauche du personnage, Y = haut, Z = devant) : indépendant de l'axe propre des os.

const PREFIX := "mixamorig_"
const BONES := ["Hips", "Spine", "Spine1", "Spine2", "Neck", "Head",
		"LeftShoulder", "LeftArm", "LeftForeArm", "RightShoulder", "RightArm", "RightForeArm",
		"LeftUpLeg", "LeftLeg", "LeftFoot", "RightUpLeg", "RightLeg", "RightFoot"]

## Poids des couches (0 à 1), lissés par HeroModel.
var idle: float = 0.0
var run: float = 0.0
var air: float = 0.0
## Vitesse verticale normalisée (-1 = chute, 1 = montée) : module la pose en l'air.
var air_rise: float = 0.0
var ride: float = 0.0
## Arc : 0 = bras baissé, 1 = arc levé ; `draw` = tension de la corde.
var aim: float = 0.0
var draw: float = 0.0
## Coup de hache : avancement du geste (0 à 1), -1 = pas de coup.
var chop: float = -1.0
## Horloge propre (respiration).
var time: float = 0.0

var _ids: Dictionary = {}

func _ready() -> void:
	_cache_bones()

func _cache_bones() -> void:
	_ids.clear()
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	for bone in BONES:
		_ids[bone] = skeleton.find_bone(PREFIX + bone)

## Vrai si une couche modifie la pose (utile aux tests).
func is_posing() -> bool:
	return idle > 0.001 or run > 0.001 or air > 0.001 or ride > 0.001 or aim > 0.001 or chop >= 0.0

func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	if _ids.is_empty():
		_cache_bones()
	if run > 0.001 and ride < 0.5:
		_apply_run(skeleton)
	if idle > 0.001:
		_apply_idle(skeleton)
	if air > 0.001:
		_apply_air(skeleton)
	if ride > 0.001:
		_apply_ride(skeleton)
	if aim > 0.001:
		_apply_bow(skeleton)
	if chop >= 0.0:
		_apply_chop(skeleton)

# --- Couches --------------------------------------------------------------------------

## Respiration et léger balancement : le personnage ne reste jamais figé comme une statue.
func _apply_idle(skeleton: Skeleton3D) -> void:
	var breath := sin(time * 1.7)
	var sway := sin(time * 0.6)
	_turn(skeleton, "Spine1", Vector3.RIGHT, (0.018 * breath - 0.01) * idle)
	_turn(skeleton, "Spine2", Vector3.RIGHT, 0.014 * breath * idle)
	_turn(skeleton, "Spine", Vector3.BACK, 0.012 * sway * idle)
	_turn(skeleton, "Head", Vector3.UP, 0.09 * sin(time * 0.37) * idle)
	_turn(skeleton, "Head", Vector3.RIGHT, -0.02 * breath * idle)
	_turn(skeleton, "LeftArm", Vector3.BACK, 0.02 * breath * idle)
	_turn(skeleton, "RightArm", Vector3.BACK, -0.02 * breath * idle)

## Course : buste penché, coudes pliés, balancement des bras et foulée amplifiés.
func _apply_run(skeleton: Skeleton3D) -> void:
	_turn(skeleton, "Spine", Vector3.RIGHT, 0.10 * run)
	_turn(skeleton, "Spine2", Vector3.RIGHT, 0.08 * run)
	_turn(skeleton, "Head", Vector3.RIGHT, -0.12 * run)
	for side in ["Left", "Right"]:
		# Amplifie l'angle avant/arrière déjà donné par la marche (reste synchronisé).
		var arm_pitch := _limb_pitch(skeleton, side + "Arm", side + "ForeArm")
		_turn(skeleton, side + "Arm", Vector3.RIGHT, -arm_pitch * 0.9 * run)
		_turn(skeleton, side + "ForeArm", Vector3.RIGHT, -1.15 * run)
		var leg_pitch := _limb_pitch(skeleton, side + "UpLeg", side + "Leg")
		_turn(skeleton, side + "UpLeg", Vector3.RIGHT, -leg_pitch * 0.3 * run)
		# Le genou se plie davantage quand la jambe revient vers l'avant.
		_turn(skeleton, side + "Leg", Vector3.RIGHT, maxf(leg_pitch, 0.0) * 0.5 * run)

## En l'air : bras écartés, une jambe repliée ; la pose s'ouvre à la retombée.
func _apply_air(skeleton: Skeleton3D) -> void:
	var fall := clampf(-air_rise, 0.0, 1.0)
	var rise := clampf(air_rise, 0.0, 1.0)
	_turn(skeleton, "Spine1", Vector3.RIGHT, (0.10 * rise - 0.06 * fall) * air)
	_turn(skeleton, "LeftArm", Vector3.BACK, (0.45 + 0.5 * fall) * air)
	_turn(skeleton, "RightArm", Vector3.BACK, -(0.45 + 0.5 * fall) * air)
	_turn(skeleton, "LeftArm", Vector3.RIGHT, -0.35 * rise * air)
	_turn(skeleton, "RightArm", Vector3.RIGHT, 0.25 * rise * air)
	_turn(skeleton, "LeftForeArm", Vector3.RIGHT, -0.5 * air)
	_turn(skeleton, "RightForeArm", Vector3.RIGHT, -0.5 * air)
	_turn(skeleton, "LeftUpLeg", Vector3.RIGHT, -(0.75 * rise + 0.3) * air)
	_turn(skeleton, "LeftLeg", Vector3.RIGHT, (1.1 * rise + 0.45) * air)
	_turn(skeleton, "RightUpLeg", Vector3.RIGHT, (0.25 * rise - 0.15 * fall) * air)
	_turn(skeleton, "RightLeg", Vector3.RIGHT, (0.35 + 0.2 * fall) * air)

## À cheval : cuisses écartées vers l'avant, genoux pliés, mains aux rênes.
func _apply_ride(skeleton: Skeleton3D) -> void:
	for side in ["Left", "Right"]:
		var out := 1.0 if side == "Left" else -1.0
		var leg_pitch := _limb_pitch(skeleton, side + "UpLeg", side + "Leg")
		_turn(skeleton, side + "UpLeg", Vector3.RIGHT, (-leg_pitch - 0.62) * ride)
		_turn(skeleton, side + "UpLeg", Vector3.BACK, 0.55 * out * ride)
		_turn(skeleton, side + "Leg", Vector3.RIGHT, 0.8 * ride)
		var arm_pitch := _limb_pitch(skeleton, side + "Arm", side + "ForeArm")
		_turn(skeleton, side + "Arm", Vector3.RIGHT, (-arm_pitch - 0.35) * ride)
		_turn(skeleton, side + "ForeArm", Vector3.RIGHT, -0.95 * ride)

## Arc tenu dans la main droite : le bras droit se tend vers la cible, le buste se met
## de profil et la main gauche ramène la corde vers la joue.
func _apply_bow(skeleton: Skeleton3D) -> void:
	_turn(skeleton, "Spine1", Vector3.UP, -0.28 * aim)
	_turn(skeleton, "Spine2", Vector3.UP, -0.28 * aim)
	_turn(skeleton, "Head", Vector3.UP, 0.5 * aim)
	# Bras de l'arc : annule le balancement de la marche puis se lève à l'horizontale.
	var bow_pitch := _limb_pitch(skeleton, "RightArm", "RightForeArm")
	_turn(skeleton, "RightArm", Vector3.RIGHT, (-bow_pitch - 1.45) * aim)
	_turn(skeleton, "RightArm", Vector3.UP, 0.42 * aim)
	# Bras de la corde : levé devant la poitrine, coude plié d'autant plus que l'arc est bandé.
	var string_pitch := _limb_pitch(skeleton, "LeftArm", "LeftForeArm")
	_turn(skeleton, "LeftArm", Vector3.RIGHT, (-string_pitch - 1.35) * aim)
	_turn(skeleton, "LeftArm", Vector3.UP, (0.25 + 0.85 * draw) * aim)
	_turn(skeleton, "LeftForeArm", Vector3.UP, -(0.9 + 1.5 * draw) * aim)

## Coup de hache : le bras droit s'arme au-dessus de l'épaule puis s'abat, le buste suit.
func _apply_chop(skeleton: Skeleton3D) -> void:
	var wind := smoothstep(0.0, 0.35, chop) * (1.0 - smoothstep(0.35, 0.62, chop))
	var strike := smoothstep(0.35, 0.62, chop) * (1.0 - smoothstep(0.72, 1.0, chop))
	_turn(skeleton, "Spine1", Vector3.UP, 0.3 * wind - 0.25 * strike)
	_turn(skeleton, "Spine2", Vector3.RIGHT, -0.12 * wind + 0.3 * strike)
	var pitch := _limb_pitch(skeleton, "RightArm", "RightForeArm")
	var weight := maxf(wind, strike)
	_turn(skeleton, "RightArm", Vector3.RIGHT, -pitch * weight - 2.45 * wind - 1.15 * strike)
	_turn(skeleton, "RightForeArm", Vector3.RIGHT, -0.75 * wind - 0.15 * strike)

# --- Outils ---------------------------------------------------------------------------

## Angle avant/arrière d'un membre (0 = pend à la verticale, positif = vers l'avant).
func _limb_pitch(skeleton: Skeleton3D, upper: String, lower: String) -> float:
	var a: int = _ids.get(upper, -1)
	var b: int = _ids.get(lower, -1)
	if a < 0 or b < 0:
		return 0.0
	var dir := skeleton.get_bone_global_pose(b).origin - skeleton.get_bone_global_pose(a).origin
	return atan2(dir.z, -dir.y)

## Tourne un os (et ses descendants) autour d'un axe du repère du squelette.
func _turn(skeleton: Skeleton3D, bone: String, axis: Vector3, angle: float) -> void:
	var id: int = _ids.get(bone, -1)
	if id < 0 or absf(angle) < 0.0001:
		return
	var pose := skeleton.get_bone_global_pose(id)
	pose.basis = Basis(axis, angle) * pose.basis
	skeleton.set_bone_global_pose(id, pose)
