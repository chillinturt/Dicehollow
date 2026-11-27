extends Node
## Headless checks for the encounter map generator: DMG XP math, deterministic layouts, connectivity,
## legal monster placement, filters, applying a map to the table and the generator window.
## Run: Godot --headless --path . res://tests/map_gen_test.tscn   (exit code 1 on failure)

var fails := 0
var passes := 0

func check(cond: bool, what: String) -> void:
	if cond:
		passes += 1
	else:
		fails += 1
		print("FAIL: ", what)

func party(n: int, lvl: int, cls := "fighter") -> Array:
	var out: Array = []
	for i in n:
		out.append({"name": "P%d" % i, "level": lvl, "classes": {cls: lvl}})
	return out

## Every passable cell reachable from the first start point (8-way, walls and pits block).
func reachable(m: Dictionary) -> Dictionary:
	var w: int = m.w
	var seen := {}
	if m.spawns.is_empty():
		return seen
	var start := Vector2i(m.spawns[0][0], m.spawns[0][1])
	var q: Array = [start]
	seen[start] = true
	var i := 0
	while i < q.size():
		var p: Vector2i = q[i]
		i += 1
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var n := p + Vector2i(dx, dy)
				if n.x < 0 or n.y < 0 or n.x >= w or n.y >= m.h or seen.has(n):
					continue
				var v: int = m.cells[n.y * w + n.x]
				if v != EngineBase.WALL and v != EngineBase.PIT:
					seen[n] = true
					q.append(n)
	return seen

func _ready() -> void:
	# --- DMG math.
	check(EncounterBuilder.thresholds(party(4, 1)) == [100, 200, 300, 400], "4 level-1 PCs: thresholds 100/200/300/400")
	check(EncounterBuilder.thresholds(party(5, 5))[2] == 3750, "5 level-5 PCs: hard = 3750")
	check(EncounterBuilder.multiplier(1, 4) == 1.0 and EncounterBuilder.multiplier(2, 4) == 1.5 and EncounterBuilder.multiplier(4, 4) == 2.0, "group multipliers 1/1.5/2")
	check(EncounterBuilder.multiplier(8, 4) == 2.5 and EncounterBuilder.multiplier(15, 4) == 4.0, "group multipliers 2.5/4")
	check(EncounterBuilder.multiplier(1, 2) == 1.5 and EncounterBuilder.multiplier(1, 6) == 0.5 and EncounterBuilder.multiplier(2, 6) == 1.0, "small party steps up, large party steps down")
	check(EncounterBuilder.multiplier(1, 7) == 0.5, "a single monster against 7 PCs: ×0.5")
	var r := EncounterBuilder.rate([{"mid": "goblin", "count": 4}], 4)
	check(r.raw == 200 and r.adjusted == 400, "4 goblins: 200 raw, 400 adjusted (%s)" % str(r))
	check(EncounterBuilder.difficulty_of(400, party(4, 1)) == "deadly", "400 adjusted XP is deadly for 4 level-1s")
	var healers := EncounterBuilder.party_profile([{"level": 3, "classes": {"wizard": 3}}, {"level": 3, "classes": {"sorcerer": 3}}, {"level": 3, "classes": {"fighter": 3}}])
	check(healers.prefer == "horde" and healers.scale < 1.0, "AoE casters and no healer: horde, budget lowered")
	var martial := EncounterBuilder.party_profile(party(4, 3, "fighter") + [{"level": 3, "classes": {"cleric": 3}}])
	check(martial.prefer == "boss" and martial.scale == 1.0, "martial party with a cleric: boss, full budget (%s)" % str(martial))

	# --- Encounters land in the requested band.
	for di in 4:
		var rng := RandomNumberGenerator.new()
		rng.seed = 42 + di
		var enc := EncounterBuilder.build({"party": party(4, 5, "cleric"), "difficulty": di, "terrain": "dungeon", "composition": "balanced"}, rng)
		check(enc.adjusted >= enc.lo and enc.adjusted <= enc.hi, "difficulty %d: adjusted %d within %d–%d" % [di, enc.adjusted, enc.lo, enc.hi])
	var rng2 := RandomNumberGenerator.new()
	var solo := EncounterBuilder.build({"party": party(4, 8, "cleric"), "difficulty": 2, "composition": "solo"}, rng2)
	check(solo.count == 1, "solo composition: one monster")
	var horde := EncounterBuilder.build({"party": party(4, 3, "cleric"), "difficulty": 1, "composition": "horde", "max_monsters": 10}, rng2)
	check(horde.count >= 5 and horde.count <= 10, "horde: 5–10 monsters (%d)" % horde.count)
	var und := EncounterBuilder.build({"party": party(4, 4, "cleric"), "difficulty": 2, "types": ["undead"], "terrain": "graveyard"}, rng2)
	check(und.picks.size() > 0 and und.picks.all(func(p): return Data.monster(p.mid).type == "undead"), "type filter: only undead")
	var swamp := EncounterBuilder.build({"party": party(4, 2, "cleric"), "difficulty": 1, "terrain": "swamp", "match_habitat": true}, rng2)
	check(swamp.picks.all(func(p): return "swamp" in EncounterBuilder.habitats_of(Data.monster(p.mid))), "habitat filter: swamp monsters only")

	# --- Maps: every terrain builds, is reachable and places legal monsters.
	for terrain in MapGenerator.TERRAINS:
		for sd in [1, 77]:
			var st := {"terrain": terrain, "seed": sd, "w": 30, "h": 20, "party": party(4, 4, "cleric"), "difficulty": 2, "hidden": 0.25,
				"river": terrain == "forest"}
			var m := MapGenerator.generate(st)
			var tag := "%s/%d" % [terrain, sd]
			check(m.cells.size() == m.w * m.h, tag + ": cell count")
			check(m.spawns.size() >= 6, tag + ": at least 6 start points (%d)" % m.spawns.size())
			var reach := reachable(m)
			var floor_n := 0
			var all_reach := true
			for y in m.h:
				for x in m.w:
					var v: int = m.cells[y * m.w + x]
					if v != EngineBase.WALL and v != EngineBase.PIT:
						floor_n += 1
						if not reach.has(Vector2i(x, y)):
							all_reach = false
			check(all_reach, tag + ": every open cell is reachable from the start")
			check(floor_n >= m.w * m.h * 0.25, tag + ": at least a quarter of the map is open (%d)" % floor_n)
			check(m.monsters.size() > 0, tag + ": monsters placed")
			var occ := {}
			var legal := true
			for mon in m.monsters:
				var md: Dictionary = Data.monster(mon.mid)
				var sz: int = CombatantFactory.SIZE_CELLS.get(md.size, 1)
				for dx in sz:
					for dy in sz:
						var p := Vector2i(mon.x + dx, mon.y + dy)
						var inb: bool = p.x < m.w and p.y < m.h
						var v: int = m.cells[p.y * m.w + p.x] if inb else EngineBase.WALL
						if not inb or v == EngineBase.WALL or v == EngineBase.PIT or occ.has(p) or not reach.has(p):
							legal = false
						if v == EngineBase.WATER and int(md.get("swim", 0)) == 0 and int(md.get("fly", 0)) == 0:
							legal = false
						occ[p] = true
			check(legal, tag + ": monsters on open, reachable, unshared cells")
	var a := MapGenerator.generate({"terrain": "cave", "seed": 5, "party": party(3, 2)})
	var b := MapGenerator.generate({"terrain": "cave", "seed": 5, "party": party(3, 2)})
	var c := MapGenerator.generate({"terrain": "cave", "seed": 6, "party": party(3, 2)})
	check(a.cells == b.cells and str(a.monsters) == str(b.monsters), "same seed and settings: same map")
	check(a.cells != c.cells, "different seed: different map")
	var e2 := MapGenerator.generate({"terrain": "cave", "seed": 5, "party": party(3, 2), "enc_seed": 3})
	check(e2.cells == a.cells, "rerolling monsters keeps the layout")
	var bare := MapGenerator.generate({"terrain": "town", "seed": 9, "include_monsters": false, "w": 200, "h": 3})
	check(bare.monsters.is_empty() and bare.w == 80 and bare.h == 8, "no monsters; size clamped to 80×8")
	var hid := MapGenerator.generate({"terrain": "dungeon", "seed": 3, "party": party(4, 5), "hidden": 1.0})
	check(hid.monsters.all(func(mm): return mm.get("hidden", false)), "hidden 100%: every monster starts hidden")

	# --- Applying to the table.
	Session.start_offline("DM", 20, 12)
	Session.auto_monsters = false
	var heroes: Array = CharacterStore.premades()
	var ids: Array = []
	for i in 3:
		ids.append(Session.add_character(heroes[i], 1, Vector2i(1 + i, 1)))
	var gm := MapGenerator.generate({"terrain": "forest", "seed": 11, "party": party(3, 3), "difficulty": 1, "hidden": 0.0})
	gm.erase("report")
	Session.request({"type": "dm_load_map", "map": gm})
	var mons := Session.engine.all_combatants().filter(func(x): return x.kind == "monster")
	check(mons.size() == gm.monsters.size(), "all generated monsters are on the table (%d/%d)" % [mons.size(), gm.monsters.size()])
	check(Session.state.w == gm.w and Session.state.theme == "forest", "map size and theme applied")
	var on_spawn := 0
	for id in ids:
		var pc: Dictionary = Session.engine.C(id)
		if [pc.pos.x, pc.pos.y] in gm.spawns:
			on_spawn += 1
	check(on_spawn == 3, "the characters moved to the start points")

	# --- The window, inside a DM battle screen.
	var scene = load("res://scenes/battle.tscn").instantiate()
	add_child(scene)
	await get_tree().process_frame
	scene.selected_cid = ids[0]
	scene.selected_ids = [ids[1]]
	scene._open_map_generator()
	await get_tree().process_frame
	var gen: MapGeneratorPanel = null
	for ch in scene.ui.get_children():
		if ch is MapGeneratorPanel:
			gen = ch
	check(gen != null, "the generator window opens from the Map tab")
	if gen:
		check(gen.party_mode == "players" and gen.party().size() == 2, "selected characters become the party (%d)" % gen.party().size())
		check(gen.party()[0].level >= 1 and not gen.party()[0].classes.is_empty(), "party levels and classes come from the characters")
		check(not gen.result.is_empty() and gen.preview.map == gen.result, "a preview is generated on open")
		gen._set_terrain("swamp")
		await get_tree().process_frame
		check(gen.settings.terrain == "swamp" and is_equal_approx(float(gen.settings.water), 0.45), "picking a terrain loads its environment defaults")
		check(gen.result.theme == "swamp", "preview regenerated for the new terrain")
		gen.party_mode = "custom"
		gen.regenerate()
		check(gen.party().size() == 4, "custom party: 4 members by default")
		var nm: String = gen.result.name
		gen._apply()
		await get_tree().process_frame
		check(Session.state.name == nm and Session.state.theme == "swamp", "Apply loads the generated map")
	scene.queue_free()
	await get_tree().process_frame

	print("MAP GEN DONE passed=%d failed=%d" % [passes, fails])
	get_tree().quit(1 if fails > 0 else 0)
