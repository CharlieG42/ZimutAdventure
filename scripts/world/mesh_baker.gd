class_name MeshBaker
extends RefCounted
## Fusionne les petits maillages d'un modèle construit par code (animaux, personnages) :
## sous chaque pivot, tous les MeshInstance3D marqués « bake » deviennent un seul maillage
## dont la couleur est portée par les sommets. Un animal passe ainsi d'une trentaine
## d'appels de dessin à un par pivot animé (corps, cou, tête, queue, pattes).

const MARK := "bake"

static var _material: StandardMaterial3D

static func shared_material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.roughness = 1.0
	return _material

## Vrai si ce maillage peut être fondu (matériau opaque, éclairé, sans émission ni texture).
static func is_bakeable(instance: MeshInstance3D) -> bool:
	if not instance.has_meta(MARK) or instance.mesh == null or instance.get_child_count() > 0:
		return false
	var mat := instance.material_override as StandardMaterial3D
	if mat == null:
		return false
	return (mat.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED
			and mat.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED
			and not mat.emission_enabled and mat.albedo_texture == null)

## Fusionne récursivement sous `root`. Retourne le nombre de maillages supprimés.
static func bake(root: Node3D) -> int:
	var removed := 0
	var pivots: Array = [root]
	pivots.append_array(root.find_children("*", "Node3D", true, false))
	for pivot in pivots:
		if pivot is MeshInstance3D:
			continue
		var parts: Array = []
		for child in (pivot as Node).get_children():
			if child is MeshInstance3D and is_bakeable(child):
				parts.append(child)
		if parts.size() < 2:
			continue
		var merged := merge(parts)
		if merged == null:
			continue
		var instance := MeshInstance3D.new()
		instance.name = "Baked"
		instance.mesh = merged
		instance.material_override = shared_material()
		instance.cast_shadow = (parts[0] as MeshInstance3D).cast_shadow
		(pivot as Node).add_child(instance)
		for part in parts:
			(pivot as Node).remove_child(part)
			(part as Node).queue_free()
			removed += 1
		removed -= 1
	return removed

## Un seul ArrayMesh à partir des maillages donnés (transformations locales appliquées).
static func merge(parts: Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for part in parts:
		var instance := part as MeshInstance3D
		var xform := instance.transform
		var normal_basis := xform.basis.inverse().transposed()
		var color: Color = (instance.material_override as StandardMaterial3D).albedo_color
		for surface in instance.mesh.get_surface_count():
			var arrays := instance.mesh.surface_get_arrays(surface)
			var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var n = arrays[Mesh.ARRAY_NORMAL]
			var idx = arrays[Mesh.ARRAY_INDEX]
			var base := verts.size()
			for i in v.size():
				verts.append(xform * v[i])
				normals.append((normal_basis * (n[i] as Vector3)).normalized() if n != null else Vector3.UP)
				colors.append(color)
			if idx != null:
				for i in (idx as PackedInt32Array):
					indices.append(base + i)
			else:
				for i in v.size():
					indices.append(base + i)
	if verts.is_empty():
		return null
	var arrays_out := []
	arrays_out.resize(Mesh.ARRAY_MAX)
	arrays_out[Mesh.ARRAY_VERTEX] = verts
	arrays_out[Mesh.ARRAY_NORMAL] = normals
	arrays_out[Mesh.ARRAY_COLOR] = colors
	arrays_out[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays_out)
	return mesh
