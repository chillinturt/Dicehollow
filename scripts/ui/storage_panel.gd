class_name StoragePanel
extends VBoxContainer
## A storage chest beside a character: what the character carries on the left, what the chest holds on the
## right, with buttons to store things and take them back, and coins either way. Every change is asked of the
## server through request_made ({"type": "stash", "obj", "op": "put" | "take", "uid", "qty"} or "coins").

signal request_made(req: Dictionary)

var holder_fn: Callable   # () -> the character (combatant)
var obj_fn: Callable      # () -> the chest (map object)
var _body: VBoxContainer
var _search := ""
var _coin_amt := 10
var _coin_kind := "gp"

func _init(holder: Callable, chest: Callable) -> void:
	holder_fn = holder
	obj_fn = chest
	add_theme_constant_override("separation", 6)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Kept outside the rebuilt body so typing doesn't lose focus.
	var se := UIKit.line("", "Search both sides…", func(t):
		_search = str(t).to_lower()
		refresh())
	add_child(se)
	_body = UIKit.vbox(6)
	add_child(_body)
	refresh()

func refresh() -> void:
	UIKit.clear(_body)
	var c: Dictionary = holder_fn.call()
	var o: Dictionary = obj_fn.call()
	if c.is_empty() or o.is_empty():
		_body.add_child(UIKit.lbl("The chest isn't there any more.", 14, UIKit.MUTED))
		return
	var st: Dictionary = o.get("store", {}) if o.get("store", null) is Dictionary else {}
	var intro := UIKit.lbl("Leave what you don't want to carry here and come back for it. Anyone in the party can take things out. Saving the map keeps what's inside for another session.", 12, UIKit.MUTED)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(intro)
	if Session.state.get("in_combat", false):
		var fl := UIKit.lbl("In a fight, each item or handful of coins is your free object interaction (then an action), on your turn.", 12, Color("#e8b84a"))
		fl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_body.add_child(fl)
	_coins_row(c, st)
	var cols := UIKit.hbox(14)
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(cols)
	var left := UIKit.vbox(4)
	UIKit.expand(left)
	cols.add_child(left)
	cols.add_child(VSeparator.new())
	var right := UIKit.vbox(4)
	UIKit.expand(right)
	cols.add_child(right)
	var mine: Array = Inventory.list(c)
	left.add_child(UIKit.lbl("%s carries  · %s lb" % [str(c.get("name", "?")), Inventory._lb_txt(snappedf(Inventory.carried_lb(c), 0.1))], 15, UIKit.GOLD))
	_list(left, c, mine, "put")
	var inside: Array = st.get("inventory", [])
	var lb := 0.0
	for e in inside:
		lb += Inventory.unit_lb(e) * int(e.get("qty", 1))
	right.add_child(UIKit.lbl("In the %s  · %s lb" % [MapObjects.name_of(o).to_lower(), Inventory._lb_txt(snappedf(lb, 0.1))], 15, UIKit.GOLD))
	_list(right, c, inside, "take")

## Coins: how many of which kind, and a button each way.
func _coins_row(c: Dictionary, st: Dictionary) -> void:
	var have := Inventory.coins(c)
	var held: Dictionary = st.get("coins", {})
	_body.add_child(UIKit.lbl("Coins — you: %s   ·   chest: %s" % [Inventory.fmt_coins(have), Inventory.fmt_coins(held)], 14, UIKit.INK))
	var row := UIKit.hbox(4)
	var s := UIKit.spin(1, 10000000, _coin_amt, func(v): _coin_amt = int(v))
	s.custom_minimum_size = Vector2(110, 0)
	row.add_child(s)
	var copts: Array = []
	for k in Inventory.COINS:
		copts.append([k, k])
	row.add_child(UIKit.option(copts, _coin_kind, func(v): _coin_kind = str(v)))
	row.add_child(UIKit.btn("Store coins →", func(): _ask({"op": "put", "coins": {_coin_kind: _coin_amt}}), "Put that many coins in the chest (as many as you have, if fewer)."))
	row.add_child(UIKit.btn("← Take coins", func(): _ask({"op": "take", "coins": {_coin_kind: _coin_amt}}), "Take that many coins out of the chest (as many as it holds, if fewer)."))
	var all_in := UIKit.btn("Store all coins", func(): _ask({"op": "put", "coins": have.duplicate()}), "Put every coin you carry in the chest.")
	all_in.disabled = Inventory.coin_count(have) == 0
	row.add_child(all_in)
	var all_out := UIKit.btn("Take all coins", func(): _ask({"op": "take", "coins": held.duplicate()}), "Take every coin out of the chest.")
	all_out.disabled = Inventory.coin_count(held) == 0
	row.add_child(all_out)
	_body.add_child(row)

func _list(box: VBoxContainer, c: Dictionary, entries: Array, op: String) -> void:
	var shown := entries.filter(func(e): return _search == "" or Inventory.display_name(e).to_lower().contains(_search))
	if shown.is_empty():
		box.add_child(UIKit.lbl("Nothing." if entries.is_empty() else "Nothing matches.", 13, UIKit.MUTED))
		return
	shown.sort_custom(func(a, b): return [InventoryPanel._rank(a), Inventory.display_name(a)] < [InventoryPanel._rank(b), Inventory.display_name(b)])
	var fighting: bool = Session.state.get("in_combat", false)
	for e in shown:
		box.add_child(_row(c, e, op, fighting))

func _row(c: Dictionary, e: Dictionary, op: String, fighting: bool) -> Control:
	var row := UIKit.hbox(4)
	var uid := str(e.get("uid", ""))
	var n := int(e.get("qty", 1))
	var nm := Inventory.display_name(e)
	if e.has("charges") and Inventory.def(e).has("charges"):
		nm += "  (%d/%d)" % [int(e.charges), int(Inventory.def(e).charges)]
	if op == "put":
		if e.get("att", false):
			nm = "✦ " + nm
		if e.get("eq", false):
			nm += "  (worn)" if not Inventory.armor_def(e).is_empty() or Inventory.weapon_def(e).is_empty() else "  (in hand)"
		elif str(e.get("in", "")) != "" and not Inventory.find(c, str(e.in)).is_empty():
			nm += "  (in the %s)" % Inventory.display_name(Inventory.find(c, str(e.in)))
	var l := UIKit.lbl(nm, 14, Color(Inventory.rarity_color(e)) if Inventory.is_magic(Inventory.def(e)) else UIKit.INK)
	l.tooltip_text = Inventory.plain(Inventory.describe(e))
	l.mouse_filter = Control.MOUSE_FILTER_STOP
	# Two columns leave little room: long names wrap rather than being cut off.
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(110, 0)
	UIKit.expand(l)
	row.add_child(l)
	var ql := UIKit.lbl("×%d" % n if n > 1 else "", 13, UIKit.MUTED)
	ql.custom_minimum_size = Vector2(40, 0)
	row.add_child(ql)
	var wl := UIKit.lbl("%s lb" % Inventory._lb_txt(snappedf(Inventory.unit_lb(e) * n, 0.01)), 12, UIKit.MUTED)
	wl.custom_minimum_size = Vector2(52, 0)
	wl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(wl)
	var why := Inventory.stash_problem(e, fighting) if op == "put" else ""
	var word := "Store" if op == "put" else "Take"
	var b1 := UIKit.btn(("%s 1" % word) if n > 1 else ("%s →" % word if op == "put" else "← %s" % word),
		func(): _ask({"op": op, "uid": uid, "qty": 1}), why if why != "" else ("Put it in the chest." if op == "put" else "Take it back."))
	b1.disabled = why != ""
	b1.custom_minimum_size = Vector2(74, 0)
	row.add_child(b1)
	if n > 1:
		var b2 := UIKit.btn("%s all" % word, func(): _ask({"op": op, "uid": uid, "qty": 0}), why if why != "" else "All %d." % n)
		b2.disabled = why != ""
		b2.custom_minimum_size = Vector2(74, 0)
		row.add_child(b2)
	return row

func _ask(r: Dictionary) -> void:
	request_made.emit(r)
