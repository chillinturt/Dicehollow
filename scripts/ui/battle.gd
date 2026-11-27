extends Node2D
## The play screen shared by DM and players: battle map, tokens, hotbar, initiative, log and DM tools.

const CELL := 64
const MapViewScript := preload("res://scripts/ui/map_view.gd")
const MonsterEditorScript := preload("res://scripts/ui/monster_editor.gd")
const TokenScript := preload("res://scripts/ui/token.gd")
const Vfx := preload("res://scripts/ui/vfx.gd")
const RIGHT_W := 380   # inspect / log column
const BOTTOM_H := 214  # card / hotbar bar
const DM_W := 330      # DM toolbox
const CAT_COLORS := {"attack": Color("#b5523b"), "spell": Color("#6b4fb0"), "feature": Color("#b08a2e"), "basic": Color("#4a5a6e"), "toggle": Color("#2f7a6a")}

var map_view: Node2D
var tokens_root: Node2D
var fx_root: Node2D
var cam: Camera2D
var tokens := {}

# HUD
var hud: CanvasLayer
var ui: Control
var init_row: HBoxContainer
var title_lbl: Label
var round_lbl: Label
var log_rt: RichTextLabel
var chat_in: LineEdit
var inspect_box: VBoxContainer
var card_box: HBoxContainer
var hotbar: HFlowContainer
var cat_row: HBoxContainer
var econ_lbl: RichTextLabel
var end_btn: Button
var auto_btn: Button
var auto_use_resources := true  # Auto Turn may spend spell slots / limited-use features
var auto_move := true  # Auto Turn may move
var tip: Label
var banner: Label
var mode_lbl: Label
var dm_tabs: TabContainer
var confirm_btn: Button

# Interaction state
var selected_cid := ""
var control_cid := ""
var mode := ""              # "", "target", "paint", "place_monster", "spawn"
var pending := {}
var paint_value := 1
var brush := 1
var place_mid := ""
var place_ally := false
var hot_cat := "all"
var free_move := false
var painting := false
var paint_buffer: Array = []
var panning := false
var event_queue: Array = []
var playing := false
var last_turn_id := ""
var monster_filter := ""
var mon_fill: Callable
var mon_list: ItemList
var bg_dialog: FileDialog
var bg_fit := true
var _last_hit_col := Color("#ffcf8a")   # spark colour for the next damage number, from the last attack's fx
var shown_hit := ""       # id of the held weapon hit this player was last asked about
# DM tools: extra selected creatures (Ctrl+click) and the inspect panel's remembered inputs.
var selected_ids: Array = []
var place_hidden := false
var dm_amount := 5
var dm_dtype := "untyped"
var dm_cond_rounds := 0
var roll_pick := "save:dex"
var roll_dc := 15
var roll_damage := ""
var roll_half := true
var _inspect_key := ""
var map_pick: OptionButton
var map_name_edit: LineEdit
var hidden_lbl: Label
var _ending := false
var top_bar: PanelContainer
var bottom_bar: PanelContainer
var right_panel: PanelContainer
# Character sheets and levelling.
var sheet_win: CharacterSheet
var sheet_cid := ""
var level_win: LevelUpWizard
var _announced_levels := {}   # cid -> allowed level already announced to this player
var party_box: VBoxContainer
var dm_xp_amount := 100
var dm_xp_split := true
# Fog of war: what this screen may show ({} = everything; see Fog.view_for).
var fog_view := {}
var fog_preview := false   # DM: look through the party's eyes
var fog_mode_opt: OptionButton
var fog_range_opt: OptionButton
var fog_shared_chk: CheckBox
const FOG_REVEAL := 10     # paint_value for the DM's reveal / re-fog brushes
const FOG_HIDE := 11

func _ready() -> void:
	RenderingServer.set_default_clear_color(UIKit.BG)
	map_view = MapViewScript.new()
	add_child(map_view)
	tokens_root = Node2D.new()
	add_child(tokens_root)
	fx_root = Node2D.new()
	add_child(fx_root)
	cam = Camera2D.new()
	add_child(cam)
	cam.make_current()
	_build_hud()
	Session.state_changed.connect(_on_state)
	Session.chat_received.connect(func(t): log_rt.append_text("\n[color=#9fe6ff]%s[/color]" % t))
	Session.portrait_arrived.connect(func(_k): _sync_tokens([]); _refresh_ui())
	Session.players_changed.connect(_refresh_dm)
	Session.sheets_changed.connect(_on_sheets_changed)
	Session.session_ended.connect(_on_session_ended)
	Session.status.connect(func(t): _flash(t))
	bg_dialog = FileDialog.new()
	bg_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	bg_dialog.access = FileDialog.ACCESS_FILESYSTEM
	bg_dialog.use_native_dialog = true
	bg_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp, *.bmp ; Images"])
	bg_dialog.file_selected.connect(_on_bg_file)
	add_child(bg_dialog)
	map_view.set_state(Session.state)
	_update_fog()
	cam.position = Vector2(Session.state.w, Session.state.h) * CELL * 0.5
	cam.zoom = Vector2.ONE * 0.8
	_sync_tokens([])
	for line in Session.state.get("log", []):
		log_rt.append_text("\n" + line)
	_refresh_ui()
	if Session.role == "player":
		_flash("Waiting for the DM…" if Session.state.combatants.is_empty() else "Connected.")

# ================================================================ HUD construction

func _build_hud() -> void:
	hud = CanvasLayer.new()
	add_child(hud)
	ui = Control.new()
	ui.theme = UIKit.theme()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(ui)
	# Top bar. Its height comes from its contents; the side panels are laid out under it (_layout_hud).
	var top = UIKit.panel(null, Color("#17131f"))
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = 0
	top_bar = top
	ui.add_child(top)
	var th = UIKit.hbox(14)
	top.add_child(th)
	var tv = UIKit.vbox(2)
	tv.custom_minimum_size = Vector2(250, 0)
	title_lbl = UIKit.lbl(Session.game_name if Session.game_name != "" else "Dicehollow", 20, UIKit.GOLD)
	round_lbl = UIKit.lbl("", 14, UIKit.MUTED)
	tv.add_child(title_lbl)
	tv.add_child(round_lbl)
	th.add_child(tv)
	var isc = ScrollContainer.new()
	isc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	UIKit.expand(isc, true, true)
	init_row = UIKit.hbox(6)
	isc.add_child(init_row)
	th.add_child(isc)
	var tb = UIKit.vbox(4)
	var tbr = UIKit.hbox(4)
	tbr.add_child(UIKit.expand(UIKit.btn("Leave", _leave, "Leave the game")))
	tbr.add_child(UIKit.expand(UIKit.btn("Center", func(): _center_on(control_cid if control_cid != "" else selected_cid), "Center the view on your character")))
	tb.add_child(tbr)
	tb.add_child(_build_volume())
	th.add_child(tb)
	# Right column: inspect + log + chat.
	var rightp = UIKit.panel(null, Color("#17131f"))
	rightp.anchor_left = 1.0
	rightp.anchor_right = 1.0
	rightp.anchor_bottom = 1.0
	rightp.offset_left = -RIGHT_W
	rightp.offset_top = 98
	right_panel = rightp
	ui.add_child(rightp)
	var rv = UIKit.vbox(6)
	rightp.add_child(rv)
	inspect_box = UIKit.vbox(4)
	var isc2 = UIKit.scroll(inspect_box)
	isc2.custom_minimum_size = Vector2(0, 250)
	isc2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	isc2.size_flags_stretch_ratio = 1.1
	rv.add_child(isc2)
	rv.add_child(UIKit.lbl("Combat log", 14, UIKit.GOLD))
	log_rt = UIKit.rich("", false)
	log_rt.scroll_following = true
	UIKit.expand(log_rt, true, true)
	log_rt.add_theme_font_size_override("normal_font_size", 13)
	log_rt.add_theme_font_size_override("bold_font_size", 13)
	rv.add_child(log_rt)
	chat_in = UIKit.line("", "Chat, or /roll 2d6+3")
	chat_in.text_submitted.connect(func(t): Session.send_chat(t); chat_in.clear())
	rv.add_child(chat_in)
	# Bottom bar: character card, hotbar, economy. It grows upwards if its contents ever need more room.
	var bottom = UIKit.panel(null, Color("#17131f"))
	bottom.anchor_top = 1.0
	bottom.anchor_bottom = 1.0
	bottom.anchor_right = 1.0
	bottom.offset_top = -BOTTOM_H
	bottom.offset_right = -(RIGHT_W + 6)
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom_bar = bottom
	ui.add_child(bottom)
	var bh = UIKit.hbox(10)
	bottom.add_child(bh)
	card_box = UIKit.hbox(8)
	card_box.custom_minimum_size = Vector2(340, 0)
	bh.add_child(card_box)
	var hv = UIKit.vbox(4)
	UIKit.expand(hv, true, true)
	cat_row = UIKit.hbox(4)
	hv.add_child(cat_row)
	for cat in [["all", "All"], ["attack", "Attacks"], ["spell", "Spells"], ["feature", "Features"], ["basic", "Actions"]]:
		var key: String = cat[0]
		var b = UIKit.btn(cat[1], func(): hot_cat = key; _refresh_hotbar())
		b.toggle_mode = true
		b.set_meta("cat", key)
		cat_row.add_child(b)
	hotbar = HFlowContainer.new()
	hotbar.add_theme_constant_override("h_separation", 5)
	hotbar.add_theme_constant_override("v_separation", 5)
	var hsc = UIKit.scroll(hotbar)
	UIKit.expand(hsc, true, true)
	hv.add_child(hsc)
	bh.add_child(hv)
	var ev = UIKit.vbox(6)
	ev.custom_minimum_size = Vector2(170, 0)
	econ_lbl = UIKit.rich("", true)
	econ_lbl.custom_minimum_size = Vector2(170, 80)
	ev.add_child(econ_lbl)
	end_btn = UIKit.btn("End Turn", func(): Session.request({"type": "end_turn"}), "End your turn (E)")
	end_btn.custom_minimum_size = Vector2(0, 44)
	end_btn.add_theme_font_size_override("font_size", 18)
	ev.add_child(end_btn)
	var ar = UIKit.hbox(4)
	auto_btn = UIKit.btn("⚙ Auto Turn", func(): Session.request({"type": "ai_turn", "cid": control_cid, "resources": auto_use_resources, "move": auto_move}), "Let the AI play this turn: it moves, picks the best attack or spell and ends the turn.")
	UIKit.expand(auto_btn)
	ar.add_child(auto_btn)
	# Auto Turn settings live in a small menu so the column stays short.
	var opts = MenuButton.new()
	opts.text = "▾"
	opts.flat = false
	opts.tooltip_text = "Auto Turn settings"
	opts.custom_minimum_size = Vector2(30, 0)
	var pm: PopupMenu = opts.get_popup()
	pm.add_check_item("Auto Turn may use resources", 0)
	pm.set_item_checked(0, auto_use_resources)
	pm.set_item_tooltip(0, "Off: Auto Turn never spends spell slots or limited-use features; it sticks to weapons, cantrips and free actions.")
	pm.add_check_item("Auto Turn may move", 1)
	pm.set_item_checked(1, auto_move)
	pm.set_item_tooltip(1, "Off: Auto Turn never moves, Dashes or repositions; it acts from where you stand.")
	pm.id_pressed.connect(func(id):
		var i := pm.get_item_index(id)
		pm.set_item_checked(i, not pm.is_item_checked(i))
		if id == 0:
			auto_use_resources = pm.is_item_checked(i)
		else:
			auto_move = pm.is_item_checked(i))
	ar.add_child(opts)
	ev.add_child(ar)
	bh.add_child(ev)
	# DM toolbox (left), sized to the space between the top and bottom bars.
	if Session.is_dm():
		dm_tabs = TabContainer.new()
		dm_tabs.position = Vector2(8, 100)
		dm_tabs.custom_minimum_size = Vector2(DM_W, 0)
		dm_tabs.size = Vector2(DM_W, 470)
		ui.add_child(dm_tabs)
		_build_dm()
	top.resized.connect(_layout_hud)
	bottom.resized.connect(_layout_hud)
	get_viewport().size_changed.connect(_layout_hud)
	_layout_hud.call_deferred()
	# Floating helpers.
	tip = UIKit.lbl("", 15, Color.WHITE)
	tip.add_theme_stylebox_override("normal", UIKit.sb(Color(0, 0, 0, 0.8), UIKit.GOLD, 1, 4, 6))
	tip.visible = false
	tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(tip)
	banner = UIKit.lbl("", 30, UIKit.GOLD)
	banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner.offset_top = 110
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	banner.add_theme_color_override("font_outline_color", Color.BLACK)
	banner.add_theme_constant_override("outline_size", 8)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.modulate.a = 0.0
	ui.add_child(banner)
	var mh = UIKit.hbox(8)
	mh.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	mh.offset_top = -262
	mh.offset_bottom = -226
	mh.grow_horizontal = Control.GROW_DIRECTION_BOTH
	mode_lbl = UIKit.lbl("", 16, Color.WHITE)
	mode_lbl.add_theme_stylebox_override("normal", UIKit.sb(Color(0, 0, 0, 0.75), UIKit.GOLD, 1, 4, 8))
	mh.add_child(mode_lbl)
	confirm_btn = UIKit.btn("Confirm targets", _confirm_targets)
	mh.add_child(confirm_btn)
	ui.add_child(mh)
	mode_lbl.visible = false
	confirm_btn.visible = false

## Fit the side panels into the space the top and bottom bars leave, whatever their real heights.
func _layout_hud() -> void:
	if top_bar == null:
		return
	var vp := ui.get_viewport_rect().size
	var top_h := top_bar.size.y
	right_panel.offset_top = top_h + 6
	if dm_tabs != null:
		var bottom_top := vp.y - bottom_bar.size.y
		dm_tabs.position = Vector2(8, top_h + 6)
		dm_tabs.size = Vector2(DM_W, maxf(200.0, bottom_top - top_h - 12))

## Make every label and check box under `node` wrap within its column instead of widening it.
## Only text stacked in a column (or set to expand) wraps: a short label beside buttons in a row keeps its width.
func _wrap_texts(node: Node) -> void:
	for ch in node.get_children():
		if (ch is Label or ch is CheckBox) and (node is VBoxContainer or ch.size_flags_horizontal & Control.SIZE_EXPAND):
			if ch.autowrap_mode == TextServer.AUTOWRAP_OFF:
				ch.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_wrap_texts(ch)

# ---------------------------------------------------------------- DM toolbox

func _build_dm() -> void:
	# Combat tab.
	var cv = UIKit.vbox(6)
	var csc = UIKit.scroll(UIKit.margin(cv, 6))
	csc.name = "Combat"
	dm_tabs.add_child(csc)
	cv.add_child(UIKit.btn("⚔ Start Combat (roll initiative)", func(): Session.request({"type": "dm_start_combat"})))
	cv.add_child(UIKit.btn("End Combat", func(): Session.request({"type": "dm_end_combat"})))
	cv.add_child(UIKit.btn("Force next turn", func(): Session.request({"type": "dm_next_turn"})))
	cv.add_child(UIKit.btn("Run AI for current turn", func(): Session.request({"type": "ai_turn"})))
	cv.add_child(UIKit.check("Monsters play automatically", Session.auto_monsters, func(p): Session.request({"type": "dm_auto_monsters", "on": p})))
	cv.add_child(UIKit.check("Free-move tokens (ignore movement)", false, func(p): free_move = p))
	cv.add_child(HSeparator.new())
	cv.add_child(UIKit.btn("Short Rest (everyone)", func(): Session.request({"type": "dm_short_rest"})))
	cv.add_child(UIKit.btn("Long Rest (everyone)", func(): Session.request({"type": "dm_long_rest"})))
	cv.add_child(UIKit.btn("Remove defeated monsters", func(): Session.request({"type": "dm_clear_dead"})))
	cv.add_child(HSeparator.new())
	var selr = UIKit.hbox(4)
	selr.add_child(UIKit.expand(UIKit.btn("Select enemies", func(): _select_team("enemy"), "Select every living enemy on the map (then damage, roll saves or add conditions to all of them)")))
	selr.add_child(UIKit.expand(UIKit.btn("Select party", func(): _select_team("party"), "Select every living party member")))
	cv.add_child(selr)
	hidden_lbl = UIKit.lbl("", 13, UIKit.MUTED)
	cv.add_child(hidden_lbl)
	cv.add_child(UIKit.btn("Reveal all hidden monsters", func(): Session.request({"type": "dm_reveal_all"}), "Spring the ambush: every hidden monster appears (and rolls initiative if a fight is on)"))
	cv.add_child(HSeparator.new())
	cv.add_child(UIKit.lbl("Click a token to inspect it: damage, heal, conditions, saves and checks. Ctrl+click selects several. Shift+click moves a token freely. Keys: Delete removes, H hides/reveals, Esc clears.", 13, UIKit.MUTED))
	for l in cv.get_children():
		if l is Label:
			l.autowrap_mode = TextServer.AUTOWRAP_WORD
	# Monsters tab.
	var mv = UIKit.vbox(6)
	mv.name = "Monsters"
	dm_tabs.add_child(UIKit.margin(mv, 6))
	dm_tabs.get_child(1).name = "Monsters"
	var search = UIKit.line("", "Search the bestiary…")
	mv.add_child(search)
	var il = ItemList.new()
	mon_list = il
	UIKit.expand(il, true, true)
	il.custom_minimum_size = Vector2(0, 140)
	mv.add_child(il)
	var fill = func():
		il.clear()
		for m in Data.monsters_sorted():
			if monster_filter == "" or monster_filter in str(m.name).to_lower() or monster_filter in str(m.get("type", "")):
				var i = il.add_item("%sCR %s  %s" % ["★ " if Data.custom_monsters.has(m.id) else "", Data.cr_text(m.cr), m.name])
				il.set_item_metadata(i, m.id)
				il.set_item_tooltip(i, "%s %s, AC %d, HP %d" % [str(m.get("size", "")).capitalize(), m.get("type", ""), int(m.ac), int(m.hp)])
	mon_fill = fill
	fill.call()
	search.text_changed.connect(func(t): monster_filter = t.to_lower(); fill.call())
	il.item_selected.connect(func(i):
		place_mid = il.get_item_metadata(i)
		_set_mode("place_monster"))
	mv.add_child(UIKit.check("Place as ally (party side)", place_ally, func(p): place_ally = p))
	var hc = UIKit.check("Place hidden (ambush: players can't see it)", place_hidden, func(p): place_hidden = p)
	hc.tooltip_text = "Hidden monsters stay off the initiative and can't be targeted until you reveal them."
	mv.add_child(hc)
	var mb = UIKit.hbox()
	mb.add_child(UIKit.expand(UIKit.btn("＋ New…", func(): _open_monster_editor({}), "Create a new monster")))
	mb.add_child(UIKit.expand(UIKit.btn("Edit / copy…", func():
		if place_mid != "":
			_open_monster_editor(_editor_template(place_mid)), "Edit the selected custom monster, or copy a bestiary monster to customise it")))
	mv.add_child(mb)
	# Map tab.
	var mpv = UIKit.vbox(6)
	var msc = UIKit.scroll(UIKit.margin(mpv, 6))
	msc.name = "Map"
	dm_tabs.add_child(msc)
	var gen_btn = UIKit.btn("🗺 Generate encounter map…", _open_map_generator, "Build a map from terrain, environment and party settings, with recommended monsters. Select characters first (Ctrl+click) to build for just them.")
	gen_btn.add_theme_color_override("font_color", UIKit.GOLD)
	mpv.add_child(gen_btn)
	mpv.add_child(HSeparator.new())
	mpv.add_child(UIKit.lbl("Paint terrain (drag on the map):", 13, UIKit.MUTED))
	var grid = GridContainer.new()
	grid.columns = 2
	for p in [[EngineBase.FLOOR, "Floor"], [EngineBase.WALL, "Wall"], [EngineBase.DIFFICULT, "Difficult"], [EngineBase.WATER, "Water"], [EngineBase.PIT, "Pit / chasm"], [-1, "Start points"]]:
		var val: int = p[0]
		grid.add_child(UIKit.expand(UIKit.btn(p[1], func():
			if val < 0:
				_set_mode("spawn")
			else:
				paint_value = val
				_set_mode("paint"))))
	mpv.add_child(grid)
	var bh = UIKit.hbox()
	bh.add_child(UIKit.lbl("Brush", 13, UIKit.MUTED))
	bh.add_child(UIKit.option([[1, "1×1"], [2, "2×2"], [3, "3×3"]], 1, func(v): brush = v))
	mpv.add_child(bh)
	mpv.add_child(UIKit.option([["stone", "Theme: Dungeon stone"], ["cave", "Theme: Cave"], ["forest", "Theme: Forest"], ["tavern", "Theme: Tavern"], ["snow", "Theme: Snow"], ["swamp", "Theme: Swamp"], ["ruins", "Theme: Ruins / graveyard"], ["badlands", "Theme: Badlands / mountain"]], Session.state.get("theme", "stone"), func(id): Session.request({"type": "dm_theme", "theme": id})))
	var rs = UIKit.hbox()
	var ws = UIKit.spin(8, 80, Session.state.w)
	var hs = UIKit.spin(8, 60, Session.state.h)
	rs.add_child(ws)
	rs.add_child(hs)
	rs.add_child(UIKit.btn("Resize", func(): Session.request({"type": "dm_resize", "w": int(ws.value), "h": int(hs.value)})))
	mpv.add_child(rs)
	mpv.add_child(UIKit.lbl("Background image:", 13, UIKit.MUTED))
	var bgr = UIKit.hbox()
	bgr.add_child(UIKit.expand(UIKit.btn("Upload image…", func(): bg_dialog.popup_centered_ratio(0.7))))
	bgr.add_child(UIKit.expand(UIKit.btn("Remove", func(): Session.request({"type": "dm_background", "key": ""}))))
	mpv.add_child(bgr)
	mpv.add_child(UIKit.check("Fit grid height to the image", bg_fit, func(p): bg_fit = p))
	mpv.add_child(UIKit.btn("Clear terrain", func(): Session.request({"type": "dm_clear_map"})))
	# Fog of war.
	mpv.add_child(HSeparator.new())
	mpv.add_child(UIKit.lbl("Fog of war", 14, UIKit.GOLD))
	var fs: Dictionary = Fog.settings(Session.state)
	fog_mode_opt = UIKit.option([["off", "Off: players see everything"], ["soft", "Soft: terrain visible, creatures hidden"], ["hard", "Hard: unexplored ground hidden"]], fs.mode,
		func(id): Session.request({"type": "dm_fog", "mode": id}))
	fog_mode_opt.fit_to_longest_item = false
	fog_mode_opt.tooltip_text = "Soft: players see the whole map but only the creatures their side can see.\nHard: ground nobody in the party has seen stays black until someone sees it."
	mpv.add_child(fog_mode_opt)
	fog_range_opt = UIKit.option([[0, "Sight: unlimited (bright light)"], [30, "Sight: 30 ft (dark)"], [60, "Sight: 60 ft (dim / dark)"], [90, "Sight: 90 ft"], [120, "Sight: 120 ft"]], fs.range,
		func(id): Session.request({"type": "dm_fog", "range": id}))
	fog_range_opt.fit_to_longest_item = false
	fog_range_opt.tooltip_text = "How far creatures see. In the dark, darkvision (and blindsight, tremorsense, truesight) reaches further."
	mpv.add_child(fog_range_opt)
	fog_shared_chk = UIKit.check("Party shares vision", fs.shared, func(p): Session.request({"type": "dm_fog", "shared": p}))
	fog_shared_chk.tooltip_text = "On: every player sees what any party member sees.\nOff: each player sees only what their own characters see."
	mpv.add_child(fog_shared_chk)
	var pvc = UIKit.check("Preview the players' view", fog_preview, func(p):
		fog_preview = p
		_update_fog()
		_sync_tokens([])
		_refresh_ui())
	pvc.tooltip_text = "Look through the party's eyes. Off, you see everything and the party's blind spots are shaded."
	mpv.add_child(pvc)
	var fb = UIKit.hbox(4)
	fb.add_child(UIKit.expand(UIKit.btn("Reveal brush", func():
		paint_value = FOG_REVEAL
		_set_mode("paint"), "Drag over the map to reveal ground to the players (hard fog)")))
	fb.add_child(UIKit.expand(UIKit.btn("Re-fog brush", func():
		paint_value = FOG_HIDE
		_set_mode("paint"), "Drag over the map to hide explored ground again")))
	mpv.add_child(fb)
	var fa = UIKit.hbox(4)
	fa.add_child(UIKit.expand(UIKit.btn("Reveal map", func(): Session.request({"type": "dm_fog_reveal"}), "Reveal the whole map's terrain to the players")))
	fa.add_child(UIKit.expand(UIKit.btn("Re-fog map", func(): Session.request({"type": "dm_fog_reset"}), "The party forgets everything it has explored (they still see what's in sight now)")))
	mpv.add_child(fa)
	mpv.add_child(HSeparator.new())
	var mname = UIKit.line(str(Session.state.get("name", "map")), "Map name")
	map_name_edit = mname
	mpv.add_child(mname)
	mpv.add_child(UIKit.btn("Save map + monsters", func():
		var nm: String = mname.text.strip_edges()
		if nm.validate_filename() == "" or nm == "":
			_flash("Give the map a name first.")
			return
		var snap = Session.map_snapshot()
		snap.name = nm
		var existed: bool = nm.validate_filename() in CharacterStore.list_maps()
		CharacterStore.save_map(nm, snap)
		_fill_maps(nm.validate_filename())
		_flash(("Map overwritten: " if existed else "Map saved: ") + nm), "Saves terrain, start points, theme, background and every living monster (hidden ones too)"))
	var lh = UIKit.hbox()
	map_pick = OptionButton.new()
	UIKit.expand(map_pick)
	lh.add_child(map_pick)
	lh.add_child(UIKit.btn("Load", func():
		if map_pick.selected < 0:
			return
		var m = CharacterStore.load_map(str(map_pick.get_item_metadata(map_pick.selected)))
		if m.is_empty():
			_flash("That map could not be read.")
			return
		Session.request({"type": "dm_load_map", "map": m}), "Load the map. Monsters on the current map are replaced; characters move to the start points."))
	mpv.add_child(lh)
	_fill_maps("")
	# Party tab.
	var pv = UIKit.vbox(6)
	var psc = UIKit.scroll(UIKit.margin(pv, 6))
	psc.name = "Party"
	dm_tabs.add_child(psc)
	party_box = pv
	_wrap_texts(dm_tabs)
	_refresh_dm()

func _open_monster_editor(tpl: Dictionary) -> void:
	var ed = MonsterEditorScript.new(tpl)
	ed.saved.connect(func(id):
		place_mid = id
		if mon_fill.is_valid():
			mon_fill.call()
		_flash("Monster saved: " + str(Data.monster(id).get("name", id))))
	ed.deleted.connect(func(_id):
		place_mid = ""
		if mon_fill.is_valid():
			mon_fill.call())
	ui.add_child(ed)

## The encounter map generator, building for the selected characters (or everyone on the map).
func _open_map_generator() -> void:
	for ch in ui.get_children():
		if ch is MapGeneratorPanel:
			ch.close()
	var pcs: Array = []
	for cid in _selection():
		if _find(cid).get("kind", "") == "pc":
			pcs.append(cid)
	var gen = MapGeneratorPanel.new(pcs)
	gen.applied.connect(func(nm):
		_flash("Generated map loaded: " + nm)
		if map_name_edit:
			map_name_edit.text = nm)
	gen.saved.connect(func(nm):
		_fill_maps(nm)
		_flash("Map saved: " + nm))
	ui.add_child(gen)

func _editor_template(mid: String) -> Dictionary:
	var src: Dictionary = Data.monster(mid).duplicate(true)
	if not Data.custom_monsters.has(mid):
		src.erase("id")
		src.name = str(src.get("name", "")) + " (custom)"
	return src

func _on_bg_file(path: String) -> void:
	var key = CharacterStore.import_background(path)
	if key == "":
		_flash("Could not read that image.")
		return
	Session.request({"type": "dm_background", "key": key, "fit": bg_fit})

## Refill the saved-maps list, selecting `pick` (or the first map).
func _fill_maps(pick: String) -> void:
	if map_pick == null:
		return
	map_pick.clear()
	var maps = CharacterStore.list_maps()
	for i in maps.size():
		map_pick.add_item(maps[i], i)
		map_pick.set_item_metadata(i, maps[i])
		if maps[i] == pick:
			map_pick.select(i)
	if maps.is_empty():
		map_pick.add_item("(no saved maps)", 0)
		map_pick.set_item_metadata(0, "")
		map_pick.disabled = true
	else:
		map_pick.disabled = false

func _select_team(team: String) -> void:
	var ids: Array = []
	for c in Session.state.combatants.values():
		if c.team == team and Session.engine.alive(c) and not (c.kind != "pc" and c.hp <= 0):
			ids.append(c.id)
	selected_cid = ids[0] if not ids.is_empty() else ""
	selected_ids = ids.slice(1)
	_refresh_ui()

func _refresh_dm() -> void:
	if dm_tabs == null or party_box == null:
		return
	var fo = get_viewport().gui_get_focus_owner()
	if fo != null and party_box.is_ancestor_of(fo) and (fo is SpinBox or fo is LineEdit):
		return  # don't rebuild under the DM's fingers
	var pv: VBoxContainer = party_box
	UIKit.clear(pv)
	# Advancement: XP or milestones, chosen by the DM.
	pv.add_child(UIKit.lbl("Advancement", 14, UIKit.GOLD))
	var adv: String = Session.advancement()
	var ao = UIKit.option([["milestone", "Milestones (you grant levels)"], ["xp", "Experience points"]], adv, func(id): Session.request({"type": "dm_advancement", "mode": id}))
	ao.fit_to_longest_item = false
	ao.tooltip_text = "Milestones: you decide when the party levels. XP: award experience and characters level when they reach the PHB thresholds."
	pv.add_child(ao)
	var who := "selected characters" if _selection().any(func(id): return _find(id).get("kind", "") == "pc") else "the whole party"
	if adv == "xp":
		var xr = UIKit.hbox(4)
		var xs = UIKit.spin(-100000, 100000, dm_xp_amount, func(v): dm_xp_amount = int(v), 25)
		xs.update_on_text_changed = true
		xs.suffix = "XP"
		UIKit.expand(xs)
		xr.add_child(xs)
		xr.add_child(UIKit.check("split", dm_xp_split, func(p): dm_xp_split = p))
		pv.add_child(xr)
		pv.add_child(UIKit.btn("Award XP to %s" % who, func(): Session.request(_pc_req({"type": "dm_xp", "amount": dm_xp_amount, "split": dm_xp_split})),
			"Give this much XP (split: divided evenly) to the selected characters, or to every party member if none are selected. Negative numbers take XP away."))
		var kill_xp: int = Session.encounter_xp() if Session.is_server() else 0
		var kb = UIKit.btn("Award defeated foes' XP (%d)" % kill_xp, func(): Session.request({"type": "dm_award_encounter"}),
			"Adds up the XP of every defeated enemy not yet counted and splits it among the party members still standing.")
		kb.disabled = kill_xp <= 0
		pv.add_child(kb)
	pv.add_child(UIKit.btn("⬆ Grant a level to %s" % who, func(): Session.request(_pc_req({"type": "dm_grant_level"})),
		"Lets each character take one more level. Players then level up from their character sheet (outside combat)."))
	# Party roster with levels and sheets.
	pv.add_child(HSeparator.new())
	pv.add_child(UIKit.lbl("Party", 14, UIKit.GOLD))
	for c in Session.state.combatants.values():
		if c.kind != "pc" or not Session.sheets.has(c.id):
			continue
		var sh: Dictionary = Session.sheets[c.id]
		var row = UIKit.hbox(4)
		var info := "%s  L%d" % [c.name, Rules.total_level(sh)]
		if adv == "xp":
			info += "  ·  %s XP" % CharacterSheet._thousands(int(sh.get("xp", 0)))
		var pend: int = Session.pending_levels(c.id)
		if pend > 0:
			info += "  ·  ⬆%d" % pend
		var il = UIKit.lbl(info, 13, UIKit.GOOD if pend > 0 else UIKit.INK)
		il.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		UIKit.expand(il)
		row.add_child(il)
		var cid: String = c.id
		row.add_child(UIKit.btn("Sheet", func(): _open_sheet(cid), "Open %s's character sheet" % c.name))
		pv.add_child(row)
	pv.add_child(HSeparator.new())
	pv.add_child(UIKit.lbl("Connected players", 14, UIKit.GOLD))
	for pid in Session.players:
		pv.add_child(UIKit.lbl("• %s%s" % [Session.players[pid].name, "" if int(pid) == 1 else "  (peer %s)" % str(pid)], 14))
	pv.add_child(HSeparator.new())
	pv.add_child(UIKit.lbl("Add a character you control:", 13, UIKit.MUTED))
	var chars = CharacterStore.list_characters() + CharacterStore.premades()
	var items: Array = []
	for i in chars.size():
		items.append([i, str(chars[i].name)])
	var sel = [0]
	if not items.is_empty():
		pv.add_child(UIKit.option(items, 0, func(id): sel[0] = id))
		pv.add_child(UIKit.btn("Add to map", func(): Session.request({"type": "dm_place_character", "ch": chars[sel[0]]})))
	_wrap_texts(pv)

## A DM request aimed at the selected PCs (none selected: the server uses the whole party).
func _pc_req(req: Dictionary) -> Dictionary:
	var ids: Array = _selection().filter(func(id): return _find(id).get("kind", "") == "pc")
	if not ids.is_empty():
		req.cids = ids
	return req

# ================================================================ character sheets & levelling

## Can this peer read that creature's sheet? Party members read each other's; the DM reads everyone's.
func _can_view_sheet(c: Dictionary) -> bool:
	return not c.is_empty() and c.kind == "pc" and Session.sheets.has(c.id) and (Session.is_dm() or c.team == "party" or _can_control(c))

## This machine's saved copy of the character (with its history), if there is one.
func _local_copy(cid: String) -> Dictionary:
	var sh: Dictionary = Session.sheets.get(cid, {})
	if str(sh.get("id", "")) == "":
		return {}
	return CharacterStore.get_character(str(sh.id))

func _sheet_opts(cid: String) -> Dictionary:
	var c: Dictionary = Session.engine.C(cid)
	var mine := _can_control(c)
	var local := _local_copy(cid) if mine else {}
	return {"live": c, "editable": mine, "advancement": Session.advancement(), "history": local.get("history", []),
		"pending": Session.pending_levels(cid), "history_remote": mine and int(c.get("owner", 1)) != Session.my_peer()}

func _open_sheet(cid: String) -> CharacterSheet:
	var c: Dictionary = Session.engine.C(cid)
	if not _can_view_sheet(c):
		_flash("You can only read the sheets of party members.")
		return null
	if is_instance_valid(sheet_win):
		sheet_win.close()
	sheet_cid = cid
	sheet_win = CharacterSheet.new(Session.sheets[cid], _sheet_opts(cid))
	sheet_win.level_up_requested.connect(func(): _open_level_up(cid))
	sheet_win.plan_changed.connect(func(plan): _send_plan(cid, plan))
	sheet_win.restore_requested.connect(func(i): _confirm_restore(cid, i))
	ui.add_child(sheet_win)
	return sheet_win

## Opens the guided level-up for a PC this peer controls. `force` (tests) opens it without a pending level.
func _open_level_up(cid: String, force := false) -> LevelUpWizard:
	var c: Dictionary = Session.engine.C(cid)
	if not _can_control(c) or not Session.sheets.has(cid):
		return null
	if not force:
		if Session.pending_levels(cid) <= 0 and not Session.is_dm():
			_flash("No level to take yet: %s" % ("earn more XP." if Session.advancement() == "xp" else "the DM grants levels."))
			return null
		if Session.state.in_combat and not Session.is_dm():
			_flash("Level up after the fight. (Levels change outside combat.)")
			return null
	if is_instance_valid(level_win):
		level_win.close()
	var base: Dictionary = Session.sheets[cid].duplicate(true)
	level_win = LevelUpWizard.new(base)
	level_win.finished.connect(func(new_sheet, label): Session.request({"type": "set_sheet", "cid": cid, "sheet": Progression.strip_history(new_sheet), "label": label}))
	ui.add_child(level_win)
	return level_win

func _send_plan(cid: String, plan: Array) -> void:
	if not Session.sheets.has(cid):
		return
	var sh: Dictionary = Session.sheets[cid].duplicate(true)
	sh.level_plan = plan
	Session.request({"type": "set_sheet", "cid": cid, "sheet": sh, "label": ""})

func _confirm_restore(cid: String, index: int) -> void:
	var local := _local_copy(cid)
	var hist: Array = local.get("history", [])
	if index < 0 or index >= hist.size():
		_flash("That backup isn't on this computer.")
		return
	var entry: Dictionary = hist[index]
	var dlg = ConfirmationDialog.new()
	dlg.title = "Restore an earlier sheet?"
	dlg.dialog_text = "Restore \"%s\" (level %d: %s)?\nThe current sheet is backed up first, so you can undo this." % [entry.get("label", "backup"), int(entry.get("level", 0)), entry.get("summary", "")]
	dlg.dialog_autowrap = true
	dlg.min_size = Vector2i(460, 0)
	dlg.confirmed.connect(func():
		var back: Dictionary = Progression.restore(local, index)
		# Restoring saves the current version as a backup; the store handler makes that backup.
		back.history = hist
		Session.request({"type": "set_sheet", "cid": cid, "sheet": Progression.strip_history(back), "label": "Before restoring \"%s\"" % entry.get("label", "backup")}))
	dlg.canceled.connect(dlg.queue_free)
	dlg.confirmed.connect(dlg.queue_free)
	ui.add_child(dlg)
	dlg.popup_centered()

func _on_sheets_changed() -> void:
	if is_instance_valid(sheet_win) and Session.sheets.has(sheet_cid):
		sheet_win.rebuild(Session.sheets[sheet_cid], _sheet_opts(sheet_cid))
	# Tell a player when one of their characters can level up.
	for cid in Session.sheets:
		var c: Dictionary = Session.engine.C(cid)
		if c.is_empty() or not _can_control(c) or (Session.is_dm() and int(c.owner) != 1):
			continue
		var allowed: int = Progression.allowed_level(Session.sheets[cid], Session.advancement())
		if Session.pending_levels(cid) > 0 and int(_announced_levels.get(cid, 0)) < allowed:
			_announced_levels[cid] = allowed
			_show_banner("Level up available: " + str(c.name))
			Sfx.play("nat20", 0.0)
	_refresh_ui()
	_refresh_dm()

# ================================================================ state sync & events

func _on_state(events: Array) -> void:
	map_view.set_state(Session.state)
	_update_fog()
	_sync_tokens(events)
	event_queue.append_array(events)
	if not playing:
		_play_events()
	_refresh_ui()

func _sync_tokens(events: Array) -> void:
	var moving = {}
	for e in events:
		if e.get("t", "") in ["move", "teleport"]:
			moving[e.cid] = true
	var seen = {}
	var shown: Array = Session.state.combatants.values()
	# The DM also sees hidden monsters, as faint ghosts.
	if Session.is_dm():
		shown += Session.state.get("reserve", {}).values()
	for c in shown:
		seen[c.id] = true
		var tk = tokens.get(c.id)
		if tk == null:
			tk = TokenScript.new()
			tk.cid = c.id
			tokens_root.add_child(tk)
			tokens[c.id] = tk
			tk.position = _token_pos(c)
		tk.setup(c)
		if _is_hidden(c.id):
			tk.modulate.a = 0.35
			tk.visible = not fog_preview
		else:
			tk.visible = _seen(c)
		if not moving.has(c.id) and not playing:
			tk.position = _token_pos(c)
	for id in tokens.keys():
		if not seen.has(id):
			tokens[id].queue_free()
			tokens.erase(id)

## Fog of war for this screen. Players see what their side (or, with vision not shared, their own
## characters) can see; the DM sees everything, with the party's blind spots shaded, unless previewing.
func _update_fog() -> void:
	var eng: CombatEngine = Session.engine
	if Session.is_dm():
		var party: Dictionary = Fog.view_for(eng, 0)
		fog_view = party if fog_preview else {}
		map_view.fog = party
		map_view.fog_dm = not fog_preview
	else:
		fog_view = Fog.view_for(eng, Session.my_peer())
		map_view.fog = fog_view
		map_view.fog_dm = false
	map_view.queue_redraw()
	# Players lose sight of (and their selection of) a creature that slips into the fog.
	if not fog_view.is_empty() and selected_cid != "" and not _seen(_find(selected_cid)):
		selected_cid = ""

## Whether this screen may show creature c (always true with no fog).
func _seen(c: Dictionary) -> bool:
	return c.is_empty() or Fog.sees(fog_view, Session.engine, c)

func _play_events() -> void:
	playing = true
	while not event_queue.is_empty():
		var e: Dictionary = event_queue.pop_front()
		match e.get("t", ""):
			"log":
				log_rt.append_text("\n" + str(e.text))
			"move":
				var tk = tokens.get(e.cid)
				if tk:
					var tw = create_tween()
					var step_n = 0
					for p in e.path:
						if step_n % 2 == 0:
							tw.tween_callback(Sfx.play.bind("step", 0.15))
						step_n += 1
						tw.tween_property(tk, "position", Vector2(p) * CELL, 0.08)
					await tw.finished
			"teleport":
				var tk2 = tokens.get(e.cid)
				if tk2:
					Sfx.play("teleport")
					var tw2 = create_tween()
					tw2.tween_property(tk2, "modulate:a", 0.0, 0.12)
					tw2.tween_callback(func(): tk2.position = Vector2(e.to) * CELL)
					tw2.tween_property(tk2, "modulate:a", 1.0, 0.12)
					await tw2.finished
			"float":
				_spawn_float(e)
				Sfx.play(_float_sfx(e))
				await get_tree().create_timer(0.12).timeout
			"fx":
				var snd = str(e.get("sfx", _fx_sfx(e)))
				Sfx.play(snd)
				# Projectiles hold the next event (usually the damage number) until they land.
				var wait = _spawn_fx(e, snd)
				await get_tree().create_timer(maxf(0.14, wait)).timeout
			"sfx":
				Sfx.play(str(e.get("name", "")))
				var ctk = tokens.get(str(e.get("cid", "")))
				if ctk and e.get("name", "") == "cast":
					Vfx.cast_circle(fx_root, ctk.center(), Color("#c8a0ff"))
	playing = false
	for c in Session.state.combatants.values() + (Session.state.get("reserve", {}).values() if Session.is_dm() else []):
		var tk3 = tokens.get(c.id)
		if tk3:
			tk3.position = _token_pos(c)

## Sound for an fx event the server didn't name one for, guessed from its kind and colour.
func _fx_sfx(e: Dictionary) -> String:
	var col = str(e.get("color", "")).to_lower()
	var by_color = {"#ff7a2a": "fire", "#ff6a2a": "fire", "#9fe6ff": "cold", "#fff07a": "lightning", "#9aff5a": "acid",
		"#6ad04a": "poison", "#8a4ac0": "necrotic", "#fff2a8": "radiant", "#7aa8ff": "thunder", "#ff7ae0": "psychic",
		"#c8a0ff": "force", "#7fdc7f": "heal", "#b38cff": "teleport", "#ff4040": "rage"}
	match e.get("kind", ""):
		"slash":
			return "sword" if col == "#ffffff" else by_color.get(col, "sword")
		"bolt":
			return "bow" if col == "#ffffff" else by_color.get(col, "force")
		_:
			return by_color.get(col, "buff")

## Sound for a floating combat number or label.
func _float_sfx(e: Dictionary) -> String:
	var text = str(e.get("text", ""))
	var col = str(e.get("color", "")).to_lower()
	if text == "Miss": return "miss"
	if text == "Nat 20!": return "nat20"
	if text in ["Down!", "Slain", "Dead"]: return "down" if text == "Down!" else "death"
	if text.begins_with("-"): return "crit" if col == "#ffd166" else "hit"
	if text.begins_with("+"): return "heal"
	if text in ["Relentless!", "Legendary Resistance"]: return "buff"
	if text == "0": return ""
	return "condition"

## Speaker toggle plus volume slider, kept in sync with the Sfx settings.
func _build_volume() -> Control:
	var h = UIKit.hbox(4)
	var mute_btn = UIKit.btn("", func(): Sfx.toggle_muted(), "Sound effects on/off")
	mute_btn.custom_minimum_size = Vector2(40, 0)
	h.add_child(mute_btn)
	var sl = HSlider.new()
	sl.min_value = 0.0
	sl.max_value = 1.0
	sl.step = 0.05
	sl.value = Sfx.volume
	sl.custom_minimum_size = Vector2(90, 0)
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl.tooltip_text = "Sound effects volume"
	sl.value_changed.connect(func(v):
		Sfx.set_volume(v)
		if v > 0.0 and Sfx.muted:
			Sfx.set_muted(false))
	sl.drag_ended.connect(func(_c): Sfx.play("click", 0.0))
	h.add_child(sl)
	var sync = func():
		mute_btn.text = "🔇" if Sfx.muted or Sfx.volume <= 0.0 else "🔊"
		sl.set_value_no_signal(Sfx.volume)
	sync.call()
	Sfx.settings_changed.connect(sync)
	h.tree_exiting.connect(func(): Sfx.settings_changed.disconnect(sync))
	return h

func _spawn_float(e: Dictionary) -> void:
	var tk = tokens.get(e.cid)
	if tk == null or not tk.visible:
		return
	var l = Label.new()
	l.text = e.text
	l.add_theme_font_size_override("font_size", 26)
	l.add_theme_color_override("font_color", Color(e.get("color", "#ffffff")))
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	l.position = tk.position + Vector2(CELL * 0.5 - 20, -10)
	l.z_index = 50
	fx_root.add_child(l)
	var tw = create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y - 50, 1.1)
	tw.tween_property(l, "modulate:a", 0.0, 1.1).set_delay(0.4)
	tw.chain().tween_callback(l.queue_free)
	_float_vfx(e, tk)

## Hit sparks, heal motes and death puffs that go with a floating number or label.
func _float_vfx(e: Dictionary, tk) -> void:
	var text = str(e.get("text", ""))
	var col = str(e.get("color", "")).to_lower()
	var pos: Vector2 = tk.center()
	if text.begins_with("-"):
		var crit = col == "#ffd166"
		var spark = Color("#ffd166") if crit else _last_hit_col
		Vfx.hit(fx_root, pos, spark, crit)
		tk.hit_react(Color(1, 0.3, 0.25), 2.0 if crit else 1.0)
		if crit:
			_shake_camera(8.0)
	elif text.begins_with("+"):
		Vfx.burst(fx_root, pos, Color(col), "heal")
	elif text in ["Down!", "Slain", "Dead"]:
		Vfx.death(fx_root, pos)
	elif text == "Nat 20!":
		Vfx.burst(fx_root, pos, Color("#ffd166"), "radiant")

func _shake_camera(strength: float) -> void:
	var tw = create_tween()
	for i in 6:
		var amt = strength * (1.0 - i / 6.0)
		tw.tween_property(cam, "offset", Vector2(randf_range(-amt, amt), randf_range(-amt, amt)), 0.03)
	tw.tween_property(cam, "offset", Vector2.ZERO, 0.04)

## Pixel centre of whichever token has its top-left on this cell, or of the cell itself.
func _center_at(p) -> Vector2:
	var tk = _token_at(p)
	if tk != null:
		return tk.center()
	return Vector2(Vector2i(Vector2(p))) * CELL + Vector2(CELL, CELL) * 0.5

## The token in cell `p`: whoever stands there, or failing that someone in a Rope Trick above it.
func _token_at(p):
	var cell = Vector2i(Vector2(p))
	var roped = null
	for c in Session.state.combatants.values():
		if Vector2i(Vector2(c.pos)) == cell and tokens.has(c.id):
			if not Session.engine.in_rope(c):
				return tokens[c.id]
			if roped == null:
				roped = tokens[c.id]
	return roped

## Where a creature's token sits. Creatures up in a Rope Trick space are drawn half-size,
## stacked two abreast from the rope's cell upwards.
func _token_pos(c: Dictionary) -> Vector2:
	var base = Vector2(c.pos) * CELL
	var eng: CombatEngine = Session.engine
	if eng == null or not eng.in_rope(c):
		return base
	var i: int = 0
	for o in eng.rope_occupants(eng.rope_space(c)):
		if o.id == c.id:
			break
		i += 1
	return base + Vector2((i % 2) * CELL * 0.5, -(i / 2) * CELL * 0.5)

## Whoever the pointer is on: a creature up in a Rope Trick space if it is over that creature's
## (half-size) token, otherwise whoever stands in `cell`.
func _creature_at_pointer(cell: Vector2i) -> Dictionary:
	var eng: CombatEngine = Session.engine
	var mp = get_global_mouse_position()
	for c in Session.state.combatants.values():
		if eng.in_rope(c) and not c.get("dead", false) and tokens.has(c.id):
			var tk = tokens[c.id]
			if Rect2(tk.position, Vector2.ONE * tk.cells() * CELL * tk.scale.x).has_point(mp) and _seen(c):
				return c
	var o: Dictionary = eng.creature_at(cell)
	return o if _seen(o) else {}

## Draws an fx event. style is the event's sound name ("sword", "bow", "fire"...), which picks the look.
## Returns how long to wait before the next event (a projectile's flight time).
func _spawn_fx(e: Dictionary, style: String) -> float:
	# Nothing to watch when it all happens out of sight.
	var eng: CombatEngine = Session.engine
	if not fog_view.is_empty() and not Fog.cell_visible(fog_view, eng, Vector2i(Vector2(e.from))) and not Fog.cell_visible(fog_view, eng, Vector2i(Vector2(e.to))):
		return 0.0
	var col = Vfx.color_for(style, Color(e.get("color", "#ffffff")))
	var from = _center_at(e.from)
	var to = _center_at(e.to)
	_last_hit_col = col if style in Vfx.MAGIC else Color("#ffcf8a")
	match e.get("kind", ""):
		"slash":
			_lunge(_token_at(e.from), to - from)
			Vfx.melee(fx_root, from, to, style if style in Vfx.MELEE_STYLES or style in Vfx.MAGIC else "sword", col)
			return 0.12
		"bolt":
			return Vfx.projectile(fx_root, from, to, style, col)
		"area":
			var cells: Array = e.get("cells", [])
			if cells.is_empty():
				cells = [e.to]
			Vfx.area(fx_root, to, cells, col, style)
			if cells.size() >= 9:
				_shake_camera(5.0)
		"burst":
			Vfx.burst(fx_root, to, col, style)
	return 0.0

## The attacker steps into its swing and back.
func _lunge(tk, dir: Vector2) -> void:
	if tk == null or dir == Vector2.ZERO:
		return
	var base: Vector2 = tk.position
	var tw = create_tween()
	tw.tween_property(tk, "position", base + dir.normalized() * 14.0, 0.07).set_ease(Tween.EASE_OUT)
	tw.tween_property(tk, "position", base, 0.12).set_ease(Tween.EASE_IN)

# ================================================================ UI refresh

func _can_control(c: Dictionary) -> bool:
	return not c.is_empty() and (Session.is_dm() or int(c.owner) == Session.my_peer())

func _refresh_ui() -> void:
	var eng: CombatEngine = Session.engine
	var st: Dictionary = Session.state
	# Who do I control right now?
	var cur = eng.current()
	if st.in_combat and _can_control(cur):
		control_cid = cur.id
	elif not _can_control(eng.C(control_cid)):
		control_cid = ""
		for c in st.combatants.values():
			if int(c.owner) == Session.my_peer() and not c.dead and (Session.role != "dm" or c.kind == "pc"):
				control_cid = c.id
				break
	if st.in_combat and not cur.is_empty() and cur.id != last_turn_id:
		last_turn_id = cur.id
		if _can_control(cur) and not Session.is_dm() or (Session.is_dm() and cur.kind == "pc" and int(cur.owner) == 1):
			_show_banner("Your turn: " + cur.name)
			Sfx.play("turn", 0.0)
		_cancel_mode()
	# Drop selections of creatures that have gone.
	if selected_cid != "" and _find(selected_cid).is_empty():
		selected_cid = ""
	selected_ids = selected_ids.filter(func(id): return not _find(id).is_empty() and id != selected_cid)
	if selected_cid == "" and not selected_ids.is_empty():
		selected_cid = selected_ids.pop_front()
	if hidden_lbl != null:
		var nh: int = st.get("reserve", {}).size()
		hidden_lbl.text = "%d hidden monster%s waiting" % [nh, "" if nh == 1 else "s"] if nh > 0 else "No hidden monsters"
	if map_name_edit != null and not map_name_edit.has_focus() and str(st.get("name", "")) != map_name_edit.get_meta("shown", ""):
		map_name_edit.set_meta("shown", str(st.get("name", "")))
		map_name_edit.text = str(st.get("name", ""))
	if fog_mode_opt != null:
		# Keep the fog controls in step with the state (a loaded map brings its own settings).
		var fs: Dictionary = Fog.settings(st)
		for i in fog_mode_opt.item_count:
			if fog_mode_opt.get_item_metadata(i) == fs.mode:
				fog_mode_opt.select(i)
		for i in fog_range_opt.item_count:
			if int(fog_range_opt.get_item_metadata(i)) == fs.range:
				fog_range_opt.select(i)
		fog_shared_chk.set_pressed_no_signal(fs.shared)
	title_lbl.text = str(st.get("name", "Dicehollow"))
	round_lbl.text = ("Round %d — %s's turn" % [st.round, cur.get("name", "")]) if st.in_combat else ("Exploration (no combat)" + ("  •  You are the DM" if Session.is_dm() else ""))
	_refresh_initiative()
	_refresh_card()
	_refresh_hotbar()
	_refresh_inspect()
	_refresh_highlights()
	_check_pending_hit()
	if is_instance_valid(sheet_win) and not Session.engine.C(sheet_cid).is_empty():
		sheet_win.update_live(Session.engine.C(sheet_cid), Session.pending_levels(sheet_cid))
	if dm_tabs != null and dm_tabs.current_tab == 3:
		_refresh_dm()

## A weapon hit held for this player's on-hit choices (Divine Smite, Stunning Strike, a maneuver):
## ask one question at a time, then send the answers. Closing a popup counts as "no".
func _check_pending_hit() -> void:
	var p: Dictionary = Session.state.get("pending_hit", {})
	if p.is_empty() or str(p.id) == shown_hit:
		return
	if not _can_control(Session.engine.C(str(p.cid))):
		return
	shown_hit = str(p.id)
	_ask_hit(p, {}, ["smite", "stunning", "maneuvers"])

func _ask_hit(p: Dictionary, picks: Dictionary, left: Array) -> void:
	var ch: Dictionary = p.choices
	while not left.is_empty() and not ch.has(left[0]):
		left = left.slice(1)
	if left.is_empty():
		Session.request({"type": "action", "cid": p.cid, "aid": "hit_choice", "params": picks})
		return
	var key: String = left[0]
	var rest: Array = left.slice(1)
	var t: Dictionary = Session.engine.C(str(p.tid))
	var crit: bool = p.res.get("crit", false)
	var head: String = "%s on %s!" % ["Critical hit" if crit else "Hit", t.get("name", "the target")]
	var items: Array = []
	var pick_key: String = key
	match key:
		"smite":
			items.append([0, "No smite"])
			var extra: int = 1 if str(t.get("type", "")) in ["undead", "fiend"] else 0
			for L in ch.smite:
				var n: int = (mini(5, 1 + int(L)) + extra) * (2 if crit else 1)
				items.append([L, "Divine Smite with a level %d slot: %dd8 radiant" % [L, n]])
		"stunning":
			items.append([false, "No Stunning Strike"])
			items.append([true, "Stunning Strike (1 ki): CON save or stunned"])
		"maneuvers":
			pick_key = "maneuver"
			items.append(["", "No maneuver"])
			for m in ch.maneuvers:
				items.append([m, "%s Attack (1 superiority die)" % str(m).capitalize()])
	var answered := [false]
	var pm = PopupMenu.new()
	pm.add_theme_font_size_override("font_size", 15)
	pm.add_separator(head)
	for i in items.size():
		pm.add_item(str(items[i][1]), i)
	pm.id_pressed.connect(func(id):
		answered[0] = true
		picks[pick_key] = items[id][0]
		_ask_hit(p, picks, rest))
	pm.popup_hide.connect(func():
		pm.queue_free()
		# Dismissed without picking: take the "no" option, after any id_pressed has had its turn.
		(func():
			if not answered[0]:
				answered[0] = true
				picks[pick_key] = items[0][0]
				_ask_hit(p, picks, rest)).call_deferred())
	ui.add_child(pm)
	pm.popup(Rect2i(Vector2i(ui.get_viewport().get_mouse_position()), Vector2i(300, 0)))

func _refresh_initiative() -> void:
	UIKit.clear(init_row)
	var eng: CombatEngine = Session.engine
	var ids: Array = Session.state.order if Session.state.in_combat else Session.state.combatants.keys()
	var cur = eng.current()
	for id in ids:
		var c = eng.C(id)
		if c.is_empty() or (c.dead and not Session.state.in_combat):
			continue
		var is_cur: bool = not cur.is_empty() and cur.id == id
		if not _seen(c):
			# Out of sight in the fog of war: a place in the order, nothing more.
			if not Session.state.in_combat:
				continue
			var up = UIKit.panel(null, Color("#2a2338") if not is_cur else Color("#4a3a68"), UIKit.GOLD if is_cur else UIKit.MUTED)
			up.custom_minimum_size = Vector2(78, 70)
			var ul = UIKit.lbl("?", 26, UIKit.MUTED)
			ul.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			ul.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			up.add_child(ul)
			up.tooltip_text = "Something you can't see"
			init_row.add_child(up)
			continue
		var p = UIKit.panel(null, Color("#2a2338") if not is_cur else Color("#4a3a68"), UIKit.GOLD if is_cur else (UIKit.PARTY if c.team == "party" else UIKit.ENEMY))
		p.custom_minimum_size = Vector2(78, 70)
		var v = UIKit.vbox(1)
		p.add_child(v)
		var tex = CharacterStore.portrait_texture(c.portrait)
		var icon = MonsterIcons.for_combatant(c) if tex == null else null
		if tex or icon:
			var tr = TextureRect.new()
			tr.texture = tex if tex else icon
			if icon:
				tr.modulate = Color(c.color).lightened(0.3)
			tr.custom_minimum_size = Vector2(34, 34)
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			v.add_child(tr)
		else:
			var l = UIKit.lbl(UIKit.initials(c.name), 18, Color(c.color))
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			v.add_child(l)
		var nl = UIKit.lbl(str(c.name).substr(0, 11), 11)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(nl)
		var show_hp: bool = c.team == "party" or Session.is_dm()
		var frac = float(maxi(c.hp, 0)) / maxf(1.0, c.max_hp)
		v.add_child(UIKit.bar(c.hp if show_hp else frac * 100.0, c.max_hp if show_hp else 100.0, UIKit.GOOD if frac > 0.5 else (Color("#e8b84a") if frac > 0.25 else UIKit.BAD), 5))
		if c.dead or c.death.dead:
			p.modulate = Color(0.5, 0.5, 0.5, 0.6)
		var cid: String = c.id
		p.gui_input.connect(func(ev):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				if ev.double_click and _can_view_sheet(Session.engine.C(cid)):
					_open_sheet(cid)
					return
				selected_cid = cid
				_center_on(cid)
				_refresh_ui())
		p.tooltip_text = "%s — initiative %d" % [c.name, int(c.get("init", 0))] if Session.state.in_combat else str(c.name)
		if _can_view_sheet(c):
			p.tooltip_text += "\nDouble-click for the character sheet"
		init_row.add_child(p)

func _refresh_card() -> void:
	UIKit.clear(card_box)
	var c = Session.engine.C(control_cid)
	if c.is_empty():
		card_box.add_child(UIKit.lbl("No character selected.\nClick one of your tokens.", 14, UIKit.MUTED))
		econ_lbl.text = ""
		end_btn.disabled = true
		auto_btn.disabled = true
		return
	var eng: CombatEngine = Session.engine
	var frame = UIKit.panel(null, Color("#0d0b12"), Color(c.color))
	frame.custom_minimum_size = Vector2(96, 96)
	var tex = CharacterStore.portrait_texture(c.portrait)
	if tex and c.form.is_empty():
		var tr = TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		frame.add_child(tr)
	elif MonsterIcons.for_combatant(c):
		var ti = TextureRect.new()
		ti.texture = MonsterIcons.for_combatant(c)
		ti.modulate = Color(c.color).lightened(0.3)
		ti.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ti.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		frame.add_child(ti)
	else:
		var l = UIKit.lbl(UIKit.initials(c.name if c.form.is_empty() else str(c.form.name)), 36, Color(c.color))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		frame.add_child(l)
	# Portrait with the sheet (and level-up) buttons under it.
	var pcol = UIKit.vbox(4)
	frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	pcol.add_child(frame)
	if _can_view_sheet(c):
		var cid: String = c.id
		var sb = UIKit.btn("📜 Sheet", func(): _open_sheet(cid), "Character sheet, features, spells, level plan and history (C)")
		pcol.add_child(sb)
		if _can_control(c) and Session.pending_levels(c.id) > 0:
			var lb = UIKit.btn("⬆ Level up", func(): _open_level_up(cid), "A new level is ready. Opens the guided level-up.")
			lb.add_theme_color_override("font_color", UIKit.GOLD)
			lb.add_theme_stylebox_override("normal", UIKit.sb(Color("#3a2c12"), UIKit.GOLD, 2))
			lb.disabled = Session.state.in_combat and not Session.is_dm()
			if lb.disabled:
				lb.tooltip_text = "Level up after the fight."
			pcol.add_child(lb)
	card_box.add_child(pcol)
	var v = UIKit.vbox(2)
	UIKit.expand(v)
	var vsc = ScrollContainer.new()
	vsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	UIKit.expand(vsc, true, true)
	vsc.add_child(v)
	var nm_l = UIKit.lbl(str(c.name) + ("  (%s)" % c.form.name if not c.form.is_empty() else ""), 17, UIKit.GOLD)
	nm_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(nm_l)
	var hp_txt = "HP %d / %d" % [maxi(c.hp, 0), c.max_hp]
	if c.temp_hp > 0: hp_txt += "  +%d temp" % c.temp_hp
	if not c.form.is_empty(): hp_txt += "  (beast %d/%d)" % [c.form.hp, c.form.max_hp]
	v.add_child(UIKit.lbl(hp_txt, 14))
	v.add_child(UIKit.bar(maxi(c.hp, 0), c.max_hp, UIKit.GOOD, 8))
	var info = "AC %d   Speed %d ft" % [eng.eff_ac(c), eng.eff_speed(c)]
	if not c.get("hd_max", {}).is_empty():
		var left: Dictionary = eng.hit_dice_left(c)
		var hd: PackedStringArray = []
		for k in c.hd_max:
			hd.append("%d/%dd%s" % [int(left.get(k, 0)), int(c.hd_max[k]), k])
		info += "   HD " + " ".join(hd)
	if not c.conc.is_empty():
		info += "   ◈ " + str(c.conc.name)
	var info_l = UIKit.lbl(info, 13, UIKit.MUTED)
	info_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(info_l)
	var res_txt = ""
	if c.slots_max.size() > 0:
		var parts: PackedStringArray = []
		for i in c.slots_max.size():
			if int(c.slots_max[i]) > 0:
				parts.append("L%d %s" % [i + 1, "●".repeat(int(c.slots_max[i]) - int(c.slots_used[i])) + "○".repeat(int(c.slots_used[i]))])
		res_txt += "  ".join(parts)
	if c.pact_max > 0:
		res_txt += "  Pact L%d %s" % [c.pact_level, "●".repeat(c.pact_max - c.pact_used) + "○".repeat(c.pact_used)]
	if res_txt != "":
		var sl_l = UIKit.lbl(res_txt.strip_edges(), 12, Color("#c8a0ff"))
		sl_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(sl_l)
	var rparts: PackedStringArray = []
	for k in c.resources:
		var r: Dictionary = c.resources[k]
		if not k.begins_with("innate_"):
			rparts.append("%s %d/%d" % [r.name, r.cur, r.max])
	if not rparts.is_empty():
		var rl = UIKit.lbl(", ".join(rparts), 12, Color("#ffd166"))
		rl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(rl)
	var conds: PackedStringArray = []
	for e in c.effects:
		if e.get("name", "") != "":
			conds.append(str(e.name))
	if c.kind == "pc" and c.hp <= 0 and not c.death.dead:
		conds.append("Dying (✓%d ✗%d)" % [c.death.s, c.death.f])
	if not conds.is_empty():
		var cl = UIKit.lbl(", ".join(conds), 12, Color("#e0a0ff"))
		cl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(cl)
	card_box.add_child(vsc)
	# Economy.
	var my_turn = eng.is_turn_of(c)
	var t: Dictionary = c.get("turn", {})
	if Session.state.in_combat:
		var dot = func(on: bool, col: String) -> String: return "[color=%s]●[/color]" % (col if on else "#444")
		var extra := ""
		if int(t.get("attacks", 0)) > 0:
			extra += "\nAttacks left: %d" % int(t.attacks)
		if my_turn and int(t.get("haste_action", 0)) > 0 and eng.has_tag(c, "haste"):
			extra += "\n[color=#7fdcff]● Haste action[/color] (1 attack, Dash, Disengage, Hide)"
		if my_turn and eng.has_cond(c, "prone") and c.hp > 0:
			extra += "\n[color=#e0c060]Prone: standing costs %d ft%s[/color]" % [eng.stand_cost(c), "" if eng.can_stand(c) else " (crawling)"]
		if my_turn and t.get("speed_zero", false):
			extra += "\n[color=#ff9c8f]Speed 0 for the rest of the turn[/color]"
		elif my_turn and eng.eff_speed(c) == 0:
			extra += "\n[color=#ff9c8f]Speed 0[/color]"
		econ_lbl.text = "%s Action   %s Bonus\n%s Reaction\n[color=#8fd0ff]Move %d ft[/color]%s%s" % [
			dot.call(int(t.get("action", 0)) > 0 or int(t.get("attacks", 0)) > 0, "#5cc892"), dot.call(int(t.get("bonus", 0)) > 0, "#ffb347"),
			dot.call(t.get("reaction", true), "#c8a0ff"), eng.move_left(c) if my_turn else 0,
			(" (dashed ×%d)" % int(t.dashes)) if my_turn and int(t.get("dashes", 0)) > 0 else "", extra]
	else:
		econ_lbl.text = "[color=#a59cb5]Out of combat:\nmove and act freely.[/color]"
	end_btn.disabled = not (Session.state.in_combat and my_turn)
	auto_btn.disabled = not (Session.state.in_combat and my_turn)

func _refresh_hotbar() -> void:
	UIKit.clear(hotbar)
	for b in cat_row.get_children():
		b.button_pressed = b.get_meta("cat") == hot_cat
	var c = Session.engine.C(control_cid)
	if c.is_empty():
		return
	var actions = Session.engine.get_actions(c)
	var order = {"attack": 0, "spell": 1, "feature": 2, "toggle": 3, "basic": 4}
	actions.sort_custom(func(a, b): return [order.get(a.cat, 9), int(a.get("level", 0)), a.name] < [order.get(b.cat, 9), int(b.get("level", 0)), b.name])
	for a in actions:
		var cat: String = a.cat
		if hot_cat != "all" and cat != hot_cat and not (hot_cat == "feature" and cat == "toggle"):
			continue
		var txt: String = a.name
		if cat == "spell":
			txt = ("◇ " if int(a.level) == 0 else "L%d " % int(a.level)) + txt
		if a.cost == "bonus": txt += "  ◐"
		if a.kind == "toggle":
			txt += ": " + (a.value_text if a.value_text != "" else ("ON" if a.on else "off"))
		var b = Button.new()
		b.text = txt
		b.custom_minimum_size = Vector2(0, 34)
		var col: Color = CAT_COLORS.get(cat, Color.GRAY)
		var on: bool = a.kind == "toggle" and a.get("on", false)
		b.add_theme_stylebox_override("normal", UIKit.sb(col.darkened(0.55 if not on else 0.1), col, 1 if not on else 2, 5, 8))
		b.add_theme_stylebox_override("hover", UIKit.sb(col.darkened(0.3), Color.WHITE, 1, 5, 8))
		b.add_theme_stylebox_override("pressed", UIKit.sb(col, Color.WHITE, 2, 5, 8))
		b.add_theme_stylebox_override("disabled", UIKit.sb(Color("#1a1722"), Color("#2e2a38"), 1, 5, 8))
		b.disabled = not a.enabled and a.kind != "toggle"
		var tipt = "%s\n%s" % [a.name, a.desc]
		if a.cost != "free":
			tipt += "\nCost: %s" % {"attack": "one attack (uses your action)", "action": "action", "bonus": "bonus action", "reaction": "reaction", "haste": "Haste action", "free": "free (uses movement)" if a.id == "stand" else "free"}.get(a.cost, a.cost)
		if int(a.get("range", 0)) > 0:
			tipt += "   Range: %d ft" % int(a.range)
		if a.get("concentration", false):
			tipt += "   (Concentration)"
		if not a.enabled and a.reason != "":
			tipt += "\n[%s]" % a.reason
		b.tooltip_text = tipt
		var act: Dictionary = a
		b.pressed.connect(func(): _on_action_pressed(act))
		hotbar.add_child(b)

## A creature on the map, or (for the DM) one hidden from the players.
func _find(cid: String) -> Dictionary:
	var c: Dictionary = Session.engine.C(cid)
	if c.is_empty() and Session.is_dm():
		c = Session.state.get("reserve", {}).get(cid, {})
	return c

func _is_hidden(cid: String) -> bool:
	return Session.state.get("reserve", {}).has(cid)

## The DM's current selection (Ctrl+click adds and removes creatures), primary first.
func _selection() -> Array:
	var out: Array = []
	for id in [selected_cid] + selected_ids:
		if id != "" and not id in out and not _find(id).is_empty():
			out.append(id)
	return out

func _sel_req(req: Dictionary) -> Dictionary:
	req.cids = _selection()
	return req

func _refresh_inspect() -> void:
	# Don't rebuild under the DM's fingers while they are typing a number or a name.
	var fo = get_viewport().gui_get_focus_owner()
	if fo != null and inspect_box.is_ancestor_of(fo) and (fo is LineEdit or fo is SpinBox) and _inspect_key == _selection_key():
		return
	_inspect_key = _selection_key()
	UIKit.clear(inspect_box)
	# Long names, summaries and check boxes wrap inside the column instead of widening it.
	_wrap_texts.call_deferred(inspect_box)
	var eng: CombatEngine = Session.engine
	var dm = Session.is_dm()
	var sel := _selection()
	var c = _find(selected_cid)
	if c.is_empty():
		inspect_box.add_child(UIKit.lbl("Click a token to inspect it." + ("\nCtrl+click to select several." if dm else ""), 14, UIKit.MUTED))
		return
	if sel.size() > 1:
		var names: PackedStringArray = []
		for id in sel:
			var o = _find(id)
			names.append("%s (%d/%d)" % [o.name, maxi(int(o.hp), 0), int(o.max_hp)])
		inspect_box.add_child(UIKit.lbl("%d creatures selected" % sel.size(), 18, UIKit.GOLD))
		var nl = UIKit.lbl(", ".join(names), 12, UIKit.MUTED)
		nl.autowrap_mode = TextServer.AUTOWRAP_WORD
		inspect_box.add_child(nl)
	else:
		inspect_box.add_child(UIKit.lbl(str(c.name) + ("  (hidden)" if _is_hidden(c.id) else ""), 18, UIKit.GOLD))
		var sm = UIKit.lbl(str(c.summary), 12, UIKit.MUTED)
		sm.autowrap_mode = TextServer.AUTOWRAP_WORD
		inspect_box.add_child(sm)
		if _can_view_sheet(c):
			var scid: String = c.id
			var shb = UIKit.btn("📜 Character sheet", func(): _open_sheet(scid), "Read the full sheet: abilities, skills, features, spells and level plan")
			if _can_control(c) and Session.pending_levels(c.id) > 0:
				shb.text = "📜 Character sheet  ·  ⬆ level up ready"
				shb.add_theme_color_override("font_color", UIKit.GOLD)
			inspect_box.add_child(shb)
		var see: bool = dm or c.team == "party"
		if see:
			var hp_line := "HP %d/%d%s   AC %d   Speed %d" % [maxi(c.hp, 0), c.max_hp, (" +%d" % c.temp_hp) if c.temp_hp > 0 else "", eng.eff_ac(c), eng.eff_speed(c)]
			if Session.state.in_combat and c.id in Session.state.order:
				hp_line += "   Init %d" % int(c.get("init", 0))
			inspect_box.add_child(UIKit.lbl(hp_line, 14))
			if c.kind == "pc" and c.hp <= 0 and not c.death.get("dead", false):
				inspect_box.add_child(UIKit.lbl("Dying: ✓%d  ✗%d%s" % [c.death.s, c.death.f, "  (stable)" if c.death.get("stable", false) else ""], 13, Color("#ff9c8f")))
		else:
			var frac = float(c.hp) / maxf(1.0, c.max_hp)
			inspect_box.add_child(UIKit.lbl("Condition: " + ("Unhurt" if frac >= 1.0 else ("Wounded" if frac > 0.5 else ("Bloodied" if frac > 0.25 else ("Near death" if c.hp > 0 else "Down")))), 14))
		var ab: PackedStringArray = []
		for a in Data.ABILITIES:
			ab.append("%s %d" % [a.to_upper(), int(c.scores.get(a, 10))])
		inspect_box.add_child(UIKit.lbl("  ".join(ab), 11, UIKit.MUTED))
		if see and int(c.get("passive", 0)) > 0:
			inspect_box.add_child(UIKit.lbl("Passive Perception %d" % int(c.passive), 11, UIKit.MUTED))
		for e in c.effects:
			if e.get("name", "") != "":
				inspect_box.add_child(UIKit.lbl("• %s%s" % [e.name, (" (%d rd)" % int(e.rounds)) if int(e.get("rounds", 0)) < 100 else ""], 12, Color("#e0a0ff")))
		if c.kind == "monster" and see:
			var txt = ""
			for a in c.attacks:
				txt += "[b]%s[/b] %s\n" % [a.name, eng._weapon_desc(a)]
			for a in c.mactions:
				txt += "[b]%s[/b] %s\n" % [a.name, a.get("desc", "")]
			for t in c.get("traits", []):
				txt += "[i]%s.[/i] %s\n" % [t.name, t.get("desc", "")]
			var r = UIKit.rich("[font_size=12]" + txt + "[/font_size]")
			inspect_box.add_child(r)
		if _can_control(c) and not _is_hidden(c.id):
			inspect_box.add_child(UIKit.check("AI plays this creature's turns", c.get("ai", false), func(p): Session.request({"type": "set_ai", "cid": c.id, "on": p})))
	# Rolls: anyone can roll checks and saves for creatures they control; the DM can add a DC and damage.
	var rollable: bool = dm or (_can_control(c) and sel.size() == 1)
	if rollable and not sel.any(func(id): return _is_hidden(id)):
		_build_roll_box(dm)
	if not dm:
		return
	inspect_box.add_child(HSeparator.new())
	# Hit points.
	var h = UIKit.hbox(4)
	var amt = UIKit.spin(0, 999, dm_amount, func(v): dm_amount = int(v))
	amt.update_on_text_changed = true
	amt.tooltip_text = "Amount for Damage, Half, Heal and Set HP"
	h.add_child(amt)
	var dtypes: Array = [["untyped", "Untyped"]]
	for t in Data.DAMAGE_TYPES:
		dtypes.append([t, t.capitalize()])
	var dto = UIKit.option(dtypes, dm_dtype, func(id): dm_dtype = id)
	dto.fit_to_longest_item = false
	dto.tooltip_text = "Damage type (resistance, immunity and vulnerability apply). Untyped ignores them."
	UIKit.expand(dto)
	h.add_child(dto)
	inspect_box.add_child(h)
	var h1 = UIKit.hbox(4)
	h1.add_child(UIKit.expand(UIKit.btn("Damage", func(): Session.request(_sel_req({"type": "dm_hp", "amount": -dm_amount, "dtype": dm_dtype})), "Deal this much damage to the selected creatures")))
	h1.add_child(UIKit.expand(UIKit.btn("Half", func(): Session.request(_sel_req({"type": "dm_hp", "amount": -(dm_amount / 2), "dtype": dm_dtype})), "Deal half (rounded down), e.g. a successful save")))
	h1.add_child(UIKit.expand(UIKit.btn("Heal", func(): Session.request(_sel_req({"type": "dm_hp", "amount": dm_amount})), "Heal. Also restores a slain monster.")))
	h1.add_child(UIKit.expand(UIKit.btn("Set HP", func(): Session.request(_sel_req({"type": "dm_set_hp", "hp": dm_amount})), "Set current HP to this number (above 0 brings the dead back)")))
	inspect_box.add_child(h1)
	# Conditions.
	var h2 = UIKit.hbox(4)
	var conds: Array = [["", "Toggle condition…"]]
	for cd in Data.CONDITIONS:
		var have: bool = sel.all(func(id): return eng.has_cond(_find(id), cd))
		conds.append([cd, ("✓ " if have else "") + cd.capitalize()])
	var co = UIKit.option(conds, "", func(id):
		if id != "":
			Session.request(_sel_req({"type": "dm_condition", "cond": id, "rounds": dm_cond_rounds})))
	co.fit_to_longest_item = false
	UIKit.expand(co)
	h2.add_child(co)
	var rs = UIKit.spin(0, 100, dm_cond_rounds, func(v): dm_cond_rounds = int(v))
	rs.update_on_text_changed = true
	rs.tooltip_text = "Rounds the condition lasts (0 = until removed). It ends at the end of the creature's own turn."
	rs.prefix = "rd"
	h2.add_child(rs)
	inspect_box.add_child(h2)
	var h3 = UIKit.hbox(4)
	h3.add_child(UIKit.lbl("Exhaustion %d" % eng.exhaustion(c), 13, UIKit.MUTED))
	h3.add_child(UIKit.btn("＋", func(): Session.request(_sel_req({"type": "dm_exhaustion", "delta": 1})), "Add a level of exhaustion"))
	h3.add_child(UIKit.btn("－", func(): Session.request(_sel_req({"type": "dm_exhaustion", "delta": -1})), "Remove a level of exhaustion"))
	inspect_box.add_child(h3)
	# Single-creature tools: initiative, name, owner.
	if sel.size() == 1 and not _is_hidden(c.id):
		if Session.state.in_combat and c.id in Session.state.order:
			var hi = UIKit.hbox(4)
			hi.add_child(UIKit.lbl("Initiative", 13, UIKit.MUTED))
			var isp = UIKit.spin(-10, 50, int(c.get("init", 0)))
			isp.update_on_text_changed = true
			hi.add_child(isp)
			hi.add_child(UIKit.btn("Set", func(): Session.request({"type": "dm_init", "cid": c.id, "init": int(isp.value)}), "Use a rolled initiative (for players rolling their own dice)"))
			inspect_box.add_child(hi)
		var hn = UIKit.hbox(4)
		var ne = UIKit.line(str(c.name), "Name")
		UIKit.expand(ne)
		hn.add_child(ne)
		var do_rename = func(_t = ""): Session.request({"type": "dm_rename", "cid": c.id, "name": ne.text})
		ne.text_submitted.connect(do_rename)
		hn.add_child(UIKit.btn("Rename", do_rename))
		inspect_box.add_child(hn)
		if c.kind == "pc" and Session.players.size() > 1:
			var owners: Array = []
			for pid in Session.players:
				owners.append([int(pid), "Played by " + str(Session.players[pid].name)])
			inspect_box.add_child(UIKit.option(owners, int(c.owner), func(id): Session.request({"type": "dm_owner", "cid": c.id, "owner": id})))
	var h4 = UIKit.hbox(4)
	var any_pc: bool = sel.any(func(id): return _find(id).kind == "pc")
	if not any_pc:
		var hidden_now: bool = sel.all(func(id): return _is_hidden(id))
		h4.add_child(UIKit.expand(UIKit.btn("Reveal" if hidden_now else "Hide", func(): Session.request(_sel_req({"type": "dm_hidden"})),
			"Show it to the players (it joins the initiative if a fight is on)" if hidden_now else "Hide it from the players: it leaves the map and the initiative until revealed (H)")))
	if not sel.any(func(id): return _is_hidden(id)):
		h4.add_child(UIKit.expand(UIKit.btn("Switch side", func(): Session.request(_sel_req({"type": "dm_team"})))))
	h4.add_child(UIKit.expand(UIKit.btn("Remove", func(): _remove_selected(), "Remove from the map (Delete)")))
	inspect_box.add_child(h4)

func _selection_key() -> String:
	return ",".join(_selection())

## Check / save roller under the inspect panel.
func _build_roll_box(dm: bool) -> void:
	inspect_box.add_child(HSeparator.new())
	var items: Array = []
	for a in Data.ABILITIES:
		items.append(["save:" + a, "%s save" % Data.ABILITY_NAMES[a]])
	for a in Data.ABILITIES:
		items.append(["check:" + a, "%s check" % Data.ABILITY_NAMES[a]])
	var sk: Array = Data.SKILLS.keys()
	sk.sort()
	for s in sk:
		items.append(["skill:" + s, "%s (%s)" % [str(s).replace("_", " ").capitalize(), str(Data.SKILLS[s]).to_upper()]])
	var r1 = UIKit.hbox(4)
	var ro = UIKit.option(items, roll_pick, func(id): roll_pick = id)
	ro.fit_to_longest_item = false
	ro.custom_minimum_size = Vector2(120, 0)
	UIKit.expand(ro)
	r1.add_child(ro)
	if dm:
		var dcs = UIKit.spin(0, 40, roll_dc, func(v): roll_dc = int(v))
		dcs.update_on_text_changed = true
		dcs.prefix = "DC"
		dcs.tooltip_text = "Difficulty class (0 = just roll and report totals)"
		r1.add_child(dcs)
	r1.add_child(UIKit.btn("Roll", func(): _do_roll(), "Roll for the selected creature(s)"))
	inspect_box.add_child(r1)
	if dm:
		var r2 = UIKit.hbox(4)
		var de = UIKit.line(roll_damage, "Damage on fail, e.g. 4d10")
		de.text_changed.connect(func(t): roll_damage = t)
		de.tooltip_text = "Optional. Rolled once; each creature that fails takes it all, and with 'half' a success takes half (Evasion applies to DEX saves)."
		UIKit.expand(de)
		r2.add_child(de)
		r2.add_child(UIKit.check("half", roll_half, func(p): roll_half = p))
		inspect_box.add_child(r2)

func _do_roll() -> void:
	var parts: PackedStringArray = roll_pick.split(":")
	var req := {"type": "roll", "kind": "save" if parts[0] == "save" else "check"}
	if parts[0] == "skill":
		req.skill = parts[1]
		req.ability = Data.SKILLS[parts[1]]
	else:
		req.ability = parts[1]
	if Session.is_dm():
		req.dc = roll_dc
		if roll_damage.strip_edges() != "" and roll_dc > 0:
			req.damage = roll_damage.strip_edges()
			req.dtype = dm_dtype
			req.half = roll_half
	Session.request(_sel_req(req))

func _remove_selected() -> void:
	var sel := _selection()
	if sel.is_empty():
		return
	Session.request({"type": "dm_remove", "cids": sel})
	selected_cid = ""
	selected_ids = []
	_refresh_ui()

# ================================================================ highlights & previews

func _refresh_highlights() -> void:
	var eng: CombatEngine = Session.engine
	var c = eng.C(control_cid)
	map_view.reach_cells = {}
	map_view.path_cells = []
	map_view.area_cells = []
	map_view.target_cells = []
	map_view.range_ft = 0
	map_view.show_spawns = Session.is_dm() and not Session.state.in_combat
	for id in tokens:
		var tk = tokens[id]
		tk.is_current = Session.state.in_combat and eng.current().get("id", "") == id
		tk.is_selected = id == selected_cid or id == control_cid or id in selected_ids
		tk.is_targetable = false
		tk.queue_redraw()
	if c.is_empty():
		map_view.queue_redraw()
		return
	if mode == "target":
		var a: Dictionary = pending.action
		map_view.range_center = eng.center_of(c) * CELL
		map_view.range_ft = int(a.range)
		for o in Session.state.combatants.values():
			if _valid_target(c, a, o):
				tokens[o.id].is_targetable = true
	elif mode == "" and Session.state.in_combat and eng.is_turn_of(c) and _can_control(c):
		map_view.reach_cells = eng.reachable(c, eng.move_budget(c))
	map_view.queue_redraw()

func _valid_target(c: Dictionary, a: Dictionary, o: Dictionary) -> bool:
	var eng: CombatEngine = Session.engine
	if o.get("dead", false) or eng.has_cond(o, "banished"):
		return false
	match a.target:
		"enemy":
			if not eng.hostile(c, o) or not eng.alive(o): return false
		"ally":
			if eng.hostile(c, o) or o.death.dead: return false
		"ally_other":
			if eng.hostile(c, o) or o.id == c.id or o.death.dead: return false
		"ally_dead":
			if eng.hostile(c, o) or not eng.revivable(o): return false
		"creature":
			if not eng.alive(o): return false
		_:
			return false
	if int(a.range) > 0 and eng.dist(c, o) > int(a.range):
		return false
	return o.id == c.id or eng.los(c, o)

func _preview_at(cell: Vector2i) -> void:
	var eng: CombatEngine = Session.engine
	var c = eng.C(control_cid)
	map_view.hover = cell
	map_view.path_cells = []
	map_view.area_cells = []
	tip.visible = false
	if c.is_empty():
		map_view.queue_redraw()
		return
	if mode == "target":
		var a: Dictionary = pending.action
		var area: Dictionary = a.get("area", {})
		if a.target in ["point", "self_area"] or (a.target == "self" and not area.is_empty()):
			if not area.is_empty():
				var from_self: bool = a.target == "self_area" or area.get("shape", "") in ["cone", "line", "emanation"]
				map_view.area_cells = eng.area_cells(c, area, cell, from_self)
				var hits: Array = eng.creatures_in_cells(map_view.area_cells, c.id if from_self else "").filter(_seen)
				var foes = hits.filter(func(o): return eng.hostile(c, o)).size()
				var friends = hits.size() - foes
				_show_tip("%d enemies%s in area" % [foes, (", [!] %d allies" % friends) if friends > 0 else ""])
			else:
				map_view.area_cells = [cell]
			if a.target == "point" and int(a.range) > 0 and eng.dist_to_cell(c, cell) > int(a.range):
				_show_tip("Out of range")
		else:
			var o = _creature_at_pointer(cell)
			if not o.is_empty():
				if _valid_target(c, a, o):
					_show_tip(_target_tip(c, a, o))
				else:
					_show_tip("Not a valid target" if eng.dist(c, o) <= int(a.range) or int(a.range) == 0 else "Out of range (%d ft)" % eng.dist(c, o))
	elif mode == "" and Session.state.in_combat and eng.is_turn_of(c) and _can_control(c):
		var reach: Dictionary = map_view.reach_cells
		if reach.has(cell) and not reach[cell].get("occupied", false):
			map_view.path_cells = [c.pos] + eng.path_to(c, cell, reach)
			_show_tip("%d ft" % int(reach[cell].cost))
	elif mode == "paint" or mode == "spawn" or mode == "place_monster":
		map_view.area_cells = _brush_cells(cell) if mode == "paint" else [cell]
		map_view.area_color = Color(0.6, 0.8, 1.0)
	map_view.queue_redraw()

func _target_tip(c: Dictionary, a: Dictionary, o: Dictionary) -> String:
	var eng: CombatEngine = Session.engine
	if a.kind == "weapon" or a.has("atk"):
		var atk: Dictionary = a.atk
		var adv = eng.attack_advantage(c, o, atk.get("melee", true), atk)
		var p = eng.hit_chance(int(atk.to_hit), eng.eff_ac(o), adv)
		var dmg = 0.0
		for d in atk.damage:
			dmg += Dice.average(d.dice)
		return "%s → %s\nHit chance %d%%%s   ~%d dmg" % [atk.name, o.name, int(round(p * 100)), " (adv)" if adv > 0 else (" (dis)" if adv < 0 else ""), int(dmg)]
	if a.kind == "spell":
		var sp = Data.spell(a.spell)
		var cb = sp.get("combat", null)
		if cb is Dictionary:
			if cb.get("attack", null) != null:
				var adv2 = eng.attack_advantage(c, o, cb.attack == "melee", {"range": int(sp.range)})
				return "%s → %s\nHit chance %d%%" % [sp.name, o.name, int(round(eng.hit_chance(int(a.spell_attack), eng.eff_ac(o), adv2) * 100))]
			if cb.get("save", null) != null:
				var fail = 1.0 - eng.save_chance(o, cb.save, int(a.dc))
				return "%s → %s\n%s save DC %d — fails ~%d%%" % [sp.name, o.name, str(cb.save).to_upper(), int(a.dc), int(round(fail * 100))]
		return "%s → %s" % [sp.name, o.name]
	return "%s → %s" % [a.name, o.name]

func _show_tip(text: String) -> void:
	tip.text = text
	tip.visible = true
	tip.reset_size()
	tip.position = get_viewport().get_mouse_position() + Vector2(18, 18)

# ================================================================ actions & targeting

func _on_action_pressed(a: Dictionary) -> void:
	var c = Session.engine.C(control_cid)
	if c.is_empty():
		return
	if a.kind == "toggle":
		_send_action(a, {})
		return
	# Choose slot level for leveled spells with several options.
	if a.kind == "spell" and a.slots.size() > 1 and not pending.has("slot_chosen"):
		var items: Array = []
		for L in a.slots:
			items.append([L, "Cast at level %d%s" % [L, "" if L == a.level else "  (upcast)"]])
		UIKit.popup_choice(ui, a.name, items, func(L): _resume_action(a, {"slot": L, "slot_chosen": true}))
		return
	var slot: int = pending.get("slot", a.slots[0] if a.get("slots", []).size() > 0 else 0)
	var opts = {}
	# Damage-type choice (Chromatic Orb, Awakened Spellbook, Dragon's Breath …).
	if a.kind == "spell" and not pending.has("dtype"):
		var types = _dtype_options(c, a, slot)
		if types.size() > 1:
			var items2: Array = []
			for t in types:
				items2.append([t, t.capitalize()])
			UIKit.popup_choice(ui, "Damage type", items2, func(t): _resume_action(a, {"slot": slot, "slot_chosen": true, "dtype": t}))
			return
	if pending.has("dtype"):
		opts.dtype = pending.dtype
	# Command: the one-word command the targets must obey on their next turn.
	if a.get("spell", "") == "command":
		if not pending.has("command"):
			var words: Array = [
				["approach", "Approach: it moves toward you and ends its turn if it gets within 5 ft"],
				["drop", "Drop: it drops what it is holding and ends its turn"],
				["flee", "Flee: it spends its turn moving away from you as fast as it can"],
				["grovel", "Grovel: it falls prone and ends its turn"],
				["halt", "Halt: it doesn't move and takes no actions"]]
			UIKit.popup_choice(ui, "Command (one word)", words, func(w): _resume_action(a, {"slot": slot, "slot_chosen": true, "command": w}))
			return
		opts.command = pending.command
	# Animate Objects: what size of object to bring to life.
	if a.get("spell", "") == "animate_objects":
		if not pending.has("obj_size"):
			var sizes: Array = []
			for sz in ["tiny", "small", "medium", "large", "huge"]:
				var n: int = Session.engine.animated_object_count(sz, maxi(0, slot - int(a.level)))
				if n > 0:
					var st: Dictionary = CombatantFactory.ANIMATED_OBJECTS[sz]
					sizes.append([sz, "%d %s object%s  (HP %d, AC %d, Slam %+d, %s)" % [n, sz.capitalize(), "" if n == 1 else "s", st.hp, st.ac, st.to_hit, st.dice]])
			UIKit.popup_choice(ui, "Animate which objects?", sizes, func(sz): _resume_action(a, {"slot": slot, "slot_chosen": true, "obj_size": sz}))
			return
		opts.obj_size = pending.obj_size
	# Lay on Hands: the paladin chooses how many points to spend (1 is enough to get a fallen ally up).
	if a.id == "lay_on_hands":
		if not pending.has("loh"):
			var pool: int = Session.engine.res_left(c, "lay_on_hands")
			var amounts: Array = [[0, "Heal as much as needed (up to %d)" % pool]]
			for n in [1, 5, 10, 15, 20, 30, 40, 50, 75]:
				if n < pool:
					amounts.append([n, "Heal %d HP%s" % [n, "  (get a fallen ally back up)" if n == 1 else ""]])
			if pool >= 5:
				amounts.append([-5, "Neutralize poison (5 points)"])
			UIKit.popup_choice(ui, "Lay on Hands (%d points left)" % pool, amounts, func(n): _resume_action(a, {"loh": n}))
			return
		if int(pending.loh) < 0:
			opts.cure = true
		elif int(pending.loh) > 0:
			opts.amount = int(pending.loh)
	if a.id == "wild_shape" and not pending.has("form"):
		var forms: Array = []
		for f in a.get("forms", []):
			forms.append([f.id, f.name])
		if forms.is_empty():
			_flash("No beast forms available.")
			return
		UIKit.popup_choice(ui, "Choose a beast form", forms, func(fid): _send_action(a, {"opts": {"form": fid}}))
		return
	if a.id == "eldritch_cannon":
		UIKit.popup_choice(ui, "Cannon type", [["flamethrower", "Flamethrower (15 ft cone, DEX save)"], ["force_ballista", "Force Ballista (ranged attack, push)"], ["protector", "Protector (temp HP to allies)"]], func(k): _send_action(a, {"opts": {"cannon": k}}))
		return
	var area: Dictionary = a.get("area", {})
	if a.target == "self" and (area.is_empty() or area.get("shape", "") == "emanation"):
		_send_action(a, {"slot": slot, "opts": opts, "targets": [c.id]})
		return
	pending = {"action": a, "slot": slot, "opts": opts, "targets": []}
	_set_mode("target")

## Re-enter _on_action_pressed after a popup choice. Only clear the temporary
## choice state if the action didn't move on to targeting (which needs `pending`).
func _resume_action(a: Dictionary, choice: Dictionary) -> void:
	pending = choice
	_on_action_pressed(a)
	if mode != "target":
		pending = {}

func _dtype_options(c: Dictionary, a: Dictionary, slot: int) -> Array:
	var sp = Data.spell(a.spell)
	var cb = sp.get("combat", null)
	if sp.id == "dragons_breath":
		return ["acid", "cold", "fire", "lightning", "poison"]
	# Spells that let the caster pick an element (Protection from Energy, Elemental Weapon, Fire Shield...).
	if cb is Dictionary and cb.get("choose_type", []).size() > 1:
		return cb.choose_type
	if not cb is Dictionary or cb.get("damage", []).is_empty():
		return []
	if sp.id == "chromatic_orb":
		return ["acid", "cold", "fire", "lightning", "poison", "thunder"]
	if c.features.has("awakened_spellbook") and a.get("class", "") == "wizard" and slot > 0:
		var types: Array = [cb.damage[0].type]
		for e in c.casting:
			if e["class"] != "wizard":
				continue
			# Awakened Spellbook draws on any spell in the book, prepared or not.
			for sid in e.get("spellbook", e.spells):
				var o = Data.spell(sid)
				var oc = o.get("combat", null)
				if int(o.get("level", 0)) == slot and oc is Dictionary:
					for d in oc.get("damage", []):
						if not d.type in types:
							types.append(d.type)
		return types
	return []

func _max_targets(a: Dictionary) -> int:
	var n = int(a.get("max_targets", 1)) + int(a.get("targets_per_slot", 0)) * maxi(0, int(pending.get("slot", 0)) - int(a.get("level", 0)))
	var c = Session.engine.C(control_cid)
	if str(c.get("toggles", {}).get("metamagic", "")) == "twinned":
		n += 1
	n = maxi(n, _shots(a))
	return maxi(1, n)

## Darts / rays / beams the pending spell fires (0 if it isn't that kind of spell). Each is aimed
## with its own click, so the same creature can be picked more than once.
func _shots(a: Dictionary) -> int:
	if a.get("spell", "") == "":
		return 0
	return Session.engine.spell_shots(Session.engine.C(control_cid), a, int(pending.get("slot", 0)))

func _shot_word(a: Dictionary) -> String:
	var cb = Data.spell(a.get("spell", "")).get("combat", {})
	if cb is Dictionary and int(cb.get("darts", 0)) > 0:
		return "darts"
	if cb is Dictionary and cb.get("beams_scale", false):
		return "beams"
	return "rays"

func _send_action(a: Dictionary, params: Dictionary) -> void:
	Session.request({"type": "action", "cid": control_cid, "aid": a.id, "params": params})
	_cancel_mode()

func _confirm_targets() -> void:
	if mode == "target" and not pending.targets.is_empty():
		_send_action(pending.action, {"targets": pending.targets, "slot": pending.slot, "opts": pending.opts})

func _set_mode(m: String) -> void:
	mode = m
	mode_lbl.visible = m != ""
	confirm_btn.visible = false
	match m:
		"target":
			var a: Dictionary = pending.action
			var mx = _max_targets(a)
			pending.max = mx
			var what = "a point" if a.target in ["point", "self_area"] else ("up to %d targets" % mx if mx > 1 else "a target")
			if _shots(a) > 1 and not a.target in ["point", "self_area", "self"]:
				what = "a target for each of %d %s (click a creature again to send it more)" % [mx, _shot_word(a)]
			mode_lbl.text = "  %s: choose %s  (right-click / Esc to cancel)  " % [a.name, what]
			confirm_btn.visible = mx > 1
		"paint":
			var what: String = {FOG_REVEAL: "revealed ground (fog of war)", FOG_HIDE: "fog back over explored ground"}.get(paint_value, "")
			if what == "":
				what = ["floor", "wall", "difficult terrain", "water", "pit"][paint_value]
			mode_lbl.text = "  Painting %s — drag on the map (right-click to stop)  " % what
		"spawn":
			mode_lbl.text = "  Click cells to toggle player start points (right-click to stop)  "
		"place_monster":
			mode_lbl.text = "  Click to place %s (right-click to stop)  " % Data.monster(place_mid).get("name", "")
	_refresh_highlights()

func _cancel_mode() -> void:
	mode = ""
	pending = {}
	mode_lbl.visible = false
	confirm_btn.visible = false
	tip.visible = false
	_refresh_highlights()

func _brush_cells(cell: Vector2i) -> Array:
	var out: Array = []
	for dx in brush:
		for dy in brush:
			out.append(cell + Vector2i(dx, dy))
	return out

# ================================================================ input

func _cell_under_mouse() -> Vector2i:
	var p = get_global_mouse_position()
	return Vector2i(floori(p.x / CELL), floori(p.y / CELL))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom(1.1)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom(1.0 / 1.1)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			panning = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if mode != "":
				_cancel_mode()
			else:
				panning = true
		elif mb.button_index == MOUSE_BUTTON_RIGHT and not mb.pressed:
			panning = false
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_on_left_click(_cell_under_mouse(), mb.shift_pressed, mb.ctrl_pressed or mb.meta_pressed)
			elif painting:
				painting = false
				_flush_paint()
	elif event is InputEventMouseMotion:
		var mm = event as InputEventMouseMotion
		if panning:
			cam.position -= mm.relative / cam.zoom
		var cell = _cell_under_mouse()
		if painting and mode == "paint":
			for p in _brush_cells(cell):
				if not p in paint_buffer:
					paint_buffer.append(p)
		if cell != map_view.hover or mode == "target":
			_preview_at(cell)
	elif event is InputEventKey and event.pressed and not event.echo:
		if _typing():
			return
		match event.keycode:
			KEY_ESCAPE:
				if mode != "":
					_cancel_mode()
				elif Session.is_dm() and selected_cid != "":
					selected_cid = ""
					selected_ids = []
					_refresh_ui()
			KEY_E:
				if not end_btn.disabled:
					Session.request({"type": "end_turn"})
			KEY_ENTER, KEY_KP_ENTER:
				_confirm_targets()
			KEY_DELETE:
				if Session.is_dm() and mode == "":
					_remove_selected()
			KEY_C:
				# Your own character sheet (or the selected party member's).
				var want: String = control_cid if control_cid != "" else selected_cid
				if want != "" and _can_view_sheet(Session.engine.C(want)):
					if is_instance_valid(sheet_win) and sheet_cid == want:
						sheet_win.close()
					else:
						_open_sheet(want)
			KEY_H:
				if Session.is_dm() and mode == "" and not _selection().is_empty() and not _selection().any(func(id): return _find(id).kind == "pc"):
					Session.request(_sel_req({"type": "dm_hidden"}))

## True while a text field has the keyboard (so WASD and hotkeys don't fire).
func _typing() -> bool:
	var fo = get_viewport().gui_get_focus_owner()
	if fo is LineEdit or fo is TextEdit or fo is SpinBox:
		return true
	# A dialog such as the monster editor is open: keys belong to it, not the map.
	for n in ui.get_children():
		if n is MonsterEditor or n is MapGeneratorPanel:
			return true
	return false

func _process(delta: float) -> void:
	if _typing():
		return
	var dir = Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): dir.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): dir.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): dir.y += 1
	if dir != Vector2.ZERO:
		cam.position += dir * 700.0 * delta / cam.zoom.x

func _zoom(f: float) -> void:
	var before = get_global_mouse_position()
	cam.zoom = (cam.zoom * f).clamp(Vector2.ONE * 0.3, Vector2.ONE * 2.5)
	var after = get_global_mouse_position()
	cam.position += before - after

## A hidden monster (DM only) whose space covers `cell`.
func _hidden_at(cell: Vector2i) -> Dictionary:
	for h in Session.state.get("reserve", {}).values():
		if cell in Session.engine.occupied_cells(h):
			return h
	return {}

func _on_left_click(cell: Vector2i, shift: bool, ctrl := false) -> void:
	var eng: CombatEngine = Session.engine
	match mode:
		"paint":
			painting = true
			paint_buffer = _brush_cells(cell)
			return
		"spawn":
			Session.request({"type": "dm_spawn", "at": cell})
			return
		"place_monster":
			if eng.in_bounds(cell):
				Session.request({"type": "dm_place_monster", "mid": place_mid, "at": cell, "team": "party" if place_ally else "enemy", "hidden": place_hidden})
			return
		"target":
			_target_click(cell)
			return
	var o = _creature_at_pointer(cell)
	if o.is_empty() and Session.is_dm():
		o = _hidden_at(cell)
	var c = eng.C(control_cid)
	if not o.is_empty():
		if ctrl and Session.is_dm():
			# Ctrl+click: add to or take out of the selection.
			if o.id == selected_cid:
				selected_cid = selected_ids.pop_front() if not selected_ids.is_empty() else ""
			elif o.id in selected_ids:
				selected_ids.erase(o.id)
			elif selected_cid == "":
				selected_cid = o.id
			else:
				selected_ids.append(o.id)
			_refresh_ui()
			return
		selected_cid = o.id
		selected_ids = []
		if _can_control(o) and not _is_hidden(o.id) and (not Session.state.in_combat or eng.is_turn_of(o)):
			control_cid = o.id
		_refresh_ui()
		return
	# The DM moves a hidden monster by selecting it and clicking an empty cell.
	if Session.is_dm() and _is_hidden(selected_cid) and eng.in_bounds(cell):
		Session.request({"type": "dm_move_hidden", "cid": selected_cid, "to": cell})
		return
	if c.is_empty() or not _can_control(c) or not eng.in_bounds(cell):
		return
	if Session.state.in_combat and not eng.is_turn_of(c) and not (Session.is_dm() and (free_move or shift)):
		_flash("It's not %s's turn." % c.name)
		return
	Session.request({"type": "move", "cid": c.id, "to": cell, "free": free_move or shift})

func _target_click(cell: Vector2i) -> void:
	var eng: CombatEngine = Session.engine
	var c = eng.C(control_cid)
	var a: Dictionary = pending.action
	if a.target in ["point", "self_area", "self"]:
		_send_action(a, {"cell": cell, "slot": pending.slot, "opts": pending.opts, "targets": []})
		return
	var o = _creature_at_pointer(cell)
	if o.is_empty() or not _valid_target(c, a, o):
		_flash("Not a valid target.")
		return
	var shots: int = _shots(a)
	if shots <= 1 and o.id in pending.targets:
		_flash("%s is already chosen." % o.name)
		return
	pending.targets.append(o.id)
	var mx: int = pending.get("max", 1)
	if pending.targets.size() >= mx:
		_confirm_targets()
	elif shots > 1:
		var counts = {}
		for tid in pending.targets:
			counts[tid] = int(counts.get(tid, 0)) + 1
		var parts: Array = []
		for tid in counts:
			parts.append("%s ×%d" % [eng.C(tid).get("name", "?"), counts[tid]])
		mode_lbl.text = "  %s: %d / %d %s aimed (%s) — click more, or Confirm to spread the rest  " % [a.name, pending.targets.size(), mx, _shot_word(a), ", ".join(parts)]
	else:
		mode_lbl.text = "  %s: %d / %d targets chosen — click more, or Confirm  " % [a.name, pending.targets.size(), mx]

func _flush_paint() -> void:
	if paint_buffer.is_empty():
		return
	if paint_value in [FOG_REVEAL, FOG_HIDE]:
		Session.request({"type": "dm_fog_paint", "cells": paint_buffer.duplicate(), "reveal": paint_value == FOG_REVEAL})
	else:
		Session.request({"type": "dm_cells", "cells": paint_buffer.duplicate(), "value": paint_value})
	paint_buffer = []

# ================================================================ misc

func _center_on(cid: String) -> void:
	var c = Session.engine.C(cid)
	if not c.is_empty() and _seen(c):
		var tw = create_tween()
		tw.tween_property(cam, "position", (Vector2(c.pos) + Vector2(0.5, 0.5)) * CELL + Vector2(180, 60) / cam.zoom, 0.3)

func _show_banner(text: String) -> void:
	banner.text = text
	var tw = create_tween()
	tw.tween_property(banner, "modulate:a", 1.0, 0.25)
	tw.tween_interval(1.3)
	tw.tween_property(banner, "modulate:a", 0.0, 0.6)

func _flash(text: String) -> void:
	log_rt.append_text("\n[color=#a59cb5][i]%s[/i][/color]" % text)

func _leave() -> void:
	Session.leave()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _on_session_ended(reason: String) -> void:
	if _ending:
		return
	_ending = true
	Session.last_end_reason = reason
	_flash(reason)
	await get_tree().create_timer(1.5).timeout
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
