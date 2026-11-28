class_name MapStream
extends RefCounted
## Endless maps: new ground is generated as the party comes within sight of a map edge, so a fight in a forest,
## a cave system or a town's streets can keep moving instead of hitting the end of the map.
##
## A generated map built with "endless" carries state.stream: the generator settings, and (ox, oy), the world
## position of local cell (0, 0). The world is cut into CHUNK × CHUNK squares; each chunk is generated from the
## seed and its own coordinates, so the same place always comes out the same. When a party creature can see a
## map edge (shadowcast to LOOK cells, walls block), the map grows by one chunk-wide strip on that side. Growing
## west or north moves everything already on the map (creatures, zones, items, objects, fog memory...), and an
## {"t": "map_shift", "d": Vector2i} event tells clients to move their camera with it.
## New ground that can't be walked to from where the party is gets a tunnel dug to it (or is filled in, if tiny).
## Past `max` cells on a side, the strip on the far side is dropped, if no living creature is in or near it;
## ground dropped this way comes back freshly generated if the party returns (fights and loot there are lost).

const CHUNK := 20
const LOOK := 12
const LAYOUTS := ["outdoor", "cave", "town"]
const DEFAULT_MAX := 100
const MAX_LIMIT := 160

const FLOOR := EngineBase.FLOOR
const WALL := EngineBase.WALL
const DIFFICULT := EngineBase.DIFFICULT
const PIT := EngineBase.PIT

## Settings a stream keeps from the generator (what chunks need to look like the rest of the map, and the
## encounter settings wandering monsters are picked with).
const KEEP := ["terrain", "seed", "obstacles", "difficult", "water", "pits", "cover", "style", "interactables", "loot", "habitat",
	"party", "difficulty", "types", "match_habitat", "allow_custom", "composition", "strength", "max_monsters"]

static func supports(terrain: String) -> bool:
	return str(MapGenerator.TERRAINS.get(terrain, {}).get("layout", "")) in LAYOUTS

static func enabled(s: Dictionary) -> bool:
	var st = s.get("stream", {})
	return st is Dictionary and st.get("on", false)

## The record a generated endless map carries (map "stream", state.stream).
static func make(settings: Dictionary) -> Dictionary:
	var keep := {}
	for k in KEEP:
		if settings.has(k):
			keep[k] = settings[k]
	return {"on": true, "set": keep, "ox": 0, "oy": 0, "max": clampi(int(settings.get("endless_max", DEFAULT_MAX)), 40, MAX_LIMIT),
		"foes": clampf(float(settings.get("endless_foes", 0.0)), 0.0, 1.0), "spawned": [], "grown": 0}

## A stream record from a map file, checked.
static func clean(st) -> Dictionary:
	if not st is Dictionary or not st.get("on", false) or not st.get("set", null) is Dictionary:
		return {}
	var out := make(st.set)
	out.set = st.set.duplicate(true)
	out.ox = int(st.get("ox", 0))
	out.oy = int(st.get("oy", 0))
	out.max = clampi(int(st.get("max", DEFAULT_MAX)), 40, MAX_LIMIT)
	out.foes = clampf(float(st.get("foes", 0.0)), 0.0, 1.0)
	var sp: Array = []
	for k in st.get("spawned", []):
		sp.append(str(k))
	out.spawned = sp.slice(-400)
	out.grown = int(st.get("grown", 0))
	return out

# ================================================================ growing the map

## Server: grow the map wherever the party can see an edge. Returns {"shift": Vector2i (how far existing
## content moved), "rects": [Rect2i] (the new ground, in local cells), "foes": [{"mid", "pos"}] (wandering
## monsters for the caller to place)}, or {} when nothing changed.
static func update(eng: EngineBase) -> Dictionary:
	if not enabled(eng.s):
		return {}
	var st: Dictionary = eng.s.stream
	var sides := sides_in_view(eng)
	if sides.is_empty():
		return {}
	var out := {"shift": Vector2i.ZERO, "rects": [], "foes": []}
	for side in ["west", "east", "north", "south"]:
		if sides.has(side):
			_grow(eng, st, side, out)
	if out.rects.is_empty():
		return {}
	stitch(eng, out.rects)
	return out

## Map edges a party creature can see, within LOOK cells: {"west": true, ...}.
static func sides_in_view(eng: EngineBase) -> Dictionary:
	var s: Dictionary = eng.s
	var w: int = s.w
	var h: int = s.h
	var out := {}
	var opaque: PackedByteArray = PackedByteArray()
	for c in eng.all_combatants():
		if c.get("team", "") != "party" or not Fog.can_look(eng, c) or eng.has_cond(c, "blinded"):
			continue
		var near := false
		for q in eng.occupied_cells(c):
			if q.x < LOOK or q.y < LOOK or q.x >= w - LOOK or q.y >= h - LOOK:
				near = true
		if not near:
			continue
		if opaque.is_empty():
			opaque = Fog.opacity(eng, false)
		var mask := PackedByteArray()
		mask.resize(w * h)
		for q in eng.occupied_cells(c):
			if eng.in_bounds(q):
				mask[q.y * w + q.x] = 1
				Fog._shadowcast(mask, opaque, w, h, q, LOOK)
		for x in w:
			if mask[x]: out.north = true
			if mask[(h - 1) * w + x]: out.south = true
		for y in h:
			if mask[y * w]: out.west = true
			if mask[y * w + w - 1]: out.east = true
	return out

static func _opposite(side: String) -> String:
	return {"west": "east", "east": "west", "north": "south", "south": "north"}[side]

static func _grow(eng: EngineBase, st: Dictionary, side: String, out: Dictionary) -> void:
	var s: Dictionary = eng.s
	var horiz := side in ["west", "east"]
	var size_now: int = int(s.w) if horiz else int(s.h)
	var mx: int = int(st.get("max", DEFAULT_MAX))
	if size_now + CHUNK > mx:
		if not _trim(eng, st, _opposite(side), size_now + CHUNK - mx, out):
			return
	var w: int = s.w
	var h: int = s.h
	var d := Vector2i.ZERO
	var rect: Rect2i
	match side:
		"west":
			d = Vector2i(CHUNK, 0)
			rect = Rect2i(0, 0, CHUNK, h)
		"north":
			d = Vector2i(0, CHUNK)
			rect = Rect2i(0, 0, w, CHUNK)
		"east":
			rect = Rect2i(w, 0, CHUNK, h)
		_:
			rect = Rect2i(0, h, w, CHUNK)
	resize_shift(s, w + (CHUNK if horiz else 0), h + (0 if horiz else CHUNK), d)
	if d != Vector2i.ZERO:
		st.ox = int(st.ox) - d.x
		st.oy = int(st.oy) - d.y
		out.shift += d
		for i in out.rects.size():
			out.rects[i] = Rect2i(out.rects[i].position + d, out.rects[i].size)
		for f in out.foes:
			f.pos += d
	out.rects.append(rect)
	st.grown = int(st.get("grown", 0)) + 1
	_fill(eng, st, rect, out)

## Drop `n` columns / rows on `side` to keep the map under its size limit. Refused (false) while a living
## creature stands in them, or a party creature is close enough to see the edge move.
static func _trim(eng: EngineBase, st: Dictionary, side: String, n: int, out: Dictionary) -> bool:
	var s: Dictionary = eng.s
	var w: int = s.w
	var h: int = s.h
	var strip: Rect2i
	match side:
		"west": strip = Rect2i(0, 0, n, h)
		"east": strip = Rect2i(w - n, 0, n, h)
		"north": strip = Rect2i(0, 0, w, n)
		_: strip = Rect2i(0, h - n, w, n)
	var guard := strip.grow(LOOK + 2)
	var bodies: Array = eng.all_combatants() + s.get("reserve", {}).values()
	for c in bodies:
		if not c.has("pos"):
			continue
		var live: bool = eng.alive(c) and not c.get("dead", false)
		for q in eng.occupied_cells(c):
			if live and strip.has_point(q):
				return false
			if live and c.get("team", "") == "party" and guard.has_point(q):
				return false
	# What's left in the strip goes: corpses of monsters (the caller removes them), loose items, objects, zones.
	for c in eng.all_combatants():
		if c.get("kind", "") != "pc" and not eng.alive(c) and strip.has_point(c.pos):
			if not out.has("remove"):
				out.remove = []
			out.remove.append(str(c.id))
	var d := Vector2i.ZERO
	var nw := w
	var nh := h
	match side:
		"west":
			d = Vector2i(-n, 0)
			nw = w - n
		"east": nw = w - n
		"north":
			d = Vector2i(0, -n)
			nh = h - n
		_: nh = h - n
	resize_shift(s, nw, nh, d)
	if d != Vector2i.ZERO:
		st.ox = int(st.ox) - d.x
		st.oy = int(st.oy) - d.y
		out.shift += d
		for i in out.rects.size():
			out.rects[i] = Rect2i(out.rects[i].position + d, out.rects[i].size)
		for f in out.foes:
			f.pos += d
	return true

## Change the map to nw × nh with everything on it moved by `d` (cells, ground, fog memory, props, labels, and
## every Vector2i anywhere in the state: creatures, zones, items, objects, ropes, start points...). Whatever ends
## up off the map is dropped where that is safe (props, labels, items, objects, start points).
static func resize_shift(s: Dictionary, nw: int, nh: int, d: Vector2i) -> void:
	var w: int = s.w
	var h: int = s.h
	s.cells = _remap(s.cells, w, h, nw, nh, d, FLOOR)
	var g: PackedByteArray = s.get("ground", PackedByteArray())
	if g.size() == w * h:
		s.ground = _remap(g, w, h, nw, nh, d, 0)
	var seen: Dictionary = s.get("fog_seen", {})
	for k in seen.keys():
		var m: PackedByteArray = seen[k]
		if m.size() == w * h:
			seen[k] = _remap(m, w, h, nw, nh, d, 0)
		else:
			seen.erase(k)
	if d != Vector2i.ZERO:
		for key in s.keys():
			if key in ["cells", "ground", "fog_seen", "log", "stream"]:
				continue
			if s[key] is Vector2i:
				s[key] = s[key] + d
			else:
				shift_in_place(s[key], d)
		for p in s.get("props", []):
			p.x = int(p.x) + d.x
			p.y = int(p.y) + d.y
		for l in s.get("labels", []):
			l.x = float(l.x) + d.x
			l.y = float(l.y) + d.y
	var inside := func(p: Vector2i) -> bool: return p.x >= 0 and p.y >= 0 and p.x < nw and p.y < nh
	s.props = s.get("props", []).filter(func(p): return inside.call(Vector2i(int(p.x), int(p.y))))
	s.labels = s.get("labels", []).filter(func(l): return float(l.x) >= 0 and float(l.y) >= 0 and float(l.x) <= nw and float(l.y) <= nh)
	s.items = s.get("items", []).filter(func(it): return not it.get("pos", null) is Vector2i or inside.call(it.pos))
	s.objects = s.get("objects", []).filter(func(o): return not o.get("pos", null) is Vector2i or inside.call(o.pos))
	s.spawns = s.get("spawns", []).filter(func(p): return not p is Vector2i or inside.call(p))
	for z in s.get("zones", []):
		if z.get("cells", null) is Array:
			z.cells = z.cells.filter(func(p): return not p is Vector2i or inside.call(p))
	s.w = nw
	s.h = nh

## A copy of `v` with every Vector2i in it (values and dictionary keys, at any depth) moved by `d`.
static func shift_value(v, d: Vector2i):
	if v is Vector2i:
		return v + d
	if v is Dictionary:
		var out := {}
		for k in v:
			out[k + d if k is Vector2i else k] = shift_value(v[k], d)
		return out
	if v is Array:
		var out2: Array = []
		out2.resize(v.size())
		for i in v.size():
			out2[i] = shift_value(v[i], d)
		return out2
	return v

## Shift every Vector2i in `v` in place (keeps the same Dictionary / Array objects, which the UI may hold).
static func shift_in_place(v, d: Vector2i) -> void:
	if v is Dictionary:
		# Cells used as keys move too.
		var vkeys: Array = v.keys().filter(func(k): return k is Vector2i)
		if not vkeys.is_empty():
			var moved := {}
			for k in vkeys:
				moved[k + d] = v[k]
				v.erase(k)
			v.merge(moved, true)
		for k in v.keys():
			var x = v[k]
			if x is Vector2i:
				v[k] = x + d
			else:
				shift_in_place(x, d)
	elif v is Array:
		for i in v.size():
			if v[i] is Vector2i:
				v[i] = v[i] + d
			else:
				shift_in_place(v[i], d)

static func _remap(src: PackedByteArray, w: int, h: int, nw: int, nh: int, d: Vector2i, fill: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(nw * nh)
	if fill != 0:
		out.fill(fill)
	for y in h:
		var ny := y + d.y
		if ny < 0 or ny >= nh:
			continue
		for x in w:
			var nx := x + d.x
			if nx >= 0 and nx < nw:
				out[ny * nw + nx] = src[y * w + x]
	return out

## Write generated ground into local rect `r`: terrain, ground materials, props, labels and objects of the
## chunks it covers (props, labels and objects whose anchor falls inside `r`), and maybe wandering monsters.
static func _fill(eng: EngineBase, st: Dictionary, r: Rect2i, out: Dictionary) -> void:
	var s: Dictionary = eng.s
	var w: int = s.w
	var h: int = s.h
	var ox: int = int(st.ox)
	var oy: int = int(st.oy)
	var cache := {}
	var g: PackedByteArray = s.get("ground", PackedByteArray())
	if g.size() != w * h:
		g = PackedByteArray()
		g.resize(w * h)
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var wx := x + ox
			var wy := y + oy
			var key := Vector2i(floori(float(wx) / CHUNK), floori(float(wy) / CHUNK))
			if not cache.has(key):
				cache[key] = chunk(st, key.x, key.y)
			var ch: Dictionary = cache[key]
			var li := (wy - key.y * CHUNK) * CHUNK + (wx - key.x * CHUNK)
			s.cells[y * w + x] = ch.cells[li]
			g[y * w + x] = ch.ground[li]
	s.ground = g
	var props: Array = s.get("props", [])
	var labels: Array = s.get("labels", [])
	for key in cache:
		var ch: Dictionary = cache[key]
		var base: Vector2i = key * CHUNK - Vector2i(ox, oy)
		for p in ch.props:
			var q := base + Vector2i(int(p.x), int(p.y))
			if r.has_point(q):
				var np: Dictionary = p.duplicate()
				np.x = q.x
				np.y = q.y
				props.append(np)
		for l in ch.labels:
			var lq := Vector2(base) + Vector2(float(l.x), float(l.y))
			if r.has_point(Vector2i(floori(lq.x), floori(lq.y))):
				var nl: Dictionary = l.duplicate()
				nl.x = lq.x
				nl.y = lq.y
				labels.append(nl)
		for o in ch.objects:
			var oq := base + Vector2i(int(o.x), int(o.y))
			if r.has_point(oq) and MapObjects.at(s, oq).is_empty():
				var obj := MapObjects.make(str(o.k), oq, int(o.get("under", FLOOR)))
				for k in ["loot", "locked", "dc", "item"]:
					if o.has(k):
						obj[k] = o[k]
				# The chunk already gave the cell its terrain; place() would read it back as "under".
				obj.id = eng.new_id("o")
				MapObjects.list(s).append(obj)
		# Wandering monsters: once per chunk, by chance, when the chunk is first fully inside the map.
		var ck := "%d,%d" % [key.x, key.y]
		var whole := Rect2i(base, Vector2i(CHUNK, CHUNK))
		if float(st.get("foes", 0.0)) > 0.0 and not ck in st.spawned and Rect2i(0, 0, w, h).encloses(whole):
			st.spawned.append(ck)
			if st.spawned.size() > 400:
				st.spawned = st.spawned.slice(-400)
			var frng := RandomNumberGenerator.new()
			frng.seed = hash([int(st.set.get("seed", 0)), key.x, key.y, "foes"])
			if frng.randf() < float(st.foes):
				for f in _foes(st, frng, ch, base):
					out.foes.append(f)
	s.props = props.slice(-6000)
	s.labels = labels.slice(-300)

## A small group of wandering monsters for a chunk: an easy encounter for the party, on open ground.
static func _foes(st: Dictionary, rng: RandomNumberGenerator, ch: Dictionary, base: Vector2i) -> Array:
	var cfg: Dictionary = st.set.duplicate(true)
	if cfg.get("party", []).is_empty():
		return []
	cfg.difficulty = "easy"
	cfg.max_monsters = mini(int(cfg.get("max_monsters", 6)), 4)
	var enc: Dictionary = EncounterBuilder.build(cfg, rng)
	var out: Array = []
	var open: Array = []
	for i in ch.cells.size():
		if ch.cells[i] == FLOOR:
			open.append(Vector2i(i % CHUNK, i / CHUNK))
	if open.is_empty():
		return out
	var anchor: Vector2i = open[rng.randi() % open.size()]
	open.sort_custom(func(a, b): return Vector2(a).distance_squared_to(Vector2(anchor)) < Vector2(b).distance_squared_to(Vector2(anchor)))
	var i := 0
	for p in enc.get("picks", []):
		for n in int(p.count):
			if i >= open.size():
				break
			out.append({"mid": str(p.mid), "pos": base + open[i]})
			i += 2
	return out

# ================================================================ connecting new ground

## Make the new ground in `rects` reachable on foot from where the party stands: every pocket of open ground
## there that the party can't walk to gets the shortest tunnel dug to it (through as few walls as possible,
## preferring new ground); pockets under 8 cells are filled in instead.
static func stitch(eng: EngineBase, rects: Array) -> void:
	var s: Dictionary = eng.s
	var w: int = s.w
	var h: int = s.h
	var n := w * h
	var starts: Array = []
	for c in eng.all_combatants():
		if c.get("team", "") == "party" and eng.alive(c) and not eng.in_rope(c):
			for q in eng.occupied_cells(c):
				if eng.in_bounds(q) and not eng.blocks_move(q):
					starts.append(q)
	if starts.is_empty():
		for p in s.get("spawns", []):
			if p is Vector2i and eng.in_bounds(p) and not eng.blocks_move(p):
				starts.append(p)
	if starts.is_empty():
		return
	var is_new := PackedByteArray()
	is_new.resize(n)
	for r in rects:
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				if x >= 0 and y >= 0 and x < w and y < h:
					is_new[y * w + x] = 1
	var main := _flood(s, starts)
	# Pockets in the new ground the party can't reach.
	var seen := PackedByteArray()
	seen.resize(n)
	var pockets: Array = []
	for i in n:
		if is_new[i] and not main[i] and not seen[i] and _open(s.cells[i]):
			var reg: Array = []
			var q: Array = [i]
			seen[i] = 1
			var k := 0
			while k < q.size():
				var cur: int = q[k]
				k += 1
				reg.append(cur)
				for nb in _nbrs(cur, w, h):
					if not seen[nb] and not main[nb] and _open(s.cells[nb]):
						seen[nb] = 1
						q.append(nb)
			pockets.append(reg)
	if pockets.is_empty():
		return
	# Cheapest dig from the party's ground to every cell: walls cost 1 to dig in new ground, 4 in old.
	var dist := PackedInt32Array()
	dist.resize(n)
	dist.fill(1 << 30)
	var parent := PackedInt32Array()
	parent.resize(n)
	parent.fill(-1)
	var buckets: Array = [[]]
	for i in n:
		if main[i]:
			dist[i] = 0
			buckets[0].append(i)
	var b := 0
	while b < buckets.size():
		var bucket: Array = buckets[b]
		var j := 0
		while j < bucket.size():
			var cur: int = bucket[j]
			j += 1
			if dist[cur] != b:
				continue
			for nb in _nbrs(cur, w, h):
				var step := 0 if _open(s.cells[nb]) else (1 if is_new[nb] else 4)
				var nd := b + step
				if nd < dist[nb]:
					dist[nb] = nd
					parent[nb] = cur
					while buckets.size() <= nd:
						buckets.append([])
					buckets[nd].append(nb)
		b += 1
	# Big pockets first: their tunnels may run through tiny pockets, which must then stay open.
	pockets.sort_custom(func(x, y): return x.size() > y.size())
	for reg in pockets:
		if reg.size() < 8:
			for i in reg:
				if is_new[i] and not main[i]:
					s.cells[i] = WALL
			continue
		var best: int = reg[0]
		for i in reg:
			if dist[i] < dist[best]:
				best = i
		var cur: int = best
		var guard := 0
		while cur >= 0 and not main[cur] and guard < n:
			guard += 1
			if not _open(s.cells[cur]):
				_dig(eng, Vector2i(cur % w, cur / w))
			main[cur] = 1
			cur = parent[cur]
		for i in reg:
			main[i] = 1

static func _open(v: int) -> bool:
	return v != WALL and v != PIT

static func _nbrs(i: int, w: int, h: int) -> Array:
	var x := i % w
	var y := i / w
	var out: Array = []
	if x > 0: out.append(i - 1)
	if x < w - 1: out.append(i + 1)
	if y > 0: out.append(i - w)
	if y < h - 1: out.append(i + w)
	return out

static func _flood(s: Dictionary, starts: Array) -> PackedByteArray:
	var w: int = s.w
	var h: int = s.h
	var out := PackedByteArray()
	out.resize(w * h)
	var q: Array = []
	for p in starts:
		var i: int = p.y * w + p.x
		if not out[i]:
			out[i] = 1
			q.append(i)
	var k := 0
	while k < q.size():
		var cur: int = q[k]
		k += 1
		for nb in _nbrs(cur, w, h):
			if not out[nb] and _open(s.cells[nb]):
				out[nb] = 1
				q.append(nb)
	return out

## Open a wall or pit cell for a tunnel: floor, and whatever stood there (a prop, an object) goes.
static func _dig(eng: EngineBase, p: Vector2i) -> void:
	var s: Dictionary = eng.s
	for o in MapObjects.at(s, p):
		MapObjects.list(s).erase(o)
	eng.set_cell(p, FLOOR)
	var g: PackedByteArray = s.get("ground", PackedByteArray())
	if g.size() == int(s.w) * int(s.h) and g[p.y * int(s.w) + p.x] in [MapGenerator.G_PLANK, MapGenerator.G_COBBLE, MapGenerator.G_FLAG, MapGenerator.G_LEAF]:
		g[p.y * int(s.w) + p.x] = MapGenerator.G_DIRT
		s.ground = g
	s.props = s.get("props", []).filter(func(pr): return not Rect2i(int(pr.x), int(pr.y), int(pr.get("w", 1)), int(pr.get("h", 1))).has_point(p))

# ================================================================ chunks

## The ground of chunk (cx, cy): {"cells", "ground" (CHUNK × CHUNK bytes), "props", "labels", "objects" (map-file
## form, chunk-local cells)}. The same seed and chunk always give the same result.
static func chunk(st: Dictionary, cx: int, cy: int) -> Dictionary:
	var cfg: Dictionary = st.get("set", {})
	var terrain := str(cfg.get("terrain", "forest"))
	var t: Dictionary = MapGenerator.TERRAINS.get(terrain, MapGenerator.TERRAINS.forest)
	var g := MapGenerator.new()
	g.s = MapGenerator.defaults_for(terrain)
	g.s.merge(cfg, true)
	g.w = CHUNK
	g.h = CHUNK
	g.rng.seed = hash([int(cfg.get("seed", 0)), cx, cy, terrain, "chunk"])
	g.cells = PackedByteArray()
	g.cells.resize(CHUNK * CHUNK)
	g.ground = PackedByteArray()
	g.ground.resize(CHUNK * CHUNK)
	match str(t.layout):
		"cave": _cave_chunk(g)
		"town": _town_chunk(g)
		_: _outdoor_chunk(g)
	var level := 1
	var party: Array = cfg.get("party", [])
	if not party.is_empty():
		var tot := 0
		for p in party:
			tot += int(p.get("level", 1)) if p is Dictionary else 1
		level = maxi(1, tot / party.size())
	var objs: Array = MapObjects.scatter(g, float(cfg.get("interactables", 0.0)), level, str(t.layout), str(cfg.get("loot", "normal")))
	return {"cells": g.cells, "ground": g.ground, "props": g.props, "labels": g.labels, "objects": objs}

## Open country: clumps of trees or boulders, pools, rough ground, pits and cover, as the terrain's sliders say.
static func _outdoor_chunk(g) -> void:
	g.cells.fill(FLOOR)
	for i in g._density(float(g.s.obstacles), 0.06):
		var c: Vector2i = g._random_cell_of([FLOOR])
		if c.x >= 0:
			g._blob(c, g.rng.randf_range(0.6, 2.2), WALL, [FLOOR])
	g._overlays([FLOOR])

## Caves: smoothed random rock (open at the chunk's edges), with a winding tunnel from the middle of the chunk
## to the middle of each edge so neighbouring chunks meet.
static func _cave_chunk(g) -> void:
	var w: int = g.w
	var h: int = g.h
	var fill := lerpf(0.4, 0.55, float(g.s.obstacles))
	for y in h:
		for x in w:
			g.cells[y * w + x] = WALL if g.rng.randf() < fill else FLOOR
	for it in 4:
		var nxt: PackedByteArray = g.cells.duplicate()
		for y in h:
			for x in w:
				var n := 0
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						if dx == 0 and dy == 0:
							continue
						var q := Vector2i(x + dx, y + dy)
						# Beyond the chunk counts as half rock, so edges neither seal nor gape.
						if not g._in(q):
							n += 1 if (x + y + it) % 2 == 0 else 0
						elif g.cells[q.y * w + q.x] == WALL:
							n += 1
				nxt[y * w + x] = WALL if n >= 5 else (FLOOR if n <= 3 else g.cells[y * w + x])
		g.cells = nxt
	var mid := Vector2i(w / 2, h / 2)
	for target in [Vector2i(w / 2, 0), Vector2i(w / 2, h - 1), Vector2i(0, h / 2), Vector2i(w - 1, h / 2)]:
		var p: Vector2i = mid
		var guard := 0
		while p != target and guard < 200:
			guard += 1
			for dy in 2:
				for dx in 2:
					if g._in(p + Vector2i(dx, dy)):
						g._put(p + Vector2i(dx, dy), FLOOR)
			var dv: Vector2i = target - p
			if g.rng.randf() < 0.3:
				p += Vector2i(0, signi(dv.y)) if absi(dv.x) > absi(dv.y) else Vector2i(signi(dv.x), 0)
				p += Vector2i(g.rng.randi_range(-1, 1), 0) if dv.x == 0 else Vector2i(0, g.rng.randi_range(-1, 1))
			else:
				p += Vector2i(signi(dv.x), 0) if absi(dv.x) >= absi(dv.y) else Vector2i(0, signi(dv.y))
			p = Vector2i(clampi(p.x, 0, w - 1), clampi(p.y, 0, h - 1))
		g._put(target, FLOOR)
	g._overlays([FLOOR])

## Town streets: a crossroads through the middle of every chunk (so streets run on from chunk to chunk), with a
## building or an open yard in each of the four blocks between them.
static func _town_chunk(g) -> void:
	var style := str(g.s.get("style", "human"))
	if not StructureBuilder.STYLE_MATS.has(style):
		style = "human"
	var mats: Dictionary = StructureBuilder.STYLE_MATS[style]
	var w: int = g.w
	var h: int = g.h
	g.cells.fill(FLOOR)
	var lot_mat: int = MapGenerator.G_FLAG if style == "dwarf" else MapGenerator.G_GRASS
	g.ground.fill(lot_mat)
	var r0 := w / 2 - 1   # street rows / columns r0 and r0 + 1
	for i in w:
		for k in 2:
			g.gset(Vector2i(i, r0 + k), int(mats.street))
			g.gset(Vector2i(r0 + k, i), int(mats.street))
			g.keep_clear[Vector2i(i, r0 + k)] = true
			g.keep_clear[Vector2i(r0 + k, i)] = true
	# Four blocks: [rect, the side facing the crossroads].
	var q := r0   # block size along each axis
	var blocks: Array = [[Rect2i(0, 0, q, q), ["south", "east"]], [Rect2i(r0 + 2, 0, w - r0 - 2, q), ["south", "west"]],
		[Rect2i(0, r0 + 2, q, h - r0 - 2), ["north", "east"]], [Rect2i(r0 + 2, r0 + 2, w - r0 - 2, h - r0 - 2), ["north", "west"]]]
	var built := float(g.s.get("obstacles", 0.6))
	for bl in blocks:
		var r: Rect2i = bl[0]
		var side: String = bl[1][g.rng.randi() % 2]
		if g.rng.randf() > 0.25 + built * 0.7:
			_yard(g, r)
			continue
		var kinds := ["house", "house", "house", "shop", "smithy", "apothecary", "stable"]
		if r.size.x >= 9 and r.size.y >= 9 and g.rng.randf() < 0.15:
			kinds = ["chapel"]
		var kind: String = kinds[g.rng.randi() % kinds.size()]
		var sz: Array = StructureBuilder.SIZES.get(kind, [5, 7, 5, 6])
		var along := mini(g.rng.randi_range(int(sz[0]), int(sz[1])), (r.size.x if side in ["north", "south"] else r.size.y) - 1)
		var depth := mini(g.rng.randi_range(int(sz[2]), int(sz[3])), (r.size.y if side in ["north", "south"] else r.size.x) - 1)
		if along < 5 or depth < 5:
			_yard(g, r)
			continue
		var bw := along if side in ["north", "south"] else depth
		var bh := depth if side in ["north", "south"] else along
		# Flush against the street it faces, a step back from the other one.
		var bx := r.position.x + (r.size.x - bw) / 2
		var by := r.position.y + (r.size.y - bh) / 2
		match side:
			"south": by = r.end.y - bh
			"north": by = r.position.y
			"east": bx = r.end.x - bw
			"west": bx = r.position.x
		StructureBuilder.building(g, Rect2i(bx, by, bw, bh), side, kind, style, mats)
	# Trees and a few rough patches between the buildings.
	for i in g._density(float(g.s.get("cover", 0.3)), 0.03):
		var c: Vector2i = g._random_cell_of([FLOOR])
		if c.x >= 0 and not g.keep_clear.has(c) and not g._near(c, WALL, 1) and g.gat(c) == lot_mat:
			g._put(c, WALL)
			g.prop("tree", c.x, c.y)
	var keep_d := float(g.s.get("difficult", 0.25))
	g.s.difficult = keep_d * 0.4
	g.s.cover = 0.0
	var keep_pits := float(g.s.get("pits", 0.0))
	g.s.pits = 0.0
	g._overlays([FLOOR])
	g.s.pits = keep_pits
	for k in g.keep_clear:
		if g._in(k) and g._at(k) == DIFFICULT:
			g._put(k, FLOOR)

## An open yard: a well, a cart or a few crates, the rest grass.
static func _yard(g, r: Rect2i) -> void:
	var c := r.get_center()
	match g.rng.randi() % 4:
		0:
			g._put(c, WALL)
			g.prop("well", c.x, c.y)
		1:
			g._fill_rect(Rect2i(c.x - 1, c.y, 2, 1), DIFFICULT)
			g.prop("cart", c.x - 1, c.y, 2, 1)
		2:
			for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]:
				g._put(c + d, DIFFICULT)
				g.prop("crate" if g.rng.randf() < 0.6 else "barrel", c.x + d.x, c.y + d.y)
		_:
			pass
