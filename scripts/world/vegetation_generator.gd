class_name VegetationGenerator
extends RefCounted

enum PlantType { PINE, SHRUB, DRY_GRASS, CACTUS, AGAVE, FLOWERS }

static func generate(type: PlantType, rng: RandomNumberGenerator) -> ArrayMesh:
	match type:
		PlantType.PINE:
			return _generate_pine(rng)
		PlantType.SHRUB:
			return _generate_shrub(rng)
		PlantType.CACTUS:
			return _generate_cactus(rng)
		PlantType.AGAVE:
			return _generate_agave(rng)
		PlantType.FLOWERS:
			return _generate_flowers(rng)
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

## Matériau « plante » : balancement du vent réglable (un cactus ne doit pas osciller).
static func _plant_material(color: Color, light: Color, wind: float, boost: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load("res://assets/landscapes/shaders/prop_foliage.gdshader")
	material.set_shader_parameter("albedo", color)
	material.set_shader_parameter("albedo_light", light)
	material.set_shader_parameter("variation_scale", 3.0)
	material.set_shader_parameter("light_boost", boost)
	material.set_shader_parameter("wind_strength", wind)
	return material

## Tige côtelée (cylindre à bout arrondi) d'un point à un autre, pour le cactus.
static func _ribbed_tube(vertices: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array,
		indices: PackedInt32Array, from: Vector3, to: Vector3, radius: float) -> void:
	var axis := (to - from)
	var length := axis.length()
	var up := axis / maxf(length, 0.001)
	var ref := Vector3.RIGHT if absf(up.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var side := up.cross(ref).normalized()
	var front := up.cross(side).normalized()
	var sides := 12
	# Profil : base, fût, épaule arrondie, sommet.
	var rings := [[0.0, 0.85], [0.06, 1.0], [0.85, 1.0], [0.95, 0.8], [0.99, 0.5], [1.0, 0.08]]
	var base := vertices.size()
	for ring in rings:
		for seg in range(sides + 1):
			var angle := float(seg) / sides * TAU
			var rib := 1.0 + 0.09 * cos(angle * 6.0)
			var dir := side * cos(angle) + front * sin(angle)
			var r := radius * float(ring[1]) * rib
			vertices.append(from + up * (length * float(ring[0])) + dir * r)
			normals.append((dir + up * (0.25 if float(ring[0]) > 0.9 else 0.0)).normalized())
			uvs.append(Vector2(float(seg) / sides, float(ring[0])))
	for r in range(rings.size() - 1):
		for seg in range(sides):
			var a := base + r * (sides + 1) + seg
			var b := a + 1
			var c := a + sides + 1
			var d := c + 1
			indices.append_array([a, c, b, b, c, d])

static func _generate_cactus(rng: RandomNumberGenerator) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var height := rng.randf_range(2.2, 3.6)
	var radius := rng.randf_range(0.2, 0.3)
	_ribbed_tube(vertices, normals, uvs, indices, Vector3.ZERO, Vector3(0.0, height, 0.0), radius)
	var arms := rng.randi_range(0, 3)
	for arm in range(arms):
		var angle := rng.randf_range(0.0, TAU)
		var dir := Vector3(cos(angle), 0.0, sin(angle))
		var attach := height * rng.randf_range(0.35, 0.62)
		var reach := rng.randf_range(0.55, 0.85)
		var elbow := Vector3(0.0, attach, 0.0) + dir * reach
		# Départ horizontal puis montée verticale, comme un saguaro.
		_ribbed_tube(vertices, normals, uvs, indices, Vector3(0.0, attach, 0.0) + dir * radius * 0.4, elbow, radius * 0.62)
		_ribbed_tube(vertices, normals, uvs, indices, elbow - Vector3(0.0, radius * 0.4, 0.0),
				elbow + Vector3(0.0, rng.randf_range(0.8, 1.5), 0.0), radius * 0.62)
	var color := Color.from_hsv(rng.randf_range(0.30, 0.37), rng.randf_range(0.6, 0.75), rng.randf_range(0.26, 0.36))
	return _build_cactus(vertices, normals, uvs, indices, color)

static func _build_cactus(vertices: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array, color: Color) -> ArrayMesh:
	var surfaces: Array = []
	surfaces.resize(Mesh.ARRAY_MAX)
	surfaces[Mesh.ARRAY_VERTEX] = vertices
	surfaces[Mesh.ARRAY_NORMAL] = normals
	surfaces[Mesh.ARRAY_TEX_UV] = uvs
	surfaces[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surfaces)
	mesh.surface_set_material(0, _plant_material(color, color.lightened(0.3), 0.0, 0.5))
	return mesh

## Agave : rosette de feuilles charnues pointant vers le haut et l'extérieur.
static func _generate_agave(rng: RandomNumberGenerator) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var leaves := rng.randi_range(9, 14)
	var length := rng.randf_range(0.7, 1.2)
	for leaf in range(leaves):
		var angle := float(leaf) / leaves * TAU + rng.randf_range(-0.2, 0.2)
		var dir := Vector3(cos(angle), 0.0, sin(angle))
		var side := Vector3(-dir.z, 0.0, dir.x)
		var pitch := rng.randf_range(0.55, 1.0)
		var l := length * rng.randf_range(0.75, 1.0)
		var width := 0.11 * l / length * 1.5
		var tip := dir * l * cos(pitch * 0.9) + Vector3(0.0, l * sin(pitch) * 0.9 + 0.08, 0.0)
		var mid := dir * l * 0.5 + Vector3(0.0, l * 0.32, 0.0)
		var normal := (Vector3.UP + dir * 0.5).normalized()
		var i0 := vertices.size()
		for v in [Vector3.ZERO + side * width * 0.35, Vector3.ZERO - side * width * 0.35, mid + side * width, mid - side * width, tip]:
			vertices.append(v)
			normals.append(normal)
			uvs.append(Vector2(0.5, 0.5))
		indices.append_array([i0, i0 + 2, i0 + 1, i0 + 1, i0 + 2, i0 + 3, i0 + 2, i0 + 4, i0 + 3])
	var color := Color.from_hsv(rng.randf_range(0.40, 0.47), rng.randf_range(0.28, 0.42), rng.randf_range(0.40, 0.52))
	var mesh := ArrayMesh.new()
	var surfaces: Array = []
	surfaces.resize(Mesh.ARRAY_MAX)
	surfaces[Mesh.ARRAY_VERTEX] = vertices
	surfaces[Mesh.ARRAY_NORMAL] = normals
	surfaces[Mesh.ARRAY_TEX_UV] = uvs
	surfaces[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surfaces)
	mesh.surface_set_material(0, _plant_material(color, color.lightened(0.35), 0.03, 0.5))
	return mesh

## Touffe de fleurs sauvages : quelques tiges fines surmontées d'une corolle colorée.
static func _generate_flowers(rng: RandomNumberGenerator) -> ArrayMesh:
	var stem_v := PackedVector3Array()
	var stem_n := PackedVector3Array()
	var stem_uv := PackedVector2Array()
	var stem_i := PackedInt32Array()
	var bloom_v := PackedVector3Array()
	var bloom_n := PackedVector3Array()
	var bloom_uv := PackedVector2Array()
	var bloom_i := PackedInt32Array()
	var stems := rng.randi_range(4, 7)
	for stem in range(stems):
		var base := Vector2(rng.randf_range(-0.25, 0.25), rng.randf_range(-0.25, 0.25))
		var height := rng.randf_range(0.3, 0.55)
		var lean := Vector2(rng.randf_range(-0.08, 0.08), rng.randf_range(-0.08, 0.08))
		var i0 := stem_v.size()
		stem_v.append(Vector3(base.x - 0.012, 0.0, base.y))
		stem_v.append(Vector3(base.x + 0.012, 0.0, base.y))
		stem_v.append(Vector3(base.x + lean.x, height, base.y + lean.y))
		for k in 3:
			stem_n.append(Vector3.UP)
			stem_uv.append(Vector2(0.5, 0.5))
		stem_i.append_array([i0, i0 + 1, i0 + 2])
		var top := Vector3(base.x + lean.x, height, base.y + lean.y)
		var petals := 6
		var c0 := bloom_v.size()
		bloom_v.append(top + Vector3(0.0, 0.03, 0.0))
		bloom_n.append(Vector3.UP)
		bloom_uv.append(Vector2(0.5, 0.5))
		for petal in range(petals):
			var a := float(petal) / petals * TAU
			bloom_v.append(top + Vector3(cos(a) * 0.075, 0.015, sin(a) * 0.075))
			bloom_n.append(Vector3.UP)
			bloom_uv.append(Vector2(0.5, 0.5))
		for petal in range(petals):
			bloom_i.append_array([c0, c0 + 1 + petal, c0 + 1 + (petal + 1) % petals])
	var mesh := ArrayMesh.new()
	var s1: Array = []
	s1.resize(Mesh.ARRAY_MAX)
	s1[Mesh.ARRAY_VERTEX] = stem_v
	s1[Mesh.ARRAY_NORMAL] = stem_n
	s1[Mesh.ARRAY_TEX_UV] = stem_uv
	s1[Mesh.ARRAY_INDEX] = stem_i
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, s1)
	mesh.surface_set_material(0, _plant_material(Color(0.28, 0.4, 0.16), Color(0.4, 0.55, 0.22), 0.1, 0.3))
	var s2: Array = []
	s2.resize(Mesh.ARRAY_MAX)
	s2[Mesh.ARRAY_VERTEX] = bloom_v
	s2[Mesh.ARRAY_NORMAL] = bloom_n
	s2[Mesh.ARRAY_TEX_UV] = bloom_uv
	s2[Mesh.ARRAY_INDEX] = bloom_i
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, s2)
	var palette := [Color(0.92, 0.35, 0.22), Color(0.95, 0.8, 0.25), Color(0.75, 0.35, 0.7), Color(0.95, 0.95, 0.85)]
	var bloom: Color = palette[rng.randi() % palette.size()]
	mesh.surface_set_material(1, _plant_material(bloom, bloom.lightened(0.2), 0.1, 0.1))
	return mesh
