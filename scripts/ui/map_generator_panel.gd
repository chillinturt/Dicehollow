class_name MapGeneratorPanel
extends PanelContainer
## DM tool: the encounter map generator window. Terrain, environment, monster and party settings on the left;
## a live preview and the encounter summary on the right. "Apply to table" loads the result through the normal
## "dm_load_map" request (monsters replaced, characters moved to the new start points).

signal applied(map_name: String)
signal saved(map_name: String)
signal closed

const MapViewScript := preload("res://scripts/ui/map_view.gd")

## Settings survive closing and reopening the window during a session.
static var remembered: Dictionary = {}

var settings: Dictionary = {}
var party_mode := "players"     # "players" (characters on the map) or "custom"
var picked: Dictionary = {}     # combatant id -> bool, for party_mode "players"
var custom_party: Array = []    # [{"class", "level"}]
var result: Dictionary = {}
var preview: MapPreview
var summary: RichTextLabel
var party_box: VBoxContainer
var profile_lbl: RichTextLabel
var blurb_lbl: Label
var env_sliders: Dictionary = {}   # settings key -> HSlider
var rooms_row: Control
var river_chk: CheckBox
var endless_box: VBoxContainer    # endless-map options (only for terrains MapStream supports)
var endless_note: Label
var seed_spin: SpinBox
var name_edit: LineEdit
var places_box: VBoxContainer     # Structures tab: named places of the current result
var struct_blurb: Label
var place_details := {}           # structure id -> RichTextLabel with its details (taverns)
var regen_timer: Timer
var _building := false

func _init(selected_pc_ids: Array = []) -> void:
	if remembered.is_empty():
		settings = MapGenerator.defaults_for("dungeon")
		settings.merge({"difficulty": 1, "strength": 0, "composition": "auto", "max_monsters": 10, "types": [],
			"match_habitat": true, "allow_custom": true, "enc_seed": 0}, true)
		settings.seed = randi() % 100000
		for i in 4:
			custom_party.append({"class": ["fighter", "cleric", "rogue", "wizard"][i], "level": 3})
	else:
		settings = remembered.settings.duplicate(true)
		party_mode = remembered.party_mode
		custom_party = remembered.custom_party.duplicate(true)
	# Characters on the map: the DM's selection if it holds any, otherwise everyone.
	var pcs := _pcs()
	for c in pcs:
		picked[c.id] = selected_pc_ids.is_empty() or c.id in selected_pc_ids
	if not selected_pc_ids.is_empty():
		party_mode = "players"
	elif pcs.is_empty():
		party_mode = "custom"

func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -600
	offset_right = 600
	offset_top = -370
	offset_bottom = 370
	add_theme_stylebox_override("panel", UIKit.sb(Color("#1b1626"), UIKit.GOLD, 2, 8, 12))
	regen_timer = Timer.new()
	regen_timer.one_shot = true
	regen_timer.wait_time = 0.2
	regen_timer.timeout.connect(regenerate)
	add_child(regen_timer)
	_build()
	regenerate()

# ---------------------------------------------------------------- building the window

func _build() -> void:
	_building = true
	var root = UIKit.vbox(8)
	add_child(root)
	var top = UIKit.hbox()
	top.add_child(UIKit.header("🗺 Encounter Map Generator", 22))
	top.add_child(UIKit.expand(Control.new()))
	top.add_child(UIKit.btn("✕", close, "Close (settings are kept)"))
	root.add_child(top)
	var body = UIKit.hbox(12)
	UIKit.expand(body, true, true)
	root.add_child(body)
	var tabs = TabContainer.new()
	tabs.custom_minimum_size = Vector2(450, 0)
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(tabs)
	_tab(tabs, "Terrain", _build_terrain())
	_tab(tabs, "Structures", _build_structures())
	_tab(tabs, "Environment", _build_environment())
	_tab(tabs, "Monsters", _build_monsters())
	_tab(tabs, "Party", _build_party())
	var right = UIKit.vbox(8)
	UIKit.expand(right, true, true)
	body.add_child(right)
	preview = MapPreview.new()
	UIKit.expand(preview, true, true)
	preview.custom_minimum_size = Vector2(0, 360)
	right.add_child(UIKit.panel(preview, Color("#0b0910")))
	right.get_child(0).size_flags_vertical = Control.SIZE_EXPAND_FILL
	summary = UIKit.rich("", false)
	summary.custom_minimum_size = Vector2(0, 190)
	summary.scroll_active = true
	right.add_child(UIKit.panel(summary))
	var br = UIKit.hbox()
	br.add_child(UIKit.btn("🎲 New map", func():
		settings.seed = randi() % 100000
		seed_spin.set_value_no_signal(settings.seed)
		regenerate(), "Same settings, a new random layout"))
	br.add_child(UIKit.btn("🎲 Reroll monsters", func():
		settings.enc_seed = int(settings.get("enc_seed", 0)) + 1
		regenerate(), "Keep the layout, pick a different set of monsters"))
	br.add_child(UIKit.expand(Control.new()))
	br.add_child(UIKit.btn("Save as map", _save, "Save to your map list without loading it"))
	var ap = UIKit.btn("✔ Apply to table", _apply, "Load this map: monsters on the current map are replaced and characters move to the start points")
	ap.add_theme_color_override("font_color", UIKit.GOLD)
	br.add_child(ap)
	right.add_child(br)
	_building = false

func _tab(tabs: TabContainer, title: String, content: Control) -> void:
	var sc = UIKit.scroll(UIKit.margin(content, 8))
	sc.name = title
	tabs.add_child(sc)

func _section(v: VBoxContainer, text: String) -> void:
	if v.get_child_count() > 0:
		v.add_child(HSeparator.new())
	v.add_child(UIKit.lbl(text, 14, UIKit.GOLD))

func _note(text: String) -> Label:
	var l = UIKit.lbl(text, 12, UIKit.MUTED)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	return l

## A labelled slider bound to settings[key]. `fmt` turns the value into the text shown beside it.
func _slider(v: VBoxContainer, label: String, key: String, mn: float, mx: float, step: float, fmt: Callable, tip := "") -> HSlider:
	var row = UIKit.hbox()
	var l = UIKit.lbl(label, 14)
	l.custom_minimum_size = Vector2(150, 0)
	l.tooltip_text = tip
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(l)
	var sl = HSlider.new()
	sl.min_value = mn
	sl.max_value = mx
	sl.step = step
	sl.value = float(settings.get(key, mn))
	sl.tooltip_text = tip
	UIKit.expand(sl)
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(sl)
	var val = UIKit.lbl(fmt.call(sl.value), 14, UIKit.INK)
	val.custom_minimum_size = Vector2(92, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val)
	sl.value_changed.connect(func(x):
		settings[key] = int(x) if step >= 1.0 else x
		val.text = fmt.call(x)
		_changed())
	v.add_child(row)
	return sl

static func _pct(x: float) -> String:
	return "%d%%" % int(round(x * 100))

func _build_terrain() -> VBoxContainer:
	var v = UIKit.vbox(6)
	_section(v, "Map")
	name_edit = UIKit.line(str(settings.get("name", "")), "Map name (blank: automatic)", func(t): settings.name = t.strip_edges())
	v.add_child(name_edit)
	var items: Array = []
	for k in MapGenerator.TERRAINS:
		items.append([k, MapGenerator.TERRAINS[k].name])
	var tr = UIKit.hbox()
	tr.add_child(UIKit.lbl("Terrain type", 14))
	tr.add_child(UIKit.expand(UIKit.option(items, settings.terrain, _set_terrain)))
	v.add_child(tr)
	blurb_lbl = _note("")
	v.add_child(blurb_lbl)
	_slider(v, "Width", "w", 12, 80, 1, func(x): return "%d sq (%d ft)" % [int(x), int(x) * 5])
	_slider(v, "Height", "h", 10, 60, 1, func(x): return "%d sq (%d ft)" % [int(x), int(x) * 5])
	var pr = UIKit.hbox()
	for p in [["Small", 20, 14], ["Medium", 30, 20], ["Large", 44, 30], ["Huge", 60, 40]]:
		pr.add_child(UIKit.expand(UIKit.btn(p[0], func():
			settings.w = p[1]
			settings.h = p[2]
			_rebuild())))
	v.add_child(pr)
	_section(v, "Layout")
	var sr = UIKit.hbox()
	sr.add_child(UIKit.lbl("Party starts on the", 14))
	sr.add_child(UIKit.expand(UIKit.option([["west", "West edge"], ["east", "East edge"], ["north", "North edge"], ["south", "South edge"], ["random", "Random edge"]],
		settings.party_side, func(id): settings.party_side = id; _changed())))
	v.add_child(sr)
	var sd = UIKit.hbox()
	sd.add_child(UIKit.lbl("Seed", 14))
	seed_spin = UIKit.spin(0, 99999, int(settings.seed), func(x): settings.seed = int(x); _changed())
	UIKit.expand(seed_spin)
	sd.add_child(seed_spin)
	sd.add_child(UIKit.btn("🎲", func():
		settings.seed = randi() % 100000
		seed_spin.set_value_no_signal(settings.seed)
		_changed(), "Random seed"))
	v.add_child(sd)
	v.add_child(_note("The same seed and settings always build the same map, so you can note a seed down and come back to it."))
	_update_blurb()
	return v

## Type names shown in the Named places list.
const PLACE_TYPES := {"town": "Town", "tavern": "Tavern", "temple": "Temple", "chapel": "Chapel", "smithy": "Smithy", "shop": "Shop",
	"apothecary": "Apothecary", "guard": "Guard", "tower": "Tower", "crypt": "Crypt", "shrine": "Shrine", "fort": "Fort"}

func _build_structures() -> VBoxContainer:
	var v = UIKit.vbox(6)
	var t: Dictionary = MapGenerator.TERRAINS[settings.terrain]
	match str(t.layout):
		"outdoor":
			_section(v, "Structures in the %s" % str(t.name).to_lower())
			var items: Array = []
			for k in MapGenerator.STRUCTURES:
				items.append([k, MapGenerator.STRUCTURES[k].name])
			var row = UIKit.hbox()
			row.add_child(UIKit.lbl("Build", 14))
			row.add_child(UIKit.expand(UIKit.option(items, settings.get("structures", "none"), func(id):
				settings.structures = id
				_update_structure_blurb()
				_changed())))
			v.add_child(row)
			struct_blurb = _note("")
			v.add_child(struct_blurb)
			_update_structure_blurb()
			_slider(v, "How many", "structure_count", 1, 8, 1, func(x): return str(int(x)),
				"Ruins, cabins or crypts; homes in a hamlet (3+ bring a tavern, 5+ a smithy); more tents in a camp")
			_style_row(v, "Building style")
			v.add_child(_note("Buildings use the terrain's materials: log cabins in a forest, stilt huts on plank decks in a swamp, stone in the mountains and the snow. The style sets the look of hamlets and inns and everyone's names."))
		"town":
			_section(v, "Town")
			_style_row(v, "Town style")
			v.add_child(_note("Human: timber houses on cobbled streets around a well or fountain. Dwarven: stone halls carved into the mountain around a statue. Elven: living-wood homes on winding dirt paths among the trees."))
			_slider(v, "Taverns", "taverns", 0, 4, 1, func(x): return str(int(x)), "How many taverns the town has (as many as fit)")
			v.add_child(_note("How built-up the town is, crates and carts, ponds and trees are on the Environment tab. Bigger maps fit a temple, a smithy, shops, an apothecary and a guard house."))
		"interior":
			_section(v, "Building")
			var items: Array = []
			for k in MapGenerator.INTERIORS:
				items.append([k, MapGenerator.INTERIORS[k]])
			var row = UIKit.hbox()
			row.add_child(UIKit.lbl("Inside a", 14))
			row.add_child(UIKit.expand(UIKit.option(items, settings.get("interior", "rooms"), func(id):
				settings.interior = id
				_update_env_visibility()
				_changed())))
			v.add_child(row)
			_style_row(v, "Style")
			v.add_child(_note("Every tavern gets its own name, owner, prices, house drink and dish, entertainment, a rumour and a layout: bar, hearth, kitchen, stage, booths, stairs and one odd feature. Big maps add guest rooms at the back."))
		_:
			v.add_child(_note("Structures are for outdoor terrains, Town streets and Indoors. Dungeons and caves are built from rooms and tunnels."))
	_section(v, "Named places")
	places_box = UIKit.vbox(6)
	v.add_child(places_box)
	return v

func _style_row(v: VBoxContainer, label: String) -> void:
	var items: Array = []
	for k in MapGenerator.STYLES:
		items.append([k, MapGenerator.STYLES[k]])
	var row = UIKit.hbox()
	row.add_child(UIKit.lbl(label, 14))
	row.add_child(UIKit.expand(UIKit.option(items, settings.get("style", "human"), func(id): settings.style = id; _changed())))
	v.add_child(row)

func _update_structure_blurb() -> void:
	if struct_blurb:
		struct_blurb.text = MapGenerator.STRUCTURES.get(str(settings.get("structures", "none")), MapGenerator.STRUCTURES.none).blurb

## The named places of the current map: rename them, reroll tavern names, read tavern details.
func _fill_places() -> void:
	if places_box == null:
		return
	UIKit.clear(places_box)
	place_details = {}
	var sts: Array = result.get("report", {}).get("structures", [])
	if sts.is_empty():
		places_box.add_child(_note("Nothing named on this map."))
		return
	places_box.add_child(_note("Type to rename: the name sticks for as long as the seed and settings build the same place. 🎲 picks a new tavern name."))
	for st in sts:
		var row = UIKit.hbox(4)
		var tl = UIKit.lbl(PLACE_TYPES.get(str(st.type), str(st.type).capitalize()), 13, UIKit.MUTED)
		tl.custom_minimum_size = Vector2(82, 0)
		row.add_child(tl)
		var e = UIKit.line(str(st.name), str(st.gen_name), func(txt): _rename(st, txt))
		UIKit.expand(e)
		row.add_child(e)
		if st.type == "tavern":
			row.add_child(UIKit.btn("🎲", func():
				var rng := RandomNumberGenerator.new()
				rng.randomize()
				var nn: String = TavernGenerator.random_name(rng, str(st.info.get("style", settings.get("style", "human"))))
				e.text = nn
				_rename(st, nn), "A new random tavern name"))
		places_box.add_child(row)
		if st.type == "tavern":
			var d = UIKit.rich(TavernGenerator.describe(st.info), true)
			d.add_theme_font_size_override("normal_font_size", 12)
			d.add_theme_font_size_override("bold_font_size", 13)
			d.add_theme_font_size_override("italics_font_size", 12)
			places_box.add_child(UIKit.margin(d, 4))
			place_details[st.id] = d

func _rename(st: Dictionary, txt: String) -> void:
	var nn := txt.strip_edges()
	var rn: Dictionary = settings.get("renames", {})
	if nn == "" or nn == str(st.gen_name):
		rn.erase(st.gen_name)
		nn = str(st.gen_name)
	else:
		rn[st.gen_name] = nn
	settings.renames = rn
	st.name = nn
	if st.info.has("name"):
		st.info.name = nn
	for l in result.get("labels", []):
		if l.get("sid", "") == st.id:
			l.text = nn
	if st.type == "town" and str(settings.get("name", "")) == "":
		result.name = nn
	if place_details.has(st.id):
		place_details[st.id].text = TavernGenerator.describe(st.info)
	preview.queue_redraw()
	_update_summary()
	remembered = {"settings": settings.duplicate(true), "party_mode": party_mode, "custom_party": custom_party.duplicate(true)}

func _build_environment() -> VBoxContainer:
	var v = UIKit.vbox(6)
	_section(v, "Terrain features")
	var town: bool = MapGenerator.TERRAINS[settings.terrain].layout == "town"
	if town:
		env_sliders.obstacles = _slider(v, "Buildings", "obstacles", 0, 1, 0.05, _pct, "How built-up the town is: more homes along the streets")
		env_sliders.difficult = _slider(v, "Crates & carts", "difficult", 0, 1, 0.05, _pct, "Crates, barrels, carts and haystacks against the buildings (difficult terrain)")
		env_sliders.water = _slider(v, "Ponds", "water", 0, 1, 0.05, _pct, "Ponds between the buildings")
	else:
		env_sliders.obstacles = _slider(v, "Obstacles", "obstacles", 0, 1, 0.05, _pct, "Walls, tree clumps or boulders. In a dungeon: higher means smaller rooms.")
		env_sliders.difficult = _slider(v, "Difficult terrain", "difficult", 0, 1, 0.05, _pct, "Rubble, undergrowth, mud, deep snow, furniture (costs double movement)")
		env_sliders.water = _slider(v, "Water", "water", 0, 1, 0.05, _pct, "Pools, bogs and lakes. Monsters that can't swim or fly are never placed in water.")
	env_sliders.pits = _slider(v, "Pits & chasms", "pits", 0, 1, 0.05, _pct, "Impassable drops")
	if town:
		env_sliders.cover = _slider(v, "Trees", "cover", 0, 1, 0.05, _pct, "Trees between the buildings (rock columns in a dwarven hold)")
	else:
		env_sliders.cover = _slider(v, "Cover", "cover", 0, 1, 0.05, _pct, "Lone pillars, rocks or headstones to hide behind")
	rooms_row = UIKit.vbox(0)
	env_sliders.rooms = _slider(rooms_row, "Rooms", "rooms", 2, 16, 1, func(x): return str(int(x)), "How many rooms (dungeons and buildings)")
	v.add_child(rooms_row)
	river_chk = UIKit.check("River crossing between the party and the enemy (bridges in town, fords in the wild)", bool(settings.river), func(p): settings.river = p; _changed())
	v.add_child(river_chk)
	_section(v, "Interactables")
	_slider(v, "Objects", "interactables", 0, 1, 0.05, _pct, "Breakable crates and barrels, weak walls to smash through, and rocks, branches, bottles or torches to pick up and fight with")
	_section(v, "Treasure")
	var loot_items: Array = []
	for k in MapObjects.LOOT:
		loot_items.append([k, MapObjects.LOOT[k].name])
	var loot_note := _note("")
	var lr = UIKit.hbox()
	var ll = UIKit.lbl("Loot", 14)
	ll.custom_minimum_size = Vector2(150, 0)
	lr.add_child(ll)
	var lo: OptionButton = UIKit.option(loot_items, str(settings.get("loot", "normal")), func(id):
		settings.loot = id
		loot_note.text = MapObjects.loot_level(id).desc
		_changed())
	lo.tooltip_text = "How much treasure is in chests (some locked) and in crates and barrels, scaled to the party's level. Monsters' own treasure is a separate table setting."
	lr.add_child(UIKit.expand(lo))
	v.add_child(lr)
	loot_note.text = MapObjects.loot_level(settings.get("loot", "normal")).desc
	v.add_child(loot_note)
	_section(v, "Endless map")
	endless_box = UIKit.vbox(6)
	endless_box.add_child(UIKit.check("Endless: new ground appears as the party nears an edge", bool(settings.get("endless", false)), func(p): settings.endless = p; _changed()))
	_slider(endless_box, "Largest size", "endless_max", 40, MapStream.MAX_LIMIT, 10, func(x): return "%d sq per side" % int(x),
		"Past this, ground far behind the party is dropped (it comes back freshly made if they return)")
	_slider(endless_box, "Wandering monsters", "endless_foes", 0, 1, 0.05, _pct, "Chance that each new stretch of ground holds a few monsters (an easy group for the party)")
	v.add_child(endless_box)
	endless_note = _note("Endless works for outdoor terrain, caves and town streets.")
	v.add_child(endless_note)
	v.add_child(UIKit.btn("Reset to this terrain's defaults", func(): _set_terrain(settings.terrain)))
	v.add_child(_note("Anything the party couldn't walk to is filled in, so every start point can reach every monster on foot."))
	_update_env_visibility()
	return v

func _build_monsters() -> VBoxContainer:
	var v = UIKit.vbox(6)
	v.add_child(UIKit.check("Add recommended monsters", bool(settings.include_monsters), func(p): settings.include_monsters = p; _changed()))
	_section(v, "Challenge")
	_slider(v, "Difficulty", "difficulty", 0, 4, 1, func(x): return EncounterBuilder.DIFFICULTY_NAMES[EncounterBuilder.DIFFICULTIES[int(x)]],
		"DMG encounter difficulty: the adjusted XP lands in this band for the chosen party")
	_slider(v, "Party power", "strength", -2, 2, 1, func(x): return ["Weak", "Below avg", "Typical", "Strong", "Very strong"][int(x) + 2],
		"Magic items, optimised builds, a fresh party: each step moves the XP budget 15%")
	var cr = UIKit.hbox()
	cr.add_child(UIKit.lbl("Composition", 14))
	var comps: Array = []
	for k in EncounterBuilder.COMPOSITIONS:
		comps.append([k, EncounterBuilder.COMPOSITIONS[k]])
	cr.add_child(UIKit.expand(UIKit.option(comps, settings.composition, func(id): settings.composition = id; _changed())))
	v.add_child(cr)
	_slider(v, "Max monsters", "max_monsters", 1, 20, 1, func(x): return str(int(x)))
	_section(v, "Enemy type (none ticked: any)")
	var grid = GridContainer.new()
	grid.columns = 3
	var boxes: Array = []
	for t in EncounterBuilder.CREATURE_TYPES:
		var cb = UIKit.check(t.capitalize(), t in settings.types, func(p):
			if p and not t in settings.types: settings.types.append(t)
			elif not p: settings.types.erase(t)
			_changed())
		boxes.append(cb)
		grid.add_child(cb)
	v.add_child(grid)
	var tb = UIKit.hbox()
	tb.add_child(UIKit.expand(UIKit.btn("Any type", func():
		settings.types = []
		for b in boxes: b.set_pressed_no_signal(false)
		_changed())))
	v.add_child(tb)
	v.add_child(UIKit.check("Only monsters that live in this terrain", bool(settings.match_habitat), func(p): settings.match_habitat = p; _changed()))
	v.add_child(UIKit.check("Include my custom monsters", bool(settings.allow_custom), func(p): settings.allow_custom = p; _changed()))
	_section(v, "Placement")
	var lr = UIKit.hbox()
	lr.add_child(UIKit.lbl("Enemies are", 14))
	var lays: Array = []
	for k in MapGenerator.LAYOUTS:
		lays.append([k, MapGenerator.LAYOUTS[k]])
	lr.add_child(UIKit.expand(UIKit.option(lays, settings.enemy_layout, func(id): settings.enemy_layout = id; _changed())))
	v.add_child(lr)
	_slider(v, "Distance", "enemy_distance", 0, 1, 0.05, func(x): return "Close" if x < 0.34 else ("Medium" if x < 0.67 else "Far side"),
		"How far from the party's start the enemies wait (not used when surrounding)")
	_slider(v, "Hidden (ambush)", "hidden", 0, 1, 0.05, _pct, "This share of the monsters starts hidden: off the initiative until you reveal them")
	return v

func _build_party() -> VBoxContainer:
	var v = UIKit.vbox(6)
	var mr = UIKit.hbox()
	mr.add_child(UIKit.lbl("Build for", 14))
	mr.add_child(UIKit.expand(UIKit.option([["players", "Characters on the map"], ["custom", "A custom party"]], party_mode, func(id):
		party_mode = id
		_fill_party()
		_changed())))
	v.add_child(mr)
	party_box = UIKit.vbox(6)
	v.add_child(party_box)
	v.add_child(HSeparator.new())
	profile_lbl = UIKit.rich("", true)
	v.add_child(profile_lbl)
	_fill_party()
	return v

func _fill_party() -> void:
	UIKit.clear(party_box)
	if party_mode == "players":
		var pcs := _pcs()
		if pcs.is_empty():
			party_box.add_child(_note("No characters are on the map yet. Players appear here once they join (or add one from the Party tab), or switch to a custom party."))
			return
		party_box.add_child(_note("Their levels and classes set the budget. Opening the generator with characters selected (Ctrl+click) ticks just those."))
		for c in pcs:
			var cb = UIKit.check("%s  —  %s" % [c.name, _class_text(c)], picked.get(c.id, true), func(p): picked[c.id] = p; _changed())
			party_box.add_child(cb)
		var r = UIKit.hbox()
		r.add_child(UIKit.expand(UIKit.btn("All", func():
			for c in pcs: picked[c.id] = true
			_fill_party()
			_changed())))
		r.add_child(UIKit.expand(UIKit.btn("None", func():
			for c in pcs: picked[c.id] = false
			_fill_party()
			_changed())))
		party_box.add_child(r)
	else:
		var sr = UIKit.hbox()
		sr.add_child(UIKit.lbl("Players", 14))
		var size_spin = UIKit.spin(1, 8, custom_party.size(), func(x):
			var n := int(x)
			while custom_party.size() < n:
				custom_party.append({"class": "fighter", "level": custom_party[-1].level if not custom_party.is_empty() else 3})
			custom_party.resize(n)
			_fill_party.call_deferred()
			_changed())
		sr.add_child(size_spin)
		sr.add_child(UIKit.lbl("  Level for all", 14))
		var all_spin = UIKit.spin(1, 20, custom_party[0].level if not custom_party.is_empty() else 3, func(x):
			for m in custom_party: m.level = int(x)
			_fill_party.call_deferred()
			_changed())
		sr.add_child(all_spin)
		party_box.add_child(sr)
		var classes: Array = []
		for k in Data.classes:
			classes.append([k, str(Data.classes[k].get("name", k))])
		classes.sort_custom(func(a, b): return a[1] < b[1])
		for i in custom_party.size():
			var m: Dictionary = custom_party[i]
			var row = UIKit.hbox()
			row.add_child(UIKit.lbl("#%d" % (i + 1), 14, UIKit.MUTED))
			row.add_child(UIKit.expand(UIKit.option(classes, m["class"], func(id): m["class"] = id; _changed())))
			row.add_child(UIKit.lbl("Lvl", 14, UIKit.MUTED))
			row.add_child(UIKit.spin(1, 20, m.level, func(x): m.level = int(x); _changed()))
			party_box.add_child(row)

static func _pcs() -> Array:
	var out: Array = []
	for c in Session.state.get("combatants", {}).values():
		if c.get("kind", "") == "pc":
			out.append(c)
	out.sort_custom(func(a, b): return str(a.name).naturalnocasecmp_to(str(b.name)) < 0)
	return out

static func _class_text(c: Dictionary) -> String:
	var parts: Array = []
	var cl: Dictionary = c.get("class_levels", {})
	for k in cl:
		parts.append("%s %d" % [str(Data.classes.get(k, {}).get("name", k)), int(cl[k])])
	return "Lvl %d %s" % [int(c.get("level", 1)), " / ".join(parts)]

## The party the encounter is built for, as EncounterBuilder expects it.
func party() -> Array:
	var out: Array = []
	if party_mode == "players":
		for c in _pcs():
			if picked.get(c.id, true):
				out.append({"name": c.name, "level": int(c.get("level", 1)), "classes": c.get("class_levels", {}).duplicate()})
	else:
		for m in custom_party:
			out.append({"name": str(m["class"]).capitalize(), "level": int(m.level), "classes": {m["class"]: int(m.level)}})
	return out

# ---------------------------------------------------------------- reacting to settings

func _set_terrain(id: String) -> void:
	var keep := settings.duplicate(true)
	settings = MapGenerator.defaults_for(id)
	for k in keep:
		if not k in ["obstacles", "difficult", "water", "pits", "cover", "rooms", "river", "terrain", "structures"]:
			settings[k] = keep[k]
	_rebuild()

## Rebuild the controls (after a terrain or preset change moves several sliders at once).
func _rebuild() -> void:
	var tab := 0
	var old_tabs = _find_tabs()
	if old_tabs:
		tab = old_tabs.current_tab
	UIKit.clear(self)
	regen_timer = Timer.new()
	regen_timer.one_shot = true
	regen_timer.wait_time = 0.2
	regen_timer.timeout.connect(regenerate)
	add_child(regen_timer)
	_build()
	var t = _find_tabs()
	if t:
		t.current_tab = tab
	regenerate()

func _find_tabs() -> TabContainer:
	var found = find_children("*", "TabContainer", true, false)
	return found[0] if not found.is_empty() else null

func _update_blurb() -> void:
	if blurb_lbl:
		blurb_lbl.text = MapGenerator.TERRAINS[settings.terrain].blurb

func _update_env_visibility() -> void:
	var layout: String = MapGenerator.TERRAINS[settings.terrain].layout
	if rooms_row:
		rooms_row.visible = layout == "rooms" or (layout == "interior" and str(settings.get("interior", "rooms")) == "rooms")
	if river_chk:
		river_chk.visible = layout in ["outdoor", "town"]
	if endless_box:
		endless_box.visible = MapStream.supports(str(settings.terrain))
		endless_note.visible = not endless_box.visible

func _changed() -> void:
	if _building or regen_timer == null:
		return
	regen_timer.start()

## Settings ready for MapGenerator, with the party and the number of start points filled in.
func build_settings() -> Dictionary:
	var st := settings.duplicate(true)
	st.party = party()
	st.spawn_count = maxi(6, maxi(st.party.size(), _pcs().size()))
	return st

func regenerate() -> void:
	result = MapGenerator.generate(build_settings())
	preview.set_map(result)
	_update_summary()
	_update_profile()
	_fill_places()
	remembered = {"settings": settings.duplicate(true), "party_mode": party_mode, "custom_party": custom_party.duplicate(true)}

func _update_profile() -> void:
	if profile_lbl == null:
		return
	var p := party()
	if p.is_empty():
		profile_lbl.text = "[color=#ff9c8f]No one in the party: tick some characters or use a custom party.[/color]"
		return
	var t := EncounterBuilder.thresholds(p)
	var prof := EncounterBuilder.party_profile(p)
	var txt := "[color=#c9a14a]%d characters, average level %d[/color]\nXP thresholds  Easy %d · Medium %d · Hard %d · Deadly %d" % [p.size(), prof.avg_level, t[0], t[1], t[2], t[3]]
	for n in prof.notes:
		txt += "\n• " + n
	profile_lbl.text = txt

func _update_summary() -> void:
	var t: Dictionary = MapGenerator.TERRAINS[settings.terrain]
	var rep: Dictionary = result.get("report", {})
	var enc: Dictionary = rep.get("encounter", {})
	var lines: Array = []
	lines.append("[b]%s[/b]  ·  %s, %d×%d squares, %d start points, seed %d" % [result.name, t.name, result.w, result.h, result.spawns.size(), int(settings.seed)])
	var objs: Array = result.get("objects", [])
	if not objs.is_empty() or result.has("stream"):
		var chests := objs.filter(func(o): return o.k == "chest").size()
		var walls := objs.filter(func(o): return o.k in ["weak_wall", "cracked_wall"]).size()
		var bits: Array = []
		if chests > 0: bits.append("%d chest%s" % [chests, "" if chests == 1 else "s"])
		if walls > 0: bits.append("%d weak wall%s" % [walls, "" if walls == 1 else "s"])
		var other := objs.size() - chests - walls
		if other > 0: bits.append("%d other object%s" % [other, "" if other == 1 else "s"])
		var gp := 0.0
		for o in objs:
			var l: Dictionary = o.get("loot", {})
			gp += int(l.get("pp", 0)) * 10 + int(l.get("gp", 0)) + int(l.get("ep", 0)) * 0.5 + int(l.get("sp", 0)) * 0.1 + int(l.get("cp", 0)) * 0.01
		var lv: Dictionary = MapObjects.loot_level(settings.get("loot", "normal"))
		if str(settings.get("loot", "normal")) == "none":
			bits.append("no loot")
		else:
			bits.append("[color=#ffd166]%s loot%s[/color]" % [lv.name, (" (%d gp in coin)" % int(gp)) if gp >= 1 else ""])
		if result.has("stream"): bits.append("[color=#8fd0ff]endless (grows to %d squares a side)[/color]" % int(result.stream.max))
		lines.append("  " + "  ·  ".join(bits))
	var taverns: Array = []
	var others := 0
	for st in rep.get("structures", []):
		if st.type == "tavern":
			taverns.append(str(st.name))
		elif st.type != "town":
			others += 1
	if not taverns.is_empty() or others > 0:
		var bits: Array = []
		if not taverns.is_empty():
			bits.append("[color=#ffd27a]%s[/color]" % ", ".join(taverns))
		if others > 0:
			bits.append("%d other named place%s" % [others, "" if others == 1 else "s"])
		lines.append("  " + "  ·  ".join(bits) + "  [color=#a59cb5](Structures tab)[/color]")
	if not settings.include_monsters:
		lines.append("[color=#a59cb5]No monsters: terrain only.[/color]")
	elif enc.is_empty() or enc.picks.is_empty():
		lines.append("[color=#ff9c8f]No monsters chosen.[/color]")
	else:
		var diff: String = enc.difficulty
		var col := {"trivial": "#a59cb5", "easy": "#5cc892", "medium": "#e6d36a", "hard": "#ff9c4a", "deadly": "#ff5a4a", "deadly+": "#ff2a6a"}.get(diff, "#ece6d8")
		lines.append("[color=%s][b]%s[/b][/color] encounter  ·  adjusted XP %d (target %d–%d)  ·  %d XP to award" % [col,
			EncounterBuilder.DIFFICULTY_NAMES.get(diff, diff.capitalize()), enc.adjusted, enc.lo, enc.hi, enc.raw])
		var hidden := 0
		var placed_by := {}
		for m in result.monsters:
			placed_by[m.mid] = placed_by.get(m.mid, 0) + 1
			if m.get("hidden", false):
				hidden += 1
		for p in enc.picks:
			var md: Dictionary = Data.monster(p.mid)
			var line := "  %d × %s  [color=#a59cb5](CR %s, %d XP each, %s %s)[/color]" % [p.count, md.get("name", p.mid), Data.cr_text(md.get("cr", 0)),
				EncounterBuilder.monster_xp(md), str(md.get("size", "")), str(md.get("type", ""))]
			if placed_by.get(p.mid, 0) < int(p.count):
				line += " [color=#ff9c8f]only %d fit on the map[/color]" % placed_by.get(p.mid, 0)
			lines.append(line)
		if hidden > 0:
			lines.append("  %d start hidden (ambush)." % hidden)
		for n in enc.notes:
			lines.append("[color=#a59cb5]• %s[/color]" % n)
	if Session.state.get("in_combat", false):
		lines.append("[color=#ff9c8f]Applying ends the current combat.[/color]")
	summary.text = "\n".join(lines)

# ---------------------------------------------------------------- output

func map_data() -> Dictionary:
	var m := result.duplicate(true)
	m.erase("report")
	if name_edit and name_edit.text.strip_edges() != "":
		m.name = name_edit.text.strip_edges()
	return m

func _apply() -> void:
	var m := map_data()
	Session.request({"type": "dm_load_map", "map": m})
	applied.emit(str(m.name))
	close()

func _save() -> void:
	var m := map_data()
	var nm: String = str(m.name)
	if nm.validate_filename() == "":
		return
	CharacterStore.save_map(nm, m)
	saved.emit(nm.validate_filename())

func close() -> void:
	closed.emit()
	queue_free()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()

# ---------------------------------------------------------------- preview

## A scaled-down drawing of the generated map: terrain, start points and monster footprints.
class MapPreview extends Control:
	var map: Dictionary = {}

	func set_map(m: Dictionary) -> void:
		map = m
		queue_redraw()

	func _draw() -> void:
		if map.is_empty():
			return
		var w: int = map.w
		var h: int = map.h
		var cs := minf(size.x / w, size.y / h)
		var off := (size - Vector2(w, h) * cs) * 0.5
		var th: Dictionary = _theme(str(map.get("theme", "stone")))
		var cells: Array = map.cells
		var ground: Array = map.get("ground", [])
		var has_g := ground.size() == w * h
		var props: Array = map.get("props", []) + MapObjects.as_props(map.get("objects", []))
		var cov: Dictionary = MapDecor.covered(props)
		var detail := cs >= 20.0
		for y in h:
			for x in w:
				var r := Rect2(off + Vector2(x, y) * cs, Vector2(cs, cs))
				var col: Color = th.floor_a if (x + y) % 2 == 0 else th.floor_b
				var v := int(cells[y * w + x])
				var gc: int = int(ground[y * w + x]) if has_g else 0
				if v == EngineBase.WALL and MapDecor.free_standing(cov, Vector2i(x, y)):
					v = EngineBase.FLOOR
				if gc > 0 and v in [EngineBase.FLOOR, EngineBase.DIFFICULT]:
					MapDecor.draw_floor(self, r, gc, x, y, detail)
					if v == EngineBase.DIFFICULT and not cov.has(Vector2i(x, y)) and cs >= 6:
						draw_circle(r.get_center(), cs * 0.14, MapDecor.FLOORS.get(gc, col).darkened(0.4))
					continue
				if gc > 0 and v == EngineBase.WALL:
					MapDecor.draw_wall(self, r, gc, x, y, detail)
					continue
				match v:
					EngineBase.WALL: col = th.wall
					EngineBase.DIFFICULT: col = col.darkened(0.25)
					EngineBase.WATER: col = Color(0.16, 0.36, 0.55)
					EngineBase.PIT: col = Color(0.02, 0.016, 0.03)
				draw_rect(r, col)
				if v == EngineBase.PIT:
					draw_rect(r.grow(-maxf(1.0, cs * 0.1)), Color("#7a5a8c"), false, maxf(1.0, cs * 0.08))
				elif v == EngineBase.DIFFICULT and cs >= 6 and not cov.has(Vector2i(x, y)):
					draw_circle(r.get_center(), cs * 0.14, col.darkened(0.4))
		if not props.is_empty():
			MapDecor.draw_props(self, props, off, cs)
		if cs >= 8:
			for x in w + 1:
				draw_line(off + Vector2(x * cs, 0), off + Vector2(x * cs, h * cs), th.grid, 1)
			for y in h + 1:
				draw_line(off + Vector2(0, y * cs), off + Vector2(w * cs, y * cs), th.grid, 1)
		for p in map.spawns:
			var r2 := Rect2(off + Vector2(p[0], p[1]) * cs, Vector2(cs, cs)).grow(-cs * 0.12)
			draw_rect(r2, Color(0.3, 0.7, 1, 0.55))
			draw_rect(r2, Color(0.6, 0.85, 1), false, 1)
		for m in map.monsters:
			var md: Dictionary = Data.monster(str(m.mid))
			var sz: int = CombatantFactory.SIZE_CELLS.get(str(md.get("size", "medium")), 1)
			var cen := off + (Vector2(m.x, m.y) + Vector2(sz, sz) * 0.5) * cs
			var rad := sz * cs * 0.42
			var col2 := Color(str(md.get("token_color", "#c0392b")))
			if m.get("hidden", false):
				draw_arc(cen, rad, 0, TAU, 24, col2.lightened(0.3), 2)
			else:
				draw_circle(cen, rad, col2)
				draw_arc(cen, rad, 0, TAU, 24, Color(1, 0.35, 0.3), maxf(1.0, cs * 0.08))
		MapDecor.draw_labels(self, map.get("labels", []), off, cs)

	static func _theme(id: String) -> Dictionary:
		var themes: Dictionary = preload("res://scripts/ui/map_view.gd").THEMES
		return themes.get(id, themes.stone)
