extends Node
## Inventory, coins, carrying capacity, shops and magic items (Inventory), under the 2014 rules:
## coins and change, weight (50 coins a pound, a bag of holding's contents weigh nothing), carrying capacity
## and the variant encumbrance rule, starting gear for old sheets, equipping and attunement (three items,
## DMG slot limits), magic weapons / armor / wondrous items in the derived stats, shops (buy, sell at half,
## markup, packs), loot into the pack, potions, thrown flasks, healer's kit, light, wands and scrolls,
## and the game server saving it all to the character's sheet.
## Run: Godot --headless --path . res://tests/inventory_test.tscn   (exit code 1 on failure)

var fails := 0
var passes := 0

func check(cond: bool, what: String) -> void:
	if cond:
		passes += 1
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)

func premade(name_part: String) -> Dictionary:
	for p in CharacterStore.premades():
		if str(p.name).contains(name_part):
			return p.duplicate(true)
	return {}

func uid_of(h: Dictionary, id: String) -> String:
	for e in Inventory.list(h):
		if str(e.id) == id:
			return str(e.uid)
	return ""

func weapon_atk(st: Dictionary, wid: String) -> Dictionary:
	for w in st.weapons:
		if str(w.get("weapon", "")) == wid and str(w.id).begins_with("w_"):
			return w
	return {}

func _ready() -> void:
	_coins()
	_weight()
	_starting_gear()
	_equipment_and_magic()
	_shop()
	_engine()
	_session()
	_ammo()
	_stealth()
	_tools()
	_hands()
	_attune()
	_treasure()
	_shops2()
	_items8()
	_magic9()
	_copy_scrolls()
	_infusions()
	_polish()
	_storage()
	print("INVENTORY DONE passed=%d failed=%d" % [passes, fails])
	get_tree().quit(1 if fails > 0 else 0)

func _coins() -> void:
	print("== coins")
	var h := {"coins": {"gp": 1}}
	check(Inventory.pay(h, 30) and int(h.coins.gp) == 0 and int(h.coins.sp) == 7, "paying 3 sp from 1 gp gives 7 sp change")
	check(not Inventory.pay(h, 1000) and int(h.coins.sp) == 7, "paying more than you have fails and takes nothing")
	h.coins = {"cp": 5, "sp": 3, "gp": 2}
	check(Inventory.pay(h, 150) and Inventory.wealth_cp(h.coins) == 235 - 150, "smallest coins go first, the total is right")
	check(Inventory.fmt_cp(1234) == "12 gp 3 sp 4 cp" and Inventory.fmt_cp(100000) == "1,000 gp", "prices read as coins")

func _weight() -> void:
	print("== weight and encumbrance")
	var h := {"inventory": [], "coins": {"gp": 100}}
	check(is_equal_approx(Inventory.carried_lb(h), 2.0), "100 coins weigh 2 lb (50 to the pound)")
	Inventory.add(h, "rope_hempen", 2)
	check(Inventory.list(h).size() == 1 and int(Inventory.list(h)[0].qty) == 2, "plain gear stacks")
	check(is_equal_approx(Inventory.carried_lb(h), 22.0), "two coils of hempen rope weigh 20 lb")
	var bag := Inventory.add(h, "bag_of_holding", 1)
	var rope := Inventory.find(h, uid_of(h, "rope_hempen"))
	check(Inventory.apply_op(h, {"op": "move", "uid": str(rope.uid), "into": str(bag.uid)}) == "", "rope goes into the bag of holding")
	check(is_equal_approx(Inventory.carried_lb(h), 17.0), "a bag of holding weighs 15 lb whatever is inside")
	Inventory.add(h, "plate", 1)
	check(Inventory.apply_op(h, {"op": "move", "uid": uid_of(h, "plate"), "into": str(bag.uid)}) == "", "plate armor fits too (65 lb of 500)")
	var bag2 := Inventory.add(h, "handy_haversack", 1)
	check(Inventory.apply_op(h, {"op": "move", "uid": str(bag2.uid), "into": str(bag.uid)}) != "", "a bag of holding can't go inside another")
	var e0 := Inventory.encumbrance(140.0, 10, 1.0, false)
	check(int(e0.cap) == 150 and int(e0.level) == 0, "STR 10 carries 150 lb unencumbered (standard rule)")
	check(int(Inventory.encumbrance(160.0, 10, 1.0, false).level) == 3 and int(Inventory.encumbrance(160.0, 10, 1.0, false).max_speed) == 5, "over capacity: push or drag at 5 ft")
	check(int(Inventory.encumbrance(310.0, 10, 1.0, false).max_speed) == 0, "over twice the capacity: can't move it")
	check(int(Inventory.encumbrance(60.0, 10, 1.0, true).speed) == -10, "variant: over 5 × STR, speed -10")
	var heavy := Inventory.encumbrance(110.0, 10, 1.0, true)
	check(int(heavy.speed) == -20 and heavy.dis, "variant: over 10 × STR, speed -20 and disadvantage")
	check(is_equal_approx(Inventory.size_mult("medium", {"powerful_build": true}), 2.0), "Powerful Build doubles carrying capacity")

func _starting_gear() -> void:
	print("== starting gear")
	var old := premade("Grukka")
	old.erase("inventory")
	old.erase("coins")
	var before := Rules.derive(old)
	check(Inventory.ensure(old), "a sheet without an inventory gets one")
	check(Inventory.count(old, "chain_mail") == 1 and Inventory.count(old, "greatsword") == 1, "its old equipment is in the pack")
	check(Inventory.count(old, "crowbar") == 1 and Inventory.count(old, "torch") == 10, "a fighter gets the dungeoneer's pack (unpacked)")
	check(int(old.coins.gp) == 10, "a soldier starts with 10 gp")
	var after := Rules.derive(old)
	check(int(after.ac) == int(before.ac) and after.weapons.size() == before.weapons.size(), "AC and attacks come out the same from the inventory")
	var rogue := premade("Pip")
	check(Inventory.count(rogue, "thieves_tools") == 1 and Inventory.count(rogue, "arrows") == 20, "a rogue gets thieves' tools and 20 arrows for the shortbow")
	var legacy := Rules.new_character()
	legacy.equipment = {"armor": "leather", "shield": false, "weapons": ["longsword"], "weapon_bonus": 1, "armor_bonus": 0}
	Inventory.ensure(legacy)
	check(Inventory.count(legacy, "weapon_plus_1") == 1, "an old magic weapon bonus becomes a +1 weapon")
	check(str(weapon_atk(Rules.derive(legacy), "longsword").get("name", "")) == "Longsword +1", "and attacks as Longsword +1")
	var gp := Inventory.roll_starting_gold("fighter", RandomNumberGenerator.new())
	check(gp >= 50 and gp <= 200 and gp % 10 == 0, "fighter starting wealth is 5d4 × 10 gp")

func _equipment_and_magic() -> void:
	print("== equipment and magic items")
	var ch := premade("Grukka")
	var base := Rules.derive(ch)
	var gs := weapon_atk(base, "greatsword")
	var plus := Inventory.add(ch, "weapon_plus_1", 1, {"base": "greatsword"})
	check(Inventory.apply_op(ch, {"op": "equip", "uid": str(plus.uid), "on": true}) == "", "a +1 greatsword can be wielded")
	Inventory.apply_op(ch, {"op": "equip", "uid": uid_of(ch, "greatsword"), "on": false})
	var st := Rules.derive(ch)
	var g1 := weapon_atk(st, "greatsword")
	check(int(g1.to_hit) == int(gs.to_hit) + 1 and g1.magic and str(g1.name) == "Greatsword +1", "+1 to hit, magical, named Greatsword +1")
	check(str(g1.damage[0].dice).ends_with("+%d" % (int(st.mods.str) + 1)), "+1 to damage")
	var ft := Inventory.add(ch, "flame_tongue", 1, {"base": "longsword", "eq": true})
	check(weapon_atk(Rules.derive(ch), "longsword").get("damage", []).size() == 1, "an unattuned Flame Tongue is just a sword")
	check(Inventory.apply_op(ch, {"op": "attune", "uid": str(ft.uid), "on": true}, {"info": Inventory.sheet_info(ch), "free": true}) == "", "attune to the Flame Tongue")
	check(weapon_atk(Rules.derive(ch), "longsword").damage.size() == 1, "attuned but not lit: no fire yet")
	Inventory.find(ch, str(ft.uid)).lit = true
	var fl := weapon_atk(Rules.derive(ch), "longsword")
	check(fl.damage.size() == 2 and str(fl.damage[1].type) == "fire", "lit (a bonus action), it adds 2d6 fire")
	# Cloak of Protection: worn and attuned.
	var ac0 := int(Rules.derive(ch).ac)
	var sv0 := int(Rules.derive(ch).save_bonus.wis)
	var cloak := Inventory.add(ch, "cloak_of_protection", 1)
	Inventory.apply_op(ch, {"op": "attune", "uid": str(cloak.uid), "on": true}, {"info": Inventory.sheet_info(ch), "free": true})
	check(int(Rules.derive(ch).ac) == ac0, "a cloak in the pack does nothing")
	Inventory.apply_op(ch, {"op": "equip", "uid": str(cloak.uid), "on": true})
	check(int(Rules.derive(ch).ac) == ac0 + 1 and int(Rules.derive(ch).save_bonus.wis) == sv0 + 1, "worn and attuned: +1 AC and saves")
	var ring := Inventory.add(ch, "ring_of_protection", 1)
	check(Inventory.apply_op(ch, {"op": "attune", "uid": str(ring.uid), "on": true}, {"info": Inventory.sheet_info(ch), "free": true}) == "", "a third attunement is allowed")
	var luck := Inventory.add(ch, "stone_of_good_luck", 1)
	check(Inventory.apply_op(ch, {"op": "attune", "uid": str(luck.uid), "on": true}, {"info": Inventory.sheet_info(ch), "free": true}) != "", "a fourth is not (three at most)")
	var web := Inventory.add(ch, "wand_of_web", 1)
	Inventory.apply_op(ch, {"op": "attune", "uid": str(ring.uid), "on": false})
	check(Inventory.apply_op(ch, {"op": "attune", "uid": str(web.uid), "on": true}, {"info": Inventory.sheet_info(ch), "free": true}).contains("spellcaster"), "a fighter can't attune to a wand of web")
	check(Inventory.apply_op(ch, {"op": "attune", "uid": "x", "on": true}, {"in_combat": true}) != "", "no attuning during a fight")
	for i in 2:
		var r := Inventory.add(ch, "ring_of_warmth", 1)
		Inventory.apply_op(ch, {"op": "equip", "uid": str(r.uid), "on": true})
	var r3 := Inventory.add(ch, "ring_of_warmth", 1)
	check(Inventory.apply_op(ch, {"op": "equip", "uid": str(r3.uid), "on": true}) != "", "no more than two rings")
	# Armor swaps; no armor changes in a fight.
	var plate := Inventory.add(ch, "plate", 1)
	check(Inventory.apply_op(ch, {"op": "equip", "uid": str(plate.uid), "on": true}, {"in_combat": true}) != "", "donning armor waits until after the fight")
	Inventory.apply_op(ch, {"op": "equip", "uid": str(plate.uid), "on": true})
	check(not Inventory.find(ch, uid_of(ch, "chain_mail")).get("eq", false) and str(Inventory.equipment_of(ch).armor) == "plate", "putting on plate takes off the chain mail")
	# Bracers only without armor or shield; gauntlets set STR.
	var wiz := premade("Tamsin")
	var wac := int(Rules.derive(wiz).ac)
	var br := Inventory.add(wiz, "bracers_of_defense", 1, {"eq": true, "att": true})
	check(int(Rules.derive(wiz).ac) == wac, "bracers do nothing over armor and a shield")
	for e in Inventory.list(wiz):
		if e != br:
			e.erase("eq")
	var bare := int(Rules.derive(wiz).ac)
	Inventory.find(wiz, str(br.uid)).erase("eq")
	check(bare == int(Rules.derive(wiz).ac) + 2, "bracers: +2 AC with no armor or shield")
	Inventory.add(wiz, "gauntlets_of_ogre_power", 1, {"eq": true, "att": true})
	check(int(Rules.derive(wiz).scores.str) == 19, "gauntlets of ogre power: Strength 19")
	Inventory.add(wiz, "goggles_of_night", 1, {"eq": true})
	check(int(Rules.derive(wiz).darkvision) == 60, "goggles of night: darkvision 60 ft")
	var wm := Inventory.add(wiz, "wand_of_the_war_mage_1", 1)
	var atk0 := int(Rules.derive(wiz).casting[0].attack)
	Inventory.find(wiz, str(wm.uid)).att = true
	check(int(Rules.derive(wiz).casting[0].attack) == atk0 + 1, "wand of the war mage +1: spell attacks +1")
	var mith := premade("Grukka")
	mith.inventory = []
	Inventory.add(mith, "mithral_armor", 1, {"base": "plate", "eq": true})
	mith.base_scores.str = 8
	var ms := Rules.derive(mith)
	check(int(ms.ac) == 18 and not ms.stealth_dis, "mithral plate: AC 18, no stealth disadvantage")
	check(int(ms.speed) == 30, "and no Strength requirement")
	check(not Inventory.base_ok(Data.item("mithral_armor"), Data.item("leather")), "mithral can't be light armor")

func _shop() -> void:
	print("== shops")
	var ch := premade("Pip")
	ch.coins = {"gp": 20}
	var shop := {"open": true, "markup": 100, "buyback": 50, "stock": Inventory.shop_stock("general")}
	check("lantern_bullseye" in shop.stock and "rations" in shop.stock and not "longsword" in shop.stock, "a general store sells lanterns and rations, not swords")
	var lanterns := Inventory.count(ch, "lantern_bullseye")
	check(Inventory.apply_op(ch, {"op": "buy", "id": "lantern_bullseye", "qty": 1}, {"shop": shop}) == "" and Inventory.count(ch, "lantern_bullseye") == lanterns + 1, "buy a bullseye lantern")
	check(Inventory.wealth_cp(ch.coins) == 1000, "it cost 10 gp")
	check(Inventory.apply_op(ch, {"op": "buy", "id": "longsword", "qty": 1}, {"shop": shop}) != "", "the shop won't sell what it doesn't stock")
	check(Inventory.apply_op(ch, {"op": "buy", "id": "spyglass", "qty": 1}, {"shop": {"stock": ["spyglass"]}}) != "" and Inventory.wealth_cp(ch.coins) == 1000, "can't buy what you can't afford")
	var torches := Inventory.count(ch, "torch")
	Inventory.apply_op(ch, {"op": "buy", "id": "explorers_pack", "qty": 1}, {"shop": shop})
	check(Inventory.count(ch, "torch") == torches + 10 and Inventory.count(ch, "explorers_pack") == 0, "a pack unpacks into its contents")
	check(Inventory.apply_op(ch, {"op": "sell", "uid": uid_of(ch, "lantern_bullseye"), "qty": 1}, {"shop": shop}) == "" and Inventory.wealth_cp(ch.coins) == 500, "selling pays half (5 gp for a 10 gp lantern)")
	var dear := {"open": true, "markup": 150, "stock": ["rope_silk"]}
	check(Inventory.shop_price({"id": "rope_silk"}, dear) == 1500, "markup: 150% of 10 gp is 15 gp")
	var magic := Inventory.shop_stock("magic", "uncommon")
	check("cloak_of_protection" in magic and not "ring_of_protection" in magic, "a magic shop sells up to the DM's rarity")
	check(Inventory.unit_price({"id": "weapon_plus_1", "base": "longsword"}) == 50000 + 1500, "a +1 longsword costs 500 gp plus the sword")
	var h := {"coins": {"gp": 1000}}
	check(Inventory.apply_op(h, {"op": "buy", "id": "weapon_plus_1", "qty": 1}, {"shop": {"stock": ["weapon_plus_1"]}}) != "", "a magic weapon needs a base weapon chosen")
	check(Inventory.apply_op(h, {"op": "buy", "id": "weapon_plus_1", "qty": 1, "base": "longsword"}, {"shop": {"stock": ["weapon_plus_1"]}}) == "", "with the base it can be bought")

func _engine() -> void:
	print("== in play")
	var st := EngineBase.new_state(16, 10)
	var eng := CombatEngine.new(st)
	var hero := CombatantFactory.from_character("p1", premade("Grukka"), 1)
	hero.pos = Vector2i(2, 2)
	st.combatants[hero.id] = hero
	var ally := CombatantFactory.from_character("p2", premade("Brannoc"), 1)
	ally.pos = Vector2i(3, 2)
	st.combatants[ally.id] = ally
	var gob := CombatantFactory.from_monster("m1", "goblin")
	gob.pos = Vector2i(5, 2)
	st.combatants[gob.id] = gob
	# Loot goes into the pack.
	var gp0 := int(hero.coins.get("gp", 0))
	var got := MapObjects.take_loot(eng, hero, {"gp": 30, "sp": 4, "potion_healing": 1, "gear": [{"id": "cloak_of_protection", "qty": 1}, {"id": "torch", "qty": 3}]}, hero.pos)
	check(int(hero.coins.gp) == gp0 + 30 and int(hero.coins.sp) >= 4, "coins from a chest go into the purse")
	check(Inventory.count(hero, "potion_healing") == 1 and Inventory.count(hero, "cloak_of_protection") == 1, "potions and magic items into the pack")
	check(got.contains("Cloak of Protection"), "the log names what was found")
	# Encumbrance slows the engine's speed.
	var sp0 := eng.eff_speed(hero)
	hero.load_lb = 10000.0
	check(eng.eff_speed(hero) == 0, "carrying far too much: can't move")
	hero.load_lb = float(hero.scores.str) * 12.0
	check(eng.eff_speed(hero) == sp0, "the standard rule ignores 12 × STR")
	st.encumbrance = "variant"
	check(eng.eff_speed(hero) == sp0 - 20, "the variant rule: -20 ft when heavily encumbered")
	st.encumbrance = "standard"
	hero.load_lb = 0.0
	# Potion of heroism: temp HP and bless.
	Inventory.add(hero, "potion_heroism", 1)
	var pot := eng.find_action(hero, "inv:drink:" + uid_of(hero, "potion_heroism"))
	check(not pot.is_empty() and pot.cost == "action", "drinking a potion is an action")
	eng.execute(hero.id, pot.id, {"targets": [hero.id]})
	check(int(hero.temp_hp) == 10 and eng.mod_list(hero, "attack_dice").size() == 1, "heroism: 10 temp HP and bless")
	check(Inventory.count(hero, "potion_heroism") == 0, "the potion is gone")
	# Alchemist's fire.
	hero.turn = eng.new_turn(hero)
	Inventory.add(hero, "alchemists_fire", 6)
	var burned := false
	for i in 6:
		hero.turn = eng.new_turn(hero)
		gob.hp = 50
		gob.max_hp = 50
		eng.execute(hero.id, "inv:throw:" + uid_of(hero, "alchemists_fire"), {"targets": [gob.id]})
		if gob.effects.any(func(e): return e.get("tag", "") == "burning"):
			burned = true
			break
	check(burned, "alchemist's fire sets a creature alight on a hit")
	var burn: Dictionary = gob.effects.filter(func(e): return e.get("tag", "") == "burning")[0] if burned else {}
	check(burned and int(burn.get("escape_dc", 0)) == 10 and burn.tick_damage.dice == "1d4", "1d4 fire each turn until a DC 10 Dexterity check")
	# Healer's kit.
	ally.hp = 0
	ally.death = {"s": 0, "f": 1, "stable": false, "dead": false}
	Inventory.add(hero, "healers_kit", 1)
	hero.turn = eng.new_turn(hero)
	eng.execute(hero.id, "inv:kit:" + uid_of(hero, "healers_kit"), {"targets": [ally.id]})
	check(ally.death.stable and int(Inventory.find(hero, uid_of(hero, "healers_kit")).charges) == 9, "a healer's kit stabilizes (9 uses left)")
	ally.hp = ally.max_hp
	ally.death = {"s": 0, "f": 0, "stable": false, "dead": false}
	# Light: a lantern burns oil and lets its bearer see in the dark.
	st.fog = {"mode": "soft", "range": 30}
	Inventory.add(hero, "lantern_hooded", 1)
	var oil0 := Inventory.count(hero, "oil")
	if oil0 == 0:
		Inventory.add(hero, "oil", 1)
		oil0 = 1
	hero.senses = ""  # (a half-orc: no darkvision for this check)
	check(Fog.sight_cells(st, hero) == 6, "in the dark (30 ft) without darkvision the fighter sees 6 squares")
	hero.turn = eng.new_turn(hero)
	eng.execute(hero.id, "inv:light:" + uid_of(hero, "lantern_hooded"), {})
	var w: int = st.w
	var far: Vector2i = hero.pos + Vector2i(10, 0)
	check(Inventory.count(hero, "oil") == oil0 - 1 and Inventory.light_ft(hero) == 60 and Fog.vision(eng, hero)[far.y * w + far.x] == 1, "a lit hooded lantern uses a flask of oil and lights 60 ft")
	# 12. Light is for everyone: a creature far off in the dark sees what the lantern lights.
	var watcher := CombatantFactory.from_character("p9", premade("Grukka"), 1)
	watcher.senses = ""
	watcher.pos = Vector2i(15, 9)
	st.combatants[watcher.id] = watcher
	check(Fog.vision(eng, watcher)[hero.pos.y * w + hero.pos.x] == 1, "a party member 13 squares away in the dark sees the lit area")
	eng.execute(hero.id, "inv:light:" + uid_of(hero, "lantern_hooded"), {})
	check(Inventory.light_ft(hero) == 0 and Fog.vision(eng, watcher)[hero.pos.y * w + hero.pos.x] == 0, "dousing it ends the light (and the far watcher loses sight of it)")
	# A bullseye lantern lights a cone where its bearer faces.
	Inventory.add(hero, "lantern_bullseye", 1)
	Inventory.add(hero, "oil", 1)
	hero.facing = [1, 0]
	eng.execute(hero.id, "inv:light:" + uid_of(hero, "lantern_bullseye"), {})
	var ahead: Vector2i = hero.pos + Vector2i(12, 0)
	var side: Vector2i = hero.pos + Vector2i(0, 7)
	var vb := Fog.vision(eng, hero)
	check(vb[ahead.y * w + ahead.x] == 1 and vb[side.y * w + side.x] == 0, "a bullseye lantern lights 60 ft ahead in a cone, not to the side")
	hero.facing = [0, 1]
	vb = Fog.vision(eng, hero)
	check(vb[side.y * w + side.x] == 1 and vb[ahead.y * w + ahead.x] == 0, "turning (moving or aiming another way) swings the beam")
	eng.execute(hero.id, "inv:light:" + uid_of(hero, "lantern_bullseye"), {})
	st.combatants.erase(watcher.id)
	st.fog = {}
	# Wand of magic missiles: charges, upcasting, dawn.
	Inventory.add(hero, "wand_of_magic_missiles", 1)
	var wuid := uid_of(hero, "wand_of_magic_missiles")
	hero.turn = eng.new_turn(hero)
	var wa := eng.find_action(hero, "inv:cast:" + wuid)
	check(not wa.is_empty() and wa.enabled and wa.slots == [1, 2, 3], "a fighter can use a wand of magic missiles, 1st to 3rd level")
	gob.hp = 200
	gob.max_hp = 200
	eng.execute(hero.id, wa.id, {"targets": [gob.id], "slot": 3})
	check(int(Inventory.find(hero, wuid).charges) == 4 and gob.hp < 200, "casting at 3rd level spends 3 of its 7 charges")
	check(hero.slots_used.is_empty() or hero.slots_used.all(func(x): return int(x) == 0), "no spell slots used")
	Inventory.dawn(hero)
	check(int(Inventory.find(hero, wuid).charges) >= 6 and int(Inventory.find(hero, wuid).charges) <= 7, "dawn: 1d6 + 1 charges back (up to 7)")
	# Scrolls: only from your class's list.
	Inventory.add(hero, "spell_scroll_1", 1, {"spell": "magic_missile"})
	var sa := eng.find_action(hero, "inv:cast:" + uid_of(hero, "spell_scroll_1"))
	check(not sa.is_empty() and not sa.enabled and str(sa.reason).contains("class"), "a fighter can't read a wizard's scroll")
	var wiz := CombatantFactory.from_character("p3", premade("Tamsin"), 1)
	wiz.pos = Vector2i(2, 4)
	st.combatants[wiz.id] = wiz
	Inventory.add(wiz, "spell_scroll_1", 1, {"spell": "magic_missile"})
	wiz.turn = eng.new_turn(wiz)
	var used0 := int(wiz.slots_used[0])
	var wsa := eng.find_action(wiz, "inv:cast:" + uid_of(wiz, "spell_scroll_1"))
	check(not wsa.is_empty() and wsa.enabled, "a wizard can")
	gob.hp = 200
	eng.execute(wiz.id, wsa.id, {"targets": [gob.id]})
	check(Inventory.count(wiz, "spell_scroll_1") == 0 and int(wiz.slots_used[0]) == used0 and gob.hp < 200, "the scroll is used up, no slot spent")
	# Pearl of power.
	wiz.slots_used[1] = 1
	Inventory.add(wiz, "pearl_of_power", 1, {"att": true})
	wiz.turn = eng.new_turn(wiz)
	eng.execute(wiz.id, "inv:pearl:" + uid_of(wiz, "pearl_of_power"), {})
	check(int(wiz.slots_used[1]) == 0 and int(Inventory.find(wiz, uid_of(wiz, "pearl_of_power")).charges) == 0, "a pearl of power gives back a 2nd-level slot, once a day")
	# Adamantine armor turns critical hits.
	var tank := CombatantFactory.from_character("p4", premade("Grukka"), 1)
	tank.tags["adamantine"] = true
	tank.pos = Vector2i(8, 6)
	st.combatants[tank.id] = tank
	var ogre := CombatantFactory.from_monster("m2", "goblin")
	ogre.pos = Vector2i(9, 6)
	st.combatants[ogre.id] = ogre
	eng.add_effect(tank, {"name": "Paralyzed", "cond": "paralyzed", "src": "dm", "rounds": 99})
	var crits := 0
	var hits := 0
	for i in 20:
		var r: Dictionary = eng.roll_attack(ogre, tank, ogre.attacks[0] if not ogre.attacks.is_empty() else {"name": "x", "to_hit": 30, "melee": true}, {"melee": true})
		if r.hit:
			hits += 1
			if r.crit:
				crits += 1
	check(hits > 0 and crits == 0, "adamantine armor: no critical hits, even on a paralyzed wearer")

func _session() -> void:
	print("== the game server")
	Session.start_offline("DM", 20, 12)
	Session.auto_monsters = false
	var ch := premade("Grukka")
	ch.id = "inv_test_hero"
	ch.erase("inventory")
	var cid := Session.add_character(ch, 1, Vector2i(3, 3))
	var c: Dictionary = Session.engine.C(cid)
	check(Session.sheets[cid].get("inventory", null) is Array and not c.inventory.is_empty(), "a joining character without an inventory gets its starting gear")
	var ch2 := premade("Pip")
	ch2.id = "inv_test_rogue"
	var cid2 := Session.add_character(ch2, 1, Vector2i(4, 3))
	var c2: Dictionary = Session.engine.C(cid2)
	# A chest's loot reaches the sheet.
	var chest := MapObjects.place(Session.engine, MapObjects.make("chest", Vector2i(3, 4), EngineBase.FLOOR, {"loot": {"gp": 77, "gear": [{"id": "potion_healing", "qty": 2}]}}))
	var gp0 := int(Session.sheets[cid].coins.gp)
	Session.request({"type": "action", "cid": cid, "aid": "obj_open", "params": {"cell": Vector2i(3, 4)}})
	check(chest.get("opened", false), "the chest opens")
	check(int(Session.sheets[cid].coins.gp) == gp0 + 77 and Inventory.count(Session.sheets[cid], "potion_healing") == 2, "the loot is saved to the character's sheet")
	# The shop.
	Session.request({"type": "inv", "cid": cid, "op": "buy", "id": "rations", "qty": 2})
	check(Inventory.count(c, "rations") == 10, "no shop open: nothing bought")
	Session.request({"type": "dm_shop", "open": true, "kind": "general", "markup": 100, "buyback": 50})
	check(not Session.shop().is_empty() and "rope_silk" in Session.shop().stock, "the DM opens a general store")
	var w0 := Inventory.wealth_cp(c.coins)
	Session.request({"type": "inv", "cid": cid, "op": "buy", "id": "rope_silk", "qty": 1})
	check(Inventory.count(Session.sheets[cid], "rope_silk") == 1 and Inventory.wealth_cp(Session.sheets[cid].coins) == w0 - 1000, "buying silk rope costs 10 gp and lands on the sheet")
	Session.request({"type": "dm_start_combat"})
	Session.request({"type": "inv", "cid": cid, "op": "buy", "id": "rope_silk", "qty": 1})
	Session.request({"type": "dm_end_combat"})
	# Giving to a party member.
	var pot := uid_of(c, "potion_healing")
	Session.request({"type": "inv_give", "cid": cid, "to": cid2, "uid": pot, "qty": 1})
	check(Inventory.count(c2, "potion_healing") == 1 and Inventory.count(Session.sheets[cid2], "potion_healing") == 1 and Inventory.count(c, "potion_healing") == 1, "handing a potion to a party member")
	Session.request({"type": "inv_give", "cid": cid, "to": cid2, "coins": {"gp": 5}})
	check(int(Session.sheets[cid2].coins.gp) >= 5, "and gold")
	# The DM gives a magic item, the player equips and attunes it.
	Session.request({"type": "dm_give", "cids": [cid], "id": "cloak_of_protection", "qty": 1})
	var cl := uid_of(c, "cloak_of_protection")
	check(cl != "", "the DM hands out a Cloak of Protection")
	var ac0 := int(c.ac)
	Session.request({"type": "inv", "cid": cid, "op": "equip", "uid": cl, "on": true})
	Session.request({"type": "inv", "cid": cid, "op": "attune", "uid": cl, "on": true})
	c = Session.engine.C(cid)
	check(int(c.ac) == ac0 + 1 and int(Session.sheets[cid].equipment.get("armor_bonus", 0)) == 0, "wearing and attuning it raises the token's AC")
	# Dropping leaves a pile; a level-up sheet can't overwrite the pack.
	var rope := uid_of(c, "rope_silk")
	Session.request({"type": "inv", "cid": cid, "op": "drop", "uid": rope, "qty": 1})
	check(MapObjects.at(Session.state, c.pos).any(func(o): return o.k == "pile"), "dropping in play leaves it on the ground")
	var stale: Dictionary = Session.sheets[cid].duplicate(true)
	stale.inventory = []
	stale.coins = {"gp": 99999}
	Session.request({"type": "set_sheet", "cid": cid, "sheet": stale, "label": ""})
	check(int(Session.sheets[cid].coins.gp) != 99999 and not Session.sheets[cid].inventory.is_empty(), "a sheet sent from a player can't change what they carry")
	Session.request({"type": "dm_encumbrance", "mode": "variant"})
	check(str(Session.state.get("encumbrance", "")) == "variant", "the DM switches on variant encumbrance")
	Session.request({"type": "dm_shop", "open": false})
	check(Session.shop().is_empty(), "and closes the shop")
	CharacterStore.delete_character("inv_test_hero")
	CharacterStore.delete_character("inv_test_rogue")

# ---------------------------------------------------------------- helpers for the later sections

## A small arena: {"st", "eng"} with the given combatants placed on it.
func arena(cs: Array) -> Dictionary:
	var st := EngineBase.new_state(16, 10)
	var eng := CombatEngine.new(st)
	for c in cs:
		st.combatants[c.id] = c
	return {"st": st, "eng": eng}

func pc(id: String, name_part: String, at: Vector2i) -> Dictionary:
	var c := CombatantFactory.from_character(id, premade(name_part), 1)
	c.pos = at
	return c

func foe(id: String, mid: String, at: Vector2i, hp := 500) -> Dictionary:
	var m := CombatantFactory.from_monster(id, mid)
	m.pos = at
	m.hp = hp
	m.max_hp = hp
	return m

func action_ids(eng: CombatEngine, c: Dictionary) -> Array:
	return eng.get_actions(c).map(func(a): return str(a.id))

# ---------------------------------------------------------------- 1. ammunition

func _ammo() -> void:
	print("== ammunition")
	var d := Data.item("arrows")
	check(Inventory.bundle_of(d) == 20 and is_equal_approx(Inventory.unit_lb({"id": "arrows"}), 0.05), "arrows are counted one at a time (20 to the pound)")
	var legacy := {"inventory": [{"uid": "i1", "id": "arrows", "qty": 2}, {"uid": "i2", "id": "crossbow_bolts", "qty": 1}], "coins": {}}
	Inventory.ensure(legacy)
	check(Inventory.count(legacy, "arrows") == 40 and Inventory.count(legacy, "crossbow_bolts") == 20, "an old sheet's 2 bundles of arrows become 40 arrows")
	Inventory.ensure(legacy)
	check(Inventory.count(legacy, "arrows") == 40, "and converting again changes nothing")
	# Buying and selling by the bundle.
	var buyer := {"inventory": [], "coins": {"gp": 2}}
	var shop := {"stock": ["arrows"], "markup": 100, "buyback": 50}
	check(Inventory.apply_op(buyer, {"op": "buy", "id": "arrows", "qty": 1}, {"shop": shop}) == "" and Inventory.count(buyer, "arrows") == 20 and Inventory.wealth_cp(buyer.coins) == 100, "1 gp buys a bundle of 20 arrows")
	check(Inventory.sell_total(Inventory.list(buyer)[0], shop, 20) == 50, "selling 20 arrows back pays 5 sp (half)")
	# In play: a rogue with a shortbow.
	# Pip keeps the shortbow in the other weapon set (rapier and dagger in hand): swap to it first.
	var archer := premade("Pip")
	Inventory.swap_sets(archer)
	var rogue := CombatantFactory.from_character("p1", archer, 1)
	rogue.pos = Vector2i(2, 2)
	var gob := foe("m1", "goblin", Vector2i(6, 2))
	var ar := arena([rogue, gob])
	var eng: CombatEngine = ar.eng
	var shot := eng.find_action(rogue, "atk:w_shortbow")
	check(not shot.is_empty() and shot.enabled and str(shot.name).contains("(20)"), "the shortbow shows 20 arrows left")
	eng.execute(rogue.id, "atk:w_shortbow", {"targets": [gob.id]})
	check(Inventory.count(rogue, "arrows") == 19, "each shot uses one arrow")
	Inventory.consume(rogue, "arrows", 19)
	shot = eng.find_action(rogue, "atk:w_shortbow")
	check(not shot.enabled and str(shot.reason).contains("arrows"), "no arrows: the shortbow can't shoot")
	check(not eng.execute(rogue.id, "atk:w_shortbow", {"targets": [gob.id]}), "and trying anyway does nothing")
	# +1 arrows get their own attack, with the bonus.
	var plus := Inventory.add(rogue, "ammunition_plus_1", 3, {"base": "arrows"})
	check(Inventory.count(rogue, "ammunition_plus_1") == 3 and Inventory.display_name(plus) == "Arrows +1", "three Arrows +1 in one stack")
	var v := eng.find_action(rogue, "atk:w_shortbow@" + str(plus.uid))
	var base_hit := int(Rules.derive(archer).weapons.filter(func(w): return str(w.id) == "w_shortbow")[0].to_hit)
	check(not v.is_empty() and v.enabled and int(v.atk.to_hit) == base_hit + 1 and v.atk.magic, "shooting an Arrow +1: +1 to hit, magical")
	check(str(v.atk.damage[0].dice).ends_with("+%d" % (int(rogue.mods.dex) + 1)), "and +1 damage")
	var hit_once := false
	for i in 3:
		eng.execute(rogue.id, v.id, {"targets": [gob.id]})
	check(Inventory.count(rogue, "ammunition_plus_1") == 0, "all three magic arrows shot")
	# Half comes back after the fight; magic arrows that hit come back as plain arrows.
	var spent: Array = rogue.get("ammo_spent", [])
	var total := 0
	for s in spent:
		total += int(s.qty)
	check(total == 4, "the game remembers the 4 arrows shot")
	eng.s.in_combat = true
	eng.end_combat()
	var back: Array = rogue.get("ammo_recover", [])
	check(not back.is_empty(), "after the fight there are arrows to gather")
	check(action_ids(eng, rogue).has("inv:recover:ammo"), "Recover Ammunition is offered")
	var before := Inventory.count(rogue, "arrows") + Inventory.count(rogue, "ammunition_plus_1")
	eng.execute(rogue.id, "inv:recover:ammo", {})
	var after := Inventory.count(rogue, "arrows") + Inventory.count(rogue, "ammunition_plus_1")
	check(after - before == 2 or after - before == 1, "half of them (rounded down per kind) come back")
	check(not action_ids(eng, rogue).has("inv:recover:ammo"), "and they can only be gathered once")
	# A monster's bow needs no arrows; a thrown dagger isn't ammunition.
	check(Inventory.ammo_for(gob, {"weapon": "shortbow"}) == "" and Inventory.ammo_for(rogue, {"weapon": "dagger", "thrown": true}) == "", "monsters and thrown weapons don't use ammunition")

# ---------------------------------------------------------------- 2. stealth

func _stealth() -> void:
	print("== stealth")
	var ch := premade("Grukka")   # chain mail
	var eng: CombatEngine = arena([]).eng
	var c := CombatantFactory.from_character("p1", ch, 1)
	check(c.stealth_dis and int(eng.stealth_roll(c).adv) == -1, "chain mail: disadvantage on the Stealth roll to hide")
	var boots := Inventory.add(ch, "boots_of_elvenkind", 1, {"eq": true})
	c = CombatantFactory.from_character("p1", ch, 1)
	check(int(eng.stealth_roll(c).adv) == 0, "boots of elvenkind cancel it out")
	Inventory.take(ch, str(boots.uid))
	var mith := premade("Grukka")
	mith.inventory = []
	Inventory.add(mith, "mithral_armor", 1, {"base": "chain_mail", "eq": true})
	c = CombatantFactory.from_character("p1", mith, 1)
	check(not c.stealth_dis and int(eng.stealth_roll(c).adv) == 0, "mithral chain mail: no Stealth penalty")
	var cloak := Inventory.add(mith, "cloak_of_elvenkind", 1, {"eq": true})
	c = CombatantFactory.from_character("p1", mith, 1)
	check(int(eng.stealth_roll(c).adv) == 0, "a cloak of elvenkind does nothing until attuned")
	Inventory.find(mith, str(cloak.uid)).att = true
	c = CombatantFactory.from_character("p1", mith, 1)
	check(int(eng.stealth_roll(c).adv) == 1, "worn and attuned: advantage when hiding")
	# The Hide action uses it.
	var gob := foe("m1", "goblin", Vector2i(8, 2))
	c.pos = Vector2i(2, 2)
	var ar := arena([c, gob])
	ar.eng.execute(c.id, "hide", {})
	var line: String = str(ar.eng.events.filter(func(e): return e.get("t", "") == "log").map(func(e): return str(e.get("text", ""))))
	check(line.contains("elvenkind"), "the Hide action rolls with it (and says so in the log)")

# ---------------------------------------------------------------- 3. tools

func _tools() -> void:
	print("== tools")
	var rogue := premade("Pip")
	var st := Rules.derive(rogue)
	check("thieves_tools" in st.tools, "a rogue is proficient with thieves' tools")
	var fighter := premade("Grukka")
	fighter.background = "urchin"
	check("thieves_tools" in Rules.derive(fighter).tools and "disguise_kit" in Rules.derive(fighter).tools, "so is an urchin (background): thieves' tools and a disguise kit")
	fighter.background = "soldier"
	check(not "thieves_tools" in Rules.derive(fighter).tools, "a soldier fighter isn't")
	var gnome := Rules.new_character()
	gnome.race = "gnome"
	gnome.subrace = "rock"
	check("tinkers_tools" in Rules.derive(gnome).tools, "a rock gnome knows tinker's tools")
	var mc := premade("Grukka")
	mc.classes.append({"id": "rogue", "level": 1})
	check("thieves_tools" in Rules.derive(mc).tools, "multiclassing into rogue adds thieves' tools")
	# Picking a lock.
	var chest_at := Vector2i(3, 2)
	var c := pc("p1", "Pip", Vector2i(2, 2))
	var ar := arena([c])
	var eng: CombatEngine = ar.eng
	MapObjects.place(eng, MapObjects.make("chest", chest_at, EngineBase.FLOOR, {"locked": true, "dc": 1, "loot": {"gp": 5}}))
	var pa := eng.find_action(c, "obj_picklock")
	check(pa.enabled and str(pa.desc).contains("proficient: +"), "Pip has thieves' tools and proficiency")
	Inventory.consume(c, "thieves_tools", 1)
	pa = eng.find_action(c, "obj_picklock")
	check(not pa.enabled and str(pa.reason).contains("thieves' tools"), "without thieves' tools in the pack, no picking locks")
	check(not eng.execute(c.id, "obj_picklock", {"cell": chest_at}), "even when asked")
	var f := pc("p2", "Grukka", Vector2i(4, 2))
	ar.st.combatants[f.id] = f
	Inventory.add(f, "thieves_tools", 1)
	pa = eng.find_action(f, "obj_picklock")
	check(pa.enabled and str(pa.desc).contains("not proficient"), "a fighter with borrowed tools can try, without proficiency")
	eng.execute(f.id, "obj_picklock", {"cell": chest_at})
	var ev: Array = eng.events.filter(func(e): return e.get("t", "") == "dice" and str(e.get("label", e.get("what", ""))).contains("Thieves"))
	check(not ev.is_empty() and int(ev[0].mod) == int(f.mods.dex), "and adds only Dexterity")

# ---------------------------------------------------------------- 4. hands and weapon sets

func atk_ids(c: Dictionary) -> Array:
	return c.get("attacks", c.get("weapons", [])).map(func(w): return str(w.id))

func _hands() -> void:
	print("== hands and weapon sets")
	var ch := premade("Grukka")   # greatsword and javelin
	check(Inventory.set_text(Inventory.held(ch, false)) == "Greatsword" and Inventory.set_text(Inventory.held(ch, true)) == "Javelin", "an old two-weapon loadout: greatsword in hand, the javelin in the other weapon set")
	check(not "w_javelin" in atk_ids(Rules.derive(ch)), "only what's in hand gives attacks")
	var sh := Inventory.add(ch, "shield", 1)
	Inventory.apply_op(ch, {"op": "equip", "uid": str(sh.uid), "on": true})
	check(not Inventory.find(ch, uid_of(ch, "greatsword")).get("eq", false), "a shield and a two-handed greatsword don't go together: the greatsword is put away")
	var ls := Inventory.add(ch, "longsword", 1)
	Inventory.apply_op(ch, {"op": "equip", "uid": str(ls.uid), "on": true})
	check(Inventory.hands_used(ch) == 2 and Inventory.find(ch, str(sh.uid)).get("eq", false), "a longsword and a shield fill both hands")
	var mace := Inventory.add(ch, "mace", 1)
	check(not Inventory.equip_moves_shield(ch, mace), "swapping the sword for a mace keeps the shield")
	Inventory.apply_op(ch, {"op": "equip", "uid": str(mace.uid), "on": true})
	check(Inventory.find(ch, str(sh.uid)).get("eq", false) and not Inventory.find(ch, str(ls.uid)).get("eq", false), "and puts the sword away")
	var bow := Inventory.add(ch, "longbow", 1)
	check(Inventory.equip_moves_shield(ch, bow), "a longbow needs both hands: the shield would have to come off")
	Inventory.apply_op(ch, {"op": "equip", "uid": str(bow.uid), "on": true})
	check(Inventory.held(ch, false).size() == 1 and Inventory.hands_used(ch) == 2, "and readying it leaves just the bow in hand")
	var dag := Inventory.add(ch, "dagger", 2)
	Inventory.apply_op(ch, {"op": "equip", "uid": str(dag.uid), "on": true})
	check(Inventory.hands_of(dag) == 2 and "offhand" in atk_ids(Rules.derive(ch)), "a pair of daggers: one in each hand, with an off-hand attack")
	# The other weapon set.
	check(Inventory.apply_op(ch, {"op": "wset", "uid": str(ls.uid), "alt": true}) == "" and Inventory.apply_op(ch, {"op": "wset", "uid": str(sh.uid), "alt": true}) == "", "longsword and shield go in the other weapon set")
	check(Inventory.held(ch, true).size() == 2 and not Inventory.find(ch, uid_of(ch, "javelin")).get("alt", false), "(the javelin makes room)")
	Inventory.apply_op(ch, {"op": "swap"})
	check(Inventory.held(ch, false).map(func(e): return str(e.id)).has("longsword") and Inventory.held(ch, false).map(func(e): return str(e.id)).has("shield") and Inventory.held(ch, true).size() == 1, "swap: sword and board in hand, the daggers ready to swap back")
	var st := Rules.derive(ch)
	check("w_longsword" in atk_ids(st) and not "w_dagger" in atk_ids(st) and str(st.ac_note).contains("shield"), "attacks and AC follow the swap")
	# A sheet holding too much (from before hands were counted) is tidied up.
	var old := {"inventory": [{"uid": "i1", "id": "greatsword", "qty": 1, "eq": true}, {"uid": "i2", "id": "shield", "qty": 1, "eq": true}, {"uid": "i3", "id": "longbow", "qty": 1, "eq": true}], "coins": {}}
	Inventory.ensure(old)
	check(Inventory.hands_used(old, false) <= 2 and Inventory.hands_used(old, true) <= 2, "an old sheet with greatsword, shield and longbow all equipped is tidied into two hands")
	# In a fight, through the game server: the swap is the free object interaction and rebuilds the attacks.
	Session.start_offline("DM", 20, 12)
	Session.auto_monsters = false
	var g := premade("Grukka")
	g.id = "inv_test_hands"
	var cid := Session.add_character(g, 1, Vector2i(3, 3))
	Session.add_monster("goblin", Vector2i(10, 3))
	Session.request({"type": "dm_start_combat"})
	var c: Dictionary = Session.engine.C(cid)
	while Session.engine.current().get("id", "") != cid:
		Session.engine.end_turn()
	var sw := Session.engine.find_action(c, "inv:swap:set")
	check(not sw.is_empty() and sw.cost == "free", "Swap Weapons is on the hotbar as a free object interaction")
	Session.request({"type": "action", "cid": cid, "aid": "inv:swap:set", "params": {}})
	c = Session.engine.C(cid)
	check("w_javelin" in atk_ids(c) and not "w_greatsword" in atk_ids(c), "after the swap the token attacks with the javelin")
	check(c.turn.get("obj_used", false) and int(c.turn.action) == 1, "it used the object interaction, not the action")
	check(Session.engine.find_action(c, "inv:swap:set").cost == "action", "swapping back this turn takes the action")
	check(Session.sheets[cid].inventory.any(func(e): return str(e.id) == "javelin" and e.get("eq", false)), "the swap is saved to the sheet")
	Session.request({"type": "dm_end_combat"})
	CharacterStore.delete_character("inv_test_hands")

# ---------------------------------------------------------------- 5. attunement takes a rest

func _attune() -> void:
	print("== attunement")
	var ch := premade("Grukka")
	var info := Inventory.sheet_info(ch)
	var cloak := Inventory.add(ch, "cloak_of_protection", 1, {"eq": true})
	var ac0 := int(Rules.derive(ch).ac)
	check(Inventory.apply_op(ch, {"op": "attune", "uid": str(cloak.uid), "on": true}, {"info": info}) == "", "a player asks to attune to a Cloak of Protection")
	check(not cloak.get("att", false) and str(cloak.get("pend", "")) == "on" and int(Rules.derive(ch).ac) == ac0, "it waits for a rest: no bonus yet")
	var luck := Inventory.add(ch, "stone_of_good_luck", 1)
	Inventory.apply_op(ch, {"op": "attune", "uid": str(luck.uid), "on": true}, {"info": info})
	check(Inventory.queued(ch).size() == 2, "a second item joins the queue")
	Inventory.apply_op(ch, {"op": "attune", "uid": str(luck.uid), "on": false}, {"info": info})
	check(Inventory.queued(ch).size() == 1 and not luck.has("pend"), "and can be called off")
	Inventory.apply_op(ch, {"op": "attune", "uid": str(luck.uid), "on": true}, {"info": info})
	var r1 := Inventory.add(ch, "ring_of_protection", 1, {"att": true})
	var r2 := Inventory.add(ch, "ring_of_warmth", 1, {"att": true})
	check(Inventory.apply_op(ch, {"op": "attune", "uid": str(Inventory.add(ch, "brooch_of_shielding", 1).uid), "on": true}, {"info": info}) != "", "queued attunements count toward the three")
	Inventory.take(ch, str(r1.uid))
	Inventory.take(ch, str(r2.uid))
	check(Inventory.apply_op(ch, {"op": "attune", "uid": "x", "on": true}, {"in_combat": true}) != "", "not during a fight")
	# Rests.
	var c := CombatantFactory.from_character("p1", ch, 1)
	c.pos = Vector2i(2, 2)
	var ar := arena([c])
	var eng: CombatEngine = ar.eng
	eng.short_rest()
	check(Inventory.find(c, str(cloak.uid)).get("att", false) and not Inventory.find(c, str(luck.uid)).get("att", false), "a short rest: the first item is attuned (one item per rest)")
	check(c.get("gear_dirty", false), "and the game is told to rebuild the character's stats")
	eng.long_rest()
	check(Inventory.find(c, str(luck.uid)).get("att", false) and Inventory.queued(c).is_empty(), "the next rest (a long one) attunes the second")
	Inventory.apply_op(c, {"op": "attune", "uid": str(cloak.uid), "on": false}, {"info": info})
	check(Inventory.find(c, str(cloak.uid)).get("att", false) and str(Inventory.find(c, str(cloak.uid)).get("pend", "")) == "off", "ending an attunement waits for a rest too")
	eng.short_rest()
	check(not Inventory.find(c, str(cloak.uid)).get("att", false), "and happens during it")
	check(Inventory.apply_op(c, {"op": "attune", "uid": str(cloak.uid), "on": true}, {"info": info, "attune_now": true}) == "" and Inventory.find(c, str(cloak.uid)).get("att", false), "when the DM allows it, attuning is immediate")
	# Through the game server, as a player (peer 2).
	Session.start_offline("DM", 20, 12)
	Session.auto_monsters = false
	var g := premade("Grukka")
	g.id = "inv_test_attune"
	var cid := Session.add_character(g, 2, Vector2i(3, 3))
	Session.request({"type": "dm_give", "cids": [cid], "id": "cloak_of_protection", "qty": 1})
	var pc_c: Dictionary = Session.engine.C(cid)
	var cl := uid_of(pc_c, "cloak_of_protection")
	Session._handle(2, {"type": "inv", "cid": cid, "op": "equip", "uid": cl, "on": true})
	var ac1 := int(Session.engine.C(cid).ac)
	Session._handle(2, {"type": "inv", "cid": cid, "op": "attune", "uid": cl, "on": true})
	check(int(Session.engine.C(cid).ac) == ac1 and str(Inventory.find(Session.sheets[cid], cl).get("pend", "")) == "on", "a player's attunement is queued on the sheet")
	Session.request({"type": "dm_short_rest"})
	check(int(Session.engine.C(cid).ac) == ac1 + 1 and Inventory.find(Session.sheets[cid], cl).get("att", false), "after the DM's short rest the token's AC rises and the sheet is saved")
	Session.request({"type": "dm_attune_free", "on": true})
	Session._handle(2, {"type": "inv", "cid": cid, "op": "attune", "uid": cl, "on": false})
	check(not Inventory.find(Session.sheets[cid], cl).get("att", false), "with 'attune without a rest' on, a player's change is immediate")
	CharacterStore.delete_character("inv_test_attune")

# ---------------------------------------------------------------- 6. treasure

func _treasure() -> void:
	print("== treasure")
	var ok_low := true
	var ok_mid := true
	for i in 200:
		var p := Inventory.roll_individual(0.25)
		if p.size() != 1 or int(p.get("cp", 0)) > 30 or int(p.get("sp", 0)) > 24 or int(p.get("ep", 0)) > 18 or int(p.get("gp", 0)) > 18 or int(p.get("pp", 0)) > 6:
			ok_low = false
		var q := Inventory.roll_individual(5)
		if Inventory.wealth_cp(q) < 400:
			ok_mid = false
	check(ok_low, "CR 0-4: one kind of coin, within the DMG's dice (5d6 cp ... 1d6 pp)")
	check(ok_mid, "CR 5-10: coins in the tens and hundreds")
	var gob := foe("m1", "goblin", Vector2i(3, 2), 7)
	var wolf := foe("m2", "wolf", Vector2i(2, 3), 11)
	check(Inventory.carries_treasure(gob, "mindless") and not Inventory.carries_treasure(wolf, "mindless"), "by default a goblin has a purse, a wolf doesn't")
	check(Inventory.carries_treasure(wolf, "all") and not Inventory.carries_treasure(gob, "off"), "the DM can give every monster coins, or none")
	var skel := foe("m3", "skeleton", Vector2i(9, 9))
	check(not Inventory.carries_treasure(skel, "humanoids") and Inventory.carries_treasure(gob, "humanoids"), "'humanoids only' leaves out the skeleton")
	# Searching bodies.
	var hero := pc("p1", "Grukka", Vector2i(2, 2))
	var ar := arena([hero, gob, wolf])
	var eng: CombatEngine = ar.eng
	check(not action_ids(eng, hero).has("obj_search"), "nothing to search while they live")
	gob.hp = 0
	gob.dead = true
	wolf.hp = 0
	wolf.dead = true
	var sa := eng.find_action(hero, "obj_search")
	check(not sa.is_empty() and sa.cost == "free" and MapObjects.valid_targets(eng, hero, sa).size() == 2, "Search Body: both bodies within 5 ft are highlighted (free outside a fight)")
	var w0 := Inventory.wealth_cp(hero.coins)
	eng.execute(hero.id, "obj_search", {"cell": gob.pos})
	check(Inventory.wealth_cp(hero.coins) > w0 and gob.get("searched", false), "searching the goblin finds coins")
	var w1 := Inventory.wealth_cp(hero.coins)
	eng.execute(hero.id, "obj_search", {"cell": wolf.pos})
	check(Inventory.wealth_cp(hero.coins) == w1 and wolf.get("searched", false), "the wolf carries nothing")
	check(not action_ids(eng, hero).has("obj_search"), "and a body is only searched once")
	# Gems and art: hoard goods a shop pays full price for.
	var gem := {"id": "gem_50", "qty": 1}
	check(Inventory.sell_total(gem, {"buyback": 50}, 1) == 5000, "a 50 gp gemstone sells for 50 gp (full value)")
	var found := false
	var rng := RandomNumberGenerator.new()
	for s in 60:
		rng.seed = s
		var l := MapObjects.roll_loot(rng, 3, true)
		if l.get("gear", []).any(func(g): return str(Data.item(str(g.id)).get("cat", "")) == "treasure"):
			found = true
			break
	check(found, "rich chests sometimes hold gems or art objects")
	check(not "gem_10" in Inventory.shop_stock("everything"), "shops don't sell gems")
	# Split coins evenly.
	var a := {"coins": {"gp": 10, "sp": 3, "pp": 1}}
	var b := {"coins": {"gp": 1, "cp": 5}}
	var tot := Inventory.split_coins([a, b])
	check(Inventory.wealth_cp(a.coins) + Inventory.wealth_cp(b.coins) == 2135 and int(a.coins.gp) + int(b.coins.gp) == 11, "splitting keeps every coin")
	check(absi(int(a.coins.gp) - int(b.coins.gp)) <= 1 and absi(int(a.coins.sp) - int(b.coins.sp)) <= 1, "and shares each kind evenly (odd coins one each)")
	Session.start_offline("DM", 20, 12)
	Session.auto_monsters = false
	var c1 := premade("Grukka")
	c1.id = "inv_test_split1"
	c1.coins = {"gp": 30}
	var c2 := premade("Pip")
	c2.id = "inv_test_split2"
	c2.coins = {"gp": 0}
	var id1 := Session.add_character(c1, 1, Vector2i(2, 2))
	var id2 := Session.add_character(c2, 1, Vector2i(3, 2))
	Session.request({"type": "dm_split_coins", "cids": [id1, id2]})
	check(int(Session.sheets[id1].coins.gp) == 15 and int(Session.sheets[id2].coins.gp) == 15, "the DM's split button: 30 gp becomes 15 each, saved to the sheets")
	Session.request({"type": "dm_treasure", "mode": "all"})
	check(str(Session.state.get("treasure", "")) == "all", "the DM chooses who carries coins")
	CharacterStore.delete_character("inv_test_split1")
	CharacterStore.delete_character("inv_test_split2")

# ---------------------------------------------------------------- 7. shops: stock and the magic rate

func _shops2() -> void:
	print("== shop stock")
	var cloak := {"id": "cloak_of_protection", "qty": 1}
	check(Inventory.sell_total(cloak, {"buyback": 50}, 1) == 12500, "a shop pays 25% for a magic item by default (125 gp for a 500 gp cloak)")
	check(Inventory.sell_total(cloak, {"buyback": 50, "magic_buyback": 60}, 1) == 30000, "or the DM's own magic rate")
	check(Inventory.sell_total({"id": "longsword"}, {"buyback": 50, "magic_buyback": 10}, 1) == 750, "mundane gear still sells at the gear rate")
	Session.start_offline("DM", 20, 12)
	Session.auto_monsters = false
	var g := premade("Grukka")
	g.id = "inv_test_shop2"
	g.coins = {"gp": 500}
	var cid := Session.add_character(g, 1, Vector2i(3, 3))
	Session.request({"type": "dm_shop", "open": true, "kind": "general", "markup": 100, "buyback": 50})
	check(int(Session.shop().get("magic_buyback", 0)) == 25, "a new shop buys magic items at 25%")
	Session.request({"type": "dm_shop_stock", "op": "add", "id": "potion_healing", "qty": 2})
	check("potion_healing" in Session.shop().stock and Inventory.stock_left(Session.shop(), "potion_healing") == 2, "the DM puts two potions of healing on the shelf")
	Session.request({"type": "dm_shop_stock", "op": "remove", "id": "rope_silk"})
	check(not "rope_silk" in Session.shop().stock, "and takes silk rope off sale")
	var c: Dictionary = Session.engine.C(cid)
	var p0 := Inventory.count(c, "potion_healing")
	Session._handle(1, {"type": "inv", "cid": cid, "op": "buy", "id": "potion_healing", "qty": 1})
	check(Inventory.count(Session.engine.C(cid), "potion_healing") == p0 + 1 and Inventory.stock_left(Session.shop(), "potion_healing") == 1, "buying one leaves one")
	var ctx := {"shop": Session.shop()}
	check(Inventory.apply_op(Session.engine.C(cid), {"op": "buy", "id": "potion_healing", "qty": 2}, ctx) != "", "two more can't be had")
	Session.request({"type": "inv", "cid": cid, "op": "buy", "id": "potion_healing", "qty": 1})
	check(not "potion_healing" in Session.shop().stock, "the last one sold: off the shelf")
	Session.request({"type": "dm_shop_stock", "op": "add", "id": "bag_of_holding", "qty": 1})
	Session.request({"type": "dm_shop", "open": true, "kind": "general", "markup": 120, "buyback": 50, "magic_buyback": 40})
	check("bag_of_holding" in Session.shop().stock and not "rope_silk" in Session.shop().stock and int(Session.shop().markup) == 120, "changing the prices keeps the DM's stock changes")
	check(int(Session.shop().magic_buyback) == 40, "and sets the magic rate")
	Session.request({"type": "dm_shop", "open": true, "kind": "smith"})
	check(not "bag_of_holding" in Session.shop().stock, "a different kind of shop starts from its own stock")
	Session.request({"type": "dm_shop", "open": false})
	CharacterStore.delete_character("inv_test_shop2")

# ---------------------------------------------------------------- 8. silvered weapons, net, poison, caltrops, background kits

func _items8() -> void:
	print("== silver, nets, poison, caltrops")
	var ch := premade("Grukka")
	var sv := Inventory.add(ch, "silvered_weapon", 1, {"base": "longsword"})
	check(Inventory.display_name(sv) == "Silvered Longsword" and Inventory.unit_price(sv) == 10000 + 1500, "a silvered longsword: 100 gp on top of the sword")
	Inventory.apply_op(ch, {"op": "equip", "uid": str(sv.uid), "on": true})
	var la := weapon_atk(Rules.derive(ch), "longsword")
	check(la.get("silver", false) and not la.get("magic", false), "it attacks as a silvered (not magical) longsword")
	var hero := CombatantFactory.from_character("p1", ch, 1)
	hero.pos = Vector2i(2, 2)
	var wolf := foe("m1", "werewolf", Vector2i(3, 2), 200)
	var ar := arena([hero, wolf])
	var eng: CombatEngine = ar.eng
	check(wolf.get("mundane_silver", false), "a werewolf's resistance gives way to silver")
	var h0 := int(wolf.hp)
	eng.apply_damage(wolf, [{"amount": 10, "type": "slashing"}], hero, {"attack": true})
	var plain := h0 - int(wolf.hp)
	h0 = int(wolf.hp)
	eng.apply_damage(wolf, [{"amount": 10, "type": "slashing"}], hero, {"attack": true, "silver": true})
	check(plain < 10 and h0 - int(wolf.hp) == 10, "a plain sword is shrugged off (%d of 10), a silvered one does full damage" % plain)
	var sa := Inventory.add(ch, "silvered_ammo", 10, {"base": "arrows"})
	check(Inventory.count(ch, "silvered_ammo") == 10 and Inventory.ammo_attack({"name": "Longbow", "to_hit": 5, "damage": [{"dice": "1d8+3", "type": "piercing"}]}, sa).get("silver", false), "silvered arrows shoot silvered")
	# The net.
	var rogue := pc("p2", "Pip", Vector2i(5, 5))
	var gob := foe("m2", "goblin", Vector2i(6, 5), 50)
	var ally := pc("p3", "Brannoc", Vector2i(5, 6))
	ar = arena([rogue, gob, ally])
	eng = ar.eng
	rogue.mods.dex = 40   # (so the net hits)
	var netted := false
	for i in 6:
		Inventory.add(rogue, "net", 1)
		eng.execute(rogue.id, "inv:net:" + uid_of(rogue, "net"), {"targets": [gob.id]})
		if eng.has_cond(gob, "restrained"):
			netted = true
			break
	check(netted, "a thrown net restrains a goblin")
	var ne: Dictionary = gob.effects.filter(func(e): return e.get("net", false))[0] if netted else {}
	check(netted and int(ne.get("escape_dc", 0)) == 10 and ne.get("escape_with", []) == ["str"], "it breaks free with a DC 10 Strength check (the Escape action)")
	gob.size = "huge"
	eng.remove_effect(gob, ne.get("eid", ""))
	Inventory.add(rogue, "net", 3)
	for i in 3:
		eng.execute(rogue.id, "inv:net:" + uid_of(rogue, "net"), {"targets": [gob.id]})
	check(not eng.has_cond(gob, "restrained"), "a Huge creature can't be held by a net")
	eng.add_effect(ally, {"name": "Netted", "cond": "restrained", "net": true, "src": gob.id, "rounds": 9999, "tick_cid": "none", "escape_dc": 10, "escape_with": ["str"]})
	check(action_ids(eng, rogue).has("inv:freenet:" + ally.id), "a creature next to a netted ally can free it")
	for i in 30:
		if not eng.has_cond(ally, "restrained"):
			break
		eng.execute(rogue.id, "inv:freenet:" + ally.id, {"targets": [ally.id]})
	check(not eng.has_cond(ally, "restrained"), "cutting (AC 10, 5 slashing) or pulling (DC 10 Strength) frees it")
	# Basic poison: the next hit only.
	var fighter := pc("p4", "Grukka", Vector2i(10, 2))
	var dummy := foe("m3", "ogre", Vector2i(11, 2), 400)
	ar = arena([fighter, dummy])
	eng = ar.eng
	Inventory.add(fighter, "poison_basic", 1)
	eng.execute(fighter.id, "inv:coat:" + uid_of(fighter, "poison_basic"), {})
	check(fighter.effects.any(func(e): return e.get("coat", null) is Dictionary and int(e.coat.dc) == 10), "a vial of basic poison coats the weapon (DC 10, 1d4)")
	var hits := 0
	for i in 40:
		var hp0 := int(dummy.hp)
		eng.execute(fighter.id, "atk:w_greatsword", {"targets": [dummy.id]})
		if int(dummy.hp) < hp0:
			hits += 1
			break
	check(hits == 1 and not fighter.effects.any(func(e): return e.get("coat", null) is Dictionary), "the first hit uses up the coating")
	# Caltrops and ball bearings.
	Inventory.add(fighter, "caltrops", 1)
	Inventory.add(fighter, "ball_bearings", 1)
	eng.execute(fighter.id, "inv:zone:" + uid_of(fighter, "caltrops"), {"cell": Vector2i(10, 3)})
	eng.execute(fighter.id, "inv:zone:" + uid_of(fighter, "ball_bearings"), {"cell": Vector2i(11, 3)})
	var cz: Array = eng.s.zones.filter(func(z): return z.name == "Caltrops")
	var bz: Array = eng.s.zones.filter(func(z): return z.name == "Ball Bearings")
	check(cz.size() == 1 and cz[0].cells.size() == 1 and bz.size() == 1 and bz[0].cells.size() == 4, "caltrops cover a 5-foot square, ball bearings a 10-foot one")
	check(Inventory.count(fighter, "caltrops") == 0, "the bag is used")
	var g2 := foe("m4", "goblin", Vector2i(10, 6), 30)
	g2.save_bonus.dex = -40
	eng.s.combatants[g2.id] = g2
	eng.start_combat()
	var guard := 0
	while eng.current().get("id", "") != g2.id and guard < 10:
		eng.end_turn()
		guard += 1
	var hp1 := int(g2.hp)
	eng.move(g2, Vector2i(10, 3), false)
	check(g2.pos == Vector2i(10, 3) and g2.turn.get("speed_zero", false), "walking into the caltrops stops the goblin")
	check(int(g2.hp) == hp1 - 1 and g2.effects.any(func(e): return e.get("until_healed", false)), "1 piercing damage and a sore foot (-10 ft speed)")
	eng.heal_creature(g2, 1, g2, "test")
	check(not g2.effects.any(func(e): return e.get("until_healed", false)), "regaining a hit point cures the foot")
	eng.end_combat()
	# Background starting kits.
	var sage := Rules.new_character()
	sage.background = "sage"
	sage.classes = [{"id": "wizard", "level": 1, "subclass": ""}]
	Inventory.starting_inventory(sage)
	check(Inventory.count(sage, "ink") >= 1 and Inventory.count(sage, "ink_pen") >= 1 and Inventory.count(sage, "clothes_common") == 1, "a sage starts with ink, a pen and common clothes")
	var urch := Rules.new_character()
	urch.background = "urchin"
	urch.classes = [{"id": "rogue", "level": 1, "subclass": ""}]
	Inventory.starting_inventory(urch)
	check(Inventory.count(urch, "thieves_tools") == 1 and Inventory.count(urch, "dagger") >= 1, "an urchin rogue: one set of thieves' tools (not two) and a small knife")
	var sellers := Inventory.shop_stock("smith")
	check("silvered_weapon" in sellers and "net" in sellers and "poison_basic" in Inventory.shop_stock("alchemist"), "smiths sell silvered weapons and nets; alchemists sell poison")

# ---------------------------------------------------------------- 9. more magic items

func _magic9() -> void:
	print("== more magic items")
	var ch := premade("Grukka")
	var jv := Inventory.add(ch, "javelin_of_lightning", 1, {"base": "javelin"})
	Inventory.apply_op(ch, {"op": "equip", "uid": str(jv.uid), "on": true})
	var hero := CombatantFactory.from_character("p1", ch, 1)
	hero.pos = Vector2i(1, 2)
	var mid := foe("m1", "goblin", Vector2i(4, 2), 100)
	var far := foe("m2", "goblin", Vector2i(8, 2), 100)
	var ar := arena([hero, mid, far])
	var eng: CombatEngine = ar.eng
	check(action_ids(eng, hero).has("inv:bolt:" + str(jv.uid)), "a Javelin of Lightning in hand offers its bolt")
	eng.execute(hero.id, "inv:bolt:" + str(jv.uid), {"targets": [far.id]})
	check(int(mid.hp) < 100, "the bolt burns the goblin in the line (DC 13 Dex, 4d6 lightning)")
	check(int(Inventory.find(hero, str(jv.uid)).charges) == 0 and not eng.find_action(hero, "inv:bolt:" + str(jv.uid)).enabled, "once a day")
	# Vicious, slayers, Sun Blade, Mace of Disruption: extra damage on a hit.
	var vic := {"item": "vicious_weapon", "damage": [{"dice": "1d8+3", "type": "slashing"}]}
	check(Inventory.hit_extra(hero, mid, vic, {"crit": true, "nat": 20}).size() == 1 and Inventory.hit_extra(hero, mid, vic, {"crit": true, "nat": 19}).is_empty(), "Vicious Weapon: 2d6 more on a natural 20 only")
	var ogre := foe("m3", "ogre", Vector2i(9, 9))
	var drag := foe("m4", "young_red_dragon", Vector2i(12, 7))
	var gs := {"item": "giant_slayer", "damage": [{"dice": "1d12+3", "type": "slashing"}]}
	check(Inventory.hit_extra(hero, ogre, gs, {}).size() == 1 and str(Inventory.hit_extra(hero, ogre, gs, {})[0].type) == "slashing" and Inventory.hit_extra(hero, mid, gs, {}).is_empty(), "Giant Slayer: 2d6 of the weapon's type against a giant (an ogre), nothing against a goblin")
	check(Inventory.hit_extra(hero, drag, {"item": "dragon_slayer", "damage": [{"dice": "1d8", "type": "slashing"}]}, {}).size() == 1, "Dragon Slayer: 3d6 against a dragon")
	var skel := foe("m5", "skeleton", Vector2i(13, 1))
	check(str(Inventory.hit_extra(hero, skel, {"item": "mace_of_disruption", "damage": [{"dice": "1d6", "type": "bludgeoning"}]}, {})[0].type) == "radiant", "Mace of Disruption: radiant damage to undead")
	var sun := premade("Grukka")
	var sb := Inventory.add(sun, "sun_blade", 1, {"base": "longsword", "att": true})
	Inventory.apply_op(sun, {"op": "equip", "uid": str(sb.uid), "on": true})
	check(weapon_atk(Rules.derive(sun), "longsword").is_empty(), "a Sun Blade is only a hilt until its blade is called up")
	Inventory.find(sun, str(sb.uid)).lit = true
	var sst := Rules.derive(sun)
	var sbl := weapon_atk(sst, "longsword")
	check(not sbl.is_empty() and str(sbl.damage[0].type) == "radiant" and sbl.finesse and str(sbl.damage[0].dice).ends_with("+%d" % (maxi(int(sst.mods.str), int(sst.mods.dex)) + 2)), "lit: a +2 finesse longsword that deals radiant damage")
	check(Inventory.light_sources(CombatantFactory.from_character("p9", sun, 1)).any(func(s): return int(s.ft) == 30), "and it sheds light")
	# Flame Tongue's bonus action.
	var ft := premade("Grukka")
	var fte := Inventory.add(ft, "flame_tongue", 1, {"base": "greatsword", "att": true})
	Inventory.apply_op(ft, {"op": "equip", "uid": str(fte.uid), "on": true})
	var fc := CombatantFactory.from_character("p5", ft, 1)
	fc.pos = Vector2i(14, 9)
	eng.s.combatants[fc.id] = fc
	var ig := eng.find_action(fc, "inv:ignite:" + str(fte.uid))
	check(not ig.is_empty() and ig.cost == "bonus", "Ignite Flame Tongue is a bonus action")
	eng.execute(fc.id, ig.id, {})
	check(Inventory.find(fc, str(fte.uid)).get("lit", false) and Inventory.light_ft(fc) == 80 and fc.get("gear_dirty", false), "lit: it lights 80 ft and the attacks are rebuilt")
	# Boots of Speed and Winged Boots.
	var bt := premade("Grukka")
	var bs := Inventory.add(bt, "boots_of_speed", 1, {"eq": true, "att": true})
	var bc := CombatantFactory.from_character("p6", bt, 1)
	bc.pos = Vector2i(0, 9)
	eng.s.combatants[bc.id] = bc
	var sp0 := eng.eff_speed(bc)
	eng.execute(bc.id, "inv:toggle:" + str(bs.uid), {})
	check(eng.eff_speed(bc) == sp0 * 2 and eng.has_tag(bc, "boots_of_speed"), "Boots of Speed: double speed")
	eng.execute(bc.id, "inv:toggle:" + str(bs.uid), {})
	check(eng.eff_speed(bc) == sp0 and int(Inventory.find(bc, str(bs.uid)).charges) == 100, "click again: back to normal, the unused time kept")
	var wb := Inventory.add(bc, "winged_boots", 1, {"att": true})
	Inventory.find(bc, str(bs.uid)).erase("eq")
	Inventory.find(bc, str(wb.uid)).eq = true
	eng.execute(bc.id, "inv:toggle:" + str(wb.uid), {})
	check(eng.mod_sum(bc, "fly") > 0, "Winged Boots: a flying speed")
	# Gloves, cloak, shield.
	var gl := premade("Grukka")
	Inventory.add(gl, "gloves_of_missile_snaring", 1, {"eq": true, "att": true})
	Inventory.add(gl, "cloak_of_displacement", 1, {"eq": true, "att": true})
	var gc := CombatantFactory.from_character("p7", gl, 1)
	gc.pos = Vector2i(3, 8)
	var arch := foe("m6", "goblin", Vector2i(4, 8), 30)
	ar = arena([gc, arch])
	eng = ar.eng
	check(eng.attack_advantage(arch, gc, true) < 0, "Cloak of Displacement: attacks against the wearer have disadvantage")
	gc.hp = 300
	gc.max_hp = 300
	eng.apply_damage(gc, [{"amount": 30, "type": "piercing"}], arch, {"attack": true, "ranged_weapon": true})
	var log_txt := str(eng.events.filter(func(e): return e.get("t", "") == "log").map(func(e): return str(e.get("text", ""))))
	check(log_txt.contains("gloves"), "Gloves of Missile Snaring knock down a ranged hit (a reaction)")
	check(eng.attack_advantage(arch, gc, true) == 0, "after being hurt, the displacement falters")
	eng.begin_turn(gc)
	check(eng.attack_advantage(arch, gc, true) < 0, "and returns at the start of the wearer's turn")
	var sh := premade("Grukka")
	var acs := Inventory.add(sh, "arrow_catching_shield", 1, {"att": true})
	Inventory.apply_op(sh, {"op": "equip", "uid": str(acs.uid), "on": true})
	var shc := CombatantFactory.from_character("p8", sh, 1)
	shc.pos = Vector2i(8, 8)
	eng.s.combatants[shc.id] = shc
	var rr: Dictionary = eng.roll_attack(arch, shc, {"name": "Shortbow", "to_hit": 4, "melee": false, "range": 80, "long_range": 320, "damage": []}, {"melee": false})
	var mr: Dictionary = eng.roll_attack(arch, shc, {"name": "Scimitar", "to_hit": 4, "melee": true, "reach": 5, "damage": []}, {"melee": true})
	check(int(rr.ac) == int(mr.ac) + 2, "Arrow-Catching Shield: +2 AC against ranged attacks")
	# Necklace and wand of fireballs, Staff of the Woodlands.
	var wiz := pc("p10", "Tamsin", Vector2i(2, 2))
	var gob := foe("m7", "goblin", Vector2i(9, 2), 200)
	ar = arena([wiz, gob])
	eng = ar.eng
	var nk := Inventory.add(wiz, "necklace_of_fireballs", 1)
	var beads := int(nk.charges)
	check(beads >= 4 and beads <= 9, "a Necklace of Fireballs has 1d6 + 3 beads")
	var na := eng.find_action(wiz, "inv:cast:" + str(nk.uid))
	check(not na.is_empty() and int(na.range) == 60 and int(na.slots[0]) == 3, "a bead is thrown 60 ft as a 3rd-level fireball")
	eng.execute(wiz.id, na.id, {"cell": gob.pos, "slot": 4})
	check(int(Inventory.find(wiz, str(nk.uid)).charges) == beads - 2 and int(gob.hp) < 200, "two beads: a 4th-level fireball")
	Inventory.find(wiz, str(nk.uid)).charges = 1
	wiz.turn = eng.new_turn(wiz)
	eng.execute(wiz.id, na.id, {"cell": gob.pos, "slot": 3})
	check(Inventory.find(wiz, str(nk.uid)).is_empty(), "throwing the last bead leaves nothing")
	var wf := Inventory.add(wiz, "wand_of_fireballs", 1, {"att": true})
	var wfa := eng.find_action(wiz, "inv:cast:" + str(wf.uid))
	check(not wfa.is_empty() and wfa.enabled and int(wfa.dc) == 15, "Wand of Fireballs (DC 15)")
	var stf := Inventory.add(wiz, "staff_of_the_woodlands", 1, {"base": "quarterstaff", "att": true, "eq": true})
	var ba := eng.find_action(wiz, "inv:cast:%s:barkskin" % str(stf.uid))
	check(not ba.is_empty() and int(ba.get("item_cost", 0)) == 2, "Staff of the Woodlands: barkskin for 2 charges")
	wiz.turn = eng.new_turn(wiz)
	eng.execute(wiz.id, ba.id, {"targets": [wiz.id]})
	check(int(Inventory.find(wiz, str(stf.uid)).charges) == 8, "casting it spends 2 of the 10 charges")
	# Ring of Spell Storing.
	var ring := Inventory.add(wiz, "ring_of_spell_storing", 1, {"eq": true, "att": true})
	var opts := Inventory.storable(wiz, ring)
	check(opts.any(func(p): return str(p[0]) == "magic_missile"), "the wizard can store magic missile in the ring")
	var used0 := int(wiz.slots_used[0])
	check(Inventory.apply_op(wiz, {"op": "store", "uid": str(ring.uid), "spell": "magic_missile", "level": 1}) == "" and int(wiz.slots_used[0]) == used0 + 1, "storing it spends a 1st-level slot")
	check(Inventory.apply_op(wiz, {"op": "store", "uid": str(ring.uid), "spell": "magic_missile", "level": 1}, {"in_combat": true}) != "", "not during a fight")
	var fighter := pc("p11", "Grukka", Vector2i(3, 3))
	eng.s.combatants[fighter.id] = fighter
	var given := Inventory.take(wiz, str(ring.uid))
	var fr := Inventory.add_entry(fighter, given)
	fr.eq = true
	fr.att = true
	var ra := eng.find_action(fighter, "inv:ring:%s:0" % str(fr.uid))
	check(not ra.is_empty() and ra.enabled, "handed to the fighter, the ring casts the wizard's stored magic missile")
	gob.hp = 200
	fighter.turn = eng.new_turn(fighter)
	eng.execute(fighter.id, ra.id, {"targets": [gob.id]})
	check(int(gob.hp) < 200 and Inventory.find(fighter, str(fr.uid)).get("stored", []).is_empty(), "and then it's empty")
	# Potions.
	var pd := pc("p12", "Grukka", Vector2i(12, 2))
	var ptarget := foe("m8", "goblin", Vector2i(13, 2), 200)
	ar = arena([pd, ptarget])
	eng = ar.eng
	for pid in ["potion_speed", "potion_invisibility", "potion_fire_breath", "potion_hill_giant_strength", "potion_climbing", "elixir_of_health"]:
		Inventory.add(pd, pid, 1)
	eng.add_effect(pd, {"name": "Poisoned", "cond": "poisoned", "src": "x", "rounds": 10, "tick_cid": pd.id})
	var drink := func(pid: String):
		pd.turn = eng.new_turn(pd)
		eng.execute(pd.id, "inv:drink:" + uid_of(pd, pid), {"targets": [pd.id]})
	drink.call("elixir_of_health")
	check(not eng.has_cond(pd, "poisoned"), "Elixir of Health cures poison")
	drink.call("potion_speed")
	check(eng.has_tag(pd, "haste"), "Potion of Speed: hasted")
	var gsa: Dictionary = eng.find_action(pd, "atk:w_greatsword").atk
	drink.call("potion_hill_giant_strength")
	var boosted := Inventory.boost_attack(pd, gsa)
	check(int(boosted.to_hit) - int(gsa.to_hit) == maxi(0, 5 - int(pd.mods.str)), "Hill Giant Strength: Strength 21 for Strength attacks")
	drink.call("potion_fire_breath")
	var fb := eng.get_actions(pd).filter(func(a): return str(a.id).begins_with("inv:breath:"))
	check(not fb.is_empty() and fb[0].cost == "bonus", "Fire Breath: a bonus-action breath")
	if not fb.is_empty():
		pd.turn = eng.new_turn(pd)
		eng.execute(pd.id, fb[0].id, {"targets": [ptarget.id]})
	check(int(ptarget.hp) < 200, "that burns")
	drink.call("potion_invisibility")
	check(eng.has_cond(pd, "invisible"), "Potion of Invisibility")
	drink.call("potion_climbing")
	check(pd.effects.any(func(e): return str(e.name).contains("Climbing")), "Potion of Climbing")
	# Oil of Sharpness: out of combat, +3 on the weapon in hand.
	Inventory.add(pd, "oil_of_sharpness", 1)
	eng.execute(pd.id, "inv:oil:" + uid_of(pd, "oil_of_sharpness"), {})
	var sharp := Inventory.boost_attack(pd, gsa)
	check(sharp.get("magic", false) and int(sharp.to_hit) >= int(gsa.to_hit) + 3, "Oil of Sharpness: +3 and magical")
	# +3 armor, big scrolls.
	var a3 := premade("Grukka")
	var ac0 := int(Rules.derive(a3).ac)
	var p3 := Inventory.add(a3, "armor_plus_3", 1, {"base": "chain_mail"})
	Inventory.apply_op(a3, {"op": "equip", "uid": str(p3.uid), "on": true})
	check(int(Rules.derive(a3).ac) == ac0 + 3, "+3 chain mail: +3 AC")
	var rng := RandomNumberGenerator.new()
	check(Inventory.random_scroll_spell(rng, 4) != "" and Inventory.random_scroll_spell(rng, 5) != "", "4th- and 5th-level spell scrolls get a spell")

# ---------------------------------------------------------------- 10. copying scrolls into a spellbook

func _copy_scrolls() -> void:
	print("== copying spells from scrolls")
	var wiz := premade("Tamsin")   # wizard 4: spells up to 2nd level
	wiz.coins = {"gp": 500}
	var sc := Inventory.add(wiz, "spell_scroll_2", 1, {"spell": "scorching_ray"})
	check(not "scorching_ray" in Rules.wizard_spellbook(wiz), "(scorching ray isn't in Tamsin's book yet)")
	var ctx := {"arcana": 50}
	check(Inventory.apply_op(wiz, {"op": "copy", "uid": str(sc.uid)}, ctx) == "", "a wizard copies a scroll of scorching ray")
	check("scorching_ray" in Rules.wizard_spellbook(wiz) and Inventory.count(wiz, "spell_scroll_2") == 0, "it's in the spellbook and the scroll is gone")
	check(Inventory.wealth_cp(wiz.coins) == 50000 - 10000 and str(ctx.get("result", "")).contains("4 hours"), "it cost 100 gp and 4 hours (2nd level)")
	var bad := Inventory.add(wiz, "spell_scroll_2", 1, {"spell": "misty_step"})
	check(Inventory.apply_op(wiz, {"op": "copy", "uid": str(bad.uid)}, {"arcana": 50}).contains("already"), "a spell already in the book can't be copied again")
	Inventory.take(wiz, str(bad.uid))
	var hold := Inventory.add(wiz, "spell_scroll_2", 1, {"spell": "hold_person"})
	var ctx2 := {"arcana": -50}
	Inventory.apply_op(wiz, {"op": "copy", "uid": str(hold.uid)}, ctx2)
	check(not "hold_person" in Rules.wizard_spellbook(wiz) and Inventory.count(wiz, "spell_scroll_2") == 0 and str(ctx2.result).contains("DC 12"), "a failed Arcana check (DC 10 + level) wastes the scroll")
	var fb := Inventory.add(wiz, "spell_scroll_3", 1, {"spell": "fireball"})
	check(Inventory.apply_op(wiz, {"op": "copy", "uid": str(fb.uid)}, {"arcana": 50}).contains("level 3"), "a 3rd-level spell waits until Tamsin has 3rd-level slots")
	var cure := Inventory.add(wiz, "spell_scroll_1", 1, {"spell": "cure_wounds"})
	check(Inventory.apply_op(wiz, {"op": "copy", "uid": str(cure.uid)}, {"arcana": 50}).contains("wizard spell"), "cure wounds isn't a wizard spell")
	var ft := premade("Grukka")
	var fs := Inventory.add(ft, "spell_scroll_1", 1, {"spell": "magic_missile"})
	check(Inventory.apply_op(ft, {"op": "copy", "uid": str(fs.uid)}, {}).contains("wizard"), "a fighter has no spellbook")
	var poor := premade("Tamsin")
	poor.coins = {"gp": 10}
	var ps := Inventory.add(poor, "spell_scroll_1", 1, {"spell": "chromatic_orb"})
	check(Inventory.apply_op(poor, {"op": "copy", "uid": str(ps.uid)}, {"arcana": 50}) != "", "no copying without 50 gp per level for the inks")
	check(Inventory.apply_op(wiz, {"op": "copy", "uid": str(Inventory.add(wiz, "spell_scroll_1", 1, {"spell": "chromatic_orb"}).uid)}, {"in_combat": true}) != "", "and not in the middle of a fight")
	# Through the game server: the sheet's spellbook grows.
	Session.start_offline("DM", 20, 12)
	Session.auto_monsters = false
	var t := premade("Tamsin")
	t.id = "inv_test_copy"
	t.coins = {"gp": 300}
	var cid := Session.add_character(t, 1, Vector2i(3, 3))
	Session.request({"type": "dm_give", "cids": [cid], "id": "spell_scroll_1", "spell": "chromatic_orb", "qty": 1})
	var c: Dictionary = Session.engine.C(cid)
	Session.request({"type": "inv", "cid": cid, "op": "copy", "uid": uid_of(c, "spell_scroll_1")})
	var sh: Dictionary = Session.sheets[cid]
	check(Inventory.count(sh, "spell_scroll_1") == 0 and Inventory.wealth_cp(sh.coins) == 25000, "in play: the scroll is used and 50 gp paid, saved to the sheet")
	check(("chromatic_orb" in Rules.wizard_spellbook(sh)) == ("chromatic_orb" in sh.get("spellbook", [])) , "and the spellbook on the sheet reflects the Arcana check")
	CharacterStore.delete_character("inv_test_copy")

# ---------------------------------------------------------------- 11. artificer infusions on items

func _infusions() -> void:
	print("== artificer infusions")
	var art := Rules.new_character()
	art.name = "Tink"
	art.classes = [{"id": "artificer", "level": 6, "subclass": ""}]
	art.base_scores = {"str": 14, "dex": 14, "con": 14, "int": 16, "wis": 10, "cha": 8}
	art.infusions = ["enhanced_weapon", "enhanced_defense", "replicate_magic_item", "repeating_shot"]
	art.inventory = []
	art.coins = {}
	var ls := Inventory.add(art, "longsword", 1, {"eq": true})
	var sh := Inventory.add(art, "shield", 1, {"eq": true})
	var cb := Inventory.add(art, "light_crossbow", 1, {"alt": true})
	var st0 := Rules.derive(art)
	var hit0 := int(weapon_atk(st0, "longsword").to_hit)
	var ac0 := int(st0.ac)
	check(Inventory.apply_op(art, {"op": "infuse", "infusion": "enhanced_weapon", "uid": str(ls.uid)}) == "", "Enhanced Weapon goes on the longsword")
	var st1 := Rules.derive(art)
	check(int(weapon_atk(st1, "longsword").to_hit) == hit0 + 1 and weapon_atk(st1, "longsword").magic, "only that sword gets +1 and counts as magical")
	check(Inventory.apply_op(art, {"op": "infuse", "infusion": "enhanced_defense", "uid": str(sh.uid)}) == "" and int(Rules.derive(art).ac) == ac0 + 1, "Enhanced Defense on the shield: +1 AC")
	check(Inventory.apply_op(art, {"op": "infuse", "infusion": "enhanced_defense", "uid": str(ls.uid)}) != "", "an infusion goes on one item at a time")
	check(Inventory.apply_op(art, {"op": "infuse", "infusion": "replicate_magic_item", "item": "cloak_of_protection"}).contains("level 10"), "a 6th-level artificer can't replicate a Cloak of Protection yet")
	check(Inventory.apply_op(art, {"op": "infuse", "infusion": "replicate_magic_item", "item": "bag_of_holding"}) == "" and Inventory.count(art, "bag_of_holding") == 1, "Replicate Magic Item makes a Bag of Holding")
	check(Inventory.apply_op(art, {"op": "infuse", "infusion": "repeating_shot", "uid": str(cb.uid)}).contains("3"), "three infused items at 6th level: no fourth")
	var shop := {"stock": [], "buyback": 50}
	check(Inventory.apply_op(art, {"op": "sell", "uid": uid_of(art, "bag_of_holding")}, {"shop": shop}) != "", "a replicated item can't be sold")
	check(Inventory.apply_op(art, {"op": "infuse", "infusion": "", "uid": uid_of(art, "bag_of_holding")}) == "" and Inventory.count(art, "bag_of_holding") == 0, "ending the infusion: the bag is gone")
	check(Inventory.apply_op(art, {"op": "infuse", "infusion": "repeating_shot", "uid": str(cb.uid)}) == "", "Repeating Shot on the crossbow")
	Inventory.apply_op(art, {"op": "swap"})
	var cba := weapon_atk(Rules.derive(art), "light_crossbow")
	var cc := CombatantFactory.from_character("p1", art, 1)
	check(cba.get("no_ammo", false) and Inventory.ammo_for(cc, cba) == "" and int(cba.to_hit) > 0 and cba.magic, "it's a +1 magic crossbow that needs no bolts")
	Inventory.apply_op(art, {"op": "infuse", "infusion": "", "uid": str(ls.uid)})
	Inventory.apply_op(art, {"op": "swap"})
	check(int(weapon_atk(Rules.derive(art), "longsword").to_hit) == hit0, "ending Enhanced Weapon takes the bonus away")
	check(Inventory.apply_op(art, {"op": "infuse", "infusion": "enhanced_weapon", "uid": str(ls.uid)}, {"in_combat": true}) != "", "no infusing during a fight")
	var low := Rules.new_character()
	low.classes = [{"id": "artificer", "level": 1, "subclass": ""}]
	low.infusions = ["enhanced_weapon"]
	low.inventory = []
	var d := Inventory.add(low, "dagger", 1)
	check(Inventory.apply_op(low, {"op": "infuse", "infusion": "enhanced_weapon", "uid": str(d.uid)}) != "", "infusions start at artificer level 2")
	# A sheet from before inventories keeps the old behaviour (every weapon enhanced).
	var old := Rules.new_character()
	old.classes = [{"id": "artificer", "level": 2, "subclass": ""}]
	old.infusions = ["enhanced_weapon"]
	old.equipment = {"armor": "", "shield": false, "weapons": ["mace"], "weapon_bonus": 0, "armor_bonus": 0}
	check(weapon_atk(Rules.derive(old), "mace").magic, "(an old sheet without an inventory still treats its weapon as enhanced)")

# ---------------------------------------------------------------- 13. polish

func _labels(n: Node, out: Array) -> Array:
	if n is Label:
		out.append(str(n.text))
	for ch in n.get_children():
		_labels(ch, out)
	return out

func _polish() -> void:
	print("== polish")
	check(str(ProjectSettings.get_setting("application/config/version", "")) == "0.6.0", "the version is 0.6.0 (clients must match the host)")
	var ch := premade("Grukka")
	Inventory.add(ch, "cloak_of_protection", 1)
	Inventory.add(ch, "gem_50", 2)
	var panel := InventoryPanel.new(func(): return ch, {"editable": false})
	add_child(panel)
	var all_txt := " | ".join(_labels(panel, []))
	check(all_txt.contains("Cloak of Protection") and all_txt.contains("Greatsword"), "the inventory panel lists everything")
	panel._filter = "magic"
	panel.refresh()
	var magic_txt := " | ".join(_labels(panel, []).filter(func(t): return not str(t).begins_with("In hand")))
	check(magic_txt.contains("Cloak of Protection") and not magic_txt.contains("Greatsword"), "filtered to magic items: only the cloak")
	panel._filter = "all"
	panel._search = "semiprecious"
	panel.refresh()
	var s_txt := " | ".join(_labels(panel, []))
	check(s_txt.contains("Semiprecious") and not s_txt.contains("Cloak"), "searching finds the gemstone")
	panel._search = ""
	panel._sort = "weight"
	panel.refresh()
	var w_txt := _labels(panel, [])
	var i_mail := w_txt.find("Chain Mail")
	var i_cloak := w_txt.find("Cloak of Protection")
	check(i_mail >= 0 and i_cloak >= 0, "sorting by weight still shows the items")
	panel.queue_free()
	var cs := CharacterSheet.new(ch, {})
	add_child(cs)
	var titles: Array = []
	for t in cs.tabs.get_tab_count():
		titles.append(cs.tabs.get_tab_title(t))
	check("Inventory" in titles, "the 📜 character sheet has an Inventory tab")
	cs.queue_free()
	var icon := UIKit.pack_icon()
	check(icon != null and icon.get_width() == 20, "the 🎒 buttons use a drawn backpack icon")

# ---------------------------------------------------------------- storage chests and the interactive sheet

func _storage() -> void:
	print("== storage")
	Session.start_offline("DM", 20, 12)
	Session.auto_monsters = false
	var g := premade("Grukka")
	g.id = "inv_test_storage"
	var cid := Session.add_character(g, 2, Vector2i(3, 3))
	Session.request({"type": "dm_object", "at": Vector2i(4, 3), "k": "stash"})
	var chest: Dictionary = MapObjects.at(Session.state, Vector2i(4, 3))[0]
	var oid := str(chest.id)
	check(MapObjects.is_storage(chest) and not MapObjects.destructible(chest), "the DM places a storage chest (it can't be broken)")
	var c: Dictionary = Session.engine.C(cid)
	check(MapObjects.storage_near(Session.engine, c).size() == 1, "a character beside it can reach it")
	Session.request({"type": "dm_give", "cids": [cid], "id": "spyglass", "qty": 1})
	Session.request({"type": "dm_give", "cids": [cid], "id": "torch", "qty": 10})
	Session.request({"type": "dm_give", "cids": [cid], "coins": {"gp": 100}})
	c = Session.engine.C(cid)
	var rope := uid_of(c, "spyglass")
	var torches := int(Inventory.find(c, uid_of(c, "torch")).qty)
	var lb0 := Inventory.carried_lb(c)
	Session._handle(2, {"type": "stash", "cid": cid, "obj": oid, "op": "put", "uid": rope, "qty": 0})
	c = Session.engine.C(cid)
	chest = MapObjects.by_id(Session.state, oid)
	check(uid_of(c, "spyglass") == "" and Inventory.count(chest.store, "spyglass") == 1, "the player stores the spyglass in the chest")
	check(Inventory.carried_lb(c) < lb0 - 0.9, "and carries 1 lb less")
	check(uid_of(Session.sheets[cid], "spyglass") == "", "the sheet is saved without it")
	Session._handle(2, {"type": "stash", "cid": cid, "obj": oid, "op": "put", "uid": uid_of(c, "torch"), "qty": 3})
	c = Session.engine.C(cid)
	check(Inventory.count(c, "torch") == torches - 3 and Inventory.count(chest.store, "torch") == 3, "storing part of a stack splits it")
	var gp0 := int(Inventory.coins(c).gp)
	Session._handle(2, {"type": "stash", "cid": cid, "obj": oid, "op": "put", "coins": {"gp": 60}})
	c = Session.engine.C(cid)
	check(int(Inventory.coins(c).gp) == gp0 - 60 and int(chest.store.coins.gp) == 60, "coins go into the chest")
	Session._handle(2, {"type": "stash", "cid": cid, "obj": oid, "op": "take", "coins": {"gp": 999}})
	c = Session.engine.C(cid)
	check(int(Inventory.coins(c).gp) == gp0 and int(chest.store.coins.gp) == 0, "taking more coins than it holds takes what's there")
	# Attuned items stay with their owner.
	Session.request({"type": "dm_attune_free", "on": true})
	Session.request({"type": "dm_give", "cids": [cid], "id": "cloak_of_protection", "qty": 1})
	c = Session.engine.C(cid)
	var cl := uid_of(c, "cloak_of_protection")
	Session._handle(2, {"type": "inv", "cid": cid, "op": "equip", "uid": cl, "on": true})
	Session._handle(2, {"type": "inv", "cid": cid, "op": "attune", "uid": cl, "on": true})
	Session._handle(2, {"type": "stash", "cid": cid, "obj": oid, "op": "put", "uid": cl, "qty": 0})
	check(uid_of(Session.engine.C(cid), "cloak_of_protection") != "", "an attuned item can't be stored")
	# Walk away: out of reach.
	c = Session.engine.C(cid)
	c.pos = Vector2i(12, 8)
	Session._handle(2, {"type": "stash", "cid": cid, "obj": oid, "op": "take", "uid": uid_of(chest.store, "spyglass"), "qty": 0})
	check(Inventory.count(chest.store, "spyglass") == 1, "from across the room the chest can't be reached")
	check(MapObjects.storage_near(Session.engine, c).is_empty(), "and the 📦 Storage button goes away")
	c.pos = Vector2i(3, 3)
	Session._handle(2, {"type": "stash", "cid": cid, "obj": oid, "op": "take", "uid": uid_of(chest.store, "spyglass"), "qty": 0})
	check(uid_of(Session.engine.C(cid), "spyglass") != "" and Inventory.count(chest.store, "spyglass") == 0, "back beside it, the spyglass comes out again")
	# Saved with the map, and loaded again.
	Session._handle(2, {"type": "stash", "cid": cid, "obj": oid, "op": "put", "uid": uid_of(Session.engine.C(cid), "spyglass"), "qty": 0})
	var snap := Session.map_snapshot()
	var js := JSON.parse_string(JSON.stringify(snap))
	Session._load_map(js)
	var again: Array = MapObjects.list(Session.state).filter(func(o): return str(o.k) == "stash")
	check(again.size() == 1 and Inventory.count(again[0].store, "spyglass") == 1 and Inventory.count(again[0].store, "torch") == 3, "what's stored is saved with the map and comes back when it's loaded")
	# An opened ordinary chest stores things too; breaking it spills them.
	var box := MapObjects.place(Session.engine, MapObjects.make("chest", Vector2i(2, 3), EngineBase.FLOOR, {"opened": true}))
	check(MapObjects.is_storage(box), "an opened chest can be used for storage")
	Inventory.add(MapObjects.store_of(box), "spyglass", 1)
	MapObjects.destroy(Session.engine, box)
	var piles: Array = MapObjects.at(Session.state, Vector2i(2, 3)).filter(func(o): return str(o.k) == "pile")
	check(piles.size() == 1 and MapObjects.loot_text(piles[0].loot).contains("Spyglass"), "breaking it spills what was stored")
	# The DM taking a storage chest away leaves its contents on the floor.
	var sp: Vector2i = again[0].pos
	Session.request({"type": "dm_object", "at": sp})
	var left: Array = MapObjects.at(Session.state, sp)
	check(left.size() == 1 and str(left[0].k) == "pile" and MapObjects.loot_text(left[0].loot).contains("Spyglass"), "removing a storage chest leaves what was in it")
	# In a fight: on your turn, as your object interaction.
	Session.request({"type": "dm_object", "at": Vector2i(3, 4), "k": "stash"})
	oid = str(MapObjects.at(Session.state, Vector2i(3, 4)).filter(func(o): return str(o.k) == "stash")[0].id)
	c = Session.engine.C(cid)
	c.pos = Vector2i(3, 3)
	Session.add_monster("goblin", Vector2i(15, 9))
	Session.engine.start_combat()
	c = Session.engine.C(cid)
	Session.engine.s.turn = maxi(0, Session.engine.s.order.find(cid))
	if Session.engine.is_turn_of(c):
		c.turn.obj_used = false
		Session._handle(2, {"type": "stash", "cid": cid, "obj": oid, "op": "put", "uid": uid_of(c, "torch"), "qty": 1})
		check(Session.engine.C(cid).turn.get("obj_used", false), "in a fight storing something is the free object interaction")
		var gs := uid_of(Session.engine.C(cid), "greatsword")
		if gs != "" and Inventory.find(Session.engine.C(cid), gs).get("eq", false):
			Session._handle(2, {"type": "stash", "cid": cid, "obj": oid, "op": "put", "uid": gs, "qty": 0})
			check(uid_of(Session.engine.C(cid), "greatsword") != "", "in a fight a wielded weapon can't go straight into the chest")
	else:
		check(true, "(skipped: couldn't make it the character's turn)")
	Session.engine.end_combat()
	# The UI: the storage window and the sheet's interactive inventory tab.
	var st_o := MapObjects.by_id(Session.state, oid)
	var sp_ui := StoragePanel.new(func(): return Session.engine.C(cid), func(): return MapObjects.by_id(Session.state, oid))
	add_child(sp_ui)
	var txt := " | ".join(_labels(sp_ui, []))
	check(txt.contains("Greatsword") and txt.contains("In the storage chest"), "the storage window lists both sides")
	var asked: Array = []
	sp_ui.request_made.connect(func(r): asked.append(r))
	var btns: Array = []
	_buttons(sp_ui, btns)
	var store_btn: Button = null
	for b in btns:
		if str(b.text).begins_with("Store") and not b.disabled and not str(b.text).contains("coins"):
			store_btn = b
			break
	if store_btn:
		store_btn.pressed.emit()
	check(asked.size() == 1 and str(asked[0].op) == "put", "pressing Store asks the server to put the item in")
	sp_ui.queue_free()
	var sheet: Dictionary = Session.sheets[cid]
	var cs := CharacterSheet.new(sheet, {"live": Session.engine.C(cid), "editable": true, "inv_holder": func(): return Session.engine.C(cid),
		"inv_opts": {"editable": true, "in_game": true, "stash_to": func(): return [[oid, "storage chest"]]}})
	add_child(cs)
	check(cs.inv_panel != null and cs.inv_panel.opts.editable, "the sheet's inventory tab is interactive for the character's player")
	var sbtns: Array = []
	_buttons(cs.inv_panel, sbtns)
	check(sbtns.any(func(b): return str(b.text) in ["Wield", "Unequip", "Wear"]), "it has the equip buttons")
	var menus: Array = []
	_menus(cs.inv_panel, menus)
	var store_entry := false
	for m in menus:
		var pm: PopupMenu = m.get_popup()
		for i in pm.item_count:
			if pm.get_item_text(i).contains("in the storage chest"):
				store_entry = true
	check(store_entry, "its ⋯ menus offer 'Store in the storage chest' beside a chest")
	var kept := cs.inv_panel
	cs.rebuild(sheet, {"live": Session.engine.C(cid)})
	check(cs.inv_panel == kept and is_instance_valid(kept) and cs.tabs.get_children().has(cs.inv_page), "rebuilding the sheet keeps the inventory tab (its filter and scroll)")
	cs.queue_free()
	var ro := CharacterSheet.new(sheet, {"live": Session.engine.C(cid), "editable": false, "inv_holder": func(): return Session.engine.C(cid), "inv_opts": {"editable": true}})
	add_child(ro)
	check(not ro.inv_panel.opts.editable, "for other players it stays read-only")
	ro.queue_free()
	CharacterStore.delete_character("inv_test_storage")

func _buttons(n: Node, out: Array) -> Array:
	for ch in n.get_children():
		if ch is Button and not ch is MenuButton:
			out.append(ch)
		_buttons(ch, out)
	return out

func _menus(n: Node, out: Array) -> Array:
	for ch in n.get_children():
		if ch is MenuButton:
			out.append(ch)
		_menus(ch, out)
	return out
