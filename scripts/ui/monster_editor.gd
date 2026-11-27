class_name MonsterEditor
extends PanelContainer
## DM tool: build or edit a custom monster. Saved under user://monsters and added to the bestiary.
## Starting from an existing monster copies its stats (and keeps its special abilities, which are not editable here).

signal saved(id: String)
signal deleted(id: String)
signal closed

const SIZES := ["tiny", "small", "medium", "large", "huge", "gargantuan"]
const CRS := [0, 0.125, 0.25, 0.5, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30]
const XP := {0: 10, 0.125: 25, 0.25: 50, 0.5: 100, 1: 200, 2: 450, 3: 700, 4: 1100, 5: 1800, 6: 2300, 7: 2900, 8: 3900, 9: 5000, 10: 5900,
	11: 7200, 12: 8400, 13: 10000, 14: 11500, 15: 13000, 16: 15000, 17: 18000, 18: 20000, 19: 22000, 20: 25000, 21: 33000, 22: 41000,
	23: 50000, 24: 62000, 25: 75000, 26: 90000, 27: 105000, 28: 120000, 29: 135000, 30: 155000}

var d: Dictionary = {}          # the monster being edited
var attacks: Array = []         # editable melee/ranged actions
var extras: Array = []          # non-attack actions kept from the template
var multi_count := 1
var multi_orig: Dictionary = {}
var editing_id := ""            # id of an existing custom monster being edited ("" = save as new)
var body: VBoxContainer
var attack_box: VBoxContainer
var msg: Label

func _init(template: Dictionary = {}) -> void:
	_load(template)

func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	custom_minimum_size = Vector2(760, 640)
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -380
	offset_right = 380
	offset_top = -330
	offset_bottom = 330
	add_theme_stylebox_override("panel", UIKit.sb(Color("#1b1626"), UIKit.GOLD, 2, 8, 12))
	_build()

# ---------------------------------------------------------------- data

func _load(t: Dictionary) -> void:
	d = t.duplicate(true) if not t.is_empty() else {
		"name": "New Monster", "size": "medium", "type": "humanoid", "cr": 1, "ac": 12, "hp": 20, "speed": 30, "fly": 0,
		"scores": {"str": 10, "dex": 10, "con": 10, "int": 10, "wis": 10, "cha": 10}, "token_color": "#a33a3a", "icon": "",
		"resist": [], "immune": [], "vulnerable": [], "condition_immune": []}
	editing_id = str(d.id) if Data.custom_monsters.has(d.get("id", "")) else ""
	attacks = []
	extras = []
	multi_count = 1
	multi_orig = {}
	for a in d.get("actions", []):
		var k = a.get("kind", "special")
		if k == "melee" or k == "ranged":
			attacks.append(a.duplicate(true))
		elif k == "multiattack":
			multi_orig = a
			multi_count = maxi(1, a.get("sequence", []).size())
		else:
			extras.append(a)
	if attacks.is_empty() and t.is_empty():
		attacks.append(_new_attack())

func _new_attack() -> Dictionary:
	return {"name": "Strike", "kind": "melee", "to_hit": 4, "reach": 5, "damage": [{"dice": "1d8+2", "type": "slashing"}]}

static func _prof(cr: float) -> int:
	return 2 + maxi(0, (int(ceil(cr)) - 1) / 4)

static func _list(txt: String) -> Array:
	var out: Array = []
	for p in txt.split(",", false):
		var s = p.strip_edges().to_lower()
		if s != "":
			out.append(s)
	return out

# ---------------------------------------------------------------- ui

func _row(label: String, w: Control) -> HBoxContainer:
	var h = UIKit.hbox()
	var l = UIKit.lbl(label, 14, UIKit.MUTED)
	l.custom_minimum_size = Vector2(110, 0)
	h.add_child(l)
	UIKit.expand(w)
	h.add_child(w)
	return h

func _build() -> void:
	for c in get_children():
		c.queue_free()
	var outer = UIKit.vbox(8)
	add_child(outer)
	outer.add_child(UIKit.header("Custom Monster" + ("  (editing)" if editing_id != "" else ""), 22))
	# Template picker.
	var tl = UIKit.hbox()
	var items: Array = [["", "— blank monster —"]]
	for m in Data.monsters_sorted():
		items.append([m.id, "%s%s (CR %s)" % ["★ " if Data.custom_monsters.has(m.id) else "", m.name, Data.cr_text(m.cr)]])
	var pick = [""]
	tl.add_child(UIKit.lbl("Start from:", 14, UIKit.MUTED))
	tl.add_child(UIKit.expand(UIKit.option(items, d.get("id", ""), func(id): pick[0] = id)))
	tl.add_child(UIKit.btn("Load", func():
		var src: Dictionary = Data.monster(pick[0]).duplicate(true)
		if pick[0] != "" and not Data.custom_monsters.has(pick[0]):
			src.erase("id")   # copying a built-in makes a new custom monster
			src.name = str(src.name) + " (custom)"
		_load(src)
		_build()))
	outer.add_child(tl)
	var sc = ScrollContainer.new()
	UIKit.expand(sc, true, true)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(sc)
	body = UIKit.vbox(8)
	UIKit.expand(body)
	sc.add_child(body)
	# Basics.
	body.add_child(_row("Name", UIKit.line(str(d.name), "Monster name", func(t): d.name = t)))
	var sz = UIKit.option(SIZES.map(func(s): return [s, s.capitalize()]), d.get("size", "medium"), func(v): d.size = v)
	body.add_child(_row("Size", sz))
	body.add_child(_row("Creature type", UIKit.line(str(d.get("type", "")), "beast, undead, fiend…", func(t): d.type = t.strip_edges().to_lower())))
	body.add_child(_row("Challenge", UIKit.option(CRS.map(func(c): return [c, "CR " + Data.cr_text(c)]), float(d.get("cr", 1)), func(v): d.cr = v)))
	var nums = UIKit.hbox(10)
	for f in [["hp", "HP", 1, 3000], ["ac", "AC", 1, 40], ["speed", "Speed", 0, 200], ["fly", "Fly", 0, 200]]:
		var key: String = f[0]
		nums.add_child(UIKit.lbl(f[1], 14, UIKit.MUTED))
		nums.add_child(UIKit.spin(f[2], f[3], int(d.get(key, 0)), func(v): d[key] = int(v)))
	body.add_child(nums)
	# Ability scores.
	var ab = UIKit.hbox(6)
	var scores: Dictionary = d.get("scores", {})
	d.scores = scores
	for a in Data.ABILITIES:
		var key: String = a
		ab.add_child(UIKit.lbl(key.to_upper(), 14, UIKit.MUTED))
		ab.add_child(UIKit.spin(1, 30, int(scores.get(key, 10)), func(v): scores[key] = int(v)))
	body.add_child(ab)
	# Token look.
	var look = UIKit.hbox(8)
	var cp = ColorPickerButton.new()
	cp.custom_minimum_size = Vector2(60, 30)
	cp.color = Color(str(d.get("token_color", "#a33a3a")))
	cp.edit_alpha = false
	cp.color_changed.connect(func(c): d.token_color = "#" + c.to_html(false))
	look.add_child(UIKit.lbl("Token colour", 14, UIKit.MUTED))
	look.add_child(cp)
	look.add_child(UIKit.lbl("Icon", 14, UIKit.MUTED))
	var icons: Array = [["", "(none)"]]
	for k in MonsterIcons.SVG:
		icons.append([k, str(k).capitalize()])
	look.add_child(UIKit.option(icons, str(d.get("icon", "")), func(v): d.icon = v))
	body.add_child(look)
	# Defences.
	for f in [["resist", "Resistances"], ["immune", "Immunities"], ["vulnerable", "Vulnerabilities"], ["condition_immune", "Condition immunities"]]:
		var key: String = f[0]
		body.add_child(_row(f[1], UIKit.line(", ".join(PackedStringArray(d.get(key, []))), "comma separated, e.g. fire, poison", func(t): d[key] = _list(t))))
	# Attacks.
	body.add_child(HSeparator.new())
	body.add_child(UIKit.lbl("Attacks", 16, UIKit.GOLD))
	attack_box = UIKit.vbox(6)
	body.add_child(attack_box)
	_fill_attacks()
	body.add_child(UIKit.btn("＋ Add attack", func():
		attacks.append(_new_attack())
		_fill_attacks()))
	var mh = UIKit.hbox()
	mh.add_child(UIKit.lbl("Attacks per Attack action", 14, UIKit.MUTED))
	mh.add_child(UIKit.spin(1, 8, multi_count, func(v): multi_count = int(v)))
	body.add_child(mh)
	if not extras.is_empty():
		var names: Array = extras.map(func(a): return str(a.get("name", "?")))
		var l = UIKit.lbl("Keeps special abilities from the template: " + ", ".join(PackedStringArray(names)), 13, UIKit.MUTED)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD
		body.add_child(l)
	# Footer.
	msg = UIKit.lbl("", 14, UIKit.BAD)
	outer.add_child(msg)
	var fh = UIKit.hbox(8)
	fh.add_child(UIKit.btn("Save to bestiary", _save))
	if editing_id != "":
		fh.add_child(UIKit.btn("Delete", func():
			CharacterStore.delete_custom_monster(editing_id)
			deleted.emit(editing_id)
			closed.emit()
			queue_free()))
	fh.add_child(UIKit.btn("Cancel", func():
		closed.emit()
		queue_free()))
	outer.add_child(fh)

func _fill_attacks() -> void:
	UIKit.clear(attack_box)
	for i in attacks.size():
		var a: Dictionary = attacks[i]
		if not a.has("damage") or a.damage.is_empty():
			a.damage = [{"dice": "1d6", "type": "bludgeoning"}]
		var dmg: Dictionary = a.damage[0]
		var p = UIKit.panel(null, Color("#241d31"))
		var v = UIKit.vbox(4)
		p.add_child(v)
		var r1 = UIKit.hbox()
		r1.add_child(UIKit.expand(UIKit.line(str(a.name), "Attack name", func(t): a.name = t)))
		r1.add_child(UIKit.option([["melee", "Melee"], ["ranged", "Ranged"]], a.get("kind", "melee"), func(k):
			a.kind = k
			if k == "ranged" and not a.has("range"):
				a.range = 60
				a.long_range = 240
			_fill_attacks()))
		r1.add_child(UIKit.btn("✕", func():
			attacks.remove_at(i)
			_fill_attacks()))
		v.add_child(r1)
		var r2 = UIKit.hbox(8)
		r2.add_child(UIKit.lbl("To hit +", 13, UIKit.MUTED))
		r2.add_child(UIKit.spin(-5, 30, int(a.get("to_hit", 0)), func(x): a.to_hit = int(x)))
		if a.get("kind", "melee") == "melee":
			r2.add_child(UIKit.lbl("Reach", 13, UIKit.MUTED))
			r2.add_child(UIKit.spin(5, 30, int(a.get("reach", 5)), func(x): a.reach = int(x), 5))
		else:
			r2.add_child(UIKit.lbl("Range", 13, UIKit.MUTED))
			r2.add_child(UIKit.spin(5, 600, int(a.get("range", 60)), func(x): a.range = int(x), 5))
			r2.add_child(UIKit.lbl("Long", 13, UIKit.MUTED))
			r2.add_child(UIKit.spin(5, 1200, int(a.get("long_range", 240)), func(x): a.long_range = int(x), 5))
		v.add_child(r2)
		var r3 = UIKit.hbox(8)
		r3.add_child(UIKit.lbl("Damage", 13, UIKit.MUTED))
		var dl = UIKit.line(str(dmg.get("dice", "1d6")), "e.g. 2d6+3", func(t): dmg.dice = t.strip_edges())
		dl.custom_minimum_size = Vector2(110, 0)
		r3.add_child(dl)
		r3.add_child(UIKit.expand(UIKit.option(Data.DAMAGE_TYPES.map(func(t): return [t, t.capitalize()]), dmg.get("type", "slashing"), func(t): dmg.type = t)))
		v.add_child(r3)
		attack_box.add_child(p)

func _error(t: String) -> void:
	msg.text = t

func _save() -> void:
	var nm := str(d.get("name", "")).strip_edges()
	if nm == "":
		_error("Give the monster a name.")
		return
	if attacks.is_empty() and extras.is_empty():
		_error("Add at least one attack.")
		return
	var rx = RegEx.create_from_string("^\\d+d\\d+([+-]\\d+)?$")
	var names := {}
	for a in attacks:
		a.damage[0].dice = str(a.damage[0].dice).replace(" ", "")
		if rx.search(a.damage[0].dice) == null:
			_error("Damage for \"%s\" must look like 2d6+3." % a.name)
			return
		if str(a.name).strip_edges() == "" or names.has(a.name):
			_error("Every attack needs a unique name.")
			return
		names[a.name] = true
	var cr := float(d.get("cr", 1))
	var m: Dictionary = d.duplicate(true)
	m.name = nm
	m.id = editing_id if editing_id != "" else "custom_%s_%s" % [nm.to_lower().validate_filename().replace(" ", "_"), CharacterStore.new_id().substr(0, 6)]
	m.cr = cr
	m.xp = XP.get(cr, 0)
	m.prof = _prof(cr)
	m.hit_dice = m.get("hit_dice", "")
	for k in ["alignment", "senses", "languages", "ac_note"]:
		m[k] = m.get(k, "")
	if str(m.senses) == "":
		m.senses = "passive Perception %d" % (10 + Rules.mod(int(m.scores.get("wis", 10))))
	for k in ["saves", "skills"]:
		m[k] = m.get(k, {})
	for k in ["swim", "climb"]:
		m[k] = int(m.get(k, 0))
	for k in ["traits", "bonus_actions", "reactions", "legendary_actions"]:
		m[k] = m.get(k, [])
	var acts: Array = []
	if multi_count > 1 and not attacks.is_empty():
		if not multi_orig.is_empty() and multi_orig.get("sequence", []).size() == multi_count and _seq_valid(multi_orig, names):
			acts.append(multi_orig)
		else:
			var seq: Array = []
			for i in multi_count:
				seq.append(attacks[i % attacks.size()].name)
			acts.append({"name": "Multiattack", "kind": "multiattack", "sequence": seq, "desc": "Makes %d attacks." % multi_count})
	acts.append_array(attacks)
	acts.append_array(extras)
	m.actions = acts
	CharacterStore.save_custom_monster(m)
	saved.emit(m.id)
	closed.emit()
	queue_free()

static func _seq_valid(multi: Dictionary, names: Dictionary) -> bool:
	for n in multi.get("sequence", []):
		if not names.has(n):
			return false
	return true
