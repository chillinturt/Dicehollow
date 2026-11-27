extends Node
## Checks for the spells fixed in docs/SPELL_AUDIT.md (one block per spell or shared mechanic).
## Run: Godot --headless --path . res://tests/spell_audit_test.tscn  (exit code 1 on failure)

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

## Cast without starting a new turn (for a second cast or a repeat on the same turn).
func cast_now(c: Dictionary, sid: String, params: Dictionary) -> bool:
	teach(c, sid)
	return eng.execute(c.id, "sp:" + sid, params)

func rig_saves(t: Dictionary, fail: bool) -> void:
	for ab in ["str", "dex", "con", "int", "wis", "cha"]:
		t.save_bonus[ab] = -100 if fail else 100
	t.legendary_res = 0

## Stop an enemy caster from countering the spell under test.
func no_counter(c: Dictionary) -> void:
	for e in c.casting:
		e.spells.erase("counterspell")

func tough(t: Dictionary, hp := 500) -> void:
	t.max_hp = hp
	t.hp = hp

func has_effect(c: Dictionary, name: String) -> bool:
	for e in c.effects:
		if e.get("name", "") == name:
			return true
	return false

func effect_named(c: Dictionary, name: String) -> Dictionary:
	for e in c.effects:
		if e.get("name", "") == name:
			return e
	return {}

## The id of `c`'s repeat action for spell `sid`, or "".
func repeat_id(c: Dictionary, sid: String) -> String:
	for a in eng.get_actions(c):
		if str(a.id).begins_with("rp:") and a.get("spell", "") == sid:
			return a.id
	return ""

func repeat_action(c: Dictionary, sid: String) -> Dictionary:
	var rid = repeat_id(c, sid)
	return eng.find_action(c, rid) if rid != "" else {}

func melee_of(c: Dictionary) -> Dictionary:
	for a in eng.attacks_of(c):
		if a.get("melee", false):
			return a
	return {}

func ranged_of(c: Dictionary) -> Dictionary:
	for a in eng.attacks_of(c):
		if not a.get("melee", true):
			return a
	return {}

## Weapon attack from `c` on `t` that hits (AC lowered; retries a natural 1).
func land_hit(c: Dictionary, t: Dictionary, atk: Dictionary) -> void:
	var ac = t.ac
	t.ac = -100
	for i in 10:
		if eng._attack_with(c, t, atk).get("hit", false):
			break
	t.ac = ac

func _ready() -> void:
	_tier1()
	_tier2_smites_and_ticks()
	_tier2_control()
	_tier2_defences()
	_tier2_riders_and_heals()
	_tier3_repeats()
	_tier4()
	print("SPELL AUDIT DONE passed=%d failed=%d" % [passes, fails])
	get_tree().quit(1 if fails > 0 else 0)

# ---------------------------------------------------------------- Tier 1
func _tier1() -> void:
	# --- Darkness: creatures that can't see each other roll attacks normally; no sight into it.
	var cs = board([["mage", "party", Vector2i(2, 2)], ["knight", "enemy", Vector2i(8, 2)], ["knight", "enemy", Vector2i(14, 2)]])
	var mage: Dictionary = cs[0]
	var kn: Dictionary = cs[1]
	cast(mage, "darkness", {"cell": Vector2i(8, 2)})
	check(not eng.can_see(mage, kn), "Darkness: can't see a creature inside")
	check(eng.attack_advantage(mage, kn, false) == 0 and eng.obscured_between(mage, kn) and eng.obscured_between(kn, mage), "Darkness: attacks in or out of it cancel to a straight roll")
	check(eng.can_see(mage, cs[2]), "Darkness: creatures outside it still see each other")
	# --- Fog Cloud grows 20 ft per slot level.
	cs = board([["mage", "party", Vector2i(2, 2)]])
	cast(cs[0], "fog_cloud", {"cell": Vector2i(10, 5), "slot": 2})
	check(eng.s.zones.size() == 1 and eng.s.zones[0].cells.has(Vector2i(10, 1)) and eng.s.zones[0].data.get("obscure", "") == "fog", "Fog Cloud at 2nd level fills a 40-ft radius")
	# --- Silence: no verbal spells inside, and no thunder damage.
	cs = board([["mage", "party", Vector2i(5, 5)], ["mage", "enemy", Vector2i(6, 5)]])
	no_counter(cs[1])
	cast(cs[0], "silence", {"cell": Vector2i(6, 5)})
	teach(cs[1], "fire_bolt")
	give_turn(cs[1])
	var fb = eng.find_action(cs[1], "sp:fire_bolt")
	check(not fb.enabled and fb.reason == "Silenced", "Silence: a caster inside can't cast verbal spells")
	var before: int = cs[1].hp
	eng.apply_damage(cs[1], [{"amount": 10, "type": "thunder"}], cs[0], {"spell": true})
	check(cs[1].hp == before, "Silence: no thunder damage inside")
	# --- Absorb Elements: resist the fire as it hits and charge the next melee hit.
	cs = board([["mage", "party", Vector2i(5, 5)], ["mage", "enemy", Vector2i(6, 5)]])
	teach(cs[0], "absorb_elements")
	tough(cs[0])
	eng.apply_damage(cs[0], [{"amount": 20, "type": "fire"}], cs[1], {"spell": true})
	check(cs[0].hp == 490 and int(cs[0].slots_used[0]) == 1, "Absorb Elements halves the triggering fire damage (hp %d)" % cs[0].hp)
	check(has_effect(cs[0], "Absorbed Fire"), "Absorb Elements charges the next melee hit")
	# --- Silvery Barbs: an enemy's successful save is rerolled, and an ally gets advantage.
	cs = board([["mage", "party", Vector2i(5, 5)], ["knight", "enemy", Vector2i(7, 5)], ["knight", "party", Vector2i(4, 5)]])
	teach(cs[0], "silvery_barbs")
	check(eng._silvery_barbs(cs[1], cs[2], 60) and int(cs[0].slots_used[0]) == 1, "Silvery Barbs fires as a reaction and spends a slot")
	check(effect_named(cs[2], "Silvery Barbs").get("one_roll", false), "Silvery Barbs gives the ally advantage on its next roll")
	# --- Temporal Shunt: an attack on a badly hurt ally is wasted and the attacker vanishes.
	cs = board([["mage", "party", Vector2i(2, 5)], ["knight", "enemy", Vector2i(7, 5)], ["knight", "party", Vector2i(6, 5)]])
	teach(cs[0], "temporal_shunt")
	cs[2].hp = 5
	rig_saves(cs[1], true)
	give_turn(cs[1])
	var r = eng.roll_attack(cs[1], cs[2], melee_of(cs[1]), {"melee": true})
	check(not r.hit and eng.has_cond(cs[1], "banished"), "Temporal Shunt wastes the attack and removes the attacker")
	# --- Gust: a Medium creature is pushed 5 ft; a Large one isn't.
	cs = board([["mage", "party", Vector2i(2, 5)], ["knight", "enemy", Vector2i(4, 5)], ["ogre", "enemy", Vector2i(4, 1)]])
	rig_saves(cs[1], true)
	rig_saves(cs[2], true)
	cast(cs[0], "gust", {"targets": [cs[1].id]})
	check(cs[1].pos == Vector2i(5, 5), "Gust pushes a Medium creature 5 ft (at %s)" % str(cs[1].pos))
	cast(cs[0], "gust", {"targets": [cs[2].id]})
	check(cs[2].pos == Vector2i(4, 1), "Gust doesn't move a Large creature")
	# --- Vortex Warp: the target is teleported to the chosen point.
	cs = board([["mage", "party", Vector2i(2, 5)], ["knight", "enemy", Vector2i(4, 5)]])
	rig_saves(cs[1], true)
	cast(cs[0], "vortex_warp", {"targets": [cs[1].id], "cell": Vector2i(15, 8)})
	check(cs[1].pos == Vector2i(15, 8), "Vortex Warp teleports the target (at %s)" % str(cs[1].pos))
	# --- Summon Beast: a bestial spirit with stats from the slot joins after the caster.
	cs = board([["mage", "party", Vector2i(2, 5)], ["knight", "enemy", Vector2i(10, 5)]])
	cast(cs[0], "summon_beast", {"cell": Vector2i(4, 5), "slot": 4})
	var spirit: Dictionary = {}
	for o in eng.all_combatants():
		if o.get("summoner", "") == cs[0].id:
			spirit = o
	check(not spirit.is_empty() and spirit.ac == 15 and int(spirit.vals.attacks) == 2 and spirit.max_hp == 40, "Summon Beast at 4th level: AC 15, 40 HP, two attacks")
	check(eng.s.order.find(spirit.get("id", "")) == eng.s.order.find(cs[0].id) + 1, "the spirit acts right after the caster")
	eng.end_concentration(cs[0], true)
	check(spirit.get("dead", false), "the spirit vanishes when concentration ends")
	# --- Warding Wind: the ground around the caster is difficult for others, not for the caster.
	cs = board([["mage", "party", Vector2i(5, 5)], ["knight", "enemy", Vector2i(9, 5)]])
	cast(cs[0], "warding_wind", {"targets": [cs[0].id]})
	check(eng.is_difficult(Vector2i(6, 5), cs[1]) and not eng.is_difficult(Vector2i(6, 5), cs[0]), "Warding Wind makes nearby ground difficult for others")
	check(eng.attack_advantage(cs[1], cs[0], false, {"range": 100}) < 0 and eng.attack_advantage(cs[1], cs[0], true) == 0, "Warding Wind: ranged attacks at disadvantage, melee unaffected")

# ---------------------------------------------------------------- Tier 2
func _tier2_smites_and_ticks() -> void:
	# --- Zephyr Strike: no opportunity attacks, and one charged attack that keeps concentration.
	var cs = board([["knight", "party", Vector2i(5, 5)], ["ogre", "enemy", Vector2i(6, 5)]])
	var kn: Dictionary = cs[0]
	var ogre: Dictionary = cs[1]
	tough(ogre)
	cast(kn, "zephyr_strike", {"targets": [kn.id]})
	check(eng.mod_any(kn, "no_provoke"), "Zephyr Strike: movement provokes no opportunity attacks")
	land_hit(kn, ogre, melee_of(kn))
	check(not has_effect(kn, "Zephyr Strike (charge)") and kn.conc.get("spell", "") == "zephyr_strike", "Zephyr Strike's charge is spent once, concentration stays")
	land_hit(kn, ogre, melee_of(kn))
	check(has_effect(kn, "Zephyr Strike"), "Zephyr Strike's OA immunity lasts after the charge")
	# --- Blinding Smite: blinded on a failed CON save, repeating the save.
	cs = board([["knight", "party", Vector2i(5, 5)], ["ogre", "enemy", Vector2i(6, 5)]])
	tough(cs[1])
	rig_saves(cs[1], true)
	cast(cs[0], "blinding_smite", {"targets": [cs[0].id]})
	land_hit(cs[0], cs[1], melee_of(cs[0]))
	var bl = effect_named(cs[1], "Blinding Smite")
	check(bl.get("cond", "") == "blinded" and bl.get("save_ends", {}).get("ability", "") == "con", "Blinding Smite blinds, with a CON save each turn")
	# --- Staggering Smite: disadvantage and no reactions on a failed WIS save; the spell ends.
	cs = board([["knight", "party", Vector2i(5, 5)], ["ogre", "enemy", Vector2i(6, 5)]])
	tough(cs[1])
	rig_saves(cs[1], true)
	cast(cs[0], "staggering_smite", {"targets": [cs[0].id]})
	land_hit(cs[0], cs[1], melee_of(cs[0]))
	check(eng.mod_any(cs[1], "disadvantage_attack") and eng.mod_any(cs[1], "no_reactions") and cs[0].conc.is_empty(), "Staggering Smite staggers the target")
	# --- Banishing Smite: a target left at 50 HP or fewer is banished.
	cs = board([["knight", "party", Vector2i(5, 5)], ["ogre", "enemy", Vector2i(6, 5)]])
	cs[1].max_hp = 200
	cs[1].hp = 30
	cs[1].resist = []
	cast(cs[0], "banishing_smite", {"targets": [cs[0].id]})
	cs[1].hp = 80
	land_hit(cs[0], cs[1], melee_of(cs[0]))
	check(cs[1].hp > 50 or eng.has_cond(cs[1], "banished"), "Banishing Smite banishes a target at 50 HP or fewer")
	# --- Immolation: burns at the end of each of the target's turns until it saves.
	cs = board([["mage", "party", Vector2i(2, 5)], ["ogre", "enemy", Vector2i(8, 5)]])
	tough(cs[1])
	rig_saves(cs[1], true)
	cast(cs[0], "immolation", {"targets": [cs[1].id], "slot": 5})
	give_turn(cs[1])
	var hp1: int = cs[1].hp
	eng.end_turn()
	check(cs[1].hp < hp1 and has_effect(cs[1], "Immolated"), "Immolation burns at the end of the target's turn")
	# --- Vitriolic Sphere: 5d4 more at the end of the target's next turn, once.
	cs = board([["mage", "party", Vector2i(2, 5)], ["ogre", "enemy", Vector2i(8, 5)]])
	tough(cs[1])
	rig_saves(cs[1], true)
	cast(cs[0], "vitriolic_sphere", {"cell": Vector2i(8, 5), "slot": 4})
	give_turn(cs[1])
	var hp2: int = cs[1].hp
	eng.end_turn()
	check(cs[1].hp < hp2 and not has_effect(cs[1], "Acid-soaked"), "Vitriolic Sphere's lingering acid lands once")
	# --- Tasha's Caustic Brew: no damage on casting, 2d4 at the start of each turn, scraped off with an action.
	cs = board([["mage", "party", Vector2i(2, 5)], ["ogre", "enemy", Vector2i(6, 5)]])
	tough(cs[1])
	rig_saves(cs[1], true)
	cast(cs[0], "tashas_caustic_brew", {"cell": Vector2i(6, 5)})
	check(cs[1].hp == 500 and has_effect(cs[1], "Caustic Acid"), "Caustic Brew covers the target without hurting it at once")
	give_turn(cs[1])
	check(cs[1].hp < 500, "Caustic Brew burns at the start of the target's turn")
	eng.execute(cs[1].id, "escape", {})
	check(not has_effect(cs[1], "Caustic Acid"), "an action scrapes the acid off")
	# --- Weird: damage only at the end of turns; a successful save frees that creature, not the others.
	cs = board([["mage", "party", Vector2i(2, 5)], ["ogre", "enemy", Vector2i(10, 5)], ["ogre", "enemy", Vector2i(10, 7)]])
	tough(cs[1])
	tough(cs[2])
	rig_saves(cs[1], true)
	rig_saves(cs[2], true)
	cast(cs[0], "weird", {"cell": Vector2i(10, 6)})
	check(cs[1].hp == 500 and eng.has_cond(cs[1], "frightened"), "Weird frightens without damage on casting")
	rig_saves(cs[1], false)
	give_turn(cs[1])
	eng.end_turn()
	check(not has_effect(cs[1], "Terrified") and has_effect(cs[2], "Terrified") and cs[0].conc.get("spell", "") == "weird", "a save frees only that creature from Weird")
	# --- Phantasmal Force: 1d6 psychic on each of the target's turns; an INT check ends it.
	cs = board([["mage", "party", Vector2i(2, 5)], ["ogre", "enemy", Vector2i(8, 5)]])
	tough(cs[1])
	rig_saves(cs[1], true)
	cast(cs[0], "phantasmal_force", {"targets": [cs[1].id]})
	give_turn(cs[1])
	check(cs[1].hp < 500 and int(effect_named(cs[1], "Phantasm").get("escape_dc", 0)) == int(cs[0].casting[0].dc), "Phantasmal Force hurts each turn and can be seen through")

func _tier2_control() -> void:
	# --- Hideous Laughter: prone and incapacitated; damage gives a new save instead of ending it.
	var cs = board([["mage", "party", Vector2i(2, 5)], ["knight", "enemy", Vector2i(8, 5)]])
	tough(cs[1])
	rig_saves(cs[1], true)
	cast(cs[0], "tashas_hideous_laughter", {"targets": [cs[1].id]})
	check(eng.has_cond(cs[1], "incapacitated") and eng.has_cond(cs[1], "prone"), "Hideous Laughter: prone and incapacitated")
	eng.apply_damage(cs[1], [{"amount": 5, "type": "fire"}], cs[0], {})
	check(eng.has_cond(cs[1], "incapacitated"), "damage doesn't end Hideous Laughter by itself")
	rig_saves(cs[1], false)
	eng.apply_damage(cs[1], [{"amount": 5, "type": "fire"}], cs[0], {})
	check(not eng.has_cond(cs[1], "incapacitated"), "a save after damage ends Hideous Laughter")
	# --- Dominate Person: the target fights for the caster until a save after damage.
	cs = board([["mage", "party", Vector2i(2, 5)], ["knight", "enemy", Vector2i(8, 5)]])
	tough(cs[1])
	rig_saves(cs[1], true)
	cast(cs[0], "dominate_person", {"targets": [cs[1].id]})
	check(cs[1].team == "party", "Dominate Person: the target joins the caster's side")
	rig_saves(cs[1], false)
	eng.apply_damage(cs[1], [{"amount": 5, "type": "fire"}], {}, {})
	check(cs[1].team == "enemy", "a save after damage ends the domination")
	cs = board([["mage", "party", Vector2i(2, 5)], ["wolf", "enemy", Vector2i(8, 5)]])
	rig_saves(cs[1], true)
	cast(cs[0], "dominate_person", {"targets": [cs[1].id]})
	check(cs[1].team == "enemy", "Dominate Person doesn't work on a beast")
	# --- Enervation: the caster can keep draining with its action, healing half.
	cs = board([["mage", "party", Vector2i(2, 5)], ["ogre", "enemy", Vector2i(8, 5)]])
	tough(cs[1])
	rig_saves(cs[1], true)
	cs[0].hp = 10
	cast(cs[0], "enervation", {"targets": [cs[1].id], "slot": 5})
	check(cs[0].hp > 10, "Enervation heals the caster for half the damage")
	give_turn(cs[0])
	var hp_e: int = cs[1].hp
	eng.execute(cs[0].id, "sustain_spell", {})
	check(cs[1].hp < hp_e, "Enervation drains again on a later turn")
	cs = board([["mage", "party", Vector2i(2, 5)], ["ogre", "enemy", Vector2i(8, 5)]])
	tough(cs[1])
	rig_saves(cs[1], false)
	cast(cs[0], "enervation", {"targets": [cs[1].id], "slot": 5})
	check(cs[0].conc.is_empty(), "a successful save ends Enervation")
	# --- Enlarge/Reduce: allies grow, enemies shrink on a failed save.
	cs = board([["mage", "party", Vector2i(2, 5)], ["knight", "party", Vector2i(3, 5)], ["knight", "enemy", Vector2i(8, 5)]])
	cast(cs[0], "enlarge_reduce", {"targets": [cs[1].id]})
	check(has_effect(cs[1], "Enlarged"), "Enlarge/Reduce enlarges an ally")
	rig_saves(cs[2], true)
	cast(cs[0], "enlarge_reduce", {"targets": [cs[2].id]})
	check(has_effect(cs[2], "Reduced") and not has_effect(cs[2], "Enlarged"), "Enlarge/Reduce shrinks an enemy")
	# --- Entangle: a creature that broke free isn't caught again just for staying in the plants.
	cs = board([["mage", "party", Vector2i(2, 5)], ["knight", "enemy", Vector2i(8, 5)]])
	rig_saves(cs[1], true)
	cast(cs[0], "entangle", {"cell": Vector2i(8, 5)})
	check(eng.has_cond(cs[1], "restrained"), "Entangle restrains on casting")
	eng.remove_effects_where(cs[1], func(e): return e.get("cond", "") == "restrained")
	give_turn(cs[1])
	check(not eng.has_cond(cs[1], "restrained") and eng.is_difficult(Vector2i(8, 5)), "Entangle doesn't re-catch a freed creature; the area stays difficult")
	# --- Cordon of Arrows: four shots, then it's spent.
	cs = board([["mage", "party", Vector2i(2, 5)], ["knight", "enemy", Vector2i(6, 5)]])
	tough(cs[1])
	rig_saves(cs[1], true)
	cast(cs[0], "cordon_of_arrows", {"cell": Vector2i(3, 5)})
	for i in 4:
		give_turn(cs[1])
		eng.end_turn()
	check(eng.s.zones.is_empty() and cs[1].hp < 500, "Cordon of Arrows fires four times, then it's spent")
	# --- Compelled Duel: disadvantage against others only; the target can't wander off.
	cs = board([["knight", "party", Vector2i(5, 5)], ["knight", "enemy", Vector2i(6, 5)], ["knight", "party", Vector2i(7, 5)]])
	rig_saves(cs[1], true)
	cast(cs[0], "compelled_duel", {"targets": [cs[1].id]})
	check(eng.attack_advantage(cs[1], cs[0], true) == 0 and eng.attack_advantage(cs[1], cs[2], true) < 0, "Compelled Duel: disadvantage against anyone but the caster")
	give_turn(cs[1])
	var reach = eng.reachable(cs[1], 60)
	check(not reach.has(Vector2i(14, 5)) and reach.has(Vector2i(10, 5)), "Compelled Duel: the target can't move more than 30 ft away")
	# --- Ray of Sickness: poisoned only on a failed CON save.
	cs = board([["mage", "party", Vector2i(2, 5)], ["ogre", "enemy", Vector2i(8, 5)]])
	tough(cs[1])
	cs[1].ac = -100
	rig_saves(cs[1], false)
	cast(cs[0], "ray_of_sickness", {"targets": [cs[1].id]})
	check(not eng.has_cond(cs[1], "poisoned"), "Ray of Sickness: a CON save avoids the poison")
	# --- Divine Word: what happens depends on current HP.
	cs = board([["priest", "party", Vector2i(5, 5)], ["knight", "enemy", Vector2i(6, 5)], ["knight", "enemy", Vector2i(6, 6)], ["knight", "enemy", Vector2i(4, 4)], ["knight", "enemy", Vector2i(5, 6)]])
	var hps = [60, 35, 25, 15]
	for i in 4:
		cs[i + 1].hp = hps[i]
		rig_saves(cs[i + 1], true)
	cast(cs[0], "divine_word", {"cell": Vector2i(6, 5)})
	check(cs[1].effects.is_empty(), "Divine Word: over 50 HP is unaffected")
	check(eng.has_cond(cs[2], "deafened") and eng.has_cond(cs[2], "blinded") and not eng.has_cond(cs[2], "stunned"), "Divine Word: 35 HP is deafened and blinded")
	check(eng.has_cond(cs[3], "stunned"), "Divine Word: 25 HP is stunned")
	check(not eng.alive(cs[4]), "Divine Word: 15 HP is killed")
	# --- Power Word Pain: only creatures with 100 HP or fewer.
	cs = board([["mage", "party", Vector2i(2, 5)], ["hill_giant", "enemy", Vector2i(8, 5)], ["knight", "enemy", Vector2i(8, 1)]])
	cs[1].hp = 105
	cast(cs[0], "power_word_pain", {"targets": [cs[1].id], "slot": 7})
	check(not has_effect(cs[1], "Wracked"), "Power Word Pain ignores a creature over 100 HP")
	cast(cs[0], "power_word_pain", {"targets": [cs[2].id], "slot": 7})
	check(eng.eff_speed(cs[2]) <= 10 and effect_named(cs[2], "Wracked").get("save_ends", {}).get("ability", "") == "con", "Power Word Pain: speed 10, CON save each turn")
	# --- Otto's Irresistible Dance: the target can spend its action on a WIS save to stop.
	cs = board([["mage", "party", Vector2i(2, 5)], ["knight", "enemy", Vector2i(8, 5)]])
	cast(cs[0], "ottos_irresistible_dance", {"targets": [cs[1].id], "slot": 6})
	rig_saves(cs[1], false)
	give_turn(cs[1])
	eng.execute(cs[1].id, "escape", {})
	check(not has_effect(cs[1], "Dancing"), "Otto's dance ends with a successful WIS save as an action")
	# --- Maze: the target is cut off from the fight until an INT check against DC 20.
	cs = board([["mage", "party", Vector2i(2, 5)], ["knight", "enemy", Vector2i(8, 5)]])
	cast(cs[0], "maze", {"targets": [cs[1].id], "slot": 8})
	check(not eng.same_space(cs[0], cs[1]) and int(effect_named(cs[1], "Lost in Maze").get("escape_dc", 0)) == 20, "Maze: the target is gone until it beats DC 20")
	# --- Flesh to Stone: three failed saves petrify; three successes end the spell.
	cs = board([["mage", "party", Vector2i(2, 5)], ["knight", "enemy", Vector2i(8, 5)]])
	rig_saves(cs[1], true)
	cast(cs[0], "flesh_to_stone", {"targets": [cs[1].id], "slot": 6})
	for i in 3:
		give_turn(cs[1])
		eng.end_turn()
	check(eng.has_cond(cs[1], "petrified"), "Flesh to Stone petrifies after three failed saves")
	eng.end_concentration(cs[0], true)
	check(eng.has_cond(cs[1], "petrified"), "the petrification outlasts concentration")
	# --- Contagion: three failed saves bring the disease.
	cs = board([["mage", "party", Vector2i(2, 5)], ["knight", "enemy", Vector2i(3, 5)]])
	cs[1].ac = -100
	rig_saves(cs[1], true)
	cast(cs[0], "contagion", {"targets": [cs[1].id], "slot": 5})
	check(eng.has_cond(cs[1], "poisoned"), "Contagion poisons on a hit")
	for i in 3:
		give_turn(cs[1])
		eng.end_turn()
	check(has_effect(cs[1], "Blinding Sickness") and not has_effect(cs[1], "Contagion"), "Contagion turns into a disease after three failures")
	# --- Calm Emotions: affected enemies won't harm the caster's side.
	cs = board([["priest", "party", Vector2i(2, 5)], ["knight", "enemy", Vector2i(8, 5)], ["knight", "party", Vector2i(9, 5)]])
	rig_saves(cs[1], true)
	cast(cs[0], "calm_emotions", {"cell": Vector2i(8, 5)})
	check(eng.charm_blocks(cs[1], cs[2]), "Calm Emotions: a calmed enemy won't attack the caster's allies")
	eng.apply_damage(cs[1], [{"amount": 1, "type": "fire"}], cs[2], {})
	check(not eng.charm_blocks(cs[1], cs[2]), "harming a calmed creature ends the calm")
	# --- Charm Person only works on humanoids; Cause Fear doesn't work on undead.
	cs = board([["mage", "party", Vector2i(2, 5)], ["wolf", "enemy", Vector2i(8, 5)], ["skeleton", "enemy", Vector2i(8, 1)]])
	rig_saves(cs[1], true)
	rig_saves(cs[2], true)
	cast(cs[0], "charm_person", {"targets": [cs[1].id]})
	check(not eng.has_cond(cs[1], "charmed"), "Charm Person doesn't charm a beast")
	cast(cs[0], "cause_fear", {"targets": [cs[2].id]})
	check(not eng.has_cond(cs[2], "frightened"), "Cause Fear doesn't frighten undead")
	cast(cs[0], "animal_friendship", {"targets": [cs[1].id]})
	check(eng.has_cond(cs[1], "charmed") and eng.charm_blocks(cs[1], cs[0]), "Animal Friendship charms a wolf, which won't attack the caster")

func _tier2_defences() -> void:
	# --- Negative Energy Flood: undead gain temporary HP instead.
	var cs = board([["mage", "party", Vector2i(2, 5)], ["zombie", "enemy", Vector2i(8, 5)]])
	cast(cs[0], "negative_energy_flood", {"targets": [cs[1].id], "slot": 5})
	check(cs[1].temp_hp > 0 and cs[1].hp == cs[1].max_hp, "Negative Energy Flood gives undead temporary HP")
	# --- Harm: can't drop the target below 1 HP, and cuts its maximum.
	cs = board([["priest", "party", Vector2i(2, 5)], ["knight", "enemy", Vector2i(8, 5)]])
	rig_saves(cs[1], true)
	cast(cs[0], "harm", {"targets": [cs[1].id], "slot": 6})
	check(cs[1].hp >= 1 and eng.alive(cs[1]) and cs[1].max_hp < 52, "Harm leaves at least 1 HP and lowers the maximum (hp %d/%d)" % [cs[1].hp, cs[1].max_hp])
	# --- Lightning Lure: pulled 10 ft, shocked only if it ends within 5 ft.
	cs = board([["mage", "party", Vector2i(2, 5)], ["knight", "enemy", Vector2i(5, 5)]])
	rig_saves(cs[1], true)
	tough(cs[1])
	cast(cs[0], "lightning_lure", {"targets": [cs[1].id]})
	check(cs[1].pos == Vector2i(3, 5) and cs[1].hp < 500, "Lightning Lure pulls the target in and shocks it (at %s)" % str(cs[1].pos))
	# --- Invulnerability: immune to all damage.
	cs = board([["mage", "party", Vector2i(2, 5)]])
	cast(cs[0], "invulnerability", {"targets": [cs[0].id], "slot": 9})
	var full: int = cs[0].hp
	eng.apply_damage(cs[0], [{"amount": 30, "type": "slashing"}, {"amount": 30, "type": "fire"}], {}, {})
	check(cs[0].hp == full, "Invulnerability: no damage at all")
	# --- Resilient Sphere: nothing gets in or out.
	cs = board([["mage", "party", Vector2i(2, 5)], ["knight", "enemy", Vector2i(8, 5)]])
	rig_saves(cs[1], true)
	cast(cs[0], "otilukes_resilient_sphere", {"targets": [cs[1].id], "slot": 4})
	check(not eng.same_space(cs[0], cs[1]) and eng.eff_speed(cs[1]) == 0, "Resilient Sphere seals the target off")
	# --- Fire Shield: a melee hit burns the attacker; the chill version resists fire.
	cs = board([["mage", "party", Vector2i(5, 5)], ["knight", "enemy", Vector2i(6, 5)]])
	tough(cs[0])
	cast(cs[0], "fire_shield", {"targets": [cs[0].id], "slot": 4})
	var kn_hp: int = cs[1].hp
	land_hit(cs[1], cs[0], melee_of(cs[1]))
	check(cs[1].hp < kn_hp, "Fire Shield burns a melee attacker")
	cast(cs[0], "fire_shield", {"targets": [cs[0].id], "slot": 4, "opts": {"dtype": "cold"}})
	var fs = effect_named(cs[0], "Fire Shield (chill)")
	check(fs.get("mods", {}).get("resist", []) == ["fire"] and fs.get("retaliate", {}).get("type", "") == "cold", "the chill shield resists fire and deals cold")
	# --- Warding Bond: the caster takes the same damage.
	cs = board([["priest", "party", Vector2i(5, 5)], ["knight", "party", Vector2i(6, 5)]])
	tough(cs[0])
	tough(cs[1])
	cast(cs[0], "warding_bond", {"targets": [cs[1].id]})
	eng.apply_damage(cs[1], [{"amount": 20, "type": "fire"}], {}, {})
	check(cs[1].hp == 490 and cs[0].hp == 490, "Warding Bond: resisted on the ward, shared by the caster (%d / %d)" % [cs[1].hp, cs[0].hp])
	# --- Mind Blank, Protection from Evil and Good, Foresight.
	cs = board([["priest", "party", Vector2i(5, 5)], ["knight", "party", Vector2i(6, 5)], ["skeleton", "enemy", Vector2i(8, 5)]])
	cast(cs[0], "mind_blank", {"targets": [cs[1].id], "slot": 8})
	var h3: int = cs[1].hp
	eng.apply_damage(cs[1], [{"amount": 10, "type": "psychic"}], {}, {})
	check(cs[1].hp == h3, "Mind Blank: immune to psychic damage")
	check(eng.add_effect(cs[1], {"name": "Charm", "cond": "charmed", "src": cs[2].id, "rounds": 5}).is_empty(), "Mind Blank: can't be charmed")
	cs = board([["priest", "party", Vector2i(5, 5)], ["knight", "party", Vector2i(6, 5)], ["skeleton", "enemy", Vector2i(8, 5)], ["knight", "enemy", Vector2i(8, 7)]])
	cast(cs[0], "protection_from_evil_and_good", {"targets": [cs[1].id]})
	check(eng.add_effect(cs[1], {"name": "Fear", "cond": "frightened", "src": cs[2].id, "rounds": 5}).is_empty(), "Protection from Evil and Good: undead can't frighten")
	check(not eng.add_effect(cs[1], {"name": "Fear2", "cond": "frightened", "src": cs[3].id, "rounds": 5}).is_empty(), "...but a humanoid still can")
	# --- Magic Weapon at 6th level is +3; Elemental Weapon takes the chosen element.
	cs = board([["mage", "party", Vector2i(5, 5)], ["knight", "party", Vector2i(6, 5)]])
	cast(cs[0], "magic_weapon", {"targets": [cs[1].id], "slot": 6})
	check(str(effect_named(cs[1], "Magic Weapon").get("mods", {}).get("attack_dice", "")) == "3", "Magic Weapon at 6th level is +3")
	cast(cs[0], "elemental_weapon", {"targets": [cs[1].id], "slot": 5, "opts": {"dtype": "cold"}})
	var ew = effect_named(cs[1], "Elemental Weapon").get("mods", {}).get("extra_damage", {})
	check(ew.get("dice", "") == "2d4" and ew.get("type", "") == "cold", "Elemental Weapon at 5th: +2d4 of the chosen element")
	# --- Elemental Bane: ignores resistance and adds 2d6 once a turn.
	cs = board([["mage", "party", Vector2i(2, 5)], ["knight", "enemy", Vector2i(8, 5)]])
	tough(cs[1])
	cs[1].resist = ["fire"]
	rig_saves(cs[1], true)
	cast(cs[0], "elemental_bane", {"targets": [cs[1].id], "slot": 4, "opts": {"dtype": "fire"}})
	eng.apply_damage(cs[1], [{"amount": 10, "type": "fire"}], cs[0], {})
	check(cs[1].hp <= 488, "Elemental Bane: fire resistance is gone and 2d6 is added (hp %d)" % cs[1].hp)
	# --- Earthbind: no flying.
	cs = board([["mage", "party", Vector2i(2, 5)], ["giant_eagle", "enemy", Vector2i(8, 5)]])
	rig_saves(cs[1], true)
	cast(cs[0], "earthbind", {"targets": [cs[1].id]})
	check(eng.mod_any(cs[1], "no_fly"), "Earthbind grounds a flier")
	# --- Feeblemind: 4d6 even on a save; on a failure no spells at all.
	cs = board([["mage", "party", Vector2i(2, 5)], ["mage", "enemy", Vector2i(8, 5)]])
	rig_saves(cs[1], true)
	no_counter(cs[1])
	cast(cs[0], "feeblemind", {"targets": [cs[1].id], "slot": 8})
	give_turn(cs[1])
	var anyspell = false
	for a in eng.get_actions(cs[1]):
		if a.kind == "spell" and a.enabled:
			anyspell = true
	check(not anyspell, "Feeblemind: no spellcasting")

func _tier2_riders_and_heals() -> void:
	# --- Ashardalon's Stride: +20 ft (+5 per slot) and a fire trail.
	var cs = board([["mage", "party", Vector2i(2, 5)], ["ogre", "enemy", Vector2i(5, 4)]])
	tough(cs[1])
	cast(cs[0], "ashardalons_stride", {"targets": [cs[0].id], "slot": 4})
	check(eng.eff_speed(cs[0]) == 30 + 25, "Ashardalon's Stride at 4th: +25 ft (got %d)" % eng.eff_speed(cs[0]))
	eng.move(cs[0], Vector2i(8, 5))
	check(cs[1].hp < 500, "Ashardalon's Stride burns creatures the caster passes")
	# --- Kinetic Jaunt: through enemy spaces, no opportunity attacks.
	cs = board([["mage", "party", Vector2i(2, 5)], ["knight", "enemy", Vector2i(3, 5)]])
	cast(cs[0], "kinetic_jaunt", {"targets": [cs[0].id]})
	check(eng._can_stand_path(cs[0], Vector2i(3, 5), false) and eng.mod_any(cs[0], "no_provoke"), "Kinetic Jaunt: move through creatures without provoking")
	# --- Chaos Bolt deals damage of a random type.
	cs = board([["mage", "party", Vector2i(2, 5)], ["ogre", "enemy", Vector2i(8, 5)]])
	tough(cs[1])
	cs[1].ac = -100
	cast(cs[0], "chaos_bolt", {"targets": [cs[1].id]})
	check(cs[1].hp < 500, "Chaos Bolt hits")
	# --- Ice Knife: the shard bursts on creatures around the target, even on a miss.
	cs = board([["mage", "party", Vector2i(2, 5)], ["ogre", "enemy", Vector2i(8, 5)], ["knight", "enemy", Vector2i(8, 6)]])
	tough(cs[1])
	tough(cs[2])
	cs[1].ac = 100
	rig_saves(cs[2], true)
	cast(cs[0], "ice_knife", {"targets": [cs[1].id]})
	check(cs[2].hp < 500, "Ice Knife's burst hits a creature next to the target even on a miss")
	# --- Hail of Thorns: the next ranged hit bursts.
	cs = board([["veteran", "party", Vector2i(2, 5)], ["ogre", "enemy", Vector2i(8, 5)], ["knight", "enemy", Vector2i(9, 5)]])
	tough(cs[1])
	tough(cs[2])
	rig_saves(cs[2], true)
	cast(cs[0], "hail_of_thorns", {"targets": [cs[0].id]})
	land_hit(cs[0], cs[1], ranged_of(cs[0]))
	check(cs[2].hp < 500 and not has_effect(cs[0], "Hail of Thorns"), "Hail of Thorns bursts on the next ranged hit")
	# --- Lightning Arrow: a miss still deals half and bursts.
	cs = board([["veteran", "party", Vector2i(2, 5)], ["ogre", "enemy", Vector2i(8, 5)]])
	tough(cs[1])
	cs[1].ac = 100
	cast(cs[0], "lightning_arrow", {"targets": [cs[0].id]})
	give_turn(cs[0])
	eng._attack_with(cs[0], cs[1], ranged_of(cs[0]))
	check(cs[1].hp < 500 and not has_effect(cs[0], "Lightning Arrow"), "Lightning Arrow: a miss still deals half damage")
	# --- Spirit Shroud: only against creatures within 10 ft, on spell attacks too.
	cs = board([["priest", "party", Vector2i(2, 5)], ["ogre", "enemy", Vector2i(3, 5)], ["ogre", "enemy", Vector2i(12, 5)]])
	cast(cs[0], "spirit_shroud", {"targets": [cs[0].id]})
	check(eng._spell_attack_riders(cs[0], cs[1], false).size() == 1 and eng._spell_attack_riders(cs[0], cs[2], false).is_empty(), "Spirit Shroud: only within 10 ft")
	check(eng.mod_any(cs[1], "no_heal"), "Spirit Shroud stops the target healing")
	# --- Healing Spirit: heals an ally starting its turn there, limited uses, can be moved.
	cs = board([["priest", "party", Vector2i(2, 5)], ["knight", "party", Vector2i(5, 5)]])
	cs[1].hp = 5
	cast(cs[0], "healing_spirit", {"cell": Vector2i(5, 5)})
	check(cs[1].hp == 5, "Healing Spirit doesn't heal on casting")
	give_turn(cs[1])
	check(cs[1].hp > 5, "Healing Spirit heals an ally starting its turn in it")
	var uses_left: int = int(eng.s.zones[0].get("uses", 0))
	check(uses_left == maxi(2, 1 + int(cs[0].casting[0].mod)) - 1, "Healing Spirit has 1 + modifier uses (min 2)")
	give_turn(cs[0])
	eng.execute(cs[0].id, repeat_id(cs[0], "healing_spirit"), {"cell": Vector2i(7, 5)})
	check(eng.s.zones[0].cells.has(Vector2i(7, 5)), "the spirit moves as a bonus action")
	# --- Aura of Vitality: a bonus action heals 2d6, right away and on later turns.
	cs = board([["priest", "party", Vector2i(2, 5)], ["knight", "party", Vector2i(4, 5)]])
	cs[1].hp = 5
	cast(cs[0], "aura_of_vitality", {"targets": [cs[0].id]})
	check(cs[1].hp == 5, "Aura of Vitality doesn't heal by itself")
	eng.execute(cs[0].id, repeat_id(cs[0], "aura_of_vitality"), {"targets": [cs[1].id]})
	check(cs[1].hp > 5, "Aura of Vitality heals with a bonus action on the casting turn")
	var hv: int = cs[1].hp
	give_turn(cs[0])
	eng.execute(cs[0].id, repeat_id(cs[0], "aura_of_vitality"), {"targets": [cs[1].id]})
	check(cs[1].hp > hv or cs[1].hp == cs[1].max_hp, "...and again on later turns")

# ---------------------------------------------------------------- Tier 3
func _tier3_repeats() -> void:
	# --- Call Lightning: a bolt on casting, another as an action on later turns.
	var cs = board([["priest", "party", Vector2i(2, 5)], ["ogre", "enemy", Vector2i(10, 5)]])
	tough(cs[1])
	rig_saves(cs[1], true)
	cast(cs[0], "call_lightning", {"cell": Vector2i(10, 5)})
	var a = repeat_action(cs[0], "call_lightning")
	check(not a.is_empty() and not a.enabled, "Call Lightning: the repeat bolt waits for the next turn")
	give_turn(cs[0])
	var h: int = cs[1].hp
	check(eng.execute(cs[0].id, repeat_id(cs[0], "call_lightning"), {"cell": Vector2i(10, 5)}) and cs[1].hp < h, "Call Lightning: another bolt on a later turn")
	eng.end_concentration(cs[0], true)
	check(repeat_id(cs[0], "call_lightning") == "", "the repeat ends with concentration")
	# --- The AI uses the repeat on a later turn instead of spending another slot.
	cs = board([["priest", "enemy", Vector2i(2, 5)], ["ogre", "party", Vector2i(10, 5)]])
	cs[0].casting[0].spells = ["call_lightning"]
	cs[0].slots_max = [4, 3, 3]
	cs[0].slots_used = [0, 0, 0]
	tough(cs[1], 999)
	cs[1].speed = 0
	for i in 2:
		give_turn(cs[0])
		CombatAI.new(eng).run_turn(cs[0])
	check(int(cs[0].slots_used[2]) == 1 and eng.s.log.any(func(l): return str(l).contains("Call Lightning: bolt")), "the AI calls a second bolt without a new slot")
	# --- Flame Blade: usable on the casting turn with the action.
	cs = board([["priest", "party", Vector2i(2, 5)], ["ogre", "enemy", Vector2i(3, 5)]])
	tough(cs[1])
	cs[1].ac = -100
	cast(cs[0], "flame_blade", {"targets": [cs[0].id]})
	eng.execute(cs[0].id, repeat_id(cs[0], "flame_blade"), {"targets": [cs[1].id]})
	check(cs[1].hp < 500, "Flame Blade slashes with the action on the casting turn")
	# --- Shadow Blade: a weapon attack using STR or DEX.
	cs = board([["mage", "party", Vector2i(2, 5)], ["ogre", "enemy", Vector2i(3, 5)]])
	tough(cs[1])
	cs[1].ac = -100
	cast(cs[0], "shadow_blade", {"targets": [cs[0].id], "slot": 3})
	var wpn = eng._conjured_weapon(cs[0], Data.spell("shadow_blade"), Data.spell("shadow_blade").combat.repeat.combat, 1)
	check(Dice.average(str(wpn.damage[0].dice)) >= 13.5 + maxi(eng.ability_mod(cs[0], "str"), eng.ability_mod(cs[0], "dex")), "Shadow Blade at 3rd level deals 3d8 (%s)" % wpn.damage[0].dice)
	for attempt in 5:  # a natural 1 still misses
		give_turn(cs[0])
		eng.execute(cs[0].id, repeat_id(cs[0], "shadow_blade"), {"targets": [cs[1].id]})
		if cs[1].hp < 500:
			break
	check(cs[1].hp < 500, "Shadow Blade strikes")
	# --- Crown of Stars: seven motes, then the spell is spent.
	cs = board([["mage", "party", Vector2i(2, 5)], ["ogre", "enemy", Vector2i(8, 5)]])
	tough(cs[1], 2000)
	cast(cs[0], "crown_of_stars", {"targets": [cs[0].id], "slot": 7})
	for i in 7:
		give_turn(cs[0])
		eng.execute(cs[0].id, repeat_id(cs[0], "crown_of_stars"), {"targets": [cs[1].id]})
	check(repeat_id(cs[0], "crown_of_stars") == "", "Crown of Stars runs out after seven motes")
	# --- Melf's Minute Meteors: two meteors per bonus action.
	cs = board([["mage", "party", Vector2i(2, 5)], ["ogre", "enemy", Vector2i(10, 5)]])
	tough(cs[1], 2000)
	cast(cs[0], "melfs_minute_meteors", {"cell": Vector2i(10, 5)})
	give_turn(cs[0])
	eng.execute(cs[0].id, repeat_id(cs[0], "melfs_minute_meteors"), {"cell": Vector2i(10, 5)})
	check(int(eng._repeat_effect(cs[0], repeat_id(cs[0], "melfs_minute_meteors").substr(3)).get("uses", 0)) == 3, "Melf's Meteors: two of the remaining five spent")
	# --- Delayed Blast Fireball: bursts when concentration ends, bigger for each turn it waited.
	cs = board([["mage", "party", Vector2i(2, 5)], ["ogre", "enemy", Vector2i(12, 5)]])
	tough(cs[1], 2000)
	rig_saves(cs[1], true)
	cast(cs[0], "delayed_blast_fireball", {"cell": Vector2i(12, 5), "slot": 7})
	check(cs[1].hp == 2000, "Delayed Blast Fireball waits")
	eng.end_turn()
	check(int(cs[0].conc.get("bead", {}).get("extra", 0)) == 1, "the bead grows at the end of the caster's turn")
	eng.end_concentration(cs[0], true)
	check(cs[1].hp < 2000, "the bead bursts when concentration ends")
	cs = board([["mage", "party", Vector2i(2, 5)], ["ogre", "enemy", Vector2i(12, 5)]])
	tough(cs[1], 2000)
	cast(cs[0], "delayed_blast_fireball", {"cell": Vector2i(12, 5), "slot": 7})
	give_turn(cs[0])
	eng.execute(cs[0].id, repeat_id(cs[0], "delayed_blast_fireball"), {})
	check(cs[1].hp < 2000 and cs[0].conc.is_empty(), "the caster can detonate the bead")
	# --- Draconic Transformation: flight and a breath each turn.
	cs = board([["mage", "party", Vector2i(2, 5)], ["ogre", "enemy", Vector2i(8, 5)]])
	tough(cs[1], 2000)
	cast(cs[0], "draconic_transformation", {"cell": Vector2i(8, 5), "slot": 7})
	check(eng.mod_sum(cs[0], "fly") >= 60 and repeat_id(cs[0], "draconic_transformation") != "", "Draconic Transformation: wings and a breath to use again")
	# --- Illusory Dragon breathes from where the dragon is.
	cs = board([["mage", "party", Vector2i(1, 5)], ["ogre", "enemy", Vector2i(16, 5)]])
	tough(cs[1], 2000)
	rig_saves(cs[1], true)
	cast(cs[0], "illusory_dragon", {"cell": Vector2i(12, 5), "slot": 8})
	give_turn(cs[0])
	eng.execute(cs[0].id, repeat_id(cs[0], "illusory_dragon"), {"cell": Vector2i(16, 5)})
	check(cs[1].hp < 2000, "Illusory Dragon's breath reaches a creature 75 ft from the caster")
	# --- Eyebite: a new target each turn.
	cs = board([["mage", "party", Vector2i(2, 5)], ["knight", "enemy", Vector2i(8, 5)], ["knight", "enemy", Vector2i(8, 7)]])
	rig_saves(cs[1], true)
	rig_saves(cs[2], true)
	cast(cs[0], "eyebite", {"targets": [cs[1].id], "slot": 6})
	check(eng.has_cond(cs[1], "unconscious"), "Eyebite puts the target to sleep")
	give_turn(cs[0])
	eng.execute(cs[0].id, repeat_id(cs[0], "eyebite"), {"targets": [cs[2].id], "opts": {"eyebite": "sickened"}})
	check(has_effect(cs[2], "Sickened"), "Eyebite targets another creature on a later turn")
	# --- Flaming Sphere: move it and ram a creature.
	cs = board([["mage", "party", Vector2i(2, 5)], ["ogre", "enemy", Vector2i(10, 5)]])
	tough(cs[1])
	rig_saves(cs[1], true)
	cast(cs[0], "flaming_sphere", {"cell": Vector2i(6, 5)})
	give_turn(cs[0])
	eng.execute(cs[0].id, repeat_id(cs[0], "flaming_sphere"), {"cell": Vector2i(9, 5)})
	check(cs[1].hp < 500, "Flaming Sphere rams a creature when moved next to it")
	# --- Storm of Vengeance: something new each round.
	cs = board([["priest", "party", Vector2i(1, 1)], ["ogre", "enemy", Vector2i(10, 5)]])
	tough(cs[1], 3000)
	rig_saves(cs[1], true)
	cast(cs[0], "storm_of_vengeance", {"cell": Vector2i(10, 5), "slot": 9})
	var hs: int = cs[1].hp
	give_turn(cs[0])
	check(cs[1].hp < hs, "Storm of Vengeance: acid rain on the next round")

# ---------------------------------------------------------------- Tier 4
func _tier4() -> void:
	# --- Wall spells are placed across the caster's line of sight at the chosen point.
	var cs = board([["mage", "party", Vector2i(2, 5)]])
	var cells: Array = eng.area_cells(cs[0], {"shape": "wall", "size": 30}, Vector2i(10, 5), false)
	check(cells.has(Vector2i(10, 2)) and cells.has(Vector2i(10, 8)) and not cells.has(Vector2i(5, 5)), "a wall runs across the line of sight, centred on the point")
	# --- Forced movement: Thorn Whip pulls, Pulse Wave pushes farther when upcast.
	cs = board([["priest", "party", Vector2i(2, 5)], ["knight", "enemy", Vector2i(6, 5)]])
	tough(cs[1])
	cs[1].ac = -100
	cast(cs[0], "thorn_whip", {"targets": [cs[1].id]})
	check(cs[1].pos == Vector2i(4, 5), "Thorn Whip pulls the target 10 ft (at %s)" % str(cs[1].pos))
	cs = board([["mage", "party", Vector2i(2, 5)], ["knight", "enemy", Vector2i(4, 5)]])
	tough(cs[1])
	rig_saves(cs[1], true)
	cast(cs[0], "pulse_wave", {"cell": Vector2i(4, 5), "slot": 4})
	check(cs[1].pos.x == 8, "Pulse Wave at 4th pushes 20 ft (at %s)" % str(cs[1].pos))
	# --- Dissonant Whispers: the target flees with its reaction.
	cs = board([["mage", "party", Vector2i(5, 5)], ["knight", "enemy", Vector2i(6, 5)]])
	tough(cs[1])
	rig_saves(cs[1], true)
	cast(cs[0], "dissonant_whispers", {"targets": [cs[1].id]})
	check(eng.dist(cs[0], cs[1]) > 20, "Dissonant Whispers sends the target running")
	# --- Confusion and Mind Whip take over the start of the target's turn.
	cs = board([["mage", "party", Vector2i(2, 5)], ["knight", "enemy", Vector2i(8, 5)]])
	rig_saves(cs[1], true)
	cast(cs[0], "tashas_mind_whip", {"targets": [cs[1].id]})
	give_turn(cs[1])
	check(cs[1].turn.bonus == 0 and eng.move_left(cs[1]) == 0 and int(cs[1].turn.action) > 0, "Mind Whip: only the action is left")
	cs = board([["mage", "party", Vector2i(2, 5)], ["knight", "enemy", Vector2i(8, 5)]])
	rig_saves(cs[1], true)
	cast(cs[0], "confusion", {"cell": Vector2i(8, 5), "slot": 4})
	check(eng.has_tag(cs[1], "confused"), "Confusion confuses")
	# --- Chain Lightning's arcs stay within 30 ft of the first target.
	cs = board([["mage", "party", Vector2i(1, 1)], ["ogre", "enemy", Vector2i(5, 5)], ["ogre", "enemy", Vector2i(18, 5)]])
	tough(cs[1])
	tough(cs[2])
	rig_saves(cs[1], true)
	rig_saves(cs[2], true)
	cast(cs[0], "chain_lightning", {"targets": [cs[1].id, cs[2].id], "slot": 6})
	check(cs[1].hp < 500 and cs[2].hp == 500, "Chain Lightning can't arc 65 ft")
	# --- Mass Heal shares 700 HP, most hurt first.
	cs = board([["priest", "party", Vector2i(2, 5)], ["knight", "party", Vector2i(3, 5)], ["knight", "party", Vector2i(4, 5)]])
	cs[1].max_hp = 600
	cs[1].hp = 1
	cs[2].max_hp = 600
	cs[2].hp = 300
	cast(cs[0], "mass_heal", {"targets": [cs[1].id, cs[2].id], "slot": 9})
	check(cs[1].hp == 600 and cs[2].hp == 401, "Mass Heal: 700 HP shared out (%d, %d)" % [cs[1].hp, cs[2].hp])
	# --- Sickening Radiance: exhaustion stacks on each failure.
	cs = board([["mage", "party", Vector2i(1, 1)], ["ogre", "enemy", Vector2i(10, 5)]])
	tough(cs[1], 2000)
	rig_saves(cs[1], true)
	cast(cs[0], "sickening_radiance", {"cell": Vector2i(10, 5)})
	give_turn(cs[1])
	eng.end_turn()
	give_turn(cs[1])
	check(eng.exhaustion(cs[1]) == 2 and eng.eff_speed(cs[1]) == 20, "Sickening Radiance: two levels of exhaustion halve speed")
	eng.end_concentration(cs[0], true)
	check(eng.exhaustion(cs[1]) == 0, "the exhaustion fades with the spell")
	# --- Stinking Cloud: a creature starting its turn inside loses its action.
	cs = board([["mage", "party", Vector2i(1, 1)], ["knight", "enemy", Vector2i(10, 5)]])
	rig_saves(cs[1], true)
	cast(cs[0], "stinking_cloud", {"cell": Vector2i(10, 5)})
	give_turn(cs[1])
	check(int(cs[1].turn.action) == 0 and int(cs[1].turn.bonus) > 0, "Stinking Cloud: the action is lost retching")
	# --- Sleet Storm makes casters inside fight for concentration.
	cs = board([["mage", "party", Vector2i(1, 1)], ["mage", "enemy", Vector2i(10, 5)]])
	rig_saves(cs[1], true)
	no_counter(cs[1])
	cs[1].conc = {"spell": "bless", "name": "Bless"}
	cast(cs[0], "sleet_storm", {"cell": Vector2i(10, 5)})
	give_turn(cs[1])
	check(cs[1].conc.is_empty() and eng.has_cond(cs[1], "prone"), "Sleet Storm: prone and concentration lost")
	# --- Blink: sometimes vanishes at the end of the caster's turn.
	cs = board([["mage", "party", Vector2i(2, 5)]])
	cast(cs[0], "blink", {"targets": [cs[0].id]})
	for i in 20:
		give_turn(cs[0])
		eng.end_turn()
	var gone = eng.s.log.any(func(l): return str(l).contains("Ethereal Plane"))
	check(gone, "Blink sends the caster to the Ethereal Plane on 11+")
	# --- Reality Break, Prismatic Spray, Meteor Swarm, Gravity Fissure cast cleanly.
	cs = board([["mage", "party", Vector2i(1, 5)], ["ogre", "enemy", Vector2i(5, 5)], ["ogre", "enemy", Vector2i(6, 6)]])
	tough(cs[1], 3000)
	tough(cs[2], 3000)
	rig_saves(cs[1], true)
	rig_saves(cs[2], true)
	cast(cs[0], "reality_break", {"targets": [cs[1].id], "slot": 8})
	check(has_effect(cs[1], "Reality Break"), "Reality Break takes hold")
	cast(cs[0], "prismatic_spray", {"cell": Vector2i(6, 5), "slot": 7})
	check(cs[2].hp < 3000 or not cs[2].effects.is_empty(), "Prismatic Spray strikes with a ray")
	var before: int = cs[1].hp + cs[2].hp
	cast(cs[0], "gravity_fissure", {"cell": Vector2i(10, 5), "slot": 6})
	check(cs[1].hp + cs[2].hp < before, "Gravity Fissure hurts creatures in and beside the line")
