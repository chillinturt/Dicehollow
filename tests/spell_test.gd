extends Node
## Headless checks for spell and effect mechanics.
## Run: Godot --headless --path . res://tests/spell_test.tscn  (exit code 1 on failure)

var eng: CombatEngine
var fails := 0
var passes := 0

func check(cond: bool, what: String) -> void:
	if cond:
		passes += 1
	else:
		fails += 1
		print("FAIL: ", what)

## Fresh 20x10 board with the given monsters [[id, team, cell], ...]; returns their combatants.
func board(spec: Array) -> Array:
	var st = EngineBase.new_state(20, 10)
	eng = CombatEngine.new(st)
	var out: Array = []
	for row in spec:
		var m = CombatantFactory.from_monster(eng.new_id("m"), row[0])
		m.team = row[1]
		m.pos = row[2]
		st.combatants[m.id] = m
		out.append(m)
	eng.start_combat()
	return out

func give_turn(c: Dictionary) -> void:
	eng.s.turn = eng.s.order.find(c.id)
	eng.begin_turn(c)

## Teach `c` a spell and give it plenty of slots.
func teach(c: Dictionary, sid: String) -> void:
	if c.casting.is_empty():
		c.casting.append({"class": "wizard", "ability": "int", "mod": 3, "dc": 15, "attack": 7, "spells": [], "at_will": []})
	if not sid in c.casting[0].spells:
		c.casting[0].spells.append(sid)
	c.slots_max = [4, 3, 3, 3, 3, 2, 1, 1, 1]
	c.slots_used = [0, 0, 0, 0, 0, 0, 0, 0, 0]

func cast(c: Dictionary, sid: String, params: Dictionary) -> bool:
	teach(c, sid)
	give_turn(c)
	return eng.execute(c.id, "sp:" + sid, params)

## Make every save `t` rolls fail (or succeed).
func rig_saves(t: Dictionary, fail: bool) -> void:
	for ab in ["str", "dex", "con", "int", "wis", "cha"]:
		t.save_bonus[ab] = -100 if fail else 100
	t.legendary_res = 0

func _ready() -> void:
	# --- True Strike survives to the caster's next turn.
	var cs = board([["mage", "party", Vector2i(2, 2)], ["ogre", "enemy", Vector2i(6, 2)]])
	var mage: Dictionary = cs[0]
	var ogre: Dictionary = cs[1]
	cast(mage, "true_strike", {"targets": [ogre.id]})
	eng.end_turn()
	check(eng.has_tag(ogre, "true_strike"), "True Strike still on the target after the caster's turn ends")
	check(eng.attack_advantage(mage, ogre, false) >= 0 and eng.has_tag(ogre, "true_strike"), "True Strike grants advantage on the next turn")

	# --- Hex adds to spell attacks; Hunter's Mark doesn't; Bestow Curse adds to spells too.
	cs = board([["mage", "party", Vector2i(2, 2)], ["ogre", "enemy", Vector2i(6, 2)]])
	mage = cs[0]
	ogre = cs[1]
	eng.add_effect(ogre, {"name": "Hexed", "tag": "hex", "spell": "hex", "src": mage.id, "mods": {"vulnerable_to_caster": {"dice": "1d6", "type": "necrotic"}}, "rounds": 10, "tick_cid": mage.id})
	check(eng._caster_riders(mage, ogre, "spell_attack", false).size() == 1, "Hex adds damage to spell attacks (Eldritch Blast)")
	check(eng._caster_riders(mage, ogre, "spell", false).is_empty(), "Hex doesn't add to saving-throw spells")
	ogre.effects.clear()
	eng.add_effect(ogre, {"name": "Hunter's Mark", "tag": "hunters_mark", "spell": "hunters_mark", "src": mage.id, "mods": {"vulnerable_to_caster": {"dice": "1d6", "type": "piercing"}}, "rounds": 10, "tick_cid": mage.id})
	check(eng._caster_riders(mage, ogre, "spell_attack", false).is_empty(), "Hunter's Mark only rides on weapon attacks")
	check(eng._caster_riders(mage, ogre, "weapon", false).size() == 1, "Hunter's Mark rides on weapon attacks")
	ogre.effects.clear()
	rig_saves(ogre, true)
	ogre.pos = Vector2i(3, 2)
	cast(mage, "bestow_curse", {"targets": [ogre.id], "slot": 3})
	check(eng._caster_riders(mage, ogre, "spell", false).size() == 1, "Bestow Curse adds 1d8 necrotic to the caster's spells")

	# --- Zones trigger when a creature walks in (Moonbeam), not only at the start of its turn.
	cs = board([["mage", "party", Vector2i(2, 2)], ["orc", "enemy", Vector2i(10, 2)]])
	mage = cs[0]
	var orc: Dictionary = cs[1]
	rig_saves(orc, true)
	orc.max_hp = 500
	orc.hp = 500
	cast(mage, "moonbeam", {"cell": Vector2i(7, 2), "slot": 2})
	check(eng.s.zones.size() == 1, "Moonbeam leaves a zone")
	give_turn(orc)
	eng.move(orc, Vector2i(7, 2))
	check(orc.hp < 500, "walking into Moonbeam hurts (hp %d)" % orc.hp)
	var hp1: int = orc.hp
	eng.move(orc, Vector2i(9, 2))
	give_turn(orc)  # new turn, but outside now
	check(orc.hp == hp1, "no damage starting a turn outside the zone")

	# --- Spike Growth hurts per 5 ft moved inside it, and not at the start of a turn.
	cs = board([["mage", "party", Vector2i(1, 1)], ["orc", "enemy", Vector2i(10, 5)]])
	mage = cs[0]
	orc = cs[1]
	orc.max_hp = 500
	orc.hp = 500
	cast(mage, "spike_growth", {"cell": Vector2i(10, 5), "slot": 2})
	give_turn(orc)
	check(orc.hp == 500, "Spike Growth doesn't hurt a creature just for starting its turn there")
	eng.move(orc, Vector2i(13, 5))
	check(orc.hp < 500 and orc.hp <= 500 - 3, "Spike Growth hurts for each 5 ft moved (hp %d)" % orc.hp)

	# --- Guardian of Faith ignores the caster's allies.
	cs = board([["priest", "party", Vector2i(1, 1)], ["orc", "party", Vector2i(10, 5)], ["goblin", "enemy", Vector2i(18, 8)]])
	var priest: Dictionary = cs[0]
	var ally: Dictionary = cs[1]
	cast(priest, "guardian_of_faith", {"cell": Vector2i(10, 5), "slot": 4})
	var ally_hp: int = ally.hp
	give_turn(ally)
	check(ally.hp == ally_hp, "Guardian of Faith doesn't hurt allies")

	# --- Aid raises max HP once, and a long rest takes it away again.
	cs = board([["priest", "party", Vector2i(1, 1)], ["orc", "party", Vector2i(2, 1)], ["goblin", "enemy", Vector2i(18, 8)]])
	priest = cs[0]
	ally = cs[1]
	var base_max: int = ally.max_hp
	cast(priest, "aid", {"targets": [ally.id], "slot": 2})
	cast(priest, "aid", {"targets": [ally.id], "slot": 2})
	check(ally.max_hp == base_max + 5, "Aid doesn't stack (max %d, base %d)" % [ally.max_hp, base_max])
	eng.end_combat()
	eng.long_rest()
	check(ally.max_hp == base_max, "long rest removes Aid's max HP bonus")

	# --- Rope Trick: an entrance that stays open. Creatures climb in and drop out; nothing else crosses.
	cs = board([["mage", "party", Vector2i(5, 5)], ["orc", "party", Vector2i(5, 6)], ["goblin", "enemy", Vector2i(9, 5)], ["orc", "party", Vector2i(12, 5)]])
	mage = cs[0]
	ally = cs[1]
	var rt_gob: Dictionary = cs[2]
	var far_ally: Dictionary = cs[3]
	rt_gob.max_hp = 500
	rt_gob.hp = 500
	check(cast(mage, "rope_trick", {"targets": [mage.id], "slot": 2}), "Rope Trick can be cast")
	check(eng.ropes().size() == 1 and eng.ropes()[0].pos == Vector2i(5, 5), "the rope hangs over the caster's cell")
	check(not eng.in_rope(mage), "casting doesn't put the caster inside: climbing takes movement")
	var moved0: int = int(mage.turn.moved)
	check(eng.execute(mage.id, "rope_in", {}) and eng.in_rope(mage), "the caster climbs the rope")
	check(int(mage.turn.moved) == moved0 + 10, "climbing in costs 10 ft of movement (spent %d)" % (int(mage.turn.moved) - moved0))
	give_turn(ally)
	check(eng.execute(ally.id, "rope_in", {}) and eng.in_rope(ally), "an ally within 5 ft climbs in on its own turn")
	give_turn(far_ally)
	check(not eng.find_action(far_ally, "rope_in").enabled, "an ally out of reach of the rope can't climb it")
	give_turn(rt_gob)
	check(eng.find_action(rt_gob, "rope_in").is_empty(), "enemies can't follow (the rope is pulled up)")
	check(not eng.los(rt_gob, mage) and not mage in eng.enemies_of(rt_gob), "creatures outside can't see or target those in the Rope Trick")
	check(eng.los(mage, ally), "creatures inside the Rope Trick can still see each other")
	check(eng.creature_at(Vector2i(5, 5)).is_empty(), "creatures inside take up no room on the map")
	check(eng.creatures_in_cells([Vector2i(5, 5), Vector2i(5, 6), rt_gob.pos]).size() == 1, "areas outside don't reach into the Rope Trick")
	teach(mage, "fire_bolt")
	give_turn(mage)
	check(not eng.execute(mage.id, "sp:fire_bolt", {"targets": [rt_gob.id]}), "can't attack out of the Rope Trick")
	# Pop out, shoot, climb back in: all in one turn.
	var gob_hp: int = rt_gob.hp
	check(eng.execute(mage.id, "rope_out", {}) and not eng.in_rope(mage) and mage.pos == Vector2i(5, 5), "dropping down lands under the rope")
	check(int(mage.turn.moved) == 0, "dropping down costs no movement")
	check(eng.los(rt_gob, mage) and mage in eng.enemies_of(rt_gob), "outside, the caster can be seen and targeted again")
	teach(mage, "magic_missile")
	check(eng.execute(mage.id, "sp:magic_missile", {"targets": [rt_gob.id], "slot": 1}) and rt_gob.hp < gob_hp, "outside, the caster can attack")
	check(eng.execute(mage.id, "rope_in", {}) and eng.in_rope(mage), "and climb back in on the same turn")
	check(not eng.los(rt_gob, mage), "back inside, the caster is out of sight again")
	# Moving also drops out; the entrance stays open behind.
	give_turn(ally)
	eng.move(ally, Vector2i(4, 7))
	check(not eng.in_rope(ally) and ally.pos == Vector2i(4, 7) and eng.los(rt_gob, ally), "moving drops out of the Rope Trick and walks on")
	check(eng.in_rope(mage), "the others stay inside")
	check(eng.ropes().size() == 1 and eng.find_action(ally, "rope_in").enabled == false, "the rope is still there (too far to climb now)")
	# Someone standing under the rope: a dropper lands beside them.
	ally.pos = Vector2i(5, 5)
	give_turn(mage)
	eng.execute(mage.id, "rope_out", {})
	check(not eng.in_rope(mage) and mage.pos != Vector2i(5, 5) and eng.cheb(mage.pos, Vector2i(5, 5)) == 1, "with the cell under the rope taken, a dropper lands next to it")
	# Climbing away from an enemy in reach provokes an opportunity attack.
	rt_gob.pos = mage.pos + Vector2i(mage.pos.x - 5, mage.pos.y - 5)
	if not eng.in_bounds(rt_gob.pos) or not eng.creature_at(rt_gob.pos, rt_gob.id).is_empty():
		rt_gob.pos = eng._free_cell_near(mage.pos)
	rt_gob.turn.reaction = true
	give_turn(mage)
	mage.max_hp = 500
	mage.hp = 500
	eng.execute(mage.id, "rope_in", {})
	check(not rt_gob.turn.reaction, "climbing out of an enemy's reach provokes an opportunity attack")
	check(eng.in_rope(mage), "and the climber still gets in")
	eng.end_combat()
	check(eng.in_rope(mage) and eng.ropes().size() == 1, "Rope Trick outlasts the fight (1 hour)")
	eng.short_rest()
	check(not eng.in_rope(mage) and eng.ropes().is_empty(), "the spell ends within a rest and everyone inside drops out")
	# The spell running out mid-fight ejects whoever is inside.
	cs = board([["mage", "party", Vector2i(5, 5)], ["goblin", "enemy", Vector2i(15, 5)]])
	mage = cs[0]
	cast(mage, "rope_trick", {"targets": [mage.id], "slot": 2})
	eng.execute(mage.id, "rope_in", {})
	eng.ropes()[0].rounds = 1
	give_turn(mage)
	check(not eng.in_rope(mage) and eng.ropes().is_empty() and mage.pos == Vector2i(5, 5), "when the duration runs out the space empties onto the ground")

	# --- Effects timed on a creature's turns still expire after it dies.
	cs = board([["orc", "party", Vector2i(2, 2)], ["goblin", "enemy", Vector2i(3, 2)], ["goblin", "enemy", Vector2i(12, 8)]])
	orc = cs[0]
	var gob: Dictionary = cs[1]
	eng.add_effect(orc, {"name": "Poisoned", "cond": "poisoned", "src": gob.id, "rounds": 1, "tick_cid": gob.id, "tick_on": "start"})
	gob.dead = true
	for i in eng.s.order.size() + 1:
		eng.end_turn()
	check(not eng.has_cond(orc, "poisoned"), "poison from a dead goblin wears off")
	# ...and when the DM has removed it from the initiative order.
	eng.add_effect(orc, {"name": "Poisoned", "cond": "poisoned", "src": gob.id, "rounds": 1, "tick_cid": gob.id, "tick_on": "start"})
	eng.s.order.erase(gob.id)
	for i in eng.s.order.size() + 1:
		eng.end_turn()
	check(not eng.has_cond(orc, "poisoned"), "poison from a removed creature wears off")
	eng.add_effect(orc, {"name": "Held", "cond": "paralyzed", "src": "x", "rounds": 10, "tick_cid": "x"})
	eng.end_combat()
	check(not eng.has_cond(orc, "paralyzed"), "combat-length conditions end with combat")

	# --- Prone from a spell lasts until the creature stands, not until the caster's next turn.
	cs = board([["mage", "party", Vector2i(2, 2)], ["orc", "enemy", Vector2i(8, 2)]])
	mage = cs[0]
	orc = cs[1]
	rig_saves(orc, true)
	cast(mage, "command", {"targets": [orc.id], "slot": 1, "opts": {"command": "grovel"}})
	check(not eng.has_cond(orc, "prone") and eng.has_tag(orc, "commanded"), "Command takes hold on the target's next turn, not at once")
	give_turn(orc)
	check(eng.has_cond(orc, "prone") and int(orc.turn.action) == 0 and eng.move_left(orc) == 0, "Grovel: the target falls prone and its turn ends")
	check(not eng.has_tag(orc, "commanded"), "the command is spent once obeyed")
	give_turn(mage)
	check(eng.has_cond(orc, "prone"), "prone doesn't time out at the caster's next turn")

	# --- Command's other words.
	cs = board([["mage", "party", Vector2i(2, 2)], ["orc", "enemy", Vector2i(8, 2)]])
	mage = cs[0]
	orc = cs[1]
	rig_saves(orc, true)
	cast(mage, "command", {"targets": [orc.id], "slot": 1, "opts": {"command": "approach"}})
	give_turn(orc)
	check(eng.dist(mage, orc) <= 5 and int(orc.turn.action) == 0, "Approach: the target walks up to the caster and its turn ends (%d ft away)" % eng.dist(mage, orc))
	orc.pos = Vector2i(5, 2)
	cast(mage, "command", {"targets": [orc.id], "slot": 1, "opts": {"command": "flee"}})
	give_turn(orc)
	check(eng.dist(mage, orc) > 15 and int(orc.turn.action) == 0, "Flee: the target runs from the caster (%d ft away)" % eng.dist(mage, orc))
	orc.pos = Vector2i(6, 2)
	var here: Vector2i = orc.pos
	cast(mage, "command", {"targets": [orc.id], "slot": 1, "opts": {"command": "halt"}})
	give_turn(orc)
	check(orc.pos == here and eng.move_left(orc) == 0 and int(orc.turn.action) == 0 and not eng.has_cond(orc, "prone"), "Halt: the target neither moves nor acts, and doesn't fall prone")
	var zcs = board([["mage", "party", Vector2i(2, 2)], ["zombie", "enemy", Vector2i(4, 2)]])
	rig_saves(zcs[1], true)
	cast(zcs[0], "command", {"targets": [zcs[1].id], "slot": 1, "opts": {"command": "grovel"}})
	check(not eng.has_tag(zcs[1], "commanded"), "Command has no effect on undead")

	# --- Self-range spells that pick a creature don't have unlimited range.
	cs = board([["mage", "party", Vector2i(1, 1)], ["orc", "enemy", Vector2i(18, 8)]])
	mage = cs[0]
	orc = cs[1]
	teach(mage, "ensnaring_strike")
	give_turn(mage)
	var es = eng.find_action(mage, "sp:ensnaring_strike")
	check(int(es.range) > 0 and int(es.range) < 85, "Ensnaring Strike gets a real range (%d)" % int(es.range))
	check(not eng.execute(mage.id, "sp:ensnaring_strike", {"targets": [orc.id], "slot": 1}) or int(es.range) >= eng.dist(mage, orc), "can't Ensnaring Strike across the map")

	# --- Death Ward, Barkskin, Freedom of Movement, Beacon of Hope, Fly.
	cs = board([["priest", "party", Vector2i(1, 1)], ["orc", "party", Vector2i(2, 1)], ["goblin", "enemy", Vector2i(18, 8)]])
	priest = cs[0]
	ally = cs[1]
	cast(priest, "death_ward", {"targets": [ally.id], "slot": 4})
	eng.apply_damage(ally, [{"amount": ally.hp + 5, "type": "fire"}], {})
	check(ally.hp == 1 and not ally.dead, "Death Ward drops the target to 1 HP instead of 0")
	cast(priest, "barkskin", {"targets": [ally.id], "slot": 2})
	ally.ac = 10
	check(eng.eff_ac(ally) == 16, "Barkskin sets AC 16 minimum (got %d)" % eng.eff_ac(ally))
	cast(priest, "freedom_of_movement", {"targets": [ally.id], "slot": 4})
	eng.add_effect(ally, {"name": "Webbed", "cond": "restrained", "src": "x", "rounds": 10, "tick_cid": "x"})
	check(not eng.has_cond(ally, "restrained"), "Freedom of Movement prevents restraint")
	cast(priest, "fly", {"targets": [ally.id], "slot": 3})
	check(eng.eff_speed(ally) >= 60, "Fly gives a 60 ft flying speed (got %d)" % eng.eff_speed(ally))
	eng.end_concentration(priest, true)
	cast(priest, "beacon_of_hope", {"targets": [ally.id], "slot": 3})
	ally.hp = 1
	cast(priest, "cure_wounds", {"targets": [ally.id], "slot": 1})
	check(ally.hp == 1 + 8 + int(priest.casting[0].mod) or ally.hp == ally.max_hp, "Beacon of Hope maximizes healing (hp %d)" % ally.hp)

	# --- Steel Wind Strike attacks every chosen target.
	cs = board([["mage", "party", Vector2i(5, 5)], ["goblin", "enemy", Vector2i(6, 5)], ["goblin", "enemy", Vector2i(6, 6)], ["goblin", "enemy", Vector2i(4, 4)]])
	mage = cs[0]
	for g in cs.slice(1):
		g.ac = -100
		g.max_hp = 999
		g.hp = 999
	# A natural 1 always misses, so allow a few castings before calling a target missed.
	var hit_all = false
	for attempt in 3:
		mage.pos = Vector2i(5, 5)
		cast(mage, "steel_wind_strike", {"targets": [cs[1].id, cs[2].id, cs[3].id], "slot": 5})
		hit_all = true
		for g in cs.slice(1):
			hit_all = hit_all and g.hp < 999
		if hit_all:
			break
	check(hit_all, "Steel Wind Strike hits each target")

	# --- Weapon-only riders don't fire from a Spiritual Weapon hit.
	cs = board([["priest", "party", Vector2i(2, 2)], ["ogre", "enemy", Vector2i(6, 2)]])
	priest = cs[0]
	ogre = cs[1]
	eng.add_effect(priest, {"name": "Searing Smite", "spell": "searing_smite", "src": priest.id, "mods": {"extra_damage": {"dice": "1d6", "type": "fire"}}, "rounds": 10, "tick_cid": priest.id})
	var sw = {"id": "sw", "name": "Spiritual Weapon", "melee": true, "to_hit": 5, "damage": [{"dice": "1d8", "type": "force"}], "reach": 60, "magic": true, "spell_attack": true}
	var parts = eng.weapon_damage(priest, ogre, sw, {"crit": false}, {})
	check(parts.size() == 1 and priest.effects.size() == 1, "Searing Smite isn't spent by a Spiritual Weapon hit")

	# --- Guiding Bolt's advantage is spent by the next attack.
	cs = board([["orc", "party", Vector2i(2, 2)], ["ogre", "enemy", Vector2i(3, 2)]])
	orc = cs[0]
	ogre = cs[1]
	var gb = Data.spell("guiding_bolt")
	eng.add_effect(ogre, eng._make_effect(orc, gb, gb.combat.effect, 10, ""))
	give_turn(orc)
	eng.roll_attack(orc, ogre, orc.attacks[0], {"melee": true})
	check(eng.mod_list(ogre, "grants_advantage").is_empty(), "Guiding Bolt's advantage is used up by one attack")

	# --- Zones with a duration fade; concentration zones take the concentration with them.
	cs = board([["mage", "party", Vector2i(1, 1)], ["orc", "enemy", Vector2i(18, 8)]])
	mage = cs[0]
	cast(mage, "cloud_of_daggers", {"cell": Vector2i(5, 5), "slot": 2})
	for i in 11:
		give_turn(mage)
	check(eng.s.zones.is_empty() and mage.conc.is_empty(), "Cloud of Daggers fades after 1 minute")

	# --- Word of Radiance only hits enemies.
	cs = board([["priest", "party", Vector2i(5, 5)], ["orc", "party", Vector2i(6, 5)], ["goblin", "enemy", Vector2i(4, 5)]])
	priest = cs[0]
	ally = cs[1]
	rig_saves(ally, true)
	ally_hp = ally.hp
	cast(priest, "word_of_radiance", {"cell": priest.pos})
	check(ally.hp == ally_hp, "Word of Radiance spares allies")

	# --- Sweep: cast every automated spell in a live battle and play out two rounds.
	# Script errors show up in the output; the check catches spells that refuse to cast.
	var refused: Array = []
	for sp in Data.spells.values():
		var cb = sp.get("combat", null)
		if not cb is Dictionary or sp.casting_time in ["reaction", "minute", "hour"]:
			continue
		cs = board([["mage", "party", Vector2i(5, 5)], ["orc", "party", Vector2i(5, 6)], ["goblin", "enemy", Vector2i(6, 5)], ["ogre", "enemy", Vector2i(8, 6)]])
		mage = cs[0]
		teach(mage, sp.id)
		give_turn(mage)
		var a = eng.find_action(mage, "sp:" + sp.id)
		var tid: String = cs[2].id
		match a.get("target", "enemy"):
			"ally", "ally_other": tid = cs[1].id
			"ally_dead":
				tid = cs[1].id
				cs[1].hp = 0
				eng._kill(cs[1], "test")
			"self": tid = mage.id
		var lv = maxi(1, int(sp.level)) if int(sp.level) > 0 else 0
		var ok = eng.execute(mage.id, "sp:" + sp.id, {"targets": [tid], "cell": cs[2].pos, "slot": lv})
		if not ok:
			refused.append(sp.id)
		for i in 8:
			var cur = eng.current()
			if cur.is_empty():
				break
			if cur.id != mage.id:
				CombatAI.new(eng).run_turn(cur)
			eng.end_turn()
	check(refused.is_empty(), "every automated spell can be cast (refused: %s)" % str(refused))

	_lingering_spell_tests()

	_test_animated_objects_and_stones()
	_test_tiny_servant()
	_test_stones_before_combat()
	_test_darts_and_rays()
	_test_ai_keeps_stones()
	print("SPELLS DONE passed=%d failed=%d" % [passes, fails])
	get_tree().quit(1 if fails > 0 else 0)

## Hit `t` with `c`'s attack until it lands (AC is lowered so only a natural 1 misses).
func land_hit(c: Dictionary, t: Dictionary, atk: Dictionary) -> void:
	var ac = t.ac
	t.ac = -100
	for i in 10:
		if eng._attack_with(c, t, atk).get("hit", false):
			break
	t.ac = ac

func has_effect(c: Dictionary, name: String) -> bool:
	for e in c.effects:
		if e.get("name", "") == name:
			return true
	return false

## Lingering damage, effects that used to do nothing, smite riders and zone-casting AI.
func _lingering_spell_tests() -> void:
	# --- Moonbeam and Cloud of Daggers don't hurt on the turn they're cast, only when a turn starts inside.
	for sid in ["moonbeam", "cloud_of_daggers"]:
		var cz = board([["mage", "party", Vector2i(2, 2)], ["ogre", "enemy", Vector2i(8, 2)]])
		rig_saves(cz[1], true)
		cast(cz[0], sid, {"cell": cz[1].pos, "slot": 2})
		check(cz[1].hp == cz[1].max_hp, "%s deals no damage when cast (hp %d/%d)" % [sid, cz[1].hp, cz[1].max_hp])
		give_turn(cz[1])
		check(cz[1].hp < cz[1].max_hp, "%s hurts a creature starting its turn inside" % sid)

	# --- Phantasmal Killer: damage at the end of each failed turn; a success ends the spell.
	var cs = board([["mage", "party", Vector2i(2, 2)], ["ogre", "enemy", Vector2i(8, 2)]])
	var mage: Dictionary = cs[0]
	var ogre: Dictionary = cs[1]
	rig_saves(ogre, true)
	ogre.max_hp = 500
	ogre.hp = 500
	cast(mage, "phantasmal_killer", {"targets": [ogre.id], "slot": 4})
	check(eng.has_cond(ogre, "frightened"), "Phantasmal Killer frightens on a failed save")
	for i in 2:
		give_turn(ogre)
		var hp0: int = ogre.hp
		eng.end_turn()
		check(ogre.hp < hp0, "Phantasmal Killer deals psychic damage at the end of turn %d" % (i + 1))
	rig_saves(ogre, false)
	give_turn(ogre)
	var hp1: int = ogre.hp
	eng.end_turn()
	check(ogre.hp == hp1 and not eng.has_cond(ogre, "frightened") and mage.conc.is_empty(), "a successful save ends Phantasmal Killer without damage")

	# --- Melf's Acid Arrow: the 2d4 lands at the end of the target's next turn, once.
	cs = board([["mage", "party", Vector2i(2, 2)], ["ogre", "enemy", Vector2i(8, 2)]])
	mage = cs[0]
	ogre = cs[1]
	ogre.ac = -100
	for i in 10:
		cast(mage, "melfs_acid_arrow", {"targets": [ogre.id], "slot": 2})
		if has_effect(ogre, "Acid Burn"):
			break
	check(has_effect(ogre, "Acid Burn"), "Melf's Acid Arrow leaves acid on a hit")
	give_turn(ogre)
	var hp2: int = ogre.hp
	eng.end_turn()
	check(ogre.hp < hp2 and not has_effect(ogre, "Acid Burn"), "Melf's acid burns at the end of the target's next turn, then stops")

	# --- Witch Bolt: the action to repeat the damage opens up on later turns.
	cs = board([["mage", "party", Vector2i(2, 2)], ["ogre", "enemy", Vector2i(6, 2)]])
	mage = cs[0]
	ogre = cs[1]
	ogre.ac = -100
	for i in 10:
		cast(mage, "witch_bolt", {"targets": [ogre.id], "slot": 1})
		if mage.conc.has("sustain"):
			break
	check(mage.conc.has("sustain"), "Witch Bolt locks on after a hit")
	check(not eng.find_action(mage, "sustain_spell").get("enabled", true), "Witch Bolt can't be repeated on the turn it's cast")
	give_turn(mage)
	var hp3: int = ogre.hp
	check(eng.execute(mage.id, "sustain_spell", {}), "Witch Bolt can be sustained on the next turn")
	check(ogre.hp < hp3 and mage.turn.action == 0, "sustained Witch Bolt deals damage and costs the action")
	check(mage.conc.has("sustain"), "sustaining Witch Bolt doesn't end it")
	give_turn(mage)
	check(eng.execute(mage.id, "dodge", {}), "can take another action while Witch Bolt is up")
	check(mage.conc.is_empty(), "using the action for something else ends Witch Bolt")

	# --- Heat Metal: a bonus action burns the target again on later turns.
	cs = board([["mage", "party", Vector2i(2, 2)], ["ogre", "enemy", Vector2i(6, 2)]])
	mage = cs[0]
	ogre = cs[1]
	cast(mage, "heat_metal", {"targets": [ogre.id], "slot": 2})
	give_turn(mage)
	var a_hm = eng.find_action(mage, "sustain_spell")
	check(a_hm.get("cost", "") == "bonus" and a_hm.get("enabled", false), "Heat Metal offers a bonus action next turn")
	var hp4: int = ogre.hp
	eng.execute(mage.id, "sustain_spell", {})
	check(ogre.hp < hp4 and has_effect(ogre, "Searing Metal"), "Heat Metal burns again and keeps the disadvantage")

	# --- Hunger of Hadar: cold at the start of a turn inside, acid at the end, every turn.
	cs = board([["mage", "party", Vector2i(2, 2)], ["ogre", "enemy", Vector2i(12, 2)]])
	mage = cs[0]
	ogre = cs[1]
	rig_saves(ogre, true)
	cast(mage, "hunger_of_hadar", {"cell": ogre.pos, "slot": 3})
	check(eng.s.zones.size() == 2 and eng.s.zones[1].get("hidden", false), "Hunger of Hadar lays a start-turn and an end-turn zone")
	for i in 2:
		var h0: int = ogre.hp
		give_turn(ogre)
		var h1: int = ogre.hp
		eng.end_turn()
		check(h1 < h0 and ogre.hp < h1, "Hunger of Hadar: cold at start and acid at end of turn %d" % (i + 1))

	# --- Sanctuary: a failed WIS save wastes the attack; attacking ends the ward.
	cs = board([["mage", "party", Vector2i(2, 2)], ["orc", "party", Vector2i(4, 2)], ["goblin", "enemy", Vector2i(5, 2)]])
	mage = cs[0]
	var orc: Dictionary = cs[1]
	var gob: Dictionary = cs[2]
	cast(mage, "sanctuary", {"targets": [orc.id], "slot": 1})
	rig_saves(gob, true)
	var r = eng.roll_attack(gob, orc, {"to_hit": 50})
	check(not r.hit and r.get("sanctuary", false), "Sanctuary turns away an attacker who fails the save")
	eng.roll_attack(orc, gob, {"to_hit": 50})
	check(not eng.has_tag(orc, "sanctuary"), "attacking an enemy ends Sanctuary")

	# --- Sanctuary: an attacker who fails the save picks another target in reach instead.
	cs = board([["orc", "party", Vector2i(4, 2)], ["orc", "party", Vector2i(5, 3)], ["goblin", "enemy", Vector2i(5, 2)]])
	var warded: Dictionary = cs[0]
	var other: Dictionary = cs[1]
	gob = cs[2]
	eng.add_effect(warded, {"name": "Sanctuary", "tag": "sanctuary", "src": warded.id, "dc": 13, "rounds": 10})
	rig_saves(gob, true)
	r = eng.roll_attack(gob, warded, {"to_hit": 50})
	check(r.get("target", {}).get("id", "") == other.id and (r.hit or int(r.nat) == 1), "a turned-away attacker switches to another target in reach")
	r = eng.roll_attack(gob, warded, {"to_hit": 50}, {"fixed_target": true})
	check(r.get("sanctuary", false) and not r.hit, "an opportunity attack can't switch targets")

	# --- Expeditious Retreat: Dash as a bonus action.
	cs = board([["mage", "party", Vector2i(2, 2)], ["goblin", "enemy", Vector2i(15, 2)]])
	mage = cs[0]
	cast(mage, "expeditious_retreat", {"slot": 1})
	give_turn(mage)
	var er = eng.find_action(mage, "er_dash")
	check(er.get("cost", "") == "bonus" and er.get("enabled", false), "Expeditious Retreat offers a bonus-action Dash")
	eng.execute(mage.id, "er_dash", {})
	check(eng.move_left(mage) == 2 * eng.eff_speed(mage), "Expeditious Dash doubles the movement")

	# --- Dragon's Breath: the touched ally exhales a cone with its action.
	cs = board([["mage", "party", Vector2i(2, 2)], ["orc", "party", Vector2i(3, 2)], ["goblin", "enemy", Vector2i(5, 2)]])
	mage = cs[0]
	orc = cs[1]
	gob = cs[2]
	gob.max_hp = 200
	gob.hp = 200
	rig_saves(gob, true)
	cast(mage, "dragons_breath", {"targets": [orc.id], "slot": 2, "opts": {"dtype": "cold"}})
	give_turn(orc)
	check(eng.find_action(orc, "dragons_breath").get("enabled", false), "Dragon's Breath gives the ally a breath action")
	eng.execute(orc.id, "dragons_breath", {"cell": gob.pos})
	check(gob.hp < 200, "Dragon's Breath damages creatures in the cone")

	# --- Compulsion: the target spends its movement heading away.
	cs = board([["mage", "party", Vector2i(2, 2)], ["ogre", "enemy", Vector2i(6, 2)]])
	mage = cs[0]
	ogre = cs[1]
	rig_saves(ogre, true)
	cast(mage, "compulsion", {"targets": [ogre.id], "slot": 4})
	give_turn(ogre)
	check(eng.dist(mage, ogre) > 20, "Compulsion moves the target away (now %d ft)" % eng.dist(mage, ogre))

	# --- Enemies Abound: everyone looks like a foe; damage allows a new save.
	cs = board([["mage", "party", Vector2i(2, 2)], ["goblin", "enemy", Vector2i(6, 2)], ["ogre", "enemy", Vector2i(8, 2)]])
	mage = cs[0]
	gob = cs[1]
	ogre = cs[2]
	rig_saves(gob, true)
	cast(mage, "enemies_abound", {"targets": [gob.id], "slot": 3})
	check(eng.hostile(gob, ogre) and ogre in eng.enemies_of(gob), "Enemies Abound: the target treats its allies as enemies")
	rig_saves(gob, false)
	gob.max_hp = 100
	gob.hp = 100
	eng.apply_damage(gob, [{"amount": 3, "type": "fire"}], mage)
	check(not eng.has_tag(gob, "enemies_abound"), "taking damage lets the target shake off Enemies Abound")

	# --- Swift Quiver: two ranged attacks as a bonus action.
	cs = board([["scout", "party", Vector2i(2, 2)], ["ogre", "enemy", Vector2i(10, 2)]])
	var scout: Dictionary = cs[0]
	ogre = cs[1]
	cast(scout, "swift_quiver", {"slot": 5})
	give_turn(scout)
	var sq = eng.find_action(scout, "swift_quiver")
	check(sq.get("cost", "") == "bonus" and sq.get("enabled", false), "Swift Quiver offers a bonus-action volley")

	# --- Thunderous Smite: pushed 10 ft and knocked prone on a failed STR save.
	cs = board([["knight", "party", Vector2i(2, 2)], ["ogre", "enemy", Vector2i(3, 2)]])
	var knight: Dictionary = cs[0]
	ogre = cs[1]
	rig_saves(ogre, true)
	cast(knight, "thunderous_smite", {"slot": 1})
	land_hit(knight, ogre, eng.best_melee(knight))
	check(eng.has_cond(ogre, "prone") and ogre.pos.x >= 4, "Thunderous Smite pushes and knocks prone (pos %s)" % str(ogre.pos))
	check(knight.conc.is_empty(), "Thunderous Smite's concentration ends once it lands")

	# --- Wrathful Smite: frightened until the spell ends or a WIS check shakes it off.
	cs = board([["knight", "party", Vector2i(2, 2)], ["ogre", "enemy", Vector2i(3, 2)]])
	knight = cs[0]
	ogre = cs[1]
	rig_saves(ogre, true)
	cast(knight, "wrathful_smite", {"slot": 1})
	land_hit(knight, ogre, eng.best_melee(knight))
	check(eng.has_cond(ogre, "frightened") and knight.conc.get("spell", "") == "wrathful_smite", "Wrathful Smite frightens and stays concentrated")
	var esc = eng.escape_effect(ogre)
	check(esc.get("escape_with", []) == ["wis"], "Wrathful Smite's fear can be ended with a WIS check")

	# --- Searing Smite: the target burns at the start of its turns until it saves.
	cs = board([["knight", "party", Vector2i(2, 2)], ["ogre", "enemy", Vector2i(3, 2)]])
	knight = cs[0]
	ogre = cs[1]
	rig_saves(ogre, true)
	cast(knight, "searing_smite", {"slot": 1})
	land_hit(knight, ogre, eng.best_melee(knight))
	var hp5: int = ogre.hp
	give_turn(ogre)
	check(ogre.hp < hp5, "Searing Smite's flames burn at the start of the target's turn")
	rig_saves(ogre, false)
	give_turn(ogre)
	check(not has_effect(ogre, "Searing Smite") and knight.conc.is_empty(), "a successful CON save puts out Searing Smite")

	# --- AI casts zones that have no save on casting.
	for sid in ["spike_growth", "cloudkill"]:
		cs = board([["mage", "enemy", Vector2i(1, 5)], ["goblin", "party", Vector2i(12, 4)], ["goblin", "party", Vector2i(13, 5)], ["goblin", "party", Vector2i(12, 6)]])
		mage = cs[0]
		teach(mage, sid)
		mage.casting[0].spells = [sid]
		mage.casting[0].at_will = []
		give_turn(mage)
		CombatAI.new(eng).run_turn(mage)
		var cast_it = false
		for z in eng.s.zones:
			if z.spell == sid:
				cast_it = true
		check(cast_it, "the AI casts %s on a group of enemies" % Data.spell(sid).name)

func _count_objects(owner_id: String) -> int:
	var n = 0
	for o in eng.all_combatants():
		if o.get("summoner", "") == owner_id and o.get("animated", "") != "" and eng.alive(o):
			n += 1
	return n

func _stones_held(c: Dictionary) -> int:
	var n = 0
	for e in c.effects:
		if e.get("tag", "") == "magic_stone":
			n += int(e.uses)
	return n

func _servants(owner_id: String) -> Array:
	return eng.all_combatants().filter(func(o): return o.get("servant", false) and o.get("summoner", "") == owner_id and eng.alive(o))

func _test_tiny_servant() -> void:
	# A board where combat hasn't started: Tiny Servant takes a minute to cast.
	var st = EngineBase.new_state(20, 10)
	eng = CombatEngine.new(st)
	var mage = CombatantFactory.from_monster(eng.new_id("m"), "mage")
	mage.team = "party"
	mage.pos = Vector2i(2, 4)
	st.combatants[mage.id] = mage
	var ogre = CombatantFactory.from_monster(eng.new_id("m"), "ogre")
	ogre.team = "enemy"
	ogre.pos = Vector2i(14, 4)
	ogre.hp = 500
	ogre.max_hp = 500
	st.combatants[ogre.id] = ogre
	teach(mage, "tiny_servant")
	teach(mage, "magic_stone")
	# --- Base casting: one servant with the XGtE statistics.
	check(eng.execute(mage.id, "sp:tiny_servant", {"cell": Vector2i(3, 4), "slot": 3}), "Tiny Servant can be cast outside combat")
	var sv: Array = _servants(mage.id)
	check(sv.size() == 1, "a 3rd-level casting animates one object (got %d)" % sv.size())
	var s1: Dictionary = sv[0]
	check(s1.ac == 15 and s1.max_hp == 10 and s1.speed == 30 and s1.attacks[0].to_hit == 5 and str(s1.attacks[0].damage[0].dice) == "1d4+3", "a servant has AC 15, 10 HP, speed 30 and a +5 slam for 1d4+3")
	check("poison" in s1.immune and "psychic" in s1.immune and "charmed" in s1.cond_immune, "a servant is immune to poison, psychic and charm")
	check(s1.pos == Vector2i(3, 4), "the servant stands where the touched object was")
	check(mage.slots_used[2] == 1 and mage.conc.is_empty(), "uses a 3rd-level slot, no concentration")
	# --- Upcasting: two more objects per slot level above 3rd.
	check(eng.tiny_servant_count(0) == 1 and eng.tiny_servant_count(1) == 3 and eng.tiny_servant_count(6) == 13, "servant counts by slot level")
	check(eng.execute(mage.id, "sp:tiny_servant", {"cell": Vector2i(3, 5), "slot": 5}), "Tiny Servant can be upcast")
	check(_servants(mage.id).size() == 6, "a 5th-level casting adds five servants and keeps the first (got %d)" % _servants(mage.id).size())
	# --- Combat: the servants share the caster's initiative, acting right after it.
	eng.start_combat()
	var idx: int = eng.s.order.find(mage.id)
	var follow = true
	for i in 6:
		if not eng.C(eng.s.order[idx + 1 + i]).get("servant", false):
			follow = false
	check(follow, "all six servants act right after the caster")
	give_turn(mage)
	var tsa = eng.find_action(mage, "sp:tiny_servant")
	check(not tsa.enabled and not eng.execute(mage.id, "sp:tiny_servant", {"cell": Vector2i(3, 4), "slot": 3}), "Tiny Servant can't be cast in combat (1 minute casting time)")
	# --- The caster drops stones (no cost at all), a servant picks them up.
	check(eng.execute(mage.id, "sp:magic_stone", {"targets": [mage.id]}), "Magic Stone can be cast")
	var econ_before: Array = [int(mage.turn.action), int(mage.turn.bonus)]
	for p in [Vector2i(3, 3), Vector2i(2, 3)]:
		eng.execute(mage.id, "magic_stone_drop", {"cell": p})
	check([int(mage.turn.action), int(mage.turn.bonus)] == econ_before and not mage.turn.get("interacted", false), "dropping a stone costs nothing, not even the free object interaction")
	check(eng.execute(mage.id, "magic_stone_pickup", {"cell": Vector2i(2, 3)}), "the caster can pick a stone back up with its free interaction")
	s1.pos = Vector2i(4, 3)
	give_turn(s1)
	var pick = eng.find_action(s1, "magic_stone_pickup")
	check(not pick.is_empty() and pick.cost == "free", "a servant next to a stone can pick it up as its free object interaction")
	check(eng.execute(s1.id, "magic_stone_pickup", {"cell": Vector2i(3, 3)}), "the servant picks up the stone")
	check(_stones_held(s1) == 1 and int(s1.turn.action) == 1, "the servant holds the stone and still has its action")
	var throw = eng.find_action(s1, "magic_stone_throw")
	check(not throw.is_empty() and int(throw.atk.to_hit) == int(mage.casting[0].attack), "the servant throws with the caster's spell attack")
	check(eng.execute(s1.id, "magic_stone_throw", {"targets": [ogre.id]}) and _stones_held(s1) == 0, "the servant throws the stone at the ogre")
	# --- A second pickup in one turn needs the Use an Object action.
	var s2: Dictionary = _servants(mage.id)[1]
	eng.put_stone_down(mage, eng._held_stone(mage, ""), Vector2i(6, 6))
	eng.put_stone_down(mage, eng._held_stone(mage, ""), Vector2i(6, 6))
	s2.pos = Vector2i(6, 5)
	give_turn(s2)
	check(eng.execute(s2.id, "magic_stone_pickup", {"cell": Vector2i(6, 6)}), "a servant picks up one stone free")
	var pick2 = eng.find_action(s2, "magic_stone_pickup")
	check(pick2.cost == "action", "a second pickup costs the Use an Object action")
	check(eng.execute(s2.id, "magic_stone_pickup", {"cell": Vector2i(6, 6)}) and int(s2.turn.action) == 0 and _stones_held(s2) == 2, "the second pickup spends the action")
	check(not eng.execute(s2.id, "magic_stone_throw", {"targets": [ogre.id]}), "with its action spent the servant can't also throw")
	# --- A servant at 0 HP reverts to an object and drops what it carries.
	eng.apply_damage(s2, [{"amount": 50, "type": "force"}], ogre, {})
	check(not eng.alive(s2) and eng.stones_at(Vector2i(6, 5)).size() == 2, "a destroyed servant drops its stones")
	# --- Servants outlast the fight (8 hours), unlike Animate Objects.
	eng.end_combat()
	check(_servants(mage.id).size() == 5, "servants remain after combat ends (got %d)" % _servants(mage.id).size())
	# --- Each casting's servants revert when its 8 hours run out.
	var marks: Array = mage.effects.filter(func(e): return e.get("tag", "") == "tiny_servant")
	check(marks.size() == 2 and int(marks[0].rounds) > 4700, "each casting is tracked for 8 hours (%s)" % str(marks.map(func(e): return e.rounds)))
	if not marks.is_empty():
		marks[0].rounds = 1
	eng.tick_effects(mage.id, "start")
	check(_servants(mage.id).size() == 4 and not eng.alive(s1), "the first casting's servant reverts; the others stay")
	# --- An AI servant grabs a stone lying next to it.
	eng.start_combat()
	var s3: Dictionary = _servants(mage.id)[0]
	eng.ground_items().clear()
	eng.ground_items().append({"id": "i9", "kind": "magic_stone", "name": "Magic Stone", "pos": s3.pos + Vector2i(1, 0), "src": mage.id, "attack": 7, "dice": "1d6+3", "rounds": 10})
	give_turn(s3)
	CombatAI.new(eng).run_turn(s3)
	check(eng.ground_items().is_empty(), "an auto-played servant picks up a stone next to it")

## Arming servants and allies with magic stones before a fight: the stones are handed over outside
## combat and are still in hand when initiative is rolled.
func _test_stones_before_combat() -> void:
	var st = EngineBase.new_state(20, 10)
	eng = CombatEngine.new(st)
	var spec: Array = [["mage", "party", Vector2i(2, 4)], ["guard", "party", Vector2i(2, 5)], ["guard", "party", Vector2i(8, 8)], ["ogre", "enemy", Vector2i(10, 4)]]
	var cs: Array = []
	for row in spec:
		var m = CombatantFactory.from_monster(eng.new_id("m"), row[0])
		m.team = row[1]
		m.pos = row[2]
		st.combatants[m.id] = m
		cs.append(m)
	var mage: Dictionary = cs[0]
	var guard: Dictionary = cs[1]
	var far_guard: Dictionary = cs[2]
	var ogre: Dictionary = cs[3]
	ogre.hp = 500
	ogre.max_hp = 500
	teach(mage, "tiny_servant")
	teach(mage, "magic_stone")
	check(eng.execute(mage.id, "sp:tiny_servant", {"cell": Vector2i(3, 4), "slot": 3}), "Tiny Servant is cast before the fight")
	var servant: Dictionary = _servants(mage.id)[0]
	check(eng.execute(mage.id, "sp:magic_stone", {"targets": [mage.id]}) and _stones_held(mage) == 3, "Magic Stone can be cast outside combat")
	var give = eng.find_action(mage, "magic_stone_give")
	check(not give.is_empty() and give.enabled and give.cost == "free" and give.target == "ally_other", "a stone holder can hand stones over outside combat")
	# --- Hand-offs: two to the servant, one to an ally; all free outside combat.
	check(eng.execute(mage.id, "magic_stone_give", {"targets": [servant.id]}), "the caster gives its servant a stone")
	check(eng.execute(mage.id, "magic_stone_give", {"targets": [servant.id]}), "the caster gives the servant a second stone")
	check(not eng.execute(mage.id, "magic_stone_give", {"targets": [far_guard.id]}), "can't hand a stone to a creature out of reach")
	check(not eng.execute(mage.id, "magic_stone_give", {"targets": [mage.id]}), "can't hand a stone to yourself")
	ogre.pos = Vector2i(3, 5)
	check(not eng.execute(mage.id, "magic_stone_give", {"targets": [ogre.id]}), "can't hand a stone to an enemy")
	ogre.pos = Vector2i(10, 4)
	check(eng.execute(mage.id, "magic_stone_give", {"targets": [guard.id]}), "the caster gives another creature a stone")
	check(_stones_held(mage) == 0 and _stones_held(servant) == 2 and _stones_held(guard) == 1, "the stones change hands (%d/%d/%d)" % [_stones_held(mage), _stones_held(servant), _stones_held(guard)])
	check(eng.find_action(mage, "magic_stone_give").is_empty() and eng.magic_stones_in_play(mage.id) == 3, "nothing left to give; all three stones still count as in play")
	# --- A holder can pass a stone on in turn.
	servant.pos = Vector2i(3, 5)
	check(eng.execute(servant.id, "magic_stone_give", {"targets": [guard.id]}) and _stones_held(servant) == 1 and _stones_held(guard) == 2, "a servant can pass a stone to someone else")
	# --- Combat starts: the stones are still in hand and can be thrown with the caster's numbers.
	eng.start_combat()
	check(_stones_held(servant) == 1 and _stones_held(guard) == 2, "stones given before combat are carried into the fight")
	give_turn(servant)
	var throw = eng.find_action(servant, "magic_stone_throw")
	check(not throw.is_empty() and throw.enabled and int(throw.atk.to_hit) == int(mage.casting[0].attack), "the servant can throw its stone on its first turn")
	check(eng.execute(servant.id, "magic_stone_throw", {"targets": [ogre.id]}) and _stones_held(servant) == 0, "the servant throws the stone it was given")
	# --- In combat a hand-off is the free object interaction; a second one takes the action.
	give_turn(guard)
	var g1 = eng.find_action(guard, "magic_stone_give")
	check(g1.cost == "free", "the first hand-off on a turn is the free object interaction")
	check(eng.execute(guard.id, "magic_stone_give", {"targets": [mage.id]}) and int(guard.turn.action) == 1 and guard.turn.get("interacted", false), "handing a stone over in combat uses the interaction, not the action")
	check(eng.find_action(guard, "magic_stone_give").cost == "action", "a second hand-off costs the Use an Object action")
	check(eng.execute(guard.id, "magic_stone_give", {"targets": [mage.id]}) and int(guard.turn.action) == 0 and _stones_held(mage) == 2, "the second hand-off spends the action")
	# --- The stones keep the spell's one-minute timer, counted on the caster's turns.
	for i in 10:
		eng.tick_effects(mage.id, "start")
	check(_stones_held(mage) == 0, "handed-over stones still expire with the spell")

func _test_animated_objects_and_stones() -> void:
	var cs = board([["mage", "party", Vector2i(2, 4)], ["ogre", "enemy", Vector2i(14, 4)]])
	var mage: Dictionary = cs[0]
	var ogre: Dictionary = cs[1]
	ogre.hp = 500
	ogre.max_hp = 500
	# --- Animate Objects: ten Tiny objects at a point, right after the caster in initiative.
	check(cast(mage, "animate_objects", {"cell": Vector2i(6, 4), "slot": 5, "opts": {"obj_size": "tiny"}}), "Animate Objects can be cast")
	check(_count_objects(mage.id) == 10, "ten Tiny objects are animated (got %d)" % _count_objects(mage.id))
	var objs: Array = eng.all_combatants().filter(func(o): return o.get("summoner", "") == mage.id)
	var obj: Dictionary = objs[0]
	check(obj.ac == 18 and obj.max_hp == 20 and obj.attacks[0].to_hit == 8 and obj.fly == 30, "a Tiny object has AC 18, 20 HP, +8 slam and hovers")
	check(eng.s.order.find(obj.id) == eng.s.order.find(mage.id) + 1, "objects act right after their caster")
	check(mage.conc.get("spell", "") == "animate_objects", "the caster concentrates on Animate Objects")
	check(eng.animated_object_count("tiny", 2) == 14 and eng.animated_object_count("medium", 0) == 5 and eng.animated_object_count("huge", 0) == 1, "object counts by size and slot level")
	var bystander: Dictionary = {}
	var thrower: Dictionary = {}
	for o in objs:
		if o.pos == Vector2i(5, 4):
			thrower = o
		elif o.pos == Vector2i(5, 3):
			bystander = o
	check(not thrower.is_empty() and not bystander.is_empty(), "objects fill the cells around the chosen point")
	# --- Magic Stone on a later turn, then drop all three stones next to the caster.
	check(cast(mage, "magic_stone", {"targets": [mage.id]}), "Magic Stone can be cast")
	check(_stones_held(mage) == 3, "the caster holds three stones")
	for p in [Vector2i(3, 4), Vector2i(3, 3), Vector2i(3, 5)]:
		check(eng.execute(mage.id, "magic_stone_drop", {"cell": p}), "the caster drops a stone at %s" % p)
	check(_stones_held(mage) == 0 and eng.ground_items().size() == 3, "three stones lie on the ground, none held")
	check(eng.find_action(mage, "magic_stone_drop").is_empty() and eng.find_action(mage, "magic_stone_throw").is_empty(), "no throw/drop actions without a stone")
	check(not eng.execute(mage.id, "magic_stone_drop", {"cell": Vector2i(3, 4)}), "can't drop a stone you don't have")
	check(int(mage.turn.action) == 1, "dropping stones is free")
	# --- An animated object picks one up (free) and throws it with the caster's numbers.
	thrower.pos = Vector2i(4, 4)
	give_turn(thrower)
	var pick = eng.find_action(thrower, "magic_stone_pickup")
	check(not pick.is_empty() and pick.cost == "free", "an object next to a stone can pick it up for free")
	check(not eng.execute(thrower.id, "magic_stone_pickup", {"cell": Vector2i(8, 8)}), "can't pick up a stone that isn't there")
	check(eng.execute(thrower.id, "magic_stone_pickup", {"cell": Vector2i(3, 4)}), "the object picks up a stone")
	check(_stones_held(thrower) == 1 and eng.ground_items().size() == 2, "the stone moves from the ground to the object")
	check(eng.find_action(thrower, "magic_stone_pickup").cost == "action", "a second pickup takes the Use an Object action")
	var throw = eng.find_action(thrower, "magic_stone_throw")
	var ce: Dictionary = mage.casting[0]
	check(not throw.is_empty() and int(throw.atk.to_hit) == int(ce.attack) and str(throw.atk.damage[0].dice) == "1d6+%d" % int(ce.mod), "the throw uses the caster's spell attack and modifier, not the object's")
	var before_log: int = eng.s.log.size()
	check(eng.execute(thrower.id, "magic_stone_throw", {"targets": [ogre.id]}), "the object throws the stone at the ogre")
	check(_stones_held(thrower) == 0, "the thrown stone is used up")
	var logged = false
	for i in range(before_log, eng.s.log.size()):
		if "vs AC" in str(eng.s.log[i]):
			logged = true
	check(logged, "the throw is rolled as an attack against the ogre")
	# --- A stone carrier that is destroyed drops what it holds.
	give_turn(bystander)
	bystander.pos = Vector2i(4, 3)
	check(eng.execute(bystander.id, "magic_stone_pickup", {"cell": Vector2i(3, 3)}), "a second object picks up a stone")
	eng.apply_damage(bystander, [{"amount": 100, "type": "force"}], ogre, {})
	check(not eng.alive(bystander), "the object is destroyed")
	check(eng.stones_at(Vector2i(4, 3)).size() == 1, "its stone falls where it was")
	# --- Ending concentration ends the objects.
	eng.end_concentration(mage)
	check(_count_objects(mage.id) == 0, "objects fall lifeless when concentration ends")
	# --- Casting Magic Stone again ends the old stones, wherever they are.
	check(cast(mage, "magic_stone", {"targets": [mage.id]}), "Magic Stone can be cast again")
	check(eng.ground_items().is_empty() and _stones_held(mage) == 3, "recasting ends the old stones and makes three new ones")
	# --- The spell's duration (10 rounds) runs out for stones on the ground too.
	eng.execute(mage.id, "magic_stone_drop", {"cell": Vector2i(3, 4)})
	for i in 10:
		eng._tick_items(mage.id)
	check(eng.ground_items().is_empty(), "a dropped stone loses its magic when the minute is up")
	# --- Animate Objects' own duration ends the objects.
	cast(mage, "animate_objects", {"cell": Vector2i(8, 4), "slot": 6, "opts": {"obj_size": "medium"}})
	check(_count_objects(mage.id) == 6, "a 6th-level casting animates six Medium objects (got %d)" % _count_objects(mage.id))
	for i in 10:
		eng.tick_effects(mage.id, "start")
	check(_count_objects(mage.id) == 0 and mage.conc.is_empty(), "the objects stop after one minute")
	# --- Combat ending sweeps away loose stones and objects.
	cast(mage, "animate_objects", {"cell": Vector2i(8, 4), "slot": 5, "opts": {"obj_size": "large"}})
	check(_count_objects(mage.id) == 2, "two Large objects (got %d)" % _count_objects(mage.id))
	eng.execute(mage.id, "magic_stone_drop", {"cell": Vector2i(3, 4)})
	eng.end_combat()
	check(eng.ground_items().is_empty() and _count_objects(mage.id) == 0 and mage.conc.is_empty(), "ending combat clears stones and objects")
	# --- The AI picks up a stone within reach and the AI casts Animate Objects.
	cs = board([["mage", "enemy", Vector2i(2, 4)], ["goblin", "party", Vector2i(10, 4)], ["goblin", "enemy", Vector2i(12, 4)]])
	var gob: Dictionary = cs[2]
	# The thrown stone mustn't kill the mage's only target before the mage gets to act.
	cs[1].max_hp = 60
	cs[1].hp = 60
	eng.ground_items().append({"id": "i1", "kind": "magic_stone", "name": "Magic Stone", "pos": Vector2i(13, 4), "src": cs[0].id, "attack": 5, "dice": "1d6+3", "rounds": 10})
	give_turn(gob)
	CombatAI.new(eng).run_turn(gob)
	check(eng.ground_items().is_empty(), "an AI creature grabs a stone lying next to it")
	var amage: Dictionary = cs[0]
	teach(amage, "animate_objects")
	amage.casting[0].spells = ["animate_objects"]
	give_turn(amage)
	CombatAI.new(eng).run_turn(amage)
	check(_count_objects(amage.id) == 10, "the AI casts Animate Objects (got %d)" % _count_objects(amage.id))

## Hits on `t` by the caster's spell since log index `from` (one "takes" line per dart that lands).
func _hits_since(t: Dictionary, from: int) -> int:
	var n = 0
	for i in range(from, eng.s.log.size()):
		var ln = str(eng.s.log[i])
		if t.name in ln and " takes " in ln:
			n += 1
	return n

func _test_darts_and_rays() -> void:
	var cs = board([["mage", "party", Vector2i(2, 4)], ["ogre", "enemy", Vector2i(8, 3)], ["ogre", "enemy", Vector2i(8, 6)]])
	var mage: Dictionary = cs[0]
	var a: Dictionary = cs[1]
	var b: Dictionary = cs[2]
	for o in [a, b]:
		o.name = "Ogre A" if o == a else "Ogre B"
		o.hp = 500
		o.max_hp = 500
	# --- Magic Missile: each dart goes where it was aimed, repeats allowed.
	var from: int = eng.s.log.size()
	check(cast(mage, "magic_missile", {"targets": [a.id, a.id, b.id], "slot": 1}), "Magic Missile can be cast at three picks")
	check(_hits_since(a, from) == 2 and _hits_since(b, from) == 1, "two darts hit the creature picked twice, one the other (%d/%d)" % [_hits_since(a, from), _hits_since(b, from)])
	from = eng.s.log.size()
	check(cast(mage, "magic_missile", {"targets": [a.id, b.id, b.id, b.id], "slot": 2}), "an upcast Magic Missile takes four picks")
	check(_hits_since(a, from) == 1 and _hits_since(b, from) == 3, "a 2nd-level casting sends 1 and 3 darts as aimed (%d/%d)" % [_hits_since(a, from), _hits_since(b, from)])
	from = eng.s.log.size()
	check(cast(mage, "magic_missile", {"targets": [b.id], "slot": 1}), "Magic Missile at one pick")
	check(_hits_since(b, from) == 3 and _hits_since(a, from) == 0, "one pick takes all three darts")
	var mm = eng.find_action(mage, "sp:magic_missile")
	check(eng.spell_shots(mage, mm, 1) == 3 and eng.spell_shots(mage, mm, 3) == 5, "dart count grows with the slot")
	# --- Scorching Ray: each ray rolls against the creature it was aimed at.
	from = eng.s.log.size()
	check(cast(mage, "scorching_ray", {"targets": [a.id, b.id, b.id], "slot": 2}), "Scorching Ray can be cast at three picks")
	var at_a = 0
	var at_b = 0
	for i in range(from, eng.s.log.size()):
		var ln = str(eng.s.log[i])
		if "vs AC" in ln:
			if "Ogre A" in ln: at_a += 1
			if "Ogre B" in ln: at_b += 1
	check(at_a == 1 and at_b == 2, "Scorching Ray splits 1 and 2 rays as aimed (%d/%d)" % [at_a, at_b])

func _test_ai_keeps_stones() -> void:
	var cs = board([["mage", "party", Vector2i(2, 4)], ["guard", "party", Vector2i(3, 3)], ["ogre", "enemy", Vector2i(12, 4)]])
	var mage: Dictionary = cs[0]
	var guard: Dictionary = cs[1]
	cs[2].hp = 500
	cs[2].max_hp = 500
	mage.casting = []
	teach(mage, "magic_stone")
	mage.casting[0].spells = ["magic_stone"]
	give_turn(mage)
	check(eng.execute(mage.id, "sp:magic_stone", {"targets": [mage.id]}), "Magic Stone can be cast")
	eng.execute(mage.id, "magic_stone_drop", {"cell": Vector2i(3, 4)})
	eng.execute(mage.id, "magic_stone_drop", {"cell": Vector2i(3, 4)})
	eng.execute(mage.id, "magic_stone_drop", {"cell": Vector2i(3, 4)})
	give_turn(guard)
	eng.execute(guard.id, "magic_stone_pickup", {"cell": Vector2i(3, 4)})
	check(_stones_held(guard) == 1, "an ally picks up a stone")
	# The AI caster, with stones still out, doesn't recast (which would end the ally's stone).
	give_turn(mage)
	CombatAI.new(eng).run_turn(mage)
	check(_stones_held(guard) == 1, "the AI caster leaves its earlier stones alone while they're in play")
	# Recasting by hand still ends the old stones (RAW) and says so.
	var from: int = eng.s.log.size()
	give_turn(mage)
	eng.execute(mage.id, "sp:magic_stone", {"targets": [mage.id]})
	var said = false
	for i in range(from, eng.s.log.size()):
		if "lose" in str(eng.s.log[i]) and "magic" in str(eng.s.log[i]):
			said = true
	check(_stones_held(guard) == 0 and said, "recasting ends the old stones and logs it")
	# With no stones out, the AI happily casts it.
	eng._end_magic_stones(mage.id)
	give_turn(mage)
	CombatAI.new(eng).run_turn(mage)
	check(_stones_held(mage) > 0 or eng.magic_stones_in_play(mage.id) > 0, "the AI casts Magic Stone when none are out")
