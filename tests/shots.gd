extends Node
## Renders each screen in a real window and saves screenshots to the given folder (first user arg).

var out := ""

func _snap(name: String) -> void:
	await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/" + name + ".png")
	print("shot ", name)

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0] if args.size() > 0 else "user://"
	get_window().size = Vector2i(1600, 900)
	var m = load("res://scenes/main_menu.tscn").instantiate()
	add_child(m)
	await _snap("menu")
	m.queue_free()
	for p in CharacterStore.premades():
		if CharacterStore.list_characters().filter(func(c): return c.name == p.name).is_empty():
			CharacterStore.save_character(p)
	var ce = load("res://scenes/characters.tscn").instantiate()
	add_child(ce)
	await _snap("characters")
	ce.tabs.current_tab = 1
	await _snap("characters_classes")
	ce.tabs.current_tab = 5
	await _snap("characters_spells")
	ce.tabs.current_tab = 6
	await _snap("characters_plan")
	ce.tabs.current_tab = 7
	await _snap("characters_history")
	ce.queue_free()
	Session.start_offline("Tester", 26, 18)
	var y := 4
	for ch in CharacterStore.premades():
		Session.add_character(ch, 1, Vector2i(4 + (y % 2), y))
		y += 2
	Session.auto_monsters = true
	for mid in ["goblin", "goblin", "hobgoblin", "orc", "mage"]:
		Session.add_monster(mid, Vector2i(17 + (y % 3), y - 8))
		y += 2
	for p in [Vector2i(10, 4), Vector2i(10, 5), Vector2i(11, 12), Vector2i(12, 12)]:
		Session.engine.set_cell(p, EngineBase.WALL)
	for p in [Vector2i(13, 8), Vector2i(14, 8), Vector2i(13, 9)]:
		Session.engine.set_cell(p, EngineBase.DIFFICULT)
	var b = load("res://scenes/battle.tscn").instantiate()
	add_child(b)
	await _snap("battle_setup")
	Session.request({"type": "dm_start_combat"})
	for i in 30:
		await get_tree().create_timer(0.3).timeout
		var cur = Session.engine.current()
		if cur.kind == "pc" and Session.state.round < 2:
			Session.request({"type": "ai_turn", "cid": cur.id})
		elif cur.kind == "pc":
			break
	b.selected_cid = Session.engine.current().get("id", "")
	b._refresh_ui()
	await _snap("battle_turn")
	# Show targeting with a hit-chance tooltip.
	var c = Session.engine.current()
	for a in Session.engine.get_actions(c):
		if a.kind == "weapon" and a.enabled:
			b._on_action_pressed(a)
			break
	await _snap("battle_targeting")
	b._cancel_mode()
	# Character sheet and levelling.
	Session.request({"type": "dm_end_combat"})
	await get_tree().create_timer(0.3).timeout
	var pc: Dictionary = Session.state.combatants.values().filter(func(o): return o.kind == "pc")[2]
	b.control_cid = pc.id
	b.selected_cid = pc.id
	Session.request({"type": "dm_grant_level"})
	b.dm_tabs.current_tab = 3
	b._refresh_ui()
	await _snap("battle_party_tab")
	var sw = b._open_sheet(pc.id)
	await _snap("sheet_overview")
	for t in [1, 2, 3]:
		sw.tabs.current_tab = t
		await _snap("sheet_tab%d" % t)
	sw.close()
	var lw = b._open_level_up(pc.id)
	var n := 0
	while is_instance_valid(lw) and n < 10:
		await _snap("levelup_%d_%s" % [n, lw.step_name()])
		if lw.is_last_step():
			break
		lw.next_step(true)
		n += 1
	if is_instance_valid(lw):
		lw.close()
	var mw = b._open_level_up(Session.state.combatants.values().filter(func(o): return o.kind == "pc")[4].id, true)
	mw.pick_class("fighter")
	await _snap("levelup_multiclass")
	mw.close()
	get_tree().quit()
