extends Node
## Two-process portrait change over ENet. Run one instance with "-- server" and another with "-- client".
## Mid-game the player picks a template icon and colour: the DM's token, sheet and the player's saved
## character all update. A path-like key and changing someone else's character are both refused.

const PORT := 7799

func _ready() -> void:
	var role := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "server"
	if role == "server":
		await _server()
	else:
		await _client()
	get_tree().quit()

func _server() -> void:
	Session.host("DM", "PortraitTest", PORT, 20, 12)
	var dm_pc := Session.add_character(CharacterStore.premades()[4], 1, Vector2i(2, 2))
	var dm_portrait := str(Session.engine.C(dm_pc).portrait)
	var pc := ""
	for i in 100:
		await get_tree().create_timer(0.1).timeout
		for c in Session.engine.all_combatants():
			if c.kind == "pc" and int(c.owner) != 1:
				pc = c.id
		if pc != "" and str(Session.engine.C(pc).portrait).begins_with("tpl_lute"):
			break
	var c: Dictionary = Session.engine.C(pc)
	var sheet: Dictionary = Session.sheets.get(pc, {})
	var ok: bool = str(c.get("portrait", "")) == "tpl_lute_2e8b57" and str(c.get("color", "")) == "#2e8b57" \
		and str(sheet.get("portrait_template", "")) == "lute" and CharacterStore.portrait_texture(c.portrait) != null \
		and str(Session.engine.C(dm_pc).portrait) == dm_portrait
	print("[server] token portrait: ", c.get("portrait", ""), "  colour: ", c.get("color", ""), "  dm pc untouched: ", str(Session.engine.C(dm_pc).portrait) == dm_portrait)
	print("[server] NET PORTRAIT ", "OK" if ok else "FAIL")
	await get_tree().create_timer(1.5).timeout

func _client() -> void:
	await get_tree().create_timer(0.8).timeout
	var ch: Dictionary = CharacterStore.premades()[2]
	ch.id = CharacterStore.new_id()
	CharacterStore.save_character(ch)
	Session.join("127.0.0.1", PORT, "Alice", ch)
	var mine := ""
	var theirs := ""
	for i in 100:
		await get_tree().create_timer(0.1).timeout
		for c in Session.state.get("combatants", {}).values():
			if c.kind == "pc":
				if int(c.owner) == Session.my_peer():
					mine = c.id
				else:
					theirs = c.id
		if mine != "" and theirs != "":
			break
	# Refused: a key that would escape the portraits folder, and someone else's character.
	var png := PortraitTemplates.render("skull", Color.RED).save_png_to_buffer()
	Session._rpc_set_portrait.rpc_id(1, mine, "../evil", png, "", "#ff0000")
	Session._rpc_set_portrait.rpc_id(1, theirs, "tpl_skull_ff0000", png, "skull", "#ff0000")
	# Accepted: pick the lute in green.
	var key := PortraitTemplates.make_portrait("lute", Color("#2e8b57"))
	Session.set_portrait(mine, key, "lute", "#2e8b57")
	var saved := {}
	for i in 60:
		await get_tree().create_timer(0.1).timeout
		saved = CharacterStore.get_character(ch.id)
		if str(Session.state.combatants.get(mine, {}).get("portrait", "")) == key and str(saved.get("portrait", "")) == key:
			break
	var ok: bool = str(Session.state.combatants[mine].portrait) == key and str(saved.get("portrait", "")) == key \
		and str(saved.get("portrait_template", "")) == "lute" and str(saved.get("color", "")) == "#2e8b57" \
		and not FileAccess.file_exists("user://evil.png") and str(Session.state.combatants[theirs].portrait) != "tpl_skull_ff0000"
	print("[client] saved portrait: ", saved.get("portrait", ""), " template: ", saved.get("portrait_template", ""))
	print("[client] NET PORTRAIT ", "OK" if ok else "FAIL")
	CharacterStore.delete_character(ch.id)
	DirAccess.remove_absolute(CharacterStore.PORTRAIT_DIR + "/" + key + ".png")
	await get_tree().create_timer(0.5).timeout
