class_name ItemPicker
extends VBoxContainer
## Pick any item to add or hand out: a category, the item, and when it applies the weapon or armor a magic
## item is made from, a scroll's spell, a damage type, and how many. Used by the character builder
## ("Add item") and the DM's Loot tab. current() returns {"id", "qty", "base", "spell", "dtype"}.

const CATS := [["weapon", "Weapons"], ["armor", "Armor & shields"], ["gear", "Adventuring gear"], ["consumable", "Consumables"],
	["tool", "Tools & focuses"], ["pack", "Equipment packs"], ["treasure", "Gems & art"], ["magic", "Magic items"]]

var cat := "magic"
var id := ""
var base := ""
var spell := ""
var dtype := "fire"
var qty := 1
var _row2: HBoxContainer
var _items_opt: OptionButton
var _show_qty := true

func _init(start_cat := "magic", show_qty := true) -> void:
	cat = start_cat
	_show_qty = show_qty
	add_theme_constant_override("separation", 4)
	var r1 := UIKit.hbox(4)
	var co := UIKit.option(CATS, cat, func(k):
		cat = k
		id = ""
		_fill())
	co.fit_to_longest_item = false
	co.custom_minimum_size = Vector2(150, 0)
	r1.add_child(co)
	_items_opt = OptionButton.new()
	_items_opt.fit_to_longest_item = false
	UIKit.expand(_items_opt)
	_items_opt.item_selected.connect(func(i):
		id = str(_items_opt.get_item_metadata(i))
		base = ""
		spell = ""
		_fill_details())
	r1.add_child(_items_opt)
	add_child(r1)
	_row2 = UIKit.hbox(4)
	add_child(_row2)
	_fill()

static func _in_cat(d: Dictionary, k: String) -> bool:
	var kind := str(d.get("kind", ""))
	var c := str(d.get("cat", ""))
	match k:
		"weapon": return kind == "weapon" or (kind == "special" and str(d.get("base_kind", "")) == "weapon")
		"armor": return kind in ["armor", "shield"]
		"gear": return (kind == "gear" and c in ["adventuring", "food", "light", "clothing", "ammo"]) or (kind == "special" and str(d.get("base_kind", "")) == "ammo")
		"consumable": return kind == "gear" and c == "consumable"
		"tool": return kind == "gear" and c in ["tool", "focus"]
		"pack": return kind == "gear" and c == "pack"
		"treasure": return kind == "gear" and c == "treasure"
		"magic": return kind == "magic"
	return false

func _fill() -> void:
	_items_opt.clear()
	var arr: Array = Data.items.values().filter(func(d): return _in_cat(d, cat))
	arr.sort_custom(func(a, b):
		var ra := Inventory.RARITIES.find(str(a.get("rarity", "")))
		var rb := Inventory.RARITIES.find(str(b.get("rarity", "")))
		return [ra, str(a.name)] < [rb, str(b.name)])
	for i in arr.size():
		var d: Dictionary = arr[i]
		var lbl := str(d.name)
		if str(d.get("rarity", "")) != "":
			lbl += "  (%s)" % str(d.rarity).replace("_", " ")
		_items_opt.add_item(lbl, i)
		_items_opt.set_item_metadata(i, str(d.id))
	if not arr.is_empty():
		var idx := 0
		for i in arr.size():
			if str(arr[i].id) == id:
				idx = i
		_items_opt.select(idx)
		id = str(arr[idx].id)
	_fill_details()

func _fill_details() -> void:
	UIKit.clear(_row2)
	var d := Data.item(id)
	_items_opt.tooltip_text = Inventory.plain(Inventory.describe({"id": id})) if not d.is_empty() else ""
	if str(d.get("base_kind", "")) != "":
		var opts: Array = []
		for b in Inventory.bases_for(d):
			opts.append([str(b.id), str(b.name)])
		if base == "" or not opts.any(func(o): return o[0] == base):
			base = str(opts[0][0]) if not opts.is_empty() else ""
		var bo := UIKit.option(opts, base, func(v): base = str(v))
		bo.fit_to_longest_item = false
		bo.tooltip_text = "Which %s it is" % str(d.base_kind)
		UIKit.expand(bo)
		_row2.add_child(bo)
	if d.has("scroll"):
		var lv := int(d.scroll.level)
		var opts: Array = [["", "Random spell"]]
		var sps: Array = Data.spells.values().filter(func(s): return int(s.get("level", -1)) == lv and s.get("combat", null) is Dictionary)
		sps.sort_custom(func(a, b): return str(a.name) < str(b.name))
		for s in sps:
			opts.append([str(s.id), str(s.name)])
		var so := UIKit.option(opts, spell, func(v): spell = str(v))
		so.fit_to_longest_item = false
		UIKit.expand(so)
		_row2.add_child(so)
	if d.get("choose_dtype", false):
		var opts: Array = []
		for t in Inventory.DAMAGE_CHOICES:
			opts.append([t, t.capitalize()])
		_row2.add_child(UIKit.option(opts, dtype, func(v): dtype = str(v)))
	if _show_qty:
		var qs := UIKit.spin(1, 100, qty, func(v): qty = int(v))
		qs.prefix = "×"
		qs.custom_minimum_size = Vector2(80, 0)
		_row2.add_child(qs)

func current() -> Dictionary:
	return {"id": id, "qty": qty, "base": base, "spell": spell, "dtype": dtype if Data.item(id).get("choose_dtype", false) else ""}
