class_name NameGen
extends RefCounted
## Fantasy names for the map generator: people, towns, gods, shops and other places. Every function takes the
## generator's RandomNumberGenerator so a seed always gives the same names. Styles: "human", "dwarf", "elf".

const FIRST := {
	"human": ["Hilda", "Bram", "Marta", "Osric", "Tamsin", "Gareth", "Wenna", "Rolf", "Elsie", "Dunstan", "Mabel", "Corwin", "Agatha",
		"Fenwick", "Ysolde", "Jory", "Beatrix", "Alaric", "Greta", "Hollis", "Imelda", "Cedric", "Nell", "Tobias"],
	"dwarf": ["Durgan", "Bruna", "Kargrim", "Torva", "Orsik", "Helja", "Brottin", "Dagna", "Rurik", "Gunnhild", "Morgra", "Balder",
		"Haldra", "Vondal", "Eldeth", "Tordek", "Kathra", "Barend"],
	"elf": ["Aelar", "Thalia", "Ilyndra", "Sylvar", "Caelynn", "Erevan", "Naivara", "Faelar", "Sariel", "Ithrin", "Vaelis", "Lia",
		"Theren", "Mirelle", "Quillan", "Shava"],
	"halfling": ["Pip", "Rosie", "Milo", "Tansy", "Wendel", "Cora", "Perrin", "Lavinia", "Merric", "Seraphina"],
	"gnome": ["Fizzwick", "Nissa", "Bimble", "Orryn", "Tana", "Zook", "Ellyjobell", "Wrenn"],
	"half-orc": ["Grukka", "Thokk", "Mhurren", "Ovak", "Shautha", "Krusk", "Volen", "Baggi"],
}
const LAST := {
	"human": ["Ashdown", "Brightwater", "Coldwell", "Thatcher", "Miller", "Hawthorne", "Greaves", "Underhill", "Blackwood", "Fairweather",
		"Penhallow", "Cobb", "Marsh", "Whitlock"],
	"dwarf": ["Ironfist", "Stonebeard", "Deepdelver", "Coppervein", "Ambershard", "Hammerfall", "Gravelgut", "Flintheart", "Battlehammer", "Goldbrow"],
	"elf": ["Moonwhisper", "Silverfrond", "Nightbreeze", "Liadon", "Galanodel", "Starbloom", "Amakiir", "Dawnpetal", "Holimion"],
	"halfling": ["Goodbarrel", "Tealeaf", "Thorngage", "Brushgather", "Highhill", "Underbough"],
	"gnome": ["Nackle", "Gearspring", "Beren", "Turen", "Fiddlewick", "Sparkpot"],
	"half-orc": ["the Quiet", "Two-Tusks", "Bonebreaker", "the Kind", "Ironhide", "the Patient"],
}
## Who runs things in each kind of town (race: weight).
const RACE_MIX := {
	"human": {"human": 55, "halfling": 15, "dwarf": 10, "half-orc": 8, "gnome": 7, "elf": 5},
	"dwarf": {"dwarf": 75, "gnome": 10, "human": 10, "halfling": 5},
	"elf": {"elf": 70, "human": 10, "halfling": 10, "gnome": 10},
}
const RACE_NAMES := {"human": "human", "dwarf": "dwarf", "elf": "elf", "halfling": "halfling", "gnome": "gnome", "half-orc": "half-orc"}

const TOWN_A := {
	"human": ["Oak", "Mill", "Ash", "Raven", "Stone", "Briar", "Wolf", "Thorn", "Elder", "Fox", "Kings", "Black", "Green", "Red", "Salt",
		"Bramble", "Cold", "High", "Marsh", "Copper", "Willow", "Hart", "Bell", "Amber"],
	"dwarf": ["Khaz", "Dun", "Bar", "Grim", "Kar", "Thol", "Mor", "Zul", "Brun", "Dur", "Gol", "Hron"],
	"elf": ["Syl", "Ael", "Lor", "Ith", "Cael", "Ely", "Fae", "Thal", "Myr", "Nim", "Vey", "Esh"],
}
const TOWN_B := {
	"human": ["brook", "ford", "wick", "ton", "haven", "bury", "field", "hollow", "stead", "vale", "cross", "moor", "well", "dale", "bridge", "gate"],
	"dwarf": ["dorn", "garad", "heim", "zan", "drak", "gol", "um", "mar", "grund", "bek", "torr", "kar"],
	"elf": ["wyn", "dell", "vael", "lune", "thas", "wen", "maris", "ora", "rien", "assa", "iel", "ethra"],
}
const TOWN_PATTERN := {"dwarf": ["%s", "%s", "Hold of %s", "%s Deep"], "elf": ["%s", "%s", "%s Glade", "%s Grove"], "human": ["%s", "%s", "%s", "%s Crossing"]}

const DEITIES := {
	"human": ["the Dawnfather", "the Lady of Coins", "the Harvest Mother", "the Stormlord", "the Silent Watcher", "the Lantern Saint", "the Pale Shepherd"],
	"dwarf": ["the Forge Father", "the Stonemother", "the Deep Warden", "the Keeper of Oaths", "the Lord of the Hearth"],
	"elf": ["the Moon Weaver", "the Green Lady", "the Starsinger", "the Twilight Hunter", "the Dreaming Tree"],
}

static func pick(rng: RandomNumberGenerator, a: Array):
	return a[rng.randi() % a.size()] if not a.is_empty() else ""

static func race_for(rng: RandomNumberGenerator, style: String) -> String:
	var mix: Dictionary = RACE_MIX.get(style, RACE_MIX.human)
	var total := 0
	for k in mix:
		total += int(mix[k])
	var roll := rng.randi_range(1, total)
	for k in mix:
		roll -= int(mix[k])
		if roll <= 0:
			return k
	return "human"

static func first_name(rng: RandomNumberGenerator, race: String) -> String:
	return pick(rng, FIRST.get(race, FIRST.human))

## {"name": "Bruna Coppervein", "first": "Bruna", "race": "dwarf"} for someone living in a `style` town.
static func person(rng: RandomNumberGenerator, style: String) -> Dictionary:
	var race := race_for(rng, style)
	var f := first_name(rng, race)
	return {"name": "%s %s" % [f, pick(rng, LAST.get(race, LAST.human))], "first": f, "race": race}

static func town_name(rng: RandomNumberGenerator, style: String) -> String:
	var st := style if TOWN_A.has(style) else "human"
	var base: String = pick(rng, TOWN_A[st]) + pick(rng, TOWN_B[st])
	return pick(rng, TOWN_PATTERN[st]) % base

static func deity(rng: RandomNumberGenerator, style: String) -> String:
	return pick(rng, DEITIES.get(style, DEITIES.human))

## A name for a building of `kind` (smithy, shop, apothecary, temple, guard, chapel, shrine, crypt, fort, tower).
static func place(rng: RandomNumberGenerator, kind: String, style: String) -> String:
	var owner := first_name(rng, race_for(rng, style))
	match kind:
		"smithy":
			if style == "dwarf" and rng.randf() < 0.5:
				return "The %s Anvil" % pick(rng, ["Ringing", "Red-Hot", "Iron", "Thundering", "Rune-Struck"])
			if rng.randf() < 0.7:
				return "%s's %s" % [owner, pick(rng, ["Forge", "Smithy"])]
			return "The %s Hammer" % pick(rng, ["Sparking", "Glowing", "Black", "Singing"])
		"shop":
			if rng.randf() < 0.5:
				return "%s's %s" % [owner, pick(rng, ["Goods", "Sundries", "Emporium", "Provisions", "Trading Post"])]
			return "The %s %s" % [pick(rng, ["Curious", "Copper", "Lucky", "Honest", "Dusty", "Golden", "Bottomless"]), pick(rng, ["Kettle", "Coin", "Lantern", "Satchel", "Scale", "Wagon", "Pack"])]
		"apothecary":
			if rng.randf() < 0.5:
				return "%s's Remedies" % owner
			return pick(rng, ["The Green Bottle", "The Bubbling Cauldron", "Mortar & Pestle", "The Healing Hand", "Herbs & Humours"])
		"temple":
			return "%s of %s" % [pick(rng, ["Temple", "Temple", "House", "Sanctum"]), deity(rng, style)]
		"chapel", "shrine":
			return "%s of %s" % [pick(rng, ["Shrine", "Chapel"]) if kind == "chapel" else "Shrine", deity(rng, style)]
		"guard":
			return {"dwarf": "Hold Guard", "elf": "Warden's Lodge"}.get(style, pick(rng, ["Watch House", "Guard Hall"]))
		"crypt":
			return "Crypt of the %s Family" % pick(rng, LAST.get(race_for(rng, style), LAST.human)).trim_prefix("the ").capitalize()
		"fort":
			return "Fort %s" % pick(rng, LAST.human)
		"tower":
			return pick(rng, ["Old Watchtower", "Watchtower", "%s's Tower" % owner, "The Lonely Tower"])
	return ""
