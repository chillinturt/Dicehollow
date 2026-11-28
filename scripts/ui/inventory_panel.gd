class_name InventoryPanel
extends VBoxContainer
## A character's belongings: purse, load against carrying capacity, attunement, and every item grouped into
## worn and wielded / in the pack / inside each bag of holding, with buttons to equip, attune, pack, give
## and drop. Shared by the character builder (it changes the sheet directly) and the game (it asks the
## server): every change is emitted as an Inventory.apply_op operation through op_requested, and gifts to
## other characters through give_requested.

signal op_requested(op: Dictionary)
signal give_requested(to: String, uid: String, qty: int, coins: Dictionary)

var holder_fn: Callable      # () -> the sheet or combatant
var opts: Dictionary         # editable, free (coins can be typed, items added), give_to: Callable -> [[cid, name]], variant: bool, note: String
var _body: VBoxContainer
var _picker: ItemPicker
const FILTERS := [["all", "Everything"], ["arms", "Weapons & armor"], ["magic", "Magic items"], ["use", "Potions & consumables"],
	["gear", "Gear & tools"], ["treasure", "Gems & art"]]
const SORTS := [["type", "Sort: type"], ["name", "Sort: name"], ["weight", "Sort: heaviest"], ["value", "Sort: most valuable"]]
var _filter := "all"
var _sort := "type"
var _search := ""
var _give_amt := 10
var _give_coin := "gp"
var _give_to := ""

func _init(holder: Callable, options := {}) -> void:
	holder_fn = holder
	opts = options
	add_theme_constant_override("separation", 6)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Show only some items, sorted another way, or matching a search (kept outside the rebuilt body so typing
	# doesn't lose focus).
	var bar := UIKit.hbox(4)
	var fo := UIKit.option(FILTERS, _filter, func(v):
		_filter = str(v)
		refresh())
	fo.fit_to_longest_item = false
	fo.tooltip_text = "Show only some of what's carried."
	bar.add_child(fo)
	var so := UIKit.option(SORTS, _sort, func(v):
		_sort = str(v)
		refresh())
	so.fit_to_longest_item = false
	so.tooltip_text = "Sort each section."
	bar.add_child(so)
	var se := UIKit.line("", "Search…", func(t):
		_search = str(t).to_lower()
		refresh())
	UIKit.expand(se)
	bar.add_child(se)
	add_child(bar)
	_body = UIKit.vbox(6)
	add_child(_body)
	if opts.get("free", false) and opts.get("editable", false):
		add_child(HSeparator.new())
		add_child(UIKit.lbl("Add an item (free: your own gear, or treasure the DM handed out)", 14, UIKit.GOLD))
		_picker = ItemPicker.new("gear")
		add_child(_picker)
		add_child(UIKit.btn("＋ Add to inventory", func():
			var cur := _picker.current()
			cur.op = "add"
			op_requested.emit(cur), "Adds the item without paying for it. Use the shop below to buy with your coins."))
	refresh()

func refresh() -> void:
	UIKit.clear(_body)
	var h: Dictionary = holder_fn.call()
	if h.is_empty():
		_body.add_child(UIKit.lbl("Nothing to show.", 14, UIKit.MUTED))
		return
	var editable: bool = opts.get("editable", false)
	_purse(h, editable)
	_load(h)
	var inv: Array = Inventory.list(h)
	var att := Inventory.attuned_count(h)
	if att > 0 or inv.any(func(e): return Inventory.needs_attunement(e)):
		var al := UIKit.lbl("Attuned to %d / %d magic items" % [att, Inventory.ATTUNE_MAX], 13, UIKit.GOLD if att < Inventory.ATTUNE_MAX else UIKit.BAD)
		al.tooltip_text = "DMG p.136: you can be attuned to at most three magic items. Attuning (or ending an attunement) takes a short rest focused on the item: it happens at the next short or long rest, one item per rest."
		_body.add_child(al)
		var q := Inventory.queued(h)
		if not q.is_empty():
			_body.add_child(UIKit.lbl("Waiting for a rest: %s" % ", ".join(q.map(func(e): return ("attune to " if str(e.pend) == "on" else "end attunement to ") + Inventory.display_name(e))), 12, UIKit.MUTED))
	_infusions(h, editable)
	if str(opts.get("note", "")) != "":
		var nl := UIKit.lbl(str(opts.note), 13, UIKit.MUTED)
		nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_body.add_child(nl)
	_hands(h, editable)
	var worn := inv.filter(func(e): return e.get("eq", false) and str(e.get("in", "")) == "")
	var other := Inventory.held(h, true)
	var pack := inv.filter(func(e): return not e.get("eq", false) and not e.get("alt", false) and str(e.get("in", "")) == "")
	var bags := inv.filter(func(e): return Inventory.container_cap(e) > 0)
	_section(h, "Worn and wielded", worn, editable, bags)
	_section(h, "Other weapon set (swap to it with ⇄)", other, editable, bags)
	_section(h, "In the pack", pack, editable, bags)
	for b in bags:
		var inside := inv.filter(func(e): return str(e.get("in", "")) == str(b.uid))
		_section(h, "Inside the %s  (%s / %d lb)" % [Inventory.display_name(b), Inventory._lb_txt(Inventory.contents_lb(h, str(b.uid))), Inventory.container_cap(b)], inside, editable, bags)
	if inv.is_empty():
		_body.add_child(UIKit.lbl("Empty.", 14, UIKit.MUTED))

## An artificer's infused items (Tasha's Cauldron) and, with Replicate Magic Item, the items it can make.
func _infusions(h: Dictionary, editable: bool) -> void:
	var lv := Inventory._artificer_level(h, h)
	if lv < 2:
		return
	var row := UIKit.hbox(6)
	var n := Inventory.infused(h).size()
	var l := UIKit.lbl("Infused items: %d / %d" % [n, Inventory.infusion_limit(lv)], 13, UIKit.GOLD)
	l.tooltip_text = "Put one of your infusions on a chosen item from its ⋯ menu (Enhanced Weapon on a weapon, Enhanced Defense on armor or a shield...). End one to free the slot."
	UIKit.expand(l)
	row.add_child(l)
	if editable and "replicate_magic_item" in h.get("infusions", []) and n < Inventory.infusion_limit(lv):
		var mb := MenuButton.new()
		mb.text = "Replicate…"
		mb.flat = false
		mb.tooltip_text = "Replicate Magic Item: make one of these items. It lasts while the infusion does."
		var ids: Array = Inventory.REPLICABLE.keys().filter(func(id): return int(Inventory.REPLICABLE[id]) <= lv and not Data.item(str(id)).is_empty())
		ids.sort()
		for i in ids.size():
			mb.get_popup().add_item(str(Data.item(str(ids[i])).name), i)
		mb.get_popup().id_pressed.connect(func(i): op_requested.emit({"op": "infuse", "infusion": "replicate_magic_item", "item": str(ids[i])}))
		row.add_child(mb)
	_body.add_child(row)

## What's in hand (two hands: a two-handed weapon, two one-handed weapons, or one and a shield) and the
## button to swap to the other weapon set.
func _hands(h: Dictionary, editable: bool) -> void:
	var now := Inventory.held(h, false)
	var other := Inventory.held(h, true)
	if now.is_empty() and other.is_empty():
		return
	var row := UIKit.hbox(6)
	var l := UIKit.lbl("In hand (%d/2): %s" % [Inventory.hands_used(h, false), Inventory.set_text(now)], 13, UIKit.INK)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.tooltip_text = "You have two hands (PHB p.146-147): a two-handed weapon (bows included) leaves no room for a shield; otherwise two one-handed weapons, or one and a shield. Wielding something that doesn't fit puts away what's in the way."
	UIKit.expand(l)
	row.add_child(l)
	if editable and not other.is_empty():
		var b := UIKit.btn("⇄ Swap weapons", func(): op_requested.emit({"op": "swap"}),
			"Ready %s instead. In a fight it's your free object interaction (an action once you've had it, or if a shield goes on or off)." % Inventory.set_text(other))
		row.add_child(b)
	_body.add_child(row)

func _purse(h: Dictionary, editable: bool) -> void:
	var c := Inventory.coins(h)
	var row := UIKit.hbox(6)
	row.add_child(UIKit.lbl("Coins", 15, UIKit.GOLD))
	if opts.get("free", false) and editable:
		for k in Inventory.COINS:
			var kk: String = k
			var s := UIKit.spin(0, 9999999, int(c[k]))
			s.suffix = k
			s.custom_minimum_size = Vector2(92, 0)
			s.tooltip_text = "%s pieces (1 %s = %s)" % [str(Inventory.COIN_NAMES[k]).capitalize(), k, Inventory.fmt_cp(int(Inventory.COIN_CP[k]))]
			s.value_changed.connect(func(v): op_requested.emit({"op": "coins", "coins": {kk: int(v)}}))
			row.add_child(s)
	else:
		var l := UIKit.lbl(Inventory.fmt_coins(c), 15)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		UIKit.expand(l)
		row.add_child(l)
	_body.add_child(row)
	_body.add_child(UIKit.lbl("Worth %s in all · %d coins weigh %s lb" % [Inventory.fmt_cp(Inventory.wealth_cp(c)), Inventory.coin_count(c),
		Inventory._lb_txt(float(Inventory.coin_count(c)) / Inventory.COINS_PER_LB)], 12, UIKit.MUTED))
	# Hand coins to another party member (in the game).
	var targets: Array = opts.get("give_to", Callable()).call() if opts.get("give_to", Callable()).is_valid() else []
	if editable and not targets.is_empty():
		if _give_to == "" or not targets.any(func(t): return t[0] == _give_to):
			_give_to = str(targets[0][0])
		var gr := UIKit.hbox(4)
		var gs := UIKit.spin(1, 1000000, _give_amt, func(v): _give_amt = int(v))
		gs.custom_minimum_size = Vector2(90, 0)
		gr.add_child(gs)
		var copts: Array = []
		for k in Inventory.COINS:
			copts.append([k, k])
		gr.add_child(UIKit.option(copts, _give_coin, func(v): _give_coin = str(v)))
		gr.add_child(UIKit.lbl("to", 13, UIKit.MUTED))
		var to := UIKit.option(targets, _give_to, func(v): _give_to = str(v))
		to.fit_to_longest_item = false
		UIKit.expand(to)
		gr.add_child(to)
		gr.add_child(UIKit.btn("Give coins", func(): give_requested.emit(_give_to, "", 0, {_give_coin: _give_amt}), "Hand coins to a party member (within 5 ft in a fight)."))
		_body.add_child(gr)

func _load(h: Dictionary) -> void:
	var lb := Inventory.carried_lb(h)
	var st := 10
	var mult := 1.0
	if h.get("kind", "") == "pc" and h.has("scores"):
		st = int(h.scores.get("str", 10))
		mult = Inventory.size_mult(str(h.get("size", "medium")), h.get("tags", {}))
	else:
		var d := Rules.derive(h)
		st = int(d.scores.str)
		mult = float(d.carry_mult)
	var variant: bool = opts.get("variant", false)
	var enc := Inventory.encumbrance(lb, st, mult, variant)
	var cap := int(enc.cap)
	var col := UIKit.GOOD if int(enc.level) == 0 else (Color("#e8b84a") if int(enc.level) < 3 else UIKit.BAD)
	var row := UIKit.hbox(8)
	row.add_child(UIKit.lbl("Load %s / %d lb" % [Inventory._lb_txt(snappedf(lb, 0.01)), cap], 14, col))
	var el := UIKit.lbl(str(enc.text), 13, col)
	el.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UIKit.expand(el)
	row.add_child(el)
	row.tooltip_text = "Carrying capacity (PHB p.176): Strength %d × 15%s = %d lb. You can push, drag or lift up to %d lb, but only at 5 ft.%s" % [st,
		"" if is_equal_approx(mult, 1.0) else " × %s for size" % str(mult), cap, cap * 2,
		"\nVariant encumbrance (on): over %d lb, speed -10 ft; over %d lb, speed -20 ft and disadvantage on STR, DEX and CON rolls." % [int(st * 5 * mult), int(st * 10 * mult)] if variant else "\nVariant encumbrance (if the DM uses it): over %d lb -10 ft; over %d lb -20 ft and disadvantage." % [int(st * 5 * mult), int(st * 10 * mult)]]
	_body.add_child(row)
	var b := UIKit.bar(minf(lb, cap * 2.0), cap, col, 8)
	b.tooltip_text = row.tooltip_text
	_body.add_child(b)

func _section(h: Dictionary, title: String, entries: Array, editable: bool, bags: Array) -> void:
	if entries.is_empty():
		return
	var lb := 0.0
	for e in entries:
		lb += Inventory.unit_lb(e) * int(e.get("qty", 1))
	var shown := entries.filter(func(e): return _shows(e))
	if shown.is_empty():
		return
	_body.add_child(UIKit.lbl("%s  · %s lb" % [title, Inventory._lb_txt(snappedf(lb, 0.01))], 15, UIKit.GOLD))
	var sorted := shown.duplicate()
	match _sort:
		"name":
			sorted.sort_custom(func(a, b): return Inventory.display_name(a) < Inventory.display_name(b))
		"weight":
			sorted.sort_custom(func(a, b): return Inventory.unit_lb(a) * int(a.get("qty", 1)) > Inventory.unit_lb(b) * int(b.get("qty", 1)))
		"value":
			sorted.sort_custom(func(a, b): return Inventory.lot_price(a, int(a.get("qty", 1))) > Inventory.lot_price(b, int(b.get("qty", 1))))
		_:
			sorted.sort_custom(func(a, b): return [_rank(a), Inventory.display_name(a)] < [_rank(b), Inventory.display_name(b)])
	for e in sorted:
		_body.add_child(_row(h, e, editable, bags))

## Whether entry `e` passes the filter and search.
func _shows(e: Dictionary) -> bool:
	var d := Inventory.def(e)
	var cat := str(d.get("cat", ""))
	var ok := true
	match _filter:
		"arms": ok = not Inventory.weapon_def(e).is_empty() or not Inventory.armor_def(e).is_empty() or Inventory.is_shield(e) or cat == "ammo"
		"magic": ok = Inventory.is_magic(d)
		"use": ok = d.has("potion") or d.has("scroll") or d.has("use") or cat == "consumable"
		"gear": ok = str(d.get("kind", "")) == "gear" and not cat in ["treasure", "consumable"]
		"treasure": ok = cat == "treasure"
	if ok and _search != "":
		ok = Inventory.display_name(e).to_lower().contains(_search) or str(d.get("desc", "")).to_lower().contains(_search)
	return ok

static func _rank(e: Dictionary) -> int:
	if not Inventory.weapon_def(e).is_empty(): return 0
	if not Inventory.armor_def(e).is_empty() or Inventory.is_shield(e): return 1
	if Inventory.is_magic(Inventory.def(e)): return 2
	return 3

func _row(h: Dictionary, e: Dictionary, editable: bool, bags: Array) -> Control:
	var row := UIKit.hbox(4)
	var uid := str(e.uid)
	var n := int(e.get("qty", 1))
	var nm := Inventory.display_name(e)
	if e.has("charges") and Inventory.def(e).has("charges"):
		nm += "  (%d/%d)" % [int(e.charges), int(Inventory.def(e).charges)]
	if e.get("att", false):
		nm = "✦ " + nm
	match str(e.get("pend", "")):
		"on": nm += "  (attunes at the next rest)"
		"off": nm += "  (attunement ends at the next rest)"
	if e.get("lit", false):
		nm += "  (lit)"
	if str(e.get("infused", "")) != "":
		nm += "  ⚙ " + Data.pretty(str(e.infused).get_slice(":", 0))
	var stored: Array = e.get("stored", [])
	if not stored.is_empty():
		nm += "  [%s]" % ", ".join(stored.map(func(s): return "%s %d" % [str(Data.spell(str(s.spell)).get("name", s.spell)), int(s.level)]))
	var l := UIKit.lbl(nm, 14, Color(Inventory.rarity_color(e)) if Inventory.is_magic(Inventory.def(e)) else UIKit.INK)
	l.tooltip_text = Inventory.plain(Inventory.describe(e))
	l.mouse_filter = Control.MOUSE_FILTER_STOP
	l.clip_text = true
	l.custom_minimum_size = Vector2(120, 0)
	UIKit.expand(l)
	row.add_child(l)
	var ql := UIKit.lbl("×%d" % n if n > 1 else "", 13, UIKit.MUTED)
	ql.custom_minimum_size = Vector2(36, 0)
	row.add_child(ql)
	var wl := UIKit.lbl("%s lb" % Inventory._lb_txt(snappedf(Inventory.unit_lb(e) * n, 0.01)), 12, UIKit.MUTED)
	wl.custom_minimum_size = Vector2(52, 0)
	wl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(wl)
	if not editable:
		return row
	if Inventory.equippable(e) and str(e.get("in", "")) == "":
		var on: bool = e.get("eq", false)
		var b := UIKit.btn("Unequip" if on else _equip_word(e), func(): op_requested.emit({"op": "equip", "uid": uid, "on": not on}),
			"Armor can only be put on or taken off outside a fight. Drawing a weapon is your free object interaction; a shield takes an action.")
		b.custom_minimum_size = Vector2(78, 0)
		row.add_child(b)
	if Inventory.needs_attunement(e):
		var at: bool = e.get("att", false)
		var pend := str(e.get("pend", ""))
		# A queued change can be called off: "Cancel" keeps things as they are.
		var want_on: bool = (not at and pend != "on") or (at and pend == "off")
		var label := "End attune" if at else "Attune"
		if pend == "on":
			label = "Cancel attune"
		elif pend == "off":
			label = "Keep attuned"
		var b := UIKit.btn(label, func(): op_requested.emit({"op": "attune", "uid": uid, "on": want_on}),
			"Attuning to a magic item, or ending an attunement, takes a short rest focused on it (DMG p.136-138): the change happens at the next short or long rest, one item per rest, unless the DM allows it now. At most three attuned items.")
		b.custom_minimum_size = Vector2(96, 0)
		row.add_child(b)
	# More: pack it away, give it, drop it.
	var mb := MenuButton.new()
	mb.text = "⋯"
	mb.flat = false
	mb.tooltip_text = "More: put in a bag, store in a chest, give, drop"
	var pm := mb.get_popup()
	var acts: Array = []
	# An artificer's infusions go on chosen items (Tasha's Cauldron).
	if Inventory._artificer_level(h, h) >= 2:
		if str(e.get("infused", "")) != "":
			acts.append([{"op": "infuse", "infusion": "", "uid": uid}, "End the %s infusion" % Data.pretty(str(e.infused))])
		else:
			var used: Array = Inventory.infused(h).map(func(o): return str(o.infused))
			for inf in h.get("infusions", []):
				if str(inf) != "replicate_magic_item" and not str(inf) in used and Inventory.infusion_fits(str(inf), e):
					acts.append([{"op": "infuse", "infusion": str(inf), "uid": uid}, "Infuse: %s" % Data.pretty(str(inf))])
	# A wizard can copy a scroll's spell into the spellbook (50 gp and 2 hours per level, an Arcana check).
	if Inventory.def(e).has("scroll") and str(e.get("spell", "")) != "" and _is_wizard(h):
		acts.append([{"op": "copy", "uid": uid}, "Copy into spellbook (%s, Arcana DC %d)" % [Inventory.fmt_cp(Inventory.copy_cost(e)), 10 + int(Data.spell(str(e.spell)).get("level", 0))]])
	# A Ring of Spell Storing being worn, in play: cast one of your spells into it.
	if int(Inventory.effects(e).get("store", 0)) > 0 and h.has("slots_used") and e.get("eq", false):
		for pr in Inventory.storable(h, e):
			acts.append([{"op": "store", "uid": uid, "spell": str(pr[0]), "level": int(pr[1])}, "Store %s in it (level %d slot)" % [str(Data.spell(str(pr[0])).get("name", pr[0])), int(pr[1])]])
	if Inventory.hands_of(e) > 0 and str(e.get("in", "")) == "":
		if e.get("alt", false):
			acts.append([{"op": "wset", "uid": uid, "alt": false}, "Take out of the other weapon set"])
		elif not e.get("eq", false):
			acts.append([{"op": "wset", "uid": uid, "alt": true}, "Ready in the other weapon set"])
	if str(e.get("in", "")) != "":
		acts.append([{"op": "move", "uid": uid, "into": ""}, "Take out of the bag"])
	elif Inventory.container_cap(e) <= 0:
		for b in bags:
			acts.append([{"op": "move", "uid": uid, "into": str(b.uid)}, "Put in the %s" % Inventory.display_name(b)])
	# A storage chest within reach (in the game): leave it there to pick up later.
	var chests: Array = opts.get("stash_to", Callable()).call() if opts.get("stash_to", Callable()).is_valid() else []
	if not chests.is_empty() and Inventory.stash_problem(e, bool(Session.state.get("in_combat", false))) == "":
		for ch in chests:
			acts.append([{"stash": str(ch[0]), "uid": uid, "qty": 1}, "Store %sin the %s" % ["one " if n > 1 else "", str(ch[1])]])
			if n > 1:
				acts.append([{"stash": str(ch[0]), "uid": uid, "qty": 0}, "Store all %d in the %s" % [n, str(ch[1])]])
	var targets: Array = opts.get("give_to", Callable()).call() if opts.get("give_to", Callable()).is_valid() else []
	for t in targets:
		acts.append([{"give": str(t[0]), "qty": 1}, "Give %sto %s" % ["one " if n > 1 else "", str(t[1])]])
		if n > 1:
			acts.append([{"give": str(t[0]), "qty": 0}, "Give all %d to %s" % [n, str(t[1])]])
	acts.append([{"op": "drop", "uid": uid, "qty": 1}, "Drop one" if n > 1 else ("Drop" if opts.get("in_game", false) else "Remove")])
	if n > 1:
		acts.append([{"op": "drop", "uid": uid, "qty": 0}, "Drop all %d" % n])
	for i in acts.size():
		pm.add_item(str(acts[i][1]), i)
	pm.id_pressed.connect(func(i):
		var a: Dictionary = acts[i][0]
		if a.has("give"):
			give_requested.emit(str(a.give), uid, int(a.qty), {})
		else:
			op_requested.emit(a))
	row.add_child(mb)
	return row

static func _is_wizard(h: Dictionary) -> bool:
	if int(h.get("class_levels", {}).get("wizard", 0)) > 0:
		return true
	return h.get("classes", []).any(func(c): return str(c.get("id", "")) == "wizard")

static func _equip_word(e: Dictionary) -> String:
	if not Inventory.armor_def(e).is_empty(): return "Wear"
	if Inventory.is_shield(e): return "Hold"
	if not Inventory.weapon_def(e).is_empty(): return "Wield"
	return "Wear"
