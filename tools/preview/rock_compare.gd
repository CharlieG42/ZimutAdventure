extends Node3D
## Aperçu comparatif de rochers : procédural d'origine, Kenney (corrigé), généré en Python.
## Lancer : godot --path . res://tools/preview/rock_compare.tscn --write-movie out.png

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.62, 0.74, 0.9)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.78, 0.9)
	e.ambient_light_energy = 0.3
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -35, 0)
	sun.light_energy = 0.6
	sun.shadow_enabled = true
	add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 20)
	floor_mesh.mesh = plane
	var sand := StandardMaterial3D.new()
	sand.albedo_color = Color(0.72, 0.56, 0.38)
	sand.roughness = 1.0
	floor_mesh.material_override = sand
	add_child(floor_mesh)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 2.6, 9.5)
	cam.rotation_degrees = Vector3(-12, 0, 0)
	cam.fov = 48
	add_child(cam)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var procedural := RockGenerator.generate(RockGenerator.RockType.BOULDER, rng)
	_place(procedural, null, Vector3(-4.2, 0, 0), "AVANT\nprocédural d'origine")
	var kenney := GlbPropLibrary.get_variant_meshes("boulder")
	_place(kenney[2], null, Vector3(0, 0, 0), "Kenney (corrigé)")
	var packed := load("res://assets/props/generated/rock_1.glb") as PackedScene
	var node := packed.instantiate() as Node3D
	node.position = Vector3(4.2, 0, 0)
	_fix_vertex_colors(node)
	add_child(node)
	_label("APRÈS\ngénéré en Python", Vector3(4.2, 3.1, 0))

func _place(mesh: Mesh, material: Material, at: Vector3, text: String) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = at
	if material != null:
		mi.material_override = material
	add_child(mi)
	_label(text, at + Vector3(0, 3.1, 0))

func _label(text: String, at: Vector3) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 56
	label.pixel_size = 0.008
	label.position = at
	label.modulate = Color(0.1, 0.07, 0.04)
	add_child(label)

## Les couleurs de sommets du GLB servent d'albédo.
func _fix_vertex_colors(node: Node) -> void:
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(i) as StandardMaterial3D
			if mat != null:
				var fixed := mat.duplicate() as StandardMaterial3D
				fixed.vertex_color_use_as_albedo = true
				mi.mesh.surface_set_material(i, fixed)
