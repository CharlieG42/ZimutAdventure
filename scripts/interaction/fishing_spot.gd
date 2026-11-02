class_name FishingSpot
extends Interactable
## Étang de pêche : avec une canne, on lance la ligne, on attend la touche, puis on ferre à temps.
## Les touches sont plus rapides à l'aube, au crépuscule et sous la pluie.

signal caught(fish_id: String)

const ROD := "tool_fishing_rod"
const WAIT_MIN := 2.5
const WAIT_MAX := 6.5
const BITE_WINDOW := 2.0
const BIG_FISH_LEVEL := 3

enum State { IDLE, WAITING, BITE }

var state: int = State.IDLE
var _timer: float = 0.0
var _rng := RandomNumberGenerator.new()
var _bobber: MeshInstance3D

static func create() -> Area3D:
	var area := Area3D.new()
	area.set_script(load("res://scripts/interaction/fishing_spot.gd"))
	area.collision_layer = 4
	area.collision_mask = 0
	area.name = "FishingSpot"
	return area

func _ready() -> void:
	_rng.randomize()
	add_to_group("fishing")
	_build()

func _has_rod() -> bool:
	var inventory := InteractionManager.get_inventory()
	return inventory != null and inventory.has_item(ROD)

func can_interact() -> bool:
	return enabled

func get_prompt() -> String:
	if not _has_rod():
		return "ACTION_FISH_NEED_ROD"
	match state:
		State.WAITING:
			return "ACTION_FISH_REEL"
		State.BITE:
			return "ACTION_FISH_STRIKE"
	return "ACTION_FISH_CAST"

func _on_interact(_interactor: Node3D) -> void:
	if not _has_rod():
		_toast(tr("TOAST_FISH_NEED_ROD"))
		return
	match state:
		State.IDLE:
			cast()
		State.WAITING:
			_reset()
			_toast(tr("TOAST_FISH_TOO_EARLY"))
		State.BITE:
			var fish_id := catch_fish()
			_reset()
			_toast(tr("TOAST_FISH_CAUGHT") % tr("ITEM_" + fish_id.to_upper()))

func cast() -> void:
	state = State.WAITING
	_timer = _rng.randf_range(WAIT_MIN, WAIT_MAX) * _bite_speed()
	_show_bobber(true)
	_sound("splash")
	_toast(tr("TOAST_FISH_CAST"))

## Coefficient de temps d'attente : < 1 = plus rapide.
func _bite_speed() -> float:
	var factor := 1.0
	var clock := InteractionManager.get_day_night()
	if clock != null:
		var phase := String(clock.call("get_phase"))
		if phase == "dawn" or phase == "dusk":
			factor *= 0.6
	var weather := InteractionManager.get_weather()
	if weather != null and bool(weather.call("is_raining")):
		factor *= 0.75
	return factor

func _process(delta: float) -> void:
	if state == State.IDLE:
		return
	_timer -= delta
	if _bobber != null:
		_bobber.position.y = 0.12 + (sin(Time.get_ticks_msec() * 0.012) * 0.06 if state == State.BITE else sin(Time.get_ticks_msec() * 0.003) * 0.015)
	if _timer > 0.0:
		return
	if state == State.WAITING:
		state = State.BITE
		_timer = BITE_WINDOW
		_sound("bite")
		_toast(tr("TOAST_FISH_BITE"))
	else:
		_reset()
		_toast(tr("TOAST_FISH_ESCAPED"))

func _reset() -> void:
	state = State.IDLE
	_timer = 0.0
	_show_bobber(false)

## Tire le poisson, l'ajoute au sac et récompense. Retourne l'identifiant de l'objet.
func catch_fish() -> String:
	var progression := InteractionManager.get_progression()
	var level := int(progression.call("get_level")) if progression != null else 1
	var fish_id := "item_fish"
	if level >= BIG_FISH_LEVEL and _rng.randf() < 0.35:
		fish_id = "item_fish_big"
	var inventory := InteractionManager.get_inventory()
	if inventory != null:
		inventory.add_item(fish_id, 1)
	if progression != null:
		progression.call("add_stat", "stat_fished", 1)
		progression.call("add_xp_for", "fish")
	_sound("splash")
	caught.emit(fish_id)
	return fish_id

func _sound(event_name: String) -> void:
	var sfx := InteractionManager.get_sfx()
	if sfx != null and sfx.has_method("play_event"):
		sfx.call("play_event", event_name)

func _show_bobber(value: bool) -> void:
	if _bobber != null:
		_bobber.visible = value

func _toast(message: String) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var hud := tree.get_first_node_in_group("hud") as Node
	if hud != null and hud.has_method("show_toast"):
		hud.show_toast(message, 1.8)

# --- Modèle ----------------------------------------------------------------------------------------

func _build() -> void:
	var water := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 4.2
	disc.bottom_radius = 4.2
	disc.height = 0.1
	water.mesh = disc
	var material := ShaderMaterial.new()
	material.shader = load("res://assets/landscapes/shaders/water_surface.gdshader")
	water.material_override = material
	water.position = Vector3(0.0, 0.05, 0.0)
	add_child(water)
	var rim := StandardMaterial3D.new()
	rim.albedo_color = Color(0.42, 0.4, 0.36)
	rim.roughness = 1.0
	for i in 12:
		var angle := float(i) / 12.0 * TAU
		var stone := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.9 + float(i % 3) * 0.25, 0.35, 0.7)
		stone.mesh = box
		stone.material_override = rim
		stone.position = Vector3(cos(angle) * 4.5, 0.12, sin(angle) * 4.5)
		stone.rotation.y = -angle
		add_child(stone)
	_bobber = MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.1
	ball.height = 0.2
	_bobber.mesh = ball
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.9, 0.15, 0.1)
	_bobber.material_override = red
	_bobber.position = Vector3(1.4, 0.12, 0.6)
	_bobber.visible = false
	add_child(_bobber)
	# Zone de visée : le joueur s'approche du bord.
	var trigger := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 5.6
	shape.height = 1.6
	trigger.shape = shape
	trigger.position = Vector3(0.0, 0.6, 0.0)
	add_child(trigger)
