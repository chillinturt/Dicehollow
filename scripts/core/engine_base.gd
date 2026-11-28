class_name EngineBase
extends RefCounted
## Battle state, geometry, effects and the core d20 machinery (attacks, saves, damage).
## The state is a plain Dictionary so it can be synced over the network unchanged.

const FLOOR := 0
const WALL := 1
const DIFFICULT := 2
const WATER := 3
const PIT := 4

var s: Dictionary
var events: Array = []

func _init(state: Dictionary = {}) -> void:
	s = state

static func new_state(w: int, h: int) -> Dictionary:
	var cells = PackedByteArray()
	cells.resize(w * h)
	cells.fill(FLOOR)
	# "clock" counts elapsed game time in rounds (6 seconds each); see revivable().
	return {"name": "Untitled", "w": w, "h": h, "cells": cells, "combatants": {}, "order": [], "turn": 0, "round": 0, "clock": 0,
		"in_combat": false, "zones": [], "items": [], "log": [], "next_id": 1, "spawns": [], "theme": "stone",
		"fog": {"mode": "off", "shared": true, "range": 0}, "fog_seen": {},
		# Map dressing (drawn only): per-cell ground material, furniture/props and place-name labels.
		"ground": PackedByteArray(), "props": [], "labels": [],
		# Things to break, pick up or open (MapObjects); "stream": endless-map bookkeeping (MapStream).
		"objects": [], "stream": {}}

# ================================================================ basics

func C(id: String) -> Dictionary:
	return s.combatants.get(id, {})

func all_combatants() -> Array:
	return s.combatants.values()

func alive(c: Dictionary) -> bool:
	return not c.is_empty() and not c.dead and not c.death.dead and not has_cond(c, "banished")

func conscious(c: Dictionary) -> bool:
	return alive(c) and c.hp > 0 and not is_incapacitated(c)

func new_id(prefix: String) -> String:
	var n: int = s.next_id
	s.next_id = n + 1
	return "%s%d" % [prefix, n]

func log_line(text: String) -> void:
	s.log.append(text)
	if s.log.size() > 300:
		s.log = s.log.slice(s.log.size() - 300)
	events.append({"t": "log", "text": text})

func float_text(cid: String, text: String, color := "#ffffff") -> void:
	events.append({"t": "float", "cid": cid, "text": text, "color": color})

## sound: an Sfx name ("sword", "fire"...). Left empty, the client picks one from kind and color.
func fx(kind: String, from: Vector2i, to: Vector2i, color := "#ffffff", cells: Array = [], sound := "") -> void:
	var e = {"t": "fx", "kind": kind, "from": from, "to": to, "color": color, "cells": cells}
	if sound != "":
		e.sfx = sound
	events.append(e)

## A sound. cid (optional) names the creature it comes from, so the client can add a visual there.
func sfx(sound: String, cid := "") -> void:
	var e = {"t": "sfx", "name": sound}
	if cid != "":
		e.cid = cid
	events.append(e)

## A dice roll that clients may animate in their dice tray (each player chooses whether to see it).
## cid: who rolled; tid: who it was against ("" if no one). dice: [{"s": sides, "v": value, "off": true if dropped}].
## mod: the bonus added to the kept roll; total: the final result; result: "HIT", "MISS", "CRIT", "SUCCESS", "FAIL" or "".
## kind: "d20" (attacks, saves, checks: the client holds the next event briefly so the dice land first) or "damage".
func dice_event(cid: String, label: String, dice: Array, mod: int, total: int, result := "", tid := "", kind := "d20") -> void:
	if dice.is_empty():
		return
	events.append({"t": "dice", "cid": cid, "tid": tid, "label": label, "dice": dice, "mod": mod, "total": total,
		"result": result, "kind": kind})

## Dice-tray dice for a Dice.roll_d20 result: the roll it didn't keep (advantage / disadvantage) is marked "off".
static func d20_faces(rr: Dictionary) -> Array:
	var out: Array = []
	var kept_done := false
	for v in rr.get("rolls", [rr.get("roll", 0)]):
		var keep: bool = not kept_done and int(v) == int(rr.roll)
		if keep:
			kept_done = true
		out.append({"s": 20, "v": int(v), "off": not keep})
	return out

func nm(c: Dictionary) -> String:
	var col = "#8fd0ff" if c.get("team", "") == "party" else "#ff9c8f"
	return "[color=%s]%s[/color]" % [col, c.get("name", "?")]

## Enemies Abound: `a` regards every other creature as an enemy.
func hostile(a: Dictionary, b: Dictionary) -> bool:
	return a.team != b.team or (a.get("id", "") != b.get("id", "") and _sees_all_as_enemies(a))

func _sees_all_as_enemies(c: Dictionary) -> bool:
	for e in c.get("effects", []):
		if e.get("tag", "") == "enemies_abound":
			return true
	return false

func allies_of(c: Dictionary, include_self := true) -> Array:
	return all_combatants().filter(func(o): return alive(o) and o.team == c.team and (include_self or o.id != c.id))

func enemies_of(c: Dictionary) -> Array:
	var all_foes: bool = _sees_all_as_enemies(c)
	return all_combatants().filter(func(o): return alive(o) and (o.team != c.team or (all_foes and o.id != c.id)) and not o.get("hidden", false) and same_space(c, o))

## Sanctuary: `a` must pass a WIS save to target the warded `t` with an attack or a harmful spell.
## Returns true when `a` is turned away. (Attacking or harming an enemy ends the ward; see _break_sanctuary.)
func sanctuary_blocks(a: Dictionary, t: Dictionary) -> bool:
	if a.is_empty() or t.is_empty() or a.get("id", "") == t.get("id", ""):
		return false
	# A charmed creature can't attack its charmer or aim harmful magic at it; Calm Emotions leaves
	# a creature unwilling to harm the caster's side (no save in either case).
	if charm_blocks(a, t):
		log_line("  [color=#aaaaaa]%s can't bring itself to harm %s.[/color]" % [nm(a), nm(t)])
		return true
	if not hostile(a, t):
		return false
	for e in t.effects:
		if e.get("tag", "") == "sanctuary":
			log_line("  %s must overcome %s's Sanctuary." % [nm(a), nm(t)])
			if saving_throw(a, "wis", int(e.get("dc", 13)), C(e.get("src", "")), {"spell": true}):
				return false
			log_line("  [color=#aaaaaa]%s can't bring itself to harm %s.[/color]" % [nm(a), nm(t)])
			float_text(t.id, "Sanctuary", "#f0e6a0")
			return true
	return false

## Charmed by `t` (or by an ally of `t`, for Calm Emotions' "pacified"): `a` won't harm `t`.
func charm_blocks(a: Dictionary, t: Dictionary) -> bool:
	for e in a.get("effects", []):
		if e.get("cond", "") == "charmed" and e.get("src", "") == t.get("id", "") and not e.get("no_charm_block", false):
			return true
		if e.get("tag", "") == "pacified":
			var src = C(e.get("src", ""))
			if not src.is_empty() and src.team == t.get("team", ""):
				return true
	return false

## Sanctuary: resolve who `a` actually targets when it aims at `t`. If the ward turns it away, it picks
## a new target within `reach` (unwarded, standing foes first; any new pick may be warded too and needs
## its own save). Returns {} if no target is left, so the attack or spell is lost.
func sanctuary_target(a: Dictionary, t: Dictionary, reach: int, exclude: Array = []) -> Dictionary:
	var tried: Array = exclude.duplicate()
	var cur: Dictionary = t
	while not cur.is_empty():
		if not sanctuary_blocks(a, cur):
			return cur
		tried.append(cur.id)
		cur = _sanctuary_new_target(a, reach, tried)
		if not cur.is_empty():
			log_line("  %s turns on %s instead." % [nm(a), nm(cur)])
	log_line("  [color=#aaaaaa]%s finds no other target.[/color]" % nm(a))
	return {}

func _sanctuary_new_target(a: Dictionary, reach: int, tried: Array) -> Dictionary:
	var best: Dictionary = {}
	if reach < 0:
		return best
	var best_k := INF
	for o in enemies_of(a):
		if o.id in tried or o.id == a.id or (reach > 0 and dist(a, o) > reach) or not los(a, o):
			continue
		var k := float(dist(a, o))
		if o.hp <= 0: k += 1000.0
		for e in o.effects:
			if e.get("tag", "") == "sanctuary":
				k += 500.0
		if k < best_k:
			best_k = k
			best = o
	return best

## The warded creature attacked or harmed an enemy: its Sanctuary ends.
func _break_sanctuary(a: Dictionary, t: Dictionary) -> void:
	if a.is_empty() or t.is_empty() or a.get("id", "") == t.get("id", "") or not hostile(a, t):
		return
	for e in a.effects.duplicate():
		if e.get("tag", "") == "sanctuary":
			a.effects.erase(e)
			log_line("  %s's Sanctuary ends." % nm(a))

# ================================================================ grid

func in_bounds(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < s.w and p.y < s.h

func cell(p: Vector2i) -> int:
	if not in_bounds(p):
		return WALL
	return s.cells[p.y * s.w + p.x]

func set_cell(p: Vector2i, v: int) -> void:
	if in_bounds(p):
		s.cells[p.y * s.w + p.x] = v

func blocks_move(p: Vector2i) -> bool:
	var v = cell(p)
	return v == WALL or v == PIT

func blocks_sight(p: Vector2i) -> bool:
	return cell(p) == WALL

func is_difficult(p: Vector2i, mover: Dictionary = {}) -> bool:
	var v = cell(p)
	if v == DIFFICULT or v == WATER:
		return true
	for z in s.zones:
		if z.data.get("difficult", false) and p in z.cells:
			return true
	# Auras that make the ground around their bearer hard going for others (Warding Wind,
	# Investiture of Ice); "enemies_only" spares the bearer's allies.
	for o in all_combatants():
		if not alive(o) or o.get("id", "") == mover.get("id", "") or in_rope(o):
			continue
		for e in o.effects:
			var a: Dictionary = e.get("aura", {})
			if a.is_empty() or not a.get("difficult", false):
				continue
			if a.get("enemies_only", false) and not mover.is_empty() and not hostile(o, mover):
				continue
			for q in occupied_cells(o):
				if cheb(q, p) * 5 <= int(a.get("radius", 10)):
					return true
	return false

## Zones on cell `p` whose data sets `key` (obscure, silence, reveal...).
func zone_flag_at(p: Vector2i, key: String) -> Dictionary:
	for z in s.zones:
		if z.data.get(key, false) and p in z.cells:
			return z
	return {}

## True when any cell `c` occupies lies in a zone with data `key`.
func in_zone_flag(c: Dictionary, key: String) -> bool:
	if c.is_empty() or not c.has("pos"):
		return false
	for p in occupied_cells(c):
		if not zone_flag_at(p, key).is_empty():
			return true
	return false

## Heavily obscured (Darkness, Fog Cloud, Sleet Storm...): `o` can't see `t` if either stands in such
## a zone, unless blindsight (or, for magical darkness, truesight / Devil's Sight) cuts through it.
func obscured_between(o: Dictionary, t: Dictionary) -> bool:
	if not in_zone_flag(o, "obscure") and not in_zone_flag(t, "obscure"):
		return false
	if _has_sense(o, "blindsight"):
		return false
	var dark: bool = false
	for c in [o, t]:
		for p in occupied_cells(c):
			var z = zone_flag_at(p, "obscure")
			if not z.is_empty() and str(z.data.obscure) == "darkness":
				dark = true
	if dark and (_has_sense(o, "truesight") or "devils_sight" in o.get("invocations", [])):
		return false
	return true

func occupied_cells(c: Dictionary, at = null) -> Array:
	var p: Vector2i = c.pos if at == null else at
	var sz: int = c.get("form", {}).get("sz", c.sz) if not c.get("form", {}).is_empty() else c.sz
	var out: Array = []
	for dx in sz:
		for dy in sz:
			out.append(p + Vector2i(dx, dy))
	return out

func creature_at(p: Vector2i, exclude := "") -> Dictionary:
	for c in all_combatants():
		# Creatures up in a Rope Trick space aren't on the map.
		if c.id == exclude or not alive(c) or in_rope(c):
			continue
		if p in occupied_cells(c):
			return c
	return {}

func cheb(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))

## Distance in feet between two creatures (closest occupied cells, 5e diagonal = 5 ft).
func dist(a: Dictionary, b: Dictionary) -> int:
	var best = 9999
	for p in occupied_cells(a):
		for q in occupied_cells(b):
			best = mini(best, cheb(p, q))
	return best * 5

func dist_to_cell(a: Dictionary, p: Vector2i) -> int:
	var best = 9999
	for q in occupied_cells(a):
		best = mini(best, cheb(p, q))
	return best * 5

func center_of(c: Dictionary) -> Vector2:
	var sz = occupied_cells(c).size()
	var side = int(sqrt(sz))
	return Vector2(c.pos) + Vector2(side, side) * 0.5

## Line of sight between cell centres; walls block.
func los_cells(a: Vector2i, b: Vector2i) -> bool:
	var pa = Vector2(a) + Vector2(0.5, 0.5)
	var pb = Vector2(b) + Vector2(0.5, 0.5)
	var steps = int(ceil(pa.distance_to(pb) * 3.0))
	for i in range(1, steps):
		var p = pa.lerp(pb, float(i) / steps)
		var cp = Vector2i(floori(p.x), floori(p.y))
		if cp != a and cp != b and blocks_sight(cp):
			return false
	return true

func los(a: Dictionary, b: Dictionary) -> bool:
	if not same_space(a, b):
		return false
	for p in occupied_cells(a):
		for q in occupied_cells(b):
			if los_cells(p, q):
				return true
	return false

## Rope Trick: the id of the caster whose extradimensional space `c` is hiding in, or "" when
## it's out in the world. Nothing passes between the space and the outside: no attacks, no
## spells, no sight lines, no areas, zones or auras. Creatures do: the entrance stays open for
## the spell's duration (see s.ropes and enter_rope / exit_rope in CombatEngine).
func rope_space(c: Dictionary) -> String:
	for e in c.get("effects", []):
		if e.get("tag", "") == "rope_trick":
			return str(e.get("src", "rope"))
		# Other sealed-off spaces work the same way (Maze's demiplane, Otiluke's Resilient Sphere, Blink).
		if str(e.get("pocket", "")) != "":
			return str(e.pocket)
	return ""

func same_space(a: Dictionary, b: Dictionary) -> bool:
	return rope_space(a) == rope_space(b)

## True while `c` is up in a Rope Trick space. Its `pos` is then the rope's cell, but it isn't
## standing there: it takes up no room on the map.
func in_rope(c: Dictionary) -> bool:
	for e in c.get("effects", []):
		if e.get("tag", "") == "rope_trick":
			return true
	return false

## s.ropes holds the open Rope Tricks: {id, src (caster id), team, pos (cell the rope hangs over),
## rounds, name}. One per caster.
func ropes() -> Array:
	if not s.has("ropes"):
		s.ropes = []
	return s.ropes

func rope_of(src_id: String) -> Dictionary:
	for r in ropes():
		if str(r.get("src", "")) == src_id:
			return r
	return {}

## Everyone currently inside the Rope Trick space that `src_id` cast.
func rope_occupants(src_id: String) -> Array:
	return all_combatants().filter(func(o): return in_rope(o) and rope_space(o) == src_id)

# ================================================================ area shapes

func area_cells(origin_c: Dictionary, area: Dictionary, target_cell: Vector2i, from_self: bool) -> Array:
	var shape: String = area.get("shape", "sphere")
	var size_ft = int(area.get("size", 5))
	var out: Array = []
	var origin: Vector2 = center_of(origin_c)
	var tc = Vector2(target_cell) + Vector2(0.5, 0.5)
	match shape:
		"sphere", "cylinder":
			var r = size_ft / 5.0
			for x in range(target_cell.x - int(r) - 1, target_cell.x + int(r) + 2):
				for y in range(target_cell.y - int(r) - 1, target_cell.y + int(r) + 2):
					var p = Vector2i(x, y)
					if in_bounds(p) and (Vector2(p) + Vector2(0.5, 0.5)).distance_to(tc) <= r + 0.01:
						out.append(p)
		"cube", "square":
			var n = maxi(1, size_ft / 5)
			var x0: int
			var y0: int
			if from_self:
				var d = Vector2i(signi(target_cell.x - origin_c.pos.x), signi(target_cell.y - origin_c.pos.y))
				if d == Vector2i.ZERO:
					d = Vector2i(1, 0)
				var sz = int(sqrt(occupied_cells(origin_c).size()))
				x0 = origin_c.pos.x + sz if d.x > 0 else (origin_c.pos.x - n if d.x < 0 else origin_c.pos.x - (n - 1) / 2)
				y0 = origin_c.pos.y + sz if d.y > 0 else (origin_c.pos.y - n if d.y < 0 else origin_c.pos.y - (n - 1) / 2)
			else:
				x0 = target_cell.x - (n - 1) / 2
				y0 = target_cell.y - (n - 1) / 2
			for x in range(x0, x0 + n):
				for y in range(y0, y0 + n):
					if in_bounds(Vector2i(x, y)):
						out.append(Vector2i(x, y))
		"cone":
			var length = size_ft / 5.0
			var dir = (tc - origin).normalized()
			if dir == Vector2.ZERO:
				dir = Vector2.RIGHT
			var half_angle = atan(0.5) + 0.02
			for x in range(int(origin.x - length) - 1, int(origin.x + length) + 2):
				for y in range(int(origin.y - length) - 1, int(origin.y + length) + 2):
					var p = Vector2i(x, y)
					if not in_bounds(p) or p in occupied_cells(origin_c):
						continue
					var v = (Vector2(p) + Vector2(0.5, 0.5)) - origin
					if v.length() <= length + 0.35 and absf(v.angle_to(dir)) <= half_angle + (0.45 / maxf(v.length(), 0.5)):
						out.append(p)
		"line":
			var length2 = size_ft / 5.0
			var width = float(area.get("width", 5)) / 5.0
			var dir2 = (tc - origin).normalized()
			if dir2 == Vector2.ZERO:
				dir2 = Vector2.RIGHT
			var end = origin + dir2 * length2
			for x in range(int(minf(origin.x, end.x)) - 1, int(maxf(origin.x, end.x)) + 2):
				for y in range(int(minf(origin.y, end.y)) - 1, int(maxf(origin.y, end.y)) + 2):
					var p = Vector2i(x, y)
					if not in_bounds(p) or p in occupied_cells(origin_c):
						continue
					var cpt = Vector2(p) + Vector2(0.5, 0.5)
					var closest = Geometry2D.get_closest_point_to_segment(cpt, origin, end)
					if cpt.distance_to(closest) <= width * 0.5 + 0.08:
						out.append(p)
		"wall":
			# A wall centred on the chosen point, running across the caster's line of sight to it
			# (Wall of Fire, Blade Barrier, Tidal Wave). area.width is its thickness (default 5 ft).
			var half_len: float = size_ft / 10.0
			var thick: float = float(area.get("width", 5)) / 5.0
			var los_dir = (tc - origin).normalized()
			if los_dir == Vector2.ZERO:
				los_dir = Vector2.RIGHT
			var along = Vector2(-los_dir.y, los_dir.x)
			var a0 = tc - along * half_len
			var a1 = tc + along * half_len
			var reach_c: int = int(half_len + thick) + 2
			for x in range(target_cell.x - reach_c, target_cell.x + reach_c + 1):
				for y in range(target_cell.y - reach_c, target_cell.y + reach_c + 1):
					var p = Vector2i(x, y)
					if not in_bounds(p):
						continue
					var cpt = Vector2(p) + Vector2(0.5, 0.5)
					var closest = Geometry2D.get_closest_point_to_segment(cpt, a0, a1)
					if cpt.distance_to(closest) <= thick * 0.5 + 0.08:
						out.append(p)
		"emanation", "aura", "radius":
			var r2 = size_ft / 5
			var occ = occupied_cells(origin_c)
			for x in range(origin_c.pos.x - r2, origin_c.pos.x + r2 + int(sqrt(occ.size()))):
				for y in range(origin_c.pos.y - r2, origin_c.pos.y + r2 + int(sqrt(occ.size()))):
					var p = Vector2i(x, y)
					if in_bounds(p) and not p in occ:
						out.append(p)
	# Walls stop areas: drop cells without line of effect from the origin point.
	var src_cell = target_cell if (shape in ["sphere", "cylinder", "wall"] or (shape in ["cube", "square"] and not from_self)) else Vector2i(floori(origin.x), floori(origin.y))
	return out.filter(func(p): return not blocks_sight(p) and los_cells(src_cell, p))

func creatures_in_cells(cells: Array, exclude_id := "") -> Array:
	var out: Array = []
	for c in all_combatants():
		# Areas fill the world, not a Rope Trick space hanging above it.
		if c.id == exclude_id or not alive(c) or rope_space(c) != "":
			continue
		for p in occupied_cells(c):
			if p in cells:
				out.append(c)
				break
	return out

# ================================================================ effects

func effects_named(c: Dictionary, tag: String) -> Array:
	return c.effects.filter(func(e): return e.get("tag", "") == tag)

func has_tag(c: Dictionary, tag: String) -> bool:
	for e in c.effects:
		if e.get("tag", "") == tag:
			return true
	return false

func has_cond(c: Dictionary, cond: String) -> bool:
	if c.is_empty():
		return false
	if cond == "unconscious" and c.get("kind", "") == "pc" and c.hp <= 0 and not c.death.dead:
		return true
	if cond == "prone" and has_cond(c, "unconscious") and c.hp <= 0:
		return true
	# Faerie Fire, Branding Smite, Sickening Radiance: the creature can't benefit from being invisible.
	if cond == "invisible" and (mod_any(c, "no_invisible") or in_zone_flag(c, "reveal")):
		return false
	for e in c.effects:
		if e.get("cond", "") == cond:
			return true
	return false

func is_incapacitated(c: Dictionary) -> bool:
	if c.hp <= 0 and c.get("kind", "") == "pc":
		return true
	for e in c.effects:
		if e.get("cond", "") in ["incapacitated", "paralyzed", "stunned", "unconscious", "petrified", "banished"]:
			return true
	return false

func mod_sum(c: Dictionary, key: String) -> float:
	var t = 0.0
	for e in c.effects:
		var m: Dictionary = e.get("mods", {})
		if m.has(key) and (m[key] is int or m[key] is float):
			t += float(m[key])
	return t

func mod_any(c: Dictionary, key: String) -> bool:
	for e in c.effects:
		if e.get("mods", {}).get(key, false):
			return true
	return false

func mod_list(c: Dictionary, key: String) -> Array:
	var out: Array = []
	for e in c.effects:
		var m: Dictionary = e.get("mods", {})
		if m.has(key):
			out.append(m[key])
	return out

func add_effect(t: Dictionary, e: Dictionary) -> Dictionary:
	var cond: String = e.get("cond", "")
	if cond != "" and (cond in t.get("cond_immune", []) or _effect_cond_immune(t, cond)):
		log_line("%s is immune to being %s." % [nm(t), cond])
		return {}
	if cond == "frightened" and _aura_of_courage(t):
		log_line("%s is protected from fear by an Aura of Courage." % nm(t))
		return {}
	if cond == "frightened" and has_tag(t, "heroism"):
		return {}
	if cond == "charmed" and _aura_of_devotion(t):
		log_line("%s is protected from charm by an Aura of Devotion." % nm(t))
		return {}
	# Protection from Evil and Good: no charm or fear from the listed creature types.
	if cond != "":
		var from = C(str(e.get("src", "")))
		for v in mod_list(t, "cond_immune_vs"):
			if v is Dictionary and cond in v.get("conds", []) and str(from.get("type", "")) in v.get("types", []):
				log_line("%s is protected from being %s." % [nm(t), cond])
				return {}
	var exh_level: bool = float(e.get("mods", {}).get("exhaustion", 0)) > 0
	if exh_level and "exhaustion" in t.get("cond_immune", []):
		log_line("%s is immune to exhaustion." % nm(t))
		return {}
	if not e.has("eid"):
		e.eid = new_id("e")
	if not e.has("mods"):
		e.mods = {}
	# Same named effect from the same source refreshes instead of stacking. Exhaustion levels
	# are one effect each and do stack.
	if not exh_level:
		for old in t.effects.duplicate():
			if old.get("name", "") == e.get("name", "") and old.get("src", "") == e.get("src", "") and e.get("name", "") != "":
				t.effects.erase(old)
	t.effects.append(e)
	if exh_level:
		_apply_exhaustion(t)
	# An incapacitated creature loses concentration (stunned, paralysed, asleep, banished...).
	if cond in ["incapacitated", "paralyzed", "stunned", "unconscious", "petrified", "banished"] and not t.get("conc", {}).is_empty() \
			and not (e.get("src", "") == t.id and e.get("spell", "") == t.conc.get("spell", "")):
		log_line("  %s is incapacitated and loses concentration." % nm(t))
		end_concentration(t, true)
	if e.get("tag", "") == "dominated":
		refresh_teams()
	if cond == "prone":
		float_text(t.id, "Prone", "#e0c060")
	elif cond != "":
		float_text(t.id, cond.capitalize(), "#e0a0ff")
	return e

## Condition immunity granted by an effect (Freedom of Movement: "cond_immune": [...]).
func _effect_cond_immune(t: Dictionary, cond: String) -> bool:
	for v in mod_list(t, "cond_immune"):
		if v is Array and cond in v:
			return true
	return false

func remove_effect(t: Dictionary, eid: String) -> void:
	for e in t.effects.duplicate():
		if e.eid == eid:
			t.effects.erase(e)
			if e.get("form_effect", false):
				end_wild_shape(t)

func remove_effects_where(t: Dictionary, pred: Callable) -> void:
	for e in t.effects.duplicate():
		if pred.call(e):
			t.effects.erase(e)

func end_concentration(c: Dictionary, quiet := false) -> void:
	if c.conc.is_empty():
		return
	var sp: String = c.conc.get("spell", "")
	if not quiet:
		log_line("%s loses concentration on %s." % [nm(c), c.conc.get("name", sp)])
	var held: Dictionary = c.conc
	c.conc = {}
	_on_spell_end(c, sp, held)
	for o in all_combatants():
		for e in o.effects.duplicate():
			if e.get("conc", false) and e.get("src", "") == c.id and e.get("spell", "") == sp:
				o.effects.erase(e)
				if e.get("form_effect", false):
					end_wild_shape(o)
	s.zones = s.zones.filter(func(z): return not (z.get("conc", false) and z.src == c.id and z.spell == sp))
	_end_conc_summons(c, sp)
	refresh_teams()

## Hook for spells that do something when they end (Delayed Blast Fireball detonates). `held` is the
## caster's concentration record at the moment it ended ({} for spells without concentration).
func _on_spell_end(_c: Dictionary, _sp: String, _held: Dictionary) -> void:
	pass

## Dominated creatures fight for whoever dominates them: their team follows the "dominated" effect
## and goes back to their own side when it ends.
func refresh_teams() -> void:
	for o in all_combatants():
		var boss: String = ""
		for e in o.get("effects", []):
			if e.get("tag", "") == "dominated":
				var src = C(str(e.get("src", "")))
				if not src.is_empty() and alive(src):
					boss = src.get("base_team", src.team)
		if boss != "":
			if not o.has("base_team"):
				o.base_team = o.team
			if o.team != boss:
				o.team = boss
				log_line("  %s now fights for the other side." % nm(o))
		elif o.has("base_team"):
			if o.team != o.base_team:
				o.team = o.base_team
				log_line("  %s is no longer dominated." % nm(o))
			o.erase("base_team")

## Creatures a concentration spell keeps in being (Animate Objects) are gone when it ends.
func _end_conc_summons(c: Dictionary, sp: String) -> void:
	for o in all_combatants():
		if o.get("conc_summon", "") == c.id + ":" + sp and not o.dead:
			o.dead = true
			drop_held_stones(o)
			log_line("  %s falls lifeless." % nm(o))

# ---------------------------------------------------------------- items on the ground
# s.items holds loose objects lying on the map: {id, kind, pos, name, src, ...}. Magic stones are the
# only kind so far; one carried by a creature is a "magic_stone" effect on it instead (see Magic Stone).

func ground_items() -> Array:
	if not s.has("items"):
		s.items = []
	return s.items

## Magic stones lying in cell `p`.
func stones_at(p: Vector2i) -> Array:
	return ground_items().filter(func(it): return it.get("kind", "") == "magic_stone" and it.pos == p)

## Put one magic stone carried in effect `e` down in cell `p` (the effect loses a use).
func put_stone_down(holder: Dictionary, e: Dictionary, p: Vector2i) -> void:
	ground_items().append({"id": new_id("i"), "kind": "magic_stone", "name": "Magic Stone", "pos": p, "src": e.get("src", ""),
		"spell": e.get("spell", "magic_stone"), "attack": int(e.attack), "dice": str(e.dice), "rounds": int(e.get("rounds", 10))})
	e.uses = int(e.uses) - 1
	if int(e.uses) <= 0:
		holder.effects.erase(e)

## A creature that dies, falls unconscious or stops existing lets go of the stones it carries.
func drop_held_stones(o: Dictionary) -> void:
	for e in o.get("effects", []).duplicate():
		if e.get("tag", "") != "magic_stone":
			continue
		var n: int = int(e.uses)
		for i in n:
			put_stone_down(o, e, o.pos)
		log_line("  %s drops %d magic stone%s." % [nm(o), n, "" if n == 1 else "s"])

## Summons made by one casting of a timed, non-concentration spell (Tiny Servant) end together.
func _end_summon_group(group: String) -> void:
	for o in all_combatants():
		if o.get("summon_group", "") == group and not o.dead:
			o.dead = true
			drop_held_stones(o)
			log_line("  %s goes still, an ordinary object again." % nm(o))

func start_concentration(c: Dictionary, spell_id: String, name: String) -> void:
	if not c.conc.is_empty():
		end_concentration(c)
	c.conc = {"spell": spell_id, "name": name}

## Tick effect durations at the start/end of `cid`'s turn.
func tick_effects(cid: String, when: String) -> void:
	for o in all_combatants():
		for e in o.effects.duplicate():
			if e.get("tick_cid", "") == cid and e.get("tick_on", "start") == when:
				e.rounds = int(e.get("rounds", 1)) - 1
				if e.rounds <= 0:
					o.effects.erase(e)
					if e.get("form_effect", false):
						end_wild_shape(o)
					if e.get("conc", false) and not e.get("outlived", false):
						var src = C(e.get("src", ""))
						if not src.is_empty() and src.conc.get("spell", "") == e.get("spell", ""):
							_end_conc_summons(src, str(e.get("spell", "")))
							var held: Dictionary = src.conc
							src.conc = {}
							_on_spell_end(src, str(e.get("spell", "")), held)
					if e.get("tag", "") == "dominated":
						refresh_teams()
					if e.get("summon_group", "") != "":
						_end_summon_group(str(e.summon_group))
					if e.get("name", "") != "":
						log_line("%s: %s ends." % [nm(o), e.name])

func _aura_of_courage(t: Dictionary) -> bool:
	for p in allies_of(t):
		if p.features.has("aura_of_courage") and conscious(p) and dist(p, t) <= (30 if p.class_levels.get("paladin", 0) >= 18 else 10):
			return true
	return false

## Aura of Devotion (Oath of Devotion 7th level): the paladin and friendly creatures within 10 ft
## (30 ft at 18th) can't be charmed while the paladin is conscious.
func _aura_of_devotion(t: Dictionary) -> bool:
	for p in allies_of(t):
		if p.features.has("aura_of_devotion") and conscious(p) and dist(p, t) <= (30 if p.class_levels.get("paladin", 0) >= 18 else 10):
			return true
	return false

func end_wild_shape(c: Dictionary) -> void:
	if c.form.is_empty():
		return
	log_line("%s returns to their normal form." % nm(c))
	c.form = {}
	remove_effects_where(c, func(e): return e.get("tag", "") == "wild_shape")

# ================================================================ derived numbers

func eff_ac(c: Dictionary) -> int:
	var base: int = c.ac
	if not c.form.is_empty():
		base = c.form.ac
	for v in mod_list(c, "set_ac"):
		base = maxi(base, int(v) + (2 if c.get("has_shield", false) else 0))
	var ac: int = base + int(mod_sum(c, "ac"))
	# Barkskin: AC can't be less than the floor, whatever armor is worn.
	for v in mod_list(c, "min_ac"):
		ac = maxi(ac, int(v))
	return ac

func eff_speed(c: Dictionary) -> int:
	var sp: int = c.speed if c.form.is_empty() else c.form.speed
	if not mod_any(c, "no_fly"):
		sp = maxi(sp, int(mod_sum(c, "fly")))  # the Fly spell's flying speed
	sp += int(mod_sum(c, "speed"))
	# Carrying too much (Inventory.encumbrance: the variant rule's -10 / -20 ft; over capacity, 5 ft or none).
	var enc: Dictionary = Inventory.encumbrance_of(s, c) if c.form.is_empty() else {}
	sp += int(enc.get("speed", 0))
	if enc.has("max_speed"):
		sp = mini(sp, int(enc.max_speed))
	var mult = 1.0
	for v in mod_list(c, "speed_mult"):
		mult *= float(v)
	for a in _auras_affecting(c):
		if a.aura.has("speed_mult"):
			mult *= float(a.aura.speed_mult)
	sp = int(sp * mult)
	# Power Word Pain: no faster than 10 ft.
	for v in mod_list(c, "max_speed"):
		sp = mini(sp, int(v))
	# Exhaustion (Sickening Radiance): level 2 halves speed, level 5 drops it to 0.
	var exh: int = exhaustion(c)
	if exh >= 5:
		return 0
	if exh >= 2:
		sp = sp / 2
	for cond in ["grappled", "restrained", "paralyzed", "stunned", "unconscious", "petrified"]:
		if has_cond(c, cond):
			return 0
	return maxi(0, sp)

## Exhaustion level from effects (each carries mods.exhaustion = 1 per level).
func exhaustion(c: Dictionary) -> int:
	return int(mod_sum(c, "exhaustion"))

## Hit point maximum after exhaustion: level 4 halves it.
func eff_max_hp(c: Dictionary) -> int:
	var mx: int = int(c.max_hp)
	return mx / 2 if exhaustion(c) >= 4 else mx

## Consequences of a new exhaustion level: at 4 the HP maximum halves (current HP drops to fit),
## at 6 the creature dies.
func _apply_exhaustion(t: Dictionary) -> void:
	var lv: int = exhaustion(t)
	log_line("  %s now has %d level%s of exhaustion." % [nm(t), lv, "" if lv == 1 else "s"])
	if lv >= 6 and alive(t):
		if t.get("kind", "") == "pc":
			_kill(t, "exhaustion")
		else:
			t.hp = 0
			t.dead = true
			log_line("  [color=#ff5050]%s dies of exhaustion![/color]" % nm(t))
		return
	if int(t.hp) > eff_max_hp(t):
		t.hp = eff_max_hp(t)

## Remove one level of exhaustion (a long rest, Greater Restoration). Returns true if one was removed.
func remove_exhaustion_level(t: Dictionary) -> bool:
	for i in range(t.effects.size() - 1, -1, -1):
		var e: Dictionary = t.effects[i]
		if float(e.get("mods", {}).get("exhaustion", 0)) > 0:
			t.effects.remove_at(i)
			return true
	return false

func _auras_affecting(t: Dictionary) -> Array:
	var out: Array = []
	for o in all_combatants():
		if not alive(o) or not same_space(o, t):
			continue
		for e in o.effects:
			var a: Dictionary = e.get("aura", {})
			if a.is_empty():
				continue
			# Most auras work on others; a few also on their source (Twilight Sanctuary: "you or a creature").
			if o.id == t.id and not a.get("include_self", false):
				continue
			if a.get("enemies_only", false) and not hostile(o, t):
				continue
			if a.get("allies_only", false) and hostile(o, t):
				continue
			if dist(o, t) <= int(a.get("radius", 10)):
				out.append({"src": o, "aura": a, "effect": e})
	return out

func ability_mod(c: Dictionary, ab: String) -> int:
	if not c.form.is_empty() and ab in ["str", "dex", "con"]:
		return Rules.mod(int(c.form.scores.get(ab, 10)))
	return int(c.mods.get(ab, 0))

func caster_entry(c: Dictionary, class_id: String) -> Dictionary:
	for e in c.casting:
		if e["class"] == class_id:
			return e
	return c.casting[0] if c.casting.size() > 0 else {}

func best_spell_dc(c: Dictionary) -> int:
	var best = 10
	for e in c.casting:
		best = maxi(best, int(e.dc))
	return best

# ================================================================ advantage

## Net advantage for `a` attacking `t`: +1 advantage, -1 disadvantage, 0 straight.
func attack_advantage(a: Dictionary, t: Dictionary, melee: bool, atk: Dictionary = {}) -> int:
	var adv = false
	var dis = false
	var d = dist(a, t)
	if mod_any(a, "advantage_attack"): adv = true
	if mod_any(t, "grants_advantage"): adv = true
	# An unseen attacker has advantage, unless the target sees invisible things (blindsight, truesight).
	if (has_cond(a, "invisible") and not _sees_invisible(t)) or a.get("hidden", false): adv = true
	for cond in ["blinded", "paralyzed", "restrained", "stunned", "unconscious", "petrified"]:
		if has_cond(t, cond): adv = true
	if has_cond(t, "prone"):
		if d <= 5: adv = true
		else: dis = true
	if a.get("toggles", {}).get("reckless", false) and melee: adv = true
	if has_tag(t, "reckless_target"): adv = true
	if has_tag(a, "fighting_spirit"): adv = true
	if a.tags.has("pack_tactics") or a.tags.has("pack_tactics_true"):
		for o in allies_of(a, false):
			if conscious(o) and dist(o, t) <= 5:
				adv = true
				break
	if melee:
		for o in allies_of(a, false):
			if o.features.has("totem_spirit_wolf") and has_tag(o, "rage") and dist(o, t) <= 5:
				adv = true
	for e in t.effects:
		if e.get("tag", "") in ["vow_of_enmity", "true_strike", "helped", "distracted"] and e.get("src", "") in [a.id, "*"]:
			adv = true
		if e.get("tag", "") in ["helped", "distracted"] and e.get("for_team", "") == a.team:
			adv = true
	if a.features.has("assassinate") and not t.get("acted", false) and s.round <= 1: adv = true
	# Disadvantage.
	if mod_any(a, "disadvantage_attack"): dis = true
	if mod_any(t, "grants_disadvantage") or has_tag(t, "dodge"): dis = true
	# Protection from Evil and Good: only some creature types attack at disadvantage.
	for v in mod_list(t, "grants_disadvantage_vs"):
		if v is Array and str(a.get("type", "")) in v:
			dis = true
	for cond in ["blinded", "frightened", "poisoned", "prone", "restrained"]:
		if has_cond(a, cond): dis = true
	if (has_cond(t, "invisible") and not _sees_invisible(a)) or t.get("hidden", false): dis = true
	# Cloak of Displacement: attacks against the wearer have disadvantage, unless it was hurt since its last
	# turn began, or is incapacitated, restrained or unable to move.
	if t.get("tags", {}).has("displacement") and not t.get("displace_off", false) and not is_incapacitated(t) \
			and not has_cond(t, "restrained") and eff_speed(t) > 0:
		dis = true
	if not melee:
		if not a.get("feats", []).has("crossbow_expert"):
			for o in enemies_of(a):
				if conscious(o) and dist(o, a) <= 5:
					dis = true
					break
		var normal: int = atk.get("range", 0)
		if normal > 0 and d > normal and not a.get("feats", []).has("sharpshooter"): dis = true
	for e in a.effects:
		if e.get("tag", "") in ["ancestral_mark", "guardian_mark", "goaded"] and e.get("src", "") != t.id:
			dis = true
		# Compelled Duel: disadvantage against anyone but the caster.
		if e.get("mods", {}).get("dis_unless_src", false) and e.get("src", "") != t.id:
			dis = true
	# Investiture of Wind: ranged weapon attacks against the creature have disadvantage.
	if not melee and not atk.get("spell_attack", false) and mod_any(t, "grants_disadvantage_ranged"):
		dis = true
	# Exhaustion level 3+: disadvantage on attack rolls.
	if exhaustion(a) >= 3:
		dis = true
	# Armor worn without proficiency: disadvantage on attack rolls that use STR or DEX.
	# Heavily encumbered (variant rule): disadvantage on attack rolls that use STR, DEX or CON.
	if Inventory.encumbrance_of(s, a).get("dis", false) and str(atk.get("ability", "str")) in ["str", "dex", "con"]:
		dis = true
	if a.get("armor_unproficient", false) and not atk.get("spell_attack", false) and str(atk.get("ability", "str")) in ["str", "dex"]:
		dis = true
	# Heavy obscurement: an unseen target is attacked at disadvantage, an unseen attacker gains
	# advantage, so two creatures that can't see each other roll normally.
	if obscured_between(a, t):
		dis = true
	if obscured_between(t, a):
		adv = true
	if adv and not dis: return 1
	if dis and not adv: return -1
	return 0

func hit_chance(to_hit: int, ac: int, adv: int) -> float:
	var need = clampi(ac - to_hit, 2, 20)
	var p = (21.0 - need) / 20.0
	if adv > 0: p = 1.0 - (1.0 - p) * (1.0 - p)
	elif adv < 0: p = p * p
	return clampf(p, 0.05, 0.95)

func save_chance(c: Dictionary, ability: String, dc: int) -> float:
	var need = dc - int(c.save_bonus.get(ability, 0))
	return clampf((21.0 - need) / 20.0, 0.05, 0.95)

# ================================================================ helpers for reactions

func can_react(c: Dictionary) -> bool:
	return conscious(c) and c.get("turn", {}).get("reaction", true) and not mod_any(c, "no_reactions")

## True while it is `c`'s own turn in combat.
func is_current(c: Dictionary) -> bool:
	return s.in_combat and not s.order.is_empty() and s.order[clampi(int(s.turn), 0, s.order.size() - 1)] == c.get("id", "")

## Reaction spells (Shield, Hellish Rebuke, ...). A creature that cast a bonus-action spell
## on its own turn can cast nothing but action cantrips for the rest of that turn.
func can_react_spell(c: Dictionary) -> bool:
	if not can_react(c):
		return false
	if mod_any(c, "no_spells") or in_zone_flag(c, "silence"):
		return false
	return not (is_current(c) and c.get("turn", {}).get("cast_bonus", false))

const SIZE_RANK := {"tiny": 0, "small": 1, "medium": 2, "large": 3, "huge": 4, "gargantuan": 5}

## Size category as a number (tiny 0 ... gargantuan 5).
func size_rank(c: Dictionary) -> int:
	if not c.get("form", {}).is_empty() and c.form.has("size"):
		return int(SIZE_RANK.get(str(c.form.size), 2))
	if c.has("size"):
		return int(SIZE_RANK.get(str(c.size), 2))
	var sz: int = int(c.get("sz", 1))
	return 2 if sz <= 1 else mini(5, sz + 1)

func _has_sense(c: Dictionary, sense: String) -> bool:
	return str(c.get("senses", "")).to_lower().contains(sense)

## Whether `o` perceives invisible creatures (blindsight or truesight; a blinded creature only by blindsight).
func _sees_invisible(o: Dictionary) -> bool:
	if has_cond(o, "blinded"):
		return _has_sense(o, "blindsight")
	return _has_sense(o, "blindsight") or _has_sense(o, "truesight")

## Whether `o` can see `t` (blindness, invisibility, hiding; blindsight and truesight help).
func can_see(o: Dictionary, t: Dictionary) -> bool:
	if has_cond(o, "blinded") and not _has_sense(o, "blindsight"):
		return false
	if has_cond(t, "invisible") and not (_has_sense(o, "blindsight") or _has_sense(o, "truesight")):
		return false
	if obscured_between(o, t):
		return false
	if t.get("hidden", false) and hostile(o, t):
		return false
	return true

func use_reaction(c: Dictionary) -> void:
	if not c.has("turn") or c.turn.is_empty():
		c.turn = {"reaction": true}
	c.turn.reaction = false

func res_left(c: Dictionary, id: String) -> int:
	return int(c.resources.get(id, {}).get("cur", 0))

func spend_res(c: Dictionary, id: String, n := 1) -> bool:
	if res_left(c, id) < n:
		return false
	c.resources[id].cur = res_left(c, id) - n
	return true

func knows_spell(c: Dictionary, sid: String) -> bool:
	for e in c.casting:
		if sid in e.get("spells", []) or sid in e.get("at_will", []):
			return true
	return false

## Lowest available slot level >= lv (0 if none). Includes pact slots.
func lowest_slot(c: Dictionary, lv: int) -> int:
	for i in range(maxi(lv, 1) - 1, c.slots_max.size()):
		if int(c.slots_max[i]) - int(c.slots_used[i]) > 0:
			return i + 1
	if c.pact_max - c.pact_used > 0 and c.pact_level >= lv:
		return c.pact_level
	return 0

func spend_slot(c: Dictionary, lv: int) -> bool:
	if lv <= 0:
		return true
	if lv - 1 < c.slots_max.size() and int(c.slots_max[lv - 1]) - int(c.slots_used[lv - 1]) > 0:
		c.slots_used[lv - 1] = int(c.slots_used[lv - 1]) + 1
		return true
	if c.pact_level == lv and c.pact_max - c.pact_used > 0:
		c.pact_used += 1
		return true
	return false

func slots_free(c: Dictionary, lv: int) -> int:
	var n = 0
	if lv - 1 < c.slots_max.size() and lv >= 1:
		n += int(c.slots_max[lv - 1]) - int(c.slots_used[lv - 1])
	if c.pact_level == lv:
		n += c.pact_max - c.pact_used
	return n

# ================================================================ roll-fixing choices

## Abilities a player decides to use after seeing a roll. In 5e the choice is theirs, so a player's
## character asks first; a player can switch any of them to "automatic" (c.toggles.auto_fix[id]).
## Monsters, characters the AI plays and unconscious ones always use the automatic rules below, which
## only spend an ability when it turns the roll around.
const FIX_NAMES := {
	"lucky": "Lucky", "indomitable": "Indomitable", "bardic_inspiration": "Bardic Inspiration",
	"emboldening_bond": "Emboldening Bond", "flash_of_genius": "Flash of Genius", "guided_strike": "Guided Strike",
	"favored_by_the_gods": "Favored by the Gods", "precision": "Precision Attack",
}

## The Session turns this on while it resolves a request, so questions can be asked. Off (the default),
## every roll-fixing ability is automatic, which is what the AI, the tests and scripted fights want.
var fix_ask := false
## Answers already given to this request's questions, in the order they were asked. The Session rolls the
## request back when a question has no answer yet and runs it again with the answer added; the dice are
## the same each time, so the question comes back in the same place.
var fix_answers: Array = []
var fix_n := 0
## The first question that had no answer: {cid, key, title, detail, answers}. Once set, the rest of this
## run is a throwaway (every later question just gets "no").
var fix_wait: Dictionary = {}

## The ids of the roll-fixing abilities `c` can have (the setting menu lists them).
static func fix_owned(c: Dictionary) -> Array:
	var out: Array = []
	var res: Dictionary = c.get("resources", {})
	var feats: Dictionary = c.get("features", {})
	if res.has("lucky"): out.append("lucky")
	if res.has("indomitable"): out.append("indomitable")
	if res.has("flash_of_genius"): out.append("flash_of_genius")
	if feats.has("guided_strike"): out.append("guided_strike")
	if res.has("favored_by_the_gods"): out.append("favored_by_the_gods")
	if "precision" in c.get("maneuvers", []): out.append("precision")
	# Anyone can be handed these by an ally.
	out.append("bardic_inspiration")
	out.append("emboldening_bond")
	return out

## Does `c` have this ability ready to use right now?
func fix_ready(c: Dictionary, id: String) -> bool:
	match id:
		"lucky", "indomitable", "flash_of_genius", "favored_by_the_gods":
			return res_left(c, id) > 0
		"guided_strike":
			return c.features.has("guided_strike") and res_left(c, "channel_divinity") > 0
		"precision":
			return "precision" in c.get("maneuvers", []) and res_left(c, "superiority") > 0
		"bardic_inspiration":
			return has_tag(c, "bardic_inspiration")
		"emboldening_bond":
			return _bond_available(c)
	return false

## True when `c` is a player's character who gets asked before `id` is used.
func fix_manual(c: Dictionary, id: String) -> bool:
	return fix_ask and c.get("kind", "") == "pc" and not c.get("ai", false) and conscious(c) \
		and not bool(c.get("toggles", {}).get("auto_fix", {}).get(id, false))

## Is there any player's character who might be asked something? (The Session only keeps a snapshot to
## roll back to when this is true.)
func fix_any_manual() -> bool:
	for c in all_combatants():
		if c.get("kind", "") != "pc" or c.get("ai", false) or not conscious(c):
			continue
		for id in FIX_NAMES:
			if fix_ready(c, id) and not bool(c.get("toggles", {}).get("auto_fix", {}).get(id, false)):
				return true
	return false

## Should `c` use `id` now? For an automatic user that is `auto_rule` (the old behaviour: use it when it
## turns the roll around). For a player's character it is their answer, asked with `detail` as context.
func fix_use(c: Dictionary, id: String, auto_rule: bool, detail: String) -> bool:
	if not fix_manual(c, id):
		return auto_rule
	if fix_n < fix_answers.size():
		fix_n += 1
		return bool(fix_answers[fix_n - 1])
	if fix_wait.is_empty():
		fix_wait = {"cid": c.id, "key": id, "answers": fix_answers.duplicate(),
			"title": "%s: use %s?" % [c.name, FIX_NAMES[id]], "detail": detail}
	return false

## The result of using a roll-fixing ability: an automatic user always stops there (as before); a player's
## character stops only if the roll now succeeds and otherwise may try another ability.
## Returns {} to carry on.
func _fix_result(c: Dictionary, id: String, ok: bool, notes: PackedStringArray, out: Dictionary) -> Dictionary:
	if ok or not fix_manual(c, id):
		out.note = ", ".join(notes)
		return out
	return {}

# ================================================================ saving throws

## Returns true on success. src may be {} for environmental effects.
func saving_throw(t: Dictionary, ability: String, dc: int, src: Dictionary, opts := {}) -> bool:
	var spell: bool = opts.get("spell", false)
	var magic: bool = spell or opts.get("magic", false)
	if ability in ["str", "dex"]:
		for cond in ["paralyzed", "stunned", "unconscious", "petrified"]:
			if has_cond(t, cond):
				log_line("  %s automatically fails the %s save (%s)." % [nm(t), ability.to_upper(), cond])
				return _legendary_or_fail(t)
	var adv = false
	var dis = false
	if t.tags.has("magic_resistance") and magic: adv = true
	if t.tags.has("gnome_cunning") and magic and ability in ["int", "wis", "cha"]: adv = true
	if ability == "dex" and t.features.has("danger_sense") and not has_cond(t, "blinded"): adv = true
	if ability == "str" and has_tag(t, "rage"): adv = true
	if ability == "dex" and has_tag(t, "dodge"): adv = true
	if ability == "dex" and has_cond(t, "restrained"): dis = true
	var cc: String = opts.get("cond", "")
	if cc == "charmed" and t.tags.has("fey_ancestry"): adv = true
	if cc == "frightened" and t.tags.has("brave"): adv = true
	if (cc == "poisoned" or opts.get("dmg_type", "") == "poison") and t.tags.has("dwarven_resilience"): adv = true
	if opts.get("concentration", false) and (t.get("feats", []).has("war_caster") or "eldritch_mind" in t.get("invocations", [])): adv = true
	if opts.get("heightened", false) or opts.get("dis", false): dis = true
	# Armor or a shield worn without proficiency: disadvantage on STR and DEX saves.
	if ability in ["str", "dex"] and t.get("armor_unproficient", false): dis = true
	if ability in ["str", "dex", "con"] and Inventory.encumbrance_of(s, t).get("dis", false): dis = true
	# Antitoxin: advantage on saves against poison.
	if (cc == "poisoned" or opts.get("dmg_type", "") == "poison") and mod_any(t, "poison_save_adv"): adv = true
	# Effects granting advantage on some saves (Beacon of Hope: WIS; Circle of Power: against spells).
	for v in mod_list(t, "save_adv"):
		if v is Array and ability in v:
			adv = true
	if spell and mod_any(t, "save_adv_spell"): adv = true
	# Disadvantage on some saves (Power Word Pain, Reduce, Blinding Sickness); exhaustion 3+ on all.
	for v in mod_list(t, "save_dis"):
		if v is Array and ability in v:
			dis = true
	if exhaustion(t) >= 3: dis = true
	# Silvery Barbs' gift: advantage on the next roll.
	for e in t.effects:
		if e.get("one_roll", false):
			adv = true
	remove_effects_where(t, func(e): return e.get("one_roll", false))
	var a = 1 if adv and not dis else (-1 if dis and not adv else 0)
	var bonus = int(t.save_bonus.get(ability, 0))
	if not t.form.is_empty() and ability in ["str", "dex", "con"]:
		bonus = ability_mod(t, ability)
	bonus += _aura_of_protection(t)
	if opts.get("concentration", false) and has_tag(t, "bladesong"):
		bonus += maxi(1, int(t.mods.int))
	var extra = ""
	for dexp in mod_list(t, "save_dice"):
		var r: int = Dice.roll(str(dexp)).total
		bonus += r
		extra += " +%d" % r
	for dexp in mod_list(t, "save_penalty_dice"):
		var r: int = Dice.roll(str(dexp)).total
		bonus -= r
		extra += " -%d" % r
	# One-shot save modifiers (Resistance cantrip, Mind Sliver).
	remove_effects_where(t, func(e): return e.get("one_save", false))
	var rr = Dice.roll_d20(a, t.tags.has("halfling_lucky"))
	var total: int = int(rr.roll) + bonus
	var ok = total >= dc
	var how = " (adv)" if a > 0 else (" (dis)" if a < 0 else "")
	var line = "  %s %s save: %d%s = %d vs DC %d" % [nm(t), ability.to_upper(), rr.roll, how, total, dc]
	if not ok:
		var res = _save_helpers(t, ability, dc, total, a, bonus)
		ok = res.ok
		total = res.total
		if res.note != "":
			line += " → " + res.note + " = %d" % total
	elif not src.is_empty() and hostile(src, t) and spell and _silvery_barbs(t, src, 60):
		var r3 = Dice.roll_d20(a)
		var low: int = mini(int(r3.roll) + bonus, total)
		line += " → Silvery Barbs forces a reroll: %d" % low
		total = low
		ok = total >= dc
	elif not src.is_empty() and hostile(src, t):
		# Chronurgist allies of the caster can force an enemy to reroll a successful save.
		for p in allies_of(src):
			if p.features.has("chronal_shift") and can_react(p) and res_left(p, "chronal_shift") > 0 and dist(p, t) <= 30 and opts.get("spell", false):
				spend_res(p, "chronal_shift")
				use_reaction(p)
				var r2 = Dice.roll_d20(a)
				total = int(r2.roll) + bonus
				ok = total >= dc
				line += " → %s's Chronal Shift forces a reroll: %d" % [nm(p), total]
				break
	line += "  [color=%s]%s[/color]" % ["#7fdc7f" if ok else "#ff7f7f", "SUCCESS" if ok else "FAIL"]
	dice_event(t.id, "%s save · DC %d" % [ability.to_upper(), dc], d20_faces(rr), bonus, total, "SUCCESS" if ok else "FAIL", str(src.get("id", "")))
	log_line(line)
	if not ok:
		return _legendary_or_fail(t)
	return true

## Silvery Barbs (reaction, 60 ft): a creature hostile to `roller` that knows the spell spends a slot
## and its reaction to make `roller` reroll a success and keep the lower roll, then gives an ally
## (the creature `roller` was acting against, if it's on the caster's side) advantage on its next
## attack roll or save. Returns true when the reroll is forced.
func _silvery_barbs(roller: Dictionary, against: Dictionary, rng: int) -> bool:
	for p in all_combatants():
		if not alive(p) or not hostile(p, roller) or not knows_spell(p, "silvery_barbs") or not can_react_spell(p):
			continue
		if not p.form.is_empty() or dist(p, roller) > rng or lowest_slot(p, 1) <= 0 or not can_see(p, roller):
			continue
		spend_slot(p, lowest_slot(p, 1))
		use_reaction(p)
		log_line("  %s casts [b]Silvery Barbs[/b] on %s!" % [nm(p), nm(roller)])
		var friend: Dictionary = against if not against.is_empty() and not hostile(p, against) and alive(against) else p
		add_effect(friend, {"name": "Silvery Barbs", "src": p.id, "spell": "silvery_barbs", "one_roll": true, "mods": {"advantage_attack": true}, "rounds": 10, "tick_cid": p.id})
		return true
	return false

## Temporal Shunt (reaction, 120 ft): when `actor` attacks or casts against the shunter's side, it makes
## a WIS save or vanishes until the end of the shunter's next turn, wasting the attack or spell.
## Only worth a slot for a leveled spell or an attack on a badly hurt ally. Returns true if it vanished.
func temporal_shunt(actor: Dictionary, victim: Dictionary, spell_level: int) -> bool:
	if spell_level <= 0 and (victim.is_empty() or victim.hp > victim.max_hp / 2):
		return false
	for p in all_combatants():
		if not alive(p) or not hostile(p, actor) or not knows_spell(p, "temporal_shunt") or not can_react_spell(p):
			continue
		if not p.form.is_empty() or dist(p, actor) > 120 or lowest_slot(p, 5) <= 0 or not can_see(p, actor):
			continue
		spend_slot(p, lowest_slot(p, 5))
		use_reaction(p)
		log_line("  %s casts [b]Temporal Shunt[/b] at %s!" % [nm(p), nm(actor)])
		var dc: int = best_spell_dc(p)
		if saving_throw(actor, "wis", dc, p, {"spell": true}):
			return false
		add_effect(actor, {"name": "Shunted", "cond": "banished", "src": p.id, "spell": "temporal_shunt", "rounds": 1, "tick_cid": p.id, "tick_on": "end"})
		log_line("  %s blinks out of time; its effort is wasted." % nm(actor))
		return true
	return false

func _legendary_or_fail(t: Dictionary) -> bool:
	if int(t.get("legendary_res", 0)) > 0:
		t.legendary_res = int(t.legendary_res) - 1
		log_line("  %s uses Legendary Resistance to succeed instead! (%d left)" % [nm(t), t.legendary_res])
		float_text(t.id, "Legendary Resistance", "#ffd166")
		return true
	return false

func _aura_of_protection(t: Dictionary) -> int:
	var best = 0
	for p in allies_of(t):
		if p.features.has("aura_of_protection") and conscious(p):
			var r = 30 if p.class_levels.get("paladin", 0) >= 18 else 10
			if p.id == t.id or dist(p, t) <= r:
				best = maxi(best, maxi(1, int(p.mods.cha)))
	return best

func _save_helpers(t: Dictionary, ability: String, dc: int, total: int, adv: int, bonus: int) -> Dictionary:
	var need = dc - total
	var notes: PackedStringArray = []
	var ctx := "%s failed a %s save: %d against DC %d." % [t.name, ability.to_upper(), total, dc]
	if res_left(t, "indomitable") > 0 and fix_use(t, "indomitable", true, ctx):
		spend_res(t, "indomitable")
		var r = Dice.roll_d20(adv)
		var nt: int = int(r.roll) + bonus
		notes.append("Indomitable reroll")
		var out = _fix_result(t, "indomitable", nt >= dc, notes, {"ok": nt >= dc, "total": nt})
		if not out.is_empty():
			return out
		total = nt
		need = dc - total
		ctx = "%s rerolled the save and got %d against DC %d." % [t.name, total, dc]
	if res_left(t, "lucky") > 0 and fix_use(t, "lucky", true, ctx):
		spend_res(t, "lucky")
		var r2 = Dice.roll_d20(0)
		var nt2: int = maxi(int(r2.roll) + bonus, total)
		notes.append("Lucky")
		var out2 = _fix_result(t, "lucky", nt2 >= dc, notes, {"ok": nt2 >= dc, "total": nt2})
		if not out2.is_empty():
			return out2
		total = nt2
		need = dc - total
		ctx = "%s's save is now %d against DC %d." % [t.name, total, dc]
	for e in t.effects:
		if e.get("tag", "") == "bardic_inspiration":
			# An automatic user peeks at the die and only spends it when it is enough; a player decides first.
			var manual := fix_manual(t, "bardic_inspiration")
			var bi: int = 0 if manual else Dice.roll(e.die).total
			if fix_use(t, "bardic_inspiration", bi >= need, ctx):
				if manual:
					bi = Dice.roll(e.die).total
				remove_effect(t, e.eid)
				notes.append("Bardic Inspiration +%d" % bi)
				var out3 = _fix_result(t, "bardic_inspiration", total + bi >= dc, notes, {"ok": true, "total": total + bi})
				if not out3.is_empty():
					return out3
				total += bi
				need = dc - total
				ctx = "%s's save is now %d against DC %d." % [t.name, total, dc]
				break
	if _bond_available(t) and fix_use(t, "emboldening_bond", need <= 4, ctx):
		var b: int = Dice.d(4)
		t.turn["bond_used"] = true
		if b >= need or fix_manual(t, "emboldening_bond"):
			notes.append("Emboldening Bond +%d" % b)
			var out4 = _fix_result(t, "emboldening_bond", total + b >= dc, notes, {"ok": true, "total": total + b})
			if not out4.is_empty():
				return out4
			total += b
			need = dc - total
			ctx = "%s's save is now %d against DC %d." % [t.name, total, dc]
	if res_left(t, "favored_by_the_gods") > 0 and fix_use(t, "favored_by_the_gods", need <= 8, ctx):
		spend_res(t, "favored_by_the_gods")
		var fg: int = Dice.roll("2d4").total
		notes.append("Favored by the Gods +%d" % fg)
		var out5 = _fix_result(t, "favored_by_the_gods", total + fg >= dc, notes, {"ok": total + fg >= dc, "total": total + fg})
		if not out5.is_empty():
			return out5
		total += fg
		need = dc - total
		ctx = "%s's save is now %d against DC %d." % [t.name, total, dc]
	for p in allies_of(t):
		if p.features.has("flash_of_genius") and can_react(p) and res_left(p, "flash_of_genius") > 0 and dist(p, t) <= 30:
			var add: int = maxi(1, int(p.mods.int))
			if fix_use(p, "flash_of_genius", add >= need, "%s (adds +%d)" % [ctx, add]):
				spend_res(p, "flash_of_genius")
				use_reaction(p)
				notes.append("%s's Flash of Genius +%d" % [p.name, add])
				var out6 = _fix_result(p, "flash_of_genius", total + add >= dc, notes, {"ok": total + add >= dc, "total": total + add})
				if not out6.is_empty():
					return out6
				total += add
				need = dc - total
				break
	if t.features.has("arcane_deflection") and can_react(t) and need <= 4:
		use_reaction(t)
		return {"ok": true, "total": total + 4, "note": "Arcane Deflection +4"}
	for p in allies_of(t):
		if p.features.has("chronal_shift") and can_react(p) and res_left(p, "chronal_shift") > 0 and dist(p, t) <= 30:
			spend_res(p, "chronal_shift")
			use_reaction(p)
			var r3 = Dice.roll_d20(adv)
			var nt3: int = int(r3.roll) + bonus
			return {"ok": nt3 >= dc, "total": nt3, "note": "%s's Chronal Shift reroll" % p.name}
	return {"ok": false, "total": total, "note": ", ".join(notes)}

func spend_res_if(c: Dictionary, id: String) -> bool:
	return spend_res(c, id) if res_left(c, id) > 0 else false

func _bond_available(t: Dictionary) -> bool:
	if not has_tag(t, "bonded") or t.get("turn", {}).get("bond_used", false):
		return false
	for o in allies_of(t, false):
		if has_tag(o, "bonded") and dist(o, t) <= 30:
			return true
	return false

# ================================================================ attack rolls

## Resolve the d20 part of an attack. atk needs to_hit; opts: melee, spell, adv (extra), bonus.
## If Sanctuary makes the attacker switch targets, the result carries the new one as "target" (callers
## should resolve damage against res.get("target", t)).
func roll_attack(a: Dictionary, t: Dictionary, atk: Dictionary, opts := {}) -> Dictionary:
	var melee: bool = opts.get("melee", atk.get("melee", true))
	var reach: int = int(atk.get("reach", 5)) if melee else int(atk.get("long_range", atk.get("range", 0)))
	if opts.get("fixed_target", false):
		reach = -1  # reactions aimed at one creature (opportunity attack, Riposte) can't switch
	var aimed: Dictionary = sanctuary_target(a, t, reach)
	if aimed.is_empty():
		return {"hit": false, "crit": false, "nat": 0, "total": 0, "ac": eff_ac(t), "adv": 0, "sanctuary": true, "target": t}
	t = aimed
	_break_sanctuary(a, t)
	if hostile(a, t) and not opts.get("fixed_target", false) and temporal_shunt(a, t, 0):
		return {"hit": false, "crit": false, "nat": 0, "total": 0, "ac": eff_ac(t), "adv": 0, "target": t}
	var res := _roll_attack_at(a, t, atk, melee, opts)
	res.target = t
	return res

func _roll_attack_at(a: Dictionary, t: Dictionary, atk: Dictionary, melee: bool, opts: Dictionary) -> Dictionary:
	# Attacking a hostile creature keeps a rage going (see CombatEngine.end_turn).
	if hostile(a, t):
		a.rage_kept = true
	var adv = attack_advantage(a, t, melee, atk) + int(opts.get("adv", 0))
	# Pre-roll defensive reactions that impose disadvantage.
	if adv >= 0 and hostile(a, t):
		if t.features.has("warding_flare") and can_react(t) and res_left(t, "warding_flare") > 0 and a.type != "construct":
			spend_res(t, "warding_flare")
			use_reaction(t)
			adv -= 1
			log_line("  %s flares with divine light (Warding Flare)." % nm(t))
		else:
			for p in allies_of(t, false):
				if "protection" in p.get("styles", []) and p.get("has_shield", false) and can_react(p) and dist(p, t) <= 5:
					use_reaction(p)
					adv -= 1
					log_line("  %s interposes their shield (Protection)." % nm(p))
					break
	adv = clampi(adv, -1, 1)
	var rr = Dice.roll_d20(adv, a.tags.has("halfling_lucky"))
	var nat: int = rr.roll
	var bonus: int = int(atk.get("to_hit", 0)) + int(opts.get("bonus", 0))
	var extra = ""
	for dexp in mod_list(a, "attack_dice"):
		var r: int = Dice.roll(str(dexp)).total
		bonus += r
		extra += " +%d" % r
	for dexp in mod_list(a, "attack_penalty_dice"):
		var r: int = Dice.roll(str(dexp)).total
		bonus -= r
		extra += " -%d" % r
	if has_tag(a, "sacred_weapon") and not opts.get("spell", false):
		bonus += maxi(1, int(a.mods.cha))
	var ac = eff_ac(t)
	# Arrow-Catching Shield: +2 AC against ranged attacks.
	if not melee and t.get("tags", {}).has("arrow_catching"):
		ac += 2
	var crit_range: int = int(a.get("vals", {}).get("crit_range", 20)) if not opts.get("spell", false) else 20
	for e in t.effects:
		if e.get("tag", "") == "hexblade_curse" and e.get("src", "") == a.id:
			crit_range = mini(crit_range, 19)
	var total = nat + bonus
	var crit = nat >= crit_range
	var hit = nat != 1 and (crit or total >= ac)
	var note = ""
	var how = " (adv %s)" % str(rr.rolls) if adv > 0 else (" (dis %s)" % str(rr.rolls) if adv < 0 else "")
	# Attacker helpers when missing.
	if not hit and nat != 1:
		var need = ac - total
		var fix = _attack_miss_helpers(a, t, need, adv, bonus)
		if fix.hit:
			hit = true
			total = fix.total
			note = fix.note
			if fix.get("crit", false):
				crit = true
		elif str(fix.get("note", "")) != "":
			# A player's character tried to fix the roll and it still missed.
			total = int(fix.total)
			note = str(fix.note)
	# Defender helpers when hit.
	if hit and not crit and hostile(a, t):
		var fx2 = _attack_hit_defense(a, t, total, ac, adv, bonus)
		if not fx2.hit:
			hit = false
			note = fx2.note
		elif fx2.note != "":
			note = fx2.note
		total = fx2.total
		ac = fx2.ac
	# Any hit on a paralysed or unconscious creature from within 5 ft is a critical (melee or ranged).
	if hit and dist(a, t) <= 5 and (has_cond(t, "paralyzed") or has_cond(t, "unconscious")):
		crit = true
	# Adamantine armor: a critical hit against the wearer becomes a normal hit.
	if crit and hit and t.get("tags", {}).has("adamantine"):
		crit = false
		note = (note + "; " if note != "" else "") + "adamantine armor turns the critical hit"
	var res_txt = "[color=#ffd166]CRIT![/color]" if crit and hit else ("[color=#7fdc7f]HIT[/color]" if hit else "[color=#aaaaaa]MISS[/color]")
	dice_event(a.id, "%s · AC %d" % [str(atk.get("name", "Attack")), ac], d20_faces(rr), bonus, total,
		"CRIT" if crit and hit else ("HIT" if hit else "MISS"), t.id)
	log_line("  %s → %s: %d%s%s = %d vs AC %d %s%s" % [nm(a), nm(t), nat, how, (" " + Rules.fmt_mod(int(atk.get("to_hit", 0))) if extra == "" else " " + Rules.fmt_mod(int(atk.get("to_hit", 0))) + extra), total, ac, res_txt, (" (" + note + ")") if note != "" else ""])
	if not hit:
		float_text(t.id, "Miss", "#bbbbbb")
	# Breaking invisibility / hiding.
	if a.get("hidden", false):
		a.hidden = false
	remove_effects_where(a, func(e): return e.get("cond", "") == "invisible" and e.get("breaks", false))
	remove_effects_where(t, func(e): return e.get("tag", "") in ["true_strike", "helped", "distracted"] and (e.get("src", "") == a.id or e.get("for_team", "") == a.team))
	# "The next attack roll against the target" effects (Guiding Bolt) are spent by any attack.
	remove_effects_where(t, func(e): return e.get("one_attack", false))
	# The attacker's own one-roll effects: Frostbite's disadvantage, Silvery Barbs' advantage.
	remove_effects_where(a, func(e): return e.get("one_own_attack", false) or e.get("one_roll", false))
	return {"hit": hit, "crit": crit and hit, "nat": nat, "total": total, "ac": ac, "adv": adv}

func _attack_miss_helpers(a: Dictionary, t: Dictionary, need: int, adv: int, bonus: int) -> Dictionary:
	var ac: int = eff_ac(t)
	var total: int = ac - need
	var notes: PackedStringArray = []
	var ctx := "%s missed %s: %d against AC %d." % [a.name, t.name, total, ac]
	if "precision" in a.get("maneuvers", []) and res_left(a, "superiority") > 0 \
			and fix_use(a, "precision", need <= int(a.vals.get("superiority_die", 8)) and need <= 5, ctx):
		spend_res(a, "superiority")
		var r: int = Dice.d(int(a.vals.superiority_die))
		notes.append("Precision Attack +%d" % r)
		total += r
		need = ac - total
		if need <= 0:
			return {"hit": true, "total": total, "note": ", ".join(notes)}
		ctx = "%s's attack is now %d against AC %d." % [a.name, total, ac]
	if a.features.has("guided_strike") and res_left(a, "channel_divinity") > 0 \
			and fix_use(a, "guided_strike", need <= 10 and need >= 3, ctx):
		spend_res(a, "channel_divinity")
		notes.append("Guided Strike +10")
		total += 10
		need = ac - total
		if need <= 0:
			return {"hit": true, "total": maxi(total, ac), "note": ", ".join(notes)}
		ctx = "%s's attack is now %d against AC %d." % [a.name, total, ac]
	if res_left(a, "lucky") > 0 and fix_use(a, "lucky", true, ctx):
		spend_res(a, "lucky")
		var r2 = Dice.roll_d20(0)
		var rr: int = int(r2.roll)
		var tot: int = rr + bonus
		notes.append("Lucky reroll")
		# A natural 1 misses and a natural 20 hits, whatever the totals.
		if rr != 1 and (rr >= 20 or tot >= ac):
			return {"hit": true, "total": tot, "note": ", ".join(notes), "crit": rr >= int(a.vals.get("crit_range", 20))}
		if not fix_manual(a, "lucky"):
			return {"hit": false}
		if rr != 1:
			total = maxi(total, tot)
			need = ac - total
		ctx = "%s's reroll was %d: still a miss against AC %d." % [a.name, tot, ac]
	for e in a.effects:
		if e.get("tag", "") == "bardic_inspiration":
			# An automatic user peeks at the die and only spends it when it is enough; a player decides first.
			var manual := fix_manual(a, "bardic_inspiration")
			var bi: int = 0 if manual else Dice.roll(e.die).total
			if fix_use(a, "bardic_inspiration", bi >= need, ctx):
				if manual:
					bi = Dice.roll(e.die).total
				remove_effect(a, e.eid)
				notes.append("Bardic Inspiration +%d" % bi)
				total += bi
				need = ac - total
				if need <= 0:
					return {"hit": true, "total": total, "note": ", ".join(notes)}
				ctx = "%s's attack is now %d against AC %d." % [a.name, total, ac]
				break
	if _bond_available(a) and fix_use(a, "emboldening_bond", need <= 4, ctx):
		a.turn["bond_used"] = true
		var b: int = Dice.d(4)
		if b >= need or fix_manual(a, "emboldening_bond"):
			notes.append("Emboldening Bond +%d" % b)
			total += b
			need = ac - total
			if need <= 0:
				return {"hit": true, "total": maxi(total, ac), "note": ", ".join(notes)}
			ctx = "%s's attack is now %d against AC %d." % [a.name, total, ac]
	if res_left(a, "favored_by_the_gods") > 0 and fix_use(a, "favored_by_the_gods", need <= 8 and need >= 2, ctx):
		spend_res(a, "favored_by_the_gods")
		var fg: int = Dice.roll("2d4").total
		notes.append("Favored by the Gods +%d" % fg)
		if fg >= need:
			return {"hit": true, "total": maxi(total + fg, ac), "note": ", ".join(notes)}
	return {"hit": false, "total": total, "note": ", ".join(notes)}

func _attack_hit_defense(a: Dictionary, t: Dictionary, total: int, ac: int, adv: int, bonus: int) -> Dictionary:
	var margin = total - ac
	# Shield spell.
	if margin < 5 and can_react_spell(t) and knows_spell(t, "shield") and lowest_slot(t, 1) > 0 and t.form.is_empty():
		var lv = lowest_slot(t, 1)
		spend_slot(t, lv)
		use_reaction(t)
		add_effect(t, {"name": "Shield", "tag": "shield", "src": t.id, "mods": {"ac": 5}, "rounds": 1, "tick_cid": t.id, "tick_on": "start"})
		log_line("  %s casts [b]Shield[/b]! (+5 AC)" % nm(t))
		return {"hit": false, "total": total, "ac": ac + 5, "note": "blocked by Shield"}
	# Cutting Words.
	for p in allies_of(t):
		if p.features.has("cutting_words") and can_react(p) and res_left(p, "bardic_inspiration") > 0 and dist(p, a) <= 60:
			var die = int(p.vals.get("bardic_die", 6))
			if margin < die / 2 + 1:
				spend_res(p, "bardic_inspiration")
				use_reaction(p)
				var r: int = Dice.d(die)
				if total - r < ac:
					return {"hit": false, "total": total - r, "ac": ac, "note": "%s's Cutting Words -%d" % [p.name, r]}
				total -= r
				margin = total - ac
				break
	# Chronal Shift: force the attacker to reroll.
	for p in allies_of(t):
		if p.features.has("chronal_shift") and can_react(p) and res_left(p, "chronal_shift") > 0 and dist(p, a) <= 30:
			spend_res(p, "chronal_shift")
			use_reaction(p)
			var r2 = Dice.roll_d20(adv)
			var nt: int = int(r2.roll) + bonus
			if int(r2.roll) == 1 or nt < ac:
				return {"hit": false, "total": nt, "ac": ac, "note": "%s's Chronal Shift reroll: %d" % [p.name, nt]}
			return {"hit": true, "total": nt, "ac": ac, "note": "Chronal Shift reroll still hits"}
	if t.features.has("arcane_deflection") and can_react(t) and margin < 2:
		use_reaction(t)
		return {"hit": false, "total": total, "ac": ac + 2, "note": "Arcane Deflection +2 AC"}
	if _silvery_barbs(a, t, 60):
		var rb = Dice.roll_d20(0)
		var nb: int = mini(int(rb.roll) + bonus, total)
		if int(rb.roll) == 1 or nb < ac:
			return {"hit": false, "total": nb, "ac": ac, "note": "Silvery Barbs reroll: %d" % nb}
		total = nb
	if res_left(t, "lucky") > 0 and fix_use(t, "lucky", margin < 6, "%s hits %s: %d against AC %d. Lucky makes the attacker reroll and you take the lower roll." % [a.name, t.name, total, ac]):
		spend_res(t, "lucky")
		var r3 = Dice.roll_d20(0)
		var nt3: int = mini(int(r3.roll) + bonus, total)
		if nt3 < ac:
			return {"hit": false, "total": nt3, "ac": ac, "note": "%s's Lucky" % t.name}
	# Mirror Image.
	for e in t.effects:
		if e.get("tag", "") == "mirror_image" and int(e.get("images", 0)) > 0:
			var need = 6 if e.images >= 3 else (8 if e.images == 2 else 11)
			if Dice.d20() >= need:
				if total >= 10 + int(t.mods.dex):
					e.images = int(e.images) - 1
					log_line("  The attack strikes an illusory duplicate! (%d left)" % e.images)
				return {"hit": false, "total": total, "ac": ac, "note": "Mirror Image"}
	return {"hit": true, "total": total, "ac": ac, "note": ""}

# ================================================================ damage

## parts: [{"amount": int, "type": String}]. Returns the HP actually lost.
func apply_damage(t: Dictionary, parts: Array, src: Dictionary, opts := {}) -> int:
	if not alive(t):
		return 0
	var magic: bool = opts.get("magic", false) or opts.get("spell", false)
	var total = 0
	var breakdown: PackedStringArray = []
	var resist: Array = t.resist.duplicate()
	for r in mod_list(t, "resist"):
		if r is Array:
			resist.append_array(r)
		else:
			resist.append(r)
	var raging = has_tag(t, "rage")
	if raging:
		resist.append_array(["bludgeoning", "piercing", "slashing"])
		if t.features.has("totem_spirit_bear"):
			resist.append_array(["acid", "cold", "fire", "force", "lightning", "necrotic", "poison", "radiant", "thunder"])
	var immune: Array = t.immune.duplicate()
	for r in mod_list(t, "immune"):
		if r is Array:
			immune.append_array(r)
		else:
			immune.append(r)
	# Silence: nothing inside can take thunder damage.
	if in_zone_flag(t, "silence"):
		immune.append("thunder")
	var vulnerable: Array = t.vulnerable
	var ignore_res: String = opts.get("ignore_resist", "")
	parts = parts.duplicate(true)
	# Absorb Elements: resist the triggering elemental damage and charge the next melee hit with it.
	if not src.is_empty() and hostile(src, t):
		var absorbed: String = _absorb_elements(t, parts)
		if absorbed != "":
			resist.append(absorbed)
	# Elemental Bane: the chosen type ignores resistance and, once a turn, deals 2d6 extra.
	for e in t.effects:
		var eb = e.get("mods", {}).get("elemental_bane", null)
		if not eb is Dictionary:
			continue
		var bt: String = str(eb.get("type", "fire"))
		resist.erase(bt)
		while bt in resist:
			resist.erase(bt)
		var key := "%s:%d" % [bt, int(s.get("turn_serial", 0))]
		if _has_type(parts, bt) and e.get("bane_turn", "") != key:
			e.bane_turn = key
			parts.append({"amount": Dice.roll(str(eb.get("dice", "2d6"))).total, "type": bt})
			log_line("  Elemental Bane flares (+%s %s)." % [str(eb.get("dice", "2d6")), bt])
	for p in parts:
		var amt: int = maxi(0, int(p.amount))
		var typ: String = p.type
		var bps = typ in ["bludgeoning", "piercing", "slashing"]
		var mundane_only: bool = t.get("mundane_resist", false) and bps
		# "Nonmagical attacks that aren't silvered": a silvered weapon gets through too (Inventory: silvered weapons).
		var gets_past: bool = magic or (opts.get("silver", false) and t.get("mundane_silver", false))
		# Flat reductions (Heavy Armor Master) come before resistance and vulnerability (PHB p.197).
		if bps and not magic and t.get("heavy_armor", false) and t.get("feats", []).has("heavy_armor_master"):
			amt = maxi(0, amt - 3)
		if typ in immune and not (mundane_only and gets_past):
			amt = 0
		elif typ in resist and typ != ignore_res and not (mundane_only and gets_past and typ in t.resist):
			amt = amt / 2
		if typ in vulnerable:
			amt *= 2
		total += amt
		breakdown.append("%d %s" % [amt, typ])
	# Path to the Grave: double the next attack's damage.
	if opts.get("attack", false):
		for e in t.effects:
			if e.get("tag", "") == "path_to_grave":
				total *= 2
				remove_effect(t, e.eid)
				log_line("  Path to the Grave doubles the damage!")
				break
	# Damage-reducing reactions against attacks.
	if opts.get("attack", false) and total > 0 and conscious(t):
		if opts.get("ranged_weapon", false) and t.features.has("deflect_missiles") and can_react(t):
			var red: int = Dice.d(10) + int(t.mods.dex) + t.class_levels.get("monk", 0)
			use_reaction(t)
			total = maxi(0, total - red)
			log_line("  %s deflects the missile (-%d)." % [nm(t), red])
		elif opts.get("ranged_weapon", false) and t.get("tags", {}).has("missile_snaring") and can_react(t):
			# Gloves of Missile Snaring: 1d10 + Dexterity modifier off a ranged weapon hit.
			var red3: int = maxi(0, Dice.d(10) + int(t.mods.dex))
			use_reaction(t)
			total = maxi(0, total - red3)
			log_line("  %s snatches at the missile with the gloves (-%d)." % [nm(t), red3])
		elif t.features.has("uncanny_dodge") and can_react(t) and (total >= 8 or total >= t.hp):
			use_reaction(t)
			total = total / 2
			log_line("  %s uses Uncanny Dodge (half damage)." % nm(t))
		elif t.tags.has("stones_endurance") and can_react(t) and res_left(t, "stones_endurance") > 0 and total >= 8:
			spend_res(t, "stones_endurance")
			use_reaction(t)
			var red2: int = Dice.d(12) + int(t.mods.con)
			total = maxi(0, total - red2)
			log_line("  %s uses Stone's Endurance (-%d)." % [nm(t), red2])
		else:
			for p in allies_of(t, false):
				if "interception" in p.get("styles", []) and can_react(p) and dist(p, t) <= 5:
					use_reaction(p)
					var red3: int = Dice.d(10) + int(p.prof)
					total = maxi(0, total - red3)
					log_line("  %s intercepts the blow (-%d)." % [nm(p), red3])
					break
	if total <= 0:
		log_line("  %s takes no damage." % nm(t))
		float_text(t.id, "0", "#bbbbbb")
		return 0
	var dealt = total
	# Arcane Ward.
	if int(t.get("ward", 0)) > 0:
		var absorb = mini(int(t.ward), total)
		t.ward = int(t.ward) - absorb
		total -= absorb
		log_line("  Arcane Ward absorbs %d." % absorb)
	if t.temp_hp > 0 and total > 0:
		var tabs = mini(int(t.temp_hp), total)
		t.temp_hp -= tabs
		total -= tabs
	# Wild Shape absorbs into the beast form.
	if not t.form.is_empty() and total > 0:
		var fh: int = t.form.hp
		if total < fh:
			t.form.hp = fh - total
			total = 0
		else:
			total -= fh
			end_wild_shape(t)
	# Taking damage keeps a rage going.
	t.rage_kept = true
	# Cloak of Displacement: the illusion falters after the wearer is hurt, until its next turn.
	if total > 0 and t.get("tags", {}).has("displacement"):
		t.displace_off = true
	var was_up: bool = t.hp > 0
	t.hp -= total
	# Harm can't drop a creature below 1 hit point.
	if opts.has("min_hp") and was_up and t.hp < int(opts.min_hp):
		t.hp = int(opts.min_hp)
	log_line("  %s takes [color=#ff8a7a]%d[/color] damage (%s)." % [nm(t), dealt, ", ".join(breakdown)])
	float_text(t.id, "-%d" % dealt, "#ff6b5b" if not opts.get("crit", false) else "#ffd166")
	# Damage ends some effects.
	remove_effects_where(t, func(e): return e.get("end_on_damage", false))
	_break_sanctuary(src, t)
	# Enemies Abound: each time the target takes damage it repeats the save.
	for e in t.effects.duplicate():
		var sod = e.get("save_on_damage", null)
		if sod is Dictionary and e in t.effects and t.hp > 0:
			# Hideous Laughter: damage gives the new save advantage.
			var sod_opts := {"spell": true}
			if e.get("save_on_damage_adv", false):
				t.effects.append({"eid": "tmp_adv", "mods": {"save_adv": [str(sod.ability)]}, "name": ""})
			var shook: bool = saving_throw(t, str(sod.ability), int(sod.dc), C(e.get("src", "")), sod_opts)
			remove_effects_where(t, func(x): return x.get("eid", "") == "tmp_adv")
			if shook:
				t.effects.erase(e)
				log_line("  %s shakes off %s." % [nm(t), e.get("name", "the effect")])
				if e.get("tag", "") == "dominated":
					refresh_teams()
	# Armor of Agathys.
	if opts.get("melee", false) and not src.is_empty():
		for e in t.effects:
			if e.get("tag", "") == "armor_of_agathys" and t.temp_hp > 0:
				log_line("  Frost lashes out from %s's Armor of Agathys!" % nm(t))
				apply_damage(src, [{"amount": int(e.value), "type": "cold"}], t, {"spell": true})
		# Fire Shield: a melee hit from within 5 ft burns (or chills) the attacker.
		for e in t.effects.duplicate():
			var rt = e.get("retaliate", null)
			if rt is Dictionary and alive(src) and src.id != t.id and dist(src, t) <= 5:
				log_line("  %s's %s lashes back at %s!" % [nm(t), e.get("name", "shield"), nm(src)])
				apply_damage(src, [{"amount": Dice.roll(str(rt.get("dice", "2d8"))).total, "type": str(rt.get("type", "fire"))}], t, {"spell": true})
	# Warding Bond: the caster takes the same damage as the warded creature.
	if not opts.get("bond", false):
		for e in t.effects.duplicate():
			if e.get("tag", "") == "warding_bond":
				var cst = C(str(e.get("src", "")))
				if not cst.is_empty() and alive(cst) and cst.id != t.id and cst.hp > 0:
					log_line("  The Warding Bond passes the pain to %s." % nm(cst))
					apply_damage(cst, [{"amount": dealt, "type": "bond"}], {}, {"bond": true})
	if t.hp <= 0:
		var zopts: Dictionary = opts
		if not opts.get("radiant", false) and _has_type(parts, "radiant"):
			zopts = opts.duplicate()
			zopts.radiant = true
		_on_zero(t, src, total, zopts, was_up)
	elif not t.conc.is_empty() and dealt > 0:
		var dc = maxi(10, dealt / 2)
		log_line("  %s must maintain concentration (DC %d)." % [nm(t), dc])
		if not saving_throw(t, "con", dc, {}, {"concentration": true}):
			end_concentration(t)
	# Hellish Rebuke & Wrath of the Storm.
	if not src.is_empty() and src.id != t.id and conscious(t) and hostile(src, t) and alive(src):
		_damage_reactions(t, src, opts)
	return dealt

func _has_type(parts: Array, typ: String) -> bool:
	for p in parts:
		if p.type == typ:
			return true
	return false

const ABSORB_TYPES := ["acid", "cold", "fire", "lightning", "thunder"]

## Absorb Elements (reaction): when `t` takes acid, cold, fire, lightning or thunder damage it can cast
## the spell to resist that type until the start of its next turn, and its next melee hit deals an extra
## 1d6 of it per slot level. Cast automatically (like Shield) when the hit is worth a slot.
## Returns the absorbed type, or "".
func _absorb_elements(t: Dictionary, parts: Array) -> String:
	if not knows_spell(t, "absorb_elements") or not can_react_spell(t) or not t.form.is_empty() or lowest_slot(t, 1) <= 0:
		return ""
	var best: String = ""
	var best_amt: int = 0
	for p in parts:
		if p.type in ABSORB_TYPES and int(p.amount) > best_amt:
			best = p.type
			best_amt = int(p.amount)
	if best == "" or best_amt < 6 or best in t.resist or best in t.immune:
		return ""
	var lv: int = lowest_slot(t, 1)
	spend_slot(t, lv)
	use_reaction(t)
	log_line("  %s casts [b]Absorb Elements[/b], drinking in the %s!" % [nm(t), best])
	add_effect(t, {"name": "Absorb Elements", "src": t.id, "spell": "absorb_elements", "mods": {"resist": [best]}, "rounds": 1, "tick_cid": t.id, "tick_on": "start"})
	add_effect(t, {"name": "Absorbed %s" % best.capitalize(), "src": t.id, "spell": "absorb_elements", "one_hit": true, "melee_only": true,
		"mods": {"extra_damage": {"dice": "%dd6" % lv, "type": best}}, "rounds": 2, "tick_cid": t.id, "tick_on": "end"})
	return best

func _damage_reactions(t: Dictionary, src: Dictionary, opts: Dictionary) -> void:
	if t.features.has("wrath_of_the_storm") and opts.get("melee", false) and can_react(t) and res_left(t, "wrath_of_the_storm") > 0 and dist(t, src) <= 5:
		spend_res(t, "wrath_of_the_storm")
		use_reaction(t)
		log_line("%s unleashes the Wrath of the Storm!" % nm(t))
		var ok = saving_throw(src, "dex", int(t.vals.cd_dc_wis), t, {"magic": true})
		var dmg: int = Dice.roll("2d8").total
		apply_damage(src, [{"amount": dmg / 2 if ok else dmg, "type": "lightning"}], t, {"magic": true})
		return
	if knows_spell(t, "hellish_rebuke") and can_react_spell(t) and lowest_slot(t, 1) > 0 and dist(t, src) <= 60 and t.form.is_empty():
		var lv = lowest_slot(t, 1)
		spend_slot(t, lv)
		use_reaction(t)
		var e = caster_entry(t, "warlock")
		log_line("%s casts [b]Hellish Rebuke[/b] at %s!" % [nm(t), nm(src)])
		fx("bolt", t.pos, src.pos, "#ff6a2a")
		var ok2 = saving_throw(src, "dex", int(e.get("dc", 13)), t, {"spell": true})
		var dmg2: int = Dice.roll("%dd10" % (lv + 1)).total
		apply_damage(src, [{"amount": dmg2 / 2 if ok2 else dmg2, "type": "fire"}], t, {"spell": true})

## Destroy a creature outright (Destroy Undead): no damage roll, and nothing like Undead Fortitude,
## Death Ward or Relentless Endurance keeps it standing.
func destroy_creature(t: Dictionary, src: Dictionary) -> void:
	if not alive(t):
		return
	t.hp = 0
	_on_zero(t, src, 0, {"destroy": true}, true)

func _on_zero(t: Dictionary, src: Dictionary, overflow: int, opts: Dictionary, was_up: bool) -> void:
	if opts.get("destroy", false):
		if t.kind == "pc":
			_kill(t, "destroyed")
			return
	# Abilities that keep a creature standing.
	for e in (t.effects if not opts.get("destroy", false) else []):
		if was_up and e.get("mods", {}).get("death_ward", false):
			t.effects.erase(e)
			t.hp = 1
			log_line("  %s is saved by Death Ward and drops to 1 HP instead!" % nm(t))
			float_text(t.id, "Death Ward", "#ffd166")
			return
	var can_cling: bool = not opts.get("destroy", false)
	if can_cling and was_up and t.tags.has("relentless_endurance") and res_left(t, "relentless_endurance") > 0 and t.hp > -t.max_hp:
		spend_res(t, "relentless_endurance")
		t.hp = 1
		log_line("  %s refuses to fall! (Relentless Endurance)" % nm(t))
		float_text(t.id, "Relentless!", "#ffd166")
		return
	if can_cling and t.features.has("relentless_rage") and has_tag(t, "rage"):
		var dc = 10 + 5 * int(t.get("rr_uses", 0))
		t.rr_uses = int(t.get("rr_uses", 0)) + 1
		if saving_throw(t, "con", dc, {}, {}):
			t.hp = 1
			log_line("  %s keeps fighting through sheer rage!" % nm(t))
			return
	# Undead Fortitude: not against radiant damage (from a spell or a weapon) or a critical hit.
	if can_cling and t.tags.has("undead_fortitude") and not opts.get("crit", false) and not opts.get("radiant", false):
		if saving_throw(t, "con", 5 + overflow, {}, {}):
			t.hp = 1
			log_line("  %s staggers but rises again (Undead Fortitude)!" % nm(t))
			return
	end_concentration(t, true)
	if t.kind == "pc":
		if not was_up:
			# Damage while already down: death save failures.
			if -t.hp >= t.max_hp:
				_kill(t, "massive damage")
				return
			t.death.f += 2 if opts.get("crit", false) else 1
			# Taking damage ends stability: the creature is dying again.
			t.death.stable = false
			t.hp = 0
			log_line("  %s suffers a death save failure (%d/3)." % [nm(t), t.death.f])
			if t.death.f >= 3:
				_kill(t, "death saves")
			return
		if -t.hp >= t.max_hp:
			_kill(t, "massive damage")
			return
		t.hp = 0
		t.death = {"s": 0, "f": 0, "stable": false, "dead": false}
		t.form = {}
		remove_effects_where(t, func(e): return e.get("tag", "") in ["rage", "bladesong", "wild_shape"])
		log_line("  [color=#ff5050]%s falls unconscious![/color]" % nm(t))
		# Falling unconscious knocks a creature prone, and it is still prone when it comes round.
		add_effect(t, {"name": "Prone", "cond": "prone", "src": t.id, "rounds": 9999, "tick_cid": "none"})
		drop_held_stones(t)
		float_text(t.id, "Down!", "#ff5050")
	else:
		t.hp = 0
		t.dead = true
		log_line("  [color=#ff5050]%s is slain![/color]" % nm(t))
		drop_held_stones(t)
		float_text(t.id, "Slain", "#ff5050")
		end_concentration(t, true)
		for o in all_combatants():
			if o.get("summoner", "") == t.id:
				drop_held_stones(o)
				o.dead = true
	if not src.is_empty():
		_on_kill(src, t, opts)

func _kill(t: Dictionary, why: String) -> void:
	t.hp = 0
	t.death.dead = true
	t.death.died_at = int(s.get("clock", 0))
	log_line("  [color=#ff3030]%s has died (%s).[/color]" % [nm(t), why])
	float_text(t.id, "Dead", "#ff3030")

func _on_kill(src: Dictionary, t: Dictionary, opts: Dictionary) -> void:
	if not hostile(src, t):
		return
	if src.features.has("dark_ones_blessing"):
		var thp: int = maxi(1, int(src.mods.cha) + src.class_levels.get("warlock", 0))
		if thp > src.temp_hp:
			src.temp_hp = thp
			log_line("  %s gains %d temp HP (Dark One's Blessing)." % [nm(src), thp])
	if src.features.has("grim_harvest") and opts.get("spell_level", 0) > 0:
		var lvl: int = opts.spell_level
		var heal: int = lvl * (3 if opts.get("school", "") == "necromancy" else 2)
		heal_creature(src, heal, src, "Grim Harvest")
	for e in t.effects:
		if e.get("tag", "") == "hexblade_curse" and e.get("src", "") == src.id:
			heal_creature(src, maxi(1, src.class_levels.get("warlock", 0) + int(src.mods.cha)), src, "Hexblade's Curse")
	if src.get("turn", {}).size() > 0:
		src.turn["killed"] = true

## Revivify: a creature that died within the last minute (10 rounds of game time).
func revivable(t: Dictionary) -> bool:
	if t.is_empty() or t.get("dead", false) or not t.death.get("dead", false):
		return false
	return int(s.get("clock", 0)) - int(t.death.get("died_at", s.get("clock", 0))) <= 10

func heal_creature(t: Dictionary, amount: int, src: Dictionary, why := "") -> int:
	if t.death.dead or t.dead:
		return 0
	if mod_any(t, "no_heal"):
		log_line("  %s can't regain hit points right now." % nm(t))
		return 0
	var before: int = t.hp
	t.hp = mini(eff_max_hp(t), maxi(t.hp, 0) + amount)
	var gained: int = t.hp - maxi(before, 0)
	if before <= 0 and t.hp > 0:
		t.death = {"s": 0, "f": 0, "stable": false, "dead": false}
		log_line("  %s regains consciousness!" % nm(t))
	# Effects that last until the creature regains a hit point (a caltrop in the foot).
	if gained > 0:
		remove_effects_where(t, func(e): return e.get("until_healed", false))
	log_line("  %s regains [color=#7fdc7f]%d[/color] HP%s." % [nm(t), gained, (" (" + why + ")") if why != "" else ""])
	float_text(t.id, "+%d" % gained, "#7fdc7f")
	return gained

func grant_temp_hp(t: Dictionary, amount: int, why := "") -> void:
	if amount > t.temp_hp:
		t.temp_hp = amount
		log_line("  %s gains %d temporary HP%s." % [nm(t), amount, (" (" + why + ")") if why != "" else ""])
		float_text(t.id, "+%d temp" % amount, "#8fd0ff")
