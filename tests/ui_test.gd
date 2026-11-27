extends Node
## Headless UI smoke test: instantiate every screen and drive a short solo battle.

func _ready() -> void:
	for path in ["res://scenes/main_menu.tscn", "res://scenes/characters.tscn"]:
		var s = load(path).instantiate()
		add_child(s)
		await get_tree().process_frame
		await get_tree().process_frame
		print("OK ", path)
		s.queue_free()
		await get_tree().process_frame
	# Solo battle.
	Session.start_offline("Tester", 26, 18)
	var y := 4
	var no_questions := {}
	for fid in EngineBase.FIX_NAMES:
		no_questions[fid] = true  # this test drives the battle, it does not answer "use Lucky?"
	for ch0 in CharacterStore.premades():
		var ch: Dictionary = ch0.duplicate(true)
		ch["auto_fix"] = no_questions
		Session.add_character(ch, 1, Vector2i(3, y))
		y += 2
	for mid in ["goblin", "goblin", "orc", "mage"]:
		Session.add_monster(mid, Vector2i(18, y - 6))
		y += 1
	var b = load("res://scenes/battle.tscn").instantiate()
	add_child(b)
	await get_tree().process_frame
	print("OK battle scene")
	# Exercise hotbar building for every character.
	for c in Session.state.combatants.values():
		b.control_cid = c.id
		b.selected_cid = c.id
		b._refresh_ui()
	Session.request({"type": "dm_start_combat"})
	for i in 40:
		await get_tree().create_timer(0.25).timeout
		if not Session.state.in_combat:
			break
		var cur = Session.engine.current()
		if cur.kind == "pc":
			Session.request({"type": "ai_turn", "cid": cur.id})
	print("Round reached: ", Session.state.round, " in_combat=", Session.state.in_combat)
	for l in Session.state.log.slice(-12): print("  LOG ", l)
	# Paint + map save/load round trip.
	Session.request({"type": "dm_cells", "cells": [Vector2i(5, 5), Vector2i(6, 5)], "value": 1})
	var snap = Session.map_snapshot()
	CharacterStore.save_map("ui_test_map", snap)
	Session.request({"type": "dm_load_map", "map": CharacterStore.load_map("ui_test_map")})
	print("map cell after load: ", Session.engine.cell(Vector2i(5, 5)))
	await _smite_popup(b)
	print("UI TEST DONE")
	get_tree().quit()

## A player's paladin hits: the battle screen asks about Divine Smite and sends the answer.
func _smite_popup(b: Node) -> void:
	var eng: CombatEngine = Session.engine
	if Session.state.in_combat:
		Session.request({"type": "dm_end_combat"})
	for o in eng.all_combatants():
		Session.state.combatants.erase(o.id)
	var pal_ch: Dictionary = CharacterStore.premades().filter(func(ch): return ch.name.begins_with("Seraphine"))[0]
	var pid: String = Session.add_character(pal_ch, 1, Vector2i(4, 4))
	var oid: String = Session.add_monster("ogre", Vector2i(5, 4))
	var pal: Dictionary = eng.C(pid)
	var ogre: Dictionary = eng.C(oid)
	ogre.hp = 900
	ogre.max_hp = 900
	Session.auto_monsters = false
	Session.request({"type": "dm_start_combat"})
	var ok := false
	for i in 30:
		eng.s.turn = eng.s.order.find(pid)
		eng.begin_turn(pal)
		b.control_cid = pid
		Session.request({"type": "action", "cid": pid, "aid": "atk:" + pal.attacks[0].id, "params": {"targets": [oid]}})
		await get_tree().process_frame
		if Session.state.get("pending_hit", {}).is_empty():
			continue
		var pm: PopupMenu = null
		for n in b.ui.get_children():
			if n is PopupMenu and n.visible:
				pm = n
		if pm == null:
			print("UI FAIL: no smite popup for a pending hit")
			break
		var hp_before: int = ogre.hp
		pm.id_pressed.emit(1)  # first smite option: the lowest slot
		await get_tree().process_frame
		ok = Session.state.get("pending_hit", {}).is_empty() and ogre.hp < hp_before and int(pal.slots_used[0]) == 1
		print("smite popup: ", pm.get_item_text(pm.get_item_index(1)), " -> ", "applied" if ok else "NOT applied")
		break
	print("UI smite popup ", "OK" if ok else "FAIL")
