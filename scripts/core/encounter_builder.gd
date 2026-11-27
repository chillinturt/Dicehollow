class_name EncounterBuilder
extends RefCounted
## Picks monsters for a generated encounter using the 5e (2014) DMG encounter-building rules:
## per-character XP thresholds, the group-size multiplier and the small/large party adjustment.
## The party's classes nudge the result (no healer → a little easier, lots of area damage → more,
## weaker monsters; an all-martial party → fewer, tougher ones).

const DIFFICULTIES := ["easy", "medium", "hard", "deadly", "deadly+"]
const DIFFICULTY_NAMES := {"easy": "Easy", "medium": "Medium", "hard": "Hard", "deadly": "Deadly", "deadly+": "Beyond deadly"}

## DMG p.82: XP thresholds by character level [easy, medium, hard, deadly].
const THRESHOLDS := {
	1: [25, 50, 75, 100], 2: [50, 100, 150, 200], 3: [75, 150, 225, 400], 4: [125, 250, 375, 500],
	5: [250, 500, 750, 1100], 6: [300, 600, 900, 1400], 7: [350, 750, 1100, 1700], 8: [450, 900, 1400, 2100],
	9: [550, 1100, 1600, 2400], 10: [600, 1200, 1900, 2800], 11: [800, 1600, 2400, 3600], 12: [1000, 2000, 3000, 4500],
	13: [1100, 2200, 3400, 5100], 14: [1250, 2500, 3800, 5700], 15: [1400, 2800, 4300, 6400], 16: [1600, 3200, 4800, 7200],
	17: [2000, 3900, 5900, 8800], 18: [2100, 4200, 6300, 9500], 19: [2400, 4900, 7300, 10900], 20: [2800, 5700, 8500, 12700],
}
## DMG p.82: encounter multipliers, with the extra ×0.5 and ×5 steps for large and small parties.
const MULTIPLIERS := [0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 4.0, 5.0]

const COMPOSITIONS := {
	"auto": "Auto (from the party)", "solo": "Solo monster", "boss": "Boss + minions",
	"balanced": "Mixed group", "horde": "Horde (many weak)",
}
const CREATURE_TYPES := ["aberration", "beast", "construct", "dragon", "elemental", "fiend", "giant", "humanoid", "monstrosity", "ooze", "undead"]

## Where each bestiary monster plausibly lives. Custom monsters (and anything missing here) fall back to TYPE_HABITATS.
const HABITATS := {
	"dungeon": ["bandit", "bandit_captain", "cultist", "cult_fanatic", "acolyte", "priest", "mage", "veteran", "knight", "assassin", "thug",
		"goblin", "hobgoblin", "bugbear", "kobold", "orc", "skeleton", "zombie", "ogre_zombie", "ghoul", "ghast", "shadow", "specter",
		"wight", "wraith", "vampire_spawn", "mummy", "giant_rat", "swarm_of_rats", "giant_spider", "gelatinous_cube", "gray_ooze",
		"imp", "quasit", "dretch", "hell_hound", "animated_armor", "flying_sword", "minotaur", "doppelganger", "basilisk", "chuul",
		"ogre", "troll", "salamander", "earth_elemental", "fire_elemental", "oni", "gladiator", "guard"],
	"cave": ["goblin", "hobgoblin", "bugbear", "kobold", "orc", "giant_rat", "swarm_of_rats", "giant_spider", "gray_ooze", "gelatinous_cube",
		"giant_badger", "black_bear", "brown_bear", "ogre", "troll", "ettin", "basilisk", "chuul", "earth_elemental", "ghoul", "shadow",
		"cockatrice", "minotaur", "stone_giant", "hydra", "young_black_dragon", "constrictor_snake", "giant_constrictor_snake", "skeleton"],
	"forest": ["bandit", "bandit_captain", "scout", "thug", "goblin", "hobgoblin", "bugbear", "orc", "gnoll", "wolf", "dire_wolf", "worg",
		"giant_spider", "brown_bear", "black_bear", "boar", "panther", "giant_badger", "giant_wasp", "giant_poisonous_snake",
		"constrictor_snake", "giant_elk", "ape", "giant_ape", "owlbear", "werewolf", "will_o_wisp", "ettin", "hill_giant",
		"cockatrice", "harpy", "hippogriff", "young_green_dragon", "troll", "giant_eagle"],
	"swamp": ["lizardfolk", "giant_toad", "giant_frog", "crocodile", "giant_poisonous_snake", "constrictor_snake",
		"giant_constrictor_snake", "swarm_of_rats", "giant_rat", "zombie", "ghoul", "will_o_wisp", "hydra", "young_black_dragon",
		"troll", "gray_ooze", "chuul", "giant_wasp", "banshee", "cultist", "merrow", "water_elemental"],
	"town": ["commoner", "bandit", "bandit_captain", "guard", "thug", "cultist", "cult_fanatic", "acolyte", "priest", "mage", "scout",
		"veteran", "knight", "gladiator", "assassin", "doppelganger", "cat", "giant_rat", "swarm_of_rats", "vampire_spawn", "werewolf",
		"imp", "quasit", "animated_armor", "flying_sword", "shadow"],
	"arctic": ["polar_bear", "wolf", "dire_wolf", "worg", "giant_elk", "orc", "scout", "veteran", "young_white_dragon", "griffon",
		"giant_eagle", "air_elemental", "stone_giant", "ettin", "troll", "wight", "ghost", "specter", "ogre"],
	"graveyard": ["skeleton", "zombie", "ogre_zombie", "ghoul", "ghast", "shadow", "specter", "will_o_wisp", "wight", "wraith",
		"vampire_spawn", "mummy", "banshee", "ghost", "cultist", "cult_fanatic", "acolyte", "priest", "giant_rat", "swarm_of_rats", "cat", "wolf"],
	"mountain": ["griffon", "hippogriff", "giant_eagle", "manticore", "harpy", "wyvern", "chimera", "young_red_dragon", "stone_giant",
		"hill_giant", "ogre", "ettin", "orc", "goblin", "hobgoblin", "kobold", "gorgon", "basilisk", "air_elemental", "earth_elemental",
		"giant_elk", "lion", "giant_hyena", "gnoll", "dire_wolf", "wolf", "scout", "veteran", "bandit", "bandit_captain", "giant_ape", "oni"],
}
const TYPE_HABITATS := {
	"aberration": ["dungeon", "cave", "swamp"], "beast": ["forest", "swamp", "mountain", "arctic", "cave"],
	"construct": ["dungeon", "town"], "dragon": ["mountain", "cave", "forest", "swamp", "arctic"],
	"elemental": ["dungeon", "mountain", "cave"], "fiend": ["dungeon", "town", "graveyard"], "giant": ["mountain", "forest", "arctic", "cave"],
	"humanoid": ["dungeon", "town", "forest", "mountain"], "monstrosity": ["forest", "mountain", "cave", "dungeon"],
	"ooze": ["dungeon", "cave", "swamp"], "undead": ["graveyard", "dungeon", "swamp"], "plant": ["forest", "swamp"], "fey": ["forest"],
	"celestial": ["mountain", "town"],
}

const XP_BY_CR := {0.0: 10, 0.125: 25, 0.25: 50, 0.5: 100, 1.0: 200, 2.0: 450, 3.0: 700, 4.0: 1100, 5.0: 1800, 6.0: 2300, 7.0: 2900,
	8.0: 3900, 9.0: 5000, 10.0: 5900, 11.0: 7200, 12.0: 8400, 13.0: 10000, 14.0: 11500, 15.0: 13000, 16.0: 15000, 17.0: 18000,
	18.0: 20000, 19.0: 22000, 20.0: 25000, 21.0: 33000, 22.0: 41000, 23.0: 50000, 24.0: 62000, 25.0: 75000, 26.0: 90000}

const HEALERS := ["cleric", "druid", "bard", "paladin", "artificer"]
const AOE_CASTERS := ["wizard", "sorcerer", "druid"]
const MARTIALS := ["fighter", "barbarian", "paladin", "monk", "rogue", "ranger"]

# ---------------------------------------------------------------- party math

## party: Array of {"name", "level", "classes": {class_id: levels}}.
static func thresholds(party: Array) -> Array:
	var t := [0, 0, 0, 0]
	for p in party:
		var row: Array = THRESHOLDS[clampi(int(p.get("level", 1)), 1, 20)]
		for i in 4:
			t[i] += row[i]
	return t

static func monster_xp(m: Dictionary) -> int:
	if m.has("xp") and int(m.xp) > 0:
		return int(m.xp)
	return int(XP_BY_CR.get(float(m.get("cr", 0)), 10))

## The DMG encounter multiplier for `count` monsters against a party of `party_size`.
static func multiplier(count: int, party_size: int) -> float:
	if count <= 0:
		return 0.0
	var idx := 1
	if count == 1: idx = 1
	elif count == 2: idx = 2
	elif count <= 6: idx = 3
	elif count <= 10: idx = 4
	elif count <= 14: idx = 5
	elif count > 14: idx = 6
	if party_size < 3:
		idx += 1
	elif party_size >= 6:
		idx -= 1
	return MULTIPLIERS[clampi(idx, 0, MULTIPLIERS.size() - 1)]

## Raw and adjusted XP for a list of {"mid", "count"} picks.
static func rate(picks: Array, party_size: int) -> Dictionary:
	var raw := 0
	var n := 0
	for p in picks:
		raw += monster_xp(Data.monster(str(p.mid))) * int(p.count)
		n += int(p.count)
	return {"raw": raw, "count": n, "adjusted": int(raw * multiplier(n, party_size))}

## Which DMG band an adjusted XP total falls in, for this party.
static func difficulty_of(adjusted: int, party: Array) -> String:
	var t := thresholds(party)
	if adjusted >= int(t[3] * 1.5): return "deadly+"
	if adjusted >= t[3]: return "deadly"
	if adjusted >= t[2]: return "hard"
	if adjusted >= t[1]: return "medium"
	if adjusted >= t[0]: return "easy"
	return "trivial"

## What the party's classes mean for the fight: budget scale, a preferred composition and notes for the DM.
static func party_profile(party: Array) -> Dictionary:
	var healer := false
	var aoe := 0
	var martial := 0
	var levels := 0
	for p in party:
		var cls: Dictionary = p.get("classes", {})
		levels += int(p.get("level", 1))
		var is_aoe := false
		var is_martial := false
		for k in cls:
			if k in HEALERS: healer = true
			if k in AOE_CASTERS: is_aoe = true
			if k in MARTIALS: is_martial = true
		if is_aoe: aoe += 1
		if is_martial and not is_aoe: martial += 1
	var n := maxi(1, party.size())
	var notes: Array = []
	var scale := 1.0
	var pref := "balanced"
	if party.is_empty():
		return {"scale": 1.0, "prefer": "balanced", "notes": ["No party chosen: add players or set the party size."], "avg_level": 1}
	if not healer:
		scale *= 0.9
		notes.append("No healer in the party: budget lowered 10%.")
	if float(aoe) / n >= 0.4:
		pref = "horde"
		notes.append("Area-damage casters: favouring more, weaker monsters.")
	elif float(martial) / n >= 0.75:
		pref = "boss"
		notes.append("Martial-heavy party: favouring fewer, tougher monsters.")
	if party.size() <= 2:
		notes.append("Small party: action economy matters, so solo bosses are risky.")
	return {"scale": scale, "prefer": pref, "notes": notes, "avg_level": int(round(float(levels) / n))}

# ---------------------------------------------------------------- monster pool

static func habitats_of(m: Dictionary) -> Array:
	var out: Array = []
	for h in HABITATS:
		if str(m.get("id", "")) in HABITATS[h]:
			out.append(h)
	if out.is_empty():
		out = TYPE_HABITATS.get(str(m.get("type", "")), [])
	return out

## Monsters allowed by the settings. Falls back to ignoring the habitat when it leaves nothing.
static func pool(settings: Dictionary, max_xp: int) -> Array:
	var types: Array = settings.get("types", [])
	var terrain: String = settings.get("habitat", settings.get("terrain", "dungeon"))
	var habitat: bool = settings.get("match_habitat", true)
	var allow_custom: bool = settings.get("allow_custom", true)
	var exclude: Array = settings.get("exclude", [])
	var out: Array = []
	var loose: Array = []
	for m in Data.monsters_sorted():
		var mid := str(m.id)
		if mid in exclude or mid == "commoner" or mid == "cat":
			continue
		if not allow_custom and Data.custom_monsters.has(mid):
			continue
		if not types.is_empty() and not str(m.get("type", "")) in types:
			continue
		var xp := monster_xp(m)
		if xp > max_xp:
			continue
		loose.append(m)
		if not habitat or terrain in habitats_of(m):
			out.append(m)
	return out if not out.is_empty() else loose

# ---------------------------------------------------------------- building

## Build the encounter. Returns {"picks": [{"mid","count"}], "raw", "adjusted", "count", "target", "difficulty", "notes", ...}.
static func build(settings: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var party: Array = settings.get("party", [])
	var psize := maxi(1, party.size())
	var prof := party_profile(party)
	var t := thresholds(party if not party.is_empty() else [{"level": 1}])
	var di: int = clampi(int(settings.get("difficulty", 1)), 0, DIFFICULTIES.size() - 1)
	var strength: float = 1.0 + 0.15 * float(settings.get("strength", 0))
	var scale: float = prof.scale * strength
	var lo: float
	var hi: float
	if di < 3:
		lo = t[di]
		hi = t[di + 1]
	elif di == 3:
		lo = t[3]
		hi = t[3] * 1.5
	else:
		lo = t[3] * 1.5
		hi = t[3] * 2.2
	lo *= scale
	hi *= scale
	var target := (lo + hi) * 0.5
	var comp: String = settings.get("composition", "auto")
	if comp == "auto":
		comp = prof.prefer
		if comp == "boss" and psize <= 2:
			comp = "balanced"
	var max_n: int = clampi(int(settings.get("max_monsters", 12)), 1, 30)
	# A single monster may never be worth more than the whole upper budget on its own.
	var candidates := pool(settings, int(hi))
	var notes: Array = prof.notes.duplicate()
	if candidates.is_empty():
		notes.append("No monster fits these filters and this budget. Loosen the creature types or raise the difficulty.")
		return {"picks": [], "raw": 0, "adjusted": 0, "count": 0, "target": int(target), "lo": int(lo), "hi": int(hi),
			"difficulty": "none", "composition": comp, "notes": notes, "thresholds": t}
	var best: Array = []
	var best_score := INF
	for attempt in 600:
		var picks := _attempt(comp, candidates, max_n, target, psize, rng)
		if picks.is_empty():
			continue
		var r := rate(picks, psize)
		var score: float = absf(r.adjusted - target) / target
		if r.adjusted > hi: score += 1.0 + (r.adjusted - hi) / target
		if r.adjusted < lo: score += 0.5 + (lo - r.adjusted) / target
		score += rng.randf() * 0.04   # break ties so rerolls vary
		if score < best_score:
			best_score = score
			best = picks
	var res := rate(best, psize)
	var diff := difficulty_of(res.adjusted, party if not party.is_empty() else [{"level": 1}])
	if res.adjusted < lo or res.adjusted > hi:
		notes.append("Closest fit with these filters is %s rather than %s." % [DIFFICULTY_NAMES.get(diff, diff), DIFFICULTY_NAMES[DIFFICULTIES[di]]])
	return {"picks": best, "raw": res.raw, "adjusted": res.adjusted, "count": res.count, "target": int(target), "lo": int(lo), "hi": int(hi),
		"difficulty": diff, "composition": comp, "notes": notes, "thresholds": t}

static func _attempt(comp: String, cands: Array, max_n: int, target: float, psize: int, rng: RandomNumberGenerator) -> Array:
	match comp:
		"solo":
			return [{"mid": _pick_near(cands, target / multiplier(1, psize), rng).id, "count": 1}]
		"boss":
			if max_n < 2:
				return _attempt("solo", cands, max_n, target, psize, rng)
			var boss: Dictionary = _pick_near(cands, target * rng.randf_range(0.35, 0.6) / multiplier(3, psize), rng)
			var kin := _kin(cands, boss, monster_xp(boss) / 3)
			if kin.is_empty():
				return []
			var minion: Dictionary = kin[rng.randi() % kin.size()]
			var n := rng.randi_range(2, mini(6, max_n - 1))
			return [{"mid": boss.id, "count": 1}, {"mid": minion.id, "count": n}]
		"horde":
			var n := rng.randi_range(mini(5, max_n), max_n)
			var each := target / multiplier(n, psize) / n
			var a: Dictionary = _pick_near(cands, each * rng.randf_range(0.7, 1.3), rng)
			if rng.randf() < 0.4 and n >= 6:
				var kin := _kin(cands, a, monster_xp(a) * 2)
				if not kin.is_empty():
					var b: Dictionary = kin[rng.randi() % kin.size()]
					var nb := rng.randi_range(1, n / 3)
					return [{"mid": a.id, "count": n - nb}, {"mid": b.id, "count": nb}]
			return [{"mid": a.id, "count": n}]
		_:  # balanced: two or three kinds of monster, 2–6 in all
			var n := rng.randi_range(mini(2, max_n), mini(6, max_n))
			var kinds := mini(n, rng.randi_range(1, 3))
			var each := target / multiplier(n, psize) / n
			var first: Dictionary = _pick_near(cands, each * rng.randf_range(0.6, 1.8), rng)
			var out := [{"mid": first.id, "count": 1}]
			var kin := _kin(cands, first, int(each * 2.5))
			for k in range(1, kinds):
				if kin.is_empty():
					break
				var m: Dictionary = kin[rng.randi() % kin.size()]
				if out.any(func(o): return o.mid == m.id):
					continue
				out.append({"mid": m.id, "count": 1})
			var left := n - out.size()
			while left > 0:
				out[rng.randi() % out.size()].count += 1
				left -= 1
			return out

## A random monster whose XP is close to `xp` (picked from the few nearest so results vary).
static func _pick_near(cands: Array, xp: float, rng: RandomNumberGenerator) -> Dictionary:
	# The four nearest by XP, found with one pass (this runs hundreds of times per build).
	var near: Array = []   # [distance, monster], kept sorted, at most 4 long
	for m in cands:
		var d := absf(monster_xp(m) - xp) + rng.randf()   # the noise breaks ties between same-CR monsters
		if near.size() < 4 or d < near[-1][0]:
			var i := near.size()
			while i > 0 and near[i - 1][0] > d:
				i -= 1
			near.insert(i, [d, m])
			if near.size() > 4:
				near.pop_back()
	return near[rng.randi() % near.size()][1]

## Monsters that belong with `m` (same creature type, or the same habitat) and are worth at most `max_xp` (min 10).
static func _kin(cands: Array, m: Dictionary, max_xp: int) -> Array:
	var same: Array = []
	for c in cands:
		if c.id != m.id and monster_xp(c) <= maxi(max_xp, 10) and str(c.get("type", "")) == str(m.get("type", "")):
			same.append(c)
	if not same.is_empty():
		return same
	for c in cands:
		if c.id != m.id and monster_xp(c) <= maxi(max_xp, 10):
			same.append(c)
	return same
