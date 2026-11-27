extends Node
## Networking and the authoritative game state. The DM hosts (server, peer 1); players join over ENet.
## Every request goes through `request()`; the server validates it, runs the CombatEngine and broadcasts
## the whole state plus a list of visual events to every peer.

signal state_changed(events: Array)
signal players_changed
signal chat_received(text: String)
signal status(text: String)
signal portrait_arrived(key: String)
signal bg_arrived(key: String)
signal session_ended(reason: String)

const DEFAULT_PORT := 7777
const AI_DELAY := 0.7

var role := ""            # "dm", "player" or "" (not in a game)
var my_name := ""
var game_name := ""
var state: Dictionary = {}
var engine: CombatEngine
var ai: CombatAI
var players := {}         # peer_id -> {"name", "cids": []}
var auto_monsters := true
var _ai_busy := false
var _pending_character: Dictionary = {}

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_set_state(EngineBase.new_state(24, 16))

func _on_connection_failed() -> void:
	status.emit("Connection failed.")
	_reset()

func _on_server_disconnected() -> void:
	session_ended.emit("The DM closed the game.")
	_reset()

func _set_state(st: Dictionary) -> void:
	state = st
	engine = CombatEngine.new(state)
	ai = CombatAI.new(engine)

func my_peer() -> int:
	return multiplayer.get_unique_id()

func is_server() -> bool:
	return multiplayer.is_server()

func is_dm() -> bool:
	return role == "dm"

# ================================================================ lifecycle

func host(dm_name: String, gname: String, port := DEFAULT_PORT, map_w := 24, map_h := 16) -> Error:
	var peer = ENetMultiplayerPeer.new()
	var err = peer.create_server(port, 12)
	if err != OK:
		status.emit("Could not host on port %d (error %d)." % [port, err])
		return err
	multiplayer.multiplayer_peer = peer
	role = "dm"
	my_name = dm_name
	game_name = gname
	players = {1: {"name": dm_name + " (DM)", "cids": []}}
	_set_state(EngineBase.new_state(map_w, map_h))
	state.name = gname
	_default_spawns()
	status.emit("Hosting \"%s\" on port %d. Players can join with your IP address." % [gname, port])
	return OK

func start_offline(dm_name: String, map_w := 24, map_h := 16) -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	role = "dm"
	my_name = dm_name
	game_name = "Solo Session"
	players = {1: {"name": dm_name + " (DM)", "cids": []}}
	_set_state(EngineBase.new_state(map_w, map_h))
	state.name = game_name
	_default_spawns()

func join(ip: String, port: int, player_name: String, character: Dictionary) -> Error:
	var peer = ENetMultiplayerPeer.new()
	var err = peer.create_client(ip, port)
	if err != OK:
		status.emit("Could not connect (error %d)." % err)
		return err
	multiplayer.multiplayer_peer = peer
	role = "player"
	my_name = player_name
	_pending_character = character
	status.emit("Connecting to %s:%d…" % [ip, port])
	return OK

func leave() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	_reset()

func _reset() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	role = ""
	players = {}
	_set_state(EngineBase.new_state(24, 16))

func _default_spawns() -> void:
	var sp: Array = []
	for i in 6:
		sp.append(Vector2i(2 + (i % 2), 4 + i))
	state.spawns = sp

func _on_connected() -> void:
	status.emit("Connected! Sending your character…")
	var ch = _pending_character
	var key: String = ch.get("portrait", "")
	_rpc_register.rpc_id(1, my_name, ch, CharacterStore.get_portrait_bytes(key))

func _on_peer_connected(id: int) -> void:
	if is_server():
		# Send existing portraits & state to the newcomer.
		for k in CharacterStore.portrait_bytes:
			_rpc_portrait.rpc_id(id, k, CharacterStore.portrait_bytes[k])
		if state.get("bg", "") != "":
			_rpc_bg.rpc_id(id, state.bg, CharacterStore.get_bg_bytes(state.bg))
		_rpc_state.rpc_id(id, state, [])
		_rpc_players.rpc_id(id, players)

func _on_peer_disconnected(id: int) -> void:
	if not is_server():
		return
	var name: String = players.get(id, {}).get("name", "A player")
	for c in engine.all_combatants():
		if c.owner == id:
			c.owner = 1
	players.erase(id)
	engine.log_line("%s left the game. The DM now controls their character." % name)
	_broadcast([])
	_rpc_players.rpc(players)
	players_changed.emit()

# ================================================================ rpc plumbing

@rpc("any_peer", "reliable")
func _rpc_register(player_name: String, ch: Dictionary, portrait: PackedByteArray) -> void:
	if not is_server():
		return
	var peer = multiplayer.get_remote_sender_id()
	var key: String = ch.get("portrait", "")
	if key != "" and not portrait.is_empty():
		CharacterStore.register_portrait(key, portrait)
		_rpc_portrait.rpc(key, portrait)
	players[peer] = {"name": player_name, "cids": []}
	if not ch.is_empty():
		var cid = add_character(ch, peer)
		players[peer].cids.append(cid)
		engine.log_line("[color=#8fd0ff]%s joined as %s.[/color]" % [player_name, ch.get("name", "?")])
	_rpc_players.rpc(players)
	players_changed.emit()
	_broadcast([])

@rpc("authority", "reliable")
func _rpc_state(st: Dictionary, events: Array) -> void:
	_set_state(st)
	state_changed.emit(events)

@rpc("authority", "reliable")
func _rpc_players(p: Dictionary) -> void:
	players = p
	players_changed.emit()

@rpc("authority", "reliable")
func _rpc_portrait(key: String, bytes: PackedByteArray) -> void:
	CharacterStore.register_portrait(key, bytes)
	portrait_arrived.emit(key)

@rpc("authority", "reliable")
func _rpc_bg(key: String, bytes: PackedByteArray) -> void:
	CharacterStore.register_bg(key, bytes)
	bg_arrived.emit(key)

@rpc("any_peer", "reliable")
func _rpc_request(req: Dictionary) -> void:
	if is_server():
		_handle(multiplayer.get_remote_sender_id(), req)

@rpc("any_peer", "call_local", "reliable")
func _rpc_chat(text: String) -> void:
	chat_received.emit(text)

func send_chat(text: String) -> void:
	text = text.strip_edges()
	if text == "":
		return
	var out = "[b]%s:[/b] %s" % [my_name, text.replace("[", "(")]
	if text.begins_with("/roll ") or text.begins_with("/r "):
		var expr = text.split(" ", false, 1)[1] if text.split(" ", false).size() > 1 else "1d20"
		var r = Dice.roll(expr)
		out = "[b]%s[/b] rolls %s: %s = [b][color=#ffd166]%d[/color][/b]" % [my_name, expr, str(r.rolls), r.total]
	_rpc_chat.rpc(out)

func _broadcast(events: Array) -> void:
	if not is_server():
		return
	# Movement left is derived from speed; refresh the cached number before clients see it
	# (a DM-applied condition or a reaction may have changed the mover's speed).
	if state.in_combat:
		engine.sync_move(engine.current())
	state_changed.emit(events)
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		_rpc_state.rpc(state, events)

## Everything the UI wants to do goes through here.
func request(req: Dictionary) -> void:
	if is_server():
		_handle(1, req)
	else:
		_rpc_request.rpc_id(1, req)

# ================================================================ server logic

func can_control(peer: int, c: Dictionary) -> bool:
	return not c.is_empty() and (peer == 1 or int(c.owner) == peer)

func add_character(ch: Dictionary, owner: int, at = null) -> String:
	var cid = engine.new_id("p")
	var c = CombatantFactory.from_character(cid, ch, owner)
	c.pos = at if at is Vector2i else _spawn_cell()
	state.combatants[cid] = c
	if state.in_combat:
		_join_initiative(c)
	return cid

func add_monster(mid: String, at: Vector2i) -> String:
	var cid = engine.new_id("m")
	var c = CombatantFactory.from_monster(cid, mid)
	c.pos = at
	# Number duplicates: "Goblin 2".
	var n = 0
	for o in engine.all_combatants():
		if o.get("monster_id", "") == mid:
			n += 1
	if n > 0:
		c.name = "%s %d" % [c.name, n + 1]
	state.combatants[cid] = c
	if state.in_combat:
		_join_initiative(c)
	return cid

func _join_initiative(c: Dictionary) -> void:
	c.turn = engine.new_turn(c)
	c.init = Dice.d20() + int(c.init_bonus)
	var idx: int = state.order.size()
	for i in state.order.size():
		if int(engine.C(state.order[i]).get("init", 0)) < c.init:
			idx = i
			break
	state.order.insert(idx, c.id)
	if idx <= state.turn:
		state.turn += 1
	engine.log_line("%s joins the fight (initiative %d)." % [engine.nm(c), c.init])

func _spawn_cell() -> Vector2i:
	for p in state.get("spawns", []):
		if engine.creature_at(p).is_empty() and not engine.blocks_move(p):
			return p
	return engine._free_cell_near(Vector2i(2, 2))

func _handle(peer: int, req: Dictionary) -> void:
	engine.events = []
	var dm = peer == 1
	var typ: String = req.get("type", "")
	var c = engine.C(req.get("cid", ""))
	match typ:
		"move":
			if can_control(peer, c):
				var free: bool = dm and (not state.in_combat or req.get("free", false))
				if state.in_combat and not free and not engine.is_turn_of(c):
					return
				engine.move(c, req.to, free)
		"action":
			if can_control(peer, c):
				# A player acting for themselves is asked about on-hit choices (Divine Smite...).
				engine.interactive = not _should_auto(c)
				engine.execute(c.id, req.aid, req.get("params", {}))
				engine.interactive = false
		"end_turn":
			var cur = engine.current()
			if can_control(peer, cur):
				engine.end_turn()
		"ai_turn":
			if dm or can_control(peer, c):
				_run_ai_now()
				return
		"set_ai":
			if can_control(peer, c):
				c.ai = req.get("on", false)
		# ---------------- DM tools
		"dm_place_monster":
			if dm: add_monster(req.mid, req.at)
		"dm_place_character":
			if dm: add_character(req.ch, 1, req.get("at", null))
		"dm_remove":
			if dm and not c.is_empty():
				state.combatants.erase(c.id)
				var idx: int = state.order.find(c.id)
				if idx >= 0:
					state.order.remove_at(idx)
					if idx < state.turn:
						state.turn -= 1
					elif idx == state.turn and state.in_combat:
						state.turn -= 1
						engine._advance()
		"dm_cells":
			if dm:
				for p in req.cells:
					engine.set_cell(p, int(req.value))
		"dm_spawn":
			if dm:
				var sp: Array = state.spawns
				if req.at in sp: sp.erase(req.at)
				else: sp.append(req.at)
		"dm_hp":
			if dm and not c.is_empty():
				var amt: int = req.amount
				if amt < 0:
					engine.apply_damage(c, [{"amount": -amt, "type": req.get("dtype", "force")}], {}, {"magic": true})
				else:
					engine.heal_creature(c, amt, {}, "DM")
		"dm_condition":
			if dm and not c.is_empty():
				var cond: String = req.cond
				if engine.has_cond(c, cond):
					engine.remove_effects_where(c, func(e): return e.get("cond", "") == cond)
					engine.log_line("DM removes %s from %s." % [cond, c.name])
				else:
					engine.add_effect(c, {"name": cond.capitalize(), "cond": cond, "src": "dm", "rounds": 9999, "tick_cid": "none"})
		"dm_team":
			if dm and not c.is_empty():
				c.team = "party" if c.team != "party" else "enemy"
		"dm_owner":
			if dm and not c.is_empty():
				c.owner = int(req.owner)
		"dm_start_combat":
			if dm: engine.start_combat()
		"dm_end_combat":
			if dm and state.in_combat: engine.end_combat()
		"dm_next_turn":
			if dm and state.in_combat: engine.end_turn()
		"dm_short_rest":
			if dm: engine.short_rest()
		"dm_long_rest":
			if dm: engine.long_rest()
		"dm_auto_monsters":
			if dm: auto_monsters = req.on
		"dm_clear_dead":
			if dm:
				for o in engine.all_combatants():
					if o.dead:
						state.combatants.erase(o.id)
						state.order.erase(o.id)
		"dm_resize":
			if dm: _resize(int(req.w), int(req.h))
		"dm_load_map":
			if dm: _load_map(req.map)
		"dm_clear_map":
			if dm:
				state.cells.fill(EngineBase.FLOOR)
		"dm_theme":
			if dm: state.theme = req.theme
		"dm_background":
			if dm: _set_background(str(req.get("key", "")), req.get("fit", false))
	_check_victory()
	_broadcast(engine.events)
	_maybe_run_ai()

func _check_victory() -> void:
	var side = engine.side_defeated()
	if side == "enemy":
		engine.log_line("[color=#7fdc7f][b]Victory! All enemies are defeated.[/b][/color]")
		engine.end_combat()
	elif side == "party":
		engine.log_line("[color=#ff5050][b]The party has fallen…[/b][/color]")
		engine.end_combat()

func _should_auto(c: Dictionary) -> bool:
	if c.is_empty():
		return false
	if c.get("ai", false):
		return true
	if c.kind == "pc" and (c.hp <= 0 or engine.is_incapacitated(c)):
		return true
	if c.kind != "pc" and engine.is_incapacitated(c):
		return true
	return auto_monsters and int(c.owner) == 1 and c.team != "party"

func _maybe_run_ai() -> void:
	if not is_server() or _ai_busy or not state.in_combat:
		return
	var cur = engine.current()
	if not _should_auto(cur):
		return
	_ai_busy = true
	await get_tree().create_timer(AI_DELAY).timeout
	_ai_busy = false
	if state.in_combat and engine.current().get("id", "") == cur.id:
		_run_ai_now()

func _run_ai_now() -> void:
	var cur = engine.current()
	if cur.is_empty():
		return
	engine.events = []
	ai.run_turn(cur)
	_check_victory()
	if state.in_combat and engine.current().get("id", "") == cur.id:
		engine.end_turn()
	_check_victory()
	_broadcast(engine.events)
	_maybe_run_ai()

## Set (or clear, with "") the map's background image and push its bytes to every player.
func _set_background(key: String, fit := false) -> void:
	if key != "" and CharacterStore.bg_texture(key) == null:
		status.emit("That image could not be loaded.")
		return
	state.bg = key
	if key == "":
		return
	_send_bg(key)
	if fit:
		var sz = CharacterStore.bg_texture(key).get_size()
		_resize(state.w, roundi(state.w * sz.y / sz.x))

func _send_bg(key: String) -> void:
	if key != "" and multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		_rpc_bg.rpc(key, CharacterStore.get_bg_bytes(key))

func _resize(w: int, h: int) -> void:
	w = clampi(w, 8, 80)
	h = clampi(h, 8, 60)
	var cells = PackedByteArray()
	cells.resize(w * h)
	cells.fill(EngineBase.FLOOR)
	for y in mini(h, state.h):
		for x in mini(w, state.w):
			cells[y * w + x] = state.cells[y * state.w + x]
	state.w = w
	state.h = h
	state.cells = cells

func map_snapshot() -> Dictionary:
	var mons: Array = []
	for c in engine.all_combatants():
		if c.kind == "monster" and not c.dead:
			mons.append({"mid": c.monster_id, "x": c.pos.x, "y": c.pos.y, "team": c.team})
	var spawns: Array = []
	for p in state.spawns:
		spawns.append([p.x, p.y])
	var custom := {}
	for m in mons:
		if Data.custom_monsters.has(m.mid):
			custom[m.mid] = Data.custom_monsters[m.mid]
	return {"name": state.name, "w": state.w, "h": state.h, "cells": Array(state.cells), "monsters": mons, "spawns": spawns, "theme": state.get("theme", "stone"), "bg": state.get("bg", ""), "custom_monsters": custom}

func _load_map(m: Dictionary) -> void:
	if state.in_combat:
		engine.end_combat()
	var w = int(m.get("w", 24))
	var h = int(m.get("h", 16))
	state.w = w
	state.h = h
	state.cells = PackedByteArray(m.get("cells", []))
	if state.cells.size() != w * h:
		state.cells.resize(w * h)
	state.theme = m.get("theme", "stone")
	for mid in m.get("custom_monsters", {}):
		if not Data.monsters.has(mid):
			CharacterStore.save_custom_monster(m.custom_monsters[mid])
	state.bg = str(m.get("bg", ""))
	if state.bg != "" and CharacterStore.bg_texture(state.bg) == null:
		state.bg = ""
	_send_bg(state.bg)
	state.name = m.get("name", state.name)
	for c in engine.all_combatants():
		if c.kind != "pc":
			state.combatants.erase(c.id)
	state.zones = []
	state.items = []
	# Open Rope Tricks belong to the old map: whoever was inside is back on the ground.
	for c in engine.all_combatants():
		engine.remove_effects_where(c, func(e): return e.get("tag", "") == "rope_trick")
	state.ropes = []
	var sp: Array = []
	for p in m.get("spawns", []):
		sp.append(Vector2i(int(p[0]), int(p[1])))
	state.spawns = sp
	for mon in m.get("monsters", []):
		var cid = add_monster(mon.mid, Vector2i(int(mon.x), int(mon.y)))
		state.combatants[cid].team = mon.get("team", "enemy")
	var i = 0
	for c in engine.all_combatants():
		if c.kind == "pc" and i < sp.size():
			c.pos = sp[i]
			i += 1
	engine.log_line("Map \"%s\" loaded." % state.name)
