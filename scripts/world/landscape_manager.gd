extends Node3D

@export var terrain_size: float = 512.0
@export var terrain_resolution: int = 256
@export var hoodoo_count: int = 40
@export var butte_count: int = 12
@export var boulder_count: int = 150
@export var pine_count: int = 220
@export var shrub_count: int = 180
@export var grass_count: int = 400
@export var seed_value: int = 1887
@export var collision_enabled: bool = true

var rng := RandomNumberGenerator.new()
var _terrain: MeshInstance3D
var _collision_body: StaticBody3D
var _props_root: Node3D
var _prop_collision: StaticBody3D
## Transformations de toutes les instances du décor (utile aux tests : le rendu
## headless ne relit pas les MultiMesh).
var prop_placements: Array[Transform3D] = []

func _ready() -> void:
	rng.seed = seed_value
	_generate_terrain()
	_place_props()

func regenerate(new_seed: int = -1) -> void:
	if new_seed >= 0:
		seed_value = new_seed
	rng.seed = seed_value
	if _terrain:
		_terrain.queue_free()
	if _collision_body:
		_collision_body.queue_free()
	if _props_root:
		_props_root.queue_free()
	if _prop_collision:
		_prop_collision.queue_free()
	_generate_terrain()
	_place_props()

func _generate_terrain() -> void:
	_terrain = MeshInstance3D.new()
	_terrain.name = "Terrain"

	var material: ShaderMaterial = load("res://assets/landscapes/materials/canyon_terrain.tres")

	var plane := PlaneMesh.new()
	plane.size = Vector2(terrain_size, terrain_size)
	plane.subdivide_width = terrain_resolution
	plane.subdivide_depth = terrain_resolution
	plane.material = material

	var final_mesh: Mesh = plane
	if collision_enabled:
		final_mesh = _displace_mesh(plane)

	_terrain.mesh = final_mesh
	add_child(_terrain)

	if collision_enabled:
		var array_mesh := final_mesh as ArrayMesh
		_collision_body = StaticBody3D.new()
		_collision_body.name = "TerrainCollision"
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(array_mesh.get_faces())
		var col := CollisionShape3D.new()
		col.shape = shape
		_collision_body.add_child(col)
		add_child(_collision_body)

func _displace_mesh(plane: PlaneMesh) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	var size := terrain_size
	var res := terrain_resolution
	var vertex_count := (res + 1) * (res + 1)
	var vertices := PackedVector3Array()
	vertices.resize(vertex_count)
	var normals := PackedVector3Array()
	normals.resize(vertex_count)
	var uvs := PackedVector2Array()
	uvs.resize(vertex_count)

	for z in range(res + 1):
		for x in range(res + 1):
			var wx: float = -size * 0.5 + size * float(x) / res
			var wz: float = -size * 0.5 + size * float(z) / res
			var nx: float = (wx + size * 0.5) / size
			var nz: float = (wz + size * 0.5) / size
			var h := _height_at(nx, nz)
			vertices[z * (res + 1) + x] = Vector3(wx, h, wz)
			uvs[z * (res + 1) + x] = Vector2(float(x) / res, float(z) / res)

	for z in range(res + 1):
		for x in range(res + 1):
			var i := z * (res + 1) + x
			var xp := vertices[min(i + 1, vertex_count - 1)]
			var xm := vertices[max(i - 1, 0)]
			var zp := vertices[min(i + res + 1, vertex_count - 1)]
			var zm := vertices[max(i - res - 1, 0)]
			var n := (zp - zm).cross(xp - xm)
			normals[i] = n.normalized() if n.length() > 0.0001 else Vector3.UP

	var indices := PackedInt32Array()
	var quad_count := res * res
	indices.resize(quad_count * 6)
	var idx := 0
	for z in range(res):
		for x in range(res):
			var a := z * (res + 1) + x
			var b := a + 1
			var c := a + res + 1
			var d := c + 1
			# Godot : faces avant = sens horaire. Cet ordre oriente les triangles vers
			# le HAUT (+Y) ; l'ordre inverse rendait le terrain invisible vu d'en haut
			# (cull_back) et faisait traverser le sol au joueur (collision à sens unique).
			indices[idx] = a; indices[idx + 1] = b; indices[idx + 2] = c
			indices[idx + 3] = b; indices[idx + 4] = d; indices[idx + 5] = c
			idx += 6

	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	out.surface_set_material(0, plane.material)
	return out

func _height_at(nx: float, nz: float) -> float:
	var ridge: float = 1.0 - abs(2.0 * nx - 1.0)
	var valley: float = smoothstep(0.0, 0.35, 1.0 - abs(2.0 * nz - 1.0))
	var canyon_depth: float = lerp(18.0, 2.0, valley)

	var n1 := _fbm(Vector2(nx * 3.0, nz * 3.0))
	var n2 := _fbm(Vector2(nx * 9.0 + 40.0, nz * 9.0 + 17.0))
	var n3 := _fbm(Vector2(nx * 24.0 + 91.0, nz * 24.0 + 55.0))

	var base: float = n1 * 6.0 + n2 * 3.0 - n3 * 1.5
	var canyon: float = -canyon_depth * (1.0 - valley) * smoothstep(0.0, 0.5, ridge)

	var cliff: float = 0.0
	var dist_edge: float = min(nx, nz, 1.0 - nx, 1.0 - nz)
	if dist_edge < 0.06:
		cliff = (0.06 - dist_edge) / 0.06 * 25.0

	return base + canyon + cliff

static func _fbm(p: Vector2) -> float:
	var value := 0.0
	var amplitude := 0.5
	var freq := 1.0
	for i in range(4):
		value += amplitude * _value_noise(p * freq)
		freq *= 2.0
		amplitude *= 0.5
	return value

static func _value_noise(p: Vector2) -> float:
	var i := Vector2i(floor(p.x), floor(p.y))
	var f: Vector2 = p - Vector2(float(i.x), float(i.y))
	f = f * f * (Vector2(3.0, 3.0) - Vector2(2.0, 2.0) * f)
	var a := _hash2(i)
	var b := _hash2(i + Vector2i(1, 0))
	var c := _hash2(i + Vector2i(0, 1))
	var d := _hash2(i + Vector2i(1, 1))
	return lerp(lerp(a, b, f.x), lerp(c, d, f.x), f.y)

static func _hash2(i: Vector2i) -> float:
	var s: float = float(i.x * 374761393 + i.y * 668265263)
	var shifted: float = float(int(s) >> 13)
	s = (s - shifted * 8192.0 * (1.0 if s >= 0.0 else -1.0)) * 1274126177.0
	var frac := sin(s * 0.0000000002328306437080797) * 43758.5453
	frac = frac - floor(frac)
	return frac * 2.0 - 1.0

func terrain_height_at(world_x: float, world_z: float) -> float:
	var nx := (world_x + terrain_size * 0.5) / terrain_size
	var nz := (world_z + terrain_size * 0.5) / terrain_size
	if nx < 0.0 or nx > 1.0 or nz < 0.0 or nz > 1.0:
		return -100.0
	return _height_at(nx, nz)

func _place_props() -> void:
	prop_placements.clear()
	_props_root = Node3D.new()
	_props_root.name = "Props"
	add_child(_props_root)

	# Collisions des accessoires : un corps statique frère de « Props » (qui ne
	# contient que des MultiMeshInstance3D), avec une forme simple par instance.
	_prop_collision = null
	if collision_enabled:
		_prop_collision = StaticBody3D.new()
		_prop_collision.name = "PropCollision"
		add_child(_prop_collision)

	# [type, nombre, grand rocher ?, forme sphérique ?, part du rayon du maillage]
	var rocks := [
		[RockGenerator.RockType.HOODOO, hoodoo_count, true, false, 0.7],
		[RockGenerator.RockType.BUTTE, butte_count, true, false, 0.85],
		[RockGenerator.RockType.BOULDER, boulder_count, false, true, 0.85],
	]
	for rock in rocks:
		var mesh: ArrayMesh = RockGenerator.generate(rock[0] as RockGenerator.RockType, rng)
		# Collision calquée sur le maillage réellement généré (tailles aléatoires).
		var box := mesh.get_aabb()
		var radius := maxf(box.size.x, box.size.z) * 0.5 * (rock[4] as float)
		_props_root.add_child(_place_multimesh(mesh, rock[1] as int, rock[2] as bool,
				radius, box.size.y, rock[3] as bool, box.position.y + box.size.y * 0.5))

	var plants := [
		[VegetationGenerator.PlantType.PINE, pine_count, 0.45, 4.0],
		[VegetationGenerator.PlantType.SHRUB, shrub_count, 0.0, 0.0],
		[VegetationGenerator.PlantType.DRY_GRASS, grass_count, 0.0, 0.0],
	]
	for plant in plants:
		var mesh: ArrayMesh = VegetationGenerator.generate(plant[0] as VegetationGenerator.PlantType, rng)
		_props_root.add_child(_place_multimesh(mesh, plant[1] as int, false,
				plant[2] as float, plant[3] as float, false))

func _place_multimesh(mesh: ArrayMesh, count: int, is_large_rock: bool,
		collider_radius: float = 0.0, collider_height: float = 0.0,
		collider_sphere: bool = false, collider_center_y: float = -1.0) -> MultiMeshInstance3D:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = count

	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	for i in range(count):
		var pos := _random_ground_position(is_large_rock)
		var scale_v := rng.randf_range(0.7, 1.4)
		# Attention : Transform3D.rotated()/scaled() appliquent aussi la rotation et l'échelle
		# à l'ORIGINE (le décor se retrouvait déplacé, flottant ou enterré, et ne
		# correspondait plus à ses collisions). On construit donc base + origine séparément.
		var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * scale_v)
		var transform := Transform3D(basis, pos)
		multimesh.set_instance_transform(i, transform)
		prop_placements.append(transform)
		if _prop_collision != null and collider_radius > 0.0:
			_add_prop_shape(pos, scale_v, collider_radius, collider_height, collider_sphere,
					collider_center_y if collider_center_y > -1.0 else collider_height * 0.5)

	return instance

func _add_prop_shape(pos: Vector3, scale_v: float, radius: float, height: float, sphere: bool, center_y: float) -> void:
	var col := CollisionShape3D.new()
	if sphere:
		var s := SphereShape3D.new()
		s.radius = radius * scale_v
		col.shape = s
		col.position = pos + Vector3(0.0, center_y * scale_v, 0.0)
	else:
		var c := CylinderShape3D.new()
		c.radius = radius * scale_v
		c.height = height * scale_v
		col.shape = c
		col.position = pos + Vector3(0.0, center_y * scale_v, 0.0)
	_prop_collision.add_child(col)

func _random_ground_position(is_large_rock: bool) -> Vector3:
	var margin := 30.0 if is_large_rock else 8.0
	var half := terrain_size * 0.5 - margin
	for attempt in range(20):
		var x := rng.randf_range(-half, half)
		var z := rng.randf_range(-half, half)
		var y := terrain_height_at(x, z)
		if y < -5.0:
			continue
		if is_large_rock:
			var slope_check := terrain_height_at(x + 2.0, z) - terrain_height_at(x - 2.0, z)
			if abs(slope_check) > 3.0:
				continue
		return Vector3(x, y, z)
	return Vector3(rng.randf_range(-half, half), 0.0, rng.randf_range(-half, half))
