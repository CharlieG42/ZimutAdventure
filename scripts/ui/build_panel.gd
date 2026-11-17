class_name BuildPanel
extends HBoxContainer
## Déplacement des constructions. Quand on vise un meuble ou un abri : bouton « Déplacer ».
## Pendant le déplacement la construction devient un fantôme (vert = posable, rouge = non)
## qui suit le joueur ; boutons Tourner / Poser / Annuler. Clavier : G déplacer, R tourner,
## E ou Entrée poser, X annuler.

## Distance du fantôme devant le joueur.
const HOLD_DISTANCE := 3.6
const BUTTON_SIZE := Vector2(150.0, 72.0)

var _spawner: Node
var _player: Node3D
var _target: Node3D
var _grab: Button
var _rotate: Button
var _drop: Button
var _cancel: Button

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 14)
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 24)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	_grab = _make_button("ACTION_MOVE", _on_grab)
	_rotate = _make_button("ACTION_ROTATE", func(): _spawner_call("rotate_move"))
	_drop = _make_button("ACTION_DROP", _on_drop)
	_cancel = _make_button("ACTION_CANCEL", func(): _spawner_call("cancel_move"))
	_refresh()
	InteractionManager.focus_changed.connect(_on_focus_changed)

func set_context(player: Node3D) -> void:
	_player = player

func _make_button(key: String, handler: Callable) -> Button:
	var button := Button.new()
	button.text = tr(key)
	button.custom_minimum_size = BUTTON_SIZE
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 24)
	button.pressed.connect(handler)
	add_child(button)
	return button

func _get_spawner() -> Node:
	if _spawner == null or not is_instance_valid(_spawner):
		_spawner = get_tree().get_first_node_in_group("structure_spawner") if is_inside_tree() else null
		if _spawner != null and not _spawner.is_connected("move_finished", _on_move_finished):
			_spawner.connect("move_finished", _on_move_finished)
	return _spawner

func _spawner_call(method: String) -> void:
	var spawner := _get_spawner()
	if spawner != null:
		spawner.call(method)

func is_moving() -> bool:
	var spawner := _get_spawner()
	return spawner != null and bool(spawner.call("is_moving"))

func _on_focus_changed(target: Node3D) -> void:
	var spawner := _get_spawner()
	_target = spawner.call("movable_for", target) as Node3D if spawner != null and target != null else null
	_refresh()

func _refresh() -> void:
	var moving := is_moving()
	_grab.visible = not moving and _target != null and is_instance_valid(_target)
	_rotate.visible = moving
	_drop.visible = moving
	_cancel.visible = moving
	visible = moving or _grab.visible

func _on_grab() -> void:
	var spawner := _get_spawner()
	if spawner == null or _target == null or not is_instance_valid(_target):
		return
	if bool(spawner.call("begin_move", _target)):
		_target = null
		_toast(tr("TOAST_MOVE_HINT"))
		_refresh()

func _on_drop() -> void:
	_spawner_call("confirm_move")

func _on_move_finished(ok: bool, message_key: String) -> void:
	_toast(tr(message_key))
	if ok:
		_refresh()

func _process(_delta: float) -> void:
	var spawner := _get_spawner()
	var moving := spawner != null and bool(spawner.call("is_moving"))
	if moving != _rotate.visible:
		_refresh()
	if not moving or _player == null or not is_instance_valid(_player):
		return
	var forward := -_player.global_transform.basis.z
	forward.y = 0.0
	if forward.length() < 0.01:
		return
	var origin := _player.global_position + forward.normalized() * HOLD_DISTANCE
	spawner.call("update_move", origin, _player.global_position)

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key := (event as InputEventKey).physical_keycode
	if is_moving():
		match key:
			KEY_R:
				_spawner_call("rotate_move")
			KEY_X:
				_spawner_call("cancel_move")
			KEY_ENTER, KEY_KP_ENTER:
				_spawner_call("confirm_move")
			_:
				return
		get_viewport().set_input_as_handled()
	elif key == KEY_G and _grab.visible:
		_on_grab()
		get_viewport().set_input_as_handled()

func _toast(message: String) -> void:
	var tree := get_tree()
	var hud := tree.get_first_node_in_group("hud") as Node if tree != null else null
	if hud != null and hud.has_method("show_toast"):
		hud.show_toast(message, 2.4)
