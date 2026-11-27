extends Node
## Screenshots of the dice tray during a solo battle with "All rolls" on, into the folder given as the
## first user arg. Needs a real window: Godot --path . res://tests/dice_shots.tscn -- <folder>
## The player's own dice setting is put back afterwards.

var out := ""

func _snap(name: String, wait := 0.0) -> void:
	if wait > 0.0:
		await get_tree().create_timer(wait).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/" + name + ".png")
	print("shot ", name)

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0] if args.size() > 0 else "user://"
	get_window().size = Vector2i(1600, 900)
	var before := DiceTray.mode()
	DiceTray.set_mode("all")
	Session.start_offline("Tester", 22, 14)
	var y := 4
	for ch in CharacterStore.premades().slice(0, 3):
		Session.add_character(ch, 1, Vector2i(8, y))
		y += 2
	Session.auto_monsters = true
	for i in 3:
		Session.add_monster("goblin", Vector2i(9, 4 + i * 2))
	var b = load("res://scenes/battle.tscn").instantiate()
	add_child(b)
	await get_tree().create_timer(0.5).timeout
	Session.request({"type": "dm_start_combat"})
	await _snap("dice_initiative", 0.3)
	await _snap("dice_initiative_settled", 0.6)
	var n := 0
	for i in 40:
		await get_tree().create_timer(0.25).timeout
		var cur = Session.engine.current()
		if cur.kind == "pc" and not b.playing:
			Session.request({"type": "ai_turn", "cid": cur.id})
			await _snap("dice_rolling_%d" % n, 0.25)
			await _snap("dice_settled_%d" % n, 0.7)
			n += 1
			if n >= 3:
				break
	DiceTray.set_mode(before)
	get_tree().quit()
