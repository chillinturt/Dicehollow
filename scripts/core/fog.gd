class_name Fog
extends RefCounted
## Fog of war. The DM picks a mode in state.fog:
##   "off"  - everyone sees the whole map and every creature.
##   "soft" - players see all terrain, but only see creatures, zones and auras their side can see now.
##   "hard" - like soft, and terrain the party has never seen is blacked out until someone sees it.
## Vision is shared by the whole party by default; with state.fog.shared off each player sees only
## what their own characters see. state.fog.range (feet, 0 = unlimited) is how far creatures see,
## as in a dark dungeon; darkvision, blindsight, tremorsense and truesight reach further.
## state.fog_seen remembers what has been seen: creature id -> PackedByteArray (1 per seen cell),
## plus "*" for cells the DM revealed by hand. The server updates it (see update_seen); every peer
## works out the current view from the same state with view_for, so nothing extra goes over the wire.

const MODES := ["off", "soft", "hard"]
const DM_REVEAL := "*"

static var _cache := {}   # vision key -> PackedByteArray

static func settings(s: Dictionary) -> Dictionary:
	var f: Dictionary = s.get("fog", {})
	return {"mode": str(f.get("mode", "off")), "shared": bool(f.get("shared", true)), "range": int(f.get("range", 0))}

static func enabled(s: Dictionary) -> bool:
	return settings(s).mode != "off"

# ================================================================ vision of one creature

## Feet a creature perceives without light: the best of its darkvision / blindsight / tremorsense / truesight.
static func special_sight_ft(c: Dictionary) -> int:
	var best := 0
	var re := RegEx.new()
	re.compile("(darkvision|blindsight|tremorsense|truesight)\\s*(\\d+)")
	for m in re.search_all(str(c.get("senses", "")).to_lower()):
		best = maxi(best, int(m.get_string(2)))
	return best

static func _sense_ft(c: Dictionary, sense: String) -> int:
	var re := RegEx.new()
	re.compile(sense + "\\s*(\\d+)")
	var m := re.search(str(c.get("senses", "")).to_lower())
	return int(m.get_string(1)) if m else 0

## How many cells `c` sees in the dark on its own (grid distance), or -1 for no limit. Light from torches and
## lanterns is shared by everyone who can see the lit cells (see light_mask), so it isn't counted here.
static func sight_cells(s: Dictionary, c: Dictionary) -> int:
	var rng: int = settings(s).range
	if rng <= 0:
		return -1
	return maxi(rng, special_sight_ft(c)) / 5

## Every light on the map: [{"cid", "pos", "ft", "cone", "dir"}] (Inventory.light_sources of each creature;
## a bullseye lantern's beam points where its bearer last moved or aimed).
static func lights(eng: EngineBase) -> Array:
	var out: Array = []
	for c in eng.all_combatants():
		if not eng.alive(c) or not c.has("pos") or eng.rope_space(c) != "":
			continue
		for src in Inventory.light_sources(c):
			var f = c.get("facing", [1, 0])
			var dir := Vector2i(int(f[0]), int(f[1])) if f is Array and f.size() == 2 and (int(f[0]) != 0 or int(f[1]) != 0) else Vector2i(1, 0)
			out.append({"cid": c.id, "pos": c.pos, "ft": int(src.ft), "cone": bool(src.cone), "dir": dir})
	return out

## The cells lit right now, for everyone (a w*h byte mask): each light shines out to its reach, stopped by walls
## and heavily obscured zones; a bullseye lantern only within its cone (as wide as it is long, PHB p.153).
static func light_mask(eng: EngineBase) -> PackedByteArray:
	var s: Dictionary = eng.s
	var w: int = s.w
	var h: int = s.h
	var ls := lights(eng)
	var key := "L|%d|%d|%d|%d|%s" % [w, h, hash(s.cells), _zone_hash(s), str(ls)]
	if _cache.has(key):
		return _cache[key]
	var out := PackedByteArray()
	out.resize(w * h)
	if not ls.is_empty():
		var opaque := opacity(eng, true)
		for l in ls:
			var c: Dictionary = eng.C(str(l.cid))
			var r: int = int(l.ft) / 5
			var m := PackedByteArray()
			m.resize(w * h)
			for q in eng.occupied_cells(c):
				if eng.in_bounds(q):
					m[q.y * w + q.x] = 1
					_shadowcast(m, opaque, w, h, q, r)
			if l.cone:
				var o: Vector2 = Vector2(l.pos) + Vector2(0.5, 0.5)
				var dir := Vector2(l.dir).normalized()
				var half := atan(0.5) + 0.05
				for i in m.size():
					if not m[i]:
						continue
					var v := Vector2(i % w, i / w) + Vector2(0.5, 0.5) - o
					if v.length() > 0.75 and absf(v.angle_to(dir)) > half + 0.45 / maxf(v.length(), 0.5):
						m[i] = 0
			out = _or_into(out, m)
	if _cache.size() > 512:
		_cache.clear()
	_cache[key] = out
	return out

## Whether `c` can see anything at all right now (alive, awake, not tucked away in a pocket space).
static func can_look(eng: EngineBase, c: Dictionary) -> bool:
	if not eng.alive(c) or int(c.get("hp", 0)) <= 0 or eng.has_cond(c, "unconscious"):
		return false
	return eng.rope_space(c) == ""

## The cells `c` sees from `at` (its position when omitted), as a w*h byte mask.
static func vision(eng: EngineBase, c: Dictionary, at = null) -> PackedByteArray:
	var s: Dictionary = eng.s
	var w: int = s.w
	var h: int = s.h
	var p: Vector2i = c.pos if at == null else at
	# Eyes: stopped by walls and by heavily obscured zones (Fog Cloud, Darkness). A blinded creature has none.
	var radius: int = 0 if eng.has_cond(c, "blinded") else sight_cells(s, c)
	if radius < 0:
		radius = w + h
	# Blindsight: only walls stop it, out to its range.
	var blind: int = _sense_ft(c, "blindsight") / 5
	# In the dark, lit cells are seen by anyone with a line of sight to them (light_mask), however far.
	var dark: bool = radius < w + h and not eng.has_cond(c, "blinded")
	var lit := light_mask(eng) if dark else PackedByteArray()
	var any_lit := dark and lit.has(1)
	var key := "%d,%d|%d|%d|%d|%d|%d|%d" % [p.x, p.y, eng.occupied_cells(c, p).size(), radius, blind, hash(s.cells), _zone_hash(s), hash(lit) if any_lit else 0]
	if _cache.has(key):
		return _cache[key]
	var out := PackedByteArray()
	out.resize(w * h)
	var with_zones := opacity(eng, true)
	var walls_only := opacity(eng, false) if blind > 0 else with_zones
	var los := PackedByteArray()
	if any_lit:
		los.resize(w * h)
	for q in eng.occupied_cells(c, p):
		if eng.in_bounds(q):
			out[q.y * w + q.x] = 1
			if radius > 0:
				_shadowcast(out, with_zones, w, h, q, radius)
			if blind > 0:
				_shadowcast(out, walls_only, w, h, q, blind)
			if any_lit:
				_shadowcast(los, with_zones, w, h, q, w + h)
	if any_lit:
		for i in out.size():
			if lit[i] and los[i]:
				out[i] = 1
	if _cache.size() > 512:
		_cache.clear()
	_cache[key] = out
	return out

static func _obscures(z: Dictionary) -> bool:
	var ob = z.get("data", {}).get("obscure", false)
	return ob != "" if ob is String else bool(ob)

static func _zone_hash(s: Dictionary) -> int:
	var parts: Array = []
	for z in s.get("zones", []):
		if _obscures(z):
			parts.append(z.cells)
	return hash(parts)

## Cells that block sight: walls, and (with_zones) heavily obscured zones.
static func opacity(eng: EngineBase, with_zones := true) -> PackedByteArray:
	var s: Dictionary = eng.s
	var w: int = s.w
	var out := PackedByteArray()
	out.resize(w * int(s.h))
	for i in out.size():
		out[i] = 1 if s.cells[i] == EngineBase.WALL else 0
	if with_zones:
		for z in s.get("zones", []):
			if _obscures(z):
				for q in z.cells:
					if eng.in_bounds(q):
						out[q.y * w + q.x] = 1
	return out

const _OCT := [[1, 0, 0, -1, -1, 0, 0, 1], [0, 1, -1, 0, 0, -1, 1, 0], [0, 1, 1, 0, 0, -1, -1, 0], [1, 0, 0, 1, -1, 0, 0, -1]]

## Recursive shadowcasting over the 8 octants around `o`. Blocking cells are lit (you see the wall)
## but nothing behind them is. Range is grid distance (5e: diagonals count as 5 ft).
static func _shadowcast(out: PackedByteArray, opaque: PackedByteArray, w: int, h: int, o: Vector2i, radius: int) -> void:
	for oc in 8:
		_cast(out, opaque, w, h, o, 1, 1.0, 0.0, radius, _OCT[0][oc], _OCT[1][oc], _OCT[2][oc], _OCT[3][oc])

static func _cast(out: PackedByteArray, opaque: PackedByteArray, w: int, h: int, o: Vector2i, row: int, start: float, end: float, radius: int, xx: int, xy: int, yx: int, yy: int) -> void:
	if start < end:
		return
	var new_start := 0.0
	for j in range(row, radius + 1):
		var dx := -j - 1
		var dy := -j
		var blocked := false
		while dx <= 0:
			dx += 1
			var x := o.x + dx * xx + dy * xy
			var y := o.y + dx * yx + dy * yy
			var l_slope := (dx - 0.5) / (dy + 0.5)
			var r_slope := (dx + 0.5) / (dy - 0.5)
			if start < r_slope:
				continue
			elif end > l_slope:
				break
			var inside := x >= 0 and y >= 0 and x < w and y < h
			if inside:
				out[y * w + x] = 1
			var solid: bool = not inside or opaque[y * w + x] == 1
			if blocked:
				if solid:
					new_start = r_slope
					continue
				blocked = false
				start = new_start
			elif solid and j < radius:
				blocked = true
				_cast(out, opaque, w, h, o, j + 1, start, l_slope, radius, xx, xy, yx, yy)
				new_start = r_slope
		if blocked:
			break

# ================================================================ who looks for whom

## The creatures whose eyes a viewer uses. peer 0 means "the party as a whole" (the DM's preview).
static func sources(eng: EngineBase, peer: int) -> Array:
	var shared: bool = settings(eng.s).shared or peer == 0
	return eng.all_combatants().filter(func(c):
		return c.get("team", "") == "party" and (shared or int(c.get("owner", 1)) == peer))

## Ids whose memories (fog_seen) a viewer shares.
static func memory_keys(eng: EngineBase, peer: int) -> Array:
	var shared: bool = settings(eng.s).shared or peer == 0
	var out: Array = [DM_REVEAL]
	for id in eng.s.get("fog_seen", {}):
		if id == DM_REVEAL:
			continue
		var c: Dictionary = eng.C(id)
		if shared:
			if c.is_empty() or c.get("team", "") == "party":
				out.append(id)
		elif not c.is_empty() and int(c.get("owner", 1)) == peer:
			out.append(id)
	return out

## What a viewer sees: {"mode", "visible": mask, "explored": mask, "self": {cid: true}} where self lists
## the viewer's own eyes (always drawn). Returns {} when fog is off.
static func view_for(eng: EngineBase, peer: int) -> Dictionary:
	var s: Dictionary = eng.s
	if not enabled(s):
		return {}
	var n: int = int(s.w) * int(s.h)
	var vis := PackedByteArray()
	vis.resize(n)
	var mine := {}
	for c in sources(eng, peer):
		mine[c.id] = true
		if can_look(eng, c):
			vis = _or_into(vis, vision(eng, c))
	var known := vis.duplicate()
	var seen: Dictionary = s.get("fog_seen", {})
	for k in memory_keys(eng, peer):
		if seen.has(k):
			known = _or_into(known, seen[k])
	return {"mode": settings(s).mode, "visible": vis, "explored": known, "self": mine}

static func _or_into(dst: PackedByteArray, src: PackedByteArray) -> PackedByteArray:
	if src.size() != dst.size():
		return dst
	for i in dst.size():
		if src[i]:
			dst[i] = 1
	return dst

## Whether a viewer (view from view_for) can see creature c.
static func sees(view: Dictionary, eng: EngineBase, c: Dictionary) -> bool:
	if view.is_empty() or view.self.has(c.get("id", "")):
		return true
	var w: int = eng.s.w
	for q in eng.occupied_cells(c):
		if eng.in_bounds(q) and view.visible[q.y * w + q.x]:
			return true
	return false

static func cell_visible(view: Dictionary, eng: EngineBase, p: Vector2i) -> bool:
	return view.is_empty() or (eng.in_bounds(p) and view.visible[p.y * int(eng.s.w) + p.x] == 1)

# ================================================================ server bookkeeping

## Server: add what every party creature sees now (and saw along any path it just walked) to its memory.
static func update_seen(eng: EngineBase, events: Array = []) -> void:
	var s: Dictionary = eng.s
	if not enabled(s):
		return
	if not s.has("fog_seen"):
		s.fog_seen = {}
	var n: int = int(s.w) * int(s.h)
	var paths := {}
	for e in events:
		if e.get("t", "") == "move":
			if not paths.has(e.cid):
				paths[e.cid] = []
			paths[e.cid].append_array(e.get("path", []))
	for c in eng.all_combatants():
		if c.get("team", "") != "party" or not can_look(eng, c):
			continue
		var mem: PackedByteArray = s.fog_seen.get(c.id, PackedByteArray())
		if mem.size() != n:
			mem = PackedByteArray()
			mem.resize(n)
		for p in paths.get(c.id, []):
			if eng.in_bounds(Vector2i(p)):
				mem = _or_into(mem, vision(eng, c, Vector2i(p)))
		mem = _or_into(mem, vision(eng, c))
		s.fog_seen[c.id] = mem

## Server: forget everything seen (the map changed size, or the DM re-fogged the map).
static func reset(s: Dictionary) -> void:
	s.fog_seen = {}

## Server: the DM reveals cells for everyone, or fogs them again (forgotten by every creature).
static func paint(s: Dictionary, cells: Array, reveal: bool) -> void:
	if not s.has("fog_seen"):
		s.fog_seen = {}
	var w: int = s.w
	var n: int = w * int(s.h)
	if reveal:
		var mem: PackedByteArray = s.fog_seen.get(DM_REVEAL, PackedByteArray())
		if mem.size() != n:
			mem = PackedByteArray()
			mem.resize(n)
		for p in cells:
			if p.x >= 0 and p.y >= 0 and p.x < w and p.y < s.h:
				mem[p.y * w + p.x] = 1
		s.fog_seen[DM_REVEAL] = mem
		return
	for k in s.fog_seen:
		var m: PackedByteArray = s.fog_seen[k]
		if m.size() != n:
			continue
		for p in cells:
			if p.x >= 0 and p.y >= 0 and p.x < w and p.y < s.h:
				m[p.y * w + p.x] = 0
		s.fog_seen[k] = m

static func reveal_all(s: Dictionary) -> void:
	var all := PackedByteArray()
	all.resize(int(s.w) * int(s.h))
	all.fill(1)
	if not s.has("fog_seen"):
		s.fog_seen = {}
	s.fog_seen[DM_REVEAL] = all
