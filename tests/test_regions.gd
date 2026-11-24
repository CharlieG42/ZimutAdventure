extends SceneTree
## Régions (biomes) : définitions, déblocage par niveau, voyage persistant, palettes appliquées
## (ciel via DayNightCycle, terrain, météo) et faune par région.
## Note : dans un test -s, les autoloads ne sont pas des identifiants globaux -> get_node_or_null.

var _failures: int = 0
var _spawner: GDScript
var rm: Node
var prog: Node

func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok - ", label)
	else:
		_failures += 1
		print("  FAIL - ", label)

func _init() -> void:
	await process_frame
	_spawner = load("res://scripts/world/predator_spawner.gd")
	rm = root.get_node_or_null("RegionManager")
	prog = root.get_node_or_null("Progression")
	_check(rm != null, "autoload RegionManager présent")
	rm.call("clear_for_test")
	prog.call("clear_for_test")

	# --- Définitions ---
	var ids: Array = rm.call("region_ids")
	_check(ids.size() == 3, "3 régions définies")
	_check(rm.call("has_region", "western") and rm.call("has_region", "outback") and rm.call("has_region", "canada"), "ids western/outback/canada")
	for rid in ids:
		var scene := load(rm.call("scene_for", rid)) as PackedScene
		_check(scene != null, "scène de %s charge (%s)" % [rid, rm.call("scene_for", rid)])

	# --- Déblocage par niveau ---
	prog.set("level", 1)
	_check(rm.call("is_unlocked", "western"), "niveau 1 : Ouest débloqué")
	_check(not rm.call("is_unlocked", "outback"), "niveau 1 : Outback verrouillé")
	_check(not rm.call("is_unlocked", "canada"), "niveau 1 : Canada verrouillé")
	prog.set("level", 4)
	_check(rm.call("is_unlocked", "outback"), "niveau 4 : Outback débloqué")
	_check(not rm.call("is_unlocked", "canada"), "niveau 4 : Canada encore verrouillé")
	prog.set("level", 8)
	_check(rm.call("is_unlocked", "canada"), "niveau 8 : Canada débloqué")
	prog.set("level", 1)

	# --- Voyage ---
	rm.set("change_scene_enabled", false)
	rm.set("_autosave", true)  # clear_for_test a désactivé l'autosave : on le remet pour tester la persistance
	_check(not rm.call("travel_to", "canada"), "voyage verrouillé refusé (niveau 1)")
	prog.set("level", 4)
	_check(rm.call("travel_to", "outback"), "voyage vers l'Outback accepté (niveau 4)")
	_check(rm.get("current_region") == "outback", "région courante = outback")
	# Persistance : le fichier de la partie est relu.
	var cfg_path := SaveSlots.file("region.cfg")
	var cfg := ConfigFile.new()
	_check(cfg.load(cfg_path) == OK and String(cfg.get_value("region", "current", "")) == "outback", "région persistée dans le fichier de partie")
	rm.set("current_region", "western")
	rm.call("reload_from_disk")
	_check(rm.get("current_region") == "outback", "reload_from_disk relit la région sauvegardée")
	DirAccess.remove_absolute(cfg_path)
	rm.call("clear_for_test")
	rm.set("change_scene_enabled", false)

	# --- Faune par région ---
	_check(rm.call("animals", "passive", "outback").has("kangaroo"), "faune outback : kangourou")
	_check(rm.call("animals", "predators", "canada").has("bear"), "prédateurs canada : ours")
	var preds_west: Array = rm.call("animals", "predators", "western")
	var preds_out: Array = rm.call("animals", "predators", "outback")
	var preds_can: Array = rm.call("animals", "predators", "canada")
	_check(_spawner.plan("night", 5, preds_west)["species"] == "wolf", "plan western niv5 nuit : loup")
	_check(_spawner.plan("night", 2, preds_west)["species"] == "coyote", "plan western niv2 nuit : coyote")
	_check(_spawner.plan("night", 5, preds_out)["species"] == "dingo", "plan outback niv5 nuit : dingo")
	_check(_spawner.plan("night", 5, preds_can)["species"] == "bear", "plan canada niv5 nuit : ours")
	var pa := load("res://scripts/world/passive_animal.gd")
	_check(pa.SPECIES.has("kangaroo") and pa.SPECIES.has("moose"), "espèces passives kangaroo/moose enregistrées")
	var pred := load("res://scripts/world/predator.gd")
	_check(pred.PREDATORS.has("dingo") and pred.PREDATORS.has("bear"), "prédateurs dingo/ours enregistrés")

	# --- Application au monde (scène outback) ---
	rm.set("current_region", "outback")
	var world := (load("res://scenes/world/outback_playground.tscn") as PackedScene).instantiate()
	root.add_child(world)
	for i in 12:
		await process_frame
	var clock := root.get_node_or_null("DayNightCycle")
	clock.call("set_hour", 12.0)
	await process_frame
	var env_node := world.get_node("WorldEnvironment") as WorldEnvironment
	var sky_mat: ShaderMaterial = env_node.environment.sky.sky_material as ShaderMaterial
	var top_day: Color = sky_mat.get_shader_parameter("top_color")
	var expected: Color = rm.call("palette", "outback").get("top_day")
	_check(top_day.is_equal_approx(expected), "ciel outback à midi = palette de la région (%s vs %s)" % [top_day, expected])
	var weather := root.get_node_or_null("Weather")
	_check(weather != null and String(weather.call("get_season")) == "summer", "météo outback : saison imposée = été")
	var landscape := world.get_node("Landscape")
	var terrain := landscape.get_node("Terrain") as MeshInstance3D
	var tmat := terrain.get_active_material(0) as ShaderMaterial
	var strata: Color = tmat.get_shader_parameter("strata_light")
	_check(strata.is_equal_approx(Color(0.88, 0.42, 0.18)), "terrain outback : strata_light rouge (%s)" % strata)
	_check(terrain.get_surface_override_material(0) != null, "matériau de terrain dupliqué (pas de fuite entre régions)")

	# Retour à l'Ouest : palette historique inchangée.
	rm.call("clear_for_test")
	rm.set("change_scene_enabled", false)
	var world2 := (load("res://scenes/world/canyon_playground.tscn") as PackedScene).instantiate()
	root.add_child(world2)
	for i in 12:
		await process_frame
	clock.call("set_hour", 12.0)
	await process_frame
	var env2 := world2.get_node("WorldEnvironment") as WorldEnvironment
	var top2: Color = (env2.environment.sky.sky_material as ShaderMaterial).get_shader_parameter("top_color")
	_check(top2.is_equal_approx(Color(0.2, 0.45, 0.86)), "ciel western à midi inchangé (%s)" % top2)

	print("TEST_REGIONS: ", "PASS" if _failures == 0 else "FAIL")
	quit(1 if _failures > 0 else 0)
