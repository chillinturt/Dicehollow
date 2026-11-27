class_name CombatantFactory
extends RefCounted
## Builds runtime combatant dictionaries. Combatants are plain Dictionaries so the whole
## battle state can be sent over the network as-is.

const SIZE_CELLS := {"tiny": 1, "small": 1, "medium": 1, "large": 2, "huge": 3, "gargantuan": 4}

static func _base(id: String, name: String) -> Dictionary:
	return {
		"id": id, "name": name, "kind": "pc", "team": "party", "owner": 1, "char_id": "", "monster_id": "",
		"portrait": "", "color": "#7a5cff", "sz": 1, "size": "medium", "senses": "", "pos": Vector2i.ZERO,
		"max_hp": 10, "hp": 10, "temp_hp": 0, "ac": 10, "speed": 30, "fly": 0,
		"scores": {}, "mods": {}, "prof": 2, "save_bonus": {}, "level": 1, "cr": 0.0, "cl": 1,
		"resist": [], "immune": [], "vulnerable": [], "cond_immune": [],
		"features": {}, "tags": {}, "vals": {}, "choices": {}, "styles": [], "maneuvers": [], "metamagic": [], "invocations": [],
		"attacks": [], "mactions": [], "bonus_actions": [], "casting": [],
		"slots_max": [], "slots_used": [], "pact_max": 0, "pact_level": 0, "pact_used": 0,
		"resources": {}, "effects": [], "conc": {}, "init": 0, "init_bonus": 0, "init_adv": false,
		"turn": {}, "toggles": {}, "death": {"s": 0, "f": 0, "stable": false, "dead": false},
		"recharge": {}, "acted": false, "form": {}, "ai": false, "summoner": "", "dead": false,
		"type": "humanoid", "skills": {}, "passive": 10, "summary": "", "hidden": false, "ward": 0, "class_levels": {},
	}

static func from_character(id: String, ch: Dictionary, owner: int) -> Dictionary:
	var st = Rules.derive(ch)
	var c = _base(id, ch.get("name", "Hero"))
	c.kind = "pc"
	c.owner = owner
	c.char_id = ch.get("id", "")
	c.portrait = ch.get("portrait", "")
	c.color = ch.get("color", "#7a5cff")
	c.sz = 1
	c.size = str(Data.race(ch.get("race", "")).get("size", "medium"))
	c.max_hp = st.max_hp
	c.hp = st.max_hp
	c.ac = st.ac
	c.speed = st.speed
	c.scores = st.scores
	c.mods = st.mods
	c.prof = st.prof
	c.save_bonus = st.save_bonus
	c.level = st.level
	c.cl = st.level
	c.resist = st.resist
	c.immune = st.immune
	c.cond_immune = st.condition_immune
	c.features = st.features
	c.tags = st.tags
	c.vals = st.vals
	c.choices = st.choices
	c.styles = st.fighting_styles
	c.maneuvers = st.maneuvers
	c.metamagic = st.metamagic
	c.invocations = st.invocations
	c.attacks = st.weapons
	c.casting = st.casting
	c.slots_max = st.slots
	c.slots_used = []
	for i in st.slots.size():
		c.slots_used.append(0)
	c.pact_max = st.pact.count
	c.pact_level = st.pact.level
	c.init_bonus = st.initiative
	c.init_adv = st.init_advantage
	c.skills = st.skills
	c.passive = st.passive_perception
	if int(st.get("darkvision", 0)) > 0:
		c.senses = "darkvision %d ft" % int(st.darkvision)  # how far they see in the dark (fog of war)
	c.summary = "%s %s" % [_race_name(ch), Rules.class_summary(ch)]
	c.heavy_armor = st.heavy_armor
	c.armored = st.armored
	c.has_shield = st.shield
	c.armor_unproficient = st.armor_unproficient
	c.class_levels = st.class_levels
	c.subclasses = st.subclasses
	c.feats = st.feats
	# Hit dice by die size ("10": count), spent on short rests and half regained on a long rest.
	var hd: Dictionary = {}
	for die in st.hit_dice_pool:
		hd[str(die)] = int(st.hit_dice_pool[die])
	c.hd_max = hd
	c.hd_used = {}
	var res = {}
	for k in st.resources:
		var r: Dictionary = st.resources[k]
		res[k] = {"name": r.name, "max": r.max, "cur": r.max, "reset": r.reset}
	c.resources = res
	# Dragonborn breath weapon.
	var sr = Data.subrace(ch.get("race", ""), ch.get("subrace", ""))
	if sr.has("breath"):
		c.breath = sr.breath
	return c

static func _race_name(ch: Dictionary) -> String:
	var sr = Data.subrace(ch.get("race", ""), ch.get("subrace", ""))
	if not sr.is_empty():
		return sr.name
	return Data.race(ch.get("race", "")).get("name", "")

static func from_monster(id: String, mid: String) -> Dictionary:
	var m = Data.monster(mid)
	var c = _base(id, m.get("name", mid))
	c.kind = "monster"
	c.team = "enemy"
	c.monster_id = mid
	c.color = m.get("token_color", "#a33")
	c.icon = str(m.get("icon", ""))
	c.sz = SIZE_CELLS.get(m.get("size", "medium"), 1)
	c.size = str(m.get("size", "medium"))
	c.senses = str(m.get("senses", ""))
	c.max_hp = int(m.get("hp", 10))
	c.hp = c.max_hp
	c.ac = int(m.get("ac", 10))
	c.speed = int(m.get("speed", 30))
	c.fly = int(m.get("fly", 0))
	var scores: Dictionary = m.get("scores", {})
	c.scores = scores
	var mods = {}
	for a in Data.ABILITIES:
		mods[a] = Rules.mod(int(scores.get(a, 10)))
	c.mods = mods
	c.prof = int(m.get("prof", 2))
	var sb = {}
	for a in Data.ABILITIES:
		sb[a] = int(m.get("saves", {}).get(a, mods[a]))
	c.save_bonus = sb
	c.cr = float(m.get("cr", 0))
	c.level = maxi(1, int(c.cr))
	c.type = m.get("type", "beast")
	c.resist = m.get("resist", [])
	c.immune = m.get("immune", [])
	c.vulnerable = m.get("vulnerable", [])
	c.cond_immune = m.get("condition_immune", [])
	c.init_bonus = mods.dex
	c.passive = 10 + int(m.get("skills", {}).get("perception", mods.wis))
	c.summary = "%s %s, CR %s" % [str(m.get("size", "")).capitalize(), m.get("type", ""), Data.cr_text(c.cr)]
	var tags = {}
	var mundane = false
	for t in m.get("traits", []):
		if t.has("tag"):
			tags[t.tag] = t.get("value", true)
		if "Mundane" in str(t.get("name", "")) or "nonmagical" in str(t.get("desc", "")).to_lower():
			mundane = true
	c.tags = tags
	c.mundane_resist = mundane
	if tags.has("legendary_resistance"):
		c.legendary_res = int(tags.legendary_resistance) if tags.legendary_resistance is int else 3
	# Monster actions -> attack profiles + special actions.
	var attacks: Array = []
	var mact: Array = []
	var idx = 0
	for a in m.get("actions", []):
		var kind: String = a.get("kind", "special")
		var aid = "m%d" % idx
		idx += 1
		if kind == "melee" or kind == "ranged":
			attacks.append({
				"id": aid, "name": a.name, "melee": kind == "melee", "to_hit": int(a.get("to_hit", 0)),
				"damage": a.get("damage", []), "reach": int(a.get("reach", 5)), "range": int(a.get("range", 0)),
				"long_range": int(a.get("long_range", 0)), "on_hit": a.get("on_hit", {}), "magic": c.cr >= 4,
				"props": [], "monster": true, "recharge": int(a.get("recharge", 0)), "desc": a.get("desc", ""),
			})
		else:
			var d: Dictionary = a.duplicate(true)
			d.id = aid
			mact.append(d)
		if int(a.get("recharge", 0)) > 0:
			c.recharge[a.name] = true
	c.attacks = attacks
	c.mactions = mact
	var bonus: Array = []
	for a in m.get("bonus_actions", []):
		var d: Dictionary = a.duplicate(true)
		d.id = "mb%d" % idx
		idx += 1
		bonus.append(d)
	c.bonus_actions = bonus
	c.reactions_desc = m.get("reactions", [])
	c.traits = m.get("traits", [])
	var sc: Dictionary = m.get("spellcasting", {})
	if not sc.is_empty():
		var ab: String = sc.get("ability", "int")
		var slots: Array = sc.get("slots", [])
		c.slots_max = slots
		c.slots_used = []
		for i in slots.size():
			c.slots_used.append(0)
		c.cl = maxi(1, slots.size() * 2 - 1)
		var once: Array = sc.get("spells", []) if slots.is_empty() else []
		c.casting = [{
			"class": "monster", "name": "Spellcasting", "ability": ab, "mod": mods.get(ab, 0),
			"dc": int(sc.get("dc", 10)), "attack": int(sc.get("attack", 2)),
			"spells": sc.get("spells", []), "at_will": sc.get("at_will", []), "once": once,
			"bonus_spells": [], "pact": false, "max_level": slots.size(),
		}]
		if not once.is_empty():
			for s in once:
				c.resources["innate_" + s] = {"name": Data.spell(s).get("name", s) + " (1/day)", "max": 1, "cur": 1, "reset": "long"}
	return c

## Beast form for Wild Shape: overlays physical stats onto the druid.
static func wild_shape_form(mid: String) -> Dictionary:
	var m = Data.monster(mid)
	var probe = from_monster("tmp", mid)
	return {"monster_id": mid, "name": m.get("name", mid), "hp": probe.max_hp, "max_hp": probe.max_hp, "ac": probe.ac,
		"speed": probe.speed, "scores": probe.scores, "attacks": probe.attacks, "mactions": probe.mactions.filter(func(a): return a.get("kind", "") == "multiattack"),
		"tags": probe.tags, "sz": probe.sz, "size": probe.size, "senses": probe.senses}

static func steel_defender(id: String, owner_c: Dictionary) -> Dictionary:
	var c = _base(id, "Steel Defender")
	var lv: int = owner_c.get("class_levels", {}).get("artificer", 3)
	var intm: int = owner_c.mods.get("int", 0)
	var pb: int = owner_c.prof
	_summon_common(c, owner_c)
	c.max_hp = 2 + intm + 5 * lv
	c.hp = c.max_hp
	c.ac = 15
	c.speed = 40
	c.scores = {"str": 14, "dex": 12, "con": 14, "int": 4, "wis": 10, "cha": 6}
	c.mods = {"str": 2, "dex": 1, "con": 2, "int": -3, "wis": 0, "cha": -2}
	c.save_bonus = {"str": 2, "dex": 1 + pb, "con": 2 + pb, "int": -3, "wis": 0, "cha": -2}
	c.immune = ["poison"]
	c.cond_immune = ["charmed", "poisoned"]
	c.color = "#8a8f99"
	c.type = "construct"
	var atk_bonus = intm + pb
	c.attacks = [{"id": "rend", "name": "Force-Empowered Rend", "melee": true, "to_hit": atk_bonus,
		"damage": [{"dice": "1d8+%d" % pb, "type": "force"}], "reach": 5, "range": 0, "long_range": 0, "magic": true, "props": [], "monster": true}]
	c.summary = "Construct companion of %s" % owner_c.name
	return c

static func eldritch_cannon(id: String, owner_c: Dictionary, kind: String) -> Dictionary:
	var names = {"flamethrower": "Cannon: Flamethrower", "force_ballista": "Cannon: Force Ballista", "protector": "Cannon: Protector"}
	var c = _base(id, names.get(kind, "Eldritch Cannon"))
	_summon_common(c, owner_c)
	var lv: int = owner_c.get("class_levels", {}).get("artificer", 3)
	var intm: int = owner_c.mods.get("int", 0)
	var dc = 8 + int(owner_c.prof) + intm
	var atk = int(owner_c.prof) + intm
	c.max_hp = 5 * lv
	c.hp = c.max_hp
	c.ac = 18
	c.speed = 15
	c.size = "small"
	c.scores = {"str": 10, "dex": 10, "con": 10, "int": 10, "wis": 10, "cha": 10}
	c.mods = {"str": 0, "dex": 0, "con": 0, "int": 0, "wis": 0, "cha": 0}
	c.save_bonus = c.mods.duplicate()
	c.immune = ["poison", "psychic"]
	c.color = "#c08a3e"
	c.type = "object"
	c.cannon = kind
	var dice = "3d8" if owner_c.get("features", {}).has("explosive_cannon") else "2d8"
	match kind:
		"flamethrower":
			c.mactions = [{"id": "flame", "name": "Flamethrower", "kind": "save", "save": "dex", "dc": dc,
				"area": {"shape": "cone", "size": 15}, "damage": [{"dice": dice, "type": "fire"}], "half_on_save": true}]
		"force_ballista":
			c.attacks = [{"id": "ballista", "name": "Force Ballista", "melee": false, "to_hit": atk,
				"damage": [{"dice": dice, "type": "force"}], "reach": 5, "range": 120, "long_range": 0, "magic": true, "props": [], "monster": true, "push": 5}]
		_:
			c.mactions = [{"id": "protect", "name": "Protector", "kind": "protector", "temp_hp": "1d8+%d" % maxi(1, intm), "radius": 10}]
	c.summary = "Eldritch cannon of %s" % owner_c.name
	return c

## Animate Objects (PHB) statistics by size. "units" is how many of the spell's ten objects one counts as.
const ANIMATED_OBJECTS := {
	"tiny":   {"units": 1, "hp": 20, "ac": 18, "to_hit": 8, "dice": "1d4+4",  "str": 4,  "dex": 18, "fly": true},
	"small":  {"units": 1, "hp": 25, "ac": 16, "to_hit": 6, "dice": "1d8+2",  "str": 6,  "dex": 14, "fly": true},
	"medium": {"units": 2, "hp": 40, "ac": 13, "to_hit": 5, "dice": "2d6+1",  "str": 10, "dex": 12, "fly": false},
	"large":  {"units": 4, "hp": 50, "ac": 10, "to_hit": 6, "dice": "2d10+2", "str": 14, "dex": 10, "fly": false},
	"huge":   {"units": 8, "hp": 80, "ac": 10, "to_hit": 8, "dice": "2d12+4", "str": 18, "dex": 6,  "fly": false},
}

## One object brought to life by Animate Objects. Tiny and Small objects are taken to be legless
## (coins, daggers, books) and hover with a 30 ft flying speed; bigger ones walk.
static func animated_object(id: String, owner_c: Dictionary, size: String, n: int) -> Dictionary:
	if not ANIMATED_OBJECTS.has(size):
		size = "tiny"
	var st: Dictionary = ANIMATED_OBJECTS[size]
	var c = _base(id, "Animated %s Object %d" % [size.capitalize(), n])
	_summon_common(c, owner_c)
	c.size = size
	c.sz = SIZE_CELLS.get(size, 1)
	c.max_hp = int(st.hp)
	c.hp = c.max_hp
	c.ac = int(st.ac)
	c.speed = 30
	c.fly = 30 if st.fly else 0
	c.scores = {"str": int(st.str), "dex": int(st.dex), "con": 10, "int": 3, "wis": 3, "cha": 1}
	var mods = {}
	for a in c.scores:
		mods[a] = Rules.mod(int(c.scores[a]))
	c.mods = mods
	c.save_bonus = mods.duplicate()
	c.init_bonus = mods.dex
	c.passive = 10 + int(mods.wis)
	c.senses = "blindsight 30 ft (blind beyond)"
	c.color = "#b08850"
	c.type = "construct"
	c.animated = size
	c.attacks = [{"id": "slam", "name": "Slam", "melee": true, "to_hit": int(st.to_hit),
		"damage": [{"dice": st.dice, "type": "bludgeoning"}], "reach": 5, "range": 0, "long_range": 0, "magic": false, "props": [], "monster": true}]
	c.summary = "%s object animated by %s" % [size.capitalize(), owner_c.name]
	return c

## One object brought to life by Tiny Servant (XGtE): a Tiny construct with AC 15, 10 HP, 30 ft walking
## and climbing speed, blindsight 60 ft and a +5 Slam for 1d4+3. It has hands enough to fetch and carry,
## so it can pick up, drop and throw magic stones like anyone else.
static func tiny_servant(id: String, owner_c: Dictionary, n: int) -> Dictionary:
	var c = _base(id, "Tiny Servant %d" % n)
	_summon_common(c, owner_c)
	c.size = "tiny"
	c.sz = 1
	c.max_hp = 10
	c.hp = 10
	c.ac = 15
	c.speed = 30
	c.climb = 30
	c.scores = {"str": 4, "dex": 16, "con": 10, "int": 2, "wis": 10, "cha": 1}
	var mods = {}
	for a in c.scores:
		mods[a] = Rules.mod(int(c.scores[a]))
	c.mods = mods
	c.save_bonus = mods.duplicate()
	c.init_bonus = mods.dex
	c.passive = 10
	c.senses = "blindsight 60 ft (blind beyond)"
	c.immune = ["poison", "psychic"]
	c.cond_immune = ["blinded", "charmed", "deafened", "exhaustion", "frightened", "paralyzed", "petrified", "poisoned"]
	c.color = "#c8a46a"
	c.type = "construct"
	c.servant = true
	c.attacks = [{"id": "slam", "name": "Slam", "melee": true, "to_hit": 5,
		"damage": [{"dice": "1d4+3", "type": "bludgeoning"}], "reach": 5, "range": 0, "long_range": 0, "magic": false, "props": [], "monster": true}]
	c.summary = "Tiny object animated by %s (Tiny Servant)" % owner_c.name
	return c

## Summon Beast (TCoE): a Small bestial spirit whose numbers come from the slot level. Air spirits
## fly 60 ft (Flyby); land and water spirits have Pack Tactics. Maul attacks equal to half the slot
## level, each using the caster's spell attack bonus for 1d8 + 4 + slot level piercing.
static func bestial_spirit(id: String, owner_c: Dictionary, kind: String, slot: int, spell_attack: int) -> Dictionary:
	if not kind in ["air", "land", "water"]:
		kind = "land"
	var c = _base(id, "Bestial Spirit (%s)" % kind.capitalize())
	_summon_common(c, owner_c)
	c.size = "small"
	c.sz = 1
	c.max_hp = (20 if kind == "air" else 30) + 5 * maxi(0, slot - 2)
	c.hp = c.max_hp
	c.ac = 11 + slot
	c.speed = 30
	c.fly = 60 if kind == "air" else 0
	if kind == "land":
		c.climb = 30
	c.scores = {"str": 18, "dex": 11, "con": 16, "int": 4, "wis": 14, "cha": 5}
	var mods = {}
	for a in c.scores:
		mods[a] = Rules.mod(int(c.scores[a]))
	c.mods = mods
	c.save_bonus = mods.duplicate()
	c.init_bonus = mods.dex
	c.passive = 10 + int(mods.wis)
	c.senses = "darkvision 60 ft"
	c.color = "#6a9a5a"
	c.type = "beast"
	if kind == "air":
		c.tags = {"flyby": true}
	else:
		c.tags = {"pack_tactics": true}
	c.vals = {"attacks": maxi(1, slot / 2)}
	c.attacks = [{"id": "maul", "name": "Maul", "melee": true, "to_hit": spell_attack,
		"damage": [{"dice": "1d8+%d" % (4 + slot), "type": "piercing"}], "reach": 5, "range": 0, "long_range": 0, "magic": true, "props": [], "monster": true}]
	c.summary = "Bestial spirit (%s) summoned by %s" % [kind, owner_c.name]
	return c

static func _summon_common(c: Dictionary, owner_c: Dictionary) -> void:
	c.kind = "summon"
	c.team = owner_c.team
	c.owner = owner_c.owner
	c.summoner = owner_c.id
	c.prof = owner_c.prof
	c.level = owner_c.level
	c.ai = owner_c.get("ai", false)
	c.pos = owner_c.pos
