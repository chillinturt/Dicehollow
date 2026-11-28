extends Node
## Screenshots of the combat HUD during a solo battle: a player's turn, aiming an attack (with the
## hover tip over an enemy), and an area spell. Into the folder given as the first user arg.
## Needs a real window: Godot --path . res://tests/combat_shots.tscn -- <folder>

var out := ""

func _snap(name: String, wait := 0.0) -> void:
	if wait > 0.0:
		await get_tree().create_timer(wait).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/" + name + ".png")
	print("shot ", name)

## Puts the pointer over a creature's token and previews that cell, as if hovering it.
func _hover(b, c: Dictionary) -> void:
	await _hover_cell(b, Vector2i(Vector2(c.pos)))

func _hover_cell(b, cell: Vector2i) -> void:
	var world: Vector2 = (Vector2(cell) + Vector2(0.5, 0.5)) * b.CELL
	var screen: Vector2 = b.get_viewport().get_canvas_transform() * world
	get_viewport().warp_mouse(screen)
	await get_tree().process_frame
	b._preview_at(cell)

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0] if args.size() > 0 else "user://"
	get_window().size = Vector2i(1600, 900)
	Session.start_offline("Tester", 24, 16)
	var y := 4
	for ch in CharacterStore.premades().slice(0, 4):
		Session.add_character(ch, 1, Vector2i(7, y))
		y += 2
	Session.auto_monsters = true
	for i in 4:
		Session.add_monster(["goblin", "goblin", "hobgoblin", "orc"][i], Vector2i(11 + i % 2, 4 + i * 2))
	var b = load("res://scenes/battle.tscn").instantiate()
	add_child(b)
	await get_tree().create_timer(0.5).timeout
	Session.request({"type": "dm_start_combat"})
	# Wait for a party member's turn with nothing left to animate.
	for i in 60:
		await get_tree().create_timer(0.25).timeout
		if Session.engine.current().kind == "pc" and not b.playing:
			break
	var cur: Dictionary = Session.engine.current()
	b.control_cid = cur.id
	b._refresh_ui()
	b._center_on(cur.id)
	await _snap("combat_turn", 1.0)
	var foes: Array = Session.state.combatants.values().filter(func(o): return o.team != "party" and not o.dead)
	for a in Session.engine.get_actions(cur):
		if a.kind == "weapon" and a.enabled:
			b._on_action_pressed(a)
			break
	if not foes.is_empty():
		await _hover(b, foes[0])
	await _snap("combat_aim", 0.4)
	b._cancel_mode()
	# Hovering a creature with nothing selected says who it is.
	if not foes.is_empty():
		await _hover(b, foes[0])
		await _snap("combat_hover_creature", 0.2)
	# An enemy next to us: walking away shows the opportunity attack warning and a red path.
	if not foes.is_empty():
		var foe: Dictionary = foes[foes.size() - 1]
		foe.pos = Vector2i(Vector2(cur.pos)) + Vector2i(1, 0)
		b._sync_tokens([])
		b._refresh_ui()
		await _hover_cell(b, Vector2i(Vector2(cur.pos)) + Vector2i(-2, 1))
		await _snap("combat_move_oa", 0.3)
	# Let a few turns play out so the log, floats and dice have something in them.
	for i in 3:
		cur = Session.engine.current()
		Session.request({"type": "ai_turn", "cid": cur.id})
		await _snap("combat_action_%d" % i, 0.5)
		for k in 40:
			await get_tree().create_timer(0.2).timeout
			if not b.playing and Session.engine.current().kind == "pc":
				break
	await _snap("combat_later", 0.6)
	get_tree().quit()
