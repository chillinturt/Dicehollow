extends Node
## Screenshots of the fog of war (DM view, players' view in hard and soft fog) into the folder given
## as the first user arg. Needs a real window: Godot --path . res://tests/fog_shots.tscn -- <folder>

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
	Session.start_offline("Tester", 26, 18)
	var eng: CombatEngine = Session.engine
	# Two rooms joined by a door, with a pillar in the first.
	for x in range(10, 11):
		for y in 18:
			if y != 8:
				eng.set_cell(Vector2i(x, y), EngineBase.WALL)
	for y in range(0, 7):
		eng.set_cell(Vector2i(18, y), EngineBase.WALL)
	for p in [Vector2i(6, 4), Vector2i(6, 5), Vector2i(13, 12), Vector2i(14, 12)]:
		eng.set_cell(p, EngineBase.WALL)
	for p in [Vector2i(20, 12), Vector2i(21, 12), Vector2i(20, 13)]:
		eng.set_cell(p, EngineBase.WATER)
	var y := 6
	for ch in CharacterStore.premades().slice(0, 3):
		Session.add_character(ch, 1, Vector2i(3, y))
		y += 2
	Session.add_monster("goblin", Vector2i(14, 9))
	Session.add_monster("orc", Vector2i(22, 3))
	Session.add_monster("goblin", Vector2i(8, 14))
	Session.request({"type": "dm_fog", "mode": "hard", "range": 0})
	var b = load("res://scenes/battle.tscn").instantiate()
	add_child(b)
	b.dm_tabs.current_tab = 2
	b.cam.position = Vector2(13, 9) * 64 + Vector2(160, 40)
	b.cam.zoom = Vector2.ONE * 0.7
	await _snap("fog_dm_view")
	b.fog_preview = true
	b._update_fog()
	b._sync_tokens([])
	b._refresh_ui()
	await _snap("fog_hard_players")
	# Walk the first PC to the doorway: the second room is now remembered.
	var pc: Dictionary = Session.state.combatants.values().filter(func(o): return o.kind == "pc")[0]
	Session.request({"type": "move", "cid": pc.id, "to": Vector2i(11, 8), "free": true})
	await get_tree().create_timer(0.8).timeout
	Session.request({"type": "move", "cid": pc.id, "to": Vector2i(5, 8), "free": true})
	await get_tree().create_timer(0.8).timeout
	await _snap("fog_hard_explored")
	Session.request({"type": "dm_fog", "mode": "soft", "range": 30})
	await _snap("fog_soft_dark")
	get_tree().quit()
