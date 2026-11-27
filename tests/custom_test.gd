extends Node
## Custom monsters and map backgrounds.

func _fail(t: String) -> void:
	print("FAIL ", t)
	get_tree().quit(1)

func _ready() -> void:
	Session.start_offline("Tester", 24, 16)
	var b = load("res://scenes/battle.tscn").instantiate()
	add_child(b)
	await get_tree().process_frame
	# Editor: build a monster through the real save path.
	var ed = MonsterEditor.new({})
	b.ui.add_child(ed)
	await get_tree().process_frame
	ed.d.name = "Test Gribbler"
	ed.d.hp = 33
	ed.attacks[0].damage[0].dice = "2d6+3"
	ed.multi_count = 2
	ed._save()
	var found = ""
	for id in Data.custom_monsters:
		if Data.custom_monsters[id].name == "Test Gribbler":
			found = id
	if found == "":
		return _fail("custom monster not registered")
	var cid = Session.add_monster(found, Vector2i(5, 5))
	var c = Session.engine.C(cid)
	if c.max_hp != 33 or c.attacks.size() != 1 or c.mactions.size() != 1:
		return _fail("combatant stats wrong: %s" % str(c.mactions))
	# Snapshot carries the definition.
	var snap = Session.map_snapshot()
	if not snap.custom_monsters.has(found):
		return _fail("snapshot missing custom monster")
	CharacterStore.delete_custom_monster(found)
	if Data.monsters.has(found):
		return _fail("delete failed")
	Session.request({"type": "dm_load_map", "map": snap})
	if not Data.monsters.has(found):
		return _fail("map load did not restore custom monster")
	CharacterStore.delete_custom_monster(found)
	# Editing a built-in template copies it.
	var ed2 = MonsterEditor.new(b._editor_template("goblin"))
	if ed2.editing_id != "" or ed2.attacks.is_empty():
		return _fail("template copy")
	# Background.
	var img = Image.create(200, 100, false, Image.FORMAT_RGB8)
	img.fill(Color.RED)
	var p = OS.get_temp_dir().path_join("bgtest.png")
	img.save_png(p)
	var key = CharacterStore.import_background(p)
	if key == "":
		return _fail("import_background")
	Session.request({"type": "dm_background", "key": key, "fit": true})
	if Session.state.bg != key or Session.state.h != 12:
		return _fail("background/fit: %s h=%d" % [Session.state.get("bg"), Session.state.h])
	await get_tree().process_frame
	b.map_view.queue_redraw()
	await get_tree().process_frame
	Session.request({"type": "dm_background", "key": ""})
	print("PASS custom_test")
	get_tree().quit(0)
