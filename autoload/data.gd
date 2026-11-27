extends Node
## Loads all rules data from res://data and exposes lookup tables.

const ABILITIES := ["str", "dex", "con", "int", "wis", "cha"]
const ABILITY_NAMES := {"str": "Strength", "dex": "Dexterity", "con": "Constitution", "int": "Intelligence", "wis": "Wisdom", "cha": "Charisma"}
const SKILLS := {
	"acrobatics": "dex", "animal_handling": "wis", "arcana": "int", "athletics": "str", "deception": "cha",
	"history": "int", "insight": "wis", "intimidation": "cha", "investigation": "int", "medicine": "wis",
	"nature": "int", "perception": "wis", "performance": "cha", "persuasion": "cha", "religion": "int",
	"sleight_of_hand": "dex", "stealth": "dex", "survival": "wis",
}
const DAMAGE_TYPES := ["acid", "bludgeoning", "cold", "fire", "force", "lightning", "necrotic", "piercing", "poison", "psychic", "radiant", "slashing", "thunder"]
const CONDITIONS := ["blinded", "charmed", "deafened", "frightened", "grappled", "incapacitated", "invisible", "paralyzed", "petrified", "poisoned", "prone", "restrained", "stunned", "unconscious"]
const BACKGROUNDS := {
	"acolyte": ["insight", "religion"], "charlatan": ["deception", "sleight_of_hand"], "criminal": ["deception", "stealth"],
	"entertainer": ["acrobatics", "performance"], "folk_hero": ["animal_handling", "survival"], "guild_artisan": ["insight", "persuasion"],
	"hermit": ["medicine", "religion"], "noble": ["history", "persuasion"], "outlander": ["athletics", "survival"],
	"sage": ["arcana", "history"], "sailor": ["athletics", "perception"], "soldier": ["athletics", "intimidation"],
	"urchin": ["sleight_of_hand", "stealth"], "haunted_one": ["arcana", "investigation"], "far_traveler": ["insight", "perception"],
	"city_watch": ["athletics", "insight"], "clan_crafter": ["history", "insight"], "cloistered_scholar": ["history", "religion"],
}
const POINT_BUY_COST := {8: 0, 9: 1, 10: 2, 11: 3, 12: 4, 13: 5, 14: 7, 15: 9}
const STANDARD_ARRAY := [15, 14, 13, 12, 10, 8]
## Full-caster spell slots by caster level (index = caster level).
const SLOT_TABLE := [[], [2], [3], [4, 2], [4, 3], [4, 3, 2], [4, 3, 3], [4, 3, 3, 1], [4, 3, 3, 2], [4, 3, 3, 3, 1],
	[4, 3, 3, 3, 2], [4, 3, 3, 3, 2, 1], [4, 3, 3, 3, 2, 1], [4, 3, 3, 3, 2, 1, 1], [4, 3, 3, 3, 2, 1, 1],
	[4, 3, 3, 3, 2, 1, 1, 1], [4, 3, 3, 3, 2, 1, 1, 1], [4, 3, 3, 3, 2, 1, 1, 1, 1], [4, 3, 3, 3, 3, 1, 1, 1, 1],
	[4, 3, 3, 3, 3, 2, 1, 1, 1], [4, 3, 3, 3, 3, 2, 2, 1, 1]]
const FIGHTING_STYLES := {
	"archery": "Archery: +2 to ranged weapon attack rolls.",
	"defense": "Defense: +1 AC while wearing armor.",
	"dueling": "Dueling: +2 damage with a one-handed melee weapon and no other weapon.",
	"great_weapon_fighting": "Great Weapon Fighting: reroll 1s and 2s on two-handed weapon damage.",
	"two_weapon_fighting": "Two-Weapon Fighting: add your modifier to off-hand damage.",
	"protection": "Protection: reaction to give disadvantage on an attack against an adjacent ally (needs a shield).",
	"interception": "Interception: reaction to reduce damage to an adjacent ally by 1d10 + PB.",
	"thrown_weapon_fighting": "Thrown Weapon Fighting: +2 damage with thrown weapons.",
	"blind_fighting": "Blind Fighting: blindsight 10 ft.",
}
const MANEUVERS := {
	"precision": "Precision Attack: add a superiority die to a missed attack roll (automatic).",
	"riposte": "Riposte: when a creature misses you in melee, counterattack (automatic).",
	"trip": "Trip Attack: add the die to damage; STR save or prone.",
	"menacing": "Menacing Attack: add the die to damage; WIS save or frightened.",
	"pushing": "Pushing Attack: add the die to damage; STR save or pushed 15 ft.",
	"goading": "Goading Attack: add the die to damage; WIS save or disadvantage against others.",
	"distracting": "Distracting Strike: add the die to damage; next ally attack has advantage.",
}
const METAMAGIC := {
	"quickened": "Quickened Spell (2 SP): cast an action spell as a bonus action.",
	"twinned": "Twinned Spell (SP = spell level): a single-target spell hits a second creature.",
	"empowered": "Empowered Spell (1 SP): reroll low damage dice.",
	"heightened": "Heightened Spell (3 SP): one target has disadvantage on its first save.",
	"careful": "Careful Spell (1 SP): allies automatically succeed on the spell's save.",
	"distant": "Distant Spell (1 SP): double the spell's range.",
}
const INVOCATIONS := {
	"agonizing_blast": "Agonizing Blast: add CHA to Eldritch Blast damage.",
	"repelling_blast": "Repelling Blast: Eldritch Blast pushes 10 ft.",
	"eldritch_spear": "Eldritch Spear: Eldritch Blast range 300 ft.",
	"devils_sight": "Devil's Sight: see in magical darkness.",
	"thirsting_blade": "Thirsting Blade: extra attack with your pact weapon (5th level).",
	"lifedrinker": "Lifedrinker: pact weapon deals +CHA necrotic (12th level).",
	"eldritch_mind": "Eldritch Mind: advantage on concentration saves.",
	"armor_of_shadows": "Armor of Shadows: Mage Armor at will.",
	"grasp_of_hadar": "Grasp of Hadar: Eldritch Blast pulls 10 ft.",
}
const INFUSIONS := {
	"enhanced_defense": "Enhanced Defense: +1 AC (+2 at 10th level).",
	"enhanced_weapon": "Enhanced Weapon: +1 to attack and damage (+2 at 10th).",
	"enhanced_arcane_focus": "Enhanced Arcane Focus: +1 to spell attacks (+2 at 10th).",
	"repeating_shot": "Repeating Shot: +1 ranged weapon, no loading.",
	"radiant_weapon": "Radiant Weapon: +1 weapon that sheds light.",
	"replicate_magic_item": "Replicate Magic Item: copy a common item (e.g. Bag of Holding).",
}

var races := {}
var classes := {}
var spells := {}
var monsters := {}
var items := {}
var features := {}
var feats := {}

func _ready() -> void:
	races = _index(_load_glob("races"))
	classes = _index(_load_glob("classes"))
	spells = _index(_load_glob("spells"))
	monsters = _index(_load_glob("monsters"))
	items = _index(_load_glob("items"))
	features = _index(_load_glob("features"))
	feats = _index(_load_glob("feats"))
	print("[Data] races=%d classes=%d spells=%d monsters=%d items=%d feats=%d" % [races.size(), classes.size(), spells.size(), monsters.size(), items.size(), feats.size()])

func _load_glob(prefix: String) -> Array:
	var out: Array = []
	var dir = DirAccess.open("res://data")
	if dir == null:
		push_error("Data: res://data missing")
		return out
	var files = Array(dir.get_files())
	files.sort()
	for f: String in files:
		# Exported builds may list "x.json.remap"-style names; only read real json files.
		if f.begins_with(prefix) and f.ends_with(".json"):
			var txt = FileAccess.get_file_as_string("res://data/" + f)
			var parsed = JSON.parse_string(txt)
			if parsed is Array:
				out.append_array(normalize(parsed))
			else:
				push_error("Data: failed to parse %s" % f)
	return out

func _index(arr: Array) -> Dictionary:
	var d = {}
	for e in arr:
		if e is Dictionary and e.has("id"):
			d[e.id] = e
	return d

## JSON numbers arrive as floats; convert whole floats to ints recursively.
static func normalize(v: Variant) -> Variant:
	if v is float:
		return int(v) if is_equal_approx(v, roundf(v)) and absf(v) < 1e12 else v
	if v is Array:
		var a: Array = []
		for e in v:
			a.append(normalize(e))
		return a
	if v is Dictionary:
		var d = {}
		for k in v:
			d[k] = normalize(v[k])
		return d
	return v

# ---------------------------------------------------------------- lookups

func race(id: String) -> Dictionary:
	return races.get(id, {})

func subrace(race_id: String, sub_id: String) -> Dictionary:
	for s in race(race_id).get("subraces", []):
		if s.id == sub_id:
			return s
	return {}

func cls(id: String) -> Dictionary:
	return classes.get(id, {})

func subclass(class_id: String, sub_id: String) -> Dictionary:
	for s in cls(class_id).get("subclasses", []):
		if s.id == sub_id:
			return s
	return {}

func spell(id: String) -> Dictionary:
	return spells.get(id, {})

func monster(id: String) -> Dictionary:
	return monsters.get(id, {})

func item(id: String) -> Dictionary:
	return items.get(id, {})

func feature(id: String) -> Dictionary:
	if features.has(id):
		return features[id]
	return {"id": id, "name": pretty(id), "desc": "See your rulebook for the details of this feature."}

func feat(id: String) -> Dictionary:
	return feats.get(id, {"id": id, "name": pretty(id), "desc": ""})

static func pretty(id: String) -> String:
	var words = id.split("_")
	var out: PackedStringArray = []
	for w in words:
		out.append(w.capitalize())
	return " ".join(out)

## Spells on a class list, optionally capped by level.
func spells_for_class(class_id: String, max_level := 9) -> Array:
	var out: Array = []
	for s in spells.values():
		if int(s.get("level", 0)) <= max_level and class_id in s.get("classes", []):
			out.append(s)
	out.sort_custom(func(a, b): return [int(a.level), a.name] < [int(b.level), b.name])
	return out

func weapons() -> Array:
	return items.values().filter(func(i): return i.kind == "weapon")

func armors() -> Array:
	return items.values().filter(func(i): return i.kind == "armor")

func monsters_sorted() -> Array:
	var arr = monsters.values()
	arr.sort_custom(func(a, b): return [float(a.get("cr", 0)), a.name] < [float(b.get("cr", 0)), b.name])
	return arr

static func cr_text(cr: Variant) -> String:
	var f = float(cr)
	if is_equal_approx(f, 0.125): return "1/8"
	if is_equal_approx(f, 0.25): return "1/4"
	if is_equal_approx(f, 0.5): return "1/2"
	return str(int(f))
