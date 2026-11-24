extends Node
## Surveille la fluidité : si la moyenne des images par seconde reste basse, la qualité baisse
## d'un cran (moins de précipitations, puis ombres allégées et rendu 3D réduit).
## Les ombres ne sont jamais coupées : en rendu Compatibility, un soleil sans ombre éclaire
## par un autre chemin et toute la scène devient plus sombre et plus terne (≈ -10 %). Un compteur
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
## Réglages d'origine des soleils allégés : lumière -> [mode, portée, fondu des cascades].
var _light_defaults: Dictionary = {}
## Ombres allégées : une seule cascade, portée courte, atlas réduit, bords nets.
const LOW_SHADOW_DISTANCE := 45.0
const LOW_SHADOW_ATLAS := 1024

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
	_apply_shadow_quality(level >= 2)
	_apply_env_quality(level)
	# Palier intermédiaire 0.9 au niveau 1, 0.8 au niveau 2.
	get_viewport().scaling_3d_scale = 0.8 if level >= 2 else (0.9 if level == 1 else 1.0)
	print("PerformanceGuard: qualité niveau %d" % level)

## Passes plein écran chères en Compatibility : SSAO coupé dès le niveau 1, glow + MSAA
## au niveau 2. Valeurs d'origine restaurées au niveau 0.
var _env_defaults: Dictionary = {}

func _apply_env_quality(lvl: int) -> void:
	var env_node := get_tree().root.find_children("*", "WorldEnvironment", true, false)
	if env_node.is_empty():
		return
	var environment := (env_node[0] as WorldEnvironment).environment
	if environment == null:
		return
	if _env_defaults.is_empty():
		_env_defaults = {
			"ssao": environment.ssao_enabled,
			"glow": environment.glow_enabled,
			"msaa": int(ProjectSettings.get_setting_with_override("rendering/anti_aliasing/quality/msaa_3d")),
			"ssao_radius": environment.ssao_radius,
			"ssao_intensity": environment.ssao_intensity,
		}
	environment.ssao_enabled = bool(_env_defaults["ssao"]) if lvl < 1 else false
	environment.glow_enabled = bool(_env_defaults["glow"]) if lvl < 2 else false
	# P2-10 : en qualité haute (niveau 0) sur PC uniquement, SSAO un peu plus large/dense.
	var pc_high := lvl == 0 and not (OS.has_feature("android") or OS.has_feature("ios"))
	environment.ssao_radius = 2.4 if pc_high else float(_env_defaults["ssao_radius"])
	environment.ssao_intensity = 1.7 if pc_high else float(_env_defaults["ssao_intensity"])
	var msaa_default := int(_env_defaults["msaa"])
	get_viewport().msaa_3d = msaa_default if lvl < 2 else Viewport.MSAA_DISABLED

func _apply_shadow_quality(low: bool) -> void:
	# Valeurs normales : celles du projet (avec les surcharges .mobile sur Android).
	var atlas := int(ProjectSettings.get_setting_with_override("rendering/lights_and_shadows/directional_shadow/size"))
	var soft := int(ProjectSettings.get_setting_with_override("rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality"))
	RenderingServer.directional_shadow_atlas_set_size(mini(LOW_SHADOW_ATLAS, atlas) if low else atlas, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(
			RenderingServer.SHADOW_QUALITY_HARD if low else soft as RenderingServer.ShadowQuality)
	for node in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
		var light := node as DirectionalLight3D
		if not light.shadow_enabled:
			continue
		if low:
			if not _light_defaults.has(light):
				_light_defaults[light] = [light.directional_shadow_mode, light.directional_shadow_max_distance,
						light.directional_shadow_blend_splits]
			light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
			light.directional_shadow_max_distance = minf(LOW_SHADOW_DISTANCE, light.directional_shadow_max_distance)
			light.directional_shadow_blend_splits = false
		elif _light_defaults.has(light):
			var saved: Array = _light_defaults[light]
			light.directional_shadow_mode = saved[0]
			light.directional_shadow_max_distance = saved[1]
			light.directional_shadow_blend_splits = saved[2]
	if not low:
		_light_defaults.clear()

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
