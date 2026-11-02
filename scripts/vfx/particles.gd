class_name VfxParticles
extends RefCounted
## Fabrique de particules 2D texturées (Kenney Particle Pack CC0, assets/vfx/particles/).
## Chaque effet a un repli procédural (quad uni) si la texture est absente.
## Godot 4 : le billboard et le blend mode se règlent sur le matériau de la draw pass
## (BaseMaterial3D), le fondu alpha sur le color_ramp (GradientTexture1D) du process material.

const TEX_ROOT := "res://assets/vfx/particles/"

static var _tex_cache: Dictionary = {}
static var _fade_tex: GradientTexture1D

static func tex(name: String) -> Texture2D:
	if _tex_cache.has(name):
		return _tex_cache[name]
	var t: Texture2D = load(TEX_ROOT + name + ".png")
	_tex_cache[name] = t
	return t

## Fondu alpha commun : opaque au début, transparent à la fin de vie.
static func _fade() -> GradientTexture1D:
	if _fade_tex != null:
		return _fade_tex
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.0)])
	_fade_tex = GradientTexture1D.new()
	_fade_tex.gradient = g
	return _fade_tex

## Matériau de la draw pass : billboard particules + blend additif (feu) ou mix (fumée).
static func _quad_material(texture: Texture2D, additive: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	if texture != null:
		m.albedo_texture = texture
	else:
		m.albedo_color = Color(1, 1, 1, 0.9)
	return m

static func _base_process() -> ParticleProcessMaterial:
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.25
	mat.direction = Vector3(0.0, 1.0, 0.0)
	mat.spread = 25.0
	mat.initial_velocity_min = 0.6
	mat.initial_velocity_max = 1.4
	mat.gravity = Vector3(0.0, 0.4, 0.0)
	mat.damping_min = 0.4
	mat.damping_max = 1.0
	mat.scale_min = 0.5
	mat.scale_max = 1.1
	mat.color_ramp = _fade()
	return mat

static func _make(texture_name: String, amount: int, lifetime: float, process: ParticleProcessMaterial,
		additive: bool, one_shot: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = one_shot
	p.explosiveness = 0.15 if one_shot else 0.0
	p.process_material = process
	var q := QuadMesh.new()
	q.size = Vector2(0.6, 0.6)
	q.material = _quad_material(tex(texture_name), additive)
	p.draw_pass_1 = q
	return p

## Feu de camp : flammes chaudes (additif) + fumée grise + braises. Renvoie l'émetteur de flammes.
static func campfire(parent: Node3D, at: Vector3, scale_factor: float = 1.0) -> GPUParticles3D:
	var s := maxf(0.4, scale_factor)
	var flames := _make("flame_02", 14, 0.9, _base_process(), true, false)
	flames.name = "FlameVfx"
	flames.position = at + Vector3(0.0, 0.25, 0.0)
	flames.process_material.emission_sphere_radius = 0.3 * s
	flames.process_material.scale_min = 0.35 * s
	flames.process_material.scale_max = 0.8 * s
	flames.process_material.color = Color(1.0, 0.62, 0.22)
	parent.add_child(flames)

	var smoke_mat := _base_process()
	smoke_mat.direction = Vector3(0.0, 1.0, 0.0)
	smoke_mat.spread = 12.0
	smoke_mat.initial_velocity_min = 0.5
	smoke_mat.initial_velocity_max = 0.9
	smoke_mat.gravity = Vector3(0.0, 0.15, 0.0)
	smoke_mat.scale_min = 0.8
	smoke_mat.scale_max = 1.6
	smoke_mat.color = Color(0.55, 0.53, 0.52, 0.8)
	var smoke := _make("smoke_03", 8, 2.6, smoke_mat, false, false)
	smoke.name = "SmokeVfx"
	smoke.position = at + Vector3(0.0, 0.7, 0.0)
	parent.add_child(smoke)

	var spark_mat := _base_process()
	spark_mat.gravity = Vector3(0.0, 1.2, 0.0)
	spark_mat.initial_velocity_min = 0.8
	spark_mat.initial_velocity_max = 1.8
	spark_mat.color = Color(1.0, 0.75, 0.3)
	var sparks := _make("spark_01", 5, 1.4, spark_mat, true, false)
	sparks.name = "SparkVfx"
	sparks.position = at + Vector3(0.0, 0.3, 0.0)
	parent.add_child(sparks)
	return flames

## Poussière de course/atterrissage (one-shot, disque doux poussière/neige).
static func dust_puff(parent: Node3D, at: Vector3, color: Color, amount: int = 10) -> GPUParticles3D:
	var mat := _base_process()
	mat.emission_sphere_radius = 0.35
	mat.direction = Vector3(0.0, 0.6, 0.0)
	mat.spread = 60.0
	mat.initial_velocity_min = 0.5
	mat.initial_velocity_max = 1.2
	mat.gravity = Vector3(0.0, -0.6, 0.0)
	mat.scale_min = 0.4
	mat.scale_max = 0.9
	mat.color = color
	var p := _make("circle_02", amount, 0.7, mat, false, true)
	p.position = at
	parent.add_child(p)
	p.emitting = true
	return p

## Éclats de roche en un coup (one-shot, gravité forte, couleur pierre).
static func rock_shards(parent: Node3D, at: Vector3, color: Color, amount: int = 10) -> GPUParticles3D:
	var mat := _base_process()
	mat.emission_sphere_radius = 0.3
	mat.direction = Vector3(0.0, 1.0, 0.0)
	mat.spread = 75.0
	mat.initial_velocity_min = 2.2
	mat.initial_velocity_max = 4.5
	mat.gravity = Vector3(0.0, -9.0, 0.0)
	mat.scale_min = 0.12
	mat.scale_max = 0.28
	mat.color = color
	var p := _make("spark_02", amount, 0.9, mat, false, true)
	p.position = at
	p.explosiveness = 0.9
	parent.add_child(p)
	p.emitting = true
	return p

## Lueur d'interaction discrète (étincelle douce).
static func glint(parent: Node3D, at: Vector3, color: Color = Color(1.0, 0.85, 0.45, 1.0)) -> GPUParticles3D:
	var mat := _base_process()
	mat.emission_sphere_radius = 0.4
	mat.spread = 30.0
	mat.initial_velocity_min = 0.1
	mat.initial_velocity_max = 0.25
	mat.gravity = Vector3.ZERO
	mat.scale_min = 0.25
	mat.scale_max = 0.5
	mat.color = color
	var p := _make("flare_01", 4, 1.8, mat, true, false)
	p.position = at
	parent.add_child(p)
	return p
