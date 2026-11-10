class_name VfxWind
extends RefCounted
## Vent sur la végétation basse : enveloppe les matériaux des maillages "soufflés"
## (herbe, buissons, fleurs) dans un ShaderMaterial (wind_sway.gdshader) qui lit la
## texture/couleur d'origine. Le joueur est exposé via l'uniforme global player_pos
## (posé chaque frame par landscape_manager) pour la pliure locale.

const SHADER := "res://assets/vfx/shaders/wind_sway.gdshader"
const WINDY_KEYS := ["grass", "shrub", "flowers"]

static var _shader: Shader

## Vrai si la clé de prop doit bouger au vent.
static func is_windy(glb_key: String) -> bool:
	return WINDY_KEYS.has(glb_key)

## Copie le maillage et remplace les matériaux de ses surfaces par le shader de vent.
static func apply_to_mesh(mesh: Mesh, glb_key: String, strength: float) -> Mesh:
	if not is_windy(glb_key) or mesh == null:
		return mesh
	if _shader == null:
		_shader = load(SHADER)
	var copy := mesh.duplicate()
	for si in range(copy.get_surface_count()):
		copy.surface_set_material(si, make_wind_material(copy.surface_get_material(si), strength, mesh.get_aabb().size.y))
	return copy

## ShaderMaterial de vent construit à partir d'un StandardMaterial3D d'origine.
static func make_wind_material(base: Material, strength: float, mesh_height: float) -> ShaderMaterial:
	var sh := ShaderMaterial.new()
	sh.shader = _shader if _shader != null else load(SHADER)
	sh.set_shader_parameter("wind_strength", strength)
	sh.set_shader_parameter("top_y", maxf(mesh_height, 0.05))
	var std := base as StandardMaterial3D
	if std != null:
		sh.set_shader_parameter("albedo_texture", std.albedo_texture)
		sh.set_shader_parameter("has_texture", std.albedo_texture != null)
		sh.set_shader_parameter("albedo_color", std.albedo_color)
		sh.set_shader_parameter("use_vertex_color", std.vertex_color_use_as_albedo)
		sh.set_shader_parameter("roughness", std.roughness)
	else:
		sh.set_shader_parameter("has_texture", false)
		sh.set_shader_parameter("albedo_color", Color.WHITE)
	return sh
