extends Node
## Headless engine smoke test: premade party vs monsters, everyone AI-controlled.
## Run: Godot --headless --path . res://tests/smoke_test.tscn

func _ready() -> void:
	var errors = 0
	# Every premade derives cleanly.
	for ch in CharacterStore.premades():
		var st = Rules.derive(ch)
		print("%s | %s | HP %d AC %d init %+d | slots %s pact %s | spells %d" % [ch.name, Rules.class_summary(ch), st.max_hp, st.ac, st.initiative, str(st.slots), str(st.pact), st.casting.reduce(func(a, e): return a + e.spells.size(), 0)])
	# Every monster builds.
	for mid in Data.monsters:
		var m = CombatantFactory.from_monster("x", mid)
		if m.max_hp <= 0:
			errors += 1
	for round_seed in 3:
		var st = EngineBase.new_state(20, 14)
		var eng = CombatEngine.new(st)
		var ai = CombatAI.new(eng)
		var i = 0
		for ch in CharacterStore.premades():
			var c = CombatantFactory.from_character(eng.new_id("p"), ch, 1)
			c.pos = Vector2i(2, 2 + i * 2)
			c.ai = true
			st.combatants[c.id] = c
			i += 1
		var foes = [["goblin", "orc", "bugbear", "mage", "dire_wolf", "ogre"], ["skeleton", "zombie", "ghoul", "wight", "cult_fanatic", "priest"], ["owlbear", "young_red_dragon", "gnoll", "hobgoblin"]][round_seed]
		var j = 0
		for mid in foes:
			if Data.monsters.has(mid):
				var m = CombatantFactory.from_monster(eng.new_id("m"), mid)
				m.pos = Vector2i(14 + (j % 2) * 2, 2 + j * 2)
				st.combatants[m.id] = m
				j += 1
		eng.start_combat()
		var turns = 0
		while st.in_combat and turns < 150:
			var cur = eng.current()
			ai.run_turn(cur)
			if st.in_combat and eng.current().get("id", "") == cur.id:
				eng.end_turn()
			var side = eng.side_defeated()
			if side != "":
				print("== battle %d: %s side defeated after %d turns, round %d" % [round_seed, side, turns, st.round])
				eng.end_combat()
			turns += 1
		if turns >= 150:
			print("== battle %d: still going after 150 turns" % round_seed)
		if round_seed == 0:
			for line in st.log.slice(0, 80):
				print(line)
	print("SMOKE DONE errors=%d" % errors)
	get_tree().quit()
