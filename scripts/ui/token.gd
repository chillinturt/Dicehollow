extends Node2D
## A creature token: circular portrait (or monster icon, or initials), team ring, HP bar, condition badges, turn glow.

const CELL := 64
const MASK := preload("res://scripts/ui/circle_mask.gdshader")

var cid := ""
var data: Dictionary = {}
var is_current := false
var is_selected := false
var is_targetable := false
var sprite: Sprite2D
var _pulse := 0.0
var _flash := 0.0
var _flash_col := Color.WHITE
var _shake := 0.0
var _jitter := Vector2.ZERO
var _sprite_base := Vector2.ZERO

func _ready() -> void:
	sprite = Sprite2D.new()
	sprite.centered = true
	var mat = ShaderMaterial.new()
	mat.shader = MASK
	sprite.material = mat
	add_child(sprite)

func setup(c: Dictionary) -> void:
	data = c
	var sz: int = c.get("sz", 1)
	if not c.get("form", {}).is_empty():
		sz = int(c.form.get("sz", sz))
	var tex = CharacterStore.portrait_texture(c.get("portrait", ""))
	sprite.texture = tex
	if tex:
		var px = sz * CELL - 12
		sprite.scale = Vector2.ONE * (float(px) / tex.get_width())
		_sprite_base = Vector2(sz, sz) * CELL * 0.5
		sprite.position = _sprite_base + _jitter
	sprite.visible = tex != null and c.get("form", {}).is_empty()
	var down: bool = c.get("dead", false) or c.get("death", {}).get("dead", false) or (c.get("kind", "") == "pc" and int(c.hp) <= 0)
	(sprite.material as ShaderMaterial).set_shader_parameter("grey", 1.0 if down else 0.0)
	modulate.a = 0.45 if c.get("dead", false) else (0.55 if _has_cond("invisible") or c.get("hidden", false) else 1.0)
	# Up in a Rope Trick space: a half-size ghost above the rope (battle.gd fans them out).
	var roped: bool = _has_tag("rope_trick")
	scale = Vector2.ONE * (0.5 if roped else 1.0)
	if roped:
		modulate.a = minf(modulate.a, 0.5)
	visible = not _has_cond("banished")
	queue_redraw()

func _has_tag(tag: String) -> bool:
	for e in data.get("effects", []):
		if e.get("tag", "") == tag:
			return true
	return false

func _has_cond(cond: String) -> bool:
	for e in data.get("effects", []):
		if e.get("cond", "") == cond:
			return true
	return false

## Size in cells (wild shape forms can change it).
func cells() -> int:
	var sz: int = data.get("sz", 1)
	if not data.get("form", {}).is_empty():
		sz = int(data.form.get("sz", sz))
	return sz

## Centre of the token in map pixels.
func center() -> Vector2:
	return position + Vector2.ONE * cells() * CELL * 0.5 * scale.x

## Flash a colour over the token and shake it (strength ~1 for a hit, ~2 for a crit).
func hit_react(col: Color, strength := 1.0) -> void:
	_flash = 1.0
	_flash_col = col
	_shake = maxf(_shake, strength)

func _process(delta: float) -> void:
	if is_current or is_targetable:
		_pulse += delta * 4.0
		queue_redraw()
	if _flash > 0.0 or _shake > 0.0:
		_flash = maxf(0.0, _flash - delta * 4.0)
		_shake = maxf(0.0, _shake - delta * 5.0)
		_jitter = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 5.0 * _shake if _shake > 0.0 else Vector2.ZERO
		sprite.modulate = Color.WHITE.lerp(_flash_col, _flash)
		sprite.position = _sprite_base + _jitter
		queue_redraw()

func _draw() -> void:
	if data.is_empty():
		return
	draw_set_transform(_jitter)
	var sz := cells()
	var size = sz * CELL
	var c = Vector2(size, size) * 0.5
	var r = size * 0.5 - 5.0
	var team_col = Color("#4aa3ff") if data.get("team", "") == "party" else Color("#ff5a4a")
	var col = Color(data.get("color", "#777777"))
	# Shadow.
	draw_circle(c + Vector2(3, 5), r + 2, Color(0, 0, 0, 0.45))
	if is_current:
		var g = 0.5 + 0.5 * sin(_pulse)
		draw_circle(c, r + 7 + g * 2, Color(1, 0.85, 0.35, 0.25 + 0.2 * g))
	if is_targetable:
		var g2 = 0.5 + 0.5 * sin(_pulse * 1.5)
		draw_arc(c, r + 6, 0, TAU, 48, Color(1, 0.3, 0.25, 0.6 + 0.4 * g2), 3)
	if not sprite.visible:
		draw_circle(c, r, col.darkened(0.35))
		draw_circle(c, r - 4, col)
		var icon = MonsterIcons.for_combatant(data)
		if icon:
			var half = r * 0.78
			# Dark offset copy so white icons still read on pale tokens (skeletons, ghosts).
			draw_texture_rect(icon, Rect2(c - Vector2(half, half) + Vector2(1.5, 2), Vector2(half, half) * 2.0), false, Color(0, 0, 0, 0.45))
			draw_texture_rect(icon, Rect2(c - Vector2(half, half), Vector2(half, half) * 2.0), false, Color(1, 1, 1, 0.95))
		else:
			var label = UIKit.initials(str(data.get("name", "?")))
			if not data.get("form", {}).is_empty():
				label = UIKit.initials(str(data.form.get("name", "?")))
			var fs = int(r * 0.8)
			var font = ThemeDB.fallback_font
			var ts = font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
			draw_string(font, c + Vector2(-ts.x * 0.5, fs * 0.35), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.95))
	if _flash > 0.0 and not sprite.visible:
		draw_circle(c, r, Color(_flash_col, 0.6 * _flash))
	draw_arc(c, r, 0, TAU, 48, team_col, 3.5 if not is_selected else 5.0)
	if is_selected:
		draw_arc(c, r + 4, 0, TAU, 48, Color(1, 1, 1, 0.9), 2)
	# HP bar.
	var hp = float(data.get("hp", 0))
	var mx = maxf(1.0, float(data.get("max_hp", 1)))
	var form: Dictionary = data.get("form", {})
	if not form.is_empty():
		hp = float(form.hp)
		mx = maxf(1.0, float(form.max_hp))
	var bw = size - 14.0
	var by = size - 9.0
	draw_rect(Rect2(7, by, bw, 7), Color(0, 0, 0, 0.75))
	var frac = clampf(hp / mx, 0.0, 1.0)
	var hc = Color("#5cc892") if frac > 0.5 else (Color("#e8b84a") if frac > 0.25 else Color("#ff5a4a"))
	if not form.is_empty():
		hc = Color("#7fdc7f").lerp(Color("#c8a0ff"), 0.5)
	draw_rect(Rect2(8, by + 1, (bw - 2) * frac, 5), hc)
	if int(data.get("temp_hp", 0)) > 0:
		draw_rect(Rect2(8, by - 4, minf(bw - 2, (bw - 2) * float(data.temp_hp) / mx), 3), Color("#8fd0ff"))
	# Concentration and condition badges.
	var badges: Array = []
	if not data.get("conc", {}).is_empty():
		badges.append(["C", Color("#c8a0ff")])
	var seen := {}
	for e in data.get("effects", []):
		if badges.size() >= 5:
			break
		var cond: String = e.get("cond", "")
		var key := ""
		var bcol := Color("#e0a0ff")
		if cond != "":
			key = cond
		elif e.get("tag", "") in ["rage", "bladesong", "haste", "bonded", "bardic_inspiration", "hunters_mark", "hex", "hexblade_curse"]:
			key = str(e.tag)
			bcol = Color("#ffd166")
		elif e.get("spell", "") == "faerie_fire" or str(e.get("name", "")) == "Outlined" or e.get("mods", {}).get("grants_advantage", false):
			key = "outlined"
			bcol = Color("#ff9be8")
		if key == "" or seen.has(key):
			continue
		seen[key] = true
		badges.append([key, bcol])
	for i in badges.size():
		var bp = Vector2(10 + i * 17, 10)
		draw_circle(bp, 8, Color(0, 0, 0, 0.8))
		draw_circle(bp, 7, Color(badges[i][1], 0.9))
		if not _draw_glyph(str(badges[i][0]), bp):
			var txt := str(badges[i][0]) if str(badges[i][0]) == "C" else str(badges[i][0]).substr(0, 2).capitalize()
			draw_string(ThemeDB.fallback_font, bp + Vector2(-6, 4), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.BLACK)
	if data.get("dead", false) or data.get("death", {}).get("dead", false):
		draw_line(c - Vector2(r, r) * 0.6, c + Vector2(r, r) * 0.6, Color("#ff3030"), 5)
		draw_line(c + Vector2(-r, r) * 0.6, c + Vector2(r, -r) * 0.6, Color("#ff3030"), 5)


## Small vector glyphs for status badges, centred on p. Returns false if there is no glyph for the key.
func _draw_glyph(key: String, p: Vector2) -> bool:
	var k := Color.BLACK
	match key:
		"outlined":  # Faerie Fire: a glowing starburst.
			for i in 4:
				var a := PI * 0.25 * i
				var d := Vector2(cos(a), sin(a)) * 5.5
				draw_line(p - d, p + d, k, 1.5)
			draw_circle(p, 2.0, k)
		"restrained", "grappled":  # Web: spokes plus a ring.
			for i in 4:
				var a2 := PI * 0.25 * i
				var d2 := Vector2(cos(a2), sin(a2)) * 5.5
				draw_line(p - d2, p + d2, k, 1.0)
			draw_arc(p, 3.0, 0, TAU, 12, k, 1.0)
		"frightened":
			draw_line(p + Vector2(0, -5), p + Vector2(0, 1), k, 2.0)
			draw_circle(p + Vector2(0, 4), 1.3, k)
		"poisoned":
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -5), p + Vector2(3.5, 1), p + Vector2(0, 5), p + Vector2(-3.5, 1)]), k)
		"prone":
			draw_line(p + Vector2(-5, 3), p + Vector2(5, 3), k, 2.0)
			draw_circle(p + Vector2(-3.5, -1), 1.8, k)
		"blinded":
			draw_arc(p, 4.0, PI, TAU, 8, k, 1.5)
			draw_arc(p, 4.0, 0, PI, 8, k, 1.5)
			draw_line(p + Vector2(-5, 5), p + Vector2(5, -5), k, 1.5)
		"paralyzed", "stunned", "unconscious", "petrified", "incapacitated":
			draw_rect(Rect2(p + Vector2(-3.5, -4), Vector2(2.5, 8)), k)
			draw_rect(Rect2(p + Vector2(1, -4), Vector2(2.5, 8)), k)
		"charmed":
			draw_circle(p + Vector2(-2, -1.5), 2.3, k)
			draw_circle(p + Vector2(2, -1.5), 2.3, k)
			draw_colored_polygon(PackedVector2Array([p + Vector2(-4.2, -0.5), p + Vector2(4.2, -0.5), p + Vector2(0, 4.5)]), k)
		_:
			return false
	return true
