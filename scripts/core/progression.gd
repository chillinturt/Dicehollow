class_name Progression
extends RefCounted
## Character advancement (5e 2014): XP and milestone levelling, what each level unlocks,
## multiclass prerequisites, applying a level-up, the level plan and the sheet history used to roll back.
##
## Character fields used here (all optional, so older saves keep working):
##   xp: int                 experience points (XP advancement)
##   level_cap: int          highest level the DM has granted (milestone advancement)
##   level_log: [class_id]   the class taken at each character level, in order
##   level_plan: [{class, note}]  planned class and a note for each character level (index = level - 1)
##   hp_rolls: {class_id: [int]}  hit points gained at each level of that class beyond the first character level
##   history: [{t, label, level, summary, data}]  earlier versions of the sheet, newest last

const XP_TABLE := [0, 300, 900, 2700, 6500, 14000, 23000, 34000, 48000, 64000, 85000, 100000, 120000, 140000, 165000, 195000, 225000, 265000, 305000, 355000]
const HISTORY_MAX := 40
const MAX_LEVEL := 20

# Known / active counts by class level (highest key at or below the level applies).
const MANEUVERS_KNOWN := {3: 3, 7: 5, 10: 7, 15: 9}
const METAMAGIC_KNOWN := {3: 2, 10: 3, 17: 4}
const INVOCATIONS_KNOWN := {2: 2, 5: 3, 7: 4, 9: 5, 12: 6, 15: 7, 18: 8}
const INFUSIONS_ACTIVE := {2: 2, 6: 3, 10: 4, 14: 5, 18: 6}
const EXPERTISE_BY_CLASS := {"rogue": {1: 2, 6: 4}, "bard": {3: 2, 10: 4}}
## Skills a class grants when you multiclass into it (PHB p.164).
const MC_SKILLS := {"bard": 1, "ranger": 1, "rogue": 1}

## Feat prerequisites (PHB / XGtE / TCoE). Checked against the character before the level is applied.
const FEAT_PREREQ := {
	"war_caster": {"spellcasting": true},
	"elemental_adept": {"spellcasting": true},
	"spell_sniper": {"spellcasting": true},
	"ritual_caster": {"any": {"int": 13, "wis": 13}},
	"heavy_armor_master": {"armor": "heavy"},
	"defensive_duelist": {"all": {"dex": 13}},
	"inspiring_leader": {"all": {"cha": 13}},
	"skulker": {"all": {"dex": 13}},
}

## Plain-language notes for players new to the game, shown beside each choice.
const HELP := {
	"class": "Each new level goes into one class. Staying in your class unlocks its higher features; taking a level in a new class (multiclassing) trades that for a mix of both. Multiclassing needs 13 or more in the main ability of your current classes and the new one.",
	"hp": "Your maximum hit points grow every level by one roll of the class's hit die plus your Constitution modifier (minimum 1). Taking the average is the safe, common choice.",
	"subclass": "Your subclass is your specialty within the class. It grants extra features now and at later levels, and the choice is permanent unless your DM allows a change.",
	"asi": "An Ability Score Improvement raises one score by 2 or two scores by 1 (no score above 20). Many tables let you take a feat instead: a special talent with its own benefits.",
	"options": "These are class choices you learn now, such as fighting styles or maneuvers. Hover any option to read what it does. Many of them can be swapped when you gain a level.",
	"skills": "Proficiency adds your proficiency bonus to checks with a skill. Expertise doubles that bonus.",
	"spells": "Pick the spells you learn at this level. Known casters (bards, sorcerers, warlocks, rangers) keep these until they swap one at a level-up. Prepared casters (clerics, druids, paladins, artificers, wizards) can change their list after every long rest.",
	"review": "Check the changes below. Confirming saves a backup of your current sheet first, so you can restore it from the History tab if you change your mind.",
}

# ================================================================ XP and level caps

static func level_for_xp(xp: int) -> int:
	var lv := 1
	for i in XP_TABLE.size():
		if xp >= int(XP_TABLE[i]):
			lv = i + 1
	return lv

## XP needed to reach `level`.
static func xp_for_level(level: int) -> int:
	return int(XP_TABLE[clampi(level, 1, MAX_LEVEL) - 1])

## The highest level this sheet may have in a game using `mode` ("xp" or "milestone").
static func allowed_level(sheet: Dictionary, mode: String) -> int:
	var total := Rules.total_level(sheet)
	var target: int = level_for_xp(int(sheet.get("xp", 0))) if mode == "xp" else int(sheet.get("level_cap", 0))
	return clampi(maxi(total, target), 1, MAX_LEVEL)

static func pending_levels(sheet: Dictionary, mode: String) -> int:
	return allowed_level(sheet, mode) - Rules.total_level(sheet)

## Value from a {level: count} table for class level `lv`.
static func table_count(table: Dictionary, lv: int) -> int:
	var best := 0
	for k in table:
		if int(k) <= lv:
			best = maxi(best, int(table[k]))
	return best

# ================================================================ level log and plan

## The class taken at each character level, oldest first. Characters saved before the log existed
## (or edited in the builder since) get one rebuilt: the first class's levels, then the others.
static func level_log(ch: Dictionary) -> Array:
	var want: Dictionary = {}
	for c in ch.get("classes", []):
		want[str(c.id)] = int(c.level)
	var out: Array = []
	var used: Dictionary = {}
	for cid in ch.get("level_log", []):
		cid = str(cid)
		if int(used.get(cid, 0)) < int(want.get(cid, 0)):
			out.append(cid)
			used[cid] = int(used.get(cid, 0)) + 1
	# The first character level must belong to the first class (it sets saves and full proficiencies).
	var first: String = str(ch.classes[0].id) if ch.get("classes", []).size() > 0 else ""
	if out.size() > 0 and out[0] != first and int(want.get(first, 0)) > 0:
		out = []
		used = {}
	for c in ch.get("classes", []):
		var cid := str(c.id)
		while int(used.get(cid, 0)) < int(want.get(cid, 0)):
			out.append(cid)
			used[cid] = int(used.get(cid, 0)) + 1
	return out

## The level plan padded to 20 entries: {class, note}. Levels already taken show the class taken.
static func level_plan(ch: Dictionary) -> Array:
	var plan: Array = []
	var saved: Array = ch.get("level_plan", [])
	var taken := level_log(ch)
	for i in MAX_LEVEL:
		var e: Dictionary = saved[i].duplicate() if i < saved.size() and saved[i] is Dictionary else {}
		var entry := {"class": str(e.get("class", "")), "note": str(e.get("note", ""))}
		if i < taken.size():
			entry["class"] = taken[i]
			entry["taken"] = true
		plan.append(entry)
	return plan

## The class the plan suggests for the next level, or "".
static func planned_class(ch: Dictionary) -> String:
	var total := Rules.total_level(ch)
	if total >= MAX_LEVEL:
		return ""
	var plan := level_plan(ch)
	return str(plan[total].get("class", ""))

## Walks the plan from level 1 to 20 and describes what each level brings, for the planner table.
## Returns [{level, class, class_level, gains: [text], warn: text, taken: bool, note}].
static func plan_rows(ch: Dictionary) -> Array:
	var plan := level_plan(ch)
	var rows: Array = []
	var sim := {"classes": []}
	for k in ch.keys():
		if k != "history":
			sim[k] = ch[k]
	sim = sim.duplicate(true)
	sim.classes = []
	for i in MAX_LEVEL:
		var e: Dictionary = plan[i]
		var cid: String = e.get("class", "")
		var row := {"level": i + 1, "class": cid, "class_level": 0, "gains": [], "warn": "", "taken": e.get("taken", false), "note": e.get("note", "")}
		if cid == "" or Data.cls(cid).is_empty():
			rows.append(row)
			continue
		if Rules.class_level(sim, cid) == 0 and not sim.classes.is_empty():
			var unmet := multiclass_unmet(_with_scores_of(sim, ch), cid)
			if not unmet.is_empty():
				row.warn = "Multiclass needs " + "; ".join(unmet)
		var g := gains(sim, cid)
		row.class_level = g.class_level
		var real_sub := Rules.subclass_of(ch, cid)
		var parts: Array = []
		if g.new_class and not sim.classes.is_empty():
			parts.append("multiclass")
		if i + 1 > 1 and Rules.prof_bonus(i + 1) > Rules.prof_bonus(i):
			parts.append("PB +%d" % Rules.prof_bonus(i + 1))
		for fid in g.features:
			parts.append(Data.feature(fid).get("name", Data.pretty(fid)))
		if g.subclass_choice or (real_sub != "" and g.class_level == int(Data.cls(cid).get("subclass_level", 3))):
			parts.append(Data.cls(cid).get("subclass_label", "Subclass") + (": " + Data.subclass(cid, real_sub).get("name", "") if real_sub != "" else ""))
		for fid in g.subclass_features:
			parts.append(Data.feature(fid).get("name", Data.pretty(fid)))
		if g.asi:
			parts.append("ASI / feat")
		if g.new_spell_level > g.old_spell_level:
			parts.append("level %d spells" % g.new_spell_level)
		row.gains = parts
		rows.append(row)
		# Advance the simulation.
		var found := false
		for c in sim.classes:
			if c.id == cid:
				c.level = int(c.level) + 1
				found = true
		if not found:
			sim.classes.append({"id": cid, "level": 1, "subclass": real_sub})
		for c in sim.classes:
			if c.id == cid and str(c.get("subclass", "")) == "" and real_sub != "":
				c.subclass = real_sub
	return rows

static func _with_scores_of(sim: Dictionary, real: Dictionary) -> Dictionary:
	var d := sim.duplicate(true)
	d.base_scores = real.get("base_scores", {})
	d.asi = real.get("asi", [])
	d.feats = real.get("feats", [])
	return d

# ================================================================ multiclassing

## Unmet multiclass prerequisites for adding a level of `class_id` (empty when allowed).
## You need the new class's prerequisite and those of every class you already have.
static func multiclass_unmet(ch: Dictionary, class_id: String) -> Array:
	if Rules.class_level(ch, class_id) > 0 or ch.get("classes", []).is_empty():
		return []
	var scores := Rules.final_scores(ch)
	var out: Array = []
	var ids: Array = [class_id]
	for c in ch.classes:
		if not c.id in ids:
			ids.append(c.id)
	for cid in ids:
		var t := prereq_unmet(cid, scores)
		if t != "":
			out.append(t)
	return out

## "" if the scores meet the class's multiclass prerequisite, else e.g. "Paladin: STR 13 and CHA 13".
static func prereq_unmet(class_id: String, scores: Dictionary) -> String:
	var prim: Array = Data.cls(class_id).get("primary", [])
	if prim.is_empty():
		return ""
	var any_of: bool = class_id == "fighter"  # Strength 13 or Dexterity 13
	var ok: bool = not any_of
	for a in prim:
		var met: bool = int(scores.get(a, 10)) >= 13
		ok = (ok or met) if any_of else (ok and met)
	if ok:
		return ""
	var names: Array = prim.map(func(a): return "%s 13" % str(a).to_upper())
	return "%s: %s" % [Data.cls(class_id).get("name", class_id), (" or " if any_of else " and ").join(names)]

static func prereq_text(class_id: String) -> String:
	var prim: Array = Data.cls(class_id).get("primary", [])
	var names: Array = prim.map(func(a): return "%s 13" % str(a).to_upper())
	return (" or " if class_id == "fighter" else " and ").join(names)

# ================================================================ what a level brings

## A copy of ch with one more level in class_id (no other choices made).
static func with_level(ch: Dictionary, class_id: String, subclass := "") -> Dictionary:
	var d := strip_history(ch)
	var found := false
	for c in d.classes:
		if c.id == class_id:
			c.level = int(c.level) + 1
			if subclass != "":
				c.subclass = subclass
			found = true
	if not found:
		d.classes.append({"id": class_id, "level": 1, "subclass": subclass})
	return d

## What taking the next level in class_id grants. Keys:
##   class_level, total, hit_die, new_class, multiclass, features, subclass_features, subclass_choice,
##   asi, pb_up, old_spell_level, new_spell_level, mc_armor, mc_weapons, mc_skills, slots_before, slots_after
static func gains(ch: Dictionary, class_id: String, subclass := "") -> Dictionary:
	var cd := Data.cls(class_id)
	var lv := Rules.class_level(ch, class_id) + 1
	var sub := subclass if subclass != "" else Rules.subclass_of(ch, class_id)
	var total := Rules.total_level(ch) if not ch.get("classes", []).is_empty() else 0
	var out := {"class": class_id, "class_level": lv, "total": total + 1, "hit_die": int(cd.get("hit_die", 8)),
		"new_class": lv == 1, "multiclass": lv == 1 and not ch.get("classes", []).is_empty(),
		"features": [], "subclass_features": [], "subclass": sub}
	for fid in cd.get("features", {}).get(str(lv), []):
		out.features.append(fid)
	var need_sub: bool = sub == "" and lv >= int(cd.get("subclass_level", 3)) and not cd.get("subclasses", []).is_empty()
	out.subclass_choice = need_sub
	if sub != "":
		var sd := Data.subclass(class_id, sub)
		# A subclass picked now grants every feature up to this level that wasn't there before.
		var from_lv: int = lv if Rules.subclass_of(ch, class_id) != "" else 1
		for k in sd.get("features", {}):
			if int(k) >= from_lv and int(k) <= lv:
				for fid in sd.features[k]:
					out.subclass_features.append(fid)
	out.asi = lv in cd.get("asi_levels", []).map(func(x): return int(x))
	out.pb_up = total >= 1 and Rules.prof_bonus(total + 1) > Rules.prof_bonus(total)
	var before := {"id": class_id, "level": lv - 1, "subclass": sub}
	var after := {"id": class_id, "level": lv, "subclass": sub}
	out.old_spell_level = Rules.max_spell_level_for(before) if lv > 1 else 0
	out.new_spell_level = Rules.max_spell_level_for(after)
	out.mc_armor = cd.get("mc_armor", []) if out.multiclass else []
	out.mc_weapons = cd.get("mc_weapons", []) if out.multiclass else []
	out.mc_skills = int(MC_SKILLS.get(class_id, 0)) if out.multiclass else 0
	var nxt := with_level(ch, class_id, sub) if not ch.get("classes", []).is_empty() else {"classes": [after]}
	out.slots_before = Rules.spell_slots(ch).slots if not ch.get("classes", []).is_empty() else []
	out.slots_after = Rules.spell_slots(nxt).slots
	out.pact_before = Rules.spell_slots(ch).pact if not ch.get("classes", []).is_empty() else {"count": 0, "level": 0}
	out.pact_after = Rules.spell_slots(nxt).pact
	return out

## Average hit points for one level of a hit die (fixed value, PHB).
static func hp_average(hit_die: int) -> int:
	return int(hit_die / 2) + 1

# ================================================================ class option limits

## Class choices with a limit: [{key, title, options, limit, chosen}] for this character.
## `key` is the character field holding the picks.
static func option_limits(ch: Dictionary) -> Array:
	var st := Rules.derive(ch)
	var f: Dictionary = st.features
	var feats: Array = st.feats
	var cl: Dictionary = st.class_levels
	var out: Array = []
	if f.has("fighting_style") or f.has("additional_fighting_style") or "fighting_initiate" in feats:
		var n := (1 if f.has("fighting_style") else 0) + (1 if f.has("additional_fighting_style") else 0) + (1 if "fighting_initiate" in feats else 0)
		out.append({"key": "fighting_styles", "title": "Fighting Styles", "options": Data.FIGHTING_STYLES, "limit": n})
	var man := 0
	if f.has("combat_superiority"):
		man += table_count(MANEUVERS_KNOWN, int(cl.get("fighter", 0)))
	if "martial_adept" in feats:
		man += 2
	if man > 0:
		out.append({"key": "maneuvers", "title": "Maneuvers", "options": Data.MANEUVERS, "limit": man})
	var mm := 0
	if f.has("metamagic"):
		mm += table_count(METAMAGIC_KNOWN, int(cl.get("sorcerer", 0)))
	if "metamagic_adept" in feats:
		mm += 2
	if mm > 0:
		out.append({"key": "metamagic", "title": "Metamagic", "options": Data.METAMAGIC, "limit": mm})
	var inv := 0
	if f.has("eldritch_invocations"):
		inv += table_count(INVOCATIONS_KNOWN, int(cl.get("warlock", 0)))
	if "eldritch_adept" in feats:
		inv += 1
	if inv > 0:
		out.append({"key": "invocations", "title": "Eldritch Invocations", "options": Data.INVOCATIONS, "limit": inv})
	if f.has("infuse_item"):
		out.append({"key": "infusions", "title": "Infusions (active)", "options": Data.INFUSIONS, "limit": table_count(INFUSIONS_ACTIVE, int(cl.get("artificer", 0)))})
	for o in out:
		o["chosen"] = ch.get(o.key, []).size()
	return out

## Expertise slots from class levels and feats.
static func expertise_limit(ch: Dictionary) -> int:
	var n := 0
	for cid in EXPERTISE_BY_CLASS:
		n += table_count(EXPERTISE_BY_CLASS[cid], Rules.class_level(ch, cid))
	if "skill_expert" in Rules.all_feats(ch):
		n += 1
	return n

## Keyed choices a newly gained feature asks for (draconic ancestry, armor model...).
static func feature_choices(features: Array) -> Array:
	var out: Array = []
	if "dragon_ancestor" in features or "draconic_resilience" in features:
		out.append({"key": "dragon_ancestor", "title": "Draconic ancestry", "items": [["acid", "Acid (black/copper)"], ["cold", "Cold (silver/white)"], ["fire", "Fire (brass/gold/red)"], ["lightning", "Lightning (blue/bronze)"], ["poison", "Poison (green)"]], "default": "fire"})
	if "armor_model" in features:
		out.append({"key": "armor_model", "title": "Armor model", "items": [["guardian", "Guardian (Thunder Gauntlets, Defensive Field)"], ["infiltrator", "Infiltrator (Lightning Launcher, +5 ft speed)"]], "default": "guardian"})
	return out

## "" if the character meets the feat's prerequisite, else what's missing.
static func feat_unmet(ch: Dictionary, feat_id: String) -> String:
	var p: Dictionary = FEAT_PREREQ.get(feat_id, {})
	if p.is_empty():
		return ""
	var st := Rules.derive(ch)
	if p.get("spellcasting", false) and st.casting.is_empty() and st.pact.count == 0:
		return "the ability to cast at least one spell"
	if p.has("armor") and not str(p.armor) in st.armor_prof:
		return "proficiency with %s armor" % p.armor
	if p.has("all"):
		for a in p.all:
			if int(st.scores.get(a, 10)) < int(p.all[a]):
				return "%s %d" % [str(a).to_upper(), int(p.all[a])]
	if p.has("any"):
		var ok := false
		for a in p.any:
			if int(st.scores.get(a, 10)) >= int(p.any[a]):
				ok = true
		if not ok:
			return " or ".join(p.any.keys().map(func(a): return "%s %d" % [str(a).to_upper(), int(p.any[a])]))
	return ""

# ================================================================ applying a level

## Apply one level-up. `pick` keys (all optional except class):
##   class, subclass, hp (int gained before CON), asi {type: "asi"|"feat", a, b, feat, feat_choice},
##   picks {field: [ids]} (fighting_styles, maneuvers...), skills [ids], expertise [ids],
##   spells {class_id: [ids]}, spellbook [ids], choices {key: value}, note
static func apply_level(ch: Dictionary, pick: Dictionary) -> Dictionary:
	var cid: String = pick["class"]
	var old_log := level_log(ch)
	var d := with_level(ch, cid, str(pick.get("subclass", "")))
	d.history = ch.get("history", []).duplicate(true)
	var cd := Data.cls(cid)
	var lv := Rules.class_level(d, cid)
	# Hit points: the first character level is always the die's maximum.
	var first_level: bool = Rules.total_level(d) == 1 and lv == 1 and d.classes.size() == 1
	if not first_level:
		var rolls: Dictionary = d.get("hp_rolls", {}).duplicate(true)
		var arr: Array = rolls.get(cid, []).duplicate()
		var idx: int = lv - (2 if d.classes[0].id == cid else 1)
		while arr.size() < idx:
			arr.append(hp_average(int(cd.get("hit_die", 8))))
		var gained: int = clampi(int(pick.get("hp", hp_average(int(cd.get("hit_die", 8))))), 1, int(cd.get("hit_die", 8)))
		if arr.size() > idx:
			arr[idx] = gained
		else:
			arr.append(gained)
		rolls[cid] = arr
		d.hp_rolls = rolls
	# Ability score improvement or feat.
	var asi: Dictionary = pick.get("asi", {})
	if not asi.is_empty():
		var entry := {"class": cid, "level": lv, "type": str(asi.get("type", "asi"))}
		if entry.type == "feat":
			entry.feat = str(asi.get("feat", ""))
			if asi.has("feat_choice") and str(asi.feat_choice) != "":
				var fc: Dictionary = d.get("feat_choices", {}).duplicate()
				fc[entry.feat] = str(asi.feat_choice)
				d.feat_choices = fc
		else:
			entry.a = str(asi.get("a", "str"))
			entry.b = str(asi.get("b", entry.a))
		var arr2: Array = d.get("asi", []).duplicate(true)
		arr2.append(entry)
		d.asi = arr2
		sort_asi(d)
	for key in pick.get("picks", {}):
		d[key] = (pick.picks[key] as Array).duplicate()
	for s in pick.get("skills", []):
		if not s in d.skills:
			d.skills.append(s)
	for s in pick.get("expertise", []):
		if not s in d.expertise:
			d.expertise.append(s)
	var spells: Dictionary = d.get("spells", {}).duplicate(true)
	for k in pick.get("spells", {}):
		spells[k] = (pick.spells[k] as Array).duplicate()
	d.spells = spells
	if pick.has("spellbook"):
		d.spellbook = (pick.spellbook as Array).duplicate()
	var choices: Dictionary = d.get("choices", {}).duplicate()
	for k in pick.get("choices", {}):
		choices[k] = pick.choices[k]
	d.choices = choices
	old_log.append(cid)
	d.level_log = old_log
	if str(pick.get("note", "")).strip_edges() != "":
		var plan := level_plan(d)
		var n: int = Rules.total_level(d)
		var saved: Array = d.get("level_plan", []).duplicate(true)
		while saved.size() < n:
			saved.append({"class": "", "note": ""})
		saved[n - 1] = {"class": cid, "note": str(pick.note).strip_edges()}
		d.level_plan = saved
	return d

## Keep ASI entries in the same order as Rules.asi_slots (the builder pairs them up by position),
## matching each slot to the entry made for that class and level.
static func sort_asi(ch: Dictionary) -> void:
	var slots := Rules.asi_slots(ch)
	var pool: Array = ch.get("asi", []).duplicate(true)
	var out: Array = []
	for sl in slots:
		var hit := -1
		for i in pool.size():
			if str(pool[i].get("class", "")) == sl.class and int(pool[i].get("level", 0)) == int(sl.level):
				hit = i
				break
		if hit < 0:
			# Older saves have entries without class/level: take them in order.
			for i in pool.size():
				if not pool[i].has("class"):
					hit = i
					break
		if hit >= 0:
			var e: Dictionary = pool[hit]
			pool.remove_at(hit)
			e["class"] = sl.class
			e["level"] = int(sl.level)
			out.append(e)
		else:
			out.append({"class": sl.class, "level": int(sl.level), "type": "asi", "a": "str", "b": "str"})
	ch.asi = out

# ================================================================ history

static func strip_history(ch: Dictionary) -> Dictionary:
	var d := ch.duplicate(true)
	d.erase("history")
	return d

## Save a copy of the sheet as it is now into its history (newest last, oldest dropped past HISTORY_MAX).
static func push_history(ch: Dictionary, label: String) -> void:
	var hist: Array = ch.get("history", [])
	hist.append({"t": int(Time.get_unix_time_from_system()), "label": label, "level": Rules.total_level(ch),
		"summary": Rules.class_summary(ch), "data": strip_history(ch)})
	while hist.size() > HISTORY_MAX:
		hist.pop_front()
	ch.history = hist

## The sheet as it was at history entry `index`. The current version goes into the history first,
## so a restore can itself be undone. XP and the DM's level grant are kept (they aren't the player's to roll back).
static func restore(ch: Dictionary, index: int) -> Dictionary:
	var hist: Array = ch.get("history", [])
	if index < 0 or index >= hist.size():
		return ch
	var entry: Dictionary = hist[index]
	var cur := ch.duplicate(true)
	push_history(cur, "Before restoring \"%s\"" % entry.get("label", "backup"))
	var d: Dictionary = (entry.data as Dictionary).duplicate(true)
	d.history = cur.history
	d.id = ch.get("id", d.get("id", ""))
	d.xp = int(ch.get("xp", d.get("xp", 0)))
	d.level_cap = int(ch.get("level_cap", d.get("level_cap", 0)))
	d.portrait = ch.get("portrait", d.get("portrait", ""))
	return d

## Short "what changed" lines between two sheets, for the review step and the history list.
static func diff_lines(a: Dictionary, b: Dictionary) -> Array:
	var sa := Rules.derive(a)
	var sb := Rules.derive(b)
	var out: Array = []
	var num = func(label: String, x, y) -> void:
		if str(x) != str(y):
			out.append("%s: %s → %s" % [label, str(x), str(y)])
	num.call("Level", sa.level, sb.level)
	num.call("Classes", Rules.class_summary(a), Rules.class_summary(b))
	num.call("Max HP", sa.max_hp, sb.max_hp)
	num.call("Proficiency bonus", "+%d" % sa.prof, "+%d" % sb.prof)
	num.call("AC", sa.ac, sb.ac)
	num.call("Speed", "%d ft" % sa.speed, "%d ft" % sb.speed)
	num.call("Initiative", Rules.fmt_mod(sa.initiative), Rules.fmt_mod(sb.initiative))
	num.call("Hit dice", sa.hit_dice, sb.hit_dice)
	for ab in Data.ABILITIES:
		num.call(ab.to_upper(), sa.scores[ab], sb.scores[ab])
	num.call("Attacks per Attack action", sa.vals.attacks, sb.vals.attacks)
	var slot_txt = func(st: Dictionary) -> String:
		var parts: PackedStringArray = []
		for i in st.slots.size():
			parts.append("%d×L%d" % [int(st.slots[i]), i + 1])
		if st.pact.count > 0:
			parts.append("pact %d×L%d" % [int(st.pact.count), int(st.pact.level)])
		return ", ".join(parts) if not parts.is_empty() else "none"
	num.call("Spell slots", slot_txt.call(sa), slot_txt.call(sb))
	var fa: Array = sa.feature_info.map(func(x): return x.name)
	var new_f: Array = []
	for fi in sb.feature_info:
		if not fi.name in fa and not fi.name in new_f:
			new_f.append(fi.name)
	if not new_f.is_empty():
		out.append("New features: " + ", ".join(new_f))
	var lost: Array = []
	var fb: Array = sb.feature_info.map(func(x): return x.name)
	for n in fa:
		if not n in fb and not n in lost:
			lost.append(n)
	if not lost.is_empty():
		out.append("Features removed: " + ", ".join(lost))
	for e in sb.casting:
		var before: Array = []
		for e2 in sa.casting:
			if e2["class"] == e["class"]:
				before = e2.spells
		var added: Array = e.spells.filter(func(x): return not x in before).map(func(x): return Data.spell(x).get("name", x))
		var removed: Array = before.filter(func(x): return not x in e.spells).map(func(x): return Data.spell(x).get("name", x))
		if not added.is_empty():
			out.append("%s spells added: %s" % [e.name, ", ".join(added)])
		if not removed.is_empty():
			out.append("%s spells removed: %s" % [e.name, ", ".join(removed)])
	var sk_new: Array = sb.skill_prof.filter(func(x): return not x in sa.skill_prof).map(func(x): return Data.pretty(x))
	if not sk_new.is_empty():
		out.append("New skill proficiencies: " + ", ".join(sk_new))
	var ex_new: Array = b.get("expertise", []).filter(func(x): return not x in a.get("expertise", [])).map(func(x): return Data.pretty(x))
	if not ex_new.is_empty():
		out.append("New expertise: " + ", ".join(ex_new))
	var fe_new: Array = sb.feats.filter(func(x): return not x in sa.feats).map(func(x): return Data.feat(x).get("name", x))
	if not fe_new.is_empty():
		out.append("New feats: " + ", ".join(fe_new))
	for key in ["fighting_styles", "maneuvers", "metamagic", "invocations", "infusions"]:
		var na: Array = b.get(key, []).filter(func(x): return not x in a.get(key, []))
		if not na.is_empty():
			out.append("%s: + %s" % [Data.pretty(key), ", ".join(na.map(func(x): return Data.pretty(x)))])
	var ap_new: Array = sb.armor_prof.filter(func(x): return not x in sa.armor_prof)
	var wp_new: Array = sb.weapon_prof.filter(func(x): return not x in sa.weapon_prof)
	if not ap_new.is_empty() or not wp_new.is_empty():
		out.append("New proficiencies: " + ", ".join((ap_new + wp_new).map(func(x): return Data.pretty(x))))
	return out
