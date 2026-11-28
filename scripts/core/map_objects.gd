class_name MapObjects
extends RefCounted
## Things on the map that creatures can interact with, following the 2014 rules:
##   * Breakable walls and furniture: object Armor Class by material and hit points by size (DMG p.246-247).
##     Objects are immune to poison and psychic damage. A broken wall leaves rubble (difficult terrain).
##   * Objects you can pick up and use as improvised weapons (PHB p.147-148): something that resembles a
##     weapon is used as that weapon (a table leg is a club), anything else deals 1d4 with no proficiency
##     bonus. Any of them can be thrown (range 20/60 ft). You can only wield what you can carry
##     (Strength score × 15 lb, doubled for each size above Medium, halved for Tiny).
##   * Chests, crates and loot: opening one, or picking something up, is your one free object interaction on
##     your turn; another one that turn takes the Use an Object action (PHB p.190). A locked chest is opened
##     with thieves' tools (Dexterity check, proficiency for rogues and artificers) or forced open with a
##     Strength (Athletics) check. Potions of healing found inside take an action to drink or give.
##
## Objects live in state.objects: {"id", "k", "pos": Vector2i, "hp", "max_hp", "under", ...}. While an object
## is there its cell has the kind's terrain ("cell": a crate is a wall, a chest difficult terrain, a rock
## leaves the floor alone); "under" is what the cell goes back to when the object is lifted away.
## Map files store objects with "x" / "y" instead of "pos" (see to_map / from_map).

const FLOOR := EngineBase.FLOOR
const WALL := EngineBase.WALL
const DIFFICULT := EngineBase.DIFFICULT

## DMG p.246: object Armor Class by material.
const MAT_AC := {"cloth": 11, "glass": 13, "wood": 15, "bone": 15, "stone": 17, "iron": 19}
## DMG p.247: object hit points by size, [fragile, resilient] (the averages of 1d4 / 2d4, 1d6 / 3d6, 1d8 / 4d8, 1d10 / 5d10).
const SIZE_HP := {"tiny": [2, 5], "small": [3, 10], "medium": [4, 18], "large": [5, 27]}
## DMG p.247: objects are immune to poison and psychic damage.
const IMMUNE := ["poison", "psychic"]

## Every kind of object. cell: the terrain it gives its cell (-1 leaves the terrain alone); broken: the terrain
## left when it breaks (-1: whatever was under it). lb: weight (0 = can't be picked up). like: the weapon it is
## used as (PHB: "a table leg is akin to a club"); otherwise dmg / type are its improvised damage.
const KINDS := {
	"weak_wall": {"name": "Rotten timber wall", "mat": "wood", "size": "small", "res": true, "cell": WALL, "broken": DIFFICULT, "lb": 0,
		"desc": "Rotting planks. A few good blows break through and leave rubble."},
	"cracked_wall": {"name": "Cracked stone wall", "mat": "stone", "size": "medium", "res": true, "cell": WALL, "broken": DIFFICULT, "lb": 0,
		"desc": "Crumbling masonry. Enough force knocks a hole through it."},
	"crate": {"name": "Crate", "mat": "wood", "size": "small", "res": true, "cell": WALL, "broken": DIFFICULT, "lb": 50, "container": true,
		"dmg": "1d4", "type": "bludgeoning", "desc": "A heavy wooden crate. Break it open, or lift and throw it."},
	"barrel": {"name": "Barrel", "mat": "wood", "size": "small", "res": true, "cell": WALL, "broken": DIFFICULT, "lb": 70, "container": true,
		"dmg": "1d4", "type": "bludgeoning", "desc": "A full barrel. Break it open, or lift and throw it."},
	"chest": {"name": "Chest", "mat": "wood", "size": "small", "res": true, "cell": DIFFICULT, "broken": DIFFICULT, "lb": 0, "container": true,
		"desc": "A chest. Open it to take what's inside."},
	"stash": {"name": "Storage chest", "mat": "wood", "size": "medium", "res": true, "cell": DIFFICULT, "broken": DIFFICULT, "lb": 0, "fixed": true, "storage": true,
		"desc": "A sturdy chest for the party's things. Store what you don't want to carry and take it back later."},
	"chair": {"name": "Chair", "mat": "wood", "size": "small", "res": false, "cell": -1, "broken": -1, "lb": 10, "dmg": "1d4", "type": "bludgeoning",
		"desc": "Improvised weapon: 1d4 bludgeoning."},
	"table_leg": {"name": "Table leg", "mat": "wood", "size": "tiny", "res": true, "cell": -1, "broken": -1, "lb": 3, "like": "club",
		"desc": "Akin to a club (PHB): 1d4 bludgeoning, proficiency applies."},
	"branch": {"name": "Heavy branch", "mat": "wood", "size": "small", "res": true, "cell": -1, "broken": -1, "lb": 10, "like": "greatclub",
		"desc": "Akin to a greatclub: 1d8 bludgeoning, proficiency applies."},
	"rock": {"name": "Rock", "mat": "stone", "size": "tiny", "res": true, "cell": -1, "broken": -1, "lb": 5, "dmg": "1d4", "type": "bludgeoning",
		"desc": "Improvised weapon: 1d4 bludgeoning, best thrown (20/60 ft)."},
	"bottle": {"name": "Bottle", "mat": "glass", "size": "tiny", "res": false, "cell": -1, "broken": -1, "lb": 2, "dmg": "1d4", "type": "bludgeoning",
		"shatter": true, "desc": "Improvised weapon: 1d4 bludgeoning. Shatters when thrown."},
	"pitchfork": {"name": "Pitchfork", "mat": "wood", "size": "small", "res": true, "cell": -1, "broken": -1, "lb": 5, "like": "trident",
		"desc": "Akin to a trident: 1d6 piercing, proficiency applies."},
	"torch": {"name": "Torch", "mat": "wood", "size": "tiny", "res": true, "cell": -1, "broken": -1, "lb": 1, "dmg": "1", "type": "fire",
		"desc": "A burning torch: 1 fire damage as an improvised weapon (PHB p.153)."},
	"item": {"name": "Weapon", "mat": "iron", "size": "tiny", "res": true, "cell": -1, "broken": -1, "lb": 3,
		"desc": "A weapon lying on the ground. Pick it up to fight with it."},
	"pile": {"name": "Loot", "mat": "cloth", "size": "tiny", "res": true, "cell": -1, "broken": -1, "lb": 0, "container": true, "fixed": true,
		"desc": "Whatever spilled out. Take it."},
}
## What the DM can place by hand, in menu order.
const PLACEABLE := ["chest", "stash", "crate", "barrel", "weak_wall", "cracked_wall", "chair", "table_leg", "branch", "rock", "bottle", "pitchfork", "torch"]

## Potions found as loot (DMG p.187-188). Drinking one, or giving one to a creature within reach, is an action.
const POTIONS := {
	"potion_healing": {"name": "Potion of Healing", "heal": "2d4+2"},
	"potion_greater_healing": {"name": "Potion of Greater Healing", "heal": "4d4+4"},
	"potion_superior_healing": {"name": "Potion of Superior Healing", "heal": "8d4+8"},
}

# ================================================================ basics

static func list(s: Dictionary) -> Array:
	if not s.has("objects") or not s.objects is Array:
		s.objects = []
	return s.objects

static func kind(o: Dictionary) -> Dictionary:
	return KINDS.get(str(o.get("k", "")), {})

static func name_of(o: Dictionary) -> String:
	if str(o.get("k", "")) == "item":
		return str(Data.item(str(o.get("item", ""))).get("name", "Weapon"))
	return str(o.get("name", kind(o).get("name", "Object")))

static func ac_of(o: Dictionary) -> int:
	var k := kind(o)
	if str(o.get("k", "")) == "item":
		return 19
	return int(o.get("ac", MAT_AC.get(str(k.get("mat", "wood")), 15)))

## The terrain this object gives its cell (-1: leaves it alone). An object can override its kind's ("cell"):
## a crate standing among furniture keeps that cell difficult terrain instead of walling it.
static func cell_of(o: Dictionary) -> int:
	return int(o.get("cell", kind(o).get("cell", -1)))

static func base_hp(k: String) -> int:
	var d: Dictionary = KINDS.get(k, {})
	var row: Array = SIZE_HP.get(str(d.get("size", "small")), [3, 10])
	return int(row[1] if d.get("res", true) else row[0])

static func destructible(o: Dictionary) -> bool:
	return not kind(o).get("fixed", false) and int(o.get("max_hp", 0)) > 0

static func liftable(o: Dictionary) -> bool:
	return int(kind(o).get("lb", 0)) > 0

static func weight(o: Dictionary) -> int:
	return int(kind(o).get("lb", 0))

static func is_container(o: Dictionary) -> bool:
	return kind(o).get("container", false) and not o.get("opened", false) and (str(o.k) in ["chest", "pile"] or not o.get("loot", {}).is_empty())

# ================================================================ storage

## Somewhere the party can leave things and come back for them: a storage chest, or any chest that has been
## opened (and emptied of its loot). What it holds lives in o.store = {"inventory": [...], "coins": {...}},
## the same shape as a character's belongings, so Inventory's functions work on it.
static func is_storage(o: Dictionary) -> bool:
	if kind(o).get("storage", false):
		return true
	return str(o.get("k", "")) == "chest" and o.get("opened", false) and not o.get("locked", false)

static func store_of(o: Dictionary) -> Dictionary:
	if not o.get("store", null) is Dictionary:
		o.store = {}
	Inventory.list(o.store)
	Inventory.coins(o.store)
	return o.store

## Whether a chest holds nothing stored.
static func store_empty(o: Dictionary) -> bool:
	var st = o.get("store", null)
	if not st is Dictionary:
		return true
	return st.get("inventory", []).is_empty() and Inventory.coin_count(st.get("coins", {})) == 0

## Storage chests `c` can reach (within 5 ft and in sight), nearest first.
static func storage_near(eng: CombatEngine, c: Dictionary) -> Array:
	if c.is_empty() or not c.has("pos"):
		return []
	var out: Array = list(eng.s).filter(func(o): return is_storage(o) and _in_reach(eng, c, o, 5))
	out.sort_custom(func(a, b): return eng.dist_to_cell(c, a.pos) < eng.dist_to_cell(c, b.pos))
	return out

## A short summary of what a chest holds ("3 items, 120 gp").
static func store_text(o: Dictionary) -> String:
	if store_empty(o):
		return "nothing"
	var st: Dictionary = o.store
	var bits: PackedStringArray = []
	var n := 0
	for e in st.get("inventory", []):
		n += int(e.get("qty", 1))
	if n > 0:
		bits.append("%d item%s" % [n, "" if n == 1 else "s"])
	if Inventory.coin_count(st.get("coins", {})) > 0:
		bits.append(Inventory.fmt_coins(st.coins))
	return ", ".join(bits)

## What a chest holds, as loot that spills onto the floor when it breaks or is taken away.
static func store_as_loot(o: Dictionary) -> Dictionary:
	if store_empty(o):
		return {}
	var l: Dictionary = {}
	for k in Inventory.COINS:
		if int(o.store.get("coins", {}).get(k, 0)) > 0:
			l[k] = int(o.store.coins[k])
	var gear: Array = []
	for e in o.store.get("inventory", []):
		var q: Dictionary = e.duplicate(true)
		q.erase("uid")
		gear.append(q)
	if not gear.is_empty():
		l.gear = gear
	return l

## Leave whatever a chest held in a loot pile on its cell (the chest broke or the DM took it away).
static func spill_store(eng: CombatEngine, o: Dictionary) -> void:
	var l := store_as_loot(o)
	o.erase("store")
	if l.is_empty():
		return
	place(eng, make("pile", o.pos, FLOOR, {"loot": l}))
	eng.log_line("  What was stored in the %s lies on the floor." % name_of(o).to_lower())

## A new object of kind `k` at `pos` (no id yet). extra: fields to set ("locked", "dc", "loot", "item"...).
static func make(k: String, pos: Vector2i, under := FLOOR, extra := {}) -> Dictionary:
	var hp := base_hp(k)
	var o := {"k": k, "pos": pos, "hp": hp, "max_hp": hp, "under": under}
	o.merge(extra, true)
	return o

## Put object `o` on the map: it gets an id and its cell takes the kind's terrain.
static func place(eng: CombatEngine, o: Dictionary) -> Dictionary:
	var k := kind(o)
	if k.is_empty() or not eng.in_bounds(o.pos):
		return {}
	o.id = eng.new_id("o")
	var c := cell_of(o)
	if c >= 0:
		o.under = _base_terrain(eng.cell(o.pos)) if not o.has("under") else int(o.under)
		eng.set_cell(o.pos, c)
	list(eng.s).append(o)
	return o

## What a cell is under an object: never a wall (a crate dropped next to a wall stands on floor).
static func _base_terrain(v: int) -> int:
	return v if v in [FLOOR, DIFFICULT, EngineBase.WATER] else FLOOR

static func at(s: Dictionary, p: Vector2i) -> Array:
	return list(s).filter(func(o): return o.pos == p)

static func by_id(s: Dictionary, id: String) -> Dictionary:
	for o in list(s):
		if str(o.get("id", "")) == id:
			return o
	return {}

## Take object `o` off the map; its cell goes back to `terrain` (-1: what was under it, if the object set the cell).
static func remove(eng: CombatEngine, o: Dictionary, terrain := -1) -> void:
	list(eng.s).erase(o)
	var k := kind(o)
	if cell_of(o) >= 0 or terrain >= 0:
		var v := terrain if terrain >= 0 else int(o.get("under", FLOOR))
		# Another object still standing there keeps the cell as it is.
		if at(eng.s, o.pos).any(func(q): return cell_of(q) >= 0):
			return
		eng.set_cell(o.pos, v)

# ================================================================ strength and carrying

## PHB p.176: carrying capacity is Strength × 15 lb, doubled for each size category above Medium
## (halved for Tiny); Powerful Build counts as one size larger.
static func carry_capacity(c: Dictionary) -> int:
	var st: int = int(c.get("scores", {}).get("str", 10))
	var mult: float = {"tiny": 0.5, "small": 1.0, "medium": 1.0, "large": 2.0, "huge": 4.0, "gargantuan": 8.0}.get(str(c.get("size", "medium")), 1.0)
	if c.get("tags", {}).has("powerful_build"):
		mult *= 2.0
	return int(st * 15 * mult)

static func held(c: Dictionary) -> Dictionary:
	var h = c.get("held_obj", {})
	return h if h is Dictionary else {}

# ================================================================ improvised weapons

## Whether `c` is proficient with weapon `w` (an items.json entry). Monsters are proficient with weapons.
static func _proficient(c: Dictionary, w: Dictionary) -> bool:
	if c.get("kind", "") != "pc":
		return true
	var profs: Array = c.get("weapon_prof", [])
	return str(w.get("category", "")) in profs or str(w.get("id", "")) in profs

## The attack `c` makes with held object `o` (thrown = a ranged throw). PHB p.147-148.
static func improvised_attack(eng: CombatEngine, c: Dictionary, o: Dictionary, thrown: bool) -> Dictionary:
	var k := kind(o)
	var like_id := str(o.get("item", "")) if str(o.get("k", "")) == "item" else str(k.get("like", ""))
	var w: Dictionary = Data.item(like_id) if like_id != "" else {}
	var mods: Dictionary = c.get("mods", {})
	var strm := int(mods.get("str", 0))
	var dexm := int(mods.get("dex", 0))
	var nm := name_of(o)
	var die: String
	var dtype: String
	var prof := false
	var ability := "str"
	var real_thrown := false
	var props: Array = []
	if not w.is_empty():
		# Resembles (or is) a real weapon: use it as that weapon.
		die = str(w.damage)
		dtype = str(w.type)
		prof = _proficient(c, w)
		props = w.get("props", [])
		if "finesse" in props and dexm > strm:
			ability = "dex"
		if not w.get("melee", true):
			ability = "dex"
		real_thrown = "thrown" in props
	else:
		die = str(k.get("dmg", "1d4"))
		dtype = str(k.get("type", "bludgeoning"))
		# Tavern Brawler (if the game has it) makes you proficient with improvised weapons.
		prof = "tavern_brawler" in c.get("feats", [])
	var bonus := int(mods.get(ability, 0))
	var to_hit := bonus + (int(c.get("prof", 2)) if prof else 0)
	var dmg := Dice.add(die, str(bonus)) if bonus != 0 else die
	var atk := {"id": "held" if not thrown else "held_throw", "name": ("Throw " if thrown else "") + nm, "weapon": "", "melee": not thrown,
		"ability": ability, "to_hit": to_hit, "damage": [{"dice": dmg, "type": dtype}], "die": die, "reach": 10 if "reach" in props else 5,
		"range": 0, "long_range": 0, "props": props, "magic": false, "finesse": "finesse" in props, "heavy": "heavy" in props,
		"held_obj": true, "improvised": w.is_empty(),
		"desc": ("Improvised weapon%s." % ("" if prof else ", no proficiency bonus")) if w.is_empty() else ("Used as a %s." % str(w.name).to_lower())}
	if thrown:
		# A thrown weapon keeps its own range; anything else thrown is improvised: 20/60 ft (PHB p.148).
		atk.range = int(w.get("range", 20)) if real_thrown else 20
		atk.long_range = int(w.get("long_range", 60)) if real_thrown else 60
		atk.thrown = true
		if not real_thrown and not w.is_empty():
			# A melee weapon that isn't made for throwing is an improvised weapon when thrown.
			atk.damage = [{"dice": Dice.add("1d4", str(strm)) if strm != 0 else "1d4", "type": dtype}]
			atk.to_hit = strm + (int(c.get("prof", 2)) if "tavern_brawler" in c.get("feats", []) else 0)
			atk.ability = "str"
			atk.improvised = true
			atk.desc = "Thrown, it's an improvised weapon: 1d4, no proficiency bonus."
	return atk

# ================================================================ actions

## Object actions for `c` (added to CombatEngine.get_actions). kind "object" actions run through execute();
## attacks with a held object are ordinary weapon actions (kind "weapon").
static func actions(eng: CombatEngine, c: Dictionary) -> Array:
	var out: Array = []
	var objs: Array = list(eng.s)
	var h := held(c)
	var t: Dictionary = c.get("turn", {})
	var free_left: bool = not eng.s.in_combat or not t.get("obj_used", false)
	var interact_cost := "free" if free_left else "action"
	var use_note := "" if free_left else " (Use an Object: you've had your free object interaction this turn)"
	if not h.is_empty():
		var melee := improvised_attack(eng, c, h, false)
		var throw := improvised_attack(eng, c, h, true)
		out.append(eng._act("atk:held", melee.name, "weapon", "attack", "enemy", int(melee.reach), eng._weapon_desc(melee), {"atk": melee, "cat": "attack"}))
		out.append(eng._act("atk:held_throw", throw.name, "weapon", "attack", "enemy", int(throw.long_range), eng._weapon_desc(throw), {"atk": throw, "cat": "attack"}))
		out.append(eng._act("obj_drop", "Drop " + name_of(h), "object", "free", "self", 0, "Let go of it (no action needed). It lands in your space, or beside you if it's bulky.", {"cat": "basic"}))
	if objs.any(func(o): return destructible(o)):
		var best := _best_attack(eng, c, true)
		if not best.is_empty():
			out.append(eng._act("obj_smash", "Attack Object", "object", "attack", "object", int(best.reach), "Replaces one attack: hit a wall, crate, chest or other object with %s (%s to hit). Objects have AC by material and HP by size (DMG); they're immune to poison and psychic damage." % [best.name, Rules.fmt_mod(int(best.to_hit))], {"cat": "basic", "atk": best}))
		var rbest := _best_attack(eng, c, false)
		if not rbest.is_empty():
			out.append(eng._act("obj_shoot", "Shoot Object", "object", "attack", "object", int(rbest.long_range if int(rbest.long_range) > 0 else rbest.range), "Replaces one attack: shoot or throw at an object with %s (%s to hit)." % [rbest.name, Rules.fmt_mod(int(rbest.to_hit))], {"cat": "basic", "atk": rbest}))
	if objs.any(func(o): return liftable(o)):
		var a := eng._act("obj_lift", "Pick Up", "object", interact_cost, "object", 5, "Pick up an object within 5 ft: swing it or throw it as an improvised weapon. You can wield up to %d lb (Strength × 15)%s." % [carry_capacity(c), use_note], {"cat": "basic"})
		if not h.is_empty():
			a.enabled = false
			a.reason = "Your hands are full: drop the %s first" % name_of(h).to_lower()
		out.append(a)
	if objs.any(func(o): return is_container(o)):
		out.append(eng._act("obj_open", "Open / Loot", "object", interact_cost, "object", 5, "Open a chest (or a broken crate) within 5 ft and take what's inside%s." % use_note, {"cat": "basic"}))
	if objs.any(func(o): return o.get("locked", false) and not o.get("opened", false)):
		var prof := _has_thieves_tools(c)
		var pa := eng._act("obj_picklock", "Pick Lock", "object", "action", "object", 5, "Dexterity check with thieves' tools against the lock's DC%s." % (" (proficient: + proficiency bonus)" if prof else " (not proficient: Dexterity only)"), {"cat": "basic"})
		# PHB p.154: picking a lock takes thieves' tools.
		if not _carries_thieves_tools(c):
			pa.enabled = false
			pa.reason = "No thieves' tools in your pack"
		out.append(pa)
		out.append(eng._act("obj_force", "Force Open", "object", "action", "object", 5, "Strength (Athletics) check against the lock's DC to break the lock or wrench the lid open.", {"cat": "basic"}))
	# A weapon lying on the ground (or held) can go into the pack instead (Inventory).
	if c.get("kind", "") == "pc":
		if objs.any(func(o): return str(o.get("k", "")) == "item"):
			out.append(eng._act("obj_stow", "Stow Weapon", "object", interact_cost, "object", 5, "Pick up a weapon within 5 ft and put it in your pack, to keep it after the fight%s." % use_note, {"cat": "basic"}))
		if str(h.get("k", "")) == "item":
			out.append(eng._act("obj_stow_held", "Stow " + name_of(h), "object", interact_cost, "self", 0, "Put the weapon you're holding into your pack%s." % use_note, {"cat": "basic"}))
		# The bodies of slain monsters can be searched for the coins they carried (DMG individual treasure).
		if not corpses(eng).is_empty():
			out.append(eng._act("obj_search", "Search Body", "object", "action" if eng.s.in_combat else "free", "object", 5,
				"Go through the pockets of a slain creature within 5 ft for coins (DMG individual treasure, by challenge rating). Takes an action in a fight.", {"cat": "basic"}))
	# Potions, thrown flasks, torches and lanterns, wands and scrolls from the character's pack.
	out.append_array(Inventory.actions(eng, c))
	return out

## Proficient with thieves' tools: a PC's tool proficiencies (class, background, race; see Inventory.tool_profs).
## A creature without a character sheet counts as proficient if it has rogue or artificer levels.
static func _has_thieves_tools(c: Dictionary) -> bool:
	if c.get("kind", "") == "pc" and c.has("tools"):
		return "thieves_tools" in c.tools
	var cl: Dictionary = c.get("class_levels", {})
	return int(cl.get("rogue", 0)) > 0 or int(cl.get("artificer", 0)) > 0

## Carrying thieves' tools to pick a lock with. Creatures without an inventory (monsters) bring their own.
static func _carries_thieves_tools(c: Dictionary) -> bool:
	if c.get("kind", "") != "pc" or not c.get("inventory", null) is Array:
		return true
	return Inventory.has_item(c, "thieves_tools")

## The attack `c` would use on an object: its best melee (or ranged) attack by average damage, a held object included.
static func _best_attack(eng: CombatEngine, c: Dictionary, melee: bool) -> Dictionary:
	var cands: Array = []
	for a in eng.attacks_of(c):
		if bool(a.get("melee", true)) == melee and str(a.get("cost", "attack")) == "attack" and not a.get("offhand", false):
			# A bow with no arrows left can't shoot at anything.
			var ammo: String = Inventory.ammo_for(c, a)
			if ammo != "" and Inventory.count(c, ammo) <= 0:
				continue
			cands.append(a)
	var h := held(c)
	if not h.is_empty():
		cands.append(improvised_attack(eng, c, h, not melee))
	var best: Dictionary = {}
	var bv := -1.0
	for a in cands:
		var v := 0.0
		for d in a.get("damage", []):
			v += Dice.average(str(d.dice))
		v += float(int(a.get("to_hit", 0))) * 0.5
		if v > bv:
			bv = v
			best = a
	if not best.is_empty() and not melee and int(best.get("range", 0)) <= 0:
		return {}
	return best

## Slain monsters not yet searched, as stand-in objects {"k": "corpse", "pos", "cid", "name"} so the object
## actions (targeting, highlighting) can aim at them.
static func corpses(eng: CombatEngine) -> Array:
	var out: Array = []
	for m in eng.all_combatants():
		if m.get("kind", "") == "monster" and (m.get("dead", false) or m.get("death", {}).get("dead", false)) and not m.get("searched", false) and m.has("pos"):
			out.append({"k": "corpse", "pos": m.pos, "cid": m.id, "name": "Body of %s" % str(m.name)})
	return out

## Objects action `a` could be used on (for target highlighting and validation).
static func valid_targets(eng: CombatEngine, c: Dictionary, a: Dictionary) -> Array:
	var aid := str(a.get("id", ""))
	if aid == "obj_search":
		return corpses(eng).filter(func(o): return _in_reach(eng, c, o, int(a.get("range", 5))))
	return list(eng.s).filter(func(o): return _fits_action(aid, o) and _in_reach(eng, c, o, int(a.get("range", 5))))

static func _fits_action(aid: String, o: Dictionary) -> bool:
	match aid:
		"obj_smash", "obj_shoot": return destructible(o)
		"obj_lift": return liftable(o)
		"obj_open": return is_container(o)
		"obj_picklock", "obj_force": return o.get("locked", false) and not o.get("opened", false)
		"obj_stow": return str(o.get("k", "")) == "item"
	return false

static func _in_reach(eng: CombatEngine, c: Dictionary, o: Dictionary, rng: int) -> bool:
	if rng > 0 and eng.dist_to_cell(c, o.pos) > rng:
		return false
	for q in eng.occupied_cells(c):
		if eng.los_cells(q, o.pos):
			return true
	return false

## The object action `a` aimed at an object at `cell`, the first one there it fits.
static func target_at(eng: CombatEngine, c: Dictionary, a: Dictionary, cell: Vector2i) -> Dictionary:
	if str(a.id) == "obj_search":
		for o in corpses(eng):
			if o.pos == cell:
				return o
		return {}
	for o in at(eng.s, cell):
		if _fits_action(str(a.id), o):
			return o
	return {}

## Run a kind "object" action. Returns false (and logs why) when it can't be done.
static func execute(eng: CombatEngine, c: Dictionary, a: Dictionary, targets: Array, cellp: Vector2i) -> bool:
	var aid := str(a.id)
	if aid == "obj_drop":
		return drop(eng, c, true)
	if aid.begins_with("inv:"):
		return Inventory.execute(eng, c, a, targets, cellp)
	if aid == "obj_stow_held":
		var h := held(c)
		if str(h.get("k", "")) != "item":
			return false
		_pay_interaction(eng, c, a)
		c.erase("held_obj")
		Inventory.add(c, str(h.get("item", "")), 1)
		eng.log_line("%s stows the %s." % [eng.nm(c), name_of(h).to_lower()])
		eng.sfx("pickup", c.id)
		return true
	var o := target_at(eng, c, a, cellp)
	if o.is_empty():
		eng.log_line("[color=#888]There's nothing there to %s.[/color]" % str(a.name).to_lower())
		return false
	if not _in_reach(eng, c, o, int(a.range)):
		eng.log_line("[color=#888]The %s is out of reach (%d ft).[/color]" % [name_of(o).to_lower(), int(a.range)])
		return false
	match aid:
		"obj_search":
			var body: Dictionary = eng.C(str(o.cid))
			if body.is_empty():
				return false
			_pay_interaction(eng, c, a)
			body.searched = true
			var purse: Dictionary = {}
			if Inventory.carries_treasure(body, str(eng.s.get("treasure", "mindless"))):
				purse = Inventory.roll_individual(float(body.get("cr", 0)))
			var got := Inventory.receive_loot(eng, c, purse) if not purse.is_empty() else ""
			eng.log_line("%s searches the body of %s%s" % [eng.nm(c), str(body.name), (": " + got + ".") if got != "" else " and finds nothing of value."])
			eng.sfx("pickup", c.id)
		"obj_smash", "obj_shoot":
			var piece: Dictionary = Inventory.spend_ammo(c, {"ammo": Inventory.ammo_for(c, a.atk)})
			if piece.get("none", false):
				return false
			eng.pay(c, "attack")
			_attack_object(eng, c, o, a.atk)
			Inventory.note_spent(c, piece, false)
		"obj_lift":
			var lb := weight(o)
			if lb > carry_capacity(c):
				eng.log_line("[color=#888]%s can't wield the %s: %d lb is more than %d lb (Strength × 15).[/color]" % [c.name, name_of(o).to_lower(), lb, carry_capacity(c)])
				return false
			if not held(c).is_empty():
				return false
			_pay_interaction(eng, c, a)
			remove(eng, o)
			o.erase("pos")
			c.held_obj = o
			eng.log_line("%s picks up the %s." % [eng.nm(c), name_of(o).to_lower()])
			eng.sfx("pickup", c.id)
		"obj_stow":
			_pay_interaction(eng, c, a)
			remove(eng, o)
			Inventory.add(c, str(o.get("item", "")), 1)
			eng.log_line("%s picks up the %s and stows it." % [eng.nm(c), name_of(o).to_lower()])
			eng.sfx("pickup", c.id)
		"obj_open":
			if o.get("locked", false):
				eng.log_line("[color=#888]The %s is locked (DC %d). Pick the lock, force it, or smash it.[/color]" % [name_of(o).to_lower(), int(o.get("dc", 15))])
				eng.float_text(c.id, "Locked", "#e8b84a")
				return false
			_pay_interaction(eng, c, a)
			_open(eng, c, o)
		"obj_picklock", "obj_force":
			if aid == "obj_picklock" and not _carries_thieves_tools(c):
				eng.log_line("[color=#888]%s has no thieves' tools to pick the lock with.[/color]" % c.name)
				return false
			eng.pay(c, "action")
			var dc := int(o.get("dc", 15))
			var total := 0
			var what := ""
			if aid == "obj_force":
				var r: Dictionary = eng.skill_check(c, "str")
				total = int(r.total)
				what = str(r.text)
			else:
				var adv := -1 if eng.has_cond(c, "poisoned") or eng.has_cond(c, "frightened") or eng.exhaustion(c) >= 1 else 0
				var rr: Dictionary = Dice.roll_d20(adv, c.get("tags", {}).has("halfling_lucky"))
				var b := int(c.get("mods", {}).get("dex", 0)) + (int(c.get("prof", 2)) if _has_thieves_tools(c) else 0)
				total = int(rr.roll) + b
				what = "Thieves' tools %d" % total
				eng.dice_event(c.id, "Thieves' tools", EngineBase.d20_faces(rr), b, total, "SUCCESS" if total >= dc else "FAIL")
			if total >= dc:
				o.locked = false
				eng.log_line("%s %s the %s (%s vs DC %d)." % [eng.nm(c), "forces open" if aid == "obj_force" else "picks the lock of", name_of(o).to_lower(), what, dc])
				eng.sfx("unlock", c.id)
				_open(eng, c, o)
			else:
				eng.log_line("%s fails to %s the %s (%s vs DC %d)." % [eng.nm(c), "force open" if aid == "obj_force" else "pick the lock of", name_of(o).to_lower(), what, dc])
	return true

static func _pay_interaction(eng: CombatEngine, c: Dictionary, a: Dictionary) -> void:
	if not eng.s.in_combat:
		return
	if str(a.cost) == "free":
		c.turn.obj_used = true
	else:
		eng.pay(c, "action")

## Take what's inside: coins and potions go to the opener, weapons are laid on the ground beside the chest.
static func _open(eng: CombatEngine, c: Dictionary, o: Dictionary) -> void:
	o.opened = true
	var loot: Dictionary = o.get("loot", {})
	var got := take_loot(eng, c, loot, o.pos)
	o.loot = {}
	if str(o.k) == "pile":
		list(eng.s).erase(o)
	eng.log_line("%s opens the %s%s" % [eng.nm(c), name_of(o).to_lower(), (": " + got + ".") if got != "" else ". It's empty."])
	eng.sfx("chest", c.id)

## Give `c` the coins, potions and items in `loot`; weapons are put on the map at (or next to) `p`. Returns a summary.
static func take_loot(eng: CombatEngine, c: Dictionary, loot: Dictionary, p: Vector2i) -> String:
	# Coins, potions, magic items and gear go into the opener's pack (Inventory), and are saved with the character.
	var bits: PackedStringArray = []
	var got := Inventory.receive_loot(eng, c, loot)
	if got != "":
		bits.append(got)
	for wid in loot.get("items", []):
		if Data.item(str(wid)).is_empty():
			continue
		var spot := _drop_spot(eng, p, false)
		place(eng, make("item", spot, FLOOR, {"item": str(wid)}))
		bits.append("a %s" % str(Data.item(str(wid)).name).to_lower())
	return ", ".join(bits)

## Whether a loot dictionary holds anything.
static func has_loot(l: Dictionary) -> bool:
	if l.get("items", []).size() > 0 or l.get("gear", []).size() > 0:
		return true
	for k in Inventory.COINS:
		if int(l.get(k, 0)) > 0:
			return true
	return POTIONS.keys().any(func(pid): return int(l.get(pid, 0)) > 0)

## Put down what `c` holds: in its own space, or the nearest open cell for something bulky.
static func drop(eng: CombatEngine, c: Dictionary, voluntary: bool) -> bool:
	var h := held(c)
	if h.is_empty():
		return false
	c.erase("held_obj")
	var bulky := int(kind(h).get("cell", -1)) == WALL
	var spot := _drop_spot(eng, c.pos, bulky)
	if spot.x < 0:
		return false
	h.pos = spot
	h.erase("under")
	h.erase("cell")
	place(eng, h)
	if voluntary:
		eng.log_line("%s drops the %s." % [eng.nm(c), name_of(h).to_lower()])
	else:
		eng.log_line("  %s drops the %s." % [eng.nm(c), name_of(h).to_lower()])
	return true

## Where something lands near `p`: `p` itself for small things; for a bulky one (a crate) the nearest cell with
## no creature, no wall and no other bulky object.
static func _drop_spot(eng: CombatEngine, p: Vector2i, bulky: bool) -> Vector2i:
	if not bulky and eng.in_bounds(p):
		return p
	for r in 4:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var q := p + Vector2i(dx, dy)
				if not eng.in_bounds(q) or eng.blocks_move(q):
					continue
				if bulky and (not eng.creature_at(q).is_empty() or not at(eng.s, q).is_empty()):
					continue
				return q
	return p if eng.in_bounds(p) else Vector2i(-1, -1)

## After a weapon attack with a held object: a thrown one leaves the hand and lands at the target's feet
## (a bottle shatters).
static func after_attack(eng: CombatEngine, c: Dictionary, atk: Dictionary, t: Dictionary) -> void:
	if not atk.get("held_obj", false) or not atk.get("thrown", false):
		return
	var h := held(c)
	if h.is_empty():
		return
	c.erase("held_obj")
	if kind(h).get("shatter", false):
		eng.log_line("  The %s shatters." % name_of(h).to_lower())
		eng.sfx("glass", t.get("id", ""))
		return
	var bulky := int(kind(h).get("cell", -1)) == WALL
	var spot := _drop_spot(eng, t.get("pos", c.pos), bulky)
	if spot.x < 0:
		return
	h.pos = spot
	h.erase("under")
	h.erase("cell")
	place(eng, h)

# ================================================================ damaging objects

## A weapon attack against an object: d20 + the attack's bonus against the object's AC (a natural 20 is a
## critical hit, a natural 1 misses).
static func _attack_object(eng: CombatEngine, c: Dictionary, o: Dictionary, atk: Dictionary) -> void:
	var melee: bool = atk.get("melee", true)
	var adv := 0
	if eng.has_cond(c, "poisoned") or eng.has_cond(c, "blinded") or eng.has_cond(c, "restrained") or eng.has_cond(c, "frightened"):
		adv = -1
	if not melee and int(atk.get("range", 0)) > 0 and eng.dist_to_cell(c, o.pos) > int(atk.range):
		adv = -1   # past normal range
	if not melee and eng.has_cond(c, "prone"):
		adv = -1
	var rr: Dictionary = Dice.roll_d20(adv, c.get("tags", {}).has("halfling_lucky"))
	var nat := int(rr.roll)
	var total := nat + int(atk.get("to_hit", 0))
	var ac := ac_of(o)
	var crit := nat == 20
	var hit := crit or (nat != 1 and total >= ac)
	eng.dice_event(c.id, str(atk.get("name", "Attack")), EngineBase.d20_faces(rr), int(atk.get("to_hit", 0)), total, "CRIT" if crit else ("HIT" if hit else "MISS"))
	eng.fx("slash" if melee else "bolt", c.pos, o.pos, "#ffffff", [], "blunt" if melee else ("throw" if atk.get("thrown", false) else "bow"))
	if eng.is_turn_of(c):
		c.turn.attacked_any = true
	if not hit:
		eng.log_line("%s attacks the %s with %s and misses (%d vs AC %d)." % [eng.nm(c), name_of(o).to_lower(), atk.get("name", "a weapon"), total, ac])
		after_attack(eng, c, atk, {"pos": o.pos})
		return
	var parts: Array = []
	for d in atk.get("damage", []):
		var r: Dictionary = Dice.roll(str(d.dice), {"crit": crit})
		parts.append({"amount": int(r.total), "type": str(d.get("type", "bludgeoning"))})
	eng.log_line("%s %s the %s with %s (%d vs AC %d)." % [eng.nm(c), "crits" if crit else "hits", name_of(o).to_lower(), atk.get("name", "a weapon"), total, ac])
	after_attack(eng, c, atk, {"pos": o.pos})
	damage(eng, o, parts, c)

## Damage parts [{"amount", "type"}] to an object. Poison and psychic do nothing; damage below the object's
## damage threshold (if it has one) does nothing either. Returns the damage taken.
static func damage(eng: CombatEngine, o: Dictionary, parts: Array, _src: Dictionary = {}) -> int:
	if not destructible(o) or not o in list(eng.s):
		return 0
	var total := 0
	for p in parts:
		if str(p.get("type", "")) in IMMUNE:
			continue
		total += maxi(0, int(p.get("amount", 0)))
	var thr := int(o.get("threshold", 0))
	if thr > 0 and total < thr:
		eng.log_line("  The %s shrugs it off (damage threshold %d)." % [name_of(o).to_lower(), thr])
		return 0
	if total <= 0:
		return 0
	o.hp = int(o.hp) - total
	eng.events.append({"t": "objfloat", "pos": o.pos, "text": "-%d" % total})
	if int(o.hp) > 0:
		eng.log_line("  The %s takes %d damage (%d / %d HP left)." % [name_of(o).to_lower(), total, int(o.hp), int(o.max_hp)])
		return total
	destroy(eng, o)
	return total

## The object breaks: a wall leaves rubble, a crate or barrel spills what was in it, a chest stays broken open.
static func destroy(eng: CombatEngine, o: Dictionary) -> void:
	var k := kind(o)
	var nm := name_of(o)
	var broken := int(k.get("broken", -1))
	var loot: Dictionary = o.get("loot", {}).duplicate(true)
	# Whatever the party stored in it spills out with the rest.
	var kept := store_as_loot(o)
	o.erase("store")
	for key in kept:
		if key == "gear":
			loot.gear = loot.get("gear", []) + kept.gear
		else:
			loot[key] = int(loot.get(key, 0)) + int(kept[key])
	remove(eng, o, broken)
	if broken == DIFFICULT and cell_of(o) == WALL:
		# Rubble where the wall stood (drawn only; the cell is difficult terrain).
		var props: Array = eng.s.get("props", [])
		props.append({"k": "rubble", "x": o.pos.x, "y": o.pos.y})
		eng.s.props = props
	eng.log_line("  [color=#ffb347]The %s breaks%s![/color]" % [nm.to_lower(), " apart, leaving rubble" if cell_of(o) == WALL else ""])
	eng.fx("burst", o.pos, o.pos, "#c8a070", [o.pos], "smash")
	var spill: bool = has_loot(loot)
	if spill:
		var pile := make("pile", o.pos, FLOOR, {"loot": loot})
		place(eng, pile)
		eng.log_line("  Something spills out of the wreckage.")

## An area spell or effect dealing damage over `cells`: every breakable object there takes it.
static func area_damage(eng: CombatEngine, cells: Array, parts: Array, src: Dictionary = {}) -> void:
	var hit: Array = []
	for o in list(eng.s):
		if destructible(o) and o.pos in cells:
			hit.append(o)
	for o in hit:
		damage(eng, o, parts, src)

## Server, after every request: creatures that drop (0 HP, unconscious, dead) let go of what they hold.
static func sweep(eng: CombatEngine) -> void:
	for c in eng.all_combatants():
		if held(c).is_empty():
			continue
		if c.get("dead", false) or int(c.get("hp", 0)) <= 0 or eng.has_cond(c, "unconscious") or eng.in_rope(c):
			drop(eng, c, false)

# ================================================================ loot

## How much treasure a generated map holds (generator setting "loot"). chests: how many chests, relative to
## Normal; crate: chance a breakable crate or barrel has something in it; extra: chance each chest gets a second
## helping of treasure (2 = always two).
const LOOT := {
	"none": {"name": "None", "chests": 0.0, "crate": 0.0, "extra": 0.0,
		"desc": "No treasure: no chests, and crates and barrels are empty."},
	"sparse": {"name": "Sparse", "chests": 0.5, "crate": 0.15, "extra": 0.0,
		"desc": "A chest or so, and the odd crate with a few coins in it."},
	"normal": {"name": "Normal", "chests": 1.0, "crate": 0.35, "extra": 0.0,
		"desc": "A couple of chests on a typical map, about what the DMG's treasure tables expect."},
	"rich": {"name": "Rich", "chests": 1.75, "crate": 0.55, "extra": 0.5,
		"desc": "More chests, often with a second helping of treasure, and more crates worth breaking open."},
	"hoard": {"name": "Hoard", "chests": 2.5, "crate": 0.7, "extra": 2.0,
		"desc": "A dragon's worth: many chests, each holding twice the usual treasure. Expect the party to level up their gear."},
}

static func loot_level(id) -> Dictionary:
	return LOOT.get(str(id), LOOT.normal)

## Add loot `b` into loot `a` (coins and potion counts add up; item and gear lists join).
static func merge_loot(a: Dictionary, b: Dictionary) -> void:
	for k in b:
		if b[k] is Array:
			a[k] = a.get(k, []) + b[k]
		elif b[k] is int or b[k] is float:
			a[k] = int(a.get(k, 0)) + int(b[k])

## Loot for a chest at average party level `level`: coins on the DMG treasure-hoard scale, potions of healing
## (greater / superior at higher tiers), sometimes a weapon, supplies or a magic item (Inventory.roll_magic).
static func roll_loot(rng: RandomNumberGenerator, level: int, rich := true) -> Dictionary:
	var out := {}
	var tier := 0 if level <= 4 else (1 if level <= 10 else 2)
	var mult: int = [10, 100, 400][tier]
	var dice := 2 if rich else 1
	var gp := 0
	for i in dice:
		gp += rng.randi_range(1, 6)
	out.gp = gp * mult / (1 if rich else 4)
	# Low-tier hoards also hold silver and copper (DMG treasure tables).
	if tier == 0:
		out.sp = rng.randi_range(0, 6) * (10 if rich else 2)
		out.cp = rng.randi_range(0, 6) * (10 if rich else 3)
	var pid: String = ["potion_healing", "potion_greater_healing", "potion_superior_healing"][tier]
	var n := rng.randi_range(0, 2) if rich else (1 if rng.randf() < 0.3 else 0)
	if n > 0:
		out[pid] = n
	if rich and rng.randf() < 0.4:
		var ws: Array = Data.items.values().filter(func(it): return it.get("kind", "") == "weapon" and not "ammunition" in it.get("props", []) and str(it.id) != "lance")
		ws.sort_custom(func(a, b): return str(a.id) < str(b.id))
		if not ws.is_empty():
			out.items = [str(ws[rng.randi() % ws.size()].id)]
	# Magic items: potions and scrolls mostly, now and then a permanent item (Inventory.roll_magic).
	var magic := Inventory.roll_magic(rng, tier, rich)
	# Adventuring supplies left behind by earlier explorers.
	if rich and rng.randf() < 0.35:
		var supplies := ["torch", "rations", "oil", "rope_hempen", "alchemists_fire", "acid_vial", "healers_kit", "antitoxin", "holy_water", "arrows", "crossbow_bolts"]
		var sid: String = supplies[rng.randi() % supplies.size()]
		# (Ammunition is counted in pieces: a few bundles' worth.)
		magic.append({"id": sid, "qty": (rng.randi_range(1, 3) * Inventory.bundle_of(Data.item(sid))) if sid in ["torch", "rations", "oil", "arrows", "crossbow_bolts"] else 1})
	# A treasure hoard's gems and art objects: trade goods a shop pays full value for (Inventory.roll_hoard_goods).
	if rich and rng.randf() < 0.45:
		magic.append_array(Inventory.roll_hoard_goods(rng, tier))
	if not magic.is_empty():
		out.gear = magic
	return out

# ================================================================ drawing

const DRAWN := {"chest": "chest", "stash": "chest", "crate": "crate", "barrel": "barrel", "chair": "chair", "rock": "stone", "bottle": "bottle",
	"table_leg": "table_leg", "branch": "branch", "pitchfork": "pitchfork", "torch": "torch", "item": "weapon_item", "pile": "loot_pile",
	"weak_wall": "weak_wall", "cracked_wall": "cracked_wall"}

## Objects (state form with "pos", or map-file form with "x" / "y") as MapDecor props to draw.
static func as_props(objs: Array) -> Array:
	var out: Array = []
	for o in objs:
		var k := str(DRAWN.get(str(o.get("k", "")), ""))
		if k == "":
			continue
		if k == "chest" and o.get("opened", false):
			k = "chest_open"
		var p: Vector2i = o.pos if o.get("pos", null) is Vector2i else Vector2i(int(o.get("x", 0)), int(o.get("y", 0)))
		out.append({"k": k, "x": p.x, "y": p.y})
	return out

## A short description of an object for a hover tip (BBCode). dm: also show what's inside.
static func tip(o: Dictionary, dm := false) -> String:
	var k := kind(o)
	var txt := "[b]%s[/b]" % name_of(o).replace("[", "[lb]")
	if destructible(o):
		var frac := float(o.hp) / maxf(1.0, float(o.max_hp))
		var col := "#5cc892" if frac > 0.5 else ("#e8b84a" if frac > 0.25 else "#ff7a6a")
		txt += "\nAC %d  ·  [color=%s]HP %d / %d[/color]" % [ac_of(o), col, int(o.hp), int(o.max_hp)]
	if o.get("locked", false) and not o.get("opened", false):
		txt += "\n[color=#e8b84a]Locked (DC %d)[/color]" % int(o.get("dc", 15))
	if is_storage(o):
		txt += "\n[color=#ffd166]Holds: %s[/color]\n[color=#a59cb5]Stand next to it and press 📦 Storage under your portrait to store or take things.[/color]" % store_text(o)
	if liftable(o):
		txt += "\n%d lb" % weight(o)
	if str(k.get("desc", "")) != "" and str(o.get("k", "")) != "item":
		txt += "\n[color=#a59cb5]%s[/color]" % str(k.desc)
	elif str(o.get("k", "")) == "item":
		var w: Dictionary = Data.item(str(o.get("item", "")))
		txt += "\n[color=#a59cb5]%s %s, %s %s[/color]" % [str(w.get("category", "")).capitalize(), "melee weapon" if w.get("melee", true) else "ranged weapon", str(w.get("damage", "")), str(w.get("type", ""))]
	if dm and not o.get("loot", {}).is_empty():
		txt += "\n[color=#ffd166]Inside: %s[/color]" % loot_text(o.loot)
	return txt

static func loot_text(l: Dictionary) -> String:
	var bits: PackedStringArray = []
	for k in Inventory.COINS:
		if int(l.get(k, 0)) > 0:
			bits.append("%d %s" % [int(l[k]), k])
	for pid in POTIONS:
		if int(l.get(pid, 0)) > 0:
			bits.append("%d× %s" % [int(l[pid]), POTIONS[pid].name])
	for w in l.get("items", []):
		bits.append(str(Data.item(str(w)).get("name", w)))
	for g in l.get("gear", []):
		if g is Dictionary:
			bits.append(("%d× " % int(g.qty) if int(g.get("qty", 1)) > 1 else "") + Inventory.display_name(g))
	return ", ".join(bits) if not bits.is_empty() else "nothing"

# ================================================================ map files

## Objects as stored in a map file: "x" / "y" instead of a Vector2i, no ids.
static func to_map(objs: Array) -> Array:
	var out: Array = []
	for o in objs:
		var q: Dictionary = o.duplicate(true)
		q.erase("id")
		q.erase("pos")
		q.x = o.pos.x
		q.y = o.pos.y
		out.append(q)
	return out

## Objects from a map file, checked, placed on the map (their cells take their terrain).
static func load_into(eng: CombatEngine, arr) -> void:
	eng.s.objects = []
	if not arr is Array:
		return
	for q in arr:
		if not q is Dictionary or not KINDS.has(str(q.get("k", ""))):
			continue
		var p := Vector2i(int(q.get("x", -1)), int(q.get("y", -1)))
		if not eng.in_bounds(p):
			continue
		var o := make(str(q.k), p, int(q.get("under", FLOOR)))
		o.hp = clampi(int(q.get("hp", o.hp)), 1, 999)
		o.max_hp = clampi(int(q.get("max_hp", o.max_hp)), 1, 999)
		if q.get("locked", false):
			o.locked = true
			o.dc = clampi(int(q.get("dc", 15)), 5, 30)
		if q.get("opened", false):
			o.opened = true
		if q.get("loot", null) is Dictionary:
			o.loot = _clean_loot(q.loot)
		if q.get("store", null) is Dictionary:
			var st := clean_store(q.store)
			if not st.is_empty():
				o.store = st
		if str(q.get("item", "")) != "" and not Data.item(str(q.item)).is_empty():
			o.item = str(q.item)
		if q.has("cell") and int(q.cell) in [-1, FLOOR, WALL, DIFFICULT]:
			o.cell = int(q.cell)
		var c := cell_of(o)
		list(eng.s).append(o)
		o.id = eng.new_id("o")
		if c >= 0:
			eng.set_cell(p, c)
		if list(eng.s).size() >= 2000:
			break

## What a storage chest holds, from a map file, checked: known items only, sane quantities, fresh uids.
static func clean_store(st: Dictionary) -> Dictionary:
	var out := {"inventory": [], "coins": {}}
	for k in Inventory.COINS:
		out.coins[k] = clampi(int(st.get("coins", {}).get(k, 0)) if st.get("coins", null) is Dictionary else 0, 0, 10000000)
	var inv = st.get("inventory", [])
	if inv is Array:
		for g in inv:
			if not g is Dictionary or Data.item(str(g.get("id", ""))).is_empty():
				continue
			var extra := {}
			for k in ["base", "spell", "dtype"]:
				if str(g.get(k, "")) != "":
					extra[k] = str(g[k])
			if g.has("charges"):
				extra.charges = clampi(int(g.charges), 0, 50)
			if g.get("stored", null) is Array:
				extra.stored = g.stored.filter(func(s): return s is Dictionary and s.has("spell")).slice(0, 5)
			var qty := clampi(int(g.get("qty", 1)), 1, 9999) if Inventory.stackable(g) else 1
			Inventory.add(out, str(g.id), qty, extra)
			if out.inventory.size() >= 300:
				break
	if out.inventory.is_empty() and Inventory.coin_count(out.coins) == 0:
		return {}
	return out

static func _clean_loot(l: Dictionary) -> Dictionary:
	var out := {}
	for k in Inventory.COINS:
		if int(l.get(k, 0)) > 0 or k == "gp":
			out[k] = clampi(int(l.get(k, 0)), 0, 1000000)
	for pid in POTIONS:
		if int(l.get(pid, 0)) > 0:
			out[pid] = clampi(int(l[pid]), 0, 20)
	var items: Array = []
	for w in l.get("items", []):
		if not Data.item(str(w)).is_empty():
			items.append(str(w))
	if not items.is_empty():
		out.items = items.slice(0, 6)
	var gear: Array = []
	for g in l.get("gear", []):
		if g is Dictionary and not Data.item(str(g.get("id", ""))).is_empty():
			var e := {"id": str(g.id), "qty": clampi(int(g.get("qty", 1)), 1, 100)}
			for k in ["base", "spell", "dtype"]:
				if str(g.get(k, "")) != "":
					e[k] = str(g[k])
			if g.has("charges"):
				e.charges = clampi(int(g.charges), 0, 50)
			gear.append(e)
	if not gear.is_empty():
		out.gear = gear.slice(0, 12)
	return out

# ================================================================ generation

## Scatter interactables over a freshly generated map (MapGenerator instance `g`; `density` 0..1).
## Turns some of the generator's crates and barrels into breakable ones, lays chests (locked now and then) with
## loot, loose objects to pick up, and weak walls where a wall is one cell thick between two open spaces.
## `loot`: how much treasure (a LOOT key). Chests come from it alone, so a map can hold treasure without clutter
## (Objects at 0) or clutter without treasure (loot "none").
## Returns objects in map-file form ({"k", "x", "y", ...}).
static func scatter(g, density: float, level: int, layout: String, loot := "normal") -> Array:
	var out: Array = []
	var lv := loot_level(loot)
	var clutter := density > 0.01
	if not clutter and float(lv.chests) <= 0.0:
		return out
	var rng: RandomNumberGenerator = g.rng
	var taken := {}
	# Walking distance from the party's start (a generated map has it; endless-map chunks don't). Treasure is
	# kept out of easy reach of the start: the reward comes after the challenge.
	var dist: PackedInt32Array = g.dist if g.dist.size() == g.w * g.h else PackedInt32Array()
	var maxd := 0
	for d in dist:
		maxd = maxi(maxd, d)
	var near_start := maxi(6, int(maxd * 0.3))
	var by_start := func(q: Vector2i) -> bool:
		return not dist.is_empty() and dist[q.y * g.w + q.x] < near_start
	# Crates and barrels the structure builder already put down (on furniture or wall cells).
	var keep_props: Array = []
	for p in g.props:
		var k := str(p.get("k", ""))
		var pos := Vector2i(int(p.x), int(p.y))
		if clutter and k in ["crate", "barrel"] and int(p.get("w", 1)) == 1 and int(p.get("h", 1)) == 1 and not taken.has(pos) and rng.randf() < 0.35 + density * 0.6:
			var o := {"k": k, "x": pos.x, "y": pos.y, "under": FLOOR}
			# (The roll is made either way, so the rest of the map doesn't change with where the party starts.)
			if rng.randf() < float(lv.crate) and not by_start.call(pos):
				o.loot = roll_loot(rng, level, false)
			# It keeps the terrain it already had (furniture is difficult terrain), so no room gets sealed off.
			if g._at(pos) != WALL:
				o.cell = g._at(pos)
			out.append(o)
			taken[pos] = true
			continue
		if clutter and k == "chair" and int(p.get("w", 1)) == 1 and int(p.get("h", 1)) == 1 and not taken.has(pos) and rng.randf() < density * 0.5:
			out.append({"k": "chair", "x": pos.x, "y": pos.y})
			taken[pos] = true
			continue
		keep_props.append(p)
	g.props = keep_props
	var covered := {}
	for p in g.props:
		for dx in int(p.get("w", 1)):
			for dy in int(p.get("h", 1)):
				covered[Vector2i(int(p.x) + dx, int(p.y) + dy)] = true
	var free_floor := func(q: Vector2i) -> bool:
		return g._in(q) and g._at(q) == FLOOR and not covered.has(q) and not taken.has(q) and not g.keep_clear.has(q)
	# Chests: tucked against a wall, mostly, and guarded: beside or behind the monsters, or (with no monsters)
	# toward the far side of the map. How many is the loot setting's call (Normal: one per 500 squares or so,
	# plus one in a dungeon, building or town).
	var chests := int(round((g.w * g.h * 0.002 + (1.0 if layout in ["rooms", "interior", "town"] else 0.0)) * float(lv.chests)))
	var spots: Array = _chest_spots(g, dist, maxd, near_start, free_floor) if chests > 0 else []
	var placed: Array = []
	for i in chests:
		var q: Vector2i = _pick_chest_spot(rng, spots, placed, taken)
		if q.x < 0:
			# Endless-map chunks (no party start, no monsters), or no room away from the start: against a wall.
			for tries in 60:
				var r := Vector2i(rng.randi_range(1, g.w - 2), rng.randi_range(1, g.h - 2))
				if free_floor.call(r) and (not by_start.call(r) or tries >= 50) and (g._near(r, WALL, 1) or tries >= 40):
					q = r
					break
		if q.x < 0:
			continue
		var o := {"k": "chest", "x": q.x, "y": q.y, "under": FLOOR, "loot": roll_loot(rng, level, true)}
		# Rich and Hoard maps: a second helping of treasure (sometimes / always).
		for extra in int(lv.extra) + (1 if rng.randf() < fmod(float(lv.extra), 1.0) else 0):
			merge_loot(o.loot, roll_loot(rng, level, true))
		if rng.randf() < 0.4:
			o.locked = true
			o.dc = [10, 12, 15, 15, 18][rng.randi() % 5]
		g._put(q, DIFFICULT)
		out.append(o)
		placed.append(q)
		taken[q] = true
	# Loose things to pick up, by setting.
	var loose: Array = ["rock", "rock", "branch"]
	match layout:
		"rooms", "cave": loose = ["rock", "rock", "torch", "table_leg"]
		"interior": loose = ["bottle", "bottle", "chair", "table_leg"]
		"town": loose = ["bottle", "pitchfork", "rock", "table_leg"]
	var n_loose := int(round(g.w * g.h * density * 0.012))
	for i in n_loose:
		var q := Vector2i(rng.randi_range(0, g.w - 1), rng.randi_range(0, g.h - 1))
		if free_floor.call(q) or (g._in(q) and g._at(q) == DIFFICULT and not covered.has(q) and not taken.has(q)):
			out.append({"k": loose[rng.randi() % loose.size()], "x": q.x, "y": q.y})
			taken[q] = true
	# Weak walls: a one-cell-thick wall with open ground on both sides, so breaking it opens a shortcut.
	if clutter and layout in ["rooms", "interior", "town", "cave"]:
		var cands: Array = []
		for y in range(1, g.h - 1):
			for x in range(1, g.w - 1):
				var q := Vector2i(x, y)
				if g._at(q) != WALL or covered.has(q) or taken.has(q):
					continue
				var ew: bool = g._passable(q + Vector2i(1, 0)) and g._passable(q + Vector2i(-1, 0)) and not g._passable(q + Vector2i(0, 1)) and not g._passable(q + Vector2i(0, -1))
				var ns: bool = g._passable(q + Vector2i(0, 1)) and g._passable(q + Vector2i(0, -1)) and not g._passable(q + Vector2i(1, 0)) and not g._passable(q + Vector2i(-1, 0))
				if ew or ns:
					cands.append(q)
		StructureBuilder.shuffle(cands, rng)
		var want := int(round(cands.size() * density * 0.12)) + (1 if not cands.is_empty() else 0)
		for q in cands.slice(0, want):
			var stone: bool = layout in ["rooms", "cave"] or g.gat(q) in [MapGenerator.G_COBBLE, MapGenerator.G_FLAG]
			out.append({"k": "cracked_wall" if stone else "weak_wall", "x": q.x, "y": q.y, "under": FLOOR})
			taken[q] = true
	return out

## Where a chest could go on a generated map, each as [score, cell] (lower is better): out of easy reach of the
## party's start; a few squares from a monster and in the same part of the map, beside or behind it rather than
## between it and the party; with no monsters, toward the far side. Against a wall is better. Empty without
## walking distances (endless-map chunks).
static func _chest_spots(g, dist: PackedInt32Array, maxd: int, near_start: int, free_floor: Callable) -> Array:
	var out: Array = []
	if dist.is_empty():
		return out
	var foes: Array = []
	var foe_at := {}
	for f in g.foes:
		if g._in(f):
			foes.append(f)
			foe_at[f] = true
	for y in range(1, g.h - 1):
		for x in range(1, g.w - 1):
			var q := Vector2i(x, y)
			var d: int = dist[y * g.w + x]
			if d < near_start or foe_at.has(q) or not free_floor.call(q):
				continue
			var sc := 0.0 if g._near(q, WALL, 1) else 2.0
			if foes.is_empty():
				sc += absf(float(d) / maxf(1.0, float(maxd)) - 0.85) * 12.0
			else:
				var best := INF
				for f in foes:
					var fd := maxi(absi(f.x - q.x), absi(f.y - q.y))
					var fw: int = dist[f.y * g.w + f.x]
					# Two or three squares off is ideal; nearer the party than the monster is worse; a big gap in
					# walking distance means a wall between them (the monster isn't really guarding it).
					var s2 := absf(fd - 2.5) * 0.8 + (3.0 if d < fw - 1 else 0.0) + maxf(0.0, absf(d - fw) - fd - 1.0) * 0.6
					best = minf(best, s2)
				sc += best
			out.append([sc, q])
	return out

## The best free spot from _chest_spots, with a little randomness, kept apart from the chests already laid.
static func _pick_chest_spot(rng: RandomNumberGenerator, spots: Array, placed: Array, taken: Dictionary) -> Vector2i:
	var best := Vector2i(-1, -1)
	var bs := INF
	for e in spots:
		var q: Vector2i = e[1]
		if taken.has(q):
			continue
		var sc: float = float(e[0]) + rng.randf() * 1.5
		for p in placed:
			if maxi(absi(p.x - q.x), absi(p.y - q.y)) < 6:
				sc += 4.0
		if sc < bs:
			bs = sc
			best = q
	return best
