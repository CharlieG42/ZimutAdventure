extends "res://scripts/player/lowpoly_hero.gd"
## Personnage GLB modulaire (homme / femme, modèles V5 dans assets/characters) : un squelette
## Mixamo commun, des pièces séparées (corps, cheveux, vêtements, accessoires) que l'on affiche
## ou masque, et des matériaux nommés recolorés d'après CharacterProfile.
## Même interface que LowpolyHero (hérité) : les poses sont posées os par os chaque image,
## par-dessus la pose de repos (bras le long du corps), avec les couches de HeroPoseLayer
## (repos, saut, cheval, arc, hache). Le héros procédural reste le plan B si le GLB manque.

const MODELS := {
	"male": "res://assets/characters/zimut_male.glb",
	"female": "res://assets/characters/zimut_female.glb",
}
const SHIRT_COLOR := Color(0.86, 0.8, 0.66)
const TROUSERS_COLOR := Color(0.3, 0.23, 0.17)
const GLOVES_COLOR := Color(0.42, 0.27, 0.15)
const FEMALE_LEGS := "res://assets/characters/zimut_female_legs.glb"
const HEIGHTS := {"male": 1.86, "female": 1.75}

## Coiffures : nom de profil -> pièces du GLB (par genre).
const HAIR := {
	"male": {
		"short": ["Hair_Short"], "long": ["Hair_Long_Male"], "ponytail": ["Hair_Tied"],
		"bun": ["Hair_Topknot_Male"], "bald": [], "curly": ["Hair_Swept_Male"], "braid": ["Hair_Tied"],
	},
	"female": {
		"short": ["Female_Hair_Bob", "Female_Hair_Bob_Sides"],
		"long": ["Female_Hair_Long_Cap", "Female_Hair_Long_Mass", "Female_Hair_Long_Back", "Female_Hair_Long_SideLocks"],
		"ponytail": ["Female_Hair_Long_Cap", "Female_Hair_Long_Back"],
		"bun": ["Female_Hair_Long_Cap", "Female_Hair_Bun"],
		"bald": [],
		"curly": ["Female_Hair_Long_Cap", "Female_Hair_Long_Mass", "Female_Hair_Long_SideLocks"],
		"braid": ["Female_Hair_Long_Cap", "Female_Hair_Braid"],
	},
}
const CLOTHES := {
	"male": ["Tunic", "Pants"],
	"female": ["Female_Dress_Bodice", "Female_Dress_Skirt", "Female_Dress_Sleeves"],
}
const ALWAYS := ["Body_Head", "Body_Neck", "Body_Hands", "Face_Nose", "Face_Mouth", "Eyes_Brown"]
const GEAR_PARTS := {
	"gear_straw_hat": ["Straw_Hat_Brim", "Straw_Hat_Crown"],
	"gear_hide_boots": ["High_Boots"],
	"gear_backpack": ["Backpack", "Backpack_Flap"],
	# Chemise, pantalon et gants : pas de maillage dédié, ils changent les couleurs (voir _color_for).
	"gear_wool_shirt": [],
	"gear_wool_trousers": [],
	"gear_leather_gloves": [],
	"armor_fur_cloak": ["Fur_Cape", "Fur_Cape_Collar", "Fur_Cape_Sides"],
}

## Surcouche de poses : même noms d'os Mixamo, mais le gauche / droit du GLB peut être inversé.
class GlbPoseLayer extends HeroPoseLayer:
	var mirrored: bool = false

	func _cache_bones() -> void:
		_ids.clear()
		var skeleton := get_skeleton()
		if skeleton == null:
			return
		for bone: String in BONES:
			var name_in_file := bone
			if mirrored:
				if bone.begins_with("Left"):
					name_in_file = "Right" + bone.substr(4)
				elif bone.begins_with("Right"):
					name_in_file = "Left" + bone.substr(5)
			_ids[bone] = skeleton.find_bone(PREFIX + name_in_file)

var skeleton: Skeleton3D
var _layer: GlbPoseLayer
var _hand_frame: Node3D
var _mat_cache := {}
var _parts := {}   # nom de nœud -> MeshInstance3D
var _model_gender: String = ""

# --- Construction ---------------------------------------------------------------------------

func rebuild() -> void:
	if _rig != null:
		_rig.free()
		_rig = null
		skeleton = null
		_parts.clear()
		_mat_cache.clear()
		_arm = {}
		_held = null
	var path: String = MODELS.get(profile.gender, MODELS["male"])
	var packed := load(path) as PackedScene if ResourceLoader.exists(path) else null
	if packed == null:
		return
	var model := packed.instantiate() as Node3D
	var sk := model.find_child("Skeleton3D", true, false) as Skeleton3D if model != null else null
	if sk == null or sk.find_bone("mixamorig_RightHand") < 0:
		if model != null:
			model.free()
		return
	_rig = Node3D.new()
	_rig.name = "GlbRig"
	add_child(_rig)
	_rig.add_child(model)
	skeleton = sk
	_model_gender = profile.gender
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		_parts[mesh.name] = mesh
	if profile.gender == "female":
		_add_female_legs()
	# Le côté « droit » du GLB est-il bien à droite du personnage (-X) ?
	var right_hand := skeleton.find_bone("mixamorig_RightHand")
	var mirrored := skeleton.get_bone_global_rest(right_hand).origin.x > 0.0
	_layer = GlbPoseLayer.new()
	_layer.mirrored = mirrored
	_layer.active = false
	_layer.name = "PoseLayer"
	skeleton.add_child(_layer)
	_layer._cache_bones()
	_hand_frame = Node3D.new()
	_hand_frame.name = "HandFrame"
	add_child(_hand_frame)
	_arm = {"r": {"hand": _hand_frame}}
	_hip_height = skeleton.get_bone_global_rest(skeleton.find_bone("mixamorig_Hips")).origin.y
	_apply_profile()
	_build_held()
	_pose(-1.0)

## Les jambes nues sous la robe : on emprunte les mollets du fichier « corps nu » (même squelette).
func _add_female_legs() -> void:
	var packed := load(FEMALE_LEGS) as PackedScene if ResourceLoader.exists(FEMALE_LEGS) else null
	if packed == null:
		return
	var donor := packed.instantiate() as Node3D
	var legs := donor.find_child("Body_LowerLegs", true, false) as MeshInstance3D
	if legs != null:
		legs.get_parent().remove_child(legs)
		legs.owner = null
		skeleton.add_child(legs)
		legs.skeleton = NodePath("..")
		_parts["Body_LowerLegs"] = legs
	donor.free()

func set_profile(new_profile: CharacterProfile) -> void:
	var regender := new_profile.gender != _model_gender
	profile = new_profile
	if regender or _rig == null:
		rebuild()
	else:
		_apply_profile()

func set_gear(items: Array) -> void:
	var worn: Array = []
	for id in GEAR_IDS:
		if items.has(id):
			worn.append(id)
	if worn == gear:
		return
	gear = worn
	_apply_profile()

func body_height() -> float:
	return float(HEIGHTS.get(profile.gender, 1.8))

# --- Apparence ---------------------------------------------------------------------------------

func _apply_profile() -> void:
	if _rig == null:
		return
	var shown := {}
	for n in ALWAYS:
		shown[n] = true
	for n in CLOTHES.get(profile.gender, []):
		shown[n] = true
	var boots := gear.has("gear_hide_boots")
	# Les bottes du modèle n'ont pas de pied (tige de 10 à 59 cm) : on garde les chaussures
	# dessous, sinon les jambes semblent coupées au-dessus de la cheville.
	shown["Shoes"] = true
	if boots:
		shown["High_Boots"] = true
	if profile.gender == "female" and gear.has("gear_wool_trousers"):
		shown["Female_Trousers"] = true
	elif profile.gender == "female" and not boots:
		shown["Body_LowerLegs"] = true
	for n in HAIR[profile.gender].get(profile.hair_style_name(), []):
		shown[n] = true
	if profile.gender == "male" and profile.beard_name() != "none":
		shown["Beard"] = true
	for id in gear:
		for n in GEAR_PARTS.get(id, []):
			shown[n] = true
	if gear.has("gear_straw_hat"):
		# Le chapeau coiffe la tête : le chignon et la queue dépasseraient.
		for n in ["Hair_Topknot_Male", "Female_Hair_Bun"]:
			shown.erase(n)
	for part_name: String in _parts:
		var mesh := _parts[part_name] as MeshInstance3D
		mesh.visible = shown.has(part_name)
		if mesh.visible:
			_recolor(mesh)

func _recolor(mesh: MeshInstance3D) -> void:
	if mesh.mesh == null:
		return
	for s in mesh.mesh.get_surface_count():
		var base := mesh.mesh.surface_get_material(s)
		if base == null:
			continue
		var key := String(base.resource_name)
		var color := _color_for(key)
		# Gants de cuir : les mains prennent une matière à part (la peau du visage ne change pas).
		if mesh.name == "Body_Hands" and gear.has("gear_leather_gloves") and key == "skin":
			key = "gloves"
			color = GLOVES_COLOR
		if not _mat_cache.has(key):
			var copy := base.duplicate() as StandardMaterial3D
			if copy == null:
				continue
			_mat_cache[key] = copy
		var mat := _mat_cache[key] as StandardMaterial3D
		if color.a > 0.0:
			mat.albedo_color = color
		mesh.set_surface_override_material(s, mat)

## Couleur du profil pour un matériau du GLB (alpha 0 : on garde la couleur d'origine).
func _color_for(material_name: String) -> Color:
	match material_name:
		"skin":
			return profile.skin_color()
		"hair":
			return profile.hair_color_value()
		"tunic", "dress", "tunic_alt":
			return SHIRT_COLOR if gear.has("gear_wool_shirt") else profile.tunic_color()
		"pants":
			return TROUSERS_COLOR if gear.has("gear_wool_trousers") else profile.pants_color()
		"eyes_brown":
			return profile.eye_color()
		_:
			return Color(0, 0, 0, 0)

# --- Poses -------------------------------------------------------------------------------------

## Remplace la pose du héros procédural : marche / course posées os par os, puis couches.
func _pose(chop: float) -> void:
	if skeleton == null or _layer == null:
		return
	if _layer._ids.is_empty():
		_layer._cache_bones()
	skeleton.reset_bone_poses()
	var w := _walk_w
	var run := _run_w
	var s := sin(_phase)
	var c := cos(_phase)
	var amp := lerpf(0.55, 0.95, run) * w
	var knee_amp := lerpf(0.75, 1.5, run) * w
	var arm_amp := lerpf(0.5, 0.95, run) * w
	var breathe := sin(_time * 1.9) * (1.0 - w)
	# Pose de base : le GLB est en T, on baisse les bras.
	for side in ["Left", "Right"]:
		var out := 1.0 if side == "Left" else -1.0
		_layer._turn(skeleton, side + "Arm", Vector3.BACK, -out * (1.38 - 0.06 - 0.02 * breathe))
	# Bassin, buste, tête.
	var hips_id: int = _layer._ids.get("Hips", -1)
	if hips_id >= 0:
		var hips_pose := skeleton.get_bone_global_pose(hips_id)
		hips_pose.origin.y -= (0.035 + 0.03 * run) * absf(s) * w + _ride_w * 0.18
		skeleton.set_bone_global_pose(hips_id, hips_pose)
	_layer._turn(skeleton, "Hips", Vector3.UP, -s * 0.1 * w)
	var lean := lerpf(0.0, 0.3, run) * w
	for spine in ["Spine", "Spine1", "Spine2"]:
		_layer._turn(skeleton, spine, Vector3.RIGHT, lean / 3.0)
		_layer._turn(skeleton, spine, Vector3.UP, s * 0.14 * w / 3.0)
	_layer._turn(skeleton, "Head", Vector3.RIGHT, -lean * 0.6)
	# Jambes.
	for side in ["Left", "Right"]:
		var sign_side := 1.0 if side == "Left" else -1.0
		var thigh_x := -s * amp * sign_side
		var knee_x := knee_amp * maxf(0.0, c * sign_side) + 0.04
		_layer._turn(skeleton, side + "UpLeg", Vector3.RIGHT, thigh_x)
		_layer._turn(skeleton, side + "Leg", Vector3.RIGHT, knee_x)
		var toe_off := 0.35 * maxf(0.0, sin(_phase * sign_side + 0.6)) * w * (1.0 - _air_w)
		_layer._turn(skeleton, side + "Foot", Vector3.RIGHT, clampf(-(thigh_x + knee_x) * 0.85 + toe_off, -0.7, 0.9))
	# Bras : balancier de marche, coudes pliés.
	for side in ["Left", "Right"]:
		var sign_side := 1.0 if side == "Left" else -1.0
		_layer._turn(skeleton, side + "Arm", Vector3.RIGHT, s * arm_amp * sign_side)
		_layer._turn(skeleton, side + "ForeArm", Vector3.RIGHT, -(0.12 + lerpf(0.15, 1.15, run) * w) - 0.05 * (1.0 - w))
	# Couches : respiration, saut, cheval, arc, hache.
	_layer.run = 0.0
	_layer.idle = clampf(1.0 - w - _air_w, 0.0, 1.0)
	_layer.air = _air_w
	_layer.air_rise = _rise
	_layer.ride = _ride_w
	_layer.aim = _aim_w
	_layer.draw = _draw
	_layer.chop = chop
	_layer.time = _time
	_layer._process_modification()
	_update_hand_frame()

## Os Mixamo par son nom « logique » (le gauche / droit du fichier peut être inversé).
func _bone_id(bone: String) -> int:
	var name_in_file := bone
	if _layer != null and _layer.mirrored:
		if bone.begins_with("Left"):
			name_in_file = "Right" + bone.substr(4)
		elif bone.begins_with("Right"):
			name_in_file = "Left" + bone.substr(5)
	return skeleton.find_bone("mixamorig_" + name_in_file)

## Place le repère de la main droite : Y le long du bras vers l'épaule, X vers la gauche du
## personnage (les outils sont modelés dans ce repère, comme sur le héros procédural).
func _update_hand_frame() -> void:
	var hand_id := _bone_id("RightHand")
	var fore_id := _bone_id("RightForeArm")
	if hand_id < 0 or fore_id < 0 or _hand_frame == null or not _hand_frame.is_inside_tree():
		return
	var hand := skeleton.global_transform * skeleton.get_bone_global_pose(hand_id)
	var fore := skeleton.global_transform * skeleton.get_bone_global_pose(fore_id)
	var y := (fore.origin - hand.origin).normalized()
	var x := global_basis.x - y * global_basis.x.dot(y)
	if x.length() < 0.001:
		return
	x = x.normalized()
	var z := x.cross(y).normalized()
	_hand_frame.global_transform = Transform3D(Basis(x, y, z), hand.origin)

func _pose_held() -> void:
	if _held == null or not is_instance_valid(_held):
		return
	if held_tool == "tool_hunting_bow" and _hand_frame != null and _hand_frame.is_inside_tree():
		# L'arc reste droit dans l'espace du personnage : penché au repos, vertical en visée.
		var basis_hero := global_basis * Basis(Vector3.RIGHT, lerpf(0.55, 0.0, _aim_w))
		_held.global_transform = Transform3D(basis_hero, _hand_frame.global_position + basis_hero * Vector3(0, -0.03, 0.04))
		return
	super._pose_held()

func hand_transform() -> Transform3D:
	if _hand_frame == null or not _hand_frame.is_inside_tree():
		return global_transform
	return _hand_frame.global_transform
