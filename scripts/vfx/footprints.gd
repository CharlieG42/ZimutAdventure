class_name Footprints
extends Node3D
## Traces de pas du joueur : une empreinte tous les ~55 cm de déplacement au sol,
## décalée alternativement à gauche/droite, posée sur le terrain, qui s'estompe
## en ~20 s. Pool plafonné (les plus vieilles sont recyclées).

const STEP_DISTANCE := 0.55
const SIDE_OFFSET := 0.13
const MARK_SIZE := Vector2(0.2, 0.32)
const MARK_ALPHA := 0.5
const FADE_SECONDS := 20.0
const MAX_MARKS := 48
const TEX := "res://assets/vfx/overlays/footprint.png"

var _tex: Texture2D
var _last_pos := Vector3.ZERO
var _alternate := false
var _marks: Array = []  # [{node: MeshInstance3D, mat: StandardMaterial3D, age: float}]
var _player: Node3D
var _landscape: Node3D

func _ready() -> void:
	add_to_group("footprints")
	_tex = load(TEX)
	_landscape = get_parent().get_node_or_null("Landscape") if get_parent() != null else null

func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") if get_tree() != null else null
		if _player == null:
			return
	var pos: Vector3 = _player.global_position
	var speed := 0.0
	var grounded := true
	if "velocity" in _player:
		speed = Vector2(_player.velocity.x, _player.velocity.z).length()
	if _player.has_method("is_on_floor"):
		grounded = _player.is_on_floor()
	var heading: float = _player.rotation.y if "rotation" in _player else 0.0
	try_spawn(pos, heading, grounded, speed)
	age_marks(delta)

## Pose une empreinte si le joueur a assez bougé au sol. Testable directement.
func try_spawn(pos: Vector3, heading: float, grounded: bool, speed: float) -> void:
	if not grounded or speed < 0.5:
		_last_pos = pos
		return
	if _last_pos == Vector3.ZERO:
		_last_pos = pos
		return
	if pos.distance_to(_last_pos) < STEP_DISTANCE:
		return
	_last_pos = pos
	_alternate = not _alternate
	var side := SIDE_OFFSET * (1.0 if _alternate else -1.0)
	# "right" perpendiculaire au cap (le joueur regarde -Z local).
	var right := Vector3(cos(heading), 0.0, -sin(heading))
	var p := pos + right * side
	var y := pos.y
	if _landscape != null and _landscape.has_method("terrain_height_at"):
		y = float(_landscape.call("terrain_height_at", p.x, p.z)) + 0.035
	var m := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = MARK_SIZE
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = _tex
	mat.albedo_color = Color(0.23, 0.16, 0.1, MARK_ALPHA)
	q.material = mat
	m.mesh = q
	m.position = Vector3(p.x, y, p.z)
	m.rotation = Vector3(-PI * 0.5, heading, 0.0)
	add_child(m)
	_marks.append({"node": m, "mat": mat, "age": 0.0})
	if _marks.size() > MAX_MARKS:
		var old: Dictionary = _marks.pop_front()
		(old["node"] as Node).queue_free()

## Vieillissement + fondu des empreintes. Testable directement.
func age_marks(delta: float) -> void:
	for i in range(_marks.size() - 1, -1, -1):
		var mark: Dictionary = _marks[i]
		mark["age"] = float(mark["age"]) + delta
		var a := MARK_ALPHA * (1.0 - float(mark["age"]) / FADE_SECONDS)
		if a <= 0.0:
			(mark["node"] as Node).queue_free()
			_marks.remove_at(i)
		else:
			var c: Color = (mark["mat"] as StandardMaterial3D).albedo_color
			c.a = a
			(mark["mat"] as StandardMaterial3D).albedo_color = c

func mark_count() -> int:
	return _marks.size()
