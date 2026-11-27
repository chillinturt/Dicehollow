class_name DialogPanel
extends PanelContainer
## A floating window drawn inside a screen: a title bar you can drag, a close button, and a body that
## always fits the screen (it shrinks to the viewport and re-centres when the window is resized).

signal closed

var body: VBoxContainer
var title_lbl: Label
var header_extra: HBoxContainer
var want_size := Vector2(980, 720)
var _drag := false
var _moved := false

func _init(title: String, wanted := Vector2(980, 720)) -> void:
	want_size = wanted
	set_meta("dialog", true)
	theme = UIKit.theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", UIKit.sb(Color("#191422"), UIKit.GOLD, 2, 10, 12))
	var v = UIKit.vbox(8)
	add_child(v)
	var bar = UIKit.hbox(8)
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	bar.mouse_default_cursor_shape = Control.CURSOR_MOVE
	bar.gui_input.connect(_on_bar_input)
	title_lbl = UIKit.header(title, 20)
	title_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_lbl.custom_minimum_size = Vector2(120, 0)
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIKit.expand(title_lbl)
	bar.add_child(title_lbl)
	header_extra = UIKit.hbox(6)
	bar.add_child(header_extra)
	var x = UIKit.btn("✕", close, "Close (Esc)")
	x.custom_minimum_size = Vector2(34, 30)
	bar.add_child(x)
	v.add_child(bar)
	body = UIKit.vbox(8)
	UIKit.expand(body, true, true)
	v.add_child(body)

func _ready() -> void:
	_fit()
	get_viewport().size_changed.connect(_fit)
	# Wrapped text can measure tall before its first layout; size back down once it settles.
	minimum_size_changed.connect(_refit_later)
	resized.connect(_refit_later)

var _refit_queued := false

func _refit_later() -> void:
	if _refit_queued:
		return
	_refit_queued = true
	(func():
		_refit_queued = false
		if is_inside_tree():
			_fit()).call_deferred()

func _fit() -> void:
	var vp := get_viewport_rect().size
	var s := Vector2(minf(want_size.x, vp.x - 32), minf(want_size.y, vp.y - 32))
	size = s
	if not _moved:
		position = ((vp - size) * 0.5).floor()
	_clamp()

func _clamp() -> void:
	var vp := get_viewport_rect().size
	position = Vector2(clampf(position.x, 0, maxf(0, vp.x - size.x)), clampf(position.y, 0, maxf(0, vp.y - size.y)))

func _on_bar_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		_drag = ev.pressed
	elif ev is InputEventMouseMotion and _drag:
		position += ev.relative
		_moved = true
		_clamp()

func _unhandled_key_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE and is_visible_in_tree():
		get_viewport().set_input_as_handled()
		close()

func close() -> void:
	closed.emit()
	queue_free()

func set_title(t: String) -> void:
	title_lbl.text = t

## A label that wraps inside its column instead of widening the dialog.
static func wrap_lbl(text: String, fsize := 14, color := UIKit.MUTED) -> Label:
	var l = UIKit.lbl(text, fsize, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(60, 0)
	return l
