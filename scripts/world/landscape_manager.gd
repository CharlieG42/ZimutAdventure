extends Node3D

@export var terrain_size: float = 512.0
@export var terrain_resolution: int = 256
@export var hoodoo_count: int = 40
@export var butte_count: int = 12
@export var boulder_count: int = 150
@export var pine_count: int = 260
@export var shrub_count: int = 180
@export var grass_count: int = 400
@export var extra_grass_count: int = 300
@export var cactus_count: int = 70
@export var agave_count: int = 110
@export var flower_count: int = 160
@export var arch_count: int = 6
@export var pebble_count: int = 700
@export var seed_value: int = 1887
@export var collision_enabled: bool = true
## Props GLB externes (assets/props/kenney/) à la place des maillages procéduraux
## quand ils sont disponibles ; sinon retombe sur le procédural.
@export var use_glb_props: bool = true

var rng := RandomNumberGenerator.new()
var _terrain: MeshInstance3D
var _collision_body: StaticBody3D
var _props_root: Node3D
var _prop_collision: StaticBody3D
var _river: Node3D
var _horizon: Node3D

# --- Horizon -------------------------------------------------------------------------------
## Mesas lointaines tout autour de la carte (hors de portée) : elles donnent l'échelle.
const HORIZON_MESAS := 54
const HORIZON_RADIUS_MIN := 430.0
const HORIZON_RADIUS_MAX := 820.0
## Plaine lointaine sous les mesas, juste sous le sommet des falaises du bord.
const HORIZON_GROUND_Y := 14.0
## Transformations de toutes les instances du décor (utile aux tests : le rendu
## headless ne relit pas les MultiMesh).
var prop_placements: Array[Transform3D] = []

## Découpage du décor en blocs et portées d'affichage (mètres).
const CHUNK_SIZE := 64.0
const RANGE_PEBBLE := 45.0    # cailloux
const RANGE_NEAR := 75.0      # herbes, fleurs
const RANGE_SHRUB := 130.0    # buissons, agaves
const RANGE_MEDIUM := 230.0   # arbres, cactus, blocs de grès

# --- Rivière ---------------------------------------------------------------------------
## La rivière traverse la carte d'ouest en est, d'un lac-source à un lac aval.
const RIVER_X_MIN := -185.0
const RIVER_X_MAX := 185.0
const RIVER_HALF_WIDTH := 4.5
const RIVER_DEPTH := 1.1
## Largeur de la plaine alluviale aplanie de part et d'autre.
const RIVER_BANK := 30.0
const LAKE_RADIUS := 13.0
## La surface de l'eau est un peu sous le niveau des berges.
const WATER_DROP := 0.3

# --- Zones -----------------------------------------------------------------------------
const ZONE_DESERT := "desert"
const ZONE_FOREST := "forest"
const ZONE_BADLANDS := "badlands"
const ZONE_RIVER := "river"
## Foyers des zones : [x, z, rayon]. Les bords sont déformés pour ne pas être des cercles.
const FOREST_BLOBS := [[-110.0, -120.0, 95.0], [-15.0, -155.0, 60.0]]
const BADLANDS_BLOBS := [[130.0, 135.0, 90.0], [35.0, 160.0, 60.0]]
## Noms affichés (clés de traduction) et point d'ancrage de l'étiquette sur la carte.
const ZONE_LABELS := [
	{"zone": ZONE_FOREST, "name": "ZONE_FOREST", "x": -100.0, "z": -125.0},
	{"zone": ZONE_BADLANDS, "name": "ZONE_BADLANDS", "x": 120.0, "z": 140.0},
	{"zone": ZONE_DESERT, "name": "ZONE_DESERT", "x": 120.0, "z": -110.0},
	{"zone": ZONE_RIVER, "name": "ZONE_RIVER", "x": -60.0, "z": 46.0},
]
## Le départ reste une plaine dégagée (camp, feu, panneau).
const START_POINT := Vector2(40.0, -30.0)
## Éléments du décor qui bloquent le passage (ils ont une collision).
const SOLID_KINDS := ["boulder", "pine", "cactus", "arch"]
## Affinité de chaque élément du décor pour [désert, pinède, mesas, berges] (0 = jamais).
const AFFINITY := {
	"hoodoo": [0.08, 0.0, 1.0, 0.0],
	"butte": [0.45, 0.05, 0.8, 0.0],
	"boulder": [0.55, 0.35, 1.0, 0.3],
	"pine": [0.05, 1.0, 0.03, 0.3],
	"shrub": [0.4, 0.6, 0.2, 0.85],
	"grass": [0.25, 0.6, 0.1, 1.0],
	"cactus": [1.0, 0.0, 0.5, 0.0],
	"agave": [1.0, 0.04, 0.6, 0.0],
	"flowers": [0.15, 0.5, 0.05, 1.0],
	"arch": [0.4, 0.0, 1.0, 0.0],
	"pebble": [0.6, 0.3, 0.9, 1.0],
}

func _ready() -> void:
	add_to_group("landscape")
	rng.seed = seed_value
	_generate_terrain()
	_place_props()
	_build_river()
	_build_horizon()

func _process(_delta: float) -> void:
	# Position du joueur exposée aux shaders (pliure de l'herbe au passage, vent).
	var player := get_tree().get_first_node_in_group("player") if get_tree() != null else null
	if player != null:
		RenderingServer.global_shader_parameter_set("player_pos", player.global_position)

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
	if _river:
		_river.queue_free()
	if _horizon:
		_horizon.queue_free()
	_generate_terrain()
	_place_props()
	_build_river()
	_build_horizon()

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
	# Couleur de sommet = zones, lues par le shader : R berges, V pinède, B mesas, A rive mouillée.
	var colors := PackedColorArray()
	colors.resize(vertex_count)

	for z in range(res + 1):
		for x in range(res + 1):
			var wx: float = -size * 0.5 + size * float(x) / res
			var wz: float = -size * 0.5 + size * float(z) / res
			var nx: float = (wx + size * 0.5) / size
			var nz: float = (wz + size * 0.5) / size
			var h := _height_at(nx, nz)
			vertices[z * (res + 1) + x] = Vector3(wx, h, wz)
			uvs[z * (res + 1) + x] = Vector2(float(x) / res, float(z) / res)
			var weights := zone_weights(wx, wz)
			var shore := 0.0
			if weights[3] > 0.0:
				shore = (1.0 - smoothstep(0.0, 1.0, h - water_level_at(wx))) * float(is_water(wx, wz, 5.0))
			colors[z * (res + 1) + x] = Color(weights[3], weights[1], weights[2], shore)

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
	arrays[Mesh.ARRAY_COLOR] = colors
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

	var x := (nx - 0.5) * terrain_size
	var z := (nz - 0.5) * terrain_size
	var h := base + canyon + cliff + _zone_relief(x, z)
	return _carve_river(x, z, h)

## Relief propre aux zones : ondulations générales, collines de la pinède, gradins et
## plateaux des mesas. Nul autour du départ, qui reste une plaine.
func _zone_relief(x: float, z: float) -> float:
	var relief := 1.8 * sin(x * 0.021 + 0.5) * sin(z * 0.017 + 1.9) + 1.0 * sin(x * 0.043 + z * 0.031)
	var forest := _blob_field(x, z, FOREST_BLOBS)
	relief += smoothstep(0.0, 0.3, forest) * (3.5 + 3.0 * sin(x * 0.05 + 2.0) * sin(z * 0.045 + 0.3))
	var badlands := _blob_field(x, z, BADLANDS_BLOBS)
	if badlands > 0.0:
		# Premier gradin en pente douce, puis plateau : falaise d'un côté, rampe de l'autre.
		var ramp := 0.05 + 0.22 * (0.5 + 0.5 * sin(x * 0.03 - z * 0.022))
		relief += smoothstep(0.03, 0.3, badlands) * 5.0 + smoothstep(0.42, 0.42 + ramp, badlands) * 8.0
	return relief * smoothstep(18.0, 48.0, START_POINT.distance_to(Vector2(x, z)))

## Aplanit la plaine alluviale au niveau de la rivière puis creuse le lit.
func _carve_river(x: float, z: float, h: float) -> float:
	var d := river_distance(x, z)
	var level := river_level_at(x)
	if d >= RIVER_BANK:
		# Les abords restent au-dessus des berges : la rivière coule au creux du terrain.
		return lerpf(maxf(h, level + 0.4), h, smoothstep(RIVER_BANK + 30.0, RIVER_BANK + 110.0, d))
	# Jamais de rivière perchée : au-delà des berges, le sol ne passe pas sous leur niveau.
	h = lerpf(level, maxf(h, level + 0.4), smoothstep(RIVER_HALF_WIDTH + 2.0, RIVER_BANK, d))
	return h - RIVER_DEPTH * (1.0 - smoothstep(RIVER_HALF_WIDTH * 0.45, RIVER_HALF_WIDTH + 1.5, d))

# --- Rivière : géométrie -----------------------------------------------------------------

## Tracé de la rivière : z du milieu du lit pour une abscisse x (mètres, repère monde).
static func river_center_z(x: float) -> float:
	return 10.0 + 28.0 * sin(x / 75.0 + 2.2) + 9.0 * sin(x / 27.0 + 1.0)

## Niveau des berges : la rivière descend doucement d'ouest en est.
static func river_level_at(x: float) -> float:
	return lerpf(-2.6, -4.6, clampf((x - RIVER_X_MIN) / (RIVER_X_MAX - RIVER_X_MIN), 0.0, 1.0))

## Altitude de la surface de l'eau.
static func water_level_at(x: float) -> float:
	return river_level_at(x) - WATER_DROP

## Distance (m) au milieu du lit ; les deux lacs d'extrémité comptent comme la rivière.
static func river_distance(x: float, z: float) -> float:
	var xc := clampf(x, RIVER_X_MIN, RIVER_X_MAX)
	var dz := z - river_center_z(xc)
	var d: float
	if x == xc:
		var slope := 28.0 / 75.0 * cos(xc / 75.0 + 2.2) + 9.0 / 27.0 * cos(xc / 27.0 + 1.0)
		d = absf(dz) / sqrt(1.0 + slope * slope)
	else:
		d = Vector2(x - xc, dz).length()
	for end_x in [RIVER_X_MIN, RIVER_X_MAX]:
		var to_lake := Vector2(x - end_x, z - river_center_z(end_x)).length()
		d = minf(d, maxf(0.0, to_lake - (LAKE_RADIUS - RIVER_HALF_WIDTH)))
	return d

## Vrai si le point est dans l'eau (lit de la rivière ou lac), avec une marge optionnelle.
func is_water(x: float, z: float, margin: float = 0.0) -> bool:
	return river_distance(x, z) < RIVER_HALF_WIDTH + margin

# --- Zones ---------------------------------------------------------------------------------

static func _blob_field(x: float, z: float, blobs: Array) -> float:
	var best := -1.0
	for blob in blobs:
		best = maxf(best, 1.0 - Vector2(x - float(blob[0]), z - float(blob[1])).length() / float(blob[2]))
	return best + 0.12 * sin(x * 0.045 + 1.3) * sin(z * 0.05 + 0.4) + 0.05 * sin(x * 0.13 + z * 0.11)

## Poids des zones en un point : [désert, pinède, mesas, berges], somme = 1.
func zone_weights(x: float, z: float) -> Array:
	var river := 1.0 - smoothstep(RIVER_HALF_WIDTH + 3.0, RIVER_BANK, river_distance(x, z))
	var forest := smoothstep(0.0, 0.25, _blob_field(x, z, FOREST_BLOBS)) * (1.0 - river)
	var badlands := smoothstep(0.0, 0.25, _blob_field(x, z, BADLANDS_BLOBS)) * (1.0 - river)
	return [maxf(0.0, 1.0 - river - forest - badlands), forest, badlands, river]

## Zone dominante en un point.
func zone_at(x: float, z: float) -> String:
	var weights := zone_weights(x, z)
	var names := [ZONE_DESERT, ZONE_FOREST, ZONE_BADLANDS, ZONE_RIVER]
	var best := 0
	for i in range(1, 4):
		if float(weights[i]) > float(weights[best]):
			best = i
	return names[best]

## Clé de traduction du nom d'une zone.
func zone_name_key(zone: String) -> String:
	for label in ZONE_LABELS:
		if label["zone"] == zone:
			return label["name"]
	return ""

func get_zone_labels() -> Array:
	return ZONE_LABELS

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
		[RockGenerator.RockType.HOODOO, hoodoo_count, true, false, 0.7, "", "hoodoo"],
		[RockGenerator.RockType.BUTTE, butte_count, true, false, 0.85, "", "butte"],
		[RockGenerator.RockType.BOULDER, boulder_count, false, true, 0.85, "sandstone", "boulder"],
	]
	for rock in rocks:
		var meshes := _rock_meshes(rock[0] as RockGenerator.RockType, rock[5] as String)
		for entry in _split_counts(rock[1] as int, meshes.size()):
			var mesh: Mesh = meshes[entry[0]]
		# Collision calquée sur le maillage réellement généré (tailles aléatoires).
			var box := mesh.get_aabb()
			var radius := maxf(box.size.x, box.size.z) * 0.5 * (rock[4] as float)
			# Les grands reliefs restent visibles de partout ; les blocs disparaissent au loin.
			var far := 0.0 if (rock[2] as bool) else RANGE_MEDIUM
			for chunk in _place_multimesh(mesh, entry[1] as int, rock[2] as bool,
					radius, box.size.y, rock[3] as bool, box.position.y + box.size.y * 0.5, far, true, [], rock[6] as String):
				_props_root.add_child(chunk)

	var plants := [
		[VegetationGenerator.PlantType.PINE, pine_count, 0.45, 4.0, "pine"],
		[VegetationGenerator.PlantType.SHRUB, shrub_count, 0.0, 0.0, "shrub"],
		[VegetationGenerator.PlantType.DRY_GRASS, grass_count, 0.0, 0.0, "grass"],
		[VegetationGenerator.PlantType.CACTUS, cactus_count, 0.4, 3.0, "cactus"],
		[VegetationGenerator.PlantType.AGAVE, agave_count, 0.0, 0.0, "", "agave"],
		[VegetationGenerator.PlantType.FLOWERS, flower_count, 0.0, 0.0, "flowers"],
	]
	for plant in plants:
		var meshes := _plant_meshes(plant[0] as VegetationGenerator.PlantType, plant[4] as String)
		for entry in _split_counts(plant[1] as int, meshes.size()):
			var mesh: Mesh = meshes[entry[0]]
			var box := mesh.get_aabb()
			var cr: float = plant[2] as float
			var ch: float = plant[3] as float
			if cr > 0.0:
				# Le cylindre de collision épouse le tronc : rayon borné, hauteur du maillage.
				cr = minf(cr, maxf(box.size.x, box.size.z) * 0.5)
				ch = box.size.y
			var tall := cr > 0.0
			var small := VfxWind.is_windy(plant[4] as String) and (plant[4] as String) != "shrub"
			var far := RANGE_MEDIUM if tall else (RANGE_NEAR if small else RANGE_SHRUB)
			var kind: String = plant[5] if plant.size() > 5 else plant[4]
			for chunk in _place_multimesh(mesh, entry[1] as int, false, cr, ch, false, -1.0, far, tall, [], kind):
				_props_root.add_child(chunk)

	# Ajouts placés APRÈS le décor historique : le tirage aléatoire des éléments existants
	# (et donc la carte des joueurs) ne change pas.
	# Arches naturelles (grands repères, toujours visibles) : une collision par pied.
	if use_glb_props and arch_count > 0:
		var arches := GlbPropLibrary.get_variant_meshes("arch")
		if not arches.is_empty():
			for entry in _split_counts(arch_count, arches.size()):
				var arch: Mesh = arches[entry[0]]
				var half_span := arch.get_aabb().size.x * 0.5 - 1.6
				for chunk in _place_multimesh(arch, entry[1] as int, true, 1.9, 5.0, false, 2.0, 0.0, true,
						[Vector3(half_span, 0.0, 0.0), Vector3(-half_span, 0.0, 0.0)], "arch"):
					_props_root.add_child(chunk)
	# Cailloux : parsèment le sol proche, sans collision ni ombre.
	if use_glb_props and pebble_count > 0:
		var pebbles := GlbPropLibrary.get_variant_meshes("pebble")
		if not pebbles.is_empty():
			for entry in _split_counts(pebble_count, pebbles.size()):
				for chunk in _place_multimesh(pebbles[entry[0]], entry[1] as int, false, 0.0, 0.0, false, -1.0, RANGE_PEBBLE, false, [], "pebble"):
					_props_root.add_child(chunk)
	if extra_grass_count > 0:
		var grasses := _plant_meshes(VegetationGenerator.PlantType.DRY_GRASS, "grass")
		for entry in _split_counts(extra_grass_count, grasses.size()):
			for chunk in _place_multimesh(grasses[entry[0]], entry[1] as int, false, 0.0, 0.0, false, -1.0, RANGE_NEAR, false, [], "grass"):
				_props_root.add_child(chunk)

## Maillages d'un type de rocher : variantes GLB si disponibles, sinon procédural.
func _rock_meshes(type: RockGenerator.RockType, glb_key: String) -> Array:
	if use_glb_props and not glb_key.is_empty():
		var variants := GlbPropLibrary.get_variant_meshes(glb_key)
		if not variants.is_empty():
			return variants
	return [RockGenerator.generate(type, rng)]

func _plant_meshes(type: VegetationGenerator.PlantType, glb_key: String) -> Array:
	var out: Array = []
	if use_glb_props and not glb_key.is_empty():
		var variants := GlbPropLibrary.get_variant_meshes(glb_key)
		if not variants.is_empty():
			out = variants
	else:
		out = [VegetationGenerator.generate(type, rng)]
	# Vent sur la végétation basse : copie du maillage + matériaux shader (l'original
	# en cache reste intact pour les autres usages, ex. buisson de baies).
	if VfxWind.is_windy(glb_key):
		var windy: Array = []
		for m in out:
			windy.append(VfxWind.apply_to_mesh(m, glb_key, 0.06))
		return windy
	return out

## Répartit `total` instances sur `n` variantes en gardant la somme exacte.
static func _split_counts(total: int, n: int) -> Array:
	var out := []
	var base := total / n
	var rem := total % n
	for i in range(n):
		out.append([i, base + (1 if i < rem else 0)])
	return out

## Place `count` instances et les regroupe par bloc de CHUNK_SIZE mètres : un MultiMesh par
## bloc, pour que le moteur n'affiche que les blocs dans le champ et à portée (`range_end`,
## 0 = toujours visible). Retourne la liste des MultiMeshInstance3D.
func _place_multimesh(mesh: Mesh, count: int, is_large_rock: bool,
		collider_radius: float = 0.0, collider_height: float = 0.0,
		collider_sphere: bool = false, collider_center_y: float = -1.0,
		range_end: float = 0.0, casts_shadow: bool = true, collider_offsets: Array = [],
		kind: String = "") -> Array:
	var buckets: Dictionary = {}
	for i in range(count):
		var pos := _random_ground_position(is_large_rock, kind)
		var scale_v := rng.randf_range(0.7, 1.4)
		# Attention : Transform3D.rotated()/scaled() appliquent aussi la rotation et l'échelle
		# à l'ORIGINE (le décor se retrouvait déplacé, flottant ou enterré, et ne
		# correspondait plus à ses collisions). On construit donc base + origine séparément.
		var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * scale_v)
		var transform := Transform3D(basis, pos)
		var cell := Vector2i(int(floor(pos.x / CHUNK_SIZE)), int(floor(pos.z / CHUNK_SIZE)))
		if not buckets.has(cell):
			buckets[cell] = []
		(buckets[cell] as Array).append(transform)
		prop_placements.append(transform)
		if _prop_collision != null and collider_radius > 0.0:
			var center_y := collider_center_y if collider_center_y > -1.0 else collider_height * 0.5
			if collider_offsets.is_empty():
				_add_prop_shape(pos, scale_v, collider_radius, collider_height, collider_sphere, center_y)
			else:
				# Plusieurs formes par instance (pieds d'une arche), tournées avec elle.
				for offset in collider_offsets:
					var at := pos + basis * (offset as Vector3)
					_add_prop_shape(Vector3(at.x, pos.y, at.z), scale_v, collider_radius, collider_height, collider_sphere, center_y)

	var instances: Array = []
	for cell in buckets:
		var transforms: Array = buckets[cell]
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = mesh
		multimesh.instance_count = transforms.size()
		# Le nœud est posé au centre du bloc (les portées se mesurent depuis lui) ; les
		# instances sont exprimées par rapport à ce centre.
		var centre := Vector3.ZERO
		for t in transforms:
			centre += (t as Transform3D).origin
		centre /= float(transforms.size())
		for i in transforms.size():
			var local: Transform3D = transforms[i]
			local.origin -= centre
			multimesh.set_instance_transform(i, local)
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = multimesh
		instance.position = centre
		instance.cast_shadow = (GeometryInstance3D.SHADOW_CASTING_SETTING_ON if casts_shadow
				else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		if range_end > 0.0:
			# La distance se mesure depuis le centre du bloc : on ajoute sa demi-diagonale.
			instance.visibility_range_end = range_end + CHUNK_SIZE * 0.71
			instance.visibility_range_end_margin = 10.0
		instances.append(instance)
	return instances

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

## Tire un point du sol pour un élément du décor : jamais dans l'eau, et d'autant plus
## volontiers que la zone lui convient (AFFINITY) — pins en pinède, cactus au désert…
func _random_ground_position(is_large_rock: bool, kind: String = "") -> Vector3:
	var margin := 30.0 if is_large_rock else 8.0
	var half := terrain_size * 0.5 - margin
	var affinity: Array = AFFINITY.get(kind, [])
	var water_margin := 6.0 if is_large_rock else 1.5
	var fallback := Vector3.ZERO
	for attempt in range(60):
		var x := rng.randf_range(-half, half)
		var z := rng.randf_range(-half, half)
		var y := terrain_height_at(x, z)
		if y < -8.0 or is_water(x, z, water_margin):
			continue
		# Le camp de départ reste dégagé : pas de grand relief à côté, rien de solide dessus.
		var from_start := START_POINT.distance_to(Vector2(x, z))
		if from_start < (40.0 if is_large_rock else (18.0 if kind in SOLID_KINDS else 0.0)):
			continue
		if is_large_rock:
			var slope_check := terrain_height_at(x + 2.0, z) - terrain_height_at(x - 2.0, z)
			if abs(slope_check) > 3.0:
				continue
		fallback = Vector3(x, y, z)
		if not affinity.is_empty():
			var weights := zone_weights(x, z)
			var chance := 0.0
			for i in 4:
				chance += float(weights[i]) * float(affinity[i])
			if rng.randf() > chance:
				continue
		return fallback
	return fallback

# --- Rivière : surface et points d'eau -------------------------------------------------------

## Ruban d'eau le long du tracé, disques des deux lacs, et point d'eau qui suit le joueur.
func _build_river() -> void:
	_river = Node3D.new()
	_river.name = "River"
	add_child(_river)
	var material := ShaderMaterial.new()
	material.shader = load("res://assets/landscapes/shaders/river_surface.gdshader")
	var half := RIVER_HALF_WIDTH + 2.0
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var step := 3.0
	var count := int((RIVER_X_MAX - RIVER_X_MIN) / step) + 1
	for i in count:
		var x := RIVER_X_MIN + step * float(i)
		var centre := Vector2(x, river_center_z(x))
		var ahead := Vector2(x + 0.5, river_center_z(x + 0.5)) - Vector2(x - 0.5, river_center_z(x - 0.5))
		var side := Vector2(-ahead.y, ahead.x).normalized()
		var y := water_level_at(x)
		for edge in [-1.0, 0.0, 1.0]:
			var p: Vector2 = centre + side * half * edge
			vertices.append(Vector3(p.x, y, p.y))
			# UV.x : 0 au bord, 1 au milieu du lit ; UV.y : distance le long du courant.
			uvs.append(Vector2(1.0 - absf(edge), x))
			normals.append(Vector3.UP)
		if i > 0:
			var b := (i - 1) * 3
			for k in 2:
				var a0 := b + k
				var a1 := b + k + 1
				var c0 := b + 3 + k
				var c1 := b + 4 + k
				indices.append_array([a0, c0, a1, a1, c0, c1])
	for end_x in [RIVER_X_MIN, RIVER_X_MAX]:
		var centre := Vector3(end_x, water_level_at(end_x) - 0.01, river_center_z(end_x))
		var start := vertices.size()
		vertices.append(centre)
		uvs.append(Vector2(1.0, end_x))
		normals.append(Vector3.UP)
		var ring := 24
		var radius := LAKE_RADIUS + 2.0
		for k in ring:
			var angle := TAU * float(k) / float(ring)
			vertices.append(centre + Vector3(cos(angle), 0.0, sin(angle)) * radius)
			uvs.append(Vector2(0.0, end_x))
			normals.append(Vector3.UP)
		for k in ring:
			indices.append_array([start, start + 1 + k, start + 1 + (k + 1) % ring])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	var surface := MeshInstance3D.new()
	surface.name = "Surface"
	surface.mesh = mesh
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_river.add_child(surface)
	_river.add_child(RiverWater.create(self))

# --- Horizon -------------------------------------------------------------------------------

## Couronne de mesas et de buttes au loin, posées sur une plaine qui prolonge le désert.
## Un seul maillage (≈ 4 300 triangles), sans ombre ; le brouillard les fond dans le ciel.
func _build_horizon() -> void:
	_horizon = Node3D.new()
	_horizon.name = "Horizon"
	add_child(_horizon)
	var horizon_rng := RandomNumberGenerator.new()
	horizon_rng.seed = seed_value + 4242
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in HORIZON_MESAS:
		# Angles répartis avec du jeu, pour qu'aucun côté ne soit vide.
		var angle := TAU * (float(i) + horizon_rng.randf_range(-0.35, 0.35)) / float(HORIZON_MESAS)
		var radius := horizon_rng.randf_range(HORIZON_RADIUS_MIN, HORIZON_RADIUS_MAX)
		var centre := Vector2(cos(angle), sin(angle)) * radius
		var spire := horizon_rng.randf() < 0.22
		var width := horizon_rng.randf_range(10.0, 22.0) if spire else horizon_rng.randf_range(35.0, 110.0)
		var height := horizon_rng.randf_range(45.0, 85.0) if spire else horizon_rng.randf_range(22.0, 60.0) * (0.6 + width / 160.0)
		var tint := horizon_rng.randf_range(-1.0, 1.0)
		_add_mesa(st, horizon_rng, centre, width, height, angle, tint)
	_add_horizon_ground(st)
	st.generate_normals()
	var mesh := st.commit()
	var material := ShaderMaterial.new()
	material.shader = load("res://assets/landscapes/shaders/horizon_mesa.gdshader")
	mesh.surface_set_material(0, material)
	var instance := MeshInstance3D.new()
	instance.name = "Mesas"
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Toujours visible : il ne faut jamais voir le bord du monde.
	instance.extra_cull_margin = 200.0
	_horizon.add_child(instance)

## Une mesa : contour irrégulier, flancs en deux gradins légèrement rentrants, sommet plat.
## Couleur de sommet : R = teinte propre (-1 à 1 ramené à 0..1), G = 1 sur le plateau.
func _add_mesa(st: SurfaceTool, horizon_rng: RandomNumberGenerator, centre: Vector2, width: float,
		height: float, facing: float, tint: float) -> void:
	var sides := 11
	var stretch := horizon_rng.randf_range(1.0, 1.9)
	var ring: Array[Vector2] = []
	for k in sides:
		var a := TAU * float(k) / float(sides)
		var r := width * 0.5 * horizon_rng.randf_range(0.75, 1.15)
		# Étirée le long de la couronne : de longues falaises plutôt que des tours.
		var local := Vector2(cos(a) * r * stretch, sin(a) * r)
		ring.append(centre + local.rotated(facing + PI * 0.5))
	var base_y := HORIZON_GROUND_Y - 2.0
	var ledge_y := HORIZON_GROUND_Y + height * horizon_rng.randf_range(0.35, 0.6)
	var top_y := HORIZON_GROUND_Y + height
	var talus := 1.0 + horizon_rng.randf_range(0.18, 0.32)
	var shrink := horizon_rng.randf_range(0.78, 0.92)
	var color_side := Color(0.5 + 0.5 * tint, 0.0, 0.0)
	var color_top := Color(0.5 + 0.5 * tint, 1.0, 0.0)
	# Pied évasé (éboulis), gradin, falaise sommitale.
	var levels := [[talus, base_y], [1.0, ledge_y - 2.0], [shrink, ledge_y + 1.0], [shrink * 0.97, top_y]]
	for l in range(levels.size() - 1):
		var lo: Array = levels[l]
		var hi: Array = levels[l + 1]
		for k in sides:
			var a0 := centre + (ring[k] - centre) * float(lo[0])
			var a1 := centre + (ring[(k + 1) % sides] - centre) * float(lo[0])
			var b0 := centre + (ring[k] - centre) * float(hi[0])
			var b1 := centre + (ring[(k + 1) % sides] - centre) * float(hi[0])
			var p0 := Vector3(a0.x, float(lo[1]), a0.y)
			var p1 := Vector3(a1.x, float(lo[1]), a1.y)
			var q0 := Vector3(b0.x, float(hi[1]), b0.y)
			var q1 := Vector3(b1.x, float(hi[1]), b1.y)
			for v in [p0, q0, p1, p1, q0, q1]:
				st.set_color(color_side)
				st.add_vertex(v)
	var top: Array = levels[levels.size() - 1]
	var c3 := Vector3(centre.x, float(top[1]), centre.y)
	for k in sides:
		var a0 := centre + (ring[k] - centre) * float(top[0])
		var a1 := centre + (ring[(k + 1) % sides] - centre) * float(top[0])
		for v in [c3, Vector3(a1.x, float(top[1]), a1.y), Vector3(a0.x, float(top[1]), a0.y)]:
			st.set_color(color_top)
			st.add_vertex(v)

## Anneau de plaine entre le bord de la carte et l'horizon (couleur de sommet B = 1).
func _add_horizon_ground(st: SurfaceTool) -> void:
	var segments := 64
	var edge := terrain_size * 0.5 - 6.0
	var outer := HORIZON_RADIUS_MAX + 400.0
	var ground := Color(0.5, 0.0, 1.0)
	for k in segments:
		var a0 := TAU * float(k) / float(segments)
		var a1 := TAU * float(k + 1) / float(segments)
		var d0 := Vector3(cos(a0), 0.0, sin(a0))
		var d1 := Vector3(cos(a1), 0.0, sin(a1))
		# Bord intérieur sur le carré de la carte, caché sous les falaises du bord.
		var i0 := d0 * edge / maxf(absf(d0.x), absf(d0.z))
		var i1 := d1 * edge / maxf(absf(d1.x), absf(d1.z))
		var o0 := d0 * outer
		var o1 := d1 * outer
		for v in [i0, o0, i1, i1, o0, o1]:
			st.set_color(ground)
			st.add_vertex(v + Vector3(0.0, HORIZON_GROUND_Y, 0.0))
