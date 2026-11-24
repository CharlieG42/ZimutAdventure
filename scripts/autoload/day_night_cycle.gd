extends Node

signal time_changed(hour: float)
signal phase_changed(phase: String)
signal day_changed(day: int)

const PHASE_DAY := "day"
const PHASE_DUSK := "dusk"
const PHASE_NIGHT := "night"
const PHASE_DAWN := "dawn"

@export var enabled: bool = true
@export var day_length: float = 600.0
@export var start_hour: float = 10.0

var hour: float = start_hour
## Jours écoulés depuis le début de la partie (le calendrier est tenu par Weather).
var day: int = 0
## Aspect imposé par la météo (0 = ciel dégagé) et la saison.
var weather_dim: float = 0.0
var weather_fog: float = 0.0
var season_tint: Color = Color.WHITE
var sun: DirectionalLight3D
## Lune : lumière froide et bleutée qui éclaire la nuit (sans ombres, pour rester légère).
var moon: DirectionalLight3D
var environment: Environment

var _phase: String = PHASE_DAY
var _base_sun_rotation: Vector3

func _ready() -> void:
	hour = fmod(start_hour, 24.0)

func bind_world(sun_light: DirectionalLight3D, env: Environment) -> void:
	sun = sun_light
	if sun != null:
		sun.add_to_group("sun")  # lu par le flare solaire (scripts/vfx/sun_flare.gd)
	environment = env
	_base_sun_rotation = sun.rotation
	_ensure_moon()
	_apply()

func _ensure_moon() -> void:
	if moon != null and is_instance_valid(moon):
		return
	if sun == null or sun.get_parent() == null:
		return
	moon = DirectionalLight3D.new()
	moon.name = "Moon"
	moon.shadow_enabled = false
	moon.light_color = Color(0.45, 0.62, 1.0)
	moon.light_energy = 0.0
	moon.visible = false
	moon.rotation_degrees = Vector3(-42.0, 205.0, 0.0)
	sun.get_parent().add_child.call_deferred(moon)

func _process(delta: float) -> void:
	if not enabled:
		return
	var next_hour := hour + 24.0 * delta / day_length
	if next_hour >= 24.0:
		day += 1
		day_changed.emit(day)
	hour = fmod(next_hour, 24.0)
	_apply()
	time_changed.emit(hour)

func get_phase() -> String:
	return _phase

func set_hour(new_hour: float) -> void:
	var wrapped := fmod(new_hour, 24.0)
	# Dormir jusqu'au matin fait passer minuit : un nouveau jour commence.
	if wrapped < hour - 6.0:
		day += 1
		day_changed.emit(day)
	hour = wrapped
	_apply()

func _apply() -> void:
	if sun == null:
		return
	var day_factor := _day_factor()
	sun.rotation.x = _base_sun_rotation.x + (hour - 12.0) / 24.0 * TAU
	sun.visible = day_factor > 0.02
	var cloud := 1.0 - 0.55 * weather_dim
	# Soleil bas = lumière dorée, plus orangée et plus rasante ; midi = blanc chaud.
	var low_sun := 1.0 - smoothstep(0.12, 0.7, day_factor)
	sun.light_energy = lerp(0.0, 1.55, pow(day_factor, 0.55)) * cloud
	sun.light_color = (Color(1.0, 0.93, 0.80).lerp(Color(1.0, 0.64, 0.36), low_sun * 0.85) * season_tint).clamp()
	if moon != null and is_instance_valid(moon):
		moon.light_energy = lerp(1.1, 0.0, smoothstep(0.0, 0.25, day_factor)) * (1.0 - 0.5 * weather_dim)
		moon.visible = moon.light_energy > 0.01
	if environment != null:
		var sky: Sky = environment.sky
		if sky != null and sky.sky_material is ShaderMaterial:
			# Ciel custom (assets/vfx/sky/sky.gdshader) : étoiles, lune, nuages animés.
			var mat := sky.sky_material as ShaderMaterial
			mat.set_shader_parameter("top_color", Color(0.09, 0.09, 0.27).lerp(Color(0.2, 0.45, 0.86), day_factor))
			var horizon_day2 := Color(0.98, 0.80, 0.58).lerp(Color(1.0, 0.5, 0.24), low_sun)
			mat.set_shader_parameter("horizon_color", Color(0.20, 0.12, 0.30).lerp(horizon_day2, smoothstep(0.0, 0.3, day_factor)))
			mat.set_shader_parameter("ground_color", Color(0.02, 0.02, 0.05).lerp(Color(0.35, 0.22, 0.14), day_factor))
			mat.set_shader_parameter("day_factor", day_factor)
			mat.set_shader_parameter("energy", lerp(0.3, 1.0, day_factor) * (1.0 - 0.35 * weather_dim))
			var sun_t: Transform3D = sun.global_transform if sun.is_inside_tree() else sun.transform
			mat.set_shader_parameter("sun_direction", sun_t.basis.z.normalized())
			mat.set_shader_parameter("sun_color", sun.light_color)
			if moon != null and is_instance_valid(moon):
				var moon_t: Transform3D = moon.global_transform if moon.is_inside_tree() else moon.transform
				mat.set_shader_parameter("moon_direction", moon_t.basis.z.normalized())
			var night_factor := 1.0 - day_factor
			mat.set_shader_parameter("star_amount", smoothstep(0.05, 0.4, night_factor))
			mat.set_shader_parameter("cloud_cover", weather_dim)
		elif sky != null and sky.sky_material is ProceduralSkyMaterial:
			var sky_mat: ProceduralSkyMaterial = sky.sky_material
			sky_mat.sky_top_color = Color(0.09, 0.09, 0.27).lerp(Color(0.2, 0.45, 0.86), day_factor)
			# Horizon : plus orangé quand le soleil est bas (aube, crépuscule).
			var horizon_day := Color(0.98, 0.80, 0.58).lerp(Color(1.0, 0.5, 0.24), low_sun)
			sky_mat.sky_horizon_color = Color(0.20, 0.12, 0.30).lerp(horizon_day, smoothstep(0.0, 0.3, day_factor))
			sky_mat.ground_bottom_color = Color(0.02, 0.02, 0.05).lerp(Color(0.35, 0.22, 0.14), day_factor)
			sky_mat.ground_horizon_color = sky_mat.sky_horizon_color.lerp(Color(0.6, 0.4, 0.25), 0.35)
			var night_factor := 1.0 - day_factor
			sky_mat.sky_cover_modulate = Color(0.15, 0.18, 0.30, 1.0).lerp(Color(0.9, 0.85, 0.8, 1.0), day_factor)
			sky_mat.sky_energy_multiplier = lerp(0.3, 1.0, day_factor) * (1.0 - 0.35 * weather_dim)
			sky_mat.ground_energy_multiplier = lerp(0.2, 1.0, day_factor)
		if environment.background_mode == Environment.BG_SKY:
			# Ombres froides (violet-bleu) sous une lumière chaude : le contraste de la direction artistique.
			var ambient_day := Color(0.60, 0.56, 0.82).lerp(Color(0.50, 0.42, 0.88), low_sun)
			environment.ambient_light_color = Color(0.36, 0.46, 0.80).lerp(ambient_day, smoothstep(0.0, 0.3, day_factor))
			environment.ambient_light_energy = lerp(0.95, 0.65, day_factor) * (1.0 - 0.2 * weather_dim)
			var nf := 1.0 - day_factor
			var fog_day := Color(0.86, 0.66, 0.5).lerp(Color(1.0, 0.5, 0.3), low_sun * 0.75)
			environment.fog_light_color = (Color(0.12, 0.10, 0.26).lerp(fog_day, day_factor) * season_tint).clamp()
			environment.fog_light_color = environment.fog_light_color.lerp(Color(0.62, 0.66, 0.72) * lerp(0.25, 1.0, day_factor), weather_fog * 0.6)
			environment.fog_light_energy = lerp(0.25, 0.65, day_factor)
			environment.fog_density = lerp(0.0012, 0.0024, day_factor) + weather_fog * 0.004
			environment.glow_enabled = true
			environment.glow_intensity = lerp(0.6, 0.9, day_factor)
			environment.glow_bloom = lerp(0.05, 0.15, day_factor)
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
