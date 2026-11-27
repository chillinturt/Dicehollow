class_name CharacterSheet
extends DialogPanel
## A read-through character sheet for any party member: overview (scores, saves, skills, attacks,
## spellcasting, resources), features, spells, the level plan and (for the owner) the sheet history.
## In a game it also shows live hit points, slots and conditions, and the Level Up button when the
## DM has granted a level.

signal level_up_requested
signal plan_changed(plan: Array)
signal restore_requested(index: int)

var sheet: Dictionary
var live: Dictionary = {}
var editable := false
var advancement := "milestone"
var history: Array = []
var tabs: TabContainer
var head_box: HBoxContainer
var pending := 0
var history_remote := false  # the backups live on the player's computer, not this one

## opts: live (combatant), editable (bool), advancement ("xp" | "milestone"), history (Array),
## pending (levels the DM has granted but not yet taken)
func _init(ch: Dictionary, opts := {}) -> void:
	super("Character sheet", Vector2(1080, 780))
	sheet = ch
	live = opts.get("live", {})
	editable = opts.get("editable", false)
	advancement = str(opts.get("advancement", "milestone"))
	history = opts.get("history", [])
	pending = int(opts.get("pending", 0))
	history_remote = opts.get("history_remote", false)
	head_box = UIKit.hbox(12)
	body.add_child(head_box)
	tabs = TabContainer.new()
	UIKit.expand(tabs, true, true)
	body.add_child(tabs)
	rebuild()

## Rebuild everything (after the sheet itself changed), keeping the open tab.
func rebuild(new_sheet: Dictionary = {}, opts := {}) -> void:
	if not new_sheet.is_empty():
		sheet = new_sheet
	for k in opts:
		match k:
			"live": live = opts.live
			"history": history = opts.history
			"pending": pending = int(opts.pending)
			"advancement": advancement = str(opts.advancement)
			"editable": editable = opts.editable
			"history_remote": history_remote = opts.history_remote
	var cur := tabs.current_tab
	set_title("%s — character sheet" % sheet.get("name", "?"))
	_build_head()
	UIKit.clear(tabs)
	_tab_overview()
	_tab_features()
	_tab_spells()
	var pv = _page("Level Plan")
	var plan := LevelPlanView.new(sheet, editable)
	plan.changed.connect(func(p): plan_changed.emit(p))
	pv.add_child(plan)
	if editable:
		_tab_history()
	tabs.current_tab = clampi(cur, 0, tabs.get_tab_count() - 1)

## Refresh only the live numbers at the top (hit points, slots, conditions).
func update_live(c: Dictionary, new_pending := -1) -> void:
	live = c
	if new_pending >= 0:
		pending = new_pending
	_build_head()

func _page(title: String) -> VBoxContainer:
	var v = UIKit.vbox(10)
	var sc = UIKit.scroll(UIKit.margin(v, 10))
	sc.name = title
	tabs.add_child(sc)
	return v

# ---------------------------------------------------------------- header

func _build_head() -> void:
	UIKit.clear(head_box)
	var st := Rules.derive(sheet)
	var frame = UIKit.panel(null, Color("#0d0b12"), Color(sheet.get("color", "#7a5cff")))
	frame.custom_minimum_size = Vector2(84, 84)
	var tex = CharacterStore.portrait_texture(str(sheet.get("portrait", "")))
	if tex:
		var tr = TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		frame.add_child(tr)
	else:
		var ini = UIKit.lbl(UIKit.initials(str(sheet.get("name", "?"))), 32, Color(sheet.get("color", "#7a5cff")))
		ini.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ini.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		frame.add_child(ini)
	head_box.add_child(frame)
	var v = UIKit.vbox(2)
	UIKit.expand(v)
	head_box.add_child(v)
	v.add_child(UIKit.lbl(str(sheet.get("name", "")), 22, UIKit.GOLD))
	var who := "%s %s  ·  %s" % [CombatantFactory._race_name(sheet), Rules.class_summary(sheet), Data.pretty(str(sheet.get("background", "")))]
	if str(sheet.get("player", "")) != "":
		who += "  ·  played by " + str(sheet.player)
	v.add_child(DialogPanel.wrap_lbl(who, 14))
	var prog := "Level %d" % st.level
	if advancement == "xp":
		var xp: int = int(sheet.get("xp", 0))
		prog += "   ·   XP %s" % _thousands(xp)
		if st.level < Progression.MAX_LEVEL:
			prog += " / %s for level %d" % [_thousands(Progression.xp_for_level(st.level + 1)), st.level + 1]
	else:
		prog += "   ·   milestone levelling"
	v.add_child(UIKit.lbl(prog, 13, UIKit.MUTED))
	if advancement == "xp" and st.level < Progression.MAX_LEVEL:
		var lo := Progression.xp_for_level(st.level)
		var hi := Progression.xp_for_level(st.level + 1)
		v.add_child(UIKit.bar(clampi(int(sheet.get("xp", 0)) - lo, 0, hi - lo), hi - lo, UIKit.GOLD, 6))
	if not live.is_empty():
		var lv = UIKit.vbox(2)
		lv.custom_minimum_size = Vector2(250, 0)
		var hp_txt := "HP %d / %d" % [maxi(int(live.hp), 0), int(live.max_hp)]
		if int(live.get("temp_hp", 0)) > 0:
			hp_txt += "  +%d temp" % int(live.temp_hp)
		lv.add_child(UIKit.lbl(hp_txt, 16))
		lv.add_child(UIKit.bar(maxi(int(live.hp), 0), int(live.max_hp), UIKit.GOOD, 8))
		var conds: PackedStringArray = []
		for e in live.get("effects", []):
			if str(e.get("name", "")) != "":
				conds.append(str(e.name))
		if not conds.is_empty():
			lv.add_child(DialogPanel.wrap_lbl(", ".join(conds), 12, Color("#e0a0ff")))
		head_box.add_child(lv)
	if pending > 0:
		var lb = UIKit.btn("⬆ Level Up (%d)" % pending if pending > 1 else "⬆ Level Up", func(): level_up_requested.emit(),
			"The DM has granted a new level. Open the guided level-up.")
		lb.custom_minimum_size = Vector2(150, 44)
		lb.add_theme_font_size_override("font_size", 17)
		lb.add_theme_color_override("font_color", UIKit.GOLD)
		lb.add_theme_stylebox_override("normal", UIKit.sb(Color("#3a2c12"), UIKit.GOLD, 2))
		lb.disabled = not editable
		if not editable:
			lb.tooltip_text = "Only this character's player (or the DM) can level them up."
		head_box.add_child(lb)

static func _thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if n < 0 else "") + s + out

# ---------------------------------------------------------------- overview

func _tab_overview() -> void:
	var v = _page("Overview")
	var st := Rules.derive(sheet)
	var cols = UIKit.hbox(18)
	v.add_child(cols)
	var left = UIKit.vbox(10)
	left.custom_minimum_size = Vector2(380, 0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 0.9
	cols.add_child(left)
	var right = UIKit.vbox(10)
	right.custom_minimum_size = Vector2(380, 0)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	# Core numbers.
	var core := "[table=4]"
	var cells := [["Armor Class", "%d [color=#8a7fa0](%s)[/color]" % [st.ac, st.ac_note]], ["Hit Points", str(st.max_hp)],
		["Speed", "%d ft" % st.speed], ["Initiative", Rules.fmt_mod(st.initiative) + (" (adv)" if st.init_advantage else "")],
		["Proficiency", "+%d" % st.prof], ["Passive Perception", str(st.passive_perception)],
		["Hit Dice", st.hit_dice], ["Darkvision", ("%d ft" % st.darkvision) if st.darkvision > 0 else "—"]]
	for c in cells:
		core += "[cell][color=#a59cb5]%s[/color]  [/cell][cell][b]%s[/b]    [/cell]" % [c[0], c[1]]
	core += "[/table]"
	left.add_child(_section("Core", core))
	# Abilities and saves.
	var ab := "[table=5][cell][color=#a59cb5]Ability   [/color][/cell][cell][color=#a59cb5]Score  [/color][/cell][cell][color=#a59cb5]Mod  [/color][/cell][cell][color=#a59cb5]Save  [/color][/cell][cell][/cell]"
	for a in Data.ABILITIES:
		var prof: bool = a in st.saves
		ab += "[cell]%s[/cell][cell][b]%d[/b][/cell][cell]%s[/cell][cell]%s%s[/cell][cell][/cell]" % [Data.ABILITY_NAMES[a], st.scores[a], Rules.fmt_mod(st.mods[a]), "● " if prof else "○ ", Rules.fmt_mod(st.save_bonus[a])]
	ab += "[/table]"
	left.add_child(_section("Abilities & saving throws", ab))
	# Skills.
	var sk := "[table=2]"
	var exp: Array = sheet.get("expertise", [])
	for s in Data.SKILLS:
		var mark := "◆ " if s in exp else ("● " if s in st.skill_prof else "○ ")
		var col := "#ece6d8" if s in st.skill_prof else "#a59cb5"
		sk += "[cell][color=%s]%s%s (%s)[/color]   [/cell][cell][b]%s[/b][/cell]" % [col, mark, Data.pretty(s), str(Data.SKILLS[s]).to_upper(), Rules.fmt_mod(int(st.skills[s]))]
	sk += "[/table]\n[color=#8a7fa0]● proficient   ◆ expertise[/color]"
	left.add_child(_section("Skills", sk))
	# Attacks.
	var at := ""
	for w in st.weapons:
		var dmg: PackedStringArray = []
		for d in w.damage:
			dmg.append("%s %s" % [d.dice, d.type])
		var rng := ""
		if not w.melee:
			rng = "  [color=#8a7fa0]%d/%d ft[/color]" % [int(w.range), int(w.long_range)] if int(w.get("range", 0)) > 0 else ""
		elif int(w.get("reach", 5)) > 5:
			rng = "  [color=#8a7fa0]reach %d ft[/color]" % int(w.reach)
		at += "• [b]%s[/b]  %s to hit, %s%s%s\n" % [w.name, Rules.fmt_mod(int(w.to_hit)), " + ".join(dmg), rng, "  [color=#8a7fa0](bonus action)[/color]" if w.get("cost", "") == "bonus" else ""]
	at += "[color=#8a7fa0]Attacks per Attack action: %d   ·   Critical on %d+[/color]" % [int(st.vals.attacks), int(st.vals.crit_range)]
	right.add_child(_section("Attacks", at))
	# Spellcasting.
	if not st.casting.is_empty() or st.pact.count > 0:
		var sc := ""
		for e in st.casting:
			sc += "• [b]%s[/b] (%s): save DC %d, spell attack %s, %d spells\n" % [e.name, str(e.ability).to_upper(), e.dc, Rules.fmt_mod(e.attack), e.spells.size()]
		var slots := PackedStringArray()
		for i in st.slots.size():
			var used := 0
			if not live.is_empty() and i < live.get("slots_used", []).size():
				used = int(live.slots_used[i])
			slots.append("L%d %s" % [i + 1, "●".repeat(int(st.slots[i]) - used) + "○".repeat(used)])
		if not slots.is_empty():
			sc += "Slots: " + "   ".join(slots) + "\n"
		if st.pact.count > 0:
			var pu: int = int(live.get("pact_used", 0)) if not live.is_empty() else 0
			sc += "Pact slots (level %d): %s\n" % [st.pact.level, "●".repeat(st.pact.count - pu) + "○".repeat(pu)]
		right.add_child(_section("Spellcasting", sc.strip_edges()))
	# Resources.
	if not st.resources.is_empty():
		var rs := ""
		for k in st.resources:
			var r: Dictionary = st.resources[k]
			var cur := int(r.max)
			if not live.is_empty() and live.get("resources", {}).has(k):
				cur = int(live.resources[k].cur)
			rs += "• %s: [b]%d / %d[/b]  [color=#8a7fa0](%s rest)[/color]\n" % [r.name, cur, int(r.max), r.reset]
		right.add_child(_section("Limited-use features", rs.strip_edges()))
	# Proficiencies and choices.
	var pr := "[b]Armor:[/b] %s\n[b]Weapons:[/b] %s" % [", ".join(st.armor_prof.map(func(x): return Data.pretty(x))) if not st.armor_prof.is_empty() else "none", ", ".join(st.weapon_prof.map(func(x): return Data.pretty(x)))]
	if not st.resist.is_empty():
		pr += "\n[b]Resistances:[/b] " + ", ".join(st.resist)
	for key in ["fighting_styles", "maneuvers", "metamagic", "invocations", "infusions"]:
		var arr: Array = sheet.get(key, [])
		if not arr.is_empty():
			pr += "\n[b]%s:[/b] %s" % [Data.pretty(key), ", ".join(arr.map(func(x): return Data.pretty(x)))]
	if not st.feats.is_empty():
		pr += "\n[b]Feats:[/b] " + ", ".join(st.feats.map(func(x): return Data.feat(x).get("name", x)))
	var eq: Dictionary = sheet.get("equipment", {})
	var gear: PackedStringArray = []
	if str(eq.get("armor", "")) != "":
		gear.append(Data.item(eq.armor).get("name", eq.armor) + (" +%d" % int(eq.armor_bonus) if int(eq.get("armor_bonus", 0)) > 0 else ""))
	if eq.get("shield", false):
		gear.append("Shield")
	for wid in eq.get("weapons", []):
		gear.append(Data.item(wid).get("name", wid))
	if not gear.is_empty():
		pr += "\n[b]Equipment:[/b] " + ", ".join(gear)
	right.add_child(_section("Proficiencies & choices", pr))
	if str(sheet.get("notes", "")).strip_edges() != "":
		right.add_child(_section("Notes", str(sheet.notes).replace("[", "(")))

func _section(title: String, bb: String) -> Control:
	var v = UIKit.vbox(4)
	v.add_child(UIKit.lbl(title, 16, UIKit.GOLD))
	var r = UIKit.rich(bb)
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(r)
	return v

# ---------------------------------------------------------------- features

func _tab_features() -> void:
	var v = _page("Features")
	var st := Rules.derive(sheet)
	var by_src: Dictionary = {}
	var order: Array = []
	for fi in st.feature_info:
		# "Fighter 3" groups under "Fighter"; race and feat sources have no level.
		var src: String = str(fi.src)
		if src.get_slice(" ", src.get_slice_count(" ") - 1).is_valid_int():
			src = src.substr(0, src.rfind(" "))
		if not by_src.has(src):
			by_src[src] = []
			order.append(src)
		by_src[src].append(fi)
	for src in order:
		var txt := ""
		for fi in by_src[src]:
			var lvl := ""
			var tail: String = str(fi.src).get_slice(" ", str(fi.src).get_slice_count(" ") - 1)
			if tail.is_valid_int():
				lvl = "  [color=#8a7fa0]level %s[/color]" % tail
			txt += "[b]%s[/b]%s%s\n%s\n\n" % [fi.name, lvl, "  [color=#5cc892]⚙ automated[/color]" if fi.auto else "", fi.desc]
		v.add_child(_section(src, txt.strip_edges()))

# ---------------------------------------------------------------- spells

func _tab_spells() -> void:
	var v = _page("Spells")
	var st := Rules.derive(sheet)
	if st.casting.is_empty():
		v.add_child(UIKit.lbl("This character doesn't cast spells.", 15, UIKit.MUTED))
		return
	for e in st.casting:
		var head := "%s — DC %d, attack %s" % [e.name, e.dc, Rules.fmt_mod(e.attack)]
		var counts: Dictionary = e.get("counts", {})
		if not counts.is_empty():
			head += ", %s %d cantrips and %d spells" % ["knows" if counts.get("prepare", "") == "known" and e["class"] != "wizard" else "prepares", int(counts.cantrips), int(counts.spells)]
		var txt := ""
		var by_lv: Dictionary = {}
		for sid in e.spells:
			var lv: int = int(Data.spell(sid).get("level", 0))
			if not by_lv.has(lv):
				by_lv[lv] = []
			by_lv[lv].append(sid)
		var lvls: Array = by_lv.keys()
		lvls.sort()
		for lv in lvls:
			txt += "[color=#c8a0ff]%s[/color]\n" % ("Cantrips" if lv == 0 else "Level %d" % lv)
			for sid in by_lv[lv]:
				var sp := Data.spell(sid)
				var always: bool = sid in e.get("bonus_spells", [])
				txt += "• [b]%s[/b]%s  [color=#a59cb5]%s[/color]\n" % [sp.get("name", sid), "  [color=#5cc892](always prepared)[/color]" if always else "", str(sp.get("summary", "")).replace("[", "(")]
		if e.has("spellbook"):
			var extra: Array = (e.spellbook as Array).filter(func(x): return not x in e.spells)
			if not extra.is_empty():
				txt += "[color=#c8a0ff]Also in the spellbook (not prepared)[/color]\n" + ", ".join(extra.map(func(x): return Data.spell(x).get("name", x))) + "\n"
		v.add_child(_section(head, txt.strip_edges()))

# ---------------------------------------------------------------- history

func _tab_history() -> void:
	var v = _page("History")
	v.add_child(DialogPanel.wrap_lbl("A backup is saved before every level-up, restore and rebuild in the character builder. Restoring puts that version back as the current sheet; the version you replace is backed up too, so a restore can be undone. XP and levels granted by the DM are kept.", 13))
	if history_remote:
		v.add_child(DialogPanel.wrap_lbl("This character's backups are kept on their player's computer. Level-ups and restores you make here are saved there, with a backup of the version they replace.", 14, UIKit.INK))
		return
	if history.is_empty():
		v.add_child(UIKit.lbl("No backups yet. One is made the first time this character levels up.", 14, UIKit.MUTED))
		return
	for i in range(history.size() - 1, -1, -1):
		var h: Dictionary = history[i]
		var row = UIKit.hbox(10)
		var info = UIKit.vbox(2)
		UIKit.expand(info)
		var when := Time.get_datetime_string_from_unix_time(int(h.get("t", 0)) + _tz_offset(), true)
		info.add_child(UIKit.lbl(str(h.get("label", "Backup")), 15, UIKit.INK))
		info.add_child(DialogPanel.wrap_lbl("%s   ·   level %d: %s" % [when, int(h.get("level", 0)), str(h.get("summary", ""))], 12))
		var diffs := Progression.diff_lines(h.get("data", {}), sheet)
		if not diffs.is_empty():
			var dl = DialogPanel.wrap_lbl("Differs from the current sheet: " + "; ".join(diffs.slice(0, 4)) + (" …" if diffs.size() > 4 else ""), 12, Color("#c8b48a"))
			info.add_child(dl)
		row.add_child(info)
		var idx := i
		var rb = UIKit.btn("Restore", func(): restore_requested.emit(idx), "Make this version the current sheet (the current one is backed up first)")
		rb.custom_minimum_size = Vector2(96, 34)
		row.add_child(rb)
		v.add_child(row)
		v.add_child(HSeparator.new())

static func _tz_offset() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60
