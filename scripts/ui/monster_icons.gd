class_name MonsterIcons
## Built-in silhouette icons for common monster families, drawn on tokens that have no portrait.
## Icons are white shapes (with darker detail) in a 64x64 viewBox, rasterised once at runtime.
## A monster picks its icon from the optional "icon" field in monsters.json, else from BY_MONSTER.

const W := "fill='#fff'"
const D := "fill='#000' fill-opacity='.55'"

const SVG := {
	"wolf": "<path " + W + " d='M12 6 L26 21 L38 21 L52 6 L54 30 L45 41 L38 54 L32 58 L26 54 L19 41 L10 30 Z'/>"
		+ "<path " + D + " d='M15 12 L23 21 L17 24 Z M49 12 L41 21 L47 24 Z M20 29 L29 32 L22 34 Z M44 29 L35 32 L42 34 Z'/>"
		+ "<ellipse " + D + " cx='32' cy='50' rx='4.5' ry='3'/>",
	"kobold": "<path " + W + " d='M22 22 Q14 14 10 3 Q20 10 27 18 Z M42 22 Q50 14 54 3 Q44 10 37 18 Z'/>"
		+ "<path " + W + " d='M18 30 L8 28 L17 38 Z M46 30 L56 28 L47 38 Z'/>"
		+ "<ellipse " + W + " cx='32' cy='32' rx='14' ry='15'/><ellipse " + W + " cx='32' cy='46' rx='9' ry='13'/>"
		+ "<ellipse " + D + " cx='25' cy='30' rx='3.5' ry='4.5'/><ellipse " + D + " cx='39' cy='30' rx='3.5' ry='4.5'/>"
		+ "<circle " + D + " cx='29' cy='53' r='1.5'/><circle " + D + " cx='35' cy='53' r='1.5'/>",
	"goblin": "<path " + W + " d='M21 27 L2 17 L20 41 Z M43 27 L62 17 L44 41 Z'/>"
		+ "<ellipse " + W + " cx='32' cy='34' rx='13' ry='16'/>"
		+ "<path " + D + " d='M22 29 L30 31 L23 34 Z M42 29 L34 31 L41 34 Z M24 44 L27 47 L30 44 L34 47 L37 44 L40 45 L32 50 Z'/>",
	"orc": "<path " + W + " d='M18 14 Q32 6 46 14 L48 36 Q46 52 32 57 Q18 52 16 36 Z M17 26 L8 22 L16 33 Z M47 26 L56 22 L48 33 Z'/>"
		+ "<path " + D + " d='M20 25 L30 27 L28 31 L21 30 Z M44 25 L34 27 L36 31 L43 30 Z'/>"
		+ "<rect " + D + " x='21' y='40' width='22' height='9' rx='3'/>"
		+ "<path " + W + " d='M23 49 L25 36 L28 49 Z M41 49 L39 36 L36 49 Z'/>",
	"skull": "<circle " + W + " cx='32' cy='28' r='20'/><rect " + W + " x='21' y='38' width='22' height='18' rx='4'/>"
		+ "<circle " + D + " cx='24' cy='30' r='6'/><circle " + D + " cx='40' cy='30' r='6'/>"
		+ "<path " + D + " d='M32 36 L28 43 L36 43 Z'/>"
		+ "<rect " + D + " x='26' y='47' width='2' height='9'/><rect " + D + " x='31' y='47' width='2' height='9'/><rect " + D + " x='36' y='47' width='2' height='9'/>",
	"ghost": "<path " + W + " d='M14 58 L14 28 A18 18 0 0 1 50 28 L50 58 L44 52 L38 58 L32 52 L26 58 L20 52 Z'/>"
		+ "<ellipse " + D + " cx='25' cy='28' rx='4' ry='6'/><ellipse " + D + " cx='39' cy='28' rx='4' ry='6'/>"
		+ "<ellipse " + D + " cx='32' cy='42' rx='4' ry='5'/>",
	"spider": "<g fill='none' stroke='#fff' stroke-width='3' stroke-linejoin='round' stroke-linecap='round'>"
		+ "<path d='M27 22 L15 11 L9 19 M26 26 L11 22 L5 32 M26 32 L11 36 L7 48 M27 38 L16 46 L14 58'/>"
		+ "<path d='M37 22 L49 11 L55 19 M38 26 L53 22 L59 32 M38 32 L53 36 L57 48 M37 38 L48 46 L50 58'/></g>"
		+ "<circle " + W + " cx='32' cy='21' r='7'/><ellipse " + W + " cx='32' cy='40' rx='11' ry='13'/>"
		+ "<circle " + D + " cx='29.5' cy='19' r='1.6'/><circle " + D + " cx='34.5' cy='19' r='1.6'/>"
		+ "<path " + D + " d='M32 33 L35 39 L32 45 L29 39 Z'/>",
	"rat": "<path fill='none' stroke='#fff' stroke-width='3' stroke-linecap='round' d='M50 42 Q62 50 54 58 Q48 62 40 58'/>"
		+ "<ellipse " + W + " cx='35' cy='38' rx='18' ry='12'/><path " + W + " d='M24 29 L4 41 L24 48 Z'/>"
		+ "<circle " + W + " cx='22' cy='26' r='6'/><circle " + D + " cx='22' cy='26' r='3'/>"
		+ "<circle " + D + " cx='14' cy='37' r='1.8'/><circle " + W + " cx='4' cy='41' r='2'/>"
		+ "<rect " + W + " x='24' y='46' width='4' height='7' rx='2'/><rect " + W + " x='42' y='46' width='4' height='7' rx='2'/>",
	"bear": "<circle " + W + " cx='16' cy='17' r='8'/><circle " + W + " cx='48' cy='17' r='8'/>"
		+ "<circle " + D + " cx='16' cy='17' r='4'/><circle " + D + " cx='48' cy='17' r='4'/>"
		+ "<circle " + W + " cx='32' cy='35' r='21'/>"
		+ "<circle " + D + " cx='24' cy='30' r='2.8'/><circle " + D + " cx='40' cy='30' r='2.8'/>"
		+ "<ellipse " + D + " cx='32' cy='42' rx='5.5' ry='4'/><path fill='none' stroke='#000' stroke-opacity='.55' stroke-width='2' d='M32 46 L32 50 M27 50 Q32 54 37 50'/>",
	"snake": "<path fill='none' stroke='#fff' stroke-width='8' stroke-linecap='round' d='M10 54 Q32 62 40 50 Q48 38 28 34 Q8 30 20 19 Q28 12 40 13'/>"
		+ "<ellipse " + W + " cx='46' cy='13' rx='9' ry='7'/><circle " + D + " cx='48' cy='10' r='1.8'/>"
		+ "<path fill='none' stroke='#fff' stroke-width='1.6' d='M54 14 L60 14 M60 14 L63 11 M60 14 L63 17'/>",
	"dragon": "<path " + W + " d='M6 44 L18 26 L12 6 L27 19 L30 10 L36 18 L54 25 L61 33 L49 35 L58 41 L40 44 L30 56 L14 54 Z'/>"
		+ "<path " + D + " d='M36 24 L43 26 L37 29 Z M52 28 L56 30 L52 31 Z'/>"
		+ "<path fill='none' stroke='#000' stroke-opacity='.55' stroke-width='2' d='M18 44 L24 38 M22 49 L28 43'/>",
	"hood": "<path " + W + " d='M32 5 Q51 7 50 34 L57 59 L7 59 L14 34 Q13 7 32 5 Z'/>"
		+ "<ellipse " + D + " cx='32' cy='31' rx='10.5' ry='13'/>"
		+ "<path " + W + " d='M25 29 L30 31 L25 32 Z M39 29 L34 31 L39 32 Z'/>",
	"helm": "<path " + W + " d='M14 52 L14 27 Q14 8 32 8 Q50 8 50 27 L50 52 Q32 59 14 52 Z'/>"
		+ "<path " + W + " d='M29 2 L35 2 L35 10 L29 10 Z'/>"
		+ "<rect " + D + " x='18' y='26' width='28' height='6' rx='1.5'/><rect " + D + " x='29' y='26' width='6' height='22' rx='1.5'/>",
	"hat": "<path " + W + " d='M36 3 Q30 8 28 16 L19 45 L45 45 L40 16 Q42 8 48 9 Q42 3 36 3 Z'/>"
		+ "<ellipse " + W + " cx='32' cy='47' rx='27' ry='6.5'/>"
		+ "<path " + D + " d='M32 24 L34 29 L39 29 L35 32 L37 37 L32 34 L27 37 L29 32 L25 29 L30 29 Z'/>"
		+ "<rect " + D + " x='20' y='40' width='24' height='4'/>",
}

## Monster id -> icon family.
const BY_MONSTER := {
	"wolf": "wolf", "dire_wolf": "wolf", "worg": "wolf", "werewolf": "wolf", "hell_hound": "wolf",
	"giant_hyena": "wolf", "gnoll": "wolf",
	"kobold": "kobold", "lizardfolk": "kobold",
	"goblin": "goblin", "hobgoblin": "goblin", "bugbear": "goblin",
	"orc": "orc", "ogre": "orc", "troll": "orc", "oni": "orc",
	"skeleton": "skull", "zombie": "skull", "ogre_zombie": "skull", "ghoul": "skull", "ghast": "skull",
	"wight": "skull", "mummy": "skull", "vampire_spawn": "skull",
	"shadow": "ghost", "specter": "ghost", "wraith": "ghost", "banshee": "ghost", "ghost": "ghost", "will_o_wisp": "ghost",
	"giant_spider": "spider",
	"giant_rat": "rat", "swarm_of_rats": "rat",
	"brown_bear": "bear", "black_bear": "bear", "polar_bear": "bear", "owlbear": "bear",
	"giant_poisonous_snake": "snake", "constrictor_snake": "snake", "giant_constrictor_snake": "snake",
	"young_black_dragon": "dragon", "young_green_dragon": "dragon", "young_red_dragon": "dragon",
	"young_white_dragon": "dragon", "wyvern": "dragon",
	"bandit": "hood", "bandit_captain": "hood", "cultist": "hood", "cult_fanatic": "hood",
	"acolyte": "hood", "priest": "hood", "assassin": "hood", "scout": "hood",
	"guard": "helm", "thug": "helm", "veteran": "helm", "knight": "helm", "gladiator": "helm", "animated_armor": "helm",
	"mage": "hat",
}

const RES := 128  # rasterised size in px

static var _cache := {}

## Icon family for a monster id ("" if none).
static func icon_for(mid: String) -> String:
	if mid == "":
		return ""
	var own := str(Data.monster(mid).get("icon", ""))
	if SVG.has(own):
		return own
	return BY_MONSTER.get(mid, "")

## Icon texture for a combatant (uses its wild shape form if it has one), or null.
static func for_combatant(c: Dictionary) -> Texture2D:
	var form: Dictionary = c.get("form", {})
	var mid := str(form.get("monster_id", "")) if not form.is_empty() else str(c.get("monster_id", ""))
	return texture(icon_for(mid))

static func texture(icon: String) -> Texture2D:
	if not SVG.has(icon):
		return null
	if _cache.has(icon):
		return _cache[icon]
	var svg := "<svg xmlns='http://www.w3.org/2000/svg' width='64' height='64' viewBox='0 0 64 64'>%s</svg>" % SVG[icon]
	var img := Image.new()
	var tex: Texture2D = null
	if img.load_svg_from_string(svg, RES / 64.0) == OK:
		tex = ImageTexture.create_from_image(img)
	_cache[icon] = tex
	return tex
