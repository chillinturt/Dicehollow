extends Node
## Two-process network test. Run one instance with "-- server" and another with "-- client".

func _ready() -> void:
	var role := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "server"
	Session.state_changed.connect(func(ev): for e in ev: if e.get("t", "") == "log": print("[%s] %s" % [role, str(e.text).replace("[b]", "").replace("[/b]", "")]))
	if role == "server":
		Session.host("DM", "NetTest", 7799, 20, 12)
		Session.add_monster("goblin", Vector2i(12, 5))
		Session.add_monster("goblin", Vector2i(13, 7))
		# Wait for a player to register.
		for i in 100:
			await get_tree().create_timer(0.1).timeout
			if Session.players.size() > 1:
				break
		print("[server] players: ", Session.players)
		Session.request({"type": "dm_start_combat"})
		await get_tree().create_timer(8.0).timeout
		print("[server] combatants: ", Session.state.combatants.values().map(func(c): return "%s hp=%d owner=%d" % [c.name, c.hp, c.owner]))
	elif role == "client_old":
		# A player on another release is turned away with a clear message.
		var why := [""]
		Session.session_ended.connect(func(r): why[0] = r)
		Session.VERSION = "0.0.1"
		await get_tree().create_timer(0.8).timeout
		Session.join("127.0.0.1", 7799, "Oldie", CharacterStore.premades()[0])
		for i in 50:
			await get_tree().create_timer(0.1).timeout
			if why[0] != "":
				break
		print("[client_old] ", "KICKED OK: " + why[0] if why[0].contains("Version mismatch") else "NOT KICKED")
	else:
		await get_tree().create_timer(0.8).timeout
		var ch: Dictionary = CharacterStore.premades()[3]
		Session.join("127.0.0.1", 7799, "Alice", ch)
		for i in 90:
			await get_tree().create_timer(0.1).timeout
			if not Session.state.in_combat:
				continue
			var cur := Session.engine.current()
			if int(cur.get("owner", 0)) == Session.my_peer():
				print("[client] my turn as %s, requesting auto turn" % cur.name)
				Session.request({"type": "ai_turn", "cid": cur.id})
				await get_tree().create_timer(1.0).timeout
		print("[client] I see %d combatants, round %d" % [Session.state.combatants.size(), Session.state.round])
	get_tree().quit()
