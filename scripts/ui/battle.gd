extends Node2D
## The play screen shared by DM and players: battle map, tokens, hotbar, initiative, log and DM tools.

const CELL := 64
const MapViewScript := preload("res://scripts/ui/map_view.gd")
const MonsterEditorScript := preload("res://scripts/ui/monster_editor.gd")
const TokenScript := preload("res://scripts/ui/token.gd")
const Vfx := preload("res://scripts/ui/vfx.gd")
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
	# Top bar.
	var top = UIKit.panel(null, Color("#17131f"))
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = 92
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
	tb.add_child(UIKit.btn("Leave game", _leave))
	tb.add_child(UIKit.btn("Center view", func(): _center_on(control_cid if control_cid != "" else selected_cid)))
	tb.add_child(_build_volume())
	th.add_child(tb)
	# Right column: inspect + log + chat.
	var rightp = UIKit.panel(null, Color("#17131f"))
	rightp.anchor_left = 1.0
	rightp.anchor_right = 1.0
	rightp.anchor_bottom = 1.0
	rightp.offset_left = -370
	rightp.offset_top = 98
	ui.add_child(rightp)
	var rv = UIKit.vbox(6)
	rightp.add_child(rv)
	inspect_box = UIKit.vbox(4)
	var isc2 = UIKit.scroll(inspect_box)
	isc2.custom_minimum_size = Vector2(0, 250)
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
	# Bottom bar: character card, hotbar, economy.
	var bottom = UIKit.panel(null, Color("#17131f"))
	bottom.anchor_top = 1.0
	bottom.anchor_bottom = 1.0
	bottom.anchor_right = 1.0
	bottom.offset_top = -214
	bottom.offset_right = -376
	ui.add_child(bottom)
	var bh = UIKit.hbox(10)
	bottom.add_child(bh)
	card_box = UIKit.hbox(8)
	card_box.custom_minimum_size = Vector2(330, 0)
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
	auto_btn = UIKit.btn("⚙ Auto Turn", func(): Session.request({"type": "ai_turn", "cid": control_cid}), "Let the AI play this turn: it moves, picks the best attack or spell and ends the turn.")
	ev.add_child(auto_btn)
	bh.add_child(ev)
	# DM toolbox (left).
	if Session.is_dm():
		dm_tabs = TabContainer.new()
		dm_tabs.position = Vector2(8, 100)
		dm_tabs.size = Vector2(300, 470)
		dm_tabs.custom_minimum_size = Vector2(300, 470)
		ui.add_child(dm_tabs)
		_build_dm()
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
	cv.add_child(UIKit.lbl("Click any token to inspect it, adjust HP, toggle conditions or hand it to the AI.", 13, UIKit.MUTED))
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
	il.custom_minimum_size = Vector2(0, 300)
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
	mv.add_child(UIKit.check("Place as ally (party side)", false, func(p): place_ally = p))
	var mb = UIKit.hbox()
	mb.add_child(UIKit.expand(UIKit.btn("＋ New monster…", func(): _open_monster_editor({}))))
	mb.add_child(UIKit.expand(UIKit.btn("Edit / copy selected…", func():
		if place_mid != "":
			_open_monster_editor(_editor_template(place_mid)))))
	mv.add_child(mb)
	# Map tab.
	var mpv = UIKit.vbox(6)
	var msc = UIKit.scroll(UIKit.margin(mpv, 6))
	msc.name = "Map"
	dm_tabs.add_child(msc)
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
	mpv.add_child(UIKit.option([["stone", "Theme: Dungeon stone"], ["cave", "Theme: Cave"], ["forest", "Theme: Forest"], ["tavern", "Theme: Tavern"], ["snow", "Theme: Snow"]], Session.state.get("theme", "stone"), func(id): Session.request({"type": "dm_theme", "theme": id})))
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
	mpv.add_child(HSeparator.new())
	var mname = UIKit.line(str(Session.state.get("name", "map")), "Map name")
	mpv.add_child(mname)
	mpv.add_child(UIKit.btn("Save map + monsters", func():
		var snap = Session.map_snapshot()
		snap.name = mname.text
		CharacterStore.save_map(mname.text, snap)
		_flash("Map saved: " + mname.text)))
	var maps = CharacterStore.list_maps()
	if not maps.is_empty():
		var msel = [maps[0]]
		var items: Array = []
		for m in maps:
			items.append([m, m])
		var lh = UIKit.hbox()
		lh.add_child(UIKit.expand(UIKit.option(items, maps[0], func(id): msel[0] = id)))
		lh.add_child(UIKit.btn("Load", func(): Session.request({"type": "dm_load_map", "map": CharacterStore.load_map(msel[0])})))
		mpv.add_child(lh)
	# Party tab.
	var pv = UIKit.vbox(6)
	pv.name = "Party"
	dm_tabs.add_child(UIKit.margin(pv, 6))
	dm_tabs.get_child(3).name = "Party"
	pv.set_meta("party", true)
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

func _refresh_dm() -> void:
	if dm_tabs == null:
		return
	var pv: VBoxContainer = dm_tabs.get_child(3).get_child(0)
	UIKit.clear(pv)
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

# ================================================================ state sync & events

func _on_state(events: Array) -> void:
	map_view.set_state(Session.state)
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
	for c in Session.state.combatants.values():
		seen[c.id] = true
		var tk = tokens.get(c.id)
		if tk == null:
			tk = TokenScript.new()
			tk.cid = c.id
			tokens_root.add_child(tk)
			tokens[c.id] = tk
			tk.position = _token_pos(c)
		tk.setup(c)
		if not moving.has(c.id) and not playing:
			tk.position = _token_pos(c)
	for id in tokens.keys():
		if not seen.has(id):
			tokens[id].queue_free()
			tokens.erase(id)

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
	for c in Session.state.combatants.values():
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
	if tk == null:
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
			if Rect2(tk.position, Vector2.ONE * tk.cells() * CELL * tk.scale.x).has_point(mp):
				return c
	return eng.creature_at(cell)

## Draws an fx event. style is the event's sound name ("sword", "bow", "fire"...), which picks the look.
## Returns how long to wait before the next event (a projectile's flight time).
func _spawn_fx(e: Dictionary, style: String) -> float:
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
	title_lbl.text = str(st.get("name", "Dicehollow"))
	round_lbl.text = ("Round %d — %s's turn" % [st.round, cur.get("name", "")]) if st.in_combat else ("Exploration (no combat)" + ("  •  You are the DM" if Session.is_dm() else ""))
	_refresh_initiative()
	_refresh_card()
	_refresh_hotbar()
	_refresh_inspect()
	_refresh_highlights()
	_check_pending_hit()

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
				selected_cid = cid
				_center_on(cid)
				_refresh_ui())
		p.tooltip_text = "%s — initiative %d" % [c.name, int(c.get("init", 0))] if Session.state.in_combat else str(c.name)
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
	card_box.add_child(frame)
	var v = UIKit.vbox(2)
	UIKit.expand(v)
	v.add_child(UIKit.lbl(str(c.name) + ("  (%s)" % c.form.name if not c.form.is_empty() else ""), 17, UIKit.GOLD))
	var hp_txt = "HP %d / %d" % [maxi(c.hp, 0), c.max_hp]
	if c.temp_hp > 0: hp_txt += "  +%d temp" % c.temp_hp
	if not c.form.is_empty(): hp_txt += "  (beast %d/%d)" % [c.form.hp, c.form.max_hp]
	v.add_child(UIKit.lbl(hp_txt, 14))
	v.add_child(UIKit.bar(maxi(c.hp, 0), c.max_hp, UIKit.GOOD, 8))
	var info = "AC %d   Speed %d ft" % [eng.eff_ac(c), eng.eff_speed(c)]
	if not c.conc.is_empty():
		info += "   ◈ " + str(c.conc.name)
	v.add_child(UIKit.lbl(info, 13, UIKit.MUTED))
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
		v.add_child(UIKit.lbl(res_txt, 12, Color("#c8a0ff")))
	var rparts: PackedStringArray = []
	for k in c.resources:
		var r: Dictionary = c.resources[k]
		if not k.begins_with("innate_"):
			rparts.append("%s %d/%d" % [r.name, r.cur, r.max])
	if not rparts.is_empty():
		var rl = UIKit.lbl(", ".join(rparts), 12, Color("#ffd166"))
		rl.autowrap_mode = TextServer.AUTOWRAP_WORD
		rl.custom_minimum_size = Vector2(200, 0)
		v.add_child(rl)
	var conds: PackedStringArray = []
	for e in c.effects:
		if e.get("name", "") != "":
			conds.append(str(e.name))
	if c.kind == "pc" and c.hp <= 0 and not c.death.dead:
		conds.append("Dying (✓%d ✗%d)" % [c.death.s, c.death.f])
	if not conds.is_empty():
		var cl = UIKit.lbl(", ".join(conds), 12, Color("#e0a0ff"))
		cl.autowrap_mode = TextServer.AUTOWRAP_WORD
		cl.custom_minimum_size = Vector2(200, 0)
		v.add_child(cl)
	card_box.add_child(v)
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

func _refresh_inspect() -> void:
	UIKit.clear(inspect_box)
	var eng: CombatEngine = Session.engine
	var c = eng.C(selected_cid)
	if c.is_empty():
		inspect_box.add_child(UIKit.lbl("Click a token to inspect it.", 14, UIKit.MUTED))
		return
	var dm = Session.is_dm()
	inspect_box.add_child(UIKit.lbl(str(c.name), 18, UIKit.GOLD))
	inspect_box.add_child(UIKit.lbl(str(c.summary), 12, UIKit.MUTED))
	var see: bool = dm or c.team == "party"
	if see:
		inspect_box.add_child(UIKit.lbl("HP %d/%d%s   AC %d   Speed %d" % [maxi(c.hp, 0), c.max_hp, (" +%d" % c.temp_hp) if c.temp_hp > 0 else "", eng.eff_ac(c), eng.eff_speed(c)], 14))
	else:
		var frac = float(c.hp) / maxf(1.0, c.max_hp)
		inspect_box.add_child(UIKit.lbl("Condition: " + ("Unhurt" if frac >= 1.0 else ("Wounded" if frac > 0.5 else ("Bloodied" if frac > 0.25 else ("Near death" if c.hp > 0 else "Down")))), 14))
	var ab: PackedStringArray = []
	for a in Data.ABILITIES:
		ab.append("%s %d" % [a.to_upper(), int(c.scores.get(a, 10))])
	inspect_box.add_child(UIKit.lbl("  ".join(ab), 11, UIKit.MUTED))
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
	if _can_control(c):
		inspect_box.add_child(UIKit.check("AI plays this creature's turns", c.get("ai", false), func(p): Session.request({"type": "set_ai", "cid": c.id, "on": p})))
	if dm:
		var h = UIKit.hbox(4)
		var amt = UIKit.spin(1, 999, 5)
		h.add_child(amt)
		h.add_child(UIKit.btn("Damage", func(): Session.request({"type": "dm_hp", "cid": c.id, "amount": -int(amt.value)})))
		h.add_child(UIKit.btn("Heal", func(): Session.request({"type": "dm_hp", "cid": c.id, "amount": int(amt.value)})))
		inspect_box.add_child(h)
		var conds: Array = [["", "Toggle condition…"]]
		for cd in Data.CONDITIONS:
			conds.append([cd, ("✓ " if eng.has_cond(c, cd) else "") + cd.capitalize()])
		inspect_box.add_child(UIKit.option(conds, "", func(id):
			if id != "":
				Session.request({"type": "dm_condition", "cid": c.id, "cond": id})))
		var h2 = UIKit.hbox(4)
		h2.add_child(UIKit.btn("Switch side", func(): Session.request({"type": "dm_team", "cid": c.id})))
		h2.add_child(UIKit.btn("Remove", func(): Session.request({"type": "dm_remove", "cid": c.id}); selected_cid = ""))
		inspect_box.add_child(h2)
		if c.kind == "pc" and Session.players.size() > 1:
			var owners: Array = []
			for pid in Session.players:
				owners.append([int(pid), str(Session.players[pid].name)])
			inspect_box.add_child(UIKit.option(owners, int(c.owner), func(id): Session.request({"type": "dm_owner", "cid": c.id, "owner": id})))

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
		tk.is_selected = id == selected_cid or id == control_cid
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
				var hits: Array = eng.creatures_in_cells(map_view.area_cells, c.id if from_self else "")
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
			mode_lbl.text = "  Painting %s — drag on the map (right-click to stop)  " % ["floor", "wall", "difficult terrain", "water", "pit"][paint_value]
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
				_on_left_click(_cell_under_mouse(), mb.shift_pressed)
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
		match event.keycode:
			KEY_ESCAPE:
				_cancel_mode()
			KEY_E:
				if not end_btn.disabled:
					Session.request({"type": "end_turn"})
			KEY_ENTER, KEY_KP_ENTER:
				_confirm_targets()

func _process(delta: float) -> void:
	if chat_in.has_focus():
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

func _on_left_click(cell: Vector2i, shift: bool) -> void:
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
			if eng.in_bounds(cell) and not eng.blocks_move(cell):
				Session.request({"type": "dm_place_monster", "mid": place_mid, "at": cell})
				if place_ally:
					await get_tree().create_timer(0.05).timeout
					var newest = ""
					for c in Session.state.combatants.values():
						if c.get("monster_id", "") == place_mid and c.pos == cell:
							newest = c.id
					if newest != "":
						Session.request({"type": "dm_team", "cid": newest})
			return
		"target":
			_target_click(cell)
			return
	var o = _creature_at_pointer(cell)
	var c = eng.C(control_cid)
	if not o.is_empty():
		selected_cid = o.id
		if _can_control(o) and (not Session.state.in_combat or eng.is_turn_of(o)):
			control_cid = o.id
		_refresh_ui()
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
	Session.request({"type": "dm_cells", "cells": paint_buffer.duplicate(), "value": paint_value})
	paint_buffer = []

# ================================================================ misc

func _center_on(cid: String) -> void:
	var c = Session.engine.C(cid)
	if not c.is_empty():
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
	_flash(reason)
	await get_tree().create_timer(1.5).timeout
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
