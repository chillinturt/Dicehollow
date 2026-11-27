extends Node
## Saves characters, maps and portraits under user:// and caches portrait textures.

const CHAR_DIR := "user://characters"
const PORTRAIT_DIR := "user://portraits"
const MAP_DIR := "user://maps"
const PORTRAIT_SIZE := 256
const MONSTER_DIR := "user://monsters"
const BG_DIR := "user://backgrounds"
const BG_MAX := 2560

var _tex_cache := {}
var portrait_bytes := {}  # key -> PackedByteArray (received over the network or loaded)
var bg_bytes := {}   # key -> jpg bytes
var _bg_cache := {}

func _ready() -> void:
	for d in [CHAR_DIR, PORTRAIT_DIR, MAP_DIR, MONSTER_DIR, BG_DIR]:
		DirAccess.make_dir_recursive_absolute(d)
	for m in list_custom_monsters():
		Data.register_monster(m)

func new_id() -> String:
	var s = ""
	for i in 16:
		s += "%x" % Dice.rng.randi_range(0, 15)
	return s

# ---------------------------------------------------------------- characters

func list_characters() -> Array:
	var out: Array = []
	var dir = DirAccess.open(CHAR_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".json"):
			var ch = Data.normalize(JSON.parse_string(FileAccess.get_file_as_string(CHAR_DIR + "/" + f)))
			if ch is Dictionary:
				out.append(ch)
	out.sort_custom(func(a, b): return str(a.get("name", "")).naturalnocasecmp_to(str(b.get("name", ""))) < 0)
	return out

func save_character(ch: Dictionary) -> void:
	if ch.get("id", "") == "":
		ch.id = new_id()
	var f = FileAccess.open(CHAR_DIR + "/" + ch.id + ".json", FileAccess.WRITE)
	f.store_string(JSON.stringify(ch, "\t"))

func delete_character(id: String) -> void:
	DirAccess.remove_absolute(CHAR_DIR + "/" + id + ".json")

func get_character(id: String) -> Dictionary:
	var p = CHAR_DIR + "/" + id + ".json"
	if not FileAccess.file_exists(p):
		return {}
	var ch = Data.normalize(JSON.parse_string(FileAccess.get_file_as_string(p)))
	return ch if ch is Dictionary else {}

# ---------------------------------------------------------------- portraits

## Import any image file as a square 256px portrait. Returns the portrait key or "".
func import_portrait(path: String) -> String:
	var img = Image.load_from_file(path)
	if img == null or img.is_empty():
		return ""
	var side = mini(img.get_width(), img.get_height())
	var x = (img.get_width() - side) / 2
	var y = (img.get_height() - side) / 4  # bias towards the top (faces)
	img = img.get_region(Rect2i(x, y, side, side))
	img.resize(PORTRAIT_SIZE, PORTRAIT_SIZE, Image.INTERPOLATE_LANCZOS)
	img.convert(Image.FORMAT_RGBA8)
	var key = new_id()
	img.save_png(PORTRAIT_DIR + "/" + key + ".png")
	return key

func get_portrait_bytes(key: String) -> PackedByteArray:
	if key == "":
		return PackedByteArray()
	if portrait_bytes.has(key):
		return portrait_bytes[key]
	var p = PORTRAIT_DIR + "/" + key + ".png"
	if FileAccess.file_exists(p):
		var b = FileAccess.get_file_as_bytes(p)
		portrait_bytes[key] = b
		return b
	return PackedByteArray()

func register_portrait(key: String, bytes: PackedByteArray) -> void:
	if key == "" or bytes.is_empty():
		return
	portrait_bytes[key] = bytes
	_tex_cache.erase(key)

func portrait_texture(key: String) -> Texture2D:
	if key == "":
		return null
	if _tex_cache.has(key):
		return _tex_cache[key]
	var bytes = get_portrait_bytes(key)
	if bytes.is_empty():
		return null
	var img = Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		return null
	var tex = ImageTexture.create_from_image(img)
	_tex_cache[key] = tex
	return tex

# ---------------------------------------------------------------- maps

func list_maps() -> Array:
	var out: Array = []
	var dir = DirAccess.open(MAP_DIR)
	if dir:
		for f in dir.get_files():
			if f.ends_with(".json"):
				out.append(f.get_basename())
	out.sort()
	return out

func save_map(name: String, data: Dictionary) -> void:
	var f = FileAccess.open(MAP_DIR + "/" + name.validate_filename() + ".json", FileAccess.WRITE)
	f.store_string(JSON.stringify(data))

func load_map(name: String) -> Dictionary:
	var p = MAP_DIR + "/" + name + ".json"
	if not FileAccess.file_exists(p):
		return {}
	var d = Data.normalize(JSON.parse_string(FileAccess.get_file_as_string(p)))
	return d if d is Dictionary else {}


# ---------------------------------------------------------------- custom monsters

func list_custom_monsters() -> Array:
	var out: Array = []
	var dir = DirAccess.open(MONSTER_DIR)
	if dir:
		for f in dir.get_files():
			if f.ends_with(".json"):
				var m = Data.normalize(JSON.parse_string(FileAccess.get_file_as_string(MONSTER_DIR + "/" + f)))
				if m is Dictionary and m.has("id"):
					out.append(m)
	return out

func save_custom_monster(m: Dictionary) -> void:
	var f = FileAccess.open(MONSTER_DIR + "/" + str(m.id).validate_filename() + ".json", FileAccess.WRITE)
	f.store_string(JSON.stringify(m, "\t"))
	Data.register_monster(m)

func delete_custom_monster(id: String) -> void:
	DirAccess.remove_absolute(MONSTER_DIR + "/" + id.validate_filename() + ".json")
	Data.unregister_monster(id)

# ---------------------------------------------------------------- map backgrounds

## Import an image as a map background (downscaled to BG_MAX px on the long side). Returns its key or "".
func import_background(path: String) -> String:
	var img = Image.load_from_file(path)
	if img == null or img.is_empty():
		return ""
	var big = maxi(img.get_width(), img.get_height())
	if big > BG_MAX:
		var f = float(BG_MAX) / big
		img.resize(maxi(1, int(img.get_width() * f)), maxi(1, int(img.get_height() * f)), Image.INTERPOLATE_LANCZOS)
	img.convert(Image.FORMAT_RGB8)
	var key = new_id()
	var bytes = img.save_jpg_to_buffer(0.88)
	var f2 = FileAccess.open(BG_DIR + "/" + key + ".jpg", FileAccess.WRITE)
	f2.store_buffer(bytes)
	bg_bytes[key] = bytes
	return key

func get_bg_bytes(key: String) -> PackedByteArray:
	if key == "":
		return PackedByteArray()
	if bg_bytes.has(key):
		return bg_bytes[key]
	var p = BG_DIR + "/" + key.validate_filename() + ".jpg"
	if FileAccess.file_exists(p):
		bg_bytes[key] = FileAccess.get_file_as_bytes(p)
		return bg_bytes[key]
	return PackedByteArray()

func register_bg(key: String, bytes: PackedByteArray) -> void:
	if key == "" or bytes.is_empty():
		return
	bg_bytes[key] = bytes
	_bg_cache.erase(key)

func bg_texture(key: String) -> Texture2D:
	if key == "":
		return null
	if _bg_cache.has(key):
		return _bg_cache[key]
	var bytes = get_bg_bytes(key)
	if bytes.is_empty():
		return null
	var img = Image.new()
	if img.load_jpg_from_buffer(bytes) != OK:
		return null
	var tex = ImageTexture.create_from_image(img)
	_bg_cache[key] = tex
	return tex

# ---------------------------------------------------------------- premade characters

func premades() -> Array:
	var out: Array = []
	# Based on C:\D&D\scribe-artificer-sheet.html (Artificer 1 / Order of Scribes wizard).
	var scribe = Rules.new_character()
	scribe.merge({"name": "Quill (Scribe Artificer)", "race": "variant_human", "race_asi_choice": ["con", "int"], "background": "sage",
		"base_scores": {"str": 8, "dex": 14, "con": 15, "int": 15, "wis": 10, "cha": 8}, "feats": ["lucky"],
		"classes": [{"id": "artificer", "level": 1, "subclass": ""}, {"id": "wizard", "level": 4, "subclass": "scribes"}],
		"asi": [{"class": "wizard", "level": 4, "type": "asi", "a": "int", "b": "int"}],
		"skills": ["investigation", "perception", "insight"],
		"spells": {"artificer": ["guidance", "magic_stone", "cure_wounds", "faerie_fire", "sanctuary"],
			"wizard": ["fire_bolt", "mind_sliver", "minor_illusion", "mage_hand", "shield", "sleep", "magic_missile", "absorb_elements", "web", "misty_step", "tashas_mind_whip", "dragons_breath"]},
		"spellbook": ["shield", "find_familiar", "sleep", "magic_missile", "absorb_elements", "detect_magic", "chromatic_orb", "tashas_hideous_laughter", "web", "misty_step", "tashas_mind_whip", "dragons_breath"],
		"equipment": {"armor": "scale_mail", "shield": true, "weapons": ["light_crossbow", "dagger"], "weapon_bonus": 0, "armor_bonus": 0},
		"color": "#c08a3e"}, true)
	out.append(scribe)
	# Based on C:\D&D\chronurgist-sheet.html (Artificer 1 / Chronurgy wizard).
	var chrono = Rules.new_character()
	chrono.merge({"name": "Tamsin (Chronurgist)", "race": "variant_human", "race_asi_choice": ["con", "int"], "background": "sage",
		"base_scores": {"str": 8, "dex": 14, "con": 15, "int": 15, "wis": 10, "cha": 8}, "feats": ["lucky"],
		"classes": [{"id": "artificer", "level": 1, "subclass": ""}, {"id": "wizard", "level": 4, "subclass": "chronurgy"}],
		"asi": [{"class": "wizard", "level": 4, "type": "asi", "a": "int", "b": "int"}],
		"skills": ["investigation", "perception", "insight"],
		"spells": {"artificer": ["guidance", "magic_stone", "cure_wounds", "faerie_fire", "sanctuary"],
			"wizard": ["mind_sliver", "toll_the_dead", "minor_illusion", "ray_of_frost", "shield", "sleep", "magic_missile", "absorb_elements", "tashas_hideous_laughter", "web", "rope_trick", "misty_step"]},
		"spellbook": ["shield", "sleep", "magic_missile", "find_familiar", "absorb_elements", "comprehend_languages", "gift_of_alacrity", "tashas_hideous_laughter", "web", "rope_trick", "tashas_mind_whip", "misty_step"],
		"equipment": {"armor": "scale_mail", "shield": true, "weapons": ["light_crossbow", "dagger"], "weapon_bonus": 0, "armor_bonus": 0},
		"color": "#4a3fc9"}, true)
	out.append(chrono)
	var cleric = Rules.new_character()
	cleric.merge({"name": "Brannoc (Twilight Cleric)", "race": "dwarf", "subrace": "hill", "background": "acolyte",
		"base_scores": {"str": 14, "dex": 10, "con": 14, "int": 8, "wis": 15, "cha": 10},
		"classes": [{"id": "cleric", "level": 5, "subclass": "twilight"}],
		"asi": [{"class": "cleric", "level": 4, "type": "asi", "a": "wis", "b": "wis"}],
		"skills": ["medicine", "persuasion"],
		"spells": {"cleric": ["sacred_flame", "toll_the_dead", "guidance", "thaumaturgy", "bless", "healing_word", "cure_wounds", "guiding_bolt", "spiritual_weapon", "aid", "spirit_guardians", "revivify", "mass_healing_word"]},
		"equipment": {"armor": "chain_mail", "shield": true, "weapons": ["warhammer", "light_crossbow"], "weapon_bonus": 0, "armor_bonus": 0},
		"color": "#3a5a9f"}, true)
	out.append(cleric)
	var fighter = Rules.new_character()
	fighter.merge({"name": "Grukka (Battle Master)", "race": "half_orc", "background": "soldier",
		"base_scores": {"str": 15, "dex": 13, "con": 14, "int": 8, "wis": 12, "cha": 10},
		"classes": [{"id": "fighter", "level": 5, "subclass": "battle_master"}],
		"asi": [{"class": "fighter", "level": 4, "type": "feat", "feat": "great_weapon_master"}],
		"skills": ["perception", "survival"], "fighting_styles": ["great_weapon_fighting"], "maneuvers": ["precision", "trip", "riposte"],
		"equipment": {"armor": "chain_mail", "shield": false, "weapons": ["greatsword", "javelin"], "weapon_bonus": 0, "armor_bonus": 0},
		"color": "#7a3a2a"}, true)
	out.append(fighter)
	var rogue = Rules.new_character()
	rogue.merge({"name": "Pip (Swashbuckler)", "race": "halfling", "subrace": "lightfoot", "background": "urchin",
		"base_scores": {"str": 8, "dex": 15, "con": 14, "int": 10, "wis": 12, "cha": 13},
		"classes": [{"id": "rogue", "level": 5, "subclass": "swashbuckler"}],
		"asi": [{"class": "rogue", "level": 4, "type": "asi", "a": "dex", "b": "dex"}],
		"skills": ["acrobatics", "perception", "deception", "persuasion"], "expertise": ["stealth", "perception"],
		"equipment": {"armor": "studded_leather", "shield": false, "weapons": ["rapier", "dagger", "shortbow"], "weapon_bonus": 0, "armor_bonus": 0},
		"color": "#2f7a4a"}, true)
	out.append(rogue)
	var paladin = Rules.new_character()
	paladin.merge({"name": "Seraphine (Vengeance Paladin)", "race": "dragonborn", "subrace": "gold", "background": "noble",
		"base_scores": {"str": 15, "dex": 8, "con": 13, "int": 8, "wis": 12, "cha": 15},
		"classes": [{"id": "paladin", "level": 5, "subclass": "vengeance"}],
		"asi": [{"class": "paladin", "level": 4, "type": "asi", "a": "str", "b": "cha"}],
		"skills": ["athletics", "intimidation"], "fighting_styles": ["defense"],
		"spells": {"paladin": ["bless", "cure_wounds", "shield_of_faith", "divine_favor", "find_steed", "aid"]},
		"equipment": {"armor": "chain_mail", "shield": true, "weapons": ["longsword", "javelin"], "weapon_bonus": 0, "armor_bonus": 0},
		"color": "#c9a14a"}, true)
	out.append(paladin)
	return out
