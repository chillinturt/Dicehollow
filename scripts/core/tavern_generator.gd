class_name TavernGenerator
extends RefCounted
## Taverns that each feel like their own place: a D&D-style name, a proprietor with a quirk, prices, a house
## drink and dish, entertainment, a rumour, and a layout of their own: bar, hearth, kitchen, stage, booths,
## stairs, guest rooms and one odd feature. Styles ("human", "dwarf", "elf") flavour all of it.

const ADJ := ["Rusty", "Gilded", "Drunken", "Sleeping", "Laughing", "Crooked", "Wandering", "Silver", "Hungry", "Jolly", "Salty",
	"Howling", "Winking", "Thirsty", "Broken", "Golden", "Merry", "Wicked", "Lucky", "Grinning", "Sly", "Bloody", "Burning", "Copper",
	"Velvet", "One-Eyed", "Tipsy", "Sunken", "Blind", "Dancing", "Snoring", "Leaky", "Brazen", "Weary", "Wayward", "Cackling",
	"Frothy", "Mossy", "Rowdy", "Painted", "Lost", "Singing", "Three-Legged", "Hairy", "Sober"]
const NOUN := ["Griffon", "Dragon", "Goblet", "Flagon", "Owlbear", "Mimic", "Tankard", "Stag", "Boar", "Kraken", "Wyvern", "Lantern",
	"Anvil", "Rose", "Hound", "Raven", "Goose", "Unicorn", "Troll", "Bard", "Wizard", "Knight", "Barrel", "Cauldron", "Lute", "Mermaid",
	"Basilisk", "Pixie", "Kobold", "Hydra", "Manticore", "Gnome", "Ogre", "Badger", "Rooster", "Toad", "Harpy", "Hippogriff",
	"Bugbear", "Cockatrice", "Satyr", "Imp", "Skull", "Crown", "Dagger", "Fiddle", "Pig", "Gelatinous Cube", "Rust Monster", "Halfling"]
const STYLE_ADJ := {
	"dwarf": ["Stout", "Iron", "Granite", "Deep", "Bearded", "Molten", "Mithral", "Hammered", "Smoky", "Rune-Carved", "Bottomless"],
	"elf": ["Moonlit", "Starlit", "Whispering", "Silvered", "Dreaming", "Evergreen", "Twilight", "Gossamer", "Dewy", "Wandering"],
}
const STYLE_NOUN := {
	"dwarf": ["Anvil", "Hammer", "Axe", "Keg", "Pickaxe", "Forge", "Delve", "Mug", "Ingot", "Gem", "Beard", "Bellows"],
	"elf": ["Bough", "Leaf", "Glade", "Harp", "Willow", "Nightingale", "Fawn", "Acorn", "Lily", "Moth", "Star", "Lantern"],
}
const PLACE_WORDS := {
	"human": ["Rest", "Respite", "Taproom", "Alehouse", "Hearth", "Haven", "Tavern", "Inn", "Lodge", "Watering Hole", "Snug"],
	"dwarf": ["Alehall", "Brewhall", "Mead Hall", "Taphouse", "Hearth", "Cellar"],
	"elf": ["Bower", "Repose", "Arbor", "Rest", "Haven", "Retreat"],
}
const OWNER_NOUNS := ["Wizard", "Giant", "Dragon", "Bard", "Goblin", "Paladin", "Hag", "Ogre", "Gnome", "Rogue", "King", "Witch", "Lich", "Druid"]
const ODD_THINGS := ["Sock", "Toenail", "Hat", "Folly", "Lament", "Tankard", "Beard", "Spoon", "Secret", "Last Coin", "Bad Idea", "Boot",
	"Pipe", "Regret", "Wager", "Hiccup"]
const SPECIALS := {
	"human": ["The Last Copper", "The Crossroads", "Nine Candles", "The Copper Kettle", "The Broken Wheel", "The Hanged Man", "Halfway House"],
	"dwarf": ["The Deep Delve", "The Thirsty Pick", "The Foaming Keg", "Hall of the Seven Kegs", "The Bottomless Mug", "The Anvil and Ale"],
	"elf": ["Hall of Seven Leaves", "The Last Starlight", "Under the Silver Bough", "The Moon's Cup", "Willowshade House", "The Quiet Glade"],
}

const QUIRKS := ["never stops polishing the same mug", "remembers every patron's name, and every patron's debt",
	"is a retired adventurer with a peg leg and too many stories", "waters down the ale and hotly denies it",
	"is, quietly, a retired assassin", "talks to a pet raven perched on the bar", "hums constantly and badly",
	"keeps a loaded crossbow under the bar and has used it", "will bet on anything", "is terrified of magic and bans spellcasting indoors",
	"collects strange trinkets as payment", "sells secrets to whoever pays best", "has three children forever running underfoot",
	"speaks only in rhyme after the second drink", "is a terrible cook and a wonderful brewer", "insists the place is haunted (it is)"]
const QUALITIES := [  # [name, weight, prices]
	["Squalid", 5, "room 7 cp a night, ale 2 cp"], ["Poor", 15, "room 1 sp a night, ale 3 cp"], ["Modest", 40, "room 5 sp a night, ale 4 cp"],
	["Comfortable", 30, "room 8 sp a night, ale 4 cp, wine 2 sp"], ["Wealthy", 10, "room 2 gp a night, ale 6 cp, fine wine 10 gp a bottle"]]
const DRINK_A := ["Dragon's Breath", "Owlbear's Hug", "Goblin Spit", "Mermaid's Kiss", "Old Stumpy", "Grave Digger", "Wizard's Ruin",
	"Black Mire", "Frostbite", "Liquid Courage", "Troll Sweat", "Honeyed Hellfire", "Bogwater", "Widowmaker", "Second Wind", "Kobold Kicker"]
const DRINK_A_STYLE := {"dwarf": ["Deepdelve", "Mithral", "Forgefire", "Stonebrew", "Old Beardsplitter"], "elf": ["Moonpetal", "Starlight", "Dewberry", "Silverleaf", "Dreamwater"]}
const DRINK_B := ["Stout", "Ale", "Mead", "Cider", "Brandy", "Whiskey", "Porter", "Lager", "Grog", "Wine"]
const DRINK_C := ["served on fire", "that glows faintly in the dark", "brewed with cave mushrooms", "that tastes of pine smoke",
	"said to put hair on your chest", "aged in an old dragon's skull", "that changes colour as you drink", "best not drunk twice",
	"with a pickled egg at the bottom", "sweet as honey, strong as an ox"]
const DISHES := {
	"human": ["roast boar with honeyed parsnips", "eel pie", "mushroom and stout stew", "spiced lamb skewers", "blackened river trout",
		"giant crab legs in garlic butter", "rabbit pie with a flaky crust", "venison in juniper sauce", "pickled eggs (if you dare)",
		"dragon-pepper chili", "a whole roast chicken and a loaf"],
	"dwarf": ["cave-mushroom steaks", "rock-salted mutton", "black bread with smoked goat cheese", "boar sausages in ale gravy",
		"deep-lake fish fried in lard", "a stew nobody will name"],
	"elf": ["elven waybread with wild honey", "moonberry tart", "sunflower-seed salad with dew-pears", "river trout wrapped in vine leaves",
		"a delicate soup of seven herbs", "honeyed figs and soft cheese"],
}
const ENTERTAINMENT := {
	"human": ["a bard who only knows three songs", "arm-wrestling at the corner table", "a dice game called Dragon's Hoard",
		"a fortune-teller with a cracked crystal ball", "cockroach racing", "a knife-throwing contest", "a weekly poetry duel",
		"a talking parrot that insults the guests", "a minstrel trio on feast days", "storytelling by the fire"],
	"dwarf": ["drinking songs that shake the rafters", "axe-throwing at a scarred target", "beard-braiding contests",
		"a game of stones and bones", "an old skald reciting clan histories"],
	"elf": ["a harpist playing songs older than the town", "poetry under the stars", "dancing lights drifting over the tables",
		"a riddle game with a silver prize", "a flute duet at dusk"],
}
const RUMORS := ["Someone has been quietly buying up all the silver in town.", "The miller's daughter swears she saw a dragon over the hills.",
	"The old mine reopened, and the miners stopped coming home.", "A noblewoman pays gold for anyone who finds her lost signet ring.",
	"Wolves have been seen walking on two legs at night.", "The toll-keeper on the bridge isn't who he says he is.",
	"There's treasure under the temple. Everyone knows it.", "The last adventurers to drink here left owing a fortune, and never came back.",
	"Ghostly lights have been dancing in the graveyard.", "A caravan went missing on the north road three days ago.",
	"The brewer swears something lives in his cellar.", "The guard captain takes bribes in ale.",
	"A hooded stranger pays for every round, then vanishes before dawn.", "The well water tastes of copper since the earthquake."]
const HEARTH_TEXT := {"human": "a roaring hearth with armchairs", "dwarf": "a great forge-hearth that never goes out", "elf": "a hearth of softly glowing stones"}
const TROPHIES := ["owlbear", "wyvern", "dire boar", "griffon", "basilisk", "giant elk", "troll"]
const LONG_TABLES := {"human": 0.45, "dwarf": 0.75, "elf": 0.15}

static func pick(rng: RandomNumberGenerator, a: Array):
	return a[rng.randi() % a.size()] if not a.is_empty() else ""

## A tavern name, e.g. "The Winking Wyvern", "The Goblet and Goose", "Bruna's Alehall", "The Wizard's Sock".
static func random_name(rng: RandomNumberGenerator, style := "human") -> String:
	var st := style if PLACE_WORDS.has(style) else "human"
	var adj: Array = ADJ + STYLE_ADJ.get(st, []) + STYLE_ADJ.get(st, [])
	var noun: Array = NOUN + STYLE_NOUN.get(st, []) + STYLE_NOUN.get(st, [])
	var r := rng.randf()
	if r < 0.42:
		return "The %s %s" % [pick(rng, adj), pick(rng, noun)]
	if r < 0.62:
		var a: String = pick(rng, noun)
		var b: String = pick(rng, noun)
		while b == a:
			b = pick(rng, noun)
		return "The %s and %s" % [a, b]
	if r < 0.77:
		return "%s's %s" % [NameGen.first_name(rng, NameGen.race_for(rng, st)), pick(rng, PLACE_WORDS[st])]
	if r < 0.9:
		return "The %s's %s" % [pick(rng, OWNER_NOUNS), pick(rng, ODD_THINGS)]
	return pick(rng, SPECIALS[st])

## Everything about a tavern except its layout: name, proprietor, quality and prices, house drink and dish,
## entertainment and a rumour.
static func make_info(rng: RandomNumberGenerator, style := "human") -> Dictionary:
	var st := style if PLACE_WORDS.has(style) else "human"
	var nm := random_name(rng, st)
	var owner := NameGen.person(rng, st)
	var total := 0
	for q in QUALITIES:
		total += int(q[1])
	var roll := rng.randi_range(1, total)
	var quality: Array = QUALITIES[2]
	for q in QUALITIES:
		roll -= int(q[1])
		if roll <= 0:
			quality = q
			break
	var drink := "%s %s, %s" % [pick(rng, DRINK_A + DRINK_A_STYLE.get(st, [])), pick(rng, DRINK_B), pick(rng, DRINK_C)]
	return {"name": nm, "proprietor": "%s (%s), who %s" % [owner.name, owner.race, pick(rng, QUIRKS)], "quality": quality[0], "prices": quality[2],
		"drink": drink, "dish": pick(rng, DISHES[st] + DISHES.human.slice(0, 4)), "entertainment": pick(rng, ENTERTAINMENT[st]),
		"rumor": pick(rng, RUMORS), "style": st, "features": []}

## The tavern's details as BBCode lines for the DM.
static func describe(info: Dictionary) -> String:
	var lines: Array = []
	lines.append("[b]%s[/b]  [color=#a59cb5](%s; %s)[/color]" % [info.get("name", "Tavern"), str(info.get("quality", "")).to_lower(), info.get("prices", "")])
	lines.append("Run by %s." % info.get("proprietor", "someone"))
	lines.append("House drink: %s. House dish: %s." % [info.get("drink", ""), info.get("dish", "")])
	lines.append("Entertainment: %s." % info.get("entertainment", ""))
	var feats: Array = info.get("features", [])
	if not feats.is_empty():
		lines.append("Inside: %s." % ", ".join(feats))
	lines.append("[i]Rumour: %s[/i]" % info.get("rumor", ""))
	return "\n".join(lines)

## Lay out a tavern inside `inner` (the floor inside its walls); the front door(s) are in the wall on `side`
## at local positions `door_us`. Returns the layout features, in words.
static func furnish(g, inner: Rect2i, side: String, door_us: Array, style: String, mats: Dictionary) -> Array:
	var f: StructureBuilder.Frame = StructureBuilder.Frame.new(inner, side)
	var rng: RandomNumberGenerator = g.rng
	var L: int = f.L
	var D: int = f.D
	var feats: Array = []
	var used := {}
	var door_mean := 0.0
	for du in door_us:
		door_mean += float(du)
		for dv in 2:
			for o in range(-1, 2):
				used[Vector2i(du + o, dv)] = true
	door_mean /= maxf(1.0, door_us.size())
	# A big hall: the back becomes guest rooms and storerooms, the tavern proper takes the front.
	if D >= 15:
		var keep := clampi(int(D * 0.55), 9, 14)
		StructureBuilder.back_rooms(g, f, keep, mats)
		feats.append("guest rooms and storerooms off the back")
		f = StructureBuilder.Frame.new(f.rect_of(0, 0, L, keep), side)
		D = keep
	# Kitchen in a back corner, away from the front door.
	var k_right := door_mean < L / 2.0
	var main_u0 := 0
	var main_u1 := L - 1
	var wall_u := -100
	var wall_v := D
	if D >= 7 and L >= 10 and rng.randf() < 0.85:
		var kw := rng.randi_range(3, 4)
		var kd := clampi(D / 2, 3, 4)
		wall_v = D - kd - 1
		var ku0 := L - kw if k_right else 0
		var ku1 := L - 1 if k_right else kw - 1
		wall_u = ku0 - 1 if k_right else ku1 + 1
		for v in range(wall_v, D):
			StructureBuilder.wall_local(g, f, used, wall_u, v, mats.wall)
		for u in range(mini(ku0, wall_u), maxi(ku1, wall_u) + 1):
			StructureBuilder.wall_local(g, f, used, u, wall_v, mats.wall)
		StructureBuilder.door_at(g, f.at(wall_u, D - 1), mats.floor)
		for u in range(ku0, ku1 + 1):
			for v in range(wall_v + 1, D):
				g.gset(f.at(u, v), MapGenerator.G_FLAG)
		StructureBuilder.wall_prop(g, f, used, (ku0 + ku1) / 2, D, "oven")
		StructureBuilder.put_local(g, f, used, (ku0 + ku1) / 2, wall_v + 1 + kd / 2, 1, 1, "worktable")
		for c in [Vector2i(ku0, wall_v + 1), Vector2i(ku1, wall_v + 1), Vector2i(ku1 if k_right else ku0, D - 1)]:
			StructureBuilder.put_local(g, f, used, c.x, c.y, 1, 1, ["barrel", "crate", "barrel"][rng.randi() % 3])
		if rng.randf() < 0.45:
			var td: Vector2i = StructureBuilder.find_free(g, f, used, 1, 1, rng, Rect2i(ku0, wall_v + 1, ku1 - ku0 + 1, kd))
			if td.x >= 0:
				StructureBuilder.put_local(g, f, used, td.x, td.y, 1, 1, "trapdoor", MapGenerator.FLOOR)
				feats.append("a trapdoor down to the cellar")
		for u in range(ku0, ku1 + 1):
			for v in range(wall_v + 1, D):
				used[Vector2i(u, v)] = true
		feats.append("a kitchen behind the bar")
		if k_right:
			main_u1 = wall_u - 1
		else:
			main_u0 = wall_u + 1
	# The bar: a counter along the back wall with a lane behind it for the barkeep, kegs and shelves on the wall.
	var bar_u0 := -1
	var bar_u1 := -1
	if D >= 5 and main_u1 - main_u0 >= 2:
		var span := main_u1 - main_u0 + 1
		var blen := clampi(int(span * rng.randf_range(0.45, 0.7)), 2, maxi(2, span - 2))
		var start: int
		if wall_u > -100:
			start = main_u1 - blen + 1 if k_right else main_u0
		else:
			start = clampi(main_u0 + (span - blen) / 2 + rng.randi_range(-2, 2), main_u0 + 1, main_u1 - blen)
		bar_u0 = start
		bar_u1 = start + blen - 1
		for u in range(start, start + blen):
			StructureBuilder.put_local(g, f, used, u, D - 2, 1, 1, "bar")
			StructureBuilder.wall_prop(g, f, used, u, D, "keg" if (u - start) % 2 == 0 else "wallshelf")
		for u in range(start - 1, start + blen + 1):
			used[Vector2i(u, D - 1)] = true
			used[Vector2i(u, D - 3)] = true
		feats.append("a %d-ft bar along the back wall" % (blen * 5))
	elif L >= 4 and D >= 2:
		var bu := L - 2 if door_mean < L / 2.0 else 1
		for v in range(maxi(0, D - 3), D):
			StructureBuilder.put_local(g, f, used, bu, v, 1, 1, "bar")
			used[Vector2i(bu + (1 if bu > L / 2 else -1), v)] = true
		feats.append("a short corner bar")
	# Hearth on the side wall away from the kitchen, a rug and armchairs in front of it.
	var hu := -1 if k_right else L
	var hv := rng.randi_range(1, maxi(1, mini(wall_v, D - 3) - 2))
	if hv < D and StructureBuilder.wall_prop(g, f, used, hu, hv, "hearth"):
		var iu := 0 if hu < 0 else L - 1
		var dir := 1 if hu < 0 else -1
		for dv in range(-1, 2):
			for du2 in 2:
				var q := Vector2i(iu + du2 * dir, hv + dv)
				if q.y >= 0 and q.y < D and g._at(f.at(q.x, q.y)) == MapGenerator.FLOOR:
					g.gset(f.at(q.x, q.y), MapGenerator.G_RUG)
		StructureBuilder.put_local(g, f, used, iu + dir, hv - 1, 1, 1, "armchair", MapGenerator.FLOOR)
		StructureBuilder.put_local(g, f, used, iu + dir, hv + 1, 1, 1, "armchair", MapGenerator.FLOOR)
		for dv in range(-1, 2):
			for du2 in 2:
				used[Vector2i(iu + du2 * dir, hv + dv)] = true
		feats.append(HEARTH_TEXT.get(style, HEARTH_TEXT.human))
	# A stage in the front corner away from the door.
	if L * D >= 70 and rng.randf() < 0.55:
		var su := L - 3 if door_mean < L / 2.0 else 0
		if StructureBuilder.put_local(g, f, used, su, 0, 3, 2, "stage"):
			feats.append("a little stage for performers")
	# Booths along the other side wall.
	if L >= 9 and D >= 7 and rng.randf() < 0.45:
		var bu2 := L - 1 if hu < 0 else 0
		var made := 0
		var v := 1
		while v + 2 < mini(D - 3, wall_v):
			if StructureBuilder.free_local(g, f, used, bu2, v, 1, 3):
				StructureBuilder.put_local(g, f, used, bu2, v, 1, 1, "bench")
				StructureBuilder.put_local(g, f, used, bu2, v + 1, 1, 1, "table_round")
				StructureBuilder.put_local(g, f, used, bu2, v + 2, 1, 1, "bench")
				used[Vector2i(bu2 + (1 if bu2 == 0 else -1), v + 1)] = true
				made += 1
			v += 4
		if made > 0:
			feats.append("high-backed booths along the wall")
	# Stairs up in a front corner.
	if D >= 6 and rng.randf() < 0.6:
		for c in ([Vector2i(0, 0), Vector2i(L - 1, 0)] if rng.randf() < 0.5 else [Vector2i(L - 1, 0), Vector2i(0, 0)]):
			if StructureBuilder.put_local(g, f, used, c.x, c.y, 1, 2, "stairs"):
				feats.append("stairs up to the rooms")
				break
	# One odd feature.
	var quirks := ["trophy", "dartboard", "ring", "bigbarrel", "shrine", "trophy"]
	if style == "dwarf":
		quirks += ["firepit", "firepit"]
	elif style == "elf":
		quirks += ["tree", "tree"]
	match pick(rng, quirks):
		"trophy", "dartboard", "shrine":
			var k: String = ["trophy", "dartboard", "shrine"][rng.randi() % 3]
			for i in 20:
				var spot: Vector2i = [Vector2i(-1, rng.randi_range(0, D - 1)), Vector2i(L, rng.randi_range(0, D - 1)), Vector2i(rng.randi_range(0, L - 1), D)][rng.randi() % 3]
				if StructureBuilder.wall_prop(g, f, used, spot.x, spot.y, k):
					feats.append({"trophy": "a stuffed %s head mounted on the wall" % pick(rng, TROPHIES), "dartboard": "a dartboard riddled with knife marks",
						"shrine": "a tiny wall shrine where regulars leave a coin for luck"}[k])
					break
		"ring":
			var p: Vector2i = StructureBuilder.find_free(g, f, used, 3, 3, rng)
			if p.x >= 0:
				StructureBuilder.put_local(g, f, used, p.x, p.y, 3, 3, "ring", MapGenerator.FLOOR)
				feats.append("a roped-off brawling ring")
		"bigbarrel":
			var p: Vector2i = StructureBuilder.find_free(g, f, used, 2, 2, rng)
			if p.x >= 0:
				StructureBuilder.put_local(g, f, used, p.x, p.y, 2, 2, "bigbarrel")
				feats.append("an enormous old barrel turned into a snug")
		"firepit":
			var p: Vector2i = StructureBuilder.find_free(g, f, used, 2, 2, rng)
			if p.x >= 0:
				StructureBuilder.put_local(g, f, used, p.x, p.y, 2, 2, "firepit")
				feats.append("a sunken fire pit in the middle of the room")
		"tree":
			var p: Vector2i = StructureBuilder.find_free(g, f, used, 1, 1, rng)
			if p.x >= 0:
				StructureBuilder.put_local(g, f, used, p.x, p.y, 1, 1, "tree", MapGenerator.WALL)
				feats.append("a living tree growing up through the floor")
	# A rug or two.
	if style != "elf" and rng.randf() < 0.35:
		var p: Vector2i = StructureBuilder.find_free(g, f, used, 3, 2, rng)
		if p.x >= 0:
			for a in 3:
				for b in 2:
					g.gset(f.at(p.x + a, p.y + b), MapGenerator.G_RUG)
	# Tables with chairs (benches at long tables), spaced so there is always a way between them.
	var want := clampi(int(L * D * (0.05 + 0.07 * float(g.s.get("difficult", 0.2)))), 2, 18)
	var cands: Array = []
	for u in L:
		for v in D:
			cands.append(Vector2i(u, v))
	StructureBuilder.shuffle(cands, rng)
	var blocked := {}
	var placed := 0
	for c in cands:
		if placed >= want:
			break
		var lu := 1
		if rng.randf() < LONG_TABLES.get(style, 0.4):
			lu = 3 if rng.randf() < 0.7 else 2
		var clash := false
		for a in lu:
			if blocked.has(c + Vector2i(a, 0)):
				clash = true
		if clash or not StructureBuilder.free_local(g, f, used, c.x, c.y, lu, 1):
			continue
		StructureBuilder.put_local(g, f, used, c.x, c.y, lu, 1, "table_long" if lu > 1 else "table_round")
		var seat := "bench" if lu > 1 else "chair"
		var ring: Array = []
		for a in lu:
			ring.append(c + Vector2i(a, -1))
			ring.append(c + Vector2i(a, 1))
		ring.append(c + Vector2i(-1, 0))
		ring.append(c + Vector2i(lu, 0))
		for q in ring:
			if not blocked.has(q) and rng.randf() < 0.8:
				StructureBuilder.put_local(g, f, used, q.x, q.y, 1, 1, seat, MapGenerator.FLOOR)
		for a in range(-1, lu + 1):
			for b in range(-1, 2):
				blocked[c + Vector2i(a, b)] = true
		placed += 1
	if style == "elf":
		for i in 3:
			var p: Vector2i = StructureBuilder.find_free(g, f, used, 1, 1, rng)
			if p.x >= 0:
				StructureBuilder.put_local(g, f, used, p.x, p.y, 1, 1, "plant")
	return feats
