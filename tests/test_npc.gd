extends SceneTree
## PNJ (GDD §4.6, premier PNJ) : trappeur placé au départ, dialogue via le HUD,
## quête « quest_trapper » verrouillée jusqu'à acceptation dans le dialogue,
## puis complétée en rapportant les peaux.

var _failures: int = 0

func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok - ", label)
	else:
		_failures += 1
		print("  FAIL - ", label)

func _init() -> void:
	await process_frame
	var quests := root.get_node_or_null("QuestManager")
	if quests == null:
		quests = load("res://scripts/autoload/quest_manager.gd").new()
		quests.name = "QuestManager"
		root.add_child(quests)
		await process_frame
	quests.call("clear_for_test")
	var inventory := root.get_node_or_null("Inventory")
	if inventory != null:
		inventory.call("clear_for_test")

	var world := (load("res://scenes/world/canyon_playground.tscn") as PackedScene).instantiate()
	root.add_child(world)
	for i in 10:
		await process_frame
	var player := world.get_node("Player") as Node3D

	# --- PNJ placé au départ ---
	var npcs := get_nodes_in_group("npcs")
	_check(npcs.size() == 1, "un PNJ placé (groupe npcs), got %d" % npcs.size())
	if npcs.is_empty():
		quit(1)
	var npc: Node = npcs[0]
	_check(npc.global_position.distance_to(player.global_position) < 15.0, "PNJ proche du départ (%d m)" % int(npc.global_position.distance_to(player.global_position)))
	_check(npc.call("get_prompt") == "ACTION_TALK", "prompt Parler")
	_check(String(npc.call("get_name_key")) == "NPC_TRAPPER_NAME", "c'est le trappeur")

	# --- Quête verrouillée tant que non acceptée ---
	_check(String(quests.call("state_name", quests.call("state_of", "quest_trapper"))) == "locked", "quest_trapper verrouillée au départ")
	_check(not quests.call("get_active").has("quest_trapper"), "pas active au départ")
	_check(String(npc.call("offered_quest")) == "quest_trapper", "le PNJ offre quest_trapper")

	# --- Dialogue via le HUD : interact ouvre le panneau ---
	var hud := world.get_node("HUD")
	npc.call("interact", player)
	await process_frame
	var panel: Control = hud.get("dialogue_panel")
	_check(panel != null, "dialogue_panel présent dans le HUD")
	if panel != null:
		_check(panel.visible, "interact ouvre le panneau de dialogue")
		var accept_btn: Control = panel.get("_accept_button")
		_check(accept_btn != null and accept_btn.visible, "bouton Accepter visible (quête offerte)")
		panel.call("_on_accept")
		await process_frame
		_check(String(quests.call("state_name", quests.call("state_of", "quest_trapper"))) == "active", "quête active après acceptation")
		_check(String(npc.call("offered_quest")) == "", "plus de quête offerte après acceptation")
		_check(not bool(npc.call("accept_quest")), "accept_quest refuse une quête déjà acceptée")
		# Fermeture par ui_cancel.
		var ev := InputEventAction.new()
		ev.action = "ui_cancel"
		ev.pressed = true
		panel.call("_unhandled_key_input", ev)
		_check(not panel.visible, "ui_cancel ferme le dialogue")

	# --- La quête se termine en rapportant 3 peaux ---
	inventory.call("add_item", "item_pelt", 3)
	await process_frame
	_check(String(quests.call("state_name", quests.call("state_of", "quest_trapper"))) == "completed", "quête terminée avec 3 peaux")

	# --- Le journal ferme le dialogue et inversement ---
	npc.call("interact", player)
	await process_frame
	if panel != null and panel.visible:
		hud.call("_on_journal_pressed")
		await process_frame
		_check(not panel.visible, "ouvrir le journal ferme le dialogue")

	# --- Locales ---
	for lang in ["fr", "en"]:
		var csv := FileAccess.get_file_as_string("res://locales/translations.%s.csv" % lang)
		for key in ["ACTION_TALK", "ACTION_ACCEPT_QUEST", "ACTION_BYE", "NPC_TRAPPER_NAME",
				"NPC_TRAPPER_LINE1", "NPC_TRAPPER_LINE2", "NPC_TRAPPER_LINE3",
				"QUEST_TRAPPER_TITLE", "QUEST_TRAPPER_DESC", "TOAST_QUEST_ACCEPTED"]:
			if not csv.contains(key + ","):
				_failures += 1
				print("  FAIL - %s : clé %s manquante" % [lang, key])

	print("TEST_NPC: ", "PASS" if _failures == 0 else "FAIL")
	quit(1 if _failures > 0 else 0)
