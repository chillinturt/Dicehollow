extends RefCounted
## Combat visual effects. Everything is drawn in code (lines, arcs, circles, CPU particles), with no textures.
## Effects are chosen by "style", which is the same name the Sfx autoload uses ("sword", "bow", "fire"...),
## so every effect the engine already gives a sound also gets a matching look.
##
##   Vfx.melee(fx_root, from_px, to_px, "sword", Color.WHITE)
##   var travel = Vfx.projectile(fx_root, from_px, to_px, "bow", Color.WHITE)   # seconds until impact
##   Vfx.area(fx_root, center_px, cells, Color("#ff7a2a"), "fire")
##   Vfx.hit(fx_root, token_center, Color.ORANGE, crit)

const CELL := 64
const MAGIC := ["fire", "cold", "lightning", "thunder", "acid", "poison", "necrotic", "radiant", "psychic", "force"]
const MELEE_STYLES := ["sword", "blunt", "claw", "bite", "punch"]
const PHYSICAL_PROJECTILES := ["bow", "crossbow", "throw"]
const TYPE_COLORS := {"fire": "#ff7a2a", "cold": "#9fe6ff", "lightning": "#fff07a", "acid": "#9aff5a", "poison": "#6ad04a",
	"necrotic": "#8a4ac0", "radiant": "#fff2a8", "thunder": "#7aa8ff", "psychic": "#ff7ae0", "force": "#c8a0ff",
	"heal": "#7fdc7f", "teleport": "#b38cff", "rage": "#ff4040"}

## A short-lived node that redraws itself every frame with fn(node, k), k going 0 -> 1 over dur seconds.
class Fx extends Node2D:
	var dur := 0.4
	var t := 0.0
	var fn: Callable

	func _process(delta: float) -> void:
		t += delta
		if t >= dur:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		fn.call(self, clampf(t / dur, 0.0, 1.0))

static func _fx(root: Node, pos: Vector2, dur: float, fn: Callable, z := 45) -> Fx:
	var f = Fx.new()
	f.position = pos
	f.dur = dur
	f.fn = fn
	f.z_index = z
	root.add_child(f)
	return f

## The colour for a style, or fallback when the style has none (weapons).
static func color_for(style: String, fallback: Color) -> Color:
	return Color(TYPE_COLORS[style]) if TYPE_COLORS.has(style) else fallback

static func _ease_out(k: float) -> float:
	return 1.0 - pow(1.0 - k, 3.0)

# ================================================================ particles

## One burst of square particles. opts: life, size, gravity, spread, dir, damping, radius, explosive.
static func particles(root: Node, pos: Vector2, col: Color, amount := 14, speed := 120.0, opts := {}) -> void:
	var p = CPUParticles2D.new()
	p.position = pos
	p.z_index = 46
	p.one_shot = true
	p.amount = maxi(1, amount)
	p.lifetime = float(opts.get("life", 0.6))
	p.explosiveness = float(opts.get("explosive", 0.9))
	p.direction = opts.get("dir", Vector2.UP)
	p.spread = float(opts.get("spread", 180.0))
	p.gravity = opts.get("gravity", Vector2.ZERO)
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.damping_min = float(opts.get("damping", 0.0))
	p.damping_max = float(opts.get("damping", 0.0))
	var sz = float(opts.get("size", 3.0))
	p.scale_amount_min = sz * 0.6
	p.scale_amount_max = sz
	if opts.has("radius"):
		p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = float(opts.radius)
	var g = Gradient.new()
	g.set_color(0, col.lightened(0.25))
	g.set_color(1, Color(col, 0.0))
	p.color_ramp = g
	root.add_child(p)
	p.emitting = true
	root.get_tree().create_timer(p.lifetime + 0.3).timeout.connect(p.queue_free)

## Particle motion that suits each damage type.
static func _style_opts(style: String) -> Dictionary:
	match style:
		"fire", "rage":
			return {"gravity": Vector2(0, -170), "speed": 70.0, "life": 0.8, "size": 4.0}
		"cold":
			return {"gravity": Vector2(0, 70), "speed": 120.0, "life": 0.7, "size": 3.0}
		"poison", "acid":
			return {"gravity": Vector2(0, -25), "speed": 35.0, "life": 1.0, "size": 7.0, "damping": 20.0}
		"radiant", "heal", "buff":
			return {"gravity": Vector2(0, -90), "speed": 40.0, "life": 0.9, "size": 3.0}
		"necrotic":
			return {"gravity": Vector2(0, 90), "speed": 55.0, "life": 0.8, "size": 4.0}
		"lightning":
			return {"speed": 240.0, "life": 0.25, "size": 2.0}
		"thunder", "force":
			return {"speed": 180.0, "life": 0.4, "size": 3.0, "damping": 120.0}
		"psychic":
			return {"speed": 60.0, "life": 0.7, "size": 3.0, "gravity": Vector2(0, -40)}
		_:
			return {"speed": 120.0, "life": 0.45, "size": 3.0}

static func _style_particles(root: Node, pos: Vector2, col: Color, style: String, amount: int, radius := 0.0) -> void:
	var o = _style_opts(style)
	if radius > 0.0:
		o.radius = radius
	particles(root, pos, col, amount, float(o.get("speed", 120.0)), o)

# ================================================================ melee

## A melee swing drawn over the target. Style picks the shape: sword arc, claw rake, bite, or impact.
static func melee(root: Node, from: Vector2, to: Vector2, style: String, col: Color) -> void:
	var dir = (to - from).normalized() if to != from else Vector2.RIGHT
	var ang = dir.angle()
	if col == Color.WHITE:
		col = Color(0.85, 0.93, 1.0)
	match style:
		"claw":
			var sd = dir.rotated(0.7)
			var side = sd.orthogonal()
			_fx(root, to, 0.32, func(n, k):
				var grow = minf(1.0, k * 2.5)
				var a = 1.0 - maxf(0.0, k - 0.35) / 0.65
				for i in 3:
					var p0 = side * (i - 1) * 10.0 - sd * 22.0 + sd * (absf(i - 1) * 4.0)
					var p1 = p0 + sd * 44.0 * grow
					n.draw_line(p0, p1, Color(1.0, 0.25, 0.2, 0.55 * a), 7.0)
					n.draw_line(p0, p1, Color(1, 1, 1, a), 2.0))
			particles(root, to, Color(0.8, 0.1, 0.1), 8, 90.0, {"life": 0.4, "dir": dir, "spread": 50.0})
		"bite":
			_fx(root, to, 0.32, func(n, k):
				var gap = lerpf(24.0, 4.0, minf(1.0, k * 2.2))
				var a = 1.0 - maxf(0.0, k - 0.5) * 2.0
				var c = Color(1, 1, 1, a)
				n.draw_arc(Vector2(0, -gap + 16), 20, PI * 1.15, PI * 1.85, 12, c, 3.0)
				n.draw_arc(Vector2(0, gap - 16), 20, PI * 0.15, PI * 0.85, 12, c, 3.0)
				for i in 4:
					var x = -12.0 + i * 8.0
					n.draw_line(Vector2(x, -gap - 2), Vector2(x + 2, -gap + 6), c, 2.5)
					n.draw_line(Vector2(x, gap + 2), Vector2(x + 2, gap - 6), c, 2.5))
			particles(root, to, Color(0.8, 0.1, 0.1), 8, 80.0, {"life": 0.4})
		"punch", "blunt":
			var heavy = style == "blunt"
			var rot = randf() * TAU
			_fx(root, to, 0.3, func(n, k):
				var e = _ease_out(k)
				var a = 1.0 - k
				n.draw_arc(Vector2.ZERO, 6.0 + (32.0 if heavy else 24.0) * e, 0, TAU, 28, Color(col, a), 5.0 * (1.0 - k) + 1.0)
				for i in 6:
					var d = Vector2.RIGHT.rotated(rot + i * TAU / 6.0)
					n.draw_line(d * (10.0 + 18.0 * e), d * (18.0 + 24.0 * e), Color(1, 0.9, 0.6, a), 3.0))
			particles(root, to, Color(0.75, 0.7, 0.6), 10, 110.0, {"life": 0.35})
		_:
			# Sword (or any blade, or a spell-charged touch): a crescent that sweeps across the target.
			var c = to - dir * 34.0
			_fx(root, c, 0.28, func(n, k):
				var head = lerpf(-1.25, 1.25, _ease_out(minf(1.0, k * 1.4)))
				var tail = maxf(-1.25, head - 1.7)
				var a = 1.0 - k * k
				n.draw_arc(Vector2.ZERO, 38, ang + tail, ang + head, 18, Color(col, 0.3 * a), 16.0)
				n.draw_arc(Vector2.ZERO, 38, ang + lerpf(tail, head, 0.35), ang + head, 14, Color(col, 0.75 * a), 7.0)
				n.draw_arc(Vector2.ZERO, 38, ang + lerpf(tail, head, 0.65), ang + head, 8, Color(1, 1, 1, a), 2.5))
			if style in MAGIC:
				_style_particles(root, to, col, style, 12)

# ================================================================ projectiles

## A projectile from -> to. Returns its travel time, so callers can hold the damage number until it lands.
static func projectile(root: Node, from: Vector2, to: Vector2, style: String, col: Color) -> float:
	var dist = from.distance_to(to)
	var dir = (to - from).normalized() if to != from else Vector2.RIGHT
	var perp = dir.orthogonal()
	if style == "lightning":
		_fx(root, Vector2.ZERO, 0.3, func(n, k):
			var rng = RandomNumberGenerator.new()
			rng.seed = int(k * 9.0) + 1
			var segs = maxi(4, int(dist / 22.0))
			var pts = PackedVector2Array()
			for i in segs + 1:
				var q = from.lerp(to, float(i) / segs)
				if i > 0 and i < segs:
					q += perp * rng.randf_range(-13.0, 13.0)
				pts.append(q)
			var a = (1.0 - k * k) * (0.45 if int(k * 12.0) % 3 == 1 else 1.0)
			n.draw_polyline(pts, Color(col, 0.35 * a), 8.0)
			n.draw_polyline(pts, Color(1, 1, 1, a), 2.5))
		impact(root, to, style, col)
		return 0.12
	var speed = {"bow": 1500.0, "crossbow": 2000.0, "throw": 950.0}.get(style, 1000.0)
	var travel = clampf(dist / speed, 0.08, 0.5)
	match style:
		"bow", "crossbow":
			var L = 24.0 if style == "bow" else 16.0
			_fx(root, Vector2.ZERO, travel, func(n, k):
				var p = from.lerp(to, k)
				var tail = p - dir * L
				var trail_start = p - dir * minf(dist * k, 90.0)
				n.draw_line(trail_start, tail, Color(1, 1, 1, 0.18), 2.0)
				n.draw_line(tail, p, Color("#c89a64"), 2.5)
				n.draw_colored_polygon(PackedVector2Array([p + dir * 6.0, p - dir * 2.0 + perp * 4.0, p - dir * 2.0 - perp * 4.0]), Color("#d8dde4"))
				n.draw_line(tail, tail - dir * 6.0 + perp * 4.0, Color.WHITE, 2.0)
				n.draw_line(tail, tail - dir * 6.0 - perp * 4.0, Color.WHITE, 2.0))
		"throw":
			var h = minf(dist * 0.2, 40.0)
			_fx(root, Vector2.ZERO, travel, func(n, k):
				var p = from.lerp(to, k) + Vector2(0, -sin(k * PI) * h)
				var r = Vector2.RIGHT.rotated(k * TAU * 3.0)
				n.draw_line(p - r * 7.0, p + r * 7.0, Color("#cfd4da"), 3.5)
				n.draw_circle(p, 2.5, Color.WHITE))
		_:
			# Spell bolt: a glowing orb with a fading tail.
			_fx(root, Vector2.ZERO, travel, func(n, k):
				for j in range(6, 0, -1):
					var kk = k - j * 0.035
					if kk < 0.0:
						continue
					n.draw_circle(from.lerp(to, kk), 7.0 - j * 0.8, Color(col, 0.5 * (1.0 - j / 6.0)))
				var p = from.lerp(to, k)
				n.draw_circle(p, 11.0, Color(col, 0.3))
				n.draw_circle(p, 6.5, col)
				n.draw_circle(p, 3.0, Color.WHITE))
	root.get_tree().create_timer(travel).timeout.connect(func():
		if is_instance_valid(root):
			impact(root, to, style, col))
	return travel

## The small splash where a projectile lands.
static func impact(root: Node, pos: Vector2, style: String, col: Color) -> void:
	if style in PHYSICAL_PROJECTILES:
		particles(root, pos, Color(0.85, 0.8, 0.7), 6, 80.0, {"life": 0.3, "size": 2.5})
		return
	_fx(root, pos, 0.3, func(n, k):
		n.draw_circle(Vector2.ZERO, 16.0 * (1.0 - k), Color(col, 0.6 * (1.0 - k)))
		n.draw_arc(Vector2.ZERO, 6.0 + 22.0 * _ease_out(k), 0, TAU, 24, Color(col, 1.0 - k), 3.0))
	_style_particles(root, pos, col, style, 12)

# ================================================================ areas & bursts

## An area spell or breath: tinted cells flash in and fade, a shockwave rolls out, and themed particles rise.
static func area(root: Node, center: Vector2, cells: Array, col: Color, style: String) -> void:
	var rects: Array = []
	var far := 0.0
	for p in cells:
		var r = Rect2(Vector2(p) * CELL, Vector2(CELL, CELL))
		rects.append(r)
		far = maxf(far, r.get_center().distance_to(center))
	var flash = style == "lightning" or style == "radiant" or style == "thunder"
	_fx(root, Vector2.ZERO, 0.75, func(n, k):
		var a = (k / 0.12) if k < 0.12 else 1.0 - (k - 0.12) / 0.88
		var fill = Color(col, 0.5 * a)
		if flash and k < 0.12:
			fill = Color(1, 1, 1, 0.6).lerp(fill, k / 0.12)
		for r in rects:
			n.draw_rect(r.grow(-2), fill)
			n.draw_rect(r.grow(-2), Color(col.lightened(0.3), 0.5 * a), false, 1.5)
		var ring_r = 10.0 + (far + CELL * 0.5) * _ease_out(minf(1.0, k * 1.6))
		n.draw_arc(center, ring_r, 0, TAU, 48, Color(col.lightened(0.4), 0.9 * (1.0 - k)), 4.0)
		if style == "thunder":
			n.draw_arc(center, ring_r * 0.7, 0, TAU, 40, Color(1, 1, 1, 0.6 * (1.0 - k)), 2.5), 39)
	# Particles over a sample of the cells, so a big area doesn't spawn hundreds of emitters.
	var picks: Array = rects.duplicate()
	picks.shuffle()
	var per = 6 if rects.size() > 8 else 10
	for i in mini(picks.size(), 10):
		_style_particles(root, picks[i].get_center(), col, style, per, CELL * 0.35)

## A burst on one creature: buffs, heals, smites, teleports, rage.
static func burst(root: Node, pos: Vector2, col: Color, style: String) -> void:
	match style:
		"heal":
			_fx(root, pos, 0.9, func(n, k):
				var a = 1.0 - k
				for i in 3:
					var p = Vector2(-16.0 + i * 16.0, 10.0 - 40.0 * k - (i % 2) * 10.0)
					n.draw_line(p - Vector2(5, 0), p + Vector2(5, 0), Color(col, a), 3.0)
					n.draw_line(p - Vector2(0, 5), p + Vector2(0, 5), Color(col, a), 3.0)
				n.draw_arc(Vector2.ZERO, 30.0, 0, TAU, 32, Color(col, 0.5 * a), 3.0))
			_style_particles(root, pos, col, "heal", 16, 22.0)
		"teleport":
			_fx(root, pos, 0.35, func(n, k):
				n.draw_arc(Vector2.ZERO, 44.0 * (1.0 - k) + 2.0, 0, TAU, 32, Color(col, 1.0 - k * 0.5), 3.0)
				n.draw_circle(Vector2.ZERO, 10.0 * k, Color(1, 1, 1, 1.0 - k)))
			particles(root, pos, col, 14, 70.0, {"life": 0.5, "radius": 26.0})
		_:
			_fx(root, pos, 0.45, func(n, k):
				var e = _ease_out(k)
				n.draw_circle(Vector2.ZERO, 26.0 * (1.0 - k), Color(col, 0.35 * (1.0 - k)))
				n.draw_arc(Vector2.ZERO, 8.0 + 34.0 * e, 0, TAU, 32, Color(col, 1.0 - k), 4.0))
			_style_particles(root, pos, col, style, 14, 18.0)

## A glowing rune circle under a caster.
static func cast_circle(root: Node, pos: Vector2, col: Color) -> void:
	_fx(root, pos, 0.6, func(n, k):
		var a = (k / 0.2) if k < 0.2 else 1.0 - (k - 0.2) / 0.8
		var spin = k * 2.5
		var r = 30.0 + 6.0 * k
		n.draw_arc(Vector2.ZERO, r, 0, TAU, 40, Color(col, 0.8 * a), 2.5)
		n.draw_arc(Vector2.ZERO, r - 7.0, 0, TAU, 40, Color(col, 0.5 * a), 1.5)
		var pts = PackedVector2Array()
		for i in 6:
			pts.append(Vector2.RIGHT.rotated(spin + i * TAU * 2.0 / 5.0) * (r - 7.0))
		n.draw_polyline(pts, Color(col.lightened(0.3), 0.7 * a), 1.5)
		for i in 5:
			n.draw_circle(Vector2.RIGHT.rotated(-spin + i * TAU / 5.0) * r, 3.0, Color(1, 1, 1, a)), 38)
	particles(root, pos, col, 10, 30.0, {"gravity": Vector2(0, -70), "life": 0.8, "radius": 26.0, "explosive": 0.4})

# ================================================================ hits

## A spark where a hit lands. Crits are larger and gold.
static func hit(root: Node, pos: Vector2, col: Color, crit := false) -> void:
	var s = 1.6 if crit else 1.0
	var rot = randf() * TAU
	_fx(root, pos, 0.24 * s, func(n, k):
		var e = _ease_out(k)
		var a = 1.0 - k
		for i in 8:
			var d = Vector2.RIGHT.rotated(rot + i * TAU / 8.0)
			var r0 = (6.0 + 14.0 * e) * s
			var r1 = r0 + (16.0 - 10.0 * k) * s * (1.0 if i % 2 == 0 else 0.6)
			n.draw_line(d * r0, d * r1, Color(col, a), 3.0 * s)
		n.draw_circle(Vector2.ZERO, 11.0 * (1.0 - k) * s, Color(1, 1, 1, 0.9 * a)), 47)
	particles(root, pos, col, 22 if crit else 10, 170.0 * s, {"life": 0.35, "size": 3.0})

## A creature drops or dies.
static func death(root: Node, pos: Vector2) -> void:
	_fx(root, pos, 0.6, func(n, k):
		var e = _ease_out(k)
		n.draw_circle(Vector2.ZERO, 30.0 * (1.0 - k), Color(0.1, 0.0, 0.0, 0.5 * (1.0 - k)))
		n.draw_arc(Vector2.ZERO, 10.0 + 40.0 * e, 0, TAU, 36, Color(1, 0.25, 0.2, 1.0 - k), 3.0))
	particles(root, pos, Color(0.35, 0.3, 0.3), 18, 90.0, {"gravity": Vector2(0, 120), "life": 0.7, "size": 4.0})
