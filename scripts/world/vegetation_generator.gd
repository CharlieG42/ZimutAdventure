class_name VegetationGenerator
extends RefCounted

enum PlantType { PINE, SHRUB, DRY_GRASS }

static func generate(type: PlantType, rng: RandomNumberGenerator) -> ArrayMesh:
	match type:
		PlantType.PINE:
			return _generate_pine(rng)
		PlantType.SHRUB:
			return _generate_shrub(rng)
		_:
			return _generate_dry_grass(rng)

static func _build_mesh(vertices: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array, color: Color) -> ArrayMesh:
	var surfaces: Array = []
	surfaces.resize(Mesh.ARRAY_MAX)
	surfaces[Mesh.ARRAY_VERTEX] = vertices
	surfaces[Mesh.ARRAY_NORMAL] = normals
	surfaces[Mesh.ARRAY_TEX_UV] = uvs
	surfaces[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surfaces)
	var material := ShaderMaterial.new()
	material.shader = load("res://assets/landscapes/shaders/prop_foliage.gdshader")
	material.set_shader_parameter("albedo", color)
	material.set_shader_parameter("albedo_light", color.lightened(0.35))
	material.set_shader_parameter("variation_scale", 2.0)
	material.set_shader_parameter("light_boost", 0.4)
	mesh.surface_set_material(0, material)
	return mesh

static func _cone(vertices: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array, base_y: float, height: float, radius: float, segments: int, tilt: Vector3) -> void:
	var base := vertices.size()
	for seg in range(segments + 1):
		var angle := float(seg) / segments * TAU
		var p := Vector3(cos(angle) * radius, base_y, sin(angle) * radius) + tilt
		vertices.append(p)
		normals.append(Vector3(cos(angle), 0.5, sin(angle)).normalized())
		uvs.append(Vector2(float(seg) / segments, 0.0))
	var apex_index := vertices.size()
	vertices.append(Vector3(0.0, base_y + height, 0.0) + tilt)
	normals.append(Vector3(0.0, 1.0, 0.0))
	uvs.append(Vector2(0.5, 1.0))
	for seg in range(segments):
		indices.append_array([base + seg, apex_index, base + seg + 1])

static func _generate_pine(rng: RandomNumberGenerator) -> ArrayMesh:
	var trunk_height := rng.randf_range(1.2, 2.2)
	var trunk_radius := rng.randf_range(0.08, 0.14)
	var foliage_height := rng.randf_range(3.5, 6.5)
	var foliage_radius := rng.randf_range(1.2, 2.2)
	var segments := 7

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	for seg in range(segments + 1):
		var angle := float(seg) / segments * TAU
		vertices.append(Vector3(cos(angle) * trunk_radius, 0.0, sin(angle) * trunk_radius))
		normals.append(Vector3(cos(angle), 0.0, sin(angle)))
		uvs.append(Vector2(float(seg) / segments, 0.0))
	var trunk_top := vertices.size()
	vertices.append(Vector3(0.0, trunk_height, 0.0))
	normals.append(Vector3(0.0, 1.0, 0.0))
	uvs.append(Vector2(0.5, 0.2))
	for seg in range(segments):
		indices.append_array([seg, trunk_top, seg + 1])

	var mesh := _build_trunk_mesh(vertices, normals, uvs, indices)

	var fverts := PackedVector3Array()
	var fnormals := PackedVector3Array()
	var fuvs := PackedVector2Array()
	var findices := PackedInt32Array()
	var layers := 4
	for layer in range(layers):
		var t := float(layer) / (layers - 1)
		var base_y := trunk_height * 0.6 + t * foliage_height
		var radius := foliage_radius * (1.0 - t * 0.85)
		var height := foliage_height * 0.42
		_cone(fverts, fnormals, fuvs, findices, base_y, height, radius, segments, Vector3.ZERO)

	var fsurfaces: Array = []
	fsurfaces.resize(Mesh.ARRAY_MAX)
	fsurfaces[Mesh.ARRAY_VERTEX] = fverts
	fsurfaces[Mesh.ARRAY_NORMAL] = fnormals
	fsurfaces[Mesh.ARRAY_TEX_UV] = fuvs
	fsurfaces[Mesh.ARRAY_INDEX] = findices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, fsurfaces)
	var green := Color.from_hsv(rng.randf_range(0.28, 0.38), rng.randf_range(0.5, 0.7), rng.randf_range(0.22, 0.32))
	var fmat := ShaderMaterial.new()
	fmat.shader = load("res://assets/landscapes/shaders/prop_foliage.gdshader")
	fmat.set_shader_parameter("albedo", green)
	fmat.set_shader_parameter("albedo_light", green.lightened(0.4))
	fmat.set_shader_parameter("variation_scale", 2.5)
	fmat.set_shader_parameter("light_boost", 0.45)
	mesh.surface_set_material(1, fmat)
	return mesh

static func _build_trunk_mesh(vertices: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array) -> ArrayMesh:
	indices = RockGenerator.orient_triangles(vertices, normals, indices)
	var surfaces: Array = []
	surfaces.resize(Mesh.ARRAY_MAX)
	surfaces[Mesh.ARRAY_VERTEX] = vertices
	surfaces[Mesh.ARRAY_NORMAL] = normals
	surfaces[Mesh.ARRAY_TEX_UV] = uvs
	surfaces[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surfaces)
	var material := ShaderMaterial.new()
	material.shader = load("res://assets/landscapes/shaders/prop_trunk.gdshader")
	material.set_shader_parameter("albedo", Color(0.24, 0.14, 0.07))
	material.set_shader_parameter("albedo_light", Color(0.38, 0.22, 0.10))
	material.set_shader_parameter("bark_scale", 6.0)
	material.set_shader_parameter("bark_depth", 0.4)
	mesh.surface_set_material(0, material)
	return mesh

static func _generate_shrub(rng: RandomNumberGenerator) -> ArrayMesh:
	var segments := 5
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var tufts := rng.randi_range(3, 5)
	for tuft in range(tufts):
		var offset := Vector3(rng.randf_range(-0.3, 0.3), 0.0, rng.randf_range(-0.3, 0.3))
		var height := rng.randf_range(0.3, 0.7)
		_cone(vertices, normals, uvs, indices, 0.0, height, rng.randf_range(0.25, 0.5), segments, offset)
	var color := Color.from_hsv(rng.randf_range(0.1, 0.16), rng.randf_range(0.4, 0.6), rng.randf_range(0.3, 0.45))
	return _build_mesh(vertices, normals, uvs, indices, color)

static func _generate_dry_grass(rng: RandomNumberGenerator) -> ArrayMesh:
	var blades := rng.randi_range(5, 9)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for blade in range(blades):
		var base := Vector2(rng.randf_range(-0.15, 0.15), rng.randf_range(-0.15, 0.15))
		var height := rng.randf_range(0.25, 0.6)
		var lean := Vector2(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.1, 0.35))
		var i0 := vertices.size()
		vertices.append(Vector3(base.x, 0.0, base.y))
		normals.append(Vector3.UP)
		uvs.append(Vector2(0.0, 0.0))
		vertices.append(Vector3(base.x + lean.x, height, base.y + lean.y))
		normals.append(Vector3(0.0, 1.0, 0.0))
		uvs.append(Vector2(0.5, 1.0))
		vertices.append(Vector3(base.x + lean.x * 0.5, height * 0.6, base.y + lean.y * 0.5))
		normals.append(Vector3(0.0, 1.0, 0.0))
		uvs.append(Vector2(1.0, 0.5))
		indices.append_array([i0, i0 + 1, i0 + 2])
	var color := Color.from_hsv(rng.randf_range(0.12, 0.18), rng.randf_range(0.5, 0.7), rng.randf_range(0.35, 0.55))
	return _build_mesh(vertices, normals, uvs, indices, color)
