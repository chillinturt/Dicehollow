class_name DiceTray
extends Control
## Animated dice for the rolls the engine reports ("dice" events, see EngineBase.dice_event).
## Everything is drawn in code. Each card shows who rolled and what for, the dice tumbling and then
## settling on their faces, the bonus and total, and the result (HIT, MISS, SUCCESS...).
##
## Whether to show it is a local setting, so every player picks their own: "off", "mine" (rolls by or
## against the creatures you control) or "all". It is saved in user://settings.cfg.
##
##   tray.add_roll(event, "Aria", Color("#8fd0ff"))

signal mode_changed

const SETTINGS := "user://settings.cfg"
const MODES := ["off", "mine", "all"]
const MODE_NAMES := {"off": "Off", "mine": "Mine", "all": "All"}
const ROLL_TIME := 0.55   # tumbling
const LIFE_D20 := 2.6     # on screen in all, before fading
const LIFE_DAMAGE := 2.0
const FADE := 0.4
const MAX_CARDS := 3
const MAX_DICE := 6       # dice drawn per card; more show as "+N"
const CARD_W := 330.0
const CARD_H := 60.0
const DIE := 30.0
const RESULT_COLORS := {"HIT": "#7fdc7f", "CRIT": "#ffd166", "MISS": "#aaaaaa", "SUCCESS": "#7fdc7f", "FAIL": "#ff7f7f"}

static var _mode := ""

var cards: Array = []  # {e, who, color, t, life, seed}

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)

# ================================================================ setting

static func mode() -> String:
	if _mode == "":
		_mode = "mine"
		var cfg = ConfigFile.new()
		if cfg.load(SETTINGS) == OK:
			var m = str(cfg.get_value("dice", "show", "mine"))
			_mode = m if m in MODES else "mine"
	return _mode

static func set_mode(m: String) -> void:
	_mode = m if m in MODES else "mine"
	var cfg = ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("dice", "show", _mode)
	cfg.save(SETTINGS)

## The next setting after the current one (Off -> My rolls -> All rolls -> Off).
static func next_mode() -> String:
	return MODES[(MODES.find(mode()) + 1) % MODES.size()]

## Whether this screen shows a roll. mine: the roll is by or against one of the viewer's creatures.
static func wants(mine: bool) -> bool:
	match mode():
		"all": return true
		"mine": return mine
	return false

# ================================================================ cards

## e: a "dice" event. who: the roller's name; color: its side's colour.
func add_roll(e: Dictionary, who: String, color: Color) -> void:
	var life: float = LIFE_DAMAGE if str(e.get("kind", "d20")) == "damage" else LIFE_D20
	cards.append({"e": e, "who": who, "color": color, "t": 0.0, "life": life, "seed": randi()})
	while cards.size() > MAX_CARDS:
		cards.pop_front()
	set_process(true)
	queue_redraw()

func clear() -> void:
	cards.clear()
	set_process(false)
	queue_redraw()

func _process(delta: float) -> void:
	for c in cards:
		c.t += delta
	cards = cards.filter(func(c): return c.t < c.life + FADE)
	if cards.is_empty():
		set_process(false)
	queue_redraw()

func _draw() -> void:
	var font := get_theme_default_font()
	# Newest card at the bottom left, older ones stacked above it.
	var y := size.y - CARD_H - 8.0
	for i in range(cards.size() - 1, -1, -1):
		var c: Dictionary = cards[i]
		var a := 1.0
		if c.t > c.life:
			a = 1.0 - (c.t - c.life) / FADE
		var slide := 1.0 - pow(1.0 - clampf(c.t / 0.18, 0.0, 1.0), 3.0)
		var pos := Vector2(4.0, y + (1.0 - slide) * 24.0)
		_draw_card(font, c, pos, clampf(a * slide, 0.0, 1.0))
		y -= CARD_H + 6.0

func _draw_card(font: Font, c: Dictionary, pos: Vector2, a: float) -> void:
	var e: Dictionary = c.e
	var rect := Rect2(pos, Vector2(CARD_W, CARD_H))
	draw_rect(rect, Color(0.07, 0.06, 0.1, 0.88 * a))
	draw_rect(rect, Color(c.color, 0.55 * a), false, 1.5)
	draw_rect(Rect2(pos, Vector2(4, CARD_H)), Color(c.color, a))
	# Header: who · what.
	var head := "%s · %s" % [c.who, str(e.get("label", ""))]
	draw_string(font, pos + Vector2(12, 16), head, HORIZONTAL_ALIGNMENT_LEFT, CARD_W - 100, 13, Color(0.85, 0.82, 0.9, a))
	var k := clampf(c.t / ROLL_TIME, 0.0, 1.0)
	var settled := k >= 1.0
	var dice: Array = e.get("dice", [])
	var shown := mini(dice.size(), MAX_DICE)
	var step := DIE + 6.0
	var rng := RandomNumberGenerator.new()
	for i in shown:
		var d: Dictionary = dice[i]
		rng.seed = int(c.seed) + i * 7919 + int(c.t / 0.06) * 31
		var spin := (1.0 - k) * (1.0 - k) * (TAU * 1.6 + i * 0.7) * (1.0 if i % 2 == 0 else -1.0)
		var hop := absf(sin(k * PI * 2.5)) * (1.0 - k) * 10.0
		var center := pos + Vector2(12 + DIE * 0.5 + i * step + (1.0 - k) * -18.0, 39 - hop)
		var face: int = int(d.v) if settled else rng.randi_range(1, maxi(2, int(d.s)))
		_draw_die(font, center, int(d.s), face, spin, d.get("off", false) and settled, settled, c.color, a, maxf(0.0, c.t - ROLL_TIME))
	if dice.size() > shown:
		draw_string(font, pos + Vector2(12 + shown * step, 44), "+%d" % (dice.size() - shown), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.8, 0.8, 0.85, a))
	if not settled:
		return
	# Bonus, total and result fade in once the dice land.
	var ta := a * clampf((c.t - ROLL_TIME) / 0.15, 0.0, 1.0)
	var right := pos.x + CARD_W - 12.0
	var res := str(e.get("result", ""))
	if res != "":
		var rc := Color(RESULT_COLORS.get(res, "#ffffff"))
		var pop := 1.0 + 0.35 * maxf(0.0, 1.0 - (c.t - ROLL_TIME) / 0.25)
		var fs := int(15 * pop)
		var w := font.get_string_size(res, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string_outline(font, Vector2(right - w, pos.y + 18), res, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, ta))
		draw_string(font, Vector2(right - w, pos.y + 18), res, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(rc, ta))
	var mod := int(e.get("mod", 0))
	var tot := "%s= %d" % [("%+d " % mod) if mod != 0 else "", int(e.get("total", 0))]
	var tw := font.get_string_size(tot, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	var ty := pos.y + 49.0
	draw_string_outline(font, Vector2(right - tw, ty), tot, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, 4, Color(0, 0, 0, ta))
	draw_string(font, Vector2(right - tw, ty), tot, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, ta))

## One die: a shape for its number of sides, the face value on top. off: a dropped roll (advantage).
func _draw_die(font: Font, center: Vector2, sides: int, face: int, angle: float, off: bool, settled: bool, tint: Color, a: float, since: float) -> void:
	var r := DIE * 0.5
	var body := Color("#2a2338").lerp(tint, 0.18)
	var edge := tint.lightened(0.2)
	var txt := Color.WHITE
	var crit := settled and not off and sides == 20 and (face == 20 or face == 1)
	if crit:
		edge = Color("#ffd166") if face == 20 else Color("#ff5a5a")
		# A brief glow when a natural 20 or 1 lands.
		var g := clampf(1.0 - since / 0.6, 0.0, 1.0)
		if g > 0.0:
			draw_circle(center, r * (1.2 + 0.5 * (1.0 - g)), Color(edge, 0.35 * g * a))
		txt = edge
	if off:
		a *= 0.35
	var pts := _shape(sides, r, angle)
	var poly := PackedVector2Array()
	for p in pts:
		poly.append(center + p)
	draw_colored_polygon(poly, Color(body, a))
	var outline := poly.duplicate()
	outline.append(poly[0])
	draw_polyline(outline, Color(edge, a), 2.0, true)
	# Facet lines so a d20 reads as a d20 (an inner triangle), a d10 as a kite.
	if sides == 20:
		var inner := PackedVector2Array()
		for j in 3:
			inner.append(center + Vector2.from_angle(angle - PI / 2 + j * TAU / 3) * r * 0.62)
		inner.append(inner[0])
		draw_polyline(inner, Color(edge, a * 0.45), 1.0, true)
	elif sides == 10:
		draw_line(poly[1], poly[3], Color(edge, a * 0.35), 1.0, true)
	var s := str(face)
	var fs := 15 if s.length() < 3 else 12
	var sz := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var tp := center + Vector2(-sz.x * 0.5, sz.y * 0.32 + (r * 0.12 if sides == 4 else 0.0))
	draw_string_outline(font, tp, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, a))
	draw_string(font, tp, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(txt, a))
	if off:
		draw_line(center + Vector2(-r * 0.7, r * 0.7), center + Vector2(r * 0.7, -r * 0.7), Color(1, 0.4, 0.4, a * 2.0), 2.0)

## Outline points for a die with `sides` faces, radius r, rotated by angle.
static func _shape(sides: int, r: float, angle: float) -> Array:
	var n := 6
	var start := -PI / 2
	var radii: Array = []
	match sides:
		4: n = 3
		6: n = 4; start = -PI / 4
		8: n = 4
		10: n = 4; radii = [1.0, 0.78, 0.6, 0.78]
		12: n = 5
		20: n = 6; start = 0.0
		_: n = 16  # d100 and odd dice: round
	var out: Array = []
	for i in n:
		var rr: float = r * (float(radii[i]) if not radii.is_empty() else 1.0)
		out.append(Vector2.from_angle(start + angle + i * TAU / n) * rr * (1.12 if n == 3 else 1.0))
	return out
