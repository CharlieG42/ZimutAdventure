class_name AnimalRig
extends Node3D
## Modèle animé d'un animal (Quaternius, CC0 — voir assets/animals/README.md).
## Le modèle est mis à l'échelle d'après sa hauteur réelle et choisit lui-même son
## animation : repos, marche, galop, broutage ; attaque et chute à la demande.
## Loin de la caméra, l'animation se met en pause (économie de processeur sur mobile).

## Espèce -> fichier, hauteur visée (m, tête comprise), couleurs de remplacement
## (nom de matériau -> couleur). « variants » : autres fichiers possibles.
const MODELS := {
	"deer": {"path": "res://assets/animals/deer.glb", "height": 1.55, "variants": ["res://assets/animals/stag.glb"],
			"variant_heights": [1.8], "variant_chance": 0.35},
	"wolf": {"path": "res://assets/animals/wolf.glb", "height": 1.0},
	"coyote": {"path": "res://assets/animals/coyote.glb", "height": 0.8,
			# Le renard du pack, repeint aux couleurs d'un coyote (fauve grisé).
			"colors": {"Main": Color(0.62, 0.5, 0.36), "Main_Light": Color(0.86, 0.79, 0.68), "Black": Color(0.3, 0.25, 0.2),
					"Grey": Color(0.55, 0.5, 0.44)}},
	"cow": {"path": "res://assets/animals/cow.glb", "height": 1.65},
	"sheep": {"path": "res://assets/animals/sheep.glb", "height": 1.0},
	# Avancé de 25 cm : le cavalier (placé à l'origine) s'assoit au milieu du dos, pas sur le garrot.
	"horse": {"path": "res://assets/animals/horse.glb", "height": 2.45, "offset": Vector3(0.0, 0.0, 0.25)},
	"dog": {"path": "res://assets/animals/shiba_inu.glb", "height": 0.72},
}
## Rôle -> noms possibles (le premier présent est utilisé).
const CLIPS := {
	"idle": ["Idle"],
	"idle_alt": ["Idle_2", "Idle"],
	"eat": ["Eating", "Idle_Headlow", "Idle_2_HeadLow", "Idle"],
	"walk": ["Walk", "WalkSlow"],
	"run": ["Gallop", "Walk"],
	"attack": ["Attack", "Attack_Headbutt", "Jump"],
	"death": ["Death"],
}
const LOOPING := ["idle", "idle_alt", "eat", "walk", "run"]
## Vitesse (m/s, à l'échelle 1) à laquelle les animations de marche et de galop sont jouées
## à vitesse normale : au-delà, elles s'accélèrent pour que les pattes ne glissent pas.
const WALK_NATURAL := 1.1
const RUN_NATURAL := 4.2
const RUN_THRESHOLD := 2.6
const BLEND := 0.25
## Au-delà de cette distance (m) de la caméra, l'animation se fige.
const PAUSE_DISTANCE := 75.0
const CHECK_SECONDS := 0.5

static var _scale_cache: Dictionary = {}

var species: String = ""
var model: Node3D
var animation_player: AnimationPlayer
var skeleton: Skeleton3D
## Facteur de taille de cette instance (le reste est porté par le nœud parent).
var size_factor: float = 1.0

var _clips: Dictionary = {}
var _current: String = ""
var _locked_left: float = 0.0
var _dead: bool = false
var _check_left: float = 0.0
var _far: bool = false
var _idle_switch_left: float = 6.0
var _rng := RandomNumberGenerator.new()

static func has_model(kind: String) -> bool:
	return MODELS.has(kind)

## Construit le modèle d'une espèce. `parent_scale` : échelle déjà appliquée par le parent
## (le modèle compense pour atteindre la hauteur visée). `tint` : variation individuelle.
static func create(kind: String, parent_scale: float = 1.0, tint: float = 1.0, seed_value: int = 0) -> AnimalRig:
	var rig := AnimalRig.new()
	rig.name = "Rig"
	rig.species = kind
	rig._rng.seed = seed_value if seed_value != 0 else randi()
	var entry: Dictionary = MODELS[kind]
	var path: String = entry["path"]
	var height: float = entry["height"]
	var variants: Array = entry.get("variants", [])
	if not variants.is_empty() and rig._rng.randf() < float(entry.get("variant_chance", 0.0)):
		var index := rig._rng.randi() % variants.size()
		path = variants[index]
		height = float((entry.get("variant_heights", []) as Array)[index])
	var scene := load(path) as PackedScene
	if scene == null:
		return null
	rig.model = scene.instantiate() as Node3D
	rig.add_child(rig.model)
	var raw := _raw_height(path, rig.model)
	rig.model.scale = Vector3.ONE * (height / maxf(raw, 0.01) / maxf(parent_scale, 0.01))
	rig.model.position = (entry.get("offset", Vector3.ZERO) as Vector3) / maxf(parent_scale, 0.01)
	# Un grand animal couvre plus de terrain à chaque foulée.
	rig.size_factor = height / 1.5
	rig.animation_player = rig.model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var skeletons := rig.model.find_children("*", "Skeleton3D", true, false)
	rig.skeleton = skeletons[0] as Skeleton3D if not skeletons.is_empty() else null
	rig._apply_materials(entry.get("colors", {}), tint)
	rig._index_clips()
	for mesh in rig.model.find_children("*", "MeshInstance3D", true, false):
		# Les ombres des animaux coûtent cher pour peu de gain : un disque au sol les remplace.
		(mesh as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rig.play_role("idle")
	return rig

## Hauteur du modèle brut (mise en cache par fichier), mesurée sur le squelette en pose de
## repos : la boîte englobante des maillages animés est parfois fausse (export du mouton).
static func _raw_height(path: String, instance: Node3D) -> float:
	if _scale_cache.has(path):
		return float(_scale_cache[path])
	var height := 1.0
	var skeletons := instance.find_children("*", "Skeleton3D", true, false)
	if not skeletons.is_empty():
		var skeleton := skeletons[0] as Skeleton3D
		var xform := _relative_transform(skeleton, instance)
		var top := 0.0
		for i in skeleton.get_bone_count():
			top = maxf(top, (xform * skeleton.get_bone_global_rest(i)).origin.y)
		# Les os s'arrêtent sous le sommet du crâne et des oreilles.
		height = top * 1.05
	_scale_cache[path] = height
	return height

static func _relative_transform(node: Node, root: Node) -> Transform3D:
	var xform := Transform3D.IDENTITY
	var walker: Node = node
	while walker != null and walker != root:
		if walker is Node3D:
			xform = (walker as Node3D).transform * xform
		walker = walker.get_parent()
	return xform

func _apply_materials(colors: Dictionary, tint: float) -> void:
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		for i in mesh_instance.mesh.get_surface_count():
			var source := mesh_instance.mesh.surface_get_material(i) as BaseMaterial3D
			if source == null:
				continue
			var material := source.duplicate() as BaseMaterial3D
			# Certains exports donnent un aspect métallique sombre : mat comme un pelage.
			material.metallic = 0.0
			material.roughness = 1.0
			var base: Color = colors.get(String(source.resource_name), source.albedo_color)
			# Variation individuelle du pelage (pas des yeux ni des sabots).
			var shade := tint if String(source.resource_name).begins_with("Main") else 1.0
			material.albedo_color = Color(base.r * shade, base.g * shade, base.b * shade, source.albedo_color.a)
			mesh_instance.set_surface_override_material(i, material)

func _index_clips() -> void:
	if animation_player == null:
		return
	var available := animation_player.get_animation_list()
	for role in CLIPS:
		for candidate in CLIPS[role]:
			var found := ""
			for anim_name in available:
				if anim_name == candidate or String(anim_name).ends_with("|" + candidate):
					found = anim_name
					break
			if found != "":
				_clips[role] = found
				var animation := animation_player.get_animation(found)
				if animation != null:
					animation.loop_mode = Animation.LOOP_LINEAR if role in LOOPING else Animation.LOOP_NONE
				break

func has_role(role: String) -> bool:
	return _clips.has(role)

func get_clip(role: String) -> String:
	return String(_clips.get(role, ""))

func get_current_role() -> String:
	return _current

## Lance une animation par rôle (fondu court). Ne relance pas celle qui joue déjà.
func play_role(role: String, speed: float = 1.0) -> void:
	if animation_player == null or not _clips.has(role):
		return
	animation_player.speed_scale = speed
	if _current == role and animation_player.is_playing():
		return
	_current = role
	animation_player.play(_clips[role], BLEND)

## Mise à jour d'après le déplacement : `speed` en m/s, `grazing` à l'arrêt pour brouter.
func update_motion(speed: float, grazing: bool, delta: float) -> void:
	if _dead:
		return
	if _locked_left > 0.0:
		_locked_left -= delta
		return
	var scale_factor := maxf(size_factor, 0.2)
	if speed > RUN_THRESHOLD * scale_factor and has_role("run"):
		play_role("run", clampf(speed / (RUN_NATURAL * scale_factor), 0.6, 2.2))
	elif speed > 0.15:
		play_role("walk", clampf(speed / (WALK_NATURAL * scale_factor), 0.5, 2.4))
	elif grazing:
		play_role("eat")
	else:
		_idle_switch_left -= delta
		if _idle_switch_left <= 0.0:
			_idle_switch_left = _rng.randf_range(5.0, 10.0)
			play_role("idle_alt" if _current == "idle" and _rng.randf() < 0.4 else "idle")
		elif _current != "idle" and _current != "idle_alt":
			play_role("idle")

## Joue l'attaque une fois, puis reprend le mouvement.
func play_attack() -> void:
	if _dead or not has_role("attack"):
		return
	play_role("attack")
	var animation := animation_player.get_animation(_clips["attack"])
	_locked_left = animation.length * 0.9 if animation != null else 0.6
	_current = ""

## Chute : joue l'animation de mort (si elle existe). Retourne sa durée en secondes.
func play_death() -> float:
	_dead = true
	if not has_role("death"):
		return 0.0
	play_role("death")
	var animation := animation_player.get_animation(_clips["death"])
	return animation.length if animation != null else 1.0

## Après une réapparition : debout, au repos.
func revive() -> void:
	_dead = false
	_locked_left = 0.0
	_current = ""
	play_role("idle")

func is_dead() -> bool:
	return _dead

## Point d'attache sur la tête (yeux des prédateurs) : un BoneAttachment3D, ou null.
func head_attachment() -> Node3D:
	if skeleton == null:
		return null
	var bone := skeleton.find_bone("Head")
	if bone < 0:
		return null
	var attachment := BoneAttachment3D.new()
	attachment.bone_idx = bone
	skeleton.add_child(attachment)
	return attachment

func _process(delta: float) -> void:
	_check_left -= delta
	if _check_left > 0.0 or animation_player == null:
		return
	_check_left = CHECK_SECONDS
	var camera := get_viewport().get_camera_3d() if get_viewport() != null else null
	if camera == null:
		return
	var far := camera.global_position.distance_to(global_position) > PAUSE_DISTANCE
	if far == _far:
		return
	_far = far
	if far:
		animation_player.pause()
	elif _current != "":
		animation_player.play()
