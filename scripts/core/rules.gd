class_name Rules
extends RefCounted
## Pure 5e (2014) rules helpers. `derive(character)` turns a saved character into combat-ready stats.

static func mod(score: int) -> int:
	return floori((score - 10) / 2.0)

static func prof_bonus(level: int) -> int:
	return 2 + int((maxi(level, 1) - 1) / 4)

static func fmt_mod(n: int) -> String:
	return ("+%d" % n) if n >= 0 else str(n)

static func new_character() -> Dictionary:
	return {
		"version": 1, "id": "", "name": "New Hero", "player": "",
		"race": "human", "subrace": "", "race_asi_choice": [],
		"background": "soldier", "alignment": "",
		"score_method": "point_buy",
		"base_scores": {"str": 8, "dex": 8, "con": 8, "int": 8, "wis": 8, "cha": 8},
		"classes": [{"id": "fighter", "level": 1, "subclass": ""}],
		"skills": [], "expertise": [],
		"feats": [], "feat_choices": {}, "asi": [],
		"fighting_styles": [], "maneuvers": [], "metamagic": [], "invocations": [], "infusions": [],
		"choices": {},
		"spells": {},
		"equipment": {"armor": "", "shield": false, "weapons": [], "weapon_bonus": 0, "armor_bonus": 0},
		"portrait": "", "portrait_template": "", "color": "#7a5cff", "notes": "",
		"xp": 0, "level_cap": 0, "level_log": [], "level_plan": [], "hp_rolls": {}, "history": [],
	}

static func total_level(ch: Dictionary) -> int:
	var t = 0
	for c in ch.get("classes", []):
		t += int(c.level)
	return maxi(t, 1)

static func class_level(ch: Dictionary, class_id: String) -> int:
	for c in ch.get("classes", []):
		if c.id == class_id:
			return int(c.level)
	return 0

static func subclass_of(ch: Dictionary, class_id: String) -> String:
	for c in ch.get("classes", []):
		if c.id == class_id:
			return str(c.get("subclass", ""))
	return ""

static func class_summary(ch: Dictionary) -> String:
	var parts: PackedStringArray = []
	for c in ch.get("classes", []):
		var cd = Data.cls(c.id)
		var sub = Data.subclass(c.id, str(c.get("subclass", "")))
		var label: String = cd.get("name", c.id)
		if not sub.is_empty():
			label = "%s (%s)" % [label, sub.name]
		parts.append("%s %d" % [label, int(c.level)])
	return " / ".join(parts)

## ASI opportunities: [{class, level}] for every class level that grants one.
static func asi_slots(ch: Dictionary) -> Array:
	var out: Array = []
	for c in ch.get("classes", []):
		for lv in Data.cls(c.id).get("asi_levels", []):
			if int(lv) <= int(c.level):
				out.append({"class": c.id, "level": int(lv)})
	return out

static func final_scores(ch: Dictionary) -> Dictionary:
	var s: Dictionary = {}
	for a in Data.ABILITIES:
		s[a] = int(ch.get("base_scores", {}).get(a, 10))
	var r = Data.race(ch.get("race", ""))
	var sr = Data.subrace(ch.get("race", ""), ch.get("subrace", ""))
	for src in [r.get("asi", {}), sr.get("asi", {})]:
		for a in src:
			s[a] += int(src[a])
	var choice: Dictionary = r.get("asi_choice", {})
	if not choice.is_empty():
		var amt = int(choice.get("amount", 1))
		var picked: Array = ch.get("race_asi_choice", [])
		for i in mini(picked.size(), int(choice.get("count", 0))):
			if s.has(picked[i]):
				s[picked[i]] += amt
	for a in ch.get("asi", []):
		if a.get("type", "asi") == "asi":
			if s.has(a.get("a", "")): s[a.a] += 1
			if s.has(a.get("b", "")): s[a.b] += 1
	for f in all_feats(ch):
		var fd = Data.feat(f)
		var abil: Array = fd.get("ability", [])
		if abil.size() == 1:
			s[abil[0]] += 1
		elif abil.size() > 1:
			var pick: String = ch.get("feat_choices", {}).get(f, abil[0])
			if s.has(pick):
				s[pick] += 1
	var cap = 20
	for a in s:
		var c = cap
		if class_level(ch, "barbarian") >= 20 and a in ["str", "con"]:
			s[a] += 4
			c = 24
		s[a] = mini(s[a], c)
	return s

static func all_feats(ch: Dictionary) -> Array:
	var out: Array = []
	for f in ch.get("feats", []):
		out.append(f)
	for a in ch.get("asi", []):
		if a.get("type", "") == "feat" and a.get("feat", "") != "":
			out.append(a.feat)
	return out

## Caster contribution of a class entry ("full", "half", "artificer", "third", "pact" or "").
static func caster_type(c: Dictionary) -> String:
	var cd = Data.cls(c.id)
	var t = cd.get("caster", null)
	if t == null:
		var sub = Data.subclass(c.id, str(c.get("subclass", "")))
		t = sub.get("caster", null)
	return "" if t == null else str(t)

static func _single_caster_level(t: String, lv: int) -> int:
	match t:
		"full": return lv
		"half": return 0 if lv < 2 else ceili(lv / 2.0)
		"artificer": return ceili(lv / 2.0)
		"third": return 0 if lv < 3 else ceili(lv / 3.0)
	return 0

static func pact_slots(lv: int) -> Dictionary:
	if lv <= 0:
		return {"count": 0, "level": 0}
	var count = 1 if lv == 1 else (2 if lv < 11 else (3 if lv < 17 else 4))
	var level = mini(5, ceili(lv / 2.0))
	return {"count": count, "level": level}

static func spell_slots(ch: Dictionary) -> Dictionary:
	var casters: Array = []
	var pact_lv = 0
	for c in ch.get("classes", []):
		var t = caster_type(c)
		if t == "pact":
			pact_lv += int(c.level)
		elif t != "":
			casters.append({"t": t, "lv": int(c.level)})
	var cl = 0
	if casters.size() == 1:
		cl = _single_caster_level(casters[0].t, casters[0].lv)
	else:
		for k in casters:
			match k.t:
				"full": cl += k.lv
				"half": cl += int(k.lv / 2)
				"artificer": cl += ceili(k.lv / 2.0)
				"third": cl += int(k.lv / 3)
	cl = clampi(cl, 0, 20)
	return {"slots": Data.SLOT_TABLE[cl].duplicate(), "pact": pact_slots(pact_lv), "caster_level": cl}

## Highest spell level a class can learn on its own progression.
static func max_spell_level_for(c: Dictionary) -> int:
	var t = caster_type(c)
	var lv = int(c.level)
	if t == "pact":
		return pact_slots(lv).level
	var cl = _single_caster_level(t, lv)
	return Data.SLOT_TABLE[cl].size()

static func spell_list_id(c: Dictionary) -> String:
	var sub = Data.subclass(c.id, str(c.get("subclass", "")))
	return str(sub.get("spell_list", c.id))

## The wizard's spellbook: leveled spells written in it. Characters saved before spellbooks existed
## have no "spellbook" key; their chosen leveled spells count as the book.
static func wizard_spellbook(ch: Dictionary) -> Array:
	if ch.has("spellbook"):
		return (ch.spellbook as Array).filter(func(x): return Data.spells.has(x))
	return ch.get("spells", {}).get("wizard", []).filter(func(x): return int(Data.spell(x).get("level", 0)) > 0)

## Spells a wizard writes into the spellbook for free: six at 1st level and two more each level.
## Spells copied from scrolls and other books come on top of this.
static func spellbook_free_spells(wizard_level: int) -> int:
	return 6 + 2 * (maxi(1, wizard_level) - 1)

## How many cantrips / leveled spells this class entry may select.
static func spell_counts(ch: Dictionary, c: Dictionary, scores: Dictionary) -> Dictionary:
	var cd = Data.cls(c.id)
	var sub = Data.subclass(c.id, str(c.get("subclass", "")))
	var src: Dictionary = cd if cd.get("caster", null) != null else sub
	var lv = int(c.level)
	var idx = clampi(lv - 1, 0, 19)
	var ab: String = src.get("spell_ability", "int")
	var m = mod(int(scores.get(ab, 10)))
	var cantrips = 0
	if src.has("cantrips"):
		cantrips = int(src.cantrips[idx])
	var spells = 0
	var prep: String = src.get("prepare", "known")
	if src.has("known"):
		spells = int(src.known[idx])
	elif prep == "level":
		spells = maxi(1, m + lv)
	elif prep == "half":
		spells = maxi(1, m + int(lv / 2))
	if c.id == "wizard":
		spells = maxi(1, m + lv)  # prepared from spellbook
	# A class with no spell slots yet (a 1st-level paladin) has no spells to prepare.
	if _single_caster_level(caster_type(c), lv) == 0 and caster_type(c) != "pact":
		spells = 0
	return {"cantrips": cantrips, "spells": spells, "prepare": prep, "ability": ab}

# ---------------------------------------------------------------- derive

static func derive(ch: Dictionary) -> Dictionary:
	var st: Dictionary = {}
	var lvl = total_level(ch)
	var pb = prof_bonus(lvl)
	var scores = final_scores(ch)
	# Magic items (Inventory): Gauntlets of Ogre Power and the like set a score unless it's already higher.
	var mm: Dictionary = Inventory.magic_mods(ch)
	st.magic = mm
	for a in mm.set_score:
		if scores.has(a) and int(mm.set_score[a]) > int(scores[a]):
			scores[a] = int(mm.set_score[a])
	var mods: Dictionary = {}
	for a in scores:
		mods[a] = mod(scores[a])
	st.level = lvl
	st.prof = pb
	st.scores = scores
	st.mods = mods
	var race = Data.race(ch.get("race", ""))
	var sub_race = Data.subrace(ch.get("race", ""), ch.get("subrace", ""))

	# --- class levels, features
	var cl: Dictionary = {}
	var subs: Dictionary = {}
	var feats_set: Dictionary = {}
	var feature_info: Array = []
	for c in ch.get("classes", []):
		cl[c.id] = int(c.level)
		subs[c.id] = str(c.get("subclass", ""))
		var cd = Data.cls(c.id)
		var sd = Data.subclass(c.id, subs[c.id])
		for src in [cd.get("features", {}), sd.get("features", {})]:
			for k in src:
				if int(k) <= int(c.level):
					for fid in src[k]:
						if not feats_set.has(fid):
							feats_set[fid] = true
							var fd = Data.feature(fid)
							feature_info.append({"id": fid, "name": fd.get("name", fid), "desc": fd.get("desc", ""), "src": "%s %s" % [cd.get("name", ""), k], "auto": fd.get("auto", false)})
	var tags: Dictionary = {}
	for t in race.get("traits", []) + sub_race.get("traits", []):
		if t.has("tag"):
			tags[t.tag] = true
		feature_info.append({"id": t.get("tag", ""), "name": t.name, "desc": t.desc, "src": race.get("name", "Race"), "auto": t.has("tag")})
	var feat_list = all_feats(ch)
	for f in feat_list:
		feats_set["feat_" + f] = true
		var fd = Data.feat(f)
		feature_info.append({"id": "feat_" + f, "name": fd.get("name", f), "desc": fd.get("desc", ""), "src": "Feat", "auto": fd.get("auto", false)})
	st.class_levels = cl
	st.subclasses = subs
	st.features = feats_set
	st.feature_info = feature_info
	for t in mm.tags:
		tags[t] = true
	st.tags = tags
	st.feats = feat_list

	# --- proficiencies
	var first: Dictionary = ch.classes[0] if ch.get("classes", []).size() > 0 else {"id": "fighter", "level": 1}
	var first_cd = Data.cls(first.id)
	var saves: Array = first_cd.get("saves", []).duplicate()
	for f in feat_list:
		var sv = Data.feat(f).get("save", "")
		if sv != "" and not sv in saves:
			saves.append(sv)
	var armor_prof: Array = []
	var weapon_prof: Array = []
	var ci = 0
	for c in ch.get("classes", []):
		var cd = Data.cls(c.id)
		var sd = Data.subclass(c.id, str(c.get("subclass", "")))
		var ap: Array = cd.get("armor", []) if ci == 0 else cd.get("mc_armor", [])
		var wp: Array = cd.get("weapons", []) if ci == 0 else cd.get("mc_weapons", [])
		for x in ap + sd.get("armor", []):
			if not x in armor_prof: armor_prof.append(x)
		for x in wp + sd.get("weapons", []):
			if not x in weapon_prof: weapon_prof.append(x)
		ci += 1
	for x in sub_race.get("armor_prof", []):
		if not x in armor_prof: armor_prof.append(x)
	if feats_set.has("battle_ready") and not "martial" in weapon_prof:
		weapon_prof.append("martial")
	st.saves = saves
	st.armor_prof = armor_prof
	st.weapon_prof = weapon_prof
	st.tools = Inventory.tool_profs(ch)
	var save_bonus: Dictionary = {}
	for a in Data.ABILITIES:
		save_bonus[a] = mods[a] + (pb if a in saves else 0) + int(mm.saves)
	st.save_bonus = save_bonus

	# --- skills
	var skill_prof: Array = []
	for s in ch.get("skills", []) + Data.BACKGROUNDS.get(ch.get("background", ""), []) + race.get("skills", []):
		if not s in skill_prof:
			skill_prof.append(s)
	var expertise: Array = ch.get("expertise", [])
	var skills: Dictionary = {}
	var jack = feats_set.has("jack_of_all_trades")
	for s in Data.SKILLS:
		var b: int = mods[Data.SKILLS[s]]
		if s in expertise:
			b += pb * 2
		elif s in skill_prof:
			b += pb
		elif jack:
			b += int(pb / 2)
		skills[s] = b + int(mm.checks)
	st.skill_prof = skill_prof
	st.skills = skills
	st.passive_perception = 10 + skills.perception + (5 if "observant" in feat_list else 0) + int(mm.passive)

	# --- hit points
	# The first character level takes the die's maximum; later levels use the HP the player rolled
	# when levelling up (hp_rolls) or the fixed average.
	var hp = 0
	ci = 0
	var rolls: Dictionary = ch.get("hp_rolls", {})
	for c in ch.get("classes", []):
		var hd = int(Data.cls(c.id).get("hit_die", 8))
		var got: Array = rolls.get(c.id, [])
		for i in int(c.level):
			if ci == 0 and i == 0:
				hp += hd
			else:
				var idx: int = i - (1 if ci == 0 else 0)
				hp += clampi(int(got[idx]), 1, hd) if idx < got.size() else int(hd / 2) + 1
		ci += 1
	hp += mods.con * lvl
	if "tough" in feat_list: hp += 2 * lvl
	if tags.has("dwarven_toughness"): hp += lvl
	if feats_set.has("draconic_resilience"): hp += cl.get("sorcerer", 0)
	st.max_hp = maxi(1, hp)
	# Hit dice are kept per die size: a multiclass character has one pool per class's die.
	var hd_pool: Dictionary = {}
	for c in ch.get("classes", []):
		var die = int(Data.cls(c.id).get("hit_die", 8))
		hd_pool[die] = int(hd_pool.get(die, 0)) + int(c.level)
	if hd_pool.is_empty():
		hd_pool[int(first_cd.get("hit_die", 8))] = lvl
	st.hit_dice_pool = hd_pool
	var hd_txt: PackedStringArray = []
	var dies: Array = hd_pool.keys()
	dies.sort()
	dies.reverse()
	for die in dies:
		hd_txt.append("%dd%d" % [int(hd_pool[die]), int(die)])
	st.hit_dice = " + ".join(hd_txt)

	# --- armor class
	# What is worn and wielded comes from the inventory (Inventory.equipment_of); old sheets keep their equipment block.
	var eq: Dictionary = Inventory.equipment_of(ch)
	var armor = Data.item(eq.get("armor", ""))
	var shield: bool = eq.get("shield", false)
	var ac: int = 10 + mods.dex
	var ac_note = "unarmored"
	if not armor.is_empty():
		ac = int(armor.base) + mini(mods.dex, int(armor.get("dex_max", 99))) + int(eq.get("armor_bonus", 0))
		ac_note = str(eq.get("armor_name", "")) if str(eq.get("armor_name", "")) != "" else armor.name
	else:
		var opts = [[10 + mods.dex, "unarmored"]]
		if feats_set.has("unarmored_defense_barbarian"): opts.append([10 + mods.dex + mods.con, "Unarmored Defense"])
		if feats_set.has("unarmored_defense_monk") and not shield: opts.append([10 + mods.dex + mods.wis, "Unarmored Defense"])
		if feats_set.has("draconic_resilience"): opts.append([13 + mods.dex, "Draconic Resilience"])
		if tags.has("natural_armor_13"): opts.append([13 + mods.dex, "Natural Armor"])
		if tags.has("natural_armor_17"): opts.append([17, "Natural Armor"])
		for o in opts:
			if o[0] > ac or ac_note == "unarmored" and o[0] >= ac:
				ac = o[0]
				ac_note = o[1]
	if shield:
		ac += 2 + int(eq.get("shield_bonus", 0))
		ac_note += " + shield" if int(eq.get("shield_bonus", 0)) == 0 else " + shield +%d" % int(eq.shield_bonus)
	var styles: Array = ch.get("fighting_styles", [])
	if "defense" in styles and not armor.is_empty(): ac += 1
	if tags.has("integrated_protection"): ac += 1
	if feats_set.has("blessing_of_the_forge"): ac += 1
	# Enhanced Defense: on the infused armor or shield (Inventory "infused"); older sheets always have it.
	if "enhanced_defense" in ch.get("infusions", []) and cl.get("artificer", 0) >= 2 and (not ch.get("inventory", null) is Array or eq.get("defense_infused", false)):
		ac += 2 if cl.artificer >= 10 else 1
	# Dual Wielder: +1 AC while wielding a separate melee weapon in each hand (so no shield).
	if "dual_wielder" in feat_list and not shield:
		var melee_n = 0
		for wid in eq.get("weapons", []):
			if Data.item(wid).get("melee", false):
				melee_n += 1
		if melee_n >= 2: ac += 1
	# Cloak / Ring of Protection; Bracers of Defense only without armor or a shield.
	ac += int(mm.ac)
	if armor.is_empty() and not shield:
		ac += int(mm.ac_unarmored)
	st.ac = ac
	st.ac_note = ac_note
	# Armor or a shield you aren't proficient with: no spellcasting, disadvantage on STR/DEX rolls.
	st.armor_unproficient = (not armor.is_empty() and not str(armor.get("category", "")) in armor_prof) or (shield and not "shield" in armor_prof)
	st.heavy_armor = armor.get("category", "") == "heavy"
	st.armored = not armor.is_empty()
	st.shield = shield

	# --- speed
	var speed = int(sub_race.get("speed", race.get("speed", 30)))
	if feats_set.has("fast_movement") and not st.heavy_armor: speed += 10
	if feats_set.has("unarmored_movement") and armor.is_empty() and not shield:
		var ml: int = cl.get("monk", 0)
		speed += 10 if ml < 6 else (15 if ml < 10 else (20 if ml < 14 else (25 if ml < 18 else 30)))
	if "mobile" in feat_list: speed += 10
	if st.heavy_armor and int(armor.get("str", 0)) > scores.str and not tags.has("dwarf_armor_speed") and not eq.get("no_str_req", false) and int(mm.speed_min) <= 0: speed -= 10
	if feats_set.has("armor_model") and ch.get("choices", {}).get("armor_model", "guardian") == "infiltrator": speed += 5
	# Boots of Striding and Springing: at least 30 ft.
	speed = maxi(speed, int(mm.speed_min))
	st.speed = speed
	st.darkvision = int(sub_race.get("darkvision", race.get("darkvision", 0)))
	# Goggles of Night: darkvision 60 ft, or 60 ft further.
	if int(mm.darkvision) > 0:
		st.darkvision = int(st.darkvision) + int(mm.darkvision) if int(st.darkvision) > 0 else int(mm.darkvision)
	st.stealth_dis = bool(armor.get("stealth_dis", false)) and not eq.get("no_stealth_dis", false)

	# --- initiative
	var init: int = mods.dex
	if "alert" in feat_list: init += 5
	if jack: init += int(pb / 2)
	if feats_set.has("temporal_awareness") or feats_set.has("tactical_wit"): init += mods.int
	if feats_set.has("dread_ambusher"): init += mods.wis
	if feats_set.has("rakish_audacity"): init += mods.cha
	st.initiative = init
	st.init_advantage = feats_set.has("feral_instinct") or feats_set.has("vigilant_blessing") or bool(mm.init_adv)

	# --- resistances
	var resist: Array = []
	for x in race.get("resist", []) + sub_race.get("resist", []):
		if not x in resist: resist.append(x)
	for x in mm.resist:
		if not x in resist: resist.append(x)
	st.resist = resist
	st.immune = ["poison"] if tags.has("poison_immunity") else []
	st.condition_immune = ["poisoned"] if tags.has("poison_immunity") else []

	# --- spellcasting
	var slot_info = spell_slots(ch)
	st.slots = slot_info.slots
	st.pact = slot_info.pact
	st.caster_level = slot_info.caster_level
	var casting: Array = []
	var focus_bonus = 0
	if "enhanced_arcane_focus" in ch.get("infusions", []) and cl.get("artificer", 0) >= 2 and (not ch.get("inventory", null) is Array or ch.inventory.any(func(e): return str(e.get("infused", "")) == "enhanced_arcane_focus")):
		focus_bonus = 2 if cl.artificer >= 10 else 1
	for c in ch.get("classes", []):
		var t = caster_type(c)
		if t == "":
			continue
		var counts = spell_counts(ch, c, scores)
		var ab: String = counts.ability
		var m: int = mods[ab]
		var chosen: Array = ch.get("spells", {}).get(c.id, []).duplicate()
		var book: Array = []
		if c.id == "wizard":
			# A wizard can only prepare leveled spells that are written in the spellbook.
			book = wizard_spellbook(ch)
			chosen = chosen.filter(func(x): return int(Data.spell(x).get("level", 0)) == 0 or x in book)
		var sd = Data.subclass(c.id, str(c.get("subclass", "")))
		var bonus: Array = []
		for k in sd.get("bonus_spells", {}):
			if int(k) <= int(c.level):
				for sid in sd.bonus_spells[k]:
					bonus.append(sid)
		for sid in sd.get("bonus_cantrips", []):
			bonus.append(sid)
		var all_ids: Array = []
		for sid in chosen + bonus:
			if Data.spells.has(sid) and not sid in all_ids:
				all_ids.append(sid)
		casting.append({
			"class": c.id, "name": Data.cls(c.id).get("name", c.id), "ability": ab, "mod": m,
			"dc": 8 + pb + m + (int(mm.spell_dc_warlock) if c.id == "warlock" else 0), "attack": pb + m + focus_bonus + int(mm.spell_attack), "spells": all_ids, "bonus_spells": bonus,
			"pact": t == "pact", "max_level": max_spell_level_for(c), "counts": counts,
		})
		if c.id == "wizard":
			casting[-1].spellbook = book
	if sub_race.get("bonus_cantrip", "") != "" and ch.get("spells", {}).has("race"):
		casting.append({"class": "race", "name": race.get("name", "Race"), "ability": "int", "mod": mods.int,
			"dc": 8 + pb + mods.int, "attack": pb + mods.int, "spells": ch.spells.race.filter(func(x): return Data.spells.has(x)),
			"bonus_spells": [], "pact": false, "max_level": 0, "counts": {}})
	st.casting = casting

	# --- scaling values used by the combat engine
	var v: Dictionary = {}
	var barb: int = cl.get("barbarian", 0)
	var monk: int = cl.get("monk", 0)
	var rogue: int = cl.get("rogue", 0)
	var bard: int = cl.get("bard", 0)
	var fighter: int = cl.get("fighter", 0)
	v.attacks = 1
	if feats_set.has("extra_attack"): v.attacks = 2
	if feats_set.has("extra_attack_2"): v.attacks = 3
	if feats_set.has("extra_attack_3"): v.attacks = 4
	if cl.get("warlock", 0) >= 5 and "thirsting_blade" in ch.get("invocations", []): v.attacks = maxi(v.attacks, 2)
	v.crit_range = 18 if feats_set.has("superior_critical") else (19 if feats_set.has("improved_critical") else 20)
	v.rage_damage = 2 if barb < 9 else (3 if barb < 16 else 4)
	v.brutal_dice = 0 if barb < 9 else (1 if barb < 13 else (2 if barb < 17 else 3))
	v.martial_die = 4 if monk < 5 else (6 if monk < 11 else (8 if monk < 17 else 10))
	v.sneak_dice = ceili(rogue / 2.0)
	v.bardic_die = 6 if bard < 5 else (8 if bard < 10 else (10 if bard < 15 else 12))
	v.superiority_die = 8 if fighter < 10 else (10 if fighter < 18 else 12)
	v.divine_strike_dice = 2 if cl.get("cleric", 0) >= 14 else 1
	v.cd_dc_wis = 8 + pb + mods.wis
	v.cd_dc_cha = 8 + pb + mods.cha
	v.ki_dc = 8 + pb + mods.wis
	v.int_dc = 8 + pb + mods.int
	v.maneuver_dc = 8 + pb + maxi(mods.str, mods.dex)
	v.breath_dc = 8 + pb + mods.con
	v.breath_dice = "%dd6" % (2 if lvl < 6 else (3 if lvl < 11 else (4 if lvl < 16 else 5)))
	st.vals = v

	# --- limited-use resources
	var res: Dictionary = {}
	var add_res = func(id: String, name: String, mx: int, reset: String) -> void:
		if mx > 0:
			res[id] = {"name": name, "max": mx, "reset": reset}
	if feats_set.has("rage"): add_res.call("rage", "Rage", [2, 2, 3, 3, 3, 4, 4, 4, 4, 4, 4, 5, 5, 5, 5, 5, 6, 6, 6, 99][barb - 1], "long")
	if feats_set.has("bardic_inspiration"): add_res.call("bardic_inspiration", "Bardic Inspiration", maxi(1, mods.cha), "short" if bard >= 5 else "long")
	var cd_uses = 0
	var cleric: int = cl.get("cleric", 0)
	if cleric >= 2: cd_uses = 1 if cleric < 6 else (2 if cleric < 18 else 3)
	if cl.get("paladin", 0) >= 3: cd_uses = maxi(cd_uses, 1)
	add_res.call("channel_divinity", "Channel Divinity", cd_uses, "short")
	if feats_set.has("wild_shape"): add_res.call("wild_shape", "Wild Shape", 2, "short")
	if feats_set.has("second_wind"): add_res.call("second_wind", "Second Wind", 1, "short")
	if feats_set.has("action_surge"): add_res.call("action_surge", "Action Surge", 2 if fighter >= 17 else 1, "short")
	if feats_set.has("indomitable"): add_res.call("indomitable", "Indomitable", 1 if fighter < 13 else (2 if fighter < 17 else 3), "long")
	if feats_set.has("combat_superiority"): add_res.call("superiority", "Superiority Dice", 4 if fighter < 7 else (5 if fighter < 15 else 6), "short")
	if feats_set.has("ki"): add_res.call("ki", "Ki", monk, "short")
	if feats_set.has("lay_on_hands"): add_res.call("lay_on_hands", "Lay on Hands", 5 * cl.get("paladin", 0), "long")
	if feats_set.has("font_of_magic"): add_res.call("sorcery_points", "Sorcery Points", cl.get("sorcerer", 0), "long")
	if feats_set.has("warding_flare"): add_res.call("warding_flare", "Warding Flare", maxi(1, mods.wis), "long")
	if feats_set.has("war_priest"): add_res.call("war_priest", "War Priest", maxi(1, mods.wis), "long")
	if feats_set.has("wrath_of_the_storm"): add_res.call("wrath_of_the_storm", "Wrath of the Storm", maxi(1, mods.wis), "long")
	if feats_set.has("emboldening_bond"): add_res.call("emboldening_bond", "Emboldening Bond", pb, "long")
	if feats_set.has("flash_of_genius"): add_res.call("flash_of_genius", "Flash of Genius", maxi(1, mods.int), "long")
	if feats_set.has("arcane_jolt"): add_res.call("arcane_jolt", "Arcane Jolt", maxi(1, mods.int), "long")
	if feats_set.has("momentary_stasis"): add_res.call("momentary_stasis", "Momentary Stasis", maxi(1, mods.int), "long")
	if feats_set.has("chronal_shift"): add_res.call("chronal_shift", "Chronal Shift", 2, "long")
	if feats_set.has("bladesong"): add_res.call("bladesong", "Bladesong", pb, "long")
	if feats_set.has("fighting_spirit"): add_res.call("fighting_spirit", "Fighting Spirit", 3, "long")
	if feats_set.has("hexblades_curse"): add_res.call("hexblades_curse", "Hexblade's Curse", 1, "short")
	if feats_set.has("healing_light"): add_res.call("healing_light", "Healing Light (d6)", 1 + cl.get("warlock", 0), "long")
	if feats_set.has("fey_presence"): add_res.call("fey_presence", "Fey Presence", 1, "short")
	if feats_set.has("eldritch_cannon"): add_res.call("eldritch_cannon", "Eldritch Cannon", 1, "long")
	if feats_set.has("arcane_recovery"): add_res.call("arcane_recovery", "Arcane Recovery", 1, "long")
	if feats_set.has("favored_by_the_gods"): add_res.call("favored_by_the_gods", "Favored by the Gods", 1, "short")
	if feats_set.has("armor_model") and ch.get("choices", {}).get("armor_model", "guardian") == "guardian":
		add_res.call("defensive_field", "Defensive Field", pb, "long")
	if "lucky" in feat_list: add_res.call("lucky", "Luck Points", 3, "long")
	if tags.has("relentless_endurance"): add_res.call("relentless_endurance", "Relentless Endurance", 1, "long")
	if tags.has("breath_weapon"): add_res.call("breath_weapon", "Breath Weapon", 1, "short")
	if tags.has("healing_hands"): add_res.call("healing_hands", "Healing Hands", 1, "long")
	if tags.has("stones_endurance"): add_res.call("stones_endurance", "Stone's Endurance", 1, "short")
	if tags.has("fury_of_the_small"): add_res.call("fury_of_the_small", "Fury of the Small", 1, "short")
	if tags.has("hidden_step"): add_res.call("hidden_step", "Hidden Step", 1, "short")
	if tags.has("fey_step"): add_res.call("fey_step", "Fey Step", 1, "short")
	if tags.has("radiant_soul") and lvl >= 3: add_res.call("radiant_soul", "Celestial Revelation", 1, "long")
	st.resources = res

	# --- attacks
	st.weapons = build_weapon_attacks(ch, st)
	# --- carrying (PHB p.176): what the inventory weighs against Strength × 15, scaled by size.
	st.load_lb = Inventory.carried_lb(ch) if ch.get("inventory", null) is Array else 0.0
	st.carry_mult = Inventory.size_mult(str(race.get("size", "medium")), tags)
	st.capacity = int(int(scores.str) * 15 * st.carry_mult)
	st.fighting_styles = styles
	st.maneuvers = ch.get("maneuvers", [])
	st.metamagic = ch.get("metamagic", [])
	st.invocations = ch.get("invocations", [])
	st.infusions = ch.get("infusions", [])
	st.choices = ch.get("choices", {})
	return st

static func is_proficient_weapon(w: Dictionary, profs: Array) -> bool:
	return w.category in profs or w.id in profs

static func is_monk_weapon(w: Dictionary) -> bool:
	if w.id == "shortsword":
		return true
	return w.category == "simple" and w.melee and not "heavy" in w.props and not "two_handed" in w.props

static func build_weapon_attacks(ch: Dictionary, st: Dictionary) -> Array:
	var out: Array = []
	var eq: Dictionary = Inventory.equipment_of(ch)
	var mods: Dictionary = st.mods
	var pb: int = st.prof
	var f: Dictionary = st.features
	var styles: Array = ch.get("fighting_styles", [])
	var wbonus = int(eq.get("weapon_bonus", 0))
	# Enhanced Weapon: with an inventory, only the infused weapon (Inventory: an entry's "infused"); older
	# sheets without one treat every weapon as infused.
	var infuse_b: int = 2 if st.class_levels.get("artificer", 0) >= 10 else 1
	var old_infuse: bool = "enhanced_weapon" in ch.get("infusions", []) and st.class_levels.get("artificer", 0) >= 2
	var has_inv: bool = ch.get("inventory", null) is Array
	if not has_inv:
		if old_infuse:
			wbonus = maxi(wbonus, infuse_b)
	var weapons: Array = eq.get("weapons", [])
	var melee_count = 0
	for wid in weapons:
		if Data.item(wid).get("melee", false):
			melee_count += 1
	var dual = melee_count >= 2
	var seen = {}
	var light_ids: Array = []
	for wid in weapons:
		var w = Data.item(wid)
		if w.is_empty():
			continue
		if "light" in w.props and w.melee:
			light_ids.append(wid)
		if seen.has(wid):
			continue
		seen[wid] = true
		var ability = "str" if w.melee else "dex"
		var finesse: bool = "finesse" in w.props or eq.get("weapon_finesse", {}).has(wid)
		if finesse or (f.has("martial_arts") and is_monk_weapon(w)):
			ability = "dex" if mods.dex > mods.str else "str"
		# A magic weapon's own bonus, name and extra damage (Inventory.equipment_of: a +1 longsword, a Flame Tongue).
		var wb: int = maxi(wbonus, int(eq.get("weapon_bonuses", {}).get(wid, 0)))
		# An infused weapon (Enhanced Weapon +1/+2, Repeating Shot or Radiant Weapon +1): magical too.
		var inf: String = str(eq.get("weapon_infused", {}).get(wid, ""))
		if inf != "" and inf in ch.get("infusions", []) and st.class_levels.get("artificer", 0) >= 2:
			wb = maxi(wb, infuse_b if inf == "enhanced_weapon" else 1)
		var extra: Array = eq.get("weapon_extra", {}).get(wid, [])
		var wname: String = str(eq.get("weapon_names", {}).get(wid, w.name))
		var magic: bool = wb > 0 or eq.get("weapon_magic", {}).has(wid)
		# A Sun Blade deals radiant damage instead of slashing.
		var wtype: String = str(eq.get("weapon_dtype", {}).get(wid, w.type))
		if f.has("hex_warrior") and mods.cha >= mods[ability]:
			ability = "cha"
		if f.has("battle_ready") and mods.int >= mods[ability]:
			ability = "int"
			magic = true
		var prof_ok = is_proficient_weapon(w, st.weapon_prof)
		# A Sun Blade counts as proficient for anyone proficient with shortswords or longswords.
		for alt in eq.get("weapon_prof_as", {}).get(wid, []):
			if is_proficient_weapon(Data.item(str(alt)), st.weapon_prof):
				prof_ok = true
		var to_hit: int = mods[ability] + (pb if prof_ok else 0) + wb
		if "archery" in styles and not w.melee: to_hit += 2
		var die: String = w.damage
		# Versatile weapons are swung two-handed when a hand is free, except by a Dueling
		# fighter, who does better one-handed (1d8+2 beats 1d10; Dueling needs one hand).
		if "versatile" in w.props and not eq.get("shield", false) and not dual and not "dueling" in styles:
			die = w.get("versatile", die)
		if f.has("martial_arts") and is_monk_weapon(w):
			if Dice.average("1d%d" % st.vals.martial_die) > Dice.average(die):
				die = "1d%d" % st.vals.martial_die
		var dmg_bonus: int = mods[ability] + wb
		if "dueling" in styles and w.melee and not "two_handed" in w.props and not dual: dmg_bonus += 2
		var reach = 10 if "reach" in w.props else 5
		var atk = {
			"id": "w_" + wid, "name": wname, "weapon": wid, "melee": w.melee, "ability": ability,
			"to_hit": to_hit, "damage": [{"dice": Dice.add(die, str(dmg_bonus)), "type": wtype}] + extra.duplicate(true),
			"die": die, "reach": reach, "range": int(w.get("range", 0)), "long_range": int(w.get("long_range", 0)),
			"props": w.props, "magic": magic, "finesse": finesse,
			"heavy": "heavy" in w.props, "two_handed": "two_handed" in w.props or (die != w.damage and "versatile" in w.props),
			"monk": f.has("martial_arts") and is_monk_weapon(w),
			# The magic item behind it (on-hit powers, Inventory.hit_extra), its own bonus, and silvering.
			"item": eq.get("weapon_items", {}).get(wid, {}).get("id", ""), "item_uid": eq.get("weapon_items", {}).get(wid, {}).get("uid", ""),
			"wb": wb, "silver": eq.get("weapon_silver", {}).has(wid),
			"no_ammo": inf == "repeating_shot" and inf in ch.get("infusions", []),   # Repeating Shot makes its own ammunition
		}
		out.append(atk)
		# Thrown melee weapons get a ranged profile too.
		if w.melee and "thrown" in w.props:
			var t = atk.duplicate(true)
			t.id = "wt_" + wid
			t.name = "Throw " + wname
			t.melee = false
			t.thrown = true
			if "thrown_weapon_fighting" in styles:
				t.damage = [{"dice": Dice.add(die, str(dmg_bonus + 2)), "type": wtype}] + extra.duplicate(true)
			out.append(t)
	# Off-hand attack (two-weapon fighting).
	if light_ids.size() >= 2 or (dual and "dual_wielder" in st.get("feats", [])):
		var oid: String = light_ids[1] if light_ids.size() >= 2 else weapons[1]
		var ow = Data.item(oid)
		var owb: int = maxi(wbonus, int(eq.get("weapon_bonuses", {}).get(oid, 0)))
		var ability = "dex" if ("finesse" in ow.props and mods.dex > mods.str) else "str"
		var dmg: int = mini(mods[ability], 0) if not "two_weapon_fighting" in styles else mods[ability]
		out.append({"id": "offhand", "name": "Off-hand " + str(eq.get("weapon_names", {}).get(oid, ow.name)), "weapon": oid, "melee": true, "ability": ability,
			"to_hit": mods[ability] + (pb if is_proficient_weapon(ow, st.weapon_prof) else 0) + owb, "damage": [{"dice": Dice.add(ow.damage, str(dmg + owb)), "type": ow.type}] + eq.get("weapon_extra", {}).get(oid, []).duplicate(true),
			"die": ow.damage, "reach": 5, "range": 0, "long_range": 0, "props": ow.props, "magic": owb > 0 or eq.get("weapon_magic", {}).has(oid),
			"finesse": "finesse" in ow.props, "offhand": true, "cost": "bonus"})
	# Unarmed strike.
	var ua_die = "1"
	var ua_type = "bludgeoning"
	var ua_ab = "str"
	if f.has("martial_arts"):
		ua_die = "1d%d" % st.vals.martial_die
		ua_ab = "dex" if mods.dex > mods.str else "str"
	elif st.tags.has("claws"):
		ua_die = "1d4"
		ua_type = "slashing"
	elif st.tags.has("bite"):
		ua_die = "1d6"
		ua_type = "piercing"
	out.append({"id": "unarmed", "name": "Unarmed Strike", "weapon": "", "melee": true, "ability": ua_ab,
		"to_hit": mods[ua_ab] + pb, "damage": [{"dice": Dice.add(ua_die, str(mods[ua_ab])), "type": ua_type}],
		"die": ua_die, "reach": 5, "range": 0, "long_range": 0, "props": [], "magic": f.has("ki_empowered_strikes"),
		"unarmed": true, "monk": f.has("martial_arts")})
	# Armorer weapons.
	if f.has("armor_model"):
		var model: String = ch.get("choices", {}).get("armor_model", "guardian")
		if model == "guardian":
			out.append({"id": "thunder_gauntlets", "name": "Thunder Gauntlets", "weapon": "", "melee": true, "ability": "int",
				"to_hit": mods.int + pb + wbonus, "damage": [{"dice": Dice.add("1d8", str(mods.int + wbonus)), "type": "thunder"}],
				"die": "1d8", "reach": 5, "range": 0, "long_range": 0, "props": [], "magic": true, "guardian_mark": true})
		else:
			out.append({"id": "lightning_launcher", "name": "Lightning Launcher", "weapon": "", "melee": false, "ability": "int",
				"to_hit": mods.int + pb + wbonus, "damage": [{"dice": Dice.add("1d6", str(mods.int + wbonus)), "type": "lightning"}],
				"die": "1d6", "reach": 5, "range": 90, "long_range": 300, "props": [], "magic": true, "launcher": true})
	return out
