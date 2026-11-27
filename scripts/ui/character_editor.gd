extends Control
## Character list + full character builder (race, classes/multiclass, subclasses, ASIs/feats,
## abilities, skills, equipment, spells, portrait) with a live derived sheet.

var chars: Array = []
var ch: Dictionary = {}
var list_box: ItemList
var tabs: TabContainer
var title_lbl: Label
var sheet_rt: RichTextLabel
var dirty := false
var file_dialog: FileDialog
var spell_filter := ""

func _ready() -> void:
	theme = UIKit.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_fit()
	get_viewport().size_changed.connect(_fit)
	var bg = ColorRect.new()
	bg.color = UIKit.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root = UIKit.hbox(12)
	var m = UIKit.margin(root, 14)
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(m)
	# Left: list.
	var left = UIKit.vbox(8)
	left.custom_minimum_size = Vector2(300, 0)
	root.add_child(left)
	left.add_child(UIKit.header("Characters"))
	list_box = ItemList.new()
	UIKit.expand(list_box, true, true)
	list_box.item_selected.connect(_on_pick)
	left.add_child(list_box)
	var row1 = UIKit.hbox()
	row1.add_child(UIKit.expand(UIKit.btn("New", _new_char)))
	row1.add_child(UIKit.expand(UIKit.btn("Duplicate", _dup_char)))
	row1.add_child(UIKit.expand(UIKit.btn("Delete", _delete_char)))
	left.add_child(row1)
	left.add_child(UIKit.btn("Add premade characters", _add_premades, "Adds the sample party, including builds based on your Scribe Artificer and Chronurgist sheets."))
	left.add_child(UIKit.btn("← Back to menu", func(): get_tree().change_scene_to_file("res://scenes/main_menu.tscn")))
	# Right: editor.
	var right = UIKit.vbox(8)
	UIKit.expand(right, true, true)
	root.add_child(right)
	var top = UIKit.hbox(10)
	title_lbl = UIKit.header("")
	UIKit.expand(title_lbl)
	top.add_child(title_lbl)
	var lvl = UIKit.btn("⬆ Level Up…", func(): _open_level_up(), "Guided level-up: pick a class or multiclass, hit points, subclass, ASI or feat, options and spells. A backup of the current sheet is kept in History.")
	lvl.custom_minimum_size = Vector2(150, 38)
	top.add_child(lvl)
	var save = UIKit.btn("💾 Save Character", _save)
	save.custom_minimum_size = Vector2(180, 38)
	top.add_child(save)
	right.add_child(top)
	var split = HSplitContainer.new()
	UIKit.expand(split, true, true)
	right.add_child(split)
	tabs = TabContainer.new()
	UIKit.expand(tabs, true, true)
	tabs.custom_minimum_size = Vector2(700, 0)
	split.add_child(tabs)
	var sheet_panel = UIKit.panel()
	sheet_panel.custom_minimum_size = Vector2(360, 0)
	sheet_rt = UIKit.rich("", false)
	UIKit.expand(sheet_rt, true, true)
	sheet_panel.add_child(sheet_rt)
	split.add_child(sheet_panel)
	file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.use_native_dialog = true
	file_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp, *.bmp, *.svg ; Images"])
	file_dialog.file_selected.connect(_on_portrait_file)
	add_child(file_dialog)
	_reload_list()
	if chars.is_empty():
		_new_char()
	else:
		list_box.select(0)
		_on_pick(0)

# ================================================================ list

func _reload_list(select_id := "") -> void:
	chars = CharacterStore.list_characters()
	list_box.clear()
	var sel = -1
	for i in chars.size():
		var c: Dictionary = chars[i]
		list_box.add_item("%s\n   %s" % [c.get("name", "?"), Rules.class_summary(c)])
		var tex = CharacterStore.portrait_texture(c.get("portrait", ""))
		if tex:
			list_box.set_item_icon(i, tex)
		if c.get("id", "") == select_id:
			sel = i
	list_box.fixed_icon_size = Vector2i(40, 40)
	if sel >= 0:
		list_box.select(sel)

func _on_pick(idx: int) -> void:
	ch = chars[idx].duplicate(true)
	_ensure_fields()
	_rebuild()

func _new_char() -> void:
	ch = Rules.new_character()
	ch.base_scores = {"str": 15, "dex": 14, "con": 13, "int": 12, "wis": 10, "cha": 8}
	ch.score_method = "standard"
	_apply_class_defaults(ch.classes[0].id)
	list_box.deselect_all()
	_rebuild()

func _dup_char() -> void:
	if ch.is_empty():
		return
	ch = ch.duplicate(true)
	ch.id = ""
	ch.name = str(ch.name) + " (copy)"
	_save()

func _delete_char() -> void:
	if ch.get("id", "") == "":
		return
	CharacterStore.delete_character(ch.id)
	_reload_list()
	if chars.is_empty():
		_new_char()
	else:
		list_box.select(0)
		_on_pick(0)

func _add_premades() -> void:
	for p in CharacterStore.premades():
		CharacterStore.save_character(p)
	_reload_list()

func _save() -> void:
	_backup_before_save()
	CharacterStore.save_character(ch)
	_reload_list(ch.id)
	title_lbl.text = "%s — saved ✓" % ch.name

## Keep the saved version in the history before overwriting it with builder edits. Edits saved within
## a few minutes of each other share one backup, so the history isn't flooded.
func _backup_before_save() -> void:
	if str(ch.get("id", "")) == "":
		return
	var prev := CharacterStore.get_character(ch.id)
	if prev.is_empty():
		return
	var a := JSON.stringify(Progression.strip_history(prev), "", true)
	var b := JSON.stringify(Progression.strip_history(ch), "", true)
	if a == b:
		return
	var hist: Array = prev.get("history", [])
	var now := int(Time.get_unix_time_from_system())
	if not hist.is_empty() and str(hist[-1].get("label", "")) == "Before builder edits" and now - int(hist[-1].get("t", 0)) < 900:
		ch.history = hist
		return
	Progression.push_history(prev, "Before builder edits")
	ch.history = prev.history

## Guided level-up from the builder (no DM cap here: the builder is for your own characters).
func _open_level_up() -> LevelUpWizard:
	if ch.is_empty():
		return null
	if Rules.total_level(ch) >= 20:
		title_lbl.text = "%s is already level 20." % ch.get("name", "")
		return null
	for n in get_children():
		if n is LevelUpWizard:
			n.close()
	var w := LevelUpWizard.new(ch)
	w.finished.connect(func(new_sheet, label):
		var old := ch.duplicate(true)
		_backup_before_save()  # unsaved builder edits are kept as their own backup first
		old.history = ch.get("history", [])
		Progression.push_history(old, label)
		var nxt: Dictionary = new_sheet.duplicate(true)
		nxt.history = old.history
		ch = nxt
		CharacterStore.save_character(ch)
		_reload_list(ch.id)
		_rebuild()
		title_lbl.text = "%s — now level %d ✓ (backup in History)" % [ch.name, Rules.total_level(ch)])
	add_child(w)
	return w

func _restore(index: int) -> void:
	var hist: Array = ch.get("history", [])
	if index < 0 or index >= hist.size():
		return
	var entry: Dictionary = hist[index]
	var dlg = ConfirmationDialog.new()
	dlg.title = "Restore an earlier sheet?"
	dlg.dialog_text = "Restore \"%s\" (level %d: %s)?\nThe current sheet is backed up first, so you can undo this." % [entry.get("label", "backup"), int(entry.get("level", 0)), entry.get("summary", "")]
	dlg.dialog_autowrap = true
	dlg.min_size = Vector2i(460, 0)
	dlg.confirmed.connect(func():
		ch = Progression.restore(ch, index)
		_ensure_fields()
		CharacterStore.save_character(ch)
		_reload_list(ch.id)
		_rebuild()
		title_lbl.text = "%s — restored ✓" % ch.name
		dlg.queue_free())
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()

func _ensure_fields() -> void:
	var base = Rules.new_character()
	for k in base:
		if not ch.has(k):
			ch[k] = base[k]

# ================================================================ build tabs

func _rebuild() -> void:
	var cur = tabs.current_tab
	UIKit.clear(tabs)
	title_lbl.text = str(ch.get("name", ""))
	_tab_basics()
	_tab_classes()
	_tab_abilities()
	_tab_skills()
	_tab_equipment()
	_tab_spells()
	_tab_plan()
	_tab_history()
	tabs.current_tab = clampi(cur, 0, tabs.get_tab_count() - 1)
	_refresh_sheet()

func _page(name: String) -> VBoxContainer:
	var v = UIKit.vbox(10)
	var sc = UIKit.scroll(UIKit.margin(v, 10))
	sc.name = name
	tabs.add_child(sc)
	return v

func _row(parent: Control, label: String, ctrl: Control, w := 170) -> Control:
	var h = UIKit.hbox(10)
	var l = UIKit.lbl(label, 15, UIKit.MUTED)
	l.custom_minimum_size = Vector2(w, 0)
	h.add_child(l)
	UIKit.expand(ctrl)
	h.add_child(ctrl)
	parent.add_child(h)
	return ctrl

func _changed(rebuild := false) -> void:
	dirty = true
	title_lbl.text = "%s *" % ch.get("name", "")
	if rebuild:
		_rebuild()
	else:
		_refresh_sheet()

# ---------------------------------------------------------------- basics

func _tab_basics() -> void:
	var v = _page("Basics")
	var top = UIKit.hbox(20)
	v.add_child(top)
	# Portrait.
	var pv = UIKit.vbox(6)
	var frame = UIKit.panel(null, Color("#0d0b12"))
	frame.custom_minimum_size = Vector2(180, 180)
	var tr = TextureRect.new()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture = CharacterStore.portrait_texture(ch.get("portrait", ""))
	frame.add_child(tr)
	if tr.texture == null:
		var ini = UIKit.lbl(UIKit.initials(str(ch.name)), 54, Color(ch.get("color", "#7a5cff")))
		ini.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ini.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		frame.add_child(ini)
	pv.add_child(frame)
	pv.add_child(UIKit.btn("📁 Upload your own image…", func(): file_dialog.popup_centered_ratio(0.6), "PNG, JPG, WEBP, BMP or SVG. It's cropped to a square and used as your token."))
	pv.add_child(UIKit.lbl("…or pick an icon:", 13, UIKit.MUTED))
	pv.add_child(_portrait_gallery())
	if ch.get("portrait", "") != "":
		pv.add_child(UIKit.btn("Remove portrait", func(): ch.portrait = ""; ch.portrait_template = ""; _changed(true)))
	var cp = ColorPickerButton.new()
	cp.color = Color(ch.get("color", "#7a5cff"))
	cp.custom_minimum_size = Vector2(0, 30)
	cp.tooltip_text = "Token colour. Template icons are redrawn in this colour."
	cp.color_changed.connect(func(col): ch.color = "#" + col.to_html(false); _changed())
	# Redraw a template portrait (and the gallery) once the colour is chosen.
	cp.popup_closed.connect(func():
		var icon := str(ch.get("portrait_template", ""))
		if icon != "":
			_set_template(icon)
		else:
			_rebuild())
	pv.add_child(UIKit.lbl("Token colour", 13, UIKit.MUTED))
	pv.add_child(cp)
	top.add_child(pv)
	var form = UIKit.vbox(8)
	UIKit.expand(form)
	top.add_child(form)
	_row(form, "Character name", UIKit.line(str(ch.name), "Name", func(t): ch.name = t; title_lbl.text = t + " *"; _refresh_sheet()))
	_row(form, "Player", UIKit.line(str(ch.get("player", "")), "Player name", func(t): ch.player = t))
	var races: Array = []
	for r in Data.races.values():
		races.append([r.id, "%s  (%s)" % [r.name, r.get("source", "")]])
	races.sort_custom(func(a, b): return a[1] < b[1])
	_row(form, "Race", UIKit.option(races, ch.race, func(id): ch.race = id; ch.subrace = ""; ch.race_asi_choice = []; _default_subrace(); _changed(true)))
	var race = Data.race(ch.race)
	if race.has("subraces"):
		if ch.subrace == "":
			_default_subrace()
		var subs: Array = []
		for s in race.subraces:
			subs.append([s.id, s.name])
		_row(form, "Subrace / Ancestry", UIKit.option(subs, ch.subrace, func(id): ch.subrace = id; _changed(true)))
	var choice: Dictionary = race.get("asi_choice", {})
	if not choice.is_empty():
		var n = int(choice.count)
		while ch.race_asi_choice.size() < n:
			for a in Data.ABILITIES:
				if not a in ch.race_asi_choice and not a in choice.get("exclude", []):
					ch.race_asi_choice.append(a)
					break
		var hb = UIKit.hbox()
		for i in n:
			var idx = i
			var items: Array = []
			for a in Data.ABILITIES:
				if not a in choice.get("exclude", []):
					items.append([a, a.to_upper()])
			hb.add_child(UIKit.option(items, ch.race_asi_choice[i], func(id): ch.race_asi_choice[idx] = id; _changed()))
		_row(form, "+%d ability choices" % int(choice.amount), hb)
	if race.get("feat", false):
		_row(form, "Racial feat", _feat_picker(ch.feats[0] if ch.feats.size() > 0 else "", func(id):
			ch.feats = [id] if id != "" else []
			_changed(true)))
		if ch.feats.size() > 0:
			_feat_ability_picker(form, ch.feats[0])
	var bgs: Array = []
	for b in Data.BACKGROUNDS:
		bgs.append([b, "%s  (%s)" % [Data.pretty(b), ", ".join(Data.BACKGROUNDS[b].map(func(s): return Data.pretty(s)))]])
	_row(form, "Background", UIKit.option(bgs, ch.background, func(id): ch.background = id; _changed(true)))
	_row(form, "Alignment", UIKit.line(str(ch.get("alignment", "")), "e.g. Neutral Good", func(t): ch.alignment = t))
	var notes = TextEdit.new()
	notes.text = str(ch.get("notes", ""))
	notes.custom_minimum_size = Vector2(0, 120)
	notes.text_changed.connect(func(): ch.notes = notes.text)
	v.add_child(UIKit.lbl("Notes", 15, UIKit.MUTED))
	v.add_child(notes)
	var traits = ""
	for t in race.get("traits", []) + Data.subrace(ch.race, ch.subrace).get("traits", []):
		traits += "[b]%s.[/b] %s\n" % [t.name, t.desc]
	v.add_child(UIKit.rich("[color=#c9a14a]Racial traits[/color]\n" + traits))

func _default_subrace() -> void:
	var race = Data.race(ch.race)
	if race.has("subraces") and race.subraces.size() > 0:
		ch.subrace = race.subraces[0].id

func _feat_picker(selected: String, cb: Callable) -> OptionButton:
	var items: Array = [["", "— choose a feat —"]]
	var fl = Data.feats.values()
	fl.sort_custom(func(a, b): return a.name < b.name)
	for f in fl:
		items.append([f.id, f.name + ("  ⚙" if f.get("auto", false) else "")])
	var o = UIKit.option(items, selected, cb)
	o.tooltip_text = Data.feat(selected).get("desc", "Feats marked ⚙ are automated in combat.")
	return o

func _feat_ability_picker(parent: Control, fid: String) -> void:
	var abil: Array = Data.feat(fid).get("ability", [])
	if abil.size() > 1:
		var items: Array = []
		for a in abil:
			items.append([a, "+1 " + a.to_upper()])
		_row(parent, "   %s bonus" % Data.feat(fid).name, UIKit.option(items, ch.feat_choices.get(fid, abil[0]), func(id): ch.feat_choices[fid] = id; _changed()))

func _on_portrait_file(path: String) -> void:
	var key = CharacterStore.import_portrait(path)
	if key == "":
		title_lbl.text = "Couldn't read that image."
		return
	ch.portrait = key
	ch.portrait_template = ""
	_changed(true)

## Grid of template icons drawn in the token colour; the class's suggested icon is outlined.
func _portrait_gallery() -> Control:
	var cur := str(ch.get("portrait_template", "")) if ch.get("portrait", "") != "" else ""
	return PortraitTemplates.gallery(Color(ch.get("color", "#7a5cff")), cur, PortraitTemplates.suggested(ch), _set_template)

func _set_template(icon: String) -> void:
	var key := PortraitTemplates.make_portrait(icon, Color(ch.get("color", "#7a5cff")))
	if key == "":
		title_lbl.text = "Couldn't draw that icon."
		return
	ch.portrait = key
	ch.portrait_template = icon
	_changed(true)

# ---------------------------------------------------------------- classes

func _tab_classes() -> void:
	var v = _page("Classes & Feats")
	v.add_child(_wl("Your first class sets saving throws and full armor proficiencies. Add more classes to multiclass, or use ⬆ Level Up for a guided level with every choice explained.", 13, UIKit.MUTED))
	var classes: Array = []
	for c in Data.classes.values():
		classes.append([c.id, "%s  (%s)" % [c.name, c.source]])
	classes.sort_custom(func(a, b): return a[1] < b[1])
	for i in ch.classes.size():
		var idx = i
		var entry: Dictionary = ch.classes[i]
		var cd = Data.cls(entry.id)
		var row = UIKit.hbox(8)
		row.add_child(UIKit.option(classes, entry.id, func(id):
			ch.classes[idx] = {"id": id, "level": entry.level, "subclass": ""}
			if idx == 0:
				_apply_class_defaults(id)
			_changed(true)))
		row.add_child(UIKit.lbl("Level", 14, UIKit.MUTED))
		var sp = UIKit.spin(1, 20, entry.level, func(val):
			ch.classes[idx].level = int(val)
			_changed(true))
		row.add_child(sp)
		var subs: Array = [["", "— %s (level %d) —" % [cd.get("subclass_label", "Subclass"), int(cd.get("subclass_level", 3))]]]
		for s in cd.get("subclasses", []):
			subs.append([s.id, "%s  (%s)" % [s.name, s.get("source", cd.source)]])
		var so = UIKit.option(subs, entry.get("subclass", ""), func(id): ch.classes[idx].subclass = id; _changed(true))
		so.disabled = int(entry.level) < int(cd.get("subclass_level", 3))
		UIKit.expand(so)
		row.add_child(so)
		if ch.classes.size() > 1:
			row.add_child(UIKit.btn("✕", func(): ch.classes.remove_at(idx); _changed(true), "Remove this class"))
		v.add_child(row)
	var total = Rules.total_level(ch)
	var add = UIKit.btn("+ Add a class (multiclass)", func():
		if Rules.total_level(ch) < 20:
			ch.classes.append({"id": "wizard" if ch.classes[0].id != "wizard" else "fighter", "level": 1, "subclass": ""})
			_changed(true))
	add.disabled = total >= 20
	v.add_child(add)
	v.add_child(UIKit.lbl("Total level %d   •   Proficiency bonus +%d" % [total, Rules.prof_bonus(total)], 16, UIKit.GOLD))
	if total > 20:
		v.add_child(UIKit.lbl("Total level can't exceed 20.", 14, UIKit.BAD))
	# Hit points rolled at level-ups (otherwise each level after the first takes the average).
	var rolls: Dictionary = ch.get("hp_rolls", {})
	var rolled: PackedStringArray = []
	for c in ch.classes:
		var got: Array = rolls.get(c.id, [])
		if not got.is_empty():
			rolled.append("%s %s" % [Data.cls(c.id).name, ", ".join(got.map(func(x): return str(int(x))))])
	var hpr = UIKit.hbox(8)
	hpr.add_child(_wl("Hit points per level: " + ("; ".join(rolled) + "  (levels without a roll use the average)" if not rolled.is_empty() else "maximum at 1st level, then the average (rolls made in Level Up are kept here)"), 13, UIKit.MUTED))
	if not rolled.is_empty():
		hpr.add_child(UIKit.btn("Use averages", func(): ch.hp_rolls = {}; _changed(true), "Forget the rolled hit points and use the fixed average for every level"))
	v.add_child(hpr)
	# ASIs / feats, paired with their slots by class and level (not by position).
	Progression.sort_asi(ch)
	var slots = Rules.asi_slots(ch)
	if not slots.is_empty():
		v.add_child(UIKit.header("Ability Score Improvements", 18))
		var asi: Array = ch.asi
		for i in slots.size():
			var sl: Dictionary = slots[i]
			if i >= asi.size():
				asi.append({"class": sl.class, "level": sl.level, "type": "asi", "a": "str", "b": "str"})
			var a: Dictionary = asi[i]
			var idx = i
			var row = UIKit.hbox(8)
			var l = UIKit.lbl("%s %d" % [Data.cls(sl.class).name, sl.level], 14, UIKit.MUTED)
			l.custom_minimum_size = Vector2(130, 0)
			row.add_child(l)
			row.add_child(UIKit.option([["asi", "+2 / +1+1"], ["feat", "Feat"]], a.get("type", "asi"), func(id): asi[idx].type = id; _changed(true)))
			if a.get("type", "asi") == "asi":
				var ab: Array = []
				for x in Data.ABILITIES:
					ab.append([x, "+1 " + x.to_upper()])
				row.add_child(UIKit.option(ab, a.get("a", "str"), func(id): asi[idx].a = id; _changed()))
				row.add_child(UIKit.option(ab, a.get("b", "str"), func(id): asi[idx].b = id; _changed()))
			else:
				row.add_child(UIKit.expand(_feat_picker(a.get("feat", ""), func(id): asi[idx].feat = id; _changed(true))))
			v.add_child(row)
			if a.get("type", "") == "feat" and a.get("feat", "") != "":
				_feat_ability_picker(v, a.feat)
		while asi.size() > slots.size():
			asi.pop_back()
	# Class options.
	var st = Rules.derive(ch)
	var f: Dictionary = st.features
	if f.has("fighting_style") or f.has("additional_fighting_style") or "fighting_initiate" in st.feats:
		var n = 1 + (1 if f.has("additional_fighting_style") else 0) + (1 if "fighting_initiate" in st.feats else 0)
		_multi_pick(v, "Fighting Styles (pick %d)" % n, Data.FIGHTING_STYLES, "fighting_styles", n)
	if f.has("combat_superiority"):
		var fl: int = st.class_levels.get("fighter", 3)
		_multi_pick(v, "Maneuvers (pick %d)" % (3 if fl < 7 else (5 if fl < 10 else (7 if fl < 15 else 9))), Data.MANEUVERS, "maneuvers", 9)
	if f.has("metamagic"):
		var sl2: int = st.class_levels.get("sorcerer", 3)
		_multi_pick(v, "Metamagic (pick %d)" % (2 if sl2 < 10 else (3 if sl2 < 17 else 4)), Data.METAMAGIC, "metamagic", 4)
	if f.has("eldritch_invocations"):
		_multi_pick(v, "Eldritch Invocations", Data.INVOCATIONS, "invocations", 8)
	if f.has("infuse_item"):
		_multi_pick(v, "Infusions (active)", Data.INFUSIONS, "infusions", 6)
	if f.has("dragon_ancestor") or f.has("draconic_resilience"):
		var types: Array = []
		for t in ["acid", "cold", "fire", "lightning", "poison"]:
			types.append([t, t.capitalize()])
		_row(v, "Draconic ancestry", UIKit.option(types, ch.choices.get("dragon_ancestor", "fire"), func(id): ch.choices.dragon_ancestor = id; _changed()))
	if f.has("armor_model"):
		_row(v, "Armor model", UIKit.option([["guardian", "Guardian (Thunder Gauntlets)"], ["infiltrator", "Infiltrator (Lightning Launcher)"]], ch.choices.get("armor_model", "guardian"), func(id): ch.choices.armor_model = id; _changed()))
	if "elemental_adept" in st.feats:
		var t2: Array = []
		for t in ["acid", "cold", "fire", "lightning", "thunder"]:
			t2.append([t, t.capitalize()])
		_row(v, "Elemental Adept type", UIKit.option(t2, ch.choices.get("elemental_adept", "fire"), func(id): ch.choices.elemental_adept = id; _changed()))
	# Features list.
	v.add_child(UIKit.header("Features", 18))
	var txt = ""
	for fi in st.feature_info:
		txt += "[b]%s[/b] [color=#8a7fa0](%s)[/color]%s\n%s\n\n" % [fi.name, fi.src, "  [color=#5cc892]⚙ automated[/color]" if fi.auto else "", fi.desc]
	v.add_child(UIKit.rich(txt))

func _multi_pick(parent: Control, title: String, options: Dictionary, key: String, limit: int) -> void:
	parent.add_child(UIKit.lbl(title, 16, UIKit.GOLD))
	var grid = GridContainer.new()
	grid.columns = 2
	for id in options:
		var oid: String = id
		var cb = UIKit.check(Data.pretty(oid), oid in ch[key], func(p):
			var arr: Array = ch[key]
			if p and not oid in arr:
				arr.append(oid)
			elif not p:
				arr.erase(oid)
			_changed())
		cb.tooltip_text = options[id]
		grid.add_child(cb)
	parent.add_child(grid)

func _apply_class_defaults(class_id: String) -> void:
	var cd = Data.cls(class_id)
	var eq: Dictionary = cd.get("default_equipment", {})
	ch.equipment = {"armor": eq.get("armor", ""), "shield": eq.get("shield", false), "weapons": eq.get("weapons", []).duplicate(), "weapon_bonus": 0, "armor_bonus": 0}

# ---------------------------------------------------------------- abilities

func _tab_abilities() -> void:
	var v = _page("Abilities")
	var methods = [["point_buy", "Point buy (27)"], ["standard", "Standard array"], ["manual", "Manual / rolled"]]
	_row(v, "Method", UIKit.option(methods, ch.get("score_method", "manual"), func(id):
		ch.score_method = id
		if id == "point_buy":
			for a in Data.ABILITIES: ch.base_scores[a] = 8
		elif id == "standard":
			var arr = Data.STANDARD_ARRAY.duplicate()
			var i = 0
			for a in Data.ABILITIES:
				ch.base_scores[a] = arr[i]
				i += 1
		_changed(true)))
	var final = Rules.final_scores(ch)
	var grid = GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 18)
	for h in ["Ability", "Base", "Bonuses", "Score", "Modifier"]:
		grid.add_child(UIKit.lbl(h, 14, UIKit.MUTED))
	var method: String = ch.get("score_method", "manual")
	for a in Data.ABILITIES:
		var ab: String = a
		grid.add_child(UIKit.lbl(Data.ABILITY_NAMES[a], 16))
		if method == "standard":
			var items: Array = []
			for val in [15, 14, 13, 12, 10, 8]:
				items.append([val, str(val)])
			grid.add_child(UIKit.option(items, int(ch.base_scores[a]), func(val):
				# Swap with whichever ability had this value.
				for other in Data.ABILITIES:
					if other != ab and int(ch.base_scores[other]) == int(val):
						ch.base_scores[other] = ch.base_scores[ab]
				ch.base_scores[ab] = val
				_changed(true)))
		else:
			var mn = 8 if method == "point_buy" else 1
			var mx = 15 if method == "point_buy" else 20
			grid.add_child(UIKit.spin(mn, mx, int(ch.base_scores[a]), func(val): ch.base_scores[ab] = int(val); _changed(true)))
		var bonus: int = int(final[a]) - int(ch.base_scores[a])
		grid.add_child(UIKit.lbl(Rules.fmt_mod(bonus) if bonus != 0 else "—", 16, UIKit.GOOD if bonus > 0 else UIKit.MUTED))
		grid.add_child(UIKit.lbl(str(final[a]), 20, UIKit.GOLD))
		grid.add_child(UIKit.lbl(Rules.fmt_mod(Rules.mod(int(final[a]))), 18))
	v.add_child(grid)
	if method == "point_buy":
		var spent = 0
		for a in Data.ABILITIES:
			spent += int(Data.POINT_BUY_COST.get(int(ch.base_scores[a]), 0))
		v.add_child(UIKit.lbl("Points spent: %d / 27" % spent, 16, UIKit.BAD if spent > 27 else UIKit.GOOD))

# ---------------------------------------------------------------- skills

func _tab_skills() -> void:
	var v = _page("Skills")
	var cd = Data.cls(ch.classes[0].id)
	var allowed: Array = cd.get("skill_list", [])
	var bg_sk: Array = Data.BACKGROUNDS.get(ch.background, [])
	var race_sk: Array = Data.race(ch.race).get("skills", [])
	var n = int(cd.get("skill_count", 2)) + int(Data.race(ch.race).get("skill_choices", 0))
	v.add_child(_wl("Choose %d skills (%s class list%s). Background and racial skills are automatic." % [n, cd.name, " + race" if Data.race(ch.race).get("skill_choices", 0) else ""], 14, UIKit.MUTED))
	var st = Rules.derive(ch)
	var grid = GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 16)
	for h in ["Skill", "Proficient", "Expertise", "Bonus"]:
		grid.add_child(UIKit.lbl(h, 13, UIKit.MUTED))
	for s in Data.SKILLS:
		var sk: String = s
		var auto: bool = sk in bg_sk or sk in race_sk
		var on_list: bool = "*" in allowed or sk in allowed
		grid.add_child(UIKit.lbl("%s (%s)%s" % [Data.pretty(sk), Data.SKILLS[sk].to_upper(), "  •" if on_list else ""], 15, UIKit.INK if on_list else UIKit.MUTED))
		var pc = UIKit.check("auto" if auto else "", auto or sk in ch.skills, func(p):
			if p and not sk in ch.skills: ch.skills.append(sk)
			elif not p: ch.skills.erase(sk)
			_changed(true))
		pc.disabled = auto
		grid.add_child(pc)
		grid.add_child(UIKit.check("", sk in ch.expertise, func(p):
			if p and not sk in ch.expertise: ch.expertise.append(sk)
			elif not p: ch.expertise.erase(sk)
			_changed(true)))
		grid.add_child(UIKit.lbl(Rules.fmt_mod(int(st.skills[sk])), 16, UIKit.GOLD))
	v.add_child(grid)
	v.add_child(_wl("Chosen: %d / %d   (• = on your class list; Expertise comes from Rogue, Bard and some feats)" % [ch.skills.size(), n], 14, UIKit.MUTED))

# ---------------------------------------------------------------- equipment

func _tab_equipment() -> void:
	var v = _page("Equipment")
	var eq: Dictionary = ch.equipment
	var st = Rules.derive(ch)
	var armors: Array = [["", "No armor"]]
	for a in Data.armors():
		var ok: bool = a.category in st.armor_prof
		armors.append([a.id, "%s (%s, AC %d%s)%s" % [a.name, a.category, a.base, "" if a.dex_max == 0 else (" + DEX" if a.dex_max > 5 else " + DEX max 2"), "" if ok else "  ⚠ not proficient"]])
	_row(v, "Armor", UIKit.option(armors, eq.get("armor", ""), func(id): eq.armor = id; _changed(true)))
	v.add_child(UIKit.check("Shield (+2 AC)%s" % ("" if "shield" in st.armor_prof else "  ⚠ not proficient"), eq.get("shield", false), func(p): eq.shield = p; _changed(true)))
	if st.get("armor_unproficient", false):
		v.add_child(_wl("⚠ Without proficiency in this armor or shield you can't cast spells, and you have disadvantage on attack rolls and saves that use Strength or Dexterity.", 13, Color(1.0, 0.7, 0.4)))
	_row(v, "Magic armor bonus", UIKit.spin(0, 3, int(eq.get("armor_bonus", 0)), func(val): eq.armor_bonus = int(val); _changed()))
	_row(v, "Magic weapon bonus", UIKit.spin(0, 3, int(eq.get("weapon_bonus", 0)), func(val): eq.weapon_bonus = int(val); _changed()))
	v.add_child(UIKit.header("Weapons", 18))
	var weapons: Array = eq.weapons
	for i in weapons.size():
		var idx = i
		var w = Data.item(weapons[i])
		var row = UIKit.hbox()
		var ok = Rules.is_proficient_weapon(w, st.weapon_prof) if not w.is_empty() else false
		row.add_child(UIKit.expand(UIKit.lbl("%s — %s %s%s%s" % [w.get("name", weapons[i]), w.get("damage", ""), w.get("type", ""), ("  [" + ", ".join(w.get("props", [])) + "]") if w.get("props", []).size() > 0 else "", "" if ok else "  ⚠ not proficient"], 15)))
		row.add_child(UIKit.btn("✕", func(): weapons.remove_at(idx); _changed(true)))
		v.add_child(row)
	var all_w: Array = []
	for w in Data.weapons():
		all_w.append([w.id, "%s (%s %s, %s)" % [w.name, w.damage, w.type, w.category]])
	all_w.sort_custom(func(a, b): return a[1] < b[1])
	var pick = [all_w[0][0]]
	var addrow = UIKit.hbox()
	addrow.add_child(UIKit.expand(UIKit.option(all_w, pick[0], func(id): pick[0] = id)))
	addrow.add_child(UIKit.btn("Add weapon", func(): weapons.append(pick[0]); _changed(true)))
	v.add_child(addrow)
	v.add_child(UIKit.btn("Reset to class starting equipment", func(): _apply_class_defaults(ch.classes[0].id); _changed(true)))
	v.add_child(UIKit.lbl("Tip: two light melee weapons enable an off-hand bonus attack.", 13, UIKit.MUTED))

# ---------------------------------------------------------------- spells

func _tab_spells() -> void:
	var st = Rules.derive(ch)
	if st.casting.is_empty() and Data.subrace(ch.race, ch.subrace).get("bonus_cantrip", "") == "":
		var v0 = _page("Spells")
		v0.add_child(UIKit.lbl("This character has no spellcasting.", 15, UIKit.MUTED))
		return
	var v = _page("Spells")
	var search = UIKit.line(spell_filter, "Filter spells by name or text…")
	v.add_child(search)
	var boxes: Array = []
	for c in ch.classes:
		var t = Rules.caster_type(c)
		if t == "":
			continue
		var counts = Rules.spell_counts(ch, c, st.scores)
		var list_id = Rules.spell_list_id(c)
		var max_lv = Rules.max_spell_level_for(c)
		var chosen: Array = ch.spells.get(c.id, [])
		ch.spells[c.id] = chosen
		var bonus: Array = []
		for e in st.casting:
			if e["class"] == c.id:
				bonus = e.bonus_spells
		# Wizards keep a spellbook and prepare their leveled spells from it ("Book" column).
		var wiz: bool = c.id == "wizard"
		if wiz and not ch.has("spellbook"):
			ch.spellbook = Rules.wizard_spellbook(ch)
		var book_col: int = 1 if wiz else -1
		var lvl_col: int = 2 if wiz else 1
		var sum_col: int = 3 if wiz else 2
		var cname: String = Data.cls(c.id).name
		var wiz_level: int = int(c.level)
		var head_text = func() -> String:
			var arr: Array = ch.spells[c.id]
			var nc: int = arr.filter(func(x): return int(Data.spell(x).get("level", 0)) == 0).size()
			var txt: String = "%s spells — cantrips %d/%d, %s %d/%d" % [cname, nc, counts.cantrips, "known" if counts.prepare == "known" and not wiz else "prepared", arr.size() - nc, counts.spells]
			if wiz:
				txt += ", spellbook %d (%d free from wizard levels)" % [(ch.spellbook as Array).size(), Rules.spellbook_free_spells(wiz_level)]
			return txt + " (max level %d)" % max_lv
		var head = _wl(head_text.call(), 16, UIKit.GOLD)
		v.add_child(head)
		if wiz:
			v.add_child(_wl("Tick Book for every spell written in your spellbook, and the first box for the ones you have prepared today. Only spells in the book can be prepared.", 13, UIKit.MUTED))
		if not bonus.is_empty():
			v.add_child(_wl("Always prepared: " + ", ".join(bonus.map(func(x): return Data.spell(x).get("name", x))), 13, UIKit.GOOD))
		var tree = Tree.new()
		tree.columns = 4 if wiz else 3
		tree.hide_root = true
		tree.column_titles_visible = true
		tree.set_column_title(0, "Prepared" if wiz else "Spell")
		if wiz:
			tree.set_column_title(book_col, "Book")
			tree.set_column_expand(book_col, false)
			tree.set_column_custom_minimum_width(book_col, 60)
		tree.set_column_title(lvl_col, "Lvl")
		tree.set_column_title(sum_col, "Summary")
		tree.set_column_expand(lvl_col, false)
		tree.set_column_custom_minimum_width(lvl_col, 40)
		tree.set_column_custom_minimum_width(0, 220)
		tree.set_column_expand(0, false)
		tree.custom_minimum_size = Vector2(0, 520)
		tree.set_meta("sum_col", sum_col)
		var root = tree.create_item()
		var pool: Array = Data.spells_for_class(list_id, max_lv)
		if Data.subclass(c.id, str(c.get("subclass", ""))).get("spell_list_extra", "") != "":
			for s in Data.spells_for_class(Data.subclass(c.id, c.subclass).spell_list_extra, max_lv):
				if not s in pool:
					pool.append(s)
		for s in pool:
			var it = tree.create_item(root)
			it.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
			it.set_editable(0, true)
			it.set_text(0, s.name + ("" if s.get("combat", null) != null else " ·"))
			it.set_checked(0, s.id in chosen)
			if wiz and int(s.level) > 0:
				it.set_cell_mode(book_col, TreeItem.CELL_MODE_CHECK)
				it.set_editable(book_col, true)
				it.set_checked(book_col, s.id in ch.spellbook)
			it.set_text(lvl_col, "C" if int(s.level) == 0 else str(s.level))
			it.set_text(sum_col, str(s.get("summary", "")))
			it.set_tooltip_text(sum_col, str(s.get("summary", "")))
			it.set_metadata(0, s.id)
			if s.id in bonus:
				it.set_custom_color(0, UIKit.GOOD)
		var cid: String = c.id
		tree.item_edited.connect(func():
			var it: TreeItem = tree.get_edited()
			var col: int = tree.get_edited_column()
			var sid: String = it.get_metadata(0)
			var arr: Array = ch.spells[cid]
			var leveled: bool = int(Data.spell(sid).get("level", 0)) > 0
			if col == book_col and book_col >= 0:
				var bk: Array = ch.spellbook
				if it.is_checked(book_col):
					if not sid in bk:
						bk.append(sid)
				else:
					# Taken out of the book, it can't stay prepared.
					bk.erase(sid)
					arr.erase(sid)
					it.set_checked(0, false)
			elif it.is_checked(0):
				if not sid in arr:
					arr.append(sid)
				# Preparing a spell that isn't in the book writes it in.
				if wiz and leveled and not sid in ch.spellbook:
					(ch.spellbook as Array).append(sid)
					it.set_checked(book_col, true)
			else:
				arr.erase(sid)
			head.text = head_text.call()
			_refresh_sheet())
		boxes.append(tree)
		v.add_child(tree)
	var sr = Data.subrace(ch.race, ch.subrace)
	if sr.get("bonus_cantrip", "") != "":
		var arr: Array = ch.spells.get("race", [])
		ch.spells["race"] = arr
		var items: Array = [["", "— choose —"]]
		for s in Data.spells_for_class(sr.bonus_cantrip, 0):
			items.append([s.id, s.name])
		_row(v, "%s cantrip" % sr.name, UIKit.option(items, arr[0] if arr.size() > 0 else "", func(id): ch.spells["race"] = [id] if id != "" else []; _changed()))
	v.add_child(_wl("Spells marked · have no combat automation (the DM adjudicates them).", 13, UIKit.MUTED))
	search.text_changed.connect(func(t):
		spell_filter = t.to_lower()
		for tree in boxes:
			var it: TreeItem = tree.get_root().get_first_child()
			while it:
				it.visible = spell_filter == "" or spell_filter in it.get_text(0).to_lower() or spell_filter in it.get_text(int(tree.get_meta("sum_col", 2))).to_lower()
				it = it.get_next())

# ---------------------------------------------------------------- level plan & history

## A label that wraps in its column.
func _wl(text: String, fsize := 14, color := UIKit.INK) -> Label:
	var l = UIKit.lbl(text, fsize, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(80, 0)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l

func _tab_plan() -> void:
	var v = _page("Level Plan")
	var plan := LevelPlanView.new(ch, true)
	plan.changed.connect(func(_p): dirty = true; title_lbl.text = "%s *" % ch.get("name", ""))
	v.add_child(plan)

func _tab_history() -> void:
	var v = _page("History")
	v.add_child(_wl("A backup is saved before every level-up and restore, and when you save changes in the builder (edits within 15 minutes share one backup). Restoring makes that version current; the version you replace is backed up too. XP and levels granted by a DM are kept.", 13, UIKit.MUTED))
	var hist: Array = ch.get("history", [])
	if hist.is_empty():
		v.add_child(UIKit.lbl("No backups yet.", 14, UIKit.MUTED))
		return
	for i in range(hist.size() - 1, -1, -1):
		var h: Dictionary = hist[i]
		var row = UIKit.hbox(10)
		var info = UIKit.vbox(2)
		UIKit.expand(info)
		info.add_child(UIKit.lbl(str(h.get("label", "Backup")), 15, UIKit.INK))
		var when := Time.get_datetime_string_from_unix_time(int(h.get("t", 0)) + CharacterSheet._tz_offset(), true)
		info.add_child(_wl("%s   ·   level %d: %s" % [when, int(h.get("level", 0)), str(h.get("summary", ""))], 12, UIKit.MUTED))
		var diffs := Progression.diff_lines(h.get("data", {}), ch)
		if not diffs.is_empty():
			info.add_child(_wl("Differs from now: " + "; ".join(diffs.slice(0, 4)) + (" …" if diffs.size() > 4 else ""), 12, Color("#c8b48a")))
		row.add_child(info)
		var idx := i
		var rb = UIKit.btn("Restore", func(): _restore(idx), "Make this version the current sheet (the current one is backed up first)")
		rb.custom_minimum_size = Vector2(96, 34)
		row.add_child(rb)
		v.add_child(row)
		v.add_child(HSeparator.new())

# ================================================================ sheet

func _refresh_sheet() -> void:
	if ch.is_empty():
		return
	var st = Rules.derive(ch)
	var t = "[font_size=22][color=#c9a14a]%s[/color][/font_size]\n" % ch.get("name", "")
	t += "[color=#a59cb5]%s %s • %s[/color]\n\n" % [CombatantFactory._race_name(ch), Rules.class_summary(ch), Data.pretty(ch.get("background", ""))]
	t += "[b]HP[/b] %d   [b]AC[/b] %d [color=#8a7fa0](%s)[/color]   [b]Speed[/b] %d ft   [b]Init[/b] %s   [b]PB[/b] +%d\n" % [st.max_hp, st.ac, st.ac_note, st.speed, Rules.fmt_mod(st.initiative), st.prof]
	t += "[b]Passive Perception[/b] %d%s\n\n" % [st.passive_perception, ("   [b]Darkvision[/b] %d ft" % st.darkvision) if st.darkvision > 0 else ""]
	t += "[table=6]"
	for a in Data.ABILITIES:
		t += "[cell][center][color=#a59cb5]%s[/color][/center][/cell]" % a.to_upper()
	for a in Data.ABILITIES:
		t += "[cell][center][b]%d[/b] (%s)[/center][/cell]" % [st.scores[a], Rules.fmt_mod(st.mods[a])]
	t += "[/table]\n"
	var sv: PackedStringArray = []
	for a in Data.ABILITIES:
		sv.append("%s%s %s" % ["● " if a in st.saves else "", a.to_upper(), Rules.fmt_mod(st.save_bonus[a])])
	t += "[b]Saves[/b] " + "  ".join(sv) + "\n"
	var sk: PackedStringArray = []
	for s in st.skill_prof:
		sk.append("%s %s" % [Data.pretty(s), Rules.fmt_mod(st.skills[s])])
	t += "[b]Skills[/b] " + ", ".join(sk) + "\n\n"
	t += "[color=#c9a14a]Attacks[/color]\n"
	for w in st.weapons:
		var dmg: PackedStringArray = []
		for d in w.damage:
			dmg.append("%s %s" % [d.dice, d.type])
		t += "• %s: %s, %s\n" % [w.name, Rules.fmt_mod(w.to_hit), " + ".join(dmg)]
	if not st.casting.is_empty():
		t += "\n[color=#c9a14a]Spellcasting[/color]\n"
		for e in st.casting:
			t += "• %s (%s): DC %d, attack %s — %d spells%s\n" % [e.name, e.ability.to_upper(), e.dc, Rules.fmt_mod(e.attack), e.spells.size(), (" prepared, spellbook %d" % e.spellbook.size()) if e.has("spellbook") else ""]
		if not st.slots.is_empty():
			t += "Slots: %s\n" % "  ".join(PackedStringArray(range(st.slots.size()).map(func(i): return "L%d×%d" % [i + 1, st.slots[i]])))
		if st.pact.count > 0:
			t += "Pact slots: %d × level %d\n" % [st.pact.count, st.pact.level]
	if not st.resources.is_empty():
		t += "\n[color=#c9a14a]Resources[/color]\n"
		for k in st.resources:
			var r: Dictionary = st.resources[k]
			t += "• %s: %d (%s rest)\n" % [r.name, r.max, r.reset]
	sheet_rt.text = t

func _fit() -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size
