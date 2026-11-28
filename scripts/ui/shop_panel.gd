class_name ShopPanel
extends VBoxContainer
## Buy from a shop's stock and sell your own gear (PHB p.144: a shop pays half the price for equipment in
## good condition, unless the DM sets another rate). Shared by the character builder (Player's Handbook
## prices) and the game (the shop the DM opened). Purchases and sales are emitted as Inventory.apply_op
## operations ("buy" / "sell") through op_requested.

signal op_requested(op: Dictionary)

const FILTERS := [["all", "Everything"], ["weapon", "Weapons"], ["armor", "Armor & shields"], ["gear", "Adventuring gear"],
	["consumable", "Consumables"], ["tool", "Tools & focuses"], ["pack", "Packs"], ["treasure", "Gems & art"], ["magic", "Magic items"]]

var holder_fn: Callable
var shop_fn: Callable
var _mode := "buy"
var _filter := "all"
var _search := ""
var _bases := {}   # item id -> chosen base
var _qty := {}     # item id -> how many
var _head: VBoxContainer
var _list: VBoxContainer
var _search_edit: LineEdit

func _init(holder: Callable, shop: Callable) -> void:
	holder_fn = holder
	shop_fn = shop
	add_theme_constant_override("separation", 6)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_head = UIKit.vbox(4)
	add_child(_head)
	var tabs := UIKit.hbox(4)
	for m in [["buy", "Buy"], ["sell", "Sell"]]:
		var mm: String = m[0]
		var b := UIKit.btn(m[1], func():
			_mode = mm
			refresh())
		b.toggle_mode = true
		b.set_meta("mode", mm)
		b.custom_minimum_size = Vector2(90, 0)
		tabs.add_child(b)
	var fo := UIKit.option(FILTERS, _filter, func(v):
		_filter = str(v)
		refresh())
	fo.fit_to_longest_item = false
	tabs.add_child(fo)
	_search_edit = UIKit.line("", "Search…", func(t):
		_search = str(t).to_lower()
		_fill())
	UIKit.expand(_search_edit)
	tabs.add_child(_search_edit)
	add_child(tabs)
	_list = UIKit.vbox(3)
	add_child(_list)
	refresh()

func refresh() -> void:
	for b in get_child(1).get_children():
		if b is Button and b.has_meta("mode"):
			b.button_pressed = b.get_meta("mode") == _mode
	UIKit.clear(_head)
	var h: Dictionary = holder_fn.call()
	var shop: Dictionary = shop_fn.call()
	if shop.is_empty():
		_head.add_child(UIKit.lbl("The shop is closed.", 15, UIKit.MUTED))
		UIKit.clear(_list)
		return
	var top := UIKit.hbox(8)
	top.add_child(UIKit.lbl(str(shop.get("name", "Shop")), 17, UIKit.GOLD))
	var info := UIKit.lbl("Prices %d%% · buys gear at %d%%, magic at %d%%" % [int(shop.get("markup", 100)), int(shop.get("buyback", 50)), int(shop.get("magic_buyback", 25))], 13, UIKit.MUTED)
	info.tooltip_text = "Prices are the Player's Handbook list prices times the shop's markup. It pays this share of the list price for what you sell (PHB: half)."
	UIKit.expand(info)
	top.add_child(info)
	_head.add_child(top)
	_head.add_child(UIKit.lbl("Your purse: %s  (%s)" % [Inventory.fmt_coins(Inventory.coins(h)), Inventory.fmt_cp(Inventory.wealth_cp(Inventory.coins(h)))], 14))
	_fill()

func _fill() -> void:
	UIKit.clear(_list)
	var h: Dictionary = holder_fn.call()
	var shop: Dictionary = shop_fn.call()
	if shop.is_empty() or h.is_empty():
		return
	if _mode == "buy":
		_fill_buy(h, shop)
	else:
		_fill_sell(h, shop)

func _match(d: Dictionary, name: String) -> bool:
	if _filter != "all" and not ItemPicker._in_cat(d, _filter):
		return false
	return _search == "" or name.to_lower().contains(_search) or str(d.get("desc", "")).to_lower().contains(_search)

func _fill_buy(h: Dictionary, shop: Dictionary) -> void:
	var wealth := Inventory.wealth_cp(Inventory.coins(h))
	var n := 0
	for id in shop.get("stock", []):
		var d := Data.item(str(id))
		if d.is_empty() or not _match(d, str(d.name)):
			continue
		n += 1
		if n > 150:
			_list.add_child(UIKit.lbl("…more: narrow it down with the filter or search.", 13, UIKit.MUTED))
			break
		var iid := str(id)
		var row := UIKit.hbox(4)
		var probe := {"id": iid, "base": str(_bases.get(iid, ""))}
		var bk := str(d.get("base_kind", ""))
		if bk != "" and probe.base == "":
			var bs := Inventory.bases_for(d)
			if not bs.is_empty():
				probe.base = str(bs[0].id)
				_bases[iid] = probe.base
		var title := str(d.name)
		if Inventory.bundle_of(d) > 1:
			title += " (%d)" % Inventory.bundle_of(d)
		var left := Inventory.stock_left(shop, iid)
		if left >= 0:
			title += "  · %d left" % left
		var nm := UIKit.lbl(title, 14, Color(Inventory.rarity_color(probe)) if Inventory.is_magic(d) else UIKit.INK)
		nm.tooltip_text = Inventory.plain(Inventory.describe(probe))
		nm.mouse_filter = Control.MOUSE_FILTER_STOP
		nm.clip_text = true
		nm.custom_minimum_size = Vector2(140, 0)
		UIKit.expand(nm)
		row.add_child(nm)
		if bk != "":
			var opts: Array = []
			for b in Inventory.bases_for(d):
				opts.append([str(b.id), str(b.name)])
			var bo := UIKit.option(opts, probe.base, func(v):
				_bases[iid] = str(v)
				_fill())
			bo.fit_to_longest_item = false
			bo.custom_minimum_size = Vector2(130, 0)
			row.add_child(bo)
		var each := Inventory.shop_price(probe, shop)
		var q := int(_qty.get(iid, 1))
		var wl := UIKit.lbl("%s lb" % Inventory._lb_txt(Inventory.unit_lb(probe) * Inventory.bundle_of(d)), 12, UIKit.MUTED)
		wl.custom_minimum_size = Vector2(48, 0)
		wl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(wl)
		var pl := UIKit.lbl(Inventory.fmt_cp(each), 13, UIKit.GOLD if each <= wealth else UIKit.BAD)
		pl.custom_minimum_size = Vector2(96, 0)
		pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(pl)
		if Inventory.stackable(probe) and not d.has("contents"):
			var qs := UIKit.spin(1, 99, q, func(v): _qty[iid] = int(v))
			qs.custom_minimum_size = Vector2(70, 0)
			row.add_child(qs)
		var b := UIKit.btn("Buy", func():
			var qn := int(_qty.get(iid, 1)) if Inventory.stackable(probe) and not d.has("contents") else 1
			op_requested.emit({"op": "buy", "id": iid, "qty": qn, "base": str(_bases.get(iid, ""))}), "Buy for %s each" % Inventory.fmt_cp(each))
		b.disabled = each > wealth
		if b.disabled:
			b.tooltip_text = "You can't afford it (%s)." % Inventory.fmt_cp(each)
		row.add_child(b)
		_list.add_child(row)
	if n == 0:
		_list.add_child(UIKit.lbl("Nothing like that in stock.", 14, UIKit.MUTED))

func _fill_sell(h: Dictionary, shop: Dictionary) -> void:
	var any := false
	for e in Inventory.list(h):
		var d := Inventory.def(e)
		var nm := Inventory.display_name(e)
		if d.get("cat", "") == "pack" or not _match(d, nm):
			continue
		any = true
		var uid := str(e.uid)
		var n := int(e.get("qty", 1))
		var row := UIKit.hbox(4)
		var l := UIKit.lbl(nm + ("  ×%d" % n if n > 1 else "") + ("  (equipped)" if e.get("eq", false) else ""), 14, Color(Inventory.rarity_color(e)) if Inventory.is_magic(d) else UIKit.INK)
		l.tooltip_text = Inventory.plain(Inventory.describe(e))
		l.mouse_filter = Control.MOUSE_FILTER_STOP
		l.clip_text = true
		l.custom_minimum_size = Vector2(140, 0)
		UIKit.expand(l)
		row.add_child(l)
		var each := Inventory.sell_price(e, shop)
		var all := Inventory.sell_total(e, shop, n)
		var bn := Inventory.bundle_of(d)
		var ptxt := Inventory.fmt_cp(each) + " each" if n > 1 else Inventory.fmt_cp(each)
		if bn > 1:
			ptxt = "%s for all" % Inventory.fmt_cp(all)
		var pl := UIKit.lbl(ptxt, 13, UIKit.GOLD)
		pl.custom_minimum_size = Vector2(110, 0)
		pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		pl.tooltip_text = "The shop pays %d%% of the list price%s." % [Inventory.buy_rate(e, shop), " (gems, art and trade goods keep their full value)" if Inventory.buy_rate(e, shop) == 100 else (" for magic items" if Inventory.is_magic(d) else "")]
		row.add_child(pl)
		if bn <= 1:
			row.add_child(UIKit.btn("Sell", func(): op_requested.emit({"op": "sell", "uid": uid, "qty": 1}), "Sell one for %s" % Inventory.fmt_cp(each)))
		if n > 1:
			row.add_child(UIKit.btn("Sell all", func(): op_requested.emit({"op": "sell", "uid": uid, "qty": n}), "Sell all %d for %s" % [n, Inventory.fmt_cp(all)]))
		_list.add_child(row)
	if not any:
		_list.add_child(UIKit.lbl("Nothing to sell.", 14, UIKit.MUTED))
