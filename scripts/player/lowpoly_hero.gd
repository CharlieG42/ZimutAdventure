extends Node3D
## Personnage low-poly du joueur (homme ou femme), construit en code : pièces facettées
## articulées par des pivots, animées ici (marche, course, saut, hache, arc, cheval).
## Même interface que HeroModel pour que player.gd l'utilise tel quel. Regarde vers +Z.
## L'apparence vient de CharacterProfile ; les vêtements (chapeau, bottes, sac, cape)
## apparaissent selon les objets fabriqués (`set_gear`).

const CHOP_TIME := 0.42
const STRIDE_SPEED := 2.6
const RUN_START := 4.9
const RUN_FULL := 7.4
const GEAR_IDS := ["gear_straw_hat", "gear_hide_boots", "gear_backpack", "armor_fur_cloak", "gear_wool_shirt", "gear_wool_trousers", "gear_leather_gloves"]

var profile: CharacterProfile = CharacterProfile.default_for("male")
var gear: Array = []
var held_tool: String = ""

var _rig: Node3D
var _hips: Node3D
var _torso: Node3D
var _head: Node3D
var _arm := {}   # "l"/"r" -> {"shoulder", "elbow", "hand"}
var _leg := {}   # "l"/"r" -> {"hip", "knee"}
var _held: Node3D
var _skirt: Node3D
var _eyelids: Array = []
var _sway: Array = []
var _blink_left: float = 0.0
var _next_blink: float = 2.5
var _hip_height: float = 0.9
var _materials := {}

var _phase: float = 0.0
var _speed: float = 0.0
var _moving: bool = false
var _grounded: bool = true
var _walk_w: float = 0.0
var _run_w: float = 0.0
var _air_w: float = 0.0
var _rise: float = 0.0
var _ride_w: float = 0.0
var _aim_w: float = 0.0
var _draw: float = 0.0
var _aim_target: float = 0.0
var _draw_target: float = 0.0
var _ride_target: float = 0.0
var _chop_left: float = 0.0
var _time: float = 0.0

# --- Interface commune avec HeroModel ---------------------------------------------------

func load_model() -> bool:
	rebuild()
	return _rig != null

func play_chop() -> void:
	_chop_left = CHOP_TIME

func is_chopping() -> bool:
	return _chop_left > 0.0

func set_bow(aiming: bool, charge: float) -> void:
	_aim_target = 1.0 if aiming else 0.0
	_draw_target = clampf(charge, 0.0, 1.0)

func get_aim_weight() -> float:
	return _aim_w

func set_riding(riding: bool) -> void:
	_ride_target = 1.0 if riding else 0.0

func set_vertical_speed(vy: float) -> void:
	_rise = clampf(vy / 5.0, -1.0, 1.0)

func update_motion(speed: float, moving: bool, grounded: bool) -> void:
	_speed = speed
	_moving = moving
	_grounded = grounded

func is_resting() -> bool:
	return not _moving and _grounded and _walk_w < 0.05

## Position de la main droite (poser un outil, une flèche).
func hand_transform() -> Transform3D:
	if _arm.is_empty() or not (_arm["r"]["hand"] as Node3D).is_inside_tree():
		return global_transform
	var t := (_arm["r"]["hand"] as Node3D).global_transform
	t.basis = t.basis.orthonormalized()
	return t

## Ce modèle dessine lui-même les outils tenus (hache, arc, couteau...).
func owns_tools() -> bool:
	return true

# --- Apparence ---------------------------------------------------------------------------

func set_profile(new_profile: CharacterProfile) -> void:
	profile = new_profile
	rebuild()

func set_gear(items: Array) -> void:
	var worn: Array = []
	for id in GEAR_IDS:
		if items.has(id):
			worn.append(id)
	if worn == gear:
		return
	gear = worn
	rebuild()

func has_gear(id: String) -> bool:
	return gear.has(id)

func set_held_tool(tool_id: String) -> void:
	if tool_id == held_tool:
		return
	held_tool = tool_id
	_build_held()

## Hauteur approximative du sommet de la tête (m).
func body_height() -> float:
	return _hip_height + (0.05 + _dims()["torso"] + 0.04 + float(_dims()["head"]) * 2.1)

func _dims() -> Dictionary:
	if profile.gender == "female":
		return {"leg": 0.76, "torso": 0.5, "sw": 0.2, "hip": 0.1, "chest": 0.155, "waist": 0.125,
				"head": 0.125, "upper": 0.26, "fore": 0.24, "thigh": 0.38, "shin": 0.38, "limb": 0.043}
	return {"leg": 0.8, "torso": 0.56, "sw": 0.255, "hip": 0.105, "chest": 0.205, "waist": 0.165,
			"head": 0.13, "upper": 0.28, "fore": 0.26, "thigh": 0.4, "shin": 0.4, "limb": 0.054}

# --- Construction ---------------------------------------------------------------------------

func rebuild() -> void:
	if _rig != null:
		_rig.free()
	_materials.clear()
	_arm.clear()
	_leg.clear()
	_held = null
	_skirt = null
	_eyelids.clear()
	_sway.clear()
	var d := _dims()
	var female := profile.gender == "female"
	var skin := profile.skin_color()
	var tunic := profile.tunic_color()
	var trim := tunic.lightened(0.35)
	var pants := profile.pants_color()
	var leather := Color(0.32, 0.21, 0.12)
	_hip_height = float(d["leg"])
	_rig = Node3D.new()
	_rig.name = "Rig"
	add_child(_rig)
	_hips = Node3D.new()
	_hips.position = Vector3(0.0, _hip_height, 0.0)
	_rig.add_child(_hips)
	var hip_w: float = d["hip"]
	# Bassin (la hanche de la femme est plus large).
	_part(_hips, _box(Vector3(hip_w * 2.0 + (0.09 if female else 0.05), 0.17, 0.26)), pants, Vector3(0, -0.02, 0))
	# Jupe (femme, pivot propre pour qu'elle ondule) ou pan de tunique (homme).
	_skirt = Node3D.new()
	_skirt.position = Vector3(0, 0.02, 0)
	_hips.add_child(_skirt)
	if female:
		_part(_skirt, _prism(8, 0.31, 0.17, 0.5), tunic, Vector3(0, -0.22, 0), Vector3.ZERO, Vector3(1.0, 1.0, 0.85))
		_part(_skirt, _prism(8, 0.325, 0.31, 0.05), trim, Vector3(0, -0.47, 0), Vector3.ZERO, Vector3(1.0, 1.0, 0.85))
	else:
		_part(_skirt, _prism(8, 0.255, 0.2, 0.34), tunic, Vector3(0, -0.14, 0), Vector3.ZERO, Vector3(1.0, 1.0, 0.75))
		_part(_skirt, _prism(8, 0.262, 0.255, 0.04), trim, Vector3(0, -0.3, 0), Vector3.ZERO, Vector3(1.0, 1.0, 0.75))
	# Torse.
	_torso = Node3D.new()
	_torso.position = Vector3(0, 0.05, 0)
	_hips.add_child(_torso)
	var torso_len: float = d["torso"]
	var chest: float = d["chest"]
	var waist: float = d["waist"]
	_part(_torso, _prism(8, waist, chest, torso_len), tunic, Vector3(0, torso_len * 0.5, 0), Vector3.ZERO, Vector3(1.0, 1.0, 0.68))
	# Poitrine (femme) : léger volume à l'avant.
	if female:
		for sx in [-1.0, 1.0]:
			_part(_torso, _ball(0.06, 6, 3), tunic, Vector3(sx * 0.06, torso_len * 0.72, 0.1))
	# Ceinture, boucle et bourse.
	_part(_torso, _prism(8, waist + 0.012, waist + 0.012, 0.07), leather, Vector3(0, 0.03, 0), Vector3.ZERO, Vector3(1.0, 1.0, 0.7))
	_part(_torso, _box(Vector3(0.05, 0.05, 0.02)), Color(0.9, 0.75, 0.3), Vector3(0, 0.03, waist * 0.7 + 0.015))
	_part(_torso, _box(Vector3(0.09, 0.1, 0.06)), leather.lightened(0.1), Vector3(hip_w + 0.07, -0.04, 0.02))
	# Col et cou.
	_part(_torso, _prism(6, 0.045, 0.05, 0.1), skin, Vector3(0, torso_len + 0.02, 0))
	_part(_torso, _prism(8, 0.085, 0.075, 0.045), trim, Vector3(0, torso_len - 0.005, 0))
	# Tête.
	_head = Node3D.new()
	_head.position = Vector3(0, torso_len + 0.05, 0)
	_torso.add_child(_head)
	_build_head(d, skin)
	# Bras : manche longue jusqu'au coude, poignet clair, main avec pouce.
	for side in ["l", "r"]:
		var sx: float = float(d["sw"]) * (1.0 if side == "l" else -1.0)
		var shoulder := Node3D.new()
		shoulder.position = Vector3(sx, torso_len - 0.07, 0)
		_torso.add_child(shoulder)
		var limb: float = d["limb"]
		var upper: float = d["upper"]
		var fore: float = d["fore"]
		_part(shoulder, _ball(limb * 1.5, 6, 3), tunic, Vector3.ZERO)
		_part(shoulder, _prism(6, limb * 1.05, limb * 0.9, upper), tunic, Vector3(0, -upper * 0.5, 0))
		var elbow := Node3D.new()
		elbow.position = Vector3(0, -upper, 0)
		shoulder.add_child(elbow)
		_part(elbow, _ball(limb * 0.92, 6, 3), tunic, Vector3.ZERO)
		_part(elbow, _prism(6, limb * 0.9, limb * 0.75, fore * 0.45), tunic, Vector3(0, -fore * 0.22, 0))
		_part(elbow, _prism(6, limb * 0.95, limb * 0.95, 0.035), trim, Vector3(0, -fore * 0.45, 0))
		_part(elbow, _prism(6, limb * 0.74, limb * 0.64, fore * 0.55), skin, Vector3(0, -fore * 0.73, 0))
		var hand := Node3D.new()
		hand.position = Vector3(0, -fore - 0.01, 0)
		elbow.add_child(hand)
		_part(hand, _box(Vector3(limb * 1.5, 0.085, limb * 1.0)), skin, Vector3(0, -0.04, 0))
		_part(hand, _box(Vector3(limb * 1.4, 0.05, limb * 0.9)), skin, Vector3(0, -0.095, 0.004))
		var thumb_dir := -1.0 if side == "l" else 1.0
		_part(hand, _box(Vector3(limb * 0.4, 0.05, limb * 0.45)), skin, Vector3(thumb_dir * limb * 0.85, -0.04, limb * 0.45), Vector3(0.4, 0, 0))
		_arm[side] = {"shoulder": shoulder, "elbow": elbow, "hand": hand}
	# Jambes : pantalon, genouillères, revers, chaussures articulées.
	for side in ["l", "r"]:
		var hx: float = hip_w * (1.0 if side == "l" else -1.0)
		var hip := Node3D.new()
		hip.position = Vector3(hx, -0.04, 0)
		_hips.add_child(hip)
		var thigh: float = d["thigh"]
		var shin: float = d["shin"]
		var radius: float = float(d["limb"]) * 1.3
		_part(hip, _prism(6, radius * 1.05, radius * 0.85, thigh), pants, Vector3(0, -thigh * 0.5, 0))
		var knee := Node3D.new()
		knee.position = Vector3(0, -thigh, 0)
		hip.add_child(knee)
		_part(knee, _ball(radius * 0.86, 6, 3), pants, Vector3.ZERO)
		_part(knee, _box(Vector3(radius * 1.0, 0.08, 0.025)), pants.darkened(0.2), Vector3(0, 0.0, radius * 0.78))
		_part(knee, _prism(6, radius * 0.85, radius * 0.66, shin), pants, Vector3(0, -shin * 0.5, 0))
		_part(knee, _prism(6, radius * 0.74, radius * 0.74, 0.05), pants.darkened(0.15), Vector3(0, -shin + 0.05, 0))
		# Pied : pivot à la cheville, semelle, chaussure et bout arrondi.
		var foot := Node3D.new()
		foot.position = Vector3(0, -shin, 0)
		knee.add_child(foot)
		_part(foot, _box(Vector3(0.115, 0.075, 0.2)), leather, Vector3(0, -0.015, 0.045))
		_part(foot, _box(Vector3(0.105, 0.06, 0.09)), leather.lightened(0.08), Vector3(0, -0.025, 0.15))
		_part(foot, _box(Vector3(0.12, 0.022, 0.3)), Color(0.14, 0.1, 0.07), Vector3(0, -0.062, 0.07))
		_leg[side] = {"hip": hip, "knee": knee, "foot": foot}
		if gear.has("gear_hide_boots"):
			var boot := Color(0.55, 0.38, 0.2)
			_part(knee, _prism(6, radius * 0.95, radius * 0.85, shin * 0.5), boot, Vector3(0, -shin * 0.75, 0))
			_part(knee, _prism(6, radius * 1.08, radius * 1.08, 0.05), Color(0.86, 0.8, 0.66), Vector3(0, -shin * 0.48, 0))
			_part(foot, _box(Vector3(0.125, 0.085, 0.21)), boot, Vector3(0, -0.012, 0.045))
	_build_gear(d)
	_build_held()

func _build_head(d: Dictionary, skin: Color) -> void:
	var r: float = d["head"]
	var female := profile.gender == "female"
	# Crâne et mâchoire.
	_part(_head, _ball(r, 8, 5), skin, Vector3(0, r + 0.02, 0), Vector3.ZERO, Vector3(0.95, 1.08, 1.0))
	_part(_head, _box(Vector3(r * (1.15 if female else 1.35), r * 0.55, r * 1.3)), skin, Vector3(0, r * 0.62, r * 0.18))
	# Oreilles.
	for sx in [-1.0, 1.0]:
		_part(_head, _box(Vector3(0.018, 0.05, 0.035)), skin.darkened(0.06), Vector3(sx * r * 0.97, r + 0.02, 0.0))
	# Yeux : blanc, iris, paupière (clignement), sourcils.
	var hair := profile.hair_color_value()
	var eye_color := profile.eye_color()
	for sx in [-1.0, 1.0]:
		var ex: float = sx * r * 0.4
		var ey: float = r + 0.045
		var ez: float = r * 0.9
		_part(_head, _box(Vector3(0.036, 0.03, 0.012)), Color(0.96, 0.96, 0.94), Vector3(ex, ey, ez))
		_part(_head, _box(Vector3(0.02, 0.026, 0.014)), eye_color, Vector3(ex, ey, ez + 0.002))
		_part(_head, _box(Vector3(0.01, 0.014, 0.016)), Color(0.04, 0.03, 0.03), Vector3(ex, ey, ez + 0.003))
		var lid := _part(_head, _box(Vector3(0.04, 0.034, 0.016)), skin, Vector3(ex, ey + 0.002, ez + 0.006))
		lid.scale.y = 0.001
		_eyelids.append(lid)
		var brow_w := 0.045 if not female else 0.04
		_part(_head, _box(Vector3(brow_w, 0.012, 0.014)), hair.darkened(0.15), Vector3(ex, ey + 0.032, ez + 0.002), Vector3(0, 0, sx * -0.12))
	# Nez, bouche, joues.
	_part(_head, _box(Vector3(0.022, 0.04, 0.03)), skin.darkened(0.1), Vector3(0, r + 0.0, r * 1.0))
	_part(_head, _box(Vector3(0.012, 0.012, 0.02)), skin.darkened(0.22), Vector3(0, r - 0.022, r * 1.03))
	_part(_head, _box(Vector3(0.05, 0.012, 0.012)), Color(0.62, 0.28, 0.26) if female else Color(0.5, 0.26, 0.22), Vector3(0, r * 0.62, r * 0.92))
	for sx in [-1.0, 1.0]:
		_part(_head, _box(Vector3(0.03, 0.025, 0.01)), Color(0.95, 0.5, 0.45, 1.0).lerp(skin, 0.7), Vector3(sx * r * 0.58, r * 0.78, r * 0.88))
	_build_hair(r, hair)
	_build_beard(r, hair)

func _build_hair(r: float, hair: Color) -> void:
	var style := profile.hair_style_name()
	var dark := hair.darkened(0.15)
	if style == "bald":
		return
	var cap := SphereMesh.new()
	cap.radius = r * 1.1
	cap.height = r * 1.1
	cap.radial_segments = 8
	cap.rings = 3
	cap.is_hemisphere = true
	_part(_head, flatten(cap), hair, Vector3(0, r + 0.075, -0.01), Vector3.ZERO, Vector3(1.0, 1.0, 1.05))
	# Frange et pattes.
	_part(_head, _box(Vector3(r * 1.7, 0.035, 0.035)), hair, Vector3(0, r + 0.085, r * 0.93))
	_part(_head, _box(Vector3(r * 0.55, 0.05, 0.04)), dark, Vector3(-r * 0.45, r + 0.065, r * 0.95), Vector3(0, 0, 0.35))
	for sx in [-1.0, 1.0]:
		_part(_head, _box(Vector3(0.025, 0.1, 0.06)), hair, Vector3(sx * r * 0.99, r + 0.0, r * 0.1))
	match style:
		"short":
			_part(_head, _box(Vector3(r * 1.95, 0.22, 0.07)), hair, Vector3(0, r + 0.0, -r * 0.95))
			for i in 3:
				_part(_head, _box(Vector3(0.05, 0.05, 0.06)), dark, Vector3((i - 1) * 0.06, r * 2.15, 0.03 * (i - 1)), Vector3(0.2 * (i - 1), 0, 0.3 * (i - 1)))
		"long":
			var back := _part(_head, _box(Vector3(r * 2.05, 0.48, 0.09)), hair, Vector3(0, -0.06, -r * 0.95))
			_sway.append({"node": back, "base": back.rotation, "amp": 0.1, "axis": Vector3.RIGHT})
			for sx in [-1.0, 1.0]:
				_part(_head, _box(Vector3(0.05, 0.3, 0.1)), hair, Vector3(sx * r * 0.98, 0.0, -r * 0.35))
				_part(_head, _box(Vector3(0.04, 0.16, 0.05)), dark, Vector3(sx * r * 0.95, -0.15, -r * 0.1))
		"ponytail":
			_part(_head, _prism(6, 0.058, 0.058, 0.03), Color(0.8, 0.25, 0.2), Vector3(0, r + 0.02, -r * 1.12), Vector3(1.2, 0, 0))
			var tail := Node3D.new()
			tail.position = Vector3(0, r + 0.02, -r * 1.15)
			_head.add_child(tail)
			_part(tail, _prism(6, 0.05, 0.015, 0.34), hair, Vector3(0, -0.17, -0.02))
			_sway.append({"node": tail, "base": tail.rotation, "amp": 0.2, "axis": Vector3.RIGHT})
		"bun":
			_part(_head, _ball(0.075, 6, 3), hair, Vector3(0, r * 2.15, -0.025))
			_part(_head, _prism(6, 0.05, 0.05, 0.02), Color(0.8, 0.25, 0.2), Vector3(0, r * 2.0, -0.025))
			_part(_head, _box(Vector3(r * 1.95, 0.16, 0.06)), hair, Vector3(0, r + 0.03, -r * 0.95))
		"curly":
			for i in 9:
				var a := float(i) / 9.0 * TAU
				_part(_head, _ball(0.06, 6, 3), hair, Vector3(cos(a) * r * 0.95, r + 0.1 + sin(a * 2.0) * 0.015, sin(a) * r * 0.95 - 0.01))
			for i in 4:
				_part(_head, _ball(0.07, 6, 3), hair, Vector3(sin(float(i) * 1.7) * 0.07, r * 2.15, cos(float(i) * 1.7) * 0.06))
		"braid":
			_part(_head, _box(Vector3(r * 1.95, 0.2, 0.07)), hair, Vector3(0, r + 0.0, -r * 0.95))
			var braid := Node3D.new()
			braid.position = Vector3(0, r - 0.02, -r * 1.1)
			_head.add_child(braid)
			for i in 5:
				_part(braid, _ball(0.05 - i * 0.004, 6, 3), hair if i % 2 == 0 else dark, Vector3(0, -0.09 * i - 0.05, -0.03 - i * 0.01))
			_part(braid, _prism(6, 0.025, 0.025, 0.03), Color(0.8, 0.25, 0.2), Vector3(0, -0.5, -0.07))
			_sway.append({"node": braid, "base": braid.rotation, "amp": 0.18, "axis": Vector3.RIGHT})

func _build_beard(r: float, hair: Color) -> void:
	if profile.gender == "female":
		return
	var beard := hair.darkened(0.05)
	match profile.beard_name():
		"stubble":
			_part(_head, _box(Vector3(r * 1.3, r * 0.5, r * 0.3)), hair.lerp(profile.skin_color(), 0.65), Vector3(0, r * 0.6, r * 0.78))
		"short":
			_part(_head, _box(Vector3(r * 1.5, r * 0.55, r * 0.35)), beard, Vector3(0, r * 0.58, r * 0.82))
			_part(_head, _box(Vector3(r * 0.9, 0.025, 0.03)), beard.darkened(0.1), Vector3(0, r * 0.82, r * 1.0))
		"full":
			_part(_head, _box(Vector3(r * 1.65, r * 0.9, r * 0.5)), beard, Vector3(0, r * 0.38, r * 0.78))
			_part(_head, _box(Vector3(r * 0.9, 0.03, 0.035)), beard.darkened(0.1), Vector3(0, r * 0.82, r * 1.02))
			_part(_head, _box(Vector3(r * 1.3, r * 0.5, r * 0.4)), beard, Vector3(0, r * 0.0, r * 0.62), Vector3(0.3, 0, 0))

func _build_gear(d: Dictionary) -> void:
	var torso_len: float = d["torso"]
	if gear.has("armor_fur_cloak"):
		var fur := Color(0.47, 0.31, 0.17)
		var sw: float = d["sw"]
		_part(_torso, _prism(8, sw + 0.1, sw + 0.02, 0.16), fur, Vector3(0, torso_len - 0.06, 0), Vector3.ZERO, Vector3(1.0, 1.0, 0.7))
		_part(_torso, _prism(8, sw + 0.03, sw + 0.03, 0.05), Color(0.85, 0.8, 0.7), Vector3(0, torso_len + 0.03, 0), Vector3.ZERO, Vector3(1.0, 1.0, 0.7))
		var cape := Node3D.new()
		cape.position = Vector3(0, torso_len - 0.08, -0.14)
		_torso.add_child(cape)
		_part(cape, _box(Vector3(sw * 1.7, 0.62, 0.04)), fur.darkened(0.12), Vector3(0, -0.31, 0))
		_part(cape, _box(Vector3(sw * 1.7, 0.05, 0.05)), Color(0.85, 0.8, 0.7), Vector3(0, -0.62, 0))
		_sway.append({"node": cape, "base": Vector3(0.05, 0, 0), "amp": 0.22, "axis": Vector3.RIGHT})
	if gear.has("gear_backpack"):
		var bag := Color(0.52, 0.35, 0.18)
		_part(_torso, _box(Vector3(0.3, 0.38, 0.15)), bag, Vector3(0, torso_len * 0.55, -0.2))
		_part(_torso, _prism(6, 0.075, 0.075, 0.32), bag.darkened(0.2), Vector3(0, torso_len * 0.55 + 0.23, -0.2), Vector3(0, 0, PI * 0.5))
		for sx in [-1.0, 1.0]:
			_part(_torso, _box(Vector3(0.04, 0.4, 0.02)), bag.darkened(0.3), Vector3(sx * 0.1, torso_len * 0.62, 0.12))
	if gear.has("gear_straw_hat"):
		var straw := Color(0.86, 0.73, 0.36)
		var r: float = d["head"]
		_part(_head, _prism(10, 0.25, 0.25, 0.02), straw, Vector3(0, r * 1.9, 0))
		_part(_head, _prism(8, r * 1.1, r * 0.85, 0.11), straw.darkened(0.08), Vector3(0, r * 1.9 + 0.06, 0))
		_part(_head, _prism(8, r * 1.12, r * 1.12, 0.03), Color(0.6, 0.2, 0.15), Vector3(0, r * 1.9 + 0.025, 0))

func _build_held() -> void:
	if _arm.is_empty():
		return
	var hand := _arm["r"]["hand"] as Node3D
	if _held != null and is_instance_valid(_held):
		_held.free()
	_held = Node3D.new()
	_held.name = "Held"
	hand.add_child(_held)
	var wood := Color(0.55, 0.36, 0.18)
	var stone := Color(0.62, 0.64, 0.68)
	var metal := Color(0.82, 0.86, 0.9)
	match held_tool:
		"tool_stone_axe":
			_part(_held, _prism(6, 0.02, 0.02, 0.6), wood, Vector3(0, 0.12, 0))
			_part(_held, _box(Vector3(0.05, 0.14, 0.17)), stone, Vector3(0, 0.36, 0.05))
		"tool_pickaxe":
			_part(_held, _prism(6, 0.02, 0.02, 0.62), wood, Vector3(0, 0.13, 0))
			_part(_held, _box(Vector3(0.04, 0.05, 0.36)), stone, Vector3(0, 0.42, 0.02))
			_part(_held, _box(Vector3(0.035, 0.04, 0.08)), stone.darkened(0.15), Vector3(0, 0.4, 0.22), Vector3(0.4, 0, 0))
		"tool_knife":
			_part(_held, _prism(6, 0.02, 0.02, 0.11), wood, Vector3(0, 0.0, 0))
			_part(_held, _box(Vector3(0.012, 0.2, 0.04)), metal, Vector3(0, 0.15, 0))
		"tool_sickle":
			_part(_held, _prism(6, 0.02, 0.02, 0.26), wood, Vector3(0, 0.05, 0))
			_part(_held, _box(Vector3(0.012, 0.16, 0.035)), metal, Vector3(0, 0.25, 0.03), Vector3(0.5, 0, 0))
			_part(_held, _box(Vector3(0.012, 0.12, 0.035)), metal, Vector3(0, 0.34, 0.12), Vector3(1.2, 0, 0))
		"tool_hoe":
			_part(_held, _prism(6, 0.02, 0.02, 0.75), wood, Vector3(0, 0.2, 0))
			_part(_held, _box(Vector3(0.04, 0.12, 0.17)), stone, Vector3(0, 0.57, 0.07), Vector3(0.5, 0, 0))
		"tool_watering_can":
			_part(_held, _prism(8, 0.08, 0.08, 0.16), Color(0.5, 0.58, 0.64), Vector3(0, 0.08, 0))
			_part(_held, _prism(6, 0.015, 0.015, 0.2), Color(0.5, 0.58, 0.64), Vector3(0, 0.15, 0.13), Vector3(1.0, 0, 0))
		"tool_fishing_rod":
			_part(_held, _prism(6, 0.016, 0.006, 1.1), wood, Vector3(0, 0.4, 0.0))
		"tool_hunting_bow":
			_part(_held, _box(Vector3(0.03, 0.05, 0.05)), wood.darkened(0.2), Vector3.ZERO)
			_part(_held, _box(Vector3(0.025, 0.4, 0.03)), wood, Vector3(0, 0.2, -0.03), Vector3(-0.2, 0, 0))
			_part(_held, _box(Vector3(0.025, 0.4, 0.03)), wood, Vector3(0, -0.2, -0.03), Vector3(0.2, 0, 0))
			_part(_held, _box(Vector3(0.006, 0.8, 0.006)), Color(0.9, 0.9, 0.85), Vector3(0, 0.0, -0.075))
		_:
			_held.visible = false
	_pose_held()

func _pose_held() -> void:
	if _held == null or not is_instance_valid(_held):
		return
	if held_tool == "tool_hunting_bow":
		# Au repos : arc porté, penché ; en visée : vertical, ventre vers la cible.
		_held.rotation = Vector3(lerpf(0.5, 0.0, _aim_w), 0.0, 0.0)
		_held.position = Vector3(0, -0.03, 0.04)
	else:
		_held.rotation = Vector3(0.95, 0.0, 0.0)
		_held.position = Vector3(0, -0.03, 0.02)

# --- Matériaux et maillages ------------------------------------------------------------------

func _material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 1.0
	m.metallic_specular = 0.1
	_materials[key] = m
	return m

func _part(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _material(color)
	node.position = pos
	node.rotation = rot
	node.scale = scl
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(node)
	return node

static var _mesh_cache := {}

static func _box(size: Vector3) -> Mesh:
	var key := "b%s" % str(size)
	if not _mesh_cache.has(key):
		var m := BoxMesh.new()
		m.size = size
		_mesh_cache[key] = m
	return _mesh_cache[key]

static func _prism(sides: int, r_bottom: float, r_top: float, height: float) -> Mesh:
	var key := "p%d_%f_%f_%f" % [sides, r_bottom, r_top, height]
	if not _mesh_cache.has(key):
		var m := CylinderMesh.new()
		m.radial_segments = sides
		m.rings = 1
		m.bottom_radius = r_bottom
		m.top_radius = r_top
		m.height = height
		_mesh_cache[key] = flatten(m)
	return _mesh_cache[key]

static func _ball(radius: float, segments: int, rings: int) -> Mesh:
	var key := "s%f_%d_%d" % [radius, segments, rings]
	if not _mesh_cache.has(key):
		var m := SphereMesh.new()
		m.radius = radius
		m.height = radius * 2.0
		m.radial_segments = segments
		m.rings = rings
		_mesh_cache[key] = flatten(m)
	return _mesh_cache[key]

## Mesh à facettes : chaque triangle reçoit sa propre normale (rendu « low-poly »).
static func flatten(source: Mesh) -> ArrayMesh:
	var arrays := source.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if indices.is_empty():
		for i in verts.size():
			indices.append(i)
	var out_verts := PackedVector3Array()
	var out_normals := PackedVector3Array()
	for i in range(0, indices.size() - 2, 3):
		var a := verts[indices[i]]
		var b := verts[indices[i + 1]]
		var c := verts[indices[i + 2]]
		var normal := (b - a).cross(c - a)
		normal = normal.normalized() if normal.length() > 0.00001 else Vector3.UP
		# Sens horaire de Godot : la normale pointe du côté visible.
		out_verts.append_array([a, b, c])
		out_normals.append_array([normal, normal, normal])
	var out := ArrayMesh.new()
	var out_arrays := []
	out_arrays.resize(Mesh.ARRAY_MAX)
	out_arrays[Mesh.ARRAY_VERTEX] = out_verts
	out_arrays[Mesh.ARRAY_NORMAL] = out_normals
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out_arrays)
	return out

# --- Animation --------------------------------------------------------------------------------

func advance_poses(delta: float) -> void:
	if _rig == null:
		return
	_time += delta
	_next_blink -= delta
	if _next_blink <= 0.0:
		_blink_left = 0.14
		_next_blink = randf_range(2.0, 5.0)
	var fast := 1.0 - exp(-12.0 * delta)
	var riding := _ride_target > 0.5
	_ride_w = lerpf(_ride_w, _ride_target, fast)
	_air_w = lerpf(_air_w, 0.0 if (_grounded or riding) else 1.0, fast)
	var walking := _moving and _grounded and not riding
	_walk_w = lerpf(_walk_w, 1.0 if walking else 0.0, 1.0 - exp(-10.0 * delta))
	_run_w = lerpf(_run_w, smoothstep(RUN_START, RUN_FULL, _speed) if walking else 0.0, fast)
	_aim_w = lerpf(_aim_w, _aim_target, 1.0 - exp(-16.0 * delta))
	_draw = lerpf(_draw, _draw_target, 1.0 - exp(-20.0 * delta))
	if walking:
		_phase += delta * 6.1 * clampf(_speed / STRIDE_SPEED, 0.5, 2.4)
	var chop := -1.0
	if _chop_left > 0.0:
		_chop_left = maxf(0.0, _chop_left - delta)
		chop = 1.0 - _chop_left / CHOP_TIME if _chop_left > 0.0 else -1.0
	_pose(chop)
	_pose_held()

func _pose(chop: float) -> void:
	var w := _walk_w
	var run := _run_w
	var s := sin(_phase)
	var c := cos(_phase)
	var amp := lerpf(0.55, 0.95, run) * w
	var knee_amp := lerpf(0.75, 1.5, run) * w
	var arm_amp := lerpf(0.5, 0.95, run) * w
	var breathe := sin(_time * 1.9) * (1.0 - w)
	# Bassin et torse.
	_hips.position.y = _hip_height - (0.035 + 0.03 * run) * absf(s) * w - _ride_w * 0.18
	_hips.rotation.y = -s * 0.1 * w
	_torso.rotation = Vector3(lerpf(0.0, 0.3, run) * w + 0.012 * breathe, s * 0.14 * w, 0.0)
	_torso.scale.y = 1.0 + 0.012 * breathe
	_head.rotation = Vector3(-_torso.rotation.x * 0.6, -s * 0.05 * w, 0.0)
	# Jambes : marche, puis pose en l'air, puis cheval.
	var air := _air_w
	for side in ["l", "r"]:
		var sign_side := 1.0 if side == "l" else -1.0
		var hip := _leg[side]["hip"] as Node3D
		var knee := _leg[side]["knee"] as Node3D
		var swing := -s * amp * sign_side
		var bend := knee_amp * maxf(0.0, c * sign_side) + 0.04
		var thigh_x := swing
		var knee_x := bend
		# En l'air : jambes en foulée (avant / arrière) ; à la retombée elles se préparent.
		var air_front := -0.55 * sign_side + 0.1
		var air_knee := 0.5 + 0.5 * (1.0 if sign_side < 0.0 else 0.0)
		thigh_x = lerpf(thigh_x, air_front * (1.0 - 0.4 * maxf(0.0, -_rise)) , air)
		knee_x = lerpf(knee_x, air_knee, air)
		# À cheval : cuisses vers l'avant, genoux pliés, jambes écartées.
		thigh_x = lerpf(thigh_x, -1.15, _ride_w)
		knee_x = lerpf(knee_x, 1.05, _ride_w)
		hip.rotation = Vector3(thigh_x, 0.0, lerpf(0.0, 0.42 * sign_side, _ride_w))
		knee.rotation = Vector3(knee_x, 0.0, 0.0)
		# Le pied reste à plat au sol (la cheville compense la jambe), la pointe se lève en fin de pas.
		var foot := _leg[side]["foot"] as Node3D
		var flat := -(thigh_x + knee_x) * 0.85
		var toe_off := 0.35 * maxf(0.0, sin(_phase * sign_side + 0.6)) * w * (1.0 - air)
		foot.rotation.x = clampf(flat + toe_off, -0.7, 0.9)
	# Bras.
	for side in ["l", "r"]:
		var sign_side := 1.0 if side == "l" else -1.0
		var shoulder := _arm[side]["shoulder"] as Node3D
		var elbow := _arm[side]["elbow"] as Node3D
		var sx := s * arm_amp * sign_side
		var sz := 0.06 * sign_side + 0.02 * breathe * sign_side
		var ex := -(0.12 + lerpf(0.15, 1.15, run) * w) - 0.05 * (1.0 - w)
		# En l'air : bras levés pour s'équilibrer.
		sx = lerpf(sx, -0.5, air)
		sz = lerpf(sz, 0.9 * sign_side, air)
		ex = lerpf(ex, -0.5, air)
		# À cheval : mains devant, sur les rênes.
		sx = lerpf(sx, -0.85, _ride_w)
		sz = lerpf(sz, 0.15 * sign_side, _ride_w)
		ex = lerpf(ex, -0.6, _ride_w)
		var sy := 0.0
		if side == "r":
			# Bras droit : coup de hache (levé puis abattu) ou arc tendu devant.
			if _aim_w > 0.01:
				sx = lerpf(sx, -1.55, _aim_w)
				sz = lerpf(sz, 0.0, _aim_w)
				ex = lerpf(ex, -0.05, _aim_w)
			if chop >= 0.0:
				var up := smoothstep(0.0, 0.38, chop)
				var down := smoothstep(0.38, 0.62, chop)
				var back := smoothstep(0.62, 1.0, chop)
				sx = lerpf(lerpf(lerpf(-0.2, -2.7, up), -0.5, down), sx, back)
				ex = lerpf(lerpf(-0.9, -0.2, down), ex, back)
		else:
			# Bras gauche : corde tendue (la main recule vers la joue).
			if _aim_w > 0.01:
				sx = lerpf(sx, -1.5, _aim_w)
				sy = lerpf(0.0, -0.35 - 0.3 * _draw, _aim_w)
				ex = lerpf(ex, -(0.35 + 1.7 * _draw), _aim_w)
				sz = lerpf(sz, 0.0, _aim_w)
		shoulder.rotation = Vector3(sx, sy, sz)
		elbow.rotation = Vector3(ex, 0.0, 0.0)
	if chop >= 0.0:
		_torso.rotation.x += 0.4 * sin(clampf(chop, 0.0, 1.0) * PI)
	# Mouvements secondaires : jupe, cheveux, cape.
	if _skirt != null:
		_skirt.rotation = Vector3(0.12 * run * w + 0.015 * breathe, 0.0, -s * 0.05 * w)
		_skirt.scale = Vector3(1.0 + 0.04 * absf(s) * w, 1.0, 1.0 + 0.05 * absf(s) * w)
	for entry in _sway:
		var node := entry["node"] as Node3D
		if node != null and is_instance_valid(node):
			var sway_amp: float = entry["amp"]
			var lag := sway_amp * (0.5 * w + 1.2 * run + 0.3 * air + 0.25 * sin(_time * 2.1 + sway_amp * 9.0))
			node.rotation = (entry["base"] as Vector3) + (entry["axis"] as Vector3) * lag
	# Clignement des yeux et léger regard.
	if _blink_left > 0.0:
		_blink_left = maxf(0.0, _blink_left - 0.016)
	for lid in _eyelids:
		if is_instance_valid(lid):
			(lid as Node3D).scale.y = 1.0 if _blink_left > 0.0 else 0.001
	_head.rotation.y += sin(_time * 0.7) * 0.05 * (1.0 - w)
