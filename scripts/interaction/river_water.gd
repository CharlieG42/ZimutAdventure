class_name RiverWater
extends Interactable
## Eau de la rivière et des lacs : un seul point d'eau qui accompagne le joueur dès qu'il
## est au bord de l'eau ou dedans. On peut donc boire partout le long de la rivière, sans
## semer des dizaines de zones d'interaction.

## Distance au bord de l'eau (m) en deçà de laquelle on peut boire.
const REACH := 2.2
const CHECK_SECONDS := 0.15

var _landscape: Node3D
var _check: float = 0.0
var _near: bool = false

static func create(landscape: Node3D) -> Area3D:
	var area := Area3D.new()
	area.set_script(load("res://scripts/interaction/river_water.gd"))
	area.name = "RiverWater"
	area.collision_layer = 4
	area.collision_mask = 0
	area.add_to_group("water")
	area.set("_landscape", landscape)
	var shape := SphereShape3D.new()
	shape.radius = 0.9
	var collision := CollisionShape3D.new()
	collision.shape = shape
	area.add_child(collision)
	return area

## L'eau courante ne s'épuise pas : simple pause entre deux gorgées.
const DRINK_AMOUNT := 0.3
const SIP_SECONDS := 2.0
var _sip_left: float = 0.0

func _ready() -> void:
	prompt_text = "ACTION_DRINK"

func can_interact() -> bool:
	return enabled and _near and _sip_left <= 0.0

func _on_interact(_interactor: Node3D) -> void:
	# Pas de référence directe aux autoloads : le décor se charge aussi sans eux (tests).
	var survival := get_tree().root.get_node_or_null("SurvivalManager")
	if survival == null or not survival.has_method("drink"):
		return
	survival.call("drink", DRINK_AMOUNT)
	_sip_left = SIP_SECONDS
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("show_toast"):
		hud.call("show_toast", tr("TOAST_DRANK"))

func _process(delta: float) -> void:
	_sip_left = maxf(0.0, _sip_left - delta)
	_check -= delta
	if _check > 0.0:
		return
	_check = CHECK_SECONDS
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null or _landscape == null:
		_near = false
		return
	var p := player.global_position
	_near = is_reachable(_landscape, p)
	if _near:
		# À hauteur de poitrine : l'aide à la visée le prend quand rien d'autre n'est visé.
		global_position = p + Vector3(0.0, 1.3, 0.0)
	else:
		global_position = Vector3(p.x, -200.0, p.z)

## Vrai si un joueur placé en `p` peut boire à la rivière.
static func is_reachable(landscape: Node3D, p: Vector3) -> bool:
	if not bool(landscape.call("is_water", p.x, p.z, REACH)):
		return false
	return p.y < float(landscape.call("water_level_at", p.x)) + 2.5
