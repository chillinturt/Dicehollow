class_name MapDecor
extends RefCounted
## Draws map dressing at any cell size: ground materials (planks, cobbles, flagstones, rugs... and what walls
## are built of), furniture and other props, and place-name labels. Used by the battle map (64 px cells) and
## the map generator's preview (small cells, less detail).

## Props that hang on a wall: the wall is drawn under them. Every other prop on a wall cell is free-standing
## (a forge, a tree, a tent): the floor is drawn under it instead.
const WALL_MOUNTED := ["hearth", "keg", "wallshelf", "oven", "rack", "trophy", "dartboard", "shrine", "banner", "door"]

const FLOORS := {
	1: Color("#6b4a2f"), 2: Color("#5d5a58"), 3: Color("#6e5a3e"), 4: Color("#55525a"), 5: Color("#3f5e34"), 6: Color("#7a2630"),
	7: Color("#a08a4a"), 8: Color("#4f5a36"),
}
const WALLS := {
	1: [Color("#3d2a1a"), Color("#5a3f27")], 2: [Color("#38363d"), Color("#67636d")], 3: [Color("#3e2c1a"), Color("#6a4c2c")],
	4: [Color("#2f2d33"), Color("#5b5862")], 5: [Color("#1d2f19"), Color("#33502b")], 8: [Color("#2e3a20"), Color("#5b6b3a")],
}
const WOOD := Color("#7a5534")
const WOOD_DARK := Color("#4a321f")
const STONE := Color("#8a8690")
const STONE_DARK := Color("#55525a")

## Cells covered by props, so terrain doodles (rubble dots) aren't drawn under furniture: Vector2i -> prop.
static func covered(props: Array) -> Dictionary:
	var out := {}
	for p in props:
		for dx in int(p.get("w", 1)):
			for dy in int(p.get("h", 1)):
				out[Vector2i(int(p.x) + dx, int(p.y) + dy)] = p
	return out

## Whether wall cell `c` should look like floor (a free-standing prop stands on it).
static func free_standing(cov: Dictionary, c: Vector2i) -> bool:
	return cov.has(c) and not str(cov[c].k) in WALL_MOUNTED

# ---------------------------------------------------------------- ground

static func draw_floor(ci: CanvasItem, r: Rect2, code: int, x: int, y: int, detail: bool, a := 1.0) -> void:
	var base: Color = FLOORS.get(code, Color("#3b3646"))
	var n := float(((x * 73856093) ^ (y * 19349663)) & 0xffff) / 65536.0
	ci.draw_rect(r, Color(base.lightened(n * 0.05), a))
	if not detail:
		return
	var s := r.size.x
	var o := r.position
	match code:
		1:  # planks running across, staggered seams
			var dk := Color(base.darkened(0.35), a)
			for i in range(1, 3):
				ci.draw_line(o + Vector2(0, s * i / 3.0), o + Vector2(s, s * i / 3.0), dk, maxf(1.0, s / 40.0))
			for i in 3:
				var sx := fposmod((x * 0.37 + i * 0.41 + y * 0.13) * s, s)
				ci.draw_line(o + Vector2(sx, s * i / 3.0), o + Vector2(sx, s * (i + 1) / 3.0), dk, maxf(1.0, s / 50.0))
		2:  # cobbles
			var st := Color(base.lightened(0.15), a)
			var dk := Color(base.darkened(0.3), a)
			for i in 4:
				var cx := (0.27 + (i % 2) * 0.48 + fposmod(n * (i + 1) * 3.1, 0.1)) * s
				var cy := (0.27 + (i / 2) * 0.48) * s
				ci.draw_circle(o + Vector2(cx, cy), s * 0.2, dk)
				ci.draw_circle(o + Vector2(cx, cy) - Vector2(1, 1), s * 0.17, st)
		3:  # dirt
			var dk := Color(base.darkened(0.2), a)
			for i in 4:
				ci.draw_circle(o + Vector2(fposmod(n * 97.0 * (i + 1), 1.0), fposmod(n * 61.0 * (i + 2), 1.0)) * s, s * 0.04, dk)
		4:  # big flagstones
			var dk := Color(base.darkened(0.3), a)
			var off := 0.5 if y % 2 == 0 else 0.0
			ci.draw_line(o + Vector2(0, s * 0.5), o + Vector2(s, s * 0.5), dk, maxf(1.0, s / 45.0))
			ci.draw_line(o + Vector2(s * off, 0), o + Vector2(s * off, s * 0.5), dk, maxf(1.0, s / 45.0))
			ci.draw_line(o + Vector2(s * fposmod(off + 0.5, 1.0), s * 0.5), o + Vector2(s * fposmod(off + 0.5, 1.0), s), dk, maxf(1.0, s / 45.0))
		5:  # grass tufts
			var lt := Color(base.lightened(0.18), a)
			for i in 3:
				var p := o + Vector2(fposmod(n * 53.0 * (i + 1), 0.8) + 0.1, fposmod(n * 37.0 * (i + 3), 0.8) + 0.15) * s
				ci.draw_line(p, p + Vector2(-s * 0.05, -s * 0.1), lt, maxf(1.0, s / 40.0))
				ci.draw_line(p, p + Vector2(s * 0.05, -s * 0.1), lt, maxf(1.0, s / 40.0))
		6:  # rug: a woven pattern
			ci.draw_rect(r.grow(-s * 0.08), Color("#c9a14a", a * 0.55), false, maxf(1.0, s / 32.0))
			ci.draw_circle(r.get_center(), s * 0.12, Color("#c9a14a", a * 0.45))
		7:  # straw
			var dk := Color(base.darkened(0.25), a)
			for i in 5:
				var p := o + Vector2(fposmod(n * 41.0 * (i + 1), 0.8) + 0.1, fposmod(n * 29.0 * (i + 2), 0.8) + 0.1) * s
				ci.draw_line(p, p + Vector2(s * 0.18, s * 0.05 * (1 if i % 2 == 0 else -1)), dk, maxf(1.0, s / 50.0))
		8:  # woven leaf-wood: curved boards
			var lt := Color(base.lightened(0.12), a)
			for i in 2:
				var cy := s * (0.3 + i * 0.4)
				ci.draw_arc(o + Vector2(s * 0.5, cy + s * 0.5), s * 0.55, -PI * 0.75, -PI * 0.25, 8, lt, maxf(1.0, s / 40.0))

static func draw_wall(ci: CanvasItem, r: Rect2, code: int, x: int, y: int, detail: bool, a := 1.0) -> void:
	var cols: Array = WALLS.get(code, WALLS[2])
	var dark: Color = cols[0]
	var top: Color = cols[1]
	var s := r.size.x
	var o := r.position
	ci.draw_rect(r, Color(dark, a))
	if not detail:
		ci.draw_rect(r.grow(-s * 0.12), Color(top, a))
		return
	var inset := Rect2(o + Vector2(3, 3) * s / 64.0, r.size - Vector2(6, 12) * s / 64.0)
	ci.draw_rect(inset, Color(top, a))
	var line := Color(dark.darkened(0.2), a)
	var lw := maxf(1.0, s / 40.0)
	match code:
		1:  # timber frame: beams and a diagonal brace
			ci.draw_rect(Rect2(inset.position, Vector2(inset.size.x, inset.size.y * 0.18)), Color(top.darkened(0.3), a))
			ci.draw_line(inset.position + Vector2(0, inset.size.y), inset.position + Vector2(inset.size.x, inset.size.y * 0.18), line, lw * 1.5)
		2:  # bricks
			for i in range(1, 4):
				ci.draw_line(inset.position + Vector2(0, inset.size.y * i / 4.0), inset.position + Vector2(inset.size.x, inset.size.y * i / 4.0), line, lw)
			for i in 4:
				var bx := inset.size.x * (0.5 if i % 2 == 0 else 0.25)
				ci.draw_line(inset.position + Vector2(bx, inset.size.y * i / 4.0), inset.position + Vector2(bx, inset.size.y * (i + 1) / 4.0), line, lw)
				if i % 2 == 1:
					ci.draw_line(inset.position + Vector2(inset.size.x * 0.75, inset.size.y * i / 4.0), inset.position + Vector2(inset.size.x * 0.75, inset.size.y * (i + 1) / 4.0), line, lw)
		3:  # palisade: upright logs with points
			for i in 3:
				var lx := inset.position.x + inset.size.x * (i + 0.5) / 3.0
				ci.draw_line(Vector2(lx - inset.size.x / 6.0, inset.position.y + s * 0.1), Vector2(lx - inset.size.x / 6.0, inset.end.y), line, lw)
				ci.draw_colored_polygon(PackedVector2Array([Vector2(lx - inset.size.x / 6.0, inset.position.y + s * 0.1), Vector2(lx, inset.position.y - s * 0.02), Vector2(lx + inset.size.x / 6.0, inset.position.y + s * 0.1)]), Color(top.lightened(0.15), a))
		4:  # dressed stone blocks
			ci.draw_line(inset.position + Vector2(0, inset.size.y * 0.5), inset.position + Vector2(inset.size.x, inset.size.y * 0.5), line, lw)
			var off := 0.33 if (x + y) % 2 == 0 else 0.66
			ci.draw_line(inset.position + Vector2(inset.size.x * off, 0), inset.position + Vector2(inset.size.x * off, inset.size.y * 0.5), line, lw)
			ci.draw_line(inset.position + Vector2(inset.size.x * (1.0 - off), inset.size.y * 0.5), inset.position + Vector2(inset.size.x * (1.0 - off), inset.size.y), line, lw)
		5:  # hedge
			for i in 4:
				ci.draw_circle(inset.position + Vector2(inset.size.x * (0.25 + (i % 2) * 0.5), inset.size.y * (0.3 + (i / 2) * 0.45)), s * 0.17, Color(top.lightened(0.08 * (i % 2)), a))
		8:  # living wood: bark grain
			for i in 3:
				var lx := inset.position.x + inset.size.x * (0.2 + i * 0.3)
				ci.draw_line(Vector2(lx, inset.position.y), Vector2(lx + s * 0.05 * sin(x + i), inset.end.y), Color(top.darkened(0.3), a), lw)
	ci.draw_rect(Rect2(o + Vector2(3, s - 9 * s / 64.0), Vector2(s - 6 * s / 64.0, 6 * s / 64.0)), Color(dark.darkened(0.3), a))

# ---------------------------------------------------------------- props

static func draw_props(ci: CanvasItem, props: Array, off: Vector2, cs: float, shown: Callable = Callable()) -> void:
	for p in props:
		if shown.is_valid() and not shown.call(Vector2i(int(p.x), int(p.y))):
			continue
		draw_prop(ci, p, off, cs)

static func draw_prop(ci: CanvasItem, p: Dictionary, off: Vector2, cs: float) -> void:
	var pw := int(p.get("w", 1))
	var ph := int(p.get("h", 1))
	var r := Rect2(off + Vector2(int(p.x), int(p.y)) * cs, Vector2(pw, ph) * cs)
	var c := r.get_center()
	var s := cs
	var lw := maxf(1.0, s / 32.0)
	var detail := s >= 20.0
	match str(p.k):
		"door":
			ci.draw_rect(r.grow(-s * 0.14), Color("#6b4423"))
			ci.draw_rect(r.grow(-s * 0.14), Color("#2e1d0f"), false, lw)
			if detail:
				ci.draw_circle(c + Vector2(s * 0.18, 0), s * 0.05, Color("#c9a14a"))
		"table_round":
			ci.draw_circle(c + Vector2(s * 0.03, s * 0.04), s * 0.34, Color(0, 0, 0, 0.3))
			ci.draw_circle(c, s * 0.33, WOOD_DARK)
			ci.draw_circle(c, s * 0.28, WOOD)
			if detail:
				ci.draw_circle(c + Vector2(-s * 0.1, -s * 0.06), s * 0.06, Color("#d9c9a0"))
				ci.draw_circle(c + Vector2(s * 0.09, s * 0.08), s * 0.05, Color("#b08a4a"))
		"table_long", "worktable":
			var tb := r.grow(-s * 0.16)
			ci.draw_rect(Rect2(tb.position + Vector2(s * 0.04, s * 0.05), tb.size), Color(0, 0, 0, 0.3))
			ci.draw_rect(tb, WOOD_DARK)
			ci.draw_rect(tb.grow(-s * 0.04), WOOD)
			if detail:
				var horiz := pw >= ph
				var n := maxi(pw, ph)
				for i in n:
					var q := Vector2(r.position.x + (i + 0.5) * s, c.y) if horiz else Vector2(c.x, r.position.y + (i + 0.5) * s)
					ci.draw_circle(q, s * 0.06, Color("#d9c9a0") if i % 2 == 0 else Color("#8c5a3a"))
		"chair", "bench":
			var k := 0.26 if str(p.k) == "chair" else 0.2
			ci.draw_rect(r.grow(-s * k), WOOD_DARK)
			if detail:
				ci.draw_rect(r.grow(-s * (k + 0.06)), WOOD.darkened(0.1))
		"armchair":
			ci.draw_rect(r.grow(-s * 0.18), Color("#5a2028"))
			ci.draw_rect(r.grow(-s * 0.28), Color("#8a3440"))
		"bar", "counter":
			ci.draw_rect(r.grow(-s * 0.06), Color("#3a2414"))
			ci.draw_rect(r.grow(-s * 0.12), Color("#6e4526"))
			if detail:
				ci.draw_line(r.position + Vector2(s * 0.12, s * 0.3), r.position + Vector2(s * 0.88, s * 0.3), Color("#9a6a3c"), lw)
		"keg", "barrel":
			ci.draw_circle(c, s * 0.3, Color("#4a2e18"))
			ci.draw_circle(c, s * 0.25, Color("#7a5030"))
			ci.draw_arc(c, s * 0.25, 0, TAU, 16, Color("#2a1a0e"), lw)
			if detail:
				ci.draw_arc(c, s * 0.15, 0, TAU, 12, Color("#2a1a0e"), lw)
		"bigbarrel":
			ci.draw_circle(c, s * 0.85, Color("#4a2e18"))
			ci.draw_circle(c, s * 0.75, Color("#7a5030"))
			for i in 3:
				ci.draw_arc(c, s * (0.25 + i * 0.22), 0, TAU, 24, Color("#2a1a0e"), lw)
		"crate":
			var q := r.grow(-s * 0.18)
			ci.draw_rect(q, Color("#8a6a3e"))
			ci.draw_rect(q, Color("#4a3418"), false, lw)
			if detail:
				ci.draw_line(q.position, q.end, Color("#4a3418"), lw)
				ci.draw_line(Vector2(q.end.x, q.position.y), Vector2(q.position.x, q.end.y), Color("#4a3418"), lw)
		"shelf", "wallshelf":
			var q := r.grow(-s * 0.1)
			ci.draw_rect(q, Color("#4a321f"))
			if detail:
				var cols := [Color("#a33"), Color("#36a"), Color("#c9a14a"), Color("#4a8")]
				for i in 4:
					ci.draw_rect(Rect2(q.position + Vector2(q.size.x * (0.08 + i * 0.23), q.size.y * 0.2), Vector2(q.size.x * 0.16, q.size.y * 0.6)), cols[(i + int(p.x) + int(p.y)) % 4])
		"rack":
			ci.draw_rect(r.grow(-s * 0.15), Color("#4a321f"))
			if detail:
				for i in 3:
					var lx := r.position.x + s * (0.3 + i * 0.2)
					ci.draw_line(Vector2(lx, r.position.y + s * 0.2), Vector2(lx, r.end.y - s * 0.2), Color("#b8b8c0"), lw * 1.5)
		"bed":
			var q := r.grow(-s * 0.1)
			ci.draw_rect(q, Color("#4a321f"))
			ci.draw_rect(q.grow(-s * 0.05), Color("#6a5a8a") if (int(p.x) + int(p.y)) % 2 == 0 else Color("#7a3a3a"))
			var pil := Rect2(q.position + Vector2(s * 0.08, s * 0.08), Vector2(q.size.x - s * 0.16, s * 0.25)) if ph >= pw else Rect2(q.position + Vector2(s * 0.08, s * 0.08), Vector2(s * 0.25, q.size.y - s * 0.16))
			ci.draw_rect(pil, Color("#e8e0d0"))
		"hearth", "oven", "forge":
			var q := r.grow(-s * 0.08)
			ci.draw_rect(q, Color("#3a3438"))
			ci.draw_rect(q.grow(-s * 0.1), Color("#1a1214"))
			var fc := q.get_center() + Vector2(0, s * 0.06)
			ci.draw_circle(fc, s * 0.2 * (1.4 if str(p.k) == "forge" else 1.0), Color("#c0401a"))
			ci.draw_circle(fc, s * 0.12 * (1.4 if str(p.k) == "forge" else 1.0), Color("#ffb040"))
			ci.draw_circle(fc, s * 0.05, Color("#fff0a0"))
		"anvil":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-0.32, -0.12) * s, c + Vector2(0.32, -0.12) * s, c + Vector2(0.18, 0.04) * s, c + Vector2(0.14, 0.2) * s, c + Vector2(-0.14, 0.2) * s, c + Vector2(-0.18, 0.04) * s]), Color("#2a2a30"))
			ci.draw_line(c + Vector2(-0.3, -0.11) * s, c + Vector2(0.3, -0.11) * s, Color("#8a8a96"), lw)
		"altar":
			ci.draw_rect(r.grow(-s * 0.12), Color("#d8d2c4"))
			ci.draw_rect(r.grow(-s * 0.12), Color("#8a8478"), false, lw)
			if detail:
				ci.draw_circle(r.position + Vector2(s * 0.3, s * 0.3), s * 0.06, Color("#ffd27a"))
				ci.draw_circle(r.end - Vector2(s * 0.3, s * 0.3), s * 0.06, Color("#ffd27a"))
		"pew":
			ci.draw_rect(r.grow(-s * 0.22), Color("#5a3a22"))
			ci.draw_rect(Rect2(r.position + Vector2(s * 0.18, s * 0.18), Vector2(r.size.x - s * 0.36, s * 0.1)), Color("#3a2414"))
		"stage":
			ci.draw_rect(r.grow(-s * 0.04), Color("#8a6238"))
			if detail:
				for i in range(1, int(r.size.y / s * 3)):
					ci.draw_line(r.position + Vector2(s * 0.04, i * s / 3.0), r.position + Vector2(r.size.x - s * 0.04, i * s / 3.0), Color("#6a4628"), lw)
			ci.draw_rect(r.grow(-s * 0.04), Color("#c9a14a"), false, lw)
		"stairs":
			ci.draw_rect(r.grow(-s * 0.06), Color("#5a4632"))
			var steps := 6
			var vert := ph >= pw
			for i in steps:
				var f := float(i) / steps
				if vert:
					ci.draw_line(r.position + Vector2(s * 0.06, r.size.y * f + s * 0.06), r.position + Vector2(r.size.x - s * 0.06, r.size.y * f + s * 0.06), Color("#2e2216"), lw)
				else:
					ci.draw_line(r.position + Vector2(r.size.x * f + s * 0.06, s * 0.06), r.position + Vector2(r.size.x * f + s * 0.06, r.size.y - s * 0.06), Color("#2e2216"), lw)
		"trapdoor":
			ci.draw_rect(r.grow(-s * 0.18), Color("#5a3a22"))
			ci.draw_rect(r.grow(-s * 0.18), Color("#2a1a0e"), false, lw)
			ci.draw_arc(c, s * 0.08, 0, TAU, 10, Color("#a0a0a8"), lw)
		"tree":
			var rad := s * 0.46 * pw
			ci.draw_circle(c + Vector2(s * 0.06, s * 0.08), rad, Color(0, 0, 0, 0.3))
			ci.draw_circle(c, rad, Color("#1f3a1c"))
			ci.draw_circle(c + Vector2(-rad * 0.25, -rad * 0.2), rad * 0.62, Color("#2f5a2a"))
			ci.draw_circle(c + Vector2(rad * 0.28, rad * 0.1), rad * 0.5, Color("#3a6a32"))
			if detail:
				ci.draw_circle(c + Vector2(-rad * 0.3, -rad * 0.3), rad * 0.22, Color("#4f7d40"))
		"plant", "flowers":
			ci.draw_circle(c, s * 0.18, Color("#2f5a2a"))
			ci.draw_circle(c + Vector2(-s * 0.08, -s * 0.05), s * 0.1, Color("#4f8a40"))
			if str(p.k) == "flowers":
				for i in 4:
					ci.draw_circle(c + Vector2(cos(i * 1.7), sin(i * 1.7)) * s * 0.16, s * 0.05, [Color("#e85a8a"), Color("#f0d050"), Color("#a070e0"), Color("#ffffff")][i])
		"well":
			ci.draw_circle(c, s * 0.42, STONE_DARK)
			ci.draw_circle(c, s * 0.34, STONE)
			ci.draw_circle(c, s * 0.22, Color("#12263a"))
			ci.draw_line(c + Vector2(-s * 0.42, 0), c + Vector2(s * 0.42, 0), WOOD_DARK, lw * 2)
		"fountain":
			ci.draw_circle(c, s * 0.95, STONE_DARK)
			ci.draw_circle(c, s * 0.85, Color("#2a5a80"))
			ci.draw_circle(c, s * 0.3, STONE)
			ci.draw_circle(c, s * 0.12, Color("#9ad0ff"))
		"statue":
			ci.draw_rect(r.grow(-s * 0.08), STONE_DARK)
			ci.draw_circle(c, s * 0.26, STONE)
			ci.draw_circle(c + Vector2(0, -s * 0.06), s * 0.12, STONE.lightened(0.2))
		"stall":
			var q := r.grow(-s * 0.08)
			ci.draw_rect(q, Color("#d8d0c0"))
			var n := int(q.size.x / (s * 0.25))
			for i in n:
				if i % 2 == 0:
					ci.draw_rect(Rect2(q.position + Vector2(i * s * 0.25, 0), Vector2(s * 0.25, q.size.y)), Color("#b03a3a") if (int(p.x) / 3) % 2 == 0 else Color("#3a6ab0"))
			ci.draw_rect(q, Color("#5a4632"), false, lw)
		"tent":
			var q := r.grow(-s * 0.08)
			ci.draw_rect(q, Color("#8a7a58"))
			ci.draw_colored_polygon(PackedVector2Array([q.position, Vector2(q.end.x, q.position.y), Vector2(q.get_center().x, q.get_center().y)]), Color("#9c8b66"))
			ci.draw_colored_polygon(PackedVector2Array([Vector2(q.position.x, q.end.y), q.end, Vector2(q.get_center().x, q.get_center().y)]), Color("#6e6046"))
			ci.draw_line(Vector2(q.position.x, q.get_center().y), Vector2(q.end.x, q.get_center().y), Color("#4a3e2a"), lw * 1.5)
		"fire", "firepit":
			var k := float(pw)
			for i in 7:
				var ang := TAU * i / 7.0
				ci.draw_circle(c + Vector2(cos(ang), sin(ang)) * s * 0.3 * k, s * 0.08 * k, STONE_DARK)
			ci.draw_circle(c, s * 0.22 * k, Color("#c0401a"))
			ci.draw_circle(c, s * 0.13 * k, Color("#ffb040"))
			ci.draw_circle(c, s * 0.05 * k, Color("#fff0a0"))
		"brazier", "lamp":
			if str(p.k) == "brazier":
				ci.draw_circle(c, s * 0.2, Color("#2a2a30"))
				ci.draw_circle(c, s * 0.13, Color("#ff8a30"))
			else:
				ci.draw_circle(c, s * 0.3, Color(1, 0.85, 0.5, 0.12))
				ci.draw_circle(c, s * 0.1, Color("#2a2a30"))
				ci.draw_circle(c, s * 0.06, Color("#ffe08a"))
		"bedroll":
			ci.draw_rect(Rect2(r.position + Vector2(s * 0.3, s * 0.12), Vector2(s * 0.4, s * 0.76)), Color("#5a6a4a"))
			ci.draw_rect(Rect2(r.position + Vector2(s * 0.3, s * 0.12), Vector2(s * 0.4, s * 0.18)), Color("#c8c0a8"))
		"stone":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-0.22, 0.3) * s, c + Vector2(-0.28, -0.1) * s, c + Vector2(-0.08, -0.36) * s, c + Vector2(0.2, -0.3) * s, c + Vector2(0.28, 0.05) * s, c + Vector2(0.2, 0.32) * s]), STONE_DARK)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-0.16, 0.2) * s, c + Vector2(-0.2, -0.08) * s, c + Vector2(-0.05, -0.27) * s, c + Vector2(0.14, -0.22) * s, c + Vector2(0.18, 0.04) * s]), STONE)
		"pillar":
			ci.draw_circle(c, s * 0.36, STONE_DARK)
			ci.draw_circle(c, s * 0.3, STONE)
		"sarcophagus":
			ci.draw_rect(r.grow(-s * 0.14), STONE_DARK)
			ci.draw_rect(r.grow(-s * 0.2), Color("#a8a29a"))
			if detail:
				ci.draw_line(Vector2(c.x, r.position.y + s * 0.25), Vector2(c.x, r.end.y - s * 0.25), STONE_DARK, lw)
				ci.draw_line(c + Vector2(-s * 0.15, -s * 0.2), c + Vector2(s * 0.15, -s * 0.2), STONE_DARK, lw)
		"urn":
			ci.draw_circle(c, s * 0.18, Color("#6a5a4a"))
			ci.draw_circle(c, s * 0.1, Color("#2a2220"))
		"hay":
			ci.draw_circle(c, s * 0.34, Color("#8a7430"))
			ci.draw_circle(c + Vector2(-s * 0.05, -s * 0.05), s * 0.26, Color("#c8a850"))
		"trough":
			ci.draw_rect(r.grow(-s * 0.2), WOOD_DARK)
			ci.draw_rect(r.grow(-s * 0.28), Color("#2a5a80"))
		"cauldron":
			ci.draw_circle(c, s * 0.32, Color("#1a1a1e"))
			ci.draw_circle(c, s * 0.24, Color("#4aa050"))
			ci.draw_circle(c + Vector2(s * 0.06, -s * 0.04), s * 0.05, Color("#9ae09a"))
		"cart":
			ci.draw_rect(Rect2(r.position + Vector2(s * 0.14, s * 0.2), Vector2(s * 0.72, s * 0.5)), WOOD)
			ci.draw_rect(Rect2(r.position + Vector2(s * 0.14, s * 0.2), Vector2(s * 0.72, s * 0.5)), WOOD_DARK, false, lw)
			ci.draw_circle(r.position + Vector2(s * 0.28, s * 0.76), s * 0.1, WOOD_DARK)
			ci.draw_circle(r.position + Vector2(s * 0.72, s * 0.76), s * 0.1, WOOD_DARK)
		"trophy":
			ci.draw_circle(c, s * 0.2, Color("#6a4a2a"))
			ci.draw_line(c + Vector2(-s * 0.12, -s * 0.1), c + Vector2(-s * 0.32, -s * 0.32), Color("#d8c8a0"), lw * 1.5)
			ci.draw_line(c + Vector2(s * 0.12, -s * 0.1), c + Vector2(s * 0.32, -s * 0.32), Color("#d8c8a0"), lw * 1.5)
		"dartboard":
			ci.draw_circle(c, s * 0.28, Color("#1a1a1a"))
			ci.draw_circle(c, s * 0.2, Color("#d8c8a0"))
			ci.draw_circle(c, s * 0.1, Color("#a03030"))
			ci.draw_circle(c, s * 0.04, Color("#1a1a1a"))
		"shrine":
			ci.draw_rect(r.grow(-s * 0.25), Color("#c9a14a"))
			ci.draw_circle(c, s * 0.06, Color("#fff0a0"))
		"banner":
			ci.draw_rect(Rect2(r.position + Vector2(s * 0.3, s * 0.1), Vector2(s * 0.4, s * 0.7)), Color("#7a2630"))
			ci.draw_circle(c, s * 0.08, Color("#c9a14a"))
		"ring":
			ci.draw_rect(r.grow(-s * 0.15), Color("#c8a870"), false, lw * 2)
			for q in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
				ci.draw_circle(q + (c - q).normalized() * s * 0.2, s * 0.07, WOOD_DARK)
		"rubble":
			for i in 4:
				ci.draw_circle(r.position + Vector2(0.25 + (i % 2) * 0.45, 0.3 + (i / 2) * 0.4) * s, s * (0.1 + 0.03 * (i % 3)), STONE_DARK.lightened(0.1 * (i % 2)))
		"gatepost":
			ci.draw_circle(c, s * 0.38, Color("#3e2c1a"))
			ci.draw_circle(c, s * 0.3, Color("#6a4c2c"))
		"dummy":
			ci.draw_line(c + Vector2(0, -s * 0.3), c + Vector2(0, s * 0.3), WOOD_DARK, lw * 2)
			ci.draw_line(c + Vector2(-s * 0.25, -s * 0.1), c + Vector2(s * 0.25, -s * 0.1), WOOD_DARK, lw * 2)
			ci.draw_circle(c + Vector2(0, -s * 0.3), s * 0.12, Color("#c8b080"))

# ---------------------------------------------------------------- labels

static func draw_labels(ci: CanvasItem, labels: Array, off: Vector2, cs: float, shown: Callable = Callable()) -> void:
	var font := ThemeDB.fallback_font
	var fs := clampi(int(cs * 0.3), 9, 20)
	for l in labels:
		var at := off + Vector2(float(l.x), float(l.y)) * cs
		if shown.is_valid() and not shown.call(Vector2i(floori(float(l.x)), floori(float(l.y)))):
			continue
		var text := str(l.text)
		var kind := str(l.get("kind", ""))
		var size := fs + (4 if kind == "town" else (2 if kind == "tavern" else 0))
		var col := Color("#ffd27a") if kind in ["tavern", "town"] else Color("#ece6d8")
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var pos := at + Vector2(-tw * 0.5, size * 0.35)
		ci.draw_rect(Rect2(pos + Vector2(-5, -size * 0.95), Vector2(tw + 10, size * 1.3)), Color(0.05, 0.04, 0.07, 0.72))
		ci.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, maxi(2, size / 5), Color(0, 0, 0, 0.85))
		ci.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
