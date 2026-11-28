extends Node
## Screenshots of the inventory: the builder's Inventory tab, and in a game a character's inventory window,
## the shop (buy and sell) and the DM's Loot tab. Into the folder given as the first user arg.
## Needs a real window: Godot --path . res://tests/inventory_shots.tscn -- <folder>

var out := ""

func _snap(name: String, wait := 0.3) -> void:
	if wait > 0.0:
		await get_tree().create_timer(wait).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/" + name + ".png")
	print("shot ", name)

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0] if args.size() > 0 else "user://"
	get_window().size = Vector2i(1600, 900)
	# The builder.
	var ce = load("res://scenes/characters.tscn").instantiate()
	add_child(ce)
	await get_tree().create_timer(0.3).timeout
	ce.ch = CharacterStore.premades()[3].duplicate(true)
	Inventory.add(ce.ch, "weapon_plus_1", 1, {"base": "greatsword", "eq": true})
	Inventory.add(ce.ch, "cloak_of_protection", 1, {"eq": true, "att": true})
	Inventory.add(ce.ch, "bag_of_holding", 1)
	Inventory.add(ce.ch, "potion_healing", 3)
	ce._ensure_fields()
	ce._rebuild()
	for t in ce.tabs.get_tab_count():
		if ce.tabs.get_tab_title(t) == "Inventory":
			ce.tabs.current_tab = t
	await _snap("builder_inventory")
	var sc: ScrollContainer = ce.tabs.get_current_tab_control()
	sc.scroll_vertical = 100000
	await _snap("builder_shop")
	ce.queue_free()
	# A game.
	Session.start_offline("Tester", 24, 16)
	var y := 4
	var first := ""
	for ch in CharacterStore.premades().slice(2, 5):
		var cid: String = Session.add_character(ch, 1, Vector2i(7, y))
		if first == "":
			first = cid
		y += 2
	var c: Dictionary = Session.engine.C(first)
	Inventory.add(c, "wand_of_magic_missiles", 1)
	Inventory.add(c, "potion_greater_healing", 2)
	Inventory.add(c, "alchemists_fire", 2)
	Inventory.add(c, "spell_scroll_1", 1, {"spell": "cure_wounds"})
	Session.request({"type": "dm_give", "cids": [first], "id": "ring_of_protection", "qty": 1})
	var b = load("res://scenes/battle.tscn").instantiate()
	add_child(b)
	await get_tree().create_timer(0.5).timeout
	b.control_cid = first
	b._refresh_ui()
	b._open_inventory(first)
	await _snap("game_inventory", 0.5)
	b.inv_win.close()
	Session.request({"type": "dm_shop", "open": true, "kind": "general", "name": "The Rusty Lantern"})
	await get_tree().create_timer(0.2).timeout
	b._refresh_ui()
	await _snap("game_card_shop")
	b._open_shop(first)
	await _snap("game_shop_buy", 0.5)
	b.shop_panel._mode = "sell"
	b.shop_panel.refresh()
	await _snap("game_shop_sell")
	b.shop_win.close()
	for t in b.dm_tabs.get_tab_count():
		if b.dm_tabs.get_tab_title(t) == "Loot":
			b.dm_tabs.current_tab = t
	await _snap("game_dm_loot")
	# Hotbar with item actions.
	b.hot_cat = "basic"
	b._refresh_hotbar()
	await _snap("game_hotbar_items")
	get_tree().quit()
