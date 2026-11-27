extends Node
## Portrait templates: every icon renders, picking one saves a portrait that loads like an
## uploaded image, and the character editor's gallery sets / redraws / clears it.
## Run: Godot --headless --path . res://tests/portrait_test.tscn [-- <sheet.png>]

var errors := 0

func check(ok: bool, what: String) -> void:
	if ok:
		print("  ok   ", what)
	else:
		errors += 1
		print("  FAIL ", what)

func _ready() -> void:
	print("== templates")
	var cols := [Color("#7a5cff"), Color("#c0392b"), Color("#f2e9c9"), Color("#2e8b57")]
	var sheet := Image.create(64 * PortraitTemplates.ORDER.size(), 64 * cols.size(), false, Image.FORMAT_RGBA8)
	for i in PortraitTemplates.ORDER.size():
		var icon: String = PortraitTemplates.ORDER[i][0]
		check(PortraitTemplates.has(icon), "%s is a known icon" % icon)
		for j in cols.size():
			var img := PortraitTemplates.render(icon, cols[j], 64)
			if img == null:
				check(false, "%s renders" % icon)
				continue
			sheet.blit_rect(img, Rect2i(0, 0, 64, 64), Vector2i(i * 64, j * 64))
	for cid in PortraitTemplates.CLASS_ICON:
		check(not Data.cls(cid).is_empty(), "suggested-icon class %s exists" % cid)
		check(PortraitTemplates.has(PortraitTemplates.CLASS_ICON[cid]), "class %s maps to a real icon" % cid)
	check(PortraitTemplates.suggested({"classes": [{"id": "wizard", "level": 1}]}) == "hat", "wizards are suggested the hat")
	check(PortraitTemplates.render("nope", Color.RED) == null, "unknown icon renders nothing")

	print("== saved portrait")
	var key := PortraitTemplates.make_portrait("sword", Color("#7a5cff"))
	check(key == "tpl_sword_7a5cff", "key is deterministic (%s)" % key)
	var tex := CharacterStore.portrait_texture(key)
	check(tex != null and tex.get_width() == CharacterStore.PORTRAIT_SIZE, "portrait loads at full size")
	check(not CharacterStore.get_portrait_bytes(key).is_empty(), "portrait bytes available for network sync")

	print("== editor")
	var ed = load("res://scripts/ui/character_editor.gd").new()
	add_child(ed)
	await get_tree().process_frame
	ed.ch = Rules.new_character()
	ed.ch.classes = [{"id": "fighter", "level": 1, "subclass": ""}]
	ed.ch.color = "#c0392b"
	ed._set_template("axe")
	check(ed.ch.portrait == "tpl_axe_c0392b" and ed.ch.portrait_template == "axe", "picking an icon sets the portrait")
	check(CharacterStore.portrait_texture(ed.ch.portrait) != null, "picked portrait has a texture")
	ed.ch.color = "#2e8b57"
	ed._set_template(ed.ch.portrait_template)
	check(ed.ch.portrait == "tpl_axe_2e8b57", "colour change redraws the template")
	ed._on_portrait_file("res://icon.svg")
	check(ed.ch.portrait != "" and not ed.ch.portrait.begins_with("tpl_") and ed.ch.portrait_template == "", "uploading an image replaces the template")
	for k in [key, "tpl_axe_c0392b", "tpl_axe_2e8b57", ed.ch.portrait]:
		DirAccess.remove_absolute(CharacterStore.PORTRAIT_DIR + "/" + k + ".png")
	ed.queue_free()

	print("== in game")
	Session.start_offline("Tester", 20, 12)
	var cid := Session.add_character(CharacterStore.premades()[0], 1, Vector2i(3, 3))
	var b = load("res://scenes/battle.tscn").instantiate()
	add_child(b)
	await get_tree().process_frame
	var pw: DialogPanel = b._open_portrait_picker(cid)
	check(pw != null, "the picker opens for your own character")
	var grid: GridContainer = null
	for n in pw.find_children("*", "GridContainer", true, false):
		if n.get_child_count() == PortraitTemplates.ORDER.size():
			grid = n
	check(grid != null and grid.get_child_count() == PortraitTemplates.ORDER.size(), "the picker shows every icon")
	var crown_i := -1
	for i in PortraitTemplates.ORDER.size():
		if PortraitTemplates.ORDER[i][0] == "crown":
			crown_i = i
	(grid.get_child(crown_i) as Button).pressed.emit()
	var tc: Dictionary = Session.engine.C(cid)
	check(str(tc.portrait).begins_with("tpl_crown_"), "clicking an icon changes the token portrait (%s)" % tc.portrait)
	check(str(Session.sheets[cid].get("portrait_template", "")) == "crown", "the sheet remembers the icon")
	check(CharacterStore.portrait_texture(tc.portrait) != null, "the new portrait has a texture")
	Session.set_portrait(cid, "../escape", "", "#ff0000")
	check(str(Session.engine.C(cid).portrait).begins_with("tpl_crown_"), "a path-like key is refused")
	DirAccess.remove_absolute(CharacterStore.PORTRAIT_DIR + "/" + str(tc.portrait) + ".png")
	pw.close()
	b.queue_free()
	Session.leave()

	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		sheet.save_png(args[0])
		print("sheet -> ", args[0])
	print("portrait_test: %s (%d errors)" % ["PASS" if errors == 0 else "FAIL", errors])
	get_tree().quit(1 if errors else 0)
