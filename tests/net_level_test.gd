extends Node
## Two-process level-up test over ENet. Run one instance with "-- server" and another with "-- client".
## The DM grants a level; the player levels up through the server, the player's own copy is saved with a
## backup, the player restores that backup, and both sides can read each other's party sheets.

const PORT := 7798

func _ready() -> void:
	var role := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "server"
	if role == "server":
		await _server()
	else:
		await _client()
	get_tree().quit()

func _server() -> void:
	Session.host("DM", "LevelTest", PORT, 20, 12)
	Session.add_character(CharacterStore.premades()[4], 1, Vector2i(2, 2))  # a DM-run party member
	for i in 100:
		await get_tree().create_timer(0.1).timeout
		if Session.players.size() > 1:
			break
	var pc := ""
	for c in Session.engine.all_combatants():
		if c.kind == "pc" and int(c.owner) != 1:
			pc = c.id
	print("[server] player character: ", Session.engine.C(pc).get("name", "none"))
	await get_tree().create_timer(0.5).timeout
	Session.request({"type": "dm_grant_level", "cids": [pc]})
	# Wait for the player's level-up, then for their restore.
	var saw_up := false
	var saw_back := false
	for i in 120:
		await get_tree().create_timer(0.1).timeout
		var lv := Rules.total_level(Session.sheets.get(pc, {}))
		if lv == 6:
			saw_up = true
		if saw_up and lv == 5:
			saw_back = true
			break
	print("[server] level up seen: ", saw_up, "  restore seen: ", saw_back, "  pending now: ", Session.pending_levels(pc))
	print("[server] NET LEVEL ", "OK" if saw_up and saw_back and Session.pending_levels(pc) == 1 else "FAIL")
	await get_tree().create_timer(1.0).timeout

func _client() -> void:
	await get_tree().create_timer(0.8).timeout
	var ch: Dictionary = CharacterStore.premades()[2]  # Brannoc, cleric 5
	Session.join("127.0.0.1", PORT, "Alice", ch)
	var mine := ""
	for i in 100:
		await get_tree().create_timer(0.1).timeout
		for c in Session.state.get("combatants", {}).values():
			if c.kind == "pc" and int(c.owner) == Session.my_peer():
				mine = c.id
		if mine != "" and Session.pending_levels(mine) > 0:
			break
	var sheets_seen := Session.sheets.size()
	print("[client] sheets visible: ", sheets_seen, "  pending: ", Session.pending_levels(mine))
	var sid: String = Session.sheets.get(mine, {}).get("id", "")
	var up := Progression.apply_level(Session.sheets[mine], {"class": "cleric", "hp": 6})
	Session.request({"type": "set_sheet", "cid": mine, "sheet": up, "label": "Before level 6 (Cleric 6)"})
	var saved := {}
	for i in 60:
		await get_tree().create_timer(0.1).timeout
		saved = CharacterStore.get_character(sid)
		if not saved.is_empty() and Rules.total_level(saved) == 6:
			break
	var backup_ok: bool = not saved.is_empty() and saved.get("history", []).size() == 1 and int(saved.history[0].level) == 5
	print("[client] local copy level ", Rules.total_level(saved) if not saved.is_empty() else 0, ", backup ok: ", backup_ok)
	# Roll the level back from the local history.
	var back := Progression.restore(saved, 0)
	Session.request({"type": "set_sheet", "cid": mine, "sheet": Progression.strip_history(back), "label": "Before restoring \"Before level 6 (Cleric 6)\""})
	for i in 60:
		await get_tree().create_timer(0.1).timeout
		if Rules.total_level(Session.sheets.get(mine, {})) == 5:
			break
	var after := CharacterStore.get_character(sid)
	var ok: bool = sheets_seen >= 2 and backup_ok and Rules.total_level(Session.sheets[mine]) == 5 and after.get("history", []).size() == 2
	print("[client] NET LEVEL ", "OK" if ok else "FAIL", "  (history %d)" % after.get("history", []).size())
	CharacterStore.delete_character(sid)
	await get_tree().create_timer(0.5).timeout
