class_name StructureBuilder
extends RefCounted
## Buildings for MapGenerator: whole towns (human, dwarven or elven), roads with hamlets and roadside inns,
## structures in the wild (ruins, camps, cabins, towers, shrines, crypts, forts) and one-building interiors.
## Everything is written into a MapGenerator instance `g`: its cells (what blocks movement), ground
## materials, props and labels. Furniture is difficult terrain, so a room never gets sealed off by it.

const FLOOR := EngineBase.FLOOR
const WALL := EngineBase.WALL
const DIFFICULT := EngineBase.DIFFICULT
const WATER := EngineBase.WATER

## Materials per style (MapGenerator.G_* codes): outer walls, masonry for important buildings, floors,
## streets and paths.  1 timber/planks, 2 masonry/cobbles, 3 palisade/dirt, 4 dressed stone/flagstones, 8 living wood.
const STYLE_MATS := {
	"human": {"wall": 1, "stone": 2, "floor": 1, "street": 2, "path": 3},
	"dwarf": {"wall": 4, "stone": 4, "floor": 4, "street": 2, "path": 4},
	"elf": {"wall": 8, "stone": 8, "floor": 8, "street": 3, "path": 3},
}
## Materials for buildings out in each kind of wilderness ("stilts": they stand on a plank deck).
const WILD_MATS := {
	"forest": {"wall": 1, "stone": 2, "floor": 1, "street": 3, "path": 3},
	"swamp": {"wall": 1, "stone": 2, "floor": 1, "street": 1, "path": 1, "stilts": true},
	"arctic": {"wall": 2, "stone": 2, "floor": 1, "street": 3, "path": 3},
	"graveyard": {"wall": 4, "stone": 4, "floor": 4, "street": 3, "path": 3},
	"mountain": {"wall": 2, "stone": 2, "floor": 4, "street": 3, "path": 3},
}
## Outer size of each kind of building, walls included: [length min, max (along the street), depth min, max].
const SIZES := {
	"tavern": [10, 14, 8, 11], "temple": [8, 11, 9, 12], "chapel": [7, 9, 7, 9], "smithy": [6, 8, 6, 7], "shop": [6, 8, 6, 7],
	"apothecary": [5, 7, 5, 7], "guard": [7, 9, 6, 7], "house": [5, 7, 5, 6], "stable": [6, 8, 5, 6], "tower": [6, 7, 6, 7],
	"crypt": [5, 6, 5, 7], "barracks": [7, 9, 6, 7],
}
const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

## Local coordinates inside a building: u runs along the front wall (the one with the door), v is the depth
## from it (0 = the row just inside the door). v = -1 is the front wall, v = D the back wall, u = -1 and
## u = L the side walls. Lets every layout be written once, whichever way the building faces.
class Frame:
	var inner: Rect2i
	var side: String
	var L: int
	var D: int

	func _init(r: Rect2i, sd: String) -> void:
		inner = r
		side = sd
		var across := sd in ["north", "south"]
		L = r.size.x if across else r.size.y
		D = r.size.y if across else r.size.x

	func at(u: int, v: int) -> Vector2i:
		match side:
			"north": return Vector2i(inner.position.x + u, inner.position.y + v)
			"west": return Vector2i(inner.position.x + v, inner.position.y + u)
			"east": return Vector2i(inner.end.x - 1 - v, inner.position.y + u)
		return Vector2i(inner.position.x + u, inner.end.y - 1 - v)

	func rect_of(u: int, v: int, lu: int, lv: int) -> Rect2i:
		var a := at(u, v)
		var b := at(u + lu - 1, v + lv - 1)
		return Rect2i(mini(a.x, b.x), mini(a.y, b.y), absi(a.x - b.x) + 1, absi(a.y - b.y) + 1)

# ---------------------------------------------------------------- small helpers

static func shuffle(a: Array, rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t

static func _ab(horiz: bool, a: int, b: int) -> Vector2i:
	return Vector2i(a, b) if horiz else Vector2i(b, a)

## Whether local cells (u, v)..(u+lu-1, v+lv-1) are free open floor inside the room.
static func free_local(g, f: Frame, used: Dictionary, u: int, v: int, lu: int, lv: int) -> bool:
	for a in lu:
		for b in lv:
			var q := Vector2i(u + a, v + b)
			if q.x < 0 or q.y < 0 or q.x >= f.L or q.y >= f.D or used.has(q):
				return false
			var p := f.at(q.x, q.y)
			if g._at(p) != FLOOR or g.keep_clear.has(p):
				return false
	return true

## Furniture `k` over local cells (u, v), lu × lv, if they are free. `cell` is what it does to movement.
static func put_local(g, f: Frame, used: Dictionary, u: int, v: int, lu: int, lv: int, k: String, cell := DIFFICULT) -> bool:
	if not free_local(g, f, used, u, v, lu, lv):
		return false
	for a in lu:
		for b in lv:
			g._put(f.at(u + a, v + b), cell)
			used[Vector2i(u + a, v + b)] = true
	if k != "":
		var r := f.rect_of(u, v, lu, lv)
		g.prop(k, r.position.x, r.position.y, r.size.x, r.size.y)
	return true

## An inside wall (a partition) at local (u, v).
static func wall_local(g, f: Frame, used: Dictionary, u: int, v: int, mat: int) -> void:
	var p := f.at(u, v)
	if g._in(p):
		g._put(p, WALL)
		g.gset(p, mat)
	used[Vector2i(u, v)] = true

## Something mounted on the wall cell at local (u, v): a hearth, kegs, a trophy...
static func wall_prop(g, f: Frame, used: Dictionary, u: int, v: int, k: String) -> bool:
	var key := Vector2i(u, v)
	var p := f.at(u, v)
	if used.has(key) or not g._in(p) or g._at(p) != WALL:
		return false
	g.prop(k, p.x, p.y)
	used[key] = true
	return true

## A doorway at world cell p; the cells around it are kept clear of furniture and clutter.
static func door_at(g, p: Vector2i, floor_mat: int) -> void:
	if not g._in(p):
		return
	g._put(p, FLOOR)
	g.gset(p, floor_mat)
	g.prop("door", p.x, p.y)
	g.keep_clear[p] = true
	for d in DIRS:
		g.keep_clear[p + d] = true

## A free lu × lv spot (local), nearest the middle of `area` (default: the whole room), or (-1, -1).
static func find_free(g, f: Frame, used: Dictionary, lu: int, lv: int, rng: RandomNumberGenerator, area := Rect2i()) -> Vector2i:
	var a := area if area.size != Vector2i.ZERO else Rect2i(0, 0, f.L, f.D)
	var c := Vector2(a.position) + Vector2(a.size) * 0.5
	var best := Vector2i(-1, -1)
	var bd := INF
	for u in range(a.position.x, a.end.x - lu + 1):
		for v in range(a.position.y, a.end.y - lv + 1):
			if free_local(g, f, used, u, v, lu, lv):
				var d := Vector2(u + lu * 0.5, v + lv * 0.5).distance_to(c) + rng.randf() * 3.0
				if d < bd:
					bd = d
					best = Vector2i(u, v)
	return best

## A random free spot (local); against a wall when `by_wall`.
static func rand_free(g, f: Frame, used: Dictionary, rng: RandomNumberGenerator, lu := 1, lv := 1, by_wall := false) -> Vector2i:
	var opts: Array = []
	for u in f.L - lu + 1:
		for v in f.D - lv + 1:
			if by_wall and not (u == 0 or v == f.D - lv or u == f.L - lu):
				continue
			if free_local(g, f, used, u, v, lu, lv):
				opts.append(Vector2i(u, v))
	return opts[rng.randi() % opts.size()] if not opts.is_empty() else Vector2i(-1, -1)

static func _clutter(g, f: Frame, used: Dictionary, n: int, kinds: Array) -> void:
	for i in n:
		var p := rand_free(g, f, used, g.rng, 1, 1, true)
		if p.x >= 0:
			put_local(g, f, used, p.x, p.y, 1, 1, kinds[g.rng.randi() % kinds.size()])

# ---------------------------------------------------------------- one building

## Walls, floor, door(s) and furniture for a building of `kind` filling `r` (walls included), its door in the
## wall on `side`. `door_hint`: the local position the door should be at (-1: anywhere). Named buildings get
## a label and an entry in g.structures. Returns {"rect", "side", "door_us", "frame", "id", "name"}.
static func building(g, r: Rect2i, side: String, kind: String, style: String, mats: Dictionary, door_hint := -1) -> Dictionary:
	var rng: RandomNumberGenerator = g.rng
	var masonry := kind in ["temple", "chapel", "smithy", "tower", "guard", "crypt", "barracks"]
	var wall_mat: int = int(mats.get("stone", mats.wall)) if masonry else int(mats.wall)
	var floor_mat: int = int(mats.floor)
	match kind:
		"smithy": floor_mat = MapGenerator.G_FLAG if style == "dwarf" else MapGenerator.G_DIRT
		"temple", "chapel", "crypt": floor_mat = MapGenerator.G_FLAG if style != "elf" else floor_mat
		"stable": floor_mat = MapGenerator.G_STRAW
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var p := Vector2i(x, y)
			var edge := x == r.position.x or y == r.position.y or x == r.end.x - 1 or y == r.end.y - 1
			g._put(p, WALL if edge else FLOOR)
			g.gset(p, wall_mat if edge else floor_mat)
	var inner := r.grow(-1)
	var f := Frame.new(inner, side)
	var dw := 2 if kind in ["tavern", "temple", "guard", "barracks", "stable"] and f.L >= 7 else 1
	var du: int
	if door_hint >= 0:
		du = clampi(door_hint - (dw - 1) * rng.randi_range(0, 1), 0, maxi(0, f.L - dw))
	elif kind in ["temple", "chapel", "crypt", "tower"]:
		du = (f.L - dw) / 2
	else:
		du = rng.randi_range(0, maxi(0, f.L - dw))
	var door_us: Array = []
	for k in dw:
		door_at(g, f.at(du + k, -1), floor_mat)
		door_us.append(du + k)
		g.keep_clear[f.at(du + k, -2)] = true
	var used := {}
	for u in door_us:
		for dv in 2:
			for o in range(-1, 2):
				used[Vector2i(u + o, dv)] = true
	var lmats := mats.duplicate()
	lmats.floor = floor_mat
	lmats.wall = wall_mat
	var nm := ""
	var info := {}
	match kind:
		"tavern":
			info = TavernGenerator.make_info(rng, style)
			nm = info.name
			info.features = TavernGenerator.furnish(g, inner, side, door_us, style, lmats)
		"house": _house(g, f, used, style)
		"smithy": _smithy(g, f, used)
		"shop": _shop(g, f, used, false)
		"apothecary": _shop(g, f, used, true)
		"temple", "chapel": _temple(g, f, used)
		"guard", "barracks": _barracks(g, f, used)
		"tower": _tower(g, f, used)
		"crypt": _crypt(g, f, used)
		"stable": _stable(g, f, used)
	if nm == "" and not kind in ["house", "stable", "barracks"]:
		nm = NameGen.place(rng, kind, style)
	var sid := ""
	if nm != "":
		sid = g.add_structure(kind, nm, r, info)
		var ly := float(r.end.y) - 0.5 if side == "north" else float(r.position.y) + 0.5
		g.label(nm, r.position.x + r.size.x / 2.0, ly, kind, sid)
	return {"rect": r, "side": side, "door_us": door_us, "frame": f, "id": sid, "name": nm}

static func _house(g, f: Frame, used: Dictionary, style: String) -> void:
	var rng: RandomNumberGenerator = g.rng
	var corners: Array = [Vector2i(0, f.D - 2), Vector2i(f.L - 1, f.D - 2)]
	shuffle(corners, rng)
	var beds := 2 if f.L * f.D >= 20 and rng.randf() < 0.6 else 1
	for c in corners:
		if beds > 0 and put_local(g, f, used, c.x, c.y, 1, 2, "bed"):
			beds -= 1
	for i in 6:
		var spot: Vector2i = [Vector2i(rng.randi_range(0, f.L - 1), f.D), Vector2i(-1, rng.randi_range(0, f.D - 1)), Vector2i(f.L, rng.randi_range(0, f.D - 1))][rng.randi() % 3]
		if wall_prop(g, f, used, spot.x, spot.y, "hearth"):
			break
	var t := find_free(g, f, used, 1, 1, rng)
	if t.x >= 0:
		put_local(g, f, used, t.x, t.y, 1, 1, "table_round")
		put_local(g, f, used, t.x - 1, t.y, 1, 1, "chair", FLOOR)
		put_local(g, f, used, t.x + 1, t.y, 1, 1, "chair", FLOOR)
	_clutter(g, f, used, rng.randi_range(1, 2), ["barrel", "crate", "shelf"])
	if style == "elf":
		_clutter(g, f, used, 1, ["plant"])
	elif rng.randf() < 0.3:
		var p := find_free(g, f, used, 2, 2, rng)
		if p.x >= 0:
			for a in 2:
				for b in 2:
					g.gset(f.at(p.x + a, p.y + b), MapGenerator.G_RUG)

static func _smithy(g, f: Frame, used: Dictionary) -> void:
	var cu := maxi(0, f.L / 2 - 1)
	put_local(g, f, used, cu, f.D - 1, 2, 1, "forge", WALL)
	put_local(g, f, used, cu, maxi(0, f.D - 3), 1, 1, "anvil")
	put_local(g, f, used, cu + 2, f.D - 1, 1, 1, "barrel")
	for i in 4:
		wall_prop(g, f, used, -1 if i % 2 == 0 else f.L, g.rng.randi_range(0, f.D - 1), "rack")
	_clutter(g, f, used, 2, ["crate", "barrel"])

static func _shop(g, f: Frame, used: Dictionary, apothecary: bool) -> void:
	var rng: RandomNumberGenerator = g.rng
	if f.D >= 5:
		for u in f.L:
			put_local(g, f, used, u, f.D - 1, 1, 1, "shelf")
		var gap := 0 if rng.randf() < 0.5 else f.L - 1
		for u in f.L:
			if u != gap:
				put_local(g, f, used, u, f.D - 3, 1, 1, "counter")
	else:
		for v in f.D:
			put_local(g, f, used, f.L - 1, v, 1, 1, "shelf")
	if apothecary:
		var c := find_free(g, f, used, 1, 1, rng)
		if c.x >= 0:
			put_local(g, f, used, c.x, c.y, 1, 1, "cauldron")
		_clutter(g, f, used, 2, ["plant", "shelf"])
	else:
		_clutter(g, f, used, rng.randi_range(2, 3), ["crate", "barrel", "crate"])

static func _temple(g, f: Frame, used: Dictionary) -> void:
	var even := f.L % 2 == 0
	var aw := 2 if even else 1
	var au := f.L / 2 - (1 if even else 0)
	put_local(g, f, used, au, f.D - 1, aw, 1, "altar")
	put_local(g, f, used, au - 1, f.D - 1, 1, 1, "brazier", FLOOR)
	put_local(g, f, used, au + aw, f.D - 1, 1, 1, "brazier", FLOOR)
	for v in f.D - 1:
		for a in aw:
			g.gset(f.at(au + a, v), MapGenerator.G_RUG)
			used[Vector2i(au + a, v)] = true
	var v := 1
	while v < f.D - 2:
		var left := au - 1
		if left >= 2:
			put_local(g, f, used, 1, v, left - 1, 1, "pew")
		var r0 := au + aw + 1
		if f.L - 1 - r0 >= 1:
			put_local(g, f, used, r0, v, f.L - 1 - r0, 1, "pew")
		v += 2
	if f.D >= 7:
		wall_prop(g, f, used, au, f.D, "banner")

static func _barracks(g, f: Frame, used: Dictionary) -> void:
	var v := 0
	while v + 1 < f.D:
		put_local(g, f, used, 0, v, 1, 2, "bed")
		put_local(g, f, used, f.L - 1, v, 1, 2, "bed")
		v += 3
	var t := find_free(g, f, used, 2, 1, g.rng)
	if t.x >= 0:
		put_local(g, f, used, t.x, t.y, 2, 1, "table_long")
	for i in 3:
		wall_prop(g, f, used, g.rng.randi_range(0, f.L - 1), f.D, "rack")

static func _tower(g, f: Frame, used: Dictionary) -> void:
	var c := Vector2i(f.L - 1, f.D - 2) if g.rng.randf() < 0.5 else Vector2i(0, f.D - 2)
	put_local(g, f, used, c.x, c.y, 1, 2, "stairs")
	wall_prop(g, f, used, -1 if c.x > 0 else f.L, f.D / 2, "rack")
	_clutter(g, f, used, 2, ["crate", "barrel"])
	if f.L * f.D >= 20:
		var t := find_free(g, f, used, 1, 1, g.rng)
		if t.x >= 0:
			put_local(g, f, used, t.x, t.y, 1, 1, "table_round")

static func _crypt(g, f: Frame, used: Dictionary) -> void:
	var n := 2 if f.L >= 5 else 1
	var us: Array = [f.L / 2] if n == 1 else [1, f.L - 2]
	for u in us:
		put_local(g, f, used, u, maxi(1, f.D / 2 - 1), 1, 2, "sarcophagus")
	put_local(g, f, used, 0, f.D - 1, 1, 1, "urn")
	put_local(g, f, used, f.L - 1, f.D - 1, 1, 1, "urn")

static func _stable(g, f: Frame, used: Dictionary) -> void:
	for u in f.L:
		if u % 2 == 0:
			put_local(g, f, used, u, f.D - 1, 1, 1, "hay")
	var t := find_free(g, f, used, 2, 1, g.rng)
	if t.x >= 0:
		put_local(g, f, used, t.x, t.y, 2, 1, "trough")

## Rooms behind a big hall: a wall across the building at depth `keep` with doors, the space behind it split
## into bedrooms and storerooms.
static func back_rooms(g, f: Frame, keep: int, mats: Dictionary) -> void:
	var used := {}
	for u in f.L:
		wall_local(g, f, used, u, keep, mats.wall)
	var n_doors := clampi(f.L / 8, 1, 3)
	for i in n_doors:
		door_at(g, f.at(int((i + 0.5) * f.L / n_doors), keep), mats.floor)
	rooms_block(g, f.rect_of(0, keep + 1, f.L, f.D - keep - 1), mats)

## Split world rect `r` into small rooms (each partition gets a door) and furnish them.
static func rooms_block(g, r: Rect2i, mats: Dictionary) -> void:
	var rng: RandomNumberGenerator = g.rng
	var regions: Array = [r]
	var leaves: Array = []
	while not regions.is_empty():
		var q: Rect2i = regions.pop_back()
		var split_x := q.size.x >= q.size.y
		var span := q.size.x if split_x else q.size.y
		if span < 8:
			leaves.append(q)
			continue
		var at := rng.randi_range(3, span - 4)
		if split_x:
			var wx := q.position.x + at
			for y in range(q.position.y, q.end.y):
				_partition(g, Vector2i(wx, y), mats)
			door_at(g, Vector2i(wx, rng.randi_range(q.position.y, q.end.y - 1)), mats.floor)
			regions.append(Rect2i(q.position.x, q.position.y, at, q.size.y))
			regions.append(Rect2i(wx + 1, q.position.y, q.end.x - wx - 1, q.size.y))
		else:
			var wy := q.position.y + at
			for x in range(q.position.x, q.end.x):
				_partition(g, Vector2i(x, wy), mats)
			door_at(g, Vector2i(rng.randi_range(q.position.x, q.end.x - 1), wy), mats.floor)
			regions.append(Rect2i(q.position.x, q.position.y, q.size.x, at))
			regions.append(Rect2i(q.position.x, wy + 1, q.size.x, q.end.y - wy - 1))
	for q in leaves:
		var f := Frame.new(q, "south")
		var used := {}
		if q.get_area() >= 6 and rng.randf() < 0.7:
			for c in [Vector2i(0, 0), Vector2i(f.L - 1, 0), Vector2i(0, f.D - 2), Vector2i(f.L - 1, f.D - 2)]:
				if put_local(g, f, used, c.x, c.y, 1, 2, "bed"):
					break
			_clutter(g, f, used, 1, ["crate", "shelf"])
		else:
			_clutter(g, f, used, rng.randi_range(2, 4), ["barrel", "crate", "barrel", "shelf"])

static func _partition(g, p: Vector2i, mats: Dictionary) -> void:
	if g.keep_clear.has(p) or not g._in(p):
		return
	g._put(p, WALL)
	g.gset(p, mats.wall)

# ---------------------------------------------------------------- indoors

## The whole map is one building (a tavern or a temple); the front door is on the party's edge.
static func indoor(g) -> void:
	var style: String = g.s.style
	g.cells.fill(FLOOR)
	var side: String = g._side()
	var length: int = (g.w if side in ["north", "south"] else g.h) - 2
	building(g, Rect2i(0, 0, g.w, g.h), side, str(g.s.interior), style, STYLE_MATS[style], length / 2)

## Floors, wall materials and table props for the plain "rooms" interior (MapGenerator._interior).
static func dress_plain(g) -> void:
	var mats: Dictionary = STYLE_MATS.get(str(g.s.style), STYLE_MATS.human)
	for i in g.cells.size():
		g.ground[i] = mats.wall if g.cells[i] == WALL else mats.floor

# ---------------------------------------------------------------- streets and lots

## Street cells next to open ground, with the direction to it: where buildings can front onto the street.
static func _edges(g, street: Dictionary) -> Array:
	var out: Array = []
	for p in street:
		if not g._in(p):
			continue
		for d in DIRS:
			var q: Vector2i = p + d
			if g._in(q) and not street.has(q):
				out.append([p, d])
	return out

## Whether a building fits on lot `r`: inside the map, off the street, clear of other buildings (with an alley).
static func _lot_ok(g, r: Rect2i, street: Dictionary, taken: Dictionary, wild: bool) -> bool:
	if r.position.x < 0 or r.position.y < 0 or r.end.x > g.w or r.end.y > g.h:
		return false
	for y in range(r.position.y - 1, r.end.y + 1):
		for x in range(r.position.x - 1, r.end.x + 1):
			var p := Vector2i(x, y)
			if taken.has(p):
				return false
			if r.has_point(p) and (street.has(p) or (not wild and g._at(p) == WATER)):
				return false
	return true

## Put a building of `kind` fronting the street. Returns building()'s result, or {} if no lot was found.
static func _place_on_street(g, kind: String, edges: Array, street: Dictionary, taken: Dictionary, style: String, mats: Dictionary, tries: int, wild: bool) -> Dictionary:
	if edges.is_empty():
		return {}
	var rng: RandomNumberGenerator = g.rng
	var sz: Array = SIZES[kind]
	var grow := 1 if style == "dwarf" and not wild else 0
	for t in tries:
		var e: Array = edges[rng.randi() % edges.size()]
		var sp: Vector2i = e[0]
		var d: Vector2i = e[1]
		var lw := rng.randi_range(sz[0], sz[1]) + grow
		var dp := rng.randi_range(sz[2], sz[3]) + grow
		if t > tries * 3 / 4:
			# Running out of room: squeeze it in a size smaller.
			lw = maxi(sz[0] - 2, 5)
			dp = maxi(sz[2] - 2, 5)
		elif t > tries / 2:
			lw = sz[0]
			dp = sz[2]
		var r: Rect2i
		var side: String
		var hint: int
		if d.x == 0:
			var x0 := sp.x - rng.randi_range(1, lw - 2)
			r = Rect2i(x0, sp.y + 1 if d.y > 0 else sp.y - dp, lw, dp)
			side = "north" if d.y > 0 else "south"
			hint = sp.x - x0 - 1
		else:
			var y0 := sp.y - rng.randi_range(1, lw - 2)
			r = Rect2i(sp.x + 1 if d.x > 0 else sp.x - dp, y0, dp, lw)
			side = "west" if d.x > 0 else "east"
			hint = sp.y - y0 - 1
		if not _lot_ok(g, r, street, taken, wild):
			continue
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				taken[Vector2i(x, y)] = true
		if wild:
			_prepare_lot(g, r, mats, street)
		return building(g, r, side, kind, style, mats, hint)
	return {}

## Clear a lot in the wild: trees, rocks and water around it go (a swamp gets a plank deck instead).
static func _prepare_lot(g, r: Rect2i, mats: Dictionary, street := {}) -> void:
	var gr := r.grow(1)
	for y in range(gr.position.y, gr.end.y):
		for x in range(gr.position.x, gr.end.x):
			var p := Vector2i(x, y)
			if not g._in(p) or street.has(p):
				continue
			g._put(p, FLOOR)
			if mats.get("stilts", false):
				g.gset(p, MapGenerator.G_PLANK)

## A road across the map along the party's way in (dirt, plank bridges over water). Returns its cells.
static func _road(g, side: String, mats: Dictionary, width := 2) -> Dictionary:
	var rng: RandomNumberGenerator = g.rng
	var horiz := side in ["west", "east"]
	var along: int = g.w if horiz else g.h
	var across: int = g.h if horiz else g.w
	var c := clampi(across / 2 - width / 2 + rng.randi_range(-2, 2), 1, maxi(1, across - width - 1))
	var road := {}
	for i in along:
		if i % 3 == 0 and i > 0 and rng.randf() < 0.6:
			c = clampi(c + rng.randi_range(-1, 1), 1, maxi(1, across - width - 1))
		for k in width:
			road[_ab(horiz, i, c + k)] = true
	for p in road:
		if not g._in(p):
			continue
		var wet: bool = g._at(p) in [WATER, DIFFICULT] and mats.get("stilts", false) or g._at(p) == WATER
		g._put(p, FLOOR)
		g.gset(p, MapGenerator.G_PLANK if wet else int(mats.get("street", mats.path)))
		g.keep_clear[p] = true
	return road

# ---------------------------------------------------------------- towns

## A town: a main street along the party's way in, cross streets, a square with a well, statue or great tree,
## market stalls, taverns, a temple, a smithy, shops and homes; lamps, crates and trees along the way.
static func town(g) -> void:
	var rng: RandomNumberGenerator = g.rng
	var style: String = g.s.style
	var mats: Dictionary = STYLE_MATS[style]
	var w: int = g.w
	var h: int = g.h
	g.cells.fill(FLOOR)
	g.place_name = NameGen.town_name(rng, style)
	var side: String = g._side()
	var horiz := side in ["west", "east"]
	var along := w if horiz else h
	var across := h if horiz else w
	var street := {}
	var taken := {}
	if style == "dwarf":
		# A hall carved out of the mountain: solid rock all round.
		for x in w:
			g._put(Vector2i(x, 0), WALL)
			g._put(Vector2i(x, h - 1), WALL)
		for y in h:
			g._put(Vector2i(0, y), WALL)
			g._put(Vector2i(w - 1, y), WALL)
	if bool(g.s.river):
		g._river()
	var water := float(g.s.water)
	if water > 0.01:
		for i in maxi(1, g._density(water, 0.006)):
			var wc: Vector2i = g._random_cell_of([FLOOR])
			if wc.x >= 0:
				g._blob(wc, rng.randf_range(1.2, 1.5 + 2.0 * water), WATER, [FLOOR])
	# Main street.
	var mw := 3 if across >= 16 else 2
	var c0 := clampi(across / 2 - mw / 2 + rng.randi_range(-1, 1), 1, maxi(1, across - mw - 1))
	var c := c0
	for i in along:
		if style == "elf" and i % 3 == 0 and i > 0:
			c = clampi(c + rng.randi_range(-1, 1), 1, maxi(1, across - mw - 1))
		for k in mw:
			street[_ab(horiz, i, c + k)] = true
	# Cross streets (elven ones may only run one way from the main street).
	var cross: Array = []
	var n_cross := 0 if along < 18 else clampi(along / 15, 1, 3)
	for j in n_cross:
		var pos := clampi(int((j + 1) * along / float(n_cross + 1)) + rng.randi_range(-2, 2), 2, along - 4)
		cross.append(pos)
		var half := style == "elf" and rng.randf() < 0.5
		var up := rng.randf() < 0.5
		for t in across:
			if half and ((t < c0) == up):
				continue
			for k in 2:
				street[_ab(horiz, pos + k, t)] = true
	# The square, where the middle cross street meets the main street.
	var plaza := Rect2i()
	if not cross.is_empty() and across >= 12:
		var pc: int = cross[cross.size() / 2]
		var ps := clampi(across / 3, 5, 9)
		var pa := clampi(pc + 1 - ps / 2, 1, along - ps - 1)
		var pb := clampi(c0 + mw / 2 - ps / 2, 1, across - ps - 1)
		for a in ps:
			for b in ps:
				street[_ab(horiz, pa + a, pb + b)] = true
		plaza = Rect2i(pa, pb, ps, ps) if horiz else Rect2i(pb, pa, ps, ps)
	for p in street:
		if not g._in(p):
			continue
		var wet: bool = g._at(p) in [WATER, DIFFICULT]
		g._put(p, FLOOR)
		g.gset(p, MapGenerator.G_PLANK if wet else int(mats.street))
	var label_at := Vector2(_ab(horiz, along / 2, c0)) + Vector2(0.5, 0.5)
	if plaza.size.x > 0:
		_square(g, plaza, style, taken)
		label_at = Vector2(plaza.position.x + plaza.size.x / 2.0, plaza.position.y + 0.5)
	var tid: String = g.add_structure("town", g.place_name, plaza if plaza.size.x > 0 else Rect2i(_ab(horiz, 0, c0), Vector2i.ONE))
	g.label(g.place_name, label_at.x, label_at.y, "town", tid)
	# Buildings: the important ones first, then homes until the frontage is used up.
	var edges := _edges(g, street)
	var plan: Array = []
	for i in clampi(int(g.s.get("taverns", 1)), 0, 4):
		plan.append("tavern")
	var area := w * h
	if area >= 400: plan.append("temple")
	if area >= 300: plan.append("smithy")
	plan.append("shop")
	if area >= 800: plan.append("apothecary")
	if area >= 1300: plan.append("guard")
	for kind in plan:
		_place_on_street(g, kind, edges, street, taken, style, mats, 250, false)
	var dens := float(g.s.obstacles)
	var max_homes := int(round(area * dens / 28.0))
	var fails := 0
	var homes := 0
	while fails < 40 and homes < max_homes:
		if _place_on_street(g, "house", edges, street, taken, style, mats, 30, false).is_empty():
			fails += 1
		else:
			homes += 1
	_town_dressing(g, street, taken, style, horiz, along, c0, mw)

## The town square's centrepiece and market stalls.
static func _square(g, plaza: Rect2i, style: String, taken: Dictionary) -> void:
	var rng: RandomNumberGenerator = g.rng
	var cen := plaza.position + plaza.size / 2 - Vector2i(1, 1)
	match style:
		"dwarf":
			g._put(cen, WALL)
			g.prop("statue", cen.x, cen.y)
			taken[cen] = true
		"elf":
			for a in 2:
				for b in 2:
					g._put(cen + Vector2i(a, b), WALL)
					taken[cen + Vector2i(a, b)] = true
			g.prop("tree", cen.x, cen.y, 2, 2)
			for a in range(-1, 3):
				for b in range(-1, 3):
					if g._at(cen + Vector2i(a, b)) == FLOOR:
						g.gset(cen + Vector2i(a, b), MapGenerator.G_GRASS)
		_:
			if rng.randf() < 0.5:
				g._put(cen, WALL)
				g.prop("well", cen.x, cen.y)
				taken[cen] = true
			else:
				for a in 2:
					for b in 2:
						g._put(cen + Vector2i(a, b), WATER)
						taken[cen + Vector2i(a, b)] = true
				g.prop("fountain", cen.x, cen.y, 2, 2)
	if plaza.size.x >= 7:
		var e := plaza.end - Vector2i(1, 1)
		for p in [plaza.position + Vector2i(1, 1), Vector2i(e.x - 2, plaza.position.y + 1), Vector2i(plaza.position.x + 1, e.y - 1), Vector2i(e.x - 2, e.y - 1)]:
			if rng.randf() < 0.75 and g._at(p) == FLOOR and g._at(p + Vector2i(1, 0)) == FLOOR:
				g._put(p, DIFFICULT)
				g._put(p + Vector2i(1, 0), DIFFICULT)
				g.prop("stall", p.x, p.y, 2, 1)
				taken[p] = true
				taken[p + Vector2i(1, 0)] = true

## Lamps along the main street, crates and barrels against the buildings, trees (or rock columns) in the gaps.
static func _town_dressing(g, street: Dictionary, taken: Dictionary, style: String, horiz: bool, along: int, c0: int, mw: int) -> void:
	var rng: RandomNumberGenerator = g.rng
	var lamp := "brazier" if style == "dwarf" else "lamp"
	for i in range(2, along - 1, 6):
		var q := _ab(horiz, i, c0 - 1 if (i / 6) % 2 == 0 else c0 + mw)
		if g._in(q) and g._at(q) == FLOOR and not street.has(q) and not taken.has(q) and not g.keep_clear.has(q):
			g.prop(lamp, q.x, q.y)
			taken[q] = true
	var crates: int = g._density(float(g.s.difficult), 0.025)
	var kinds := ["crate", "barrel", "barrel", "hay" if style == "human" else "crate", "cart" if style != "elf" else "barrel"]
	for i in crates * 8:
		if crates <= 0:
			break
		var p: Vector2i = g._random_cell_of([FLOOR], 20)
		if p.x < 0 or taken.has(p) or g.keep_clear.has(p) or not _beside_building(g, p):
			continue
		g._put(p, DIFFICULT)
		g.prop(kinds[rng.randi() % kinds.size()], p.x, p.y)
		taken[p] = true
		crates -= 1
	var trees: int = g._density(float(g.s.cover), 0.07 if style == "elf" else 0.03)
	for i in trees * 8:
		if trees <= 0:
			break
		var p: Vector2i = g._random_cell_of([FLOOR], 20)
		if p.x < 0 or street.has(p) or taken.has(p) or g.keep_clear.has(p) or _beside_building(g, p) or g.gat(p) != MapGenerator.G_NONE:
			continue
		g._put(p, WALL)
		if style != "dwarf":
			g.prop("tree", p.x, p.y)
		taken[p] = true
		trees -= 1
	if style == "elf":
		for i in g._density(float(g.s.cover), 0.03):
			var p: Vector2i = g._random_cell_of([FLOOR], 20)
			if p.x >= 0 and not street.has(p) and not taken.has(p) and g.gat(p) == MapGenerator.G_NONE:
				g.prop("flowers", p.x, p.y)
				taken[p] = true

static func _beside_building(g, p: Vector2i) -> bool:
	for d in DIRS:
		var q: Vector2i = p + d
		if g._at(q) == WALL and g.gat(q) != MapGenerator.G_NONE:
			return true
	return false

# ---------------------------------------------------------------- the wild

## Structures standing in an outdoor map, chosen by settings.structures, built from the terrain's materials.
static func wilderness(g) -> void:
	var rng: RandomNumberGenerator = g.rng
	var type := str(g.s.structures)
	var terr := str(g.s.terrain)
	var mats: Dictionary = WILD_MATS.get(terr, WILD_MATS.forest)
	var style := str(g.s.style)
	var n := clampi(int(g.s.get("structure_count", 2)), 1, 8)
	var side: String = g._side()
	var lots: Array = []   # Rect2i already used
	match type:
		"hamlet", "inn":
			var smats: Dictionary = STYLE_MATS[style].duplicate()
			smats.street = mats.street
			smats.path = mats.path
			if mats.get("stilts", false):
				smats.stilts = true
			var road := _road(g, side, smats)
			var edges := _edges(g, road)
			var taken := {}
			if type == "inn":
				_place_on_street(g, "tavern", edges, road, taken, style, smats, 300, true)
				_place_on_street(g, "stable", edges, road, taken, style, smats, 200, true)
			else:
				g.place_name = NameGen.town_name(rng, style)
				var mid: Vector2i = road.keys()[road.size() / 2]
				var tid: String = g.add_structure("town", g.place_name, Rect2i(mid, Vector2i.ONE))
				g.label(g.place_name, mid.x + 0.5, mid.y - 0.5, "town", tid)
				if n >= 3:
					_place_on_street(g, "tavern", edges, road, taken, style, smats, 300, true)
				if n >= 5:
					_place_on_street(g, "smithy", edges, road, taken, style, smats, 200, true)
				for i in n:
					_place_on_street(g, "house", edges, road, taken, style, smats, 120, true)
		"ruins":
			for i in n:
				var r := _spot(g, side, lots, rng.randi_range(5, 9), rng.randi_range(5, 8))
				if r.position.x >= 0:
					_ruin(g, r, mats)
		"camp":
			_camp(g, side, lots, n)
		"cabins":
			for i in n:
				_wild_building(g, "house", side, lots, mats, style)
		"tower":
			_wild_building(g, "tower", side, lots, mats, style)
			for i in n - 1:
				_wild_building(g, "house", side, lots, mats, style)
		"shrine":
			if rng.randf() < 0.5 or g.w < 14 or g.h < 12:
				_stone_circle(g, side, lots, style)
			else:
				_wild_building(g, "chapel", side, lots, mats, style)
		"crypts":
			for i in n:
				_wild_building(g, "crypt", side, lots, mats, style)
		"fort":
			_fort(g, side, lots, mats, style)

## A free rw × rh lot away from the party's edge and other lots, or Rect2i(-1, -1, 0, 0).
static func _spot(g, side: String, lots: Array, rw: int, rh: int) -> Rect2i:
	var rng: RandomNumberGenerator = g.rng
	var w: int = g.w
	var h: int = g.h
	if rw > w - 2 or rh > h - 2:
		return Rect2i(-1, -1, 0, 0)
	var zone := 5
	for t in 200:
		var r := Rect2i(rng.randi_range(1, w - rw - 1), rng.randi_range(1, h - rh - 1), rw, rh)
		var bad := false
		if t < 150:
			match side:
				"west": bad = r.position.x < zone
				"east": bad = r.end.x > w - zone
				"north": bad = r.position.y < zone
				"south": bad = r.end.y > h - zone
			if bad:
				continue
		for o in lots:
			if r.grow(2).intersects(o):
				bad = true
				break
		if not bad:
			lots.append(r)
			return r
	return Rect2i(-1, -1, 0, 0)

## A lone building in the wild with its door toward the party and a short path out of it.
static func _wild_building(g, kind: String, side: String, lots: Array, mats: Dictionary, style: String) -> Dictionary:
	var rng: RandomNumberGenerator = g.rng
	var sz: Array = SIZES[kind]
	for attempt in 2:
		var lw: int = rng.randi_range(sz[0], sz[1]) if attempt == 0 else sz[0]
		var dp: int = rng.randi_range(sz[2], sz[3]) if attempt == 0 else sz[2]
		var across: bool = side in ["north", "south"]
		var r := _spot(g, side, lots, lw if across else dp, dp if across else lw)
		if r.position.x < 0:
			continue
		_prepare_lot(g, r, mats)
		var b := building(g, r, side, kind, style, mats)
		var f: Frame = b.frame
		for u in b.door_us:
			for k in range(2, 5):
				var p := f.at(u, -k)
				if g._in(p):
					g._put(p, FLOOR)
					g.gset(p, int(mats.path))
					g.keep_clear[p] = true
		return b
	return {}

## Broken walls with gaps and rubble, a flagstone floor showing through.
static func _ruin(g, r: Rect2i, mats: Dictionary) -> void:
	var rng: RandomNumberGenerator = g.rng
	_prepare_lot(g, r, mats)
	var edge_cells: Array = []
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var p := Vector2i(x, y)
			var edge := x == r.position.x or y == r.position.y or x == r.end.x - 1 or y == r.end.y - 1
			if edge:
				edge_cells.append(p)
				if rng.randf() < 0.62:
					g._put(p, WALL)
					g.gset(p, int(mats.stone))
				elif rng.randf() < 0.5:
					g._put(p, DIFFICULT)
					g.prop("rubble", p.x, p.y)
			else:
				if rng.randf() < 0.6:
					g.gset(p, MapGenerator.G_FLAG)
				if rng.randf() < 0.12:
					g._put(p, DIFFICULT)
					g.prop("rubble", p.x, p.y)
	# At least two ways in.
	for i in 2:
		var p: Vector2i = edge_cells[rng.randi() % edge_cells.size()]
		g._put(p, FLOOR)
	if r.size.x >= 7 and r.size.y >= 7:
		var c := r.get_center()
		g._put(c, WALL)
		g.gset(c, MapGenerator.G_FLAG)
		g.prop("pillar", c.x, c.y)

## Tents around a campfire in a trampled clearing, with bedrolls and supplies.
static func _camp(g, side: String, lots: Array, n: int) -> void:
	var rng: RandomNumberGenerator = g.rng
	var rad := clampi(3 + n / 2, 3, 6)
	var r := _spot(g, side, lots, rad * 2 + 1, rad * 2 + 1)
	if r.position.x < 0:
		return
	var c := r.position + Vector2i(rad, rad)
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var p := Vector2i(x, y)
			if Vector2(p - c).length() <= rad + rng.randf_range(-0.4, 0.6):
				g._put(p, FLOOR)
				g.gset(p, MapGenerator.G_DIRT)
	g._put(c, DIFFICULT)
	g.prop("fire", c.x, c.y)
	var tents := clampi(n + 1, 2, 6)
	var a0 := rng.randf() * TAU
	for i in tents:
		var ang := a0 + TAU * i / tents
		var tp := c + Vector2i(roundi(cos(ang) * (rad - 1.3)), roundi(sin(ang) * (rad - 1.3))) - Vector2i(1, 1) + Vector2i(1 if cos(ang) < 0 else 0, 1 if sin(ang) < 0 else 0)
		var ok := true
		for a in 2:
			for b in 2:
				var q := tp + Vector2i(a, b)
				if not g._in(q) or g._at(q) != FLOOR or maxi(absi(q.x - c.x), absi(q.y - c.y)) < 2:
					ok = false
		if not ok:
			continue
		for a in 2:
			for b in 2:
				g._put(tp + Vector2i(a, b), WALL)
		g.prop("tent", tp.x, tp.y, 2, 2)
	for d in [Vector2i(-1, -1), Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1)]:
		var q: Vector2i = c + d
		if rng.randf() < 0.7 and g._at(q) == FLOOR:
			g.prop("bedroll", q.x, q.y)
	for i in rng.randi_range(1, 3):
		var q := c + Vector2i(rng.randi_range(-rad + 1, rad - 1), rng.randi_range(-rad + 1, rad - 1))
		if g._at(q) == FLOOR and maxi(absi(q.x - c.x), absi(q.y - c.y)) >= 2:
			g._put(q, DIFFICULT)
			g.prop(["crate", "barrel"][rng.randi() % 2], q.x, q.y)

## Standing stones in a ring around an altar.
static func _stone_circle(g, side: String, lots: Array, style: String) -> void:
	var rng: RandomNumberGenerator = g.rng
	var rad := 3 if mini(g.w, g.h) < 24 else 4
	var r := _spot(g, side, lots, rad * 2 + 3, rad * 2 + 3)
	if r.position.x < 0:
		return
	var c := r.get_center()
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if Vector2(Vector2i(x, y) - c).length() <= rad + 1.2:
				g._put(Vector2i(x, y), FLOOR)
				g.gset(Vector2i(x, y), MapGenerator.G_GRASS)
	var k := 8 if rad == 3 else 10
	var a0 := rng.randf() * TAU
	for i in k:
		var p := c + Vector2i(roundi(cos(a0 + TAU * i / k) * rad), roundi(sin(a0 + TAU * i / k) * rad))
		g._put(p, WALL)
		g.prop("stone", p.x, p.y)
	g._put(c, DIFFICULT)
	g.prop("altar", c.x, c.y)
	var nm := NameGen.place(rng, "shrine", style)
	var sid: String = g.add_structure("shrine", nm, r)
	g.label(nm, c.x + 0.5, r.position.y + 0.5, "shrine", sid)

## A palisade with a gate toward the party; a tower and a barracks inside.
static func _fort(g, side: String, lots: Array, mats: Dictionary, style: String) -> void:
	var rng: RandomNumberGenerator = g.rng
	var across: bool = side in ["north", "south"]
	var fl := clampi(int((g.w if across else g.h) * 0.6), 12, 26)
	var fd := clampi(int((g.h if across else g.w) * 0.55), 10, 20)
	var r := _spot(g, side, lots, fl if across else fd, fd if across else fl)
	if r.position.x < 0:
		r = _spot(g, side, lots, 12 if across else 10, 10 if across else 12)
	if r.position.x < 0:
		_wild_building(g, "tower", side, lots, mats, style)
		return
	_prepare_lot(g, r, mats)
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var p := Vector2i(x, y)
			var edge := x == r.position.x or y == r.position.y or x == r.end.x - 1 or y == r.end.y - 1
			g._put(p, WALL if edge else FLOOR)
			g.gset(p, MapGenerator.G_DIRT)
	var f := Frame.new(r.grow(-1), side)
	var gw := 3 if f.L >= 14 else 2
	var gu := (f.L - gw) / 2
	for k in gw:
		var p := f.at(gu + k, -1)
		g._put(p, FLOOR)
		g.keep_clear[p] = true
		g.keep_clear[f.at(gu + k, 0)] = true
		g.keep_clear[f.at(gu + k, -2)] = true
	g.prop("gatepost", f.at(gu - 1, -1).x, f.at(gu - 1, -1).y)
	g.prop("gatepost", f.at(gu + gw, -1).x, f.at(gu + gw, -1).y)
	var nm := NameGen.place(rng, "fort", style)
	var sid: String = g.add_structure("fort", nm, r)
	g.label(nm, r.position.x + r.size.x / 2.0, r.position.y + 0.5 if side != "north" else r.end.y - 0.5, "fort", sid)
	var smats := mats.duplicate()
	if f.D >= 8 and f.L >= 8:
		building(g, f.rect_of(0, f.D - 6, 6, 6), side, "tower", style, smats)
	if f.D >= 8 and f.L >= 16:
		building(g, f.rect_of(f.L - 8, f.D - 6, 8, 6), side, "barracks", style, smats)
	var used := {}
	for i in rng.randi_range(2, 4):
		var p := rand_free(g, f, used, rng)
		if p.x >= 0 and p.y < f.D - 7:
			put_local(g, f, used, p.x, p.y, 1, 1, ["crate", "barrel", "dummy", "dummy"][rng.randi() % 4])
