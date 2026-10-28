class_name RockGenerator
extends RefCounted

enum RockType { HOODOO, BUTTE, BOULDER }

static func generate(type: RockType, rng: RandomNumberGenerator) -> ArrayMesh:
	match type:
		RockType.HOODOO:
			return _generate_hoodoo(rng)
		RockType.BUTTE:
			return _generate_butte(rng)
		_:
			return _generate_boulder(rng)

static func _rock_color(rng: RandomNumberGenerator, base: Color) -> Color:
	var h = base.h + rng.randf_range(-0.03, 0.03)
	var s = clamp(base.s + rng.randf_range(-0.08, 0.08), 0.0, 1.0)
	var v = clamp(base.v + rng.randf_range(-0.08, 0.08), 0.0, 1.0)
	return Color.from_hsv(h, s, v)

static func _build_mesh(surfaces: Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surfaces)
	mesh.surface_set_material(0, _rock_material())
	return mesh

static func _rock_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load("res://assets/landscapes/shaders/prop_rock.gdshader")
	material.set_shader_parameter("grain_scale", 4.0)
	material.set_shader_parameter("grain_strength", 0.35)
	material.set_shader_parameter("roughness_base", 0.9)
	return material

static func _generate_hoodoo(rng: RandomNumberGenerator) -> ArrayMesh:
	var height := rng.randf_range(8.0, 22.0)
	var base_radius := rng.randf_range(2.5, 5.0)
	var shaft_top := rng.randf_range(1.0, 2.2)
	var cap_radius := shaft_top * rng.randf_range(1.3, 2.2)
	var cap_height := rng.randf_range(0.8, 2.0)
	var segments := 7
	var rings := 6

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	for ring in range(rings + 1):
		var t := float(ring) / rings
		var y := t * (height - cap_height)
		var radius: float = lerp(base_radius, shaft_top, t)
		radius *= 1.0 + rng.randf_range(-0.06, 0.06)
		for seg in range(segments + 1):
			var angle := float(seg) / segments * TAU
			var pos := Vector3(cos(angle) * radius, y, sin(angle) * radius)
			vertices.append(pos)
			normals.append(Vector3(cos(angle), 0.05, sin(angle)).normalized())
			uvs.append(Vector2(float(seg) / segments, t))

	var cap_start := vertices.size()
	for ring in range(3):
		var t := float(ring) / 2.0
		var y := height - cap_height + t * cap_height
		var radius: float = lerp(shaft_top, cap_radius, t)
		for seg in range(segments + 1):
			var angle := float(seg) / segments * TAU
			var pos := Vector3(cos(angle) * radius, y, sin(angle) * radius)
			vertices.append(pos)
			var n := Vector3(cos(angle), 0.3, sin(angle)).normalized()
			normals.append(n)
			uvs.append(Vector2(float(seg) / segments, 1.0 + t))

	var grid_w := segments + 1
	for ring in range(rings):
		for seg in range(segments):
			var a := ring * grid_w + seg
			var b := a + grid_w
			indices.append_array([a, b, a + 1, a + 1, b, b + 1])
	for ring in range(2):
		for seg in range(segments):
			var a := cap_start + ring * grid_w + seg
			var b := a + grid_w
			indices.append_array([a, a + 1, b, a + 1, b + 1, b])

	var surfaces: Array = []
	surfaces.resize(Mesh.ARRAY_MAX)
	surfaces[Mesh.ARRAY_VERTEX] = vertices
	surfaces[Mesh.ARRAY_NORMAL] = normals
	surfaces[Mesh.ARRAY_TEX_UV] = uvs
	surfaces[Mesh.ARRAY_INDEX] = indices

	var mesh := _build_mesh(surfaces)
	var mat := mesh.surface_get_material(0) as ShaderMaterial
	mat.set_shader_parameter("albedo", _rock_color(rng, Color(0.62, 0.32, 0.16)))
	mat.set_shader_parameter("albedo_dark", _rock_color(rng, Color(0.38, 0.18, 0.09)))
	return mesh

static func _generate_butte(rng: RandomNumberGenerator) -> ArrayMesh:
	var height := rng.randf_range(15.0, 40.0)
	var base_radius := rng.randf_range(6.0, 12.0)
	var top_radius := base_radius * rng.randf_range(0.45, 0.7)
	var overhang := rng.randf_range(1.05, 1.25)
	var cliff_height := height * rng.randf_range(0.55, 0.8)
	var segments := 9
	var rings := 8

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	for ring in range(rings + 1):
		var t := float(ring) / rings
		var y := t * height
		var radius: float
		if t < cliff_height / height:
			radius = lerp(base_radius, base_radius * 0.92, t / (cliff_height / height))
		else:
			var tc := (t - cliff_height / height) / (1.0 - cliff_height / height)
			radius = lerp(base_radius * 0.92, top_radius, tc)
		radius *= 1.0 + rng.randf_range(-0.05, 0.05)
		for seg in range(segments + 1):
			var angle := float(seg) / segments * TAU
			vertices.append(Vector3(cos(angle) * radius, y, sin(angle) * radius))
			normals.append(Vector3(cos(angle), 0.02, sin(angle)).normalized())
			uvs.append(Vector2(float(seg) / segments, t))

	for ring in range(2):
		var t := float(ring)
		var y := height + t * 2.0
		var radius: float = lerp(top_radius, top_radius * overhang, t)
		for seg in range(segments + 1):
			var angle := float(seg) / segments * TAU
			vertices.append(Vector3(cos(angle) * radius, y, sin(angle) * radius))
			normals.append(Vector3(0.0, 1.0, 0.0))
			uvs.append(Vector2(float(seg) / segments, 2.0 + t))

	var grid_w := segments + 1
	var cliff_rings := int(cliff_height / height * rings)
	for ring in range(rings):
		for seg in range(segments):
			var a := ring * grid_w + seg
			var b := a + grid_w
			indices.append_array([a, b, a + 1, a + 1, b, b + 1])
	var cap_start := (rings + 1) * grid_w
	for seg in range(segments):
		var a := cap_start + seg
		indices.append_array([a, cap_start + grid_w + seg, a + 1])

	var surfaces: Array = []
	surfaces.resize(Mesh.ARRAY_MAX)
	surfaces[Mesh.ARRAY_VERTEX] = vertices
	surfaces[Mesh.ARRAY_NORMAL] = normals
	surfaces[Mesh.ARRAY_TEX_UV] = uvs
	surfaces[Mesh.ARRAY_INDEX] = indices

	var mesh := _build_mesh(surfaces)
	var mat := mesh.surface_get_material(0) as ShaderMaterial
	mat.set_shader_parameter("albedo", _rock_color(rng, Color(0.72, 0.42, 0.2)))
	mat.set_shader_parameter("albedo_dark", _rock_color(rng, Color(0.45, 0.24, 0.12)))
	return mesh

static func _generate_boulder(rng: RandomNumberGenerator) -> ArrayMesh:
	var radius := rng.randf_range(0.6, 2.5)
	var segments := 8
	var rings := 5

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	for ring in range(rings + 1):
		var phi := float(ring) / rings * PI
		for seg in range(segments + 1):
			var theta := float(seg) / segments * TAU
			var wobble := 1.0 + rng.randf_range(-0.15, 0.15)
			var pos := Vector3(
				sin(phi) * cos(theta) * radius * wobble,
				cos(phi) * radius * 0.7 * wobble,
				sin(phi) * sin(theta) * radius * wobble
			)
			if ring == 0:
				pos.y = -radius * 0.7
			vertices.append(pos)
			normals.append(pos.normalized())
			uvs.append(Vector2(float(seg) / segments, float(ring) / rings))

	var grid_w := segments + 1
	for ring in range(rings):
		for seg in range(segments):
			var a := ring * grid_w + seg
			var b := a + grid_w
			if ring == 0:
				indices.append_array([a, b, a + 1])
			else:
				indices.append_array([a, b, a + 1, a + 1, b, b + 1])

	var surfaces: Array = []
	surfaces.resize(Mesh.ARRAY_MAX)
	surfaces[Mesh.ARRAY_VERTEX] = vertices
	surfaces[Mesh.ARRAY_NORMAL] = normals
	surfaces[Mesh.ARRAY_TEX_UV] = uvs
	surfaces[Mesh.ARRAY_INDEX] = indices

	var mesh := _build_mesh(surfaces)
	var mat := mesh.surface_get_material(0) as ShaderMaterial
	mat.set_shader_parameter("albedo", _rock_color(rng, Color(0.5, 0.28, 0.15)))
	mat.set_shader_parameter("albedo_dark", _rock_color(rng, Color(0.3, 0.16, 0.08)))
	return mesh
