class_name LevelUpWizard
extends DialogPanel
## Guided level-up, one step at a time: class (or multiclass), hit points, subclass, ability score
## improvement or feat, class options, skills, spells, then a review of every change. Only the steps
## this level actually needs are shown. Each step says in plain words what the choice means, and
## enforces the rules (multiclass and feat prerequisites, ability cap, pick counts) unless the
## "outside the rules" box is ticked for a DM-approved exception.

signal finished(new_sheet: Dictionary, label: String)

var base: Dictionary        # the sheet before this level
var pick := {}              # choices so far (see Progression.apply_level)
var allow_unmet := false    # DM-approved exceptions to prerequisites and pick counts
var step := "class"
var steps: Array = []
var content: VBoxContainer
var crumbs: RichTextLabel
var status_lbl: Label
var back_btn: Button
var next_btn: Button
var spell_filter := ""

func _init(sheet: Dictionary, opts := {}) -> void:
	super("Level up", Vector2(1100, 800))
	base = sheet.duplicate(true)
	allow_unmet = opts.get("allow_unmet", false)
	pick = {"class": "", "subclass": "", "hp_mode": "avg", "hp": 0, "asi": {}, "picks": {}, "skills": [], "expertise": [], "spells": {}, "choices": {}, "note": ""}
	var planned := Progression.planned_class(base)
	pick["class"] = planned if planned != "" and (allow_unmet or Progression.multiclass_unmet(base, planned).is_empty()) else str(base.classes[0].id)
	_reset_for_class()
	crumbs = UIKit.rich("")
	body.add_child(crumbs)
	var sc = ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	UIKit.expand(sc, true, true)
	content = UIKit.vbox(10)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(UIKit.margin(content, 6))
	sc.get_child(0).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(sc)
	var nav = UIKit.hbox(10)
	var ov = UIKit.check("Allow choices outside the rules (DM approved)", allow_unmet, func(p): allow_unmet = p; _show())
	ov.tooltip_text = "Skips multiclass and feat prerequisites and lets you pick more or fewer options and spells than the rules allow."
	nav.add_child(ov)
	status_lbl = UIKit.lbl("", 14, Color("#ff9c8f"))
	status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_lbl.custom_minimum_size = Vector2(120, 0)
	status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UIKit.expand(status_lbl)
	nav.add_child(status_lbl)
	back_btn = UIKit.btn("← Back", _back)
	back_btn.custom_minimum_size = Vector2(100, 40)
	nav.add_child(back_btn)
	next_btn = UIKit.btn("Next →", func(): next_step())
	next_btn.custom_minimum_size = Vector2(170, 40)
	next_btn.add_theme_font_size_override("font_size", 17)
	nav.add_child(next_btn)
	body.add_child(nav)
	_show()

# ---------------------------------------------------------------- navigation

func step_name() -> String:
	return step

func is_last_step() -> bool:
	return step == "review"

func _compute_steps() -> void:
	steps = ["class"]
	var cid: String = pick["class"]
	var g := Progression.gains(base, cid, str(pick.subclass))
	steps.append("hp")
	if Progression.gains(base, cid).subclass_choice:
		steps.append("subclass")
	if g.asi:
		steps.append("asi")
	var after := _preview(false)
	var opts := Progression.option_limits(after)
	var need_opts := false
	for o in opts:
		var before := 0
		for o2 in Progression.option_limits(base):
			if o2.key == o.key:
				before = int(o2.limit)
		if int(o.limit) > before or int(o.chosen) != int(o.limit):
			need_opts = true
	if not Progression.feature_choices(g.features + g.subclass_features).is_empty():
		need_opts = true
	if need_opts:
		steps.append("options")
	if g.mc_skills > 0 or Progression.expertise_limit(after) > base.get("expertise", []).size():
		steps.append("skills")
	var entry := _entry(after, cid)
	if not entry.is_empty() and Rules.caster_type(entry) != "":
		steps.append("spells")
	steps.append("review")

func next_step(force := false) -> void:
	var err := _validate()
	if err != "" and not force:
		status_lbl.text = err
		return
	if err != "" and force:
		_defaults()
	if step == "review":
		_confirm()
		return
	_compute_steps()
	var i := steps.find(step)
	step = steps[mini(i + 1, steps.size() - 1)]
	_show()

func _back() -> void:
	_compute_steps()
	var i := steps.find(step)
	if i > 0:
		step = steps[i - 1]
		_show()

## Called when a test (or the plan) picks a class directly.
func pick_class(cid: String) -> void:
	pick["class"] = cid
	_reset_for_class()
	step = "class"
	_show()

func _reset_for_class() -> void:
	var cid: String = pick["class"]
	var hd := int(Data.cls(cid).get("hit_die", 8))
	pick.subclass = ""
	pick.hp_mode = "avg"
	pick.hp = Progression.hp_average(hd)
	pick.asi = {}
	pick.picks = {}
	pick.skills = []
	pick.expertise = []
	pick.spells = {}
	pick.erase("spellbook")
	pick.choices = {}
	# Ability scores for the ASI default to the class's main ability.
	var prim: Array = Data.cls(cid).get("primary", ["str"])
	pick.asi_default = str(prim[0])

## The sheet with the choices so far applied. `full` includes the class options and spells picked.
func _preview(full := true) -> Dictionary:
	var p := pick.duplicate(true)
	if not full:
		p.picks = {}
		p.spells = {}
		p.erase("spellbook")
		p.skills = []
		p.expertise = []
	# The wizard's "+2 to one" / "+1 to two" become the sheet's {type: "asi", a, b}.
	var a: Dictionary = p.get("asi", {})
	if str(a.get("type", "")) == "asi2":
		p.asi = {"type": "asi", "a": a.a, "b": a.a}
	elif str(a.get("type", "")) == "asi11":
		p.asi = {"type": "asi", "a": a.a, "b": a.b}
	elif str(a.get("type", "")) == "feat" and str(a.get("feat", "")) == "":
		p.asi = {}
	return Progression.apply_level(base, p)

func _entry(ch: Dictionary, cid: String) -> Dictionary:
	for c in ch.get("classes", []):
		if c.id == cid:
			return c
	return {}

func _show() -> void:
	_compute_steps()
	if not step in steps:
		step = steps[-1] if step == "review" else "class"
	status_lbl.text = ""
	var names := {"class": "Class", "hp": "Hit Points", "subclass": "Subclass", "asi": "Ability Scores", "options": "Class Options", "skills": "Skills", "spells": "Spells", "review": "Review"}
	var parts: PackedStringArray = []
	for i in steps.size():
		var s: String = steps[i]
		if s == step:
			parts.append("[color=#c9a14a][b]%d %s[/b][/color]" % [i + 1, names[s]])
		else:
			parts.append("[color=#a59cb5]%d %s[/color]" % [i + 1, names[s]])
	var g := Progression.gains(base, pick["class"], str(pick.subclass))
	crumbs.text = "[font_size=15]%s[/font_size]\n[color=#a59cb5]%s → level %d: %s %d[/color]" % ["  ›  ".join(parts), base.get("name", ""), int(g.total), Data.cls(pick["class"]).get("name", ""), int(g.class_level)]
	set_title("Level up — %s" % base.get("name", ""))
	UIKit.clear(content)
	content.add_child(DialogPanel.wrap_lbl(Progression.HELP.get(step, ""), 14, Color("#b9b0c9")))
	match step:
		"class": _step_class()
		"hp": _step_hp()
		"subclass": _step_subclass()
		"asi": _step_asi()
		"options": _step_options()
		"skills": _step_skills()
		"spells": _step_spells()
		"review": _step_review()
	back_btn.disabled = steps.find(step) <= 0
	next_btn.text = "✔ Confirm level up" if step == "review" else "Next →"

# ---------------------------------------------------------------- step: class

func _step_class() -> void:
	var planned := Progression.planned_class(base)
	if planned != "":
		var note: String = str(Progression.level_plan(base)[Rules.total_level(base)].get("note", ""))
		content.add_child(UIKit.lbl("Your level plan: %s%s" % [Data.cls(planned).get("name", planned), ("  —  " + note) if note != "" else ""], 15, UIKit.GOOD))
	var cols = UIKit.hbox(14)
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(cols)
	var left = UIKit.vbox(4)
	left.custom_minimum_size = Vector2(330, 0)
	cols.add_child(left)
	var group := ButtonGroup.new()
	left.add_child(UIKit.lbl("Continue a class", 14, UIKit.GOLD))
	for c in base.classes:
		left.add_child(_class_button(str(c.id), group, "%s %d → %d" % [Data.cls(c.id).name, int(c.level), int(c.level) + 1], ""))
	left.add_child(UIKit.lbl("Multiclass into a new class", 14, UIKit.GOLD))
	var ids: Array = Data.classes.keys()
	ids.sort_custom(func(a, b): return str(Data.cls(a).name) < str(Data.cls(b).name))
	for cid in ids:
		if Rules.class_level(base, cid) > 0:
			continue
		var unmet := Progression.multiclass_unmet(base, cid)
		left.add_child(_class_button(cid, group, "%s 1%s" % [Data.cls(cid).name, "" if unmet.is_empty() else "  ⚠"], "; ".join(unmet)))
	var right = UIKit.vbox(6)
	UIKit.expand(right)
	cols.add_child(right)
	right.add_child(UIKit.rich(_class_details(pick["class"])))

func _class_button(cid: String, group: ButtonGroup, text: String, warn: String) -> Button:
	var b = UIKit.btn(text, func(): pick["class"] = cid; _reset_for_class(); _show())
	b.toggle_mode = true
	b.button_group = group
	b.button_pressed = pick["class"] == cid
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.tooltip_text = ("Prerequisite not met: " + warn) if warn != "" else ("Multiclass prerequisite: " + Progression.prereq_text(cid) if Rules.class_level(base, cid) == 0 else "")
	if warn != "":
		b.add_theme_color_override("font_color", Color("#d0a090"))
	return b

func _class_details(cid: String) -> String:
	var cd := Data.cls(cid)
	var g := Progression.gains(base, cid)
	var t := "[font_size=20][color=#c9a14a]%s %d[/color][/font_size]   [color=#a59cb5]d%d hit die · %s[/color]\n" % [cd.name, g.class_level, g.hit_die, cd.get("source", "")]
	if g.multiclass:
		var unmet := Progression.multiclass_unmet(base, cid)
		t += "[color=%s]Multiclass prerequisite: %s%s[/color]\n" % ["#5cc892" if unmet.is_empty() else "#ff9c8f", Progression.prereq_text(cid), "  ✓ met" if unmet.is_empty() else ("  ✗ " + "; ".join(unmet))]
		var prof: PackedStringArray = []
		for x in g.mc_armor + g.mc_weapons:
			prof.append(Data.pretty(str(x)))
		t += "Proficiencies gained: %s%s\n" % [", ".join(prof) if not prof.is_empty() else "none", (", plus %d skill" % g.mc_skills) if g.mc_skills > 0 else ""]
		t += "[color=#a59cb5]You don't gain this class's saving throws or starting equipment when multiclassing.[/color]\n"
	if g.pb_up:
		t += "Proficiency bonus rises to [b]+%d[/b].\n" % Rules.prof_bonus(g.total)
	t += "\n[color=#c9a14a]You gain[/color]\n"
	var any := false
	for fid in g.features + g.subclass_features:
		var fd := Data.feature(fid)
		t += "• [b]%s[/b]%s — %s\n" % [fd.get("name", Data.pretty(fid)), "  [color=#5cc892]⚙[/color]" if fd.get("auto", false) else "", fd.get("desc", "")]
		any = true
	if g.subclass_choice:
		t += "• [b]%s[/b] — choose your subclass (next steps).\n" % cd.get("subclass_label", "Subclass")
		any = true
	if g.asi:
		t += "• [b]Ability Score Improvement[/b] — +2 to one score, +1 to two, or a feat.\n"
		any = true
	if g.new_spell_level > g.old_spell_level:
		t += "• Spells of level [b]%d[/b] for this class.\n" % g.new_spell_level
		any = true
	if str(g.slots_before) != str(g.slots_after):
		t += "• Spell slots: %s → %s\n" % [_slots(g.slots_before), _slots(g.slots_after)]
		any = true
	if str(g.pact_before) != str(g.pact_after):
		t += "• Pact slots: %d × level %d → %d × level %d\n" % [int(g.pact_before.count), int(g.pact_before.level), int(g.pact_after.count), int(g.pact_after.level)]
		any = true
	if not any:
		t += "[color=#a59cb5]More hit points and everything that scales with your class level.[/color]\n"
	var nxt: Array = []
	var lvc: int = int(g.class_level)
	for k in cd.get("features", {}):
		if int(k) > lvc and int(k) <= lvc + 3:
			for fid in cd.features[k]:
				nxt.append("%s (%s)" % [Data.feature(fid).get("name", Data.pretty(fid)), k])
	if not nxt.is_empty():
		t += "\n[color=#a59cb5]Coming up: %s[/color]" % ", ".join(nxt)
	return t

func _slots(arr: Array) -> String:
	if arr.is_empty():
		return "none"
	var p: PackedStringArray = []
	for i in arr.size():
		p.append("%d×L%d" % [int(arr[i]), i + 1])
	return " ".join(p)

# ---------------------------------------------------------------- step: hit points

func _step_hp() -> void:
	var cid: String = pick["class"]
	var hd := int(Data.cls(cid).get("hit_die", 8))
	var con := Rules.mod(int(Rules.final_scores(base).con))
	var avg := Progression.hp_average(hd)
	content.add_child(UIKit.lbl("Hit die d%d   ·   Constitution modifier %s" % [hd, Rules.fmt_mod(con)], 16, UIKit.GOLD))
	var group := ButtonGroup.new()
	var r1 = CheckBox.new()
	r1.text = "Take the average: %d" % avg
	r1.button_group = group
	r1.button_pressed = pick.hp_mode == "avg"
	r1.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	r1.toggled.connect(func(p):
		if p:
			pick.hp_mode = "avg"
			pick.hp = avg
			_show())
	content.add_child(r1)
	var rr = UIKit.hbox(8)
	var r2 = CheckBox.new()
	r2.text = "Roll a d%d" % hd
	r2.button_group = group
	r2.button_pressed = pick.hp_mode == "roll"
	r2.toggled.connect(func(p):
		if p and pick.hp_mode != "roll":
			pick.hp_mode = "roll"
			pick.hp = Dice.roll("1d%d" % hd).total
			_show())
	rr.add_child(r2)
	if pick.hp_mode == "roll":
		rr.add_child(UIKit.lbl("rolled [ %d ]" % int(pick.hp), 15, UIKit.GOLD))
	content.add_child(rr)
	var mr = UIKit.hbox(8)
	var r3 = CheckBox.new()
	r3.text = "I rolled my own die:"
	r3.button_group = group
	r3.button_pressed = pick.hp_mode == "manual"
	r3.toggled.connect(func(p):
		if p:
			pick.hp_mode = "manual"
			_show())
	mr.add_child(r3)
	var sp = UIKit.spin(1, hd, clampi(int(pick.hp), 1, hd), func(val): pick.hp = int(val); _hp_total_label())
	sp.editable = pick.hp_mode == "manual"
	mr.add_child(sp)
	content.add_child(mr)
	content.add_child(HSeparator.new())
	var tl = UIKit.lbl("", 18, UIKit.INK)
	tl.name = "hp_total"
	content.add_child(tl)
	_hp_total_label()
	content.add_child(DialogPanel.wrap_lbl("Hit points also include bonuses such as Tough, Dwarven Toughness and Draconic Resilience; the total above already counts them. If your Constitution modifier goes up later, your maximum rises for every level.", 13))

func _hp_total_label() -> void:
	var l := content.get_node_or_null("hp_total") as Label
	if l == null:
		return
	var before := int(Rules.derive(base).max_hp)
	var after := int(Rules.derive(_preview(false)).max_hp)
	l.text = "Maximum hit points: %d → %d  (+%d)" % [before, after, after - before]

# ---------------------------------------------------------------- step: subclass

func _step_subclass() -> void:
	var cid: String = pick["class"]
	var cd := Data.cls(cid)
	content.add_child(UIKit.lbl("Choose your %s" % cd.get("subclass_label", "subclass"), 18, UIKit.GOLD))
	var cols = UIKit.hbox(14)
	content.add_child(cols)
	var left = UIKit.vbox(4)
	left.custom_minimum_size = Vector2(330, 0)
	cols.add_child(left)
	var group := ButtonGroup.new()
	for s in cd.get("subclasses", []):
		var sid: String = s.id
		var b = UIKit.btn("%s  (%s)" % [s.name, s.get("source", cd.get("source", ""))], func(): pick.subclass = sid; pick.picks = {}; pick.spells = {}; _show())
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = pick.subclass == sid
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.custom_minimum_size = Vector2(320, 0)
		b.tooltip_text = s.name
		left.add_child(b)
	var right = UIKit.vbox(6)
	UIKit.expand(right)
	cols.add_child(right)
	if pick.subclass == "":
		right.add_child(UIKit.lbl("Pick a subclass on the left to see what it grants.", 15, UIKit.MUTED))
		return
	var sd := Data.subclass(cid, pick.subclass)
	var t := "[font_size=20][color=#c9a14a]%s[/color][/font_size]\n" % sd.name
	var keys: Array = sd.get("features", {}).keys()
	keys.sort_custom(func(a, b): return int(a) < int(b))
	var lv := Rules.class_level(base, cid) + 1
	for k in keys:
		for fid in sd.features[k]:
			var fd := Data.feature(fid)
			var now: bool = int(k) <= lv
			t += "%s[b]%s[/b] [color=#8a7fa0](level %s)[/color]%s — %s\n" % ["• " if now else "◦ ", fd.get("name", Data.pretty(fid)), k, "  [color=#5cc892]now[/color]" if now else "", fd.get("desc", "")]
	if sd.has("bonus_spells"):
		t += "\n[color=#c9a14a]Always-prepared spells[/color]\n"
		var bk: Array = sd.bonus_spells.keys()
		bk.sort_custom(func(a, b): return int(a) < int(b))
		for k in bk:
			t += "Level %s: %s\n" % [k, ", ".join(sd.bonus_spells[k].map(func(x): return Data.spell(x).get("name", x)))]
	if sd.get("caster", null) != null:
		t += "\n[color=#c8a0ff]This subclass gives you spellcasting (%s).[/color]\n" % str(sd.get("spell_ability", "")).to_upper()
	right.add_child(UIKit.rich(t))

# ---------------------------------------------------------------- step: ASI / feat

func _step_asi() -> void:
	if pick.asi.is_empty():
		pick.asi = {"type": "asi2", "a": pick.asi_default, "b": pick.asi_default}
	var a: Dictionary = pick.asi
	var scores := Rules.final_scores(base)
	var row = UIKit.hbox(10)
	row.add_child(UIKit.lbl("Improvement", 15, UIKit.MUTED))
	var mo = UIKit.option([["asi2", "+2 to one ability"], ["asi11", "+1 to two abilities"], ["feat", "Take a feat instead"]], a.type, func(id):
		a.type = id
		if id == "asi11" and a.a == a.b:
			for x in Data.ABILITIES:
				if x != a.a and int(scores[x]) < 20:
					a.b = x
					break
		_show())
	row.add_child(mo)
	content.add_child(row)
	if a.type != "feat":
		var items: Array = []
		for x in Data.ABILITIES:
			var cur := int(scores[x])
			items.append([x, "%s  (%d → %d)%s" % [Data.ABILITY_NAMES[x], cur, mini(cur + (2 if a.type == "asi2" else 1), 20), "  max" if cur >= 20 else ""]])
		var r2 = UIKit.hbox(10)
		r2.add_child(UIKit.lbl("Raise", 15, UIKit.MUTED))
		r2.add_child(UIKit.option(items, a.a, func(id):
			a.a = id
			if a.type == "asi2":
				a.b = id
			_show()))
		if a.type == "asi11":
			r2.add_child(UIKit.lbl("and", 15, UIKit.MUTED))
			r2.add_child(UIKit.option(items, a.b, func(id): a.b = id; _show()))
		content.add_child(r2)
		var after := Rules.final_scores(_preview(false))
		var lines: PackedStringArray = []
		for x in Data.ABILITIES:
			if int(after[x]) != int(scores[x]):
				lines.append("%s %d → %d (modifier %s → %s)" % [x.to_upper(), int(scores[x]), int(after[x]), Rules.fmt_mod(Rules.mod(int(scores[x]))), Rules.fmt_mod(Rules.mod(int(after[x])))])
		content.add_child(UIKit.lbl("  ·  ".join(lines) if not lines.is_empty() else "No change (that score is already at 20).", 15, UIKit.GOOD if not lines.is_empty() else UIKit.BAD))
		content.add_child(DialogPanel.wrap_lbl("Tip: an even score is what raises a modifier. Going from 15 to 16 improves rolls; 16 to 17 doesn't (until the next +1).", 13))
		return
	# Feat.
	var have := Rules.all_feats(base)
	var cols = UIKit.hbox(14)
	content.add_child(cols)
	var left = UIKit.vbox(3)
	left.custom_minimum_size = Vector2(330, 0)
	cols.add_child(left)
	var group := ButtonGroup.new()
	var fl: Array = Data.feats.values()
	fl.sort_custom(func(x, y): return x.name < y.name)
	for f in fl:
		var fid: String = f.id
		var unmet := Progression.feat_unmet(base, fid)
		var taken: bool = fid in have
		var b = UIKit.btn("%s%s%s" % [f.name, "  ⚙" if f.get("auto", false) else "", "  (taken)" if taken else ("  ⚠" if unmet != "" else "")], func(): a.feat = fid; a.erase("feat_choice"); _show())
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = str(a.get("feat", "")) == fid
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = taken
		b.tooltip_text = f.get("desc", "") + (("\nPrerequisite: " + unmet) if unmet != "" else "")
		left.add_child(b)
	var right = UIKit.vbox(6)
	UIKit.expand(right)
	cols.add_child(right)
	var fid2: String = str(a.get("feat", ""))
	if fid2 == "":
		right.add_child(UIKit.lbl("Pick a feat to read it. ⚙ means it's automated in combat.", 15, UIKit.MUTED))
		return
	var fd := Data.feat(fid2)
	right.add_child(UIKit.lbl(fd.get("name", fid2), 20, UIKit.GOLD))
	right.add_child(DialogPanel.wrap_lbl(fd.get("desc", ""), 15, UIKit.INK))
	var unmet2 := Progression.feat_unmet(base, fid2)
	if unmet2 != "":
		right.add_child(DialogPanel.wrap_lbl("Prerequisite not met: " + unmet2, 14, UIKit.BAD))
	var abil: Array = fd.get("ability", [])
	if abil.size() > 1:
		var items2: Array = []
		for x in abil:
			items2.append([x, "+1 %s  (%d)" % [str(x).to_upper(), int(scores.get(x, 10))]])
		if not a.has("feat_choice"):
			a.feat_choice = abil[0]
		var r3 = UIKit.hbox(8)
		r3.add_child(UIKit.lbl("Ability increase", 14, UIKit.MUTED))
		r3.add_child(UIKit.option(items2, a.feat_choice, func(id): a.feat_choice = id))
		right.add_child(r3)
	elif abil.size() == 1:
		right.add_child(UIKit.lbl("Also +1 %s" % str(abil[0]).to_upper(), 14, UIKit.GOOD))

# ---------------------------------------------------------------- step: class options

func _step_options() -> void:
	var after := _preview(false)
	var g := Progression.gains(base, pick["class"], str(pick.subclass))
	for fc in Progression.feature_choices(g.features + g.subclass_features):
		var key: String = fc.key
		if not pick.choices.has(key):
			pick.choices[key] = base.get("choices", {}).get(key, fc.default)
		var r = UIKit.hbox(10)
		r.add_child(UIKit.lbl(fc.title, 15, UIKit.GOLD))
		r.add_child(UIKit.option(fc.items, pick.choices[key], func(id): pick.choices[key] = id))
		content.add_child(r)
	for o in Progression.option_limits(after):
		var key: String = o.key
		if not pick.picks.has(key):
			pick.picks[key] = base.get(key, []).duplicate()
		var chosen: Array = pick.picks[key]
		var limit: int = int(o.limit)
		var head = UIKit.lbl("", 16, UIKit.GOLD)
		content.add_child(head)
		var upd = func():
			head.text = "%s — %d of %d chosen" % [o.title, chosen.size(), limit]
			head.add_theme_color_override("font_color", UIKit.GOLD if chosen.size() == limit else Color("#ffb347"))
		upd.call()
		var grid = GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 12)
		var boxes: Array = []
		for id in o.options:
			var oid: String = id
			var cb = UIKit.check(Data.pretty(oid), oid in chosen)
			cb.tooltip_text = str(o.options[id])
			cb.custom_minimum_size = Vector2(220, 0)
			cb.toggled.connect(func(p):
				if p and not oid in chosen:
					if chosen.size() >= limit and not allow_unmet:
						cb.set_pressed_no_signal(false)
						status_lbl.text = "You can choose %d %s. Untick one first." % [limit, str(o.title).to_lower()]
						return
					chosen.append(oid)
				elif not p:
					chosen.erase(oid)
				status_lbl.text = ""
				upd.call())
			boxes.append(cb)
			grid.add_child(cb)
		content.add_child(grid)
		var newly := ""
		for o2 in Progression.option_limits(base):
			if o2.key == key and int(o2.limit) < limit:
				newly = " (up from %d)" % int(o2.limit)
		if newly == "" and Progression.option_limits(base).filter(func(x): return x.key == key).is_empty():
			newly = " (new at this level)"
		content.add_child(DialogPanel.wrap_lbl("You may know %d%s. Hover an option for its rules text. You can also swap ones you already know." % [limit, newly], 13))

# ---------------------------------------------------------------- step: skills

func _step_skills() -> void:
	var g := Progression.gains(base, pick["class"], str(pick.subclass))
	var st := Rules.derive(base)
	if g.mc_skills > 0:
		var cd := Data.cls(pick["class"])
		var allowed: Array = cd.get("skill_list", [])
		content.add_child(UIKit.lbl("Multiclass skill — choose %d from the %s list (%d chosen)" % [g.mc_skills, cd.name, pick.skills.size()], 16, UIKit.GOLD))
		var grid = GridContainer.new()
		grid.columns = 3
		for s in Data.SKILLS:
			if not ("*" in allowed or s in allowed):
				continue
			var sk: String = s
			var have: bool = sk in st.skill_prof
			var cb = UIKit.check(Data.pretty(sk) + ("  (have)" if have else ""), sk in pick.skills, func(p):
				if p and not sk in pick.skills:
					if pick.skills.size() >= g.mc_skills and not allow_unmet:
						status_lbl.text = "Choose %d." % g.mc_skills
						_show()
						return
					pick.skills.append(sk)
				elif not p:
					pick.skills.erase(sk)
				_show())
			cb.disabled = have
			cb.custom_minimum_size = Vector2(220, 0)
			grid.add_child(cb)
		content.add_child(grid)
	var after := _preview()
	var exp_limit := Progression.expertise_limit(after)
	var exp_have: Array = base.get("expertise", [])
	var exp_new: int = exp_limit - exp_have.size()
	if exp_new > 0:
		content.add_child(UIKit.lbl("Expertise — choose %d skill%s you're proficient in (%d chosen)" % [exp_new, "" if exp_new == 1 else "s", pick.expertise.size()], 16, UIKit.GOLD))
		var prof: Array = Rules.derive(after).skill_prof
		var grid2 = GridContainer.new()
		grid2.columns = 3
		for s in Data.SKILLS:
			if not s in prof or s in exp_have:
				continue
			var sk2: String = s
			var cb2 = UIKit.check(Data.pretty(sk2), sk2 in pick.expertise, func(p):
				if p and not sk2 in pick.expertise:
					if pick.expertise.size() >= exp_new and not allow_unmet:
						status_lbl.text = "Choose %d." % exp_new
						_show()
						return
					pick.expertise.append(sk2)
				elif not p:
					pick.expertise.erase(sk2)
				_show())
			cb2.custom_minimum_size = Vector2(220, 0)
			grid2.add_child(cb2)
		content.add_child(grid2)
		content.add_child(DialogPanel.wrap_lbl("Thieves' tools expertise isn't tracked here; note it on your sheet if you choose it.", 13))

# ---------------------------------------------------------------- step: spells

func _step_spells() -> void:
	var cid: String = pick["class"]
	var after := _preview()
	var entry := _entry(after, cid)
	var st := Rules.derive(after)
	var counts := Rules.spell_counts(after, entry, st.scores)
	var max_lv := Rules.max_spell_level_for(entry)
	var wiz: bool = cid == "wizard"
	if not pick.spells.has(cid):
		pick.spells[cid] = base.get("spells", {}).get(cid, []).duplicate()
	if wiz and not pick.has("spellbook"):
		pick.spellbook = Rules.wizard_spellbook(base).duplicate()
	var chosen: Array = pick.spells[cid]
	var known: bool = counts.prepare == "known" and not wiz
	var head = UIKit.lbl("", 16, UIKit.GOLD)
	content.add_child(head)
	var old_counts := {"cantrips": 0, "spells": 0}
	var old_entry := _entry(base, cid)
	if not old_entry.is_empty() and Rules.caster_type(old_entry) != "":
		old_counts = Rules.spell_counts(base, old_entry, Rules.final_scores(base))
	var book_free := 0
	if wiz:
		book_free = Rules.spellbook_free_spells(int(entry.level)) - (Rules.spellbook_free_spells(int(old_entry.level)) if not old_entry.is_empty() else 0)
	var base_book: Array = Rules.wizard_spellbook(base) if wiz else []
	var upd = func():
		var nc: int = chosen.filter(func(x): return int(Data.spell(x).get("level", 0)) == 0).size()
		var t := "%s spells (up to level %d) — cantrips %d/%d, %s %d/%d" % [Data.cls(cid).name, max_lv, nc, int(counts.cantrips), "known" if known else "prepared", chosen.size() - nc, int(counts.spells)]
		if wiz:
			var added: int = (pick.spellbook as Array).filter(func(x): return not x in base_book).size()
			t += ", new in spellbook %d/%d" % [added, book_free]
		head.text = t
	upd.call()
	var notes: PackedStringArray = []
	if int(counts.cantrips) > int(old_counts.cantrips):
		notes.append("+%d cantrip" % (int(counts.cantrips) - int(old_counts.cantrips)))
	if int(counts.spells) > int(old_counts.spells):
		notes.append("+%d %s spell%s" % [int(counts.spells) - int(old_counts.spells), "known" if known else "prepared", "" if int(counts.spells) - int(old_counts.spells) == 1 else "s"])
	if wiz and book_free > 0:
		notes.append("write %d new spells into your spellbook for free" % book_free)
	if not notes.is_empty():
		content.add_child(UIKit.lbl("This level: " + ", ".join(notes), 15, UIKit.GOOD))
	if known:
		content.add_child(DialogPanel.wrap_lbl("You may also replace one spell you know with another from your class list (untick it, tick the new one).", 13))
	elif wiz:
		content.add_child(DialogPanel.wrap_lbl("Tick Book for spells you write into your spellbook and the first box for the ones you prepare. You can prepare any spell in your book after a long rest.", 13))
	else:
		content.add_child(DialogPanel.wrap_lbl("You can change these after any long rest, so there's no wrong answer here.", 13))
	var search = UIKit.line(spell_filter, "Filter spells by name or text…")
	content.add_child(search)
	var tree = Tree.new()
	tree.columns = 4 if wiz else 3
	tree.hide_root = true
	tree.column_titles_visible = true
	var book_col := 1 if wiz else -1
	var lvl_col := 2 if wiz else 1
	var sum_col := 3 if wiz else 2
	tree.set_column_title(0, "Prepared" if wiz else ("Known" if known else "Prepared"))
	if wiz:
		tree.set_column_title(book_col, "Book")
		tree.set_column_expand(book_col, false)
		tree.set_column_custom_minimum_width(book_col, 60)
	tree.set_column_title(lvl_col, "Lvl")
	tree.set_column_title(sum_col, "Summary")
	tree.set_column_expand(lvl_col, false)
	tree.set_column_custom_minimum_width(lvl_col, 40)
	tree.set_column_expand(0, false)
	tree.set_column_custom_minimum_width(0, 230)
	tree.custom_minimum_size = Vector2(0, 380)
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var root = tree.create_item()
	var pool: Array = Data.spells_for_class(Rules.spell_list_id(entry), max_lv)
	var extra_list: String = str(Data.subclass(cid, str(entry.get("subclass", ""))).get("spell_list_extra", ""))
	if extra_list != "":
		for s in Data.spells_for_class(extra_list, max_lv):
			if not s in pool:
				pool.append(s)
	var bonus: Array = []
	for e in st.casting:
		if e["class"] == cid:
			bonus = e.bonus_spells
	for s in pool:
		var it = tree.create_item(root)
		it.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
		it.set_editable(0, not s.id in bonus)
		it.set_text(0, s.name + (" (always)" if s.id in bonus else ""))
		it.set_checked(0, s.id in chosen or s.id in bonus)
		if wiz and int(s.level) > 0:
			it.set_cell_mode(book_col, TreeItem.CELL_MODE_CHECK)
			it.set_editable(book_col, true)
			it.set_checked(book_col, s.id in pick.spellbook)
		it.set_text(lvl_col, "C" if int(s.level) == 0 else str(s.level))
		it.set_text(sum_col, str(s.get("summary", "")))
		it.set_tooltip_text(sum_col, str(s.get("summary", "")))
		it.set_metadata(0, s.id)
		if int(s.level) == max_lv and max_lv > Rules.max_spell_level_for(old_entry if not old_entry.is_empty() else {"id": cid, "level": 0}):
			it.set_custom_color(lvl_col, UIKit.GOOD)
	tree.item_edited.connect(func():
		var it: TreeItem = tree.get_edited()
		var col: int = tree.get_edited_column()
		var sid: String = it.get_metadata(0)
		var leveled: bool = int(Data.spell(sid).get("level", 0)) > 0
		if col == book_col and book_col >= 0:
			var bk: Array = pick.spellbook
			if it.is_checked(book_col):
				if not sid in bk: bk.append(sid)
			else:
				bk.erase(sid)
				chosen.erase(sid)
				it.set_checked(0, false)
		elif it.is_checked(0):
			if not sid in chosen: chosen.append(sid)
			if wiz and leveled and not sid in pick.spellbook:
				(pick.spellbook as Array).append(sid)
				it.set_checked(book_col, true)
		else:
			chosen.erase(sid)
		upd.call())
	content.add_child(tree)
	search.text_changed.connect(func(t):
		spell_filter = t.to_lower()
		var it: TreeItem = tree.get_root().get_first_child()
		while it:
			it.visible = spell_filter == "" or spell_filter in it.get_text(0).to_lower() or spell_filter in it.get_text(sum_col).to_lower()
			it = it.get_next())
	if spell_filter != "":
		search.text_changed.emit(spell_filter)

# ---------------------------------------------------------------- step: review

func _step_review() -> void:
	var after := _preview()
	var lines := Progression.diff_lines(base, after)
	var t := "[font_size=18][color=#c9a14a]%s — level %d → %d[/color][/font_size]\n" % [base.get("name", ""), Rules.total_level(base), Rules.total_level(after)]
	for l in lines:
		t += "• %s\n" % str(l).replace("[", "(")
	var hp_how := {"avg": "average", "roll": "rolled", "manual": "your roll"}
	t += "\n[color=#a59cb5]Hit points this level: %d (%s) %s CON[/color]" % [int(pick.hp), hp_how.get(pick.hp_mode, ""), Rules.fmt_mod(Rules.mod(int(Rules.final_scores(after).con)))]
	content.add_child(UIKit.rich(t))
	var warn := _rules_warnings(after)
	if not warn.is_empty():
		content.add_child(DialogPanel.wrap_lbl("⚠ " + "\n⚠ ".join(warn), 14, Color("#ffb347")))
	var nr = UIKit.hbox(8)
	nr.add_child(UIKit.lbl("Note for this level", 14, UIKit.MUTED))
	var ne = UIKit.line(str(pick.note), "e.g. took Sentinel for the tank build (saved in your level plan)", func(tx): pick.note = tx)
	UIKit.expand(ne)
	nr.add_child(ne)
	content.add_child(nr)

## Things the player may still want to do (fewer picks than allowed and so on). Not blocking.
func _rules_warnings(after: Dictionary) -> Array:
	var out: Array = []
	var cid: String = pick["class"]
	var entry := _entry(after, cid)
	if not entry.is_empty() and Rules.caster_type(entry) != "":
		var counts := Rules.spell_counts(after, entry, Rules.final_scores(after))
		var arr: Array = after.get("spells", {}).get(cid, [])
		var nc: int = arr.filter(func(x): return int(Data.spell(x).get("level", 0)) == 0).size()
		if nc < int(counts.cantrips):
			out.append("%d cantrip%s still to choose (you can pick later in the builder)." % [int(counts.cantrips) - nc, "" if int(counts.cantrips) - nc == 1 else "s"])
		if arr.size() - nc < int(counts.spells):
			out.append("%d spell%s still to choose." % [int(counts.spells) - (arr.size() - nc), "" if int(counts.spells) - (arr.size() - nc) == 1 else "s"])
	return out

# ---------------------------------------------------------------- validation

func _validate() -> String:
	var cid: String = pick["class"]
	match step:
		"class":
			if cid == "" or Data.cls(cid).is_empty():
				return "Pick a class."
			if Rules.total_level(base) >= Progression.MAX_LEVEL:
				return "This character is already level 20."
			var unmet := Progression.multiclass_unmet(base, cid)
			if not unmet.is_empty() and not allow_unmet:
				return "Multiclass prerequisite not met: %s. Tick the DM-approved box to allow it." % "; ".join(unmet)
		"subclass":
			if str(pick.subclass) == "":
				return "Choose a subclass."
		"asi":
			var a: Dictionary = pick.asi
			if a.get("type", "") == "feat":
				if str(a.get("feat", "")) == "":
					return "Choose a feat, or switch to an ability score increase."
				var un := Progression.feat_unmet(base, str(a.feat))
				if un != "" and not allow_unmet:
					return "Feat prerequisite not met: %s." % un
			else:
				var scores := Rules.final_scores(base)
				var cap_hit: bool = int(scores.get(a.get("a", "str"), 10)) >= 20 or (a.type == "asi11" and int(scores.get(a.get("b", "str"), 10)) >= 20)
				if a.type == "asi11" and a.a == a.b:
					return "Pick two different abilities (or use +2 to one)."
				if cap_hit and not allow_unmet:
					return "That ability is already 20, the maximum."
		"options":
			if not allow_unmet:
				for o in Progression.option_limits(_preview(false)):
					var n: int = (pick.picks.get(o.key, base.get(o.key, [])) as Array).size()
					if n != int(o.limit):
						return "%s: choose %d (you have %d)." % [o.title, int(o.limit), n]
		"skills":
			if not allow_unmet:
				var g := Progression.gains(base, cid, str(pick.subclass))
				if pick.skills.size() < g.mc_skills:
					return "Choose your multiclass skill."
				var exp_new: int = Progression.expertise_limit(_preview()) - base.get("expertise", []).size()
				if pick.expertise.size() < exp_new:
					return "Choose %d skill%s for expertise." % [exp_new, "" if exp_new == 1 else "s"]
		"spells":
			if not allow_unmet:
				var after := _preview()
				var entry := _entry(after, cid)
				var counts := Rules.spell_counts(after, entry, Rules.final_scores(after))
				var arr: Array = pick.spells.get(cid, [])
				var nc: int = arr.filter(func(x): return int(Data.spell(x).get("level", 0)) == 0).size()
				if nc > int(counts.cantrips):
					return "Too many cantrips: %d of %d." % [nc, int(counts.cantrips)]
				if arr.size() - nc > int(counts.spells):
					return "Too many spells: %d of %d." % [arr.size() - nc, int(counts.spells)]
				var max_lv := Rules.max_spell_level_for(entry)
				for sid in arr:
					if int(Data.spell(sid).get("level", 0)) > max_lv:
						return "%s is above the highest spell level you can learn (%d)." % [Data.spell(sid).get("name", sid), max_lv]
	return ""

## Fill in whatever the current step needs so a test (or a hurried player) can move on.
func _defaults() -> void:
	var cid: String = pick["class"]
	match step:
		"class":
			if Data.cls(cid).is_empty():
				pick["class"] = str(base.classes[0].id)
			allow_unmet = allow_unmet or not Progression.multiclass_unmet(base, pick["class"]).is_empty()
		"subclass":
			var subs: Array = Data.cls(cid).get("subclasses", [])
			if not subs.is_empty():
				pick.subclass = str(subs[0].id)
		"asi":
			var scores := Rules.final_scores(base)
			var best := ""
			for x in Data.cls(cid).get("primary", []) + Data.ABILITIES:
				if int(scores[x]) <= 18 and best == "":
					best = x
			pick.asi = {"type": "asi2", "a": best if best != "" else "str", "b": best if best != "" else "str"}
			if best == "":
				allow_unmet = true
		"options":
			for o in Progression.option_limits(_preview(false)):
				var arr: Array = pick.picks.get(o.key, base.get(o.key, [])).duplicate()
				for id in o.options:
					if arr.size() >= int(o.limit):
						break
					if not id in arr:
						arr.append(id)
				while arr.size() > int(o.limit):
					arr.pop_back()
				pick.picks[o.key] = arr
		"skills":
			var g := Progression.gains(base, cid, str(pick.subclass))
			var st := Rules.derive(base)
			var allowed: Array = Data.cls(cid).get("skill_list", [])
			for s in Data.SKILLS:
				if pick.skills.size() >= g.mc_skills:
					break
				if ("*" in allowed or s in allowed) and not s in st.skill_prof:
					pick.skills.append(s)
			var after := _preview()
			var exp_new: int = Progression.expertise_limit(after) - base.get("expertise", []).size()
			for s in Rules.derive(after).skill_prof:
				if pick.expertise.size() >= exp_new:
					break
				if not s in base.get("expertise", []) and not s in pick.expertise:
					pick.expertise.append(s)
		"spells":
			allow_unmet = true

func _confirm() -> void:
	var after := _preview()
	var label := "Before level %d (%s %d)" % [Rules.total_level(after), Data.cls(pick["class"]).get("name", ""), Rules.class_level(after, pick["class"])]
	finished.emit(after, label)
	close()
