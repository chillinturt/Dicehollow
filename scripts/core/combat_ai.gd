class_name CombatAI
extends RefCounted
## Plays a combatant's turn: scores every (action, target, position) by expected value, moves and acts.

var eng: CombatEngine

func _init(engine: CombatEngine) -> void:
	eng = engine

func run_turn(c: Dictionary) -> void:
	if not eng.alive(c) or c.hp <= 0 or eng.is_incapacitated(c):
		return
	_pre_buffs(c)
	for a in eng.get_actions(c):
		if a.id == "magic_stone_pickup" and a.enabled:
			var pick = _eval_feature(c, a, {})
			if not pick.is_empty():
				_do(c, pick)
			break
	var guard = 0
	while guard < 10:
		guard += 1
		if not eng.alive(c) or c.hp <= 0:
			return
		var plan = _best_plan(c, ["action", "attack"])
		if plan.is_empty():
			break
		if not _do(c, plan):
			break
	# Held (grapple, web, vines...) with nothing to hit: spend the action breaking free, then use the movement.
	if eng.can_pay(c, "action") and not eng.escape_effect(c).is_empty():
		eng.execute(c.id, "escape", {})
		if eng.escape_effect(c).is_empty():
			var plan2 = _best_plan(c, ["attack"])
			if not plan2.is_empty():
				_do(c, plan2)
			elif eng.move_budget(c) > 0 and eng.eff_speed(c) > 0:
				var near0 = _nearest_enemy(c)
				if not near0.is_empty() and eng.dist(c, near0) > 5:
					_approach(c, near0)
	# Nobody in sight, but foes are holed up in a Rope Trick: wait under the rope for them.
	if _nearest_enemy(c).is_empty() and eng.move_budget(c) > 0 and eng.eff_speed(c) > 0:
		_camp_rope(c)
	# Couldn't reach anything: close the distance (Dash is pointless at speed 0).
	if eng.can_pay(c, "action") and _nearest_enemy(c).size() > 0 and eng.eff_speed(c) > 0:
		var near = _nearest_enemy(c)
		if eng.dist(c, near) > 5:
			eng.execute(c.id, "dash", {})
			_approach(c, near)
	elif eng.move_budget(c) > 0:
		_reposition(c)
	# Bonus actions.
	guard = 0
	while guard < 3 and eng.can_pay(c, "bonus"):
		guard += 1
		var bp = _best_plan(c, ["bonus"])
		if bp.is_empty() or not _do(c, bp):
			break

func _do(c: Dictionary, plan: Dictionary) -> bool:
	if plan.has("cell") and plan.cell != c.pos and plan.get("move", true):
		eng.move(c, plan.cell)
		if not eng.alive(c) or c.hp <= 0:
			return false
	var params = {"targets": plan.get("targets", []), "cell": plan.get("aim", c.pos), "slot": plan.get("slot", 0), "opts": plan.get("opts", {})}
	return eng.execute(c.id, plan.aid, params)

func _nearest_enemy(c: Dictionary) -> Dictionary:
	var best = {}
	var bd = 99999
	for o in eng.enemies_of(c):
		if o.hp <= 0 and o.kind == "pc":
			continue
		var d = eng.dist(c, o)
		if d < bd:
			bd = d
			best = o
	return best

func _approach(c: Dictionary, t: Dictionary) -> void:
	var reach = eng.reachable(c, eng.move_budget(c))
	var best: Vector2i = c.pos
	var bd = eng.dist(c, t)
	var saved: Vector2i = c.pos
	for cell in reach:
		if reach[cell].get("occupied", false):
			continue
		c.pos = cell
		var d = eng.dist(c, t)
		if d < bd or (d == bd and reach[cell].cost < reach.get(best, {"cost": 9999}).cost):
			bd = d
			best = cell
	c.pos = saved
	if best != c.pos:
		eng.move(c, best)

## Move next to the nearest Rope Trick that hides conscious enemies. Anyone who drops out lands
## in reach, shoots at disadvantage, and provokes an opportunity attack climbing back up.
func _camp_rope(c: Dictionary) -> void:
	var rope: Dictionary = {}
	for r in eng.ropes():
		var foes: Array = eng.rope_occupants(str(r.src)).filter(func(o): return eng.hostile(c, o) and eng.conscious(o))
		if foes.is_empty():
			continue
		if rope.is_empty() or eng.dist_to_cell(c, r.pos) < eng.dist_to_cell(c, rope.pos):
			rope = r
	if rope.is_empty() or eng.dist_to_cell(c, rope.pos) <= 5:
		return
	var reach = eng.reachable(c, eng.move_budget(c))
	var best: Vector2i = c.pos
	var bd: int = eng.dist_to_cell(c, rope.pos)
	for cell in reach:
		if reach[cell].get("occupied", false):
			continue
		var d: int = eng._dist_from(c, cell, {"pos": rope.pos, "sz": 1}) * 5
		if d < bd or (d == bd and reach[cell].cost < reach.get(best, {"cost": 9999}).cost):
			bd = d
			best = cell
	if best != c.pos:
		eng.move(c, best)

func _reposition(c: Dictionary) -> void:
	# Ranged creatures step away from adjacent enemies when they still have movement.
	if not _prefers_range(c):
		return
	var threatened = false
	for o in eng.enemies_of(c):
		if eng.conscious(o) and eng.dist(c, o) <= 5:
			threatened = true
	if not threatened or c.turn.get("disengaged", false) == false and c.kind == "monster" and not c.tags.has("nimble_escape"):
		return
	var reach = eng.reachable(c, eng.move_budget(c))
	var saved: Vector2i = c.pos
	var best: Vector2i = c.pos
	var best_score = -1
	for cell in reach:
		if reach[cell].get("occupied", false):
			continue
		c.pos = cell
		var mind = 999
		for o in eng.enemies_of(c):
			mind = mini(mind, eng.dist(c, o))
		if mind > best_score and mind <= 60:
			best_score = mind
			best = cell
	c.pos = saved
	if best != c.pos:
		eng.move(c, best)

func _prefers_range(c: Dictionary) -> bool:
	var melee = 0.0
	var ranged = 0.0
	for a in eng.attacks_of(c):
		var v = _avg_parts(a.get("damage", []))
		if a.get("melee", true):
			melee = maxf(melee, v)
		else:
			ranged = maxf(ranged, v)
	return ranged > melee or (c.casting.size() > 0 and melee < 6)

func _avg_parts(parts: Array) -> float:
	var t = 0.0
	for p in parts:
		t += Dice.average(p.dice)
	return t

# ---------------------------------------------------------------- pre-turn buffs

func _pre_buffs(c: Dictionary) -> void:
	var near = _nearest_enemy(c)
	if near.is_empty():
		return
	var close = eng.dist(c, near) <= eng.move_left(c) + 10
	for a in eng.get_actions(c):
		if not a.enabled or a.cost != "bonus":
			continue
		match a.id:
			"rage", "bladesong", "fighting_spirit", "radiant_soul":
				if close:
					eng.execute(c.id, a.id, {})
					return
			"vow_of_enmity", "hexblades_curse":
				if eng.dist(c, near) <= int(a.range):
					eng.execute(c.id, a.id, {"targets": [near.id]})
					return
			"sp:hunters_mark", "sp:hex":
				if c.conc.is_empty() and eng.dist(c, near) <= int(a.range):
					eng.execute(c.id, a.id, {"targets": [near.id], "slot": a.slots[0]})
					return
	# Paladins arm a smite when a slot is spare.
	if c.features.has("divine_smite") and int(c.toggles.get("smite", 0)) == 0 and eng.lowest_slot(c, 1) > 0 and near.hp > 10:
		c.toggles.smite = eng.lowest_slot(c, 1)

# ---------------------------------------------------------------- planning

func _best_plan(c: Dictionary, costs: Array) -> Dictionary:
	var actions = eng.get_actions(c)
	var reach = eng.reachable(c, eng.move_budget(c) if eng.s.in_combat else 0)
	var best = {}
	var best_v = 0.5
	for a in actions:
		if not a.enabled or not a.cost in costs or a.kind in ["toggle", "basic", "mspecial"]:
			continue
		var plan = _evaluate(c, a, reach)
		if plan.is_empty():
			continue
		if plan.value > best_v:
			best_v = plan.value
			best = plan
	return best

func _candidate_cells(c: Dictionary, t: Dictionary, rng: int, reach: Dictionary, ranged: bool) -> Dictionary:
	# Cheapest cell from which `t` is within range and visible. Ranged attackers avoid melee.
	var saved: Vector2i = c.pos
	var best = {}
	var best_score = 999999.0
	for cell in reach:
		if reach[cell].get("occupied", false):
			continue
		c.pos = cell
		if eng.dist(c, t) <= rng and (t.id == c.id or eng.los(c, t)):
			var score: float = reach[cell].cost
			if ranged:
				for o in eng.enemies_of(c):
					if eng.conscious(o) and eng.dist(c, o) <= 5:
						score += 40.0
			if score < best_score:
				best_score = score
				best = {"cell": cell, "cost": reach[cell].cost}
	c.pos = saved
	return best

func _evaluate(c: Dictionary, a: Dictionary, reach: Dictionary) -> Dictionary:
	match a.kind:
		"weapon":
			return _eval_attack(c, a, reach, [a.atk])
		"multiattack":
			var atks: Array = []
			for name in a.m.get("sequence", []):
				for x in eng.attacks_of(c):
					if x.name == name:
						atks.append(x)
			if atks.is_empty():
				return {}
			return _eval_attack(c, a, reach, atks)
		"msave":
			return _eval_area(c, a, reach, a.m.get("damage", []), int(a.m.get("dc", 10)), a.m.get("save", "dex"), a.m.get("half_on_save", true), a.m.get("condition", ""))
		"spell":
			return _eval_spell(c, a, reach)
		"feature":
			return _eval_feature(c, a, reach)
		"mprotector":
			var n = 0
			for o in eng.allies_of(c):
				if eng.dist(c, o) <= 10 and o.temp_hp == 0:
					n += 1
			return {"aid": a.id, "value": n * 3.0}
	return {}

func _target_value(c: Dictionary, t: Dictionary, dmg: float) -> float:
	# Prefer finishing blows and dangerous low-HP targets.
	var v = minf(dmg, float(t.hp) + 2.0)
	if dmg >= t.hp:
		v += 6.0
	if t.kind == "pc" and t.hp <= 0:
		return 0.5  # don't waste attacks on downed characters (mostly)
	# Sanctuary: the attack only happens if the attacker passes its WIS save.
	for e in t.effects:
		if e.get("tag", "") == "sanctuary" and eng.hostile(c, t):
			v *= eng.save_chance(c, "wis", int(e.get("dc", 13)))
	return v

func _eval_attack(c: Dictionary, a: Dictionary, reach: Dictionary, atks: Array) -> Dictionary:
	var first: Dictionary = atks[0]
	var rng: int = int(first.reach) if first.get("melee", true) else int(first.get("range", 0))
	if first.get("melee", true) and c.tags.has("long_limbed"):
		rng += 5
	if rng <= 0:
		rng = int(first.get("long_range", 5))
	var best = {}
	# Enemies Abound: every creature looks like a foe and the target is picked at random.
	var confused: bool = eng._sees_all_as_enemies(c)
	for t in eng.enemies_of(c):
		var pos = _candidate_cells(c, t, rng, reach, not first.get("melee", true))
		if pos.is_empty():
			continue
		var saved: Vector2i = c.pos
		c.pos = pos.cell
		var adv = eng.attack_advantage(c, t, first.get("melee", true), first)
		c.pos = saved
		var ev = 0.0
		for atk in atks:
			var p = eng.hit_chance(int(atk.get("to_hit", 0)), eng.eff_ac(t), adv)
			ev += p * _avg_parts(atk.get("damage", []))
		ev = _target_value(c, t, ev) - float(pos.cost) * 0.01
		if confused:
			ev = randf_range(1.0, 10.0)
		if best.is_empty() or ev > best.value:
			best = {"aid": a.id, "value": ev, "targets": [t.id], "cell": pos.cell}
	return best

func _eval_area(c: Dictionary, a: Dictionary, reach: Dictionary, dmg: Array, dc: int, save: String, half: bool, cond: String) -> Dictionary:
	var area: Dictionary = a.get("area", {})
	var avg = _avg_parts(dmg)
	if area.is_empty():
		# Single-target save.
		var best1 = {}
		for t in eng.enemies_of(c):
			var pos = _candidate_cells(c, t, maxi(5, int(a.range)), reach, true)
			if pos.is_empty():
				continue
			var fail = 1.0 if save == "" else 1.0 - eng.save_chance(t, save, dc)
			var ev = fail * avg + (1.0 - fail) * (avg / 2.0 if half else 0.0) + (fail * 12.0 if cond in ["paralyzed", "stunned", "incapacitated", "frightened", "restrained"] else 0.0)
			ev = _target_value(c, t, ev)
			if best1.is_empty() or ev > best1.value:
				best1 = {"aid": a.id, "value": ev, "targets": [t.id], "cell": pos.cell}
		return best1
	var from_self: bool = a.target in ["self_area", "self"]
	var best = {}
	var saved: Vector2i = c.pos
	var origins: Array = [c.pos]
	var near = _nearest_enemy(c)
	if not near.is_empty():
		var pc = _candidate_cells(c, near, maxi(5, int(area.get("size", 15)) - 5) if from_self else maxi(5, int(a.range)), reach, false)
		if not pc.is_empty():
			origins.append(pc.cell)
	for o_cell in origins:
		c.pos = o_cell
		var aims: Array = []
		for t in eng.enemies_of(c):
			aims.append(t.pos)
		if area.get("shape", "") == "emanation":
			aims = [c.pos]
		for aim in aims:
			if not from_self and eng.dist_to_cell(c, aim) > int(a.range):
				continue
			if not from_self and not eng.los_cells(c.pos, aim):
				continue
			var cells = eng.area_cells(c, area, aim, from_self)
			var ev = 0.0
			for v in eng.creatures_in_cells(cells, c.id):
				var fail = 1.0 if save == "" else 1.0 - eng.save_chance(v, save, dc)
				var e = fail * avg + (1.0 - fail) * (avg / 2.0 if half else 0.0)
				if cond != "":
					e += fail * 8.0
				if eng.hostile(c, v):
					ev += minf(e, float(v.hp) + 4.0) if v.hp > 0 else 0.0
				else:
					ev -= e * 1.5
			if best.is_empty() or ev > best.value:
				best = {"aid": a.id, "value": ev, "aim": aim, "cell": o_cell}
	c.pos = saved
	return best

func _eval_spell(c: Dictionary, a: Dictionary, reach: Dictionary, override: Dictionary = {}) -> Dictionary:
	var sp = Data.spell(a.spell)
	var cb = sp.get("combat", null) if override.is_empty() else override
	if not cb is Dictionary:
		return {}
	var cbd: Dictionary = cb
	var slot: int = a.slots[0]
	# Using a spell that is already running (a repeat) costs no slot and keeps concentration.
	var repeat: bool = not override.is_empty()
	var cost_pen = 0.0 if repeat else float(slot) * (3.0 if c.kind == "pc" else 1.0)
	if not repeat and sp.get("concentration", false) and not c.conc.is_empty():
		return {}
	var dc: int = a.dc
	var dmg = _avg_parts(cbd.get("damage", []))
	# Damage over time on a failed save (Caustic Brew, Phantasmal Force): count a couple of turns of it.
	var eff0 = cbd.get("effect", null)
	if dmg <= 0 and eff0 is Dictionary and eff0.get("tick_damage", null) is Dictionary:
		dmg = Dice.average(str(eff0.tick_damage.get("dice", "1d6"))) * 2.0
		cbd = cbd.duplicate(true)
		cbd.damage = [{"dice": "%d" % int(dmg), "type": str(eff0.tick_damage.get("type", "force"))}]
	if int(sp.level) == 0 and cbd.get("cantrip_scaling", false):
		var cl = int(c.get("cl", c.level))
		dmg *= 1 + (1 if cl >= 5 else 0) + (1 if cl >= 11 else 0) + (1 if cl >= 17 else 0)
	if cbd.get("upcast_dice", "") != "" and slot > int(sp.level):
		dmg += Dice.average(cbd.upcast_dice) * (slot - int(sp.level))
	if cbd.get("add_mod", false):
		dmg += float(caster_mod(c, a))
	var tgt: String = cbd.get("target", "self")
	# Animate Objects: ten Tiny objects next to the nearest enemy.
	if cbd.get("special", "") == "animate_objects":
		var foe = _nearest_enemy(c)
		if foe.is_empty() or eng.dist_to_cell(c, foe.pos) > int(a.range) or not eng.los_cells(c.pos, foe.pos):
			return {}
		var n: int = eng.animated_object_count("tiny", maxi(0, slot - int(sp.level)))
		return {"aid": a.id, "value": n * 4.0 - cost_pen, "aim": foe.pos, "slot": slot, "opts": {"obj_size": "tiny"}}
	# Magic Stone: casting it only readies stones (throwing them takes later actions), and recasting
	# would end the stones from the last casting that this caster or its allies still hold.
	if cbd.get("special", "") == "magic_stone":
		if eng.magic_stones_in_play(c.id) > 0 or _nearest_enemy(c).is_empty():
			return {}
		return {"aid": a.id, "value": dmg * 1.5 - cost_pen, "targets": [c.id], "slot": slot}
	# Healing.
	if cbd.has("heal"):
		var best_h = {}
		for o in eng.allies_of(c):
			var missing: int = o.max_hp - maxi(0, o.hp)
			if missing <= 0 or o.death.dead:
				continue
			var urgency = 3.0 if o.hp <= 0 else (1.5 if o.hp < o.max_hp * 0.35 else 0.4)
			var pos = _candidate_cells(c, o, maxi(5, int(a.range)), reach, false)
			if pos.is_empty():
				continue
			var v = minf(Dice.average(cbd.heal) + float(caster_mod(c, a)), float(missing)) * urgency - cost_pen + (12.0 if o.hp <= 0 else 0.0)
			if best_h.is_empty() or v > best_h.value:
				best_h = {"aid": a.id, "value": v, "targets": [o.id], "cell": pos.cell, "slot": slot}
		return best_h
	# Damage / control.
	if cbd.get("attack", null) != null:
		var rays = int(cbd.get("rays", 1)) + int(cbd.get("rays_per_slot", 0)) * maxi(0, slot - int(sp.level))
		if cbd.get("beams_scale", false):
			var cl2 = int(c.get("cl", c.level))
			rays = 1 + (1 if cl2 >= 5 else 0) + (1 if cl2 >= 11 else 0) + (1 if cl2 >= 17 else 0)
		var atk = {"to_hit": int(a.spell_attack), "damage": [{"dice": "%d" % int(dmg), "type": "force"}], "melee": cbd.attack == "melee", "reach": int(a.range), "range": int(a.range)}
		var plan = _eval_attack(c, a, reach, [atk])
		if plan.is_empty():
			return {}
		plan.value = plan.value * rays - cost_pen
		plan.slot = slot
		return plan
	if int(cbd.get("darts", 0)) > 0 or cbd.get("special", "") == "magic_missile":
		var t = _nearest_enemy(c)
		if t.is_empty():
			return {}
		var pos = _candidate_cells(c, t, int(a.range), reach, true)
		if pos.is_empty():
			return {}
		return {"aid": a.id, "value": 3.5 * (3 + slot - 1) - cost_pen, "targets": [t.id], "cell": pos.cell, "slot": slot}
	var cond: String = cbd.get("effect", {}).get("condition", "") if cbd.get("effect", null) is Dictionary else ""
	if cbd.get("save", null) != null and (dmg > 0 or cond != ""):
		var fake = a.duplicate()
		var plan2 = _eval_area(c, fake, reach, cbd.get("damage", []) if dmg > 0 else [], dc, cbd.save, cbd.get("half_on_save", false), cond)
		if plan2.is_empty():
			return {}
		if cond != "" and dmg <= 0:
			plan2.value += 4.0
		plan2.value -= cost_pen
		plan2.slot = slot
		if fake.area.is_empty() and a.target in ["enemy", "creature"]:
			pass
		return plan2
	# Lingering zones with no save on casting (Spike Growth, Cloudkill, Moonbeam, Cloud of Daggers):
	# value the creatures caught inside, counting a few turns of damage.
	if not cbd.get("zone", {}).is_empty() and not cbd.get("area", {}).is_empty():
		var z: Dictionary = cbd.zone
		var zparts: Array = (z.get("damage", []) as Array).duplicate(true)
		var zcond: String = z.get("effect", {}).get("condition", "") if z.get("effect", null) is Dictionary else ""
		if zparts.is_empty() and zcond == "":
			return {}
		if not zparts.is_empty() and cbd.get("upcast_dice", "") != "" and slot > int(sp.level):
			zparts[0].dice = Dice.add(str(zparts[0].dice), Dice.times(cbd.upcast_dice, slot - int(sp.level)))
		var zsave: String = str(z.get("save", ""))
		var zplan = _eval_area(c, a, reach, zparts, dc, zsave, z.get("half_on_save", false), zcond)
		if zplan.is_empty():
			return {}
		var turns: float = 2.0 if z.get("trigger", "start_turn") == "move" else 1.5
		zplan.value = zplan.value * turns - cost_pen
		zplan.slot = slot
		return zplan
	if not cbd.get("aura", {}).is_empty():
		var n = 0
		for o in eng.enemies_of(c):
			if eng.dist(c, o) <= int(cbd.aura.get("radius", 10)) + 15:
				n += 1
		return {"aid": a.id, "value": n * Dice.average(cbd.aura.get("damage", [{"dice": "2d8"}])[0].dice) * 1.2 - cost_pen, "slot": slot}
	# Buffs on allies (Bless etc.) when enemies are near.
	# Skip buffs the engine can't make do anything (Guidance, effects without mods), and
	# throwaway concentration cantrips that would block a real concentration spell later.
	var eff = cbd.get("effect", null)
	var useful: bool = eff is Dictionary and (not eff.get("mods", {}).is_empty() or str(eff.get("condition", "")) != "" or cbd.get("special", "") == "heroism")
	if cbd.get("special", "") in ["guidance", "resistance", "true_strike"] or int(sp.level) == 0:
		useful = false
	if useful and tgt in ["ally", "creature"] and sp.get("concentration", false):
		var targets: Array = []
		for o in eng.allies_of(c):
			if eng.dist(c, o) <= int(a.range):
				targets.append(o.id)
		var mx: int = int(a.max_targets) + int(a.targets_per_slot) * maxi(0, slot - int(sp.level))
		targets = targets.slice(0, mx)
		if targets.is_empty() or _nearest_enemy(c).is_empty():
			return {}
		return {"aid": a.id, "value": 2.5 * targets.size() - cost_pen + 2.0, "targets": targets, "slot": slot}
	return {}

## A running spell's repeat action (Call Lightning's bolt, Flame Blade, Bigby's Hand...): valued like
## casting its sub-block, without the slot cost. Moving a zone or ending the spell early (Holy Weapon's
## burst, detonating Delayed Blast Fireball) is left to the player.
func _eval_repeat(c: Dictionary, a: Dictionary, reach: Dictionary) -> Dictionary:
	var e: Dictionary = eng._repeat_effect(c, str(a.get("eid", "")))
	if e.is_empty():
		return {}
	var sp = Data.spell(str(e.spell))
	var rp: Dictionary = sp.combat.repeat
	var sub: Dictionary = rp.get("combat", {})
	if rp.get("ends_spell", false):
		return {}
	if sub.get("move_zone", false):
		return {}
	if sub.get("weapon_attack", false):
		return _eval_attack(c, a, reach, [eng._conjured_weapon(c, sp, sub, int(e.upl))])
	var fake: Dictionary = {"id": a.id, "spell": sp.id, "slots": [int(e.slot)], "dc": int(e.dc), "spell_attack": int(e.attack), "class": str(e.get("class", "")),
		"range": int(a.range), "area": sub.get("area", {}), "target": str(sub.get("target", "enemy")), "max_targets": int(sub.get("max_targets", 1)),
		"targets_per_slot": 0, "level": int(sp.level), "cost": a.cost}
	var plan: Dictionary = _eval_spell(c, fake, reach, sub)
	if plan.is_empty():
		return {}
	plan.aid = a.id
	plan.erase("slot")
	return plan

func caster_mod(c: Dictionary, a: Dictionary) -> int:
	return int(eng.caster_entry(c, a.get("class", "")).get("mod", 0))

func _eval_feature(c: Dictionary, a: Dictionary, reach: Dictionary) -> Dictionary:
	if a.get("repeat", false):
		return _eval_repeat(c, a, reach)
	if a.id == "swift_quiver":
		return _eval_attack(c, a, reach, [a.atk, a.atk])
	if a.has("atk"):
		return _eval_attack(c, a, reach, [a.atk])
	match a.id:
		"magic_stone_pickup":
			# Grab a stone lying within reach while it's free (a thrown stone beats most slams at range).
			if a.cost == "free":
				for it in eng.ground_items():
					if it.get("kind", "") == "magic_stone" and eng.dist_to_cell(c, it.pos) <= 5:
						return {"aid": a.id, "value": 3.0, "aim": it.pos}
		"sustain_spell":
			var su: Dictionary = c.conc.get("sustain", {})
			var st = eng.C(su.get("target", ""))
			var sdata: Dictionary = Data.spell(su.get("spell", "")).get("combat", {}).get("sustain", {})
			if not st.is_empty() and eng.dist(c, st) <= int(sdata.get("range", 30)) and eng.los(c, st):
				return {"aid": a.id, "value": _target_value(c, st, _avg_parts(sdata.get("damage", [])))}
		"dragons_breath":
			for e in c.effects:
				if e.get("eid", "") == a.get("eid", ""):
					var br: Dictionary = e.get("breath", {})
					return _eval_area(c, a, reach, [{"dice": br.get("dice", "3d6"), "type": br.get("type", "fire")}], int(e.get("dc", 13)), str(br.get("save", "dex")), true, "")
		"second_wind":
			if c.hp < c.max_hp * 0.5:
				return {"aid": a.id, "value": 8.0}
		"lay_on_hands", "healing_hands", "hand_of_healing", "healing_light":
			for o in eng.allies_of(c):
				if (o.hp <= 0 or o.hp < o.max_hp * 0.3) and not o.death.dead and not (a.id == "lay_on_hands" and str(o.get("type", "")) in ["undead", "construct"]):
					var pos = _candidate_cells(c, o, maxi(5, int(a.range)), reach, false)
					if not pos.is_empty():
						return {"aid": a.id, "value": 15.0 if o.hp <= 0 else 7.0, "targets": [o.id], "cell": pos.cell}
		"action_surge":
			if c.turn.get("action", 0) == 0 and _nearest_enemy(c).size() > 0 and eng.dist(c, _nearest_enemy(c)) <= 10:
				return {"aid": a.id, "value": 9.0}
		"flurry_of_blows":
			var t = _nearest_enemy(c)
			if not t.is_empty() and eng.dist(c, t) <= 5 and eng.res_left(c, "ki") >= 2:
				return {"aid": a.id, "value": 7.0, "targets": [t.id]}
		"turn_undead", "turn_the_unholy", "turn_the_faithless", "radiance_of_the_dawn", "conquering_presence", "fey_presence":
			var kinds: Dictionary = {"turn_undead": ["undead"], "turn_the_unholy": ["fiend", "undead"], "turn_the_faithless": ["fey", "fiend"]}
			var n = 0
			for o in eng.enemies_of(c):
				if eng.dist(c, o) <= int(a.range) and o.hp > 0 and not eng.has_tag(o, "turned") and (not kinds.has(a.id) or str(o.get("type", "")) in kinds[a.id]):
					n += 1
			if n >= 2 or (n >= 1 and a.id == "radiance_of_the_dawn"):
				return {"aid": a.id, "value": 6.0 * n}
		"preserve_life", "balm_of_peace":
			var hurt = 0
			for o in eng.allies_of(c):
				if eng.dist(c, o) <= int(a.range) and o.hp < o.max_hp / 2:
					hurt += 1
			if hurt >= 2:
				return {"aid": a.id, "value": 7.0 * hurt}
		"twilight_sanctuary", "emboldening_bond":
			if not eng.has_tag(c, "twilight_sanctuary") and not eng.has_tag(c, "bonded"):
				return {"aid": a.id, "value": 10.0}
		"breath_weapon":
			var br: Dictionary = c.breath
			return _eval_area(c, a, reach, [{"dice": c.vals.breath_dice, "type": br.type}], int(c.vals.breath_dc), br.save, true, "")
		"momentary_stasis":
			var t2 = _nearest_enemy(c)
			if not t2.is_empty() and eng.dist(c, t2) <= 60:
				return {"aid": a.id, "value": 6.0, "targets": [t2.id]}
		"bardic_inspiration":
			for o in eng.allies_of(c, false):
				if eng.dist(c, o) <= 60 and not eng.has_tag(o, "bardic_inspiration") and o.kind == "pc":
					return {"aid": a.id, "value": 3.0, "targets": [o.id]}
		"defensive_field":
			if c.temp_hp == 0 and c.hp < c.max_hp:
				return {"aid": a.id, "value": 4.0}
	return {}
