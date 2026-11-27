extends Node
## Fog of war: shadowcast vision, sight range and darkvision, shared vs exclusive vision,
## remembered (explored) cells, and the DM's fog requests through Session.
## Run: Godot --headless --path . res://tests/fog_test.tscn

var errors := 0

func check(ok: bool, what: String) -> void:
	if ok:
		print("  ok   ", what)
	else:
		errors += 1
		print("  FAIL ", what)

func at(mask: PackedByteArray, st: Dictionary, p: Vector2i) -> bool:
	return mask[p.y * int(st.w) + p.x] == 1

func pc(eng: EngineBase, owner: int, pos: Vector2i, senses := "") -> Dictionary:
	var c = CombatantFactory.from_character(eng.new_id("p"), CharacterStore.premades()[0], owner)
	c.pos = pos
	c.senses = senses
	eng.s.combatants[c.id] = c
	return c

func _ready() -> void:
	print("== vision")
	var st = EngineBase.new_state(20, 12)
	var eng = CombatEngine.new(st)
	# A wall across x = 8, rows 0..10, with a gap at row 11.
	for y in 11:
		eng.set_cell(Vector2i(8, y), EngineBase.WALL)
	st.fog = {"mode": "soft", "shared": true, "range": 0}
	var a = pc(eng, 2, Vector2i(3, 5))
	var v = Fog.vision(eng, a)
	check(at(v, st, Vector2i(3, 5)), "a creature sees its own cell")
	check(at(v, st, Vector2i(7, 5)), "sees open floor in front of the wall")
	check(at(v, st, Vector2i(8, 5)), "sees the wall itself")
	check(not at(v, st, Vector2i(12, 5)), "can't see behind the wall")
	check(at(v, st, Vector2i(0, 0)), "unlimited range reaches the far corner on its side")
	# Sight range: 30 ft = 6 cells.
	st.fog.range = 30
	v = Fog.vision(eng, a)
	check(at(v, st, Vector2i(3, 11)), "sees 6 cells away with 30 ft range")
	st.fog.range = 10
	v = Fog.vision(eng, a)
	check(at(v, st, Vector2i(5, 3)) and not at(v, st, Vector2i(6, 5)) and not at(v, st, Vector2i(3, 8)), "10 ft range: 2 cells, no further")
	st.fog.range = 30
	v = Fog.vision(eng, a)
	check(at(v, st, Vector2i(3, 0)), "sees 5 cells up")
	var b = pc(eng, 2, Vector2i(1, 1), "darkvision 60 ft")
	var vb = Fog.vision(eng, b)
	check(at(vb, st, Vector2i(1, 11)), "darkvision 60 ft sees 10 cells in the dark")
	check(Fog.special_sight_ft({"senses": "Darkvision 120 ft., passive Perception 9"}) == 120 and Fog.special_sight_ft({"senses": "blindsight 10 ft, darkvision 60 ft"}) == 60, "senses text parsed")
	# Blinded: only its own cell.
	st.fog.range = 0
	eng.add_effect(a, {"name": "Blinded", "cond": "blinded", "src": "dm", "rounds": 9999, "tick_cid": "none"})
	v = Fog.vision(eng, a)
	var lit := 0
	for i in v.size():
		lit += v[i]
	check(lit == 1, "a blinded creature sees only its own space (%d cells)" % lit)
	eng.remove_effects_where(a, func(e): return e.get("cond", "") == "blinded")
	# Heavily obscured zone blocks sight; blindsight sees through it.
	st.zones.append({"name": "Fog Cloud", "cells": [Vector2i(5, 4), Vector2i(5, 5), Vector2i(5, 6)], "data": {"obscure": true}})
	v = Fog.vision(eng, a)
	check(at(v, st, Vector2i(5, 5)), "sees the edge of a fog cloud")
	check(not at(v, st, Vector2i(6, 5)), "can't see past a fog cloud")
	a.senses = "blindsight 30 ft"
	v = Fog.vision(eng, a)
	check(at(v, st, Vector2i(6, 5)), "blindsight sees through the fog cloud")
	a.senses = ""
	st.zones = []

	print("== shared vs exclusive")
	var c = pc(eng, 3, Vector2i(15, 5))   # another player's character, beyond the wall
	var gob = CombatantFactory.from_monster(eng.new_id("m"), "goblin")
	gob.pos = Vector2i(16, 6)
	st.combatants[gob.id] = gob
	var view2 = Fog.view_for(eng, 2)
	check(Fog.sees(view2, eng, gob), "shared: player 2 sees the goblin through player 3's eyes")
	st.fog.shared = false
	view2 = Fog.view_for(eng, 2)
	var view3 = Fog.view_for(eng, 3)
	check(not Fog.sees(view2, eng, gob), "exclusive: player 2 can't see the goblin")
	check(Fog.sees(view3, eng, gob), "exclusive: player 3 still sees it")
	check(Fog.sees(view2, eng, a), "a player always sees their own character")
	st.fog.mode = "off"
	check(Fog.view_for(eng, 2).is_empty() and Fog.sees({}, eng, gob), "fog off: everything visible")

	print("== memory (explored)")
	st.fog = {"mode": "hard", "shared": true, "range": 0}
	st.fog_seen = {}
	st.combatants.erase(c.id)
	Fog.update_seen(eng)
	var vw = Fog.view_for(eng, 2)
	check(not at(vw.explored, st, Vector2i(14, 2)), "hard: unexplored beyond the wall")
	# Walk through the gap at row 11 and look around.
	eng.remove_effects_where(a, func(_e): return true)
	Fog.update_seen(eng, [{"t": "move", "cid": a.id, "path": [Vector2i(5, 11), Vector2i(8, 11), Vector2i(11, 11)]}])
	a.pos = Vector2i(11, 11)
	vw = Fog.view_for(eng, 2)
	check(at(vw.explored, st, Vector2i(14, 2)), "cells seen along the path are remembered")
	a.pos = Vector2i(3, 5)
	b.pos = Vector2i(1, 1)
	vw = Fog.view_for(eng, 2)
	check(at(vw.explored, st, Vector2i(14, 2)) and not at(vw.visible, st, Vector2i(14, 2)), "back behind the wall: remembered but not visible")
	Fog.paint(st, [Vector2i(14, 2)], false)
	vw = Fog.view_for(eng, 2)
	check(not at(vw.explored, st, Vector2i(14, 2)), "DM re-fogs a cell")
	Fog.paint(st, [Vector2i(19, 0)], true)
	check(at(Fog.view_for(eng, 2).explored, st, Vector2i(19, 0)), "DM reveals a cell")
	Fog.reveal_all(st)
	check(at(Fog.view_for(eng, 2).explored, st, Vector2i(18, 10)), "DM reveals the whole map")

	print("== session requests")
	Session.start_offline("DM", 20, 12)
	var s2: Dictionary = Session.state
	Session.add_character(CharacterStore.premades()[0], 1)
	Session.request({"type": "dm_fog", "mode": "hard", "shared": false, "range": 60})
	check(Fog.settings(s2).mode == "hard" and not Fog.settings(s2).shared and Fog.settings(s2).range == 60, "dm_fog sets mode, sharing and range")
	check(not s2.fog_seen.is_empty(), "the server remembers what the party saw")
	Session.request({"type": "dm_fog_reset"})
	check(s2.fog_seen.size() == 1, "reset forgets, then re-sees from where the party stands")
	Session.request({"type": "dm_fog_reveal"})
	check(s2.fog_seen.has(Fog.DM_REVEAL), "reveal-all marks every cell")
	var snap = Session.map_snapshot()
	check(snap.fog.mode == "hard", "saved maps keep fog settings")
	Session.request({"type": "dm_resize", "w": 24, "h": 14})
	check(not s2.fog_seen.has(Fog.DM_REVEAL), "resizing the map forgets what was explored")
	Session.request({"type": "dm_fog", "mode": "off"})
	Session.request({"type": "dm_load_map", "map": snap})
	check(Fog.settings(Session.state).mode == "hard", "loading a map brings its fog settings")
	Session.leave()

	# Speed: a big open map with six viewers.
	var big = EngineBase.new_state(80, 60)
	var beng = CombatEngine.new(big)
	big.fog = {"mode": "hard", "shared": true, "range": 0}
	for i in 6:
		pc(beng, 1, Vector2i(5 + i * 10, 30))
	var t0 := Time.get_ticks_msec()
	Fog.update_seen(beng)
	Fog.view_for(beng, 0)
	print("  80x60 map, 6 viewers: %d ms" % (Time.get_ticks_msec() - t0))
	print("FOG DONE errors=%d" % errors)
	get_tree().quit(1 if errors > 0 else 0)
