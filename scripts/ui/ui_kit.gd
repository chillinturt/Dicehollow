class_name UIKit
extends RefCounted
## Shared theme and small widget helpers so every screen is built in code with one look.

const BG := Color("#14111c")
const PANEL := Color("#1f1a2b")
const PANEL_2 := Color("#2a2338")
const GOLD := Color("#c9a14a")
const GOLD_SOFT := Color("#8a6f35")
const INK := Color("#ece6d8")
const MUTED := Color("#a59cb5")
const ACCENT := Color("#8a5cc4")
const GOOD := Color("#5cc892")
const BAD := Color("#ff6b5b")
const PARTY := Color("#4aa3ff")
const ENEMY := Color("#ff5a4a")

static var _theme: Theme

static func sb(bg: Color, border := Color(0, 0, 0, 0), bw := 0, radius := 6, pad := 8) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad * 0.6
	s.content_margin_bottom = pad * 0.6
	return s

static func theme() -> Theme:
	if _theme:
		return _theme
	var t = Theme.new()
	t.default_font_size = 15
	t.set_color("font_color", "Label", INK)
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", GOLD)
	t.set_color("font_disabled_color", "Button", Color(0.55, 0.52, 0.6))
	t.set_stylebox("normal", "Button", sb(PANEL_2, GOLD_SOFT, 1))
	t.set_stylebox("hover", "Button", sb(Color("#3a3050"), GOLD, 1))
	t.set_stylebox("pressed", "Button", sb(Color("#4a3a68"), GOLD, 2))
	t.set_stylebox("disabled", "Button", sb(Color("#1c1826"), Color("#3a3448"), 1))
	t.set_stylebox("focus", "Button", sb(Color(0, 0, 0, 0), GOLD, 1))
	t.set_stylebox("panel", "PanelContainer", sb(PANEL, GOLD_SOFT, 1, 8, 10))
	t.set_stylebox("panel", "Panel", sb(PANEL, GOLD_SOFT, 1, 8, 10))
	t.set_stylebox("normal", "LineEdit", sb(Color("#120f19"), Color("#4a4060"), 1, 4, 6))
	t.set_stylebox("focus", "LineEdit", sb(Color("#120f19"), GOLD, 1, 4, 6))
	t.set_color("font_color", "LineEdit", INK)
	t.set_stylebox("normal", "OptionButton", sb(PANEL_2, GOLD_SOFT, 1))
	t.set_stylebox("hover", "OptionButton", sb(Color("#3a3050"), GOLD, 1))
	t.set_stylebox("pressed", "OptionButton", sb(Color("#3a3050"), GOLD, 1))
	t.set_stylebox("panel", "TabContainer", sb(PANEL, GOLD_SOFT, 1, 6, 10))
	t.set_stylebox("tab_selected", "TabContainer", sb(Color("#3a3050"), GOLD, 1, 4, 10))
	t.set_stylebox("tab_unselected", "TabContainer", sb(PANEL_2, Color(0, 0, 0, 0), 0, 4, 10))
	t.set_stylebox("tab_hovered", "TabContainer", sb(Color("#332a46"), GOLD_SOFT, 1, 4, 10))
	t.set_color("font_selected_color", "TabContainer", GOLD)
	t.set_color("font_unselected_color", "TabContainer", MUTED)
	t.set_stylebox("panel", "Tree", sb(Color("#120f19"), Color("#4a4060"), 1, 4, 4))
	t.set_color("font_color", "Tree", INK)
	t.set_stylebox("panel", "ItemList", sb(Color("#120f19"), Color("#4a4060"), 1, 4, 4))
	t.set_color("font_color", "ItemList", INK)
	t.set_stylebox("normal", "RichTextLabel", sb(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 2))
	t.set_color("default_color", "RichTextLabel", INK)
	t.set_stylebox("panel", "TooltipPanel", sb(Color("#0f0c16"), GOLD, 1, 4, 8))
	t.set_color("font_color", "TooltipLabel", INK)
	t.set_stylebox("panel", "PopupMenu", sb(Color("#1a1524"), GOLD, 1, 4, 6))
	t.set_stylebox("panel", "PopupPanel", sb(Color("#1a1524"), GOLD, 1, 6, 10))
	t.set_stylebox("normal", "SpinBox", sb(Color("#120f19"), Color("#4a4060"), 1))
	t.set_color("font_color", "CheckBox", INK)
	t.set_color("font_color", "CheckButton", INK)
	# Sliders (the volume control): a visible track that fills gold up to the grabber.
	var track := sb(Color("#0d0b12"), Color("#4a4060"), 1, 3, 0)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", track)
	var fill := sb(GOLD_SOFT, Color(0, 0, 0, 0), 0, 3, 0)
	fill.content_margin_top = 3
	fill.content_margin_bottom = 3
	t.set_stylebox("grabber_area", "HSlider", fill)
	var fill_hi := fill.duplicate()
	fill_hi.bg_color = GOLD
	t.set_stylebox("grabber_area_highlight", "HSlider", fill_hi)
	_theme = t
	return t

static func lbl(text: String, size := 15, color := INK) -> Label:
	var l = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

static func header(text: String, size := 22) -> Label:
	var l = lbl(text, size, GOLD)
	return l

static func rich(text := "", fit := true) -> RichTextLabel:
	var r = RichTextLabel.new()
	r.bbcode_enabled = true
	r.text = text
	r.fit_content = fit
	r.scroll_active = not fit
	r.selection_enabled = true
	return r

static func btn(text: String, cb: Callable = Callable(), tip := "") -> Button:
	var b = Button.new()
	b.text = text
	b.tooltip_text = tip
	if cb.is_valid():
		b.pressed.connect(cb)
	return b

static func vbox(sep := 6) -> VBoxContainer:
	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v

static func hbox(sep := 6) -> HBoxContainer:
	var h = HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h

static func panel(child: Control = null, bg := PANEL, border := GOLD_SOFT) -> PanelContainer:
	var p = PanelContainer.new()
	p.add_theme_stylebox_override("panel", sb(bg, border, 1, 8, 10))
	if child:
		p.add_child(child)
	return p

static func line(text := "", placeholder := "", cb: Callable = Callable()) -> LineEdit:
	var e = LineEdit.new()
	e.text = text
	e.placeholder_text = placeholder
	if cb.is_valid():
		e.text_changed.connect(cb)
	return e

static func spin(mn: float, mx: float, val: float, cb: Callable = Callable(), step := 1.0) -> SpinBox:
	var s = SpinBox.new()
	s.min_value = mn
	s.max_value = mx
	s.step = step
	s.value = val
	if cb.is_valid():
		s.value_changed.connect(cb)
	return s

## items: Array of [id, label]. Calls cb(id) on change.
static func option(items: Array, selected_id = null, cb: Callable = Callable()) -> OptionButton:
	var o = OptionButton.new()
	var sel = 0
	for i in items.size():
		o.add_item(str(items[i][1]), i)
		o.set_item_metadata(i, items[i][0])
		if items[i][0] == selected_id:
			sel = i
	if items.size() > 0:
		o.select(sel)
	if cb.is_valid():
		o.item_selected.connect(func(idx): cb.call(o.get_item_metadata(idx)))
	return o

static func check(text: String, on: bool, cb: Callable = Callable()) -> CheckBox:
	var c = CheckBox.new()
	c.text = text
	c.button_pressed = on
	if cb.is_valid():
		c.toggled.connect(cb)
	return c

static func margin(child: Control, px := 12) -> MarginContainer:
	var m = MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, px)
	m.add_child(child)
	return m

static func scroll(child: Control) -> ScrollContainer:
	var s = ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.add_child(child)
	return s

static func clear(node: Node) -> void:
	for ch in node.get_children():
		node.remove_child(ch)
		ch.queue_free()

static func expand(c: Control, h := true, v := false) -> Control:
	if h: c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if v: c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c

static func bar(value: float, max_value: float, color: Color, h := 10) -> ProgressBar:
	var p = ProgressBar.new()
	p.max_value = maxf(1.0, max_value)
	p.value = value
	p.show_percentage = false
	p.custom_minimum_size = Vector2(0, h)
	p.add_theme_stylebox_override("background", sb(Color("#0d0b12"), Color("#3a3448"), 1, 3, 0))
	p.add_theme_stylebox_override("fill", sb(color, Color(0, 0, 0, 0), 0, 3, 0))
	return p

static var _pack_tex: ImageTexture

## A small drawn backpack (20 × 20) for the inventory buttons: the 🎒 emoji renders as an unreadable blob
## at button size in some fonts.
static func pack_icon() -> ImageTexture:
	if _pack_tex != null:
		return _pack_tex
	var img := Image.create(20, 20, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var leather := Color("#b5793c")
	var dark := Color("#4a2e14")
	var flap := Color("#8f5a28")
	var pocket := Color("#c98f52")
	var paint := func(x0: int, y0: int, x1: int, y1: int, col: Color) -> void:
		for x in range(x0, x1 + 1):
			for y in range(y0, y1 + 1):
				img.set_pixel(x, y, col)
	# Handle loop on top.
	paint.call(7, 1, 12, 1, dark)
	paint.call(6, 2, 6, 4, dark)
	paint.call(13, 2, 13, 4, dark)
	# Body with a dark outline and rounded corners.
	paint.call(3, 5, 16, 18, dark)
	paint.call(4, 6, 15, 17, leather)
	for p in [Vector2i(3, 5), Vector2i(16, 5), Vector2i(3, 18), Vector2i(16, 18)]:
		img.set_pixelv(p, Color(0, 0, 0, 0))
	# Flap and buckle.
	paint.call(4, 6, 15, 9, flap)
	paint.call(3, 10, 16, 10, dark)
	paint.call(9, 9, 10, 11, GOLD)
	# Front pocket.
	paint.call(6, 12, 13, 17, dark)
	paint.call(7, 13, 12, 16, pocket)
	_pack_tex = ImageTexture.create_from_image(img)
	return _pack_tex

static func initials(name: String) -> String:
	var parts = name.replace("(", " ").split(" ", false)
	var out = ""
	for p in parts:
		if out.length() < 2 and p.length() > 0 and p[0] == p[0].to_upper():
			out += p[0]
	return out if out != "" else name.substr(0, 2).to_upper()

static func popup_choice(parent: Node, title: String, items: Array, cb: Callable) -> void:
	## items: Array of [id, label]
	var pm = PopupMenu.new()
	pm.add_theme_font_size_override("font_size", 15)
	if title != "":
		pm.add_separator(title)
	for i in items.size():
		pm.add_item(str(items[i][1]), i)
		pm.set_item_metadata(pm.get_item_index(i), items[i][0])
	pm.id_pressed.connect(func(id): cb.call(items[id][0]))
	pm.popup_hide.connect(pm.queue_free)
	parent.add_child(pm)
	pm.popup(Rect2i(Vector2i(parent.get_viewport().get_mouse_position()), Vector2i(220, 0)))
