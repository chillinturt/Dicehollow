extends Node
## Regressions from the 5e (2014) rules audit: character derivation, damage, death, exhaustion,
## once-per-turn riders, rage and rests.
## Run: Godot --headless --path . res://tests/audit5e_test.tscn   (exit code 1 on failure)

var eng: CombatEngine
var fails := 0
var passes := 0

func check(cond: bool, what: String) -> void:
	if cond:
		passes += 1
	else:
		fails += 1
		print("FAIL: ", what)

## Board with characters [[character, cell], ...] and monsters [[id, team, cell], ...].
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

func give_turn(c: Dictionary) -> void:
	eng.s.turn = eng.s.order.find(c.id)
	eng.begin_turn(c)

func hero(classes: Array, extra := {}) -> Dictionary:
	var ch = Rules.new_character()
	ch.merge({"name": "Hero", "race": "human", "background": "soldier",
		"base_scores": {"str": 15, "dex": 14, "con": 14, "int": 10, "wis": 10, "cha": 12},
		"classes": classes}, true)
	ch.merge(extra, true)
	return ch

func attack_named(c: Dictionary, id: String) -> Dictionary:
	for a in c.attacks:
		if a.id == id:
			return a
	return {}

func _ready() -> void:
	# --- A 1st-level paladin has no spell slots and so prepares no spells.
	var pal1 = hero([{"id": "paladin", "level": 1, "subclass": ""}], {"base_scores": {"str": 15, "dex": 10, "con": 14, "int": 8, "wis": 10, "cha": 16}})
	var sc = Rules.spell_counts(pal1, pal1.classes[0], Rules.final_scores(pal1))
	check(int(sc.spells) == 0, "paladin 1 prepares no spells (got %d)" % int(sc.spells))
	var pal2 = pal1.duplicate(true)
	pal2.classes[0].level = 2
	sc = Rules.spell_counts(pal2, pal2.classes[0], Rules.final_scores(pal2))
	check(int(sc.spells) == 4, "paladin 2 with CHA 17: 3 + 1 = 4 prepared (got %d)" % int(sc.spells))

	# --- Multiclass hit dice are tracked per die size.
	var mc = hero([{"id": "fighter", "level": 3, "subclass": "champion"}, {"id": "wizard", "level": 2, "subclass": "evocation"}])
	var st = Rules.derive(mc)
	check(st.hit_dice == "3d10 + 2d6", "fighter 3 / wizard 2 hit dice are 3d10 + 2d6 (got %s)" % st.hit_dice)

	# --- Dual Wielder's +1 AC needs a melee weapon in each hand, so not with a shield.
	var dw = hero([{"id": "fighter", "level": 4, "subclass": "champion"}], {"feats": ["dual_wielder"],
		"equipment": {"armor": "leather", "shield": false, "weapons": ["rapier", "rapier"], "weapon_bonus": 0, "armor_bonus": 0}})
	var ac_dw: int = Rules.derive(dw).ac
	dw.equipment.weapons = ["rapier", "light_crossbow"]
	check(Rules.derive(dw).ac == ac_dw - 1, "Dual Wielder: no AC bonus with only one melee weapon")
	dw.equipment.weapons = ["rapier", "rapier"]
	dw.equipment.shield = true
	check(Rules.derive(dw).ac == ac_dw + 1, "Dual Wielder: shield gives +2 but no Dual Wielder +1 (got %d vs %d)" % [Rules.derive(dw).ac, ac_dw])

	# --- Dueling with a versatile weapon: wielded one-handed so the +2 applies.
	var duel = hero([{"id": "fighter", "level": 1, "subclass": ""}], {"fighting_styles": ["dueling"],
		"equipment": {"armor": "chain_mail", "shield": false, "weapons": ["longsword"], "weapon_bonus": 0, "armor_bonus": 0}})
	var ls = attack_named({"attacks": Rules.derive(duel).weapons}, "w_longsword")
	check(ls.die == "1d8" and ls.damage[0].dice == "1d8+5", "Dueling longsword: 1d8 + STR 3 + 2 (got %s)" % ls.damage[0].dice)
	var gw = hero([{"id": "fighter", "level": 1, "subclass": ""}], {"fighting_styles": ["great_weapon_fighting"],
		"equipment": {"armor": "chain_mail", "shield": false, "weapons": ["longsword"], "weapon_bonus": 0, "armor_bonus": 0}})
	ls = attack_named({"attacks": Rules.derive(gw).weapons}, "w_longsword")
	check(ls.die == "1d10", "without Dueling a free hand swings the longsword two-handed (1d10)")

	# --- Off-hand attack only adds proficiency with a proficient weapon.
	var wiz = hero([{"id": "wizard", "level": 1, "subclass": ""}], {"equipment": {"armor": "", "shield": false, "weapons": ["handaxe", "handaxe"], "weapon_bonus": 0, "armor_bonus": 0}})
	var oh = attack_named({"attacks": Rules.derive(wiz).weapons}, "offhand")
	check(not oh.is_empty() and int(oh.to_hit) == 3, "wizard off-hand handaxe: STR +3, no proficiency (got %s)" % str(oh.get("to_hit", "?")))

	# --- Any attack that hits a paralysed creature from within 5 ft is a crit, ranged too.
	var cs = board([], [["orc", "party", Vector2i(2, 2)], ["goblin", "enemy", Vector2i(3, 2)]])
	var orc: Dictionary = cs[0]
	var gob: Dictionary = cs[1]
	eng.add_effect(gob, {"name": "Held", "cond": "paralyzed", "src": "dm", "rounds": 99, "tick_cid": "none"})
	var crit_ok = true
	for i in 20:
		var r = eng.roll_attack(orc, gob, {"to_hit": 50, "melee": false, "range": 80, "long_range": 320}, {"melee": false})
		if r.hit and not r.crit:
			crit_ok = false
	check(crit_ok, "ranged hits on a paralysed creature within 5 ft are critical hits")

	# --- Invisibility gives no edge against blindsight.
	orc.senses = "blindsight 30 ft."
	eng.add_effect(gob, {"name": "Invisible", "cond": "invisible", "src": "dm", "rounds": 99, "tick_cid": "none"})
	eng.remove_effects_where(gob, func(e): return e.get("cond", "") == "paralyzed")
	check(eng.attack_advantage(orc, gob, true) == 0, "attacking an invisible creature you sense with blindsight: no disadvantage")
	check(eng.attack_advantage(gob, orc, true) == 0, "an invisible attacker gets no advantage against blindsight")
	orc.senses = ""
	check(eng.attack_advantage(orc, gob, true) == -1, "without blindsight the invisible goblin imposes disadvantage")

	# --- Heavy Armor Master's -3 comes before resistance.
	cs = board([], [["ogre", "enemy", Vector2i(2, 2)], ["goblin", "party", Vector2i(8, 2)]])
	var ogre: Dictionary = cs[0]
	ogre.heavy_armor = true
	ogre.feats = ["heavy_armor_master"]
	ogre.resist = ["slashing"]
	ogre.mundane_resist = false
	var lost: int = eng.apply_damage(ogre, [{"amount": 11, "type": "slashing"}], {}, {})
	check(lost == 4, "11 slashing: HAM -3 then resistance halves = 4 (got %d)" % lost)

	# --- Dying: damage ends stability; Relentless Endurance only when dropping from above 0.
	var orcish = hero([{"id": "fighter", "level": 3, "subclass": "champion"}], {"race": "half_orc"})
	cs = board([[orcish, Vector2i(2, 2)]], [["goblin", "enemy", Vector2i(8, 2)]])
	var pc: Dictionary = cs[0]
	pc.resources.relentless_endurance.cur = 0
	eng.apply_damage(pc, [{"amount": pc.hp + 1, "type": "slashing"}], {}, {})
	check(pc.hp == 0 and not pc.death.dead, "the fighter drops to 0")
	pc.resources.relentless_endurance.cur = 1
	pc.death.stable = true
	eng.apply_damage(pc, [{"amount": 2, "type": "slashing"}], {}, {})
	check(pc.hp == 0 and int(pc.death.f) == 1, "Relentless Endurance doesn't lift a creature already at 0; damage is a failed save")
	check(not pc.death.stable, "damage at 0 HP makes a stable creature dying again")
	check(eng.res_left(pc, "relentless_endurance") == 1, "Relentless Endurance not spent")
	eng.apply_damage(pc, [{"amount": 2, "type": "slashing"}], {}, {"crit": true})
	check(int(pc.death.f) == 3 and pc.death.dead, "a critical hit at 0 HP is two failures (dead at 3)")

	# --- Exhaustion levels stack; 4 halves max HP; long rest removes one; 6 kills.
	var fig = hero([{"id": "fighter", "level": 5, "subclass": "champion"}])
	cs = board([[fig, Vector2i(2, 2)]], [["goblin", "enemy", Vector2i(8, 2)]])
	pc = cs[0]
	var mx: int = pc.max_hp
	for i in 4:
		eng.add_effect(pc, {"name": "Exhaustion", "src": "dm", "rounds": 99999, "tick_cid": "none", "mods": {"exhaustion": 1}, "exhaustion": true})
	check(eng.exhaustion(pc) == 4, "four DM exhaustion levels stack (got %d)" % eng.exhaustion(pc))
	check(pc.hp == mx / 2 and eng.eff_max_hp(pc) == mx / 2, "exhaustion 4 halves the HP maximum")
	eng.heal_creature(pc, 999, pc)
	check(pc.hp == mx / 2, "healing can't pass the halved maximum")
	eng.short_rest()
	check(eng.exhaustion(pc) == 4, "a short rest doesn't remove exhaustion")
	eng.long_rest()
	check(eng.exhaustion(pc) == 3 and pc.hp == mx, "a long rest removes one level and restores full HP")
	for i in 3:
		eng.add_effect(pc, {"name": "Exhaustion", "src": "dm", "rounds": 99999, "tick_cid": "none", "mods": {"exhaustion": 1}, "exhaustion": true})
	check(pc.death.dead, "exhaustion 6 is death")

	# --- Sneak Attack: once per turn, but every turn (opportunity attacks on the enemy's turn too);
	# thrown non-finesse weapons don't qualify.
	var rog = hero([{"id": "rogue", "level": 5, "subclass": "thief"}], {"base_scores": {"str": 10, "dex": 16, "con": 14, "int": 10, "wis": 10, "cha": 10},
		"equipment": {"armor": "leather", "shield": false, "weapons": ["rapier", "handaxe"], "weapon_bonus": 0, "armor_bonus": 0}})
	cs = board([[rog, Vector2i(2, 2)]], [["ogre", "enemy", Vector2i(3, 2)]])
	var rg: Dictionary = cs[0]
	ogre = cs[1]
	give_turn(rg)
	var rap = attack_named(rg, "w_rapier")
	var hx = attack_named(rg, "wt_handaxe")
	check(eng.weapon_damage(rg, ogre, hx, {"adv": 1}, {}).size() == 1, "thrown handaxe: no Sneak Attack")
	check(eng.weapon_damage(rg, ogre, rap, {"adv": 1}, {}).size() == 2, "rapier with advantage: Sneak Attack")
	check(eng.weapon_damage(rg, ogre, rap, {"adv": 1}, {}).size() == 1, "only once on the rogue's turn")
	give_turn(ogre)
	check(eng.weapon_damage(rg, ogre, rap, {"adv": 1}, {}).size() == 2, "Sneak Attack again on the ogre's turn (opportunity attack)")

	# --- Rage: no spellcasting, ends early without attacking or taking damage; frenzy exhausts.
	var bc = hero([{"id": "barbarian", "level": 3, "subclass": "berserker"}, {"id": "cleric", "level": 1, "subclass": "life"}],
		{"spells": {"cleric": ["sacred_flame", "cure_wounds", "bless"]}, "equipment": {"armor": "", "shield": false, "weapons": ["greataxe"], "weapon_bonus": 0, "armor_bonus": 0}})
	cs = board([[bc, Vector2i(2, 2)]], [["ogre", "enemy", Vector2i(10, 2)]])
	var bb: Dictionary = cs[0]
	ogre = cs[1]
	give_turn(bb)
	eng.execute(bb.id, "sp:bless", {"targets": [bb.id], "slot": 1})
	check(not bb.conc.is_empty(), "Bless gives concentration")
	eng.execute(bb.id, "rage", {})
	check(eng.has_tag(bb, "rage") and bb.conc.is_empty(), "raging ends concentration")
	check(not eng.find_action(bb, "sp:sacred_flame").enabled, "can't cast spells while raging")
	eng.end_turn()
	check(not eng.has_tag(bb, "rage"), "rage ends when the turn ends with no attack and no damage")
	give_turn(bb)
	eng.execute(bb.id, "rage", {})
	eng.apply_damage(bb, [{"amount": 1, "type": "fire"}], ogre, {})
	eng.end_turn()
	check(eng.has_tag(bb, "rage"), "taking damage keeps the rage going")
	bb.frenzied = true
	eng.remove_effects_where(bb, func(e): return e.get("tag", "") == "rage")
	give_turn(bb)
	check(eng.exhaustion(bb) == 1, "a frenzied rage leaves a level of exhaustion when it ends")

	# --- Short rest spends hit dice; long rest gives back half; Relentless Rage DC persists.
	fig = hero([{"id": "fighter", "level": 5, "subclass": "champion"}])
	cs = board([[fig, Vector2i(2, 2)]], [["goblin", "enemy", Vector2i(8, 2)]])
	pc = cs[0]
	pc.rr_uses = 2
	eng.end_combat()
	eng.start_combat()
	check(int(pc.get("rr_uses", 0)) == 2, "Relentless Rage DC isn't reset by a new fight")
	pc.hp = 1
	eng.short_rest()
	var spent: int = int(pc.hd_used.get("10", 0))
	check(spent >= 1 and pc.hp > 1 and pc.hp <= pc.max_hp, "short rest spends hit dice to heal (spent %d, hp %d)" % [spent, pc.hp])
	check(int(pc.get("rr_uses", 0)) == 0, "a short rest resets Relentless Rage")
	pc.hd_used["10"] = 5
	pc.hp = 1
	eng.short_rest()
	check(pc.hp == 1, "no hit dice left: a short rest heals nothing")
	eng.long_rest()
	check(int(pc.hd_used["10"]) == 3, "long rest regains half the hit dice (2 of 5; got %d used)" % int(pc.hd_used["10"]))

	# --- Being incapacitated ends concentration.
	var clr = hero([{"id": "cleric", "level": 3, "subclass": "life"}], {"spells": {"cleric": ["bless", "sacred_flame"]}})
	cs = board([[clr, Vector2i(2, 2)]], [["goblin", "enemy", Vector2i(8, 2)]])
	var cl: Dictionary = cs[0]
	give_turn(cl)
	eng.execute(cl.id, "sp:bless", {"targets": [cl.id], "slot": 1})
	check(not cl.conc.is_empty(), "cleric concentrates on Bless")
	eng.add_effect(cl, {"name": "Stunned", "cond": "stunned", "src": "dm", "rounds": 1, "tick_cid": "none"})
	check(cl.conc.is_empty(), "a stunned caster loses concentration")

	# --- SRD exhaustion immunities (skeletons, ghosts, elementals...); zombies aren't immune.
	cs = board([], [["skeleton", "enemy", Vector2i(2, 2)], ["zombie", "enemy", Vector2i(4, 2)], ["fire_elemental", "enemy", Vector2i(6, 2)]])
	for m in cs:
		eng.add_effect(m, {"name": "Exhaustion", "src": "dm", "rounds": 99999, "tick_cid": "none", "mods": {"exhaustion": 1}, "exhaustion": true})
	check(eng.exhaustion(cs[0]) == 0 and eng.exhaustion(cs[2]) == 0, "skeletons and fire elementals are immune to exhaustion")
	check(eng.exhaustion(cs[1]) == 1, "zombies can be exhausted")

	print("AUDIT5E DONE passed=%d failed=%d" % [passes, fails])
	get_tree().quit(1 if fails > 0 else 0)
