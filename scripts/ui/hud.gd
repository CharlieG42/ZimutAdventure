extends CanvasLayer

@onready var interact_button: Button = $SafeArea/VBox/BottomBar/InteractButton
@onready var journal_button: Button = $SafeArea/VBox/BottomBar/JournalButton
@onready var map_button: Button = $SafeArea/VBox/BottomBar/MapButton
@onready var sprint_button: Button = $SafeArea/VBox/BottomBar/SprintButton
@onready var compass_label: Label = $SafeArea/VBox/TopBar/CompassLabel
@onready var clock_label: Label = $SafeArea/VBox/TopBar/ClockLabel
@onready var interact_prompt: Label = $SafeArea/VBox/CenterPrompt
@onready var toast: Label = $SafeArea/VBox/Toast
@onready var joystick: Control = $VirtualJoystick
@onready var touch_look: Control = $TouchLook

var _player: CharacterBody3D
var _toast_timer: SceneTreeTimer
var _interaction_manager: Node
var _inventory: Node
var _day_night: Node

func _ready() -> void:
	var is_touch := DisplayServer.get_name() == "android"
	interact_button.visible = is_touch
	sprint_button.visible = is_touch
	journal_button.visible = is_touch
	map_button.visible = is_touch
	joystick.visible = is_touch
	touch_look.visible = is_touch

	interact_button.pressed.connect(_on_interact_pressed)
	sprint_button.button_down.connect(func(): Input.action_press("sprint"))
	sprint_button.button_up.connect(func(): Input.action_release("sprint"))
	journal_button.pressed.connect(func(): Input.action_press("open_journal"))
	map_button.pressed.connect(func(): Input.action_press("open_map"))

	_interaction_manager = InteractionManager
	_inventory = Inventory
	_day_night = DayNightCycle

	if _interaction_manager != null:
		_interaction_manager.connect("focus_changed", _on_focus_changed)
	if _inventory != null:
		_inventory.connect("item_added", _on_item_added)
	if _day_night != null:
		_day_night.connect("time_changed", _on_time_changed)

	interact_prompt.visible = false
	toast.visible = false

	_player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	if _player != null:
		joystick.moved.connect(_player.set_joystick_vector)
		touch_look.look_delta.connect(_player.apply_touch_look)

func _process(_delta: float) -> void:
	if _player != null:
		var yaw_deg := fmod(rad_to_deg(_player.global_rotation.y) + 360.0, 360.0)
		compass_label.text = "%s %03d°" % [tr("HUD_NORTH"), int(yaw_deg)]

func show_toast(message: String, duration: float = 2.0) -> void:
	toast.text = message
	toast.visible = true
	if _toast_timer != null:
		_toast_timer.timeout.disconnect(_hide_toast)
	_toast_timer = get_tree().create_timer(duration)
	_toast_timer.timeout.connect(_hide_toast)

func _hide_toast() -> void:
	toast.visible = false

func _on_interact_pressed() -> void:
	if _player != null and _player.has_method("_try_interact"):
		_player.call("_try_interact")

func _on_focus_changed(target: Node3D) -> void:
	if target != null and target is Interactable:
		var interactable := target as Interactable
		interact_prompt.text = tr(interactable.get_prompt())
		interact_prompt.visible = true
		interact_button.disabled = not interactable.can_interact()
	else:
		interact_prompt.visible = false
		interact_button.disabled = true

func _on_item_added(item_id: String, amount: int) -> void:
	show_toast(tr("TOAST_COLLECTED") % [amount, tr("ITEM_" + item_id.to_upper())])

func _on_time_changed(hour: float) -> void:
	clock_label.text = "%02d:%02d" % [int(hour), int(fmod(hour, 1.0) * 60.0)]
