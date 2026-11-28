extends Node
## Headless checks for the laws of movement and the action economy.
## Run: Godot --headless --path . res://tests/rules_test.tscn

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

## Make `c` the active creature with a fresh turn.
func give_turn(c: Dictionary) -> void:
	eng.s.turn = eng.s.order.find(c.id)
	eng.begin_turn(c)

func _ready() -> void:
	# --- Speed, Dash, and speed changes mid-turn.
	var cs = board([["orc", "party", Vector2i(2, 2)], ["goblin", "enemy", Vector2i(18, 8)]])
	var orc: Dictionary = cs[0]
	give_turn(orc)
	check(eng.move_left(orc) == 30, "orc starts with 30 ft (got %d)" % eng.move_left(orc))
	eng.move(orc, Vector2i(5, 2))
	check(eng.move_left(orc) == 15, "15 ft left after moving 15 (got %d)" % eng.move_left(orc))
	check(not eng.move(orc, Vector2i(9, 2)), "can't move 20 ft with 15 left")
	eng.execute(orc.id, "dash", {})
	check(eng.move_left(orc) == 45, "Dash adds speed: 45 left (got %d)" % eng.move_left(orc))
	check(not eng.find_action(orc, "dash").enabled, "no second Dash without an action")
	eng.add_effect(orc, {"name": "Test Grab", "cond": "grappled", "src": "dm", "rounds": 99, "tick_cid": "none"})
	check(eng.move_left(orc) == 0 and not eng.move(orc, Vector2i(6, 2)), "grappled mid-turn: speed 0, can't move")
	eng.remove_effects_where(orc, func(e): return e.get("cond", "") == "grappled")
	eng.add_effect(orc, {"name": "Hasted", "tag": "haste", "src": orc.id, "mods": {"speed_mult": 2}, "rounds": 10, "tick_cid": orc.id})
	check(eng.move_left(orc) == 105, "Haste mid-turn doubles speed: 60x2-15 = 105 (got %d)" % eng.move_left(orc))

	# --- Haste's limited action.
	cs = board([["orc", "party", Vector2i(2, 2)], ["goblin", "enemy", Vector2i(18, 8)]])
	orc = cs[0]
	eng.add_effect(orc, {"name": "Hasted", "tag": "haste", "src": orc.id, "mods": {"speed_mult": 2}, "rounds": 10, "tick_cid": orc.id})
	give_turn(orc)
	eng.execute(orc.id, "dodge", {})
	var dash = eng.find_action(orc, "dash")
	check(dash.cost == "haste" and dash.enabled, "Haste action can Dash after the action is spent")
	check(not eng.find_action(orc, "dodge").enabled, "Haste action can't Dodge")
	eng.execute(orc.id, "dash", {})
	check(not eng.find_action(orc, "dash").enabled, "Haste action used up")

	# --- Creature spaces: allies cost double, hostile spaces need a 2-size gap.
	cs = board([["orc", "party", Vector2i(2, 2)], ["orc", "party", Vector2i(3, 2)], ["goblin", "enemy", Vector2i(2, 4)], ["ogre", "party", Vector2i(10, 4)], ["goblin", "enemy", Vector2i(12, 4)]])
	orc = cs[0]
	give_turn(orc)
	var r = eng.reachable(orc, 30)
	check(int(r[Vector2i(3, 2)].cost) == 10, "entering an ally's space costs double (got %s)" % str(r[Vector2i(3, 2)].cost))
	check(r[Vector2i(3, 2)].occupied, "can't end in an ally's space")
	check(not r.has(Vector2i(2, 4)), "medium orc can't cross a small goblin's space")
	var ogre: Dictionary = cs[3]
	give_turn(ogre)
	r = eng.reachable(ogre, 40)
	check(r.has(Vector2i(12, 4)) and r[Vector2i(12, 4)].occupied, "large ogre can cross a small goblin's space (two sizes apart)")

	# --- Prone: stand for half speed, or crawl.
	cs = board([["orc", "party", Vector2i(2, 2)], ["goblin", "enemy", Vector2i(18, 8)]])
	orc = cs[0]
	give_turn(orc)
	eng.add_effect(orc, {"name": "Prone", "cond": "prone", "src": "dm", "rounds": 99, "tick_cid": "none"})
	check(eng.move_budget(orc) == 15, "prone: 15 ft left after standing (got %d)" % eng.move_budget(orc))
	eng.move(orc, Vector2i(4, 2))
	check(not eng.has_cond(orc, "prone") and eng.move_left(orc) == 5, "moving stands up first: 30 - 15 - 10 = 5 (got %d)" % eng.move_left(orc))
	eng.add_effect(orc, {"name": "Prone", "cond": "prone", "src": "dm", "rounds": 99, "tick_cid": "none"})
	check(not eng.can_stand(orc) and not eng.find_action(orc, "stand").enabled, "can't stand with 5 ft left")
	r = eng.reachable(orc, eng.move_budget(orc))
	check(not r.has(Vector2i(5, 2)), "crawling: 5 ft isn't enough for one square")

	# --- Frightened: no moving closer to the source.
	cs = board([["orc", "party", Vector2i(2, 2)], ["goblin", "enemy", Vector2i(10, 2)]])
	orc = cs[0]
	var gob: Dictionary = cs[1]
	give_turn(orc)
	eng.add_effect(orc, {"name": "Frightened", "cond": "frightened", "src": gob.id, "rounds": 10, "tick_cid": gob.id})
	r = eng.reachable(orc, 30)
	check(not r.has(Vector2i(3, 2)), "frightened orc can't step toward the goblin")
	check(r.has(Vector2i(1, 2)) and r.has(Vector2i(2, 3)), "frightened orc can step away or sideways")

	# --- Opportunity attacks: Disengage, Sentinel, and sight.
	cs = board([["orc", "party", Vector2i(2, 2)], ["orc", "enemy", Vector2i(3, 2)]])
	orc = cs[0]
	var foe: Dictionary = cs[1]
	give_turn(orc)
	eng.execute(orc.id, "disengage", {})
	eng.move(orc, Vector2i(0, 2))
	check(foe.turn.reaction, "Disengage: no opportunity attack")
	cs = board([["orc", "party", Vector2i(2, 2)], ["orc", "enemy", Vector2i(3, 2)]])
	orc = cs[0]
	foe = cs[1]
	foe.feats = ["sentinel"]
	give_turn(orc)
	eng.execute(orc.id, "disengage", {})
	orc.ac = -100
	eng.move(orc, Vector2i(0, 2))
	check(not foe.turn.reaction, "Sentinel attacks through Disengage")
	# The OA happens as the orc leaves reach; a hit stops it before it takes that step.
	check(orc.turn.speed_zero == (orc.pos == Vector2i(2, 2)), "a Sentinel hit stops the mover in place")
	if orc.turn.speed_zero:
		check(eng.move_left(orc) == 0 and not eng.move(orc, Vector2i(2, 4)), "after a Sentinel hit, no more movement this turn")
	cs = board([["orc", "party", Vector2i(2, 2)], ["orc", "enemy", Vector2i(3, 2)]])
	orc = cs[0]
	foe = cs[1]
	give_turn(orc)
	eng.add_effect(orc, {"name": "Invisible", "cond": "invisible", "src": "dm", "rounds": 99, "tick_cid": "none"})
	eng.move(orc, Vector2i(0, 2))
	check(foe.turn.reaction, "no opportunity attack against a creature you can't see")
	cs = board([["orc", "party", Vector2i(2, 2)], ["orc", "enemy", Vector2i(3, 2)]])
	orc = cs[0]
	foe = cs[1]
	give_turn(orc)
	# The HUD's warning (opportunity_threats) names the same creature before the move.
	var away: Array = eng.path_to(orc, Vector2i(0, 2), eng.reachable(orc, eng.move_budget(orc)))
	var threats: Array = eng.opportunity_threats(orc, away)
	check(threats.size() == 1 and threats[0].id == foe.id, "move warning names the orc whose reach we leave")
	check(eng.opportunity_threats(orc, [Vector2i(2, 3)]).is_empty(), "no warning for a step that stays in reach")
	# Enough HP that a critical OA can't drop the orc before it moves (that made this check flaky).
	orc.max_hp = 999
	orc.hp = 999
	eng.move(orc, Vector2i(0, 2))
	check(not foe.turn.reaction, "leaving reach provokes an opportunity attack")
	check(eng.move_left(orc) <= 20, "movement still spent after the OA")
	check(eng.opportunity_threats(orc, [Vector2i(0, 3)]).is_empty(), "no warning from a foe whose reaction is spent")
	# Disengage clears the warning too.
	cs = board([["orc", "party", Vector2i(2, 2)], ["orc", "enemy", Vector2i(3, 2)]])
	orc = cs[0]
	give_turn(orc)
	eng.execute(orc.id, "disengage", {})
	check(eng.opportunity_threats(orc, [Vector2i(1, 2), Vector2i(0, 2)]).is_empty(), "no move warning after Disengage")

	# --- Spellcasting on one turn: bonus-action spell rule.
	cs = board([["mage", "party", Vector2i(2, 2)], ["goblin", "enemy", Vector2i(18, 8)]])
	var mage: Dictionary = cs[0]
	give_turn(mage)
	mage.turn.cast_bonus = true
	check(eng.spell_block_reason(mage, "action", 1) != "", "after a bonus spell: no leveled action spell")
	check(eng.spell_block_reason(mage, "action", 0) == "", "after a bonus spell: action cantrip allowed")
	check(not eng.can_react_spell(mage), "after a bonus spell: no reaction spells this turn")
	mage.turn.cast_bonus = false
	mage.turn.cast_leveled_action = true
	check(eng.spell_block_reason(mage, "bonus", 0) != "", "after a leveled spell: no bonus spell, even a cantrip")

	# --- Grapples: escaping takes an action; they end when the grappler drops.
	cs = board([["orc", "party", Vector2i(2, 2)], ["orc", "enemy", Vector2i(3, 2)]])
	orc = cs[0]
	foe = cs[1]
	give_turn(orc)
	eng.add_effect(orc, {"name": "Grappled", "cond": "grappled", "src": foe.id, "escape_dc": 99, "rounds": 99, "tick_cid": foe.id})
	var esc = eng.find_action(orc, "escape")
	check(not esc.is_empty() and esc.cost == "action", "Escape Grapple is an action")
	eng.execute(orc.id, "escape", {})
	check(eng.has_cond(orc, "grappled") and int(orc.turn.action) == 0, "failed escape still spends the action")
	foe.dead = true
	eng.release_broken_grapples()
	check(not eng.has_cond(orc, "grappled"), "grapple ends when the grappler dies")

	# --- Web: restrained creatures can tear free with a Strength check, and the AI tries to.
	cs = board([["orc", "enemy", Vector2i(2, 2)], ["mage", "party", Vector2i(12, 2)]])
	orc = cs[0]
	foe = cs[1]
	var web_sp = Data.spell("web")
	var webbed = eng._make_effect(foe, web_sp, web_sp.combat.effect, 14, "dex")
	check(int(webbed.get("escape_dc", 0)) == 14 and webbed.get("escape_with", []) == ["str"], "Web restraint carries an escape DC from the spell")
	eng.add_effect(orc, webbed)
	give_turn(orc)
	var brk = eng.find_action(orc, "escape")
	check(not brk.is_empty() and brk.name == "Break Free" and brk.enabled, "restrained by Web offers Break Free")
	webbed.escape_dc = -50
	CombatAI.new(eng).run_turn(orc)
	check(not eng.has_cond(orc, "restrained"), "AI spends its action breaking out of a web")
	check(orc.pos != Vector2i(2, 2), "AI uses its freed movement to close in")

	# --- Turn ownership and incapacitation.
	cs = board([["orc", "party", Vector2i(2, 2)], ["orc", "enemy", Vector2i(8, 2)]])
	orc = cs[0]
	foe = cs[1]
	give_turn(orc)
	check(not eng.can_pay(foe, "action") and not eng.can_pay(foe, "free"), "nothing payable off-turn")
	eng.add_effect(orc, {"name": "Stunned", "cond": "stunned", "src": "dm", "rounds": 99, "tick_cid": "none"})
	var any_enabled = false
	for a in eng.get_actions(orc):
		if a.enabled and a.kind != "toggle":
			any_enabled = true
	check(not any_enabled and eng.move_left(orc) == 0, "stunned: no actions, no movement")

	print("RULES DONE passed=%d failed=%d" % [passes, fails])
	get_tree().quit(1 if fails > 0 else 0)
