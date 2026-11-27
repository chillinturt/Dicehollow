extends Node
## Dice rolling utilities. Dice strings: "2d6", "1d8+3", "3", "2d6+1d4+2".

var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.randomize()

func d(sides: int) -> int:
	if sides <= 1:
		return max(sides, 0)
	return rng.randi_range(1, sides)

func d20() -> int:
	return d(20)

## Roll a d20 with advantage (adv > 0), disadvantage (adv < 0), or straight.
## Returns {"roll": kept, "rolls": [a, b?]}.
func roll_d20(adv: int, halfling_lucky := false) -> Dictionary:
	var a = d20()
	if halfling_lucky and a == 1:
		a = d20()
	if adv == 0:
		return {"roll": a, "rolls": [a]}
	var b = d20()
	if halfling_lucky and b == 1:
		b = d20()
	var kept = maxi(a, b) if adv > 0 else mini(a, b)
	return {"roll": kept, "rolls": [a, b]}

## Parse a dice string into terms: [{"n":2,"s":6}, {"flat":3}]
func parse(expr: String) -> Array:
	var terms: Array = []
	var s = expr.replace(" ", "").to_lower()
	if s == "":
		return terms
	s = s.replace("-", "+-")
	for part in s.split("+", false):
		var sign = 1
		var p: String = part
		if p.begins_with("-"):
			sign = -1
			p = p.substr(1)
		if "d" in p:
			var bits = p.split("d")
			var n = 1 if bits[0] == "" else int(bits[0])
			terms.append({"n": n * sign, "s": int(bits[1])})
		elif p != "":
			terms.append({"flat": int(p) * sign})
	return terms

## Build a dice string from terms.
func to_str(terms: Array) -> String:
	var out = ""
	for t in terms:
		var piece = ""
		if t.has("flat"):
			if int(t.flat) == 0:
				continue
			piece = str(t.flat)
		else:
			piece = "%dd%d" % [int(t.n), int(t.s)]
		if out != "" and not piece.begins_with("-"):
			out += "+"
		out += piece
	return out if out != "" else "0"

## Multiply the dice count (not flats) — used for crits and cantrip scaling.
func scale_dice(expr: String, mult: int) -> String:
	var terms = parse(expr)
	for t in terms:
		if t.has("n"):
			t.n = int(t.n) * mult
	return to_str(terms)

## Add `extra` dice string to `expr`.
func add(expr: String, extra: String) -> String:
	if extra == "" or extra == "0":
		return expr
	if expr == "" or expr == "0":
		return extra
	return to_str(parse(expr) + parse(extra))

## Repeat a dice string n times ("1d6" x3 -> "3d6").
func times(expr: String, n: int) -> String:
	if n <= 0:
		return "0"
	var out: Array = []
	for t in parse(expr):
		var c: Dictionary = t.duplicate()
		if c.has("n"):
			c.n = int(c.n) * n
		else:
			c.flat = int(c.flat) * n
		out.append(c)
	return to_str(out)

## Roll a dice string. Options: crit (double dice), max (maximise dice),
## min_die (treat lower results as this, e.g. Elemental Adept = 2), reroll_below (GWF: reroll 1s and 2s once).
## Returns {"total": int, "rolls": Array[int], "expr": String}
func roll(expr: String, opts := {}) -> Dictionary:
	var total = 0
	var rolls: Array = []
	var crit: bool = opts.get("crit", false)
	var maximize: bool = opts.get("max", false)
	var min_die: int = opts.get("min_die", 0)
	var reroll_below: int = opts.get("reroll_below", 0)
	for t in parse(expr):
		if t.has("flat"):
			total += int(t.flat)
			continue
		var n: int = absi(int(t.n))
		var sign = 1 if int(t.n) >= 0 else -1
		if crit:
			n *= 2
		for i in n:
			var r: int = int(t.s) if maximize else d(int(t.s))
			if reroll_below > 0 and r <= reroll_below and not maximize:
				r = d(int(t.s))
			if min_die > 0 and r < min_die:
				r = min_die
			rolls.append(r * sign)
			total += r * sign
	return {"total": total, "rolls": rolls, "expr": expr}

## Average value of a dice string (for AI and previews).
func average(expr: String) -> float:
	var total = 0.0
	for t in parse(expr):
		if t.has("flat"):
			total += float(t.flat)
		else:
			total += float(t.n) * (float(t.s) + 1.0) / 2.0
	return total

func max_value(expr: String) -> int:
	var total = 0
	for t in parse(expr):
		if t.has("flat"):
			total += int(t.flat)
		else:
			total += int(t.n) * int(t.s)
	return total
