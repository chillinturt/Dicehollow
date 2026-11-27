extends Node
## Dice tray: the engine reports attack, save, damage, initiative and contest rolls as "dice" events
## whose numbers match the roll, and the per-player show setting saves and filters.
## Run: Godot --headless --path . res://tests/dice_test.tscn

var errors := 0

func check(ok: bool, what: String) -> void:
	if ok:
		print("  ok   ", what)
	else:
		errors += 1
		print("  FAIL ", what)

func dice_events(eng: EngineBase) -> Array:
	return eng.events.filter(func(e): return e.get("t", "") == "dice")

func faces_ok(e: Dictionary) -> bool:
	for d in e.get("dice", []):
		if int(d.v) < 1 or int(d.v) > int(d.s):
			return false
	return not e.get("dice", []).is_empty()

func _ready() -> void:
	var st = EngineBase.new_state(12, 8)
	var eng = CombatEngine.new(st)
	var p = CombatantFactory.from_character(eng.new_id("p"), CharacterStore.premades()[0], 2)
	p.pos = Vector2i(2, 2)
	st.combatants[p.id] = p
	var g = CombatantFactory.from_monster(eng.new_id("m"), "goblin")
	g.pos = Vector2i(3, 2)
	st.combatants[g.id] = g

	print("== attack")
	var atk: Dictionary = eng.attacks_of(p)[0]
	for adv in [0, 1, -1]:
		eng.events = []
		var r = eng.roll_attack(p, g, atk, {"adv": adv})
		var ev = dice_events(eng)
		check(ev.size() == 1, "one dice event per attack roll (adv %d)" % adv)
		if ev.is_empty():
			continue
		var e: Dictionary = ev[0]
		check(e.cid == p.id and e.tid == g.id and e.kind == "d20", "attack event names roller, target and kind")
		check(faces_ok(e), "attack dice are real d20 faces")
		var kept: Array = e.dice.filter(func(d): return not d.get("off", false))
		check(kept.size() == 1 and int(kept[0].v) == int(r.nat), "the kept die is the natural roll (adv %d)" % adv)
		check(int(e.total) == int(r.total), "event total matches the attack total")
		check(e.result == ("CRIT" if r.crit else ("HIT" if r.hit else "MISS")), "event result matches the hit")

	print("== advantage marks the dropped die")
	var faces = EngineBase.d20_faces({"roll": 17, "rolls": [4, 17]})
	check(faces.size() == 2 and faces[0].off and not faces[1].off, "the lower die is dropped with advantage")
	faces = EngineBase.d20_faces({"roll": 9, "rolls": [9, 9]})
	check(faces.filter(func(d): return d.off).size() == 1, "a tie drops exactly one die")

	print("== save")
	eng.events = []
	var ok = eng.saving_throw(g, "dex", 13, p, {"spell": true})
	var sv = dice_events(eng)
	check(sv.size() == 1 and sv[0].cid == g.id and sv[0].tid == p.id, "a save reports its roller and the source")
	check(not sv.is_empty() and sv[0].result == ("SUCCESS" if ok else "FAIL"), "save result matches")
	check(not sv.is_empty() and faces_ok(sv[0]), "save dice are real d20 faces")

	print("== damage")
	eng.events = []
	var parts = eng.weapon_damage(p, g, atk, {"crit": false, "hit": true}, {})
	var dm = dice_events(eng).filter(func(e): return e.kind == "damage")
	var total := 0
	for x in parts:
		total += int(x.amount)
	check(dm.size() == 1, "weapon damage reports one damage roll")
	if not dm.is_empty():
		var sum := 0
		for d in dm[0].dice:
			sum += int(d.v)
		check(faces_ok(dm[0]), "damage dice are real faces")
		check(int(dm[0].total) == total and sum + int(dm[0].mod) == total, "damage dice + bonus = damage dealt")
	eng.events = []
	parts = eng.weapon_damage(p, g, atk, {"crit": true, "hit": true}, {})
	dm = dice_events(eng).filter(func(e): return e.kind == "damage")
	var normal_dice := 0
	for d in atk.get("damage", []):
		for t in Dice.parse(d.dice):
			if t.has("n"):
				normal_dice += int(t.n)
	check(not dm.is_empty() and dm[0].dice.size() >= normal_dice * 2, "a critical hit shows the doubled dice")

	print("== spell damage")
	eng.events = []
	eng._roll_parts(p, [{"dice": "3d6+2", "type": "fire"}], false, {})
	dm = dice_events(eng)
	check(dm.size() == 1 and dm[0].dice.size() == 3 and int(dm[0].mod) == 2, "spell damage 3d6+2 shows three d6 and +2")

	print("== initiative")
	eng.events = []
	eng.start_combat()
	var ini = dice_events(eng).filter(func(e): return e.kind == "init")
	check(ini.size() == 2, "every creature's initiative is reported (%d)" % ini.size())
	for e in ini:
		check(int(e.total) == int(eng.C(e.cid).init), "initiative total matches %s" % e.cid)

	print("== contest")
	eng.events = []
	var sc = eng.skill_check(p, "str")
	var ce = dice_events(eng)
	check(ce.size() == 1 and int(ce[0].total) == int(sc.total), "an Athletics check reports its total")

	print("== Dice.roll faces")
	var rr = Dice.roll("2d8+1d4+3")
	check(rr.dice.size() == 3 and rr.dice[0].s == 8 and rr.dice[2].s == 4, "Dice.roll lists each die with its sides")
	var sum2 := 3
	for d in rr.dice:
		sum2 += int(d.v)
	check(sum2 == int(rr.total), "the listed faces add up to the total")

	print("== setting")
	var cfg := ConfigFile.new()
	var had := cfg.load(DiceTray.SETTINGS) == OK
	var before = cfg.get_value("dice", "show") if had and cfg.has_section_key("dice", "show") else null
	DiceTray.set_mode("all")
	check(DiceTray.wants(false) and DiceTray.wants(true), "all: shows everyone's rolls")
	DiceTray.set_mode("mine")
	check(DiceTray.wants(true) and not DiceTray.wants(false), "mine: shows only your own rolls")
	DiceTray.set_mode("off")
	check(not DiceTray.wants(true), "off: shows nothing")
	DiceTray._mode = ""
	check(DiceTray.mode() == "off", "the setting is saved and loaded back")
	check(DiceTray.next_mode() == "mine", "the button cycles off -> mine")
	DiceTray.set_mode("bogus")
	check(DiceTray.mode() == "mine", "an unknown setting falls back to mine")
	# Put the player's own setting back.
	cfg = ConfigFile.new()
	cfg.load(DiceTray.SETTINGS)
	if before == null:
		if cfg.has_section_key("dice", "show"):
			cfg.erase_section_key("dice", "show")
	else:
		cfg.set_value("dice", "show", before)
	cfg.save(DiceTray.SETTINGS)
	DiceTray._mode = ""

	print("== tray")
	var tray := DiceTray.new()
	tray.size = Vector2(380, 500)
	add_child(tray)
	for i in 6:
		tray.add_roll({"label": "Test", "dice": [{"s": 20, "v": 12}], "mod": 3, "total": 15, "result": "HIT", "kind": "d20"}, "Aria", Color.SKY_BLUE)
	check(tray.cards.size() == DiceTray.MAX_CARDS, "the tray keeps at most %d cards" % DiceTray.MAX_CARDS)
	tray.clear()
	check(tray.cards.is_empty(), "clear empties the tray")

	print("DICE DONE errors=%d" % errors)
	get_tree().quit(1 if errors > 0 else 0)
