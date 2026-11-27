extends Node2D
## Draws the battle grid: floor, walls, terrain, spell zones, spawn points and interaction highlights.

const CELL := 64

const THEMES := {
	"stone": {"floor_a": Color("#3b3646"), "floor_b": Color("#37323f"), "wall": Color("#17141d"), "wall_top": Color("#5a5168"), "grid": Color(1, 1, 1, 0.06)},
	"forest": {"floor_a": Color("#2f4a2c"), "floor_b": Color("#2b4428"), "wall": Color("#16241a"), "wall_top": Color("#3f6b3a"), "grid": Color(1, 1, 1, 0.05)},
	"cave": {"floor_a": Color("#3d3328"), "floor_b": Color("#382f25"), "wall": Color("#15100c"), "wall_top": Color("#5c4a38"), "grid": Color(1, 1, 1, 0.05)},
	"tavern": {"floor_a": Color("#5a3f28"), "floor_b": Color("#543a25"), "wall": Color("#21160e"), "wall_top": Color("#7a5a3a"), "grid": Color(0, 0, 0, 0.12)},
	"snow": {"floor_a": Color("#c9d3dc"), "floor_b": Color("#c2ccd6"), "wall": Color("#56606e"), "wall_top": Color("#8f9aa8"), "grid": Color(0, 0, 0, 0.08)},
	"swamp": {"floor_a": Color("#36442c"), "floor_b": Color("#323f29"), "wall": Color("#1a2214"), "wall_top": Color("#4d5e34"), "grid": Color(1, 1, 1, 0.05)},
	"ruins": {"floor_a": Color("#3a4038"), "floor_b": Color("#363c34"), "wall": Color("#1b1e1b"), "wall_top": Color("#6a706a"), "grid": Color(1, 1, 1, 0.05)},
	"badlands": {"floor_a": Color("#6b5640"), "floor_b": Color("#65513c"), "wall": Color("#2e2218"), "wall_top": Color("#8f7556"), "grid": Color(0, 0, 0, 0.1)},
}

var state: Dictionary = {}
var reach_cells: Dictionary = {}
var path_cells: Array = []
var area_cells: Array = []
var area_color := Color(1, 0.5, 0.2)
var target_cells: Array = []
var range_center := Vector2.ZERO
var range_ft := 0
var hover := Vector2i(-1, -1)
var show_spawns := false
## Fog of war (a Fog.view_for result; {} = none). fog_dm: the DM sees through it, only shaded.
var fog: Dictionary = {}
var fog_dm := false

func _ready() -> void:
	Session.bg_arrived.connect(func(_k): queue_redraw())

func set_state(st: Dictionary) -> void:
	state = st
	queue_redraw()

func cell_rect(p: Vector2i) -> Rect2:
	return Rect2(Vector2(p) * CELL, Vector2(CELL, CELL))

func _draw() -> void:
	if state.is_empty():
		return
	var w: int = state.w
	var h: int = state.h
	var th: Dictionary = THEMES.get(state.get("theme", "stone"), THEMES.stone)
	var cells: PackedByteArray = state.cells
	draw_rect(Rect2(-CELL * 0.25, -CELL * 0.25, w * CELL + CELL * 0.5, h * CELL + CELL * 0.5), Color("#0b0910"))
	var bg_tex: Texture2D = CharacterStore.bg_texture(str(state.get("bg", "")))
	var wa := 0.55 if bg_tex else 1.0   # terrain is see-through over a background image
	if bg_tex:
		draw_texture_rect(bg_tex, Rect2(0, 0, w * CELL, h * CELL), false)
	for y in h:
		for x in w:
			var v = cells[y * w + x]
			var r = cell_rect(Vector2i(x, y))
			var base: Color = th.floor_a if (x + y) % 2 == 0 else th.floor_b
			# Deterministic speckle so floors don't look flat.
			var n = float((x * 73856093) ^ (y * 19349663)) / 4294967296.0
			base = base.lightened(fposmod(n, 0.04))
			match v:
				EngineBase.WALL:
					draw_rect(r, Color(th.wall, wa))
					draw_rect(Rect2(r.position + Vector2(3, 3), r.size - Vector2(6, 12)), Color(th.wall_top, wa))
					draw_rect(Rect2(r.position + Vector2(3, r.size.y - 9), Vector2(r.size.x - 6, 6)), th.wall.darkened(0.3))
				EngineBase.DIFFICULT:
					draw_rect(r, Color(base.darkened(0.12), 0.3 if bg_tex else 1.0))
					for i in 5:
						var p = r.position + Vector2(10 + (i * 23) % 44, 12 + (i * 17) % 40)
						draw_circle(p, 4.0, base.darkened(0.45))
						draw_circle(p + Vector2(-1, -1), 2.5, base.lightened(0.1))
				EngineBase.WATER:
					draw_rect(r, Color(0.14, 0.32, 0.48, 0.45 if bg_tex else 1.0))
					draw_line(r.position + Vector2(8, 22), r.position + Vector2(28, 18), Color("#4a86b8"), 2)
					draw_line(r.position + Vector2(30, 44), r.position + Vector2(54, 40), Color("#4a86b8"), 2)
				EngineBase.PIT:
					draw_rect(r, Color(0.02, 0.016, 0.03, 0.6 if bg_tex else 1.0))
					draw_rect(r, Color("#2a2230"), false, 2)
				_:
					if not bg_tex:
						draw_rect(r, base)
	# Grid lines.
	if bg_tex:
		th = th.duplicate()
		th.grid = Color(1, 1, 1, 0.22)
	for x in w + 1:
		draw_line(Vector2(x * CELL, 0), Vector2(x * CELL, h * CELL), th.grid, 1)
	for y in h + 1:
		draw_line(Vector2(0, y * CELL), Vector2(w * CELL, y * CELL), th.grid, 1)
	# Spell zones.
	for z in state.get("zones", []):
		if z.get("hidden", false) or not z.cells.any(_shown):
			continue
		var col = Color(z.get("color", "#c8a0ff"))
		col.a = 0.28
		for p in z.cells:
			draw_rect(cell_rect(p), col)
		if z.cells.size() > 0:
			draw_string(ThemeDB.fallback_font, Vector2(z.cells[0]) * CELL + Vector2(4, 14), z.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.8))
	# Loose items on the ground (magic stones): small glowing pebbles, several per cell fanned out.
	var per_cell = {}
	for it in state.get("items", []):
		var k: Vector2i = it.pos
		if not _shown(k):
			continue
		var i: int = per_cell.get(k, 0)
		per_cell[k] = i + 1
		var cen2 = Vector2(k) * CELL + Vector2(CELL * 0.5, CELL * 0.72) + Vector2((i % 3 - 1) * 11, -(i / 3) * 10)
		draw_circle(cen2, 9.0, Color(0.75, 0.6, 1.0, 0.25))
		draw_circle(cen2, 5.0, Color("#8c7fa8"))
		draw_circle(cen2 + Vector2(-1.5, -1.5), 2.2, Color("#e6dcff"))
	# Rope Tricks: a rope hanging from the shimmer of the entrance overhead.
	for rp in state.get("ropes", []):
		if not _shown(rp.pos):
			continue
		var rr = cell_rect(rp.pos)
		var top = rr.position + Vector2(CELL * 0.5, 9)
		var rope_pts = PackedVector2Array()
		for i in 9:
			var f = i / 8.0
			rope_pts.append(top + Vector2(sin(f * TAU * 1.5) * 3.0, 4 + f * (CELL - 30)))
		draw_polyline(rope_pts, Color("#3a2c1a"), 5, true)
		draw_polyline(rope_pts, Color("#d9b77a"), 2.5, true)
		draw_set_transform(top, 0.0, Vector2(1.0, 0.45))
		draw_circle(Vector2.ZERO, 15, Color(0.75, 0.6, 1.0, 0.22))
		draw_arc(Vector2.ZERO, 15, 0, TAU, 32, Color(0.85, 0.75, 1.0, 0.9), 2)
		draw_set_transform(Vector2.ZERO)
		draw_string(ThemeDB.fallback_font, rr.position + Vector2(3, CELL - 5), str(rp.get("name", "Rope Trick")), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.8))
	# Auras around casters.
	for c in state.get("combatants", {}).values():
		if c.get("dead", false) or not (fog.is_empty() or fog_dm or Fog.sees(fog, Session.engine, c)):
			continue
		for e in c.effects:
			var a: Dictionary = e.get("aura", {})
			if not a.is_empty():
				var cen = (Vector2(c.pos) + Vector2(c.sz, c.sz) * 0.5) * CELL
				var rad = (float(a.get("radius", 10)) / 5.0 + c.sz * 0.5) * CELL
				var col2 = Color("#fff2a8") if a.has("temp_hp") else Color("#c8a0ff")
				draw_circle(cen, rad, Color(col2, 0.07))
				draw_arc(cen, rad, 0, TAU, 64, Color(col2, 0.5), 2)
	_draw_fog(w, h)
	if show_spawns:
		for p in state.get("spawns", []):
			var r2 = cell_rect(p)
			draw_rect(r2.grow(-6), Color(0.3, 0.7, 1, 0.25))
			draw_string(ThemeDB.fallback_font, r2.position + Vector2(10, 38), "START", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.6, 0.85, 1))
	# Movement range.
	for p in reach_cells:
		if not reach_cells[p].get("occupied", false):
			draw_rect(cell_rect(p).grow(-2), Color(0.35, 0.65, 1.0, 0.13))
	# Weapon/spell range ring.
	if range_ft > 0:
		draw_arc(range_center, (range_ft / 5.0 + 0.5) * CELL, 0, TAU, 96, Color(1, 0.85, 0.4, 0.45), 2)
	for p in target_cells:
		draw_rect(cell_rect(p).grow(-3), Color(1, 0.3, 0.25, 0.22))
	for p in area_cells:
		draw_rect(cell_rect(p), Color(area_color, 0.32))
		draw_rect(cell_rect(p), Color(area_color, 0.6), false, 1)
	if path_cells.size() > 1:
		var pts = PackedVector2Array()
		for p in path_cells:
			pts.append(Vector2(p) * CELL + Vector2(CELL, CELL) * 0.5)
		draw_polyline(pts, Color(1, 0.9, 0.5, 0.85), 4, true)
		draw_circle(pts[pts.size() - 1], 8, Color(1, 0.9, 0.5))
	if hover.x >= 0 and hover.x < w and hover.y >= 0 and hover.y < h:
		draw_rect(cell_rect(hover), Color(1, 1, 1, 0.5), false, 2)

## Whether things on cell p (zones, items, ropes) are drawn: in sight, or the DM is looking.
func _shown(p: Vector2i) -> bool:
	if fog.is_empty() or fog_dm:
		return true
	var w: int = state.w
	return p.x >= 0 and p.y >= 0 and p.x < w and p.y < int(state.h) and fog.visible[p.y * w + p.x] == 1

## Fog of war over the map. Out of sight: dimmed. Never seen, with hard fog: black. The DM gets the
## same picture, only faint, so they can tell what the party can and can't see.
func _draw_fog(w: int, h: int) -> void:
	if fog.is_empty():
		return
	var hard: bool = fog.mode == "hard"
	var vis: PackedByteArray = fog.visible
	var known: PackedByteArray = fog.explored
	var dim := Color(0.03, 0.02, 0.06, 0.22 if fog_dm else 0.58)
	var black := Color(0.04, 0.035, 0.06, 0.45) if fog_dm else Color("#0b0910")
	for y in h:
		# Runs of same-shaded cells in a row are drawn as one rectangle.
		var x := 0
		while x < w:
			var i := y * w + x
			var shade := 0 if vis[i] else (2 if hard and not known[i] else 1)
			var x2 := x + 1
			while x2 < w:
				var j := y * w + x2
				if (0 if vis[j] else (2 if hard and not known[j] else 1)) != shade:
					break
				x2 += 1
			if shade > 0:
				draw_rect(Rect2(x * CELL, y * CELL, (x2 - x) * CELL, CELL), black if shade == 2 else dim)
			x = x2
	# A soft edge where sight ends, so the boundary doesn't look like a grid of tiles.
	if not fog_dm:
		var edge := Color(dim, dim.a * 0.45)
		for y in h:
			for x in w:
				if not vis[y * w + x]:
					continue
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var q: Vector2i = Vector2i(x, y) + d
					if q.x < 0 or q.y < 0 or q.x >= w or q.y >= h or vis[q.y * w + q.x]:
						continue
					var r := cell_rect(Vector2i(x, y))
					var band := 10.0
					var br := Rect2(r.position + Vector2(maxf(0, d.x) * (CELL - band), maxf(0, d.y) * (CELL - band)), Vector2(float(CELL) if d.x == 0 else band, float(CELL) if d.y == 0 else band))
					draw_rect(br, edge)
