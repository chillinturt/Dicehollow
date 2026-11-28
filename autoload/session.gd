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
signal sheets_changed

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
var _in_handle := false
var _fix_snap: Dictionary = {}     # the state before the request being resolved (see _fix_begin)
var _fix_rng: Dictionary = {}      # and the dice that go with it
var _fix_gseed := 0
var _fix_answers: Array = []
var _fix_redo: Callable
var _fix_replaying := false
var _pending_character: Dictionary = {}
var last_end_reason := ""  # why the last game ended (shown on the main menu)
## Character sheets of the PCs in the game (cid -> character dictionary without its history), kept in
## sync on every peer so party members can read each other's sheets and level plans.
var sheets := {}

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
	state.advancement = "milestone"
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
	state.advancement = "milestone"
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
	if str(character.get("id", "")) == "":
		# A premade has no id yet: give it one so its progress can be saved on this machine later.
		character = character.duplicate(true)
		character.id = CharacterStore.new_id()
	_pending_character = Progression.strip_history(character)
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
	sheets = {}
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
		_rpc_sheets.rpc_id(id, sheets)
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
func _rpc_sheets(s: Dictionary) -> void:
	sheets = s
	sheets_changed.emit()

## The server tells a character's owner to save a changed sheet (level-up, restore, XP) on their disk.
@rpc("authority", "reliable")
func _rpc_store_sheet(sheet: Dictionary, label: String, old_sheet: Dictionary) -> void:
	store_local(sheet, label, old_sheet)

@rpc("authority", "reliable")
func _rpc_status(text: String) -> void:
	status.emit(text)

@rpc("authority", "reliable")
func _rpc_players(p: Dictionary) -> void:
	players = p
	players_changed.emit()

@rpc("authority", "reliable")
func _rpc_portrait(key: String, bytes: PackedByteArray) -> void:
	CharacterStore.register_portrait(key, bytes)
	portrait_arrived.emit(key)

## Change a PC's portrait (and token colour) mid-game. The image is already saved on this machine under
## `key`; its bytes travel with the request so the DM can share it with everyone.
func set_portrait(cid: String, key: String, template := "", color := "") -> void:
	var bytes := CharacterStore.get_portrait_bytes(key)
	if is_server():
		_apply_portrait(1, cid, key, bytes, template, color)
	else:
		_rpc_set_portrait.rpc_id(1, cid, key, bytes, template, color)

const PORTRAIT_MAX_BYTES := 2 * 1024 * 1024

@rpc("any_peer", "reliable")
func _rpc_set_portrait(cid: String, key: String, bytes: PackedByteArray, template: String, color: String) -> void:
	if is_server():
		_apply_portrait(multiplayer.get_remote_sender_id(), cid, key, bytes, template, color)

func _apply_portrait(peer: int, cid: String, key: String, bytes: PackedByteArray, template: String, color: String) -> void:
	var c = engine.C(cid)
	if c.is_empty() or c.kind != "pc" or not can_control(peer, c):
		return
	if not CharacterStore.valid_portrait_key(key) or bytes.is_empty() or bytes.size() > PORTRAIT_MAX_BYTES \
			or Image.new().load_png_from_buffer(bytes) != OK:
		_tell(peer, "That portrait couldn't be used (it must be a PNG under 2 MB).")
		return
	CharacterStore.register_portrait(key, bytes)
	portrait_arrived.emit(key)
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		_rpc_portrait.rpc(key, bytes)
	c.portrait = key
	if Color.html_is_valid(color):
		c.color = "#" + Color(color).to_html(false)
	if sheets.has(cid):
		var sheet: Dictionary = sheets[cid]
		sheet.portrait = key
		sheet.portrait_template = template if PortraitTemplates.has(template) else ""
		sheet.color = c.color
		_store_for_owner(c, sheet, "", {})
	engine.log_line("%s has a new portrait." % c.name)
	_broadcast([])
	_broadcast_sheets()

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
	if not engine.fix_wait.is_empty():
		_fix_ask_player()
		events = []
	# Movement left is derived from speed; refresh the cached number before clients see it
	# (a DM-applied condition or a reaction may have changed the mover's speed).
	if state.in_combat:
		engine.sync_move(engine.current())
	# Creatures that drop let go of what they hold; then, on an endless map, new ground appears where the party
	# can see the edge (which may move everything: the events' cells move with it).
	MapObjects.sweep(engine)
	# Loot picked up, potions drunk, scrolls read: save what changed to the characters' sheets.
	_sync_gear()
	_stream_update(events)
	# Fog of war: whatever the party sees now (or saw along the way) is remembered.
	Fog.update_seen(engine, events)
	state_changed.emit(events)
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		_rpc_state.rpc(state, events)

## Endless maps (MapStream): grow the map toward any edge the party can see, place wandering monsters that
## turned up in the new ground, and tell clients how far everything moved.
func _stream_update(events: Array) -> void:
	var res: Dictionary = MapStream.update(engine)
	if res.is_empty():
		return
	var d: Vector2i = res.shift
	if d != Vector2i.ZERO:
		MapStream.shift_in_place(events, d)
		events.append({"t": "map_shift", "d": d})
	for id in res.get("remove", []):
		var t: Dictionary = engine.C(str(id))
		if not t.is_empty():
			_remove_creature(t)
	var named := {}
	for f in res.get("foes", []):
		var probe := CombatantFactory.from_monster("probe", str(f.mid))
		var at: Vector2i = f.pos
		if not _fits(probe, at, "", true):
			continue
		var cid := add_monster(str(f.mid), at)
		named[str(engine.C(cid).name)] = true
	var lines: Array = ["[color=#a59cb5]New ground comes into view. The map is now %d × %d squares.[/color]" % [state.w, state.h]]
	if not named.is_empty():
		lines.append("[color=#ff9c8f]Something stirs in the newly seen ground: %s.[/color]" % ", ".join(named.keys()))
	for line in lines:
		var before: int = engine.events.size()
		engine.log_line(line)
		# log_line queues the event on engine.events; make sure it reaches this broadcast either way.
		if not is_same(events, engine.events):
			events.append(engine.events[before])

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
	ch = Progression.strip_history(ch)
	# Sheets from before inventories get their class and background starting gear (Inventory.ensure).
	Inventory.ensure(ch)
	if str(ch.get("id", "")) == "":
		ch.id = CharacterStore.new_id()  # so its progress can be saved later
	for k in ["xp", "level_cap"]:
		if not ch.has(k):
			ch[k] = 0
	sheets[cid] = ch
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
	c.init = int(Dice.roll_d20(0, c.get("tags", {}).has("halfling_lucky")).roll) + int(c.init_bonus)
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
	if str(req.get("type", "")) == "fix_choice":
		_answer_fix(peer, req)
		return
	if not state.get("pending_fix", {}).is_empty():
		return  # a player is deciding whether to use an ability: the game waits for the answer
	_fix_begin(func(): _handle(peer, req))
	_in_handle = true
	_handle_op(peer, req)
	_in_handle = false
	engine.fix_ask = false

# ================================================================ roll-fixing choices
# Lucky, Indomitable and friends are the player's call (see EngineBase.FIX_NAMES). The engine resolves a
# whole request in one go, so it can't stop in the middle of a roll to ask. Instead the server keeps a
# snapshot of the state and the dice before each request. When a player's character is about to use one of
# these abilities and has no answer yet, the engine notes the question and carries on; `_broadcast` then
# throws that run away, restores the snapshot and shows the question. The answer is added to the ones
# already given and the request is run again from the same snapshot with the same dice, so every roll comes
# out the same until the question is reached, where the answer now decides what happens.

func _fix_begin(redo: Callable) -> void:
	engine.fix_ask = false
	engine.fix_wait = {}
	engine.fix_n = 0
	if _fix_replaying:
		_fix_replaying = false
		engine.fix_answers = _fix_answers
		engine.fix_ask = true
		return
	engine.fix_answers = []
	_fix_answers = []
	_fix_snap = {}
	_fix_redo = redo
	if not is_server() or not engine.fix_any_manual():
		return
	_fix_snap = state.duplicate(true)
	_fix_rng = {"seed": Dice.rng.seed, "state": Dice.rng.state}
	_fix_gseed = randi()
	seed(_fix_gseed)  # the few spots that use the global random numbers replay the same way
	engine.fix_ask = true

## The run just finished stopped at a question: undo it and ask.
func _fix_ask_player() -> void:
	var w: Dictionary = engine.fix_wait
	engine.fix_wait = {}
	engine.fix_ask = false
	var snap: Dictionary = _fix_snap.duplicate(true)
	state.clear()
	for k in snap:
		state[k] = snap[k]
	Dice.rng.seed = int(_fix_rng.seed)
	Dice.rng.state = int(_fix_rng.state)
	seed(_fix_gseed)
	_fix_answers = w.answers
	engine.events = []
	state.pending_fix = {"id": engine.new_id("fix"), "cid": w.cid, "key": w.key, "title": w.title, "detail": w.detail}

func _answer_fix(peer: int, req: Dictionary) -> void:
	var p: Dictionary = state.get("pending_fix", {})
	if p.is_empty() or str(req.get("id", "")) != str(p.id) or not _fix_redo.is_valid():
		return
	if not can_control(peer, engine.C(str(p.cid))):
		return
	state.erase("pending_fix")
	_fix_answers = _fix_answers.duplicate()
	_fix_answers.append(bool(req.get("use", false)))
	_fix_replaying = true
	_fix_redo.call()

func _handle_op(peer: int, req: Dictionary) -> void:
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
		"set_sheet":
			_set_sheet(peer, c, req.get("sheet", {}), str(req.get("label", "")))
		"inv":
			_inventory_op(peer, c, req)
		"inv_give":
			_give(peer, c, engine.C(str(req.get("to", ""))), req)
		"stash":
			_stash(peer, c, req)
		"set_auto_fix":
			# Switch one roll-fixing ability (Lucky...) between "ask me" and "use it automatically".
			var fid := str(req.get("id", ""))
			if can_control(peer, c) and c.kind == "pc" and EngineBase.FIX_NAMES.has(fid):
				var af: Dictionary = c.toggles.get("auto_fix", {})
				af[fid] = bool(req.get("on", false))
				c.toggles["auto_fix"] = af
				if sheets.has(c.id):
					sheets[c.id].auto_fix = af.duplicate()
					_store_for_owner(c, sheets[c.id], "", {})
					_broadcast_sheets()
		# ---------------- DM tools
		"dm_advancement":
			if dm and str(req.get("mode", "")) in ["xp", "milestone"]:
				state.advancement = req.mode
				engine.log_line("[color=#ffd166]Advancement: %s.[/color]" % ("experience points" if req.mode == "xp" else "milestones (the DM grants levels)"))
				_broadcast_sheets()
		"dm_xp":
			if dm:
				_award_xp(_pc_targets(req), int(req.get("amount", 0)), req.get("split", false))
		"dm_award_encounter":
			if dm:
				_award_encounter_xp()
		"dm_grant_level":
			if dm:
				_grant_level(_pc_targets(req))
		"dm_shop":
			if dm: _set_shop(req)
		"dm_give":
			if dm: _dm_give(_pc_targets(req), req)
		"dm_shop_stock":
			if dm: _shop_stock(req)
		"dm_split_coins":
			if dm: _split_coins(_pc_targets(req))
		"dm_treasure":
			if dm and Inventory.TREASURE_MODES.any(func(m): return m[0] == str(req.get("mode", ""))):
				state.treasure = str(req.mode)
				engine.log_line("[color=#a59cb5]Treasure on bodies: %s.[/color]" % str(Inventory.TREASURE_MODES.filter(func(m): return m[0] == state.treasure)[0][1]).to_lower())
		"dm_attune_free":
			if dm:
				state.attune_free = bool(req.get("on", false))
				engine.log_line("[color=#a59cb5]Attunement: %s.[/color]" % ("the DM allows attuning without a rest" if state.attune_free else "attuning or ending an attunement takes a short rest (DMG)"))
		"dm_encumbrance":
			if dm and str(req.get("mode", "")) in ["standard", "variant"]:
				state.encumbrance = str(req.mode)
				engine.log_line("[color=#a59cb5]Encumbrance: %s.[/color]" % ("the variant rule (over 5 × STR lb: -10 ft; over 10 × STR: -20 ft and disadvantage on STR, DEX and CON rolls)" if req.mode == "variant" else "the standard rule (only more than 15 × STR lb slows you)"))
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
				var painted := {}
				for p in req.cells:
					# Never wall a creature in: walls and pits skip occupied cells.
					if solid and not engine.creature_at(p).is_empty():
						continue
					engine.set_cell(p, int(req.value))
					painted[p] = true
				# Objects (crates, chests, weak walls...) on repainted cells go with the old terrain.
				state.objects = MapObjects.list(state).filter(func(o): return not painted.has(o.pos))
				# Furniture and other props on repainted cells go with the old terrain.
				if not painted.is_empty() and not state.get("props", []).is_empty():
					state.props = state.props.filter(func(pr):
						for dx in int(pr.get("w", 1)):
							for dy in int(pr.get("h", 1)):
								if painted.has(Vector2i(int(pr.x) + dx, int(pr.y) + dy)):
									return false
						return true)
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
				state.ground = PackedByteArray()
				state.props = []
				state.labels = []
				state.objects = []
				state.stream = {}
		"dm_object":
			# Place an object (a chest gets loot for the party's level), or remove the one already on that cell.
			if dm and engine.in_bounds(req.get("at", Vector2i(-1, -1))):
				var at: Vector2i = req.at
				var here: Array = MapObjects.at(state, at)
				if not here.is_empty():
					for o in here:
						MapObjects.remove(engine, o)
						# Taking a chest away doesn't destroy what the party stored in it.
						if not MapObjects.store_empty(o):
							MapObjects.spill_store(engine, o)
				elif MapObjects.KINDS.has(str(req.get("k", ""))):
					var k := str(req.k)
					if int(MapObjects.KINDS[k].get("cell", -1)) == EngineBase.WALL and not engine.creature_at(at).is_empty():
						status.emit("Someone is standing there.")
						return
					var extra := {}
					if MapObjects.KINDS[k].get("container", false):
						var rng := RandomNumberGenerator.new()
						rng.randomize()
						extra.loot = MapObjects.roll_loot(rng, _party_level(), k == "chest")
						if k == "chest" and req.get("locked", false):
							extra.locked = true
							extra.dc = clampi(int(req.get("dc", 15)), 5, 30)
					MapObjects.place(engine, MapObjects.make(k, at, EngineBase.FLOOR, extra))
		"dm_stream":
			# Switch an endless map's growing on or off.
			if dm and not state.get("stream", {}).is_empty():
				state.stream.on = bool(req.get("on", true))
				engine.log_line("[color=#a59cb5]%s[/color]" % ("Endless map: new ground appears as the party nears an edge." if state.stream.on else "Endless map paused: the map stays as it is."))
		"dm_label":
			# Rename (or, with empty text, remove) a place name on the map.
			if dm:
				var labels: Array = state.get("labels", [])
				var li := int(req.get("i", -1))
				if li >= 0 and li < labels.size():
					var txt := str(req.get("text", "")).strip_edges().left(60)
					if txt == "":
						labels.remove_at(li)
					else:
						labels[li].text = txt
		"dm_theme":
			if dm: state.theme = req.theme
		"dm_fog":
			if dm: _set_fog(req)
		"dm_fog_reset":
			if dm:
				Fog.reset(state)
				engine.log_line("[color=#a59cb5]The fog of war rolls back in: the party forgets what it has explored.[/color]")
		"dm_fog_reveal":
			if dm:
				Fog.reveal_all(state)
				engine.log_line("[color=#a59cb5]The DM reveals the whole map.[/color]")
		"dm_fog_paint":
			if dm: Fog.paint(state, req.get("cells", []), bool(req.get("reveal", true)))
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
				engine.dice_event(t.id, ab.to_upper() + " save", EngineBase.d20_faces(r), b, int(r.roll) + b)
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
			engine.dice_event(t.id, what.replace(" check", "") + ((" · DC %d" % dc) if dc > 0 else ""), EngineBase.d20_faces(r2), b2, tot, ("SUCCESS" if ok else "FAIL") if dc > 0 else "")
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
		engine.sfx("victory")
		engine.end_combat()
	elif side == "party":
		engine.log_line("[color=#ff5050][b]The party has fallen…[/b][/color]")
		engine.sfx("defeat")
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
	if not is_server() or _ai_busy or not state.in_combat or not state.get("pending_fix", {}).is_empty():
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
	if not state.get("pending_fix", {}).is_empty():
		return
	var cur = engine.current()
	if cur.is_empty():
		return
	# Called from _handle (Auto Turn), the request has already begun; on its own (a monster's turn) it starts here.
	if not _in_handle:
		_fix_begin(func(): _run_ai_now(use_resources, allow_move))
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
	if not _in_handle:
		engine.fix_ask = false
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
	var old_ground: PackedByteArray = state.get("ground", PackedByteArray())
	if old_ground.size() == state.w * state.h:
		var ground := PackedByteArray()
		ground.resize(w * h)
		for y in mini(h, state.h):
			for x in mini(w, state.w):
				ground[y * w + x] = old_ground[y * state.w + x]
		state.ground = ground
	state.props = state.get("props", []).filter(func(p): return int(p.x) + int(p.get("w", 1)) <= w and int(p.y) + int(p.get("h", 1)) <= h)
	state.labels = state.get("labels", []).filter(func(l): return float(l.x) < w and float(l.y) < h)
	state.objects = MapObjects.list(state).filter(func(o): return o.pos.x < w and o.pos.y < h)
	state.w = w
	state.h = h
	state.cells = cells
	Fog.reset(state)  # the remembered cells no longer line up

## Average level of the player characters on the map (1 if there are none).
func _party_level() -> int:
	var tot := 0
	var n := 0
	for c in engine.all_combatants():
		if c.kind == "pc":
			tot += int(c.get("level", 1))
			n += 1
	return maxi(1, tot / maxi(1, n))

## DM fog-of-war settings: any of "mode" (off / soft / hard), "shared" (party shares vision) and
## "range" (feet creatures see without darkvision; 0 = unlimited).
func _set_fog(req: Dictionary) -> void:
	var f: Dictionary = Fog.settings(state)
	var old := f.duplicate()
	if str(req.get("mode", "")) in Fog.MODES:
		f.mode = str(req.mode)
	if req.has("shared"):
		f.shared = bool(req.shared)
	if req.has("range"):
		f.range = clampi(int(req.range), 0, 1000)
	state.fog = f
	if not state.has("fog_seen"):
		state.fog_seen = {}
	if f.mode != old.mode:
		var says := {"off": "Fog of war is off: everyone sees the whole map.",
			"soft": "Soft fog of war: you see the lay of the land, but only creatures your side can see.",
			"hard": "Hard fog of war: unexplored ground stays hidden until someone sees it."}
		engine.log_line("[color=#a59cb5]%s[/color]" % says[f.mode])
	if f.shared != old.shared:
		engine.log_line("[color=#a59cb5]%s[/color]" % ("The party shares its vision." if f.shared else "Each player now sees only what their own characters see."))
	if f.range != old.range:
		engine.log_line("[color=#a59cb5]%s[/color]" % ("Sight is unlimited (bright light)." if f.range == 0 else "Without darkvision, creatures see %d ft." % f.range))

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
	var snap := {"name": state.name, "w": state.w, "h": state.h, "cells": Array(state.cells), "monsters": mons, "spawns": spawns, "theme": state.get("theme", "stone"), "bg": state.get("bg", ""), "custom_monsters": custom, "fog": Fog.settings(state)}
	var ground: PackedByteArray = state.get("ground", PackedByteArray())
	if ground.size() == state.w * state.h or not state.get("props", []).is_empty() or not state.get("labels", []).is_empty():
		snap.ground = Array(ground) if ground.size() == state.w * state.h else []
		snap.props = state.get("props", []).duplicate(true)
		snap.labels = state.get("labels", []).duplicate(true)
	if not MapObjects.list(state).is_empty():
		snap.objects = MapObjects.to_map(state.objects)
	if not state.get("stream", {}).is_empty():
		snap.stream = state.stream.duplicate(true)
	return snap

## Map dressing from a saved or generated map, checked: per-cell ground materials, props and labels.
func _load_dressing(m: Dictionary, w: int, h: int) -> void:
	var g = m.get("ground", [])
	state.ground = PackedByteArray(g) if (g is Array or g is PackedByteArray) and g.size() == w * h else PackedByteArray()
	var props: Array = []
	for p in m.get("props", []):
		if p is Dictionary and p.has("k") and p.has("x") and p.has("y"):
			var q := {"k": str(p.k).left(24), "x": clampi(int(p.x), 0, w - 1), "y": clampi(int(p.y), 0, h - 1)}
			if p.has("w"): q.w = clampi(int(p.w), 1, 8)
			if p.has("h"): q.h = clampi(int(p.h), 1, 8)
			props.append(q)
	state.props = props.slice(0, 4000)
	var labels: Array = []
	for l in m.get("labels", []):
		if l is Dictionary and l.has("text"):
			labels.append({"text": str(l.text).left(60), "x": clampf(float(l.get("x", 0)), 0, w), "y": clampf(float(l.get("y", 0)), 0, h),
				"kind": str(l.get("kind", "")).left(16), "style": str(l.get("style", "")).left(8)})
	state.labels = labels.slice(0, 200)

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
	_load_dressing(m, w, h)
	# Interactable objects, and the endless-map record if the map grows as the party explores.
	MapObjects.load_into(engine, m.get("objects", []))
	state.stream = MapStream.clean(m.get("stream", {}))
	# A new place: nothing explored yet. A map saved with fog settings brings them along.
	Fog.reset(state)
	if m.get("fog", {}) is Dictionary and not m.get("fog", {}).is_empty():
		var mf: Dictionary = m.fog
		state.fog = {"mode": str(mf.get("mode", "off")) if str(mf.get("mode", "off")) in Fog.MODES else "off",
			"shared": bool(mf.get("shared", true)), "range": clampi(int(mf.get("range", 0)), 0, 1000)}
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

# ================================================================ character advancement

## The PCs a DM request is about: the selected ones, or every PC on the party's side if none were picked.
func _pc_targets(req: Dictionary) -> Array:
	var out: Array = _targets(req).filter(func(t): return t.kind == "pc" and sheets.has(t.id))
	if out.is_empty() and req.get("cids", []).is_empty() and str(req.get("cid", "")) == "":
		for t in engine.all_combatants():
			if t.kind == "pc" and t.team == "party" and sheets.has(t.id):
				out.append(t)
	return out

func advancement() -> String:
	return str(state.get("advancement", "milestone"))

## Levels this PC may take right now (granted by the DM or earned with XP, not yet taken).
func pending_levels(cid: String) -> int:
	if not sheets.has(cid):
		return 0
	return Progression.pending_levels(sheets[cid], advancement())

func _broadcast_sheets() -> void:
	if not is_server():
		return
	for cid in sheets.keys():
		if not state.combatants.has(cid) and not state.get("reserve", {}).has(cid):
			sheets.erase(cid)
	sheets_changed.emit()
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		_rpc_sheets.rpc(sheets)

## Tell one peer something (the DM sees it in their log; a player in theirs).
func _tell(peer: int, text: String) -> void:
	if peer == 1 or not multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		status.emit(text)
	else:
		_rpc_status.rpc_id(peer, text)

## Have the character's owner save the new sheet. `label` names the backup of the old version
## (empty for small updates such as XP, which don't make a backup).
func _store_for_owner(c: Dictionary, sheet: Dictionary, label: String, old_sheet: Dictionary) -> void:
	var owner := int(c.owner)
	if owner == 1 or not multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		store_local(sheet, label, old_sheet)
	elif owner in multiplayer.get_peers():
		_rpc_store_sheet.rpc_id(owner, sheet, label, old_sheet)

## Save a sheet from the game into this machine's character store, backing up the version it replaces.
## Characters that were never saved here (premades) are only written for real changes, not XP ticks.
func store_local(sheet: Dictionary, label: String, old_sheet: Dictionary = {}) -> void:
	var id := str(sheet.get("id", ""))
	if id == "":
		return
	var full: Dictionary = CharacterStore.get_character(id)
	if full.is_empty() and label == "":
		return
	var old: Dictionary = full if not full.is_empty() else old_sheet.duplicate(true)
	var hist: Array = full.get("history", [])
	if label != "" and not old.is_empty():
		old = old.duplicate(true)
		old.history = hist
		Progression.push_history(old, label)
		hist = old.history
	var out: Dictionary = Progression.strip_history(sheet)
	# The portrait key is this machine's; keep the local one if the game's copy lost it.
	if str(out.get("portrait", "")) == "" and not full.is_empty():
		out.portrait = full.get("portrait", "")
	CharacterStore.persist_portrait(str(out.get("portrait", "")))
	out.history = hist
	CharacterStore.save_character(out)

## A player (or the DM) replaces a PC's sheet: a level-up, a restore from history or a plan edit.
func _set_sheet(peer: int, c: Dictionary, incoming, label: String) -> void:
	if c.is_empty() or c.kind != "pc" or not can_control(peer, c) or not incoming is Dictionary or not sheets.has(c.id):
		return
	var dm := peer == 1
	var old: Dictionary = sheets[c.id]
	var sheet: Dictionary = Progression.strip_history(incoming)
	var base := Rules.new_character()
	for k in base:
		if not sheet.has(k):
			sheet[k] = base[k]
	sheet.erase("history")
	var err := _sheet_problem(sheet)
	if err != "":
		_tell(peer, "Sheet not accepted: " + err)
		return
	var before := Rules.total_level(old)
	var after := Rules.total_level(sheet)
	if not dm:
		if after != before and state.in_combat:
			_tell(peer, "Levels change outside combat. Finish the fight first.")
			return
		if after > Progression.allowed_level(old, advancement()):
			_tell(peer, "%s can't go above level %d yet: %s" % [old.get("name", "That character"), Progression.allowed_level(old, advancement()),
				"not enough XP." if advancement() == "xp" else "the DM hasn't granted that level."])
			return
	# The DM's grants and XP aren't the player's to change.
	sheet.xp = int(old.get("xp", 0))
	sheet.level_cap = int(old.get("level_cap", 0))
	sheet.id = str(old.get("id", sheet.get("id", "")))
	sheet.portrait = str(old.get("portrait", ""))
	# What a character carries is the game's to change (loot, the shop), not an old copy of the sheet's.
	sheet.inventory = old.get("inventory", []).duplicate(true)
	sheet.coins = old.get("coins", {}).duplicate()
	Inventory.sync_equipment(sheet)
	sheets[c.id] = sheet
	_apply_sheet(c, sheet)
	if after > before:
		engine.log_line("[color=#ffd166][b]⬆ %s reaches level %d![/b] (%s)[/color]" % [c.name, after, Rules.class_summary(sheet)])
	elif after < before:
		engine.log_line("[color=#ffd166]%s's sheet goes back to level %d (%s).[/color]" % [c.name, after, Rules.class_summary(sheet)])
	elif label.begins_with("Before restoring"):
		engine.log_line("[color=#ffd166]%s restores an earlier version of their sheet.[/color]" % c.name)
	_store_for_owner(c, sheet, label, old)
	_broadcast_sheets()

func _sheet_problem(sheet: Dictionary) -> String:
	var classes = sheet.get("classes", [])
	if not classes is Array or classes.is_empty():
		return "it has no classes."
	var total := 0
	var seen := {}
	for c in classes:
		if not c is Dictionary or Data.cls(str(c.get("id", ""))).is_empty():
			return "unknown class."
		if seen.has(c.id):
			return "a class appears twice."
		seen[c.id] = true
		var lv := int(c.get("level", 0))
		if lv < 1 or lv > 20:
			return "class levels must be 1 to 20."
		total += lv
	if total > 20:
		return "total level can't exceed 20."
	return ""

## Rebuild a PC's combat stats from a new sheet, keeping where it stands and what has happened to it:
## damage taken, spent slots and features, conditions, concentration, initiative.
func _apply_sheet(c: Dictionary, sheet: Dictionary) -> void:
	var fresh := CombatantFactory.from_character(c.id, sheet, int(c.owner))
	var keep := ["id", "name", "owner", "team", "pos", "hp", "temp_hp", "init", "turn", "effects", "conc", "death", "ai",
		"form", "dead", "hidden", "ward", "acted", "toggles", "recharge", "summoner", "slots_used", "pact_used", "hd_used", "resources", "orphan"]
	var old_max := int(c.max_hp)
	var old_res: Dictionary = c.get("resources", {})
	var old_slots: Array = c.get("slots_used", [])
	for k in fresh:
		if not k in keep:
			c[k] = fresh[k]
	if int(c.hp) > 0:
		c.hp = clampi(int(fresh.max_hp) - (old_max - int(c.hp)), 1, int(fresh.max_hp))
	var used: Array = []
	for i in fresh.slots_max.size():
		used.append(mini(int(old_slots[i]) if i < old_slots.size() else 0, int(fresh.slots_max[i])))
	c.slots_used = used
	c.pact_used = mini(int(c.get("pact_used", 0)), int(fresh.pact_max))
	var res: Dictionary = {}
	for k in fresh.resources:
		var r: Dictionary = fresh.resources[k].duplicate()
		if old_res.has(k):
			var spent: int = int(old_res[k].max) - int(old_res[k].cur)
			r.cur = clampi(int(r.max) - spent, 0, int(r.max))
		res[k] = r
	c.resources = res
	var hd_used: Dictionary = {}
	for die in c.get("hd_used", {}):
		if fresh.hd_max.has(die):
			hd_used[die] = mini(int(c.hd_used[die]), int(fresh.hd_max[die]))
	c.hd_used = hd_used
	c.char_id = str(sheet.get("id", c.get("char_id", "")))

func _award_xp(targets: Array, amount: int, split: bool) -> void:
	if targets.is_empty() or amount == 0:
		return
	var each: int = amount / targets.size() if split else amount
	var names: PackedStringArray = []
	for t in targets:
		var sh: Dictionary = sheets[t.id]
		var was := Progression.pending_levels(sh, "xp")
		sh.xp = maxi(0, int(sh.get("xp", 0)) + each)
		names.append(str(t.name))
		_store_for_owner(t, sh, "", {})
		if advancement() == "xp" and Progression.pending_levels(sh, "xp") > was:
			engine.log_line("[color=#ffd166][b]⬆ %s can level up![/b] (%d XP)[/color]" % [t.name, int(sh.xp)])
	engine.log_line("[color=#ffd166]%s %d XP%s: %s.[/color]" % ["Awarded" if each >= 0 else "Removed", absi(each), " each" if targets.size() > 1 else "", ", ".join(names)])
	_broadcast_sheets()

## XP for every defeated enemy not yet counted, shared among the party members still standing.
func _award_encounter_xp() -> void:
	var party: Array = engine.all_combatants().filter(func(t): return t.kind == "pc" and t.team == "party" and not t.get("dead", false) and sheets.has(t.id))
	var total := encounter_xp()
	if total <= 0 or party.is_empty():
		status.emit("No defeated enemies to award XP for.")
		return
	for o in engine.all_combatants():
		if _unawarded_kill(o):
			o.xp_awarded = true
	_award_xp(party, total, true)

## XP still to award for defeated enemies on the map.
func encounter_xp() -> int:
	var total := 0
	for o in engine.all_combatants():
		if _unawarded_kill(o):
			total += EncounterBuilder.monster_xp(Data.monster(str(o.monster_id)))
	return total

func _unawarded_kill(o: Dictionary) -> bool:
	return o.kind == "monster" and o.team == "enemy" and (o.dead or int(o.hp) <= 0) and not o.get("xp_awarded", false)

## Milestone: each target may take one more level. With XP advancement it tops their XP up to the next level.
func _grant_level(targets: Array) -> void:
	var names: PackedStringArray = []
	for t in targets:
		var sh: Dictionary = sheets[t.id]
		var cur_allowed := Progression.allowed_level(sh, advancement())
		if cur_allowed >= Progression.MAX_LEVEL:
			continue
		var target: int = cur_allowed + 1
		if advancement() == "xp":
			sh.xp = maxi(int(sh.get("xp", 0)), Progression.xp_for_level(target))
		sh.level_cap = maxi(int(sh.get("level_cap", 0)), target)
		names.append("%s (level %d)" % [t.name, target])
		_store_for_owner(t, sh, "", {})
	if not names.is_empty():
		engine.log_line("[color=#ffd166][b]⬆ Level up![/b] The DM grants a new level to %s. Open the character sheet to level up.[/color]" % ", ".join(names))
	_broadcast_sheets()

# ================================================================ belongings and shops (Inventory)

## After every request: a PC whose pack or purse changed in play (loot, a potion drunk, a scroll read, a
## torch lit) has the change written to its sheet and saved by its owner.
func _sync_gear() -> void:
	var changed := false
	for c in engine.all_combatants():
		if c.kind != "pc" or not sheets.has(c.id) or not c.get("inventory", null) is Array:
			continue
		var sh: Dictionary = sheets[c.id]
		if c.inventory == sh.get("inventory", []) and c.get("coins", {}) == sh.get("coins", {}) and not c.get("gear_dirty", false):
			continue
		sh.inventory = c.inventory.duplicate(true)
		sh.coins = c.get("coins", {}).duplicate()
		Inventory.sync_equipment(sh)
		c.load_lb = Inventory.carried_lb(c)
		# Weapons swapped (or an item changed what the character wields): attacks and AC come from the sheet again.
		if c.get("gear_dirty", false):
			c.erase("gear_dirty")
			_apply_sheet(c, sh)
		_store_for_owner(c, sh, "", {})
		changed = true
	if changed:
		_broadcast_sheets()

## A PC's changed belongings: rebuild its stats from the sheet (AC, attacks, magic items, load) and save.
func _commit_gear(c: Dictionary) -> void:
	var sh: Dictionary = sheets[c.id]
	sh.inventory = c.inventory.duplicate(true)
	sh.coins = c.get("coins", {}).duplicate()
	Inventory.sync_equipment(sh)
	_apply_sheet(c, sh)
	_store_for_owner(c, sh, "", {})
	_broadcast_sheets()

## The shop the DM has open ({} when none).
func shop() -> Dictionary:
	var sh = state.get("shop", {})
	return sh if sh is Dictionary and sh.get("open", false) else {}

## A player equips, attunes, drops, packs, buys or sells (see Inventory.apply_op).
func _inventory_op(peer: int, c: Dictionary, req: Dictionary) -> void:
	if c.is_empty() or c.kind != "pc" or not sheets.has(c.id) or not can_control(peer, c):
		return
	var dm := peer == 1
	var op := str(req.get("op", ""))
	var fighting: bool = state.in_combat
	if op in ["buy", "sell"]:
		if shop().is_empty():
			_tell(peer, "There's no shop open.")
			return
		if fighting and not dm:
			_tell(peer, "No shopping in the middle of a fight.")
			return
	if op in ["add", "coins"] and not dm:
		return
	var e := Inventory.find(c, str(req.get("uid", "")))
	# In a fight, drawing a weapon is your free object interaction (then an action); a shield takes an action
	# (PHB p.146), and so does taking something out of a bag of holding.
	var cost := ""
	if fighting and not dm and op in ["equip", "move", "swap"]:
		if not engine.is_turn_of(c):
			_tell(peer, "Wait for your turn.")
			return
		# Swapping weapon sets is one object interaction, unless a shield goes on or off (an action).
		var shield_moves: bool = Inventory.swap_moves_shield(c) if op == "swap" else (op == "equip" and not e.is_empty() and req.get("on", true) and Inventory.equip_moves_shield(c, e))
		if op == "move" or Inventory.is_shield(e) or shield_moves:
			cost = "action"
		elif not c.turn.get("obj_used", false):
			cost = "obj"
		else:
			cost = "action"
		if cost == "action" and not engine.can_pay(c, "action"):
			_tell(peer, "That takes an action, and %s has none left." % c.name)
			return
	# Attunement waits for a rest unless the DM does it, or has switched on "attune without a rest".
	var ctx := {"in_combat": fighting, "shop": shop(), "free": dm, "info": Inventory.sheet_info(sheets[c.id]),
		"attune_now": dm or bool(state.get("attune_free", false)), "sheet": sheets[c.id]}
	# Dropping in play leaves the item on the ground for someone else to pick up.
	var dropped := {}
	if op == "drop" and state.combatants.has(c.id) and not e.is_empty():
		dropped = Inventory.take(c, str(e.uid), int(req.get("qty", 0)))
		if dropped.is_empty():
			return
		_drop_pile(c, dropped)
	else:
		var err := Inventory.apply_op(c, req, ctx)
		if err != "":
			_tell(peer, err)
			return
	if cost == "obj":
		c.turn.obj_used = true
	elif cost == "action":
		engine.pay(c, "action")
	match op:
		"buy":
			var probe := {"id": str(req.get("id", "")), "base": str(req.get("base", ""))}
			var qn := int(req.get("qty", 1))
			engine.log_line("[color=#ffd166]%s buys %s%s.[/color]" % [c.name, ("%d× " % qn) if qn > 1 else "", Inventory.display_name(probe)])
		"sell":
			engine.log_line("[color=#ffd166]%s sells something to the %s.[/color]" % [c.name, str(shop().get("name", "shop"))])
		"drop":
			engine.log_line("%s drops %s." % [c.name, Inventory.display_name(dropped)])
		"equip":
			if fighting and e.get("eq", false):
				engine.log_line("%s readies the %s." % [c.name, Inventory.display_name(e).to_lower()])
		"swap":
			engine.log_line("%s swaps weapons: now holding %s." % [c.name, Inventory.set_text(Inventory.held(c, false))])
		"copy":
			engine.log_line("[color=#c8a0ff]%s copies a scroll: %s[/color]" % [c.name, str(ctx.get("result", ""))])
		"infuse":
			var inf := str(req.get("infusion", ""))
			if inf == "":
				engine.log_line("[color=#c8a0ff]%s ends an infusion.[/color]" % c.name)
			elif inf == "replicate_magic_item":
				engine.log_line("[color=#c8a0ff]%s replicates a %s with an infusion.[/color]" % [c.name, str(Data.item(str(req.get("item", ""))).get("name", "magic item"))])
			else:
				engine.log_line("[color=#c8a0ff]%s infuses %s with %s.[/color]" % [c.name, Inventory.display_name(e) if not e.is_empty() else "an item", Data.pretty(inf)])
		"store":
			engine.log_line("[color=#c8a0ff]%s casts %s into the ring.[/color]" % [c.name, str(Data.spell(str(req.get("spell", ""))).get("name", "a spell"))])
		"attune":
			match str(e.get("pend", "")):
				"on":
					engine.log_line("[color=#c8a0ff]%s will attune to %s during the next short or long rest.[/color]" % [c.name, Inventory.display_name(e)])
				"off":
					engine.log_line("[color=#c8a0ff]%s will end attunement to %s during the next short or long rest.[/color]" % [c.name, Inventory.display_name(e)])
		"add":
			engine.log_line("[color=#ffd166]The DM gives %s %s.[/color]" % [c.name, Inventory.display_name({"id": str(req.get("id", "")), "base": str(req.get("base", "")), "spell": str(req.get("spell", ""))})])
	_commit_gear(c)

## Leave `entry` on the ground where `c` stands (a loot pile anyone can open).
func _drop_pile(c: Dictionary, entry: Dictionary) -> void:
	for o in MapObjects.at(state, c.pos):
		if str(o.get("k", "")) == "pile" and not o.get("opened", false):
			var l: Dictionary = o.get("loot", {})
			var g: Array = l.get("gear", [])
			g.append(entry)
			l.gear = g
			o.loot = l
			return
	MapObjects.place(engine, MapObjects.make("pile", c.pos, EngineBase.FLOOR, {"loot": {"gear": [entry]}}))

## Hand an item (uid, qty) or coins ({"coins": {...}}) to another party member. In a fight they must be
## within 5 ft, and it's your object interaction (an action if you've had it).
func _give(peer: int, c: Dictionary, to: Dictionary, req: Dictionary) -> void:
	if c.is_empty() or to.is_empty() or c.id == to.id or not can_control(peer, c) or to.kind != "pc" or not sheets.has(c.id) or not sheets.has(to.id):
		return
	var dm := peer == 1
	if state.in_combat and not dm:
		if not engine.is_turn_of(c):
			_tell(peer, "Wait for your turn.")
			return
		if engine.dist(c, to) > 5:
			_tell(peer, "%s is too far away to hand things to (5 ft)." % to.name)
			return
		if c.turn.get("obj_used", false):
			if not engine.can_pay(c, "action"):
				_tell(peer, "Handing it over takes an action now, and %s has none left." % c.name)
				return
			engine.pay(c, "action")
		else:
			c.turn.obj_used = true
	var what := ""
	if req.get("coins", null) is Dictionary:
		var amt: Dictionary = {}
		var purse := Inventory.coins(c)
		for k in Inventory.COINS:
			var n := clampi(int(req.coins.get(k, 0)), 0, int(purse[k]))
			if n > 0:
				amt[k] = n
				purse[k] = int(purse[k]) - n
		if amt.is_empty():
			return
		Inventory.give_coins(to, amt)
		what = Inventory.fmt_coins(amt)
	else:
		var e := Inventory.find(c, str(req.get("uid", "")))
		if e.is_empty():
			return
		var part := Inventory.take(c, str(e.uid), int(req.get("qty", 0)))
		Inventory.add_entry(to, part)
		what = (("%d× " % int(part.qty)) if int(part.get("qty", 1)) > 1 else "") + Inventory.display_name(part)
	engine.log_line("%s gives %s %s." % [c.name, to.name, what])
	_commit_gear(c)
	_commit_gear(to)

## Store things in (or take them from) a storage chest within 5 ft: {"obj", "op": "put" | "take", "uid", "qty"}
## for an item (qty 0 = the whole stack) or {"obj", "op": "put" | "take", "coins": {...}} for coins. In a fight
## each one is your object interaction on your turn (then an action), like handing something over.
func _stash(peer: int, c: Dictionary, req: Dictionary) -> void:
	if c.is_empty() or c.kind != "pc" or not sheets.has(c.id) or not can_control(peer, c):
		return
	var o := MapObjects.by_id(state, str(req.get("obj", "")))
	if o.is_empty() or not MapObjects.is_storage(o):
		_tell(peer, "There's no chest there to store things in.")
		return
	var dm := peer == 1
	if not dm and not MapObjects._in_reach(engine, c, o, 5):
		_tell(peer, "%s has to stand next to the %s (within 5 ft)." % [c.name, MapObjects.name_of(o).to_lower()])
		return
	var op := str(req.get("op", ""))
	if not op in ["put", "take"]:
		return
	var store := MapObjects.store_of(o)
	var fighting: bool = state.in_combat
	var src: Dictionary = c if op == "put" else store
	var dst: Dictionary = store if op == "put" else c
	var e := {}
	if not req.get("coins", null) is Dictionary:
		e = Inventory.find(src, str(req.get("uid", "")))
		if e.is_empty():
			return
		if op == "put":
			var why := Inventory.stash_problem(e, fighting)
			if why != "":
				_tell(peer, why)
				return
	if fighting and not dm:
		if not engine.is_turn_of(c):
			_tell(peer, "Wait for your turn.")
			return
		if c.turn.get("obj_used", false):
			if not engine.can_pay(c, "action"):
				_tell(peer, "That takes an action now (you've had your free object interaction), and %s has none left." % c.name)
				return
			engine.pay(c, "action")
		else:
			c.turn.obj_used = true
	var what := ""
	if req.get("coins", null) is Dictionary:
		var moved := Inventory.transfer_coins(src, dst, req.coins)
		if moved.is_empty():
			return
		what = Inventory.fmt_coins(moved)
	else:
		var n := int(req.get("qty", 0))
		var have := int(e.get("qty", 1))
		var moved := Inventory.transfer(src, dst, str(e.uid), n)
		if moved.is_empty():
			return
		var qn := have if n <= 0 or n >= have else n
		what = (("%d× " % qn) if qn > 1 else "") + Inventory.display_name(moved)
	var chest := MapObjects.name_of(o).to_lower()
	if op == "put":
		engine.log_line("%s puts %s in the %s." % [c.name, what, chest])
	else:
		engine.log_line("%s takes %s from the %s." % [c.name, what, chest])
	engine.sfx("pickup", c.id)
	_commit_gear(c)

## The DM opens, changes or closes the shop.
func _set_shop(req: Dictionary) -> void:
	if not req.get("open", false):
		if not shop().is_empty():
			engine.log_line("[color=#a59cb5]%s closes.[/color]" % str(state.shop.get("name", "The shop")))
		state.shop = {}
		return
	var kind := str(req.get("kind", "general"))
	if not Inventory.SHOPS.has(kind):
		kind = "general"
	var magic_max := str(req.get("magic_max", "uncommon"))
	if not magic_max in Inventory.RARITIES:
		magic_max = "uncommon"
	var was_open := not shop().is_empty()
	var old: Dictionary = shop()
	var nm := str(req.get("name", "")).strip_edges().left(40)
	# Updating an open shop of the same kind keeps the DM's own stock changes and limited quantities.
	var same: bool = was_open and str(old.get("kind", "")) == kind and str(old.get("magic_max", "")) == magic_max
	state.shop = {"open": true, "kind": kind, "name": nm if nm != "" else str(Inventory.SHOPS[kind].name),
		"markup": clampi(int(req.get("markup", 100)), 10, 1000), "buyback": clampi(int(req.get("buyback", 50)), 0, 100),
		"magic_buyback": clampi(int(req.get("magic_buyback", 25)), 0, 100),
		"magic_max": magic_max, "stock": old.stock.duplicate() if same else Inventory.shop_stock(kind, magic_max),
		"qty": old.get("qty", {}).duplicate() if same else {}}
	if not was_open:
		engine.log_line("[color=#ffd166]🛒 %s is open for business. Click 🛒 Shop under your portrait to buy and sell.[/color]" % state.shop.name)

## The DM adds an item to the open shop's stock (qty > 0: only that many; 0: as many as anyone wants) or
## takes one off the shelves.
func _shop_stock(req: Dictionary) -> void:
	var sh: Dictionary = shop()
	var id := str(req.get("id", ""))
	if sh.is_empty() or Data.item(id).is_empty():
		status.emit("Open a shop first." if sh.is_empty() else "Unknown item.")
		return
	if not sh.get("qty", null) is Dictionary:
		sh.qty = {}
	var nm := str(Data.item(id).get("name", id))
	if str(req.get("op", "add")) == "remove":
		sh.stock.erase(id)
		sh.qty.erase(id)
		engine.log_line("[color=#a59cb5]%s no longer sells %s.[/color]" % [str(sh.name), nm])
		return
	if not id in sh.stock:
		sh.stock.append(id)
	var n := int(req.get("qty", 0))
	if n > 0:
		sh.qty[id] = mini(n, 9999)
	else:
		sh.qty.erase(id)
	engine.log_line("[color=#ffd166]%s now sells %s%s.[/color]" % [str(sh.name), nm, (" (%d in stock)" % n) if n > 0 else ""])

## The DM shares out the coins the chosen characters (or the whole party) carry, evenly, coin by coin.
func _split_coins(targets: Array) -> void:
	if targets.size() < 2:
		status.emit("Choose two or more characters (or none, for the whole party) to split coins between.")
		return
	var totals := Inventory.split_coins(targets)
	for t in targets:
		_commit_gear(t)
	engine.log_line("[color=#ffd166]The DM splits the party's coins (%s) evenly between %s.[/color]" % [Inventory.fmt_coins(totals),
		", ".join(targets.map(func(t): return str(t.name)))])

## The DM hands out items or coins (treasure, rewards) to the chosen characters.
func _dm_give(targets: Array, req: Dictionary) -> void:
	var names: PackedStringArray = []
	var probe := {"id": str(req.get("id", "")), "base": str(req.get("base", "")), "spell": str(req.get("spell", "")), "dtype": str(req.get("dtype", ""))}
	for t in targets:
		if req.get("coins", null) is Dictionary:
			Inventory.give_coins(t, req.coins)
		else:
			var err := Inventory.apply_op(t, {"op": "add", "id": probe.id, "qty": int(req.get("qty", 1)), "base": probe.base,
				"spell": probe.spell, "dtype": probe.dtype}, {"free": true})
			if err != "":
				status.emit(err)
				return
		names.append(str(t.name))
		_commit_gear(t)
	if names.is_empty():
		return
	var what := ""
	if req.get("coins", null) is Dictionary:
		what = Inventory.fmt_coins(req.coins)
	else:
		var qn := int(req.get("qty", 1))
		what = (("%d× " % qn) if qn > 1 else "") + Inventory.display_name(probe)
	engine.log_line("[color=#ffd166]The DM gives %s: %s.[/color]" % [", ".join(names), what])
