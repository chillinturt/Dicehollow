extends Node
## Layout audit: builds every screen (and its tabs, panels and dialogs) at the minimum logical size
## (1600x900; the window stretches with aspect "expand", so the canvas is never smaller) and reports
## any control that runs off the screen, spills out of its parent, or has text clipped away.

var issues := 0
var checked := 0
var verbose := false

func _ready() -> void:
	verbose = "verbose" in OS.get_cmdline_user_args()
	get_window().size = Vector2i(1600, 900)
	await _frames(2)
	print("viewport ", get_viewport().get_visible_rect().size)
	# Premades are added for the audit and removed again afterwards (the player's own characters stay).
	var added: Array = []
	for p in CharacterStore.premades():
		if CharacterStore.list_characters().filter(func(c): return c.name == p.name).is_empty():
			CharacterStore.save_character(p)
			added.append(p.id)
	await _menu()
	await _characters()
	await _battle()
	for id in added:
		CharacterStore.delete_character(id)
	print("LAYOUT DONE screens=%d issues=%d" % [checked, issues])
	get_tree().quit(1 if issues > 0 else 0)

func _frames(n := 3) -> void:
	for i in n:
		await get_tree().process_frame

# ---------------------------------------------------------------- screens

func _menu() -> void:
	var m = load("res://scenes/main_menu.tscn").instantiate()
	add_child(m)
	await _frames()
	await audit(m, "menu/welcome")
	for f in ["_show_host", "_show_join", "_show_solo"]:
		m.call(f)
		await audit(m, "menu/" + f.trim_prefix("_show_"))
	m.queue_free()
	await _frames(1)

func _characters() -> void:
	var ce = load("res://scenes/characters.tscn").instantiate()
	add_child(ce)
	await _frames()
	for i in ce.chars.size():
		ce.list_box.select(i)
		ce._on_pick(i)
		for t in ce.tabs.get_tab_count():
			ce.tabs.current_tab = t
			await audit(ce, "characters/%s/%s" % [ce.chars[i].name, ce.tabs.get_tab_title(t)])
	ce._new_char()
	for t in ce.tabs.get_tab_count():
		ce.tabs.current_tab = t
		await audit(ce, "characters/new/%s" % ce.tabs.get_tab_title(t))
	# Dialogs opened from the builder.
	if ce.has_method("_open_level_up"):
		ce.list_box.select(0)
		ce._on_pick(0)
		await _dialogs_from(ce, ce, "characters")
	ce.queue_free()
	await _frames(1)

func _battle() -> void:
	Session.start_offline("Tester", 26, 18)
	var y := 4
	for ch in CharacterStore.premades():
		Session.add_character(ch, 1, Vector2i(4 + (y % 2), y))
		y += 2
	for mid in ["goblin", "goblin", "hobgoblin", "orc", "mage", "young_red_dragon"]:
		Session.add_monster(mid, Vector2i(17 + (y % 3), y - 8))
		y += 2
	Session.auto_monsters = false
	var b = load("res://scenes/battle.tscn").instantiate()
	add_child(b)
	await _frames()
	for t in b.dm_tabs.get_tab_count():
		b.dm_tabs.current_tab = t
		await audit(b.ui, "battle/setup/dm-" + b.dm_tabs.get_tab_title(t), b)
	b.dm_tabs.current_tab = 0
	Session.request({"type": "dm_start_combat"})
	await _frames()
	for c in Session.state.combatants.values():
		b.control_cid = c.id
		b.selected_cid = c.id
		b.selected_ids = []
		# Make the card as busy as it gets: conditions, concentration, dying.
		b._refresh_ui()
		await audit(b.ui, "battle/combat/" + str(c.name), b)
	# A battered PC with lots of effects.
	var pc: Dictionary = Session.state.combatants.values().filter(func(o): return o.kind == "pc")[0]
	for cond in ["poisoned", "frightened", "restrained", "prone", "blinded"]:
		Session.request({"type": "dm_condition", "cid": pc.id, "cond": cond})
	Session.request({"type": "dm_exhaustion", "cid": pc.id, "delta": 1})
	b.control_cid = pc.id
	b.selected_cid = pc.id
	b._refresh_ui()
	await audit(b.ui, "battle/combat/conditions", b)
	b._select_team("enemy")
	await audit(b.ui, "battle/combat/multi-select", b)
	# Targeting mode label.
	b.selected_ids = []
	for a in Session.engine.get_actions(pc):
		if a.kind == "weapon" and a.enabled:
			b.control_cid = pc.id
			b._on_action_pressed(a)
			break
	await audit(b.ui, "battle/combat/targeting", b)
	b._cancel_mode()
	# Panels opened over the map.
	b._open_map_generator()
	await audit(b.ui, "battle/map-generator", b)
	for n in b.ui.get_children():
		if n is MapGeneratorPanel:
			n.close()
	b._open_monster_editor({})
	await audit(b.ui, "battle/monster-editor", b)
	for n in b.ui.get_children():
		if n is MonsterEditor:
			n.queue_free()
	await _frames(1)
	if b.has_method("_open_sheet"):
		await _dialogs_from(b, b.ui, "battle")
	Session.request({"type": "dm_end_combat"})
	await _frames()
	b.queue_free()
	Session.leave()
	await _frames(1)

## The character sheet, level plan, history and level-up wizard (every step) for each premade.
func _dialogs_from(owner: Node, ui_root: Control, tag: String) -> void:
	if tag == "battle":
		for c in Session.state.combatants.values():
			if c.kind != "pc":
				continue
			var w = owner._open_sheet(c.id)
			for t in w.tabs.get_tab_count():
				w.tabs.current_tab = t
				await audit(ui_root, "%s/sheet/%s/%s" % [tag, c.name, w.tabs.get_tab_title(t)], owner)
			w.close()
			await _frames(1)
		# Portrait picker (first PC is enough: the layout doesn't depend on the character).
		for c in Session.state.combatants.values():
			if c.kind == "pc":
				var pw = owner._open_portrait_picker(c.id)
				await audit(ui_root, "%s/portrait/%s" % [tag, c.name], owner)
				pw.close()
				await _frames(1)
				break
		# Level-up wizard for every PC, walking every step.
		for c in Session.state.combatants.values():
			if c.kind != "pc":
				continue
			var lw = owner._open_level_up(c.id, true)
			await _walk_wizard(lw, ui_root, "%s/level-up/%s" % [tag, c.name], owner)
	else:
		for i in owner.chars.size():
			owner.list_box.select(i)
			owner._on_pick(i)
			var lw = owner._open_level_up()
			await _walk_wizard(lw, ui_root, "%s/level-up/%s" % [tag, owner.chars[i].name], owner)
		# Multiclass path from the first character.
		owner.list_box.select(0)
		owner._on_pick(0)
		var mw = owner._open_level_up()
		var other := ""
		for cid in Data.classes:
			if Rules.class_level(owner.ch, cid) == 0:
				other = cid
				break
		mw.allow_unmet = true
		mw.pick_class(other)
		await _walk_wizard(mw, ui_root, "%s/level-up/multiclass-%s" % [tag, other], owner)

func _walk_wizard(lw, ui_root: Control, label: String, owner: Node) -> void:
	var guard := 0
	while is_instance_valid(lw) and guard < 14:
		await audit(ui_root, "%s/%s" % [label, lw.step_name()], owner)
		if lw.is_last_step():
			break
		lw.next_step(true)
		guard += 1
	if is_instance_valid(lw):
		lw.close()
	await _frames(1)

# ---------------------------------------------------------------- the audit

func audit(root: Control, label: String, battle: Node = null) -> void:
	await _frames(3)
	checked += 1
	var found: Array = []
	var vp: Rect2 = get_viewport().get_visible_rect()
	_walk(root, vp, false, false, found)
	if battle != null and "ui" in battle:
		_hud_overlaps(battle, found)
	if found.is_empty():
		if verbose:
			print("ok   ", label)
		return
	print("FAIL ", label)
	for f in found:
		print("     - ", f)
	issues += found.size()

func _desc(n: Node) -> String:
	var s := n.get_class()
	if n is Label or n is Button:
		s += " \"%s\"" % str(n.text).left(40).replace("\n", " ")
	elif n is RichTextLabel:
		s += " \"%s\"" % n.get_parsed_text().left(40).replace("\n", " ")
	var p := n.get_parent()
	var chain: PackedStringArray = []
	var k := 0
	while p != null and k < 3:
		chain.append(p.get_class() + ("(" + p.name + ")" if not str(p.name).begins_with("@") else ""))
		p = p.get_parent()
		k += 1
	return s + "  in " + " < ".join(chain)

func _walk(n: Node, vp: Rect2, scrolled: bool, reported: bool, found: Array) -> void:
	if n is Control:
		var c := n as Control
		if not c.is_visible_in_tree():
			return
		var r := c.get_global_rect()
		if r.size.x > 0.5 and r.size.y > 0.5:
			if not scrolled and not reported and not _inside(r, vp):
				found.append("off-screen %s  rect=%s  culprit: %s" % [_desc(c), _rs(r), _culprit(c)])
				reported = true
			var p := c.get_parent() as Control
			if p != null and not p is ScrollContainer and p.is_visible_in_tree() and not c.top_level:
				var pr := p.get_global_rect()
				if not _inside(r, pr) and not (p is TabContainer and r.position.y < pr.position.y):
					if not reported:
						found.append("overflows parent %s  rect=%s parent=%s  culprit: %s" % [_desc(c), _rs(r), _rs(pr), _culprit(c)])
					reported = true
			if c is RichTextLabel and not c.scroll_active and not c.fit_content:
				if c.get_content_height() > c.size.y + 2:
					found.append("clipped text %s  content=%d box=%d" % [_desc(c), c.get_content_height(), int(c.size.y)])
			if c is Label and (c.clip_text or c.text_overrun_behavior != TextServer.OVERRUN_NO_TRIMMING) and c.autowrap_mode == TextServer.AUTOWRAP_OFF:
				var font: Font = c.get_theme_font("font")
				var fs: int = c.get_theme_font_size("font_size")
				var w := font.get_string_size(c.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				if w > c.size.x + 2:
					found.append("truncated label %s  text=%d box=%d" % [_desc(c), int(w), int(c.size.x)])
		if c is ScrollContainer:
			scrolled = true
	for ch in n.get_children():
		_walk(ch, vp, scrolled, reported, found)

## Follows the widest (or tallest) child down to whatever is forcing the size.
func _culprit(c: Control) -> String:
	var out: PackedStringArray = []
	var cur: Control = c
	for depth in 12:
		var best: Control = null
		var bm := Vector2.ZERO
		for ch in cur.get_children():
			if ch is Control and ch.visible and not ch.top_level:
				var m: Vector2 = ch.get_combined_minimum_size()
				if best == null or m.x + m.y > bm.x + bm.y:
					best = ch
					bm = m
		if best == null:
			break
		var d := best.get_class()
		if best is Label or best is Button:
			d += " \"%s\"" % str(best.text).left(50).replace("
", " ")
		out.append("%s min=%dx%d" % [d, bm.x, bm.y])
		cur = best
	return " > ".join(out)

## The fixed HUD panels on the battle screen must not cover one another.
func _hud_overlaps(b: Node, found: Array) -> void:
	var panels: Array = []
	for ch in b.ui.get_children():
		if ch is Control and ch.is_visible_in_tree() and (ch is PanelContainer or ch is TabContainer or ch is BoxContainer) and ch != b.tip and ch != b.banner:
			if ch.get_global_rect().size.x > 1:
				panels.append(ch)
	for i in panels.size():
		for j in range(i + 1, panels.size()):
			var a: Rect2 = panels[i].get_global_rect().grow(-1)
			var c: Rect2 = panels[j].get_global_rect().grow(-1)
			# Dialogs float above the HUD on purpose.
			if _floating(panels[i]) or _floating(panels[j]):
				continue
			if a.intersects(c):
				found.append("HUD overlap %s %s  with  %s %s" % [_desc(panels[i]), _rs(a), _desc(panels[j]), _rs(c)])

func _floating(c: Control) -> bool:
	return c is MonsterEditor or c is MapGeneratorPanel or c.has_meta("dialog")

func _inside(r: Rect2, outer: Rect2) -> bool:
	return r.position.x >= outer.position.x - 1.5 and r.position.y >= outer.position.y - 1.5 \
		and r.end.x <= outer.end.x + 1.5 and r.end.y <= outer.end.y + 1.5

func _rs(r: Rect2) -> String:
	return "(%d,%d %dx%d)" % [r.position.x, r.position.y, r.size.x, r.size.y]
