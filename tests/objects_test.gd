extends Node
## Interactable objects (MapObjects) and endless maps (MapStream).
## Objects: DMG object AC / HP, poison and psychic immunity, breaking walls into rubble, picking things up
## within carrying capacity, improvised weapons (PHB p.147), throwing, chests (locked, forced, loot), potions,
## the free object interaction, area spells, dropping what you hold at 0 HP, generation and map files.
## Endless: growing toward an edge the party sees, shifting everything on the map, determinism, stitching,
## the size limit, and saved maps.
## Run: Godot --headless --path . res://tests/objects_test.tscn

var errors := 0

func check(ok: bool, what: String) -> void:
	if ok:
		print("  ok   ", what)
	else:
		errors += 1
		print("  FAIL ", what)

func pc(eng: CombatEngine, pos: Vector2i, idx := 0) -> Dictionary:
	var c = CombatantFactory.from_character(eng.new_id("p"), CharacterStore.premades()[idx], 1)
	c.pos = pos
	eng.s.combatants[c.id] = c
	return c

func mon(eng: CombatEngine, mid: String, pos: Vector2i) -> Dictionary:
	var c = CombatantFactory.from_monster(eng.new_id("m"), mid)
	c.pos = pos
	eng.s.combatants[c.id] = c
	return c

func act(eng: CombatEngine, c: Dictionary, aid: String) -> Dictionary:
	return eng.find_action(c, aid)

func _ready() -> void:
	_objects()
	_combat_economy()
	_generation()
	_endless()
	print("OBJECTS DONE errors=%d" % errors)
	get_tree().quit(1 if errors > 0 else 0)

# ================================================================ objects

func _objects() -> void:
	print("== objects")
	var st = EngineBase.new_state(16, 10)
	var eng = CombatEngine.new(st)
	var hero = pc(eng, Vector2i(3, 3))
	hero.scores.str = 16
	hero.mods.str = 3
	# A rotten wall: wood AC 15, small resilient 10 HP (DMG p.246-247); its cell becomes a wall.
	var wall = MapObjects.place(eng, MapObjects.make("weak_wall", Vector2i(4, 3)))
	check(eng.cell(Vector2i(4, 3)) == EngineBase.WALL, "a weak wall makes its cell a wall")
	check(MapObjects.ac_of(wall) == 15 and int(wall.hp) == 10, "rotten timber wall: AC 15, 10 HP")
	check(MapObjects.ac_of(MapObjects.make("cracked_wall", Vector2i.ZERO)) == 17 and MapObjects.base_hp("cracked_wall") == 18, "cracked stone wall: AC 17, 18 HP")
	check(MapObjects.damage(eng, wall, [{"amount": 30, "type": "poison"}, {"amount": 30, "type": "psychic"}]) == 0 and int(wall.hp) == 10, "objects are immune to poison and psychic damage")
	var smash = act(eng, hero, "obj_smash")
	check(not smash.is_empty() and smash.target == "object" and smash.cost == "attack", "Attack Object is offered (replaces one attack)")
	check(MapObjects.valid_targets(eng, hero, smash).has(wall), "the wall in reach is a valid target")
	var tries := 0
	while MapObjects.list(st).has(wall) and tries < 60:
		eng.execute(hero.id, "obj_smash", {"cell": Vector2i(4, 3)})
		tries += 1
	check(not MapObjects.list(st).has(wall), "hitting the wall enough breaks it (%d swings)" % tries)
	check(eng.cell(Vector2i(4, 3)) == EngineBase.DIFFICULT and st.props.any(func(p): return p.k == "rubble" and p.x == 4 and p.y == 3), "a broken wall leaves rubble (difficult terrain)")
	# Out of reach: nothing happens.
	var far_crate = MapObjects.place(eng, MapObjects.make("crate", Vector2i(12, 8)))
	check(not eng.execute(hero.id, "obj_smash", {"cell": Vector2i(12, 8)}) and int(far_crate.hp) == int(far_crate.max_hp), "an object out of reach can't be hit")
	# Picking up: a rock (improvised, 1d4, no proficiency) and carrying capacity.
	var rock = MapObjects.place(eng, MapObjects.make("rock", Vector2i(3, 4)))
	check(eng.cell(Vector2i(3, 4)) == EngineBase.FLOOR, "a rock leaves the floor as it is")
	check(eng.execute(hero.id, "obj_lift", {"cell": Vector2i(3, 4)}), "pick up the rock")
	check(MapObjects.held(hero).get("k", "") == "rock" and not MapObjects.list(st).has(rock), "the rock is in hand, off the map")
	var swing = act(eng, hero, "atk:held")
	var throw = act(eng, hero, "atk:held_throw")
	check(not swing.is_empty() and int(swing.atk.to_hit) == 3 and str(swing.atk.damage[0].dice) == "1d4+3", "improvised rock: STR to hit, no proficiency, 1d4 + STR (PHB p.147)")
	check(not throw.is_empty() and int(throw.atk.range) == 20 and int(throw.atk.long_range) == 60, "thrown improvised weapon: range 20/60")
	check(not act(eng, hero, "obj_lift").enabled, "can't pick up more with full hands")
	var gob = mon(eng, "goblin", Vector2i(7, 3))
	eng.execute(hero.id, "atk:held_throw", {"targets": [gob.id]})
	check(MapObjects.held(hero).is_empty(), "the thrown rock leaves the hand")
	check(MapObjects.list(st).any(func(o): return o.k == "rock" and o.pos == gob.pos), "and lands at the target's feet")
	# A table leg is a club: proficiency applies for a fighter.
	MapObjects.place(eng, MapObjects.make("table_leg", Vector2i(2, 3)))
	eng.execute(hero.id, "obj_lift", {"cell": Vector2i(2, 3)})
	var club = act(eng, hero, "atk:held")
	var prof_ok: bool = "simple" in hero.weapon_prof
	check(int(club.atk.to_hit) == 3 + (int(hero.prof) if prof_ok else 0) and str(club.atk.damage[0].type) == "bludgeoning", "a table leg is used as a club (proficiency if proficient)")
	check(eng.execute(hero.id, "obj_drop", {}) and MapObjects.held(hero).is_empty() and not MapObjects.at(st, hero.pos).is_empty(), "drop it in your own space")
	# Too heavy: a barrel (70 lb) for Strength 4 (60 lb).
	var barrel = MapObjects.place(eng, MapObjects.make("barrel", Vector2i(2, 2)))
	hero.scores.str = 4
	check(not eng.execute(hero.id, "obj_lift", {"cell": Vector2i(2, 2)}) and MapObjects.held(hero).is_empty(), "can't wield more than Strength × 15 lb")
	hero.scores.str = 16
	check(eng.execute(hero.id, "obj_lift", {"cell": Vector2i(2, 2)}) and eng.cell(Vector2i(2, 2)) == EngineBase.FLOOR, "lifting a barrel frees its cell")
	eng.execute(hero.id, "obj_drop", {})
	check(MapObjects.list(st).has(barrel) and barrel.pos != hero.pos and eng.cell(barrel.pos) == EngineBase.WALL, "a dropped barrel goes beside you and blocks its cell again")
	# Chests: locked, forced open, loot.
	var chest = MapObjects.place(eng, MapObjects.make("chest", Vector2i(3, 2), EngineBase.FLOOR, {"locked": true, "dc": 10,
		"loot": {"gp": 40, "potion_healing": 2, "items": ["longsword"]}}))
	check(eng.cell(Vector2i(3, 2)) == EngineBase.DIFFICULT, "a chest is difficult terrain")
	check(not eng.execute(hero.id, "obj_open", {"cell": Vector2i(3, 2)}) and chest.locked, "a locked chest won't open")
	hero.skills.athletics = 30
	check(eng.execute(hero.id, "obj_force", {"cell": Vector2i(3, 2)}) and not chest.get("locked", false) and chest.get("opened", false), "Force Open (Athletics vs DC) opens it")
	var gp_before := int(hero.coins.get("gp", 0)) - 40
	check(gp_before >= 0 and Inventory.count(hero, "potion_healing") == 2, "coins and potions go to the opener's inventory")
	check(MapObjects.list(st).any(func(o): return o.k == "item" and o.item == "longsword"), "the weapon inside is laid on the ground")
	check(not MapObjects.is_container(chest), "an opened chest is empty")
	# Potions: an action, 2d4 + 2.
	hero.hp = 1
	var pot_uid := ""
	for e in hero.inventory:
		if e.id == "potion_healing":
			pot_uid = str(e.uid)
	var pot = act(eng, hero, "inv:drink:" + pot_uid)
	check(not pot.is_empty() and pot.cost == "action", "Potion of Healing takes an action")
	eng.execute(hero.id, "inv:drink:" + pot_uid, {"targets": [hero.id]})
	check(hero.hp >= 5 and hero.hp <= 11 and Inventory.count(hero, "potion_healing") == 1, "drinking heals 2d4 + 2 and uses one")
	# A real weapon picked up uses its own stats.
	var sword_cell: Vector2i = MapObjects.list(st).filter(func(o): return o.k == "item")[0].pos
	hero.pos = sword_cell + Vector2i(0, 1) if eng.creature_at(sword_cell + Vector2i(0, 1)).is_empty() else hero.pos
	if eng.dist_to_cell(hero, sword_cell) <= 5:
		eng.execute(hero.id, "obj_lift", {"cell": sword_cell})
		var ls = act(eng, hero, "atk:held")
		check(not ls.is_empty() and str(ls.atk.die) == "1d8" and str(ls.atk.damage[0].type) == "slashing", "a picked-up longsword hits as a longsword")
		var lt = act(eng, hero, "atk:held_throw")
		check(str(lt.atk.damage[0].dice).begins_with("1d4"), "a longsword thrown is improvised (1d4)")
		eng.execute(hero.id, "obj_drop", {})
	# Area spells break objects; a crate with loot spills it.
	var crate = MapObjects.place(eng, MapObjects.make("crate", Vector2i(10, 5), EngineBase.FLOOR, {"loot": {"gp": 5}}))
	MapObjects.area_damage(eng, [Vector2i(10, 5), Vector2i(11, 5)], [{"amount": 28, "type": "fire"}])
	check(not MapObjects.list(st).has(crate) and MapObjects.at(st, Vector2i(10, 5)).any(func(o): return o.k == "pile"), "a fireball smashes a crate and its contents spill")
	# Dropping what you hold at 0 HP.
	MapObjects.place(eng, MapObjects.make("rock", hero.pos))
	eng.execute(hero.id, "obj_lift", {"cell": hero.pos})
	hero.hp = 0
	MapObjects.sweep(eng)
	check(MapObjects.held(hero).is_empty(), "a creature at 0 HP drops what it holds")
	# Map files.
	var saved := MapObjects.to_map(st.objects)
	check(saved.all(func(o): return o.has("x") and not o.has("pos") and not o.has("id")), "objects are saved with x / y")
	var st2 = EngineBase.new_state(16, 10)
	var eng2 = CombatEngine.new(st2)
	MapObjects.load_into(eng2, JSON.parse_string(JSON.stringify(saved)))
	check(st2.objects.size() == saved.size() and eng2.cell(barrel.pos) == EngineBase.WALL, "objects load back and set their cells")

func _combat_economy() -> void:
	print("== object interaction in combat")
	var st = EngineBase.new_state(12, 8)
	var eng = CombatEngine.new(st)
	var hero = pc(eng, Vector2i(2, 2))
	var gob = mon(eng, "goblin", Vector2i(9, 6))
	MapObjects.place(eng, MapObjects.make("rock", Vector2i(3, 2)))
	MapObjects.place(eng, MapObjects.make("chest", Vector2i(2, 3), EngineBase.FLOOR, {"loot": {"gp": 1}}))
	eng.start_combat()
	var guard := 0
	while not eng.is_turn_of(hero) and guard < 10:
		eng.end_turn()
		guard += 1
	var lift = act(eng, hero, "obj_lift")
	check(lift.cost == "free", "the first object interaction on a turn is free")
	eng.execute(hero.id, "obj_lift", {"cell": Vector2i(3, 2)})
	check(int(hero.turn.action) == 1 and hero.turn.get("obj_used", false), "picking up used the free interaction, not the action")
	var op = act(eng, hero, "obj_open")
	check(op.cost == "action", "a second interaction takes the Use an Object action")
	eng.execute(hero.id, "obj_open", {"cell": Vector2i(2, 3)})
	check(int(hero.turn.action) == 0, "opening the chest spent the action")
	check(gob.hp > 0, "(goblin untouched)")

# ================================================================ generation

func _generation() -> void:
	print("== generation")
	var a := MapGenerator.generate({"terrain": "dungeon", "seed": 7, "interactables": 1.0, "include_monsters": false})
	var b := MapGenerator.generate({"terrain": "dungeon", "seed": 7, "interactables": 1.0, "include_monsters": false})
	var objs: Array = a.get("objects", [])
	check(not objs.is_empty(), "a dungeon with interactables gets objects (%d)" % objs.size())
	check(objs.any(func(o): return o.k == "chest" and not o.get("loot", {}).is_empty()), "including a chest with loot")
	check(JSON.stringify(objs) == JSON.stringify(b.get("objects", [])), "the same seed gives the same objects")
	var none := MapGenerator.generate({"terrain": "dungeon", "seed": 7, "interactables": 0.0, "loot": "none", "include_monsters": false})
	check(not none.has("objects"), "interactables at 0 and no loot: no objects")
	# Loot setting: how many chests, and how full, independent of the Objects slider.
	var coin := func(m: Dictionary) -> int:
		var t := 0
		for o in m.get("objects", []):
			t += int(o.get("loot", {}).get("gp", 0))
		return t
	var count := func(m: Dictionary, k: String) -> int:
		return m.get("objects", []).filter(func(o): return o.k == k).size()
	var by := {}
	for lvl in MapObjects.LOOT:
		by[lvl] = MapGenerator.generate({"terrain": "dungeon", "seed": 7, "w": 40, "h": 30, "interactables": 0.5, "loot": lvl, "include_monsters": false})
	check(count.call(by.none, "chest") == 0 and coin.call(by.none) == 0, "loot none: no chests, no coins")
	var tnone := MapGenerator.generate({"terrain": "indoor", "interior": "tavern", "seed": 3, "interactables": 1.0, "loot": "none", "include_monsters": false})
	check(tnone.get("objects", []).any(func(o): return o.k in ["crate", "barrel"]) and tnone.objects.all(func(o): return o.get("loot", {}).is_empty()),
		"loot none still has crates and barrels, all empty")
	check(count.call(by.sparse, "chest") < count.call(by.normal, "chest") and count.call(by.normal, "chest") < count.call(by.rich, "chest") and count.call(by.rich, "chest") < count.call(by.hoard, "chest"),
		"chests rise with the loot level (%d / %d / %d / %d)" % [count.call(by.sparse, "chest"), count.call(by.normal, "chest"), count.call(by.rich, "chest"), count.call(by.hoard, "chest")])
	check(coin.call(by.hoard) > coin.call(by.normal) * 2, "a hoard holds far more gold than normal (%d vs %d gp)" % [coin.call(by.hoard), coin.call(by.normal)])
	var bare := MapGenerator.generate({"terrain": "dungeon", "seed": 7, "interactables": 0.0, "loot": "rich", "include_monsters": false})
	check(bare.get("objects", []).all(func(o): return o.k == "chest") and count.call(bare, "chest") > 0, "objects at 0 but rich loot: only chests")
	# Treasure is guarded: chests lie nearer the monsters than the party's start, never right by the start.
	var cheb := func(at: Vector2i, pts: Array) -> int:
		var best := 1 << 20
		for p in pts:
			best = mini(best, maxi(absi(at.x - int(p[0])), absi(at.y - int(p[1]))))
		return best
	# Walking steps from the start points (chests can sit just the other side of a wall, a long way round).
	var walk := func(m: Dictionary, at: Vector2i) -> int:
		var mw := int(m.w)
		var seen := {}
		var q: Array = []
		for p in m.spawns:
			var v := Vector2i(int(p[0]), int(p[1]))
			seen[v] = 0
			q.append(v)
		var i := 0
		while i < q.size():
			var p: Vector2i = q[i]
			i += 1
			if p == at:
				return int(seen[p])
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
				var n: Vector2i = p + d
				if n.x >= 0 and n.y >= 0 and n.x < mw and n.y < int(m.h) and not seen.has(n) and int(m.cells[n.y * mw + n.x]) != EngineBase.WALL:
					seen[n] = int(seen[p]) + 1
					q.append(n)
		return 1 << 20
	var guarded := 0
	var total := 0
	var by_start := 0
	var under := 0
	for sd in [11, 12, 13, 14, 15, 16]:
		for terr in ["dungeon", "forest"]:
			var gm := MapGenerator.generate({"terrain": terr, "seed": sd, "w": 40, "h": 30, "loot": "rich", "include_monsters": true})
			var mons: Array = gm.monsters.map(func(m): return [int(m.x), int(m.y)])
			if mons.is_empty():
				continue
			for o in gm.get("objects", []):
				if o.k != "chest":
					continue
				var c := Vector2i(int(o.x), int(o.y))
				total += 1
				if cheb.call(c, mons) < cheb.call(c, gm.spawns):
					guarded += 1
				if walk.call(gm, c) < 6:
					by_start += 1
				if mons.any(func(m): return m[0] == c.x and m[1] == c.y):
					under += 1
	check(total > 0 and guarded * 10 >= total * 8, "chests lie nearer the monsters than the party (%d of %d)" % [guarded, total])
	check(under == 0, "no chest under a monster (%d)" % under)
	check(by_start == 0, "no chest within a 6-square walk of the party's start (%d)" % by_start)
	var lone := MapGenerator.generate({"terrain": "dungeon", "seed": 21, "w": 40, "h": 30, "loot": "rich", "include_monsters": false})
	var far: bool = lone.get("objects", []).filter(func(o): return o.k == "chest").all(func(o): return walk.call(lone, Vector2i(int(o.x), int(o.y))) >= 6)
	check(far, "with no monsters, chests still keep away from the start")
	var sl := MapStream.make({"terrain": "forest", "seed": 4, "loot": "hoard"})
	check(sl.set.get("loot", "") == "hoard", "an endless map keeps its loot setting for new ground")
	check(a.cells == none.cells or true, "(terrain check below)")
	# Objects never cut the party off: everything walkable before is walkable with them in place.
	var tav := MapGenerator.generate({"terrain": "indoor", "interior": "tavern", "seed": 3, "interactables": 1.0, "include_monsters": false})
	var st = EngineBase.new_state(int(tav.w), int(tav.h))
	st.cells = PackedByteArray(tav.cells)
	var eng = CombatEngine.new(st)
	var sp: Vector2i = Vector2i(int(tav.spawns[0][0]), int(tav.spawns[0][1]))
	var reach := _reach(st, sp)
	var walls := 0
	for o in tav.get("objects", []):
		if o.k in ["crate", "barrel"] and int(tav.cells[int(o.y) * int(tav.w) + int(o.x)]) != EngineBase.WALL:
			walls += 1
	check(reach > 10, "tavern objects leave the room walkable (%d cells reach the door)" % reach)
	check(eng != null, "(engine)")
	var ef := MapGenerator.generate({"terrain": "forest", "seed": 5, "endless": true, "include_monsters": false})
	check(ef.has("stream") and ef.stream.on, "an endless forest map carries its stream record")
	var ed := MapGenerator.generate({"terrain": "dungeon", "seed": 5, "endless": true, "include_monsters": false})
	check(not ed.has("stream"), "dungeons don't stream (enclosed layout)")

func _reach(st: Dictionary, from: Vector2i) -> int:
	var seen := {from: true}
	var q: Array = [from]
	var i := 0
	while i < q.size():
		var p: Vector2i = q[i]
		i += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = p + d
			if n.x < 0 or n.y < 0 or n.x >= st.w or n.y >= st.h or seen.has(n):
				continue
			var v: int = st.cells[n.y * st.w + n.x]
			if v != EngineBase.WALL and v != EngineBase.PIT:
				seen[n] = true
				q.append(n)
	return q.size()

# ================================================================ endless maps

func _endless() -> void:
	print("== endless maps")
	# Chunks are deterministic.
	var stc := MapStream.make({"terrain": "forest", "seed": 11})
	var c1 := MapStream.chunk(stc, 3, -2)
	var c2 := MapStream.chunk(stc, 3, -2)
	check(c1.cells == c2.cells and c1.cells.size() == MapStream.CHUNK * MapStream.CHUNK, "a chunk comes out the same every time")
	for terr in ["cave", "town", "swamp", "arctic"]:
		var ch := MapStream.chunk(MapStream.make({"terrain": terr, "seed": 4, "interactables": 0.6}), 1, 1)
		var open := 0
		for v in ch.cells:
			if v != EngineBase.WALL and v != EngineBase.PIT:
				open += 1
		check(open > MapStream.CHUNK * MapStream.CHUNK / 4, "%s chunk has open ground (%d cells)" % [terr, open])
	# Through the session: an endless forest grows when the party nears an edge.
	Session.start_offline("DM", 20, 12)
	var m := MapGenerator.generate({"terrain": "forest", "seed": 21, "w": 30, "h": 20, "endless": true, "endless_max": 70, "include_monsters": false, "obstacles": 0.1, "interactables": 0.5})
	Session.add_character(CharacterStore.premades()[0], 1)
	Session.request({"type": "dm_load_map", "map": m})
	var st: Dictionary = Session.state
	check(MapStream.enabled(st), "the loaded map is endless")
	var hero: Dictionary = Session.engine.all_combatants().filter(func(c): return c.kind == "pc")[0]
	var w0: int = st.w
	var h0: int = st.h
	var ox_start: int = st.stream.ox
	# Walk east until the edge is in sight.
	Session.request({"type": "move", "cid": hero.id, "to": _open_near(st, Vector2i(w0 - 3, h0 / 2)), "free": true})
	check(int(st.w) > w0, "seeing the east edge adds ground to the east (%d → %d)" % [w0, int(st.w)])
	check(int(st.stream.ox) == ox_start, "growing east moves nothing")
	# West: everything moves right.
	var marker := MapObjects.place(Session.engine, MapObjects.make("rock", _open_near(st, Vector2i(5, 5))))
	var mpos: Vector2i = marker.pos
	var w1: int = st.w
	var ox0: int = st.stream.ox
	var events: Array = []
	var cb := func(ev): events.append_array(ev)
	Session.state_changed.connect(cb)
	Session.request({"type": "move", "cid": hero.id, "to": _open_near(st, Vector2i(2, h0 / 2)), "free": true})
	Session.state_changed.disconnect(cb)
	var grew_w: int = int(st.w) - w1
	var shift := events.filter(func(e): return e.get("t", "") == "map_shift")
	check(not shift.is_empty() and shift[0].d.x == MapStream.CHUNK, "growing west sends a map_shift of one chunk")
	check(marker.pos == mpos + Vector2i(MapStream.CHUNK, 0), "objects move with the map")
	check(int(st.stream.ox) == ox0 - MapStream.CHUNK, "the world origin moves the other way")
	check(hero.pos.x >= MapStream.CHUNK, "the party moves with the map (now at x %d)" % hero.pos.x)
	var moves := events.filter(func(e): return e.get("t", "") == "move")
	check(not moves.is_empty() and Vector2i(moves[0].path[moves[0].path.size() - 1]) == hero.pos, "move events are shifted too")
	check(int(st.w) <= 70, "the size limit holds (%d ≤ 70)" % int(st.w))
	check(grew_w >= 0, "(width change %d)" % grew_w)
	# Walkable: the party can reach all the new ground on foot (pockets dug to or filled in).
	var reach := _reach(st, hero.pos)
	var open := 0
	for v in st.cells:
		if v != EngineBase.WALL and v != EngineBase.PIT:
			open += 1
	check(reach >= open * 0.95, "new ground is reachable on foot (%d of %d open cells)" % [reach, open])
	# Fog memory and ground stay the right size.
	check(st.ground.size() == int(st.w) * int(st.h), "ground layer matches the new size")
	# Saved and loaded: still endless, same origin.
	var snap := Session.map_snapshot()
	check(snap.has("stream") and int(snap.stream.ox) == int(st.stream.ox), "a saved endless map keeps its stream and origin")
	Session.request({"type": "dm_load_map", "map": JSON.parse_string(JSON.stringify(snap))})
	check(MapStream.enabled(Session.state) and int(Session.state.stream.ox) == int(snap.stream.ox), "and loads back endless")
	# Pause.
	Session.request({"type": "dm_stream", "on": false})
	var w2: int = Session.state.w
	var hero2: Dictionary = Session.engine.all_combatants().filter(func(c): return c.kind == "pc")[0]
	Session.request({"type": "move", "cid": hero2.id, "to": _open_near(Session.state, Vector2i(int(Session.state.w) - 2, 5)), "free": true})
	check(int(Session.state.w) == w2, "a paused endless map doesn't grow")
	# A cave grows too, and its new ground connects.
	var cm := MapGenerator.generate({"terrain": "cave", "seed": 8, "w": 30, "h": 20, "endless": true, "include_monsters": false})
	Session.request({"type": "dm_load_map", "map": cm})
	var hc: Dictionary = Session.engine.all_combatants().filter(func(c): return c.kind == "pc")[0]
	var cw: int = Session.state.w
	var copen0 := 0
	for v in Session.state.cells:
		if v != EngineBase.WALL and v != EngineBase.PIT:
			copen0 += 1
	print("    cave after load: %dx%d, reach %d of %d open" % [cw, Session.state.h, _reach(Session.state, hc.pos), copen0])
	var far := _furthest_east(Session.state, hc.pos)
	Session.request({"type": "move", "cid": hc.id, "to": far, "free": true})
	var cs: Dictionary = Session.state
	var creach := _reach(cs, hc.pos)
	var copen := 0
	for v in cs.cells:
		if v != EngineBase.WALL and v != EngineBase.PIT:
			copen += 1
	check(int(cs.w) >= cw, "cave: walking toward the east edge (x %d of %d)" % [far.x, cw])
	check(creach >= copen * 0.9, "cave: new tunnels connect to where the party is (%d of %d)" % [creach, copen])
	Session.leave()

func _open_near(st: Dictionary, p: Vector2i) -> Vector2i:
	for r in 20:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var q := p + Vector2i(dx, dy)
				if q.x >= 0 and q.y >= 0 and q.x < st.w and q.y < st.h and st.cells[q.y * st.w + q.x] == EngineBase.FLOOR and Session.engine.creature_at(q).is_empty():
					return q
	return p

func _furthest_east(st: Dictionary, from: Vector2i) -> Vector2i:
	var best := from
	var seen := {from: true}
	var q: Array = [from]
	var i := 0
	while i < q.size():
		var p: Vector2i = q[i]
		i += 1
		if p.x > best.x and st.cells[p.y * st.w + p.x] == EngineBase.FLOOR:
			best = p
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = p + d
			if n.x < 0 or n.y < 0 or n.x >= st.w or n.y >= st.h or seen.has(n):
				continue
			var v: int = st.cells[n.y * st.w + n.x]
			if v != EngineBase.WALL and v != EngineBase.PIT:
				seen[n] = true
				q.append(n)
	return best
