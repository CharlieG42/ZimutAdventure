class_name KineticScroll
extends ScrollContainer
## Défilement tactile réactif : on peut faire glisser le doigt n'importe où dans la liste
## (même sur une carte ou un bouton), avec inertie au relâchement.
## Un simple appui reste un clic ; le glissement n'est pris qu'au-delà de DRAG_THRESHOLD.

const DRAG_THRESHOLD := 8.0
## Décélération de l'inertie (par seconde) et vitesse en dessous de laquelle on s'arrête.
const FRICTION := 4.0
const MIN_VELOCITY := 20.0
const MAX_VELOCITY := 6000.0

var _pressed: bool = false
var _dragging: bool = false
var _start_y: float = 0.0
var _last_y: float = 0.0
var _velocity: float = 0.0
var _press_time_ms: int = 0
var _remainder: float = 0.0

func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll_deadzone = 0

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index != MOUSE_BUTTON_LEFT:
			return
		if button.pressed:
			if get_global_rect().has_point(button.global_position):
				_begin(button.global_position.y)
		else:
			_end()
	elif event is InputEventMouseMotion and _pressed:
		_drag((event as InputEventMouseMotion).global_position.y, event)

func _begin(y: float) -> void:
	_pressed = true
	_dragging = false
	_start_y = y
	_last_y = y
	_velocity = 0.0
	_press_time_ms = Time.get_ticks_msec()

func _drag(y: float, event: InputEvent) -> void:
	if not _dragging:
		if absf(y - _start_y) < DRAG_THRESHOLD:
			return
		_dragging = true
		_cancel_button_press()
	var delta_y := y - _last_y
	_last_y = y
	scroll_vertical = int(scroll_vertical - delta_y)
	var now := Time.get_ticks_msec()
	var dt := maxf(float(now - _press_time_ms) / 1000.0, 0.001)
	_press_time_ms = now
	# Vitesse lissée pour une inertie stable.
	_velocity = lerpf(_velocity, -delta_y / dt, 0.6)
	_velocity = clampf(_velocity, -MAX_VELOCITY, MAX_VELOCITY)
	get_viewport().set_input_as_handled()

func _end() -> void:
	if _pressed and _dragging:
		# Doigt arrêté avant de lever : pas d'inertie.
		if Time.get_ticks_msec() - _press_time_ms > 120:
			_velocity = 0.0
		get_viewport().set_input_as_handled()
	else:
		_velocity = 0.0
	_pressed = false
	_dragging = false

## Le bouton sous le doigt est déjà « enfoncé » : on annule pour qu'il ne se déclenche pas.
func _cancel_button_press() -> void:
	var hovered := get_viewport().gui_get_hovered_control()
	var node: Node = hovered
	while node != null and node != self:
		if node is BaseButton:
			var base := node as BaseButton
			base.disabled = true
			base.set_deferred("disabled", false)
			break
		node = node.get_parent()

func _process(delta: float) -> void:
	if _pressed or absf(_velocity) < MIN_VELOCITY:
		_velocity = 0.0 if not _pressed else _velocity
		return
	var before := scroll_vertical
	# Reste fractionnaire cumulé : à 60+ fps un pas est souvent inférieur à 1 px.
	_remainder += _velocity * delta
	var step := int(_remainder)
	_remainder -= float(step)
	scroll_vertical = before + step
	if step != 0 and scroll_vertical == before:
		_velocity = 0.0
		return
	_velocity = move_toward(_velocity, 0.0, absf(_velocity) * FRICTION * delta)

## API de test : simule un glissement vertical complet.
func simulate_drag(from_y: float, to_y: float) -> void:
	_begin(from_y)
	_drag(to_y, null)
	_end()
