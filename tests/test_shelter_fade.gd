extends SceneTree
## L'abri devient transparent quand la caméra s'en approche, et redevient opaque ensuite.

var _failures: int = 0

func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok - ", label)
	else:
		_failures += 1
		print("  FAIL - ", label)

func _initialize() -> void:
	await process_frame
	var shelter: Node3D = load("res://scripts/world/placed_structure.gd").create("shelter")
	root.add_child(shelter)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.current = true
	await process_frame
	camera.global_position = shelter.to_global(Vector3(0.0, 1.5, 12.0))
	for i in 90:
		await process_frame
	_check(shelter.call("fade_amount") == 0.0, "caméra loin : abri opaque")
	camera.global_position = shelter.to_global(Vector3(4.0, 1.5, 0.0))
	for i in 60:
		await process_frame
	_check(shelter.call("fade_amount") > 0.5, "caméra contre le mur : abri transparent")
	var meshes := shelter.find_children("*", "MeshInstance3D", true, false)
	_check(not meshes.is_empty() and (meshes[0] as MeshInstance3D).transparency > 0.5, "les maillages sont transparents")
	camera.global_position = shelter.to_global(Vector3(0.0, 1.5, 15.0))
	for i in 90:
		await process_frame
	_check(shelter.call("fade_amount") == 0.0, "caméra éloignée : abri de nouveau opaque")
	print("TEST_SHELTER_FADE: ", "PASS" if _failures == 0 else "FAIL")
	quit(1 if _failures > 0 else 0)
