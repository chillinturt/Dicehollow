extends Node
## Screenshots of generated structures: the generator window on a town, then towns in each style, an indoor
## tavern and a swamp with stilt cabins on the battle map, into the folder given as the first user arg.
## Needs a real window: Godot --path . res://tests/structure_shots.tscn -- <folder>

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
	Session.auto_monsters = false
	var b = load("res://scenes/battle.tscn").instantiate()
	add_child(b)
	await get_tree().process_frame
	b._open_map_generator()
	await get_tree().process_frame
	var gen: MapGeneratorPanel = null
	for ch in b.ui.get_children():
		if ch is MapGeneratorPanel:
			gen = ch
	gen.settings.w = 44
	gen.settings.h = 30
	gen.settings.seed = 9
	gen._set_terrain("town")
	gen._find_tabs().current_tab = 1
	await _snap("gen_town_window")
	gen.close()
	var maps := [
		["town_human", {"terrain": "town", "style": "human", "seed": 9, "w": 44, "h": 30}],
		["town_dwarf", {"terrain": "town", "style": "dwarf", "seed": 9, "w": 44, "h": 30}],
		["town_elf", {"terrain": "town", "style": "elf", "seed": 9, "w": 44, "h": 30}],
		["tavern_indoor", {"terrain": "indoor", "interior": "tavern", "seed": 4, "w": 30, "h": 20}],
		["swamp_cabins", {"terrain": "swamp", "structures": "cabins", "structure_count": 3, "seed": 5, "w": 30, "h": 20}],
		["forest_inn", {"terrain": "forest", "structures": "inn", "seed": 5, "w": 30, "h": 20}],
	]
	for e in maps:
		var st: Dictionary = e[1]
		st.include_monsters = false
		var m := MapGenerator.generate(st)
		m.erase("report")
		Session.request({"type": "dm_load_map", "map": m})
		await get_tree().process_frame
		b.cam.position = Vector2(m.w, m.h) * 32 + Vector2(160, 40)
		b.cam.zoom = Vector2.ONE * (0.42 if m.w > 40 else 0.62)
		await _snap(e[0])
	# A close look at the tavern furniture.
	var tv := MapGenerator.generate({"terrain": "indoor", "interior": "tavern", "seed": 4, "w": 30, "h": 20, "include_monsters": false})
	tv.erase("report")
	Session.request({"type": "dm_load_map", "map": tv})
	b.cam.position = Vector2(10, 10) * 64
	b.cam.zoom = Vector2.ONE * 1.1
	await _snap("tavern_close")
	get_tree().quit()
