extends Node
## Halfling racial traits (PHB 2014): Small, 25 ft, +2 DEX; Lucky; Brave; Halfling Nimbleness;
## Lightfoot (+1 CHA, Naturally Stealthy) and Stout (+1 CON, Stout Resilience).
## Run: Godot --headless --path . res://tests/halfling_test.tscn   (exit code 1 on failure)

var eng: CombatEngine
var fails := 0
var passes := 0

func check(cond: bool, what: String) -> void:
	if cond:
		passes += 1
	else:
		fails += 1
		print("FAIL: ", what)

func board(pcs: Array, mons: Array) -> Array:
	var st = EngineBase.new_state(24, 14)
	eng = CombatEngine.new(st)
	var out: Array = []
	for row in pcs:
		var c = CombatantFactory.from_character(eng.new_id("p"), row[0], 1)
		c.pos = row[1]
		st.combatants[c.id] = c
		out.append(c)
	for row in mons:
		var m = CombatantFactory.from_monster(eng.new_id("m"), row[0])
		m.team = row[1]
		m.pos = row[2]
		st.combatants[m.id] = m
		out.append(m)
	eng.start_combat()
	return out

func pc(race: String, subrace := "") -> Dictionary:
	var ch = Rules.new_character()
	ch.merge({"name": race.capitalize(), "race": race, "subrace": subrace, "background": "soldier",
		"base_scores": {"str": 10, "dex": 14, "con": 12, "int": 10, "wis": 10, "cha": 10},
		"classes": [{"id": "fighter", "level": 1, "subclass": ""}]}, true)
	return ch

## How many of `n` saves succeed.
func saves(t: Dictionary, ab: String, dc: int, opts: Dictionary, n: int) -> int:
	var ok := 0
	for i in n:
		if eng.saving_throw(t, ab, dc, {}, opts):
			ok += 1
	return ok

func _ready() -> void:
	# --- Derived stats.
	var lf = pc("halfling", "lightfoot")
	var sc = Rules.final_scores(lf)
	check(int(sc.dex) == 16 and int(sc.cha) == 11, "Lightfoot: +2 DEX, +1 CHA")
	var stout = pc("halfling", "stout")
	sc = Rules.final_scores(stout)
	check(int(sc.dex) == 16 and int(sc.con) == 13, "Stout: +2 DEX, +1 CON")
	var cs = board([[lf, Vector2i(2, 2)], [stout, Vector2i(2, 6)], [pc("human"), Vector2i(2, 10)]], [])
	var h: Dictionary = cs[0]
	var s: Dictionary = cs[1]
	var hu: Dictionary = cs[2]
	check(h.size == "small" and eng.size_rank(h) < eng.size_rank(hu), "halflings are Small")
	check(int(h.speed) == 25, "halfling speed 25 ft (got %d)" % int(h.speed))
	for tag in ["halfling_lucky", "brave", "halfling_nimbleness", "naturally_stealthy"]:
		check(h.tags.has(tag), "a Lightfoot halfling has %s" % tag)
	check(s.tags.has("dwarven_resilience") and not h.tags.has("dwarven_resilience"), "only the Stout halfling has Stout Resilience")
	check("poison" in s.resist and not "poison" in h.resist, "Stout halflings resist poison")

	# --- Lucky: a natural 1 is rerolled on attacks, checks and saves.
	var ones := 0
	var ones_plain := 0
	for i in 2000:
		if int(Dice.roll_d20(0, true).roll) == 1: ones += 1
		if int(Dice.roll_d20(0, false).roll) == 1: ones_plain += 1
	check(ones < 30 and ones_plain > 60, "Lucky turns most natural 1s into rerolls (%d vs %d in 2000)" % [ones, ones_plain])
	# Ability checks (grapple/shove contests, escapes): count totals that can only come from a natural 1.
	var b: int = eng._escape_bonus(h, "dex")
	var b2: int = eng._escape_bonus(hu, "dex")
	ones = 0
	ones_plain = 0
	for i in 2000:
		if int(eng.skill_check(h, "dex").total) == 1 + b: ones += 1
		if int(eng.skill_check(hu, "dex").total) == 1 + b2: ones_plain += 1
	check(ones < 30 and ones_plain > 60, "Lucky applies to contested checks (%d vs %d natural 1s)" % [ones, ones_plain])

	# --- Brave: advantage on saves against being frightened (WIS +0 for both, DC 15).
	var brave_ok := saves(h, "wis", 15, {"cond": "frightened"}, 1000)
	var plain_ok := saves(hu, "wis", 15, {"cond": "frightened"}, 1000)
	check(brave_ok > plain_ok + 120, "Brave gives advantage against fear (%d vs %d of 1000)" % [brave_ok, plain_ok])
	var other := saves(h, "wis", 15, {"cond": "charmed"}, 1000)
	check(other < brave_ok - 120, "Brave doesn't help against charm (%d)" % other)

	# --- Stout Resilience: advantage on saves against poison, resistance to poison damage.
	var con_s: int = int(s.save_bonus.get("con", 0))
	var con_h: int = int(h.save_bonus.get("con", 0))
	check(con_s == con_h + 1 or con_s == con_h, "comparable CON saves")
	var st_ok := saves(s, "con", 15, {"cond": "poisoned"}, 1000)
	var lf_ok := saves(h, "con", 15, {"cond": "poisoned"}, 1000)
	check(st_ok > lf_ok + 120, "Stout Resilience: advantage against being poisoned (%d vs %d)" % [st_ok, lf_ok])
	st_ok = saves(s, "con", 15, {"dmg_type": "poison"}, 1000)
	check(st_ok > lf_ok + 120, "Stout Resilience: advantage against poison damage saves (%d)" % st_ok)
	s.hp = s.max_hp
	var taken: int = eng.apply_damage(s, [{"amount": 6, "type": "poison"}], {})
	check(taken == 3, "Stout halflings take half poison damage (took %d of 6)" % taken)
	# A monster's poison breath tells the save it's against poison.
	check(eng._first_dmg_type([{"dice": "2d6", "type": "poison"}]) == "poison", "poison saves are recognised from the damage type")

	# --- Halfling Nimbleness: move through the space of any creature larger than you.
	# Ogre (Large, 2x2) at (6,2)-(7,3); the halfling stands at (5,2), the human at (5,10) by an ogre at (6,10).
	cs = board([[pc("halfling", "lightfoot"), Vector2i(5, 2)], [pc("human"), Vector2i(5, 10)]],
		[["ogre", "enemy", Vector2i(6, 2)], ["ogre", "enemy", Vector2i(6, 10)], ["goblin", "enemy", Vector2i(5, 6)]])
	h = cs[0]
	hu = cs[1]
	var ogre: Dictionary = cs[2]
	var gob: Dictionary = cs[4]
	check(eng.size_rank(ogre) == eng.size_rank(h) + 2, "an ogre is two sizes larger than a halfling")
	check(eng._can_stand_path(h, Vector2i(6, 2), false), "a halfling may pass through a hostile ogre's space")
	check(not eng._can_stand_path(hu, Vector2i(6, 10), false), "a human can't pass through a hostile ogre (one size apart)")
	# A hostile Small goblin is the halfling's own size: no passing.
	h.pos = Vector2i(5, 5)
	check(not eng._can_stand_path(h, gob.pos, false), "a halfling can't pass through a hostile creature its own size")
	# A Medium hostile (one size larger) is passable only thanks to Nimbleness.
	var bandit = CombatantFactory.from_monster(eng.new_id("m"), "bandit")
	bandit.team = "enemy"
	bandit.pos = Vector2i(10, 6)
	eng.s.combatants[bandit.id] = bandit
	check(eng._can_stand_path(h, bandit.pos, false), "a halfling may pass through a hostile Medium creature")
	h.tags.erase("halfling_nimbleness")
	check(not eng._can_stand_path(h, bandit.pos, false), "without Nimbleness a Small creature can't pass a hostile Medium one")
	h.tags["halfling_nimbleness"] = true
	# Movement: the halfling walks straight through the ogre (its space is difficult terrain) and
	# can't end its move inside it.
	h.pos = Vector2i(5, 2)
	eng.s.turn = eng.s.order.find(h.id)
	eng.begin_turn(h)
	var reach: Dictionary = eng.reachable(h, 25)
	check(reach.has(Vector2i(6, 2)) and reach[Vector2i(6, 2)].occupied, "the ogre's space is on the halfling's path but not a place to stop")
	check(int(reach[Vector2i(6, 2)].cost) == 10, "a creature's space costs double (got %d)" % int(reach[Vector2i(6, 2)].cost))
	# Wall off the way around so the only route east is through the ogre.
	for y in range(0, 14):
		if y < 2 or y > 3:
			eng.set_cell(Vector2i(6, y), EngineBase.WALL)
			eng.set_cell(Vector2i(7, y), EngineBase.WALL)
	reach = eng.reachable(h, 25)
	check(reach.has(Vector2i(8, 2)) and not reach[Vector2i(8, 2)].occupied, "the halfling reaches the far side of the ogre (25 ft through its space)")
	var p0: Vector2i = h.pos
	check(eng.move(h, Vector2i(8, 2)), "the halfling's move through the ogre succeeds")
	check(h.pos == Vector2i(8, 2) and h.pos != p0, "the halfling ends up behind the ogre")

	print("HALFLING DONE passed=%d failed=%d" % [passes, fails])
	get_tree().quit(1 if fails > 0 else 0)
