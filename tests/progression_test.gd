extends Node
## Character advancement: XP table, multiclass prerequisites, level gains, applying a level-up,
## HP rolls, history and restore, the level plan, the wizard, and the server's sheet handling.

var passed := 0
var failed := 0
var made_ids: Array = []

func check(cond: bool, what: String) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		print("FAIL: ", what)

func premade(prefix: String) -> Dictionary:
	for p in CharacterStore.premades():
		if str(p.name).begins_with(prefix):
			return p
	return {}

func _ready() -> void:
	_xp()
	_multiclass()
	_gains_and_apply()
	_history()
	_plan()
	await _wizard()
	await _session()
	for id in made_ids:
		CharacterStore.delete_character(id)
	print("PROGRESSION DONE passed=%d failed=%d" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)

func _xp() -> void:
	check(Progression.level_for_xp(0) == 1, "0 XP is level 1")
	check(Progression.level_for_xp(299) == 1, "299 XP is level 1")
	check(Progression.level_for_xp(300) == 2, "300 XP is level 2")
	check(Progression.level_for_xp(6500) == 5, "6500 XP is level 5")
	check(Progression.level_for_xp(400000) == 20, "lots of XP caps at 20")
	check(Progression.xp_for_level(6) == 14000, "level 6 needs 14000 XP")
	var sh := premade("Brannoc")
	sh.xp = 14000
	check(Progression.pending_levels(sh, "xp") == 1, "14000 XP lets a level 5 cleric take level 6")
	check(Progression.pending_levels(sh, "milestone") == 0, "milestone: nothing granted yet")
	sh.level_cap = 7
	check(Progression.pending_levels(sh, "milestone") == 2, "milestone: granted up to 7 means two levels pending")

func _multiclass() -> void:
	var grukka := premade("Grukka")  # half-orc fighter: STR 17, DEX 13, INT 8, CHA 10
	check(not Progression.multiclass_unmet(grukka, "wizard").is_empty(), "INT 8 fighter can't multiclass into wizard")
	check(not Progression.multiclass_unmet(grukka, "paladin").is_empty(), "CHA 10 fighter can't multiclass into paladin")
	check(Progression.multiclass_unmet(grukka, "barbarian").is_empty(), "STR 17 fighter can multiclass into barbarian")
	check(Progression.multiclass_unmet(grukka, "fighter").is_empty(), "levelling your own class needs no prerequisite")
	var pip := premade("Pip")  # halfling rogue DEX 17
	check(Progression.multiclass_unmet(pip, "fighter").is_empty(), "fighter accepts DEX 13 instead of STR")
	check(Progression.prereq_unmet("monk", {"dex": 14, "wis": 12}) != "", "monk needs both DEX and WIS 13")

func _gains_and_apply() -> void:
	var cleric := premade("Brannoc")
	var g := Progression.gains(cleric, "cleric")
	check(g.class_level == 6 and not g.asi and not g.subclass_choice, "cleric 6: no ASI, subclass already chosen")
	check("steps_of_night" in g.subclass_features, "Twilight cleric 6 gains Steps of Night")
	var before := Rules.derive(cleric)
	var up := Progression.apply_level(cleric, {"class": "cleric", "hp": 3})
	var after := Rules.derive(up)
	check(Rules.total_level(up) == 6, "apply_level adds a level")
	check(after.max_hp == before.max_hp + 3 + after.mods.con + 1, "rolled HP (3) + CON + Dwarven Toughness is added (%d -> %d)" % [before.max_hp, after.max_hp])
	check(up.hp_rolls.get("cleric", []).size() == 5, "HP rolls stored for cleric levels 2-6")
	check(Progression.level_log(up).size() == 6, "level log has six entries")
	# Average HP when nothing was rolled matches the old fixed formula.
	var avg_up := Progression.apply_level(cleric, {"class": "cleric"})
	check(Rules.derive(avg_up).max_hp == before.max_hp + 5 + after.mods.con + 1, "average HP for a d8 is 5 (+1 Dwarven Toughness)")
	# Fighter 6 gets an ASI.
	var grukka := premade("Grukka")
	var gf := Progression.gains(grukka, "fighter")
	check(gf.asi, "fighter 6 grants an ASI")
	var g2 := Progression.apply_level(grukka, {"class": "fighter", "asi": {"type": "asi", "a": "str", "b": "str"}})
	check(int(Rules.final_scores(g2).str) == int(Rules.final_scores(grukka).str) + 2, "ASI +2 STR applied")
	check(g2.asi.size() == 2 and int(g2.asi[1].level) == 6, "ASI entry recorded for fighter 6")
	# Multiclass: rogue 5 takes fighter 1.
	var pip := premade("Pip")
	var gm := Progression.gains(pip, "fighter")
	check(gm.multiclass and "medium" in gm.mc_armor and "fighting_style" in gm.features, "fighter multiclass: medium armor and a fighting style")
	var mc := Progression.apply_level(pip, {"class": "fighter", "hp": 10, "picks": {"fighting_styles": ["archery"]}})
	var st := Rules.derive(mc)
	check("medium" in st.armor_prof and not "con" in st.saves, "multiclass gives armor, not saving throws")
	check(Rules.class_summary(mc).contains("Fighter 1"), "class summary shows the new class")
	check(Progression.option_limits(mc).filter(func(o): return o.key == "fighting_styles" and int(o.limit) == 1).size() == 1, "fighting style limit 1")
	check(Rules.derive(mc).max_hp == Rules.derive(pip).max_hp + 10 + st.mods.con, "multiclass HP uses the stored roll for fighter level 1")
	# ASIs stay paired with their slots when a later class level is inserted before them.
	var two := Progression.apply_level(mc, {"class": "rogue"})  # rogue 6: expertise, no ASI
	Progression.sort_asi(two)
	check(two.asi.size() == Rules.asi_slots(two).size(), "asi entries match slots")
	check(Progression.expertise_limit(two) == 4, "rogue 6 has four expertise picks")
	# Subclass picked at level 3 grants its level-3 features.
	var w := Rules.new_character()
	w.classes = [{"id": "fighter", "level": 2, "subclass": ""}]
	var g3 := Progression.gains(w, "fighter")
	check(g3.subclass_choice, "fighter 3 asks for a subclass")
	var g3b := Progression.gains(w, "fighter", "battle_master")
	check("combat_superiority" in g3b.subclass_features, "Battle Master 3 grants Combat Superiority")
	var bm := Progression.apply_level(w, {"class": "fighter", "subclass": "battle_master"})
	check(Progression.option_limits(bm).filter(func(o): return o.key == "maneuvers" and int(o.limit) == 3).size() == 1, "three maneuvers at Battle Master 3")
	check(Progression.feat_unmet(premade("Grukka"), "war_caster") != "", "War Caster needs spellcasting")
	check(Progression.feat_unmet(premade("Brannoc"), "war_caster") == "", "a cleric can take War Caster")

func _history() -> void:
	var ch := premade("Seraphine")
	ch.xp = 900
	var up := Progression.apply_level(ch, {"class": "paladin"})
	var old := ch.duplicate(true)
	Progression.push_history(old, "Before level 6")
	up.history = old.history
	check(up.history.size() == 1 and int(up.history[0].level) == 5, "history holds the level 5 sheet")
	up.xp = 14500
	var back := Progression.restore(up, 0)
	check(Rules.total_level(back) == 5, "restore returns to level 5")
	check(int(back.xp) == 14500, "restore keeps XP")
	check(back.history.size() == 2 and int(back.history[1].level) == 6, "the replaced level 6 sheet is backed up too")
	var again := Progression.restore(back, 1)
	check(Rules.total_level(again) == 6, "a restore can be undone")
	var long := Rules.new_character()
	for i in Progression.HISTORY_MAX + 5:
		Progression.push_history(long, "b%d" % i)
	check(long.history.size() == Progression.HISTORY_MAX, "history is capped")
	check(not Progression.diff_lines(ch, up).is_empty(), "diff lists changes")

func _plan() -> void:
	var ch := premade("Grukka")
	var rows := Progression.plan_rows(ch)
	check(rows.size() == 20 and rows[4].taken and not rows[5].taken, "plan: five levels taken")
	var plan: Array = []
	for i in 20:
		plan.append({"class": "", "note": ""})
	plan[5] = {"class": "fighter", "note": "ASI STR"}
	plan[6] = {"class": "wizard", "note": "dip"}
	ch.level_plan = plan
	check(Progression.planned_class(ch) == "fighter", "planned class for level 6")
	rows = Progression.plan_rows(ch)
	check(rows[5].gains.has("ASI / feat"), "plan row 6 shows the ASI")
	check(str(rows[6].warn).contains("INT 13"), "plan warns about the wizard prerequisite")
	check(int(rows[6].class_level) == 1, "wizard dip is wizard level 1")

func _wizard() -> void:
	# Walk every step with defaults for each premade, then a multiclass.
	for p in CharacterStore.premades():
		var w := LevelUpWizard.new(p)
		var got := [{}]
		w.finished.connect(func(sh, _l): got[0] = sh)
		add_child(w)
		await get_tree().process_frame
		var guard := 0
		while is_instance_valid(w) and guard < 15:
			w.next_step(true)
			guard += 1
			await get_tree().process_frame
		check(not got[0].is_empty() and Rules.total_level(got[0]) == Rules.total_level(p) + 1, "wizard levels up " + str(p.name))
	var pip := premade("Pip")
	var w2 := LevelUpWizard.new(pip)
	var got2 := [{}]
	w2.finished.connect(func(sh, _l): got2[0] = sh)
	add_child(w2)
	w2.pick_class("fighter")
	await get_tree().process_frame
	w2.next_step()
	check(w2.step_name() == "hp", "multiclass passes the class step when prerequisites are met")
	var g := 0
	while is_instance_valid(w2) and g < 15:
		w2.next_step(true)
		g += 1
		await get_tree().process_frame
	check(Rules.class_level(got2[0], "fighter") == 1 and got2[0].get("fighting_styles", []).size() == 1, "multiclass fighter picked a fighting style")
	# Prerequisites block unless overridden.
	var w3 := LevelUpWizard.new(premade("Grukka"))
	add_child(w3)
	w3.pick_class("wizard")
	w3.next_step()
	check(w3.step_name() == "class", "unmet multiclass prerequisite blocks the class step")
	w3.allow_unmet = true
	w3.next_step()
	check(w3.step_name() == "hp", "the DM-approved box allows it")
	w3.close()
	await get_tree().process_frame

func _session() -> void:
	Session.start_offline("Tester", 20, 14)
	var ch := premade("Brannoc")
	var cid := Session.add_character(ch, 2, Vector2i(3, 3))
	var c: Dictionary = Session.engine.C(cid)
	var sid: String = Session.sheets[cid].id
	made_ids.append(sid)
	check(sid != "", "a premade gets an id in the game")
	check(Session.advancement() == "milestone", "milestone advancement by default")
	c.hp = c.max_hp - 7
	c.slots_used[0] = 2
	var up := Progression.apply_level(Session.sheets[cid], {"class": "cleric", "hp": 8})
	Session._set_sheet(2, c, up, "Before level 6")
	check(Rules.total_level(Session.sheets[cid]) == 5, "player can't level without a grant")
	Session._grant_level([c])
	check(Session.pending_levels(cid) == 1, "DM grant gives one pending level")
	var max_before := int(c.max_hp)
	Session._set_sheet(2, c, up, "Before level 6")
	check(Rules.total_level(Session.sheets[cid]) == 6, "granted level is accepted")
	check(int(c.max_hp) > max_before and int(c.hp) == int(c.max_hp) - 7, "damage carries over the level-up")
	check(int(c.slots_used[0]) == 2, "spent slots carry over")
	check(int(c.level) == 6, "combatant rebuilt at level 6")
	var saved := CharacterStore.get_character(sid)
	check(not saved.is_empty() and saved.history.size() == 1 and int(saved.history[0].level) == 5, "owner's copy saved with a level 5 backup")
	# Can't skip ahead.
	var up2 := Progression.apply_level(Session.sheets[cid], {"class": "cleric"})
	Session._set_sheet(2, c, up2, "Before level 7")
	check(Rules.total_level(Session.sheets[cid]) == 6, "no second level without another grant")
	# Restore the backup (rolling back the level).
	var full := CharacterStore.get_character(sid)
	var back := Progression.restore(full, 0)
	Session._set_sheet(2, c, back, "Before restoring \"Before level 6\"")
	check(Rules.total_level(Session.sheets[cid]) == 5, "rolled back to level 5")
	check(Session.pending_levels(cid) == 1, "the granted level is available again after a rollback")
	check(CharacterStore.get_character(sid).history.size() == 2, "the rollback itself is backed up")
	# XP mode.
	Session._handle(1, {"type": "dm_advancement", "mode": "xp"})
	check(Session.advancement() == "xp", "switched to XP")
	Session.sheets[cid].xp = 0
	Session.sheets[cid].level_cap = 0
	Session._award_xp([c], 6500, false)
	check(int(Session.sheets[cid].xp) == 6500 and Session.pending_levels(cid) == 0, "6500 XP is still level 5")
	Session._award_xp([c], 7500, false)
	check(Session.pending_levels(cid) == 1, "14000 XP: level 6 available")
	var gid := Session.add_monster("goblin", Vector2i(8, 8))
	Session.engine.C(gid).hp = 0
	Session.engine.C(gid).dead = true
	check(Session.encounter_xp() == 50, "a dead goblin is worth 50 XP")
	Session._award_encounter_xp()
	check(int(Session.sheets[cid].xp) == 14050 and Session.encounter_xp() == 0, "encounter XP awarded once")
	# Combat blocks level changes for players.
	var foe := Session.add_monster("orc", Vector2i(10, 10))
	Session.engine.start_combat()
	var up3 := Progression.apply_level(Session.sheets[cid], {"class": "cleric"})
	Session._set_sheet(2, c, up3, "Before level 6")
	check(Rules.total_level(Session.sheets[cid]) == 5, "no level-ups mid-fight")
	Session.engine.end_combat()
	Session._set_sheet(2, c, up3, "Before level 6")
	check(Rules.total_level(Session.sheets[cid]) == 6, "level-up after the fight")
	# Another player can't touch it.
	var hack := Progression.apply_level(Session.sheets[cid], {"class": "cleric"})
	Session.sheets[cid].level_cap = 20
	Session._set_sheet(3, c, hack, "x")
	check(Rules.total_level(Session.sheets[cid]) == 6, "only the owner (or DM) can change a sheet")
	Session.leave()
	await get_tree().process_frame
