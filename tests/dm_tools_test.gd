extends Node
## Headless checks for the DM toolbox: placement, hidden monsters, HP tools, conditions, group rolls,
## initiative edits, removal and map changes. Drives Session the way the battle screen does.
## Run: Godot --headless --path . res://tests/dm_tools_test.tscn   (exit code 1 on failure)

var fails := 0
var passes := 0

func check(cond: bool, what: String) -> void:
	if cond:
		passes += 1
	else:
		fails += 1
		print("FAIL: ", what)

func req(r: Dictionary) -> void:
	Session.request(r)

func eng() -> CombatEngine:
	return Session.engine

func fresh() -> void:
	Session.start_offline("DM", 20, 12)
	Session.auto_monsters = false

func mon_named(n: String) -> Dictionary:
	for c in eng().all_combatants():
		if c.name == n:
			return c
	for c in Session.state.get("reserve", {}).values():
		if c.name == n:
			return c
	return {}

func _ready() -> void:
	var hero_ch: Dictionary = CharacterStore.premades()[0]

	# --- Placement: no stacking, team and numbering.
	fresh()
	req({"type": "dm_place_monster", "mid": "goblin", "at": Vector2i(5, 5)})
	req({"type": "dm_place_monster", "mid": "goblin", "at": Vector2i(5, 5)})
	check(eng().all_combatants().size() == 1, "a monster can't be placed on top of another")
	eng().set_cell(Vector2i(7, 7), EngineBase.WALL)
	req({"type": "dm_place_monster", "mid": "goblin", "at": Vector2i(7, 7)})
	check(eng().all_combatants().size() == 1, "a monster can't be placed in a wall")
	req({"type": "dm_place_monster", "mid": "ogre", "at": Vector2i(4, 4)})
	check(eng().all_combatants().size() == 1, "a Large monster can't overlap another creature")
	req({"type": "dm_place_monster", "mid": "goblin", "at": Vector2i(6, 6), "team": "party"})
	var g2 := mon_named("Goblin 2")
	check(not g2.is_empty() and g2.team == "party", "placed as an ally in one request, numbered Goblin 2")
	req({"type": "dm_remove", "cid": mon_named("Goblin").id})
	req({"type": "dm_place_monster", "mid": "goblin", "at": Vector2i(8, 5)})
	var names := {}
	for c in eng().all_combatants():
		names[c.name] = true
	check(names.size() == eng().all_combatants().size(), "no duplicate names after removing the first goblin (%s)" % str(names.keys()))

	# --- Hidden monsters: off the map and out of the initiative until revealed.
	fresh()
	var hid := Session.add_character(hero_ch, 1, Vector2i(2, 2))
	req({"type": "dm_place_monster", "mid": "orc", "at": Vector2i(10, 5)})
	req({"type": "dm_place_monster", "mid": "goblin", "at": Vector2i(12, 5), "hidden": true})
	var gob := mon_named("Goblin")
	check(Session.state.reserve.has(gob.id) and eng().C(gob.id).is_empty(), "a monster placed hidden is in the reserve, not on the map")
	req({"type": "dm_place_monster", "mid": "orc", "at": Vector2i(12, 5)})
	check(eng().all_combatants().size() == 2, "can't place a creature on a hidden monster's cell")
	var snap := Session.map_snapshot()
	check(snap.monsters.any(func(m): return m.get("hidden", false)), "map save keeps hidden monsters")
	req({"type": "dm_start_combat"})
	check(not gob.id in Session.state.order and Session.state.order.size() == 2, "hidden monsters don't roll initiative")
	var cur_before: String = eng().current().id
	req({"type": "dm_hidden", "cid": gob.id})
	check(gob.id in Session.state.order and not eng().C(gob.id).is_empty(), "revealing mid-fight puts it on the map and in the initiative")
	check(eng().current().id == cur_before, "revealing doesn't change whose turn it is")
	req({"type": "dm_hidden", "cids": [gob.id]})
	check(not gob.id in Session.state.order and Session.state.reserve.has(gob.id), "hiding again takes it out of the initiative")
	req({"type": "dm_hidden", "cid": hid})
	check(not eng().C(hid).is_empty(), "player characters can't be hidden")
	req({"type": "dm_move_hidden", "cid": gob.id, "to": Vector2i(15, 8)})
	check(Session.state.reserve[gob.id].pos == Vector2i(15, 8), "the DM can move a hidden monster")
	req({"type": "dm_load_map", "map": snap})
	check(Session.state.reserve.size() == 1 and eng().all_combatants().filter(func(c): return c.kind == "monster").size() == 1, "loading a map restores hidden monsters as hidden")
	req({"type": "dm_reveal_all"})
	check(Session.state.reserve.is_empty(), "Reveal all empties the reserve")

	# --- Damage, heal and set HP.
	fresh()
	req({"type": "dm_place_monster", "mid": "skeleton", "at": Vector2i(5, 5)})
	req({"type": "dm_place_monster", "mid": "skeleton", "at": Vector2i(7, 5)})
	var s1 := mon_named("Skeleton")
	var s2 := mon_named("Skeleton 2")
	s1.hp = 13; s2.hp = 13; s1.max_hp = 13; s2.max_hp = 13
	req({"type": "dm_hp", "cids": [s1.id, s2.id], "amount": -4})
	check(s1.hp == 9 and s2.hp == 9, "untyped DM damage hits every selected creature in full (%d, %d)" % [s1.hp, s2.hp])
	req({"type": "dm_hp", "cid": s1.id, "amount": -4, "dtype": "poison"})
	check(s1.hp == 9, "typed DM damage respects immunity (skeleton vs poison)")
	req({"type": "dm_hp", "cid": s1.id, "amount": -2, "dtype": "bludgeoning"})
	check(s1.hp == 5, "typed DM damage respects vulnerability (got %d)" % s1.hp)
	req({"type": "dm_set_hp", "cid": s1.id, "hp": 0})
	check(s1.dead, "Set HP 0 slays a monster")
	req({"type": "dm_hp", "cid": s1.id, "amount": 6})
	check(not s1.dead and s1.hp == 6, "healing a slain monster brings it back (DM override)")
	req({"type": "dm_set_hp", "cid": s2.id, "hp": 11})
	check(s2.hp == 11, "Set HP sets the number")
	var pc := eng().C(Session.add_character(hero_ch, 1, Vector2i(2, 2)))
	req({"type": "dm_set_hp", "cid": pc.id, "hp": 0})
	check(pc.hp == 0 and not pc.death.dead and eng().has_cond(pc, "prone"), "Set HP 0 on a PC knocks it unconscious, not dead")
	req({"type": "dm_set_hp", "cid": pc.id, "hp": 5})
	check(pc.hp == 5, "Set HP brings a dying PC back up")

	# --- Conditions: group toggle and timed conditions.
	req({"type": "dm_condition", "cids": [s1.id, s2.id], "cond": "restrained"})
	check(eng().has_cond(s1, "restrained") and eng().has_cond(s2, "restrained"), "condition applied to the whole selection")
	req({"type": "dm_condition", "cids": [s1.id, s2.id], "cond": "restrained"})
	check(not eng().has_cond(s1, "restrained") and not eng().has_cond(s2, "restrained"), "toggling again removes it from all")
	req({"type": "dm_condition", "cid": s1.id, "cond": "prone"})
	req({"type": "dm_condition", "cids": [s1.id, s2.id], "cond": "prone"})
	check(eng().has_cond(s1, "prone") and eng().has_cond(s2, "prone"), "mixed selection: the condition goes on everyone who lacks it")
	req({"type": "dm_condition", "cids": [s1.id, s2.id], "cond": "prone"})
	req({"type": "dm_start_combat"})
	req({"type": "dm_condition", "cid": s2.id, "cond": "blinded", "rounds": 2})
	var turns := 0
	for i in 12:
		if not eng().has_cond(s2, "blinded"):
			break
		if eng().current().id == s2.id:
			turns += 1
		req({"type": "dm_next_turn"})
	check(not eng().has_cond(s2, "blinded") and turns == 2, "a 2-round condition ends after the creature's 2nd turn (took %d)" % turns)
	req({"type": "dm_end_combat"})

	# --- Exhaustion.
	req({"type": "dm_exhaustion", "cid": pc.id, "delta": 1})
	req({"type": "dm_exhaustion", "cid": pc.id, "delta": 1})
	check(eng().exhaustion(pc) == 2, "two levels of exhaustion")
	check(eng().eff_speed(pc) < int(pc.speed), "exhaustion 2 halves speed")
	req({"type": "dm_exhaustion", "cid": pc.id, "delta": -1})
	check(eng().exhaustion(pc) == 1, "remove a level")
	s1.cond_immune.append("exhaustion")
	req({"type": "dm_exhaustion", "cid": s1.id, "delta": 1})
	check(eng().exhaustion(s1) == 0, "a creature immune to exhaustion gains none")

	# --- Group rolls: a trap that deals 20 on a failed DEX save, half on a success.
	fresh()
	var a := eng().C(Session.add_character(hero_ch, 1, Vector2i(2, 2)))
	var b := eng().C(Session.add_character(CharacterStore.premades()[1], 1, Vector2i(4, 2)))
	a.max_hp = 200; a.hp = 200; b.max_hp = 200; b.hp = 200
	req({"type": "roll", "cids": [a.id, b.id], "kind": "save", "ability": "dex", "dc": 99, "damage": "20", "half": true})
	check(a.hp == 180 and b.hp == 180, "DC 99 trap: everyone fails and takes the full 20")
	req({"type": "roll", "cids": [a.id], "kind": "save", "ability": "dex", "dc": 1, "damage": "20", "half": true})
	check(a.hp == 170 or a.features.has("evasion"), "DC 1 trap: success takes half")
	a.features["evasion"] = true
	req({"type": "roll", "cids": [a.id], "kind": "save", "ability": "dex", "dc": 1, "damage": "20", "half": true})
	check(a.hp == 170, "Evasion: a successful DEX save takes nothing")
	var log_n: int = Session.state.log.size()
	req({"type": "roll", "cids": [a.id], "kind": "check", "ability": "wis", "skill": "perception"})
	check(Session.state.log.size() > log_n and str(Session.state.log[-1]).contains("="), "a skill check logs a total")
	# A player can roll for their own character, but can't attach damage or roll for others.
	a.owner = 5
	var hp_b: int = b.hp
	Session._handle(5, {"type": "roll", "cids": [a.id, b.id], "kind": "save", "ability": "dex", "dc": 99, "damage": "50"})
	check(a.hp == 170 and b.hp == hp_b, "players can't attach damage to rolls")
	a.owner = 1

	# --- Initiative edits and removals keep the right creature acting.
	fresh()
	Session.add_character(hero_ch, 1, Vector2i(1, 10))
	Session.add_character(hero_ch, 1, Vector2i(3, 10))
	Session.add_character(hero_ch, 1, Vector2i(5, 10))
	for i in 4:
		req({"type": "dm_place_monster", "mid": "goblin", "at": Vector2i(3 + i * 2, 3)})
	req({"type": "dm_start_combat"})
	var order: Array = Session.state.order.duplicate()
	var cur: String = eng().current().id
	var last: Dictionary = eng().C(order[-1])
	req({"type": "dm_init", "cid": last.id, "init": 40})
	check(Session.state.order[0] == last.id and eng().current().id == cur, "setting initiative re-sorts without changing whose turn it is")
	req({"type": "dm_next_turn"})
	cur = eng().current().id
	var before_idx: int = Session.state.order.find(cur) - 1
	if before_idx >= 0:
		req({"type": "dm_remove", "cid": Session.state.order[before_idx]})
		check(eng().current().id == cur, "removing someone earlier in the order keeps the current turn")
	var nxt: String = Session.state.order[(Session.state.order.find(cur) + 1) % Session.state.order.size()]
	req({"type": "dm_remove", "cid": cur})
	check(eng().current().id == nxt, "removing the current creature passes the turn to the next one")
	# Clear dead keeps the turn and spares PCs.
	var pcd := eng().C(Session.add_character(hero_ch, 1, Vector2i(10, 10)))
	pcd.hp = 0; pcd.death.dead = true; pcd.dead = false
	var victims: Array = Session.state.order.filter(func(id): return id != eng().current().id and eng().C(id).kind == "monster")
	cur = eng().current().id
	if not victims.is_empty():
		var v: Dictionary = eng().C(victims[0])
		v.hp = 0; v.dead = true
		req({"type": "dm_clear_dead"})
		check(eng().C(v.id).is_empty() and eng().current().id == cur, "Remove defeated monsters keeps the current turn")
	check(not eng().C(pcd.id).is_empty(), "Remove defeated monsters leaves dead PCs for revival")

	# --- Map changes never strand creatures in walls or off the map.
	fresh()
	var far := eng().C(Session.add_character(hero_ch, 1, Vector2i(18, 10)))
	req({"type": "dm_resize", "w": 10, "h": 8})
	check(eng().in_bounds(far.pos), "shrinking the map pulls creatures back onto it (%s)" % str(far.pos))
	var walled := {"name": "walls", "w": 10, "h": 8, "cells": [], "monsters": [], "spawns": []}
	var cells: Array = []
	for i in 80:
		cells.append(EngineBase.WALL if i < 40 else EngineBase.FLOOR)
	walled.cells = cells
	far.pos = Vector2i(1, 1)
	req({"type": "dm_load_map", "map": walled})
	check(not eng().blocks_move(far.pos), "loading a map moves characters out of walls (%s)" % str(far.pos))

	# --- Reconnect: a dropped player's character is handed back instead of duplicated.
	fresh()
	var ch2: Dictionary = hero_ch.duplicate(true)
	ch2.id = "abc123"
	var rid := Session.add_character(ch2, 7, Vector2i(3, 3))
	var rc := eng().C(rid)
	rc.owner = 1
	rc.orphan = true
	var back := Session._orphan_for(ch2)
	check(back.get("id", "") == rid and not rc.has("orphan"), "a reconnecting player gets their old token back")

	# --- Chat dice: sane expressions only (a huge roll would freeze the game).
	check(Session._valid_dice("1d20+5") and Session._valid_dice("2d6+1d4-1") and Session._valid_dice("d20"), "normal dice expressions are accepted")
	check(not Session._valid_dice("99999999d6") and not Session._valid_dice("abc") and not Session._valid_dice("1d0") and not Session._valid_dice(""), "absurd or malformed dice are refused")
	var got: Array = []
	var grab = func(t): got.append(t)
	Session.chat_received.connect(grab)
	Session.send_chat("/roll 1d20+4 adv")
	Session.send_chat("/hroll 2d6")
	Session.send_chat("/roll lots")
	Session.chat_received.disconnect(grab)
	check(got.size() == 3 and str(got[0]).contains("adv") and str(got[1]).contains("private") and str(got[2]).contains("Can't roll"), "chat rolls: advantage, private DM roll, bad input (%s)" % str(got))

	# --- Battle screen: multi-select, hidden ghosts and the inspect panel build without errors.
	fresh()
	Session.add_character(hero_ch, 1, Vector2i(2, 2))
	req({"type": "dm_place_monster", "mid": "orc", "at": Vector2i(8, 4)})
	req({"type": "dm_place_monster", "mid": "orc", "at": Vector2i(10, 4), "hidden": true})
	var scene = load("res://scenes/battle.tscn").instantiate()
	add_child(scene)
	await get_tree().process_frame
	var hidden_id: String = Session.state.reserve.keys()[0]
	check(scene.tokens.has(hidden_id), "the DM sees a ghost token for a hidden monster")
	scene._select_team("enemy")
	check(scene._selection().size() == 1, "Select enemies picks the visible enemy")
	scene._on_left_click(Vector2i(10, 4), false, true)
	check(scene._selection().size() == 2, "Ctrl+click adds the hidden monster to the selection")
	scene._refresh_inspect()
	check(scene.inspect_box.get_child_count() > 3, "inspect panel builds for a mixed selection")
	scene._on_left_click(Vector2i(10, 4), false, true)
	check(scene._selection().size() == 1, "Ctrl+click again removes it")
	scene.selected_cid = hidden_id
	scene._on_left_click(Vector2i(12, 6), false, false)
	check(Session.state.reserve[hidden_id].pos == Vector2i(12, 6), "clicking an empty cell moves the selected hidden monster")
	scene._remove_selected()
	check(Session.state.reserve.is_empty(), "Delete removes a hidden monster")
	scene.queue_free()
	await get_tree().process_frame

	print("DM TOOLS DONE passed=%d failed=%d" % [passes, fails])
	get_tree().quit(1 if fails > 0 else 0)
