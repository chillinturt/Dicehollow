extends Node
## Playtest regressions for Wizard, Cleric and Paladin (and the shared rules they lean on).
## Run: Godot --headless --path . res://tests/class_test.tscn   (exit code 1 on failure)

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

func log_text() -> String:
	return "\n".join(eng.s.get("log", []))

func wizard(level := 5, sub := "evocation", armor := "") -> Dictionary:
	var w = Rules.new_character()
	w.merge({"name": "Wiz", "race": "human", "background": "sage",
		"base_scores": {"str": 8, "dex": 14, "con": 14, "int": 16, "wis": 12, "cha": 10},
		"classes": [{"id": "wizard", "level": level, "subclass": sub}],
		"spells": {"wizard": ["fire_bolt", "shield", "magic_missile", "mage_armor", "misty_step", "fireball", "hold_person", "dispel_magic"]},
		"equipment": {"armor": armor, "shield": false, "weapons": ["quarterstaff", "dagger"]}}, true)
	return w

func paladin(oath: String, level := 5) -> Dictionary:
	var p = Rules.new_character()
	p.merge({"name": "Pally", "race": "human", "background": "noble",
		"base_scores": {"str": 16, "dex": 10, "con": 14, "int": 8, "wis": 10, "cha": 16},
		"classes": [{"id": "paladin", "level": level, "subclass": oath}], "fighting_styles": ["defense"],
		"spells": {"paladin": ["bless", "cure_wounds", "shield_of_faith", "dispel_magic"]},
		"equipment": {"armor": "chain_mail", "shield": true, "weapons": ["longsword"]}}, true)
	return p

func cleric(level := 5, sub := "twilight") -> Dictionary:
	var c = Rules.new_character()
	c.merge({"name": "Cleric", "race": "human", "background": "acolyte",
		"base_scores": {"str": 12, "dex": 10, "con": 14, "int": 8, "wis": 16, "cha": 10},
		"classes": [{"id": "cleric", "level": level, "subclass": sub}],
		"spells": {"cleric": ["sacred_flame", "toll_the_dead", "guidance", "bless", "healing_word", "cure_wounds", "spiritual_weapon", "spirit_guardians", "dispel_magic"]},
		"equipment": {"armor": "chain_mail", "shield": true, "weapons": ["mace"]}}, true)
	return c

func _ready() -> void:
	# ------------------------------------------------------------ area damage is rolled once
	var same = true
	for i in 8:
		var cs = board([[wizard(), Vector2i(2, 6)]], [["ogre", "enemy", Vector2i(12, 6)], ["ogre", "enemy", Vector2i(14, 6)]])
		var wiz = cs[0]
		give_turn(wiz)
		eng.execute(wiz.id, "sp:fireball", {"cell": Vector2i(13, 6), "slot": 3})
		var a: int = cs[1].max_hp - cs[1].hp
		var b: int = cs[2].max_hp - cs[2].hp
		if not (a == b or a == b / 2 or b == a / 2):
			same = false
	check(same, "Fireball rolls one damage total for every creature (each takes all or half of it)")

	# ------------------------------------------------------------ Destroy Undead destroys outright
	var destroyed = false
	var clean_log = true
	for i in 25:
		var cs = board([[cleric(), Vector2i(4, 6)]], [["zombie", "enemy", Vector2i(7, 6)]])
		give_turn(cs[0])
		eng.s.log = []
		eng.execute(cs[0].id, "turn_undead", {"targets": [cs[0].id]})
		if cs[1].dead:
			destroyed = true
			clean_log = not log_text().contains("CON save") and not log_text().contains("damage (")
			break
	check(destroyed, "a zombie (CR 1/4) that fails against a 5th-level cleric's Turn Undead is destroyed")
	check(clean_log, "Destroy Undead deals no damage roll and allows no Undead Fortitude save")

	# ------------------------------------------------------------ Undead Fortitude vs radiant spells
	var cs2 = board([[cleric(), Vector2i(4, 6)]], [["zombie", "enemy", Vector2i(7, 6)]])
	var zom = cs2[1]
	zom.hp = 3
	eng.s.log = []
	eng.apply_damage(zom, [{"amount": 8, "type": "radiant"}], cs2[0], {"spell": true})
	check(zom.dead and not log_text().contains("Undead Fortitude"), "radiant spell damage bypasses Undead Fortitude")

	# ------------------------------------------------------------ prone after dropping, still prone when healed
	cs2 = board([[paladin("devotion"), Vector2i(4, 6)], [cleric(), Vector2i(3, 6)]], [["orc", "enemy", Vector2i(5, 6)]])
	var pal = cs2[0]
	var cle = cs2[1]
	eng.apply_damage(pal, [{"amount": pal.hp + 2, "type": "slashing"}], cs2[2], {"attack": true, "melee": true})
	check(pal.hp == 0 and eng.has_cond(pal, "prone"), "a PC dropped to 0 HP is prone")
	give_turn(cle)
	eng.execute(cle.id, "sp:healing_word", {"targets": [pal.id], "slot": 1})
	check(pal.hp > 0 and eng.has_cond(pal, "prone"), "healed back up, the PC is still prone and must stand")
	give_turn(pal)
	check(eng.find_action(pal, "stand").enabled, "and can spend half its speed to stand")

	# ------------------------------------------------------------ Twilight Sanctuary includes the cleric
	cs2 = board([[cleric(), Vector2i(4, 6)], [paladin("devotion"), Vector2i(5, 6)]], [["orc", "enemy", Vector2i(18, 6)]])
	cle = cs2[0]
	give_turn(cle)
	eng.execute(cle.id, "twilight_sanctuary", {"targets": [cle.id]})
	eng.end_turn()
	check(int(cle.temp_hp) > 0, "Twilight Sanctuary grants the cleric temp HP too (got %d)" % int(cle.temp_hp))

	# ------------------------------------------------------------ Lay on Hands: chosen amount, limits
	cs2 = board([[paladin("vengeance"), Vector2i(4, 6)], [cleric(), Vector2i(5, 6)]], [["orc", "enemy", Vector2i(18, 6)], ["zombie", "party", Vector2i(4, 7)]])
	pal = cs2[0]
	cle = cs2[1]
	cle.hp = 0
	cle.death = {"s": 0, "f": 1, "stable": false, "dead": false}
	give_turn(pal)
	eng.execute(pal.id, "lay_on_hands", {"targets": [cle.id], "opts": {"amount": 1}})
	check(cle.hp == 1 and eng.res_left(pal, "lay_on_hands") == 24, "Lay on Hands for 1 HP spends 1 point (hp %d, pool %d)" % [cle.hp, eng.res_left(pal, "lay_on_hands")])
	give_turn(pal)
	cle.hp = cle.max_hp
	check(not eng.execute(pal.id, "lay_on_hands", {"targets": [cle.id]}) and eng.res_left(pal, "lay_on_hands") == 24 and pal.turn.action == 1, "Lay on Hands on a full-HP ally is refused without spending anything")
	cs2[3].hp = 5
	check(not eng.execute(pal.id, "lay_on_hands", {"targets": [cs2[3].id]}), "Lay on Hands has no effect on undead")
	eng.add_effect(cle, {"name": "Poisoned", "cond": "poisoned", "src": cs2[2].id, "rounds": 10, "tick_cid": cs2[2].id})
	cle.hp = cle.max_hp - 3
	eng.execute(pal.id, "lay_on_hands", {"targets": [cle.id], "opts": {"cure": true}})
	check(not eng.has_cond(cle, "poisoned") and eng.res_left(pal, "lay_on_hands") == 19, "Lay on Hands neutralizes poison for 5 points")
	cs2[3].hp = 5
	give_turn(cle)
	var zhp: int = cs2[3].hp
	eng.execute(cle.id, "sp:cure_wounds", {"targets": [cs2[3].id], "slot": 1})
	check(cs2[3].hp == zhp, "Cure Wounds has no effect on an allied undead")

	# ------------------------------------------------------------ Paladin Channel Divinity options
	cs2 = board([[paladin("devotion", 7), Vector2i(4, 6)]], [["zombie", "enemy", Vector2i(6, 6)]])
	pal = cs2[0]
	give_turn(pal)
	check(eng.find_action(pal, "turn_the_unholy").get("enabled", false), "Devotion paladin has Turn the Unholy")
	eng.execute(pal.id, "turn_the_unholy", {"targets": [pal.id]})
	check(eng.res_left(pal, "channel_divinity") == 0, "Turn the Unholy spends Channel Divinity")
	var ch = cs2[1]
	eng.add_effect(pal, {"name": "Charmed", "cond": "charmed", "src": ch.id, "rounds": 10, "tick_cid": ch.id})
	check(not eng.has_cond(pal, "charmed"), "Aura of Devotion: a 7th-level Devotion paladin can't be charmed")
	cs2 = board([[paladin("vengeance"), Vector2i(4, 6)]], [["orc", "enemy", Vector2i(8, 6)]])
	pal = cs2[0]
	give_turn(pal)
	eng.execute(pal.id, "abjure_enemy", {"targets": [cs2[1].id]})
	check(eng.eff_speed(cs2[1]) <= 15, "Abjure Enemy stops or halves the target's speed (now %d)" % eng.eff_speed(cs2[1]))

	# ------------------------------------------------------------ short rest ends short spells
	cs2 = board([[cleric(), Vector2i(4, 6)], [wizard(), Vector2i(3, 6)]], [["orc", "enemy", Vector2i(14, 6)]])
	cle = cs2[0]
	var wiz2 = cs2[1]
	give_turn(cle)
	eng.execute(cle.id, "sp:spirit_guardians", {"targets": [cle.id], "slot": 3})
	eng.execute(cle.id, "sp:spiritual_weapon", {"cell": Vector2i(13, 6), "targets": [cs2[2].id], "slot": 2})
	give_turn(wiz2)
	eng.execute(wiz2.id, "sp:mage_armor", {"targets": [wiz2.id], "slot": 1})
	eng.short_rest()
	check(cle.conc.is_empty() and not eng.has_tag(cle, "spiritual_weapon"), "a short rest ends Spirit Guardians and Spiritual Weapon")
	check(eng.has_tag(wiz2, "mage_armor"), "a short rest keeps 8-hour Mage Armor")

	# ------------------------------------------------------------ armor without proficiency
	cs2 = board([[wizard(5, "evocation", "chain_mail"), Vector2i(4, 6)]], [["orc", "enemy", Vector2i(5, 6)]])
	var tin = cs2[0]
	give_turn(tin)
	check(not eng.find_action(tin, "sp:fire_bolt").enabled, "a wizard in chain mail can't cast spells")
	check(eng.attack_advantage(tin, cs2[1], true, tin.attacks[0]) < 0, "and attacks at disadvantage")

	# ------------------------------------------------------------ Dispel Magic
	cs2 = board([[cleric(), Vector2i(4, 6)], [paladin("devotion"), Vector2i(5, 6)]], [["orc", "enemy", Vector2i(12, 6)]])  # a mage would Counterspell the dispel
	cle = cs2[0]
	pal = cs2[1]
	var mage = cs2[2]
	eng.start_concentration(mage, "hold_person", "Hold Person")
	eng.add_effect(pal, {"name": "Held", "cond": "paralyzed", "src": mage.id, "spell": "hold_person", "conc": true, "rounds": 10, "tick_cid": mage.id})
	eng.add_effect(pal, {"name": "Blessed", "src": cle.id, "spell": "bless", "conc": true, "mods": {"attack_dice": "1d4"}, "rounds": 10, "tick_cid": cle.id})
	give_turn(cle)
	eng.execute(cle.id, "sp:dispel_magic", {"targets": [pal.id], "slot": 3})
	check(not eng.has_cond(pal, "paralyzed"), "Dispel Magic ends Hold Person on an ally")
	check(mage.conc.is_empty(), "and the enemy caster's concentration with it")
	check(pal.effects.any(func(e): return e.get("name", "") == "Blessed"), "but leaves the ally's friendly Bless alone")

	# ------------------------------------------------------------ Harm's max HP cut ends on a long rest
	cs2 = board([[paladin("devotion"), Vector2i(4, 6)]], [["orc", "enemy", Vector2i(18, 6)]])
	pal = cs2[0]
	var full: int = pal.max_hp
	pal.max_hp -= 10
	pal.max_hp_cut = 10
	eng.end_combat()
	eng.long_rest()
	check(pal.max_hp == full and pal.hp == full, "a long rest restores the max HP Harm took away")

	# ------------------------------------------------------------ Divine Smite is chosen after the hit
	var asked = false
	var smote = false
	var declined_ok = false
	for i in 40:
		cs2 = board([[paladin("devotion"), Vector2i(4, 6)]], [["ogre", "enemy", Vector2i(5, 6)]])
		pal = cs2[0]
		var ogre = cs2[1]
		ogre.hp = 500
		ogre.max_hp = 500
		give_turn(pal)
		eng.interactive = true
		eng.execute(pal.id, "atk:" + pal.attacks[0].id, {"targets": [ogre.id]})
		eng.interactive = false
		var p: Dictionary = eng.s.get("pending_hit", {})
		if p.is_empty():
			continue  # missed
		asked = true
		check(ogre.hp == 500, "the hit's damage waits for the smite decision")
		check(p.choices.get("smite", []) == [1, 2], "the choice offers each slot level the paladin has (%s)" % str(p.choices.get("smite", [])))
		var used_before: int = int(pal.slots_used[1])
		if i % 2 == 0:
			eng.execute(pal.id, "hit_choice", {"smite": 2})
			smote = ogre.hp < 500 and int(pal.slots_used[1]) == used_before + 1 and log_text().contains("Divine Smite")
		else:
			# Doing anything else first settles the hit without a smite.
			eng.end_turn()
			declined_ok = ogre.hp < 500 and int(pal.slots_used[0]) == 0 and int(pal.slots_used[1]) == 0
		if smote and declined_ok:
			break
	check(asked, "a player's paladin is asked about Divine Smite after a melee hit")
	check(smote, "choosing a level 2 smite spends that slot and adds the radiant damage")
	check(declined_ok, "moving on without answering applies the hit with no smite")
	cs2 = board([[paladin("devotion"), Vector2i(4, 6)]], [["ogre", "enemy", Vector2i(5, 6)]])
	pal = cs2[0]
	give_turn(pal)
	eng.execute(pal.id, "atk:" + pal.attacks[0].id, {"targets": [cs2[1].id]})
	check(eng.s.get("pending_hit", {}).is_empty(), "the AI and scripted attacks never wait for an answer")

	# ------------------------------------------------------------ Revivify: within a minute only
	cs2 = board([[cleric(), Vector2i(4, 6)], [paladin("devotion"), Vector2i(5, 6)]], [["orc", "enemy", Vector2i(18, 6)]])
	cle = cs2[0]
	pal = cs2[1]
	cle.casting[0].spells.append("revivify")
	pal.hp = 0
	eng._kill(pal, "test")
	eng.s.clock = int(eng.s.clock) + 11
	give_turn(cle)
	var slots_before: int = int(cle.slots_used[2])
	check(not eng.execute(cle.id, "sp:revivify", {"targets": [pal.id], "slot": 3}) and int(cle.slots_used[2]) == slots_before, "Revivify fails on a creature dead over a minute, without spending the slot")
	pal.death.died_at = int(eng.s.clock) - 9
	check(eng.execute(cle.id, "sp:revivify", {"targets": [pal.id], "slot": 3}) and pal.hp == 1, "Revivify works within a minute of death")
	cs2 = board([[paladin("devotion"), Vector2i(5, 6)]], [["orc", "enemy", Vector2i(18, 6)]])
	pal = cs2[0]
	pal.hp = 0
	eng._kill(pal, "test")
	for r in 11:
		eng.end_turn()
		eng.end_turn()
	check(not eng.revivable(pal), "eleven combat rounds later the minute has passed (clock %d)" % int(eng.s.clock))

	# ------------------------------------------------------------ Arcane Recovery is the wizard's choice
	cs2 = board([[wizard(), Vector2i(4, 6)]], [["orc", "enemy", Vector2i(18, 6)]])
	var wz = cs2[0]
	wz.slots_used[0] = 2
	wz.slots_used[2] = 1
	eng.short_rest()
	check(int(wz.slots_used[0]) == 2 and int(wz.slots_used[2]) == 1 and eng.res_left(wz, "arcane_recovery") == 1, "a short rest doesn't spend Arcane Recovery by itself")
	check(not eng.find_action(wz, "arcane_rec_3").is_empty() and not eng.find_action(wz, "arcane_rec_1").is_empty(), "after the rest the wizard can choose which slots to recover")
	eng.execute(wz.id, "arcane_rec_1", {})
	eng.execute(wz.id, "arcane_rec_1", {})
	check(int(wz.slots_used[0]) == 0 and eng.res_left(wz, "arcane_recovery") == 0, "recovering two 1st-level slots spends the day's use")
	check(eng.find_action(wz, "arcane_rec_3").is_empty(), "and leaves only 1 level of budget, not enough for a 3rd-level slot")
	eng.start_combat()
	check(eng.find_action(wz, "arcane_rec_1").is_empty(), "the leftover budget is gone once a fight starts")

	# ------------------------------------------------------------ Turned undead run away
	var ran = false
	for i in 20:
		cs2 = board([[cleric(), Vector2i(4, 6)]], [["zombie", "enemy", Vector2i(6, 6)]])
		cle = cs2[0]
		var z = cs2[1]
		z.cr = 5  # too tough to be destroyed
		for ab in ["str", "dex", "con", "int", "wis", "cha"]:
			z.save_bonus[ab] = -100
		give_turn(cle)
		eng.execute(cle.id, "turn_undead", {"targets": [cle.id]})
		if not eng.has_tag(z, "turned"):
			continue
		check(not eng.is_incapacitated(z), "a turned creature isn't simply incapacitated")
		check(not eng.can_react(z), "a turned creature can't take reactions")
		var before: int = eng.dist(cle, z)
		give_turn(z)
		ran = eng.dist(cle, z) > before + 20 and int(z.turn.action) == 0
		break
	check(ran, "a turned zombie spends its turn Dashing away from the cleric")

	# ------------------------------------------------------------ Wizard spellbook vs prepared spells
	var bw = wizard()
	bw.spellbook = ["shield", "magic_missile", "fireball", "sleep"]
	var bst = Rules.derive(bw)
	var went: Dictionary = bst.casting[0]
	check("fireball" in went.spells and not "misty_step" in went.spells, "only spells written in the spellbook can be prepared")
	check("sleep" in went.spellbook and not "sleep" in went.spells, "a spell in the book isn't castable until it's prepared")
	check("fire_bolt" in went.spells, "cantrips don't need the spellbook")
	check(Rules.wizard_spellbook(wizard()).has("misty_step"), "older wizards without a spellbook keep all their spells")

	print("CLASS TEST DONE passed=%d failed=%d" % [passes, fails])
	get_tree().quit(1 if fails > 0 else 0)
