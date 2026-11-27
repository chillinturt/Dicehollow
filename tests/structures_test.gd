extends Node
## Headless checks for generated structures: towns in every style and size, Indoors taverns and temples,
## every wilderness structure on every outdoor terrain, tavern names and details, renaming, and the map
## dressing (ground, props, labels) surviving load, save, paint, resize and clear on the table.
## Run: Godot --headless --path . res://tests/structures_test.tscn   (exit code 1 on failure)
## Optional: -- <folder> writes ASCII dumps of a few maps there.

var fails := 0
var passes := 0

func check(cond: bool, what: String) -> void:
	if cond:
		passes += 1
	else:
		fails += 1
		print("FAIL: ", what)

func party(n: int, lvl: int) -> Array:
	var out: Array = []
	for i in n:
		out.append({"name": "P%d" % i, "level": lvl, "classes": {"fighter": lvl}})
	return out

## Every open cell reachable from the first start point, and monsters on legal cells.
func sound(m: Dictionary, tag: String) -> void:
	var w: int = m.w
	var h: int = m.h
	check(m.cells.size() == w * h, tag + ": cell count")
	check(m.spawns.size() >= 6, tag + ": start points (%d)" % m.spawns.size())
	if m.spawns.is_empty():
		return
	var seen := {}
	var start := Vector2i(m.spawns[0][0], m.spawns[0][1])
	var q: Array = [start]
	seen[start] = true
	var i := 0
	while i < q.size():
		var p: Vector2i = q[i]
		i += 1
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var n := p + Vector2i(dx, dy)
				if n.x < 0 or n.y < 0 or n.x >= w or n.y >= h or seen.has(n):
					continue
				var v: int = m.cells[n.y * w + n.x]
				if v != EngineBase.WALL and v != EngineBase.PIT:
					seen[n] = true
					q.append(n)
	var open := 0
	var unreached := 0
	for y in h:
		for x in w:
			var v: int = m.cells[y * w + x]
			if v != EngineBase.WALL and v != EngineBase.PIT:
				open += 1
				if not seen.has(Vector2i(x, y)):
					unreached += 1
	check(unreached == 0, tag + ": every open cell reachable (%d not)" % unreached)
	check(open >= w * h * 0.25, tag + ": a quarter open (%d)" % open)
	for mon in m.monsters:
		var sz: int = CombatantFactory.SIZE_CELLS.get(Data.monster(mon.mid).get("size", "medium"), 1)
		for dx in sz:
			for dy in sz:
				var p := Vector2i(mon.x + dx, mon.y + dy)
				if p.x >= w or p.y >= h or not seen.has(p):
					check(false, tag + ": monster %s on a bad cell %s" % [mon.mid, p])
	if m.has("ground"):
		check(m.ground.size() == w * h, tag + ": ground layer size")
	for p in m.get("props", []):
		if int(p.x) < 0 or int(p.y) < 0 or int(p.x) + int(p.get("w", 1)) > w or int(p.y) + int(p.get("h", 1)) > h:
			check(false, tag + ": prop %s off the map" % str(p))
			break
	var named := 0
	for st in m.report.get("structures", []):
		if str(st.name) != "":
			named += 1
	check(m.get("labels", []).size() == named, tag + ": one label per named place (%d/%d)" % [m.get("labels", []).size(), named])

func count_type(m: Dictionary, t: String) -> int:
	return m.report.structures.filter(func(s): return s.type == t).size()

func count_prop(m: Dictionary, k: String) -> int:
	return m.get("props", []).filter(func(p): return p.k == k).size()

func ascii(m: Dictionary) -> String:
	var cov := {}
	for p in m.get("props", []):
		cov[Vector2i(int(p.x), int(p.y))] = str(p.k)
	var s := ""
	for y in m.h:
		for x in m.w:
			var v: int = m.cells[y * m.w + x]
			var c: String = [".", "#", ":", "~", " "][v] if v < 5 else "?"
			if cov.has(Vector2i(x, y)):
				var k: String = cov[Vector2i(x, y)]
				c = {"door": "+", "bar": "=", "table_round": "o", "table_long": "T", "chair": "h", "bench": "b", "tree": "♣", "hearth": "H", "bed": "B", "stall": "$"}.get(k, k.left(1).to_upper())
			s += c
		s += "\n"
	return s

func _ready() -> void:
	var out_dir := ""
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	var dumps := {}

	print("section towns")
	# --- Towns: every style, every size preset, both seeds.
	for style in MapGenerator.STYLES:
		for size in [[20, 14], [30, 20], [44, 30], [60, 40]]:
			for sd in [3, 41]:
				var m := MapGenerator.generate({"terrain": "town", "style": style, "seed": sd, "w": size[0], "h": size[1], "party": party(4, 3), "taverns": 2})
				var tag := "town/%s/%dx%d/%d" % [style, size[0], size[1], sd]
				print(tag)
				sound(m, tag)
				check(count_type(m, "town") == 1 and m.report.place_name != "" and m.name == m.report.place_name, tag + ": the town has a name and the map takes it (%s)" % m.name)
				if size[0] >= 30:
					check(count_type(m, "tavern") >= 1, tag + ": at least one tavern (%d)" % count_type(m, "tavern"))
					check(count_prop(m, "door") >= 3, tag + ": several buildings with doors")
				if size[0] >= 44:
					check(count_type(m, "temple") == 1, tag + ": a temple")
				check(m.theme == MapGenerator.STYLE_THEMES.town[style], tag + ": theme %s" % m.theme)
				if sd == 3 and size[0] == 44:
					dumps["town_" + style] = m
	var t1 := MapGenerator.generate({"terrain": "town", "seed": 9, "w": 44, "h": 30, "include_monsters": false})
	var t2 := MapGenerator.generate({"terrain": "town", "seed": 9, "w": 44, "h": 30, "include_monsters": false})
	check(t1.cells == t2.cells and str(t1.props) == str(t2.props) and str(t1.labels) == str(t2.labels), "towns are deterministic")
	var tr := MapGenerator.generate({"terrain": "town", "seed": 9, "w": 44, "h": 30, "include_monsters": false, "river": true})
	check(tr.ground.has(MapGenerator.G_PLANK), "a river through town gets plank bridges")
	var t0 := MapGenerator.generate({"terrain": "town", "seed": 9, "w": 44, "h": 30, "include_monsters": false, "taverns": 0})
	check(count_type(t0, "tavern") == 0, "taverns 0: no tavern")
	var tiny := MapGenerator.generate({"terrain": "town", "seed": 2, "w": 12, "h": 8, "include_monsters": false})
	check(tiny.w == 12 and tiny.spawns.size() >= 1, "a tiny town still builds")

	print("section indoors")
	# --- Indoors: plain rooms, a tavern and a temple in every style, small to huge.
	for style in MapGenerator.STYLES:
		for interior in MapGenerator.INTERIORS:
			for size in [[16, 12], [30, 20], [60, 40]]:
				var m := MapGenerator.generate({"terrain": "indoor", "interior": interior, "style": style, "seed": 7, "w": size[0], "h": size[1], "party": party(4, 5)})
				var tag := "indoor/%s/%s/%dx%d" % [interior, style, size[0], size[1]]
				sound(m, tag)
				if interior == "tavern":
					check(count_type(m, "tavern") == 1, tag + ": one tavern")
					var info: Dictionary = m.report.structures[0].info
					check(str(info.name) != "" and m.name == info.name, tag + ": the map is named after the tavern (%s)" % m.name)
					check(not info.features.is_empty() and str(info.proprietor) != "" and str(info.drink) != "" and str(info.rumor) != "", tag + ": tavern details and layout features")
					check(count_prop(m, "bar") >= 2, tag + ": a bar counter")
					if size[0] >= 30:
						check(count_prop(m, "table_round") + count_prop(m, "table_long") >= 3, tag + ": tables")
					if size[0] >= 60:
						check(info.features.any(func(f): return "guest rooms" in f), tag + ": guest rooms in a big hall")
					if size[0] == 30 and style == "human":
						dumps["tavern_human"] = m
				elif interior == "temple":
					check(count_prop(m, "altar") >= 1 and count_prop(m, "pew") >= 2, tag + ": altar and pews")
				else:
					check(m.has("ground") and count_type(m, "tavern") == 0, tag + ": plain rooms get floors but no tavern")
	# Two taverns from different seeds differ in name and layout.
	var names := {}
	for sd in 30:
		var m := MapGenerator.generate({"terrain": "indoor", "interior": "tavern", "seed": sd, "w": 30, "h": 20, "include_monsters": false})
		names[m.name] = true
	check(names.size() >= 24, "30 seeds give at least 24 different tavern names (%d)" % names.size())

	print("section wild")
	# --- Every wilderness structure on every outdoor terrain.
	for terrain in MapGenerator.TERRAINS:
		if MapGenerator.TERRAINS[terrain].layout != "outdoor":
			continue
		for st in MapGenerator.STRUCTURES:
			for sd in [5, 19]:
				var m := MapGenerator.generate({"terrain": terrain, "structures": st, "structure_count": 4, "seed": sd, "w": 30, "h": 20, "party": party(4, 3), "river": sd == 19})
				var tag := "%s/%s/%d" % [terrain, st, sd]
				sound(m, tag)
				match st:
					"inn": check(count_type(m, "tavern") == 1, tag + ": the inn is a tavern")
					"hamlet": check(count_type(m, "tavern") == 1 and count_prop(m, "bed") >= 3, tag + ": hamlet homes and a tavern")
					"crypts": check(count_type(m, "crypt") >= 2, tag + ": crypts (%d)" % count_type(m, "crypt"))
					"cabins": check(count_prop(m, "bed") >= 2, tag + ": cabins with beds")
					"camp": check(count_prop(m, "tent") >= 2 and count_prop(m, "fire") == 1, tag + ": tents round a fire")
					"fort": check(count_type(m, "fort") == 1, tag + ": a fort")
					"tower": check(count_type(m, "tower") == 1, tag + ": a tower")
					"shrine": check(count_type(m, "shrine") + count_type(m, "chapel") == 1, tag + ": a shrine")
					"ruins": check(count_prop(m, "rubble") >= 1, tag + ": rubble in the ruins")
					"none": check(m.report.structures.is_empty(), tag + ": nothing built")
				if terrain == "swamp" and st == "cabins" and sd == 5:
					dumps["swamp_cabins"] = m
				if terrain == "forest" and st == "hamlet" and sd == 5:
					dumps["forest_hamlet"] = m
	var gy := MapGenerator.defaults_for("graveyard")
	check(gy.structures == "crypts" and MapGenerator.defaults_for("forest").structures == "none", "graveyards default to crypts, forests to nothing")
	var habitat_enc := MapGenerator.generate({"terrain": "indoor", "interior": "tavern", "seed": 4, "party": party(4, 3), "difficulty": 1})
	check(habitat_enc.monsters.size() > 0 and habitat_enc.report.encounter.picks.all(func(p): return "town" in EncounterBuilder.habitats_of(Data.monster(p.mid))), "indoors draws from the town habitat")

	print("section names")
	# --- Names and renaming.
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var tn := {}
	for i in 60:
		var nm := TavernGenerator.random_name(rng, ["human", "dwarf", "elf"][i % 3])
		check(nm.strip_edges() != "" and not "%s" in nm, "tavern name '%s'" % nm)
		tn[nm] = true
	check(tn.size() >= 50, "60 tavern names are mostly different (%d)" % tn.size())
	var base := {"terrain": "town", "seed": 9, "w": 44, "h": 30, "include_monsters": false}
	var bm := MapGenerator.generate(base)
	var tav: Array = bm.report.structures.filter(func(s): return s.type == "tavern")
	if not tav.is_empty():
		var gen: String = tav[0].gen_name
		var rn := base.duplicate()
		rn.renames = {gen: "The DM's Own Bar", bm.report.place_name: "Dmtown"}
		var rm := MapGenerator.generate(rn)
		var rt: Array = rm.report.structures.filter(func(s): return s.gen_name == gen)
		check(not rt.is_empty() and rt[0].name == "The DM's Own Bar" and rt[0].info.name == "The DM's Own Bar", "a renamed tavern keeps its new name")
		check(rm.labels.any(func(l): return l.text == "The DM's Own Bar") and not rm.labels.any(func(l): return l.text == gen), "the label shows the new name")
		check(rm.name == "Dmtown", "renaming the town renames the map")
		check(rm.cells == bm.cells, "renaming changes nothing else")

	print("section table")
	# --- On the table: load, snapshot, paint, rename, resize, clear.
	Session.start_offline("DM", 20, 12)
	Session.auto_monsters = false
	var tm := MapGenerator.generate({"terrain": "town", "seed": 9, "w": 44, "h": 30, "include_monsters": false})
	tm.erase("report")
	Session.request({"type": "dm_load_map", "map": tm})
	check(Session.state.ground.size() == 44 * 30 and Session.state.props.size() == tm.props.size() and Session.state.labels.size() == tm.labels.size(), "the map's dressing loads onto the table")
	var snap := Session.map_snapshot()
	check(snap.ground == tm.ground and snap.props.size() == tm.props.size() and snap.labels.size() == tm.labels.size(), "a saved map keeps its dressing")
	Session.request({"type": "dm_label", "i": 0, "text": "Renamed Place"})
	check(Session.state.labels[0].text == "Renamed Place", "the DM renames a place on the table")
	var nl: int = Session.state.labels.size()
	Session.request({"type": "dm_label", "i": 0, "text": ""})
	check(Session.state.labels.size() == nl - 1, "an empty name takes the label off")
	var door: Dictionary = {}
	for p in Session.state.props:
		if p.k == "door":
			door = p
			break
	var np: int = Session.state.props.size()
	Session.request({"type": "dm_cells", "cells": [Vector2i(int(door.x), int(door.y))], "value": EngineBase.WALL})
	check(Session.state.props.size() == np - 1, "painting over a prop removes it")
	Session.request({"type": "dm_resize", "w": 20, "h": 15})
	check(Session.state.ground.size() == 20 * 15 and Session.state.props.all(func(p): return int(p.x) + int(p.get("w", 1)) <= 20 and int(p.y) + int(p.get("h", 1)) <= 15), "resizing trims the dressing")
	Session.request({"type": "dm_clear_map"})
	check(Session.state.props.is_empty() and Session.state.labels.is_empty() and Session.state.ground.is_empty(), "clearing the map clears the dressing")
	var old := {"name": "Old", "w": 10, "h": 8, "cells": [], "spawns": [[1, 1]], "monsters": []}
	Session.request({"type": "dm_load_map", "map": old})
	check(Session.state.props.is_empty() and Session.state.ground.is_empty(), "an old map without dressing loads clean")

	print("section window")
	# --- The generator window.
	var scene = load("res://scenes/battle.tscn").instantiate()
	add_child(scene)
	await get_tree().process_frame
	scene._open_map_generator()
	await get_tree().process_frame
	var gen_p: MapGeneratorPanel = null
	for ch in scene.ui.get_children():
		if ch is MapGeneratorPanel:
			gen_p = ch
	check(gen_p != null, "the generator opens")
	if gen_p:
		gen_p.settings.w = 44
		gen_p.settings.h = 30
		gen_p._set_terrain("town")
		await get_tree().process_frame
		check(gen_p.settings.terrain == "town" and gen_p.result.has("props") and gen_p.places_box.get_child_count() > 1, "town: the named places list fills")
		var sts: Array = gen_p.result.report.structures
		var tv: Array = sts.filter(func(s): return s.type == "tavern")
		if not tv.is_empty():
			gen_p._rename(tv[0], "Panel Pub")
			check(gen_p.result.labels.any(func(l): return l.text == "Panel Pub") and gen_p.settings.renames.has(tv[0].gen_name), "renaming in the window updates the label and remembers it")
			gen_p.regenerate()
			check(gen_p.result.labels.any(func(l): return l.text == "Panel Pub"), "the new name survives regenerating")
		gen_p.settings.style = "dwarf"
		gen_p.regenerate()
		check(gen_p.result.theme == "dwarfhold", "dwarven style: dwarven hold theme")
		gen_p._set_terrain("indoor")
		gen_p.settings.interior = "tavern"
		gen_p.regenerate()
		await get_tree().process_frame
		check(gen_p.place_details.size() == 1, "indoor tavern: details shown")
		gen_p._set_terrain("forest")
		gen_p.settings.structures = "inn"
		gen_p.regenerate()
		check(gen_p.result.report.structures.any(func(s): return s.type == "tavern"), "forest with a roadside inn")
		gen_p._apply()
		await get_tree().process_frame
		check(not Session.state.labels.is_empty(), "applying puts the names on the table")
	scene.queue_free()
	await get_tree().process_frame

	if out_dir != "":
		DirAccess.make_dir_recursive_absolute(out_dir)
		for k in dumps:
			var f := FileAccess.open(out_dir.path_join(k + ".txt"), FileAccess.WRITE)
			var m: Dictionary = dumps[k]
			f.store_string("%s\n%s\n" % [m.name, ascii(m)])
			for st in m.report.structures:
				if st.type == "tavern":
					f.store_string(TavernGenerator.describe(st.info) + "\n\n")
			f.close()
	print("STRUCTURES DONE passed=%d failed=%d" % [passes, fails])
	get_tree().quit(1 if fails > 0 else 0)
