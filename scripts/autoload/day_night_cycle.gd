extends Node

signal time_changed(hour: float)
signal phase_changed(phase: String)

const PHASE_DAY := "day"
const PHASE_DUSK := "dusk"
const PHASE_NIGHT := "night"
const PHASE_DAWN := "dawn"

@export var enabled: bool = true
@export var day_length: float = 600.0
@export var start_hour: float = 10.0

var hour: float = start_hour
var sun: DirectionalLight3D
var environment: Environment

var _phase: String = PHASE_DAY
var _base_sun_rotation: Vector3

func _ready() -> void:
	hour = fmod(start_hour, 24.0)

func bind_world(sun_light: DirectionalLight3D, env: Environment) -> void:
	sun = sun_light
	environment = env
	_base_sun_rotation = sun.rotation
	_apply()

func _process(delta: float) -> void:
	if not enabled:
		return
	hour = fmod(hour + 24.0 * delta / day_length, 24.0)
	_apply()
	time_changed.emit(hour)

func get_phase() -> String:
	return _phase

func set_hour(new_hour: float) -> void:
	hour = fmod(new_hour, 24.0)
	_apply()

func _apply() -> void:
	if sun == null:
		return
	var day_factor := _day_factor()
	sun.rotation.x = _base_sun_rotation.x + (hour - 12.0) / 24.0 * TAU
	sun.visible = day_factor > 0.02
	sun.light_energy = lerp(0.0, 1.4, day_factor)
	sun.light_color = Color(0.55, 0.50, 0.60).lerp(Color(1.0, 0.90, 0.75), day_factor)
	if environment != null:
		var sky: Sky = environment.sky
		if sky != null and sky.sky_material is ProceduralSkyMaterial:
			var sky_mat: ProceduralSkyMaterial = sky.sky_material
			sky_mat.sky_top_color = Color(0.10, 0.13, 0.28).lerp(Color(0.45, 0.65, 0.85), day_factor)
			sky_mat.sky_horizon_color = Color(0.05, 0.06, 0.12).lerp(Color(0.85, 0.60, 0.40), day_factor)
			sky_mat.ground_bottom_color = Color(0.02, 0.02, 0.05).lerp(Color(0.35, 0.22, 0.14), day_factor)
			sky_mat.ground_horizon_color = Color(0.03, 0.03, 0.07).lerp(Color(0.60, 0.40, 0.25), day_factor)
		if environment.background_mode == Environment.BG_SKY:
			environment.ambient_light_color = Color(0.15, 0.16, 0.22).lerp(Color(0.75, 0.65, 0.55), day_factor)
			environment.ambient_light_energy = lerp(0.15, 0.6, day_factor)
	_update_phase()

func _day_factor() -> float:
	return clamp(cos((hour - 12.0) / 24.0 * TAU), 0.0, 1.0)

func _update_phase() -> void:
	var h := hour
	var new_phase: String
	if h >= 6.0 and h < 17.0:
		new_phase = PHASE_DAY
	elif h >= 17.0 and h < 20.0:
		new_phase = PHASE_DUSK
	elif h >= 20.0 or h < 4.0:
		new_phase = PHASE_NIGHT
	else:
		new_phase = PHASE_DAWN
	if new_phase != _phase:
		_phase = new_phase
		phase_changed.emit(_phase)
