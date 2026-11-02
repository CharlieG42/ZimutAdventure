class_name GlbPropLibrary
extends RefCounted
## Bibliothèque des props GLB externes (assets/props/kenney/, sources Kenney CC0
## + ruines composées par tools/make_glb_props.py). Godot importe les .glb nativement.
## Si un prop est indisponible (fichier absent ou non importé), les accesseurs
## renvoient un tableau vide / null : les appelants retombent sur le procédural.

const PROP_ROOT := "res://assets/props/kenney/"

## prop_id -> variantes (chemins relatifs à PROP_ROOT).
const PROPS := {
	"pine": [
		"nature/pine_default_a.glb", "nature/pine_default_b.glb",
		"nature/pine_tall_a.glb", "nature/pine_tall_b.glb",
		"nature/pine_round_a.glb", "nature/pine_round_b.glb", "nature/pine_round_c.glb",
		"nature/pine_small_a.glb", "nature/pine_small_b.glb",
	],
	"boulder": [
		"nature/boulder_a.glb", "nature/boulder_b.glb", "nature/boulder_c.glb",
		"nature/boulder_d.glb", "nature/boulder_e.glb", "nature/boulder_f.glb",
		"nature/boulder_g.glb", "nature/boulder_h.glb",
		"nature/boulder_flat_a.glb", "nature/boulder_flat_b.glb",
	],
	"shrub": [
		"nature/shrub_a.glb", "nature/shrub_b.glb", "nature/shrub_c.glb", "nature/shrub_d.glb",
	],
	"grass": ["nature/grass_a.glb", "nature/grass_b.glb", "nature/grass_c.glb"],
	"flowers": [
		"nature/flower_red_a.glb", "nature/flower_red_b.glb", "nature/flower_red_c.glb",
		"nature/flower_purple_a.glb", "nature/flower_purple_b.glb", "nature/flower_purple_c.glb",
		"nature/flower_yellow_a.glb", "nature/flower_yellow_b.glb", "nature/flower_yellow_c.glb",
	],
	"cactus": ["nature/cactus_short.glb", "nature/cactus_tall.glb"],
	"ruin": ["castle/ruin_a.glb", "castle/ruin_b.glb"],
}

static var _mesh_cache: Dictionary = {}

static func get_paths(prop_id: String) -> Array:
	return PROPS.get(prop_id, [])

static func has_prop(prop_id: String) -> bool:
	return not get_paths(prop_id).is_empty()

## Un maillage (ArrayMesh, toutes surfaces fusionnées) par variante du prop.
static func get_variant_meshes(prop_id: String) -> Array:
	if _mesh_cache.has(prop_id):
		return _mesh_cache[prop_id]
	var meshes: Array = []
	for rel in get_paths(prop_id):
		var mesh := _load_merged_mesh(PROP_ROOT + rel)
		if mesh != null:
			meshes.append(mesh)
	_mesh_cache[prop_id] = meshes
	return meshes

## Instancie une variante aléatoire de la scène GLB (ex. ruine), ou null.
static func instantiate_scene(prop_id: String, rng := RandomNumberGenerator.new()) -> Node3D:
	var paths := get_paths(prop_id)
	if paths.is_empty():
		return null
	var packed: PackedScene = load(PROP_ROOT + paths[rng.randi() % paths.size()])
	if packed == null:
		return null
	return packed.instantiate()

static func _load_merged_mesh(path: String) -> Mesh:
	var packed: PackedScene = load(path)
	if packed == null:
		return null
	var scene := packed.instantiate() as Node3D
	if scene == null:
		return null
	var groups: Array = []
	_collect_into(scene, Transform3D.IDENTITY, groups)
	scene.free()
	if groups.is_empty():
		return null
	# Les nœuds GLB (tmpParent Kenney) peuvent décaler le maillage sous y=0 :
	# on remonte tout pour que le prop repose exactement sur le sol.
	var min_y := INF
	for g in groups:
		var verts: PackedVector3Array = g["arrays"][Mesh.ARRAY_VERTEX]
		for i in range(verts.size()):
			min_y = minf(min_y, verts[i].y)
	if min_y < -0.001:
		for g in groups:
			var verts: PackedVector3Array = g["arrays"][Mesh.ARRAY_VERTEX]
			for i in range(verts.size()):
				verts[i].y -= min_y
	var mesh := ArrayMesh.new()
	for g in groups:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, g["arrays"])
		if g["material"] != null:
			mesh.surface_set_material(mesh.get_surface_count() - 1, g["material"])
	return mesh

## Aplatit toutes les surfaces de tous les MeshInstance3D de la scène en groupes
## (un groupe = une surface de sortie, avec sa transformée nodale baked et son matériau).
static func _collect_into(node: Node3D, parent_xform: Transform3D, groups: Array) -> void:
	var xform: Transform3D = parent_xform * node.transform
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			return
		for si in range(mi.mesh.get_surface_count()):
			var arr := mi.mesh.surface_get_arrays(si)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			if verts.is_empty():
				continue
			var g := {"arrays": [], "material": null}
			g["arrays"].resize(Mesh.ARRAY_MAX)
			var v := PackedVector3Array()
			v.resize(verts.size())
			var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
			var indices: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			var basis := xform.basis
			for i in range(verts.size()):
				v[i] = xform * verts[i]
				if n != null and i < n.size():
					n[i] = (basis * n[i]).normalized()
			var idx := PackedInt32Array()
			if indices == null or indices.is_empty():
				idx.resize(verts.size())
				for i in range(verts.size()):
					idx[i] = i
			else:
				idx = indices
			g["arrays"][Mesh.ARRAY_VERTEX] = v
			g["arrays"][Mesh.ARRAY_NORMAL] = n
			if uv != null and not uv.is_empty():
				g["arrays"][Mesh.ARRAY_TEX_UV] = uv
			g["arrays"][Mesh.ARRAY_INDEX] = idx
			var mat: Material = mi.mesh.surface_get_material(si)
			if mat == null:
				mat = mi.material_override
			g["material"] = mat
			groups.append(g)
	for child in node.get_children():
		if child is Node3D:
			_collect_into(child as Node3D, xform, groups)
