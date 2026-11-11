extends Node
## Surveille la fluidité : si la moyenne des images par seconde reste basse, la qualité baisse
## d'un cran (moins de précipitations, puis ombres coupées et rendu 3D réduit). Un compteur
## (FPS, appels de dessin, mémoire) s'affiche par 5 appuis rapides en haut au centre de l'écran,
## ou avec F3, et l'état est écrit dans user://perf.log pour mesurer sur un appareil réel.

const LOW_FPS := 40.0
const SAMPLE_SECONDS := 6.0
const MAX_LEVEL := 2
const TAP_COUNT := 5
const TAP_WINDOW := 3.0

var enabled: bool = DisplayServer.get_name() != "headless"
var level: int = 0
## "auto" : s'adapte aux FPS ; "high" : qualité maximale fixe ; "low" : qualité réduite fixe.
var mode: String = "auto"
var _accum: float = 0.0
var _frames: int = 0
var _label: Label
var _layer: CanvasLayer
var _taps: Array = []
var _log_timer: float = 0.0
var _shadowless: Array = []

func _ready() -> void:
	set_process(enabled)
	set_process_input(enabled)

func _process(delta: float) -> void:
	_accum += delta
	_frames += 1
	if _label != null and _label.visible:
		_label.text = report()
	if _accum < SAMPLE_SECONDS:
		return
	var average := float(_frames) / _accum
	_accum = 0.0
	_frames = 0
	_log_timer += SAMPLE_SECONDS
	if _log_timer >= 30.0 and _label != null and _label.visible:
		_log_timer = 0.0
		_write_log(average)
	if mode == "auto" and average < LOW_FPS and level < MAX_LEVEL:
		set_level(level + 1)

## Décision de baisse de qualité (testable) : vrai si la moyenne justifie un cran de moins.
static func should_degrade(average_fps: float, current_level: int) -> bool:
	return average_fps < LOW_FPS and current_level < MAX_LEVEL

func set_mode(new_mode: String) -> void:
	mode = new_mode
	if mode == "high":
		set_level(0)
	elif mode == "low":
		set_level(MAX_LEVEL)

func set_overlay_visible(value: bool) -> void:
	if (_label != null and _label.visible) != value:
		toggle_overlay()

func set_level(new_level: int) -> void:
	level = clampi(new_level, 0, MAX_LEVEL)
	get_tree().call_group("fx_quality", "set_fx_level", level)
	var weather := InteractionManager.get_weather()
	if weather != null and weather.has_method("set_low_quality"):
		weather.call("set_low_quality", level >= 1)
	if level >= 2:
		for light in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
			if (light as DirectionalLight3D).shadow_enabled:
				(light as DirectionalLight3D).shadow_enabled = false
				_shadowless.append(light)
		get_viewport().scaling_3d_scale = 0.8
	else:
		for light in _shadowless:
			if is_instance_valid(light):
				(light as DirectionalLight3D).shadow_enabled = true
		_shadowless.clear()
		get_viewport().scaling_3d_scale = 1.0
	print("PerformanceGuard: qualité niveau %d" % level)

func report() -> String:
	return "%d FPS | q%d | %d draws | %.0f Mo" % [
		int(Engine.get_frames_per_second()), level,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		float(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576.0]

func toggle_overlay() -> void:
	if _label == null:
		_layer = CanvasLayer.new()
		_layer.layer = 100
		add_child(_layer)
		_label = Label.new()
		_label.position = Vector2(12, 4)
		_label.add_theme_font_size_override("font_size", 20)
		_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
		_label.add_theme_color_override("font_outline_color", Color.BLACK)
		_label.add_theme_constant_override("outline_size", 6)
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_layer.add_child(_label)
		_label.visible = false
	_label.visible = not _label.visible

func _write_log(average: float) -> void:
	var file := FileAccess.open("user://perf.log", FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open("user://perf.log", FileAccess.WRITE)
	if file == null:
		return
	file.seek_end()
	file.store_line("%s moyenne=%.1f %s" % [Time.get_datetime_string_from_system(), average, report()])

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		toggle_overlay()
		return
	var at := Vector2.ZERO
	var tapped := false
	if event is InputEventScreenTouch and event.pressed:
		tapped = true
		at = event.position
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		tapped = true
		at = event.position
	if not tapped:
		return
	var size := get_viewport().get_visible_rect().size
	if absf(at.x - size.x * 0.5) > 120.0 or at.y > 70.0:
		return
	var now := Time.get_ticks_msec() / 1000.0
	_taps.append(now)
	while not _taps.is_empty() and now - float(_taps[0]) > TAP_WINDOW:
		_taps.pop_front()
	if _taps.size() >= TAP_COUNT:
		_taps.clear()
		toggle_overlay()
