# Dicehollow data schema

All rules data lives in `res://data/*.json`. Every file is a JSON **array** of objects.
The loader (`autoload/data.gd`) loads every file matching `spells*.json` into one spell table and
every file matching `monsters*.json` into one monster table, keyed by `id`.

Conventions
- `id`: lowercase snake_case, ASCII only, unique (e.g. `tashas_caustic_brew`, `melfs_acid_arrow`).
- Distances are in **feet** (integers). Grid squares are 5 ft. Touch = 5. Self = 0.
- Durations are in **rounds** (1 round = 6 s): 1 minute = 10, 10 minutes = 100, 1 hour = 600, 8 hours = 4800. 0 = instantaneous.
- Abilities: `str dex con int wis cha`.
- Damage types: `acid bludgeoning cold fire force lightning necrotic piercing poison psychic radiant slashing thunder`.
- Conditions: `blinded charmed deafened frightened grappled incapacitated invisible paralyzed petrified poisoned prone restrained stunned unconscious`.
- Dice strings: `"2d6"`, `"1d8+3"`, `"3"` (flat). No other syntax.
- Summaries/descriptions are short and **in your own words** — never paste book text.

---------------------------------------------------------------------------------------------------
## spells*.json

```jsonc
{
  "id": "fire_bolt",
  "name": "Fire Bolt",
  "level": 0,                        // 0 = cantrip
  "school": "evocation",
  "classes": ["artificer", "sorcerer", "wizard"],   // 2014 class lists INCLUDING XGtE/TCoE expanded lists
  "source": "PHB",                   // PHB, XGtE, TCoE, SCAG, EGtW, FTD, AI, SCC ...
  "casting_time": "action",          // action | bonus | reaction | minute | hour
  "range": 120,                      // feet; 0 = self; 5 = touch
  "components": "V,S",               // V,S,M
  "concentration": false,
  "ritual": false,
  "duration_rounds": 0,
  "summary": "Hurl a mote of fire: ranged spell attack for 1d10 fire. Damage grows at 5th, 11th, 17th level.",
  "combat": { ... }                  // null when the spell has no in-combat automation (utility spells)
}
```

### `combat` object (all keys optional except `target`)

```jsonc
{
  "target": "enemy",        // enemy | ally | creature | self | point | self_area
                            //   enemy/ally/creature: pick creatures within range
                            //   point: pick a cell within range; `area` is centred there (or aimed from caster for cone/line)
                            //   self_area: area originates at the caster (cone/line/cube aimed at a cell, or emanation around caster)
  "max_targets": 1,         // creatures that can be picked (Bless 3, Magic Missile 3 darts -> use darts instead)
  "targets_per_slot": 0,    // extra creatures per slot level above the spell's level (Bless, Hold Person = 1)
  "area": {"shape": "sphere", "size": 20},   // sphere(radius) | cube(side) | cone(length) | line(length) | emanation(radius around caster)
  "attack": "ranged",       // ranged | melee | null  -> spell attack roll vs AC
  "save": "dex",            // ability for the saving throw, or null
  "half_on_save": true,
  "damage": [{"dice": "8d6", "type": "fire"}],   // one or more parts
  "upcast_dice": "1d6",     // added to the FIRST damage part per slot level above base
  "cantrip_scaling": true,  // damage dice count x2 at char level 5, x3 at 11, x4 at 17
  "add_mod": false,         // add the caster's spellcasting modifier to damage (or to healing)
  "rays": 1,                // separate attack rolls (Scorching Ray 3)
  "rays_per_slot": 0,       // extra rays per slot level above base (Scorching Ray 1)
  "beams_scale": false,     // Eldritch Blast: beams 1/2/3/4 at char level 1/5/11/17
  "darts": 0,               // Magic Missile: auto-hit darts (3), +1 per slot above base via darts_per_slot
  "darts_per_slot": 0,
  "heal": "1d8",            // healing dice
  "upcast_heal": "1d8",
  "temp_hp": "1d4+4",
  "upcast_temp_hp": "5",
  "effect": {               // applied: on hit (attack), on failed save (save), or always (no attack/no save, e.g. buffs)
    "name": "Blessed",
    "condition": "paralyzed",          // optional standard condition applied while the effect lasts
    "mods": {                          // all optional
      "ac": 2,                         // flat AC change
      "attack_dice": "1d4",            // added to target's attack rolls
      "save_dice": "1d4",              // added to target's saving throws
      "attack_penalty_dice": "1d4",    // subtracted (Bane)
      "save_penalty_dice": "1d4",
      "speed": -10,                    // flat speed change in feet
      "speed_mult": 0.5,               // multiply speed (0 = can't move)
      "advantage_attack": true,        // target has advantage on its attacks
      "disadvantage_attack": true,     // target has disadvantage on its attacks
      "grants_advantage": true,        // attacks AGAINST target have advantage
      "grants_disadvantage": true,     // attacks AGAINST target have disadvantage
      "resist": ["fire"],              // damage resistances gained
      "extra_damage": {"dice": "1d6", "type": "radiant"},  // target's weapon hits deal extra damage
      "no_reactions": true,
      "no_heal": true,
      "vulnerable_to_caster": {"dice": "1d6", "type": "necrotic"},  // caster deals extra dmg to this target (Hunter's Mark: weapon hits; Hex: any attack; others e.g. Bestow Curse: attacks and spells)
      "min_ac": 16,                    // AC can't be lower than this (Barkskin)
      "fly": 60,                       // flying speed (Fly)
      "save_adv": ["wis"],             // advantage on these saving throws (Beacon of Hope)
      "save_adv_spell": true,          // advantage on saves against spells (Circle of Power)
      "max_heal": true,                // healing spells on the target heal the maximum (Beacon of Hope)
      "cond_immune": ["restrained"],   // immune to these conditions (Freedom of Movement)
      "grants_disadvantage_vs": ["fiend"],  // attacks against the target from these creature types have disadvantage
      "half_str_damage": true,         // target deals half damage with Strength weapon attacks (Ray of Enfeeblement)
      "death_ward": true               // the first drop to 0 HP leaves the target at 1 instead (Death Ward)
    },
    "one_attack": true,                // ends after the next attack roll against the target (Guiding Bolt)
    "one_save": true,                  // ends after the target's next saving throw (Mind Sliver)
    "escape": ["str"],                 // a restraint the target can end with an action: check vs the spell DC (Web)
                                       //   any ability works; STR/DEX use Athletics/Acrobatics (Wrathful Smite: ["wis"])
    "save_ends": true,                 // target repeats the save at the end of each of its turns
    "save_on_damage": true,            // target repeats the save each time it takes damage (Enemies Abound)
    "tag": "sanctuary",                // engine hook: sanctuary, expeditious_retreat, dragons_breath, compelled,
                                       //   enemies_abound, swift_quiver (see below)
    "tick_damage": {                   // damage over time on the target's own turn
      "dice": "4d10", "type": "psychic",
      "when": "end",                   // start | end of the target's turn
      "save": "wis",                   // optional: save first; success ends the spell, failure takes the damage
      "once": false,                   // true = happens once, then the effect ends (Melf's Acid Arrow)
      "upcast": "1d10"                 // added per slot level above the spell's level
    },
    "on_hit": {                        // smites: what happens after the weapon hit's damage
      "save": "str", "push": 10, "condition": "prone",   // on a failed save (Thunderous Smite)
      "escape": ["wis"],                                  // lasting condition ended by a check (Wrathful Smite)
      "tick_damage": { ... }                              // lasting damage (Searing Smite)
    },                                 // a lasting rider keeps the caster's concentration; otherwise the spell ends
    "breath": {"dice": "3d6", "save": "dex", "shape": "cone", "size": 15},  // Dragon's Breath: the target's breath action
    "duration_rounds": 10              // shorter than the spell = runs out without ending concentration
  },
  "half_on_miss": true,     // attack spells: a miss deals half the damage and applies no effect (Melf's Acid Arrow)
  "sustain": {              // repeat the damage on later turns while concentrating (Witch Bolt, Heat Metal)
    "cost": "action",       // action | bonus
    "range": 30,            // spell ends if the target is beyond this or out of sight when you try
    "on_hit": true,         // attack spells: only locks on when the first attack hits
    "ends_on_other_action": true, // spending your action on anything else (after the cast turn) ends the spell (Witch Bolt)
    "upcast": "1d8",        // optional: added per slot level above base
    "reapply_effect": true, // re-applies `effect` (Heat Metal's disadvantage)
    "damage": [{"dice": "1d12", "type": "lightning"}]
  },
  "zones_extra": [ { ... } ],  // more zones on the same cells with other triggers (Hunger of Hadar's end-of-turn acid)
  "zone": {                 // persistent area left on the map (Cloud of Daggers, Moonbeam, Web, Spirit Guardians uses aura)
                            // creatures already inside when it's cast aren't affected until their turn trigger,
                            // so don't add top-level damage/save to a zone spell unless it really hits on casting
    "trigger": "start_turn",           // start_turn: starts its turn inside, or enters it for the first time on a turn
                                       // end_turn: ends its turn inside, or enters it (Create Bonfire)
                                       // move: every 5 ft moved inside it (Spike Growth)
    "enter": true,                     // false = entering doesn't trigger it, only the turn trigger (Stinking Cloud)
    "enemies_only": false,             // spares the caster's side (Guardian of Faith)
    "save": "con", "half_on_save": true,
    "damage": [{"dice": "2d10", "type": "radiant"}],
    "effect": { ... },                 // effect applied on failed save while inside (e.g. restrained)
    "difficult": false                 // zone cells are difficult terrain
  },
  "aura": {                 // moves with the caster (Spirit Guardians). Same keys as zone + "radius", "enemies_only", "allies_only", "include_self" (also affects its source)
    "radius": 15, "enemies_only": true, "trigger": "start_turn",
    "save": "wis", "half_on_save": true, "damage": [{"dice": "3d8", "type": "radiant"}], "speed_mult": 0.5
  },
  "enemies_only": false,    // area hits only creatures hostile to the caster ("each creature of your choice")
  "special": "magic_missile"   // for spells the engine handles with custom code (see list below); other keys still apply
}
```

Special handlers the engine implements (`_sp_<name>` in combat_engine.gd; use these exact strings, otherwise omit `special`):
`magic_missile, toll_the_dead, sleep, color_spray, eldritch_blast, chromatic_orb, misty_step, dimension_door, thunder_step,
thunderwave, booming_blade, green_flame_blade, hunters_mark, hex, spiritual_weapon, vampiric_touch, magic_stone, animate_objects,
tiny_servant, mage_armor, shield, armor_of_agathys, heroism, mirror_image, blur, invisibility, greater_invisibility, haste, slow,
banishment, rope_trick, hold_person, hold_monster, polymorph, power_word_kill, power_word_stun, revivify, spare_the_dying, ray_of_frost,
chill_touch, shocking_grasp, true_strike, resistance, guidance, blade_ward, shillelagh, faerie_fire, healing_word_mass,
lesser_restoration, life_transference, divine_word, power_word_pain, chaos_bolt, lightning_lure, negative_energy_flood,
enlarge_reduce, vortex_warp, calm_emotions, reality_break, prismatic_spray, mass_heal, eyebite, summon_beast,
delayed_blast_fireball, meteor_swarm, gravity_fissure, dispel_magic, command`

Marker-only `special` values (no handler; the generic path or a hook does the work): `aid` (max HP rise),
`counterspell`, `hellish_rebuke` (reactions cast automatically), `divine_favor`, `false_life`.
Reaction spells cast automatically by the engine when they matter: Shield, Counterspell, Hellish Rebuke,
Absorb Elements, Silvery Barbs, Temporal Shunt (only for a leveled spell or an attack on an ally at half HP or less).

### More `combat` keys

Targeting and filters
```jsonc
  "only_types": ["humanoid"],   // creature types the spell can affect (Charm Person); PCs count as humanoid
  "immune_types": ["undead"],   // creature types it can't affect (Cause Fear)
  "max_int": 3,                 // creatures with higher INT are unaffected (Animal Friendship)
  "near_first": 30,             // extra targets must be within this many ft of the first (Chain Lightning, Acid Splash)
  "save_only_hostile": true,    // allies choose to fail the save (Levitate, Resilient Sphere)
  "area_per_slot": 20,          // area size grows per slot level above base (Fog Cloud, Confusion)
  "area": {"shape": "wall", "size": 60, "width": 5}   // a wall centred on the point, across the caster's line of sight
```
Damage and saves
```jsonc
  "no_save_damage": true,       // the damage lands even on a successful save (Feeblemind)
  "min_hp": 1,                  // the damage can't drop the target below this (Harm)
  "reduce_max_hp": true,        // a failed save lowers max HP by the damage taken (Harm)
  "save_ends_spell": true,      // a successful save ends the concentration spell (Enervation)
  "drain": true,                // the caster regains half the damage dealt (Enervation; also a sustain key)
  "effect_save": "con",         // attack spells: the effect also needs a failed save (Ray of Sickness)
  "burst": {"radius": 5, "save": "dex", "half_on_save": false, "damage": [...], "upcast": "1d6", "spare_caster": true},
                                // attack spells: damage around the target after the attack, hit or miss (Ice Knife)
  "choose_type": ["fire", "cold"],  // the caster picks an element (UI popup -> opts.dtype); sets the effect's
                                // extra_damage type, single resistance, or elemental_bane type (Fire Shield: "cold" = chill)
```
Forced movement (top-level for a failed save or a hit; also zone/aura data)
```jsonc
  "push": 10, "pull": 10,       // away from / toward the caster
  "push_center": 10, "pull_center": 20,  // away from / toward the area's centre (Dust Devil, Maelstrom, Gravity Sinkhole)
  "random_move": 5,             // a random direction (Infestation)
  "max_size": "large",          // largest size moved
  "move_per_slot": 5,           // extra feet per slot level (Pulse Wave)
  "flee": true                  // the target uses its reaction to run from the caster (Dissonant Whispers)
```
On the caster
```jsonc
  "self_effect": { ... },       // an effect put on the caster as well (Draconic Transformation's wings, Zephyr Strike's charge)
  "repeat": {                   // something the caster can do again while the spell lasts (shown as an action)
    "cost": "action",           // action | bonus | attack (Attack action: Extra Attack applies) | free
    "combat": { ... },          // resolved like a spell. Extra keys: "weapon_attack": true (Shadow Blade),
                                //   "move_zone": true (move this spell's zone to the point; Flaming Sphere, Dawn)
    "uses": 7, "uses_per_slot": 2, "per_use": 2,   // limited shots (Crown of Stars; Melf's meteors fire two per use)
    "same_turn": true,          // usable on the casting turn (Flame Blade, Aura of Vitality)
    "range": 60, "label": "...", "desc": "...",
    "move": 30, "ram": true,    // move_zone: max distance; creatures in the new spot are caught at once
    "origin": "cell",           // the area starts at the point picked when casting (Illusory Dragon's breath)
    "ends_spell": true,         // using it ends the spell (Holy Weapon's burst, detonating Delayed Blast Fireball)
    "rounds": 14400             // how long the action stays available if not the spell's duration (Goodberry)
  }
```
### More `effect` keys
```jsonc
  "mods": {
    "immune": ["fire"],                 // damage immunities (Invulnerability, Mind Blank, Investitures)
    "no_fly": true,                     // can't fly (Earthbind)
    "no_provoke": true,                 // movement provokes no opportunity attacks (Zephyr Strike, Kinetic Jaunt)
    "pass_creatures": true,             // can move through any creature's space (Kinetic Jaunt)
    "leash": 30,                        // can't willingly move farther than this from the caster (Compelled Duel)
    "dis_unless_src": true,             // disadvantage on attacks against anyone but the caster (Compelled Duel)
    "grants_disadvantage_ranged": true, // ranged weapon attacks against the creature have disadvantage (Warding Wind)
    "save_dis": ["str"],                // disadvantage on these saves (Power Word Pain, Reduce)
    "max_speed": 10,                    // speed can't exceed this (Power Word Pain)
    "exhaustion": 1,                    // levels of exhaustion (2: half speed, 3: disadvantage on attacks and saves, 5: speed 0)
    "no_invisible": true,               // can't benefit from being invisible (Faerie Fire)
    "no_spells": true,                  // can't cast spells (Feeblemind)
    "weapon_damage_penalty": "1d4",     // weapon damage reduced (Reduce)
    "elemental_bane": {"type": "fire", "dice": "2d6"},   // that type ignores resistance and adds 2d6 once a turn
    "cond_immune_vs": {"types": ["undead"], "conds": ["charmed", "frightened"]}  // Protection from Evil and Good
  },
  "mods_per_slot": {"speed": 5},        // numeric mods that grow per slot level (Ashardalon's Stride)
  "slot_tiers": [{"slot": 4, "mods": {...}}],  // mods replaced at set slot levels (Magic Weapon, Elemental Weapon)
  "upcast_every": 2,                    // extra_damage upcast dice every N slot levels (Spirit Shroud)
  "until_target_turn_end": true,        // lasts until the end of the target's next turn (Mind Whip, Frostbite)
  "extra_conditions": ["prone"],        // further conditions added with the effect (Hideous Laughter)
  "save_on_damage_adv": true,           // the save when damaged has advantage (Hideous Laughter)
  "save_count": {"ability": "con", "fails": 3, "successes": 3, "on_fail": {effect}},  // Flesh to Stone, Contagion
  "escape_dc": 20,                      // fixed escape DC instead of the spell's (Maze)
  "escape_save": true,                  // the escape action makes a saving throw, not a check (Otto's Irresistible Dance)
  "escape_auto": true,                  // the escape action always works (scraping off Caustic Brew)
  "pocket": "maze",                     // the creature is cut off from everything else (Maze, Resilient Sphere)
  "retaliate": {"dice": "2d8", "type": "fire"},   // melee attackers within 5 ft take this (Fire Shield)
  "trail": {"dice": "1d6", "type": "fire", "upcast": "1d6"},  // creatures the bearer moves near take this (Ashardalon's Stride)
  "no_conc": true,                      // outlasts the spell's concentration (Holy Weapon's blindness)
  // weapon riders on the caster:
  "one_hit": true,                      // spent by the next weapon hit (Zephyr Strike, Hail of Thorns)
  "ranged_only": true, "melee_only": true,
  "spent_on_miss": true,                // also spent by a miss (Zephyr Strike)
  "on_miss": {"half_extra": true},      // a miss still deals half the extra damage (and the on_hit burst) (Lightning Arrow)
  "any_attack": true, "within": 10, "no_heal_on_hit": true,   // Spirit Shroud: spell attacks too, only within 10 ft
  "on_hit": {"burst": {...}, "banish_below": 50, "mods": {...}, "save_ends": true}  // more smite riders
  // tick_damage: "spell_ends": false = a successful save frees only that creature (Weird)
  // tags: dominated (fights for the caster), confused, crown_of_madness, mind_whip, blink, reality_break, warding_bond, pacified
```
### More `zone` keys
```jsonc
  "trigger": "none",            // never triggers (terrain or flags only: Darkness, Silence, Entangle's plants)
  "obscure": "darkness",        // heavily obscured: creatures inside can't see or be seen ("darkness": truesight / Devil's Sight see through)
  "silence": true,              // no verbal spells inside, immune to thunder
  "reveal": true,               // nothing inside can be invisible (Sickening Radiance)
  "heal": "1d6",                // heals the caster's side instead (Healing Spirit); "upcast_heal" from the spell
  "uses": 4, "uses_per_slot": 2, "uses_mod": true,   // limited triggers (Cordon of Arrows; Healing Spirit: 1 + mod, min 2)
  "conc_check": true,           // concentrating creatures inside save or lose it (Sleet Storm, Earthquake)
  "poison_gas": true,           // creatures immune to poison are unaffected (Stinking Cloud)
  "lose_action": true,          // a failed save costs the creature its action (Stinking Cloud)
  "not_caster": true,           // never affects the caster (Dust Devil)
  "storm": true,                // Storm of Vengeance's round-by-round stages
  // an effect with "stacking": true adds a new copy on each failure (Sickening Radiance's exhaustion)
```

---------------------------------------------------------------------------------------------------
## monsters*.json  (SRD 5.1 creatures only)

```jsonc
{
  "id": "goblin",
  "name": "Goblin",
  "size": "small",                  // tiny small medium large huge gargantuan
  "type": "humanoid",               // aberration beast celestial construct dragon elemental fey fiend giant humanoid monstrosity ooze plant undead
  "alignment": "neutral evil",
  "cr": 0.25,
  "xp": 50,
  "ac": 15,
  "ac_note": "leather armor, shield",
  "hp": 7,
  "hit_dice": "2d6",
  "speed": 30, "fly": 0, "swim": 0, "climb": 0,
  "scores": {"str": 8, "dex": 14, "con": 10, "int": 10, "wis": 8, "cha": 8},
  "prof": 2,
  "saves": {"dex": 4},              // ONLY proficient saves, total bonus
  "skills": {"stealth": 6},
  "resist": [], "immune": [], "vulnerable": [], "condition_immune": [],
  "senses": "darkvision 60 ft., passive Perception 9",
  "languages": "Common, Goblin",
  "traits": [
    {"name": "Nimble Escape", "desc": "Can Disengage or Hide as a bonus action.", "tag": "nimble_escape"}
  ],
  // Engine-understood trait tags: pack_tactics, nimble_escape, magic_resistance, undead_fortitude,
  // sunlight_sensitivity, aggressive, regeneration (+ "value": 10), pounce, charge, rampage, keen_senses,
  // brute (extra weapon die, already baked into damage), flyby, legendary_resistance (+ "value": 3), avoidance,
  // spider_climb, amphibious, incorporeal_movement, false_appearance, reckless, martial_advantage, surprise_attack
  "actions": [
    {"name": "Multiattack", "kind": "multiattack", "sequence": ["Bite", "Claw", "Claw"], "desc": "One bite, two claws."},
    {"name": "Scimitar", "kind": "melee", "to_hit": 4, "reach": 5,
     "damage": [{"dice": "1d6+2", "type": "slashing"}]},
    {"name": "Shortbow", "kind": "ranged", "to_hit": 4, "range": 80, "long_range": 320,
     "damage": [{"dice": "1d6+2", "type": "piercing"}]},
    {"name": "Bite", "kind": "melee", "to_hit": 4, "reach": 5, "damage": [{"dice": "2d4+2", "type": "piercing"}],
     "on_hit": {"save": "str", "dc": 11, "condition": "prone"}},          // on_hit: save (optional) + condition and/or extra damage
    {"name": "Fire Breath", "kind": "save", "save": "dex", "dc": 13, "area": {"shape": "cone", "size": 15},
     "damage": [{"dice": "6d6", "type": "fire"}], "half_on_save": true, "recharge": 5},   // recharge 5 = "Recharge 5-6"
    {"name": "Frightful Presence", "kind": "save", "save": "wis", "dc": 13, "area": {"shape": "emanation", "size": 120},
     "condition": "frightened", "save_ends": true, "duration_rounds": 10},
    {"name": "Heal Self", "kind": "special", "desc": "..."}     // kind special = described only, not automated
  ],
  // on_hit keys: save, dc, condition, duration_rounds, save_ends, damage (extra parts on hit, halved on save if half_on_save), escape_dc (grapple)
  "bonus_actions": [],
  "reactions": [{"name": "Parry", "kind": "special", "desc": "Adds 2 to AC against one melee attack that would hit."}],
  "legendary_actions": [],
  "spellcasting": {                  // optional; spells are ids from spells*.json
    "ability": "int", "dc": 13, "attack": 5,
    "slots": [4, 3, 2],              // slots per level, index 0 = 1st level
    "at_will": ["fire_bolt", "mage_hand"],
    "spells": ["magic_missile", "shield", "misty_step", "fireball"]
  },
  "token_color": "#4a7a3a",          // hex colour for the default token
  "icon": "wolf"                     // optional token icon: wolf kobold goblin orc skull ghost spider rat bear snake dragon hood helm hat
                                     // (omit to use the built-in default for the monster id, see scripts/ui/monster_icons.gd)
}
```
