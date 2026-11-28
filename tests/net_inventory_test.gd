extends Node
## Two-process inventory test over ENet. Run one instance with "-- server" and another with "-- client".
## The DM opens a shop and puts a chest beside the player's character; the player buys a bullseye lantern
## and loots the chest, and the purchase and the loot end up in the player's own saved copy of the character.

const PORT := 7797
const CHAR_ID := "net_inventory_test_char"

func _ready() -> void:
	var role := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "server"
	if role == "server":
		await _server()
	else:
		await _client()
	get_tree().quit()

func _server() -> void:
	Session.host("DM", "InventoryTest", PORT, 20, 12)
	for i in 100:
		await get_tree().create_timer(0.1).timeout
		if Session.players.size() > 1:
			break
	var pc: Dictionary = {}
	for c in Session.engine.all_combatants():
		if c.kind == "pc" and int(c.owner) != 1:
			pc = c
	print("[server] player character: ", pc.get("name", "none"))
	await get_tree().create_timer(0.3).timeout
	Session.request({"type": "dm_shop", "open": true, "kind": "general", "name": "Test Store"})
	var cell: Vector2i = pc.pos + Vector2i(1, 0)
	MapObjects.place(Session.engine, MapObjects.make("chest", cell, EngineBase.FLOOR, {"loot": {"gp": 123, "gear": [{"id": "wand_of_magic_missiles", "qty": 1, "charges": 7}]}}))
	Session._broadcast([])
	var ok := false
	for i in 150:
		await get_tree().create_timer(0.1).timeout
		var sh: Dictionary = Session.sheets.get(pc.id, {})
		if Inventory.count(sh, "lantern_bullseye") >= 1 and Inventory.count(sh, "wand_of_magic_missiles") == 1:
			ok = true
			break
	# Part two: the DM hands out a cloak and stocks one potion; the player swaps weapons, asks to attune
	# (queued for a rest) and buys the potion; the DM's short rest completes the attunement.
	Session.request({"type": "dm_give", "cids": [pc.id], "id": "cloak_of_protection", "qty": 1})
	Session.request({"type": "dm_shop_stock", "op": "add", "id": "potion_healing", "qty": 1})
	var queued := false
	for i in 150:
		await get_tree().create_timer(0.1).timeout
		var sh: Dictionary = Session.sheets.get(pc.id, {})
		if Inventory.queued(sh).size() == 1:
			queued = true
			break
	print("[server] attunement queued: ", queued)
	Session.request({"type": "dm_short_rest"})
	var ok2 := false
	for i in 150:
		await get_tree().create_timer(0.1).timeout
		var sh: Dictionary = Session.sheets.get(pc.id, {})
		var cl := Inventory.list(sh).filter(func(e): return str(e.id) == "cloak_of_protection")
		var jav := Inventory.held(sh).any(func(e): return str(e.id) == "javelin")
		if queued and not cl.is_empty() and cl[0].get("att", false) and jav and Inventory.count(sh, "potion_healing") >= 1 and not "potion_healing" in Session.shop().get("stock", []):
			ok2 = true
			break
	# Part three: the player stores the lantern in the chest they opened (an opened chest is storage).
	var ok3 := false
	for i in 150:
		await get_tree().create_timer(0.1).timeout
		var ch: Dictionary = MapObjects.at(Session.state, cell)[0] if not MapObjects.at(Session.state, cell).is_empty() else {}
		if not ch.is_empty() and ch.get("store", null) is Dictionary and Inventory.count(ch.store, "lantern_bullseye") == 1 and Inventory.count(Session.sheets.get(pc.id, {}), "lantern_bullseye") == 0:
			ok3 = true
			break
	print("[server] lantern stored in the chest: ", ok3)
	print("[server] NET INVENTORY ", "OK" if ok and ok2 and ok3 else "FAIL")
	await get_tree().create_timer(1.5).timeout

func _client() -> void:
	await get_tree().create_timer(0.8).timeout
	var ch: Dictionary = CharacterStore.premades()[3].duplicate(true)  # Grukka
	ch.id = CHAR_ID
	ch.coins = {"gp": 50}
	CharacterStore.save_character(ch)
	Session.join("127.0.0.1", PORT, "Alice", CharacterStore.get_character(CHAR_ID))
	var mine := ""
	for i in 100:
		await get_tree().create_timer(0.1).timeout
		for c in Session.state.get("combatants", {}).values():
			if c.kind == "pc" and int(c.owner) == Session.my_peer():
				mine = c.id
		if mine != "" and not Session.shop().is_empty() and not MapObjects.list(Session.state).is_empty():
			break
	print("[client] shop open: ", not Session.shop().is_empty())
	Session.request({"type": "inv", "cid": mine, "op": "buy", "id": "lantern_bullseye", "qty": 1})
	await get_tree().create_timer(0.4).timeout
	var chest: Dictionary = MapObjects.list(Session.state)[0]
	Session.request({"type": "action", "cid": mine, "aid": "obj_open", "params": {"cell": chest.pos}})
	var saved := {}
	for i in 60:
		await get_tree().create_timer(0.1).timeout
		saved = CharacterStore.get_character(CHAR_ID)
		if Inventory.count(saved, "wand_of_magic_missiles") == 1 and Inventory.count(saved, "lantern_bullseye") >= 1:
			break
	var ok: bool = Inventory.count(saved, "wand_of_magic_missiles") == 1 and Inventory.count(saved, "lantern_bullseye") >= 1 and int(saved.get("coins", {}).get("gp", 0)) == 50 - 10 + 123
	print("[client] saved copy: gp %d, lantern %d, wand %d" % [int(saved.get("coins", {}).get("gp", 0)), Inventory.count(saved, "lantern_bullseye"), Inventory.count(saved, "wand_of_magic_missiles")])
	# Part two: swap to the javelin, attune to the DM's cloak (waits for a rest), buy the shop's one potion.
	Session.request({"type": "inv", "cid": mine, "op": "swap"})
	var cloak := ""
	for i in 100:
		await get_tree().create_timer(0.1).timeout
		var me: Dictionary = Session.state.combatants.get(mine, {})
		for e in me.get("inventory", []):
			if str(e.id) == "cloak_of_protection":
				cloak = str(e.uid)
		if cloak != "" and "potion_healing" in Session.shop().get("stock", []):
			break
	Session.request({"type": "inv", "cid": mine, "op": "equip", "uid": cloak, "on": true})
	Session.request({"type": "inv", "cid": mine, "op": "attune", "uid": cloak, "on": true})
	Session.request({"type": "inv", "cid": mine, "op": "buy", "id": "potion_healing", "qty": 1})
	var ok2 := false
	for i in 120:
		await get_tree().create_timer(0.1).timeout
		saved = CharacterStore.get_character(CHAR_ID)
		var cl := Inventory.list(saved).filter(func(e): return str(e.id) == "cloak_of_protection")
		if not cl.is_empty() and cl[0].get("att", false) and Inventory.held(saved).any(func(e): return str(e.id) == "javelin") and Inventory.count(saved, "potion_healing") >= 1:
			ok2 = true
			break
	print("[client] saved copy after the rest: cloak attuned and javelin in hand: ", ok2, "; shop sold out: ", not "potion_healing" in Session.shop().get("stock", []))
	# Part three: store the lantern in the opened chest beside us.
	var lantern := ""
	for e in Session.state.combatants[mine].get("inventory", []):
		if str(e.id) == "lantern_bullseye":
			lantern = str(e.uid)
	Session.request({"type": "stash", "cid": mine, "obj": str(chest.id), "op": "put", "uid": lantern, "qty": 0})
	var ok3 := false
	for i in 100:
		await get_tree().create_timer(0.1).timeout
		saved = CharacterStore.get_character(CHAR_ID)
		var sc := MapObjects.by_id(Session.state, str(chest.id))
		if Inventory.count(saved, "lantern_bullseye") == 0 and sc.get("store", null) is Dictionary and Inventory.count(sc.store, "lantern_bullseye") == 1:
			ok3 = true
			break
	print("[client] lantern stored, saved copy without it: ", ok3)
	print("[client] NET INVENTORY ", "OK" if ok and ok2 and ok3 else "FAIL")
	CharacterStore.delete_character(CHAR_ID)
	await get_tree().create_timer(0.5).timeout
