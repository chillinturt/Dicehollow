class_name Inventory
extends RefCounted
## Characters' belongings under the 2014 rules: coins, gear, equipped weapons and armor, magic items and
## attunement, carrying capacity and encumbrance, shops, and the items a character can use in a fight.
##
## A character sheet (and the combatant built from it) holds:
##   "coins":     {"pp", "gp", "ep", "sp", "cp"} (PHB p.143; 50 coins weigh a pound)
##   "inventory": [entry, ...], each entry {"uid", "id", "qty"} plus, when they apply:
##       "eq"      equipped: armor worn, shield or weapon at hand, ring / cloak / boots... worn, light lit
##       "att"     attuned (DMG p.136-138: at most three items, and only outside combat)
##       "base"    the weapon or armor a magic variant is made from ("+1 Weapon" + "longsword")
##       "charges" charges left (wands, a healer's kit), "spell" a scroll's spell, "dtype" a damage type
##       "in"      the uid of the container it's in (a Bag of Holding: its contents weigh nothing)
##       "alt"     a weapon or shield in the other weapon set (swapped in with one object interaction)
##       "pend"    an attunement change waiting for the next rest ("on" / "off", in "pend_n" order)
##       "pcs"     ammunition counted in pieces (older sheets counted bundles; ensure() converts them)
##       "lit"     a Flame Tongue or Sun Blade switched on; "stored" a Ring of Spell Storing's spells;
##       "infused" an artificer infusion on it (a "replicate_magic_item" entry only exists while infused)
## The sheet's old "equipment" block ({armor, shield, weapons, weapon_bonus, armor_bonus}) is now worked out
## from the inventory (see equipment_of / sync_equipment); sheets made before inventories are converted by
## ensure(). Items are defined in data/items*.json (prices in copper pieces, weights in pounds).

const COINS := ["pp", "gp", "ep", "sp", "cp"]
const COIN_CP := {"cp": 1, "sp": 10, "ep": 50, "gp": 100, "pp": 1000}
const COIN_NAMES := {"pp": "platinum", "gp": "gold", "ep": "electrum", "sp": "silver", "cp": "copper"}
const COINS_PER_LB := 50
const ATTUNE_MAX := 3
## DMG p.141: one cloak, pair of boots, gloves or bracers, headwear, amulet, belt and pair of eyewear; two rings.
const SLOT_MAX := {"ring": 2, "cloak": 1, "hands": 1, "head": 1, "neck": 1, "belt": 1, "boots": 1, "eyes": 1}
const SLOT_NAMES := {"ring": "rings", "cloak": "a cloak", "hands": "gloves or bracers", "head": "headwear", "neck": "an amulet",
	"belt": "a belt", "boots": "boots", "eyes": "eyewear"}
const RARITIES := ["common", "uncommon", "rare", "very_rare", "legendary"]
const RARITY_COLORS := {"common": "#d8d0bd", "uncommon": "#5cc892", "rare": "#4aa3ff", "very_rare": "#b07cff", "legendary": "#ff9c40"}
## PHB p.143: starting wealth by class, [d4s, multiplier]. Artificer: Tasha's Cauldron.
const STARTING_GOLD := {"barbarian": [2, 10], "bard": [5, 10], "cleric": [5, 10], "druid": [2, 10], "fighter": [5, 10],
	"monk": [5, 1], "paladin": [5, 10], "ranger": [5, 10], "rogue": [4, 10], "sorcerer": [3, 10], "warlock": [4, 10],
	"wizard": [4, 10], "artificer": [5, 10]}
## The equipment pack each class's starting equipment offers (PHB chapter 3), and the class's other kit.
const CLASS_PACK := {"barbarian": "explorers_pack", "bard": "entertainers_pack", "cleric": "priests_pack", "druid": "explorers_pack",
	"fighter": "dungeoneers_pack", "monk": "dungeoneers_pack", "paladin": "priests_pack", "ranger": "explorers_pack",
	"rogue": "burglars_pack", "sorcerer": "dungeoneers_pack", "warlock": "scholars_pack", "wizard": "scholars_pack", "artificer": "dungeoneers_pack"}
const CLASS_KIT := {"cleric": ["holy_symbol_amulet"], "paladin": ["holy_symbol_emblem"], "wizard": ["spellbook", "component_pouch"],
	"sorcerer": ["component_pouch"], "warlock": ["component_pouch"], "druid": ["druidic_focus_mistletoe"], "rogue": ["thieves_tools"],
	"artificer": ["thieves_tools", "tinkers_tools"], "bard": ["lute"], "monk": [], "fighter": [], "barbarian": [], "ranger": []}
## Gold in each background's starting equipment (PHB and the other books' backgrounds).
const BACKGROUND_GOLD := {"acolyte": 15, "charlatan": 15, "criminal": 15, "entertainer": 15, "folk_hero": 10, "guild_artisan": 15,
	"hermit": 5, "noble": 25, "outlander": 10, "sage": 10, "sailor": 10, "soldier": 10, "urchin": 10, "haunted_one": 1,
	"far_traveler": 5, "city_watch": 10, "clan_crafter": 5, "cloistered_scholar": 10}
## What each background's starting equipment adds to the pack (PHB chapter 4 and the other backgrounds;
## trinkets, letters and keepsakes with no game use are left out). Gold: see BACKGROUND_GOLD.
const BACKGROUND_KIT := {"acolyte": ["holy_symbol_amulet", "book", "robes", "clothes_common", "pouch"],
	"charlatan": ["clothes_fine", "disguise_kit", "pouch"], "criminal": ["crowbar", "clothes_common", "pouch"],
	"entertainer": ["lute", "clothes_costume", "pouch"], "folk_hero": ["carpenters_tools", "shovel", "pot_iron", "clothes_common", "pouch"],
	"guild_artisan": ["smiths_tools", "clothes_travelers", "pouch"], "hermit": ["case_map", "blanket", "clothes_common", "herbalism_kit"],
	"noble": ["clothes_fine", "pouch"], "outlander": ["quarterstaff", "hunting_trap", "clothes_travelers", "pouch"],
	"sage": ["ink", "ink_pen", "clothes_common", "pouch"], "sailor": ["club", "rope_silk", "clothes_common", "pouch"],
	"soldier": ["dice_set", "clothes_common", "pouch"], "urchin": ["dagger", "clothes_common", "pouch"],
	"haunted_one": ["chest", "clothes_common", "pouch"], "far_traveler": ["clothes_travelers", "lute", "pouch"],
	"city_watch": ["manacles", "signal_whistle", "clothes_common", "pouch"], "clan_crafter": ["smiths_tools", "clothes_travelers", "pouch"],
	"cloistered_scholar": ["robes", "ink", "ink_pen", "parchment", "pouch"]}
## Tool proficiencies (PHB chapters 2-4). Where a class, background or race lets you pick one ("an artisan's
## tool of your choice", "one gaming set"), the first listed is the default: a sheet can name others in its
## "tools" list. First class / multiclassing into the class.
const CLASS_TOOLS := {"rogue": ["thieves_tools"], "artificer": ["thieves_tools", "tinkers_tools"], "druid": ["herbalism_kit"],
	"bard": ["lute", "flute", "lyre"], "monk": ["brewers_supplies"]}
const MC_CLASS_TOOLS := {"rogue": ["thieves_tools"], "artificer": ["thieves_tools", "tinkers_tools"], "bard": ["lute"]}
const BACKGROUND_TOOLS := {"charlatan": ["disguise_kit", "forgery_kit"], "criminal": ["dice_set", "thieves_tools"],
	"entertainer": ["disguise_kit", "lute"], "folk_hero": ["carpenters_tools"], "guild_artisan": ["smiths_tools"],
	"hermit": ["herbalism_kit"], "noble": ["playing_cards"], "outlander": ["flute"], "sailor": ["navigators_tools"],
	"soldier": ["dice_set"], "urchin": ["disguise_kit", "thieves_tools"], "far_traveler": ["lute"], "clan_crafter": ["smiths_tools"]}
const RACE_TOOLS := {"dwarf": ["smiths_tools"], "gnome/rock": ["tinkers_tools"]}
## Artificer infusions (Tasha's Cauldron) put on one chosen item each. WEAPON_INFUSIONS go on a weapon.
const WEAPON_INFUSIONS := ["enhanced_weapon", "repeating_shot", "radiant_weapon"]
## Replicate Magic Item: what an artificer of at least this level can make (the ones the game has).
const REPLICABLE := {"bag_of_holding": 2, "goggles_of_night": 2, "boots_of_elvenkind": 6, "cloak_of_elvenkind": 6,
	"boots_of_striding_and_springing": 10, "brooch_of_shielding": 10, "cloak_of_protection": 10, "gauntlets_of_ogre_power": 10,
	"gloves_of_missile_snaring": 10, "headband_of_intellect": 10, "periapt_of_wound_closure": 10, "winged_boots": 10,
	"amulet_of_health": 14, "belt_of_hill_giant_strength": 14, "boots_of_speed": 14, "bracers_of_defense": 14, "ring_of_protection": 14}
## Shops the DM can open, and what they sell.
const SHOPS := {
	"general": {"name": "General Store", "blurb": "Adventuring gear, food, light, rope, tools and packs."},
	"smith": {"name": "Blacksmith & Armorer", "blurb": "Weapons, armor, shields and ammunition."},
	"alchemist": {"name": "Alchemist & Apothecary", "blurb": "Potions of healing, acid, alchemist's fire, antitoxin, holy water, healer's kits."},
	"magic": {"name": "Magic Shop", "blurb": "Magic items up to the rarity you allow."},
	"everything": {"name": "Grand Bazaar", "blurb": "Every mundane item in the Player's Handbook."},
}
const DAMAGE_CHOICES := ["acid", "cold", "fire", "force", "lightning", "necrotic", "poison", "psychic", "radiant", "thunder"]

# ================================================================ items and entries

static func def(entry: Dictionary) -> Dictionary:
	return Data.item(str(entry.get("id", "")))

static func base_def(entry: Dictionary) -> Dictionary:
	return Data.item(str(entry.get("base", "")))

static func is_magic(d: Dictionary) -> bool:
	return str(d.get("kind", "")) == "magic"

## "weapon", "armor", "shield", "gear", or a magic item's type ("potion", "wondrous", "ring", "wand"...).
static func type_of(entry: Dictionary) -> String:
	var d := def(entry)
	if is_magic(d):
		return str(d.get("type", "wondrous"))
	return str(d.get("kind", "gear"))

## The weapon this entry fights as ({} if none): a weapon, or a magic weapon's base.
static func weapon_def(entry: Dictionary) -> Dictionary:
	var d := def(entry)
	if str(d.get("kind", "")) == "weapon":
		return d
	# A magic weapon, or a mundane variant (a silvered weapon), fights as its base weapon.
	if str(d.get("base_kind", "")) == "weapon":
		return base_def(entry)
	return {}

static func armor_def(entry: Dictionary) -> Dictionary:
	var d := def(entry)
	if str(d.get("kind", "")) == "armor":
		return d
	if str(d.get("base_kind", "")) == "armor":
		return base_def(entry)
	return {}

## A weapon whose power is switched on with a bonus action (Flame Tongue's fire, a Sun Blade's blade):
## {"ft": light it sheds, "hilt": no blade (and no attack) until lit}, or {}.
static func ignite_of(entry: Dictionary) -> Dictionary:
	var ig = effects(entry).get("ignite", {})
	return ig if ig is Dictionary else {}

static func is_shield(entry: Dictionary) -> bool:
	var d := def(entry)
	return str(d.get("kind", "")) == "shield" or (is_magic(d) and str(d.get("type", "")) == "shield")

static func effects(entry: Dictionary) -> Dictionary:
	var e = def(entry).get("effects", {})
	return e if e is Dictionary else {}

static func rarity(entry: Dictionary) -> String:
	return str(def(entry).get("rarity", ""))

static func rarity_color(entry: Dictionary) -> String:
	return str(RARITY_COLORS.get(rarity(entry), "#ece6d8"))

static func needs_attunement(entry: Dictionary) -> bool:
	var a = def(entry).get("attune", false)
	return (a is bool and a) or (a is String and a != "")

## Things you wear or wield to use: weapons, armor, shields, worn wondrous items and rings, light sources.
static func equippable(entry: Dictionary) -> bool:
	var d := def(entry)
	if not weapon_def(entry).is_empty() or not armor_def(entry).is_empty() or is_shield(entry):
		return true
	if d.has("light"):
		return false   # lit with the Light action, not equipped
	return str(d.get("slot", "")) != ""

static func display_name(entry: Dictionary) -> String:
	var d := def(entry)
	if d.is_empty():
		return Data.pretty(str(entry.get("id", "?")))
	var nm := str(d.get("name", entry.id))
	if str(entry.get("base", "")) != "" and d.has("name_fmt"):
		nm = (str(d.name_fmt) % str(base_def(entry).get("name", entry.base))) if "%s" in str(d.name_fmt) else str(d.name_fmt)
	if str(entry.get("spell", "")) != "":
		nm = "Scroll of %s" % str(Data.spell(str(entry.spell)).get("name", entry.spell))
	if str(entry.get("dtype", "")) != "":
		nm += " (%s)" % str(entry.dtype)
	return nm

## Ammunition is sold in bundles (20 arrows for 1 gp) but carried and shot one piece at a time: the item's
## price and weight are for the bundle, an entry's qty counts pieces.
static func bundle_of(d: Dictionary) -> int:
	return maxi(1, int(d.get("bundle", 1)))

## Weight of one of these, in pounds.
static func unit_lb(entry: Dictionary) -> float:
	var d := def(entry)
	# An equipment pack weighs what's in it.
	if d.get("contents", null) is Array:
		var t := 0.0
		for pair in d.contents:
			t += float(Data.item(str(pair[0])).get("lb", 0)) * int(pair[1]) / bundle_of(Data.item(str(pair[0])))
		return t
	if d.has("lb"):
		return float(d.lb) / bundle_of(d)
	var b := base_def(entry)
	return float(b.get("lb", 0)) / bundle_of(b)

## List price of what a shop sells as one, in copper pieces: one item, or one bundle of ammunition. A magic
## or silvered weapon, armor or piece of ammunition also costs its base item (one piece of a bundle).
static func unit_price(entry: Dictionary) -> int:
	var d := def(entry)
	var p := int(d.get("price", 0))
	if str(entry.get("base", "")) != "":
		var b := base_def(entry)
		p += int(b.get("price", 0)) / bundle_of(b)
	return p

## List price of `qty` of these (pieces of ammunition, rounded down to the copper).
static func lot_price(entry: Dictionary, qty: int) -> int:
	return unit_price(entry) * qty / bundle_of(def(entry))

## Whether a new entry like this joins an existing stack: plain gear, potions, ammunition and weapons do;
## armor, shields, worn items and anything with charges stays one per entry.
static func stackable(entry: Dictionary) -> bool:
	var d := def(entry)
	if d.has("charges") or entry.has("charges") or not armor_def(entry).is_empty() or is_shield(entry):
		return false
	if is_magic(d):
		return str(d.get("type", "")) in ["potion", "scroll", "ammunition"]
	if d.has("effects") and d.effects.has("container"):
		return false
	return true

static func _same_stack(a: Dictionary, b: Dictionary) -> bool:
	for k in ["id", "base", "spell", "dtype", "in", "coat", "infused"]:
		if str(a.get(k, "")) != str(b.get(k, "")):
			return false
	return bool(a.get("eq", false)) == bool(b.get("eq", false)) and bool(a.get("alt", false)) == bool(b.get("alt", false)) \
		and not a.get("att", false) and not b.get("att", false)

static func list(h: Dictionary) -> Array:
	if not h.get("inventory", null) is Array:
		h.inventory = []
	return h.inventory

static func coins(h: Dictionary) -> Dictionary:
	if not h.get("coins", null) is Dictionary:
		h.coins = {}
	for k in COINS:
		if not h.coins.has(k):
			h.coins[k] = 0
	return h.coins

static func find(h: Dictionary, uid: String) -> Dictionary:
	for e in list(h):
		if str(e.get("uid", "")) == uid:
			return e
	return {}

static func _new_uid(h: Dictionary) -> String:
	var n := 0
	for e in list(h):
		var u := str(e.get("uid", ""))
		if u.begins_with("i") and u.substr(1).is_valid_int():
			n = maxi(n, int(u.substr(1)))
	return "i%d" % (n + 1)

## Add `qty` of item `id` (extra: base / spell / dtype / charges / eq...). Returns the entry it went into.
static func add(h: Dictionary, id: String, qty := 1, extra := {}) -> Dictionary:
	var d := Data.item(id)
	if d.is_empty() or qty <= 0:
		return {}
	var e := {"id": id, "qty": qty}
	for k in extra:
		if k in ["base", "spell", "dtype", "charges", "eq", "att", "in", "stored", "alt", "infused", "lit"] and extra[k] != null and str(extra[k]) != "":
			e[k] = extra[k]
	if d.has("charges") and not e.has("charges"):
		e.charges = int(d.charges)
		# A Necklace of Fireballs comes with 1d6 + 3 beads.
		if str(d.get("charges_roll", "")) != "":
			e.charges = int(Dice.roll(str(d.charges_roll)).total)
	if bundle_of(d) > 1:
		e.pcs = true   # counted in pieces (see ensure: older sheets counted bundles)
	if bool(d.get("choose_dtype", false)) and not e.has("dtype"):
		e.dtype = "fire"
	if stackable(e):
		for o in list(h):
			if _same_stack(o, e):
				o.qty = int(o.get("qty", 1)) + qty
				return o
		e.uid = _new_uid(h)
		list(h).append(e)
		return e
	# One entry each.
	var first := {}
	for i in qty:
		var one := e.duplicate(true)
		one.qty = 1
		one.uid = _new_uid(h)
		list(h).append(one)
		if first.is_empty():
			first = one
	return first

## Add an entry taken from someone (or somewhere) else, keeping its magic details. Returns the new entry.
static func add_entry(h: Dictionary, src: Dictionary) -> Dictionary:
	var extra := {}
	for k in ["base", "spell", "dtype", "charges", "stored"]:
		if src.has(k):
			extra[k] = src[k]
	return add(h, str(src.get("id", "")), int(src.get("qty", 1)), extra)

## Take `qty` from the entry `uid` (the whole stack when qty <= 0). Returns what was taken, as a loose entry.
static func take(h: Dictionary, uid: String, qty := 0) -> Dictionary:
	var e := find(h, uid)
	if e.is_empty():
		return {}
	var have := int(e.get("qty", 1))
	if qty <= 0 or qty >= have:
		list(h).erase(e)
		# Whatever was in a container comes out of it.
		for o in list(h):
			if str(o.get("in", "")) == uid:
				o.erase("in")
		var out: Dictionary = e.duplicate(true)
		for k in ["uid", "eq", "att", "in", "alt"]:
			out.erase(k)
		return out
	e.qty = have - qty
	var part: Dictionary = e.duplicate(true)
	part.qty = qty
	for k in ["uid", "eq", "att", "in", "alt"]:
		part.erase(k)
	return part

## Why entry `e` can't go into a storage chest right now ("" = it can). An attuned (or attuning) item and an
## artificer's infused item stay with their owner; in a fight, worn and wielded things have to come off first.
static func stash_problem(e: Dictionary, in_combat: bool) -> String:
	if e.is_empty():
		return "That item isn't there any more."
	if e.get("att", false) or str(e.get("pend", "")) != "":
		return "End the attunement to %s first (it stays with you while you're attuned)." % display_name(e)
	if str(e.get("infused", "")) != "":
		return "End the infusion on %s first." % display_name(e)
	if in_combat and (e.get("eq", false) or e.get("alt", false)):
		return "Put %s away first: in a fight you can't store what you're wearing or holding." % display_name(e)
	return ""

## Move `qty` (0 = all) of entry `uid` from `from` to `to` (a character and a chest's store, either way).
## Returns the moved entry as it now sits in `to`, or {} if nothing moved.
static func transfer(from: Dictionary, to: Dictionary, uid: String, qty := 0) -> Dictionary:
	var part := take(from, uid, qty)
	if part.is_empty():
		return {}
	for k in ["pend", "lit", "coat", "infused"]:
		part.erase(k)
	return add_entry(to, part)

## Move coins (amounts per kind, capped at what `from` holds) from one purse to another. Returns what moved.
static func transfer_coins(from: Dictionary, to: Dictionary, amt: Dictionary) -> Dictionary:
	var src := coins(from)
	var moved := {}
	for k in COINS:
		var n := clampi(int(amt.get(k, 0)), 0, int(src[k]))
		if n > 0:
			moved[k] = n
			src[k] = int(src[k]) - n
	give_coins(to, moved)
	return moved

static func count(h: Dictionary, id: String) -> int:
	var n := 0
	for e in list(h):
		if str(e.get("id", "")) == id and str(e.get("in", "")) == "":
			n += int(e.get("qty", 1))
	return n

## Use up `qty` of item `id` carried (not in a container). Returns false (and takes nothing) if there isn't enough.
static func consume(h: Dictionary, id: String, qty := 1) -> bool:
	if count(h, id) < qty:
		return false
	for e in list(h).duplicate():
		if qty <= 0:
			break
		if str(e.get("id", "")) != id or str(e.get("in", "")) != "":
			continue
		var n := mini(qty, int(e.get("qty", 1)))
		take(h, str(e.uid), n)
		qty -= n
	return true

# ================================================================ coins

static func wealth_cp(c: Dictionary) -> int:
	var t := 0
	for k in COINS:
		t += int(c.get(k, 0)) * int(COIN_CP[k])
	return t

static func coin_count(c: Dictionary) -> int:
	var t := 0
	for k in COINS:
		t += int(c.get(k, 0))
	return t

## A price or amount in copper as coins ("12 gp 5 sp").
static func fmt_cp(cp: int) -> String:
	if cp <= 0:
		return "0 gp"
	var bits: PackedStringArray = []
	var gp := cp / 100
	var sp := (cp % 100) / 10
	var c := cp % 10
	if gp > 0: bits.append("%s gp" % _thousands(gp))
	if sp > 0: bits.append("%d sp" % sp)
	if c > 0: bits.append("%d cp" % c)
	return " ".join(bits)

static func fmt_coins(c: Dictionary) -> String:
	var bits: PackedStringArray = []
	for k in COINS:
		if int(c.get(k, 0)) > 0:
			bits.append("%s %s" % [_thousands(int(c[k])), k])
	return ", ".join(bits) if not bits.is_empty() else "no coins"

static func _thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if n < 0 else "") + s + out

## Pay `cp` copper's worth out of `h`'s purse, smallest coins first, taking change in gold, silver and copper.
## Returns false (and pays nothing) if the purse holds too little.
static func pay(h: Dictionary, cp: int) -> bool:
	var c := coins(h)
	if cp <= 0:
		return true
	if wealth_cp(c) < cp:
		return false
	var left := cp
	for k in ["cp", "sp", "ep", "gp", "pp"]:
		if left <= 0:
			break
		var val: int = COIN_CP[k]
		var n := mini(int(c[k]), ceili(float(left) / val))
		c[k] = int(c[k]) - n
		left -= n * val
	if left < 0:
		give_cp(h, -left)
	return true

## Add `cp` copper's worth as gold, silver and copper.
static func give_cp(h: Dictionary, cp: int) -> void:
	var c := coins(h)
	c.gp = int(c.gp) + cp / 100
	c.sp = int(c.sp) + (cp % 100) / 10
	c.cp = int(c.cp) + cp % 10

static func give_coins(h: Dictionary, add_c: Dictionary) -> void:
	var c := coins(h)
	for k in COINS:
		c[k] = maxi(0, int(c[k]) + int(add_c.get(k, 0)))

# ================================================================ weight and encumbrance

## Pounds carried: every entry not inside a magic container, plus coins (50 to the pound).
static func carried_lb(h: Dictionary) -> float:
	var t := 0.0
	for e in list(h):
		if str(e.get("in", "")) != "" and not find(h, str(e.in)).is_empty():
			continue
		t += unit_lb(e) * int(e.get("qty", 1))
	return t + float(coin_count(coins(h))) / COINS_PER_LB

## Pounds inside container `uid`.
static func contents_lb(h: Dictionary, uid: String) -> float:
	var t := 0.0
	for e in list(h):
		if str(e.get("in", "")) == uid:
			t += unit_lb(e) * int(e.get("qty", 1))
	return t

static func container_cap(entry: Dictionary) -> int:
	return int(effects(entry).get("container", 0))

## PHB p.176: Strength × 15, doubled for each size above Medium (halved for Tiny); Powerful Build counts as a size larger.
static func size_mult(size: String, tags: Dictionary) -> float:
	var m: float = {"tiny": 0.5, "small": 1.0, "medium": 1.0, "large": 2.0, "huge": 4.0, "gargantuan": 8.0}.get(size, 1.0)
	return m * (2.0 if tags.has("powerful_build") else 1.0)

## Load status for `lb` carried with Strength `st` (PHB p.176). variant: the optional encumbrance rule.
##   level 0: fine. 1: encumbered (variant, over 5 × STR): speed -10. 2: heavily encumbered (variant, over
##   10 × STR): speed -20 and disadvantage on ability checks, attack rolls and saves that use STR, DEX or CON.
##   3: over the carrying capacity (15 × STR): you can only push or drag it, speed 5 ft. 4: over twice the
##   capacity: you can't move it at all.
static func encumbrance(lb: float, st: int, mult: float, variant: bool) -> Dictionary:
	var cap := st * 15.0 * mult
	var out := {"level": 0, "speed": 0, "cap": int(cap), "lb": lb, "text": "Unencumbered", "dis": false}
	if lb > cap * 2.0:
		out.merge({"level": 4, "max_speed": 0, "text": "Can't move (over %d lb)" % int(cap * 2)}, true)
	elif lb > cap:
		out.merge({"level": 3, "max_speed": 5, "text": "Over capacity: pushing or dragging, speed 5 ft"}, true)
	elif variant and lb > st * 10.0 * mult:
		out.merge({"level": 2, "speed": -20, "dis": true, "text": "Heavily encumbered: speed -20 ft, disadvantage on STR/DEX/CON rolls"}, true)
	elif variant and lb > st * 5.0 * mult:
		out.merge({"level": 1, "speed": -10, "text": "Encumbered: speed -10 ft"}, true)
	return out

## Encumbrance of a combatant in the engine's current game (state.encumbrance "variant" turns on the variant rule).
static func encumbrance_of(s: Dictionary, c: Dictionary) -> Dictionary:
	if c.get("kind", "") != "pc" or not c.has("load_lb"):
		return {"level": 0, "speed": 0, "dis": false}
	var st: int = int(c.get("scores", {}).get("str", 10))
	var enc := encumbrance(float(c.load_lb), st, size_mult(str(c.get("size", "medium")), c.get("tags", {})), str(s.get("encumbrance", "")) == "variant")
	# Boots of Striding and Springing: speed isn't reduced by encumbrance.
	if c.get("tags", {}).has("striding"):
		enc.speed = 0
	return enc

# ================================================================ equipment and magic

## The equipment block the rules use, worked out from what is equipped. Sheets without an inventory keep
## their old equipment block.
static func equipment_of(ch: Dictionary) -> Dictionary:
	if not ch.get("inventory", null) is Array:
		var old: Dictionary = ch.get("equipment", {}).duplicate(true)
		for k in ["armor", "shield", "weapons", "weapon_bonus", "armor_bonus"]:
			if not old.has(k):
				old[k] = {"armor": "", "shield": false, "weapons": [], "weapon_bonus": 0, "armor_bonus": 0}[k]
		return old
	var eq := {"armor": "", "armor_bonus": 0, "armor_name": "", "shield": false, "shield_bonus": 0, "weapons": [],
		"weapon_bonus": 0, "weapon_bonuses": {}, "weapon_extra": {}, "weapon_magic": {}, "weapon_names": {}, "no_str_req": false, "no_stealth_dis": false,
		"weapon_items": {}, "weapon_silver": {}, "weapon_dtype": {}, "weapon_finesse": {}, "weapon_prof_as": {}, "weapon_infused": {}}
	for e in ch.inventory:
		if not e.get("eq", false) or str(e.get("in", "")) != "":
			continue
		var fx := effects(e)
		var active: bool = not needs_attunement(e) or bool(e.get("att", false))
		var w := weapon_def(e)
		if not w.is_empty():
			var wid := str(w.id)
			var ig := ignite_of(e)
			var lit: bool = active and bool(e.get("lit", false))
			# A Sun Blade is only a hilt until its blade is called up.
			if ig.get("hilt", false) and not lit:
				continue
			var n := 2 if int(e.get("qty", 1)) >= 2 and "light" in w.get("props", []) else 1
			for i in n:
				eq.weapons.append(wid)
			if fx.get("silver", false):
				eq.weapon_silver[wid] = true
				eq.weapon_names[wid] = display_name(e)
			# Artificer infusion on this weapon (Enhanced Weapon: +1, +2 from 10th level; see infusion_bonus).
			if str(e.get("infused", "")) in WEAPON_INFUSIONS:
				eq.weapon_infused[wid] = str(e.infused)
			if is_magic(def(e)):
				var b := int(fx.get("bonus", 0)) if active else 0
				if b >= int(eq.weapon_bonuses.get(wid, 0)):
					eq.weapon_bonuses[wid] = b
					eq.weapon_names[wid] = display_name(e)
				var ex = fx.get("extra", [])
				# Flame Tongue's fire only burns while it is lit.
				if active and ex is Array and not ex.is_empty() and (ig.is_empty() or lit):
					eq.weapon_extra[wid] = ex.duplicate(true)
				if active and (b > 0 or fx.get("magic", false) or fx.has("extra")):
					eq.weapon_magic[wid] = true
				if active:
					# On-hit powers (Vicious, slayers, Mace of Disruption, Dagger of Venom) are looked up by item id.
					eq.weapon_items[wid] = {"id": str(def(e).id), "uid": str(e.get("uid", ""))}
					if str(fx.get("dtype", "")) != "":
						eq.weapon_dtype[wid] = str(fx.dtype)
					if fx.get("finesse", false):
						eq.weapon_finesse[wid] = true
					if fx.get("prof_as", []) is Array and not fx.get("prof_as", []).is_empty():
						eq.weapon_prof_as[wid] = fx.prof_as.duplicate()
			continue
		var a := armor_def(e)
		if str(e.get("infused", "")) == "enhanced_defense" and (not a.is_empty() or is_shield(e)):
			eq.defense_infused = true
		if not a.is_empty():
			eq.armor = str(a.id)
			eq.armor_name = display_name(e)
			if is_magic(def(e)) and active:
				eq.armor_bonus = int(fx.get("bonus", 0))
				eq.no_str_req = bool(fx.get("no_str_req", false))
				eq.no_stealth_dis = bool(fx.get("no_stealth_dis", false))
			continue
		if is_shield(e):
			eq.shield = true
			if is_magic(def(e)) and active:
				eq.shield_bonus = maxi(int(eq.shield_bonus), int(fx.get("bonus", 0)))
	return eq

## Keep the sheet's equipment block in step with its inventory (other code still reads it).
static func sync_equipment(ch: Dictionary) -> void:
	if ch.get("inventory", null) is Array:
		var eq := equipment_of(ch)
		ch.equipment = {"armor": eq.armor, "shield": eq.shield, "weapons": eq.weapons.duplicate(), "weapon_bonus": 0, "armor_bonus": int(eq.armor_bonus)}

## Is this magic item working for its owner right now? Worn items must be worn, attunement items attuned,
## and nothing in a container counts.
static func active(entry: Dictionary) -> bool:
	if str(entry.get("in", "")) != "":
		return false
	if needs_attunement(entry) and not entry.get("att", false):
		return false
	if equippable(entry) and not entry.get("eq", false):
		return false
	return true

## Everything the active magic items add to a character, merged:
##   ac, ac_unarmored, saves, checks, passive, darkvision, speed_min, spell_attack, spell_dc_warlock,
##   set_score {ability: score}, resist [types], tags [names], init_adv.
static func magic_mods(ch: Dictionary) -> Dictionary:
	var out := {"ac": 0, "ac_unarmored": 0, "saves": 0, "checks": 0, "passive": 0, "darkvision": 0, "speed_min": 0,
		"spell_attack": 0, "spell_dc_warlock": 0, "set_score": {}, "resist": [], "tags": [], "init_adv": false, "items": []}
	if not ch.get("inventory", null) is Array:
		return out
	for e in ch.inventory:
		var d := def(e)
		if not is_magic(d) or not active(e):
			continue
		var fx := effects(e)
		if fx.is_empty():
			continue
		out.items.append(display_name(e))
		for k in ["ac", "ac_unarmored", "saves", "checks", "passive", "spell_attack", "spell_dc_warlock"]:
			out[k] = int(out[k]) + int(fx.get(k, 0))
		out.darkvision = maxi(int(out.darkvision), int(fx.get("darkvision", 0)))
		out.speed_min = maxi(int(out.speed_min), int(fx.get("speed_min", 0)))
		if fx.get("init_adv", false):
			out.init_adv = true
		var ss = fx.get("set_score", {})
		if ss is Dictionary:
			for ab in ss:
				out.set_score[ab] = maxi(int(out.set_score.get(ab, 0)), int(ss[ab]))
		for r in fx.get("resist", []):
			if not r in out.resist:
				out.resist.append(r)
		if fx.get("resist_choice", false) and str(e.get("dtype", "")) != "" and not str(e.dtype) in out.resist:
			out.resist.append(str(e.dtype))
		for t in fx.get("tags", []):
			if not t in out.tags:
				out.tags.append(t)
		if int(fx.get("speed_min", 0)) > 0 and not "striding" in out.tags:
			out.tags.append("striding")
	return out

static func attuned_count(h: Dictionary) -> int:
	return list(h).filter(func(e): return e.get("att", false)).size()

## Attunement changes waiting for a rest, in the order they were asked for: [entry, ...] with "pend" "on" / "off".
static func queued(h: Dictionary) -> Array:
	var arr := list(h).filter(func(e): return str(e.get("pend", "")) in ["on", "off"])
	arr.sort_custom(func(a, b): return int(a.get("pend_n", 0)) < int(b.get("pend_n", 0)))
	return arr

static func _queue(h: Dictionary, e: Dictionary, what: String) -> void:
	var n := 0
	for o in queued(h):
		n = maxi(n, int(o.get("pend_n", 0)))
	e.pend = what
	e.pend_n = n + 1

static func _unqueue(e: Dictionary) -> void:
	e.erase("pend")
	e.erase("pend_n")

## A rest (short or long): the first queued attunement change happens (one item per rest: the rest is spent
## focused on that item, DMG p.136). Returns a line for the log, or "".
static func rest_attune(h: Dictionary, info := {}) -> String:
	for e in queued(h):
		var what := str(e.pend)
		_unqueue(e)
		if what == "off":
			e.erase("att")
			return "ends attunement to %s" % display_name(e)
		# The item must still be one they can attune to (they may have hit three in the meantime).
		if attune_problem(h, e, info) != "" or str(e.get("in", "")) != "":
			continue
		e.att = true
		return "attunes to %s" % display_name(e)
	return ""

## Why `who` (a sheet or a combatant) can't attune to `entry` ("" if it can). info: {"casting": bool, "class_levels": {}}.
static func attune_problem(h: Dictionary, entry: Dictionary, info: Dictionary) -> String:
	if not needs_attunement(entry):
		return "It doesn't need attunement."
	if entry.get("att", false):
		return ""
	# Changes already queued for the next rests count as made.
	var pending := 0
	for o in queued(h):
		if o != entry:
			pending += 1 if str(o.pend) == "on" else -1
	if attuned_count(h) + pending >= ATTUNE_MAX:
		return "You can be attuned to no more than three magic items. End an attunement first."
	var req = def(entry).get("attune", true)
	if req is String:
		if req == "spellcaster" and not info.get("casting", false):
			return "Only a spellcaster can attune to it."
		if req != "spellcaster" and int(info.get("class_levels", {}).get(req, 0)) <= 0:
			return "Only a %s can attune to it." % req
	return ""

## The tools a character is proficient with (item ids): class, background and race grants, plus any the sheet
## lists in "tools" (the player's own picks).
static func tool_profs(ch: Dictionary) -> Array:
	var out: Array = []
	var add_all := func(arr: Array) -> void:
		for t in arr:
			if not str(t) in out and not Data.item(str(t)).is_empty():
				out.append(str(t))
	var i := 0
	for c in ch.get("classes", []):
		add_all.call((CLASS_TOOLS if i == 0 else MC_CLASS_TOOLS).get(str(c.get("id", "")), []))
		i += 1
	add_all.call(BACKGROUND_TOOLS.get(str(ch.get("background", "")), []))
	var race := str(ch.get("race", ""))
	add_all.call(RACE_TOOLS.get(race, []))
	add_all.call(RACE_TOOLS.get("%s/%s" % [race, str(ch.get("subrace", ""))], []))
	var own = ch.get("tools", [])
	if own is Array:
		add_all.call(own)
	return out

## Whether `c` (a combatant or sheet) carries item `id` where it can use it (not packed in a bag of holding).
static func has_item(c: Dictionary, id: String) -> bool:
	return count(c, id) > 0

## The information attune_problem needs, for a combatant in play.
static func combatant_info(c: Dictionary) -> Dictionary:
	return {"casting": not c.get("casting", []).is_empty() and c.get("casting", []).any(func(e): return str(e.get("class", "")) != "race"),
		"class_levels": c.get("class_levels", {})}

## Called by the engine after a short or long rest: each PC's next queued attunement change happens.
static func rest_attunements(eng: CombatEngine) -> void:
	for c in eng.all_combatants():
		if c.get("kind", "") != "pc" or not c.get("inventory", null) is Array or not eng.alive(c):
			continue
		var line := rest_attune(c, combatant_info(c))
		if line != "":
			eng.log_line("[color=#c8a0ff]✦ During the rest %s %s.[/color]" % [eng.nm(c), line])
			c.gear_dirty = true
			if not queued(c).is_empty():
				eng.log_line("[color=#a59cb5]  (%d more attunement change%s wait for the next rest.)[/color]" % [queued(c).size(), "" if queued(c).size() == 1 else "s"])

## The information attune_problem needs, for a character sheet.
static func sheet_info(ch: Dictionary) -> Dictionary:
	var cl := {}
	var casting := false
	for c in ch.get("classes", []):
		cl[str(c.id)] = int(c.level)
		if Rules.caster_type(c) != "":
			casting = true
	return {"casting": casting, "class_levels": cl}

## Why `entry` can't be equipped right now ("" if it can). Equipping armor or a shield swaps out the old one.
static func equip_problem(h: Dictionary, entry: Dictionary, in_combat: bool) -> String:
	if not equippable(entry):
		return "That isn't something you wear or wield."
	if str(entry.get("in", "")) != "":
		return "Take it out of the container first."
	if in_combat and not armor_def(entry).is_empty():
		return "Donning armor takes minutes: not during a fight."
	var slot := str(def(entry).get("slot", ""))
	if slot != "" and not entry.get("eq", false):
		var worn := list(h).filter(func(o): return o.get("eq", false) and str(def(o).get("slot", "")) == slot).size()
		if worn >= int(SLOT_MAX.get(slot, 1)):
			return "You're already wearing %s (DMG: no more than %s)." % [SLOT_NAMES.get(slot, slot), "two rings" if slot == "ring" else "one"]
	return ""

# ================================================================ hands and weapon sets

## Hands a weapon or shield takes when held (PHB p.146-147): a shield or a one-handed weapon 1, a two-handed
## weapon 2, and a stack of two or more light weapons 2 (one in each hand). Anything else 0.
static func hands_of(e: Dictionary) -> int:
	if is_shield(e):
		return 1
	var w := weapon_def(e)
	if w.is_empty():
		return 0
	if "two_handed" in w.get("props", []):
		return 2
	if int(e.get("qty", 1)) >= 2 and "light" in w.get("props", []):
		return 2
	return 1

## The weapons and shield in hand (alt false) or in the other weapon set, ready to swap to (alt true).
static func held(h: Dictionary, alt := false) -> Array:
	return list(h).filter(func(o): return hands_of(o) > 0 and str(o.get("in", "")) == "" and bool(o.get("alt" if alt else "eq", false)))

static func hands_used(h: Dictionary, alt := false) -> int:
	var n := 0
	for o in held(h, alt):
		n += hands_of(o)
	return n

## Free hands for `e` in a set by putting away what's in the way: other weapons first (a two-handed one
## first), then the shield. Returns what was put away.
static func make_room(h: Dictionary, e: Dictionary, alt: bool) -> Array:
	var key := "alt" if alt else "eq"
	var others := held(h, alt).filter(func(o): return o != e)
	var used := 0
	for o in others:
		used += hands_of(o)
	var stowed: Array = []
	others.sort_custom(func(a, b): return [is_shield(a), -hands_of(a)] < [is_shield(b), -hands_of(b)])
	for o in others:
		if used + hands_of(e) <= 2:
			break
		o.erase(key)
		used -= hands_of(o)
		stowed.append(o)
	return stowed

## Does equipping `e` take off the shield, or put one on? (Donning or doffing a shield takes an action.)
static func equip_moves_shield(h: Dictionary, e: Dictionary) -> bool:
	if is_shield(e):
		return true
	if hands_of(e) <= 0 or e.get("eq", false):
		return false
	var copy := {"inventory": list(h).duplicate(true)}
	return make_room(copy, find(copy, str(e.get("uid", ""))), false).any(func(o): return is_shield(o))

## Does swapping weapon sets put a shield on or take one off?
static func swap_moves_shield(h: Dictionary) -> bool:
	return held(h, false).any(func(o): return is_shield(o)) != held(h, true).any(func(o): return is_shield(o))

static func has_other_set(h: Dictionary) -> bool:
	return not held(h, true).is_empty()

## Swap the weapons and shield in hand with the other weapon set.
static func swap_sets(h: Dictionary) -> void:
	var now := held(h, false)
	var other := held(h, true)
	for o in now:
		o.erase("eq")
		o.alt = true
	for o in other:
		o.erase("alt")
		o.eq = true

static func set_text(arr: Array) -> String:
	if arr.is_empty():
		return "empty hands"
	return " and ".join(arr.map(func(o): return display_name(o)))

## Sheets from before hands were counted may hold more than two hands' worth: what doesn't fit goes to the
## other weapon set (or, if that is full too, into the pack).
static func fix_hands(h: Dictionary) -> bool:
	var changed := false
	for alt in [false, true]:
		var used := 0
		for o in held(h, alt):
			if used + hands_of(o) <= 2:
				used += hands_of(o)
				continue
			o.erase("alt" if alt else "eq")
			changed = true
			if not alt and hands_used(h, true) + hands_of(o) <= 2:
				o.alt = true
	return changed

# ================================================================ operations (sheet editor and game server)

## Apply one inventory operation to `h` (a sheet or a combatant). Returns "" on success, or why not.
## ctx: "in_combat", "shop" (the open shop, for buy / sell), "free" (the character editor or the DM: add and
## set coins freely), "info" (see sheet_info: attunement requirements).
##   {"op": "equip", "uid", "on"}  {"op": "attune", "uid", "on"}  {"op": "drop", "uid", "qty"}
##   {"op": "move", "uid", "into"}  {"op": "buy", "id", "qty", "base"}  {"op": "sell", "uid", "qty"}
##   {"op": "add", "id", "qty", "base", "spell", "dtype"}  {"op": "coins", "coins": {...}}
##   {"op": "wset", "uid", "alt"}: put a weapon or shield in the other weapon set (alt false: take it out)
##   {"op": "swap"}: swap the weapons in hand with the other weapon set
static func apply_op(h: Dictionary, op: Dictionary, ctx := {}) -> String:
	var in_combat: bool = ctx.get("in_combat", false)
	var free: bool = ctx.get("free", false)
	match str(op.get("op", "")):
		"equip":
			var e := find(h, str(op.get("uid", "")))
			if e.is_empty():
				return "That item is gone."
			var on: bool = op.get("on", true)
			if not on:
				if in_combat and not armor_def(e).is_empty():
					return "Doffing armor takes minutes: not during a fight."
				e.erase("eq")
				return ""
			var why := equip_problem(h, e, in_combat)
			if why != "":
				return why
			# One suit of armor and one shield at a time: the old one comes off.
			for o in list(h):
				if o == e or not o.get("eq", false):
					continue
				if (not armor_def(e).is_empty() and not armor_def(o).is_empty()) or (is_shield(e) and is_shield(o)):
					o.erase("eq")
			# Two hands: a two-handed weapon leaves no room for a shield; two one-handed weapons, or one and
			# a shield. What's in the way goes back in the pack.
			if hands_of(e) > 0:
				e.erase("alt")
				make_room(h, e, false)
			e.eq = true
			return ""
		"wset":
			var e := find(h, str(op.get("uid", "")))
			if e.is_empty() or hands_of(e) <= 0:
				return "Only weapons and shields go in a weapon set."
			if not op.get("alt", true):
				e.erase("alt")
				return ""
			if str(e.get("in", "")) != "":
				return "Take it out of the container first."
			e.erase("eq")
			make_room(h, e, true)
			e.alt = true
			return ""
		"swap":
			if not has_other_set(h) and held(h, false).is_empty():
				return "Put a weapon in your other weapon set first."
			swap_sets(h)
			return ""
		"store":
			return store_spell(h, str(op.get("uid", "")), str(op.get("spell", "")), int(op.get("level", 0)), in_combat)
		"infuse":
			return infuse(h, ctx.get("sheet", h), op, in_combat)
		"copy":
			# A wizard copies a scroll's spell into the spellbook. ctx.sheet: the character sheet that holds the
			# spellbook (h itself in the character builder); ctx.result gets how it went.
			var sheet: Dictionary = ctx.get("sheet", h)
			var e := find(h, str(op.get("uid", "")))
			var why := copy_problem(sheet, h, e, in_combat)
			if why != "":
				return why
			var res := copy_spell(sheet, h, e, int(ctx.get("arcana", _arcana_bonus(h, sheet))))
			ctx.result = res.text
			return ""
		"attune":
			if in_combat:
				return "Attuning takes a short rest: not during a fight."
			var e := find(h, str(op.get("uid", "")))
			if e.is_empty():
				return "That item is gone."
			# Attuning, or ending an attunement, takes a short rest focused on the item (DMG p.136-138): the
			# change waits for the next short or long rest, unless the DM (or the character builder) says now.
			var now: bool = ctx.get("attune_now", free)
			if not op.get("on", true):
				if str(e.get("pend", "")) == "on":
					_unqueue(e)
					return ""
				if not e.get("att", false):
					return ""
				if now:
					e.erase("att")
					_unqueue(e)
				else:
					_queue(h, e, "off")
				return ""
			if e.get("att", false):
				if str(e.get("pend", "")) == "off":
					_unqueue(e)   # changed their mind: stay attuned
				return ""
			if str(e.get("pend", "")) == "on":
				return ""
			var why := attune_problem(h, e, ctx.get("info", {}))
			if why != "":
				return why
			if now:
				e.att = true
			else:
				_queue(h, e, "on")
			return ""
		"drop":
			if take(h, str(op.get("uid", "")), int(op.get("qty", 0))).is_empty():
				return "That item is gone."
			return ""
		"move":
			var e := find(h, str(op.get("uid", "")))
			if e.is_empty():
				return "That item is gone."
			var into := str(op.get("into", ""))
			if into == "":
				e.erase("in")
				return ""
			var bag := find(h, into)
			if bag.is_empty() or container_cap(bag) <= 0 or bag == e:
				return "That isn't a container."
			if container_cap(e) > 0:
				return "Putting a bag of holding inside another extradimensional space tears both open (DMG). Don't."
			if contents_lb(h, into) + unit_lb(e) * int(e.get("qty", 1)) > container_cap(bag):
				return "It won't fit: the %s holds %d lb." % [display_name(bag), container_cap(bag)]
			e.erase("eq")
			e.erase("alt")
			e["in"] = into
			return ""
		"buy":
			var shop: Dictionary = ctx.get("shop", {})
			var id := str(op.get("id", ""))
			var qty := clampi(int(op.get("qty", 1)), 1, 100)
			var d := Data.item(id)
			if d.is_empty():
				return "Unknown item."
			if not free and not id in shop.get("stock", []):
				return "The shop doesn't sell that."
			var probe := {"id": id, "base": str(op.get("base", ""))}
			var why := _base_problem(probe)
			if why != "":
				return why
			var each := shop_price(probe, shop)
			if not _in_stock(shop, id, qty):
				return "The shop only has %d of those left." % int(shop.get("qty", {}).get(id, 0))
			if not pay(h, each * qty):
				return "Not enough money: %s costs %s." % [display_name(probe), fmt_cp(each * qty)]
			# Ammunition is sold by the bundle (qty bundles of 20 arrows) and carried by the piece.
			_receive(h, id, qty * bundle_of(d), {"base": probe.base, "spell": str(op.get("spell", "")), "dtype": str(op.get("dtype", ""))})
			# Limited stock counts down for whoever buys (the DM in a solo game too).
			_take_stock(shop, id, qty)
			return ""
		"sell":
			var shop: Dictionary = ctx.get("shop", {})
			var e := find(h, str(op.get("uid", "")))
			if e.is_empty():
				return "That item is gone."
			if def(e).get("cat", "") == "pack":
				return "Unpack it first."
			if str(e.get("infused", "")) == "replicate_magic_item":
				return "A replicated item only exists while your infusion lasts: it can't be sold."
			var qty := clampi(int(op.get("qty", 1)), 1, int(e.get("qty", 1)))
			var got := sell_total(e, shop, qty)
			take(h, str(e.uid), qty)
			give_cp(h, got)
			return ""
		"add":
			if not free:
				return "Only the DM can conjure items."
			var id := str(op.get("id", ""))
			if Data.item(id).is_empty():
				return "Unknown item."
			var probe := {"id": id, "base": str(op.get("base", ""))}
			var why := _base_problem(probe)
			if why != "":
				return why
			_receive(h, id, clampi(int(op.get("qty", 1)), 1, 1000), {"base": probe.base, "spell": str(op.get("spell", "")), "dtype": str(op.get("dtype", ""))})
			return ""
		"coins":
			if not free:
				return "Only the DM can set coins."
			var c := coins(h)
			var set_c: Dictionary = op.get("coins", {})
			for k in COINS:
				if set_c.has(k):
					c[k] = clampi(int(set_c[k]), 0, 10000000)
			return ""
	return "Unknown operation."

## Add bought or conjured items; a pack is unpacked into its contents, a scroll gets a spell, a choice of
## damage type defaults sensibly.
static func _receive(h: Dictionary, id: String, qty: int, extra: Dictionary) -> void:
	var d := Data.item(id)
	if d.get("contents", null) is Array:
		for i in qty:
			for pair in d.contents:
				add(h, str(pair[0]), int(pair[1]))
		return
	if d.has("scroll") and str(extra.get("spell", "")) == "":
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([id, list(h).size(), wealth_cp(coins(h))])
		extra.spell = random_scroll_spell(rng, int(d.scroll.level))
	add(h, id, qty, extra)

## A magic weapon or armor needs a base item it can be made from.
static func _base_problem(probe: Dictionary) -> String:
	var d := def(probe)
	var bk := str(d.get("base_kind", ""))
	if bk == "":
		probe.base = ""
		return ""
	var b := Data.item(str(probe.get("base", "")))
	if b.is_empty() or not base_ok(d, b):
		return "Pick which %s it is." % bk
	return ""

## Can magic item `d` be made from base item `b`? (Moon-touched and Flame Tongue are swords; mithral and
## adamantine are medium or heavy armor, not hide.)
static func base_ok(d: Dictionary, b: Dictionary) -> bool:
	if base_kind_of(b) != str(d.get("base_kind", "")):
		return false
	if d.get("base_ids", []) is Array and not d.get("base_ids", []).is_empty() and not str(b.id) in d.base_ids:
		return false
	if d.get("base_cats", []) is Array and not d.get("base_cats", []).is_empty() and not str(b.get("category", "")) in d.base_cats:
		return false
	if str(b.id) in d.get("base_not", []):
		return false
	return true

## What a base item counts as for magic variants: "weapon", "armor", or "ammo" for arrows, bolts and the like.
static func base_kind_of(b: Dictionary) -> String:
	if str(b.get("cat", "")) == "ammo":
		return "ammo"
	return str(b.get("kind", ""))

static func bases_for(d: Dictionary) -> Array:
	var out: Array = []
	for b in Data.items.values():
		if base_ok(d, b):
			out.append(b)
	out.sort_custom(func(a, b): return str(a.name) < str(b.name))
	return out

# ================================================================ shops

## Item ids a shop of kind `kind` sells. magic_max: the rarest magic item a magic shop carries.
static func shop_stock(kind: String, magic_max := "uncommon") -> Array:
	var out: Array = []
	var top := RARITIES.find(magic_max)
	for d in Data.items.values():
		var id := str(d.id)
		var k := str(d.get("kind", ""))
		var cat := str(d.get("cat", ""))
		var ok := false
		match kind:
			"general":
				ok = k == "gear" and cat in ["adventuring", "food", "light", "clothing", "ammo", "pack", "tool", "focus"] or id in ["oil", "healers_kit"]
			"smith":
				ok = k in ["weapon", "armor", "shield", "special"] or cat == "ammo" or id == "net"
			"alchemist":
				ok = id in ["acid_vial", "alchemists_fire", "antitoxin", "holy_water", "healers_kit", "oil", "vial", "bottle_glass",
					"herbalism_kit", "alchemists_supplies", "poisoners_kit", "potion_healing", "potion_greater_healing", "poison_basic"]
			"magic":
				ok = k == "magic" and RARITIES.find(str(d.get("rarity", "common"))) <= top and RARITIES.find(str(d.get("rarity", ""))) >= 0
			"everything":
				ok = (k in ["weapon", "armor", "shield", "gear", "special"] and cat != "treasure") or id == "potion_healing"
		if ok:
			out.append(id)
	out.sort_custom(func(a, b): return [_cat_rank(Data.item(a)), str(Data.item(a).name)] < [_cat_rank(Data.item(b)), str(Data.item(b).name)])
	return out

static func _cat_rank(d: Dictionary) -> int:
	match str(d.get("kind", "")):
		"weapon": return 0
		"armor": return 1
		"shield": return 2
		"magic": return 4 + RARITIES.find(str(d.get("rarity", "common")))
	return 3

## What the shop asks for one (list price × the DM's markup percent).
static func shop_price(entry: Dictionary, shop: Dictionary) -> int:
	return maxi(1, int(round(unit_price(entry) * float(shop.get("markup", 100)) / 100.0)))

## The share of the list price (percent) a shop pays for `entry`: half for gear in good condition (PHB p.144)
## unless the DM sets another rate; magic items at the shop's lower magic rate (25% unless the DM sets it);
## gems, art objects and other trade goods keep their full value (PHB p.144).
static func buy_rate(entry: Dictionary, shop: Dictionary) -> int:
	var d := def(entry)
	if str(d.get("cat", "")) == "treasure":
		return 100
	if is_magic(d):
		return int(shop.get("magic_buyback", 25))
	return int(shop.get("buyback", 50))

## What a shop pays for one (one piece of ammunition: see sell_total for a handful).
static func sell_price(entry: Dictionary, shop: Dictionary) -> int:
	return sell_total(entry, shop, 1)

## What a shop pays for `qty` of `entry`. A wand or kit is worth its share of charges left.
static func sell_total(entry: Dictionary, shop: Dictionary, qty: int) -> int:
	var p := lot_price(entry, qty)
	var d := def(entry)
	if d.has("charges") and int(d.charges) > 0:
		p = p * clampi(int(entry.get("charges", d.charges)), 0, int(d.charges)) / int(d.charges)
	return int(p * float(buy_rate(entry, shop)) / 100.0)

## A shop's limited stock: shop.qty {id: how many are left}; items not listed there are unlimited.
static func stock_left(shop: Dictionary, id: String) -> int:
	var q = shop.get("qty", {})
	if q is Dictionary and q.has(id):
		return int(q[id])
	return -1

static func _in_stock(shop: Dictionary, id: String, qty: int) -> bool:
	var left := stock_left(shop, id)
	return left < 0 or left >= qty

static func _take_stock(shop: Dictionary, id: String, qty: int) -> void:
	var left := stock_left(shop, id)
	if left < 0:
		return
	shop.qty[id] = left - qty
	if left - qty <= 0:
		shop.qty.erase(id)
		shop.get("stock", []).erase(id)

# ================================================================ starting equipment

## Class and background starting gear for a sheet without an inventory: what it already has equipped, its
## class's equipment pack and kit, and its background's gold. (Rolling starting wealth instead: see
## roll_starting_gold.)
static func starting_inventory(ch: Dictionary) -> void:
	ch.inventory = []
	ch.coins = {"pp": 0, "gp": int(BACKGROUND_GOLD.get(str(ch.get("background", "")), 10)), "ep": 0, "sp": 0, "cp": 0}
	var eq: Dictionary = ch.get("equipment", {})
	var ab := int(eq.get("armor_bonus", 0))
	var wb := int(eq.get("weapon_bonus", 0))
	if str(eq.get("armor", "")) != "" and not Data.item(str(eq.armor)).is_empty():
		if ab > 0:
			add(ch, "armor_plus_%d" % clampi(ab, 1, 2), 1, {"base": str(eq.armor), "eq": true})
		else:
			add(ch, str(eq.armor), 1, {"eq": true})
	if eq.get("shield", false):
		add(ch, "shield", 1, {"eq": true})
	for wid in eq.get("weapons", []):
		if Data.item(str(wid)).is_empty():
			continue
		if wb > 0:
			add(ch, "weapon_plus_%d" % clampi(wb, 1, 3), 1, {"base": str(wid), "eq": true})
		else:
			add(ch, str(wid), 1, {"eq": true})
	var first := str(ch.get("classes", [{}])[0].get("id", "")) if not ch.get("classes", []).is_empty() else ""
	if CLASS_PACK.has(first):
		_receive(ch, str(CLASS_PACK[first]), 1, {})
	for kid in CLASS_KIT.get(first, []):
		add(ch, str(kid), 1)
	# The background's own kit (clothes, tools, a pouch for the gold...), skipping what the class already gave.
	for bid in BACKGROUND_KIT.get(str(ch.get("background", "")), []):
		var bd := Data.item(str(bid))
		var owned := count(ch, str(bid)) > 0
		var unique: bool = str(bd.get("kind", "")) == "weapon" or str(bd.get("cat", "")) in ["tool", "focus"]
		if not bd.is_empty() and not (owned and unique):
			add(ch, str(bid), 1)
	# Ammunition for the bows and crossbows.
	for wid in eq.get("weapons", []):
		var ammo := str(Data.item(str(wid)).get("ammo", ""))
		if ammo != "" and count(ch, ammo) == 0:
			add(ch, ammo, bundle_of(Data.item(ammo)))
	fix_hands(ch)   # at most two hands of weapons and shield ready; the rest in the other weapon set
	sync_equipment(ch)

## Give a sheet made before inventories existed its starting inventory. Returns true if it changed.
static func ensure(ch: Dictionary) -> bool:
	if ch.is_empty():
		return false
	var changed := false
	if not ch.get("inventory", null) is Array:
		starting_inventory(ch)
		changed = true
	# Ammunition used to be counted in bundles ("Arrows (20)" × 1); it is counted in pieces now.
	for e in list(ch):
		var bn := bundle_of(def(e))
		if bn > 1 and not e.has("pcs"):
			e.qty = int(e.get("qty", 1)) * bn
			e.pcs = true
			changed = true
	if fix_hands(ch):
		changed = true
	coins(ch)
	sync_equipment(ch)
	return changed

## PHB p.143 starting wealth for the first class, in gold pieces.
static func roll_starting_gold(class_id: String, rng: RandomNumberGenerator) -> int:
	var row: Array = STARTING_GOLD.get(class_id, [4, 10])
	var t := 0
	for i in int(row[0]):
		t += rng.randi_range(1, 4)
	return t * int(row[1])

# ================================================================ loot

## Random magic items for a chest at tier `tier` (0: levels 1-4, 1: 5-10, 2: 11+): mostly potions and
## scrolls, sometimes a permanent item (after the DMG's Magic Item Tables A to F).
static func roll_magic(rng: RandomNumberGenerator, tier: int, rich := true) -> Array:
	var out: Array = []
	var chance: float = [0.35, 0.55, 0.75][tier] if rich else [0.08, 0.15, 0.25][tier]
	if rng.randf() >= chance:
		return out
	var want := _pick_rarity(rng, tier)
	# Healing potions come with every chest anyway (MapObjects.roll_loot).
	var pool: Array = Data.items.values().filter(func(d): return is_magic(d) and str(d.get("rarity", "")) == want and not str(d.id).ends_with("_healing"))
	# Permanent items are rarer than consumables.
	if rng.randf() < 0.6:
		var cons := pool.filter(func(d): return str(d.get("type", "")) in ["potion", "scroll"])
		if not cons.is_empty():
			pool = cons
	if pool.is_empty():
		return out
	pool.sort_custom(func(a, b): return str(a.id) < str(b.id))
	var d: Dictionary = pool[rng.randi() % pool.size()]
	out.append(make_magic(rng, str(d.id)))
	return out

static func _pick_rarity(rng: RandomNumberGenerator, tier: int) -> String:
	var r := rng.randf()
	match tier:
		0: return "common" if r < 0.55 else ("uncommon" if r < 0.97 else "rare")
		1: return "common" if r < 0.15 else ("uncommon" if r < 0.7 else ("rare" if r < 0.97 else "very_rare"))
	return "uncommon" if r < 0.3 else ("rare" if r < 0.8 else "very_rare")

## A loose entry for magic item `id`, with a base weapon or armor, damage type or scroll spell chosen at random.
static func make_magic(rng: RandomNumberGenerator, id: String) -> Dictionary:
	var d := Data.item(id)
	var e := {"id": id, "qty": 1}
	if str(d.get("base_kind", "")) != "":
		var bases := bases_for(d).filter(func(b): return str(b.id) != "lance" and not "ammunition" in b.get("props", []) or str(d.base_kind) != "weapon")
		if not bases.is_empty():
			e.base = str(bases[rng.randi() % bases.size()].id)
	if str(d.get("type", "")) == "ammunition":
		e.qty = rng.randi_range(4, 10)
	if d.get("choose_dtype", false):
		e.dtype = DAMAGE_CHOICES[rng.randi() % DAMAGE_CHOICES.size()]
	if d.has("scroll"):
		e.spell = random_scroll_spell(rng, int(d.scroll.level))
	if d.has("charges"):
		e.charges = int(d.charges)
	return e

## A spell of `level` the engine runs in combat, for a scroll.
static func random_scroll_spell(rng: RandomNumberGenerator, level: int) -> String:
	var pool: Array = []
	for sp in Data.spells.values():
		if int(sp.get("level", -1)) == level and sp.get("combat", null) is Dictionary and str(sp.get("casting_time", "action")) in ["action", "bonus"]:
			pool.append(str(sp.id))
	pool.sort()
	return pool[rng.randi() % pool.size()] if not pool.is_empty() else ""

# ================================================================ treasure (DMG chapter 7)

## DMG p.136 individual treasure: [highest CR, rows]; each row [highest d100 roll, {coin: [dice, multiplier]}].
const INDIVIDUAL_TREASURE := [
	[4, [[30, {"cp": ["5d6", 1]}], [60, {"sp": ["4d6", 1]}], [70, {"ep": ["3d6", 1]}], [95, {"gp": ["3d6", 1]}], [100, {"pp": ["1d6", 1]}]]],
	[10, [[30, {"cp": ["4d6", 100], "ep": ["1d6", 10]}], [60, {"sp": ["6d6", 10], "gp": ["2d6", 10]}], [70, {"ep": ["3d6", 10], "gp": ["2d6", 10]}],
		[95, {"gp": ["4d6", 10]}], [100, {"gp": ["2d6", 10], "pp": ["3d6", 1]}]]],
	[16, [[20, {"sp": ["4d6", 100], "gp": ["1d6", 100]}], [35, {"ep": ["1d6", 100], "gp": ["1d6", 100]}], [75, {"gp": ["2d6", 100], "pp": ["1d6", 10]}],
		[100, {"gp": ["2d6", 100], "pp": ["2d6", 10]}]]],
	[999, [[15, {"ep": ["2d6", 1000], "gp": ["8d6", 100]}], [55, {"gp": ["1d6", 1000], "pp": ["1d6", 100]}], [100, {"gp": ["1d6", 1000], "pp": ["2d6", 100]}]]],
]
## Who carries a purse, as the DM sets it (state.treasure): "mindless" (the default) skips beasts, plants,
## oozes and swarms; "humanoids" only humanoids; "all" every monster; "off" no individual treasure at all.
const TREASURE_MODES := [["mindless", "Monsters carry coins (not beasts, plants, oozes or swarms)"], ["humanoids", "Only humanoids carry coins"],
	["all", "Every monster carries coins"], ["off", "No coins on bodies"]]
## Gems and art objects in a hoard by tier (DMG p.137-139, simplified): [gem ids, art ids].
const HOARD_GOODS := [[["gem_10", "gem_50"], ["art_25"]], [["gem_50", "gem_100"], ["art_250"]], [["gem_500", "gem_1000"], ["art_750", "art_2500"]]]

static func carries_treasure(c: Dictionary, mode: String) -> bool:
	if c.get("kind", "") != "monster":
		return false
	var typ := str(c.get("type", "")).to_lower()
	match mode:
		"off": return false
		"all": return true
		"humanoids": return typ.begins_with("humanoid")
	return not (typ.begins_with("beast") or typ.begins_with("plant") or typ.begins_with("ooze") or "swarm" in str(c.get("monster_id", "")).to_lower() or "swarm" in str(c.get("name", "")).to_lower())

## Coins a monster of challenge rating `cr` carries (DMG individual treasure), using the game's dice.
static func roll_individual(cr: float) -> Dictionary:
	var rows: Array = INDIVIDUAL_TREASURE[-1][1]
	for band in INDIVIDUAL_TREASURE:
		if cr <= float(band[0]):
			rows = band[1]
			break
	var r := Dice.d(100)
	var out := {}
	for row in rows:
		if r <= int(row[0]):
			for k in row[1]:
				out[k] = int(Dice.roll(str(row[1][k][0])).total) * int(row[1][k][1])
			break
	return out

## A few gems or art objects for a treasure hoard at `tier` (0: levels 1-4, 1: 5-10, 2: 11+), as gear entries.
static func roll_hoard_goods(rng: RandomNumberGenerator, tier: int) -> Array:
	var pick: Array = HOARD_GOODS[clampi(tier, 0, 2)]
	var gems := rng.randf() < 0.6
	var ids: Array = pick[0] if gems else pick[1]
	var id: String = ids[rng.randi() % ids.size()]
	var n := rng.randi_range(2, 6) if gems else rng.randi_range(1, 4)
	return [{"id": id, "qty": n}]

## Split the coins of everyone in `holders` evenly, coin by coin (no changing platinum into copper): each
## gets the same share of every kind, and the odd coins left over go one each around the party.
static func split_coins(holders: Array) -> Dictionary:
	var k := holders.size()
	if k == 0:
		return {}
	var totals := {}
	for h in holders:
		var c := coins(h)
		for coin in COINS:
			totals[coin] = int(totals.get(coin, 0)) + int(c[coin])
			c[coin] = 0
	var turn := 0
	for coin in COINS:
		var n: int = totals[coin]
		for i in k:
			coins(holders[i])[coin] = n / k
		for j in n % k:
			var who: Dictionary = holders[(turn + j) % k]
			coins(who)[coin] = int(coins(who)[coin]) + 1
		turn += n % k
	return totals

# ================================================================ describing

static func describe(entry: Dictionary) -> String:
	var d := def(entry)
	var col := rarity_color(entry)
	var txt := "[b][color=%s]%s[/color][/b]" % [col, display_name(entry).replace("[", "[lb]")]
	var bits: PackedStringArray = []
	if is_magic(d):
		bits.append("%s %s" % [str(d.get("rarity", "")).replace("_", " ").capitalize(), str(d.get("type", "")).replace("_", " ")])
		if needs_attunement(entry):
			var req = d.get("attune", true)
			bits.append("requires attunement%s" % ((" by a " + str(req)) if req is String else ""))
	else:
		var w := weapon_def(entry)
		var a := armor_def(entry)
		if not w.is_empty():
			bits.append("%s %s weapon, %s %s" % [str(w.category).capitalize(), "melee" if w.melee else "ranged", str(w.damage), str(w.type)])
			if not w.get("props", []).is_empty():
				bits.append(", ".join(w.props.map(func(p): return str(p).replace("_", "-"))))
		elif not a.is_empty():
			bits.append("%s armor, AC %d%s" % [str(a.category).capitalize(), int(a.base), "" if int(a.dex_max) == 0 else (" + Dex" if int(a.dex_max) > 5 else " + Dex (max 2)")])
			if int(a.get("str", 0)) > 0: bits.append("Str %d" % int(a.str))
			if a.get("stealth_dis", false): bits.append("Stealth disadvantage")
		elif is_shield(entry):
			bits.append("+2 AC")
	txt += "\n[color=#a59cb5]%s[/color]" % " · ".join(bits) if not bits.is_empty() else ""
	var w2 := weapon_def(entry)
	if is_magic(d) and not w2.is_empty():
		txt += "\n[color=#a59cb5]%s, %s %s[/color]" % [str(w2.name), str(w2.damage), str(w2.type)]
	var a2 := armor_def(entry)
	if is_magic(d) and not a2.is_empty():
		txt += "\n[color=#a59cb5]%s armor, AC %d[/color]" % [str(a2.name), int(a2.base)]
	var bn := bundle_of(d)
	if bn > 1:
		txt += "\n%s lb and %s for %d" % [_lb_txt(float(d.get("lb", 0))), fmt_cp(unit_price(entry)), bn]
	else:
		txt += "\n%s lb · %s" % [_lb_txt(unit_lb(entry)), fmt_cp(unit_price(entry))]
	if entry.has("charges") and d.has("charges"):
		txt += " · %d / %d charges" % [int(entry.charges), int(d.charges)]
	if str(entry.get("spell", "")) != "":
		var sp := Data.spell(str(entry.spell))
		txt += "\n[color=#c8a0ff]%s (%s): %s[/color]" % [str(sp.get("name", "")), "cantrip" if int(sp.get("level", 0)) == 0 else "level %d" % int(sp.get("level", 0)), str(sp.get("summary", ""))]
	if str(d.get("desc", "")) != "":
		txt += "\n" + str(d.desc).replace("[", "[lb]")
	return txt

## BBCode from describe() as plain text, for a tooltip.
static func plain(bb: String) -> String:
	var re := RegEx.new()
	re.compile("\\[/?(b|i|color[^\\]]*|font_size[^\\]]*)\\]")
	return re.sub(bb, "", true).replace("[lb]", "[")

static func _lb_txt(lb: float) -> String:
	if is_equal_approx(lb, roundf(lb)):
		return str(int(lb))
	return ("%.2f" % lb).rstrip("0").rstrip(".")

# ================================================================ weapon powers on a hit (the engine calls these)

## Extra damage a magic weapon adds to a hit, before it lands (so resistances apply): a slayer's or a Mace of
## Disruption's damage against its foes, a Sun Blade's radiance against undead, a Vicious Weapon's crit.
static func hit_extra(c: Dictionary, t: Dictionary, atk: Dictionary, res: Dictionary) -> Array:
	var out: Array = []
	var d := Data.item(str(atk.get("item", "")))
	if d.is_empty() or atk.get("spell_attack", false):
		return out
	var fx: Dictionary = d.get("effects", {})
	var wtype := str(atk.get("damage", [{}])[0].get("type", "slashing")) if not atk.get("damage", []).is_empty() else "slashing"
	var ttype := str(t.get("type", "")).to_lower()
	for v in fx.get("vs", []):
		if v.get("types", []).any(func(x): return ttype.begins_with(str(x))):
			var dice := str(v.dice)
			if res.get("crit", false):
				dice = Dice.add(dice, dice)
			out.append({"amount": int(Dice.roll(dice).total), "type": wtype if str(v.type) == "weapon" else str(v.type)})
	if str(fx.get("crit_extra", "")) != "" and res.get("crit", false) and int(res.get("nat", 0)) == 20:
		out.append({"amount": int(Dice.roll(str(fx.crit_extra)).total), "type": wtype})
	return out

## Riders after a weapon hit lands: a coat of poison (basic poison, Dagger of Venom), a Giant Slayer knocking a
## giant down, a Mace of Disruption destroying a weakened fiend or undead.
static func on_weapon_hit(eng: CombatEngine, c: Dictionary, t: Dictionary, atk: Dictionary, res: Dictionary) -> void:
	if atk.get("spell_attack", false) or c.is_empty():
		return
	var wtype := str(atk.get("damage", [{}])[0].get("type", "")) if not atk.get("damage", []).is_empty() else ""
	var shot := ammo_for(c, atk) != ""
	# Poison on the blade (or on three pieces of ammunition): the next hit with it (or each of three shots).
	for e in c.get("effects", []).duplicate():
		var coat = e.get("coat", null)
		if not coat is Dictionary or not eng.alive(t):
			continue
		if str(coat.get("for", "weapon")) == "ammo" and not shot:
			continue
		if str(coat.get("for", "weapon")) == "weapon" and (shot or not wtype in ["piercing", "slashing"]):
			continue
		if str(coat.get("item", "")) != "" and str(coat.item) != str(atk.get("item", "")):
			continue
		var dc := int(coat.get("dc", 10))
		if not eng.saving_throw(t, "con", dc, c, {"dmg_type": "poison"}):
			eng.apply_damage(t, [{"amount": int(Dice.roll(str(coat.get("dice", "1d4"))).total), "type": "poison"}], c, {})
			if int(coat.get("poisoned", 0)) > 0 and eng.alive(t):
				eng.add_effect(t, {"name": "Poisoned (%s)" % str(e.get("name", "venom")), "cond": "poisoned", "src": c.id, "rounds": int(coat.poisoned), "tick_cid": t.id, "tick_on": "end"})
		else:
			eng.log_line("  %s shrugs off the poison." % eng.nm(t))
		coat.hits = int(coat.get("hits", 1)) - 1
		if int(coat.hits) <= 0:
			c.effects.erase(e)
		break
	var d := Data.item(str(atk.get("item", "")))
	if d.is_empty() or not eng.alive(t):
		return
	var fx: Dictionary = d.get("effects", {})
	var ttype := str(t.get("type", "")).to_lower()
	var sp = fx.get("slayer_prone", null)
	if sp is Dictionary and sp.get("types", []).any(func(x): return ttype.begins_with(str(x))) and not eng.has_cond(t, "prone"):
		if not eng.saving_throw(t, "str", int(sp.get("dc", 15)), c, {"cond": "prone"}):
			eng.add_effect(t, {"name": "Prone", "cond": "prone", "src": c.id, "rounds": 9999, "tick_cid": "none"})
			eng.log_line("  The %s knocks %s flat!" % [str(d.name), eng.nm(t)])
	var dis = fx.get("disrupt", null)
	if dis is Dictionary and dis.get("types", []).any(func(x): return ttype.begins_with(str(x))) and int(t.hp) <= int(dis.get("hp", 25)):
		if not eng.saving_throw(t, "wis", int(dis.get("dc", 15)), c, {"magic": true}):
			eng.log_line("  [color=#ffd166]%s is destroyed by the mace's holy light![/color]" % eng.nm(t))
			eng.apply_damage(t, [{"amount": int(t.hp) + int(t.get("temp_hp", 0)) + 999, "type": "radiant"}], c, {"magic": true, "ignore_resist": "radiant"})

## Artificer levels and the infusions the sheet has chosen (its "infusions" list), for `h` and its sheet.
static func _artificer_level(h: Dictionary, sheet: Dictionary) -> int:
	if h.get("class_levels", null) is Dictionary and h.class_levels.has("artificer"):
		return int(h.class_levels.artificer)
	for c in sheet.get("classes", []):
		if str(c.get("id", "")) == "artificer":
			return int(c.get("level", 0))
	return 0

## How many items an artificer can keep infused (Tasha's: 2 at 2nd level, 3 at 6th, 4 at 10th...).
static func infusion_limit(level: int) -> int:
	return Progression.table_count(Progression.INFUSIONS_ACTIVE, level)

static func infused(h: Dictionary) -> Array:
	return list(h).filter(func(e): return str(e.get("infused", "")) != "")

## Which entries infusion `inf` can go on: Enhanced Weapon on a mundane weapon, Repeating Shot on one that
## shoots ammunition, Enhanced Defense on mundane armor or a shield, Enhanced Arcane Focus on a rod, staff or wand.
static func infusion_fits(inf: String, e: Dictionary) -> bool:
	if e.is_empty() or is_magic(def(e)) or str(e.get("in", "")) != "":
		return false
	match inf:
		"enhanced_weapon", "radiant_weapon":
			return not weapon_def(e).is_empty()
		"repeating_shot":
			return "ammunition" in weapon_def(e).get("props", [])
		"enhanced_defense":
			return not armor_def(e).is_empty() or is_shield(e)
		"enhanced_arcane_focus":
			var id := str(e.get("id", ""))
			return str(def(e).get("cat", "")) == "focus" and (id.ends_with("_rod") or id.ends_with("_staff") or id.ends_with("_wand"))
	return false

## Infuse an item, or end an infusion (Tasha's Cauldron, artificer). op: {"infusion", "uid"} to infuse that
## entry; {"infusion": "replicate_magic_item", "item": magic item id} to create the item; {"infusion": "", "uid"}
## to end an infusion (a replicated item vanishes). Outside combat only. Returns "" or why not.
static func infuse(h: Dictionary, sheet: Dictionary, op: Dictionary, in_combat: bool) -> String:
	var lv := _artificer_level(h, sheet)
	var inf := str(op.get("infusion", ""))
	if lv < 2:
		return "Only an artificer of 2nd level or higher can infuse items."
	if in_combat:
		return "Infusing an item is done between fights."
	if inf == "":
		var e := find(h, str(op.get("uid", "")))
		if e.is_empty() or str(e.get("infused", "")) == "":
			return "That item isn't infused."
		if str(e.infused) == "replicate_magic_item":
			take(h, str(e.uid))
		else:
			e.erase("infused")
		return ""
	if not inf in sheet.get("infusions", []):
		return "You don't know the %s infusion." % Data.pretty(inf)
	if infused(h).size() >= infusion_limit(lv):
		return "You can keep only %d items infused at a time. End an infusion first." % infusion_limit(lv)
	if inf == "replicate_magic_item":
		var item := str(op.get("item", ""))
		if not REPLICABLE.has(item) or Data.item(item).is_empty():
			return "That isn't something you can replicate."
		if lv < int(REPLICABLE[item]):
			return "Replicating a %s takes artificer level %d." % [str(Data.item(item).name), int(REPLICABLE[item])]
		if list(h).any(func(o): return str(o.get("infused", "")) == "replicate_magic_item" and str(o.id) == item):
			return "You already have a replicated %s." % str(Data.item(item).name)
		var made := add(h, item, 1)
		made.infused = "replicate_magic_item"
		return ""
	if infused(h).any(func(o): return str(o.infused) == inf):
		return "%s is already on another item." % Data.pretty(inf)
	var t := find(h, str(op.get("uid", "")))
	if not infusion_fits(inf, t):
		return "%s can't go on that." % Data.pretty(inf)
	# A stack gives up one item to be infused (it no longer stacks with the rest).
	if int(t.get("qty", 1)) > 1:
		var one := take(h, str(t.uid), 1)
		one.uid = _new_uid(h)
		one.qty = 1
		list(h).append(one)
		t = one
	t.infused = inf
	return ""

## Why `sheet`'s wizard can't copy scroll `e` into the spellbook ("" if they can). PHB p.114: a spell of a level
## you have slots for, 2 hours and 50 gp per level, so not during a fight; the scroll must hold a wizard spell.
static func copy_problem(sheet: Dictionary, h: Dictionary, e: Dictionary, in_combat: bool) -> String:
	if e.is_empty() or not def(e).has("scroll") or str(e.get("spell", "")) == "":
		return "That isn't a spell scroll."
	var wiz := {}
	for c in sheet.get("classes", []):
		if str(c.get("id", "")) == "wizard":
			wiz = c
	if wiz.is_empty():
		return "Only a wizard keeps a spellbook to copy spells into."
	if in_combat:
		return "Copying a spell takes hours: not during a fight."
	var sp := Data.spell(str(e.spell))
	var lv := int(sp.get("level", 0))
	if lv <= 0:
		return "Cantrips aren't written in a spellbook."
	if not "wizard" in sp.get("classes", []):
		return "%s isn't a wizard spell." % str(sp.get("name", ""))
	if lv > Rules.max_spell_level_for(wiz):
		return "You can't copy a level %d spell until you have level %d spell slots." % [lv, lv]
	if str(e.spell) in Rules.wizard_spellbook(sheet):
		return "%s is already in your spellbook." % str(sp.get("name", ""))
	if wealth_cp(coins(h)) < copy_cost(e):
		return "Copying it takes %s of rare inks and you don't have that much." % fmt_cp(copy_cost(e))
	return ""

## 50 gp per spell level (PHB p.114).
static func copy_cost(e: Dictionary) -> int:
	return 5000 * int(Data.spell(str(e.get("spell", ""))).get("level", 1))

static func _arcana_bonus(h: Dictionary, sheet: Dictionary) -> int:
	if h.get("skills", null) is Dictionary and h.skills.has("arcana"):
		return int(h.skills.arcana)
	return int(Rules.derive(sheet).skills.get("arcana", 0))

## Copy scroll `e`'s spell into `sheet`'s spellbook: pay the ink (from `h`, the sheet or its token), spend the
## hours, and make the DMG's Intelligence (Arcana) check, DC 10 + the spell's level (DMG p.200). Win or lose,
## the scroll is used up. Returns {"ok", "text"}.
static func copy_spell(sheet: Dictionary, h: Dictionary, e: Dictionary, arcana: int) -> Dictionary:
	var sid := str(e.spell)
	var sp := Data.spell(sid)
	var lv := int(sp.get("level", 1))
	pay(h, copy_cost(e))
	take(h, str(e.uid), 1)
	var r: Dictionary = Dice.roll_d20(0)
	var total := int(r.roll) + arcana
	var dc := 10 + lv
	var head := "%d hours and %s of inks later" % [2 * lv, fmt_cp(5000 * lv)]
	if total < dc:
		return {"ok": false, "text": "%s, the copy of %s won't hold (Arcana %d vs DC %d): the scroll is spent." % [head, str(sp.get("name", sid)), total, dc]}
	if not sheet.has("spellbook"):
		sheet.spellbook = Rules.wizard_spellbook(sheet)
	sheet.spellbook.append(sid)
	return {"ok": true, "text": "%s, %s is written into the spellbook (Arcana %d vs DC %d). The scroll crumbles." % [head, str(sp.get("name", sid)), total, dc]}

## Levels of spells a Ring of Spell Storing holds now.
static func stored_levels(e: Dictionary) -> int:
	var n := 0
	for st in e.get("stored", []):
		n += int(st.get("level", 1))
	return n

## Spells `c` (a combatant in play) could cast into ring `e` now: [[spell id, slot level], ...], each at the
## lowest slot it has free that still fits in the ring.
static func storable(c: Dictionary, e: Dictionary) -> Array:
	var out: Array = []
	var room := int(effects(e).get("store", 0)) - stored_levels(e)
	var used: Array = c.get("slots_used", [])
	var mx: Array = c.get("slots_max", [])
	var seen := {}
	for ce in c.get("casting", []):
		for sid in ce.get("spells", []):
			var sp := Data.spell(str(sid))
			var lv := int(sp.get("level", 0))
			if lv <= 0 or seen.has(sid) or not sp.get("combat", null) is Dictionary:
				continue
			for L in range(lv, mini(room, mx.size()) + 1):
				if L - 1 < used.size() and int(used[L - 1]) < int(mx[L - 1]):
					out.append([str(sid), L])
					seen[sid] = true
					break
	return out

## Cast spell `sid` at slot level `level` into Ring of Spell Storing `uid` (DMG p.192): the caster spends the
## slot; the ring remembers the spell, its level and the caster's save DC and attack bonus. Up to 5 levels.
static func store_spell(c: Dictionary, uid: String, sid: String, level: int, in_combat: bool) -> String:
	var e := find(c, uid)
	if e.is_empty() or int(effects(e).get("store", 0)) <= 0:
		return "That isn't a ring that stores spells."
	if in_combat:
		return "Store spells in the ring between fights."
	if not e.get("eq", false):
		return "Put the ring on first."
	var sp := Data.spell(sid)
	var entry := {}
	for ce in c.get("casting", []):
		if sid in ce.get("spells", []):
			entry = ce
	if sp.is_empty() or entry.is_empty() or not c.has("slots_used"):
		return "You don't have that spell ready."
	level = maxi(level, int(sp.get("level", 1)))
	if level < 1 or stored_levels(e) + level > int(effects(e).store):
		return "The ring can only hold %d more level%s of spells." % [int(effects(e).store) - stored_levels(e), "" if int(effects(e).store) - stored_levels(e) == 1 else "s"]
	var used: Array = c.slots_used
	var mx: Array = c.get("slots_max", [])
	if level - 1 >= mx.size() or int(used[level - 1]) >= int(mx[level - 1]):
		return "No level %d spell slot left." % level
	used[level - 1] = int(used[level - 1]) + 1
	var stored: Array = e.get("stored", [])
	stored.append({"spell": sid, "level": level, "dc": int(entry.get("dc", 13)), "attack": int(entry.get("attack", 5)), "by": str(c.get("name", ""))})
	e.stored = stored
	return ""

## Wipe off whatever coat of poison is on `c`'s weapon (a new one replaces it).
static func remove_coat(c: Dictionary) -> void:
	for e in c.get("effects", []).duplicate():
		if e.get("coat", null) is Dictionary:
			c.effects.erase(e)

## The attack as it lands right now: Oil of Sharpness on the weapon (+3, magical) or a Potion of Hill Giant
## Strength (Strength 21 for Strength attacks). Returns `atk` itself when nothing applies.
static func boost_attack(c: Dictionary, atk: Dictionary) -> Dictionary:
	if atk.get("spell_attack", false) or c.get("effects", []).is_empty():
		return atk
	var out := atk
	for e in c.effects:
		var sharp := int(e.get("sharp", 0))
		if sharp > 0 and str(e.get("sharp_weapon", "")) == str(atk.get("weapon", "")) and str(atk.get("weapon", "")) != "":
			var add := maxi(0, sharp - int(atk.get("wb", 0)))
			out = out.duplicate(true)
			out.to_hit = int(out.to_hit) + add
			if not out.get("damage", []).is_empty():
				out.damage[0].dice = bump_dice(str(out.damage[0].dice), add)
			out.magic = true
		var ss := int(e.get("set_str", 0))
		if ss > 0 and str(atk.get("ability", "")) == "str":
			var add2 := maxi(0, Rules.mod(ss) - int(c.get("mods", {}).get("str", 0)))
			if add2 > 0:
				out = out.duplicate(true)
				out.to_hit = int(out.to_hit) + add2
				if not out.get("damage", []).is_empty():
					out.damage[0].dice = bump_dice(str(out.damage[0].dice), add2)
	return out

# ================================================================ ammunition (PHB p.146-147)

## The ammunition a PC's attack shoots ("arrows", "crossbow_bolts"...), or "" when it needs none. Monsters
## (no inventory) don't count arrows.
static func ammo_for(c: Dictionary, atk: Dictionary) -> String:
	if c.get("kind", "") != "pc" or not c.get("inventory", null) is Array:
		return ""
	if atk.get("thrown", false) or atk.get("held_obj", false) or atk.get("no_ammo", false):
		return ""
	var w := Data.item(str(atk.get("weapon", "")))
	if not "ammunition" in w.get("props", []):
		return ""
	return str(w.get("ammo", ""))

## Pieces of special ammunition (magic, silvered) of kind `ammo` that `c` carries outside containers.
static func special_ammo(c: Dictionary, ammo: String) -> Array:
	return list(c).filter(func(e): return str(e.get("base", "")) == ammo and str(e.get("in", "")) == "" and int(e.get("qty", 0)) > 0)

## The attack shooting special ammunition entry `e`: its bonus, magic and silver added to `atk`.
static func ammo_attack(atk: Dictionary, e: Dictionary) -> Dictionary:
	var a: Dictionary = atk.duplicate(true)
	var fx := effects(e)
	var b := int(fx.get("bonus", 0))
	if b != 0:
		a.to_hit = int(a.get("to_hit", 0)) + b
		if not a.get("damage", []).is_empty():
			a.damage[0].dice = bump_dice(str(a.damage[0].dice), b)
	if b > 0 or is_magic(def(e)):
		a.magic = true
	if fx.get("silver", false):
		a.silver = true
	a.name = "%s · %s" % [str(atk.name), display_name(e)]
	return a

## A dice expression with `b` added to its flat modifier ("1d6+4" + 1 = "1d6+5").
static func bump_dice(dice: String, b: int) -> String:
	if b == 0:
		return dice
	var re := RegEx.create_from_string("^(.*\\d+d\\d+)([+-]\\d+)$")
	var m := re.search(dice)
	if m == null:
		return Dice.add(dice, str(b))
	var n := int(m.get_string(2)) + b
	return m.get_string(1) + ("" if n == 0 else ("+%d" % n if n > 0 else str(n)))

## Attack actions built for an ammunition weapon: the plain shot (counting what's left, disabled with none)
## and one per kind of special ammunition carried. `a` is the engine's action for the weapon.
static func ammo_actions(eng: CombatEngine, c: Dictionary, a: Dictionary) -> Array:
	var ammo := ammo_for(c, a.get("atk", {}))
	if ammo == "":
		return [a]
	var out: Array = []
	var n := count(c, ammo)
	var nm := str(Data.item(ammo).get("name", ammo)).to_lower()
	a.ammo = ammo
	a.name = "%s (%d)" % [str(a.name), n]
	a.desc = "%s Uses one of your %s (%d left)." % [str(a.desc), nm, n]
	if n <= 0 and a.enabled:
		a.enabled = false
		a.reason = "No %s" % nm
	out.append(a)
	for e in special_ammo(c, ammo):
		var atk2 := ammo_attack(a.atk, e)
		var v := eng._act(str(a.id) + "@" + str(e.uid), "%s (%d)" % [str(atk2.name), int(e.qty)], "weapon", str(a.cost), "enemy", int(a.range), eng._weapon_desc(atk2), {"atk": atk2, "cat": "attack", "ammo": ammo, "ammo_uid": str(e.uid)})
		if not a.enabled and str(a.reason) != "No %s" % nm:
			v.enabled = false
			v.reason = a.reason
		out.append(v)
	return out

## Spend the shot for weapon action `a` (before the attack roll). Returns the loose piece used ({} if the
## attack needs no ammunition), or {"none": true} when there's nothing left to shoot.
static func spend_ammo(c: Dictionary, a: Dictionary) -> Dictionary:
	var ammo := str(a.get("ammo", ""))
	if ammo == "":
		return {}
	var uid := str(a.get("ammo_uid", ""))
	if uid != "":
		var got := take(c, uid, 1)
		return got if not got.is_empty() else {"none": true}
	for e in list(c):
		if str(e.get("id", "")) == ammo and str(e.get("base", "")) == "" and str(e.get("in", "")) == "":
			return take(c, str(e.uid), 1)
	return {"none": true}

## Note a piece shot in a fight, to be gathered up afterwards. A magic piece that hits loses its magic
## (DMG p.150); silvered ones stay silvered.
static func note_spent(c: Dictionary, piece: Dictionary, hit: bool) -> void:
	if piece.is_empty() or piece.get("none", false):
		return
	var p := {"id": str(piece.id), "qty": 1}
	if str(piece.get("base", "")) != "":
		p.base = str(piece.base)
		if hit and is_magic(def(piece)):
			p = {"id": str(piece.base), "qty": 1}
	var spent: Array = c.get("ammo_spent", [])
	for s in spent:
		if str(s.id) == str(p.id) and str(s.get("base", "")) == str(p.get("base", "")):
			s.qty = int(s.qty) + 1
			c.ammo_spent = spent
			return
	spent.append(p)
	c.ammo_spent = spent

## End of a fight: half the ammunition each PC shot can be gathered up (rounded down, PHB p.146). Returns
## log lines for the creatures that have some to recover.
static func combat_over(eng: CombatEngine) -> void:
	for c in eng.all_combatants():
		var spent: Array = c.get("ammo_spent", [])
		c.erase("ammo_spent")
		var back: Array = []
		for s in spent:
			var n := int(s.qty) / 2
			if n > 0:
				var e: Dictionary = s.duplicate()
				e.qty = n
				back.append(e)
		if back.is_empty():
			c.erase("ammo_recover")
			continue
		c.ammo_recover = back
		eng.log_line("[color=#a59cb5]%s could gather up %s from the battlefield (Recover Ammunition).[/color]" % [eng.nm(c), _ammo_list(back)])

static func _ammo_list(arr: Array) -> String:
	var bits: PackedStringArray = []
	for e in arr:
		bits.append("%d %s" % [int(e.qty), display_name(e).to_lower()])
	return ", ".join(bits)

## The hotbar actions for what `c` carries: potions, thrown flasks, a healer's kit, light sources, wands
## and scrolls, a pearl of power. Items in a container can't be used until taken out.
static func actions(eng: CombatEngine, c: Dictionary) -> Array:
	var out: Array = []
	if c.get("kind", "") != "pc" or not c.get("inventory", null) is Array:
		return out
	var t: Dictionary = c.get("turn", {})
	var interact := "free" if not eng.s.in_combat or not t.get("obj_used", false) else "action"
	# After a fight: gather up the arrows and bolts that can still be used (a minute's search).
	if not eng.s.in_combat and not c.get("ammo_recover", []).is_empty():
		out.append(eng._act("inv:recover:ammo", "Recover Ammunition", "object", "free", "self", 0,
			"Spend a minute searching the battlefield for what you shot: %s (half of it, PHB p.146)." % _ammo_list(c.ammo_recover), {"cat": "basic"}))
	# Swap to the other weapon set: one object interaction (free once a turn), an action if a shield goes on or off.
	if has_other_set(c):
		var sw_cost := "action" if eng.s.in_combat and swap_moves_shield(c) else interact
		out.append(eng._act("inv:swap:set", "Swap Weapons", "object", sw_cost, "self", 0,
			"Put away %s and ready %s. Your free object interaction%s." % [set_text(held(c, false)), set_text(held(c, true)),
			" (a shield goes on or off: that takes an action, PHB p.146)" if swap_moves_shield(c) else ""], {"cat": "basic"}))
	# A burning torch or candle has left the pack: it can still be put out.
	for le in c.get("effects", []):
		if str(le.get("light_uid", "")).begins_with("burning_"):
			out.append(eng._act("inv:douse:" + str(le.light_uid), "Douse " + str(Data.item(str(le.get("light_id", ""))).get("name", "light")), "object", interact, "self", 0,
				"Put out the flame (an object interaction). A doused torch is spent.", {"cat": "basic"}))
	for e in c.inventory:
		if str(e.get("in", "")) != "":
			continue
		var d := def(e)
		var uid := str(e.uid)
		var nm := display_name(e)
		var n := int(e.get("qty", 1))
		var cnt := (" (%d)" % n) if n > 1 else ""
		if d.has("potion"):
			out.append(eng._act("inv:drink:" + uid, "%s%s" % [nm, cnt], "object", "action", "ally", 5, "Drink it, or give it to a creature within 5 ft (an action). %s" % str(d.get("desc", "")), {"cat": "basic", "uid": uid}))
			continue
		var use = d.get("use", null)
		if use is Dictionary:
			match str(use.get("type", "")):
				"throw":
					out.append(eng._act("inv:throw:" + uid, "Throw %s%s" % [nm, cnt], "object", "action", "enemy", int(use.get("range", 20)), str(d.get("desc", "")), {"cat": "basic", "uid": uid}))
				"drink":
					out.append(eng._act("inv:drink:" + uid, "%s%s" % [nm, cnt], "object", "action", "self", 0, str(d.get("desc", "")), {"cat": "basic", "uid": uid}))
				"stabilize":
					var a := eng._act("inv:kit:" + uid, "Healer's Kit (%d)" % int(e.get("charges", 0)), "object", "action", "ally", 5, str(d.get("desc", "")), {"cat": "basic", "uid": uid})
					if int(e.get("charges", 0)) <= 0:
						a.enabled = false
						a.reason = "No uses left"
					out.append(a)
				"zone":
					# Caltrops and ball bearings: scattered on the ground next to you.
					out.append(eng._act("inv:zone:" + uid, "Scatter %s%s" % [nm, cnt], "object", "action", "point", 5, str(d.get("desc", "")),
						{"cat": "basic", "uid": uid, "area": ZONES[str(use.zone)].area}))
				"net":
					out.append(eng._act("inv:net:" + uid, "Throw Net%s" % cnt, "object", "action", "enemy", int(use.get("long_range", 15)),
						"%s (Ranged attack %s.)" % [str(d.get("desc", "")), Rules.fmt_mod(_net_to_hit(c))], {"cat": "basic", "uid": uid}))
				"coat":
					out.append(eng._act("inv:coat:" + uid, "Poison Weapon%s" % cnt, "object", "action", "self", 0, str(d.get("desc", "")), {"cat": "basic", "uid": uid}))
					if held(c).any(func(o): return not str(weapon_def(o).get("ammo", "")).is_empty()):
						out.append(eng._act("inv:coatammo:" + uid, "Poison 3 Arrows%s" % cnt, "object", "action", "self", 0, "Coat three pieces of ammunition instead: each of the next three shots that hits carries the poison.", {"cat": "basic", "uid": uid}))
				"oil":
					var oa := eng._act("inv:oil:" + uid, "Apply %s" % nm, "object", "free", "self", 0, str(d.get("desc", "")), {"cat": "basic", "uid": uid})
					if eng.s.in_combat:
						oa.enabled = false
						oa.reason = "Takes a minute: not in a fight"
					elif _sharp_target(c).is_empty():
						oa.enabled = false
						oa.reason = "Hold a slashing or piercing weapon"
					out.append(oa)
			continue
		if d.has("light"):
			var lit := _light_effect(c, uid)
			var fuel := str(d.light.get("fuel", ""))
			var a := eng._act("inv:light:" + uid, ("Douse " if not lit.is_empty() else "Light ") + nm, "object", interact, "self", 0,
				"%s%s Lighting or dousing it is an object interaction." % [str(d.get("desc", "")), (" Lighting it uses a flask of oil (%d left)." % count(c, "oil")) if fuel == "oil" else ""], {"cat": "basic", "uid": uid})
			if lit.is_empty() and fuel == "oil" and count(c, "oil") <= 0:
				a.enabled = false
				a.reason = "No oil"
			out.append(a)
			continue
		var fx := effects(e)
		# Switched-on powers of what's worn or wielded: Flame Tongue's fire, a Sun Blade's blade, Boots of Speed.
		if not ignite_of(e).is_empty() and e.get("eq", false) and active(e):
			var on: bool = e.get("lit", false)
			out.append(eng._act("inv:ignite:" + uid, ("Quench " if on else "Ignite ") + nm, "object", "bonus", "self", 0,
				str(d.get("desc", "")), {"cat": "basic", "uid": uid}))
		if fx.has("toggle") and e.get("eq", false) and active(e):
			var on2 := not _toggle_effect(c, uid).is_empty()
			var ta := eng._act("inv:toggle:" + uid, ("Stop: " if on2 else "") + nm, "object", "bonus", "self", 0,
				"%s %s left today." % [str(d.get("desc", "")), _rounds_text(int(e.get("charges", 0)))], {"cat": "basic", "uid": uid})
			if not on2 and int(e.get("charges", 0)) <= 0:
				ta.enabled = false
				ta.reason = "Used up until dawn"
			out.append(ta)
		if fx.has("bolt") and e.get("eq", false):
			var ba := eng._act("inv:bolt:" + uid, "Lightning Javelin", "object", "action", "enemy", int(fx.bolt.get("len", 120)), str(d.get("desc", "")), {"cat": "attack", "uid": uid})
			if int(e.get("charges", 0)) <= 0:
				ba.enabled = false
				ba.reason = "Used: recharges at dawn"
			out.append(ba)
		if fx.has("venom") and e.get("eq", false):
			var va := eng._act("inv:venom:" + uid, "Coat %s with Venom" % nm, "object", "action", "self", 0, str(d.get("desc", "")), {"cat": "basic", "uid": uid})
			if int(e.get("charges", 0)) <= 0:
				va.enabled = false
				va.reason = "Used: recharges at dawn"
			out.append(va)
		if fx.has("casts") and active(e):
			for cs in fx.casts:
				var sp := Data.spell(str(cs.spell))
				if sp.is_empty() or not sp.get("combat", null) is Dictionary:
					continue
				var a := _cast_action(eng, c, e, str(cs.spell), int(sp.get("level", 1)), {"cost": int(cs.cost), "multi": true})
				if not a.is_empty():
					out.append(a)
		if fx.has("store") and active(e):
			var stored: Array = e.get("stored", [])
			for i in stored.size():
				var st0: Dictionary = stored[i]
				var a := _cast_action(eng, c, e, str(st0.spell), int(st0.level), {"stored": i, "dc": int(st0.dc), "attack": int(st0.attack)})
				if not a.is_empty():
					out.append(a)
		if fx.has("cast") and active(e):
			var a := _cast_action(eng, c, e, str(fx.cast.spell), int(Data.spell(str(fx.cast.spell)).get("level", 1)), fx.cast)
			if not a.is_empty():
				out.append(a)
		elif d.has("scroll") and str(e.get("spell", "")) != "":
			var a := _cast_action(eng, c, e, str(e.spell), int(d.scroll.level), d.scroll)
			if not a.is_empty():
				out.append(a)
		elif fx.has("pearl") and active(e):
			var a := eng._act("inv:pearl:" + uid, nm, "object", "action", "self", 0, str(d.get("desc", "")), {"cat": "basic", "uid": uid})
			if int(e.get("charges", 0)) <= 0:
				a.enabled = false
				a.reason = "Used: recharges at dawn"
			elif _pearl_slot(eng, c, int(fx.pearl)) <= 0:
				a.enabled = false
				a.reason = "No spent spell slot of level %d or lower" % int(fx.pearl)
			out.append(a)
	# A Potion of Fire Breath still working: breathe fire as a bonus action.
	for fe in c.get("effects", []):
		var br = fe.get("breath", null)
		if br is Dictionary and int(br.get("uses", 0)) > 0:
			out.append(eng._act("inv:breath:" + str(fe.get("eid", "x")), "Fire Breath (%d)" % int(br.uses), "object", "bonus", "enemy", int(br.get("range", 30)),
				"Exhale fire at a creature within %d ft: DC %d Dexterity save, %s %s (half on a save)." % [int(br.get("range", 30)), int(br.get("dc", 13)), str(br.dice), str(br.type)], {"cat": "attack"}))
	# Someone next to you is caught in a net: cut or pull it off them.
	for o in eng.all_combatants():
		if o.id != c.id and eng.alive(o) and eng.dist(c, o) <= 5 and not _net_effect(o).is_empty():
			out.append(eng._act("inv:freenet:" + str(o.id), "Free %s from the Net" % str(o.name), "object", "action", "ally_other", 5,
				"Cut the net (an attack against AC 10 with a slashing weapon; 5 slashing damage destroys it) or pull it away (a DC 10 Strength check).", {"cat": "basic"}))
	return out

## Item zones: caltrops (5-foot square) and ball bearings (10-foot square), PHB p.151-152.
const ZONES := {
	"caltrops": {"name": "Caltrops", "area": {"shape": "cube", "size": 5}, "dc": 15, "color": "#9aa0a6",
		"data": {"trigger": "enter", "save": "dex", "damage": [{"dice": "1", "type": "piercing"}], "stop_on_fail": true,
			"effect": {"name": "Caltrop in the foot", "mods": {"speed": -10}, "duration_rounds": 4800, "until_healed": true}}},
	"ball_bearings": {"name": "Ball Bearings", "area": {"shape": "cube", "size": 10}, "dc": 10, "color": "#c9ccd1",
		"data": {"trigger": "enter", "save": "dex", "effect": {"name": "Slipped on ball bearings", "condition": "prone"}}},
}

## A net's attack bonus: Dexterity, plus proficiency for those trained in martial weapons (PHB p.148).
static func _net_to_hit(c: Dictionary) -> int:
	var prof: bool = "martial" in c.get("weapon_prof", []) or "net" in c.get("weapon_prof", [])
	return int(c.get("mods", {}).get("dex", 0)) + (int(c.get("prof", 2)) if prof else 0)

static func _net_effect(c: Dictionary) -> Dictionary:
	for e in c.get("effects", []):
		if e.get("net", false):
			return e
	return {}

## The weapon in hand Oil of Sharpness (or poison) can go on: slashing or piercing. {} if none.
static func _sharp_target(c: Dictionary) -> Dictionary:
	for o in held(c):
		var w := weapon_def(o)
		if not w.is_empty() and str(w.get("type", "")) in ["slashing", "piercing"]:
			return o
	return {}

static func _toggle_effect(c: Dictionary, uid: String) -> Dictionary:
	for e in c.get("effects", []):
		if str(e.get("toggle_uid", "")) == uid:
			return e
	return {}

static func _rounds_text(r: int) -> String:
	if r >= 600:
		return "%s hour%s" % [_lb_txt(snappedf(r / 600.0, 0.1)), "" if r == 600 else "s"]
	if r >= 10:
		return "%d minute%s" % [r / 10, "" if r / 10 == 1 else "s"]
	return "%d round%s" % [r, "" if r == 1 else "s"]

## A spell action cast from a wand or scroll: the engine's own spell action, with the item's DC / attack and
## the slot levels its charges allow.
static func _cast_action(eng: CombatEngine, c: Dictionary, e: Dictionary, sid: String, level: int, info: Dictionary) -> Dictionary:
	var sp := Data.spell(sid)
	if sp.is_empty():
		return {}
	var mine: Dictionary = eng.caster_entry(c, "") if not c.get("casting", []).is_empty() else {}
	var dc := int(info.get("dc", mine.get("dc", 13)))
	var atk := int(info.get("attack", mine.get("attack", 5)))
	var entry := {"class": "item", "name": display_name(e), "ability": str(mine.get("ability", "int")), "mod": int(mine.get("mod", 0)),
		"dc": dc, "attack": atk, "spells": [sid], "bonus_spells": [], "pact": false, "max_level": level}
	var a: Dictionary = eng._spell_action(c, entry, sid)
	var d := def(e)
	a.id = "inv:cast:" + str(e.uid)
	if info.get("multi", false):
		a.id = "inv:cast:%s:%s" % [str(e.uid), sid]   # a staff with several spells
	if info.has("stored"):
		a.id = "inv:ring:%s:%d" % [str(e.uid), int(info.stored)]
	a.item_uid = str(e.uid)
	a["class"] = "item"
	# A Necklace of Fireballs bead is thrown, not cast: 60 feet.
	if int(info.get("range", 0)) > 0:
		a.range = int(info.range)
	var slots: Array = []
	if info.has("stored"):
		# A spell held in a Ring of Spell Storing: cast at the level it was stored at, with its caster's numbers.
		a.ring_index = int(info.stored)
		a.slots = [level]
		a.innate = false
		a.name = "%s (ring, level %d)" % [str(sp.name), level]
		if a.reason == "No spell slots":
			a.enabled = true
			a.reason = ""
		return a
	if info.has("cost"):
		# A staff spends a fixed number of charges per spell, cast at its own level.
		var chg := int(e.get("charges", 0))
		a.item_cost = int(info.cost)
		a.slots = [level]
		a.innate = false
		a.name = "%s (staff, %d)" % [str(sp.name), int(info.cost)]
		a.desc = "%s: %d charge%s (%d left). %s" % [display_name(e), int(info.cost), "" if int(info.cost) == 1 else "s", chg, str(a.get("desc", ""))]
		if chg < int(info.cost):
			a.enabled = false
			a.reason = "Not enough charges"
		elif a.reason == "No spell slots":
			a.enabled = true
			a.reason = ""
		return a
	if d.has("scroll"):
		slots = [level]
		a.name = "%s (scroll)" % str(sp.name)
		# 2014 rules: the spell must be on one of your classes' spell lists.
		if not _on_class_list(c, sp):
			a.enabled = false
			a.reason = "Not on your class's spell list"
			a.slots = slots
			return a
	else:
		var ch := int(e.get("charges", 0))
		var top := mini(int(info.get("max_level", level)), level + ch - 1) if not info.get("fixed", false) else level
		for L in range(level, top + 1):
			slots.append(L)
		a.name = "%s (%s, %d)" % [str(sp.name), str(d.get("type", "wand")), ch]
		a.desc = "%s: %d charge%s left. %s" % [display_name(e), ch, "" if ch == 1 else "s", str(a.get("desc", ""))]
	a.slots = slots
	a.innate = false
	if slots.is_empty() or (not d.has("scroll") and int(e.get("charges", 0)) <= 0):
		a.enabled = false
		a.reason = "No charges left"
		a.slots = [level]
	elif str(a.get("reason", "")) == "No spell slots":
		a.enabled = true
		a.reason = ""
	return a

static func _on_class_list(c: Dictionary, sp: Dictionary) -> bool:
	for cid in c.get("class_levels", {}):
		if int(c.class_levels[cid]) > 0 and cid in sp.get("classes", []):
			return true
	return false

## Called by the engine when an item spell is cast: spend the wand's charges or use up the scroll. A scroll
## of a higher level than the reader can cast needs a check (DC 10 + level) or it's wasted. Returns false
## when the spell fails.
static func spend_for_cast(eng: CombatEngine, c: Dictionary, a: Dictionary, slot: int) -> bool:
	var e := find(c, str(a.get("item_uid", "")))
	if e.is_empty():
		return false
	var d := def(e)
	if d.has("scroll"):
		var lv := int(d.scroll.level)
		take(c, str(e.uid), 1)
		if lv > int(_max_castable(c)):
			var ab := _casting_ability(c)
			var r: Dictionary = Dice.roll_d20(0, c.get("tags", {}).has("halfling_lucky"))
			var b := int(c.mods.get(ab, 0))
			var total := int(r.roll) + b
			eng.dice_event(c.id, "Read scroll (%s)" % ab.to_upper(), EngineBase.d20_faces(r), b, total, "SUCCESS" if total >= 10 + lv else "FAIL")
			if total < 10 + lv:
				eng.log_line("%s tries to read a scroll of %s (%s check %d vs DC %d) and fails: the magic fizzles and the scroll crumbles." % [eng.nm(c), str(Data.spell(str(e.spell)).get("name", "")), ab.to_upper(), total, 10 + lv])
				return false
		eng.log_line("%s reads a scroll; it crumbles to dust." % eng.nm(c))
		return true
	# A Ring of Spell Storing: the stored spell is used up.
	if a.has("ring_index"):
		var stored: Array = e.get("stored", [])
		var i := int(a.ring_index)
		if i < 0 or i >= stored.size():
			return false
		stored.remove_at(i)
		e.stored = stored
		eng.log_line("%s releases a spell stored in the %s." % [eng.nm(c), display_name(e)])
		return true
	var need := 1 + maxi(0, slot - int(Data.spell(str(a.get("spell", ""))).get("level", 1)))
	if effects(e).get("cast", {}).get("fixed", false):
		need = 1
	if a.has("item_cost"):
		need = int(a.item_cost)   # a staff's fixed price per spell
	if int(e.get("charges", 0)) < need:
		return false
	e.charges = maxi(0, int(e.get("charges", 0)) - need)
	# Necklace of Fireballs: beads are pulled off and thrown; with none left the necklace is gone.
	if effects(e).get("cast", {}).get("beads", false):
		eng.log_line("%s pulls %d bead%s from the necklace and throws %s." % [eng.nm(c), need, "" if need == 1 else "s", "it" if need == 1 else "them"])
		if int(e.charges) <= 0:
			eng.log_line("  That was the last bead.")
			take(c, str(e.uid), 1)
		return true
	if int(e.charges) <= 0 and not d.has("charges_roll"):
		# DMG: a wand whose last charge is spent crumbles to ash on a d20 roll of 1.
		var r := Dice.d(20)
		if r == 1:
			eng.log_line("[color=#ff9c8f]The %s's last charge is spent and it crumbles to ash.[/color]" % display_name(e))
			take(c, str(e.uid), 1)
	return true

static func _max_castable(c: Dictionary) -> int:
	var best := 0
	for e in c.get("casting", []):
		best = maxi(best, int(e.get("max_level", 0)))
	return best

static func _casting_ability(c: Dictionary) -> String:
	var best := "int"
	var bv := -99
	for e in c.get("casting", []):
		if int(c.mods.get(str(e.ability), 0)) > bv:
			bv = int(c.mods.get(str(e.ability), 0))
			best = str(e.ability)
	return best

static func _light_effect(c: Dictionary, uid: String) -> Dictionary:
	for e in c.get("effects", []):
		if str(e.get("light_uid", "")) == uid:
			return e
	return {}

## Feet of light `c`'s lit torches and lanterns give it to see by (fog of war).
static func light_ft(c: Dictionary) -> int:
	var best := 0
	for src in light_sources(c):
		best = maxi(best, int(src.ft))
	return best

## Every light `c` carries: lit torches and lanterns (effects with "light_uid"), a burning Flame Tongue or Sun
## Blade, a Mace of Disruption. [{"ft": reach in feet (bright + dim), "cone": a bullseye lantern's beam}].
static func light_sources(c: Dictionary) -> Array:
	var out: Array = []
	for e in c.get("effects", []):
		if e.has("light_uid") and int(e.get("light_ft", 0)) > 0:
			out.append({"ft": int(e.light_ft), "cone": bool(Data.item(str(e.get("light_id", ""))).get("light", {}).get("cone", false))})
	if c.get("inventory", null) is Array:
		for e in c.inventory:
			if not e.get("eq", false) or not active(e):
				continue
			var fx := effects(e)
			if int(fx.get("light_ft", 0)) > 0:
				out.append({"ft": int(fx.light_ft), "cone": false})
			elif not ignite_of(e).is_empty() and e.get("lit", false):
				out.append({"ft": int(ignite_of(e).get("ft", 40)), "cone": false})
			if str(e.get("infused", "")) == "radiant_weapon":
				out.append({"ft": 60, "cone": false})   # Radiant Weapon: bright 30 ft, dim 30 more
	return out

## The highest spent slot of level `max_lv` or lower (0 if none).
static func _pearl_slot(eng: CombatEngine, c: Dictionary, max_lv: int) -> int:
	var used: Array = c.get("slots_used", [])
	for L in range(mini(max_lv, used.size()), 0, -1):
		if int(used[L - 1]) > 0:
			return L
	return 0

## Run an "inv:" action. Returns false (and logs why) when it can't be done.
static func execute(eng: CombatEngine, c: Dictionary, a: Dictionary, targets: Array, cell := Vector2i(-1, -1)) -> bool:
	var parts := str(a.id).split(":")
	if parts.size() < 3:
		return false
	var what := parts[1]
	if what == "douse":
		var lit := _light_effect(c, parts[2])
		if lit.is_empty():
			return false
		if eng.s.in_combat:
			if str(a.cost) == "free":
				c.turn.obj_used = true
			else:
				eng.pay(c, "action")
		c.effects.erase(lit)
		eng.log_line("%s puts out the %s." % [eng.nm(c), str(Data.item(str(lit.get("light_id", ""))).get("name", "light")).to_lower()])
		return true
	if what == "breath":
		var fe: Dictionary = {}
		for x in c.effects:
			if str(x.get("eid", "")) == parts[2] and x.get("breath", null) is Dictionary:
				fe = x
		if fe.is_empty() or targets.is_empty() or int(fe.breath.get("uses", 0)) <= 0:
			return false
		var br: Dictionary = fe.breath
		var t0: Dictionary = targets[0]
		eng.pay(c, "bonus")
		br.uses = int(br.uses) - 1
		eng.log_line("%s breathes a gout of fire at %s!" % [eng.nm(c), eng.nm(t0)])
		eng.fx("bolt", c.pos, t0.pos, "#ff7a2a", [], "fire")
		var saved: bool = eng.saving_throw(t0, "dex", int(br.get("dc", 13)), c, {"dmg_type": str(br.type)})
		var amt := int(Dice.roll(str(br.dice)).total)
		eng.apply_damage(t0, [{"amount": amt / 2 if saved else amt, "type": str(br.type)}], c, {"magic": true})
		if int(br.uses) <= 0:
			c.effects.erase(fe)
		return true
	if what == "freenet":
		var o: Dictionary = targets[0] if not targets.is_empty() else eng.C(parts[2])
		var ne := _net_effect(o)
		if ne.is_empty() or eng.dist(c, o) > 5:
			return false
		eng.pay(c, "action")
		var blade: Dictionary = {}
		for atk0 in eng.attacks_of(c):
			if atk0.get("melee", false) and not atk0.get("damage", []).is_empty() and str(atk0.damage[0].type) == "slashing":
				blade = atk0
				break
		var freed := false
		if not blade.is_empty():
			# Cut it: an attack against the net's AC 10; 5 slashing damage destroys it.
			var r0: Dictionary = Dice.roll_d20(0, c.get("tags", {}).has("halfling_lucky"))
			var hit_total := int(r0.roll) + int(blade.to_hit)
			var dmg := int(Dice.roll(str(blade.damage[0].dice)).total) if hit_total >= 10 and int(r0.roll) != 1 else 0
			freed = dmg >= 5
			eng.log_line("%s slashes at the net around %s with the %s (%d vs AC 10, %d damage): %s" % [eng.nm(c), eng.nm(o), str(blade.name).to_lower(), hit_total, dmg, "it falls apart!" if freed else "it holds."])
		else:
			var chk: Dictionary = eng.skill_check(c, "str")
			freed = int(chk.total) >= 10
			eng.log_line("%s pulls at the net around %s (%s vs DC 10): %s" % [eng.nm(c), eng.nm(o), str(chk.text), "free!" if freed else "it holds."])
		if freed:
			eng.remove_effect(o, ne.eid)
			eng.sync_move(o)
		return true
	if what == "swap":
		if not has_other_set(c):
			return false
		if eng.s.in_combat:
			if str(a.cost) == "free":
				c.turn.obj_used = true
			else:
				eng.pay(c, "action")
		var was := set_text(held(c, false))
		swap_sets(c)
		eng.log_line("%s puts away %s and readies %s." % [eng.nm(c), was, set_text(held(c, false))])
		# The game server rebuilds the attacks and AC from the sheet (Session._sync_gear).
		c.gear_dirty = true
		return true
	if what == "recover":
		var back: Array = c.get("ammo_recover", [])
		if back.is_empty() or eng.s.in_combat:
			return false
		for r in back:
			add_entry(c, r)
		eng.log_line("%s gathers up %s." % [eng.nm(c), _ammo_list(back)])
		c.erase("ammo_recover")
		return true
	var e := find(c, parts[2])
	if e.is_empty():
		eng.log_line("[color=#888]%s doesn't have that any more.[/color]" % c.name)
		return false
	var d := def(e)
	match what:
		"drink":
			var t: Dictionary = targets[0] if not targets.is_empty() else c
			if t.get("dead", false) or t.get("death", {}).get("dead", false):
				eng.log_line("[color=#888]A potion can't help the dead.[/color]")
				return false
			eng.pay(c, "action")
			take(c, str(e.uid), 1)
			if t.id == c.id:
				eng.log_line("%s drinks %s." % [eng.nm(c), _a(display_name(e))])
			else:
				eng.log_line("%s gives %s %s." % [eng.nm(c), eng.nm(t), _a(display_name(e))])
			eng.sfx("potion", t.id)
			_drink(eng, c, t, e, d)
		"throw":
			if targets.is_empty():
				return false
			var t: Dictionary = targets[0]
			eng.pay(c, "action")
			take(c, str(e.uid), 1)
			var use: Dictionary = d.use
			var atk := {"id": "inv_throw", "name": display_name(e), "melee": false, "ability": "dex", "to_hit": int(c.mods.get("dex", 0)),
				"damage": [], "range": int(use.get("range", 20)), "long_range": int(use.get("range", 20)) * 3, "props": ["thrown"], "improvised": true}
			eng.log_line("%s throws %s at %s." % [eng.nm(c), _a(display_name(e)), eng.nm(t)])
			var res: Dictionary = eng.roll_attack(c, t, atk, {"melee": false})
			t = res.get("target", t)
			eng.fx("bolt", c.pos, t.pos, "#ffb347", [], "glass")
			if not res.hit:
				return true
			var vs: Array = use.get("vs", [])
			if not vs.is_empty() and not str(t.get("type", "")) in vs:
				eng.log_line("  It splashes harmlessly over %s." % eng.nm(t))
				return true
			var dice := str(use.damage)
			if res.get("crit", false):
				dice = Dice.add(dice, dice.split("+")[0])
			eng.apply_damage(t, [{"amount": Dice.roll(dice).total, "type": str(use.dtype)}], c, {"attack": true, "crit": res.get("crit", false)})
			if use.get("burn", false) and eng.alive(t):
				eng.add_effect(t, {"name": "Burning (alchemist's fire)", "tag": "burning", "src": c.id, "rounds": 100, "tick_cid": t.id, "tick_on": "end",
					"tick_damage": {"dice": "1d4", "type": "fire", "when": "start"}, "escape_dc": 10, "escape_with": ["dex"]})
				eng.log_line("  %s catches fire! (an action and a DC 10 Dexterity check puts it out)" % eng.nm(t))
		"kit":
			if targets.is_empty():
				return false
			var t: Dictionary = targets[0]
			if int(t.get("hp", 1)) > 0 or t.get("kind", "") != "pc":
				eng.log_line("[color=#888]A healer's kit stabilizes a creature at 0 hit points.[/color]")
				return false
			if t.death.get("stable", false) or t.death.get("dead", false):
				eng.log_line("[color=#888]%s is %s.[/color]" % [t.name, "already stable" if t.death.get("stable", false) else "dead"])
				return false
			eng.pay(c, "action")
			e.charges = maxi(0, int(e.get("charges", 0)) - 1)
			t.death.stable = true
			t.death.s = 0
			t.death.f = 0
			eng.log_line("%s uses a healer's kit on %s, who is now stable (%d use%s left)." % [eng.nm(c), eng.nm(t), int(e.charges), "" if int(e.charges) == 1 else "s"])
			if int(e.charges) <= 0:
				take(c, str(e.uid), 1)
		"light":
			var lit := _light_effect(c, str(e.uid))
			if eng.s.in_combat:
				if str(a.cost) == "free":
					c.turn.obj_used = true
				else:
					eng.pay(c, "action")
			if not lit.is_empty():
				c.effects.erase(lit)
				eng.log_line("%s puts out the %s." % [eng.nm(c), display_name(e).to_lower()])
				return true
			var li: Dictionary = d.light
			if str(li.get("fuel", "")) == "oil" and not consume(c, "oil", 1):
				eng.log_line("[color=#888]The %s needs a flask of oil.[/color]" % display_name(e).to_lower())
				return false
			# A torch or candle burns away; a lantern keeps its oil burning for 6 hours.
			var hours := int(li.get("hours", 1))
			if str(li.get("fuel", "")) == "" and not d.has("effects") and not is_magic(d):
				take(c, str(e.uid), 1)
				e = {"uid": "burning_" + str(d.id), "id": d.id}
			eng.add_effect(c, {"name": "%s (lit)" % str(d.name), "src": c.id, "light_uid": str(e.uid), "light_ft": int(li.get("ft", 20)), "light_id": str(d.id),
				"rounds": hours * 600, "tick_cid": c.id, "tick_on": "end"})
			eng.log_line("%s lights %s: light out to %d ft." % [eng.nm(c), _a(str(d.name).to_lower()), int(li.get("ft", 20))])
		"zone":
			var z0: Dictionary = ZONES.get(str(d.get("use", {}).get("zone", "")), {})
			if z0.is_empty():
				return false
			if eng.s.in_combat:
				eng.pay(c, "action")
			take(c, str(e.uid), 1)
			var cells: Array = eng.area_cells(c, z0.area, cell, false)
			eng.s.zones.append({"zid": eng.new_id("z"), "src": c.id, "spell": "", "name": str(z0.name), "cells": cells, "data": z0.data.duplicate(true),
				"dc": int(z0.dc), "upl": 0, "conc": false, "rounds": 0, "color": str(z0.color), "center": cell, "area": z0.area, "item": true})
			eng.log_line("%s scatters %s on the ground." % [eng.nm(c), str(z0.name).to_lower()])
		"net":
			if targets.is_empty():
				return false
			var t: Dictionary = targets[0]
			eng.pay(c, "action")
			# A net is the only attack you make with that action (PHB p.148).
			if c.get("turn", {}).has("attacks"):
				c.turn.attacks = 99
			take(c, str(e.uid), 1)
			var use: Dictionary = d.use
			var atk := {"id": "inv_net", "name": "Net", "melee": false, "ability": "dex", "to_hit": _net_to_hit(c), "damage": [],
				"range": int(use.get("range", 5)), "long_range": int(use.get("long_range", 15)), "props": ["thrown"]}
			eng.log_line("%s throws a net at %s." % [eng.nm(c), eng.nm(t)])
			var res: Dictionary = eng.roll_attack(c, t, atk, {"melee": false})
			t = res.get("target", t)
			eng.fx("bolt", c.pos, t.pos, "#c9b27a", [], "throw")
			if not res.hit:
				return true
			if str(t.get("size", "medium")) in ["huge", "gargantuan"]:
				eng.log_line("  %s is too big to be held by a net." % eng.nm(t))
				return true
			eng.add_effect(t, {"name": "Netted", "cond": "restrained", "net": true, "src": c.id, "rounds": 9999, "tick_cid": "none",
				"escape_dc": 10, "escape_with": ["str"]})
			eng.sync_move(t)
			eng.log_line("  %s is caught in the net! (DC 10 Strength check to break free, or 5 slashing damage to the net)" % eng.nm(t))
		"coat", "coatammo":
			if eng.s.in_combat:
				eng.pay(c, "action")
			take(c, str(e.uid), 1)
			var use2: Dictionary = d.use
			var ammo := what == "coatammo"
			remove_coat(c)
			eng.add_effect(c, {"name": "Poisoned %s" % ("ammunition" if ammo else "weapon"), "src": c.id, "rounds": 10, "tick_cid": c.id, "tick_on": "end",
				"coat": {"dice": str(use2.get("dice", "1d4")), "dc": int(use2.get("dc", 10)), "for": "ammo" if ammo else "weapon", "hits": 3 if ammo else 1}})
			eng.log_line("%s coats %s with poison." % [eng.nm(c), "three pieces of ammunition" if ammo else "a weapon"])
		"oil":
			var w := _sharp_target(c)
			if w.is_empty() or eng.s.in_combat:
				return false
			take(c, str(e.uid), 1)
			eng.add_effect(c, {"name": "Oil of Sharpness (%s)" % display_name(w), "src": c.id, "rounds": int(d.use.get("rounds", 600)), "tick_cid": c.id, "tick_on": "end",
				"sharp": int(d.use.get("bonus", 3)), "sharp_weapon": str(weapon_def(w).id)})
			eng.log_line("%s works Oil of Sharpness into the %s: +%d for an hour." % [eng.nm(c), display_name(w).to_lower(), int(d.use.get("bonus", 3))])
		"ignite":
			if eng.s.in_combat:
				eng.pay(c, "bonus")
			var on: bool = not e.get("lit", false)
			if on:
				e.lit = true
			else:
				e.erase("lit")
			eng.log_line("%s %s" % [eng.nm(c), ("calls up the %s: it blazes with light." % display_name(e)) if on else ("lets the %s go dark." % display_name(e))])
			c.gear_dirty = true   # the attack changes (Session._sync_gear rebuilds it)
		"toggle":
			var tg: Dictionary = effects(e).toggle
			var cur := _toggle_effect(c, str(e.uid))
			if eng.s.in_combat:
				eng.pay(c, "bonus")
			if not cur.is_empty():
				e.charges = maxi(0, int(cur.get("rounds", 0)))
				c.effects.erase(cur)
				eng.sync_move(c)
				eng.log_line("%s turns off the %s (%s left today)." % [eng.nm(c), display_name(e), _rounds_text(int(e.charges))])
				return true
			var left := int(e.get("charges", 0))
			if left <= 0:
				return false
			e.charges = 0   # the time left travels with the effect, and comes back when it's switched off
			var mods := {"speed_mult": 2} if str(tg.kind) == "speed" else {"fly": int(c.get("speed", 30))}
			eng.add_effect(c, {"name": str(tg.name), "tag": "boots_of_speed" if str(tg.kind) == "speed" else "winged_boots", "toggle_uid": str(e.uid),
				"src": c.id, "rounds": left, "tick_cid": c.id, "tick_on": "end", "mods": mods})
			eng.sync_move(c)
			eng.log_line("%s %s." % [eng.nm(c), "clicks the boots' heels together: speed doubled" if str(tg.kind) == "speed" else "spreads the boots' little wings: flying"])
		"bolt":
			if targets.is_empty() or int(e.get("charges", 0)) <= 0:
				return false
			var t: Dictionary = targets[0]
			var bolt: Dictionary = effects(e).bolt
			eng.pay(c, "action")
			e.charges = 0
			eng.log_line("%s hurls the javelin and it becomes a bolt of lightning!" % eng.nm(c))
			eng.fx("bolt", c.pos, t.pos, "#9fd8ff", [], "lightning")
			var dist_ft: int = maxi(5, eng.dist(c, t))
			for p in eng.area_cells(c, {"shape": "line", "size": dist_ft, "width": 5}, t.pos, true):
				var o: Dictionary = eng.creature_at(p)
				if o.is_empty() or o.id == c.id or o.id == t.id or not eng.alive(o):
					continue
				var ok: bool = eng.saving_throw(o, "dex", int(bolt.get("dc", 13)), c, {"dmg_type": "lightning", "magic": true})
				var amt := int(Dice.roll(str(bolt.get("dice", "4d6"))).total)
				eng.apply_damage(o, [{"amount": amt / 2 if ok else amt, "type": "lightning"}], c, {"magic": true})
			var jav: Dictionary = {}
			for atk1 in eng.attacks_of(c):
				if str(atk1.get("id", "")) == "wt_javelin":
					jav = atk1
			if jav.is_empty():
				jav = {"id": "wt_javelin", "name": "Javelin of Lightning", "melee": false, "to_hit": int(c.mods.get("str", 0)) + int(c.get("prof", 2)), "range": 30, "long_range": 120,
					"damage": [{"dice": Dice.add("1d6", str(int(c.mods.get("str", 0)))), "type": "piercing"}], "magic": true, "thrown": true}
			jav = jav.duplicate(true)
			jav.range = int(bolt.get("len", 120))
			jav.long_range = int(bolt.get("len", 120))
			var res2: Dictionary = eng.roll_attack(c, t, jav, {"melee": false})
			t = res2.get("target", t)
			if res2.hit:
				eng._attack_hit(c, t, jav, res2, false, {})
				var ld := str(bolt.get("dice", "4d6"))
				if res2.get("crit", false):
					ld = Dice.add(ld, ld)
				if eng.alive(t):
					eng.apply_damage(t, [{"amount": int(Dice.roll(ld).total), "type": "lightning"}], c, {"magic": true})
		"venom":
			if int(e.get("charges", 0)) <= 0:
				return false
			eng.pay(c, "action")
			e.charges = 0
			var vn: Dictionary = effects(e).venom
			remove_coat(c)
			eng.add_effect(c, {"name": "Venom (%s)" % display_name(e), "src": c.id, "rounds": int(vn.get("rounds", 10)), "tick_cid": c.id, "tick_on": "end",
				"coat": {"dice": str(vn.get("dice", "2d10")), "dc": int(vn.get("dc", 15)), "for": "weapon", "hits": 1, "item": str(d.id), "poisoned": 10}})
			eng.log_line("Thick black poison seeps over %s's %s." % [eng.nm(c), display_name(e).to_lower()])
		"pearl":
			var L := _pearl_slot(eng, c, int(effects(e).get("pearl", 3)))
			if L <= 0 or int(e.get("charges", 0)) <= 0:
				return false
			eng.pay(c, "action")
			c.slots_used[L - 1] = int(c.slots_used[L - 1]) - 1
			e.charges = 0
			eng.log_line("%s speaks the pearl's command word and regains a level %d spell slot." % [eng.nm(c), L])
			eng.float_text(c.id, "+L%d slot" % L, "#c8a0ff")
	return true

static func _drink(eng: CombatEngine, c: Dictionary, t: Dictionary, e: Dictionary, d: Dictionary) -> void:
	var p = d.get("potion", null)
	if p is Dictionary:
		if p.has("heal"):
			var r: Dictionary = Dice.roll(str(p.heal))
			eng.dice_event(c.id, str(d.name), r.dice, int(r.total) - int(r.rolls.reduce(func(x, y): return x + y, 0)), int(r.total), "", t.id, "damage")
			eng.heal_creature(t, int(r.total), c, str(d.name))
		var rounds := int(p.get("rounds", 600))
		if int(p.get("temp_hp", 0)) > 0:
			eng.grant_temp_hp(t, int(p.temp_hp), str(d.name))
		if p.get("bless", false):
			eng.add_effect(t, {"name": "Heroism (potion)", "src": "potion_" + str(t.id), "mods": {"attack_dice": "1d4", "save_dice": "1d4"},
				"rounds": rounds, "tick_cid": t.id, "tick_on": "end"})
		var fx_src := "potion_" + str(t.id)
		if p.get("climb", false):
			eng.add_effect(t, {"name": "Climbing (potion)", "src": fx_src, "rounds": rounds, "tick_cid": t.id, "tick_on": "end"})
			eng.log_line("  %s can climb as fast as they walk for an hour." % eng.nm(t))
		if p.get("breath", null) is Dictionary:
			eng.add_effect(t, {"name": "Fire Breath (potion)", "src": fx_src, "rounds": rounds, "tick_cid": t.id, "tick_on": "end", "breath": p.breath.duplicate(true)})
			eng.log_line("  Smoke curls from %s's mouth: fire breath, %d uses (a bonus action each)." % [eng.nm(t), int(p.breath.get("uses", 3))])
		if int(p.get("set_str", 0)) > 0:
			eng.add_effect(t, {"name": "Hill Giant Strength (Str %d)" % int(p.set_str), "src": fx_src, "rounds": rounds, "tick_cid": t.id, "tick_on": "end", "set_str": int(p.set_str)})
			eng.log_line("  %s swells with a giant's strength (Strength %d)." % [eng.nm(t), int(p.set_str)])
		if p.get("haste", false):
			eng.add_effect(t, {"name": "Hasted (potion)", "tag": "haste", "src": fx_src, "mods": {"ac": 2, "speed_mult": 2}, "rounds": rounds, "tick_cid": t.id, "tick_on": "end"})
			eng.sync_move(t)
			eng.log_line("  %s moves in a blur: hasted for a minute." % eng.nm(t))
		if p.get("invisible", false):
			eng.add_effect(t, {"name": "Invisible (potion)", "cond": "invisible", "breaks": true, "src": fx_src, "rounds": rounds, "tick_cid": t.id, "tick_on": "end"})
			eng.log_line("  %s fades from sight." % eng.nm(t))
		if p.get("cure", []) is Array and not p.get("cure", []).is_empty():
			var cured: Array = p.cure
			var gone: PackedStringArray = []
			for e2 in t.effects.duplicate():
				if str(e2.get("cond", "")) in cured:
					gone.append(str(e2.cond))
					eng.remove_effect(t, e2.eid)
			eng.log_line("  %s feels cleansed%s." % [eng.nm(t), (": no longer " + ", ".join(gone)) if not gone.is_empty() else ""])
		var rs := str(p.get("resist", ""))
		if rs != "":
			var types: Array = Data.DAMAGE_TYPES.duplicate() if rs == "all" else [str(e.get("dtype", "fire"))]
			eng.add_effect(t, {"name": str(d.name), "src": "potion_" + str(t.id), "mods": {"resist": types}, "rounds": rounds, "tick_cid": t.id, "tick_on": "end"})
			eng.log_line("  %s resists %s damage." % [eng.nm(t), "all" if rs == "all" else types[0]])
	var use = d.get("use", null)
	if use is Dictionary and str(use.get("effect", "")) == "antitoxin":
		eng.add_effect(t, {"name": "Antitoxin", "src": "antitoxin_" + str(t.id), "mods": {"poison_save_adv": true}, "rounds": 600, "tick_cid": t.id, "tick_on": "end"})
		eng.log_line("  %s has advantage on saves against poison for an hour." % eng.nm(t))

static func _a(name: String) -> String:
	var l := name.to_lower()
	return ("an " if l.substr(0, 1) in ["a", "e", "i", "o", "u"] else "a ") + name

## Dawn (a long rest): wands regain charges, a pearl of power can be used again.
static func dawn(c: Dictionary) -> void:
	if not c.get("inventory", null) is Array:
		return
	for e in c.inventory:
		var d := def(e)
		if not d.has("charges") or not d.has("recharge"):
			continue
		var mx := int(d.charges)
		if str(d.recharge) == "full":
			e.charges = mx
		else:
			e.charges = mini(mx, int(e.get("charges", 0)) + int(Dice.roll(str(d.recharge)).total))

## Loot (coins, potions, magic items, gear) into `c`'s pack. Returns a summary.
static func receive_loot(eng: CombatEngine, c: Dictionary, loot: Dictionary) -> String:
	var bits: PackedStringArray = []
	var got_c := {}
	for k in COINS:
		var n := int(loot.get(k, 0))
		if n > 0:
			got_c[k] = n
			bits.append("%s %s" % [_thousands(n), k])
	if not got_c.is_empty():
		give_coins(c, got_c)
		eng.float_text(c.id, "+" + fmt_coins(got_c), "#ffd166")
	# Old map files list potions by id with a count.
	for pid in ["potion_healing", "potion_greater_healing", "potion_superior_healing", "potion_supreme_healing"]:
		var n := int(loot.get(pid, 0))
		if n > 0:
			add(c, pid, n)
			bits.append("%d %s%s" % [n, str(Data.item(pid).name).to_lower(), "" if n == 1 else "s"])
	for g in loot.get("gear", []):
		if g is Dictionary and not Data.item(str(g.get("id", ""))).is_empty():
			var got := add_entry(c, g)
			var nm := display_name(got)
			var qn := int(g.get("qty", 1))
			bits.append(("[color=%s]%s[/color]" % [rarity_color(got), nm]) if is_magic(def(got)) else (("%d× %s" % [qn, nm]) if qn > 1 else nm))
	return ", ".join(bits)
