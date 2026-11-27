extends Control
## Title screen: manage characters, host a game as DM, join a game, or start a solo test battle.

var right: VBoxContainer
var status_lbl: Label

func _ready() -> void:
	theme = UIKit.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_fit()
	get_viewport().size_changed.connect(_fit)
	var bg = ColorRect.new()
	bg.color = UIKit.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root = UIKit.hbox(30)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(UIKit.margin(root, 48))
	get_child(1).set_anchors_preset(Control.PRESET_FULL_RECT)
	# Left column: title and navigation.
	var left = UIKit.vbox(14)
	left.custom_minimum_size = Vector2(380, 0)
	root.add_child(left)
	var title = UIKit.lbl("Dicehollow", 54, UIKit.GOLD)
	left.add_child(title)
	left.add_child(UIKit.lbl("A virtual tabletop for 5th Edition (2014 rules)", 17, UIKit.MUTED))
	left.add_child(_spacer(20))
	for item in [["Characters", _open_characters, "Create and edit characters, upload portraits."],
			["Host a Game (DM)", _show_host, "Run a game: build maps, place monsters, run combat."],
			["Join a Game", _show_join, "Join a DM's game over the network with one of your characters."],
			["Solo Test Battle", _show_solo, "Try the combat system locally against a sample encounter."],
			["Quit", func(): get_tree().quit(), ""]]:
		var b = UIKit.btn(item[0], item[1], item[2])
		b.custom_minimum_size = Vector2(320, 48)
		b.add_theme_font_size_override("font_size", 19)
		left.add_child(b)
	left.add_child(_spacer(20))
	status_lbl = UIKit.lbl("", 14, UIKit.MUTED)
	status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	left.add_child(status_lbl)
	Session.status.connect(func(t): status_lbl.text = t)
	if Session.last_end_reason != "":
		status_lbl.text = Session.last_end_reason
		Session.last_end_reason = ""
	left.add_child(UIKit.lbl("Version " + Session.VERSION, 12, UIKit.MUTED))
	# Right column: context panel.
	right = UIKit.vbox(10)
	UIKit.expand(right, true, true)
	var rp = UIKit.panel(UIKit.margin(right, 16))
	UIKit.expand(rp, true, true)
	root.add_child(rp)
	_show_welcome()

func _spacer(h: int) -> Control:
	var c = Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c

func _show_welcome() -> void:
	UIKit.clear(right)
	right.add_child(UIKit.header("Welcome, adventurer"))
	var r = UIKit.rich("""[color=#a59cb5]How it works[/color]

• [b]Players[/b] build characters in [b]Characters[/b] (any 2014 race, class, subclass — including Artificer, Twilight and Peace clerics, Scribes and Chronurgy wizards — with multiclassing) and upload a portrait image for their token.

• The [b]DM[/b] hosts a game, paints a battle map, drops monsters from the bestiary, and starts combat.

• Players join with the DM's IP address. On your turn, click a cell to move and click an action on the hotbar, then a target. Attack rolls, saving throws, damage, resistances, concentration, reactions (Shield, Counterspell, opportunity attacks…) and class features resolve automatically.

• Monsters play themselves (or the DM can take control), and anyone can press [b]Auto Turn[/b] to let the AI play their turn.

[color=#a59cb5]Tip:[/color] start with [b]Solo Test Battle[/b] to see everything working with the premade party.""", true)
	right.add_child(r)

func _form_row(parent: Control, label: String, ctrl: Control) -> Control:
	var h = UIKit.hbox(10)
	var l = UIKit.lbl(label, 15, UIKit.MUTED)
	l.custom_minimum_size = Vector2(160, 0)
	h.add_child(l)
	UIKit.expand(ctrl)
	h.add_child(ctrl)
	parent.add_child(h)
	return ctrl

func _show_host() -> void:
	UIKit.clear(right)
	right.add_child(UIKit.header("Host a Game"))
	right.add_child(UIKit.lbl("You'll be the Dungeon Master. Share your IP address and port with players.", 14, UIKit.MUTED))
	var dm_name: LineEdit = _form_row(right, "Your name", UIKit.line("Dungeon Master"))
	var gname: LineEdit = _form_row(right, "Game name", UIKit.line("The Sunless Citadel"))
	var port: SpinBox = _form_row(right, "Port", UIKit.spin(1024, 65535, Session.DEFAULT_PORT))
	var w: SpinBox = _form_row(right, "Map width (squares)", UIKit.spin(8, 80, 28))
	var h: SpinBox = _form_row(right, "Map height (squares)", UIKit.spin(8, 60, 18))
	var ips = UIKit.lbl("Your local IP addresses: " + ", ".join(_local_ips()), 13, UIKit.MUTED)
	ips.autowrap_mode = TextServer.AUTOWRAP_WORD
	right.add_child(ips)
	var go = UIKit.btn("Start Hosting", func():
		if Session.host(dm_name.text, gname.text, int(port.value), int(w.value), int(h.value)) == OK:
			get_tree().change_scene_to_file("res://scenes/battle.tscn"))
	go.custom_minimum_size = Vector2(0, 44)
	right.add_child(go)

func _local_ips() -> Array:
	var out: Array = []
	for ip in IP.get_local_addresses():
		if ip.count(".") == 3 and not ip.begins_with("127.") and not ip.begins_with("169.254"):
			out.append(ip)
	return out if not out.is_empty() else ["127.0.0.1"]

func _all_characters() -> Array:
	var chars = CharacterStore.list_characters()
	for p in CharacterStore.premades():
		p.name = "[Premade] " + p.name
		chars.append(p)
	return chars

func _show_join() -> void:
	UIKit.clear(right)
	right.add_child(UIKit.header("Join a Game"))
	var chars = _all_characters()
	if chars.is_empty():
		right.add_child(UIKit.lbl("Create a character first.", 15, UIKit.BAD))
		return
	var pname: LineEdit = _form_row(right, "Your name", UIKit.line("Player"))
	var ip: LineEdit = _form_row(right, "DM's IP address", UIKit.line("127.0.0.1"))
	var port: SpinBox = _form_row(right, "Port", UIKit.spin(1024, 65535, Session.DEFAULT_PORT))
	var items: Array = []
	for i in chars.size():
		items.append([i, "%s — %s" % [chars[i].name, Rules.class_summary(chars[i])]])
	var sel = [0]
	_form_row(right, "Character", UIKit.option(items, 0, func(id): sel[0] = id))
	var go = UIKit.btn("Join", func():
		var ch: Dictionary = chars[sel[0]].duplicate(true)
		ch.name = str(ch.name).replace("[Premade] ", "")
		if Session.join(ip.text.strip_edges(), int(port.value), pname.text, ch) == OK:
			get_tree().change_scene_to_file("res://scenes/battle.tscn"))
	go.custom_minimum_size = Vector2(0, 44)
	right.add_child(go)

func _show_solo() -> void:
	UIKit.clear(right)
	right.add_child(UIKit.header("Solo Test Battle"))
	right.add_child(UIKit.lbl("Pick up to six heroes. You control everyone; monsters play themselves.", 14, UIKit.MUTED))
	var chars = _all_characters()
	var picks: Array = []
	var list = UIKit.vbox(4)
	for i in chars.size():
		var on = i >= chars.size() - 6 and chars.size() > 0
		if on and picks.size() < 4:
			picks.append(i)
		var idx = i
		list.add_child(UIKit.check("%s — %s" % [chars[i].name, Rules.class_summary(chars[i])], idx in picks, func(p):
			if p and not idx in picks: picks.append(idx)
			elif not p: picks.erase(idx)))
	var sc = UIKit.scroll(list)
	sc.custom_minimum_size = Vector2(0, 260)
	UIKit.expand(sc, true, true)
	right.add_child(sc)
	var enc = ["goblins", "undead", "beasts", "cultists", "dragon"]
	var enc_sel = ["goblins"]
	_form_row(right, "Encounter", UIKit.option([["goblins", "Goblin warband (easy)"], ["undead", "Restless dead (medium)"], ["beasts", "Owlbear & wolves (medium)"], ["cultists", "Cult and its mage (hard)"], ["dragon", "Young red dragon (deadly)"]], "goblins", func(id): enc_sel[0] = id))
	var go = UIKit.btn("Start Battle", func():
		Session.start_offline("You", 26, 18)
		var x = 3
		var y = 5
		for i in picks.slice(0, 6):
			var ch: Dictionary = chars[i].duplicate(true)
			ch.name = str(ch.name).replace("[Premade] ", "")
			Session.add_character(ch, 1, Vector2i(x + (y % 2), y))
			y += 2
		_sample_map(enc_sel[0])
		get_tree().change_scene_to_file("res://scenes/battle.tscn"))
	go.custom_minimum_size = Vector2(0, 44)
	right.add_child(go)

func _sample_map(kind: String) -> void:
	var eng = Session.engine
	# A ruined hall: border walls, pillars, rubble.
	for x in Session.state.w:
		eng.set_cell(Vector2i(x, 0), EngineBase.WALL)
		eng.set_cell(Vector2i(x, Session.state.h - 1), EngineBase.WALL)
	for y in Session.state.h:
		eng.set_cell(Vector2i(0, y), EngineBase.WALL)
		eng.set_cell(Vector2i(Session.state.w - 1, y), EngineBase.WALL)
	for p in [Vector2i(9, 4), Vector2i(9, 12), Vector2i(15, 4), Vector2i(15, 12)]:
		eng.set_cell(p, EngineBase.WALL)
		eng.set_cell(p + Vector2i(1, 0), EngineBase.WALL)
	for p in [Vector2i(12, 7), Vector2i(12, 8), Vector2i(13, 8), Vector2i(11, 9), Vector2i(6, 14), Vector2i(7, 14)]:
		eng.set_cell(p, EngineBase.DIFFICULT)
	for p in [Vector2i(18, 15), Vector2i(19, 15), Vector2i(19, 16), Vector2i(20, 16)]:
		eng.set_cell(p, EngineBase.WATER)
	var groups = {
		"goblins": ["goblin", "goblin", "goblin", "goblin", "hobgoblin", "wolf"],
		"undead": ["skeleton", "skeleton", "zombie", "zombie", "ghoul", "shadow"],
		"beasts": ["owlbear", "wolf", "wolf", "dire_wolf"],
		"cultists": ["cultist", "cultist", "cultist", "cult_fanatic", "mage", "thug"],
		"dragon": ["young_red_dragon", "kobold", "kobold", "kobold"],
	}
	var i = 0
	for mid in groups.get(kind, groups.goblins):
		if Data.monsters.has(mid):
			Session.add_monster(mid, Vector2i(19 + (i % 3) * 2, 3 + (i / 3) * 4 + (i % 2) * 2))
			i += 1
	Session.engine.log_line("[color=#ffd166]Solo battle ready. Press [b]Start Combat[/b] in the DM panel when you're set.[/color]")

func _open_characters() -> void:
	get_tree().change_scene_to_file("res://scenes/characters.tscn")

func _fit() -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size
