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
## Players must run the same build as the DM: the state format and RPCs change between releases.
var VERSION: String = str(ProjectSettings.get_setting("application/config/version", "dev"))

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
var last_end_reason := ""  # why the last game ended (shown on the main menu)

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
	_rpc_register.rpc_id(1, my_name, ch, CharacterStore.get_portrait_bytes(key), VERSION)

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
			c.orphan = true  # handed back if the same character reconnects
	players.erase(id)
	engine.log_line("%s left the game. The DM now controls their character." % name)
	_broadcast([])
	_rpc_players.rpc(players)
	players_changed.emit()

# ================================================================ rpc plumbing

@rpc("any_peer", "reliable")
func _rpc_register(player_name: String, ch: Dictionary, portrait: PackedByteArray, version := "") -> void:
	if not is_server():
		return
	var peer = multiplayer.get_remote_sender_id()
	if version != VERSION:
		_rpc_kicked.rpc_id(peer, "Version mismatch: the DM runs Dicehollow %s but you run %s. Download the same release as the DM." % [VERSION, version if version != "" else "an older build"])
		engine.log_line("[color=#ff9c8f]%s tried to join with Dicehollow %s (you run %s) and was turned away.[/color]" % [player_name, version if version != "" else "an older build", VERSION])
		_broadcast([])
		_disconnect_later(peer)
		return
	var key: String = ch.get("portrait", "")
	if key != "" and not portrait.is_empty():
		CharacterStore.register_portrait(key, portrait)
		_rpc_portrait.rpc(key, portrait)
	players[peer] = {"name": player_name, "cids": []}
	if not ch.is_empty():
		# Reconnecting after a dropped connection: take the old token back instead of adding a twin.
		var back := _orphan_for(ch)
		if not back.is_empty():
			back.owner = peer
			players[peer].cids.append(back.id)
			engine.log_line("[color=#8fd0ff]%s rejoined and takes back %s.[/color]" % [player_name, back.name])
		else:
			var cid = add_character(ch, peer)
			players[peer].cids.append(cid)
			engine.log_line("[color=#8fd0ff]%s joined as %s.[/color]" % [player_name, ch.get("name", "?")])
	_rpc_players.rpc(players)
	players_changed.emit()
	_broadcast([])

## A character left behind by a player whose connection dropped, matching the one now joining.
func _orphan_for(ch: Dictionary) -> Dictionary:
	for c in engine.all_combatants():
		if c.kind != "pc" or not c.get("orphan", false) or int(c.owner) != 1:
			continue
		var same_id: bool = str(ch.get("id", "")) != "" and str(c.get("char_id", "")) == str(ch.get("id", ""))
		if same_id or str(c.name) == str(ch.get("name", "")):
			c.erase("orphan")
			return c
	return {}

func _disconnect_later(peer: int) -> void:
	await get_tree().create_timer(0.5).timeout
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer and peer in multiplayer.get_peers():
		(multiplayer.multiplayer_peer as ENetMultiplayerPeer).disconnect_peer(peer)

@rpc("authority", "reliable")
func _rpc_kicked(reason: String) -> void:
	session_ended.emit(reason)
	status.emit(reason)

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
	var safe_name := my_name.replace("[", "(")
	var out = "[b]%s:[/b] %s" % [safe_name, text.replace("[", "(")]
	var words: PackedStringArray = text.split(" ", false)
	var cmd: String = words[0].to_lower()
	if cmd in ["/roll", "/r", "/hroll", "/gmroll", "/dmroll"]:
		var private: bool = cmd != "/roll" and cmd != "/r"
		var expr := "1d20"
		var adv := 0
		var parts: Array = Array(words.slice(1))
		if not parts.is_empty() and str(parts[-1]).to_lower() in ["adv", "advantage", "dis", "disadvantage"]:
			adv = 1 if str(parts[-1]).to_lower().begins_with("adv") else -1
			parts.pop_back()
		if not parts.is_empty():
			expr = "".join(parts).to_lower()
		if not _valid_dice(expr):
			chat_received.emit("[color=#ff9c8f]Can't roll \"%s\". Try /roll 1d20+5, /roll 2d6+3, or /roll 1d20+4 adv.[/color]" % expr.replace("[", "("))
			return
		var r = Dice.roll(expr)
		var shown: String = str(r.rolls)
		if adv != 0 and expr.begins_with("1d20"):
			# Advantage / disadvantage: roll the d20 twice and keep the higher / lower.
			var r2 = Dice.roll(expr)
			var keep = r if (r.total >= r2.total) == (adv > 0) else r2
			shown = "%s / %s (%s)" % [str(r.rolls), str(r2.rolls), "adv" if adv > 0 else "dis"]
			r = keep
		out = "[b]%s[/b] rolls %s%s: %s = [b][color=#ffd166]%d[/color][/b]" % [safe_name, expr, " (to the DM)" if private else "", shown, r.total]
		if private:
			# Only the roller and the DM see it.
			chat_received.emit("[color=#a59cb5][i](private)[/i][/color] " + out)
			if not is_server():
				_rpc_chat.rpc_id(1, "[color=#a59cb5][i](private)[/i][/color] " + out)
			return
	_rpc_chat.rpc(out)

## A dice expression we're willing to roll: terms like 2d6, d20, +3, at most 100 dice of up to d1000.
func _valid_dice(expr: String) -> bool:
	var re := RegEx.create_from_string("^([+-]?(\\d*d\\d+|\\d+))+$")
	if re.search(expr) == null:
		return false
	var dice := 0
	for t in Dice.parse(expr):
		if t.has("n"):
			dice += absi(int(t.n))
			if int(t.s) < 1 or int(t.s) > 1000:
				return false
	return dice <= 100

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
	# Number duplicates: "Goblin 2", "Goblin 3"... never reusing a name still on the map (hidden ones included).
	var taken := {}
	for o in engine.all_combatants() + state.get("reserve", {}).values():
		taken[str(o.name)] = true
	if taken.has(c.name):
		var base: String = c.name
		var n := 2
		while taken.has("%s %d" % [base, n]):
			n += 1
		c.name = "%s %d" % [base, n]
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
			if dm or can_control(peer, engine.current()):
				_run_ai_now(bool(req.get("resources", true)), bool(req.get("move", true)))
				return
		"set_ai":
			if can_control(peer, c):
				c.ai = req.get("on", false)
		"roll":
			# A check or save for one or more creatures. Players may roll for their own characters;
			# only the DM can attach a DC and damage (traps, hazards, spells the engine doesn't run).
			var who: Array = _targets(req).filter(func(t): return dm or can_control(peer, t))
			if not dm:
				req.erase("dc")
				req.erase("damage")
			_group_roll(who, req)
		# ---------------- DM tools
		"dm_place_monster":
			if dm and not Data.monster(str(req.mid)).is_empty():
				var hidden: bool = req.get("hidden", false)
				var probe := CombatantFactory.from_monster("probe", str(req.mid))
				if not _fits(probe, req.at, "", true):
					status.emit("There's no room for that creature there.")
					return
				var mid := add_monster(req.mid, req.at)
				var m: Dictionary = engine.C(mid)
				if str(req.get("team", "")) in ["party", "enemy"]:
					m.team = req.team
				if hidden:
					_toggle_hidden(mid)
		"dm_place_character":
			if dm: add_character(req.ch, 1, req.get("at", null))
		"dm_remove":
			if dm:
				for t in _targets(req):
					_remove_creature(t)
				for id in [req.get("cid", "")] + req.get("cids", []):
					state.get("reserve", {}).erase(str(id))
		"dm_hidden":
			if dm:
				for id in ([req.cid] if req.has("cid") else []) + req.get("cids", []):
					_toggle_hidden(str(id))
		"dm_reveal_all":
			if dm:
				for id in state.get("reserve", {}).keys():
					_toggle_hidden(id)
		"dm_move_hidden":
			if dm and state.get("reserve", {}).has(str(req.get("cid", ""))):
				var h: Dictionary = state.reserve[str(req.cid)]
				if engine.in_bounds(req.to):
					h.pos = req.to
		"dm_cells":
			if dm:
				var solid: bool = int(req.value) in [EngineBase.WALL, EngineBase.PIT]
				for p in req.cells:
					# Never wall a creature in: walls and pits skip occupied cells.
					if solid and not engine.creature_at(p).is_empty():
						continue
					engine.set_cell(p, int(req.value))
		"dm_spawn":
			if dm:
				var sp: Array = state.spawns
				if req.at in sp: sp.erase(req.at)
				else: sp.append(req.at)
		"dm_hp":
			if dm:
				var amt: int = req.amount
				# Untyped by default: the DM's number is what the creature takes (no resistance).
				var dtype: String = str(req.get("dtype", "untyped"))
				for t in _targets(req):
					if amt < 0:
						engine.apply_damage(t, [{"amount": -amt, "type": dtype}], {}, {"magic": true})
					elif amt > 0:
						_heal_or_revive(t, amt)
		"dm_set_hp":
			if dm:
				for t in _targets(req):
					_set_hp(t, int(req.hp))
		"dm_condition":
			if dm:
				var cond: String = req.cond
				var targets := _targets(req)
				# With several creatures selected, apply to all unless every one already has it.
				var all_have := not targets.is_empty() and targets.all(func(t): return engine.has_cond(t, cond))
				for t in targets:
					if all_have:
						engine.remove_effects_where(t, func(e): return e.get("cond", "") == cond)
						engine.log_line("DM removes %s from %s." % [cond, t.name])
					elif not engine.has_cond(t, cond):
						var rounds: int = int(req.get("rounds", 0))
						# A timed condition ends at the end of the creature's Nth turn from now.
						var added: Dictionary = engine.add_effect(t, {"name": cond.capitalize(), "cond": cond, "src": "dm", "rounds": rounds if rounds > 0 else 9999,
							"tick_cid": t.id if rounds > 0 else "none", "tick_on": "end"})
						if not added.is_empty():
							engine.log_line("DM: %s is %s%s." % [t.name, cond, (" for %d round%s" % [rounds, "" if rounds == 1 else "s"]) if rounds > 0 else ""])
		"dm_exhaustion":
			if dm:
				for t in _targets(req):
					_change_exhaustion(t, int(req.get("delta", 1)))
		"dm_team":
			if dm:
				for t in _targets(req):
					t.team = "party" if t.team != "party" else "enemy"
		"dm_owner":
			if dm and not c.is_empty():
				c.owner = int(req.owner)
				c.erase("orphan")
		"dm_init":
			if dm and state.in_combat and not c.is_empty():
				_set_initiative(c, int(req.init))
		"dm_rename":
			if dm and not c.is_empty() and str(req.get("name", "")).strip_edges() != "":
				var nn: String = str(req.name).strip_edges().left(32)
				engine.log_line("DM renames %s to %s." % [c.name, nn])
				c.name = nn
		"dm_start_combat":
			if dm:
				if engine.all_combatants().filter(func(o): return engine.alive(o) and o.kind != "summon").is_empty():
					status.emit("Place some creatures first.")
					return
				engine.start_combat()
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
				# Slain monsters and summons only: a dead PC stays so it can be raised (Revivify...).
				for o in engine.all_combatants():
					if o.dead and o.kind != "pc":
						_remove_creature(o)
		"dm_resize":
			if dm:
				_resize(int(req.w), int(req.h))
				_settle_creatures()
		"dm_load_map":
			if dm: _load_map(req.map)
		"dm_clear_map":
			if dm:
				state.cells.fill(EngineBase.FLOOR)
		"dm_theme":
			if dm: state.theme = req.theme
		"dm_background":
			if dm:
				_set_background(str(req.get("key", "")), req.get("fit", false))
				_settle_creatures()
	_check_victory()
	_broadcast(engine.events)
	_maybe_run_ai()

## The creatures a request is about: "cids" (a multi-selection) or the single "cid".
func _targets(req: Dictionary) -> Array:
	var out: Array = []
	var ids: Array = req.get("cids", [])
	if ids.is_empty() and str(req.get("cid", "")) != "":
		ids = [req.cid]
	for id in ids:
		var t: Dictionary = engine.C(str(id))
		if not t.is_empty() and not t in out:
			out.append(t)
	return out

## True if creature c could stand at p: on the map, not in a wall or pit, not on anyone else.
func _fits(c: Dictionary, p: Vector2i, ignore := "", check_reserve := false) -> bool:
	for q in engine.occupied_cells(c, p):
		if not engine.in_bounds(q) or engine.blocks_move(q) or not engine.creature_at(q, ignore).is_empty():
			return false
		if check_reserve:
			for h in state.get("reserve", {}).values():
				if q in engine.occupied_cells(h):
					return false
	return true

## Nearest cell to p where c fits (p itself if it already does).
func _fit_near(c: Dictionary, p: Vector2i) -> Vector2i:
	p = Vector2i(clampi(p.x, 0, state.w - 1), clampi(p.y, 0, state.h - 1))
	if _fits(c, p, c.get("id", "")):
		return p
	for r in range(1, maxi(state.w, state.h)):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var q := p + Vector2i(dx, dy)
				if engine.in_bounds(q) and _fits(c, q, c.get("id", "")):
					return q
	return p

## After the map changes shape or terrain: anyone left off the map or inside a wall steps to the nearest free cell.
func _settle_creatures() -> void:
	for o in engine.all_combatants():
		if not engine.alive(o) or engine.in_rope(o):
			continue
		var bad := false
		for q in engine.occupied_cells(o):
			if not engine.in_bounds(q) or engine.blocks_move(q):
				bad = true
		if bad:
			o.pos = _fit_near(o, o.pos)
	for h in state.get("reserve", {}).values():
		h.pos = Vector2i(clampi(h.pos.x, 0, state.w - 1), clampi(h.pos.y, 0, state.h - 1))
	var keep: Array = []
	for p in state.spawns:
		if engine.in_bounds(p):
			keep.append(p)
	state.spawns = keep

## Take a creature off the map, keeping the initiative order pointing at the right creature.
func _remove_creature(t: Dictionary) -> void:
	var was_current: bool = state.in_combat and engine.current().get("id", "") == t.id
	if was_current:
		engine.settle_pending_hit()
	state.combatants.erase(t.id)
	var idx: int = state.order.find(t.id)
	if idx < 0:
		return
	state.order.remove_at(idx)
	if not state.in_combat:
		return
	if state.order.is_empty():
		engine.end_combat()
	elif idx < state.turn:
		state.turn -= 1
	elif was_current:
		state.turn -= 1
		engine._advance()

## Hide a creature from the players (it leaves the map and the initiative, so it can't be targeted),
## or reveal a hidden one (it joins the initiative if a fight is on).
func _toggle_hidden(id: String) -> void:
	if not state.has("reserve"):
		state.reserve = {}
	if state.reserve.has(id):
		var h: Dictionary = state.reserve[id]
		state.reserve.erase(id)
		h.pos = _fit_near(h, h.pos)
		state.combatants[id] = h
		engine.log_line("[color=#ffb347]%s appears![/color]" % h.name)
		if state.in_combat and engine.alive(h):
			_join_initiative(h)
		return
	var t: Dictionary = engine.C(id)
	if t.is_empty() or t.kind == "pc":
		return
	_remove_creature(t)
	state.reserve[id] = t
	status.emit("%s is hidden from the players." % t.name)  # DM-only: the log is shared

func _heal_or_revive(t: Dictionary, amt: int) -> void:
	# The DM can bring back a monster slain by mistake.
	if t.dead and t.kind != "pc":
		t.dead = false
		t.hp = 0
		engine.log_line("DM restores %s." % t.name)
		if state.in_combat and not t.id in state.order:
			_join_initiative(t)
	engine.heal_creature(t, amt, {}, "DM")

## Set current HP outright (DM override). Above 0 also brings a creature back from death.
func _set_hp(t: Dictionary, hp: int) -> void:
	hp = clampi(hp, 0, engine.eff_max_hp(t))
	if hp > 0 and (t.dead or t.death.get("dead", false)):
		t.dead = false
		t.death = {"s": 0, "f": 0, "stable": false, "dead": false}
		if state.in_combat and not t.id in state.order:
			_join_initiative(t)
	var before: int = t.hp
	if hp <= 0 and before > 0:
		# Going down follows the normal rules (unconscious and prone, or slain), not just a number change.
		t.temp_hp = 0
		t.ward = 0
		if not t.form.is_empty():
			engine.end_wild_shape(t)
		engine.apply_damage(t, [{"amount": int(t.hp), "type": "untyped"}], {}, {"magic": true})
		return
	if before <= 0 and hp > 0:
		engine.heal_creature(t, hp, {}, "DM")
		return
	t.hp = hp
	engine.log_line("DM sets %s to %d HP." % [t.name, hp])

## Exhaustion levels are stacked effects carrying mods.exhaustion = 1 each.
func _change_exhaustion(t: Dictionary, delta: int) -> void:
	# The engine handles immunity, stacking, halved max HP at level 4 and death at level 6.
	if delta > 0 and engine.exhaustion(t) < 6:
		engine.add_effect(t, {"name": "Exhaustion", "src": "dm", "rounds": 99999, "tick_cid": "none", "mods": {"exhaustion": 1}, "exhaustion": true})
	elif delta < 0 and engine.remove_exhaustion_level(t):
		engine.log_line("DM: %s loses a level of exhaustion (now %d)." % [t.name, engine.exhaustion(t)])

## Move c to initiative `val`, keeping whoever is acting now as the current turn.
func _set_initiative(c: Dictionary, val: int) -> void:
	var cur_id: String = engine.current().get("id", "")
	c.init = val
	var idx: int = state.order.find(c.id)
	if idx < 0:
		return
	state.order.remove_at(idx)
	var at: int = state.order.size()
	for i in state.order.size():
		var o: Dictionary = engine.C(state.order[i])
		if int(o.get("init", 0)) < val:
			at = i
			break
	state.order.insert(at, c.id)
	state.turn = maxi(0, state.order.find(cur_id))
	engine.log_line("DM sets %s's initiative to %d." % [c.name, val])

## Ability check, skill check or saving throw for each creature in `who`.
## req: kind ("check" | "save"), ability, skill (optional), dc (optional), damage (dice, optional),
## dtype, half (save for half). Damage is rolled once and applied to every creature that fails.
func _group_roll(who: Array, req: Dictionary) -> void:
	if who.is_empty():
		return
	var kind: String = str(req.get("kind", "check"))
	var skill: String = str(req.get("skill", ""))
	var ab: String = str(req.get("ability", Data.SKILLS.get(skill, "dex")))
	var dc: int = int(req.get("dc", 0))
	var dmg_expr: String = str(req.get("damage", "")).strip_edges()
	var dmg_total := 0
	if dmg_expr != "" and dc > 0:
		dmg_expr = dmg_expr.replace(" ", "").to_lower()
		if not _valid_dice(dmg_expr):
			status.emit("Can't roll damage \"%s\" (try 4d10 or 2d6+3)." % dmg_expr)
			return
		dmg_total = Dice.roll(dmg_expr).total
	var what: String = (skill.replace("_", " ").capitalize() if skill != "" else Data.ABILITY_NAMES.get(ab, ab)) + (" save" if kind == "save" else " check")
	engine.log_line("[color=#ffd166]%s%s[/color]" % [what, (" (DC %d)" % dc) if dc > 0 else ""])
	for t in who:
		if not engine.alive(t):
			continue
		var ok := true
		if kind == "save":
			if dc > 0:
				ok = engine.saving_throw(t, ab, dc, {}, {})
			else:
				var b: int = int(t.save_bonus.get(ab, engine.ability_mod(t, ab))) + engine._aura_of_protection(t)
				var adv: int = -1 if engine.exhaustion(t) >= 3 or (ab == "dex" and engine.has_cond(t, "restrained")) else 0
				var r = Dice.roll_d20(adv, t.tags.has("halfling_lucky"))
				engine.log_line("  %s %s save: %d%s %s = [b]%d[/b]" % [engine.nm(t), ab.to_upper(), r.roll, " (dis)" if adv < 0 else "", Rules.fmt_mod(b), int(r.roll) + b])
		else:
			var b2: int = engine.ability_mod(t, ab)
			if skill != "":
				b2 = int(t.get("skills", {}).get(skill, Data.monster(str(t.get("monster_id", ""))).get("skills", {}).get(skill, b2)))
			# Disadvantage on ability checks: exhaustion, poisoned, frightened (5e 2014).
			var dis: bool = engine.exhaustion(t) >= 1 or engine.has_cond(t, "poisoned") or engine.has_cond(t, "frightened")
			var r2 = Dice.roll_d20(-1 if dis else 0, t.tags.has("halfling_lucky"))
			var tot: int = int(r2.roll) + b2
			ok = dc <= 0 or tot >= dc
			engine.log_line("  %s: %d%s %s = [b]%d[/b]%s" % [engine.nm(t), r2.roll, " (dis)" if dis else "", Rules.fmt_mod(b2), tot,
				("  [color=%s]%s[/color]" % ["#7fdc7f" if ok else "#ff7f7f", "SUCCESS" if ok else "FAIL"]) if dc > 0 else ""])
		if dmg_total > 0:
			var amt: int = dmg_total if not ok else (dmg_total / 2 if req.get("half", true) else 0)
			# Evasion: no damage on a successful DEX save for half, half on a failure.
			if kind == "save" and ab == "dex" and req.get("half", true) and t.features.has("evasion") and not engine.is_incapacitated(t):
				amt = 0 if ok else dmg_total / 2
			if amt > 0:
				engine.apply_damage(t, [{"amount": amt, "type": str(req.get("dtype", "untyped"))}], {}, {"magic": true})

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

func _run_ai_now(use_resources := true, allow_move := true) -> void:
	var cur = engine.current()
	if cur.is_empty():
		return
	engine.events = []
	ai.use_resources = use_resources
	ai.allow_move = allow_move
	ai.run_turn(cur)
	ai.use_resources = true
	ai.allow_move = true
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
			mons.append({"mid": c.monster_id, "x": c.pos.x, "y": c.pos.y, "team": c.team, "name": c.name})
	for c in state.get("reserve", {}).values():
		if c.kind == "monster" and not c.dead:
			mons.append({"mid": c.monster_id, "x": c.pos.x, "y": c.pos.y, "team": c.team, "name": c.name, "hidden": true})
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
	state.reserve = {}
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
	var missing: Array = []
	for mon in m.get("monsters", []):
		if Data.monster(str(mon.mid)).is_empty():
			missing.append(str(mon.mid))
			continue
		var cid = add_monster(mon.mid, Vector2i(int(mon.x), int(mon.y)))
		var nc: Dictionary = state.combatants[cid]
		nc.team = mon.get("team", "enemy")
		if str(mon.get("name", "")) != "":
			nc.name = str(mon.name)
		if mon.get("hidden", false):
			_toggle_hidden(cid)
	# Player characters go to the start points; anyone left over (or standing in a wall) finds a free cell.
	var i = 0
	for c in engine.all_combatants():
		if c.kind == "pc" and i < sp.size() and _fits(c, sp[i], c.id):
			c.pos = sp[i]
			i += 1
	_settle_creatures()
	for c in engine.all_combatants():
		if c.kind != "monster" and not _fits(c, c.pos, c.id):
			c.pos = _fit_near(c, c.pos)
	engine.log_line("Map \"%s\" loaded." % state.name)
	if not missing.is_empty():
		engine.log_line("[color=#ff9c8f]Unknown monsters skipped: %s[/color]" % ", ".join(missing))
