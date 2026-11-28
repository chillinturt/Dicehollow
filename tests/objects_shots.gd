extends Node
## Screenshots of interactable objects and an endless map: a generated tavern full of objects, aiming
## "Attack Object" at a weak wall (gold outlines, hover tip), a damaged crate, and an endless forest after it
## has grown. Into the folder given as the first user arg.
## Needs a real window: Godot --path . res://tests/objects_shots.tscn -- <folder>

var out := ""

func _snap(name: String, wait := 0.0) -> void:
	if wait > 0.0:
		await get_tree().create_timer(wait).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/" + name + ".png")
	print("shot ", name)

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
	Session.add_character(CharacterStore.premades()[0], 1, Vector2i(5, 5))
	var b = load("res://scenes/battle.tscn").instantiate()
	add_child(b)
	await get_tree().create_timer(0.4).timeout
	# A hand-made room: every kind of object.
	var eng: CombatEngine = Session.engine
	var hero: Dictionary = eng.all_combatants()[0]
	for y in range(2, 10):
		Session.engine.set_cell(Vector2i(9, y), EngineBase.WALL)
	var x := 2
	for k in MapObjects.PLACEABLE:
		if k in ["weak_wall", "cracked_wall"]:
			continue
		Session.request({"type": "dm_object", "k": k, "at": Vector2i(x, 3)})
		x += 1 if x < 8 else 0
		if x > 8:
			break
	Session.request({"type": "dm_object", "k": "weak_wall", "at": Vector2i(9, 5)})
	Session.request({"type": "dm_object", "k": "cracked_wall", "at": Vector2i(9, 7)})
	Session.request({"type": "dm_object", "k": "chest", "at": Vector2i(3, 7), "locked": true})
	for o in Session.state.objects:
		if o.k == "crate":
			o.hp = 4
	Session.request({"type": "move", "cid": hero.id, "to": Vector2i(8, 5), "free": true})
	b.control_cid = hero.id
	b._refresh_ui()
	b._center_on(hero.id)
	await _snap("objects_room", 0.8)
	for a in eng.get_actions(hero):
		if a.id == "obj_smash":
			b._on_action_pressed(a)
	await _hover_cell(b, Vector2i(9, 5))
	await _snap("objects_aim", 0.4)
	b._cancel_mode()
	await _hover_cell(b, Vector2i(3, 7))
	await _snap("objects_chest_tip", 0.3)
	# A generated tavern with interactables.
	var tav := MapGenerator.generate({"terrain": "indoor", "interior": "tavern", "seed": 3, "w": 30, "h": 20, "interactables": 1.0, "include_monsters": false})
	Session.request({"type": "dm_load_map", "map": tav})
	b._center_on(hero.id)
	await _snap("objects_tavern", 0.8)
	# An endless forest, after walking east twice.
	var ef := MapGenerator.generate({"terrain": "forest", "seed": 21, "w": 30, "h": 20, "endless": true, "include_monsters": false, "interactables": 0.6})
	Session.request({"type": "dm_load_map", "map": ef})
	for i in 2:
		var tgt := Vector2i(int(Session.state.w) - 3, int(Session.state.h) / 2)
		for r in 6:
			if not Session.engine.blocks_move(tgt):
				break
			tgt += Vector2i(0, 1)
		Session.request({"type": "move", "cid": hero.id, "to": tgt, "free": true})
		await get_tree().create_timer(0.5).timeout
	b.cam.zoom = Vector2.ONE * 0.32
	b.cam.position = Vector2(Session.state.w, Session.state.h) * b.CELL * 0.5
	await _snap("endless_forest", 0.6)
	var town := MapGenerator.generate({"terrain": "town", "seed": 9, "w": 40, "h": 30, "endless": true, "include_monsters": false, "interactables": 0.6})
	Session.request({"type": "dm_load_map", "map": town})
	var tgt2 := Vector2i(int(Session.state.w) - 3, int(Session.state.h) / 2)
	for r in 10:
		if not Session.engine.blocks_move(tgt2):
			break
		tgt2 += Vector2i(0, 1)
	Session.request({"type": "move", "cid": hero.id, "to": tgt2, "free": true})
	await get_tree().create_timer(0.5).timeout
	b.cam.zoom = Vector2.ONE * 0.3
	b.cam.position = Vector2(Session.state.w, Session.state.h) * b.CELL * 0.5
	await _snap("endless_town", 0.6)
	var cave := MapGenerator.generate({"terrain": "cave", "seed": 8, "w": 30, "h": 20, "endless": true, "include_monsters": false, "interactables": 0.6})
	Session.request({"type": "dm_load_map", "map": cave})
	await get_tree().create_timer(0.5).timeout
	b.cam.zoom = Vector2.ONE * 0.35
	b.cam.position = Vector2(Session.state.w, Session.state.h) * b.CELL * 0.5
	await _snap("endless_cave", 0.6)
	Session.leave()
	get_tree().quit()
