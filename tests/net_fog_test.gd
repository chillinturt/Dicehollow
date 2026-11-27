extends Node
## Two-process fog-of-war test over ENet. Run one instance with "-- server" and another with "-- client".
## A wall splits the map; the DM's party member and a goblin are on the far side. With vision not
## shared the player can't see the goblin; once the DM shares vision, they can.

const PORT := 7797

func _ready() -> void:
	var role := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "server"
	if role == "server":
		await _server()
	else:
		await _client()
	get_tree().quit()

func _server() -> void:
	Session.host("DM", "FogTest", PORT, 20, 12)
	for y in 12:
		Session.engine.set_cell(Vector2i(8, y), EngineBase.WALL)
	Session.add_character(CharacterStore.premades()[4], 1, Vector2i(12, 2))   # the DM's party member
	Session.add_monster("goblin", Vector2i(15, 6))
	for i in 100:
		await get_tree().create_timer(0.1).timeout
		if Session.players.size() > 1:
			break
	Session.request({"type": "dm_fog", "mode": "hard", "shared": false})
	await get_tree().create_timer(1.5).timeout
	Session.request({"type": "dm_fog", "shared": true})
	await get_tree().create_timer(2.5).timeout
	print("[server] done")

func _client() -> void:
	await get_tree().create_timer(0.5).timeout
	Session.join("127.0.0.1", PORT, "Player", CharacterStore.premades()[0])
	var fails := 0
	var phase := 0
	for i in 60:
		await get_tree().create_timer(0.1).timeout
		var f := Fog.settings(Session.state)
		if f.mode == "hard" and not f.shared and phase == 0:
			var gob: Dictionary = Session.engine.all_combatants().filter(func(c): return c.kind == "monster")[0]
			var v := Fog.view_for(Session.engine, Session.my_peer())
			var ok_hidden := not Fog.sees(v, Session.engine, gob)
			var ok_seen: bool = Session.state.get("fog_seen", {}).values().all(func(m): return m is PackedByteArray)
			print("[client] exclusive: goblin hidden=%s, memories arrive as byte masks=%s" % [ok_hidden, ok_seen])
			fails += int(not ok_hidden) + int(not ok_seen)
			phase = 1
		elif f.mode == "hard" and f.shared and phase == 1:
			var gob2: Dictionary = Session.engine.all_combatants().filter(func(c): return c.kind == "monster")[0]
			var ok_shared := Fog.sees(Fog.view_for(Session.engine, Session.my_peer()), Session.engine, gob2)
			print("[client] shared: goblin seen through the DM's character=%s" % ok_shared)
			fails += int(not ok_shared)
			phase = 2
			break
	if phase < 2:
		fails += 1
		print("[client] never saw both fog settings (phase %d)" % phase)
	print("NET FOG DONE failed=%d" % fails)
	Session.leave()
