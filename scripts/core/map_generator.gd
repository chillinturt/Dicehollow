class_name MapGenerator
extends RefCounted
## DM tool: procedurally builds an encounter map from a settings dictionary. The result has the same shape as
## a saved map (Session.map_snapshot), so it loads through the normal "dm_load_map" request. Generation is
## deterministic for a given seed and settings.
##
## Settings (all optional, see DEFAULTS): terrain, w, h, seed, obstacles, difficult, water, pits, cover (0..1),
## rooms, river, party_side, enemy_distance (0..1), enemy_layout, include_monsters, hidden (0..1), spawn_count,
## plus the encounter settings EncounterBuilder reads (party, difficulty, composition, types, ...).

const FLOOR := EngineBase.FLOOR
const WALL := EngineBase.WALL
const DIFFICULT := EngineBase.DIFFICULT
const WATER := EngineBase.WATER
const PIT := EngineBase.PIT

## Ground materials (map "ground" layer, one byte per cell; drawing only, movement comes from the cells).
## Under open ground it is the floor; under a wall it is what the wall is built of.
const G_NONE := 0      # the theme's own floor / wall
const G_PLANK := 1     # floor: wooden planks   wall: timber frame
const G_COBBLE := 2    # floor: cobblestones    wall: brick / masonry
const G_DIRT := 3      # floor: dirt path       wall: log palisade
const G_FLAG := 4      # floor: flagstones      wall: dressed stone blocks (dwarven)
const G_GRASS := 5     # floor: grass           wall: hedge
const G_RUG := 6       # floor: rug / carpet
const G_STRAW := 7     # floor: straw / hay
const G_LEAF := 8      # floor: woven leaf-wood (elven)  wall: living wood

## Each terrain: how it is laid out, its colour theme and the default environment sliders.
## "habitat" is the monster habitat it draws from (defaults to the terrain's own id), "structures" its default
## wilderness structures (outdoor terrains only, see STRUCTURES).
const TERRAINS := {
	"dungeon": {"name": "Dungeon", "layout": "rooms", "theme": "stone", "obstacles": 0.4, "difficult": 0.1, "water": 0.0, "pits": 0.05, "cover": 0.25, "rooms": 6, "river": false,
		"blurb": "Rooms joined by 10-ft corridors."},
	"cave": {"name": "Cave", "layout": "cave", "theme": "cave", "obstacles": 0.45, "difficult": 0.25, "water": 0.15, "pits": 0.1, "cover": 0.15, "rooms": 0, "river": false,
		"blurb": "Winding natural tunnels and caverns."},
	"forest": {"name": "Forest", "layout": "outdoor", "theme": "forest", "obstacles": 0.35, "difficult": 0.3, "water": 0.08, "pits": 0.0, "cover": 0.35, "rooms": 0, "river": false,
		"blurb": "Tree clusters (walls) and undergrowth."},
	"swamp": {"name": "Swamp", "layout": "outdoor", "theme": "swamp", "obstacles": 0.12, "difficult": 0.45, "water": 0.45, "pits": 0.0, "cover": 0.15, "rooms": 0, "river": false,
		"blurb": "Bogs, pools and mud."},
	"town": {"name": "Town streets", "layout": "town", "theme": "village", "habitat": "town", "obstacles": 0.6, "difficult": 0.25, "water": 0.0, "pits": 0.0, "cover": 0.3, "rooms": 0, "river": false,
		"blurb": "Streets and a square lined with homes, shops, a temple and taverns. Pick human, dwarven or elven below."},
	"indoor": {"name": "Indoors", "layout": "interior", "theme": "tavern", "habitat": "town", "obstacles": 0.3, "difficult": 0.2, "water": 0.0, "pits": 0.0, "cover": 0.2, "rooms": 5, "river": false,
		"blurb": "Inside one building: plain rooms, a tavern or a temple. Furniture is difficult terrain."},
	"arctic": {"name": "Arctic", "layout": "outdoor", "theme": "snow", "obstacles": 0.12, "difficult": 0.4, "water": 0.12, "pits": 0.05, "cover": 0.2, "rooms": 0, "river": false,
		"blurb": "Ice ridges, deep snow and open water."},
	"graveyard": {"name": "Graveyard", "layout": "outdoor", "theme": "ruins", "obstacles": 0.2, "difficult": 0.2, "water": 0.0, "pits": 0.08, "cover": 0.6, "rooms": 0, "river": false,
		"structures": "crypts", "blurb": "Crypts, headstones and open graves."},
	"mountain": {"name": "Mountain pass", "layout": "outdoor", "theme": "badlands", "obstacles": 0.3, "difficult": 0.35, "water": 0.0, "pits": 0.15, "cover": 0.3, "rooms": 0, "river": false,
		"blurb": "Boulders, scree and chasms."},
}
const SIDES := ["west", "east", "north", "south", "random"]
const LAYOUTS := {"group": "One group ahead", "spread": "Spread out", "surround": "Surrounding the party"}

## Structures that can stand in the wild (outdoor terrains).
const STRUCTURES := {
	"none": {"name": "None", "blurb": "Just the land."},
	"ruins": {"name": "Ruins", "blurb": "Broken walls of old buildings, rubble inside."},
	"camp": {"name": "Camp", "blurb": "Tents around a campfire: bandits, hunters or an army scout party."},
	"cabins": {"name": "Cabins", "blurb": "A few lone homes with furniture inside (stilt huts in a swamp)."},
	"tower": {"name": "Watchtower", "blurb": "A stone tower with stairs and supplies, maybe a wall around it."},
	"shrine": {"name": "Shrine", "blurb": "A ring of standing stones around an altar, or a small chapel."},
	"crypts": {"name": "Crypts", "blurb": "Stone mausoleums with sarcophagi inside."},
	"hamlet": {"name": "Hamlet", "blurb": "A handful of homes along a road, with a tavern when there are enough."},
	"inn": {"name": "Roadside inn", "blurb": "A tavern and its stable on a road through the wilds."},
	"fort": {"name": "Fort", "blurb": "A palisade with a gate, a tower and a barracks inside."},
}
## Building styles for towns, hamlets, inns and interiors.
const STYLES := {"human": "Human", "dwarf": "Dwarven", "elf": "Elven"}
## What an "Indoors" map is.
const INTERIORS := {"rooms": "Plain rooms", "tavern": "Tavern", "temple": "Temple"}
## Map colour theme per style (towns and interiors).
const STYLE_THEMES := {"town": {"human": "village", "dwarf": "dwarfhold", "elf": "glade"}, "indoor": {"human": "tavern", "dwarf": "dwarfhold", "elf": "glade"}}

const DEFAULTS := {
	"terrain": "dungeon", "w": 30, "h": 20, "seed": 0, "rooms": 6, "river": false,
	"party_side": "west", "enemy_distance": 0.6, "enemy_layout": "group", "include_monsters": true, "hidden": 0.0,
	"spawn_count": 6, "name": "",
	"structures": "none", "structure_count": 2, "style": "human", "interior": "rooms", "taverns": 1,
	"renames": {},   # generated place name -> the DM's name for it
}

var s: Dictionary
var w: int
var h: int
var cells: PackedByteArray
var rng := RandomNumberGenerator.new()
var spawns: Array = []        # Vector2i
var dist: PackedInt32Array    # walking steps from the party's start points (-1 = unreachable)
var ground: PackedByteArray   # G_* per cell
var props: Array = []         # {"k", "x", "y", "w", "h"}: furniture and dressing, drawn over the cells
var labels: Array = []        # {"text", "x", "y", "kind", "sid"}: place names (x, y: centre, in cells)
var structures: Array = []    # {"id", "type", "name", "gen_name", "rect", "info"}: what was built
var keep_clear := {}          # Vector2i -> true: doorsteps and paths that clutter must not block
var place_name := ""          # a town or hamlet's name

## Settings for `terrain` with its default environment sliders filled in.
static func defaults_for(terrain: String) -> Dictionary:
	var d := DEFAULTS.duplicate(true)
	var t: Dictionary = TERRAINS.get(terrain, TERRAINS.dungeon)
	d.terrain = terrain
	for k in ["obstacles", "difficult", "water", "pits", "cover", "rooms", "river"]:
		d[k] = t[k]
	d.structures = t.get("structures", "none")
	return d

## The colour theme a map built with these settings gets.
static func theme_for(st: Dictionary) -> String:
	var terrain := str(st.get("terrain", "dungeon"))
	var t: Dictionary = TERRAINS.get(terrain, TERRAINS.dungeon)
	if STYLE_THEMES.has(terrain):
		return STYLE_THEMES[terrain].get(str(st.get("style", "human")), t.theme)
	return t.theme

## Build a map. Returns a map dictionary (see Session.map_snapshot) plus "report": the encounter and map summary.
static func generate(settings: Dictionary) -> Dictionary:
	var g = new()
	return g._run(settings)

func _run(settings: Dictionary) -> Dictionary:
	s = defaults_for(str(settings.get("terrain", "dungeon")))
	s.merge(settings, true)
	w = clampi(int(s.w), 8, 80)
	h = clampi(int(s.h), 8, 60)
	rng.seed = hash([int(s.seed), w, h, str(s.terrain)])
	var t: Dictionary = TERRAINS.get(s.terrain, TERRAINS.dungeon)
	if not settings.has("habitat"):
		s.habitat = t.get("habitat", s.terrain)
	if not s.style in STYLES:
		s.style = "human"
	cells = PackedByteArray()
	cells.resize(w * h)
	ground = PackedByteArray()
	ground.resize(w * h)
	match t.layout:
		"rooms": _rooms()
		"cave": _cave()
		"interior":
			if str(s.interior) in ["tavern", "temple"]:
				StructureBuilder.indoor(self)
			else:
				_interior()
		"town": StructureBuilder.town(self)
		_:
			_outdoor()
			if str(s.structures) != "none" and STRUCTURES.has(str(s.structures)):
				StructureBuilder.wilderness(self)
	_choose_spawns()
	_connect()
	_apply_renames()
	var monsters: Array = []
	var enc := {}
	if s.include_monsters:
		var erng := RandomNumberGenerator.new()
		erng.seed = hash([int(s.seed), int(s.get("enc_seed", 0)), "encounter"])
		enc = EncounterBuilder.build(s, erng)
		monsters = _place_monsters(enc.get("picks", []))
	var sp: Array = []
	for p in spawns:
		sp.append([p.x, p.y])
	var custom := {}
	for m in monsters:
		if Data.custom_monsters.has(m.mid):
			custom[m.mid] = Data.custom_monsters[m.mid]
	var nm: String = str(s.name)
	if nm == "":
		if place_name != "":
			nm = place_name
		elif structures.size() == 1 and t.layout == "interior":
			nm = str(structures[0].name)
		else:
			nm = "%s %d" % [t.name, int(s.seed) % 10000]
	var out := {"name": nm, "w": w, "h": h, "cells": Array(cells), "monsters": monsters, "spawns": sp, "theme": theme_for(s), "bg": "",
		"custom_monsters": custom, "report": {"encounter": enc, "terrain": s.terrain, "placed": monsters.size(), "seed": int(s.seed),
			"structures": structures, "place_name": place_name}}
	if Array(ground).any(func(g): return g != G_NONE) or not props.is_empty() or not labels.is_empty():
		out.ground = Array(ground)
		out.props = props
		out.labels = labels
	return out

## The DM's own names for places replace the generated ones (matched by generated name, so they stick for as
## long as the same seed builds the same place).
func _apply_renames() -> void:
	var rn: Dictionary = s.get("renames", {})
	for st in structures:
		var nn := str(rn.get(st.gen_name, "")).strip_edges()
		if nn != "":
			st.name = nn
			if st.info.has("name"):
				st.info.name = nn
		for l in labels:
			if l.get("sid", "") == st.id:
				l.text = st.name
		if st.type == "town":
			place_name = st.name

# ---------------------------------------------------------------- dressing helpers (used by StructureBuilder)

## A prop drawn over the cells at (x, y), `pw` × `ph` cells big. Purely visual.
func prop(k: String, x: int, y: int, pw := 1, ph := 1) -> void:
	if _in(Vector2i(x, y)):
		var p := {"k": k, "x": x, "y": y}
		if pw != 1: p.w = pw
		if ph != 1: p.h = ph
		props.append(p)

func gset(p: Vector2i, code: int) -> void:
	if _in(p):
		ground[_i(p)] = code

func gat(p: Vector2i) -> int:
	return ground[_i(p)] if _in(p) else G_NONE

## A place name drawn on the map at cell coordinates (x, y) (its centre).
func label(text: String, x: float, y: float, kind: String, sid: String) -> void:
	labels.append({"text": text, "x": snappedf(x, 0.5), "y": snappedf(y, 0.5), "kind": kind, "sid": sid, "style": str(s.get("style", "human"))})

## Record a built place; returns its id.
func add_structure(type: String, nm: String, r: Rect2i, info := {}) -> String:
	var id := "s%d" % structures.size()
	structures.append({"id": id, "type": type, "name": nm, "gen_name": nm, "rect": [r.position.x, r.position.y, r.size.x, r.size.y], "info": info})
	return id

# ---------------------------------------------------------------- grid helpers

func _i(p: Vector2i) -> int:
	return p.y * w + p.x

func _in(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < w and p.y < h

func _at(p: Vector2i) -> int:
	return cells[_i(p)] if _in(p) else WALL

func _put(p: Vector2i, v: int) -> void:
	if _in(p):
		cells[_i(p)] = v

func _passable(p: Vector2i) -> bool:
	var v := _at(p)
	return v != WALL and v != PIT

func _fill_rect(r: Rect2i, v: int) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			_put(Vector2i(x, y), v)

## A ragged blob of `v` around `c`, painted only over cells whose value is in `over`.
func _blob(c: Vector2i, radius: float, v: int, over: Array) -> void:
	var r := int(ceil(radius))
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var p := c + Vector2i(dx, dy)
			if _in(p) and _at(p) in over and Vector2(dx, dy).length() <= radius + rng.randf_range(-0.6, 0.4):
				_put(p, v)

func _random_cell_of(vals: Array, tries := 200) -> Vector2i:
	for i in tries:
		var p := Vector2i(rng.randi_range(0, w - 1), rng.randi_range(0, h - 1))
		if _at(p) in vals:
			return p
	return Vector2i(-1, -1)

## How many features to scatter: `per_cell` per map cell with the slider at 100%, scaled linearly by the slider.
func _density(slider: float, per_cell: float) -> int:
	return int(round(w * h * slider * per_cell)) if slider > 0.01 else 0

# ---------------------------------------------------------------- layouts

## Dungeon: rectangular rooms on solid rock, joined in a chain by 2-wide corridors, plus a loop or two.
func _rooms() -> void:
	cells.fill(WALL)
	var want: int = clampi(int(s.rooms), 2, 16)
	var max_side := int(lerpf(12, 5, float(s.obstacles)))
	max_side = clampi(max_side, 4, mini(w, h) - 2)
	var rooms: Array = []
	for attempt in want * 40:
		if rooms.size() >= want:
			break
		var rw := rng.randi_range(4, max_side)
		var rh := rng.randi_range(4, max_side)
		if rw >= w - 2 or rh >= h - 2:
			continue
		var r := Rect2i(rng.randi_range(1, w - rw - 1), rng.randi_range(1, h - rh - 1), rw, rh)
		var ok := true
		for o in rooms:
			if r.grow(1).intersects(o):
				ok = false
				break
		if ok:
			rooms.append(r)
	if rooms.is_empty():
		rooms.append(Rect2i(1, 1, w - 2, h - 2))
	for r in rooms:
		_fill_rect(r, FLOOR)
	# Chain the rooms along the party → enemy axis so the fight has a direction.
	var horiz: bool = str(s.party_side) in ["west", "east", "random"]
	rooms.sort_custom(func(a, b): return (a.get_center().x if horiz else a.get_center().y) < (b.get_center().x if horiz else b.get_center().y))
	for i in range(1, rooms.size()):
		_corridor(rooms[i - 1].get_center(), rooms[i].get_center())
	for i in mini(2, rooms.size() / 3):
		_corridor(rooms[rng.randi() % rooms.size()].get_center(), rooms[rng.randi() % rooms.size()].get_center())
	_overlays([FLOOR])
	# Pillars inside the larger rooms.
	for r in rooms:
		if r.size.x >= 6 and r.size.y >= 6 and rng.randf() < float(s.cover) * 1.5:
			for p in [r.position + Vector2i(1, 1) + Vector2i(1, 1), r.end - Vector2i(3, 3), Vector2i(r.position.x + 2, r.end.y - 3), Vector2i(r.end.x - 3, r.position.y + 2)]:
				_put(p, WALL)

## A 2-wide L-shaped corridor, kept inside the solid outer edge.
func _corridor(a: Vector2i, b: Vector2i) -> void:
	var p := a
	var xfirst := rng.randf() < 0.5
	for leg in 2:
		if (leg == 0) == xfirst:
			while p.x != b.x:
				_dig(p)
				p.x += signi(b.x - p.x)
		else:
			while p.y != b.y:
				_dig(p)
				p.y += signi(b.y - p.y)
	_dig(p)

func _dig(p: Vector2i) -> void:
	for dy in 2:
		for dx in 2:
			var q := p + Vector2i(dx, dy)
			if q.x > 0 and q.y > 0 and q.x < w - 1 and q.y < h - 1 and _at(q) == WALL:
				_put(q, FLOOR)

## Cave: cellular automata smoothing of random rock, then the biggest open region is kept.
func _cave() -> void:
	var fill := lerpf(0.36, 0.52, float(s.obstacles))
	for tries in 6:
		for y in h:
			for x in w:
				var edge := x == 0 or y == 0 or x == w - 1 or y == h - 1
				cells[y * w + x] = WALL if edge or rng.randf() < fill else FLOOR
		for it in 5:
			var nxt := cells.duplicate()
			for y in range(1, h - 1):
				for x in range(1, w - 1):
					var n := 0
					for dy in range(-1, 2):
						for dx in range(-1, 2):
							if (dx != 0 or dy != 0) and cells[(y + dy) * w + x + dx] == WALL:
								n += 1
					nxt[y * w + x] = WALL if n >= 5 or (n == 0 and it < 2 and rng.randf() < 0.3) else (FLOOR if n <= 3 else cells[y * w + x])
			cells = nxt
		if _largest_region().size() >= w * h * 0.35:
			break
		fill -= 0.04
	var keep := {}
	for p in _largest_region():
		keep[p] = true
	for y in h:
		for x in w:
			if not keep.has(Vector2i(x, y)):
				cells[y * w + x] = WALL
	_overlays([FLOOR])

## Outdoors: open ground with clumps of trees or boulders, an optional river, pools, rough ground and cover.
func _outdoor() -> void:
	cells.fill(FLOOR)
	if s.river:
		_river()
	for i in _density(float(s.obstacles), 0.06):
		var c := _random_cell_of([FLOOR])
		if c.x >= 0:
			_blob(c, rng.randf_range(0.6, 2.2), WALL, [FLOOR])
	_overlays([FLOOR])

## A meandering river across the middle (between the two sides), with fords of difficult terrain.
func _river() -> void:
	var vertical: bool = str(s.party_side) in ["west", "east", "random"]
	var length := h if vertical else w
	var across := w if vertical else h
	var c := across / 2 + rng.randi_range(-across / 8, across / 8)
	var width := rng.randi_range(2, 3)
	var fords: Array = []
	for i in rng.randi_range(1, 2):
		fords.append(rng.randi_range(2, length - 4))
	for i in length:
		c = clampi(c + rng.randi_range(-1, 1), 3, across - 4 - width)
		for k in width:
			var p := Vector2i(c + k, i) if vertical else Vector2i(i, c + k)
			var ford := fords.any(func(f): return absi(i - f) <= 1)
			_put(p, DIFFICULT if ford else WATER)

## Inside a building: outer walls, the floor split into rooms with wide doorways, tables as difficult terrain.
func _interior() -> void:
	cells.fill(FLOOR)
	for x in w:
		_put(Vector2i(x, 0), WALL)
		_put(Vector2i(x, h - 1), WALL)
	for y in h:
		_put(Vector2i(0, y), WALL)
		_put(Vector2i(w - 1, y), WALL)
	var regions: Array = [Rect2i(1, 1, w - 2, h - 2)]
	var splits: int = clampi(int(s.rooms) - 1, 0, 14)
	for i in splits:
		regions.sort_custom(func(r1, r2): return r1.get_area() > r2.get_area())
		var r: Rect2i = regions.pop_front()
		var split_x := r.size.x >= r.size.y
		var span := r.size.x if split_x else r.size.y
		if span < 9:
			regions.append(r)
			continue
		var at := rng.randi_range(4, span - 5)
		var a: Rect2i
		var b: Rect2i
		if split_x:
			var wx := r.position.x + at
			for y in range(r.position.y, r.end.y):
				_put(Vector2i(wx, y), WALL)
			var door := rng.randi_range(r.position.y, r.end.y - 2)
			_put(Vector2i(wx, door), FLOOR)
			_put(Vector2i(wx, door + 1), FLOOR)
			a = Rect2i(r.position, Vector2i(at, r.size.y))
			b = Rect2i(wx + 1, r.position.y, r.end.x - wx - 1, r.size.y)
		else:
			var wy := r.position.y + at
			for x in range(r.position.x, r.end.x):
				_put(Vector2i(x, wy), WALL)
			var door := rng.randi_range(r.position.x, r.end.x - 2)
			_put(Vector2i(door, wy), FLOOR)
			_put(Vector2i(door + 1, wy), FLOOR)
			a = Rect2i(r.position, Vector2i(r.size.x, at))
			b = Rect2i(r.position.x, wy + 1, r.size.x, r.end.y - wy - 1)
		regions.append(a)
		regions.append(b)
	# Tables and benches: short runs of difficult terrain away from the walls.
	for i in _density(float(s.difficult), 0.04):
		var c := _random_cell_of([FLOOR])
		if c.x < 0 or _near(c, WALL, 1):
			continue
		var run := Vector2i(1, 0) if rng.randf() < 0.5 else Vector2i(0, 1)
		var n := 0
		for k in rng.randi_range(2, 3):
			if _at(c + run * k) == FLOOR and not _near(c + run * k, WALL, 1):
				_put(c + run * k, DIFFICULT)
				n = k
			else:
				break
		if n >= 1:
			var a := c + run
			var e := c + run * n
			prop("table_long" if n > 1 else "table_round", mini(a.x, e.x), mini(a.y, e.y), absi(e.x - a.x) + 1, absi(e.y - a.y) + 1)
	var keep_difficult := float(s.difficult)
	s.difficult = 0.0   # already placed as tables
	var keep_cover := float(s.cover)
	s.cover = 0.0       # pillars are added below as props
	_overlays([FLOOR])
	s.difficult = keep_difficult
	s.cover = keep_cover
	StructureBuilder.dress_plain(self)
	if keep_cover > 0.01:
		for i in _density(keep_cover, 0.04):
			var c := _random_cell_of([FLOOR])
			if c.x >= 0 and not _near(c, WALL, 1) and not _near(c, PIT, 1) and not _near(c, DIFFICULT, 1):
				_put(c, WALL)
				prop(["pillar", "crate", "barrel", "shelf"][rng.randi() % 4], c.x, c.y)

func _near(p: Vector2i, v: int, r: int) -> bool:
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if (dx != 0 or dy != 0) and _at(p + Vector2i(dx, dy)) == v:
				return true
	return false

## Water, rough ground, pits and cover laid over open floor.
func _overlays(over: Array) -> void:
	var water := float(s.water)
	if water > 0.01:
		for i in maxi(1, _density(water, 0.02)):
			var c := _random_cell_of(over)
			if c.x >= 0:
				_blob(c, rng.randf_range(1.2, 1.5 + 3.0 * water), WATER, over)
	var diff := float(s.difficult)
	if diff > 0.01:
		for i in maxi(1, _density(diff, 0.04)):
			var c := _random_cell_of(over)
			if c.x >= 0:
				_blob(c, rng.randf_range(0.8, 2.6), DIFFICULT, over)
	var pits := float(s.pits)
	if pits > 0.01:
		for i in maxi(1, _density(pits, 0.03)):
			var c := _random_cell_of([FLOOR, DIFFICULT])
			if c.x >= 0 and not _near(c, WALL, 1):
				_blob(c, rng.randf_range(0.5, 1.3), PIT, [FLOOR, DIFFICULT])
	var cover := float(s.cover)
	if cover > 0.01:
		# Lone pillars, rocks or headstones: only where they can't seal off a passage.
		for i in _density(cover, 0.06):
			var c := _random_cell_of([FLOOR, DIFFICULT])
			if c.x >= 0 and not _near(c, WALL, 1) and not _near(c, PIT, 1):
				_put(c, WALL)

# ---------------------------------------------------------------- connectivity and start points

func _neighbors(p: Vector2i) -> Array:
	var out: Array = []
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
		var q: Vector2i = p + d
		if _in(q):
			out.append(q)
	return out

func _region_from(start: Vector2i) -> Array:
	var seen := {start: true}
	var out: Array = [start]
	var i := 0
	while i < out.size():
		for q in _neighbors(out[i]):
			if not seen.has(q) and _passable(q):
				seen[q] = true
				out.append(q)
		i += 1
	return out

func _largest_region() -> Array:
	var seen := {}
	var best: Array = []
	for y in h:
		for x in w:
			var p := Vector2i(x, y)
			if seen.has(p) or not _passable(p):
				continue
			var reg := _region_from(p)
			for q in reg:
				seen[q] = true
			if reg.size() > best.size():
				best = reg
	return best

func _side() -> String:
	var side := str(s.party_side)
	if side == "random" or not side in SIDES:
		side = ["west", "east", "north", "south"][rng.randi() % 4]
		s.party_side = side
	return side

## Start points: a tight cluster of open cells closest to the middle of the party's map edge.
func _choose_spawns() -> void:
	var side := _side()
	var anchor := Vector2(w * 0.5, h * 0.5)
	match side:
		"west": anchor = Vector2(0, h * 0.5)
		"east": anchor = Vector2(w - 1, h * 0.5)
		"north": anchor = Vector2(w * 0.5, 0)
		"south": anchor = Vector2(w * 0.5, h - 1)
	var region := _largest_region()
	if region.is_empty():
		cells.fill(FLOOR)
		region = _largest_region()
	var best: Vector2i = region[0]
	var bd := INF
	for p in region:
		var d := Vector2(p).distance_to(anchor) + (3.0 if _at(p) != FLOOR else 0.0)
		if d < bd:
			bd = d
			best = p
	var want: int = clampi(int(s.spawn_count), 1, 12)
	spawns = []
	var seen := {best: true}
	var q: Array = [best]
	var i := 0
	while i < q.size() and spawns.size() < want:
		var p: Vector2i = q[i]
		i += 1
		if _at(p) in [FLOOR, DIFFICULT]:
			spawns.append(p)
		for n in _neighbors(p):
			if not seen.has(n) and _passable(n):
				seen[n] = true
				q.append(n)

## Everything the party can't walk to becomes solid, and walking distances from the start points are recorded.
func _connect() -> void:
	dist = PackedInt32Array()
	dist.resize(w * h)
	dist.fill(-1)
	var q: Array = []
	for p in spawns:
		dist[_i(p)] = 0
		q.append(p)
	var i := 0
	while i < q.size():
		var p: Vector2i = q[i]
		i += 1
		for n in _neighbors(p):
			if dist[_i(n)] < 0 and _passable(n):
				dist[_i(n)] = dist[_i(p)] + 1
				q.append(n)
	for y in h:
		for x in w:
			var p := Vector2i(x, y)
			if dist[_i(p)] < 0 and _at(p) != PIT:
				_put(p, WALL)

# ---------------------------------------------------------------- monsters

func _fits(m: Dictionary, p: Vector2i, taken: Dictionary) -> bool:
	var sz: int = CombatantFactory.SIZE_CELLS.get(str(m.get("size", "medium")), 1)
	var flies: bool = int(m.get("fly", 0)) > 0
	var swims: bool = int(m.get("swim", 0)) > 0
	for dx in sz:
		for dy in sz:
			var q := p + Vector2i(dx, dy)
			if not _in(q) or not _passable(q) or taken.has(q) or q in spawns or dist[_i(q)] < 3:
				return false
			if _at(q) == WATER and not (swims or flies):
				return false
	return true

func _claim(m: Dictionary, p: Vector2i, taken: Dictionary) -> void:
	var sz: int = CombatantFactory.SIZE_CELLS.get(str(m.get("size", "medium")), 1)
	for dx in sz:
		for dy in sz:
			taken[p + Vector2i(dx, dy)] = true

## Cells at roughly `frac` of the way from the party to the far side of the map, best first.
func _anchor_candidates(frac: float) -> Array:
	var maxd := 0
	for d in dist:
		maxd = maxi(maxd, d)
	var want := maxf(5.0, frac * maxd)
	var out: Array = []
	for y in h:
		for x in w:
			var d: int = dist[y * w + x]
			if d >= 3 and _at(Vector2i(x, y)) != WATER:
				out.append([absf(d - want) + rng.randf() * 2.0, Vector2i(x, y)])
	out.sort_custom(func(a, b): return a[0] < b[0])
	return out.map(func(e): return e[1])

func _place_monsters(picks: Array) -> Array:
	var list: Array = []   # one entry per creature, biggest first so they get the roomy spots
	for p in picks:
		for i in int(p.count):
			list.append(str(p.mid))
	list.sort_custom(func(a, b): return CombatantFactory.SIZE_CELLS.get(str(Data.monster(a).get("size", "medium")), 1) > CombatantFactory.SIZE_CELLS.get(str(Data.monster(b).get("size", "medium")), 1))
	if list.is_empty():
		return []
	var layout := str(s.enemy_layout)
	var anchors: Array = []
	var center := Vector2.ZERO
	for p in spawns:
		center += Vector2(p)
	center /= maxf(1.0, spawns.size())
	if layout == "surround":
		# Several groups at a short walk, around the party in different directions.
		var cands := _anchor_candidates(0.3)
		var groups := clampi(list.size(), 2, 4)
		for c in cands:
			if anchors.size() >= groups:
				break
			var ang := (Vector2(c) - center).angle()
			var ok := true
			for a in anchors:
				if absf(angle_difference(ang, (Vector2(a) - center).angle())) < TAU / (groups + 1):
					ok = false
					break
			if ok:
				anchors.append(c)
	else:
		var cands := _anchor_candidates(float(s.enemy_distance) * 0.85 + 0.15)
		var kinds := 1
		if layout == "spread":
			kinds = clampi(picks.size() + 1, 2, 4)
		for c in cands:
			if anchors.size() >= kinds:
				break
			if anchors.all(func(a): return Vector2(a).distance_to(Vector2(c)) >= 6):
				anchors.append(c)
	if anchors.is_empty():
		anchors.append(Vector2i(w / 2, h / 2))
	var taken := {}
	var out: Array = []
	var gi := 0
	for mid in list:
		var m: Dictionary = Data.monster(mid)
		var anchor: Vector2i = anchors[gi % anchors.size()]
		gi += 1
		var spot := _nearest_fit(m, anchor, taken)
		if spot.x < 0:
			continue
		_claim(m, spot, taken)
		out.append({"mid": mid, "x": spot.x, "y": spot.y, "team": "enemy"})
	# Ambush: a share of the monsters start hidden.
	var hide_n := int(round(float(s.hidden) * out.size()))
	var order := range(out.size())
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = order[i]
		order[i] = order[j]
		order[j] = tmp
	for k in hide_n:
		out[order[k]].hidden = true
	return out

func _nearest_fit(m: Dictionary, anchor: Vector2i, taken: Dictionary) -> Vector2i:
	var r := maxi(w, h)
	for rad in r:
		var ring: Array = []
		for dy in range(-rad, rad + 1):
			for dx in range(-rad, rad + 1):
				if maxi(absi(dx), absi(dy)) == rad:
					ring.append(anchor + Vector2i(dx, dy))
		# Shuffle the ring a little so groups don't line up in rows.
		for i in range(ring.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp = ring[i]
			ring[i] = ring[j]
			ring[j] = tmp
		for p in ring:
			if _fits(m, p, taken):
				return p
	return Vector2i(-1, -1)
