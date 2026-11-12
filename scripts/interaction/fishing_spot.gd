class_name FishingSpot
extends Interactable
## Étang de pêche, en quatre temps simples :
##  1. lancer la ligne (le bouchon se pose devant le joueur) ;
##  2. attendre la touche — relever avant ne coûte rien ;
##  3. ferrer quand le bouchon plonge (signal « ! », son et vibration) ;
##  4. tirer plusieurs fois pour remonter le poisson (jauge à l'écran).
## Les touches sont plus rapides à l'aube, au crépuscule et sous la pluie.

signal caught(fish_id: String)

const ROD := "tool_fishing_rod"
const WAIT_MIN := 2.5
const WAIT_MAX := 6.5
const BITE_WINDOW := 2.6
const BIG_FISH_LEVEL := 3
## Nombre de tractions pour remonter la prise, et délai maximal entre deux tractions.
const PULLS_SMALL := 3
const PULLS_BIG := 5
const PULL_TIMEOUT := 1.8
## On s'éloigne de l'étang : la ligne est perdue.
const LEAVE_DISTANCE := 8.5

enum State { IDLE, WAITING, BITE, REELING }

var state: int = State.IDLE
var _timer: float = 0.0
var _rng := RandomNumberGenerator.new()
var _bobber: MeshInstance3D
var _bite_mark: Label3D
var _line: MeshInstance3D
var _line_mesh: ImmediateMesh
var _angler: Node3D
var _hooked_fish: String = ""
var _pulls_needed: int = 0
var _pulls_done: int = 0
var _bobber_rest := Vector3(1.4, 0.12, 0.6)

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
		State.REELING:
			return "ACTION_FISH_PULL"
	return "ACTION_FISH_CAST"

func _on_interact(interactor: Node3D) -> void:
	if not _has_rod():
		_toast(tr("TOAST_FISH_NEED_ROD"))
		return
	match state:
		State.IDLE:
			cast(interactor)
		State.WAITING:
			_reset()
			_toast(tr("TOAST_FISH_TOO_EARLY"))
		State.BITE:
			strike()
		State.REELING:
			pull()

## Lance la ligne : le bouchon se pose entre le centre de l'étang et le pêcheur.
func cast(angler: Node3D = null) -> void:
	_angler = angler
	state = State.WAITING
	_timer = _rng.randf_range(WAIT_MIN, WAIT_MAX) * _bite_speed()
	_place_bobber()
	_show_bobber(true)
	_hold_focus(true)
	_sound("splash")
	_toast(tr("TOAST_FISH_CAST"))

## Ferre le poisson qui vient de mordre : il faut ensuite le remonter.
func strike() -> void:
	if state != State.BITE:
		return
	state = State.REELING
	_pulls_done = 1
	_timer = PULL_TIMEOUT
	_show_bite_mark(false)
	_sound("splash")
	_vibrate(30)
	_update_gauge()
	if _pulls_done >= _pulls_needed:
		_land()

## Une traction sur la ligne ; la dernière sort le poisson de l'eau.
func pull() -> void:
	if state != State.REELING:
		return
	_pulls_done += 1
	_timer = PULL_TIMEOUT
	_sound("harvest")
	_vibrate(20)
	_update_gauge()
	if _pulls_done >= _pulls_needed:
		_land()

func _land() -> void:
	var fish_id := catch_fish()
	var message := tr("TOAST_FISH_CAUGHT") % tr("ITEM_" + fish_id.to_upper())
	if fish_id == "item_fish_big":
		message = tr("TOAST_FISH_BIG") + " " + message
	_reset()
	_toast(message)

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
	_animate_bobber()
	_update_line()
	if _angler != null and is_instance_valid(_angler) and _angler.is_inside_tree():
		var away := _angler.global_position - global_position
		away.y = 0.0
		if away.length() > LEAVE_DISTANCE:
			_reset()
			_toast(tr("TOAST_FISH_LEFT"))
			return
	if _timer > 0.0:
		return
	match state:
		State.WAITING:
			_start_bite()
		_:
			_reset()
			_toast(tr("TOAST_FISH_ESCAPED"))

func _start_bite() -> void:
	state = State.BITE
	_timer = BITE_WINDOW
	_hooked_fish = _roll_fish()
	_pulls_needed = PULLS_BIG if _hooked_fish == "item_fish_big" else PULLS_SMALL
	_pulls_done = 0
	_show_bite_mark(true)
	_sound("bite")
	_vibrate(120)
	_toast(tr("TOAST_FISH_BITE"))

func _roll_fish() -> String:
	var progression := InteractionManager.get_progression()
	var level := int(progression.call("get_level")) if progression != null else 1
	if level >= BIG_FISH_LEVEL and _rng.randf() < 0.35:
		return "item_fish_big"
	return "item_fish"

func _reset() -> void:
	state = State.IDLE
	_timer = 0.0
	_hooked_fish = ""
	_pulls_needed = 0
	_pulls_done = 0
	_show_bobber(false)
	_show_bite_mark(false)
	_hold_focus(false)
	if _line != null:
		_line.visible = false
	var hud := _hud()
	if hud != null and hud.has_method("clear_gauge"):
		hud.call("clear_gauge")

## Tire le poisson, l'ajoute au sac et récompense. Retourne l'identifiant de l'objet.
func catch_fish() -> String:
	var progression := InteractionManager.get_progression()
	var fish_id := _hooked_fish if _hooked_fish != "" else _roll_fish()
	var inventory := InteractionManager.get_inventory()
	if inventory != null:
		inventory.add_item(fish_id, 1)
	if progression != null:
		progression.call("add_stat", "stat_fished", 1)
		progression.call("add_xp_for", "fish")
	_sound("splash")
	caught.emit(fish_id)
	return fish_id

# --- Retours à l'écran -----------------------------------------------------------------------------

## Pendant la pêche, l'invite reste affichée même si le joueur regarde ailleurs.
func _hold_focus(value: bool) -> void:
	var manager := InteractionManager.get_instance()
	if manager == null or not manager.has_method("set_forced_target"):
		return
	if value:
		manager.call("set_forced_target", self)
	elif manager.get("_forced") == self:
		manager.call("set_forced_target", null)

func _update_gauge() -> void:
	var hud := _hud()
	if hud != null and hud.has_method("set_gauge") and _pulls_needed > 0:
		hud.call("set_gauge", tr("HUD_FISH_REEL"), float(_pulls_done) / float(_pulls_needed))

func _place_bobber() -> void:
	if _bobber == null:
		return
	var offset := _bobber_rest
	if _angler != null and is_instance_valid(_angler) and _angler.is_inside_tree() and is_inside_tree():
		var toward := _angler.global_position - global_position
		toward.y = 0.0
		if toward.length() > 0.5:
			var reach := clampf(toward.length() - 4.4, 0.4, 2.6)
			var local := global_transform.basis.inverse() * (toward.normalized() * reach)
			offset = Vector3(local.x, _bobber_rest.y, local.z)
	_bobber.position = offset
	if _bite_mark != null:
		_bite_mark.position = offset + Vector3(0.0, 0.75, 0.0)

func _animate_bobber() -> void:
	if _bobber == null:
		return
	var t := Time.get_ticks_msec()
	match state:
		State.BITE:
			_bobber.position.y = 0.02 + sin(t * 0.02) * 0.07
		State.REELING:
			_bobber.position.y = 0.06 + sin(t * 0.03) * 0.05
		_:
			_bobber.position.y = 0.12 + sin(t * 0.003) * 0.015
	if _bite_mark != null and _bite_mark.visible:
		_bite_mark.scale = Vector3.ONE * (1.0 + 0.2 * sin(t * 0.02))

## Fil de pêche tendu entre la main du pêcheur et le bouchon.
func _update_line() -> void:
	if _line == null or _bobber == null or _angler == null or not is_instance_valid(_angler) or not _angler.is_inside_tree():
		return
	_line.visible = _bobber.visible
	_line_mesh.clear_surfaces()
	var from := to_local(_angler.global_position + Vector3(0.0, 1.5, 0.0))
	var to := _bobber.position
	_line_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for i in 9:
		var t := float(i) / 8.0
		var point := from.lerp(to, t)
		# Léger ventre du fil, tendu quand le poisson tire.
		point.y -= sin(t * PI) * (0.08 if state != State.WAITING else 0.45)
		_line_mesh.surface_add_vertex(point)
	_line_mesh.surface_end()

func _sound(event_name: String) -> void:
	var sfx := InteractionManager.get_sfx()
	if sfx != null and sfx.has_method("play_event"):
		sfx.call("play_event", event_name)

func _vibrate(milliseconds: int) -> void:
	if PlatformInfo.is_touch():
		Input.vibrate_handheld(milliseconds)

func _show_bobber(value: bool) -> void:
	if _bobber != null:
		_bobber.visible = value

func _show_bite_mark(value: bool) -> void:
	if _bite_mark != null:
		_bite_mark.visible = value

func _hud() -> Node:
	var tree := get_tree()
	return tree.get_first_node_in_group("hud") as Node if tree != null else null

func _toast(message: String) -> void:
	var hud := _hud()
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
	_bobber.position = _bobber_rest
	_bobber.visible = false
	add_child(_bobber)
	# Signal de touche : un « ! » bien visible au-dessus du bouchon.
	_bite_mark = Label3D.new()
	_bite_mark.text = "!"
	_bite_mark.font_size = 160
	_bite_mark.pixel_size = 0.006
	_bite_mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bite_mark.no_depth_test = true
	_bite_mark.modulate = Color(1.0, 0.85, 0.2)
	_bite_mark.outline_size = 36
	_bite_mark.outline_modulate = Color(0.1, 0.05, 0.0)
	_bite_mark.position = _bobber_rest + Vector3(0.0, 0.75, 0.0)
	_bite_mark.visible = false
	add_child(_bite_mark)
	_line = MeshInstance3D.new()
	_line_mesh = ImmediateMesh.new()
	_line.mesh = _line_mesh
	var thread := StandardMaterial3D.new()
	thread.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	thread.albedo_color = Color(0.95, 0.95, 0.9)
	_line.material_override = thread
	_line.visible = false
	add_child(_line)
	# Zone de visée : le joueur s'approche du bord.
	var trigger := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 5.6
	shape.height = 1.6
	trigger.shape = shape
	trigger.position = Vector3(0.0, 0.6, 0.0)
	add_child(trigger)
