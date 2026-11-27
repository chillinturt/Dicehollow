class_name LevelPlanView
extends VBoxContainer
## The level plan: one row per character level (1-20) showing the class taken or planned, the class
## level it reaches, what that level unlocks, and a note. Levels already taken are fixed; future
## levels can be planned by the character's owner. Multiclass prerequisites are checked as you plan.

signal changed(plan: Array)

var ch: Dictionary
var editable := false
var grid: GridContainer
var summary: RichTextLabel
var fill_class := ""

func _init(character: Dictionary, can_edit := false) -> void:
	ch = character
	editable = can_edit
	add_theme_constant_override("separation", 8)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary = UIKit.rich("")
	add_child(summary)
	add_child(DialogPanel.wrap_lbl("Plan the class you'll take at each level and jot down choices you're aiming for (feats, subclass, spells). The level-up wizard suggests the planned class. Unlocks are what that class level grants in this ruleset.", 13))
	if editable:
		var tools = UIKit.hbox(6)
		tools.add_child(UIKit.lbl("Fill empty future levels with", 13, UIKit.MUTED))
		var items: Array = []
		for cid in _class_ids():
			items.append([cid, Data.cls(cid).name])
		fill_class = str(ch.classes[0].id) if ch.get("classes", []).size() > 0 else "fighter"
		var fo = UIKit.option(items, fill_class, func(id): fill_class = id)
		fo.fit_to_longest_item = false
		fo.custom_minimum_size = Vector2(130, 0)
		tools.add_child(fo)
		tools.add_child(UIKit.btn("Fill", _fill, "Put this class on every future level that has no class planned yet"))
		tools.add_child(UIKit.btn("Clear plan", _clear, "Remove every planned future class (notes are kept)"))
		add_child(tools)
	grid = GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 4)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(grid)
	_build()

func _class_ids() -> Array:
	var ids: Array = Data.classes.keys()
	ids.sort_custom(func(a, b): return str(Data.cls(a).name) < str(Data.cls(b).name))
	return ids

func _build() -> void:
	UIKit.clear(grid)
	for h in ["Lv", "Class", "Class lv", "Unlocks", "Note"]:
		grid.add_child(UIKit.lbl(h, 13, UIKit.MUTED))
	var rows := Progression.plan_rows(ch)
	var total := Rules.total_level(ch)
	var end_counts: Dictionary = {}
	var warns := 0
	for r in rows:
		var i: int = int(r.level) - 1
		var taken: bool = r.taken
		var col: Color = UIKit.GOLD if taken else (UIKit.INK if r["class"] != "" else UIKit.MUTED)
		var lv = UIKit.lbl(str(r.level), 14, col)
		lv.custom_minimum_size = Vector2(26, 0)
		grid.add_child(lv)
		if taken or not editable:
			var cname: String = Data.cls(str(r["class"])).get("name", "—") if r["class"] != "" else "—"
			var cl = UIKit.lbl(cname + ("  ✓" if taken else ""), 14, col)
			cl.custom_minimum_size = Vector2(130, 0)
			cl.tooltip_text = "Taken" if taken else "Planned"
			grid.add_child(cl)
		else:
			var items: Array = [["", "—"]]
			for cid in _class_ids():
				items.append([cid, Data.cls(cid).name])
			var idx := i
			var o = UIKit.option(items, str(r["class"]), func(id): _set_class(idx, id))
			o.fit_to_longest_item = false
			o.custom_minimum_size = Vector2(130, 0)
			grid.add_child(o)
		grid.add_child(UIKit.lbl(str(r.class_level) if int(r.class_level) > 0 else "", 14, col))
		var g: Array = r.gains
		var txt: String = ", ".join(g)
		if str(r.warn) != "":
			txt += ("\n" if txt != "" else "") + "⚠ " + str(r.warn)
			warns += 1
		var ul = UIKit.lbl(txt, 13, Color("#ff9c8f") if str(r.warn) != "" else (UIKit.INK if taken else UIKit.MUTED))
		ul.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ul.custom_minimum_size = Vector2(240, 0)
		ul.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(ul)
		if editable:
			var idx2 := i
			var ne = UIKit.line(str(r.note), "note", func(t): _set_note(idx2, t))
			ne.custom_minimum_size = Vector2(170, 0)
			ne.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.add_child(ne)
		else:
			var nl = UIKit.lbl(str(r.note), 13, UIKit.MUTED)
			nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			nl.custom_minimum_size = Vector2(150, 0)
			nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.add_child(nl)
		if r["class"] != "":
			end_counts[r["class"]] = int(r.class_level)
	var parts: PackedStringArray = []
	for cid in end_counts:
		parts.append("%s %d" % [Data.cls(cid).name, end_counts[cid]])
	var planned_to: int = 0
	for r in rows:
		if r["class"] != "":
			planned_to = int(r.level)
	var t := "[color=#c9a14a]Level %d now[/color]" % total
	if planned_to > total:
		t += "  ·  planned to level %d: [b]%s[/b]" % [planned_to, " / ".join(parts)]
	else:
		t += "  ·  [color=#a59cb5]no future levels planned yet[/color]"
	if warns > 0:
		t += "\n[color=#ff9c8f]⚠ %d planned level%s break multiclass prerequisites with your current scores.[/color]" % [warns, "" if warns == 1 else "s"]
	summary.text = t

func _saved() -> Array:
	var saved: Array = ch.get("level_plan", []).duplicate(true)
	while saved.size() < Progression.MAX_LEVEL:
		saved.append({"class": "", "note": ""})
	for i in saved.size():
		if not saved[i] is Dictionary:
			saved[i] = {"class": "", "note": ""}
	return saved

func _set_class(i: int, cid: String) -> void:
	var saved := _saved()
	saved[i]["class"] = cid
	ch.level_plan = saved
	_build()
	changed.emit(ch.level_plan)

func _set_note(i: int, t: String) -> void:
	var saved := _saved()
	saved[i]["note"] = t
	ch.level_plan = saved
	changed.emit(ch.level_plan)

func _fill() -> void:
	var saved := _saved()
	var total := Rules.total_level(ch)
	for i in range(total, Progression.MAX_LEVEL):
		if str(saved[i].get("class", "")) == "":
			saved[i]["class"] = fill_class
	ch.level_plan = saved
	_build()
	changed.emit(ch.level_plan)

func _clear() -> void:
	var saved := _saved()
	var total := Rules.total_level(ch)
	for i in range(total, Progression.MAX_LEVEL):
		saved[i]["class"] = ""
	ch.level_plan = saved
	_build()
	changed.emit(ch.level_plan)
