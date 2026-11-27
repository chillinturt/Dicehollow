class_name CombatEngine
extends EngineBase
## Turn flow, action lists and resolution of weapons, spells and class features.

const CANNON_TYPES := ["flamethrower", "force_ballista", "protector"]
## Effects that end when the target takes damage (charms end when the caster's side harms the target).
const END_ON_DAMAGE_SPELLS := ["sleep", "hypnotic_pattern", "charm_person", "charm_monster", "animal_friendship", "suggestion"]
## Healing spells that "have no effect on undead or constructs".
const NO_UNDEAD_HEALING := ["cure_wounds", "healing_word", "mass_cure_wounds", "mass_healing_word", "prayer_of_healing", "mass_heal"]
## The words a Command spell can give.
const COMMAND_WORDS := ["approach", "drop", "flee", "grovel", "halt"]

## Set by the session while it runs a request from a player who is playing the actor themselves.
## Only then does a weapon hit stop to ask about choices made after a hit (Divine Smite, Stunning
## Strike, maneuvers); the AI and tests use the pre-armed toggles instead.
var interactive := false

# ================================================================ turn flow

func current() -> Dictionary:
	if not s.in_combat or s.order.is_empty():
		return {}
	return C(s.order[clampi(s.turn, 0, s.order.size() - 1)])

func is_turn_of(c: Dictionary) -> bool:
	var cur = current()
	return not cur.is_empty() and cur.id == c.id

## Per-turn economy. Movement is derived, not stored: remaining = (speed + speed_bonus) x (1 + dashes) - moved,
## so a speed change mid-turn (Haste, grappled, Ray of Frost, Wild Shape) applies at once, as the rules say.
## "move" is a cached copy of move_left() for the UI.
func new_turn(c: Dictionary) -> Dictionary:
	return {"move": eff_speed(c), "moved": 0, "dashes": 0, "speed_bonus": 0, "speed_zero": false,
		"action": 1, "bonus": 1, "reaction": true, "attacks": 0, "attacked": false, "attacked_any": false,
		"cast_bonus": false, "cast_leveled_action": false, "once": {}, "disengaged": false, "melee_targets": [],
		"killed": false, "crit": false, "cantrip": false, "surged": false, "flurry": false, "haste_action": 0}

func start_combat() -> void:
	if s.in_combat:
		return
	# Arcane Recovery has to be used right after the short rest, not in the middle of a fight.
	for c in all_combatants():
		c.erase("arcane_budget")
	# Battle Smith defenders join automatically.
	for c in all_combatants():
		if alive(c) and c.features.has("steel_defender") and not _has_summon(c, "Steel Defender"):
			var d = CombatantFactory.steel_defender(new_id("s"), c)
			d.pos = _free_cell_near(c.pos)
			s.combatants[d.id] = d
	var order: Array = []
	for c in all_combatants():
		if not alive(c):
			continue
		c.turn = new_turn(c)
		c.acted = false
		c.rr_uses = 0
		if c.kind == "summon":
			continue
		var adv = 1 if c.get("init_adv", false) else 0
		var r = Dice.roll_d20(adv, c.tags.has("halfling_lucky"))
		var bonus: int = int(c.init_bonus) + int(mod_sum(c, "initiative"))
		for e in c.effects:
			if e.get("tag", "") == "gift_of_alacrity":
				bonus += Dice.d(8)
		c.init = int(r.roll) + bonus
		c.init_tiebreak = int(c.mods.get("dex", 0)) * 100 + Dice.d(99)
		order.append(c)
		log_line("%s rolls initiative: %d%s %s = [b]%d[/b]" % [nm(c), r.roll, " (adv)" if adv > 0 else "", Rules.fmt_mod(bonus), c.init])
	order.sort_custom(func(a, b): return [a.init, a.init_tiebreak] > [b.init, b.init_tiebreak])
	var ids: Array = []
	for c in order:
		ids.append(c.id)
		for o in all_combatants():
			if o.kind == "summon" and o.summoner == c.id and alive(o):
				o.init = c.init
				ids.append(o.id)
	s.order = ids
	s.turn = 0
	s.round = 1
	s.in_combat = true
	log_line("[color=#ffd166][b]⚔ Combat begins! Round 1[/b][/color]")
	# Inspiring Leader.
	for c in all_combatants():
		if c.get("feats", []).has("inspiring_leader"):
			for o in allies_of(c):
				grant_temp_hp(o, c.level + maxi(0, int(c.mods.cha)), "Inspiring Leader")
	if not s.order.is_empty():
		begin_turn(current())

func _has_summon(c: Dictionary, name: String) -> bool:
	for o in all_combatants():
		if o.get("summoner", "") == c.id and o.name == name and alive(o):
			return true
	return false

func _free_cell_near(p: Vector2i) -> Vector2i:
	for r in range(1, 6):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				var q = p + Vector2i(dx, dy)
				if in_bounds(q) and not blocks_move(q) and creature_at(q).is_empty():
					return q
	return p

func end_combat() -> void:
	settle_pending_hit()
	s.in_combat = false
	s.order = []
	s.round = 0
	for c in all_combatants():
		c.turn = {}
		end_wild_shape(c)
		# Combat-length effects (1 minute or less) end with the fight, conditions included.
		# Prone, grapples and other holds (which have no timer) end too.
		remove_effects_where(c, func(e): return int(e.get("rounds", 0)) <= 10 or e.get("cond", "") == "prone" or e.has("escape_dc"))
		c.hidden = false
		# Creatures kept in being by a concentration spell (Animate Objects) go when the fight ends.
		if c.get("conc_summon", "") != "" and not c.dead:
			var csrc = C(str(c.conc_summon).get_slice(":", 0))
			if not csrc.is_empty():
				end_concentration(csrc, true)
			c.dead = true
		if c.kind == "summon" and c.get("cannon", "") != "":
			c.dead = true
	# Loose magic stones lose their magic with the fight, like other effects of a minute or less.
	s.items = ground_items().filter(func(it): return int(it.get("rounds", 0)) > 10)
	log_line("[color=#ffd166][b]Combat ends.[/b][/color]")

func begin_turn(c: Dictionary) -> void:
	c.turn = new_turn(c)
	# A serial per turn taken, so "not on the turn it was cast" checks work whatever the round.
	s.turn_serial = int(s.get("turn_serial", 0)) + 1
	c.turn.serial = s.turn_serial
	c.acted = true
	refresh_teams()
	log_line("[color=#c9a14a]— %s's turn (round %d) —[/color]" % [c.name, s.round])
	tick_effects(c.id, "start")
	_tick_zones(c)
	_tick_ropes(c.id)
	_tick_items(c.id)
	_tick_damage(c, "start")
	if not alive(c):
		return
	if c.kind == "pc" and c.hp <= 0 and not c.death.dead:
		_death_save(c)
		return
	if c.tags.has("regeneration") and c.hp > 0 and c.hp < c.max_hp:
		var amt = int(c.tags.regeneration) if c.tags.regeneration is int else 10
		heal_creature(c, amt, c, "Regeneration")
	for name in c.recharge.keys():
		if not c.recharge[name]:
			var need = _recharge_need(c, name)
			var r = Dice.d(6)
			if r >= need:
				c.recharge[name] = true
				log_line("%s's %s recharges (%d)." % [nm(c), name, r])
	# Heroism temp HP.
	for e in c.effects:
		if e.get("tag", "") == "heroism":
			grant_temp_hp(c, int(e.get("value", 1)), "Heroism")
	# Zones and auras that hurt creatures starting their turn there.
	_zone_triggers(c)
	_aura_triggers(c, "start_turn")
	_halo_of_spores(c)
	if not alive(c) or c.hp <= 0:
		return
	if c.features.has("dread_ambusher") and s.round == 1:
		c.turn.speed_bonus = 10
		c.turn.ambush = true
	if has_tag(c, "haste"):
		c.turn.haste_action = 1
	release_broken_grapples()
	sync_move(c)
	# Starry archer / spiritual weapon etc. are handled as bonus actions.
	if is_incapacitated(c):
		log_line("%s is incapacitated and can't act." % nm(c))
	else:
		_compelled_move(c)
		_start_turn_compulsions(c)
	_storm_stages(c)

## Damage over time on `c` at the start or end of its turn (effect key "tick_damage"):
##   with "save": the creature saves first; success ends the spell, failure deals the damage
##     (Phantasmal Killer, Searing Smite's flames).
##   without: the damage just lands; "once" removes the effect afterwards (Melf's Acid Arrow).
func _tick_damage(c: Dictionary, when: String) -> void:
	for e in c.effects.duplicate():
		var td = e.get("tick_damage", null)
		if not td is Dictionary or str(td.get("when", "end")) != when or not e in c.effects or not alive(c):
			continue
		var src = C(e.get("src", ""))
		if td.has("save"):
			log_line("%s struggles against %s." % [nm(c), e.get("name", "an effect")])
			if saving_throw(c, str(td.save), int(e.get("dc", 10)), src, {"spell": true, "cond": e.get("cond", "")}):
				log_line("  %s is free of %s." % [nm(c), e.get("name", "")])
				c.effects.erase(e)
				# "On a success, the spell ends." (Weird: only for that creature, "spell_ends": false.)
				if td.get("spell_ends", true) and e.get("conc", false) and not src.is_empty() and src.conc.get("spell", "") == e.get("spell", ""):
					end_concentration(src, true)
				continue
		apply_damage(c, [{"amount": Dice.roll(str(td.dice)).total, "type": str(td.get("type", "force"))}], src, {"spell": true})
		if td.get("once", false):
			c.effects.erase(e)

## Compulsion: an affected creature spends its movement heading the way the caster chose
## (away from the caster unless a cell was picked) before it does anything else.
func _compelled_move(c: Dictionary) -> void:
	var ce = {}
	for e in c.effects:
		if e.get("tag", "") == "compelled":
			ce = e
	if ce.is_empty() or move_budget(c) <= 0:
		return
	var src = C(ce.get("src", ""))
	var toward = ce.get("toward", null)
	var anchor: Vector2 = Vector2(toward) if toward is Vector2i else (center_of(src) if not src.is_empty() else Vector2(c.pos))
	var away: bool = not toward is Vector2i
	var reach = reachable(c, move_budget(c))
	var best: Vector2i = c.pos
	var best_d: float = Vector2(c.pos).distance_to(anchor)
	for q in reach:
		if reach[q].get("occupied", false):
			continue
		var d: float = Vector2(q).distance_to(anchor)
		if (away and d > best_d + 0.01) or (not away and d < best_d - 0.01):
			best_d = d
			best = q
	if best != c.pos:
		log_line("%s is compelled to move." % nm(c))
		move(c, best)

## Spells that take over part of a creature's turn as it begins:
##   confused (Confusion): d10 — 1 wanders at random, 2-6 does nothing, 7-8 lashes out at a random
##     creature within reach, 9-10 acts normally. Either way it can't take reactions (mods.no_reactions).
##   crown_of_madness: it must spend its action attacking one of its own allies within reach, if any.
##   mind_whip (Tasha's Mind Whip): it gets only one of move, action or bonus action; here it keeps the action.
func _start_turn_compulsions(c: Dictionary) -> void:
	for e in c.effects.duplicate():
		if not e in c.effects or not alive(c) or c.hp <= 0:
			continue
		match str(e.get("tag", "")):
			"confused":
				var r: int = Dice.d(10)
				if r == 1:
					log_line("%s is confused and wanders off (%d)." % [nm(c), r])
					var reach = reachable(c, move_left(c))
					var cells: Array = reach.keys().filter(func(q): return not reach[q].get("occupied", false) and q != c.pos)
					if not cells.is_empty():
						move(c, cells[randi() % cells.size()])
					c.turn.action = 0
					c.turn.bonus = 0
					c.turn.speed_zero = true
				elif r <= 6:
					log_line("%s is confused and does nothing (%d)." % [nm(c), r])
					c.turn.action = 0
					c.turn.bonus = 0
					c.turn.speed_zero = true
				elif r <= 8:
					log_line("%s is confused and lashes out (%d)." % [nm(c), r])
					var atk = best_melee(c)
					var near: Array = all_combatants().filter(func(o): return alive(o) and o.id != c.id and not atk.is_empty() and dist(c, o) <= int(atk.get("reach", 5)))
					if not near.is_empty():
						_attack_with(c, near[randi() % near.size()], atk)
					c.turn.action = 0
					c.turn.bonus = 0
					c.turn.speed_zero = true
				else:
					log_line("%s shakes off the confusion for now (%d)." % [nm(c), r])
			"crown_of_madness":
				var atk2 = best_melee(c)
				var src = C(str(e.get("src", "")))
				var victim: Dictionary = {}
				for o in all_combatants():
					if alive(o) and o.id != c.id and o.hp > 0 and not src.is_empty() and o.id != src.id and hostile(src, o) and not atk2.is_empty() and dist(c, o) <= int(atk2.get("reach", 5)):
						victim = o
						break
				if not victim.is_empty():
					log_line("%s is driven to attack %s!" % [nm(c), nm(victim)])
					_attack_with(c, victim, atk2, {"opportunity": true})
					c.turn.action = 0
			"mind_whip":
				log_line("%s's mind reels: it can only take its action this turn." % nm(c))
				c.turn.bonus = 0
				c.turn.speed_zero = true
			"commanded":
				c.effects.erase(e)
				_obey_command(c, C(str(e.get("src", ""))), str(e.get("command", "grovel")))
			"turned":
				_turned_turn(c, C(str(e.get("src", ""))))
	sync_move(c)

## Command: the creature obeys the word on its turn, then the spell is spent.
func _obey_command(c: Dictionary, src: Dictionary, word: String) -> void:
	match word:
		"approach":
			# It moves straight toward the caster, and its turn ends if it gets within 5 ft.
			if not src.is_empty() and alive(src):
				_step_toward(c, src)
				if dist(c, src) <= 5:
					log_line("%s obeys the command to approach and ends its turn." % nm(c))
					_lose_turn(c)
				else:
					log_line("%s obeys the command to approach." % nm(c))
		"drop":
			log_line("%s obeys the command to drop what it is holding, and its turn ends." % nm(c))
			_lose_turn(c)
		"flee":
			log_line("%s obeys the command to flee." % nm(c))
			if not src.is_empty():
				_run_from(c, src, true)
			_lose_turn(c)
		"halt":
			log_line("%s obeys the command to halt: it doesn't move or act." % nm(c))
			_lose_turn(c)
		_:
			log_line("%s obeys the command to grovel: it falls prone and its turn ends." % nm(c))
			if not has_cond(c, "prone"):
				add_effect(c, {"name": "Prone", "cond": "prone", "src": c.id, "rounds": 99, "tick_cid": c.id})
			_lose_turn(c)

## Turned: the creature spends its turn getting as far from the turner as it can. It Dashes, or
## tries to break a hold that keeps it in place, and if it has nowhere to go it takes the Dodge action.
func _turned_turn(c: Dictionary, src: Dictionary) -> void:
	if src.is_empty():
		_lose_turn(c)
		return
	var hold: Dictionary = escape_effect(c)
	if move_left(c) <= 0 and not hold.is_empty():
		log_line("%s is turned and struggles to get away." % nm(c))
		_basic(c, {"id": "escape", "cost": "action"}, [])
		if escape_effect(c).is_empty() and alive(c):
			_run_from(c, src, false)
	elif _run_from(c, src, true):
		log_line("%s flees from %s." % [nm(c), nm(src)])
	else:
		log_line("%s is turned but has nowhere to run, so it cowers (Dodge)." % nm(c))
		add_effect(c, {"name": "Dodging", "tag": "dodge", "src": c.id, "rounds": 1, "tick_cid": c.id, "tick_on": "start"})
	_lose_turn(c)

## Move `c` as far from `from` as its movement allows. With `dash`, once it has moved it takes the
## Dash action and keeps going. Returns true if it moved at all.
func _run_from(c: Dictionary, from: Dictionary, dash: bool) -> bool:
	var moved := false
	for leg in (2 if dash else 1):
		if leg == 1:
			if not moved or not s.in_combat or int(c.turn.get("action", 0)) <= 0 or not alive(c) or c.hp <= 0:
				break
			pay(c, "action")
			c.turn.dashes = int(c.turn.get("dashes", 0)) + 1
			sync_move(c)
		var budget: int = move_left(c) if s.in_combat else eff_speed(c)
		if budget <= 0:
			break
		var reach = reachable(c, budget)
		var best: Vector2i = c.pos
		var best_d: int = _dist_from(c, c.pos, from)
		for q in reach:
			if reach[q].get("occupied", false):
				continue
			var d: int = _dist_from(c, q, from)
			if d > best_d:
				best_d = d
				best = q
		if best == c.pos:
			break
		move(c, best)
		moved = true
	return moved

## Move `c` along the most direct route toward `to`, as far as its movement allows.
func _step_toward(c: Dictionary, to: Dictionary) -> void:
	var budget: int = move_left(c) if s.in_combat else eff_speed(c)
	if budget <= 0:
		return
	var reach = reachable(c, budget)
	var best: Vector2i = c.pos
	var best_d: int = dist(c, to)
	for q in reach:
		if reach[q].get("occupied", false):
			continue
		var d: int = _dist_from(c, q, to)
		if d < best_d:
			best_d = d
			best = q
	if best != c.pos:
		move(c, best)

## The creature's turn is spent: no action, bonus action or further movement.
func _lose_turn(c: Dictionary) -> void:
	c.turn.action = 0
	c.turn.bonus = 0
	c.turn.haste_action = 0
	c.turn.speed_zero = true

## Storm of Vengeance: each round (on the caster's turn) the storm does something new over its area.
func _storm_stages(c: Dictionary) -> void:
	for z in s.zones.duplicate():
		if z.get("src", "") != c.id or not z.data.get("storm", false):
			continue
		z.stage = int(z.get("stage", 1)) + 1
		var inside: Array = creatures_in_cells(z.cells, c.id)
		match int(z.stage):
			2:
				log_line("Acidic rain falls from the storm.")
				for o in inside:
					apply_damage(o, [{"amount": Dice.roll("1d6").total, "type": "acid"}], c, {"spell": true})
			3:
				log_line("Six bolts of lightning lance down from the storm.")
				var foes: Array = inside.filter(func(o): return hostile(c, o)).slice(0, 6)
				for o in foes:
					fx("bolt", o.pos, o.pos, "#9fd0ff", [], "lightning")
					var ok = saving_throw(o, "dex", int(z.dc), c, {"spell": true})
					var amt: int = Dice.roll("10d6").total
					apply_damage(o, [{"amount": amt / 2 if ok else amt, "type": "lightning"}], c, {"spell": true})
			4:
				log_line("Hailstones pound everything under the storm.")
				for o in inside:
					apply_damage(o, [{"amount": Dice.roll("2d6").total, "type": "bludgeoning"}], c, {"spell": true})
			5:
				log_line("Gusts and freezing rain lash the area: it becomes difficult terrain and heavily obscured.")
				z.data = z.data.duplicate(true)
				z.data.difficult = true
				z.data.obscure = "storm"

## Count down the zones `c` created; they vanish when the spell's duration runs out
## (and a concentration zone takes the concentration with it).
func _tick_zones(c: Dictionary) -> void:
	for z in s.zones.duplicate():
		if z.get("src", "") != c.id or int(z.get("rounds", 0)) <= 0:
			continue
		z.rounds = int(z.rounds) - 1
		if z.rounds <= 0:
			s.zones.erase(z)
			log_line("%s fades away." % z.name)
			if z.get("conc", false) and c.conc.get("spell", "") == z.spell:
				end_concentration(c, true)

## Count down loose items whose magic comes from `cid` (magic stones on the ground last as long as the spell).
func _tick_items(cid: String) -> void:
	for it in ground_items().duplicate():
		if str(it.get("src", "")) != cid:
			continue
		it.rounds = int(it.get("rounds", 1)) - 1
		if it.rounds <= 0:
			ground_items().erase(it)
			log_line("A magic stone on the ground loses its glow.")

func _recharge_need(c: Dictionary, name: String) -> int:
	for a in c.attacks + c.mactions:
		if a.get("name", "") == name:
			return maxi(2, int(a.get("recharge", 5)))
	return 5

func _death_save(c: Dictionary) -> void:
	if c.death.stable:
		log_line("%s is unconscious but stable." % nm(c))
		return
	var r = Dice.d20()
	if r == 20:
		c.hp = 1
		c.death = {"s": 0, "f": 0, "stable": false, "dead": false}
		log_line("%s rolls a natural 20 on a death save and regains 1 HP!" % nm(c))
		float_text(c.id, "Nat 20!", "#ffd166")
		sync_move(c)
		return
	if r == 1:
		c.death.f += 2
	elif r >= 10:
		c.death.s += 1
	else:
		c.death.f += 1
	log_line("%s makes a death saving throw: %d (successes %d, failures %d)" % [nm(c), r, c.death.s, c.death.f])
	if c.death.f >= 3:
		_kill(c, "failed death saves")
	elif c.death.s >= 3:
		c.death.stable = true
		log_line("%s is now stable." % nm(c))

func end_turn() -> void:
	settle_pending_hit()
	var c = current()
	if c.is_empty():
		return
	_tick_damage(c, "end")
	# Repeat saves for "save ends" effects.
	for e in c.effects.duplicate():
		var se = e.get("save_ends", null)
		if se is Dictionary and not se.is_empty() and alive(c):
			log_line("%s tries to shake off %s." % [nm(c), e.get("name", "an effect")])
			if saving_throw(c, se.ability, int(se.dc), C(e.get("src", "")), {"spell": true, "cond": e.get("cond", "")}):
				c.effects.erase(e)
				log_line("  %s is no longer affected by %s." % [nm(c), e.get("name", "")])
	_save_countdowns(c)
	_end_turn_spells(c)
	_aura_triggers(c, "end_turn")
	_zone_triggers(c, "end_turn")
	tick_effects(c.id, "end")
	if c.has("toggles"):
		c.toggles.erase("reckless")
	c.hidden = c.get("hidden", false) and c.turn.get("stayed_hidden", true)
	_advance()

## Flesh to Stone, Contagion: the creature saves at the end of each of its turns, counting successes
## and failures. Three failures bring on the "on_fail" effect (petrified, a disease); three successes
## end the spell for it. save_count: {ability, fails, successes, on_fail: {effect data}}.
func _save_countdowns(c: Dictionary) -> void:
	for e in c.effects.duplicate():
		var sc = e.get("save_count", null)
		if not sc is Dictionary or not e in c.effects or not alive(c):
			continue
		var src = C(str(e.get("src", "")))
		log_line("%s struggles against %s." % [nm(c), e.get("name", "an effect")])
		if saving_throw(c, str(sc.get("ability", "con")), int(e.get("dc", 10)), src, {"spell": true}):
			e.successes = int(e.get("successes", 0)) + 1
		else:
			e.fails = int(e.get("fails", 0)) + 1
		log_line("  (%d success%s, %d failure%s)" % [int(e.get("successes", 0)), "" if int(e.get("successes", 0)) == 1 else "es", int(e.get("fails", 0)), "" if int(e.get("fails", 0)) == 1 else "s"])
		if int(e.get("fails", 0)) >= int(sc.get("fails", 3)):
			c.effects.erase(e)
			var of = sc.get("on_fail", null)
			if of is Dictionary:
				var ne = _make_effect(src if not src.is_empty() else c, Data.spell(str(e.get("spell", ""))), of, int(e.get("dc", 10)), "")
				# The final effect outlasts the caster's concentration (a petrified creature stays stone).
				ne.conc = false
				add_effect(c, ne)
				log_line("  %s succumbs: %s." % [nm(c), ne.get("name", "")])
		elif int(e.get("successes", 0)) >= int(sc.get("successes", 3)):
			c.effects.erase(e)
			log_line("  %s throws off %s." % [nm(c), e.get("name", "")])
			if e.get("conc", false) and not src.is_empty() and src.conc.get("spell", "") == e.get("spell", ""):
				end_concentration(src, true)

## End-of-turn spell upkeep on the creature whose turn it was.
func _end_turn_spells(c: Dictionary) -> void:
	# Delayed Blast Fireball: the bead grows 1d6 for every turn it waits.
	var bead = c.conc.get("bead", null) if c.get("conc", null) is Dictionary else null
	if bead is Dictionary:
		bead.extra = int(bead.get("extra", 0)) + 1
		log_line("The bead of fire glows brighter (+%dd6)." % int(bead.extra))
	for e in c.effects.duplicate():
		match str(e.get("tag", "")):
			# Reality Break: save at the end of each turn; a failure tears reality again.
			"reality_break":
				var rsrc = C(str(e.get("src", "")))
				if saving_throw(c, "wis", int(e.get("dc", 15)), rsrc, {"spell": true}):
					c.effects.erase(e)
					log_line("  Reality knits itself back together around %s." % nm(c))
					if not rsrc.is_empty() and rsrc.conc.get("spell", "") == "reality_break":
						end_concentration(rsrc, true)
				elif not rsrc.is_empty():
					_reality_tear(rsrc, c)
			# Blink: on 11+ the caster slips into the Ethereal Plane until the start of its next turn.
			"blink":
				var r: int = Dice.d20()
				if r >= 11:
					add_effect(c, {"name": "Ethereal", "pocket": "ethereal:" + c.id, "src": c.id, "spell": "blink", "rounds": 1, "tick_cid": c.id, "tick_on": "start"})
					log_line("%s blinks away to the Ethereal Plane (%d)." % [nm(c), r])
				else:
					log_line("%s stays put (Blink %d)." % [nm(c), r])

func _advance() -> void:
	if s.order.is_empty():
		return
	var n: int = s.order.size()
	for i in n:
		s.turn = int(s.turn) + 1
		if s.turn >= n:
			s.turn = 0
			s.round = int(s.round) + 1
			s.clock = int(s.get("clock", 0)) + 1
			log_line("[color=#ffd166][b]Round %d[/b][/color]" % s.round)
			_tick_orphan_effects()
		var nxt = C(s.order[s.turn])
		if alive(nxt) and not (nxt.kind != "pc" and nxt.hp <= 0):
			begin_turn(nxt)
			return
		# A dead or banished creature's turn is skipped, but effects timed on its turns
		# (a slain caster's Guiding Bolt, a dead monster's poison) still run out.
		if not nxt.is_empty():
			_tick_items(nxt.id)
			_tick_ropes(nxt.id)
			tick_effects(nxt.id, "start")
			tick_effects(nxt.id, "end")
	# Nobody can act.
	end_combat()

## Effects timed on the turns of a creature that is no longer in the initiative order
## (removed by the DM, or never in it) tick once per round so they don't last forever.
func _tick_orphan_effects() -> void:
	var seen = {}
	for o in all_combatants():
		for e in o.effects:
			var tc: String = e.get("tick_cid", "")
			if tc == "" or tc == "none" or tc in s.order:
				continue
			seen[tc] = true
	for it in ground_items().duplicate():
		if not str(it.get("src", "")) in s.order:
			seen[str(it.get("src", ""))] = true
	for tc in seen:
		tick_effects(tc, "start")
		_tick_items(tc)
		tick_effects(tc, "end")

func side_defeated() -> String:
	var party = false
	var enemy = false
	for c in all_combatants():
		if not alive(c) or c.hp <= 0 or c.kind == "summon":
			continue
		if c.team == "party": party = true
		else: enemy = true
	if s.in_combat and not enemy: return "enemy"
	if s.in_combat and not party: return "party"
	return ""

# ================================================================ zones & auras

## Zone triggers (zone.data.trigger):
##   start_turn (default): a creature starting its turn inside, or entering it for the first time on a turn
##                         (unless "enter": false, e.g. Stinking Cloud).
##   end_turn:             a creature ending its turn inside, or entering it (Create Bonfire, Flaming Sphere).
##   move:                 every 5 ft a creature moves inside it (Spike Growth).
## Each zone affects a creature at most once per turn (except "move" zones). "enemies_only" spares the caster's side.
func _zone_triggers(c: Dictionary, when := "start_turn") -> void:
	for z in s.zones.duplicate():
		if not z in s.zones or not alive(c) or c.hp <= 0 and c.kind != "pc":
			continue
		var trig: String = z.data.get("trigger", "start_turn")
		if trig != when or not _zone_applies(z, c) or not _in_zone(z, c, c.pos):
			continue
		if not _zone_once(z, c):
			continue
		log_line("%s %s its turn inside %s." % [nm(c), "starts" if when == "start_turn" else "ends", z.name])
		_resolve_area_effect(C(z.src), c, z.data, int(z.dc), z.spell, z.get("upl", 0), z)

func _zone_applies(z: Dictionary, c: Dictionary) -> bool:
	if rope_space(c) != "":
		return false
	var src = C(z.get("src", ""))
	if z.data.get("enemies_only", false) and not src.is_empty() and not hostile(src, c):
		return false
	# "Any creature other than you" (Dust Devil).
	if z.data.get("not_caster", false) and z.get("src", "") == c.id:
		return false
	return true

func _in_zone(z: Dictionary, c: Dictionary, at: Vector2i) -> bool:
	for p in occupied_cells(c, at):
		if p in z.cells:
			return true
	return false

## Marks zone `z` as having affected `c` this turn; false if it already did.
func _zone_once(z: Dictionary, c: Dictionary) -> bool:
	var key = "t%d" % int(s.get("turn_serial", 0))
	if not z.has("hit"):
		z.hit = {}
	if z.hit.get(c.id, "") == key:
		return false
	z.hit[c.id] = key
	return true

## A creature moved (walked, or was pushed or teleported) from `from` to `to`: zones it entered
## for the first time this turn, and "move" zones it travelled through, take effect.
func _zone_enter(c: Dictionary, from: Vector2i, to: Vector2i) -> void:
	if not s.in_combat:
		return
	for z in s.zones.duplicate():
		if not z in s.zones or not alive(c) or (c.hp <= 0 and c.kind != "pc"):
			continue
		if not _zone_applies(z, c) or not _in_zone(z, c, to):
			continue
		var trig: String = z.data.get("trigger", "start_turn")
		if trig == "move":
			log_line("%s moves through %s." % [nm(c), z.name])
			_resolve_area_effect(C(z.src), c, z.data, int(z.dc), z.spell, z.get("upl", 0), z)
			continue
		if _in_zone(z, c, from) or not z.data.get("enter", true) or trig == "none":
			continue
		if not _zone_once(z, c):
			continue
		log_line("%s enters %s." % [nm(c), z.name])
		_resolve_area_effect(C(z.src), c, z.data, int(z.dc), z.spell, z.get("upl", 0), z)
	# Auras with a damaging or controlling effect (Spirit Guardians) also hit creatures that move into them.
	for o in all_combatants():
		if not alive(o) or o.id == c.id or not alive(c) or not same_space(o, c):
			continue
		for e in o.effects:
			var a: Dictionary = e.get("aura", {})
			if a.is_empty() or not (a.has("damage") or a.has("save")) or a.get("trigger", "start_turn") != "start_turn":
				continue
			if a.get("enemies_only", false) and not hostile(o, c):
				continue
			if a.get("allies_only", false) and hostile(o, c):
				continue
			var r: int = int(a.get("radius", 10))
			if _dist_from(c, to, o) * 5 > r or _dist_from(c, from, o) * 5 <= r:
				continue
			if not _zone_once(e, c):
				continue
			log_line("%s moves into %s's %s." % [nm(c), o.name, e.get("name", "aura")])
			_resolve_area_effect(o, c, a, int(e.get("dc", best_spell_dc(o))), e.get("spell", ""), int(e.get("upl", 0)))
			break

func _aura_triggers(c: Dictionary, trigger: String) -> void:
	for a in _auras_affecting(c):
		var aura: Dictionary = a.aura
		if aura.get("trigger", "start_turn") != trigger:
			continue
		var src: Dictionary = a.src
		if aura.has("temp_hp"):
			var amt: int = Dice.roll(aura.temp_hp).total
			grant_temp_hp(c, amt, a.effect.get("name", "aura"))
			continue
		if not aura.has("damage") and not aura.has("save"):
			continue
		if trigger == "start_turn" and not _zone_once(a.effect, c):
			continue
		log_line("%s is caught in %s's %s." % [nm(c), src.name, a.effect.get("name", "aura")])
		_resolve_area_effect(src, c, aura, int(a.effect.get("dc", best_spell_dc(src))), a.effect.get("spell", ""), int(a.effect.get("upl", 0)))

func _resolve_area_effect(src: Dictionary, t: Dictionary, data: Dictionary, dc: int, spell_id: String, upl: int, zone: Dictionary = {}) -> void:
	# Healing zones (Healing Spirit) mend only the caster's side, and use up a charge each time.
	if data.has("heal"):
		if not src.is_empty() and hostile(src, t):
			return
		if t.hp >= t.max_hp:
			return
		var hd: String = str(data.heal)
		var hcb = Data.spell(spell_id).get("combat", null)
		if upl > 0 and hcb is Dictionary and str(hcb.get("upcast_heal", "")) != "":
			hd = Dice.add(hd, Dice.times(hcb.upcast_heal, upl))
		heal_creature(t, Dice.roll(hd, {"max": mod_any(t, "max_heal")}).total, src, Data.spell(spell_id).get("name", ""))
		_use_zone_charge(zone)
		return
	# Gas that only works on creatures that breathe (Stinking Cloud).
	if data.get("poison_gas", false) and ("poison" in t.immune or "poisoned" in t.cond_immune):
		log_line("  %s is unaffected by the gas." % nm(t))
		return
	# Sleet Storm, Earthquake: a concentrating creature inside must save or lose its spell.
	if data.get("conc_check", false) and not t.conc.is_empty():
		log_line("  %s fights to keep concentrating." % nm(t))
		if not saving_throw(t, "con", dc, src, {"concentration": true}):
			end_concentration(t)
	_use_zone_charge(zone)
	var ok = false
	if data.has("save"):
		ok = saving_throw(t, data.save, dc, src, {"spell": true, "cond": data.get("effect", {}).get("condition", "") if data.get("effect", null) is Dictionary else ""})
	if data.has("damage"):
		var parts: Array = []
		var first = true
		var half: bool = data.get("half_on_save", false)
		var evade: bool = data.get("save", "") == "dex" and t.features.has("evasion")
		var cb = Data.spell(spell_id).get("combat", null)
		for d in data.damage:
			var dice: String = d.dice
			if first and upl > 0 and cb is Dictionary and str(cb.get("upcast_dice", "")) != "":
				dice = Dice.add(dice, Dice.times(cb.upcast_dice, upl))
			first = false
			var amt: int = Dice.roll(dice).total
			if ok:
				amt = 0 if (evade or not half) else amt / 2
			elif evade and half:
				amt = amt / 2
			parts.append({"amount": amt, "type": d.type})
		if not parts.is_empty():
			apply_damage(t, parts, src, {"spell": true})
	if data.has("effect") and not ok and alive(t):
		var e = _make_effect(src, Data.spell(spell_id), data.effect, dc, data.get("save", ""))
		# Stacking effects (Sickening Radiance's exhaustion): each failure adds another level.
		if data.effect.get("stacking", false):
			var n: int = 1
			for old in t.effects:
				if old.get("spell", "") == spell_id and old.get("src", "") == e.src:
					n += 1
			e.name = "%s %d" % [e.name, n]
		var exists = false
		for old in t.effects:
			if old.get("name", "") == e.get("name", "") and old.get("src", "") == e.get("src", ""):
				exists = true
		if not exists:
			add_effect(t, e)
	if not ok and alive(t):
		var center: Vector2 = center_of(src) if src.has("pos") else Vector2(t.pos)
		if zone.has("center") and zone.center is Vector2i:
			center = Vector2(zone.center) + Vector2(0.5, 0.5)
		_forced_move(src, t, data, center, upl)
		# Stinking Cloud: the creature spends its action retching.
		if data.get("lose_action", false) and is_current(t) and t.get("turn", {}).has("action"):
			t.turn.action = 0
			log_line("  %s retches and loses its action." % nm(t))

# ---------------------------------------------------------------- shared spell mechanics

## Drop creatures a spell can't affect:
##   only_types / immune_types: creature types (Charm Person: humanoids; Cause Fear: not undead or constructs)
##   max_int: beasts too clever are unaffected (Animal Friendship: INT 3 or less)
##   near_first: extra targets must be within this many feet of the first (Chain Lightning 30, Acid Splash 5)
func _filter_spell_victims(c: Dictionary, cbd: Dictionary, victims: Array) -> Array:
	var only: Array = cbd.get("only_types", [])
	var immune: Array = cbd.get("immune_types", [])
	var max_int: int = int(cbd.get("max_int", 99))
	var out: Array = []
	for t in victims:
		var typ: String = str(t.get("type", "humanoid"))
		if t.get("kind", "") == "pc":
			typ = "humanoid"
		var ok: bool = true
		if not only.is_empty() and not typ in only:
			ok = false
		if typ in immune:
			ok = false
		if int(t.get("scores", {}).get("int", 10)) > max_int:
			ok = false
		if not ok:
			log_line("  %s is unaffected." % nm(t))
			continue
		out.append(t)
	var near: int = int(cbd.get("near_first", 0))
	if near > 0 and out.size() > 1:
		var first: Dictionary = out[0]
		var kept: Array = [first]
		for t in out.slice(1):
			if dist(first, t) <= near:
				kept.append(t)
			else:
				log_line("  %s is too far from %s to be caught." % [nm(t), nm(first)])
		out = kept
	return out

## Riders on the caster that also add to spell attacks (Spirit Shroud: any attack against a creature
## within 10 ft, and the target can't regain hit points until the caster's next turn).
func _spell_attack_riders(c: Dictionary, t: Dictionary, crit: bool) -> Array:
	var out: Array = []
	for e in c.effects:
		var ex = e.get("mods", {}).get("extra_damage", null)
		if not ex is Dictionary or not e.get("any_attack", false):
			continue
		if int(e.get("within", 0)) > 0 and dist(c, t) > int(e.within):
			continue
		out.append({"amount": Dice.roll(str(ex.dice), {"crit": crit}).total, "type": str(ex.type)})
		_shroud_no_heal(c, t, e)
	return out

func _shroud_no_heal(c: Dictionary, t: Dictionary, e: Dictionary) -> void:
	if e.get("no_heal_on_hit", false) and alive(t):
		add_effect(t, {"name": "Shrouded", "src": c.id, "spell": e.get("spell", ""), "mods": {"no_heal": true}, "rounds": 1, "tick_cid": c.id, "tick_on": "start"})

## Push, pull or jostle a creature that failed a save (or was hit), from combat or zone data:
##   push: away from the caster      push_center: away from the area's centre
##   pull: toward the caster         pull_center: toward the area's centre
##   random_move: a few feet in a random direction (Infestation)
##   max_size: largest size affected ("large", "medium"...); move_per_slot: extra feet per slot level
func _forced_move(src: Dictionary, t: Dictionary, data: Dictionary, center: Vector2, upl: int) -> void:
	if not alive(t) or t.hp <= 0 or src.is_empty():
		return
	var ms: String = str(data.get("max_size", "gargantuan"))
	if size_rank(t) > int(SIZE_RANK.get(ms, 5)):
		return
	var extra: int = int(data.get("move_per_slot", 0)) * upl
	if int(data.get("push", 0)) > 0:
		push_creature(t, center_of(src), int(data.push) + extra)
	if int(data.get("push_center", 0)) > 0:
		push_creature(t, center, int(data.push_center) + extra)
	if int(data.get("pull", 0)) > 0:
		pull_creature(t, center_of(src), int(data.pull) + extra)
	if int(data.get("pull_center", 0)) > 0:
		pull_creature(t, center, int(data.pull_center) + extra)
	if int(data.get("random_move", 0)) > 0:
		var dirs = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
		var d: Vector2i = dirs[randi() % dirs.size()]
		pull_creature(t, center_of(t) + Vector2(d) * 10.0, int(data.random_move))

## Drag `t` up to `ft` feet straight toward a point, stopping at anything in the way or when it
## would get no closer.
func pull_creature(t: Dictionary, toward: Vector2, ft: int) -> void:
	var start: Vector2i = t.pos
	var moved = false
	for i in ft / 5:
		var here: Vector2 = center_of(t)
		var dir: Vector2 = toward - here
		if dir.length() < 1.0:
			break
		var step := Vector2i(signi(roundi(dir.normalized().x * 1.4)), signi(roundi(dir.normalized().y * 1.4)))
		if step == Vector2i.ZERO:
			break
		var nxt: Vector2i = t.pos + step
		var ok = true
		for oc in occupied_cells(t, nxt):
			if blocks_move(oc) or not creature_at(oc, t.id).is_empty():
				ok = false
		if not ok or (here + Vector2(step)).distance_to(toward) >= here.distance_to(toward):
			break
		t.pos = nxt
		moved = true
	if moved:
		events.append({"t": "move", "cid": t.id, "path": [t.pos]})
		log_line("  %s is pulled %d ft." % [nm(t), cheb(start, t.pos) * 5])
		release_broken_grapples()
		_zone_enter(t, start, t.pos)

## Dissonant Whispers: the target uses its reaction (if it has one) to run as far from `from` as it can.
func _flee(t: Dictionary, from: Dictionary) -> void:
	if not alive(t) or t.hp <= 0 or not can_react(t) or eff_speed(t) <= 0:
		return
	use_reaction(t)
	var reach = reachable(t, eff_speed(t))
	var best: Vector2i = t.pos
	var best_d: int = dist(t, from)
	for q in reach:
		if reach[q].get("occupied", false):
			continue
		var d: int = _dist_from(t, q, from)
		if d > best_d:
			best_d = d
			best = q
	if best != t.pos:
		log_line("  %s flees in terror." % nm(t))
		move(t, best, true)

## A burst of damage around a cell (Ice Knife's shards, Hail of Thorns, Lightning Arrow):
## {radius, save, half_on_save, damage: [...], upcast: dice per slot level}.
func _burst(c: Dictionary, spell_id: String, at: Vector2i, data: Dictionary, dc: int, upl: int) -> void:
	var cells = area_cells(c, {"shape": "sphere", "size": int(data.get("radius", 5))}, at, false)
	fx("area", at, at, _dmg_color(data.get("damage", [{"type": "force"}])), cells, _dmg_sfx(data.get("damage", [])))
	# The burst's damage is rolled once for every creature it catches.
	var rolls: Array = []
	var first = true
	for d in data.get("damage", []):
		var dice: String = str(d.dice)
		if first and upl > 0 and str(data.get("upcast", "")) != "":
			dice = Dice.add(dice, Dice.times(str(data.upcast), upl))
		first = false
		rolls.append(Dice.roll(dice).total)
	for o in creatures_in_cells(cells, c.id if data.get("spare_caster", true) else ""):
		var ok: bool = false
		if data.has("save"):
			ok = saving_throw(o, str(data.save), dc, c, {"spell": true})
		var parts: Array = []
		var di = 0
		for d in data.get("damage", []):
			var amt: int = int(rolls[di])
			di += 1
			if ok:
				amt = amt / 2 if data.get("half_on_save", false) else 0
			parts.append({"amount": amt, "type": str(d.type)})
		if not parts.is_empty():
			apply_damage(o, parts, c, {"spell": true})

## A zone with limited uses spends one; it vanishes when none are left.
func _use_zone_charge(zone: Dictionary) -> void:
	if zone.is_empty() or not zone.has("uses"):
		return
	zone.uses = int(zone.uses) - 1
	if int(zone.uses) <= 0 and zone in s.zones:
		s.zones.erase(zone)
		log_line("%s is spent." % zone.get("name", "The spell"))

func _halo_of_spores(c: Dictionary) -> void:
	for d in enemies_of(c):
		if d.features.has("halo_of_spores") and can_react(d) and dist(d, c) <= 10:
			use_reaction(d)
			var lv: int = d.class_levels.get("druid", 2)
			var die = "1d4" if lv < 6 else ("1d6" if lv < 10 else ("1d8" if lv < 14 else "1d10"))
			if has_tag(d, "symbiotic"):
				die = Dice.times(die, 2)
			log_line("%s's Halo of Spores lashes %s." % [nm(d), nm(c)])
			var dc = best_spell_dc(d)
			if not saving_throw(c, "con", dc, d, {"magic": true}):
				apply_damage(c, [{"amount": Dice.roll(die).total, "type": "necrotic"}], d, {"magic": true})
			return

# ================================================================ movement
#
# Rules enforced here (5e 2014, PHB ch. 9):
# - Movement allowance = speed x (1 + Dashes), minus feet already moved. A speed change mid-turn
#   is applied straight away (speed 0 = no more movement).
# - Difficult terrain, and any other creature's space, costs 1 extra foot per foot.
# - You can move through an ally's space but not end there. You can move through a hostile
#   creature's space only if it is at least two sizes larger or smaller than you.
# - Standing up from prone costs half your speed. If you can't afford it you crawl (1 extra foot per foot).
# - A frightened creature can't willingly move closer to the source of its fear.
# - Leaving a hostile creature's reach provokes an opportunity attack if it can see you,
#   unless you Disengaged (Sentinel ignores Disengage; a Sentinel hit drops your speed to 0).

## Feet of movement left this turn.
func move_left(c: Dictionary) -> int:
	if not s.in_combat:
		return 9999
	var t: Dictionary = c.get("turn", {})
	if t.is_empty() or t.get("speed_zero", false):
		return 0
	var sp: int = eff_speed(c)
	if sp <= 0:
		return 0
	var allowance: int = (sp + int(t.get("speed_bonus", 0))) * (1 + int(t.get("dashes", 0)))
	return maxi(0, allowance - int(t.get("moved", 0)))

## Refresh the cached "move" number that the HUD shows.
func sync_move(c: Dictionary) -> void:
	if not c.is_empty() and c.get("turn", {}) is Dictionary and not c.get("turn", {}).is_empty():
		c.turn.move = move_left(c)

func stand_cost(c: Dictionary) -> int:
	return (eff_speed(c) + int(c.get("turn", {}).get("speed_bonus", 0))) / 2

func can_stand(c: Dictionary) -> bool:
	return has_cond(c, "prone") and c.hp > 0 and eff_speed(c) > 0 and move_left(c) >= stand_cost(c)

func _crawling(c: Dictionary) -> bool:
	return s.in_combat and has_cond(c, "prone") and c.hp > 0 and not can_stand(c)

## Feet available for travel: what's left after standing up if prone (and able to stand).
func move_budget(c: Dictionary) -> int:
	var left = move_left(c)
	if s.in_combat and has_cond(c, "prone") and c.hp > 0 and can_stand(c):
		return left - stand_cost(c)
	return left

## Creatures `c` is frightened of and can see.
func _fear_sources(c: Dictionary) -> Array:
	var out: Array = []
	for e in c.effects:
		if e.get("cond", "") == "frightened":
			var src = C(e.get("src", ""))
			if alive(src) and src.id != c.id and can_see(c, src):
				out.append(src)
	return out

func _dist_from(c: Dictionary, at: Vector2i, o: Dictionary) -> int:
	var best = 9999
	for p in occupied_cells(c, at):
		for q in occupied_cells(o):
			best = mini(best, cheb(p, q))
	return best

## Dijkstra over the grid. Returns {cell: {"cost": ft, "from": cell}} for reachable cells within budget.
func reachable(c: Dictionary, budget: int) -> Dictionary:
	var start: Vector2i = c.pos
	var dist_map = {start: {"cost": 0, "from": start}}
	var frontier: Array = [[0, start]]
	var dirs = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
	# The Fly spell grants flight through its effect (mods.fly).
	var flying: bool = (int(c.get("fly", 0)) > 0 and c.form.is_empty()) or mod_sum(c, "fly") > 0
	# Earthbind: no flying.
	if mod_any(c, "no_fly"):
		flying = false
	var enforce: bool = s.in_combat
	var crawl: bool = enforce and _crawling(c)
	var fears: Array = _fear_sources(c) if enforce else []
	# Compelled Duel: no step may take the creature more than 30 ft from the caster.
	var leashes: Array = []
	if enforce:
		for e in c.effects:
			if int(e.get("mods", {}).get("leash", 0)) > 0 and not C(str(e.get("src", ""))).is_empty():
				leashes.append([C(str(e.src)), int(e.mods.leash)])
	while not frontier.is_empty():
		var best_i = 0
		for i in frontier.size():
			if frontier[i][0] < frontier[best_i][0]:
				best_i = i
		var cur: Array = frontier[best_i]
		frontier.remove_at(best_i)
		var cost: int = cur[0]
		var p: Vector2i = cur[1]
		if cost > dist_map[p].cost:
			continue
		for d in dirs:
			var q: Vector2i = p + d
			if not _can_stand_path(c, q, flying):
				continue
			if d.x != 0 and d.y != 0:
				if blocks_move(Vector2i(p.x + d.x, p.y)) or blocks_move(Vector2i(p.x, p.y + d.y)):
					continue
			# Frightened: no step may bring you closer to what you fear.
			var nearer = false
			for f in fears:
				if _dist_from(c, q, f) < _dist_from(c, p, f):
					nearer = true
					break
			if nearer:
				continue
			var leashed = false
			for l in leashes:
				if _dist_from(c, q, l[0]) * 5 > int(l[1]) and _dist_from(c, q, l[0]) > _dist_from(c, p, l[0]):
					leashed = true
			if leashed:
				continue
			var step = 5
			if enforce:
				for oc in occupied_cells(c, q):
					if (not flying and is_difficult(oc, c)) or (not creature_at(oc, c.id).is_empty() and not mod_any(c, "pass_creatures")):
						step = 10
						break
			if crawl:
				step += 5
			var nc = cost + step
			if nc > budget:
				continue
			if not dist_map.has(q) or nc < dist_map[q].cost:
				dist_map[q] = {"cost": nc, "from": p}
				frontier.append([nc, q])
	# Mark cells occupied by others (you can pass through allies but not end there).
	for q in dist_map.keys():
		dist_map[q].occupied = false
		if q == start:
			continue
		for oc in occupied_cells(c, q):
			if not creature_at(oc, c.id).is_empty():
				dist_map[q].occupied = true
				break
	return dist_map

func _truthy(v) -> bool:
	if v is bool:
		return v
	if v is int or v is float:
		return v != 0
	if v is String:
		return v != ""
	return v != null

func _can_stand_path(c: Dictionary, q: Vector2i, flying: bool) -> bool:
	for oc in occupied_cells(c, q):
		if not in_bounds(oc):
			return false
		var v = cell(oc)
		if v == WALL or (v == PIT and not flying):
			return false
		var o = creature_at(oc, c.id)
		# A hostile creature's space can only be crossed if it is two or more sizes apart from you
		# (Kinetic Jaunt lets you move through any creature's space).
		if not o.is_empty() and hostile(o, c) and absi(size_rank(o) - size_rank(c)) < 2 and not mod_any(c, "pass_creatures"):
			return false
	return true

func path_to(c: Dictionary, dest: Vector2i, reach: Dictionary) -> Array:
	var path: Array = []
	if not reach.has(dest) or reach[dest].get("occupied", false):
		return path
	var p = dest
	while p != c.pos:
		path.push_front(p)
		p = reach[p].from
	return path

## Spend half your speed to stand up from prone. Returns false if you can't afford it.
func stand_up(c: Dictionary) -> bool:
	if not has_cond(c, "prone"):
		return true
	if s.in_combat:
		if not can_stand(c):
			return false
		c.turn.moved = int(c.turn.get("moved", 0)) + stand_cost(c)
	remove_effects_where(c, func(e): return e.get("cond", "") == "prone")
	log_line("%s stands up." % nm(c))
	sync_move(c)
	return true

## Move a combatant along a path to dest. Returns true if it moved at all.
func move(c: Dictionary, dest: Vector2i, free := false) -> bool:
	settle_pending_hit()
	if c.pos == dest and not in_rope(c):
		return false
	var enforce: bool = s.in_combat and not free
	if enforce:
		if move_left(c) <= 0:
			return false
		# Standing up comes first if it's affordable; otherwise the creature crawls.
		if has_cond(c, "prone") and c.hp > 0 and can_stand(c):
			stand_up(c)
	# Leaving a Rope Trick space: the creature drops to the ground under the rope (which costs no
	# movement) and carries on from there. A cell it couldn't reach from there leaves it inside.
	if in_rope(c):
		var land: Vector2i = rope_landing(c)
		if dest != land:
			var held: Vector2i = c.pos
			c.pos = land
			var from_land = reachable(c, move_left(c) if enforce else 9999)
			c.pos = held
			if not from_land.has(dest) or from_land[dest].get("occupied", false):
				return false
		exit_rope(c)
		if c.pos == dest or not alive(c) or c.hp <= 0:
			return true
	var budget: int = move_left(c) if enforce else 9999
	var reach = reachable(c, budget)
	var path = path_to(c, dest, reach)
	if path.is_empty():
		return false
	var walked: Array = [c.pos]
	var prev: Vector2i = c.pos
	for step in path:
		var step_cost: int = int(reach[step].cost) - int(reach[prev].cost)
		if enforce:
			# Re-check every step: a reaction (Sentinel, a grapple) can change speed mid-move.
			if step_cost > move_left(c):
				break
			_opportunity_attacks(c, prev, step)
			if not alive(c) or c.hp <= 0 or step_cost > move_left(c):
				break
		c.pos = step
		walked.append(step)
		var came_from: Vector2i = prev
		prev = step
		if enforce:
			c.turn.moved = int(c.turn.get("moved", 0)) + step_cost
		# Moonbeam, Spike Growth, Spirit Guardians... trigger as the creature moves in.
		if enforce:
			_zone_enter(c, came_from, step)
			if not alive(c) or c.hp <= 0:
				break
		# Ashardalon's Stride: creatures the caster passes within 5 ft of take fire (once a turn each).
		if enforce:
			_trail_damage(c)
		# Booming Blade detonates when the target willingly moves.
		for e in c.effects.duplicate():
			if e.get("tag", "") == "booming_blade":
				c.effects.erase(e)
				log_line("%s moves and the booming energy detonates!" % nm(c))
				apply_damage(c, [{"amount": Dice.roll(e.dice).total, "type": "thunder"}], C(e.src), {"spell": true})
		if not alive(c) or c.hp <= 0:
			break
	if enforce:
		sync_move(c)
	if walked.size() > 1:
		events.append({"t": "move", "cid": c.id, "path": walked})
		release_broken_grapples()
	return walked.size() > 1

## Effects with "trail": {dice, type, upcast} burn every creature the bearer moves within 5 ft of,
## once per turn per creature (Ashardalon's Stride).
func _trail_damage(c: Dictionary) -> void:
	for e in c.effects:
		var trl = e.get("trail", null)
		if not trl is Dictionary:
			continue
		if not e.has("trail_hit"):
			e.trail_hit = {}
		var key := "t%d" % int(s.get("turn_serial", 0))
		for o in all_combatants():
			if not alive(o) or o.id == c.id or o.hp <= 0 or not same_space(c, o) or dist(c, o) > 5 or e.trail_hit.get(o.id, "") == key:
				continue
			e.trail_hit[o.id] = key
			var dice: String = str(trl.get("dice", "1d6"))
			if int(e.get("upl", 0)) > 0 and str(trl.get("upcast", "")) != "":
				dice = Dice.add(dice, Dice.times(str(trl.upcast), int(e.upl)))
			log_line("  Flames trail behind %s and lick at %s." % [nm(c), nm(o)])
			apply_damage(o, [{"amount": Dice.roll(dice).total, "type": str(trl.get("type", "fire"))}], c, {"spell": true})

## A grapple ends when the grappler is incapacitated or the two end up out of its reach.
func release_broken_grapples() -> void:
	for o in all_combatants():
		for e in o.effects.duplicate():
			if e.get("cond", "") != "grappled" or not e.has("escape_dc"):
				continue
			var g = C(e.get("src", ""))
			if g.is_empty() or not alive(g) or g.hp <= 0 or is_incapacitated(g) or not same_space(g, o) or dist(g, o) > _reach_of(g):
				o.effects.erase(e)
				log_line("%s is no longer grappled." % nm(o))
				sync_move(o)

func _reach_of(c: Dictionary) -> int:
	var r = 5
	for a in attacks_of(c):
		if a.get("melee", false):
			r = maxi(r, int(a.get("reach", 5)))
	if c.tags.has("long_limbed") and is_turn_of(c):
		r += 5
	return r

func _opportunity_attacks(mover: Dictionary, from: Vector2i, to: Vector2i) -> void:
	var disengaged: bool = mover.get("turn", {}).get("disengaged", false) or mod_any(mover, "no_provoke")
	# Hidden creatures can still make opportunity attacks, so don't use enemies_of() here.
	var foes = all_combatants().filter(func(o): return alive(o) and hostile(o, mover) and same_space(o, mover))
	for o in foes:
		if not can_react(o) or (o.kind == "summon" and o.get("cannon", "") != ""):
			continue
		var sentinel: bool = o.get("feats", []).has("sentinel")
		if disengaged and not sentinel:
			continue
		if not can_see(o, mover):
			continue
		var reach = _reach_of(o)
		var was_in = false
		var now_in = false
		for p in occupied_cells(o):
			for q in occupied_cells(mover, from):
				if cheb(p, q) * 5 <= reach: was_in = true
			for q in occupied_cells(mover, to):
				if cheb(p, q) * 5 <= reach: now_in = true
		if not was_in or now_in:
			continue
		if (mover.get("feats", []).has("mobile") or mover.features.has("fancy_footwork")) and o.id in mover.get("turn", {}).get("melee_targets", []):
			continue
		var atk = best_melee(o)
		if atk.is_empty():
			continue
		use_reaction(o)
		log_line("%s makes an [b]opportunity attack[/b] against %s!" % [nm(o), nm(mover)])
		var r = _attack_with(o, mover, atk, {"opportunity": true})
		if r.get("hit", false) and sentinel and mover.get("turn", {}) is Dictionary and not mover.turn.is_empty():
			mover.turn.speed_zero = true
			log_line("  %s's Sentinel stops %s in place (speed 0 this turn)." % [nm(o), nm(mover)])
		if not alive(mover) or mover.hp <= 0:
			return

func best_melee(c: Dictionary) -> Dictionary:
	var best = {}
	var best_v = -1.0
	for a in attacks_of(c):
		if a.get("melee", false) and a.get("cost", "attack") != "bonus":
			var v = 0.0
			for d in a.damage:
				v += Dice.average(d.dice)
			if v > best_v:
				best_v = v
				best = a
	return best

func push_creature(t: Dictionary, from: Vector2, ft: int) -> void:
	var dir = (center_of(t) - from).normalized()
	if dir == Vector2.ZERO:
		return
	var steps = ft / 5
	var moved = false
	var start: Vector2i = t.pos
	for i in steps:
		var nxt = Vector2i((center_of(t) - Vector2(0.5, 0.5) + dir).round())
		var ok = true
		for oc in occupied_cells(t, nxt):
			if blocks_move(oc) or not creature_at(oc, t.id).is_empty():
				ok = false
		if not ok:
			break
		t.pos = nxt
		moved = true
	if moved:
		events.append({"t": "move", "cid": t.id, "path": [t.pos]})
		log_line("  %s is pushed back." % nm(t))
		release_broken_grapples()
		_zone_enter(t, start, t.pos)

func teleport(c: Dictionary, dest: Vector2i) -> bool:
	for oc in occupied_cells(c, dest):
		if blocks_move(oc) or not creature_at(oc, c.id).is_empty():
			return false
	var from: Vector2i = c.pos
	c.pos = dest
	events.append({"t": "teleport", "cid": c.id, "from": from, "to": dest})
	fx("burst", from, dest, "#b38cff")
	release_broken_grapples()
	_zone_enter(c, from, dest)
	return true

# ================================================================ action lists

func attacks_of(c: Dictionary) -> Array:
	if not c.form.is_empty():
		return c.form.attacks
	var out: Array = c.attacks.duplicate()
	# Shillelagh swaps club/quarterstaff to the spellcasting stat and a d8.
	if has_tag(c, "shillelagh"):
		var e = caster_entry(c, "druid")
		var m: int = int(e.get("mod", 0))
		var outs: Array = []
		for a in out:
			if a.get("weapon", "") in ["club", "quarterstaff"]:
				var b: Dictionary = a.duplicate(true)
				b.to_hit = m + int(c.prof)
				b.damage = [{"dice": "1d8+%d" % m, "type": "bludgeoning"}]
				b.magic = true
				b.name += " (Shillelagh)"
				outs.append(b)
			else:
				outs.append(a)
		out = outs
	return out

func can_pay(c: Dictionary, cost: String) -> bool:
	if not s.in_combat:
		return cost != "reaction"
	if not is_turn_of(c):
		return false
	var t: Dictionary = c.turn
	match cost:
		"action": return int(t.action) > 0
		"attack": return int(t.attacks) > 0 or int(t.action) > 0 or _haste_ready(c)
		"haste": return _haste_ready(c)
		"bonus": return int(t.bonus) > 0
		"free": return true
	return false

## Haste's extra action: one weapon attack, Dash, Disengage, Hide or Use an Object.
func _haste_ready(c: Dictionary) -> bool:
	return int(c.turn.get("haste_action", 0)) > 0 and has_tag(c, "haste")

## Why a spell with this casting cost can't be cast now ("" if it can).
## Rule: after a bonus-action spell, the only other spell you can cast that turn is a cantrip
## with a casting time of 1 action, and the reverse holds too.
func spell_block_reason(c: Dictionary, cost: String, level: int) -> String:
	if not s.in_combat or not is_turn_of(c):
		return ""
	var t: Dictionary = c.turn
	match cost:
		"bonus":
			if t.get("cast_bonus", false):
				return "Already cast a bonus-action spell"
			if t.get("cast_leveled_action", false):
				return "After a leveled spell, no bonus-action spells"
		"action":
			if t.get("cast_bonus", false) and level > 0:
				return "After a bonus-action spell, only cantrips"
	return ""

func pay(c: Dictionary, cost: String, sustaining := false) -> void:
	if not s.in_combat:
		return
	var t: Dictionary = c.turn
	match cost:
		"action":
			if int(t.action) > 0:
				t.action -= 1
				if not sustaining:
					_action_spent_elsewhere(c)
			else:
				t.haste_action = 0
		"bonus":
			t.bonus -= 1
		"haste":
			t.haste_action = 0
		"attack":
			if int(t.attacks) > 0:
				t.attacks -= 1
			elif int(t.action) > 0:
				t.action -= 1
				_action_spent_elsewhere(c)
				t.attacked = true
				var n: int = int(c.vals.get("attacks", 1)) if c.form.is_empty() else 1
				if c.form.is_empty() and c.features.has("extra_attack") and c.class_levels.get("druid", 0) > 0:
					n = int(c.vals.get("attacks", 1))
				if t.get("ambush", false):
					n += 1
					t.ambush_extra = true
				t.attacks = n - 1
			else:
				t.haste_action = 0
				t.attacked = true

## Witch Bolt: on a later turn, spending your action on anything but the bolt ends the spell.
func _action_spent_elsewhere(c: Dictionary) -> void:
	var su: Dictionary = c.conc.get("sustain", {}) if c.get("conc", null) is Dictionary else {}
	if su.is_empty() or int(su.get("cast_serial", -1)) == int(c.get("turn", {}).get("serial", -2)):
		return
	var sp = Data.spell(su.get("spell", ""))
	var data = sp.get("combat", {}).get("sustain", {}) if sp.get("combat", null) is Dictionary else {}
	if data is Dictionary and data.get("ends_on_other_action", false):
		log_line("%s turns its action elsewhere: %s ends." % [nm(c), sp.get("name", "the spell")])
		end_concentration(c, true)

func _act(id: String, name: String, kind: String, cost: String, target: String, rng: int, desc: String, extra := {}) -> Dictionary:
	var a = {"id": id, "name": name, "kind": kind, "cost": cost, "target": target, "range": rng, "desc": desc, "enabled": true, "reason": "", "cat": extra.get("cat", kind)}
	a.merge(extra, true)
	return a

func get_actions(c: Dictionary) -> Array:
	var out: Array = []
	if c.is_empty() or not alive(c) or c.hp <= 0:
		return out
	var inc = is_incapacitated(c)
	var t: Dictionary = c.get("turn", {})
	# --- weapon / natural attacks
	for atk in attacks_of(c):
		var cost: String = atk.get("cost", "attack")
		var rng: int = int(atk.reach) if atk.melee else int(atk.get("long_range", 0) if int(atk.get("long_range", 0)) > 0 else atk.get("range", 0))
		if atk.melee and c.tags.has("long_limbed"): rng += 5
		var a = _act("atk:" + atk.id, atk.name, "weapon", cost, "enemy", rng, _weapon_desc(atk), {"atk": atk, "cat": "attack"})
		if cost == "bonus" and not t.get("attacked", false) and s.in_combat:
			a.enabled = false
			a.reason = "Take the Attack action first"
		if int(atk.get("recharge", 0)) > 0 and not c.recharge.get(atk.name, true):
			a.enabled = false
			a.reason = "Recharging"
		out.append(a)
	# --- monster special actions
	var macts: Array = c.form.get("mactions", []) if not c.form.is_empty() else c.mactions
	for m in macts:
		out.append(_monster_action(c, m, "action"))
	if c.form.is_empty():
		for m in c.bonus_actions:
			if m.get("kind", "") in ["melee", "ranged"]:
				var atk2 = {"id": m.id, "name": m.name, "melee": m.kind == "melee", "to_hit": int(m.get("to_hit", 0)), "damage": m.get("damage", []), "reach": int(m.get("reach", 5)), "range": int(m.get("range", 0)), "long_range": int(m.get("long_range", 0)), "on_hit": m.get("on_hit", {}), "props": [], "monster": true}
				out.append(_act("atk:" + m.id, m.name, "weapon", "bonus", "enemy", int(atk2.reach) if atk2.melee else int(atk2.range), _weapon_desc(atk2), {"atk": atk2, "cat": "attack", "bonus_free": true}))
			else:
				out.append(_monster_action(c, m, "bonus"))
	# --- spells
	if c.form.is_empty() or c.class_levels.get("druid", 0) >= 18:
		out.append_array(_spell_actions(c))
	# --- class / race features
	out.append_array(_feature_actions(c))
	# --- basic actions
	# With the regular action spent, Haste's extra action can still Dash, Disengage or Hide.
	var lim: String = "haste" if s.in_combat and int(t.get("action", 0)) <= 0 and _haste_ready(c) else "action"
	out.append(_act("dash", "Dash", "basic", lim, "self", 0, "Gain extra movement equal to your speed this turn.", {"cat": "basic"}))
	out.append(_act("disengage", "Disengage", "basic", lim, "self", 0, "Your movement doesn't provoke opportunity attacks this turn.", {"cat": "basic"}))
	out.append(_act("dodge", "Dodge", "basic", "action", "self", 0, "Attacks against you have disadvantage and you have advantage on DEX saves until your next turn.", {"cat": "basic"}))
	out.append(_act("help", "Help", "basic", "action", "enemy", 5, "Distract an adjacent enemy: the next ally attack against it has advantage.", {"cat": "basic"}))
	out.append(_act("hide", "Hide", "basic", lim, "self", 0, "Make a Stealth check against enemies' passive Perception to become hidden.", {"cat": "basic"}))
	if has_cond(c, "prone"):
		var st = _act("stand", "Stand Up", "basic", "free", "self", 0, "Spend half your speed (%d ft) to stand up from prone." % stand_cost(c), {"cat": "basic"})
		if s.in_combat and not can_stand(c):
			st.enabled = false
			st.reason = "Not enough movement (needs %d ft)" % stand_cost(c) if eff_speed(c) > 0 else "Your speed is 0"
		out.append(st)
	# Rope Trick: the entrance stays open, so creatures climb in and drop out as they like.
	if in_rope(c):
		out.append(_act("rope_out", "Drop Down", "basic", "free", "self", 0, "Drop out of the Rope Trick space to the ground under the rope (no movement cost; moving does it too). Attacks and spells can't cross the entrance, so come out to use them.", {"cat": "basic"}))
	else:
		var rope = rope_for(c)
		if not rope.is_empty():
			var ra = _act("rope_in", "Climb Rope", "basic", "free", "self", 0, "Spend %d ft of movement to climb into the Rope Trick space (from within 5 ft of the rope). Inside you can't be seen, targeted or caught in areas, and can't attack or cast out." % rope_climb_cost(c), {"cat": "basic"})
			var why: String = rope_block_reason(c, rope)
			if why != "":
				ra.enabled = false
				ra.reason = why
			out.append(ra)
	var grab = escape_effect(c)
	if not grab.is_empty():
		var label = "Escape Grapple" if grab.get("cond", "") == "grappled" else "Break Free"
		var skills: Array = []
		for ab in _escape_abilities(grab):
			skills.append(_escape_label(ab))
		out.append(_act("escape", label, "basic", "action", "self", 0, "%s check against DC %d to break free of %s." % [" or ".join(skills), int(grab.get("escape_dc", 10)), grab.get("name", "the hold")], {"cat": "basic"}))
	if c.features.has("cunning_action") or c.tags.has("nimble_escape"):
		out.append(_act("b_dash", "Cunning Dash", "basic", "bonus", "self", 0, "Dash as a bonus action.", {"cat": "basic", "base": "dash"}))
		out.append(_act("b_disengage", "Cunning Disengage", "basic", "bonus", "self", 0, "Disengage as a bonus action.", {"cat": "basic", "base": "disengage"}))
		out.append(_act("b_hide", "Cunning Hide", "basic", "bonus", "self", 0, "Hide as a bonus action.", {"cat": "basic", "base": "hide"}))
	if c.tags.has("aggressive"):
		out.append(_act("b_dash", "Aggressive", "basic", "bonus", "self", 0, "Bonus action: move up to your speed toward an enemy.", {"cat": "basic", "base": "dash"}))
	if has_tag(c, "expeditious_retreat") and not (c.features.has("cunning_action") or c.tags.has("nimble_escape")):
		out.append(_act("er_dash", "Expeditious Dash", "basic", "bonus", "self", 0, "Dash as a bonus action (Expeditious Retreat).", {"cat": "basic", "base": "dash"}))
	# --- toggles
	out.append_array(_toggle_actions(c))
	# Economy & incapacitation. An incapacitated creature can't take actions, bonus actions or
	# reactions, free features included; it can still stand up if it has the movement.
	for a in out:
		if inc and a.kind != "toggle" and a.id != "stand":
			a.enabled = false
			a.reason = "Incapacitated"
		elif a.enabled and not can_pay(c, a.cost) and a.kind != "toggle":
			a.enabled = false
			a.reason = "Not your turn" if s.in_combat and not is_turn_of(c) else "No %s left" % {"attack": "attacks/actions", "haste": "Haste action"}.get(a.cost, a.cost)
	return out

const ESCAPE_SKILL := {"str": "athletics", "dex": "acrobatics"}

## The hold on `c` that an action can break (a grapple, a restraint such as Web, or another effect
## you shake off with a check, like Wrathful Smite's fear), or {}.
## Restraints come first: tearing free of a web is what gives a creature its speed back.
func escape_effect(c: Dictionary) -> Dictionary:
	var grab = {}
	var other = {}
	for e in c.effects:
		if not e.has("escape_dc"):
			continue
		if e.get("cond", "") == "restrained":
			return e
		if e.get("cond", "") == "grappled":
			if grab.is_empty():
				grab = e
		elif other.is_empty():
			other = e
	return grab if not grab.is_empty() else other

## Abilities whose check (or matching skill) can break `e`. Grapples allow Athletics or Acrobatics.
func _escape_abilities(e: Dictionary) -> Array:
	var out: Array = []
	for ab in e.get("escape_with", ["str", "dex"]):
		if ab in ["str", "dex", "con", "int", "wis", "cha"]:
			out.append(ab)
	return out if not out.is_empty() else ["str"]

## Check bonus and label for an escape with ability `ab`: Athletics / Acrobatics for STR / DEX, a plain check otherwise.
func _escape_bonus(c: Dictionary, ab: String) -> int:
	return int(c.skills.get(ESCAPE_SKILL[ab], ability_mod(c, ab))) if ESCAPE_SKILL.has(ab) else ability_mod(c, ab)

func _escape_label(ab: String) -> String:
	return ESCAPE_SKILL[ab].capitalize() if ESCAPE_SKILL.has(ab) else ab.to_upper()

func find_action(c: Dictionary, aid: String) -> Dictionary:
	for a in get_actions(c):
		if a.id == aid:
			return a
	return {}

func _weapon_desc(atk: Dictionary) -> String:
	var dmg: PackedStringArray = []
	for d in atk.get("damage", []):
		dmg.append("%s %s" % [d.dice, d.type])
	var rng = "reach %d ft" % int(atk.get("reach", 5)) if atk.get("melee", true) else "range %d/%d ft" % [int(atk.get("range", 0)), int(atk.get("long_range", 0))]
	var d2 = "%s to hit, %s, %s." % [Rules.fmt_mod(int(atk.get("to_hit", 0))), rng, " + ".join(dmg)]
	if atk.get("desc", "") != "":
		d2 += " " + str(atk.desc)
	return d2

func _monster_action(c: Dictionary, m: Dictionary, cost: String) -> Dictionary:
	var kind: String = m.get("kind", "special")
	var desc: String = m.get("desc", "")
	match kind:
		"multiattack":
			return _act("ma:" + m.id, m.name, "multiattack", cost, "enemy", _reach_of(c), desc if desc != "" else "Attacks: " + ", ".join(m.get("sequence", [])), {"m": m, "cat": "attack"})
		"save":
			var tgt = "enemy"
			var rng = int(m.get("range", 60))
			var area: Dictionary = m.get("area", {})
			if not area.is_empty():
				tgt = "self_area" if area.get("shape", "") in ["cone", "line", "emanation", "cube"] else "point"
				rng = int(m.get("range", area.get("size", 15) if area.get("shape", "") in ["cone", "line"] else 60))
				if area.get("shape", "") == "emanation":
					tgt = "self"
			var d = "DC %d %s save." % [int(m.get("dc", 10)), str(m.get("save", "dex")).to_upper()]
			for p in m.get("damage", []):
				d += " %s %s." % [p.dice, p.type]
			var a = _act("ms:" + m.id, m.name, "msave", cost, tgt, rng, d + " " + desc, {"m": m, "area": area, "cat": "attack"})
			if int(m.get("recharge", 0)) > 0 and not c.recharge.get(m.name, true):
				a.enabled = false
				a.reason = "Recharging"
			return a
		"protector":
			return _act("mp:" + m.id, m.name, "mprotector", cost, "self", 0, "Allies within 10 ft gain %s temporary HP." % m.temp_hp, {"m": m, "cat": "feature"})
	var sp = _act("mx:" + m.id, m.name, "mspecial", cost, "self", 0, desc + " (resolve manually)", {"m": m, "cat": "feature"})
	return sp

func _spell_actions(c: Dictionary) -> Array:
	var out: Array = []
	var seen = {}
	for e in c.casting:
		var ids: Array = e.get("spells", []).duplicate()
		for x in e.get("at_will", []):
			if not x in ids:
				ids.append(x)
		for sid in ids:
			if seen.has(sid):
				continue
			var sp = Data.spell(sid)
			if sp.is_empty():
				continue
			seen[sid] = true
			var lv = int(sp.get("level", 0))
			var ct: String = sp.get("casting_time", "action")
			var cb = sp.get("combat", null)
			var cbd: Dictionary = cb if cb is Dictionary else {}
			var tgt: String = cbd.get("target", "self")
			if cbd.get("special", "") in ["spiritual_weapon"]:
				tgt = "enemy"
			if cbd.get("special", "") in ["misty_step", "thunder_step", "dimension_door"]:
				tgt = "point"
			if cbd.get("special", "") == "revivify":
				tgt = "ally_dead"
			var rng = int(sp.get("range", 0))
			if rng < 0 or rng > 5000:
				rng = 5000
			# "Self"-range spells that still pick a creature or point (a range of 0 would mean
			# unlimited reach): conjured blades reach 5 ft, auras 30 ft, weapon riders
			# (Ensnaring Strike, Lightning Arrow, Hail of Thorns) the caster's weapon range.
			if rng == 0 and tgt in ["enemy", "creature", "ally", "point"]:
				if cbd.get("attack", null) == "melee":
					rng = 5
				elif tgt == "ally":
					rng = 30
				else:
					rng = _weapon_range(c)
			if c.get("feats", []).has("spell_sniper") and cbd.get("attack", null) != null:
				rng *= 2
			if sid == "eldritch_blast" and "eldritch_spear" in c.get("invocations", []):
				rng = 300
			var slots: Array = []
			var innate = false
			if lv == 0 or sid in e.get("at_will", []):
				slots = [0]
			elif c.resources.has("innate_" + sid):
				if res_left(c, "innate_" + sid) > 0:
					slots = [lv]
					innate = true
			else:
				for L in range(lv, 10):
					if slots_free(c, L) > 0:
						slots.append(L)
			var cost = "action" if ct == "action" else ("bonus" if ct == "bonus" else ("reaction" if ct == "reaction" else "long"))
			var desc: String = sp.get("summary", "")
			if not cb is Dictionary:
				desc += " [Not automated in combat]"
			# Quickened Spell turns a 1-action casting time into a bonus action.
			var quick: bool = cost == "action" and str(c.get("toggles", {}).get("metamagic", "")) == "quickened" and res_left(c, "sorcery_points") >= 2
			if quick:
				cost = "bonus"
			var a = _act("sp:" + sid, sp.name, "spell", cost if cost != "long" else "action", tgt, rng, desc,
				{"spell": sid, "level": lv, "slots": slots, "class": e["class"], "area": cbd.get("area", {}), "innate": innate,
				 "concentration": sp.get("concentration", false), "max_targets": int(cbd.get("max_targets", 1)), "targets_per_slot": int(cbd.get("targets_per_slot", 0)),
				 "dc": int(e.dc), "spell_attack": int(e.attack), "cat": "spell", "school": sp.get("school", ""),
				 "quickened": quick, "base_cost": "action" if quick else (cost if cost != "long" else "action")})
			if slots.is_empty():
				a.enabled = false
				a.reason = "No spell slots"
			elif cost == "reaction":
				a.enabled = false
				a.reason = "Reaction (cast automatically)"
			elif cost == "long":
				a.enabled = not s.in_combat
				a.reason = "Casting time too long for combat"
			elif spell_block_reason(c, cost, lv) != "":
				a.enabled = false
				a.reason = spell_block_reason(c, cost, lv)
			# Feeblemind: no spells at all. Silence: no spells with a verbal component.
			if mod_any(c, "no_spells"):
				a.enabled = false
				a.reason = "Can't cast spells"
			elif c.get("armor_unproficient", false) and e["class"] != "race":
				a.enabled = false
				a.reason = "Wearing armor you aren't proficient with"
			elif "V" in str(sp.get("components", "")) and in_zone_flag(c, "silence"):
				a.enabled = false
				a.reason = "Silenced"
			out.append(a)
	return out

## Longest normal range among the creature's weapon attacks (melee reach counts), at least 5 ft.
func _weapon_range(c: Dictionary) -> int:
	var r = 5
	for a in attacks_of(c):
		r = maxi(r, int(a.get("reach", 5)) if a.get("melee", true) else int(a.get("range", 0)))
	return r

func _feature_actions(c: Dictionary) -> Array:
	var out: Array = []
	var f: Dictionary = c.features
	var t: Dictionary = c.get("turn", {})
	var add = func(id: String, name: String, cost: String, target: String, rng: int, desc: String, res: String = "", res_n: int = 1, extra := {}) -> void:
		var a = _act(id, name, "feature", cost, target, rng, desc, extra)
		a.cat = "feature"
		if res != "":
			a.res = res
			if res_left(c, res) < res_n:
				a.enabled = false
				a.reason = "No uses left"
		out.append(a)
	if f.has("rage"):
		if has_tag(c, "rage"):
			add.call("end_rage", "End Rage", "bonus", "self", 0, "Stop raging.")
		else:
			add.call("rage", "Rage", "bonus", "self", 0, "Enter a rage: +%d melee damage, resist B/P/S, advantage on STR." % int(c.vals.get("rage_damage", 2)), "rage")
	if f.has("frenzy") and has_tag(c, "rage"):
		var fa = best_melee(c)
		if not fa.is_empty():
			add.call("frenzy", "Frenzied Strike", "bonus", "enemy", int(fa.reach), "Bonus action melee attack while raging.", "", 1, {"atk": fa})
	if f.has("bardic_inspiration"):
		add.call("bardic_inspiration", "Bardic Inspiration", "bonus", "ally_other", 60, "Give an ally a d%d to add to a failed attack or save." % int(c.vals.bardic_die), "bardic_inspiration")
	if f.has("second_wind"):
		add.call("second_wind", "Second Wind", "bonus", "self", 0, "Regain 1d10 + %d HP." % c.class_levels.get("fighter", 1), "second_wind")
	if f.has("action_surge"):
		add.call("action_surge", "Action Surge", "free", "self", 0, "Gain an additional action this turn.", "action_surge")
		if t.get("surged", false):
			out[-1].enabled = false
			out[-1].reason = "Already surged this turn"
	if f.has("fighting_spirit"):
		add.call("fighting_spirit", "Fighting Spirit", "bonus", "self", 0, "Advantage on weapon attacks this turn and temp HP.", "fighting_spirit")
	if f.has("martial_arts"):
		var ua = _unarmed(c)
		add.call("martial_arts", "Martial Arts Strike", "bonus", "enemy", 5, "Bonus unarmed strike after attacking.", "", 1, {"atk": ua})
		if not t.get("attacked", false) and s.in_combat:
			out[-1].enabled = false
			out[-1].reason = "Take the Attack action first"
	if f.has("ki"):
		add.call("flurry_of_blows", "Flurry of Blows", "bonus", "enemy", 5, "1 ki: two unarmed strikes.", "ki")
		if not t.get("attacked", false) and s.in_combat:
			out[-1].enabled = false
			out[-1].reason = "Take the Attack action first"
		add.call("patient_defense", "Patient Defense", "bonus", "self", 0, "1 ki: Dodge as a bonus action.", "ki")
		add.call("step_of_the_wind", "Step of the Wind", "bonus", "self", 0, "1 ki: Dash and Disengage as a bonus action.", "ki")
	if f.has("hand_of_healing"):
		add.call("hand_of_healing", "Hand of Healing", "action", "ally", 5, "1 ki: heal 1d%d + WIS." % int(c.vals.martial_die), "ki")
	if f.has("lay_on_hands"):
		add.call("lay_on_hands", "Lay on Hands", "action", "ally", 5, "Heal from your pool (%d left)." % res_left(c, "lay_on_hands"), "lay_on_hands")
	if f.has("channel_divinity") or f.has("turn_undead"):
		var cd_desc = "Uses Channel Divinity."
		if f.has("turn_undead"): add.call("turn_undead", "Turn Undead", "action", "self", 30, "Undead within 30 ft: WIS save or turned. " + cd_desc, "channel_divinity")
		if f.has("preserve_life"): add.call("preserve_life", "Preserve Life", "action", "self", 30, "Heal allies within 30 ft (pool %d). " % (5 * c.class_levels.get("cleric", 0)) + cd_desc, "channel_divinity")
		if f.has("radiance_of_the_dawn"): add.call("radiance_of_the_dawn", "Radiance of the Dawn", "action", "self", 30, "Enemies within 30 ft: CON save, 2d10+%d radiant. " % c.class_levels.get("cleric", 0) + cd_desc, "channel_divinity")
		if f.has("twilight_sanctuary"): add.call("twilight_sanctuary", "Twilight Sanctuary", "action", "self", 30, "30 ft aura: allies ending their turn in it gain 1d6+%d temp HP. " % c.class_levels.get("cleric", 0) + cd_desc, "channel_divinity")
		if f.has("balm_of_peace"): add.call("balm_of_peace", "Balm of Peace", "action", "self", 15, "Heal allies within 15 ft 2d6+WIS. " + cd_desc, "channel_divinity")
		if f.has("path_to_the_grave"): add.call("path_to_the_grave", "Path to the Grave", "action", "enemy", 30, "The next attack against the target deals double damage. " + cd_desc, "channel_divinity")
		if f.has("turn_the_unholy"): add.call("turn_the_unholy", "Turn the Unholy", "action", "self", 30, "Fiends and undead within 30 ft: WIS save or turned for 1 minute. " + cd_desc, "channel_divinity")
		if f.has("turn_the_faithless"): add.call("turn_the_faithless", "Turn the Faithless", "action", "self", 30, "Fey and fiends within 30 ft: WIS save or turned for 1 minute. " + cd_desc, "channel_divinity")
		if f.has("abjure_enemy"): add.call("abjure_enemy", "Abjure Enemy", "action", "enemy", 60, "WIS save (fiends and undead at disadvantage) or frightened with speed 0 for 1 minute; on a success its speed is halved. " + cd_desc, "channel_divinity")
		if f.has("sacred_weapon"): add.call("sacred_weapon", "Sacred Weapon", "action", "self", 0, "+CHA to weapon attack rolls for 1 minute. " + cd_desc, "channel_divinity")
		if f.has("vow_of_enmity"): add.call("vow_of_enmity", "Vow of Enmity", "bonus", "enemy", 10, "Advantage on attacks against the target for 1 minute. " + cd_desc, "channel_divinity")
		if f.has("natures_wrath"): add.call("natures_wrath", "Nature's Wrath", "action", "enemy", 10, "STR save or restrained. " + cd_desc, "channel_divinity")
		if f.has("conquering_presence"): add.call("conquering_presence", "Conquering Presence", "action", "self", 30, "Enemies within 30 ft: WIS save or frightened. " + cd_desc, "channel_divinity")
	if f.has("emboldening_bond"):
		add.call("emboldening_bond", "Emboldening Bond", "action", "self", 30, "Bond up to %d allies within 30 ft (including you)." % int(c.prof), "emboldening_bond")
	if f.has("war_priest"):
		var wa = best_melee(c)
		if not wa.is_empty():
			add.call("war_priest", "War Priest Strike", "bonus", "enemy", int(wa.reach), "Bonus action weapon attack.", "war_priest", 1, {"atk": wa})
			if not t.get("attacked", false) and s.in_combat:
				out[-1].enabled = false
				out[-1].reason = "Take the Attack action first"
	if f.has("war_magic") and t.get("cantrip", false):
		var wm = best_melee(c)
		if not wm.is_empty():
			add.call("war_magic", "War Magic Strike", "bonus", "enemy", int(wm.reach), "Bonus weapon attack after a cantrip.", "", 1, {"atk": wm})
	if c.get("feats", []).has("polearm_master"):
		for a in attacks_of(c):
			if a.get("weapon", "") in ["glaive", "halberd", "quarterstaff", "spear"]:
				var b: Dictionary = a.duplicate(true)
				b.id = "pam"
				b.damage = [{"dice": "1d4+%d" % int(c.mods[a.ability]), "type": "bludgeoning"}]
				add.call("polearm_master", "Polearm Butt", "bonus", "enemy", int(a.reach), "Bonus 1d4 attack with the haft.", "", 1, {"atk": b})
				if not t.get("attacked", false) and s.in_combat:
					out[-1].enabled = false
					out[-1].reason = "Take the Attack action first"
				break
	if c.get("feats", []).has("great_weapon_master") and t.get("gwm_bonus", false):
		var ga = best_melee(c)
		add.call("gwm_bonus", "Cleave (GWM)", "bonus", "enemy", int(ga.get("reach", 5)), "Bonus attack after a crit or kill.", "", 1, {"atk": ga})
	if f.has("wild_shape"):
		if c.form.is_empty():
			var ws_cost = "bonus" if f.has("combat_wild_shape") else "action"
			add.call("wild_shape", "Wild Shape", ws_cost, "self", 0, "Transform into a beast (max CR %s)." % Data.cr_text(_wild_shape_max_cr(c)), "wild_shape", 1, {"forms": wild_shape_forms(c)})
			if f.has("symbiotic_entity"): add.call("symbiotic_entity", "Symbiotic Entity", "action", "self", 0, "Spend Wild Shape: %d temp HP, stronger spores." % (4 * c.class_levels.get("druid", 2)), "wild_shape")
			if f.has("starry_form"):
				add.call("starry_archer", "Starry Form: Archer", "bonus", "self", 0, "Spend Wild Shape: luminous arrows as a bonus action.", "wild_shape")
				add.call("starry_chalice", "Starry Form: Chalice", "bonus", "self", 0, "Spend Wild Shape: healing spells heal another creature 1d8+WIS.", "wild_shape")
		else:
			add.call("revert_form", "Revert Form", "bonus", "self", 0, "Return to your normal form.")
	if has_tag(c, "starry_archer"):
		var e = caster_entry(c, "druid")
		var arrow = {"id": "arrow", "name": "Luminous Arrow", "melee": false, "to_hit": int(e.get("attack", 4)), "damage": [{"dice": "1d8+%d" % int(c.mods.wis), "type": "radiant"}], "range": 60, "long_range": 60, "reach": 5, "magic": true, "spell_attack": true}
		add.call("luminous_arrow", "Luminous Arrow", "bonus", "enemy", 60, "Ranged spell attack, 1d8+WIS radiant.", "", 1, {"atk": arrow})
	# Arcane Recovery, after a short rest: regain expended slots one at a time, up to the level budget.
	if f.has("arcane_recovery") and not s.in_combat and int(c.get("arcane_budget", 0)) > 0:
		var budget: int = int(c.arcane_budget)
		for L in range(1, mini(6, c.slots_max.size() + 1)):
			if L <= budget and int(c.slots_used[L - 1]) > 0:
				add.call("arcane_rec_%d" % L, "Recover Lv%d Slot" % L, "free", "self", 0, "Arcane Recovery: regain an expended level %d slot (%d of %d levels left to recover after this short rest)." % [L, budget, ceili(c.class_levels.get("wizard", 1) / 2.0)], "", 1, {"slot_level": L})
	if f.has("font_of_magic"):
		var costs = {1: 2, 2: 3, 3: 5, 4: 6, 5: 7}
		for L in range(1, 6):
			if L <= int(c.class_levels.get("sorcerer", 0) / 2.0 + 0.5) or L == 1:
				add.call("fom_%d" % L, "Create Lv%d Slot" % L, "bonus", "self", 0, "Spend %d sorcery points for a level %d spell slot." % [costs[L], L], "sorcery_points", costs[L], {"slot_level": L, "sp_cost": costs[L]})
	if f.has("hexblades_curse"):
		add.call("hexblades_curse", "Hexblade's Curse", "bonus", "enemy", 30, "Curse a creature: +%d damage, crit on 19-20." % int(c.prof), "hexblades_curse")
	if f.has("healing_light"):
		add.call("healing_light", "Healing Light", "bonus", "ally", 60, "Spend up to %d d6 from your pool to heal." % maxi(1, int(c.mods.cha)), "healing_light")
	if f.has("fey_presence"):
		add.call("fey_presence", "Fey Presence", "action", "self", 10, "Creatures within 10 ft: WIS save or frightened.", "fey_presence")
	if f.has("bladesong") and not has_tag(c, "bladesong"):
		add.call("bladesong", "Bladesong", "bonus", "self", 0, "+%d AC, +10 ft speed, + concentration for 1 minute." % maxi(1, int(c.mods.int)), "bladesong")
	if f.has("momentary_stasis"):
		add.call("momentary_stasis", "Momentary Stasis", "action", "enemy", 60, "CON save or incapacitated with 0 speed until the end of your next turn.", "momentary_stasis")
	if f.has("eldritch_cannon") and not _has_cannon(c):
		var has_free = res_left(c, "eldritch_cannon") > 0 or lowest_slot(c, 1) > 0
		add.call("eldritch_cannon", "Eldritch Cannon", "action", "self", 5, "Create a cannon (free once per long rest, then costs a spell slot).", "", 1, {"cannons": CANNON_TYPES})
		if not has_free:
			out[-1].enabled = false
			out[-1].reason = "No uses or slots"
	if c.resources.has("defensive_field"):
		add.call("defensive_field", "Defensive Field", "bonus", "self", 0, "Gain %d temp HP." % c.class_levels.get("artificer", 3), "defensive_field")
	if c.tags.has("breath_weapon") and c.has("breath"):
		var br: Dictionary = c.breath
		add.call("breath_weapon", "Breath Weapon", "action", "self_area", int(br.get("size", 15)), "%s %s %s, DC %d %s save." % [c.vals.breath_dice, br.type, br.shape, int(c.vals.breath_dc), str(br.save).to_upper()], "breath_weapon", 1, {"area": {"shape": br.shape, "size": int(br.get("size", 15))}})
	if c.tags.has("healing_hands"):
		add.call("healing_hands", "Healing Hands", "action", "ally", 5, "Heal %d HP." % int(c.level), "healing_hands")
	if c.tags.has("fey_step"):
		add.call("fey_step", "Fey Step", "bonus", "point", 30, "Teleport up to 30 ft.", "fey_step")
	if c.tags.has("hidden_step"):
		add.call("hidden_step", "Hidden Step", "bonus", "self", 0, "Become invisible until your next turn or until you attack.", "hidden_step")
	if c.tags.has("radiant_soul") and c.resources.has("radiant_soul") and not has_tag(c, "radiant_soul"):
		add.call("radiant_soul", "Celestial Revelation", "bonus", "self", 0, "For 1 minute, once per turn add %d radiant damage." % int(c.level), "radiant_soul")
	if f.has("planar_warrior"):
		add.call("planar_warrior", "Planar Warrior", "bonus", "enemy", 30, "Your next hit on the target this turn deals +1d8 force.")
	if not c.conc.is_empty() and c.conc.spell in ["hunters_mark", "hex"]:
		var marked = false
		for o in all_combatants():
			for e in o.effects:
				if e.get("tag", "") in ["hunters_mark", "hex"] and e.get("src", "") == c.id and alive(o) and o.hp > 0:
					marked = true
		if not marked:
			add.call("move_mark", "Move " + Data.spell(c.conc.spell).get("name", "Mark"), "bonus", "enemy", 90, "Shift your mark to a new creature.")
	for e in c.effects:
		match e.get("tag", ""):
			"spiritual_weapon":
				var sw = {"id": "sw", "name": "Spiritual Weapon", "melee": true, "to_hit": int(e.attack), "damage": [{"dice": e.dice, "type": "force"}], "reach": 60, "range": 0, "long_range": 0, "magic": true, "spell_attack": true}
				add.call("spiritual_weapon_attack", "Spiritual Weapon", "bonus", "enemy", 60, "Melee spell attack with your floating weapon.", "", 1, {"atk": sw})
			"vampiric_touch":
				var vt = {"id": "vt", "name": "Vampiric Touch", "melee": true, "to_hit": int(e.attack), "damage": [{"dice": e.dice, "type": "necrotic"}], "reach": 5, "range": 0, "long_range": 0, "magic": true, "spell_attack": true, "drain": true}
				add.call("vampiric_touch_attack", "Vampiric Touch", "action", "enemy", 5, "Melee spell attack; heal half the damage.", "", 1, {"atk": vt})
			"magic_stone":
				var ms = {"id": "ms", "name": "Magic Stone", "melee": false, "to_hit": int(e.attack), "damage": [{"dice": e.dice, "type": "bludgeoning"}], "reach": 5, "range": 60, "long_range": 60, "magic": true, "spell_attack": true}
				add.call("magic_stone_throw", "Throw Magic Stone (%d)" % int(e.uses), "action", "enemy", 60, "Ranged spell attack, %s bludgeoning." % e.dice, "", 1, {"atk": ms, "eid": e.eid})
				add.call("magic_stone_drop", "Drop Magic Stone (%d)" % int(e.uses), "free", "point", 5, "Set one stone down in your space or an adjacent one, where another creature can pick it up.", "", 1, {"eid": e.eid})
				# Handing a stone over is an object interaction: free once a turn, then Use an Object.
				# Outside combat it costs nothing, so a caster can arm its servants before a fight.
				var handed: bool = s.in_combat and t.get("interacted", false)
				add.call("magic_stone_give", "Give Magic Stone (%d)" % int(e.uses), "action" if handed else "free", "ally_other", 5,
					"Hand one stone to a creature within 5 ft; it can throw it on its own turn%s." % (" (Use an Object: free interaction already used)" if handed else " (free object interaction)"), "", 1, {"eid": e.eid})
			"dragons_breath":
				var br: Dictionary = e.get("breath", {})
				if not br.is_empty():
					var bsz: int = int(br.get("size", 15))
					add.call("dragons_breath", "Dragon's Breath", "action", "self_area", bsz, "Exhale a %d-ft %s: DC %d %s save, %s %s (half on a success)." % [bsz, br.get("shape", "cone"), int(e.get("dc", 13)), str(br.get("save", "dex")).to_upper(), br.dice, br.get("type", "fire")], "", 1, {"area": {"shape": br.get("shape", "cone"), "size": bsz}, "eid": e.eid})
			"swift_quiver":
				var ra = _best_ranged_weapon(c)
				if not ra.is_empty():
					add.call("swift_quiver", "Swift Quiver", "bonus", "enemy", int(ra.get("range", 80)), "Two ranged weapon attacks as a bonus action.", "", 1, {"atk": ra})
	# Magic stones lying within reach. The first pickup in a turn is the free object interaction;
	# another one takes the Use an Object action.
	var near_stone = false
	for it in ground_items():
		if it.get("kind", "") == "magic_stone" and dist_to_cell(c, it.pos) <= 5:
			near_stone = true
			break
	if near_stone:
		var used: bool = s.in_combat and t.get("interacted", false)
		add.call("magic_stone_pickup", "Pick Up Magic Stone", "action" if used else "free", "point", 5,
			"Pick up a magic stone in your space or an adjacent one%s." % (" (Use an Object: free interaction already used)" if used else " (free object interaction)"))
	# Witch Bolt / Heat Metal: keep hurting the creature the spell is locked on to.
	var su: Dictionary = c.conc.get("sustain", {}) if c.conc is Dictionary else {}
	if not su.is_empty():
		var ssp = Data.spell(su.get("spell", ""))
		var sdata: Dictionary = ssp.get("combat", {}).get("sustain", {}) if ssp.get("combat", null) is Dictionary else {}
		var st = C(su.get("target", ""))
		if not sdata.is_empty() and not st.is_empty() and alive(st):
			var dd: PackedStringArray = []
			for d in sdata.get("damage", []):
				dd.append("%s %s" % [d.dice, d.type])
			add.call("sustain_spell", "%s: %s" % [ssp.name, st.name], str(sdata.get("cost", "action")), "self", int(sdata.get("range", 30)), "Deal %s to %s again." % [" + ".join(dd), st.name])
			if s.in_combat and int(su.get("cast_serial", -1)) == int(c.get("turn", {}).get("serial", -2)):
				out[-1].enabled = false
				out[-1].reason = "Starts on your next turn"
	out.append_array(_repeat_actions(c))
	return out

## The creature's best ranged weapon attack (no spell attacks), or {}.
func _best_ranged_weapon(c: Dictionary) -> Dictionary:
	var best = {}
	var best_v = -1.0
	for a in attacks_of(c):
		if a.get("melee", true) or a.get("spell_attack", false) or a.get("cost", "attack") != "attack":
			continue
		var v = 0.0
		for d in a.get("damage", []):
			v += Dice.average(d.dice)
		if v > best_v:
			best_v = v
			best = a
	return best

func _toggle_actions(c: Dictionary) -> Array:
	var out: Array = []
	var tg: Dictionary = c.get("toggles", {})
	var f: Dictionary = c.features
	var mk = func(key: String, name: String, desc: String, value_text: String) -> Dictionary:
		return _act("tog:" + key, name, "toggle", "free", "self", 0, desc, {"cat": "toggle", "key": key, "on": _truthy(tg.get(key, false)), "value_text": value_text})
	if f.has("reckless_attack"):
		out.append(mk.call("reckless", "Reckless Attack", "Advantage on STR melee attacks this turn; enemies have advantage against you until your next turn.", ""))
	if f.has("divine_smite"):
		var lv: int = int(tg.get("smite", 0))
		out.append(mk.call("smite", "Divine Smite", "On your turn you choose after each melee hit (crits included) whether to smite. Arm a slot level here (click to cycle) to smite automatically on your next melee hit, such as an opportunity attack.", ("Lv %d" % lv) if lv > 0 else "off"))
	if c.get("feats", []).has("great_weapon_master"):
		out.append(mk.call("gwm", "Great Weapon Master", "-5 to hit, +10 damage with heavy melee weapons.", ""))
	if c.get("feats", []).has("sharpshooter"):
		out.append(mk.call("sharpshooter", "Sharpshooter", "-5 to hit, +10 damage with ranged weapons.", ""))
	if f.has("stunning_strike"):
		out.append(mk.call("stunning", "Stunning Strike", "On your turn you choose after each melee hit. Arm it here to spend 1 ki on your next melee hit, such as an opportunity attack: CON save or stunned.", ""))
	if f.has("combat_superiority"):
		var opts: Array = c.maneuvers.filter(func(m): return not m in ["precision", "riposte"])
		if not opts.is_empty():
			var cur: String = str(tg.get("maneuver", ""))
			out.append(mk.call("maneuver", "Maneuver", "Apply a maneuver to your next hit (click to cycle): " + ", ".join(opts), cur.capitalize() if cur != "" else "off"))
	if f.has("metamagic") and not c.metamagic.is_empty():
		var cur2: String = str(tg.get("metamagic", ""))
		out.append(mk.call("metamagic", "Metamagic", "Apply metamagic to your next spell (click to cycle): " + ", ".join(c.metamagic), cur2.capitalize() if cur2 != "" else "off"))
	return out

func _unarmed(c: Dictionary) -> Dictionary:
	for a in attacks_of(c):
		if a.get("unarmed", false):
			return a
	return {"id": "unarmed", "name": "Unarmed Strike", "melee": true, "to_hit": int(c.mods.str) + int(c.prof), "damage": [{"dice": "1+%d" % int(c.mods.str), "type": "bludgeoning"}], "reach": 5, "props": [], "unarmed": true}

func _has_cannon(c: Dictionary) -> bool:
	for o in all_combatants():
		if o.get("summoner", "") == c.id and o.get("cannon", "") != "" and alive(o):
			return true
	return false

func _wild_shape_max_cr(c: Dictionary) -> float:
	var lv: int = c.class_levels.get("druid", 2)
	if c.features.has("circle_forms"):
		return maxf(1.0, float(lv / 3)) if lv >= 6 else 1.0
	return 1.0 if lv >= 8 else (0.5 if lv >= 4 else 0.25)

func wild_shape_forms(c: Dictionary) -> Array:
	var mx = _wild_shape_max_cr(c)
	var lv: int = c.class_levels.get("druid", 2)
	var out: Array = []
	for m in Data.monsters_sorted():
		if m.get("type", "") != "beast" or float(m.get("cr", 0)) > mx:
			continue
		if int(m.get("fly", 0)) > 0 and lv < 8:
			continue
		if int(m.get("swim", 0)) > 0 and int(m.get("speed", 30)) < 20 and lv < 4:
			continue
		out.append({"id": m.id, "name": "%s (CR %s)" % [m.name, Data.cr_text(m.cr)]})
	return out

# ================================================================ execute

## Validate and run an action. params: {targets: [ids], cell: Vector2i, slot: int, opts: {}}
func execute(cid: String, aid: String, params: Dictionary) -> bool:
	var c = C(cid)
	if c.is_empty():
		return false
	if aid == "hit_choice":
		return resolve_hit(cid, params)
	settle_pending_hit()
	var a = find_action(c, aid)
	if a.is_empty():
		return false
	if a.kind == "toggle":
		# Reckless Attack is declared on your own turn, when you make your first attack.
		if a.key == "reckless" and s.in_combat and not c.toggles.get("reckless", false):
			if not is_turn_of(c) or c.turn.get("attacked_any", false):
				log_line("[color=#888]Reckless Attack must be declared before your first attack on your turn.[/color]")
				return false
		_toggle(c, a)
		return true
	if not a.enabled:
		log_line("[color=#888]%s can't use %s: %s[/color]" % [c.name, a.name, a.reason])
		return false
	var targets: Array = []
	for tid in params.get("targets", []):
		var t = C(tid)
		if not t.is_empty():
			targets.append(t)
	var cell_v = params.get("cell", null)
	var cellp: Vector2i = cell_v if cell_v is Vector2i else c.pos
	# Range / sight validation for creature targets.
	if a.target in ["enemy", "ally", "creature", "ally_other", "ally_dead"]:
		if targets.is_empty():
			return false
		for t in targets:
			if a.target != "ally_dead" and not alive(t):
				log_line("[color=#888]%s is no longer a valid target.[/color]" % t.name)
				return false
			# Revivify only works within a minute of death; checked before the slot and diamonds are spent.
			if a.target == "ally_dead" and not revivable(t):
				log_line("[color=#888]%s can't be revived: %s[/color]" % [t.name, "it isn't dead." if not t.death.dead else "it died more than a minute ago."])
				return false
			if in_rope(c) != in_rope(t) or (in_rope(c) and not same_space(c, t)):
				log_line("[color=#888]Attacks and spells can't cross a Rope Trick entrance%s.[/color]" % (": %s has to drop down first" % c.name if in_rope(c) else ""))
				return false
			if dist(c, t) > int(a.range) and int(a.range) > 0:
				log_line("[color=#888]%s is out of range (%d ft > %d ft).[/color]" % [t.name, dist(c, t), int(a.range)])
				return false
			if t.id != c.id and not los(c, t):
				log_line("[color=#888]No line of sight to %s.[/color]" % t.name)
				return false
	# From inside a Rope Trick space nothing can be aimed at the world outside.
	if rope_space(c) != "" and (a.target == "point" or (not a.get("area", {}).is_empty() and a.area.get("shape", "") != "emanation")):
		log_line("[color=#888]%s can't reach the world outside the Rope Trick space.[/color]" % c.name)
		return false
	if a.target == "point" and int(a.range) > 0 and dist_to_cell(c, cellp) > int(a.range):
		log_line("[color=#888]That point is out of range.[/color]")
		return false
	if a.target == "point" and not los_cells(c.pos, cellp):
		log_line("[color=#888]No line of sight to that point.[/color]")
		return false
	match a.kind:
		"weapon":
			if targets.is_empty():
				return false
			pay(c, a.cost)
			_attack_with(c, targets[0], a.atk, {"bonus_attack": a.cost == "bonus", "ask_on_hit": true})
		"multiattack":
			pay(c, a.cost)
			_multiattack(c, a.m, targets[0])
		"msave":
			pay(c, a.cost)
			_monster_save_action(c, a, targets, cellp)
		"mprotector":
			pay(c, a.cost)
			log_line("%s's cannon shimmers with protective energy." % nm(c))
			for o in allies_of(c):
				if dist(c, o) <= 10:
					grant_temp_hp(o, Dice.roll(a.m.temp_hp).total, "Protector")
		"mspecial":
			pay(c, a.cost)
			log_line("%s uses [b]%s[/b]. %s" % [nm(c), a.name, a.m.get("desc", "")])
		"spell":
			return _cast(c, a, targets, cellp, params)
		"feature":
			return _feature(c, a, targets, cellp, params)
		"basic":
			_basic(c, a, targets)
	return true

func _toggle(c: Dictionary, a: Dictionary) -> void:
	var tg: Dictionary = c.toggles
	match a.key:
		"smite":
			var cur = int(tg.get("smite", 0))
			var nxt = 0
			for L in range(cur + 1, 6):
				if slots_free(c, L) > 0:
					nxt = L
					break
			tg.smite = nxt
		"maneuver":
			var opts: Array = c.maneuvers.filter(func(m): return not m in ["precision", "riposte"])
			opts.push_front("")
			var i = opts.find(str(tg.get("maneuver", "")))
			tg.maneuver = opts[(i + 1) % opts.size()]
		"metamagic":
			var mm: Array = c.metamagic.duplicate()
			mm.push_front("")
			var j = mm.find(str(tg.get("metamagic", "")))
			tg.metamagic = mm[(j + 1) % mm.size()]
		_:
			tg[a.key] = not tg.get(a.key, false)
			if a.key == "reckless" and tg.reckless:
				add_effect(c, {"name": "Reckless", "tag": "reckless_target", "src": c.id, "rounds": 1, "tick_cid": c.id, "tick_on": "start"})

func _basic(c: Dictionary, a: Dictionary, targets: Array) -> void:
	pay(c, a.cost)
	var base: String = a.get("base", a.id)
	match base:
		"dash":
			if s.in_combat:
				c.turn.dashes = int(c.turn.get("dashes", 0)) + 1
				sync_move(c)
			log_line("%s dashes." % nm(c))
		"stand":
			stand_up(c)
		"rope_in":
			enter_rope(c, rope_for(c))
		"rope_out":
			exit_rope(c)
		"escape":
			var g = escape_effect(c)
			if not g.is_empty():
				var best_ab = ""
				var bonus = -99
				for ab in _escape_abilities(g):
					var b: int = _escape_bonus(c, ab)
					if b > bonus:
						bonus = b
						best_ab = ab
				var roll: int = Dice.d20() + bonus
				var dc: int = int(g.get("escape_dc", 10))
				var what = "the grapple" if g.get("cond", "") == "grappled" else str(g.get("name", "the hold"))
				# Caustic Brew: scraping the acid off just takes the action.
				if g.get("escape_auto", false):
					roll = dc
				# Otto's Irresistible Dance: the action buys a saving throw rather than a check.
				elif g.get("escape_save", false):
					var ab: String = str(_escape_abilities(g)[0])
					roll = dc if saving_throw(c, ab, dc, C(str(g.get("src", ""))), {"spell": true}) else dc - 1
					best_ab = ab
				if roll >= dc:
					remove_effect(c, g.eid)
					log_line("%s breaks free of %s (%s %d vs DC %d)." % [nm(c), what, _escape_label(best_ab), roll, dc])
				else:
					log_line("%s struggles but can't escape %s (%d vs DC %d)." % [nm(c), what, roll, dc])
				sync_move(c)
		"disengage":
			c.turn.disengaged = true
			log_line("%s disengages." % nm(c))
		"dodge":
			add_effect(c, {"name": "Dodging", "tag": "dodge", "src": c.id, "rounds": 1, "tick_cid": c.id, "tick_on": "start"})
			log_line("%s takes the Dodge action." % nm(c))
		"help":
			if not targets.is_empty():
				add_effect(targets[0], {"name": "Distracted", "tag": "helped", "src": "*", "for_team": c.team, "rounds": 1, "tick_cid": c.id, "tick_on": "start"})
				log_line("%s helps an ally against %s." % [nm(c), nm(targets[0])])
		"hide":
			var roll: int = Dice.d20() + int(c.skills.get("stealth", c.mods.dex))
			var best = 0
			for o in enemies_of(c):
				if conscious(o):
					best = maxi(best, int(o.get("passive", 10)))
			if roll >= best:
				c.hidden = true
				log_line("%s hides (Stealth %d vs passive Perception %d)." % [nm(c), roll, best])
			else:
				log_line("%s fails to hide (Stealth %d vs %d)." % [nm(c), roll, best])

# ================================================================ weapon attacks

func _attack_with(c: Dictionary, t: Dictionary, atk: Dictionary, opts := {}) -> Dictionary:
	var melee: bool = atk.get("melee", true)
	var to_hit = int(atk.get("to_hit", 0))
	var power = false
	var tg: Dictionary = c.get("toggles", {})
	if not atk.get("spell_attack", false):
		if tg.get("gwm", false) and melee and atk.get("heavy", false): power = true
		if tg.get("sharpshooter", false) and not melee: power = true
	var res = roll_attack(c, t, atk, {"melee": melee, "bonus": -5 if power else 0, "spell": atk.get("spell_attack", false), "fixed_target": opts.get("opportunity", false)})
	t = res.get("target", t)
	fx("slash" if melee else "bolt", c.pos, t.pos, "#ffffff" if not atk.get("spell_attack", false) else "#c8a0ff", [], _attack_sfx(atk, melee))
	if is_turn_of(c):
		c.turn.attacked_any = true
		if melee:
			c.turn.melee_targets.append(t.id)
	if not res.hit:
		_rider_on_miss(c, t, melee, atk)
		# Riposte.
		if melee and "riposte" in t.get("maneuvers", []) and can_react(t) and res_left(t, "superiority") > 0 and dist(t, c) <= 5:
			var ra = best_melee(t)
			if not ra.is_empty():
				spend_res(t, "superiority")
				use_reaction(t)
				log_line("%s ripostes!" % nm(t))
				var rr = roll_attack(t, c, ra, {"melee": true, "fixed_target": true})
				if rr.hit:
					var parts = weapon_damage(t, c, ra, rr, {})
					parts.append({"amount": Dice.d(int(t.vals.get("superiority_die", 8))), "type": parts[0].type if parts.size() > 0 else "slashing"})
					apply_damage(c, parts, t, {"attack": true, "melee": true, "magic": ra.get("magic", false), "crit": rr.crit})
		return res
	# A player making their own attack decides on Divine Smite, Stunning Strike and maneuvers
	# once they know it hit (and whether it was a crit). The damage waits for that answer.
	if interactive and opts.get("ask_on_hit", false):
		var choices: Dictionary = hit_choices(c, atk)
		if not choices.is_empty():
			var held: Dictionary = res.duplicate()
			held.erase("target")
			s.pending_hit = {"id": new_id("hit"), "cid": c.id, "tid": t.id, "atk": atk.duplicate(true), "res": held,
				"power": power, "opts": opts.duplicate(true), "choices": choices}
			return res
	_attack_hit(c, t, atk, res, power, opts)
	return res

## What `c` could still add to a weapon hit it has just landed: smite slot levels, Stunning Strike,
## maneuvers. Options already armed with a toggle aren't offered again.
func hit_choices(c: Dictionary, atk: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	if atk.get("spell_attack", false):
		return out
	var melee: bool = atk.get("melee", true)
	var tg: Dictionary = c.get("toggles", {})
	if melee and c.features.has("divine_smite") and int(tg.get("smite", 0)) == 0:
		var levels: Array = []
		for L in range(1, 10):
			if slots_free(c, L) > 0:
				levels.append(L)
		if not levels.is_empty():
			out.smite = levels
	if melee and c.features.has("stunning_strike") and not tg.get("stunning", false) and res_left(c, "ki") > 0:
		out.stunning = true
	if c.features.has("combat_superiority") and str(tg.get("maneuver", "")) == "" and res_left(c, "superiority") > 0:
		var mans: Array = c.get("maneuvers", []).filter(func(m): return not m in ["precision", "riposte"])
		if not mans.is_empty():
			out.maneuvers = mans
	return out

## Finish a held hit with the player's picks: {smite: slot level (0 = none), stunning: bool, maneuver: id}.
func resolve_hit(cid: String, picks: Dictionary) -> bool:
	var p: Dictionary = s.get("pending_hit", {})
	if p.is_empty() or p.cid != cid:
		return false
	s.erase("pending_hit")
	var c = C(p.cid)
	var t = C(p.tid)
	if c.is_empty() or t.is_empty():
		return false
	var ch: Dictionary = p.choices
	var tg: Dictionary = c.toggles
	var lv: int = int(picks.get("smite", 0))
	if lv > 0 and lv in ch.get("smite", []):
		tg.smite = lv
	var stun: bool = picks.get("stunning", false) and ch.get("stunning", false)
	if stun:
		tg.stunning = true
	var man: String = str(picks.get("maneuver", ""))
	if man != "" and man in ch.get("maneuvers", []):
		tg.maneuver = man
	_attack_hit(c, t, p.atk, p.res, p.power, p.opts)
	# Picks made for this hit don't carry over to the next one (a slain target never gets stunned).
	tg.smite = 0
	if stun:
		tg.stunning = false
	if man != "":
		tg.maneuver = ""
	return true

## A held hit is finished with no extras as soon as anything else happens.
func settle_pending_hit() -> void:
	var p: Dictionary = s.get("pending_hit", {})
	if not p.is_empty():
		resolve_hit(str(p.cid), {})

func _attack_hit(c: Dictionary, t: Dictionary, atk: Dictionary, res: Dictionary, power: bool, opts: Dictionary) -> void:
	var melee: bool = atk.get("melee", true)
	var wctx = {"power": power, "opts": opts}
	var parts2 = weapon_damage(c, t, atk, res, wctx)
	var dealt = apply_damage(t, parts2, c, {"attack": true, "melee": melee, "ranged_weapon": not melee and not atk.get("spell_attack", false), "magic": atk.get("magic", false) or atk.get("spell_attack", false), "crit": res.crit, "radiant": _has_type(parts2, "radiant")})
	if res.crit and is_turn_of(c):
		c.turn.gwm_bonus = true
	if is_turn_of(c) and c.turn.get("killed", false):
		c.turn.gwm_bonus = true
	if atk.get("drain", false) and dealt > 0:
		heal_creature(c, dealt / 2, c, "Vampiric Touch")
	_on_hit_riders(c, t, atk, res, opts)
	for se in wctx.get("smite_hits", []):
		_smite_rider(c, t, se)

## Riders that are spent even when the weapon attack misses:
##   spent_on_miss: Zephyr Strike's one charged attack.
##   on_miss: Lightning Arrow still deals half its damage to the target and bursts.
func _rider_on_miss(c: Dictionary, t: Dictionary, melee: bool, atk: Dictionary) -> void:
	if atk.get("spell_attack", false):
		return
	for e in c.effects.duplicate():
		if not e.get("one_hit", false) or (melee and e.get("ranged_only", false)) or (not melee and e.get("melee_only", false)):
			continue
		var om = e.get("on_miss", null)
		if e.get("spent_on_miss", false) and not om is Dictionary:
			c.effects.erase(e)
			continue
		if not om is Dictionary:
			continue
		c.effects.erase(e)
		var ex = e.get("mods", {}).get("extra_damage", null)
		if om.get("half_extra", false) and ex is Dictionary and alive(t):
			apply_damage(t, [{"amount": Dice.roll(str(ex.dice)).total / 2, "type": str(ex.type)}], c, {"spell": true})
		var oh = e.get("on_hit", {})
		if oh is Dictionary and oh.get("burst", null) is Dictionary:
			_burst(c, str(e.get("spell", "")), t.pos, oh.burst, int(e.get("dc", best_spell_dc(c))), int(e.get("upl", 0)))
		if e.get("conc", false) and c.conc.get("spell", "") == e.get("spell", ""):
			end_concentration(c, true)

## What a smite does beyond its damage (effect key "on_hit"), once it has landed:
##   save + push / condition (Thunderous Smite: pushed 10 ft and prone; Wrathful Smite: frightened,
##   shaken off with a WIS check as an action), or tick_damage (Searing Smite's flames).
## A rider that lasts keeps the caster's concentration; otherwise the spell ends here.
func _smite_rider(c: Dictionary, t: Dictionary, e: Dictionary) -> void:
	var oh: Dictionary = e.on_hit
	var dc: int = int(e.get("dc", best_spell_dc(c)))
	var lasting = false
	var rounds: int = maxi(1, int(e.get("rounds", 10)))
	# Hail of Thorns / Lightning Arrow: the shot bursts around the target.
	if oh.get("burst", null) is Dictionary:
		_burst(c, str(e.get("spell", "")), t.pos, oh.burst, dc, int(e.get("upl", 0)))
	# Banishing Smite: a target left at 50 HP or fewer is banished while the caster concentrates.
	if int(oh.get("banish_below", 0)) > 0 and alive(t) and t.hp > 0 and t.hp <= int(oh.banish_below):
		add_effect(t, {"name": "Banished", "cond": "banished", "src": c.id, "spell": e.get("spell", ""), "conc": true, "rounds": rounds, "tick_cid": c.id})
		log_line("  %s is banished!" % nm(t))
		lasting = true
	if alive(t):
		var failed = true
		if oh.has("save"):
			failed = not saving_throw(t, str(oh.save), dc, c, {"spell": true, "cond": str(oh.get("condition", ""))})
		# Staggering Smite: disadvantage and no reactions until the end of the target's next turn.
		if failed and oh.get("mods", null) is Dictionary:
			add_effect(t, {"name": e.get("name", "Smite"), "src": c.id, "spell": e.get("spell", ""), "mods": oh.mods.duplicate(true),
				"rounds": 2 if is_current(t) else 1, "tick_cid": t.id, "tick_on": "end"})
		if failed:
			if int(oh.get("push", 0)) > 0:
				push_creature(t, center_of(c), int(oh.push))
			var cond: String = str(oh.get("condition", ""))
			if cond != "" and alive(t):
				var ce = {"name": e.get("name", "Smite"), "cond": cond, "src": c.id, "spell": e.get("spell", ""), "conc": true,
					"rounds": rounds, "tick_cid": c.id, "tick_on": "start"}
				if cond == "prone":
					ce.name = "Prone"
					ce.conc = false
					ce.rounds = 9999
					ce.tick_cid = "none"
				if oh.get("escape", null) is Array:
					ce.escape_dc = dc
					ce.escape_with = oh.escape.duplicate()
				# Blinding Smite: the target repeats the save at the end of each of its turns.
				if oh.get("save_ends", false) and oh.has("save"):
					ce.save_ends = {"ability": str(oh.save), "dc": dc}
				if not add_effect(t, ce).is_empty() and ce.conc:
					lasting = true
		if oh.get("tick_damage", null) is Dictionary and alive(t):
			add_effect(t, {"name": e.get("name", "Smite"), "src": c.id, "spell": e.get("spell", ""), "conc": true, "rounds": rounds,
				"tick_cid": c.id, "tick_on": "start", "dc": dc, "tick_damage": oh.tick_damage.duplicate(true)})
			lasting = true
	if not lasting and e.get("conc", false) and c.conc.get("spell", "") == e.get("spell", ""):
		end_concentration(c, true)

## Roll weapon damage including all class/race riders. Returns [{amount, type}].
func weapon_damage(c: Dictionary, t: Dictionary, atk: Dictionary, res: Dictionary, ctx: Dictionary) -> Array:
	var crit: bool = res.get("crit", false)
	var melee: bool = atk.get("melee", true)
	var parts: Array = []
	var gwf: bool = "great_weapon_fighting" in c.get("styles", []) and melee and atk.get("two_handed", false)
	var notes: PackedStringArray = []
	var once: Dictionary = c.get("turn", {}).get("once", {})
	var my_turn = is_turn_of(c)
	var weapon_type = "bludgeoning"
	var first = true
	for d in atk.get("damage", []):
		var r = Dice.roll(d.dice, {"crit": crit, "reroll_below": 2 if gwf else 0})
		var amt: int = r.total
		if first:
			weapon_type = d.type
			# Savage Attacker: reroll weapon dice once per turn.
			if c.get("feats", []).has("savage_attacker") and melee and not once.get("savage", false):
				var r2 = Dice.roll(d.dice, {"crit": crit})
				if r2.total > amt:
					amt = r2.total
				once.savage = true
			if crit and melee and atk.has("die"):
				if c.tags.has("savage_attacks"):
					amt += Dice.roll(atk.die).total
				if int(c.vals.get("brutal_dice", 0)) > 0:
					amt += Dice.roll(Dice.times(atk.die, int(c.vals.brutal_dice))).total
		first = false
		parts.append({"amount": amt, "type": d.type})
	if parts.is_empty():
		return parts
	var crit_mult = 2 if crit else 1
	var wpn: bool = not atk.get("spell_attack", false)  # weapon-only riders skip Spiritual Weapon and other spell attacks
	var dmg_dice = func(expr: String, typ: String, label: String) -> void:
		var amt: int = Dice.roll(expr, {"crit": crit}).total
		parts.append({"amount": amt, "type": typ})
		notes.append("%s %d" % [label, amt])
	# Rage.
	if has_tag(c, "rage") and melee and wpn and atk.get("ability", "str") == "str":
		parts[0].amount += int(c.vals.get("rage_damage", 2))
	if ctx.get("power", false):
		parts[0].amount += 10
		notes.append("power attack +10")
	# Sneak Attack.
	if int(c.vals.get("sneak_dice", 0)) > 0 and (atk.get("finesse", false) or not melee) and not once.get("sneak", false) and not atk.get("spell_attack", false):
		var ok: bool = res.get("adv", 0) > 0
		if res.get("adv", 0) >= 0 and not ok:
			for o in allies_of(c, false):
				if conscious(o) and dist(o, t) <= 5:
					ok = true
					break
			if not ok and c.features.has("rakish_audacity") and dist(c, t) <= 5:
				var alone = true
				for o in all_combatants():
					if o.id != c.id and o.id != t.id and alive(o) and dist(o, c) <= 5:
						alone = false
				ok = alone
		if ok:
			once.sneak = true
			dmg_dice.call("%dd6" % int(c.vals.sneak_dice), weapon_type, "Sneak Attack")
	# Divine Smite (toggle, consumed on use).
	var smite_lv = int(c.get("toggles", {}).get("smite", 0))
	if smite_lv > 0 and melee and not atk.get("spell_attack", false):
		var lv = smite_lv if slots_free(c, smite_lv) > 0 else lowest_slot(c, smite_lv)
		if lv > 0 and spend_slot(c, lv):
			var n = mini(5, 1 + lv) + (1 if t.get("type", "") in ["undead", "fiend"] else 0)
			dmg_dice.call("%dd8" % n, "radiant", "Divine Smite")
			fx("burst", t.pos, t.pos, "#fff2a8")
		c.toggles.smite = 0
	if c.features.has("improved_divine_smite") and melee and wpn:
		dmg_dice.call("1d8", "radiant", "Improved Smite")
	# Divine Strike.
	for f in ["divine_strike_radiant", "divine_strike_thunder", "divine_strike_poison", "divine_strike_fire", "divine_strike_psychic", "divine_strike_weapon"]:
		# "Once on each of your turns": not on an opportunity attack during someone else's turn.
		if c.features.has(f) and my_turn and not once.get("divine_strike", false) and not atk.get("spell_attack", false):
			once.divine_strike = true
			var typ: String = weapon_type if f == "divine_strike_weapon" else f.replace("divine_strike_", "")
			dmg_dice.call("%dd8" % int(c.vals.get("divine_strike_dice", 1)), typ, "Divine Strike")
	if c.features.has("divine_fury") and has_tag(c, "rage") and wpn and not once.get("divine_fury", false):
		once.divine_fury = true
		dmg_dice.call("1d6+%d" % (c.class_levels.get("barbarian", 3) / 2), "radiant", "Divine Fury")
	if c.features.has("colossus_slayer") and wpn and t.hp < t.max_hp and not once.get("colossus", false):
		once.colossus = true
		dmg_dice.call("1d8", weapon_type, "Colossus Slayer")
	if c.features.has("dreadful_strikes") and wpn and not once.get("dreadful_" + t.id, false):
		once["dreadful_" + t.id] = true
		dmg_dice.call("1d4" if c.class_levels.get("ranger", 3) < 11 else "1d6", "psychic", "Dreadful Strikes")
	if c.features.has("gathered_swarm") and wpn and not once.get("swarm", false):
		once.swarm = true
		dmg_dice.call("1d6", "piercing", "Gathered Swarm")
	if c.get("turn", {}).get("ambush_extra", false) and not once.get("ambush", false) and int(c.turn.attacks) == 0:
		once.ambush = true
		dmg_dice.call("1d8", weapon_type, "Dread Ambusher")
	for rp in _caster_riders(c, t, "spell_attack" if atk.get("spell_attack", false) else "weapon", crit, weapon_type):
		parts.append(rp)
		notes.append("%s %d" % [rp.label, rp.amount])
	for e in t.effects:
		var tag: String = e.get("tag", "")
		if e.get("src", "") != c.id:
			continue
		if tag == "hexblade_curse":
			parts.append({"amount": int(c.prof), "type": weapon_type})
		elif tag == "planar_mark" and not once.get("planar", false) and not atk.get("spell_attack", false):
			once.planar = true
			dmg_dice.call("1d8" if c.class_levels.get("ranger", 3) < 11 else "2d8", "force", "Planar Warrior")
	for e in c.effects.duplicate():
		var ex = e.get("mods", {}).get("extra_damage", null)
		var has_dmg: bool = ex is Dictionary and not ex.is_empty()
		# A rider with no damage of its own still fires on the hit (Hail of Thorns' burst).
		var bare_rider: bool = not has_dmg and e.get("one_hit", false) and e.get("on_hit", null) is Dictionary
		# Smites, Divine Favor, Magic Weapon... ride on weapon attacks, not on spell attacks.
		if (has_dmg or bare_rider) and not atk.get("spell_attack", false):
			if melee and e.get("ranged_only", false):
				continue
			if not melee and e.get("melee_only", false):
				continue
			# Spirit Shroud: only against creatures within 10 ft.
			if int(e.get("within", 0)) > 0 and dist(c, t) > int(e.within):
				continue
			if has_dmg:
				dmg_dice.call(ex.dice, ex.type, e.get("name", "bonus"))
				_shroud_no_heal(c, t, e)
			if e.get("spell", "").ends_with("_smite") or e.get("one_hit", false):
				c.effects.erase(e)
				if e.get("on_hit", null) is Dictionary:
					# The smite's push, fear or flames land after the damage (see _smite_rider);
					# the spell's concentration carries a lasting rider.
					if not ctx.has("smite_hits"):
						ctx.smite_hits = []
					ctx.smite_hits.append(e)
				elif e.get("conc", false) and not e.get("keep_conc", false):
					end_concentration(c, true)
	if has_tag(c, "symbiotic") and melee and wpn:
		dmg_dice.call("1d6", "necrotic", "Symbiotic Entity")
	if has_tag(c, "radiant_soul") and not once.get("radiant_soul", false):
		once.radiant_soul = true
		parts.append({"amount": int(c.level), "type": "radiant"})
	if c.tags.has("fury_of_the_small") and t.sz > c.sz and res_left(c, "fury_of_the_small") > 0:
		spend_res(c, "fury_of_the_small")
		parts.append({"amount": int(c.level), "type": weapon_type})
		notes.append("Fury of the Small")
	if c.tags.has("surprise_attack") and s.round <= 1 and not t.get("acted", false) and not once.get("surprise", false):
		once.surprise = true
		dmg_dice.call("2d6", weapon_type, "Surprise Attack")
	if c.features.has("arcane_jolt") and atk.get("magic", false) and not once.get("jolt", false) and res_left(c, "arcane_jolt") > 0 and not atk.get("spell_attack", false):
		once.jolt = true
		spend_res(c, "arcane_jolt")
		dmg_dice.call("2d6", "force", "Arcane Jolt")
	if atk.get("launcher", false) and not once.get("launcher", false):
		once.launcher = true
		dmg_dice.call("1d6", "lightning", "Lightning Launcher")
	if "lifedrinker" in c.get("invocations", []) and melee and wpn and c.class_levels.get("warlock", 0) >= 12:
		parts.append({"amount": maxi(1, int(c.mods.cha)), "type": "necrotic"})
	# Maneuver dice.
	var man: String = str(c.get("toggles", {}).get("maneuver", ""))
	if man != "" and res_left(c, "superiority") > 0 and not atk.get("spell_attack", false):
		spend_res(c, "superiority")
		dmg_dice.call("1d%d" % int(c.vals.get("superiority_die", 8)), weapon_type, man.capitalize() + " Attack")
		c.turn["pending_maneuver"] = man
		c.toggles.maneuver = ""
	# Hand of Harm (once per turn, monk unarmed).
	if c.features.has("hand_of_harm") and atk.get("unarmed", false) and not once.get("harm", false) and res_left(c, "ki") >= 2:
		once.harm = true
		spend_res(c, "ki")
		dmg_dice.call("1d%d+%d" % [int(c.vals.martial_die), int(c.mods.wis)], "necrotic", "Hand of Harm")
	# Monster on-hit extra damage (no save).
	var oh: Dictionary = atk.get("on_hit", {})
	if not oh.is_empty() and oh.has("damage") and not oh.has("save"):
		for d in oh.damage:
			dmg_dice.call(d.dice, d.type, "")
	# Reduce (Enlarge/Reduce): the weapon deals 1d4 less damage (minimum 1).
	if wpn and not parts.is_empty():
		for pen in mod_list(c, "weapon_damage_penalty"):
			parts[0].amount = maxi(1, int(parts[0].amount) - Dice.roll(str(pen)).total)
	# Ray of Enfeeblement: half damage with Strength-based weapon attacks.
	if wpn and mod_any(c, "half_str_damage") and str(atk.get("ability", "str" if melee else "dex")) == "str":
		for p in parts:
			p.amount = int(p.amount) / 2
		notes.append("enfeebled: half damage")
	if not notes.is_empty():
		log_line("    (%s)" % ", ".join(notes))
	return parts

## Extra damage `c` deals to `t` because of a mark or curse it placed (mods.vulnerable_to_caster).
## kind: "weapon" (weapon attack), "spell_attack" (spell attack roll), "spell" (any other damaging spell).
##   Hunter's Mark: weapon attacks only. Hex: any attack. Bestow Curse and the like: attacks and spells.
func _caster_riders(c: Dictionary, t: Dictionary, kind: String, crit: bool, weapon_type := "") -> Array:
	var out: Array = []
	for e in t.effects:
		if e.get("src", "") != c.id:
			continue
		var v = e.get("mods", {}).get("vulnerable_to_caster", null)
		var tag: String = e.get("tag", "")
		if not v is Dictionary:
			if tag in ["hunters_mark", "hex"]:
				v = {"dice": "1d6", "type": "necrotic"}
			else:
				continue
		if tag == "hunters_mark" and kind != "weapon":
			continue
		if tag == "hex" and kind == "spell":
			continue
		var typ: String = str(v.get("type", "necrotic"))
		if tag == "hunters_mark" and weapon_type != "":
			typ = weapon_type
		var amt: int = Dice.roll(str(v.get("dice", "1d6")), {"crit": crit}).total
		var label: String = Data.spell(e.get("spell", tag)).get("name", e.get("name", "Curse"))
		out.append({"amount": amt, "type": typ, "label": label})
	return out

func _on_hit_riders(c: Dictionary, t: Dictionary, atk: Dictionary, res: Dictionary, opts: Dictionary) -> void:
	if not alive(t):
		return
	var melee: bool = atk.get("melee", true)
	# Maneuvers.
	var man: String = c.get("turn", {}).get("pending_maneuver", "")
	if man != "":
		c.turn.pending_maneuver = ""
		var dc = int(c.vals.get("maneuver_dc", 13))
		match man:
			"trip":
				if t.sz <= 2 and not saving_throw(t, "str", dc, c):
					add_effect(t, {"name": "Prone", "cond": "prone", "src": c.id, "rounds": 99, "tick_cid": t.id})
			"menacing":
				if not saving_throw(t, "wis", dc, c, {"cond": "frightened"}):
					add_effect(t, {"name": "Menaced", "cond": "frightened", "src": c.id, "rounds": 2, "tick_cid": c.id, "tick_on": "end"})
			"pushing":
				if t.sz <= 2 and not saving_throw(t, "str", dc, c):
					push_creature(t, center_of(c), 15)
			"goading":
				if not saving_throw(t, "wis", dc, c):
					add_effect(t, {"name": "Goaded", "tag": "goaded", "src": c.id, "rounds": 2, "tick_cid": c.id, "tick_on": "end"})
			"distracting":
				add_effect(t, {"name": "Distracted", "tag": "distracted", "src": "*", "for_team": c.team, "rounds": 1, "tick_cid": c.id, "tick_on": "start"})
	# Stunning Strike.
	if melee and c.get("toggles", {}).get("stunning", false) and res_left(c, "ki") > 0:
		spend_res(c, "ki")
		c.toggles.stunning = false
		log_line("%s attempts a Stunning Strike." % nm(c))
		if not saving_throw(t, "con", int(c.vals.ki_dc), c):
			add_effect(t, {"name": "Stunned", "cond": "stunned", "src": c.id, "rounds": 2, "tick_cid": c.id, "tick_on": "end"})
	# Open Hand Technique on flurry hits.
	if opts.get("flurry", false) and c.features.has("open_hand_technique"):
		if not saving_throw(t, "dex", int(c.vals.ki_dc), c):
			add_effect(t, {"name": "Prone", "cond": "prone", "src": c.id, "rounds": 99, "tick_cid": t.id})
	# Rage marks.
	if c.features.has("ancestral_protectors") and has_tag(c, "rage") and not c.get("turn", {}).get("once", {}).get("ancestral", false):
		c.turn.once.ancestral = true
		add_effect(t, {"name": "Ancestral Spirits", "tag": "ancestral_mark", "src": c.id, "rounds": 1, "tick_cid": c.id, "tick_on": "start"})
	if atk.get("guardian_mark", false):
		add_effect(t, {"name": "Thunder-struck", "tag": "guardian_mark", "src": c.id, "rounds": 1, "tick_cid": c.id, "tick_on": "start"})
	if int(atk.get("push", 0)) > 0 and t.sz <= 2:
		push_creature(t, center_of(c), int(atk.push))
	# Monster on-hit conditions.
	var oh: Dictionary = atk.get("on_hit", {})
	if not oh.is_empty():
		var failed = true
		if oh.has("save"):
			failed = not saving_throw(t, oh.save, int(oh.get("dc", 10)), c, {"cond": oh.get("condition", ""), "dmg_type": "poison" if str(oh.get("condition", "")) == "poisoned" else ""})
			if oh.has("damage"):
				var parts: Array = []
				for d in oh.damage:
					var amt: int = Dice.roll(d.dice).total
					if not failed:
						amt = amt / 2 if oh.get("half_on_save", true) else 0
					parts.append({"amount": amt, "type": d.type})
				apply_damage(t, parts, c, {"magic": atk.get("magic", false)})
		if failed and oh.get("condition", "") != "" and alive(t):
			var e = {"name": str(oh.condition).capitalize(), "cond": oh.condition, "src": c.id, "rounds": int(oh.get("duration_rounds", 10)), "tick_cid": c.id, "tick_on": "start"}
			if oh.get("save_ends", false) and oh.has("save"):
				e.save_ends = {"ability": oh.save, "dc": int(oh.get("dc", 10))}
			if oh.condition == "grappled":
				# Escaping takes the grappled creature's action (see "Escape Grapple"), not a free save.
				e.rounds = 99
				e.escape_dc = int(oh.get("escape_dc", 10))
				e.erase("save_ends")
			elif oh.has("escape_dc"):
				# Other escapable holds (Giant Spider's web): a Strength check as an action ends it.
				e.rounds = 99
				e.escape_dc = int(oh.escape_dc)
				e.escape_with = oh.get("escape_with", ["str"])
				e.erase("save_ends")
			if oh.condition == "prone":
				e.rounds = 99
				e.tick_cid = t.id
			add_effect(t, e)

func _multiattack(c: Dictionary, m: Dictionary, target: Dictionary) -> void:
	log_line("%s uses [b]%s[/b]." % [nm(c), m.name])
	var t = target
	for name in m.get("sequence", []):
		var atk = {}
		for a in attacks_of(c):
			if a.name == name:
				atk = a
				break
		if atk.is_empty():
			# Sequence might name a save action (e.g. Frightful Presence).
			for x in c.mactions:
				if x.name == name and x.get("kind", "") == "save":
					_monster_save_action(c, {"m": x, "area": x.get("area", {})}, [t], t.pos)
			continue
		if not alive(t) or t.hp <= 0:
			t = _nearest_enemy_in_range(c, atk)
			if t.is_empty():
				return
		var rng: int = int(atk.reach) if atk.melee else int(atk.get("long_range", atk.get("range", 0)))
		if dist(c, t) > rng:
			continue
		_attack_with(c, t, atk)

func _nearest_enemy_in_range(c: Dictionary, atk: Dictionary) -> Dictionary:
	var rng: int = int(atk.reach) if atk.melee else int(atk.get("long_range", atk.get("range", 0)))
	var best = {}
	var bd = 99999
	for o in enemies_of(c):
		if o.hp <= 0 and o.kind == "pc":
			continue
		var d = dist(c, o)
		if d <= rng and d < bd:
			bd = d
			best = o
	return best

func _monster_save_action(c: Dictionary, a: Dictionary, targets: Array, cellp: Vector2i) -> void:
	var m: Dictionary = a.m
	if int(m.get("recharge", 0)) > 0:
		c.recharge[m.name] = false
	log_line("%s uses [b]%s[/b]!" % [nm(c), m.name])
	var area: Dictionary = m.get("area", {})
	var victims: Array = targets
	if not area.is_empty():
		var shape: String = area.get("shape", "")
		var from_self: bool = shape in ["cone", "line", "emanation"] or (shape == "cube" and a.get("target", "") == "self_area")
		var cells = area_cells(c, area, cellp, from_self)
		fx("area", c.pos, cellp, _dmg_color(m.get("damage", [])), cells, _dmg_sfx(m.get("damage", [])))
		victims = creatures_in_cells(cells, c.id)
	var dc = int(m.get("dc", 10))
	# One damage roll for everyone caught (a dragon's breath is rolled once).
	var rolls: Array = []
	for d in m.get("damage", []):
		rolls.append(Dice.roll(d.dice).total)
	for t in victims:
		if not alive(t):
			continue
		var ok = saving_throw(t, m.get("save", "dex"), dc, c, {"cond": m.get("condition", ""), "magic": true})
		var parts: Array = []
		var di = 0
		for d in m.get("damage", []):
			var amt: int = int(rolls[di])
			di += 1
			if ok:
				amt = amt / 2 if m.get("half_on_save", true) else 0
			parts.append({"amount": amt, "type": d.type})
		if ok and t.features.has("evasion") and m.get("save", "") == "dex":
			parts = []
		elif not ok and t.features.has("evasion") and m.get("save", "") == "dex":
			for p in parts:
				p.amount = p.amount / 2
		if not parts.is_empty():
			apply_damage(t, parts, c, {"magic": true})
		if not ok and m.get("condition", "") != "" and alive(t):
			var e = {"name": str(m.condition).capitalize(), "cond": m.condition, "src": c.id, "rounds": int(m.get("duration_rounds", 10)), "tick_cid": c.id, "tick_on": "start"}
			if m.get("save_ends", false):
				e.save_ends = {"ability": m.get("save", "wis"), "dc": dc}
			add_effect(t, e)

func _dmg_color(parts: Array) -> String:
	var typ: String = parts[0].type if parts.size() > 0 else "force"
	return {"fire": "#ff7a2a", "cold": "#9fe6ff", "lightning": "#fff07a", "acid": "#9aff5a", "poison": "#6ad04a",
		"necrotic": "#8a4ac0", "radiant": "#fff2a8", "thunder": "#7aa8ff", "psychic": "#ff7ae0", "force": "#c8a0ff"}.get(typ, "#dddddd")

const MAGIC_TYPES := ["fire", "cold", "lightning", "thunder", "acid", "poison", "necrotic", "radiant", "psychic", "force"]

## Sound for spell or breath damage; physical damage (e.g. Magic Stone) gets a thrown-object sound.
func _dmg_sfx(parts: Array) -> String:
	if parts.is_empty():
		return "buff"
	var typ: String = parts[0].get("type", "force")
	if typ in ["bludgeoning", "piercing", "slashing"]:
		return "throw"
	return typ if typ in MAGIC_TYPES else "force"

## Sound for a weapon or natural attack: picked from the attack's name, then its damage type.
func _attack_sfx(atk: Dictionary, melee: bool) -> String:
	var parts: Array = atk.get("damage", [])
	var typ: String = parts[0].get("type", "") if parts.size() > 0 else ""
	if typ in MAGIC_TYPES and (atk.get("spell_attack", false) or atk.get("monster", false) and not melee):
		return _dmg_sfx(parts)
	var n = (str(atk.get("name", "")) + " " + str(atk.get("id", ""))).to_lower()
	if melee:
		if "bite" in n or "beak" in n: return "bite"
		if "claw" in n or "talon" in n or "rake" in n: return "claw"
		if atk.get("unarmed", false) or "unarmed" in n or "fist" in n or "slam" in n: return "punch"
		if typ == "bludgeoning": return "blunt"
		return "sword"
	if "crossbow" in n: return "crossbow"
	if "bow" in n or "arrow" in n: return "bow"
	return "throw"

# ================================================================ spells

func _make_effect(src: Dictionary, sp: Dictionary, e: Dictionary, dc: int, save_ab: String) -> Dictionary:
	var rounds = int(e.get("duration_rounds", sp.get("duration_rounds", 10)))
	if rounds <= 0:
		rounds = 9999
	var out = {"name": e.get("name", sp.get("name", "Effect")), "cond": e.get("condition", ""), "mods": e.get("mods", {}).duplicate(true),
		"src": src.get("id", ""), "spell": sp.get("id", ""), "rounds": rounds, "tick_cid": src.get("id", ""), "tick_on": "start",
		"conc": sp.get("concentration", false)}
	# An effect shorter than its spell (Heat Metal's 1-round disadvantage, Hunger of Hadar's blindness)
	# runs out without ending the caster's concentration.
	if out.conc and int(e.get("duration_rounds", 0)) > 0 and int(e.duration_rounds) < int(sp.get("duration_rounds", 0)):
		out.outlived = true
	if e.get("save_ends", false) and save_ab != "":
		out.save_ends = {"ability": save_ab, "dc": dc}
	# Knocked prone lasts until the creature stands up, not until a timer runs out.
	if out.cond == "prone":
		out.rounds = 9999
		out.tick_cid = "none"
		out.conc = false
	# One-shot riders: Guiding Bolt's advantage is spent by the next attack, Mind Sliver's
	# penalty by the next save.
	# one_hit: a weapon rider spent by the next hit (Zephyr Strike, Hail of Thorns); ranged_only: it rides
	# on ranged weapon attacks only; one_own_attack: spent by the bearer's next attack roll (Frostbite);
	# keep_conc: spending it doesn't end the caster's concentration; save_on_damage_adv: the new save
	# when hurt has advantage (Hideous Laughter).
	for flag in ["one_attack", "one_save", "melee_only", "one_hit", "ranged_only", "one_own_attack", "one_roll", "keep_conc", "save_on_damage_adv", "escape_save", "escape_auto", "spent_on_miss", "any_attack", "no_heal_on_hit"]:
		if e.get(flag, false):
			out[flag] = true
	# Restraints you can tear free of with an action (Web, Entangle...): ability check vs the spell DC
	# (or a fixed DC, like Maze's 20).
	if e.get("escape", null) is Array:
		out.escape_dc = int(e.get("escape_dc", dc))
		out.escape_with = e.escape.duplicate()
	# Three-save countdowns (Flesh to Stone, Contagion), damage back at melee attackers (Fire Shield),
	# a sealed-off space (Maze, Resilient Sphere): copied for the handlers.
	for key in ["save_count", "retaliate", "on_miss", "trail"]:
		if e.get(key, null) is Dictionary:
			out[key] = e[key].duplicate(true)
	if str(e.get("pocket", "")) != "":
		out.pocket = str(e.pocket)
	if int(e.get("within", 0)) > 0:
		out.within = int(e.within)
	# An effect that outlasts the spell that made it (Holy Weapon ends as its burst blinds).
	if e.get("no_conc", false):
		out.conc = false
	if sp.get("id", "") in END_ON_DAMAGE_SPELLS:
		out.end_on_damage = true
	if sp.get("id", "") in ["hunters_mark", "hex"]:
		out.tag = sp.id
	if str(e.get("tag", "")) != "":
		out.tag = e.tag
	out.dc = dc
	# Damage over time (Phantasmal Killer, Melf's Acid Arrow), a weapon-hit rider (smites),
	# a breath the target can exhale (Dragon's Breath): copied for the handlers to read.
	for key in ["tick_damage", "on_hit", "breath"]:
		if e.get(key, null) is Dictionary:
			out[key] = e[key].duplicate(true)
	# Enemies Abound: the target repeats the save each time it takes damage.
	if e.get("save_on_damage", false) and save_ab != "":
		out.save_on_damage = {"ability": save_ab, "dc": dc}
	return out

func _cast(c: Dictionary, a: Dictionary, targets: Array, cellp: Vector2i, params: Dictionary) -> bool:
	var sp = Data.spell(a.spell)
	var cb = sp.get("combat", null)
	var cbd: Dictionary = cb if cb is Dictionary else {}
	var slot = int(params.get("slot", a.slots[0] if a.slots.size() > 0 else 0))
	if not slot in a.slots:
		slot = a.slots[0]
	var opts: Dictionary = params.get("opts", {})
	var meta: String = str(c.get("toggles", {}).get("metamagic", ""))
	var cost: String = a.cost
	# Metamagic.
	var mm_cost = 0
	match meta:
		"quickened":
			if cost == "action" or a.get("quickened", false):
				cost = "bonus"
				mm_cost = 2
			else:
				meta = ""
		"twinned":
			mm_cost = maxi(1, slot)
		"empowered", "careful", "distant":
			mm_cost = 1
		"heightened":
			mm_cost = 3
	if meta != "" and res_left(c, "sorcery_points") < mm_cost:
		meta = ""
		cost = a.get("base_cost", a.cost)
	# Validate the economy before spending anything.
	if not can_pay(c, cost):
		log_line("[color=#888]%s has no %s left for %s.[/color]" % [c.name, cost, sp.name])
		return false
	var block := spell_block_reason(c, cost, int(a.level))
	if block != "":
		log_line("[color=#888]%s can't cast %s: %s.[/color]" % [c.name, sp.name, block])
		return false
	if meta != "":
		spend_res(c, "sorcery_points", mm_cost)
		log_line("%s uses %s Spell (%d SP)." % [nm(c), meta.capitalize(), mm_cost])
		c.toggles.metamagic = ""
	# Max targets.
	var max_t: int = int(a.get("max_targets", 1)) + int(a.get("targets_per_slot", 0)) * maxi(0, slot - int(a.level))
	if meta == "twinned":
		max_t += 1
	# Darts, rays and beams can each go to a different creature (or several to the same one).
	max_t = maxi(max_t, spell_shots(c, a, slot))
	if targets.size() > max_t:
		targets = targets.slice(0, max_t)
	# Pay.
	pay(c, cost)
	if a.get("innate", false):
		spend_res(c, "innate_" + a.spell)
	elif slot > 0:
		spend_slot(c, slot)
	if s.in_combat:
		if cost == "bonus": c.turn.cast_bonus = true
		elif cost == "action" and int(a.level) > 0: c.turn.cast_leveled_action = true
		if int(a.level) == 0: c.turn.cantrip = true
	remove_effects_where(c, func(e): return e.get("cond", "") == "invisible" and e.get("breaks", false))
	c.hidden = false
	var lvtxt = "" if slot == 0 else " (level %d)" % slot
	log_line("%s casts [b][color=#c8a0ff]%s[/color][/b]%s." % [nm(c), sp.name, lvtxt])
	sfx("cast", c.id)
	# Counterspell from the other side.
	if int(sp.level) > 0 and _try_counterspell(c, sp, slot):
		return true
	if sp.get("concentration", false):
		start_concentration(c, sp.id, sp.name)
	# Sanctuary: a harmful spell aimed at a warded creature needs a WIS save first; on a failure the
	# caster picks a new target in range, or that part of the spell is lost. Casting a harmful spell at
	# an enemy ends the caster's own ward. (Spell attacks are checked per attack roll in roll_attack.)
	var harmful: bool = cbd.get("save", null) != null or cbd.has("damage") or int(cbd.get("darts", 0)) > 0
	if harmful and cbd.get("attack", null) == null and cbd.get("target", "") in ["enemy", "creature"]:
		var kept: Array = []
		var taken: Array = targets.map(func(o): return o.id)
		# Magic Missile's darts keep repeat picks (two darts at one creature); the Sanctuary check is
		# made once per creature, not once per dart.
		var repeats: bool = spell_shots(c, a, slot) > 0
		var redirected: Dictionary = {}
		for t in targets:
			var nt: Dictionary = redirected[t.id] if redirected.has(t.id) else sanctuary_target(c, t, maxi(5, int(sp.get("range", 0))), taken)
			redirected[t.id] = nt
			if nt.is_empty():
				continue
			_break_sanctuary(c, nt)
			if repeats or not nt in kept:
				kept.append(nt)
			if not nt.id in taken:
				taken.append(nt.id)
		if kept.is_empty() and not targets.is_empty():
			log_line("  The spell is lost.")
			if sp.get("concentration", false):
				end_concentration(c, true)
			return true
		targets = kept
	if cbd.is_empty():
		log_line("  [color=#999](%s has no combat automation — the DM resolves its effects.)[/color]" % sp.name)
		return true
	var ctx = {"slot": slot, "upl": maxi(0, slot - int(sp.level)), "meta": meta, "opts": opts, "entry": caster_entry(c, a["class"]),
		"dc": int(a.dc), "attack": int(a.spell_attack), "cell": cellp}
	var special: String = cbd.get("special", "")
	if special != "" and has_method("_sp_" + special):
		var handled: bool = call("_sp_" + special, c, sp, cbd, targets, ctx)
		if handled:
			_after_cast(c, sp, ctx)
			return true
	_generic_spell(c, sp, cbd, targets, ctx)
	_after_cast(c, sp, ctx)
	return true

func _after_cast(c: Dictionary, sp: Dictionary, ctx: Dictionary) -> void:
	var cb = sp.get("combat", null)
	if cb is Dictionary and cb.get("repeat", null) is Dictionary:
		_start_repeat(c, sp, cb, ctx)
	_after_cast_wards(c, sp, ctx)

# ---------------------------------------------------------------- repeatable spells
# combat.repeat: what the caster can do again on later turns while the spell lasts (Call Lightning's
# bolt, Flame Blade's slashes, Bigby's Hand, Draconic Transformation's breath, Melf's meteors...).
#   cost: action | bonus | attack (uses the Attack action, so Extra Attack applies) | free
#   combat: a combat block resolved like a spell (target, area, save, damage, attack, special...)
#     weapon_attack: true makes it a weapon attack (Shadow Blade) using the caster's STR or DEX
#     move_zone: true moves the spell's zone to the chosen point (Flaming Sphere, Dawn); "move": max feet,
#       "ram": creatures in the new spot are caught at once
#   uses / uses_per_slot: limited shots (Melf's Minute Meteors, Crown of Stars); per_use: shots per action
#   same_turn: usable on the turn it's cast (otherwise from the next turn)
#   range, label, origin: "cell" (the area starts from the point picked at casting: Illusory Dragon)
#   ends_spell: using it ends the spell (Holy Weapon's burst, Delayed Blast Fireball's detonation)
# While it lasts the caster carries a "repeat" marker effect; concentration spells lose it with
# concentration, the others when their duration runs out.

func _start_repeat(c: Dictionary, sp: Dictionary, cbd: Dictionary, ctx: Dictionary) -> void:
	var rp: Dictionary = cbd.repeat
	if sp.get("concentration", false) and c.conc.get("spell", "") != sp.id:
		return
	var uses: int = int(rp.get("uses", 0))
	if uses > 0:
		uses += int(rp.get("uses_per_slot", 0)) * int(ctx.upl)
	remove_effects_where(c, func(e): return e.get("tag", "") == "repeat" and e.get("spell", "") == sp.id)
	add_effect(c, {"name": "%s (active)" % sp.name, "tag": "repeat", "spell": sp.id, "src": c.id, "uses": uses,
		"upl": int(ctx.upl), "slot": int(ctx.slot), "dc": int(ctx.dc), "attack": int(ctx.attack), "class": str(ctx.entry.get("class", "")),
		"conc": sp.get("concentration", false), "rounds": maxi(1, int(rp.get("rounds", sp.get("duration_rounds", 10)))), "tick_cid": c.id, "tick_on": "start",
		"cast_serial": int(c.get("turn", {}).get("serial", -1)), "origin": ctx.cell})

## The actions offered by `c`'s active repeatable spells.
func _repeat_actions(c: Dictionary) -> Array:
	var out: Array = []
	for e in c.effects:
		if e.get("tag", "") != "repeat":
			continue
		var sp = Data.spell(str(e.get("spell", "")))
		var rp = sp.get("combat", {}).get("repeat", null) if sp.get("combat", null) is Dictionary else null
		if not rp is Dictionary:
			continue
		var sub: Dictionary = rp.get("combat", {})
		var tgt: String = str(sub.get("target", "enemy"))
		var rng: int = int(rp.get("range", sp.get("range", 0)))
		if rng <= 0:
			rng = 5 if sub.get("attack", null) == "melee" or sub.get("weapon_attack", false) else 60
		var desc: String = str(rp.get("desc", "Use %s again." % sp.name))
		if int(e.get("uses", 0)) > 0:
			desc += " (%d left)" % int(e.uses)
		var a = _act("rp:" + str(e.eid), str(rp.get("label", sp.name)), "feature", str(rp.get("cost", "action")), tgt, rng, desc,
			{"cat": "spell", "eid": e.eid, "area": sub.get("area", {}), "max_targets": int(sub.get("max_targets", 1)), "repeat": true, "spell": sp.id})
		if tgt == "self" and sub.get("area", {}).is_empty():
			a.target = "self"
		if s.in_combat and not rp.get("same_turn", false) and int(e.get("cast_serial", -1)) == int(c.get("turn", {}).get("serial", -2)):
			a.enabled = false
			a.reason = "Starts on your next turn"
		out.append(a)
	return out

func _repeat_effect(c: Dictionary, eid: String) -> Dictionary:
	for e in c.effects:
		if e.get("eid", "") == eid and e.get("tag", "") == "repeat":
			return e
	return {}

func _run_repeat(c: Dictionary, eid: String, targets: Array, cellp: Vector2i, opts: Dictionary) -> void:
	var e: Dictionary = _repeat_effect(c, eid)
	if e.is_empty():
		return
	var sp = Data.spell(str(e.spell))
	var rp: Dictionary = sp.combat.repeat
	var sub: Dictionary = rp.get("combat", {})
	var ctx = {"slot": int(e.slot), "upl": int(e.upl), "meta": "", "opts": opts, "entry": caster_entry(c, str(e.get("class", ""))),
		"dc": int(e.dc), "attack": int(e.attack), "cell": cellp}
	if str(rp.get("origin", "")) == "cell" and e.get("origin", null) is Vector2i:
		ctx.origin_cell = e.origin
	log_line("%s uses [b]%s[/b]." % [nm(c), str(rp.get("label", sp.name))])
	var shots: int = maxi(1, int(rp.get("per_use", 1)))
	if int(e.get("uses", 0)) > 0:
		shots = mini(shots, int(e.uses))
	for i in shots:
		if sub.get("move_zone", false):
			_move_spell_zone(c, sp, rp, cellp)
		elif sub.get("weapon_attack", false):
			if not targets.is_empty():
				_attack_with(c, targets[0], _conjured_weapon(c, sp, sub, int(e.upl)), {})
		elif str(sub.get("special", "")) != "" and has_method("_sp_" + str(sub.special)):
			call("_sp_" + str(sub.special), c, sp, sub, targets, ctx)
		else:
			_generic_spell(c, sp, sub, targets, ctx)
	if int(e.get("uses", 0)) > 0:
		e.uses = int(e.uses) - shots
		if int(e.uses) <= 0:
			c.effects.erase(e)
			log_line("  That was the last of %s." % sp.name)
			if sp.get("concentration", false) and c.conc.get("spell", "") == sp.id:
				end_concentration(c, true)
	if rp.get("ends_spell", false):
		c.effects.erase(e)
		if c.conc.get("spell", "") == sp.id:
			end_concentration(c, true)

## A conjured blade used as a weapon (Shadow Blade): finesse, so STR or DEX, with proficiency.
func _conjured_weapon(c: Dictionary, sp: Dictionary, sub: Dictionary, upl: int) -> Dictionary:
	var ab: int = maxi(ability_mod(c, "str"), ability_mod(c, "dex"))
	var dice: String = str(sub.get("damage", [{"dice": "2d8"}])[0].dice)
	var steps: int = upl
	if sp.id == "shadow_blade":
		steps = mini(3, (upl + 1) / 2)  # 3d8 at 3rd-4th, 4d8 at 5th-6th, 5d8 at 7th+
	if steps > 0 and str(sub.get("upcast_dice", "")) != "":
		dice = Dice.add(dice, Dice.times(str(sub.upcast_dice), steps))
	dice = Dice.add(dice, str(ab))
	return {"id": "conj_" + sp.id, "name": sp.name, "melee": true, "to_hit": int(c.get("prof", 2)) + ab, "reach": 5,
		"damage": [{"dice": dice, "type": str(sub.get("damage", [{"type": "psychic"}])[0].type)}], "magic": true, "props": ["finesse", "light"], "die": "1d8"}

## Move a spell's zone so it's centred on `cell` (Flaming Sphere, Dust Devil, Dawn, Healing Spirit...).
func _move_spell_zone(c: Dictionary, sp: Dictionary, rp: Dictionary, dest: Vector2i) -> void:
	for z in s.zones:
		if z.get("src", "") != c.id or z.get("spell", "") != sp.id:
			continue
		var from: Vector2i = z.get("center", dest)
		if int(rp.get("move", 0)) > 0 and cheb(from, dest) * 5 > int(rp.move):
			log_line("  That's too far to move it (%d ft max)." % int(rp.move))
			return
		z.center = dest
		z.cells = area_cells(c, z.get("area", {"shape": "sphere", "size": 5}), dest, false)
	log_line("  %s moves." % sp.name)
	if rp.get("ram", false):
		for z in s.zones.duplicate():
			if z.get("src", "") != c.id or z.get("spell", "") != sp.id or z.get("hidden", false):
				continue
			for o in creatures_in_cells(z.cells, c.id):
				if _zone_applies(z, o) and _zone_once(z, o):
					_resolve_area_effect(c, o, z.data, int(z.dc), z.spell, int(z.get("upl", 0)), z)
			break

func _after_cast_wards(c: Dictionary, sp: Dictionary, ctx: Dictionary) -> void:
	if c.features.has("arcane_ward") and sp.get("school", "") == "abjuration" and int(ctx.slot) > 0:
		var mx: int = 2 * c.class_levels.get("wizard", 2) + int(c.mods.int)
		if not c.get("ward_made", false):
			c.ward = mx
			c.ward_made = true
		else:
			c.ward = mini(mx, int(c.ward) + 2 * int(ctx.slot))
		log_line("  Arcane Ward: %d HP." % c.ward)

func _try_counterspell(caster: Dictionary, sp: Dictionary, slot: int) -> bool:
	for o in enemies_of(caster):
		if not knows_spell(o, "counterspell") or not can_react_spell(o) or dist(o, caster) > 60 or not o.form.is_empty():
			continue
		var lv = lowest_slot(o, maxi(3, mini(slot, 9)))
		if lv == 0:
			lv = lowest_slot(o, 3)
		if lv == 0:
			continue
		spend_slot(o, lv)
		use_reaction(o)
		log_line("%s casts [b]Counterspell[/b] (level %d)!" % [nm(o), lv])
		fx("bolt", o.pos, caster.pos, "#7ad0ff", [], "force")
		if slot <= lv:
			log_line("  [color=#7ad0ff]%s's %s is countered![/color]" % [nm(caster), sp.name])
			return true
		var e = caster_entry(o, "wizard")
		var roll: int = Dice.d20() + int(e.get("mod", 0))
		if roll >= 10 + slot:
			log_line("  Ability check %d vs DC %d — [color=#7ad0ff]countered![/color]" % [roll, 10 + slot])
			return true
		log_line("  Ability check %d vs DC %d — the spell gets through." % [roll, 10 + slot])
		return false
	return false

func _spell_mod(c: Dictionary, ctx: Dictionary) -> int:
	return int(ctx.entry.get("mod", 0))

## Build damage parts (unrolled) for a spell at a slot.
func _spell_damage(c: Dictionary, sp: Dictionary, cbd: Dictionary, ctx: Dictionary) -> Array:
	var parts: Array = []
	var tier = 1
	if cbd.get("cantrip_scaling", false) or int(sp.get("level", 0)) == 0 and cbd.has("damage"):
		var cl = int(c.get("cl", c.level))
		tier = 1 + (1 if cl >= 5 else 0) + (1 if cl >= 11 else 0) + (1 if cl >= 17 else 0)
	var first = true
	for d in cbd.get("damage", []):
		var dice: String = d.dice
		if int(sp.get("level", 0)) == 0 and cbd.get("cantrip_scaling", true) and not cbd.get("beams_scale", false) and not cbd.get("special", "") in ["magic_stone"]:
			dice = Dice.scale_dice(dice, tier)
		if first and int(ctx.upl) > 0 and cbd.get("upcast_dice", "") != "":
			var up_steps: int = ctx.upl
			if sp.id in ["spiritual_weapon", "flame_blade", "shadow_blade", "elemental_weapon"]:
				up_steps = ctx.upl / 2
			dice = Dice.add(dice, Dice.times(cbd.upcast_dice, up_steps))
		var typ: String = d.type
		var dt: String = str(ctx.opts.get("dtype", ""))
		if dt != "" and dt in Data.DAMAGE_TYPES and (sp.id == "chromatic_orb" or c.features.has("awakened_spellbook") or sp.id in ["dragons_breath", "elemental_weapon", "spirit_shroud"]):
			typ = dt
		if first:
			var flat = 0
			if cbd.get("add_mod", false): flat += _spell_mod(c, ctx)
			if sp.id == "eldritch_blast" and "agonizing_blast" in c.get("invocations", []): flat += int(c.mods.cha)
			if c.features.has("potent_spellcasting") and int(sp.level) == 0 and ctx.entry.get("class", "") == "cleric": flat += int(c.mods.wis)
			if c.features.has("empowered_evocation") and sp.get("school", "") == "evocation" and ctx.entry.get("class", "") == "wizard": flat += int(c.mods.int)
			if c.features.has("elemental_affinity") and typ == str(c.choices.get("dragon_ancestor", "fire")): flat += int(c.mods.cha)
			if c.features.has("alchemical_savant") and ctx.entry.get("class", "") == "artificer" and typ in ["acid", "fire", "necrotic", "poison"]: flat += maxi(1, int(c.mods.int))
			if flat != 0:
				dice = Dice.add(dice, str(flat))
			if c.features.has("arcane_firearm") and ctx.entry.get("class", "") == "artificer":
				dice = Dice.add(dice, "1d8")
		first = false
		parts.append({"dice": dice, "type": typ})
	return parts

func _roll_parts(c: Dictionary, parts: Array, crit: bool, ctx: Dictionary) -> Array:
	var out: Array = []
	var adept: String = ""
	if c.get("feats", []).has("elemental_adept"):
		adept = str(c.choices.get("elemental_adept", "fire"))
	for p in parts:
		var o = {"crit": crit}
		if adept == p.type:
			o.min_die = 2
		var r = Dice.roll(p.dice, o)
		var amt: int = r.total
		if ctx.get("meta", "") == "empowered":
			# Reroll the lowest dice (up to CHA mod) and keep the new values.
			var rolls: Array = r.rolls.duplicate()
			rolls.sort()
			var n = mini(maxi(1, int(c.mods.cha)), rolls.size())
			for i in n:
				var sides = 0
				for t in Dice.parse(p.dice):
					if t.has("s"): sides = int(t.s)
				if sides > 0 and rolls[i] < (sides + 1) / 2.0:
					amt += Dice.d(sides) - int(rolls[i])
		out.append({"amount": amt, "type": p.type})
	return out

func _spell_targets_area(c: Dictionary, sp: Dictionary, cbd: Dictionary, ctx: Dictionary) -> Array:
	var area: Dictionary = cbd.get("area", {})
	var tgt: String = cbd.get("target", "")
	var from_self = tgt == "self_area" or area.get("shape", "") in ["cone", "line", "emanation"]
	var origin: Dictionary = c
	# Illusory Dragon breathes from where the dragon is, not from the caster.
	if ctx.get("origin_cell", null) is Vector2i:
		origin = {"id": "", "pos": ctx.origin_cell, "sz": 1, "size": "medium", "form": {}}
	var cells = area_cells(origin, area, ctx.cell, from_self)
	ctx.cells = cells
	var color = _dmg_color(cbd.get("damage", [{"type": "force"}]))
	fx("area", c.pos, ctx.cell, color, cells, _dmg_sfx(cbd.get("damage", [])))
	var victims = creatures_in_cells(cells, c.id if from_self else "")
	# "Each creature of your choice" areas (Word of Radiance, Destructive Wave) spare the caster's side.
	if cbd.get("enemies_only", false):
		victims = victims.filter(func(v): return hostile(c, v))
	# Sculpt Spells / Careful Spell protect allies.
	if (c.features.has("sculpt_spells") and sp.get("school", "") == "evocation") or ctx.meta == "careful":
		var spared = 0
		var limit = 1 + int(sp.level) if ctx.meta != "careful" else maxi(1, int(c.mods.cha))
		var keep: Array = []
		for v in victims:
			if not hostile(c, v) and spared < limit:
				spared += 1
				log_line("  %s is shielded from the spell." % nm(v))
				continue
			keep.append(v)
		victims = keep
	return victims

func _generic_spell(c: Dictionary, sp: Dictionary, cbd: Dictionary, targets: Array, ctx: Dictionary) -> void:
	var upl: int = ctx.upl
	# Areas that grow with the slot (Fog Cloud +20 ft, Confusion +5 ft radius per level).
	if int(cbd.get("area_per_slot", 0)) > 0 and upl > 0 and not cbd.get("area", {}).is_empty():
		cbd = cbd.duplicate(true)
		cbd.area.size = int(cbd.area.size) + int(cbd.area_per_slot) * upl
	var dc: int = ctx.dc
	var tgt: String = cbd.get("target", "self")
	var victims: Array = targets
	if not cbd.get("area", {}).is_empty() and tgt in ["point", "self_area", "self"] and cbd.get("aura", {}).is_empty():
		victims = _spell_targets_area(c, sp, cbd, ctx)
	elif tgt == "self":
		victims = [c]
	victims = _filter_spell_victims(c, cbd, victims)
	var dmg_parts = _spell_damage(c, sp, cbd, ctx)
	var spell_lv = int(sp.level)
	var kill_opts = {"spell": true, "spell_level": ctx.slot, "school": sp.get("school", "")}
	# A buff on the caster that comes with the spell (Draconic Transformation's flight).
	if cbd.get("self_effect", null) is Dictionary:
		var se = _make_effect(c, sp, cbd.self_effect, dc, "")
		add_effect(c, se)
	# --- attack-roll spells (with rays)
	if cbd.get("attack", null) != null and not victims.is_empty():
		var rays = int(cbd.get("rays", 1)) + int(cbd.get("rays_per_slot", 0)) * upl
		if cbd.get("beams_scale", false):
			var cl = int(c.get("cl", c.level))
			rays = 1 + (1 if cl >= 5 else 0) + (1 if cl >= 11 else 0) + (1 if cl >= 17 else 0)
		elif not cbd.has("rays") and victims.size() > 1:
			# Multi-target attack spells (Steel Wind Strike) roll one attack per chosen creature.
			rays = victims.size()
		var atk = {"to_hit": ctx.attack, "melee": cbd.attack == "melee", "range": int(sp.range)}
		for i in rays:
			var t: Dictionary = victims[i % victims.size()]
			if not alive(t):
				continue
			fx("bolt", c.pos, t.pos, _dmg_color(cbd.get("damage", [{"type": "force"}])), [], _dmg_sfx(cbd.get("damage", [])))
			var r = roll_attack(c, t, atk, {"melee": cbd.attack == "melee", "spell": true})
			t = r.get("target", t)
			if r.hit:
				if not dmg_parts.is_empty():
					var o = kill_opts.duplicate()
					o.crit = r.crit
					o.attack = true
					o.melee = cbd.attack == "melee"
					var rolled_a = _roll_parts(c, dmg_parts, r.crit, ctx)
					rolled_a.append_array(_caster_riders(c, t, "spell_attack", r.crit))
					rolled_a.append_array(_spell_attack_riders(c, t, r.crit))
					apply_damage(t, rolled_a, c, o)
				# Ray of Sickness: the rider also needs a failed save ("effect_save").
				if cbd.get("effect_save", null) == null or (alive(t) and not saving_throw(t, str(cbd.effect_save), dc, c, {"spell": true, "cond": cbd.get("effect", {}).get("condition", "")})):
					_apply_spell_effect(c, sp, cbd, t, dc, ctx)
				_forced_move(c, t, cbd, center_of(c), upl)
				if not ctx.has("hit_target"):
					ctx.hit_target = t.id
				if cbd.get("special", "") == "eldritch_blast" and "repelling_blast" in c.get("invocations", []) and alive(t):
					push_creature(t, center_of(c), 10)
			elif cbd.get("half_on_miss", false) and not dmg_parts.is_empty():
				# Melf's Acid Arrow: a miss still splashes half the initial damage (and nothing later).
				var halfp = _roll_parts(c, dmg_parts, false, ctx)
				for p in halfp:
					p.amount = int(p.amount) / 2
				apply_damage(t, halfp, c, kill_opts)
			# Ice Knife: the shard bursts around the target whether it hit or not.
			if cbd.get("burst", null) is Dictionary:
				_burst(c, sp.id, t.pos, cbd.burst, dc, upl)
		_start_sustain(c, sp, cbd, ctx, ctx.get("hit_target", ""))
		return
	# --- magic missile style darts
	if int(cbd.get("darts", 0)) > 0:
		_sp_magic_missile(c, sp, cbd, victims, ctx)
		return
	# --- saving-throw spells
	if cbd.get("save", null) != null:
		var first_failed: bool = false
		var center: Vector2 = Vector2(ctx.cell) + Vector2(0.5, 0.5) if tgt == "point" else center_of(c)
		# A spell that hits several creatures at once (Fireball, Sacred Flame twinned...) rolls its
		# damage once; each creature then takes all, half or none of that roll by its own save.
		var shared: Array = _roll_parts(c, dmg_parts, false, ctx) if not dmg_parts.is_empty() else []
		for t in victims:
			if not alive(t):
				continue
			if tgt in ["enemy", "creature"]:
				fx("bolt", c.pos, t.pos, _dmg_color(cbd.get("damage", [{"type": "force"}])), [], _dmg_sfx(cbd.get("damage", [])))
			var ok: bool
			# Willing creatures can choose to fail (Levitate, Vortex Warp on an ally).
			if cbd.get("save_only_hostile", false) and not hostile(c, t):
				ok = false
			else:
				ok = saving_throw(t, cbd.save, dc, c, {"spell": true, "cond": cbd.get("effect", {}).get("condition", ""), "heightened": ctx.meta == "heightened" and t == victims[0], "dmg_type": dmg_parts[0].type if dmg_parts.size() > 0 else ""})
			if t == victims[0]:
				first_failed = not ok
			if not dmg_parts.is_empty():
				var rolled: Array = shared.duplicate(true)
				var half: bool = cbd.get("half_on_save", false) or (spell_lv == 0 and c.features.has("potent_cantrip"))
				var always: bool = cbd.get("no_save_damage", false)  # Feeblemind: the damage lands either way
				if always:
					pass
				elif cbd.save == "dex" and t.features.has("evasion") and half:
					for p in rolled:
						p.amount = 0 if ok else p.amount / 2
				elif ok:
					for p in rolled:
						p.amount = p.amount / 2 if half else 0
				if not ok or half or always:
					rolled.append_array(_caster_riders(c, t, "spell", false))
					var dopts: Dictionary = kill_opts.duplicate()
					if cbd.has("min_hp"):
						dopts.min_hp = int(cbd.min_hp)
					var lost: int = apply_damage(t, rolled, c, dopts)
					if cbd.get("drain", false) and lost > 0:
						heal_creature(c, lost / 2, c, sp.name)
					# Harm: a failed save also cuts the hit point maximum by the damage taken.
					if not ok and cbd.get("reduce_max_hp", false) and lost > 0 and alive(t):
						var cut: int = mini(lost, int(t.max_hp) - 1)
						t.max_hp = int(t.max_hp) - cut
						t.max_hp_cut = int(t.get("max_hp_cut", 0)) + cut
						t.hp = mini(int(t.hp), int(t.max_hp))
						log_line("  %s's hit point maximum drops by %d." % [nm(t), cut])
			if not ok:
				_apply_spell_effect(c, sp, cbd, t, dc, ctx)
				_forced_move(c, t, cbd, center, upl)
				if cbd.get("flee", false):
					_flee(t, c)
			elif cbd.get("save_ends_spell", false) and victims.size() == 1 and sp.get("concentration", false):
				# Enervation: a successful save ends the spell.
				end_concentration(c, true)
		if cbd.has("sustain") and not victims.is_empty() and first_failed:
			_start_sustain(c, sp, cbd, ctx, victims[0].id)
		_spell_zone(c, sp, cbd, ctx)
		return
	# --- automatic damage (no attack/save)
	if not dmg_parts.is_empty() and cbd.get("zone", {}).is_empty() and cbd.get("aura", {}).is_empty():
		var rolled_all: Array = _roll_parts(c, dmg_parts, false, ctx)
		for t in victims:
			apply_damage(t, rolled_all.duplicate(true), c, kill_opts)
	# --- healing
	if cbd.has("heal"):
		var heal_dice: String = cbd.heal
		if int(ctx.upl) > 0 and cbd.get("upcast_heal", "") != "":
			heal_dice = Dice.add(heal_dice, Dice.times(cbd.upcast_heal, ctx.upl))
		if cbd.get("add_mod", false):
			heal_dice = Dice.add(heal_dice, str(_spell_mod(c, ctx)))
		var area_heal: bool = not cbd.get("area", {}).is_empty()
		for t in victims:
			if not alive(t):
				continue
			# Area healing (Healing Spirit) only mends the caster's side.
			if area_heal and hostile(c, t):
				continue
			# Cure Wounds, Healing Word and their mass and prayer versions don't work on undead or constructs.
			if sp.id in NO_UNDEAD_HEALING and str(t.get("type", "")) in ["undead", "construct"]:
				log_line("  %s has no effect on %s." % [sp.name, nm(t)])
				continue
			# Beacon of Hope: healing is maximized.
			var maxed: bool = (c.features.has("circle_of_mortality") and t.hp <= 0) or mod_any(t, "max_heal")
			var amt: int = Dice.roll(heal_dice, {"max": maxed}).total
			if c.features.has("disciple_of_life") and spell_lv > 0:
				amt += 2 + int(ctx.slot)
			if c.features.has("alchemical_savant") and ctx.entry.get("class", "") == "artificer":
				amt += maxi(1, int(c.mods.int))
			if sp.id == "aid":
				# Aid raises max HP while it lasts; a new casting replaces the old bonus rather than stacking.
				t.max_hp = int(t.max_hp) - int(t.get("aid_bonus", 0)) + amt
				t.aid_bonus = amt
				t.hp = mini(int(t.hp), int(t.max_hp))
			heal_creature(t, amt, c, sp.name)
			fx("burst", t.pos, t.pos, "#7fdc7f")
		_starry_chalice(c, victims)
	# --- temp hp
	if cbd.has("temp_hp"):
		var thp: String = cbd.temp_hp
		if int(ctx.upl) > 0 and cbd.get("upcast_temp_hp", "") != "":
			thp = Dice.add(thp, Dice.times(cbd.upcast_temp_hp, ctx.upl))
		for t in victims:
			grant_temp_hp(t, Dice.roll(thp).total, sp.name)
	# --- buffs and other effects
	if cbd.has("effect") and cbd.get("save", null) == null:
		for t in victims:
			_apply_spell_effect(c, sp, cbd, t, dc, ctx)
	if cbd.has("sustain") and not victims.is_empty():
		_start_sustain(c, sp, cbd, ctx, victims[0].id)
	# --- auras and zones
	if not cbd.get("aura", {}).is_empty():
		var aura: Dictionary = cbd.aura.duplicate(true)
		# Keep the spell's own effect on the caster (Warding Wind) apart from the aura marker.
		var aura_name: String = sp.name + " (aura)" if cbd.has("effect") else sp.name
		add_effect(c, {"name": aura_name, "spell": sp.id, "src": c.id, "aura": aura, "dc": dc, "upl": upl, "conc": sp.get("concentration", false),
			"rounds": maxi(1, int(sp.get("duration_rounds", 10))), "tick_cid": c.id, "tick_on": "start"})
		log_line("  An aura surrounds %s." % nm(c))
	_spell_zone(c, sp, cbd, ctx)

func _spell_zone(c: Dictionary, sp: Dictionary, cbd: Dictionary, ctx: Dictionary) -> void:
	if cbd.get("zone", {}).is_empty():
		return
	var cells: Array = ctx.get("cells", [])
	if cells.is_empty():
		cells = area_cells(c, cbd.get("area", {"shape": "sphere", "size": 5}), ctx.cell, cbd.get("target", "") == "self_area")
	# Zones last for the spell's duration (counted on the caster's turns); 0 = permanent terrain (Plant Growth).
	# "zones_extra" lays more triggers over the same cells (Hunger of Hadar: cold at the start of a turn,
	# acid at the end); those are hidden on the map so the area is drawn once.
	var datas: Array = [cbd.zone]
	datas.append_array(cbd.get("zones_extra", []))
	for i in datas.size():
		var zd: Dictionary = datas[i]
		var z = {"zid": new_id("z"), "src": c.id, "spell": sp.id, "name": sp.name, "cells": cells, "data": zd, "dc": ctx.dc,
			"upl": ctx.upl, "conc": sp.get("concentration", false), "rounds": maxi(0, int(sp.get("duration_rounds", 0))),
			"color": _dmg_color(zd.get("damage", cbd.get("damage", [{"type": "force"}]))),
			"center": ctx.cell, "area": cbd.get("area", {}), "self_area": cbd.get("target", "") == "self_area"}
		# Zones with a limited number of uses (Cordon of Arrows' four pieces, Healing Spirit's 1 + modifier).
		if zd.has("uses") or zd.get("uses_mod", false):
			var n: int = int(zd.get("uses", 0)) + int(zd.get("uses_per_slot", 0)) * int(ctx.upl)
			if zd.get("uses_mod", false):
				n = maxi(2, 1 + _spell_mod(c, ctx))
			z.uses = n
		if i > 0:
			z.hidden = true
		s.zones.append(z)
	log_line("  %s fills the area." % sp.name)

## Spells you keep using on later turns (Witch Bolt's action, Heat Metal's bonus action): remember the
## target on the caster's concentration, so the action is offered until the spell ends.
func _start_sustain(c: Dictionary, sp: Dictionary, cbd: Dictionary, ctx: Dictionary, tid: String) -> void:
	var su = cbd.get("sustain", null)
	if not su is Dictionary or tid == "" or c.conc.get("spell", "") != sp.id:
		return
	c.conc.sustain = {"spell": sp.id, "target": tid, "upl": int(ctx.upl), "dc": int(ctx.dc),
		"cast_serial": int(c.get("turn", {}).get("serial", -1))}

func _sustain_spell(c: Dictionary) -> void:
	var su: Dictionary = c.conc.get("sustain", {})
	var sp = Data.spell(su.get("spell", ""))
	var cbd: Dictionary = sp.get("combat", {}) if sp.get("combat", null) is Dictionary else {}
	var data: Dictionary = cbd.get("sustain", {})
	var t = C(su.get("target", ""))
	if sp.is_empty() or data.is_empty() or t.is_empty() or not alive(t):
		return
	if dist(c, t) > int(data.get("range", sp.get("range", 30))) or not los(c, t):
		log_line("%s is out of reach: %s ends." % [nm(t), sp.name])
		end_concentration(c, true)
		return
	log_line("%s sustains [b]%s[/b] on %s." % [nm(c), sp.name, nm(t)])
	var parts: Array = []
	var first = true
	for d in data.get("damage", []):
		var dice: String = d.dice
		if first and int(su.upl) > 0 and str(data.get("upcast", "")) != "":
			dice = Dice.add(dice, Dice.times(data.upcast, int(su.upl)))
		first = false
		parts.append({"amount": Dice.roll(dice).total, "type": d.type})
	fx("bolt", c.pos, t.pos, _dmg_color(data.get("damage", [{"type": "force"}])), [], _dmg_sfx(data.get("damage", [])))
	if not parts.is_empty():
		var lost: int = apply_damage(t, parts, c, {"spell": true, "spell_level": int(sp.level) + int(su.upl)})
		# Enervation: the caster regains half the necrotic damage dealt.
		if data.get("drain", false) and lost > 0:
			heal_creature(c, lost / 2, c, sp.name)
	if data.get("reapply_effect", false) and alive(t):
		_apply_spell_effect(c, sp, cbd, t, int(su.dc), {"upl": su.upl})

func _apply_spell_effect(c: Dictionary, sp: Dictionary, cbd: Dictionary, t: Dictionary, dc: int, ctx: Dictionary) -> void:
	var eff = cbd.get("effect", null)
	if not eff is Dictionary or eff.is_empty() or not alive(t):
		return
	var save_ab: String = str(cbd.get("save", ""))
	if save_ab == "" and cbd.get("effect_save", null) != null:
		save_ab = str(cbd.effect_save)
	var e = _make_effect(c, sp, eff, dc, save_ab)
	var upl: int = int(ctx.get("upl", 0))
	var slot: int = int(ctx.get("slot", int(sp.get("level", 0)) + upl))
	e.upl = upl
	if upl > 0:
		# Upcast smites hit harder (Searing Smite), and damage over time can scale too (Phantasmal Killer).
		# "upcast_every": the extra dice come every N slot levels (Spirit Shroud: 1d8 per two levels).
		var ex = e.mods.get("extra_damage", null)
		if ex is Dictionary and str(cbd.get("upcast_dice", "")) != "":
			var steps: int = upl / maxi(1, int(eff.get("upcast_every", 1)))
			if steps > 0:
				ex.dice = Dice.add(str(ex.dice), Dice.times(cbd.upcast_dice, steps))
		if e.has("tick_damage") and str(e.tick_damage.get("upcast", "")) != "":
			e.tick_damage.dice = Dice.add(str(e.tick_damage.dice), Dice.times(e.tick_damage.upcast, upl))
		# Numeric mods that grow per slot level (Ashardalon's Stride: +5 ft speed).
		for k in eff.get("mods_per_slot", {}):
			e.mods[k] = int(e.mods.get(k, 0)) + int(eff.mods_per_slot[k]) * upl
	# Stronger at set slot levels (Magic Weapon +2 at 4th, +3 at 6th; Elemental Weapon at 5th and 7th).
	for tier in eff.get("slot_tiers", []):
		if slot >= int(tier.get("slot", 99)):
			for k in tier.get("mods", {}):
				e.mods[k] = tier.mods[k].duplicate(true) if tier.mods[k] is Dictionary else tier.mods[k]
	# The caster picks the element (Protection from Energy, Elemental Weapon, Elemental Bane, Spirit Shroud).
	var dt_pick: String = str(ctx.get("opts", {}).get("dtype", ""))
	var choices: Array = cbd.get("choose_type", [])
	if dt_pick != "" and dt_pick in choices:
		if e.mods.get("extra_damage", null) is Dictionary:
			e.mods.extra_damage.type = dt_pick
		if e.mods.get("resist", null) is Array and e.mods.resist.size() == 1 and sp.get("id", "") != "fire_shield":
			e.mods.resist = [dt_pick]
		if e.mods.get("elemental_bane", null) is Dictionary:
			e.mods.elemental_bane.type = dt_pick
	# Fire Shield: the chill shield resists fire and lashes back with cold.
	if sp.get("id", "") == "fire_shield" and dt_pick == "cold":
		e.mods.resist = ["fire"]
		if e.has("retaliate"):
			e.retaliate.type = "cold"
		e.name = "Fire Shield (chill)"
	# "Until the end of its next turn" (Staggering Smite, Mind Whip): timed on the target's own turns.
	if eff.get("until_target_turn_end", false):
		e.tick_cid = t.id
		e.tick_on = "end"
		e.rounds = 2 if is_current(t) else 1
		e.outlived = true
	# A sealed-off space of the target's own (Maze, Resilient Sphere).
	if e.has("pocket"):
		e.pocket = "%s:%s" % [e.pocket, t.id]
	# Extra conditions that come with the effect (Hideous Laughter also knocks the target prone).
	for xc in eff.get("extra_conditions", []):
		var xe = _make_effect(c, sp, {"name": str(xc).capitalize(), "condition": xc}, dc, "")
		add_effect(t, xe)
	if e.has("breath"):
		# Dragon's Breath: the breath scales with the slot, and the caster picks the damage type.
		if upl > 0 and str(cbd.get("upcast_dice", "")) != "":
			e.breath.dice = Dice.add(str(e.breath.dice), Dice.times(cbd.upcast_dice, upl))
		var dt: String = str(ctx.get("opts", {}).get("dtype", ""))
		e.breath.type = dt if dt in ["acid", "cold", "fire", "lightning", "poison"] else str(e.breath.get("type", "fire"))
	add_effect(t, e)

func _starry_chalice(c: Dictionary, healed: Array) -> void:
	if not has_tag(c, "starry_chalice"):
		return
	var best = {}
	for o in allies_of(c):
		if dist(o, c) <= 30 and not o in healed and (best.is_empty() or float(o.hp) / o.max_hp < float(best.hp) / best.max_hp):
			best = o
	if not best.is_empty():
		heal_creature(best, Dice.roll("1d8+%d" % int(c.mods.wis)).total, c, "Starry Chalice")

# ---------------------------------------------------------------- special spell handlers (return true if fully handled)

## How many darts, rays or beams a spell action fires when cast with `slot` (0 for other spells).
## The caster aims each one: the chosen target list holds one entry per shot, repeats allowed.
func spell_shots(c: Dictionary, a: Dictionary, slot: int) -> int:
	var cb = Data.spell(a.get("spell", "")).get("combat", null)
	if not cb is Dictionary or cb.get("target", "") == "self":
		return 0
	var upl: int = maxi(0, slot - int(a.get("level", 0)))
	if int(cb.get("darts", 0)) > 0:
		return int(cb.darts) + int(cb.get("darts_per_slot", 1)) * upl
	if cb.get("beams_scale", false):
		var cl = int(c.get("cl", c.level))
		return 1 + (1 if cl >= 5 else 0) + (1 if cl >= 11 else 0) + (1 if cl >= 17 else 0)
	if cb.has("rays"):
		return int(cb.rays) + int(cb.get("rays_per_slot", 0)) * upl
	return 0

## Darts go to the chosen targets in order (one entry per dart, so picking a creature twice sends it two).
## If fewer targets were picked than there are darts, the list repeats.
func _sp_magic_missile(c: Dictionary, sp: Dictionary, cbd: Dictionary, targets: Array, ctx: Dictionary) -> bool:
	if targets.is_empty():
		return true
	var darts = int(cbd.get("darts", 3)) + int(cbd.get("darts_per_slot", 1)) * int(ctx.upl)
	for i in darts:
		var t: Dictionary = targets[i % targets.size()]
		if not alive(t):
			continue
		if has_tag(t, "shield"):
			log_line("  A dart fizzles against %s's Shield." % nm(t))
			continue
		if knows_spell(t, "shield") and can_react_spell(t) and lowest_slot(t, 1) > 0 and hostile(c, t):
			spend_slot(t, lowest_slot(t, 1))
			use_reaction(t)
			add_effect(t, {"name": "Shield", "tag": "shield", "src": t.id, "mods": {"ac": 5}, "rounds": 1, "tick_cid": t.id, "tick_on": "start"})
			log_line("  %s casts Shield, absorbing the darts!" % nm(t))
			continue
		fx("bolt", c.pos, t.pos, "#c8a0ff")
		apply_damage(t, [{"amount": Dice.roll("1d4+1").total, "type": "force"}], c, {"spell": true, "spell_level": ctx.slot})
	return true

func _sp_toll_the_dead(c: Dictionary, sp: Dictionary, cbd: Dictionary, targets: Array, ctx: Dictionary) -> bool:
	var cl = int(c.get("cl", c.level))
	var n = 1 + (1 if cl >= 5 else 0) + (1 if cl >= 11 else 0) + (1 if cl >= 17 else 0)
	for t in targets:
		var die = 12 if t.hp < t.max_hp else 8
		fx("burst", t.pos, t.pos, "#8a4ac0")
		var flat = int(c.mods.wis) if c.features.has("potent_spellcasting") and ctx.entry.get("class", "") == "cleric" else 0
		if not saving_throw(t, "wis", ctx.dc, c, {"spell": true}):
			apply_damage(t, [{"amount": Dice.roll("%dd%d+%d" % [n, die, flat]).total, "type": "necrotic"}], c, {"spell": true})
		elif c.features.has("potent_cantrip"):
			apply_damage(t, [{"amount": Dice.roll("%dd%d" % [n, die]).total / 2, "type": "necrotic"}], c, {"spell": true})
	return true

func _sp_sleep(c: Dictionary, sp: Dictionary, cbd: Dictionary, targets: Array, ctx: Dictionary) -> bool:
	var victims = _spell_targets_area(c, sp, cbd, ctx)
	var pool: int = Dice.roll(Dice.add("5d8", Dice.times("2d8", ctx.upl))).total
	log_line("  Sleep affects up to %d HP of creatures." % pool)
	victims.sort_custom(func(a, b): return a.hp < b.hp)
	for t in victims:
		if t.hp <= 0 or has_cond(t, "unconscious"):
			continue
		if t.type in ["undead", "construct"] or t.tags.has("fey_ancestry") or "charmed" in t.cond_immune:
			continue
		if t.hp > pool:
			break
		pool -= t.hp
		add_effect(t, {"name": "Magical Sleep", "cond": "unconscious", "src": c.id, "spell": "sleep", "rounds": 10, "tick_cid": c.id, "end_on_damage": true})
		log_line("  %s falls asleep." % nm(t))
	return true

func _sp_color_spray(c: Dictionary, sp: Dictionary, cbd: Dictionary, targets: Array, ctx: Dictionary) -> bool:
	var victims = _spell_targets_area(c, sp, cbd, ctx)
	var pool: int = Dice.roll(Dice.add("6d10", Dice.times("2d10", ctx.upl))).total
	victims.sort_custom(func(a, b): return a.hp < b.hp)
	for t in victims:
		if t.hp > pool or has_cond(t, "blinded") or t.hp <= 0:
			continue
		pool -= t.hp
		add_effect(t, {"name": "Dazzled", "cond": "blinded", "src": c.id, "spell": "color_spray", "rounds": 2, "tick_cid": c.id, "tick_on": "end"})
	return true

func _sp_eldritch_blast(c: Dictionary, sp: Dictionary, cbd: Dictionary, targets: Array, ctx: Dictionary) -> bool:
	return false  # generic path handles beams, agonizing and repelling blast

func _sp_chromatic_orb(c: Dictionary, sp: Dictionary, cbd: Dictionary, targets: Array, ctx: Dictionary) -> bool:
	return false  # generic path honours opts.dtype

func _sp_misty_step(c: Dictionary, sp: Dictionary, cbd: Dictionary, targets: Array, ctx: Dictionary) -> bool:
	if not teleport(c, ctx.cell):
		log_line("  The destination is blocked.")
	else:
		log_line("  %s vanishes in silvery mist and reappears." % nm(c))
	return true

func _sp_dimension_door(c: Dictionary, sp: Dictionary, cbd: Dictionary, targets: Array, ctx: Dictionary) -> bool:
	return _sp_misty_step(c, sp, cbd, targets, ctx)

func _sp_thunder_step(c: Dictionary, sp: Dictionary, cbd: Dictionary, targets: Array, ctx: Dictionary) -> bool:
	var origin: Vector2i = c.pos
	var victims: Array = []
	for o in all_combatants():
		if alive(o) and o.id != c.id and dist(c, o) <= 10:
			victims.append(o)
	if not teleport(c, ctx.cell):
		log_line("  The destination is blocked.")
		return true
	fx("area", origin, origin, "#7aa8ff", area_cells({"pos": origin, "size": 1, "form": {}}, {"shape": "emanation", "size": 10}, origin, true))
	var dice = Dice.add("3d10", Dice.times("1d10", ctx.upl))
	for t in victims:
		var ok = saving_throw(t, "con", ctx.dc, c, {"spell": true})
		var amt: int = Dice.roll(dice).total
		apply_damage(t, [{"amount": amt / 2 if ok else amt, "type": "thunder"}], c, {"spell": true})
	return true

func _sp_thunderwave(c: Dictionary, sp: Dictionary, cbd: Dictionary, targets: Array, ctx: Dictionary) -> bool:
	var victims = _spell_targets_area(c, sp, cbd, ctx)
	var dice = Dice.add("2d8", Dice.times("1d8", ctx.upl))
	for t in victims:
		var ok = saving_throw(t, "con", ctx.dc, c, {"spell": true})
		var amt: int = Dice.roll(dice).total
		apply_damage(t, [{"amount": amt / 2 if ok else amt, "type": "thunder"}], c, {"spell": true})
		if not ok and alive(t):  # 2014 Thunderwave pushes creatures of any size
			push_creature(t, center_of(c), 10)
	return true

func _blade_cantrip(c: Dictionary, targets: Array, ctx: Dictionary, kind: String) -> bool:
	if targets.is_empty():
		return true
	var t: Dictionary = targets[0]
	var atk = best_melee(c)
	if atk.is_empty() or dist(c, t) > int(atk.get("reach", 5)):
		log_line("  You need a melee weapon and a target within reach.")
		return true
	var cl = int(c.get("cl", c.level))
	var tier = (1 if cl >= 5 else 0) + (1 if cl >= 11 else 0) + (1 if cl >= 17 else 0)
	var r = roll_attack(c, t, atk, {"melee": true})
	t = r.get("target", t)
	if not r.hit:
		return true
	var parts = weapon_damage(c, t, atk, r, {})
	if kind == "booming" and tier > 0:
		parts.append({"amount": Dice.roll("%dd8" % tier, {"crit": r.crit}).total, "type": "thunder"})
	if kind == "green" and tier > 0:
		parts.append({"amount": Dice.roll("%dd8" % tier, {"crit": r.crit}).total, "type": "fire"})
	apply_damage(t, parts, c, {"attack": true, "melee": true, "magic": atk.get("magic", false), "crit": r.crit})
	if kind == "booming" and alive(t):
		add_effect(t, {"name": "Booming Blade", "tag": "booming_blade", "src": c.id, "dice": "%dd8" % (tier + 1), "rounds": 1, "tick_cid": c.id, "tick_on": "start"})
	if kind == "green":
		for o in enemies_of(c):
			if o.id != t.id and dist(o, t) <= 5 and dist(c, o) <= 5 + 30:
				var dmg: int = int(ctx.entry.get("mod", 0)) + (Dice.roll("%dd8" % tier).total if tier > 0 else 0)
				fx("bolt", t.pos, o.pos, "#7aff7a", [], "fire")
				apply_damage(o, [{"amount": maxi(0, dmg), "type": "fire"}], c, {"spell": true})
				break
	return true

func _sp_booming_blade(c: Dictionary, sp: Dictionary, cbd: Dictionary, targets: Array, ctx: Dictionary) -> bool:
	return _blade_cantrip(c, targets, ctx, "booming")

func _sp_green_flame_blade(c: Dictionary, sp: Dictionary, cbd: Dictionary, targets: Array, ctx: Dictionary) -> bool:
	return _blade_cantrip(c, targets, ctx, "green")

func _sp_hunters_mark(c: Dictionary, sp: Dictionary, cbd: Dictionary, targets: Array, ctx: Dictionary) -> bool:
	for t in targets:
		var e = _make_effect(c, sp, cbd.get("effect", {"name": sp.name}), ctx.dc, "")
		e.tag = sp.id
		add_effect(t, e)
		log_line("  %s is marked." % nm(t))
	return true

func _sp_hex(c: Dictionary, sp: Dictionary, cbd: Dictionary, targets: Array, ctx: Dictionary) -> bool:
	return _sp_hunters_mark(c, sp, cbd, targets, ctx)

func _sp_spiritual_weapon(c: Dictionary, sp: Dictionary, cbd: Dictionary, targets: Array, ctx: Dictionary) -> bool:
	var dice = Dice.add("1d8+%d" % _spell_mod(c, ctx), Dice.times("1d8", int(ctx.upl) / 2))
	add_effect(c, {"name": "Spiritual Weapon", "tag": "spiritual_weapon", "src": c.id, "spell": sp.id, "attack": ctx.attack, "dice": dice, "rounds": 10, "tick_cid": c.id, "tick_on": "start"})
	if not targets.is_empty():
		var t: Dictionary = targets[0]
		var atk = {"to_hit": ctx.attack, "melee": true, "reach": 60, "damage": [{"dice": dice, "type": "force"}], "magic": true, "spell_attack": true}
		fx("slash", c.pos, t.pos, "#fff2a8")
		var r = roll_attack(c, t, atk, {"melee": true, "spell": true})
		t = r.get("target", t)
		if r.hit:
			apply_damage(t, [{"amount": Dice.roll(dice, {"crit": r.crit}).total, "type": "force"}], c, {"spell": true, "attack": true, "crit": r.crit})
	return true

func _sp_vampiric_touch(c: Dictionary, sp: Dictionary, cbd: Dictionary, targets: Array, ctx: Dictionary) -> bool:
	var dice = Dice.add("3d6", Dice.times("1d6", ctx.upl))
	add_effect(c, {"name": "Vampiric Touch", "tag": "vampiric_touch", "src": c.id, "spell": sp.id, "conc": true, "attack": ctx.attack, "dice": dice, "rounds": 10, "tick_cid": c.id, "tick_on": "start"})
	if not targets.is_empty():
		_attack_with(c, targets[0], {"to_hit": ctx.attack, "melee": true, "reach": 5, "damage": [{"dice": dice, "type": "necrotic"}], "magic": true, "spell_attack": true, "drain": true})
	return true

## The caster holds three stones (a "magic_stone" effect with "uses"). Anyone holding one can throw it;
## stones can be dropped, picked up and passed around (see _stone_actions). Whoever throws it, the attack
## uses the caster's spell attack bonus and spellcasting modifier, which are stored with the stone.
## Casting it again ends the spell on any stones still enchanted from before.
func _sp_magic_stone(c: Dictionary, sp: Dictionary, cbd: Dictionary, targets: Array, ctx: Dictionary) -> bool:
	_end_magic_stones(c.id)
	add_effect(c, {"name": "Magic Stones", "tag": "magic_stone", "src": c.id, "spell": sp.id, "attack": ctx.attack, "dice": "1d6+%d" % _spell_mod(c, ctx), "uses": 3, "rounds": 10, "tick_cid": c.id, "tick_on": "start"})
	log_line("  Three pebbles glow with power.")
	return true

## Stones from `src_id`'s casting still enchanted: carried by anyone or lying on the ground.
func magic_stones_in_play(src_id: String) -> int:
	var n = 0
	for o in all_combatants():
		for e in o.effects:
			if e.get("tag", "") == "magic_stone" and e.get("src", "") == src_id:
				n += int(e.get("uses", 0))
	for it in ground_items():
		if it.get("kind", "") == "magic_stone" and it.get("src", "") == src_id:
			n += 1
	return n

## The magic-stone effect `c` carries with this eid (or its first one), or {}.
func _held_stone(c: Dictionary, eid: String) -> Dictionary:
	var first = {}
	for e in c.effects:
		if e.get("tag", "") != "magic_stone":
			continue
		if e.get("eid", "") == eid:
			return e
		if first.is_empty():
			first = e
	return first

## `c` takes hold of one stone described by `stone` (a ground item or another holder's effect): it joins
## the stones `c` already carries from the same casting, keeping the caster's attack numbers and timer.
func _take_stone(c: Dictionary, stone: Dictionary) -> void:
	var src: String = str(stone.get("src", ""))
	for e in c.effects:
		if e.get("tag", "") == "magic_stone" and e.get("src", "") == src:
			e.uses = int(e.uses) + 1
			e.rounds = maxi(int(e.get("rounds", 1)), int(stone.get("rounds", 1)))
			return
	add_effect(c, {"name": "Magic Stones", "tag": "magic_stone", "src": src, "spell": stone.get("spell", "magic_stone"),
		"attack": int(stone.attack), "dice": str(stone.dice), "uses": 1, "rounds": int(stone.get("rounds", 10)), "tick_cid": src, "tick_on": "start"})

func _end_magic_stones(src_id: String) -> void:
	var n: int = magic_stones_in_play(src_id)
	if n > 0:
		log_line("  The %d stone%s from the earlier casting lose%s their magic." % [n, "" if n == 1 else "s", "s" if n == 1 else ""])
	for o in all_combatants():
		remove_effects_where(o, func(e): return e.get("tag", "") == "magic_stone" and e.get("src", "") == src_id)
	s.items = ground_items().filter(func(it): return not (it.get("kind", "") == "magic_stone" and it.get("src", "") == src_id))

## Animate Objects: ten units of objects (+2 per slot level above 5th) come to life around the chosen point.
## Tiny and Small count as one unit, Medium two, Large four, Huge eight; ctx.opts.obj_size picks the size.
## They share the caster's initiative (acting right after it) and fall lifeless when concentration ends.
func _sp_animate_objects(c: Dictionary, sp: Dictionary, cbd: Dictionary, targets: Array, ctx: Dictionary) -> bool:
	var size: String = str(ctx.opts.get("obj_size", "tiny"))
	if not CombatantFactory.ANIMATED_OBJECTS.has(size):
		size = "tiny"
	var count: int = animated_object_count(size, int(ctx.upl))
	if count <= 0:
		log_line("  Not enough objects of that size can be animated.")
		end_concentration(c, true)
		return true
	var made: Array = []
	var at: Vector2i = ctx.cell
	for i in count:
		var o = CombatantFactory.animated_object(new_id("s"), c, size, i + 1)
		var spot = _free_spot_near(at, int(o.sz))
		if spot.x < 0:
			break
		o.pos = spot
		o.conc_summon = c.id + ":" + sp.id
		o.init = int(c.get("init", 0))
		s.combatants[o.id] = o
		made.append(o)
	_join_after_caster(c, made)
	# The spell lasts up to a minute: this marker counts it down and takes the objects with it.
	add_effect(c, {"name": "Animate Objects", "tag": "animate_objects", "src": c.id, "spell": sp.id, "conc": true, "rounds": 10, "tick_cid": c.id, "tick_on": "start"})
	fx("burst", at, at, "#d8b070", [], "buff")
	log_line("  %d %s object%s spring%s to life." % [made.size(), size, "" if made.size() == 1 else "s", "s" if made.size() == 1 else ""])
	return true

## Summons made mid-fight take their turns right after the caster's own entry and any companions
## already following it (they share the caster's initiative).
func _join_after_caster(c: Dictionary, made: Array) -> void:
	if not s.in_combat:
		return
	var idx: int = s.order.find(c.id)
	var ins: int = (idx if idx >= 0 else int(s.turn)) + 1
	while ins < s.order.size() and C(s.order[ins]).get("summoner", "") == c.id:
		ins += 1
	for o in made:
		o.turn = new_turn(o)
		s.order.insert(ins, o.id)
		ins += 1

## Tiny Servant (XGtE, 3rd level, 1 minute casting time, touch, 8 hours, no concentration): one Tiny object
## per casting plus two for each slot level above 3rd. The casting time keeps it out of combat; servants made
## beforehand join the fight right after their caster. Each casting's servants revert to objects when its
## 8 hours run out (a marker effect on the caster) or when they drop to 0 HP. Casting it again doesn't end
## earlier servants. The caster commands them (bonus action in the rules); here the owner plays their turns.
func _sp_tiny_servant(c: Dictionary, sp: Dictionary, cbd: Dictionary, targets: Array, ctx: Dictionary) -> bool:
	var count: int = tiny_servant_count(int(ctx.upl))
	var group: String = new_id("g")
	var made: Array = []
	var n0: int = 0
	for o in all_combatants():
		if o.get("servant", false) and o.get("summoner", "") == c.id:
			n0 += 1
	var at: Vector2i = ctx.cell
	for i in count:
		var o = CombatantFactory.tiny_servant(new_id("s"), c, n0 + i + 1)
		var spot = _free_spot_near(at, 1)
		if spot.x < 0:
			break
		o.pos = spot
		o.summon_group = group
		o.init = int(c.get("init", 0))
		s.combatants[o.id] = o
		made.append(o)
	_join_after_caster(c, made)
	# One marker per casting, named after its servants (add_effect would merge same-named markers).
	var label: String = "Tiny Servant %d" % (n0 + 1) if made.size() <= 1 else "Tiny Servants %d-%d" % [n0 + 1, n0 + made.size()]
	add_effect(c, {"name": label, "tag": "tiny_servant", "src": c.id, "spell": sp.id, "summon_group": group,
		"rounds": int(sp.get("duration_rounds", 4800)), "tick_cid": c.id, "tick_on": "start"})
	fx("burst", at, at, "#d8b070", [], "buff")
	log_line("  %d tiny object%s sprout%s little legs and stand%s ready to serve." % [made.size(), "" if made.size() == 1 else "s", "s" if made.size() == 1 else "", "s" if made.size() == 1 else ""])
	return true

func tiny_servant_count(upl: int) -> int:
	return 1 + 2 * maxi(0, upl)

func animated_object_count(size: String, upl: int) -> int:
	var st: Dictionary = CombatantFactory.ANIMATED_OBJECTS.get(size, {"units": 1})
	return (10 + 2 * maxi(0, upl)) / int(st.units)

## The nearest cell to `p` (p itself first) where a creature `sz` cells wide fits; (-1, -1) if none within 6 cells.
func _free_spot_near(p: Vector2i, sz: int) -> Vector2i:
	for r in range(0, 7):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var q = p + Vector2i(dx, dy)
				var ok = true
				for ox in sz:
					for oy in sz:
						var w = q + Vector2i(ox, oy)
						if not in_bounds(w) or blocks_move(w) or not creature_at(w).is_empty():
							ok = false
				if ok:
					return q
	return Vector2i(-1, -1)

func _sp_mage_armor(c: Dictionary, sp: Dictionary, cbd: Dictionary, targets: Array, ctx: Dictionary) -> bool:
	for t in (targets if not targets.is_empty() else [c]):
		if t.get("armored", false):
			log_line("  Mage Armor has no effect on armored creatures.")
			continue
		add_effect(t, {"name": "Mage Armor", "tag": "mage_armor", "src": c.id, "spell": sp.id, "mods": {"set_ac": 13 + int(t.mods.dex)}, "rounds": 4800, "tick_cid": c.id})
	return true

func _sp_shield(c: Dictionary, sp: Dictionary, cbd: Dictionary, targets: Array, ctx: Dictionary) -> bool:
	add_effect(c, {"name": "Shield", "tag": "shield", "src": c.id, "mods": {"ac": 5}, "rounds": 1, "tick_cid": c.id, "tick_on": "start"})
	return true

func _sp_armor_of_agathys(c: Dictionary, sp: Dictionary, cbd: Dictionary, targets: Array, ctx: Dictionary) -> bool:
	var v = 5 * maxi(1, int(ctx.slot))
	grant_temp_hp(c, v, sp.name)
	add_effect(c, {"name": "Armor of Agathys", "tag": "armor_of_agathys", "src": c.id, "value": v, "rounds": 600, "tick_cid": c.id})
	return true

func _sp_heroism(c: Dictionary, sp: Dictionary, cbd: Dictionary, targets: Array, ctx: Dictionary) -> bool:
	for t in targets:
		add_effect(t, {"name": "Heroism", "tag": "heroism", "src": c.id, "spell": sp.id, "conc": true, "value": maxi(1, _spell_mod(c, ctx)), "rounds": 10, "tick_cid": c.id})
		grant_temp_hp(t, maxi(1, _spell_mod(c, ctx)), "Heroism")
	return true

func _sp_mirror_image(c: Dictionary, sp: Dictionary, cbd: Dictionary, targets: Array, ctx: Dictionary) -> bool:
	add_effect(c, {"name": "Mirror Image", "tag": "mirror_image", "src": c.id, "images": 3, "rounds": 10, "tick_cid": c.id})
	return true

func _sp_blur(c: Dictionary, sp: Dictionary, cbd: Dictionary, targets: Array, ctx: Dictionary) -> bool:
	add_effect(c, {"name": "Blur", "src": c.id, "spell": sp.id, "conc": true, "mods": {"grants_disadvantage": true}, "rounds": 10, "tick_cid": c.id})
	return true

func _sp_invisibility(c: Dictionary, sp: Dictionary, cbd: Dictionary, targets: Array, ctx: Dictionary) -> bool:
	for t in (targets if not targets.is_empty() else [c]):
		add_effect(t, {"name": "Invisible", "cond": "invisible", "breaks": true, "src": c.id, "spell": sp.id, "conc": true, "rounds": 600, "tick_cid": c.id})
	return true

func _sp_greater_invisibility(c: Dictionary, sp: Dictionary, cbd: Dictionary, targets: Array, ctx: Dictionary) -> bool:
	for t in (targets if not targets.is_empty() else [c]):
		add_effect(t, {"name": "Greater Invisibility", "cond": "invisible", "src": c.id, "spell": sp.id, "conc": true, "rounds": 10, "tick_cid": c.id})
	return true

func _sp_haste(c: Dictionary, sp: Dictionary, cbd: Dictionary, targets: Array, ctx: Dictionary) -> bool:
	for t in targets:
		add_effect(t, {"name": "Hasted", "tag": "haste", "src": c.id, "spell": sp.id, "conc": true, "mods": {"ac": 2, "speed_mult": 2}, "rounds": 10, "tick_cid": c.id})
	return true

func _sp_slow(c: Dictionary, sp: Dictionary, cbd: Dictionary, targets: Array, ctx: Dictionary) -> bool:
	var victims = targets
	if not cbd.get("area", {}).is_empty():
		victims = _spell_targets_area(c, sp, cbd, ctx).filter(func(o): return hostile(c, o)).slice(0, 6)
	for t in victims:
		if not saving_throw(t, "wis", ctx.dc, c, {"spell": true}):
			add_effect(t, {"name": "Slowed", "src": c.id, "spell": sp.id, "conc": true, "mods": {"ac": -2, "speed_mult": 0.5, "no_reactions": true}, "save_ends": {"ability": "wis", "dc": ctx.dc}, "rounds": 10, "tick_cid": c.id})
	return true

func _sp_banishment(c: Dictionary, sp: Dictionary, cbd: Dictionary, targets: Array, ctx: Dictionary) -> bool:
	for t in targets:
		if not saving_throw(t, "cha", ctx.dc, c, {"spell": true}):
			add_effect(t, {"name": "Banished", "cond": "banished", "src": c.id, "spell": sp.id, "conc": true, "rounds": 10, "tick_cid": c.id})
			log_line("  %s vanishes to another plane!" % nm(t))
	return true

## Rope Trick (PHB): a rope rises from the caster's cell to an invisible entrance that stays open
## for the hour the spell lasts (it outlasts the fight). How it plays here:
## - The caster's side climbs in from within 5 ft of the rope: 10 ft of movement (5 ft of rope at
##   climbing cost), or 5 ft for a creature with a climbing or flying speed. Leaving a foe's reach
##   that way provokes opportunity attacks. Up to eight creatures, Medium or smaller, fit.
## - Leaving is a drop to the ground under the rope and costs no movement.
## - Attacks and spells can't cross the entrance either way, and nothing outside can see in, so
##   those inside can't be seen, targeted or caught in areas, and have to drop out to attack or
##   cast at the world. Those inside pull the rope up after them, so foes can't follow.
## - Everything inside drops out when the spell ends. A caster keeps one rope at a time.
const ROPE_CAPACITY := 8
## A cell far off the map: "from" or "to" for a move that starts or ends in a Rope Trick space.
const NOWHERE := Vector2i(-9999, -9999)

func _sp_rope_trick(c: Dictionary, sp: Dictionary, cbd: Dictionary, targets: Array, ctx: Dictionary) -> bool:
	end_rope(c.id)
	ropes().append({"id": new_id("r"), "src": c.id, "team": c.team, "pos": c.pos, "rounds": int(sp.get("duration_rounds", 600)), "name": sp.name})
	log_line("  A rope rises to an invisible extradimensional space. The way in stays open: allies within 5 ft can climb up, and drop back out.")
	return true

## Feet of movement it costs `c` to go up the rope.
func rope_climb_cost(c: Dictionary) -> int:
	var easy: bool = ((int(c.get("climb", 0)) > 0 or int(c.get("fly", 0)) > 0) and c.form.is_empty()) or mod_sum(c, "fly") > 0
	return (5 if easy and not mod_any(c, "no_fly") else 10) + (5 if _crawling(c) else 0)

## The nearest open Rope Trick that would let `c` in (one cast by its own side), or {}.
func rope_for(c: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	for r in ropes():
		if str(r.get("team", "")) != str(c.get("team", "")):
			continue
		if best.is_empty() or dist_to_cell(c, r.pos) < dist_to_cell(c, best.pos):
			best = r
	return best

## Why `c` can't climb rope `r` right now ("" if it can).
func rope_block_reason(c: Dictionary, r: Dictionary) -> String:
	if r.is_empty():
		return "No rope to climb"
	if dist_to_cell(c, r.pos) > 5:
		return "Move within 5 ft of the rope first"
	if size_rank(c) > SIZE_RANK.medium:
		return "Too big for the space"
	if rope_occupants(str(r.src)).size() >= ROPE_CAPACITY:
		return "The space is full (%d creatures)" % ROPE_CAPACITY
	if s.in_combat and move_budget(c) < rope_climb_cost(c):
		return "Not enough movement (needs %d ft)" % rope_climb_cost(c) if eff_speed(c) > 0 else "Your speed is 0"
	return ""

## `c` climbs rope `r` into the space above it. Returns false if it couldn't (or was stopped on the way).
func enter_rope(c: Dictionary, r: Dictionary) -> bool:
	if in_rope(c) or rope_block_reason(c, r) != "":
		return false
	var from: Vector2i = c.pos
	if s.in_combat:
		if has_cond(c, "prone") and c.hp > 0 and can_stand(c):
			stand_up(c)
		# Going up the rope takes the creature out of every reach around it.
		_opportunity_attacks(c, from, NOWHERE)
		var cost: int = rope_climb_cost(c)
		if not alive(c) or c.hp <= 0 or move_left(c) < cost:
			sync_move(c)
			return false
		c.turn.moved = int(c.turn.get("moved", 0)) + cost
	c.pos = r.pos
	c.hidden = false
	add_effect(c, {"name": "Rope Trick", "tag": "rope_trick", "src": str(r.src), "spell": "rope_trick", "rounds": 9999, "tick_cid": "none"})
	events.append({"t": "move", "cid": c.id, "path": [from, r.pos]})
	log_line("%s climbs the rope into the Rope Trick space." % nm(c))
	release_broken_grapples()
	sync_move(c)
	return true

## Where `c` lands when it leaves its Rope Trick space: under the rope, or the nearest free spot.
func rope_landing(c: Dictionary) -> Vector2i:
	var r: Dictionary = rope_of(rope_space(c))
	var under: Vector2i = r.pos if not r.is_empty() else c.pos
	var spot: Vector2i = _free_spot_near(under, int(sqrt(occupied_cells(c).size())))
	return spot if spot.x >= 0 else under

## `c` drops out of its Rope Trick space to the ground. Returns false if it wasn't in one.
func exit_rope(c: Dictionary, quiet := false) -> bool:
	if not in_rope(c):
		return false
	var land: Vector2i = rope_landing(c)
	remove_effects_where(c, func(e): return e.get("tag", "") == "rope_trick")
	c.pos = land
	events.append({"t": "move", "cid": c.id, "path": [land]})
	if not quiet:
		log_line("%s drops down out of the Rope Trick space." % nm(c))
	# Whatever fills the landing spot (Moonbeam, Spirit Guardians...) catches it as it arrives.
	if s.in_combat and alive(c):
		_zone_enter(c, NOWHERE, land)
	sync_move(c)
	return true

## The Rope Trick cast by `src_id` ends: everything inside drops out.
func end_rope(src_id: String) -> void:
	var r: Dictionary = rope_of(src_id)
	if r.is_empty():
		return
	log_line("%s's Rope Trick ends." % nm(C(src_id)) if not C(src_id).is_empty() else "A Rope Trick ends.")
	for o in rope_occupants(src_id):
		exit_rope(o, true)
		log_line("  %s drops out of the vanishing space." % nm(o))
	ropes().erase(r)

## Count down the Rope Trick `cid` cast (on its turns, like its zones).
func _tick_ropes(cid: String) -> void:
	var r: Dictionary = rope_of(cid)
	if r.is_empty():
		return
	r.rounds = int(r.get("rounds", 1)) - 1
	if int(r.rounds) <= 0:
		end_rope(cid)

func _sp_hold_person(c: Dictionary, sp: Dictionary, cbd: Dictionary, targets: Array, ctx: Dictionary) -> bool:
	for t in targets:
		if sp.id == "hold_person" and t.type != "humanoid":
			log_line("  %s is not humanoid and is unaffected." % nm(t))
			continue
		if not saving_throw(t, "wis", ctx.dc, c, {"spell": true, "heightened": ctx.meta == "heightened"}):
			add_effect(t, {"name": "Held", "cond": "paralyzed", "src": c.id, "spell": sp.id, "conc": true, "save_ends": {"ability": "wis", "dc": ctx.dc}, "rounds": 10, "tick_cid": c.id})
	return true

func _sp_hold_monster(c: Dictionary, sp: Dictionary, cbd: Dictionary, targets: Array, ctx: Dictionary) -> bool:
	return _sp_hold_person(c, sp, cbd, targets, ctx)

func _sp_polymorph(c: Dictionary, sp: Dictionary, cbd: Dictionary, targets: Array, ctx: Dictionary) -> bool:
	for t in targets:
		if hostile(c, t):
			if t.kind == "summon" or saving_throw(t, "wis", ctx.dc, c, {"spell": true}):
				continue
			var form = CombatantFactory.wild_shape_form("cat" if Data.monsters.has("cat") else "giant_rat")
			t.form = form
			add_effect(t, {"name": "Polymorphed", "tag": "wild_shape", "form_effect": true, "src": c.id, "spell": sp.id, "conc": true, "rounds": 600, "tick_cid": c.id})
			log_line("  %s is turned into a %s!" % [nm(t), form.name])
		else:
			var best = ""
			var best_cr = -1.0
			for m in Data.monsters.values():
				if m.get("type", "") == "beast" and float(m.cr) <= float(t.level) and float(m.cr) > best_cr:
					best_cr = float(m.cr)
					best = m.id
			if best != "":
				t.form = CombatantFactory.wild_shape_form(best)
				add_effect(t, {"name": "Polymorphed", "tag": "wild_shape", "form_effect": true, "src": c.id, "spell": sp.id, "conc": true, "rounds": 600, "tick_cid": c.id})
				log_line("  %s becomes a %s!" % [nm(t), t.form.name])
	return true

func _sp_power_word_kill(c: Dictionary, sp: Dictionary, cbd: Dictionary, targets: Array, ctx: Dictionary) -> bool:
	for t in targets:
		if t.hp <= 100:
			apply_damage(t, [{"amount": t.hp + t.temp_hp + (t.max_hp if t.kind == "pc" else 0), "type": "psychic"}], c, {"spell": true})
		else:
			log_line("  %s has too much vitality (%d HP)." % [nm(t), t.hp])
	return true

func _sp_power_word_stun(c: Dictionary, sp: Dictionary, cbd: Dictionary, targets: Array, ctx: Dictionary) -> bool:
	for t in targets:
		if t.hp <= 150:
			add_effect(t, {"name": "Stunned", "cond": "stunned", "src": c.id, "spell": sp.id, "save_ends": {"ability": "con", "dc": ctx.dc}, "rounds": 100, "tick_cid": c.id})
	return true

## Command: the caster picks the word (opts.command: approach, drop, flee, grovel or halt). Each target
## that fails its WIS save obeys on its next turn (see _obey_command). Undead are unaffected.
func _sp_command(c: Dictionary, sp: Dictionary, cbd: Dictionary, targets: Array, ctx: Dictionary) -> bool:
	var word: String = str(ctx.opts.get("command", ""))
	if not word in COMMAND_WORDS:
		word = command_word_for(c, targets[0] if not targets.is_empty() else {})
	log_line("  \"%s!\"" % word.capitalize())
	for t in targets:
		if not alive(t):
			continue
		fx("bolt", c.pos, t.pos, "#c8a0ff", [], "psychic")
		if str(t.get("type", "")) == "undead":
			log_line("  %s is undead and ignores the command." % nm(t))
			continue
		if saving_throw(t, "wis", int(ctx.dc), c, {"spell": true, "heightened": ctx.meta == "heightened" and t == targets[0]}):
			continue
		add_effect(t, {"name": "Commanded (%s)" % word.capitalize(), "tag": "commanded", "command": word, "src": c.id,
			"spell": "command", "rounds": 1, "tick_cid": t.id, "tick_on": "end"})
		log_line("  %s must %s on its next turn." % [nm(t), word])
	return true

## The word the AI (or a caster who didn't pick one) gives: grovel when an ally of the caster is
## next to the target to take advantage of it lying prone, otherwise halt.
func command_word_for(c: Dictionary, t: Dictionary) -> String:
	if not t.is_empty():
		for o in allies_of(c):
			if conscious(o) and dist(o, t) <= 5:
				return "grovel"
	return "halt"

func _sp_revivify(c: Dictionary, sp: Dictionary, cbd: Dictionary, targets: Array, ctx: Dictionary) -> bool:
	for t in targets:
		if revivable(t):
			t.death = {"s": 0, "f": 0, "stable": false, "dead": false}
			t.hp = 1
			log_line("  %s returns to life!" % nm(t))
	return true

func _sp_spare_the_dying(c: Dictionary, sp: Dictionary, cbd: Dictionary, targets: Array, ctx: Dictionary) -> bool:
	for t in targets:
		if t.hp <= 0 and not t.death.dead:
			t.death.stable = true
			log_line("  %s is stabilized." % nm(t))
	return true

func _sp_ray_of_frost(c: Dictionary, sp: Dictionary, cbd: Dictionary, targets: Array, ctx: Dictionary) -> bool:
	var e: Dictionary = cbd.duplicate(true)
	e.effect = {"name": "Chilled", "mods": {"speed": -10}, "duration_rounds": 1}
	_generic_spell(c, sp, e, targets, ctx)
	return true

func _sp_chill_touch(c: Dictionary, sp: Dictionary, cbd: Dictionary, targets: Array, ctx: Dictionary) -> bool:
	var e: Dictionary = cbd.duplicate(true)
	e.effect = {"name": "Chill Touch", "mods": {"no_heal": true}, "duration_rounds": 1}
	_generic_spell(c, sp, e, targets, ctx)
	return true

func _sp_shocking_grasp(c: Dictionary, sp: Dictionary, cbd: Dictionary, targets: Array, ctx: Dictionary) -> bool:
	var e: Dictionary = cbd.duplicate(true)
	e.effect = {"name": "Shocked", "mods": {"no_reactions": true}, "duration_rounds": 1}
	_generic_spell(c, sp, e, targets, ctx)
	return true

func _sp_true_strike(c: Dictionary, sp: Dictionary, cbd: Dictionary, targets: Array, ctx: Dictionary) -> bool:
	for t in targets:
		# Advantage on your first attack against it on your NEXT turn: survives the end of this turn.
		add_effect(t, {"name": "True Strike", "tag": "true_strike", "src": c.id, "spell": sp.id, "conc": true, "rounds": 2, "tick_cid": c.id, "tick_on": "end"})
	return true

func _sp_resistance(c: Dictionary, sp: Dictionary, cbd: Dictionary, targets: Array, ctx: Dictionary) -> bool:
	for t in (targets if not targets.is_empty() else [c]):
		add_effect(t, {"name": "Resistance", "src": c.id, "spell": sp.id, "conc": true, "one_save": true, "mods": {"save_dice": "1d4"}, "rounds": 10, "tick_cid": c.id})
	return true

func _sp_guidance(c: Dictionary, sp: Dictionary, cbd: Dictionary, targets: Array, ctx: Dictionary) -> bool:
	log_line("  Guidance helps with ability checks (resolve at the table).")
	return true

func _sp_blade_ward(c: Dictionary, sp: Dictionary, cbd: Dictionary, targets: Array, ctx: Dictionary) -> bool:
	add_effect(c, {"name": "Blade Ward", "src": c.id, "mods": {"resist": ["bludgeoning", "piercing", "slashing"]}, "rounds": 1, "tick_cid": c.id})
	return true

func _sp_shillelagh(c: Dictionary, sp: Dictionary, cbd: Dictionary, targets: Array, ctx: Dictionary) -> bool:
	add_effect(c, {"name": "Shillelagh", "tag": "shillelagh", "src": c.id, "rounds": 10, "tick_cid": c.id})
	return true

func _sp_faerie_fire(c: Dictionary, sp: Dictionary, cbd: Dictionary, targets: Array, ctx: Dictionary) -> bool:
	return false

func _sp_healing_word_mass(c: Dictionary, sp: Dictionary, cbd: Dictionary, targets: Array, ctx: Dictionary) -> bool:
	return false

## Dispel Magic: spells on the target of the slot's level or lower end; each stronger one needs a
## spellcasting ability check against DC 10 + its level. On an ally only spells from hostile casters
## are dispelled (the caster picks which magic to end); on anyone else, every spell on it.
func _sp_dispel_magic(c: Dictionary, sp: Dictionary, cbd: Dictionary, targets: Array, ctx: Dictionary) -> bool:
	var auto_lv: int = int(ctx.slot)
	for t in targets:
		var ended = 0
		var friendly: bool = not hostile(c, t)
		for e in t.effects.duplicate():
			var sid: String = str(e.get("spell", ""))
			if sid == "" or not e in t.effects:
				continue
			var esp = Data.spell(sid)
			if esp.is_empty() or int(esp.get("level", 0)) <= 0:
				continue
			var esrc = C(str(e.get("src", "")))
			if friendly and (esrc.is_empty() or not hostile(c, esrc)):
				continue
			var lv: int = int(esp.level) + int(e.get("upl", 0))
			if lv > auto_lv:
				var bonus: int = int(ctx.entry.get("mod", 0)) + (int(c.prof) if c.features.has("improved_abjuration") else 0)
				var roll: int = Dice.d20() + bonus
				if roll < 10 + lv:
					log_line("  %s holds against the dispel (check %d vs DC %d)." % [esp.name, roll, 10 + lv])
					continue
				log_line("  Check %d vs DC %d: %s unravels." % [roll, 10 + lv, esp.name])
			t.effects.erase(e)
			ended += 1
			log_line("  %s on %s is dispelled." % [e.get("name", esp.name), nm(t)])
			if e.get("form_effect", false):
				end_wild_shape(t)
			# A concentration spell with nothing left of it ends for its caster.
			if e.get("conc", false) and not esrc.is_empty() and esrc.conc.get("spell", "") == sid and not _spell_still_active(esrc.id, sid):
				end_concentration(esrc, true)
		if ended == 0:
			log_line("  No spell on %s is dispelled." % nm(t))
		refresh_teams()
		sync_move(t)
	return true

## Whether anything of `sid` cast by `src_id` is still on a creature or in a zone.
func _spell_still_active(src_id: String, sid: String) -> bool:
	for o in all_combatants():
		for e in o.effects:
			if e.get("src", "") == src_id and e.get("spell", "") == sid:
				return true
	for z in s.zones:
		if z.get("src", "") == src_id and z.get("spell", "") == sid:
			return true
	return false

## Lesser Restoration: end one disease or the blinded, deafened, paralyzed or poisoned condition.
func _sp_lesser_restoration(c: Dictionary, sp: Dictionary, cbd: Dictionary, targets: Array, ctx: Dictionary) -> bool:
	for t in targets:
		for cond in ["paralyzed", "blinded", "poisoned", "deafened"]:
			var hit: Array = t.effects.filter(func(e): return e.get("cond", "") == cond)
			if not hit.is_empty():
				remove_effect(t, hit[0].eid)
				log_line("  %s is no longer %s." % [nm(t), cond])
				break
	return true

## Life Transference: the caster takes 4d8 necrotic (+1d8 per slot above 3rd, can't be reduced)
## and the target regains twice that.
func _sp_life_transference(c: Dictionary, sp: Dictionary, cbd: Dictionary, targets: Array, ctx: Dictionary) -> bool:
	var t: Dictionary = targets[0] if not targets.is_empty() else {}
	if t.is_empty() or t.id == c.id:
		log_line("  Life Transference needs another creature to heal.")
		return true
	var cost: int = Dice.roll(Dice.add("4d8", Dice.times("1d8", ctx.upl))).total
	var before: int = int(c.hp)
	c.hp = int(c.hp) - cost
	log_line("  %s pours %d HP of their own life force out." % [nm(c), cost])
	float_text(c.id, "-%d" % cost, "#8a4ac0")
	if c.hp <= 0:
		_on_zero(c, {}, -c.hp, {}, before > 0)
	heal_creature(t, cost * 2, c, sp.name)
	fx("burst", t.pos, t.pos, "#7fdc7f")
	return true

## Divine Word: each chosen creature within 30 ft makes a CHA save; on a failure what happens depends
## on its current HP: 50 or fewer deafened (1 minute), 40 or fewer also blinded (10 minutes),
## 30 or fewer also stunned (1 hour), 20 or fewer killed.
func _sp_divine_word(c: Dictionary, sp: Dictionary, cbd: Dictionary, targets: Array, ctx: Dictionary) -> bool:
	for t in _spell_targets_area(c, sp, cbd, ctx):
		if not alive(t) or t.hp <= 0 or saving_throw(t, "cha", ctx.dc, c, {"spell": true}):
			continue
		var hp: int = int(t.hp)
		if hp > 50:
			log_line("  %s is too hale to be affected." % nm(t))
			continue
		if hp <= 20:
			log_line("  The word slays %s outright!" % nm(t))
			apply_damage(t, [{"amount": hp + int(t.temp_hp) + int(t.max_hp), "type": "radiant"}], c, {"spell": true})
			continue
		var rounds: int = 600 if hp <= 30 else (100 if hp <= 40 else 10)
		add_effect(t, {"name": "Deafened", "cond": "deafened", "src": c.id, "spell": sp.id, "rounds": rounds, "tick_cid": c.id})
		if hp <= 40:
			add_effect(t, {"name": "Blinded", "cond": "blinded", "src": c.id, "spell": sp.id, "rounds": rounds, "tick_cid": c.id})
		if hp <= 30:
			add_effect(t, {"name": "Stunned", "cond": "stunned", "src": c.id, "spell": sp.id, "rounds": rounds, "tick_cid": c.id})
	return true

## Power Word Pain: a creature with 100 HP or fewer is wracked (speed 10 ft at most, disadvantage on
## attacks and on saves other than CON) until it succeeds on a CON save at the end of one of its turns.
func _sp_power_word_pain(c: Dictionary, sp: Dictionary, cbd: Dictionary, targets: Array, ctx: Dictionary) -> bool:
	for t in targets:
		if int(t.hp) > 100:
			log_line("  %s has too much life left to be affected." % nm(t))
			continue
		if "charmed" in t.cond_immune:
			log_line("  %s is unaffected." % nm(t))
			continue
		add_effect(t, {"name": "Wracked", "src": c.id, "spell": sp.id, "rounds": 600, "tick_cid": c.id,
			"mods": {"max_speed": 10, "disadvantage_attack": true, "save_dis": ["str", "dex", "int", "wis", "cha"]},
			"save_ends": {"ability": "con", "dc": ctx.dc}})
		log_line("  %s is wracked with pain." % nm(t))
	return true

const CHAOS_TYPES := ["acid", "cold", "fire", "force", "lightning", "poison", "psychic", "thunder"]

## Chaos Bolt: 2d8 + 1d6 (+1d6 per slot level), the type set by one of the d8s; if both d8s match,
## the bolt leaps to another creature within 30 ft of the one it hit.
func _sp_chaos_bolt(c: Dictionary, sp: Dictionary, cbd: Dictionary, targets: Array, ctx: Dictionary) -> bool:
	var t: Dictionary = targets[0] if not targets.is_empty() else {}
	var hit_ids: Array = []
	while not t.is_empty() and alive(t):
		hit_ids.append(t.id)
		fx("bolt", c.pos, t.pos, "#d070ff", [], "force")
		var r = roll_attack(c, t, {"to_hit": ctx.attack, "melee": false, "range": int(sp.range)}, {"melee": false, "spell": true})
		t = r.get("target", t)
		if not r.hit:
			break
		var a: int = Dice.d(8)
		var b: int = Dice.d(8)
		var typ: String = CHAOS_TYPES[a - 1]
		var extra: String = Dice.add("1d6", Dice.times("1d6", int(ctx.upl)))
		var amt: int = a + b + Dice.roll(extra, {"crit": r.crit}).total
		if r.crit:
			amt += Dice.roll("2d8").total
		log_line("  The bolt turns to %s (d8s: %d, %d)." % [typ, a, b])
		apply_damage(t, [{"amount": amt, "type": typ}], c, {"spell": true, "attack": true})
		if a != b:
			break
		var nxt: Dictionary = {}
		for o in enemies_of(c):
			if not o.id in hit_ids and o.hp > 0 and dist(o, t) <= 30:
				nxt = o
				break
		if nxt.is_empty():
			break
		log_line("  The chaos leaps to %s!" % nm(nxt))
		t = nxt
	return true

## Lightning Lure: STR save or the target (Large or smaller) is pulled up to 10 ft toward the caster,
## then takes the lightning only if it ends within 5 ft.
func _sp_lightning_lure(c: Dictionary, sp: Dictionary, cbd: Dictionary, targets: Array, ctx: Dictionary) -> bool:
	var parts = _spell_damage(c, sp, cbd, ctx)
	for t in targets:
		if saving_throw(t, "str", ctx.dc, c, {"spell": true}):
			continue
		if size_rank(t) <= 3:
			pull_creature(t, center_of(c), 10)
		if dist(c, t) <= 5 and alive(t):
			apply_damage(t, _roll_parts(c, parts, false, ctx), c, {"spell": true})
		else:
			log_line("  %s ends too far away to be shocked." % nm(t))
	return true

## Negative Energy Flood: undead gain 5d12 temporary HP instead; others make a CON save, half on success.
func _sp_negative_energy_flood(c: Dictionary, sp: Dictionary, cbd: Dictionary, targets: Array, ctx: Dictionary) -> bool:
	for t in targets:
		if str(t.get("type", "")) == "undead":
			grant_temp_hp(t, Dice.roll("5d12").total, sp.name)
			continue
		var ok = saving_throw(t, "con", ctx.dc, c, {"spell": true})
		var amt: int = Dice.roll("5d12").total
		apply_damage(t, [{"amount": amt / 2 if ok else amt, "type": "necrotic"}], c, {"spell": true, "spell_level": ctx.slot})
	return true

## Enlarge/Reduce: allies are enlarged (+1d4 weapon damage, advantage on STR saves) unless the caster
## picks "reduce" (opts.mode); a hostile target is reduced (-1d4 weapon damage, disadvantage on STR
## saves) on a failed CON save.
func _sp_enlarge_reduce(c: Dictionary, sp: Dictionary, cbd: Dictionary, targets: Array, ctx: Dictionary) -> bool:
	for t in targets:
		var reduce: bool = hostile(c, t) or str(ctx.opts.get("mode", "")) == "reduce"
		if hostile(c, t) and saving_throw(t, "con", ctx.dc, c, {"spell": true}):
			continue
		if reduce:
			add_effect(t, {"name": "Reduced", "src": c.id, "spell": sp.id, "conc": true, "rounds": 10, "tick_cid": c.id,
				"mods": {"weapon_damage_penalty": "1d4", "save_dis": ["str"]}})
			log_line("  %s shrinks." % nm(t))
		else:
			add_effect(t, {"name": "Enlarged", "src": c.id, "spell": sp.id, "conc": true, "rounds": 10, "tick_cid": c.id,
				"mods": {"extra_damage": {"dice": "1d4", "type": "bludgeoning"}, "save_adv": ["str"]}})
			log_line("  %s grows." % nm(t))
	return true

## Vortex Warp: a target that fails its CON save (allies may choose to fail) is teleported to the chosen
## point, or if none was picked, as far from the caster as the spell reaches.
func _sp_vortex_warp(c: Dictionary, sp: Dictionary, cbd: Dictionary, targets: Array, ctx: Dictionary) -> bool:
	var rng: int = 90 + 30 * int(ctx.upl)
	for t in targets:
		if hostile(c, t) and saving_throw(t, "con", ctx.dc, c, {"spell": true}):
			continue
		var dest: Vector2i = ctx.cell
		if dest == c.pos or dist_to_cell(c, dest) > rng or not los_cells(c.pos, dest):
			var best_d = -1
			for x in range(c.pos.x - rng / 5, c.pos.x + rng / 5 + 1):
				for y in range(c.pos.y - rng / 5, c.pos.y + rng / 5 + 1):
					var q = Vector2i(x, y)
					if not in_bounds(q) or blocks_move(q) or not creature_at(q).is_empty() or not los_cells(c.pos, q):
						continue
					var d: int = cheb(q, c.pos) if hostile(c, t) else -cheb(q, c.pos)
					if d > best_d or best_d == -1:
						best_d = d
						dest = q
		if teleport(t, dest):
			log_line("  %s is swept away through a vortex." % nm(t))
	return true

## Calm Emotions: allies in the area are freed of charm and fear; hostile humanoids that fail a CHA save
## become indifferent and won't harm the caster's side until the spell ends or they're hurt.
func _sp_calm_emotions(c: Dictionary, sp: Dictionary, cbd: Dictionary, targets: Array, ctx: Dictionary) -> bool:
	for t in _spell_targets_area(c, sp, cbd, ctx):
		if not hostile(c, t):
			remove_effects_where(t, func(e): return e.get("cond", "") in ["charmed", "frightened"])
			log_line("  %s is calmed." % nm(t))
			continue
		if str(t.get("type", "")) != "humanoid" and t.get("kind", "") != "pc":
			continue
		if saving_throw(t, "cha", ctx.dc, c, {"spell": true, "cond": "charmed"}):
			continue
		add_effect(t, {"name": "Calmed", "tag": "pacified", "src": c.id, "spell": sp.id, "conc": true, "rounds": 10, "tick_cid": c.id, "end_on_damage": true})
		log_line("  %s loses the will to fight." % nm(t))
	return true

## Reality Break: on a failed WIS save the target suffers a random tear in reality now and at the end
## of each of its turns until it succeeds on the save (see _reality_tear).
func _sp_reality_break(c: Dictionary, sp: Dictionary, cbd: Dictionary, targets: Array, ctx: Dictionary) -> bool:
	for t in targets:
		if saving_throw(t, "wis", ctx.dc, c, {"spell": true}):
			continue
		add_effect(t, {"name": "Reality Break", "tag": "reality_break", "src": c.id, "spell": sp.id, "conc": true, "rounds": 10, "tick_cid": c.id, "dc": ctx.dc})
		_reality_tear(c, t)
	return true

## d10: 1-2 stunned until the end of its next turn; 3-5 6d12 psychic; 6-8 8d12 force and teleported up
## to 30 ft at random; 9-10 10d12 cold and blinded until the end of its next turn.
func _reality_tear(c: Dictionary, t: Dictionary) -> void:
	var r: int = Dice.d(10)
	if r <= 2:
		log_line("  Reality warps around %s, leaving it stunned (%d)." % [nm(t), r])
		add_effect(t, {"name": "Reality-stunned", "cond": "stunned", "src": c.id, "spell": "reality_break", "rounds": 1, "tick_cid": t.id, "tick_on": "end"})
	elif r <= 5:
		log_line("  Visions of the void claw at %s's mind (%d)." % [nm(t), r])
		apply_damage(t, [{"amount": Dice.roll("6d12").total, "type": "psychic"}], c, {"spell": true})
	elif r <= 8:
		log_line("  A rift swallows %s and spits it out elsewhere (%d)." % [nm(t), r])
		apply_damage(t, [{"amount": Dice.roll("8d12").total, "type": "force"}], c, {"spell": true})
		if alive(t):
			var spot := _free_spot_near(t.pos + Vector2i(randi_range(-6, 6), randi_range(-6, 6)), int(t.sz))
			if spot.x >= 0:
				teleport(t, spot)
	else:
		log_line("  The cold of the void engulfs %s (%d)." % [nm(t), r])
		apply_damage(t, [{"amount": Dice.roll("10d12").total, "type": "cold"}], c, {"spell": true})
		if alive(t):
			add_effect(t, {"name": "Void-blinded", "cond": "blinded", "src": c.id, "spell": "reality_break", "rounds": 1, "tick_cid": t.id, "tick_on": "end"})

const PRISM := [["fire", "red"], ["acid", "orange"], ["lightning", "yellow"], ["poison", "green"], ["cold", "blue"]]

## Prismatic Spray: each creature in the cone makes one DEX save and is struck by a random ray (d8):
## 1-5 10d6 of an element (half on a save); 6 indigo: restrained, turning to stone after three failed
## CON saves; 7 violet: blinded, repeating a WIS save; 8: struck by two rays (rerolling 8s).
func _sp_prismatic_spray(c: Dictionary, sp: Dictionary, cbd: Dictionary, targets: Array, ctx: Dictionary) -> bool:
	for t in _spell_targets_area(c, sp, cbd, ctx):
		if not alive(t):
			continue
		var ok = saving_throw(t, "dex", ctx.dc, c, {"spell": true})
		var rays: Array = [Dice.d(8)]
		if rays[0] == 8:
			rays = [Dice.d(7), Dice.d(7)]
		for r in rays:
			if r <= 5:
				var amt: int = Dice.roll("10d6").total
				log_line("  A %s ray strikes %s." % [PRISM[r - 1][1], nm(t)])
				apply_damage(t, [{"amount": amt / 2 if ok else amt, "type": PRISM[r - 1][0]}], c, {"spell": true})
			elif ok:
				log_line("  %s dodges the %s ray." % [nm(t), "indigo" if r == 6 else "violet"])
			elif r == 6:
				log_line("  An indigo ray begins to turn %s to stone." % nm(t))
				add_effect(t, {"name": "Indigo Ray", "cond": "restrained", "src": c.id, "spell": sp.id, "rounds": 9999, "tick_cid": "none", "dc": ctx.dc,
					"save_count": {"ability": "con", "fails": 3, "successes": 3, "on_fail": {"name": "Petrified", "condition": "petrified", "duration_rounds": 0}}})
			else:
				log_line("  A violet ray blinds %s." % nm(t))
				add_effect(t, {"name": "Violet Ray", "cond": "blinded", "src": c.id, "spell": sp.id, "rounds": 10, "tick_cid": c.id, "save_ends": {"ability": "wis", "dc": ctx.dc}})
	return true

## Mass Heal: 700 HP of healing shared among the chosen creatures, most hurt first; it also cures
## blindness and deafness.
func _sp_mass_heal(c: Dictionary, sp: Dictionary, cbd: Dictionary, targets: Array, ctx: Dictionary) -> bool:
	var pool: int = 700
	var order: Array = targets.filter(func(o): return alive(o) and not hostile(c, o))
	order.sort_custom(func(a, b): return float(maxi(0, a.hp)) / a.max_hp < float(maxi(0, b.hp)) / b.max_hp)
	for t in order:
		remove_effects_where(t, func(e): return e.get("cond", "") in ["blinded", "deafened"])
		var need: int = int(t.max_hp) - maxi(0, int(t.hp))
		if need <= 0 or pool <= 0:
			continue
		var amt: int = mini(need, pool)
		pool -= amt
		heal_creature(t, amt, c, sp.name)
	return true

## Eyebite: one creature within 60 ft makes a WIS save or suffers the caster's choice (opts.eyebite):
## asleep (unconscious until it takes damage, the default), panicked (frightened and running from the
## caster each turn) or sickened (disadvantage on attacks, repeating the save each turn).
func _sp_eyebite(c: Dictionary, sp: Dictionary, cbd: Dictionary, targets: Array, ctx: Dictionary) -> bool:
	var mode: String = str(ctx.opts.get("eyebite", "asleep"))
	for t in targets:
		if not alive(t) or saving_throw(t, "wis", ctx.dc, c, {"spell": true}):
			continue
		match mode:
			"panicked":
				add_effect(t, {"name": "Panicked", "cond": "frightened", "tag": "compelled", "src": c.id, "spell": sp.id, "conc": true, "rounds": 10, "tick_cid": c.id})
			"sickened":
				add_effect(t, {"name": "Sickened", "src": c.id, "spell": sp.id, "conc": true, "rounds": 10, "tick_cid": c.id, "mods": {"disadvantage_attack": true}, "save_ends": {"ability": "wis", "dc": ctx.dc}})
			_:
				if "charmed" in t.cond_immune or str(t.get("type", "")) in ["undead", "construct"]:
					log_line("  %s can't be put to sleep." % nm(t))
					continue
				add_effect(t, {"name": "Eyebitten", "cond": "unconscious", "src": c.id, "spell": sp.id, "conc": true, "rounds": 10, "tick_cid": c.id, "end_on_damage": true})
		log_line("  %s is %s." % [nm(t), mode])
	return true

## Summon Beast: a bestial spirit appears at the point, joins the fight right after the caster and lasts
## while the caster concentrates (opts.beast: air, land or water; land by default).
func _sp_summon_beast(c: Dictionary, sp: Dictionary, cbd: Dictionary, targets: Array, ctx: Dictionary) -> bool:
	var kind: String = str(ctx.opts.get("beast", "land"))
	var o = CombatantFactory.bestial_spirit(new_id("s"), c, kind, int(ctx.slot), int(ctx.attack))
	var spot := _free_spot_near(ctx.cell, 1)
	if spot.x < 0:
		log_line("  There's no room for the spirit.")
		end_concentration(c, true)
		return true
	o.pos = spot
	o.conc_summon = c.id + ":" + sp.id
	o.init = int(c.get("init", 0))
	s.combatants[o.id] = o
	_join_after_caster(c, [o])
	add_effect(c, {"name": sp.name, "tag": "summon_beast", "src": c.id, "spell": sp.id, "conc": true, "rounds": int(sp.get("duration_rounds", 600)), "tick_cid": c.id})
	fx("burst", spot, spot, "#8fd07a", [], "buff")
	log_line("  A %s spirit takes shape." % kind)
	return true

## Delayed Blast Fireball: a bead hangs at the point and bursts when the spell ends (concentration
## broken or dropped, the minute up, or the caster detonating it), 12d6 + 1d6 for each turn it waited.
func _sp_delayed_blast_fireball(c: Dictionary, sp: Dictionary, cbd: Dictionary, targets: Array, ctx: Dictionary) -> bool:
	if c.conc.get("spell", "") == sp.id:
		c.conc.bead = {"cell": ctx.cell, "dc": ctx.dc, "upl": ctx.upl, "extra": 0}
	log_line("  A glowing bead of fire hangs in the air, waiting.")
	return true

func _detonate_bead(c: Dictionary, e: Dictionary) -> void:
	var sp = Data.spell("delayed_blast_fireball")
	var cbd: Dictionary = sp.combat.duplicate(true)
	cbd.erase("special")
	cbd.erase("repeat")
	cbd.damage = [{"dice": Dice.add(str(cbd.damage[0].dice), "%dd6" % int(e.get("extra", 0))), "type": "fire"}]
	log_line("[b]The bead of fire bursts![/b]")
	var ctx = {"slot": int(sp.level) + int(e.get("upl", 0)), "upl": int(e.get("upl", 0)), "meta": "", "opts": {}, "entry": caster_entry(c, ""),
		"dc": int(e.get("dc", 15)), "attack": 0, "cell": e.get("cell", c.pos)}
	_generic_spell(c, sp, cbd, [], ctx)

func _on_spell_end(c: Dictionary, sp: String, held: Dictionary) -> void:
	if sp == "delayed_blast_fireball" and held.get("bead", null) is Dictionary:
		_detonate_bead(c, held.bead)

## Meteor Swarm: up to four 40-ft spheres (ctx.opts.cells adds points to the one picked); a creature
## caught in several is hit only once.
func _sp_meteor_swarm(c: Dictionary, sp: Dictionary, cbd: Dictionary, targets: Array, ctx: Dictionary) -> bool:
	var points: Array = [ctx.cell]
	for p in ctx.opts.get("cells", []):
		if p is Vector2i and points.size() < 4:
			points.append(p)
	var cells: Array = []
	for p in points:
		for q in area_cells(c, cbd.area, p, false):
			if not q in cells:
				cells.append(q)
	var sub: Dictionary = cbd.duplicate(true)
	sub.erase("special")
	ctx.cells = cells
	fx("area", c.pos, ctx.cell, "#ff8a3a", cells, "fire")
	var victims: Array = creatures_in_cells(cells)
	sub.target = "enemy"
	sub.erase("area")
	_generic_spell(c, sp, sub, victims, ctx)
	return true

## Gravity Fissure: the 100-ft line hits everything in it; creatures within 10 ft of the line (but not
## in it) are pulled toward it and take the damage too on a failed CON save.
func _sp_gravity_fissure(c: Dictionary, sp: Dictionary, cbd: Dictionary, targets: Array, ctx: Dictionary) -> bool:
	var sub: Dictionary = cbd.duplicate(true)
	sub.erase("special")
	_generic_spell(c, sp, sub, targets, ctx)
	var line: Array = ctx.get("cells", [])
	var dmg = _spell_damage(c, sp, sub, ctx)
	for o in all_combatants():
		if not alive(o) or o.id == c.id or o.hp <= 0 or line.is_empty():
			continue
		var best: Vector2i = line[0]
		var bd: int = 999
		for q in line:
			if cheb(q, o.pos) < bd:
				bd = cheb(q, o.pos)
				best = q
		if bd == 0 or bd * 5 > 10:
			continue
		if saving_throw(o, "con", ctx.dc, c, {"spell": true}):
			continue
		pull_creature(o, Vector2(best) + Vector2(0.5, 0.5), 10)
		apply_damage(o, _roll_parts(c, dmg, false, ctx), c, {"spell": true})
	return true

# ================================================================ class features

## Turn Undead and the oath versions (Turn the Unholy, Turn the Faithless): each creature of the given
## types within 30 ft that can see or hear `c` makes a WIS save. On a failure it is turned for 1 minute
## or until it takes damage; Destroy Undead instead destroys undead of CR `destroy_cr` or lower.
func _turn_creatures(c: Dictionary, types: Array, dc: int, destroy_cr: float) -> void:
	fx("area", c.pos, c.pos, "#fff2a8", area_cells(c, {"shape": "emanation", "size": 30}, c.pos, true))
	var any = false
	for o in enemies_of(c):
		if not str(o.get("type", "")) in types or dist(c, o) > 30 or o.hp <= 0 or has_cond(o, "deafened") and has_cond(o, "blinded"):
			continue
		any = true
		if saving_throw(o, "wis", dc, c, {"magic": true, "cond": "turned"}):
			continue
		if o.type == "undead" and destroy_cr >= 0.0 and float(o.cr) <= destroy_cr and o.kind != "pc":
			log_line("  [color=#fff2a8]%s is destroyed by the holy power![/color]" % nm(o))
			fx("burst", o.pos, o.pos, "#fff2a8")
			destroy_creature(o, c)
		else:
			# Turned: it can't take reactions and spends its turns running from `c` (see _turned_turn);
			# damage breaks it.
			log_line("  %s is turned." % nm(o))
			add_effect(o, {"name": "Turned", "tag": "turned", "mods": {"no_reactions": true}, "end_on_damage": true, "src": c.id, "rounds": 10, "tick_cid": c.id})
	if not any:
		log_line("  No creature it can affect is close enough.")

func _feature(c: Dictionary, a: Dictionary, targets: Array, cellp: Vector2i, params: Dictionary) -> bool:
	var opts: Dictionary = params.get("opts", {})
	var t: Dictionary = targets[0] if targets.size() > 0 else {}
	# Checks that must pass before anything is spent.
	match a.id:
		"magic_stone_drop":
			if not in_bounds(cellp) or blocks_move(cellp) or _held_stone(c, a.get("eid", "")).is_empty():
				log_line("[color=#888]A stone can't be set down there.[/color]")
				return false
		"magic_stone_pickup":
			if stones_at(cellp).is_empty():
				log_line("[color=#888]There is no magic stone there.[/color]")
				return false
		"magic_stone_give":
			if _held_stone(c, a.get("eid", "")).is_empty():
				return false
			if t.is_empty() or t.id == c.id or not alive(t) or t.hp <= 0 or hostile(c, t):
				log_line("[color=#888]%s can't take a magic stone.[/color]" % str(t.get("name", "That creature")))
				return false
		"lay_on_hands":
			if t.is_empty():
				return false
			if str(t.get("type", "")) in ["undead", "construct"]:
				log_line("[color=#888]Lay on Hands has no effect on undead or constructs.[/color]")
				return false
			if opts.get("cure", false):
				if res_left(c, "lay_on_hands") < 5:
					log_line("[color=#888]Neutralizing poison takes 5 points from the pool.[/color]")
					return false
				if not has_cond(t, "poisoned"):
					log_line("[color=#888]%s isn't poisoned.[/color]" % nm(t))
					return false
			elif t.hp >= t.max_hp:
				log_line("[color=#888]%s is already at full health.[/color]" % nm(t))
				return false
	if a.get("res", "") != "" and not a.id.begins_with("fom_"):
		spend_res(c, a.res)
	pay(c, a.cost, a.id == "sustain_spell")
	var lv: int = c.level
	match a.id:
		"rage":
			add_effect(c, {"name": "Rage", "tag": "rage", "src": c.id, "rounds": 10, "tick_cid": c.id})
			log_line("%s flies into a [color=#ff5050][b]RAGE[/b][/color]!" % nm(c))
			fx("burst", c.pos, c.pos, "#ff4040", [], "rage")
		"end_rage":
			remove_effects_where(c, func(e): return e.get("tag", "") == "rage")
		"frenzy", "war_priest", "war_magic", "polearm_master", "gwm_bonus", "spiritual_weapon_attack", "luminous_arrow", "martial_arts":
			if a.id == "gwm_bonus":
				c.turn.gwm_bonus = false
			_attack_with(c, t, a.atk, {"bonus_attack": true})
		"swift_quiver":
			log_line("%s draws twice from the Swift Quiver." % nm(c))
			for i in 2:
				if t.is_empty() or not alive(t) or t.hp <= 0:
					t = _nearest_enemy_in_range(c, a.atk)
				if t.is_empty():
					break
				_attack_with(c, t, a.atk, {"bonus_attack": true})
		"sustain_spell":
			_sustain_spell(c)
		"dragons_breath":
			var be: Dictionary = {}
			for e in c.effects:
				if e.get("eid", "") == a.get("eid", ""):
					be = e
			var br: Dictionary = be.get("breath", {})
			if not br.is_empty():
				var src = C(be.get("src", ""))
				var cells = area_cells(c, a.area, cellp, true)
				var bt: String = str(br.get("type", "fire"))
				fx("area", c.pos, cellp, _dmg_color([{"type": bt}]), cells, _dmg_sfx([{"type": bt}]))
				log_line("%s exhales a blast of %s (Dragon's Breath)!" % [nm(c), bt])
				var broll: int = Dice.roll(str(br.dice)).total
				for o in creatures_in_cells(cells, c.id):
					var bok = saving_throw(o, str(br.get("save", "dex")), int(be.get("dc", 13)), src if not src.is_empty() else c, {"spell": true, "dmg_type": bt})
					var bdmg: int = broll
					if br.get("save", "dex") == "dex" and o.features.has("evasion"):
						bdmg = 0 if bok else bdmg / 2
					elif bok:
						bdmg = bdmg / 2
					apply_damage(o, [{"amount": bdmg, "type": bt}], c, {"spell": true})
		"vampiric_touch_attack":
			_attack_with(c, t, a.atk, {})
		"magic_stone_throw":
			var se = _held_stone(c, a.get("eid", ""))
			if not se.is_empty():
				se.uses = int(se.uses) - 1
				if int(se.uses) <= 0:
					remove_effect(c, se.eid)
			_attack_with(c, t, a.atk, {})
		"magic_stone_drop":
			var de = _held_stone(c, a.get("eid", ""))
			if de.is_empty():
				return false
			put_stone_down(c, de, cellp)
			log_line("%s sets a magic stone down." % nm(c))
		"magic_stone_pickup":
			var here = stones_at(cellp)
			if here.is_empty():
				log_line("[color=#888]There is no magic stone there.[/color]")
				return false
			var it: Dictionary = here[0]
			ground_items().erase(it)
			if s.in_combat:
				c.turn.interacted = true
			_take_stone(c, it)
			log_line("%s picks up a magic stone." % nm(c))
		"magic_stone_give":
			var ge = _held_stone(c, a.get("eid", ""))
			if ge.is_empty():
				return false
			if s.in_combat:
				c.turn.interacted = true
			_take_stone(t, ge)
			ge.uses = int(ge.uses) - 1
			if int(ge.uses) <= 0:
				remove_effect(c, ge.eid)
			log_line("%s hands a magic stone to %s." % [nm(c), nm(t)])
		"bardic_inspiration":
			add_effect(t, {"name": "Bardic Inspiration (d%d)" % int(c.vals.bardic_die), "tag": "bardic_inspiration", "die": "1d%d" % int(c.vals.bardic_die), "src": c.id, "rounds": 100, "tick_cid": c.id})
			log_line("%s inspires %s." % [nm(c), nm(t)])
		"second_wind":
			heal_creature(c, Dice.roll("1d10+%d" % c.class_levels.get("fighter", 1)).total, c, "Second Wind")
		"action_surge":
			c.turn.action = int(c.turn.action) + 1
			c.turn.surged = true
			log_line("%s surges into action!" % nm(c))
		"fighting_spirit":
			add_effect(c, {"name": "Fighting Spirit", "tag": "fighting_spirit", "src": c.id, "rounds": 1, "tick_cid": c.id, "tick_on": "end"})
			var f_lv: int = c.class_levels.get("fighter", 3)
			grant_temp_hp(c, 5 if f_lv < 10 else (10 if f_lv < 15 else 15), "Fighting Spirit")
		"flurry_of_blows":
			c.turn.flurry = true
			var ua = _unarmed(c)
			log_line("%s unleashes a Flurry of Blows!" % nm(c))
			for i in 2:
				if not alive(t) or t.hp <= 0:
					break
				_attack_with(c, t, ua, {"flurry": true})
		"patient_defense":
			add_effect(c, {"name": "Dodging", "tag": "dodge", "src": c.id, "rounds": 1, "tick_cid": c.id, "tick_on": "start"})
		"step_of_the_wind":
			c.turn.dashes = int(c.turn.get("dashes", 0)) + 1
			c.turn.disengaged = true
			sync_move(c)
			log_line("%s moves like the wind." % nm(c))
		"hand_of_healing":
			heal_creature(t, Dice.roll("1d%d+%d" % [int(c.vals.martial_die), int(c.mods.wis)]).total, c, "Hand of Healing")
		"lay_on_hands":
			# The pool was charged 1 point up front; settle the real cost here.
			var pool: int = res_left(c, "lay_on_hands") + 1
			if opts.get("cure", false):
				remove_effects_where(t, func(e): return e.get("cond", "") == "poisoned")
				c.resources.lay_on_hands.cur = maxi(0, pool - 5)
				log_line("%s lays hands on %s and neutralizes the poison." % [nm(c), nm(t)])
			else:
				var need: int = maxi(0, t.max_hp - maxi(t.hp, 0))
				var want: int = int(opts.get("amount", 0))
				var amt: int = mini(mini(need, pool), want if want > 0 else need)
				amt = maxi(1, amt)
				c.resources.lay_on_hands.cur = maxi(0, pool - amt)
				heal_creature(t, amt, c, "Lay on Hands")
		"turn_undead":
			log_line("%s presents a holy symbol: [b]Turn Undead[/b]!" % nm(c))
			var cl: int = c.class_levels.get("cleric", 2)
			var destroy_cr = -1.0 if cl < 5 else (0.5 if cl < 8 else (1.0 if cl < 11 else (2.0 if cl < 14 else (3.0 if cl < 17 else 4.0))))
			_turn_creatures(c, ["undead"], int(c.vals.cd_dc_wis), destroy_cr)
		"turn_the_unholy":
			log_line("%s raises a holy symbol: [b]Turn the Unholy[/b]!" % nm(c))
			_turn_creatures(c, ["fiend", "undead"], int(c.vals.cd_dc_cha), -1.0)
		"turn_the_faithless":
			log_line("%s speaks a primal word: [b]Turn the Faithless[/b]!" % nm(c))
			_turn_creatures(c, ["fey", "fiend"], int(c.vals.cd_dc_cha), -1.0)
		"abjure_enemy":
			log_line("%s abjures %s!" % [nm(c), nm(t)])
			var dis: bool = t.get("type", "") in ["fiend", "undead"]
			if t.tags.has("frightened_immune") or "frightened" in t.get("cond_immune", []):
				add_effect(t, {"name": "Abjured", "src": c.id, "mods": {"speed_mult": 0.5}, "rounds": 10, "tick_cid": c.id})
			elif not saving_throw(t, "wis", int(c.vals.cd_dc_cha), c, {"magic": true, "cond": "frightened", "dis": dis}):
				# Frightened with speed 0 for 1 minute, or until it takes any damage.
				add_effect(t, {"name": "Abjured", "cond": "frightened", "src": c.id, "mods": {"speed_mult": 0}, "end_on_damage": true, "rounds": 10, "tick_cid": c.id})
			else:
				add_effect(t, {"name": "Abjured (slowed)", "src": c.id, "mods": {"speed_mult": 0.5}, "rounds": 10, "tick_cid": c.id})
			sync_move(t)
		"preserve_life":
			var pool: int = 5 * c.class_levels.get("cleric", 2)
			var hurt = allies_of(c).filter(func(o): return dist(c, o) <= 30 and o.hp < o.max_hp / 2 and not str(o.get("type", "")) in ["undead", "construct"] and not o.death.dead)
			hurt.sort_custom(func(x, y): return x.hp < y.hp)
			for o in hurt:
				var give = mini(pool, o.max_hp / 2 - maxi(0, o.hp))
				if give > 0:
					heal_creature(o, give, c, "Preserve Life")
					pool -= give
		"radiance_of_the_dawn":
			fx("area", c.pos, c.pos, "#fff2a8", area_cells(c, {"shape": "emanation", "size": 30}, c.pos, true))
			var dawn: int = Dice.roll("2d10+%d" % c.class_levels.get("cleric", 2)).total
			for o in enemies_of(c):
				if dist(c, o) <= 30:
					var ok = saving_throw(o, "con", int(c.vals.cd_dc_wis), c, {"magic": true})
					var dmg: int = dawn
					apply_damage(o, [{"amount": dmg / 2 if ok else dmg, "type": "radiant"}], c, {"magic": true})
		"twilight_sanctuary":
			add_effect(c, {"name": "Twilight Sanctuary", "tag": "twilight_sanctuary", "src": c.id, "rounds": 10, "tick_cid": c.id,
				"aura": {"radius": 30, "allies_only": true, "include_self": true, "trigger": "end_turn", "temp_hp": "1d6+%d" % c.class_levels.get("cleric", 2)}})
			log_line("%s is wreathed in a sphere of twilight." % nm(c))
		"balm_of_peace":
			for o in allies_of(c):
				if dist(c, o) <= 15 and o.hp < o.max_hp:
					heal_creature(o, Dice.roll("2d6+%d" % maxi(0, int(c.mods.wis))).total, c, "Balm of Peace")
		"path_to_the_grave":
			add_effect(t, {"name": "Path to the Grave", "tag": "path_to_grave", "src": c.id, "rounds": 2, "tick_cid": c.id, "tick_on": "end"})
		"sacred_weapon":
			add_effect(c, {"name": "Sacred Weapon", "tag": "sacred_weapon", "src": c.id, "rounds": 10, "tick_cid": c.id})
		"vow_of_enmity":
			add_effect(t, {"name": "Vow of Enmity", "tag": "vow_of_enmity", "src": c.id, "rounds": 10, "tick_cid": c.id})
		"natures_wrath":
			if not saving_throw(t, "str", int(c.vals.cd_dc_cha), c, {"magic": true}):
				add_effect(t, {"name": "Entangled", "cond": "restrained", "src": c.id, "save_ends": {"ability": "str", "dc": int(c.vals.cd_dc_cha)}, "rounds": 10, "tick_cid": c.id})
		"conquering_presence":
			for o in enemies_of(c):
				if dist(c, o) <= 30 and not saving_throw(o, "wis", int(c.vals.cd_dc_cha), c, {"magic": true, "cond": "frightened"}):
					add_effect(o, {"name": "Frightened", "cond": "frightened", "src": c.id, "save_ends": {"ability": "wis", "dc": int(c.vals.cd_dc_cha)}, "rounds": 10, "tick_cid": c.id})
		"emboldening_bond":
			var group = allies_of(c).filter(func(o): return dist(c, o) <= 30)
			group.sort_custom(func(x, y): return dist(c, x) < dist(c, y))
			for o in group.slice(0, int(c.prof)):
				add_effect(o, {"name": "Emboldening Bond", "tag": "bonded", "src": c.id, "rounds": 100, "tick_cid": c.id})
			log_line("%s forges an Emboldening Bond." % nm(c))
		"wild_shape":
			var fid: String = opts.get("form", "")
			var forms: Array = a.get("forms", [])
			if fid == "" and not forms.is_empty():
				fid = forms[-1].id
			if fid == "" or Data.monster(fid).is_empty():
				return false
			c.form = CombatantFactory.wild_shape_form(fid)
			add_effect(c, {"name": "Wild Shape", "tag": "wild_shape", "form_effect": true, "src": c.id, "rounds": 600 * max(1, c.class_levels.get("druid", 2) / 2), "tick_cid": c.id})
			log_line("%s transforms into a [b]%s[/b]!" % [nm(c), c.form.name])
			fx("burst", c.pos, c.pos, "#7fdc7f")
		"revert_form":
			end_wild_shape(c)
		"symbiotic_entity":
			grant_temp_hp(c, 4 * c.class_levels.get("druid", 2), "Symbiotic Entity")
			add_effect(c, {"name": "Symbiotic Entity", "tag": "symbiotic", "src": c.id, "rounds": 100, "tick_cid": c.id})
		"starry_archer", "starry_chalice":
			remove_effects_where(c, func(e): return e.get("tag", "") in ["starry_archer", "starry_chalice"])
			add_effect(c, {"name": "Starry Form", "tag": a.id, "src": c.id, "rounds": 100, "tick_cid": c.id})
			log_line("%s's body glows with starlight." % nm(c))
		"hexblades_curse":
			add_effect(t, {"name": "Hexblade's Curse", "tag": "hexblade_curse", "src": c.id, "rounds": 10, "tick_cid": c.id})
		"healing_light":
			var dice = mini(maxi(1, int(c.mods.cha)), res_left(c, "healing_light") + 1)
			var need2: int = t.max_hp - maxi(0, t.hp)
			var used = mini(dice, maxi(1, ceili(need2 / 3.5)))
			c.resources.healing_light.cur = maxi(0, res_left(c, "healing_light") + 1 - used)
			heal_creature(t, Dice.roll("%dd6" % used).total, c, "Healing Light")
		"fey_presence":
			for o in enemies_of(c):
				if dist(c, o) <= 10 and not saving_throw(o, "wis", best_spell_dc(c), c, {"magic": true, "cond": "frightened"}):
					add_effect(o, {"name": "Frightened", "cond": "frightened", "src": c.id, "rounds": 2, "tick_cid": c.id, "tick_on": "end"})
		"bladesong":
			add_effect(c, {"name": "Bladesong", "tag": "bladesong", "src": c.id, "mods": {"ac": maxi(1, int(c.mods.int)), "speed": 10}, "rounds": 10, "tick_cid": c.id})
			sync_move(c)  # the +10 ft speed applies immediately through eff_speed()
			log_line("%s begins the Bladesong." % nm(c))
		"momentary_stasis":
			if t.sz > 2:
				log_line("  %s is too large." % nm(t))
			elif not saving_throw(t, "con", int(c.vals.int_dc), c, {"magic": true}):
				add_effect(t, {"name": "Momentary Stasis", "cond": "incapacitated", "src": c.id, "mods": {"speed_mult": 0}, "rounds": 2, "tick_cid": c.id, "tick_on": "end"})
		"eldritch_cannon":
			if res_left(c, "eldritch_cannon") > 0:
				spend_res(c, "eldritch_cannon")
			else:
				spend_slot(c, lowest_slot(c, 1))
			var kind: String = opts.get("cannon", "force_ballista")
			if not kind in CANNON_TYPES:
				kind = "force_ballista"
			var can = CombatantFactory.eldritch_cannon(new_id("s"), c, kind)
			can.pos = cellp if (in_bounds(cellp) and creature_at(cellp).is_empty() and not blocks_move(cellp)) else _free_cell_near(c.pos)
			s.combatants[can.id] = can
			if s.in_combat:
				can.turn = new_turn(can)
				s.order.insert(s.turn + 1, can.id)
			log_line("%s builds an [b]%s[/b]." % [nm(c), can.name])
		"defensive_field":
			grant_temp_hp(c, c.class_levels.get("artificer", 3), "Defensive Field")
		"breath_weapon":
			var br: Dictionary = c.breath
			var cells = area_cells(c, {"shape": br.shape, "size": int(br.get("size", 15))}, cellp, true)
			fx("area", c.pos, cellp, _dmg_color([{"type": br.type}]), cells, _dmg_sfx([{"type": br.type}]))
			log_line("%s exhales a blast of %s!" % [nm(c), br.type])
			var broll2: int = Dice.roll(c.vals.breath_dice).total
			for o in creatures_in_cells(cells, c.id):
				var ok2 = saving_throw(o, br.save, int(c.vals.breath_dc), c, {})
				var dmg2: int = broll2
				apply_damage(o, [{"amount": dmg2 / 2 if ok2 else dmg2, "type": br.type}], c, {"magic": true})
		"healing_hands":
			heal_creature(t, int(c.level), c, "Healing Hands")
		"fey_step":
			if not teleport(c, cellp):
				log_line("  The destination is blocked.")
		"hidden_step":
			add_effect(c, {"name": "Hidden Step", "cond": "invisible", "breaks": true, "src": c.id, "rounds": 1, "tick_cid": c.id, "tick_on": "start"})
		"radiant_soul":
			add_effect(c, {"name": "Celestial Revelation", "tag": "radiant_soul", "src": c.id, "rounds": 10, "tick_cid": c.id})
		"planar_warrior":
			add_effect(t, {"name": "Planar Mark", "tag": "planar_mark", "src": c.id, "rounds": 1, "tick_cid": c.id, "tick_on": "end"})
		"move_mark":
			var sp2 = Data.spell(c.conc.spell)
			_sp_hunters_mark(c, sp2, sp2.get("combat", {}), [t], {"dc": 0})
		_:
			if a.id.begins_with("rp:"):
				_run_repeat(c, str(a.eid), targets, cellp, opts)
				return true
			if a.id.begins_with("arcane_rec_"):
				var L2: int = a.slot_level
				# The once-a-day use is spent with the first slot recovered.
				if res_left(c, "arcane_recovery") > 0:
					spend_res(c, "arcane_recovery")
				c.slots_used[L2 - 1] = int(c.slots_used[L2 - 1]) - 1
				c.arcane_budget = int(c.get("arcane_budget", 0)) - L2
				log_line("%s uses Arcane Recovery to regain a level %d spell slot." % [nm(c), L2])
				return true
			if a.id.begins_with("fom_"):
				var L: int = a.slot_level
				if spend_res(c, "sorcery_points", int(a.sp_cost)):
					if L - 1 < c.slots_max.size() and int(c.slots_used[L - 1]) > 0:
						c.slots_used[L - 1] = int(c.slots_used[L - 1]) - 1
					else:
						while c.slots_max.size() < L:
							c.slots_max.append(0)
							c.slots_used.append(0)
						c.slots_max[L - 1] = int(c.slots_max[L - 1]) + 1
					log_line("%s forges a level %d spell slot from sorcery points." % [nm(c), L])
				return true
			log_line("%s uses %s." % [nm(c), a.name])
	return true

# ================================================================ rests & DM tools

func short_rest() -> void:
	if s.in_combat:
		end_combat()
	_end_all_ropes()
	# A short rest takes an hour: spells and effects of an hour or less run out (Spirit Guardians,
	# Spiritual Weapon, Shield of Faith, Bless...); 8-hour ones (Mage Armor, Aid) carry on.
	for c in all_combatants():
		if not c.conc.is_empty():
			var csp = Data.spell(str(c.conc.get("spell", "")))
			if csp.is_empty() or int(csp.get("duration_rounds", 0)) <= 600:
				end_concentration(c, true)
	for c in all_combatants():
		remove_effects_where(c, func(e): return int(e.get("rounds", 0)) <= 600 or e.get("cond", "") == "prone")
	s.zones = s.zones.filter(func(z): return int(z.get("rounds", 0)) <= 0 or int(z.get("rounds", 0)) > 600)
	for c in all_combatants():
		if not alive(c):
			continue
		for k in c.resources:
			if c.resources[k].reset == "short":
				c.resources[k].cur = c.resources[k].max
		c.pact_used = 0
		# Spend hit dice: heal roughly half the missing HP.
		if c.kind == "pc" and c.hp > 0 and c.hp < c.max_hp:
			heal_creature(c, (c.max_hp - c.hp) / 2, c, "short rest")
		# Arcane Recovery isn't spent automatically: the wizard may use it now (the "Recover Lv N
		# Slot" actions, until the next fight or long rest) or save it for a later short rest.
		if c.features.has("arcane_recovery") and res_left(c, "arcane_recovery") > 0:
			c.arcane_budget = ceili(c.class_levels.get("wizard", 1) / 2.0)
			log_line("%s can use Arcane Recovery to regain up to %d levels of spell slots." % [nm(c), c.arcane_budget])
	s.clock = int(s.get("clock", 0)) + 600  # an hour
	log_line("[color=#8fd0ff]The party takes a short rest.[/color]")

## A rest is at least as long as Rope Trick's hour.
func _end_all_ropes() -> void:
	for r in ropes().duplicate():
		end_rope(str(r.src))

func long_rest() -> void:
	_end_all_ropes()
	for c in all_combatants():
		if c.death.dead or c.dead:
			continue
		# Aid's 8-hour max HP boost is gone after a long rest.
		c.max_hp = int(c.max_hp) - int(c.get("aid_bonus", 0))
		c.aid_bonus = 0
		# Harm's cut to the hit point maximum lasts until a long rest.
		c.max_hp = int(c.max_hp) + int(c.get("max_hp_cut", 0))
		c.max_hp_cut = 0
		c.hp = c.max_hp
		c.temp_hp = 0
		c.death = {"s": 0, "f": 0, "stable": false, "dead": false}
		for k in c.resources:
			c.resources[k].cur = c.resources[k].max
		for i in c.slots_used.size():
			c.slots_used[i] = 0
		c.pact_used = 0
		c.effects = c.effects.filter(func(e): return int(e.get("rounds", 0)) > 4800 and e.get("cond", "") != "prone")
		c.conc = {}
		c.form = {}
		c.ward = 0
		c.ward_made = false
		c.legendary_res = 3 if c.tags.has("legendary_resistance") else 0
		c.erase("arcane_budget")
	s.zones = []
	s.clock = int(s.get("clock", 0)) + 4800  # eight hours
	log_line("[color=#8fd0ff]The party takes a long rest and recovers fully.[/color]")
