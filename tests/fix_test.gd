extends Node
## Lucky and the other roll-fixing abilities ask the player first (EngineBase.FIX_NAMES), unless the player
## switched them to automatic. Run: Godot --headless --path . res://tests/fix_test.tscn  (prints FIX TEST FAILED on failure)

var fails := 0
var passes := 0

func check(cond: bool, what: String) -> void:
	if cond:
		passes += 1
	else:
		fails += 1
		print("FAIL: ", what)

func _ready() -> void:
	_engine_level()
	await _session_level()
	print("FIX TEST: %d passed, %d failed" % [passes, fails])
	if fails > 0:
		print("FIX TEST FAILED")
	get_tree().quit(1 if fails > 0 else 0)

func _lucky_pc() -> Dictionary:
	return CharacterStore.premades().filter(func(ch): return "lucky" in ch.get("feats", []))[0]

## A player's lucky character and a goblin, in a bare engine.
func _board() -> Array:
	var st = EngineBase.new_state(20, 12)
	var eng = CombatEngine.new(st)
	var pc = CombatantFactory.from_character(eng.new_id("p"), _lucky_pc(), 1)
	pc.pos = Vector2i(3, 3)
	st.combatants[pc.id] = pc
	var gob = CombatantFactory.from_monster(eng.new_id("m"), "goblin")
	gob.pos = Vector2i(4, 3)
	st.combatants[gob.id] = gob
	eng.start_combat()
	return [eng, pc, gob]

func _engine_level() -> void:
	# Off by default: the AI and scripted fights use Lucky the old way.
	var b = _board()
	var eng: CombatEngine = b[0]
	var pc: Dictionary = b[1]
	check(eng.res_left(pc, "lucky") == 3, "the premade has 3 luck points")
	eng.saving_throw(pc, "wis", 99, {})
	check(eng.res_left(pc, "lucky") == 2, "with no questions asked, a failed save spends Lucky itself")
	# Asking: nothing is spent until the player says yes, and the question is recorded.
	b = _board()
	eng = b[0]
	pc = b[1]
	eng.fix_ask = true
	var ok: bool = eng.saving_throw(pc, "wis", 99, {})
	check(not ok, "the save fails while the question is open")
	check(eng.res_left(pc, "lucky") == 3, "nothing is spent while the question is open")
	check(str(eng.fix_wait.get("key", "")) == "lucky" and eng.fix_wait.get("cid", "") == pc.id, "the question names Lucky and the character")
	check(eng.fix_wait.answers == [], "no earlier answers")
	# Yes spends a point; no does not.
	b = _board()
	eng = b[0]
	pc = b[1]
	eng.fix_ask = true
	eng.fix_answers = [true]
	eng.saving_throw(pc, "wis", 99, {})
	check(eng.res_left(pc, "lucky") == 2 and eng.fix_wait.is_empty(), "yes spends a luck point and asks nothing more")
	b = _board()
	eng = b[0]
	pc = b[1]
	eng.fix_ask = true
	eng.fix_answers = [false]
	eng.saving_throw(pc, "wis", 99, {})
	check(eng.res_left(pc, "lucky") == 3 and eng.fix_wait.is_empty(), "no keeps the luck point")
	# Automatic setting: uses it without asking.
	b = _board()
	eng = b[0]
	pc = b[1]
	eng.fix_ask = true
	pc.toggles["auto_fix"] = {"lucky": true}
	eng.saving_throw(pc, "wis", 99, {})
	check(eng.res_left(pc, "lucky") == 2 and eng.fix_wait.is_empty(), "an automatic Lucky is spent without a question")
	# A monster never asks.
	b = _board()
	eng = b[0]
	var gob: Dictionary = b[2]
	eng.fix_ask = true
	eng.saving_throw(gob, "wis", 99, {})
	check(eng.fix_wait.is_empty(), "monsters never ask")
	# Your own miss: asked after the roll.
	b = _board()
	eng = b[0]
	pc = b[1]
	gob = b[2]
	gob.ac = 40
	eng.fix_ask = true
	var atk: Dictionary = pc.attacks[0] if not pc.attacks.is_empty() else {"to_hit": 5, "melee": true, "reach": 5}
	var res = eng.roll_attack(pc, gob, atk, {"melee": true})
	if int(res.nat) != 1 and int(res.nat) != 20:
		check(str(eng.fix_wait.get("key", "")) == "lucky", "a missed attack asks about Lucky")
		check(eng.res_left(pc, "lucky") == 3, "and spends nothing yet")
	# Being hit: asked too.
	b = _board()
	eng = b[0]
	pc = b[1]
	gob = b[2]
	pc.ac = 1
	eng.fix_ask = true
	var gatk: Dictionary = {"to_hit": 8, "melee": true, "reach": 5}
	var hit_res = eng.roll_attack(gob, pc, gatk, {"melee": true})
	if int(hit_res.nat) != 1 and int(hit_res.nat) < 20:
		check(str(eng.fix_wait.get("key", "")) == "lucky", "a hit on the character asks about Lucky")

## Through the server: the request is undone, the player is asked, the answer replays it with the same dice.
func _session_level() -> void:
	Session.start_offline("Tester", 20, 12)
	var pid: String = Session.add_character(_lucky_pc(), 1, Vector2i(3, 3))
	var gid: String = Session.add_monster("goblin", Vector2i(4, 3))
	var eng: CombatEngine = Session.engine
	var pc: Dictionary = eng.C(pid)
	var gob: Dictionary = eng.C(gid)
	pc.ac = 1
	Session.request({"type": "dm_start_combat"})
	Session.auto_monsters = true
	var asked := false
	var snap: Dictionary = {}
	var rng_seed := 0
	var rng_state := 0
	for attempt in 40:
		Session.state.erase("pending_fix")
		eng.s.turn = eng.s.order.find(gid)
		eng.begin_turn(gob)
		pc.hp = pc.max_hp
		pc.resources.lucky.cur = 3
		snap = Session.state.duplicate(true)
		rng_seed = Dice.rng.seed
		rng_state = Dice.rng.state
		Session._run_ai_now()
		if not Session.state.get("pending_fix", {}).is_empty():
			asked = true
			break
		# The goblin missed or rolled a critical hit: put everything back and try again with new dice.
		_restore(snap)
	check(asked, "a goblin's hit asks the player about Lucky")
	if not asked:
		return
	pc = eng.C(pid)
	gob = eng.C(gid)
	var q: Dictionary = Session.state.pending_fix
	check(str(q.key) == "lucky" and q.cid == pid, "the question is about Lucky for the right character")
	check(pc.hp == pc.max_hp and eng.res_left(pc, "lucky") == 3, "the unfinished turn was undone")
	check(int(gob.turn.action) == 1, "the goblin's action is back")
	# Another request while the question is open does nothing.
	var pos_before: Vector2i = pc.pos
	Session.request({"type": "move", "cid": pid, "to": Vector2i(8, 8), "free": true})
	check(pc.pos == pos_before, "the game waits for the answer")
	# Answer "no", then run the same turn again with no question possible: the same dice give the same result.
	Session.request({"type": "fix_choice", "id": q.id, "use": false})
	check(Session.state.get("pending_fix", {}).is_empty(), "the question is closed after the answer")
	pc = eng.C(pid)
	var hp_no: int = pc.hp
	check(eng.res_left(pc, "lucky") == 3, "no keeps all 3 luck points")
	check(hp_no < pc.max_hp, "the goblin's hit landed")
	_restore(snap)
	Dice.rng.seed = rng_seed
	Dice.rng.state = rng_state
	eng.C(pid).resources.lucky.cur = 0  # nothing to ask about: the plain, uninterrupted turn
	Session._run_ai_now()
	check(eng.C(pid).hp == hp_no, "the replay rolled the same dice (HP %d vs %d)" % [eng.C(pid).hp, hp_no])
	# Answer "yes" spends a point.
	_restore(snap)
	Dice.rng.seed = rng_seed
	Dice.rng.state = rng_state
	Session._run_ai_now()
	var q2: Dictionary = Session.state.get("pending_fix", {})
	check(not q2.is_empty(), "the same turn asks again")
	if not q2.is_empty():
		# Only the character's owner (or the DM) can answer.
		eng.C(pid).owner = 7
		Session._handle(9, {"type": "fix_choice", "id": q2.id, "use": true})
		check(not Session.state.get("pending_fix", {}).is_empty(), "another player can't answer for the character")
		Session._handle(7, {"type": "fix_choice", "id": "stale", "use": true})
		check(not Session.state.get("pending_fix", {}).is_empty(), "an answer to some other question is ignored")
		Session._handle(7, {"type": "fix_choice", "id": q2.id, "use": true})
		check(eng.res_left(eng.C(pid), "lucky") == 2, "yes spends one luck point")
		check(Session.state.get("pending_fix", {}).is_empty(), "the owner's answer closes the question")
	# Switching Lucky to automatic means no question.
	_restore(snap)
	Session.request({"type": "set_auto_fix", "cid": pid, "id": "lucky", "on": true})
	check(bool(eng.C(pid).toggles.auto_fix.get("lucky", false)), "set_auto_fix turns Lucky automatic")
	Session._run_ai_now()
	check(Session.state.get("pending_fix", {}).is_empty(), "an automatic Lucky doesn't ask")
	# The battle screen shows the question and sends the answer.
	_restore(snap)
	Dice.rng.seed = rng_seed
	Dice.rng.state = rng_state
	var bs = load("res://scenes/battle.tscn").instantiate()
	add_child(bs)
	await get_tree().process_frame
	Session._run_ai_now()
	bs.control_cid = pid
	bs.selected_cid = pid
	bs._refresh_ui()
	check(bs.fix_panel != null and bs.fix_panel.visible, "the battle screen shows the question")
	if bs.fix_panel != null:
		check(bs.fix_title.text.contains("Lucky"), "it names the ability")
	var pm := PopupMenu.new()
	bs.add_child(pm)
	bs._fill_fix_menu(pm)
	check(pm.item_count >= 2, "the setting menu lists the character's abilities")
	bs._answer_fix(false)
	check(Session.state.get("pending_fix", {}).is_empty(), "answering from the screen closes the question")
	check(bs.fix_panel == null or not bs.fix_panel.visible, "and hides it")
	bs.queue_free()
	await get_tree().process_frame

## Put the shared state dictionary back the way it was (in place: the engine and the session hold it).
func _restore(snap: Dictionary) -> void:
	var fresh: Dictionary = snap.duplicate(true)
	Session.state.clear()
	for k in fresh:
		Session.state[k] = fresh[k]
