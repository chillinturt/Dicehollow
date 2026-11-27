class_name PortraitTemplates
## Ready-made character portraits: a class-themed silhouette drawn on the character's token colour.
## Picking one saves a normal 256px portrait PNG (key "tpl_<icon>_<hex>"), so tokens, the
## character list and multiplayer portrait sync treat it exactly like an uploaded image.

const W := "fill='#fff'"
const D := "fill='#000' fill-opacity='.55'"
const DS := "fill='none' stroke='#000' stroke-opacity='.55' stroke-width='2' stroke-linecap='round'"

## Icons drawn here; "hat", "hood", "helm" and "dragon" come from MonsterIcons.
const SVG := {
	"sword": "<path " + W + " d='M29 4 L35 4 L36 40 L28 40 Z'/>"
		+ "<rect " + D + " x='31.3' y='8' width='1.4' height='30'/>"
		+ "<rect " + W + " x='17' y='40' width='30' height='5' rx='2'/>"
		+ "<rect " + W + " x='29.5' y='45' width='5' height='10'/><circle " + W + " cx='32' cy='58' r='4'/>",
	"shield": "<path " + W + " d='M32 4 L54 12 Q54 44 32 60 Q10 44 10 12 Z'/>"
		+ "<rect " + D + " x='29' y='15' width='6' height='32'/><rect " + D + " x='19' y='24' width='26' height='6'/>",
	"axe": "<rect " + W + " x='30' y='6' width='5' height='54' rx='2'/>"
		+ "<path " + W + " d='M35 8 Q56 4 60 30 Q50 24 35 30 Z M30 8 Q8 4 4 30 Q14 24 30 30 Z'/>"
		+ "<rect " + D + " x='29' y='34' width='7' height='3'/><rect " + D + " x='29' y='40' width='7' height='3'/>",
	"bow": "<path fill='none' stroke='#fff' stroke-width='5' stroke-linecap='round' d='M20 6 Q52 32 20 58'/>"
		+ "<path fill='none' stroke='#fff' stroke-width='1.5' d='M20 6 L20 58'/>"
		+ "<path fill='none' stroke='#fff' stroke-width='3' d='M10 32 L50 32'/>"
		+ "<path " + W + " d='M60 32 L48 25 L48 39 Z M10 32 L4 26 L12 26 L16 32 L12 38 L4 38 Z'/>",
	"sun": "<path " + W + " d='M32 2 L36 15 L28 15 Z M32 62 L36 49 L28 49 Z M62 32 L49 28 L49 36 Z M2 32 L15 28 L15 36 Z"
		+ " M53 11 L47 23 L41 17 Z M11 11 L17 23 L23 17 Z M53 53 L47 41 L41 47 Z M11 53 L17 41 L23 47 Z'/>"
		+ "<circle " + W + " cx='32' cy='32' r='13'/><circle " + D + " cx='32' cy='32' r='6'/>",
	"lute": "<path " + W + " d='M30 30 L50 9 L55 14 L35 34 Z M50 9 L54 2 L62 10 L55 14 Z'/>"
		+ "<ellipse " + W + " cx='26' cy='42' rx='16' ry='17'/>"
		+ "<circle " + D + " cx='27' cy='39' r='5'/><rect " + D + " x='17' y='50' width='14' height='3' rx='1'/>",
	"leaf": "<path " + W + " d='M32 60 Q6 34 18 16 Q26 6 32 4 Q38 6 46 16 Q58 34 32 60 Z'/>"
		+ "<path " + DS + " d='M32 10 L32 56 M32 24 L23 18 M32 24 L41 18 M32 36 L21 28 M32 36 L43 28 M32 47 L25 41 M32 47 L39 41'/>",
	"fist": "<rect " + W + " x='16' y='22' width='32' height='32' rx='8'/>"
		+ "<circle " + W + " cx='21' cy='22' r='6'/><circle " + W + " cx='29' cy='20' r='6'/>"
		+ "<circle " + W + " cx='37' cy='20' r='6'/><circle " + W + " cx='44' cy='22' r='6'/>"
		+ "<path " + DS + " d='M25 18 L25 30 M33 16 L33 30 M41 18 L41 30'/>"
		+ "<path " + D + " d='M16 36 L35 33 Q40 36 35 41 L18 43 Z'/>"
		+ "<rect " + W + " x='21' y='52' width='22' height='10' rx='2'/>",
	"flame": "<path " + W + " d='M32 60 Q12 58 12 40 Q12 26 24 16 Q22 28 30 30 Q26 14 36 4 Q38 20 48 28 Q54 34 52 44 Q50 58 32 60 Z'/>"
		+ "<path " + D + " d='M32 56 Q22 54 23 45 Q24 38 30 34 Q30 42 36 42 Q42 46 40 51 Q38 56 32 56 Z'/>",
	"eye": "<path " + W + " d='M4 32 Q32 6 60 32 Q32 58 4 32 Z'/>"
		+ "<circle " + D + " cx='32' cy='32' r='12'/><ellipse " + W + " cx='32' cy='32' rx='2.5' ry='9'/>"
		+ "<path " + W + " d='M14 14 L19 21 L16 22 Z M50 14 L45 21 L48 22 Z M32 2 L34 11 L30 11 Z'/>",
	"gear": "<rect " + W + " x='28' y='3' width='8' height='13' rx='1.5'/>"
		+ "<rect " + W + " x='28' y='3' width='8' height='13' rx='1.5' transform='rotate(45 32 32)'/>"
		+ "<rect " + W + " x='28' y='3' width='8' height='13' rx='1.5' transform='rotate(90 32 32)'/>"
		+ "<rect " + W + " x='28' y='3' width='8' height='13' rx='1.5' transform='rotate(135 32 32)'/>"
		+ "<rect " + W + " x='28' y='3' width='8' height='13' rx='1.5' transform='rotate(180 32 32)'/>"
		+ "<rect " + W + " x='28' y='3' width='8' height='13' rx='1.5' transform='rotate(225 32 32)'/>"
		+ "<rect " + W + " x='28' y='3' width='8' height='13' rx='1.5' transform='rotate(270 32 32)'/>"
		+ "<rect " + W + " x='28' y='3' width='8' height='13' rx='1.5' transform='rotate(315 32 32)'/>"
		+ "<circle " + W + " cx='32' cy='32' r='19'/><circle " + D + " cx='32' cy='32' r='8'/>",
	"crown": "<path " + W + " d='M8 46 L8 16 L20 30 L32 10 L44 30 L56 16 L56 46 Z'/>"
		+ "<rect " + W + " x='8' y='46' width='48' height='9' rx='2'/>"
		+ "<rect " + D + " x='8' y='40' width='48' height='4'/>"
		+ "<circle " + D + " cx='32' cy='30' r='3.5'/><circle " + D + " cx='19' cy='50.5' r='2.5'/>"
		+ "<circle " + D + " cx='32' cy='50.5' r='2.5'/><circle " + D + " cx='45' cy='50.5' r='2.5'/>",
}

## Gallery order: [icon, label]. The first 13 match the classes in CLASS_ICON.
const ORDER := [
	["sword", "Sword"], ["axe", "Axe"], ["shield", "Shield"], ["bow", "Bow"],
	["hood", "Hood"], ["hat", "Wizard hat"], ["flame", "Flame"], ["eye", "Eldritch eye"],
	["sun", "Holy sun"], ["leaf", "Leaf"], ["fist", "Fist"], ["lute", "Lute"],
	["gear", "Gear"], ["helm", "Helm"], ["crown", "Crown"], ["dragon", "Dragon"],
]

## Class id -> suggested icon.
const CLASS_ICON := {
	"fighter": "sword", "barbarian": "axe", "paladin": "shield", "ranger": "bow", "rogue": "hood",
	"wizard": "hat", "sorcerer": "flame", "warlock": "eye", "cleric": "sun", "druid": "leaf",
	"monk": "fist", "bard": "lute", "artificer": "gear",
}

const KEY_PREFIX := "tpl_"

static var _preview_cache := {}

static func has(icon: String) -> bool:
	return SVG.has(icon) or MonsterIcons.SVG.has(icon)

static func label(icon: String) -> String:
	for e in ORDER:
		if e[0] == icon:
			return e[1]
	return icon.capitalize()

## Suggested icon for a character (from its first class), or "".
static func suggested(ch: Dictionary) -> String:
	var classes: Array = ch.get("classes", [])
	if classes.is_empty():
		return ""
	return CLASS_ICON.get(str(classes[0].get("id", "")), "")

## Portrait key for an icon on a colour.
static func key_for(icon: String, color: Color) -> String:
	return KEY_PREFIX + icon + "_" + color.to_html(false)

## Draw an icon on a disc of the given colour, as a size x size RGBA image (null if unknown).
static func render(icon: String, color: Color, size := 256) -> Image:
	var body: String = SVG.get(icon, MonsterIcons.SVG.get(icon, ""))
	if body == "":
		return null
	# Dark ink on light colours so the silhouette stays readable.
	var light := color.get_luminance() > 0.6
	if light:
		body = body.replace("#fff", "#1a1622").replace("#000", "#fffbe8")
	var svg := "<svg xmlns='http://www.w3.org/2000/svg' width='64' height='64' viewBox='0 0 64 64'>%s</svg>" % body
	var ico := Image.new()
	var icon_px := int(size * 0.62)
	if ico.load_svg_from_string(svg, icon_px / 64.0) != OK:
		return null
	ico.convert(Image.FORMAT_RGBA8)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var outer := color.darkened(0.55)
	var inner := color.lightened(0.12) if not light else color
	var c := (size - 1) / 2.0
	var r := size * 0.47
	for y in size:
		for x in size:
			var d := Vector2(x - c, y - c).length()
			# Soft radial shading inside the disc, dark rim outside it.
			var t := clampf(d / r, 0.0, 1.0)
			var col := inner.lerp(color.darkened(0.2), t * t)
			col = col.lerp(outer, clampf(d - r + 1.0, 0.0, 1.0))
			img.set_pixel(x, y, col)
	var off := (size - ico.get_width()) / 2
	img.blend_rect(ico, Rect2i(Vector2i.ZERO, ico.get_size()), Vector2i(off, off))
	return img

## Small cached preview texture for the gallery.
static func preview(icon: String, color: Color, size := 48) -> Texture2D:
	var k := "%s_%s_%d" % [icon, color.to_html(false), size]
	if not _preview_cache.has(k):
		var img := render(icon, color, size)
		_preview_cache[k] = ImageTexture.create_from_image(img) if img else null
	return _preview_cache[k]

## Grid of template icons drawn in `color`. `current` is outlined in gold, `suggested` in soft gold.
## Clicking an icon calls on_pick(icon).
static func gallery(color: Color, current: String, suggested_icon: String, on_pick: Callable) -> GridContainer:
	var grid = GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	for e in ORDER:
		var icon: String = e[0]
		var b = Button.new()
		b.icon = preview(icon, color, 36)
		b.expand_icon = true
		b.custom_minimum_size = Vector2(42, 42)
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = e[1] + (" (suggested for your class)" if icon == suggested_icon else "")
		if icon == current:
			b.add_theme_stylebox_override("normal", UIKit.sb(Color("#2a2238"), UIKit.GOLD, 2, 6, 2))
		elif icon == suggested_icon:
			b.add_theme_stylebox_override("normal", UIKit.sb(Color("#1a1622"), UIKit.GOLD_SOFT, 2, 6, 2))
		else:
			b.add_theme_stylebox_override("normal", UIKit.sb(Color("#1a1622"), Color(0, 0, 0, 0), 0, 6, 2))
		b.add_theme_stylebox_override("hover", UIKit.sb(Color("#2a2238"), UIKit.GOLD_SOFT, 1, 6, 2))
		b.add_theme_stylebox_override("pressed", UIKit.sb(Color("#2a2238"), UIKit.GOLD, 2, 6, 2))
		b.pressed.connect(on_pick.bind(icon))
		grid.add_child(b)
	return grid

## Save the template as a portrait and return its key ("" on failure).
static func make_portrait(icon: String, color: Color) -> String:
	var img := render(icon, color, CharacterStore.PORTRAIT_SIZE)
	if img == null:
		return ""
	return CharacterStore.save_portrait_image(img, key_for(icon, color))
