class_name Predator
extends PassiveAnimal
## Prédateur nocturne (loup, coyote) : rôde, charge le joueur qui s'approche, mord, et s'en prend
## au bétail laissé hors enclos. Il fuit le feu de camp, le chien apprivoisé le mord, et il se
## tue à la hache (corps à corps) ou à l'arc. Il laisse une peau et un peu de viande.

const PREDATORS := {
	"wolf": {"scale": 0.85, "fur": Color(0.4, 0.4, 0.44), "belly": Color(0.74, 0.74, 0.76),
			"ear": 0.22, "neck": 0.28, "hop": 0.0, "speed": 1.0,
			"hp": 4, "damage": 0.14, "chase": 5.6, "detect": 26.0, "pelts": 2},
	"coyote": {"scale": 0.65, "fur": Color(0.64, 0.5, 0.32), "belly": Color(0.86, 0.76, 0.6),
			"ear": 0.24, "neck": 0.24, "hop": 0.0, "speed": 1.1,
			"hp": 2, "damage": 0.08, "chase": 5.2, "detect": 18.0, "pelts": 1},
}
const BITE_RANGE := 1.9
const BITE_COOLDOWN := 1.3
const FIRE_DISTANCE := 11.0
const RAID_RANGE := 25.0
const RAID_COOLDOWN := 25.0
const DOG_GUARD_RANGE := 3.5

var _attack_cd: float = 0.0
var _fear_left: float = 0.0
var _fear_from: Vector3 = Vector3.ZERO
var _retreating: bool = false
var _retreat_left: float = 0.0
var _raid_cd: float = 0.0
var _dog_cd: float = 0.0
var _announced: bool = false
var _stats: Dictionary

static func new_for(kind: String) -> Predator:
	var predator := (load("res://scenes/world/predator.tscn") as PackedScene).instantiate() as Predator
	predator.species = kind
	return predator

func _species_config() -> Dictionary:
	return PREDATORS.get(species, PREDATORS["wolf"])

func _ready() -> void:
	super._ready()
	add_to_group("predators")
	_stats = _species_config()
	_hp = int(_stats["hp"])
	wander_radius = 26.0
	_decorate()

func _decorate() -> void:
	var tail := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.06
	capsule.height = 0.5
	var fur := StandardMaterial3D.new()
	fur.albedo_color = (_config["fur"] as Color).darkened(0.15)
	capsule.material = fur
	tail.mesh = capsule
	tail.position = Vector3(0.0, 1.0, -0.6)
	tail.rotation_degrees = Vector3(-60.0, 0.0, 0.0)
	_model.add_child(tail)
	if _head == null:
		return
	# Yeux rougeoyants : on les repère dans le noir.
	var eye_mat := StandardMaterial3D.new()
	eye_mat.albedo_color = Color(1.0, 0.2, 0.1)
	eye_mat.emission_enabled = true
	eye_mat.emission = Color(1.0, 0.25, 0.1)
	eye_mat.emission_energy_multiplier = 2.0
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.03
		sphere.height = 0.06
		sphere.radial_segments = 6
		sphere.rings = 3
		sphere.material = eye_mat
		eye.mesh = sphere
		eye.position = Vector3(0.06 * side, 0.05, 0.17)
		_head.add_child(eye)

# --- Comportement ---------------------------------------------------------------------

## Un prédateur ne fuit pas le joueur comme un gibier.
func _scare_direction() -> Vector3:
	return Vector3.ZERO

func _update_behavior(delta: float) -> void:
	_attack_cd = maxf(0.0, _attack_cd - delta)
	_raid_cd = maxf(0.0, _raid_cd - delta)
	_dog_cd = maxf(0.0, _dog_cd - delta)
	if (_player == null or not is_instance_valid(_player)) and is_inside_tree():
		_player = get_tree().get_first_node_in_group("player") as Node3D
	_guard_dog_bite()
	var wanted := Vector3.ZERO
	var chase_speed: float = _stats["chase"]
	if _retreating:
		_retreat_left -= delta
		wanted = _away_from(_player.global_position if _player != null else global_position + Vector3.FORWARD) * chase_speed * 0.7
		if _retreat_left <= 0.0:
			queue_free()
			return
	elif _fear_left > 0.0:
		_fear_left -= delta
		wanted = _away_from(_fear_from) * chase_speed
	elif _fire_nearby() != null:
		wanted = _away_from(_fire_nearby().global_position) * chase_speed * 0.9
	else:
		var target := _pick_target()
		if target != null:
			wanted = _chase(target, chase_speed, delta)
		else:
			super._update_behavior(delta)
			return
	_track_stuck(wanted, delta)
	velocity.x = move_toward(velocity.x, wanted.x, 40.0 * delta)
	velocity.z = move_toward(velocity.z, wanted.z, 40.0 * delta)
	if wanted.length_squared() > 0.01:
		_face_direction(wanted.normalized(), delta)

func _away_from(point: Vector3) -> Vector3:
	var away := global_position - point
	away.y = 0.0
	return away.normalized() if away.length_squared() > 0.001 else Vector3.RIGHT

## Le joueur d'abord, sinon du bétail laissé dehors.
func _pick_target() -> Node3D:
	if _player != null and is_instance_valid(_player):
		var offset := _player.global_position - global_position
		offset.y = 0.0
		if offset.length() < float(_stats["detect"]):
			return _player
	if _raid_cd <= 0.0:
		var best: Node3D = null
		var best_distance := RAID_RANGE
		for animal in get_tree().get_nodes_in_group("tamed"):
			if not is_instance_valid(animal) or not bool(animal.get("is_livestock")) or bool(animal.get("penned")):
				continue
			var distance := global_position.distance_to(animal.global_position)
			if distance < best_distance:
				best_distance = distance
				best = animal
		return best
	return null

func _chase(target: Node3D, speed: float, _delta: float) -> Vector3:
	var offset := target.global_position - global_position
	offset.y = 0.0
	var distance := offset.length()
	if not _announced and target == _player:
		_announced = true
		_toast(tr("TOAST_PREDATOR_NEAR") % tr("ANIMAL_" + species.to_upper()))
	if distance < BITE_RANGE:
		if target == _player:
			_bite()
		else:
			_raid(target)
		return Vector3.ZERO
	return offset / distance * speed

func _bite() -> void:
	if _attack_cd > 0.0:
		return
	_attack_cd = BITE_COOLDOWN
	var survival := InteractionManager.get_survival()
	if survival != null:
		survival.call("damage", float(_stats["damage"]))
		_toast(tr("TOAST_BITTEN"))

func _raid(animal: Node3D) -> void:
	_raid_cd = RAID_COOLDOWN
	if animal.has_method("scare_by_predator"):
		animal.call("scare_by_predator")
	# Le butin pris, il repart rôder au loin.
	_fear_left = 3.0
	_fear_from = animal.global_position

## Un chien apprivoisé qui garde les lieux mord l'intrus.
func _guard_dog_bite() -> void:
	if _dog_cd > 0.0:
		return
	for companion in get_tree().get_nodes_in_group("tamed"):
		if is_instance_valid(companion) and companion.get("species") == "dog" \
				and companion.global_position.distance_to(global_position) < DOG_GUARD_RANGE:
			_dog_cd = 1.5
			hit(1, companion.global_position)
			return

func _fire_nearby() -> Node3D:
	for fire in get_tree().get_nodes_in_group("campfire"):
		if is_instance_valid(fire) and fire.has_method("is_lit") and bool(fire.call("is_lit")) \
				and fire.global_position.distance_to(global_position) < FIRE_DISTANCE:
			return fire
	return null

## Le jour se lève : il regagne les collines puis disparaît.
func retreat() -> void:
	if _retreating:
		return
	_retreating = true
	_retreat_left = 10.0

# --- Dégâts -----------------------------------------------------------------------------------

func take_arrow_hit(from_position: Vector3) -> void:
	hit(2, from_position)

func hit(damage: int, from_position: Vector3) -> void:
	if _dead:
		return
	_hp -= damage
	_fear_left = 2.5
	_fear_from = from_position
	if _hp <= 0:
		_die()

func _die() -> void:
	_dead = true
	remove_from_group("predators")
	var inventory := InteractionManager.get_inventory()
	if inventory != null:
		inventory.add_item("item_pelt", int(_stats["pelts"]))
		inventory.add_item("item_raw_meat", 1)
	var progression := InteractionManager.get_progression()
	if progression != null:
		progression.call("add_stat", "stat_predators", 1)
		progression.call("add_xp_for", "hunt")
	_toast(tr("TOAST_PREDATOR_KILLED") % tr("ANIMAL_" + species.to_upper()))
	collision_layer = 0
	collision_mask = 0
	set_physics_process(false)
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3(1.0, 0.05, 1.0), 0.5)
	tween.tween_callback(queue_free)

func _toast(message: String) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var hud := tree.get_first_node_in_group("hud") as Node
	if hud != null and hud.has_method("show_toast"):
		hud.show_toast(message, 2.2)
