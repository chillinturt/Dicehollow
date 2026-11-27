# Dicehollow

A sprite-based virtual tabletop built in Godot 4.7 (GDScript). The first ruleset is
**D&D 5th Edition, 2014 rules**, including expanded material (Artificer, Tasha's/Xanathar's
subclasses such as the Twilight and Peace domains, Scribes and Chronurgy wizards, and so on).

The DM hosts a game and builds encounters. Players join with their own characters and portraits.
Combat runs BG3-style: click a hotbar action, click a target, and the rules resolve themselves.

## Play it (no Godot needed)

1. Go to the [latest release](https://github.com/chillinturt/Dicehollow/releases/latest) and download **Dicehollow-windows.zip**.
2. Unzip it anywhere and run `Dicehollow.exe`. Windows SmartScreen may warn about an unsigned app: click **More info → Run anyway**.
3. To play together, one person picks **Host a Game (DM)** and everyone else picks **Join a Game** and enters the host's IP address and port (default 7777).
   - Same house or LAN: use the host's local IP (for example `192.168.1.20`).
   - Over the internet: the host forwards TCP/UDP port 7777 on their router and shares their public IP, or everyone joins the same [Tailscale](https://tailscale.com/) network (free, no port forwarding) and uses the host's Tailscale IP.
   - Allow Dicehollow through Windows Firewall when asked.

Everyone must run the same release version. The DM turns away a player on a different version, and the version shows on the main menu.

## Modify it in Godot

The full project is in this repo. Get it with **Code → Download ZIP**, or `git clone https://github.com/chillinturt/Dicehollow.git`, or grab the *Source code* zip attached to each release.

1. Install [Godot 4.7](https://godotengine.org/download) (the standard build works; the .NET build also works, as the project is pure GDScript).
2. In the Project Manager, click **Import** and select this folder's `project.godot`.
3. Press **F5** to run it.

Game rules and content live in the JSON files under `data/` (see `docs/DATA_SCHEMA.md`), and the code is in `scripts/` and `autoload/`. To build your own executable: **Project → Export → Windows Desktop → Export Project** (install export templates when Godot asks). Pull requests are welcome.

## Running from source

Open the folder in Godot 4.7 and press F5, or run:

    Godot_v4.7.2-stable_mono_win64.exe --path path\to\Dicehollow

Main menu:

| Button | What it does |
|---|---|
| **Characters** | Build characters: race, subrace, multiclassing, subclasses, ASIs/feats, abilities (point buy, standard array, manual), skills/expertise, equipment, spells (wizards keep a spellbook and prepare from it), and an uploaded portrait (PNG/JPG/WEBP, auto-cropped to a square token). **⬆ Level Up…** runs the guided level-up, the **Level Plan** tab plans levels 1-20, and **History** restores earlier versions of the sheet. *Add premade characters* adds a sample party, including a Scribe Artificer and a Chronurgy Wizard. |
| **Host a Game (DM)** | Starts an ENet server (default port 7777) and opens the battle map with the DM toolbox. |
| **Join a Game** | Connects to the DM's IP and port with one of your characters. Your portrait is sent to everyone. |
| **Solo Test Battle** | Runs everything locally against a sample encounter. This is the quickest way to try the game. |

Over the internet, the DM must forward the port, or both sides can use a LAN or VPN such as Tailscale.

## Playing

**Moving.** On your turn, reachable squares are highlighted. Hover to see the path and its cost, then click to move. Opportunity attacks trigger automatically.

The engine enforces the movement rules:
- Movement left = speed × (1 + Dashes) − feet moved. Speed changes apply straight away, so becoming grappled leaves you 0 ft and gaining Haste adds movement.
- Difficult terrain and other creatures' spaces cost double. You can't end your move in another creature's space. You can pass through a hostile creature only if it is two or more sizes larger or smaller than you.
- Standing up from prone costs half your speed (moving stands you up automatically, or use **Stand Up**). If you can't afford it, you crawl at double cost.
- A frightened creature can't move closer to what it fears.
- You provoke an opportunity attack only from enemies that can see you. Disengage prevents them, except from Sentinel. A Sentinel hit drops your speed to 0 for the rest of the turn.
- **Grapple**, **Shove (Prone)** and **Shove (Push)** each replace one attack of the Attack action (so Extra Attack lets you grapple and then hit). The target must be within reach and no more than one size larger: your Athletics against its Athletics or Acrobatics (whichever is better), and a tie goes to the target. A grappled creature has speed 0; **Release Grapple** lets go at no cost.
- Escaping a grapple takes your action (**Escape Grapple**: Athletics or Acrobatics against the escape DC, or a contest against the grappler's Athletics if a character grappled you). The grapple also ends if the grappler is incapacitated or you end up out of its reach.
- Restraints like Web, Entangle, Earthen Grasp, Black Tentacles and a Giant Spider's web work the same way: **Break Free** takes your action and is a Strength (Athletics) check against the spell DC or the creature's escape DC. Black Tentacles also allows Dexterity (Acrobatics).

**Turn economy.** Each turn you get one action, one bonus action, movement, and one reaction per round. The engine also enforces:
- An incapacitated creature can't use anything, free features included.
- Haste's extra action allows only one weapon attack, Dash, Disengage or Hide.
- If you cast a bonus-action spell, the only other spell you can cast that turn is a 1-action cantrip. That includes reaction spells such as Shield on your own turn. Quickened Spell counts as a bonus-action spell.
- Reckless Attack must be declared before your first attack.
- In armor or a shield you aren't proficient with, you can't cast spells and have disadvantage on Strength and Dexterity attack rolls and saves. The character builder warns you.

**Dropping and healing.** A character dropped to 0 HP falls prone and stays prone when healed, so it has to spend half its speed to stand. **Lay on Hands** asks how many points to spend: 1 is enough to get a fallen ally back up, or spend 5 to neutralize poison. It won't spend anything on a target already at full HP, and it has no effect on undead or constructs. Cure Wounds, Healing Word and their mass versions don't affect undead or constructs either.

**Rolls.** An area spell or breath weapon rolls its damage once, and each creature takes all or half of that roll depending on its save. Radiant damage from any source, spell or weapon, stops Undead Fortitude. Turn Undead destroys low-CR undead outright, with no damage roll. Turned creatures spend their turns Dashing away from you (or Dodging if they're cornered) and can't take reactions.

**Acting.** Hotbar buttons are colour-coded by type: attacks (red), spells (purple, showing slot level), features (gold), toggles (teal), basic actions (grey). Click an action, then a target. Spells with a choice ask first (slot level, damage type, the word for Command). Hovering a target shows your **hit chance** or the target's **chance to fail its save**. Area spells preview their template.

**Economy and controls.** Action, bonus action, reaction and remaining movement are shown bottom-right. **End Turn** (or E) passes the turn. **⚙ Auto Turn** lets the AI play your turn.

**Sound.** Attacks, spells (by damage type), hits, misses, healing, deaths, footsteps and your turn all have sound effects, synthesized in code by the `Sfx` autoload. Use the 🔊 button in the top bar to mute and the slider to set the volume. Both are saved between sessions.

**Dice.** Rolls can tumble across a dice tray in the bottom-left corner of the map: attacks, saves, checks, contests, initiative, death saves and damage, each with the right die shape. A die dropped for advantage or disadvantage is struck through, and natural 20s and 1s glow. The 🎲 button in the top bar picks what *you* see: **Off**, **Mine** (rolls by or against your creatures) or **All**. Each player has their own setting, saved on their own computer. Rolls by creatures hidden in the fog stay hidden.

**Camera.** WASD or arrow keys, or right/middle-drag, to pan. Mouse wheel zooms. Right-click or Esc cancels targeting.

**Toggles.**
- Divine Smite, Stunning Strike and Battle Master maneuvers: on your own turn you're asked after each melee hit (you know if it was a crit by then) whether to use them and, for a smite, which slot. Arming one here instead uses it on your next hit automatically, which is how you smite on an opportunity attack.
- Reckless Attack, Great Weapon Master, Sharpshooter.
- Metamagic.

**Ask-first abilities.** In 5e you decide whether to use these after you see the roll, so the game asks you, even on a monster's turn:
- Lucky (on your own failed attack or save, or when an attack hits you), Indomitable, Favored by the Gods.
- Bardic Inspiration and Emboldening Bond, when an ally has given you one.
- Flash of Genius (the artificer is asked when an ally within 30 ft fails a save), Guided Strike, Precision Attack.

A box appears with the roll ("Use Lucky?"), and the game waits until you answer. The DM sees the same box and can answer for a player who is away. To stop being asked about an ability, open the **🎲** menu next to Auto Turn and tick it: from then on it is used automatically, only when it would turn the roll around. The setting is saved with the character. The DM picks a character to change by selecting it first. Monsters, and characters played by the AI, always use these abilities automatically.

How it works: the server saves the game and the dice before each action. When a question comes up, it undoes the action, asks, and then runs the action again with the same dice, so every roll before the question comes out the same.

**Automatic reactions:**
- Shield, Counterspell, Absorb Elements, Hellish Rebuke.
- Uncanny Dodge, Deflect Missiles.
- Cutting Words, Chronal Shift, Warding Flare.
- Protection and Interception fighting styles.
- Riposte.
- Legendary Resistance (monsters).

### DM toolbox (left panel)
- **Combat:** start combat (rolls initiative), end it, force the next turn, run the AI for the current turn, toggle whether monsters play automatically, free-move tokens (or hold Shift), short or long rest, and clear slain monsters (dead player characters stay so they can be raised). **Select enemies / Select party** selects a whole side at once. A short rest lasts an hour, so it ends the fight and any spell or effect of an hour or less, such as Spirit Guardians, Spiritual Weapon or Bless. Longer ones, like Mage Armor and Aid, carry on. After a short rest each character gets **Spend Hit Die (dN)** actions: every click rolls one die and heals its roll + CON modifier, so players choose how many to spend (Song of Rest adds its die once, with the first one). They stay until the next fight or long rest. A long rest restores up to half the hit dice, removes one level of exhaustion, and also undoes Harm's cut to maximum HP. A character needs at least 1 HP when the long rest starts to benefit from it: at 0 HP the time passes (effects run out) but HP, hit dice, spell slots, features and exhaustion stay as they were. A stable character wakes with 1 HP. After a short rest, a wizard with Arcane Recovery gets **Recover Lv N Slot** actions to choose which slots to regain. They stay until the next fight or long rest, and if the wizard doesn't use them, Arcane Recovery is saved for a later short rest. Game time passes at one round per combat round, an hour per short rest and eight per long rest. Revivify only works on someone who died within the last minute (10 rounds).
- **Monsters:** search the bestiary (102 SRD creatures plus your own) and click the map to place them, as enemies or allies. Monsters can't be stacked or placed in walls. Duplicates are numbered (Goblin, Goblin 2, ...). Tick **Place hidden** to set up an ambush: hidden monsters show only to the DM, as faint ghosts. They stay off the initiative and can't be targeted until you **Reveal** them (one at a time, or **Reveal all hidden monsters** on the Combat tab). A monster revealed mid-fight rolls initiative and joins in. Select a hidden monster and click an empty cell to move it. **New monster / Edit / copy selected** opens the monster editor.
- **Map:** paint floor, walls, difficult terrain, water and pits with a 1–3 brush (walls and pits never paint over a creature). Set player start points, pick a theme (stone, cave, forest, tavern, snow, swamp, ruins, badlands), upload a background image, resize the map, and save or load maps together with their monsters, including hidden ones and their names. Shrinking or loading a map moves anyone left off the map or inside a wall to the nearest free cell.
- **Fog of war** (Map tab): **Off**, **Soft** (players see all the terrain, but only the creatures, spell zones and auras their side can see right now) or **Hard** (also blacks out ground nobody in the party has seen; explored ground stays visible but dimmed once out of sight). **Sight** sets how far creatures see: unlimited in bright light, or 30–120 ft in the dark, where darkvision, blindsight, tremorsense and truesight reach further. Walls, Fog Cloud, Darkness and other heavily obscured zones block sight (blindsight sees through zones). **Party shares vision** is on by default; untick it and each player sees only what their own characters see. You see everything, with the party's blind spots shaded; tick **Preview the players' view** to look through their eyes. **Reveal brush** / **Re-fog brush** paint explored ground in or out, and **Reveal map** / **Re-fog map** do the whole map. Saved maps keep their fog settings. Unseen creatures are hidden on the map and show as **?** in the initiative order. The fog decides what the screen shows: every client still receives the full game state, and the combat log still names creatures.
- **Map generator** (**🗺 Generate encounter map…** at the top of the Map tab): builds a whole map, with recommended monsters if you want them, from four tabs of settings. A live preview and an encounter summary update as you change things. **Apply to table** loads the result like a saved map, and **Save as map** adds it to your map list.
  - *Terrain:* dungeon, cave, forest, swamp, town interior, arctic, graveyard or mountain pass, plus the map size, which edge the party starts on, and a seed (the same seed and settings always give the same map).
  - *Environment:* sliders for obstacles, difficult terrain, water, pits and cover, with each terrain's own defaults. Dungeons and buildings also have a room count, and outdoor maps can have a river crossing with fords. Anything the party can't walk to is filled in.
  - *Monsters:* difficulty from Easy to Beyond deadly (the DMG 2014 XP thresholds and group multipliers), party power, composition (solo, boss + minions, mixed group, horde, or chosen automatically from the party), the most monsters allowed, creature types, whether to use only monsters that live in that terrain, and placement: one group ahead, spread out, or surrounding the party, at a set distance, with a share starting hidden as an ambush.
  - *Party:* build for the characters on the map (their real levels and classes; Ctrl+click characters before opening the generator to build for just them), or for a custom party where you set each member's class and level. The party's classes adjust the budget: with no healer it is 10% lower, area-damage casters bring more and weaker monsters, and a mostly martial party gets fewer and tougher ones.
  Rerolling the monsters keeps the layout. Monsters that can't swim or fly are never placed in water.
- **Party:** choose how the party advances, see each character's level and XP, open their sheets, see who's connected, and add characters you control. If a player's connection drops, the DM controls their character. When the player rejoins with the same character they take that token back, so no duplicate is made.
  - *Milestones* (the default): **Grant a level** to the selected characters, or to the whole party if none are selected.
  - *Experience points*: **Award XP** (to each, or **split** evenly), or **Award defeated foes' XP** to add up every defeated enemy not yet counted and share it among the party members still standing. Characters can level when they reach the PHB thresholds (300 XP for level 2, up to 355,000 for level 20). **Grant a level** still works in XP mode and tops a character's XP up to the next threshold.

**Inspect panel** (click any token; **Ctrl+click** to select several, then everything below applies to all of them):
- **HP:** type an amount, then **Damage**, **Half** (for a successful save), **Heal** or **Set HP**. Damage is untyped by default, so the creature takes exactly that much. Pick a damage type to apply resistance, immunity and vulnerability. Healing or setting HP above 0 brings back a monster slain by mistake. Setting a PC to 0 knocks them unconscious under the normal rules.
- **Conditions:** toggle any condition, optionally for a number of rounds. A timed condition ends at the end of the creature's own turn. **Exhaustion** levels go up and down with ＋/－, and their effects apply (disadvantage on checks, halved speed, and so on).
- **Rolls:** roll any saving throw, ability check or skill check for the selection. Set a **DC** and optional **damage** (for example `4d10`, with **half** on a success) to run a trap or an effect the engine doesn't automate. The damage is rolled once, and Evasion applies to DEX saves. Players can use the same roller for their own character's checks and saves.
- **Initiative:** set a creature's initiative to a number a player rolled at the table. The order re-sorts without changing whose turn it is.
- Rename a creature, switch its side, hide or reveal it, hand control to the AI, reassign a character to a player, or remove the token.
- **Keys:** Delete removes the selection, H hides or reveals it, and Esc clears it.

**Chat dice:** `/roll 2d6+3`, `/roll 1d20+5 adv` (or `dis`). `/hroll 1d20` makes a private roll that only you and the DM see.

### Character sheets and levelling

**Reading sheets.** Click **📜 Sheet** under your portrait, press **C**, click **Character sheet** in the inspect panel, or double-click a portrait in the initiative bar. You can open any party member's sheet; the DM can open everyone's. Each sheet has:
- **Overview:** AC, HP, speed, initiative, proficiency, passive Perception, hit dice, ability scores and saves, all 18 skills (● proficient, ◆ expertise), attacks with to-hit and damage, spellcasting DC, attack bonus and slots, limited-use features, proficiencies, class choices, feats and equipment. Live HP, spent slots, used features and conditions update during play.
- **Features:** every class, subclass, racial and feat feature with its rules text, grouped by source. ⚙ marks the automated ones.
- **Spells:** the spells known or prepared, by level, with summaries and always-prepared spells.
- **Level Plan:** the class taken or planned at each level from 1 to 20, the class level it reaches, what that level unlocks (features, subclass, ASI, new spell levels, proficiency bonus), and a note. The owner can plan future levels and fill them in bulk. Planned multiclass levels are checked against the character's current scores. The level-up wizard suggests the planned class.
- **History** (your own characters): the backups of this sheet, with what differs from the current version, and **Restore**.

**Levelling up.** When the DM grants a level (or you reach the XP), the game announces it, and a gold **⬆ Level up** button appears on your card and sheet. Levels are taken outside combat. The guided level-up shows only the steps this level needs:
1. **Class:** continue a class or multiclass. Each option previews what it grants. Multiclass prerequisites (13 in the main abilities of your current classes and the new one; Fighter takes STR *or* DEX) are enforced, and the proficiencies a multiclass grants are listed. You don't gain the new class's saving throws.
2. **Hit points:** take the average, roll the die, or enter your own roll. The new maximum includes CON and bonuses such as Tough and Dwarven Toughness. Rolled values are kept per level on the sheet.
3. **Subclass**, when the class reaches its subclass level. Each subclass lists its features at every level and its always-prepared spells.
4. **Ability Score Improvement or feat:** +2 to one score, +1 to two (capped at 20), or a feat. Feat prerequisites are checked, and feats that raise an ability ask which one.
5. **Class options:** fighting styles, maneuvers, metamagic, invocations, infusions, draconic ancestry and armor model, with the number you may know at this level. Known options can be swapped.
6. **Skills:** the skill a multiclass into Bard, Ranger or Rogue grants, and expertise picks.
7. **Spells:** new cantrips and spells within the class's highest spell level. Known casters can swap one; wizards write their free spells into the spellbook.
8. **Review:** every change (HP, proficiency bonus, slots, features, spells, proficiencies), reminders for picks still open, and an optional note saved in the level plan.

Every step explains the choice in plain words for new players. The rules are enforced, but a **"Allow choices outside the rules (DM approved)"** box lifts prerequisites and pick counts for house rules.

**Backups and rolling back.** Before a level-up, a restore or a builder save that changes the sheet, the previous version goes into the sheet's history (up to 40 backups). Builder edits saved within 15 minutes of each other share one backup. **Restore** brings a version back, after backing up the current one, so a restore can itself be undone. XP and levels granted by the DM are never rolled back, so a level undone by mistake can be taken again straight away. In a game, sheet changes go through the DM's server, which checks them (only the owner or the DM, never above the granted level, not mid-fight) and saves the result on the player's own computer.

## What the engine automates
- Attack rolls with advantage and disadvantage from conditions, Pack Tactics, Reckless Attack, prone, invisibility, range and Help. Crits, including Improved Critical, Hexblade's Curse, and automatic crits on paralyzed or unconscious targets.
- Damage resistance, immunity and vulnerability. Mundane-weapon resistance is bypassed by magic weapons and spells.
- Saving throws with Aura of Protection, Bless, Bane, Magic Resistance, Gnome Cunning, Danger Sense, Evasion and Potent Cantrip.
- Concentration checks (War Caster, Eldritch Mind, Bladesong), and ending concentration cleans up its effects.
- Temp HP, death saves, massive damage, Relentless Endurance, Undead Fortitude and Relentless Rage.
- Spell slots: multiclass slots, pact magic, upcasting and cantrip scaling.
- Spell resolution: attacks with multiple rays or beams, saving-throw spells, area templates (sphere, cube, cone, line, emanation), persistent zones (Moonbeam, Web, Cloud of Daggers, Spike Growth) that trigger when a creature enters, starts or ends its turn there, or moves through them, and auras (Spirit Guardians). Specific handlers for about 50 spells, including Magic Missile, Sleep, Hunter's Mark, Hex, Spiritual Weapon, Haste, Hold Person, Polymorph, Counterspell, Dispel Magic (on an ally it ends only hostile spells), Misty Step, Thunderwave and the blade cantrips.
- Class features (roughly 120): Rage, Sneak Attack, Extra Attack, Action Surge, Second Wind, Ki, Divine Smite, Lay on Hands, Channel Divinity options (including the oath options Turn the Unholy, Turn the Faithless and Abjure Enemy), Aura of Devotion, Wild Shape (using beast stat blocks from the bestiary), Twilight Sanctuary, Emboldening Bond, Steel Defender, Eldritch Cannon, Font of Magic, Bladesong, Momentary Stasis, Awakened Spellbook damage swaps, and more. In the character builder, features marked **⚙ automated** are handled by the engine. Everything else shows its description for the table to adjudicate.
- Monster AI: scores every action, target and reachable position by expected damage (or healing and control value), avoids hitting allies with area attacks, moves into position, and uses multiattack, recharge abilities and spells.

## Not yet automated
- Spells with `combat: null` in the data (utility, summoning, walls without damage). They still spend the slot and the action, and the DM adjudicates the effect.
- Cover, vision and lighting, dragging a grappled creature, mounted combat, the Ready action, Haste's lethargy, and legendary or lair actions. Legendary Resistance is supported.
- Light sources. Fog-of-war sight range is one map-wide setting: torches, the Light spell and lit areas don't brighten parts of the map.
- Character levelling happens in the character builder, not in-game. There's no XP tracking yet.

## Layout

```
autoload/      Data (loads JSON), Dice, CharacterStore (saves, portraits, maps, premades), Session (networking + authority), Sfx (synthesized sound effects)
data/          classes, races, items, feats, features (hand-written); spells_0_2, spells_3_9, monsters (generated)
docs/          DATA_SCHEMA.md - the JSON format for spells and monsters
scripts/core/  rules.gd (character -> stats), combatant_factory.gd, engine_base.gd (geometry, d20, damage),
               map_generator.gd (procedural maps), encounter_builder.gd (DMG XP budgets, monster picks),
               combat_engine.gd (turns, actions, spells, features), combat_ai.gd
               progression.gd (XP, multiclass prerequisites, level gains, level-ups, level plan, sheet history)
scripts/ui/    main_menu, character_editor, battle (HUD + input), map_view, token, ui_kit, monster_editor, map_generator_panel,
               dialog_panel, character_sheet, level_plan_view, level_up_wizard
tests/         headless tests (see below)
```

The server owns the state, a plain Dictionary. Clients send requests, and the server runs
`CombatEngine` and broadcasts the full state plus a list of visual events, which clients animate in order.
To add content, edit the JSON files. New ids in `features.json`, or new `special` spell handlers
(`_sp_<id>` in `combat_engine.gd`), hook into the engine.

Saved data lives in `%APPDATA%\Godot\app_userdata\Dicehollow\` (characters, portraits, maps).

### Tests (headless)

    Godot..._console.exe --headless --path . res://tests/smoke_test.tscn   # derives premades, builds every monster, runs 3 AI-vs-AI battles
    Godot..._console.exe --headless --path . res://tests/ui_test.tscn      # instantiates every screen, plays a solo battle, saves and loads a map
    Godot..._console.exe --headless --path . res://tests/rules_test.tscn   # movement and action-economy rules (exit code 1 on failure)
    Godot..._console.exe --headless --path . res://tests/spell_test.tscn   # spell and effect mechanics, then casts every automated spell (exit code 1 on failure)
    Godot..._console.exe --headless --path . res://tests/spell_audit_test.tscn   # the spells fixed in docs/SPELL_AUDIT.md (exit code 1 on failure)
    Godot..._console.exe --headless --path . res://tests/class_test.tscn   # Wizard, Cleric and Paladin playtest fixes (exit code 1 on failure)
    Godot..._console.exe --headless --path . res://tests/audit5e_test.tscn    # 5e 2014 rules audit fixes: hit dice, exhaustion, rage, sneak attack, death saves (exit code 1 on failure)
    Godot..._console.exe --headless --path . res://tests/dm_tools_test.tscn   # DM toolbox: placement, hidden monsters, HP, conditions, group rolls, initiative, map changes (exit code 1 on failure)
    Godot..._console.exe --headless --path . res://tests/map_gen_test.tscn    # map generator: XP math, every terrain reachable, legal monster placement, applying to the table (exit code 1 on failure)
    Godot..._console.exe --headless --path . res://tests/progression_test.tscn   # XP, multiclass prerequisites, level gains, HP rolls, history and restore, the wizard, server checks (exit code 1 on failure)
    Godot..._console.exe --headless --path . res://tests/layout_test.tscn   # builds every screen, tab, dialog and level-up step at 1600x900 and reports anything off-screen, overflowing or clipped (exit code 1 on failure)
    Godot..._console.exe --headless --path . res://tests/net_test.tscn -- server   (and in a second terminal: -- client, or -- client_old to check that a mismatched version is turned away)
    Godot..._console.exe --headless --path . res://tests/net_level_test.tscn -- server   (and -- client in a second terminal: grant a level, level up, restore over the network)
    Godot..._console.exe --headless --path . res://tests/fog_test.tscn     # fog of war: vision through walls and fog clouds, sight range and darkvision, shared vs own vision, explored memory, DM fog requests (exit code 1 on failure)
    Godot..._console.exe --headless --path . res://tests/net_fog_test.tscn -- server   (and -- client in a second terminal: fog settings and memories reach the player, shared vs own vision)
    Godot..._console.exe --path . res://tests/fog_shots.tscn -- <folder>   # screenshots of the fog of war (DM view, hard and soft fog); needs a window

## Content note
Spell and monster data was generated for this prototype. Monsters are limited to the open SRD 5.1.
Summaries are paraphrased, not book text. Stat blocks and class lists were written from memory and
haven't been checked against the books, so treat them as needing a spot-check, especially less common
spells' class lists.

## License

Code is MIT licensed (see `LICENSE`). Dungeons & Dragons is a trademark of Wizards of the Coast; this is an unofficial fan project. Monster data is limited to the SRD 5.1 (CC-BY-4.0).
