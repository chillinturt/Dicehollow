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
| **Characters** | Build characters: race, subrace, multiclassing, subclasses, ASIs/feats, abilities (point buy, standard array, manual), skills/expertise, equipment, spells (wizards keep a spellbook and prepare from it), and an uploaded portrait (PNG/JPG/WEBP, auto-cropped to a square token). *Add premade characters* adds a sample party, including a Scribe Artificer and a Chronurgy Wizard. |
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
- Escaping a grapple takes your action (**Escape Grapple**: Athletics or Acrobatics against the escape DC). The grapple also ends if the grappler is incapacitated or you end up out of its reach.
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

**Camera.** WASD or arrow keys, or right/middle-drag, to pan. Mouse wheel zooms. Right-click or Esc cancels targeting.

**Toggles.**
- Divine Smite, Stunning Strike and Battle Master maneuvers: on your own turn you're asked after each melee hit (you know if it was a crit by then) whether to use them and, for a smite, which slot. Arming one here instead uses it on your next hit automatically, which is how you smite on an opportunity attack.
- Reckless Attack, Great Weapon Master, Sharpshooter.
- Metamagic.

**Automatic reactions:**
- Shield, Counterspell, Absorb Elements, Hellish Rebuke.
- Uncanny Dodge, Deflect Missiles.
- Cutting Words, Chronal Shift, Flash of Genius, Warding Flare.
- Protection and Interception fighting styles.
- Riposte, Lucky, Bardic Inspiration, Emboldening Bond, Indomitable.
- Legendary Resistance (monsters).

### DM toolbox (left panel)
- **Combat:** start combat (rolls initiative), end it, force the next turn, run the AI for the current turn, toggle whether monsters play automatically, free-move tokens (or hold Shift), short or long rest, and clear slain monsters (dead player characters stay so they can be raised). **Select enemies / Select party** selects a whole side at once. A short rest lasts an hour, so it ends the fight and any spell or effect of an hour or less, such as Spirit Guardians, Spiritual Weapon or Bless. Longer ones, like Mage Armor and Aid, carry on. During a short rest each hurt character spends hit dice (largest first) until healed or out of dice: each die heals its roll + CON modifier, plus Song of Rest. A long rest restores up to half the hit dice, removes one level of exhaustion, and also undoes Harm's cut to maximum HP. After a short rest, a wizard with Arcane Recovery gets **Recover Lv N Slot** actions to choose which slots to regain. They stay until the next fight or long rest, and if the wizard doesn't use them, Arcane Recovery is saved for a later short rest. Game time passes at one round per combat round, an hour per short rest and eight per long rest. Revivify only works on someone who died within the last minute (10 rounds).
- **Monsters:** search the bestiary (102 SRD creatures plus your own) and click the map to place them, as enemies or allies. Monsters can't be stacked or placed in walls. Duplicates are numbered (Goblin, Goblin 2, ...). Tick **Place hidden** to set up an ambush: hidden monsters show only to the DM, as faint ghosts. They stay off the initiative and can't be targeted until you **Reveal** them (one at a time, or **Reveal all hidden monsters** on the Combat tab). A monster revealed mid-fight rolls initiative and joins in. Select a hidden monster and click an empty cell to move it. **New monster / Edit / copy selected** opens the monster editor.
- **Map:** paint floor, walls, difficult terrain, water and pits with a 1–3 brush (walls and pits never paint over a creature). Set player start points, pick a theme (stone, cave, forest, tavern, snow), upload a background image, resize the map, and save or load maps together with their monsters, including hidden ones and their names. Shrinking or loading a map moves anyone left off the map or inside a wall to the nearest free cell.
- **Party:** see who's connected and add characters you control. If a player's connection drops, the DM controls their character. When the player rejoins with the same character they take that token back, so no duplicate is made.

**Inspect panel** (click any token; **Ctrl+click** to select several, then everything below applies to all of them):
- **HP:** type an amount, then **Damage**, **Half** (for a successful save), **Heal** or **Set HP**. Damage is untyped by default, so the creature takes exactly that much. Pick a damage type to apply resistance, immunity and vulnerability. Healing or setting HP above 0 brings back a monster slain by mistake. Setting a PC to 0 knocks them unconscious under the normal rules.
- **Conditions:** toggle any condition, optionally for a number of rounds. A timed condition ends at the end of the creature's own turn. **Exhaustion** levels go up and down with ＋/－, and their effects apply (disadvantage on checks, halved speed, and so on).
- **Rolls:** roll any saving throw, ability check or skill check for the selection. Set a **DC** and optional **damage** (for example `4d10`, with **half** on a success) to run a trap or an effect the engine doesn't automate. The damage is rolled once, and Evasion applies to DEX saves. Players can use the same roller for their own character's checks and saves.
- **Initiative:** set a creature's initiative to a number a player rolled at the table. The order re-sorts without changing whose turn it is.
- Rename a creature, switch its side, hide or reveal it, hand control to the AI, reassign a character to a player, or remove the token.
- **Keys:** Delete removes the selection, H hides or reveals it, and Esc clears it.

**Chat dice:** `/roll 2d6+3`, `/roll 1d20+5 adv` (or `dis`). `/hroll 1d20` makes a private roll that only you and the DM see.

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
- Cover, vision and lighting, grappling or shoving initiated by players, dragging a grappled creature, mounted combat, the Ready action, Haste's lethargy, and legendary or lair actions. Legendary Resistance is supported.
- Fog of war. Hide monsters with the DM tools until they should appear.
- Character levelling happens in the character builder, not in-game. There's no XP tracking yet.

## Layout

```
autoload/      Data (loads JSON), Dice, CharacterStore (saves, portraits, maps, premades), Session (networking + authority), Sfx (synthesized sound effects)
data/          classes, races, items, feats, features (hand-written); spells_0_2, spells_3_9, monsters (generated)
docs/          DATA_SCHEMA.md - the JSON format for spells and monsters
scripts/core/  rules.gd (character -> stats), combatant_factory.gd, engine_base.gd (geometry, d20, damage),
               combat_engine.gd (turns, actions, spells, features), combat_ai.gd
scripts/ui/    main_menu, character_editor, battle (HUD + input), map_view, token, ui_kit
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
    Godot..._console.exe --headless --path . res://tests/net_test.tscn -- server   (and in a second terminal: -- client, or -- client_old to check that a mismatched version is turned away)

## Content note
Spell and monster data was generated for this prototype. Monsters are limited to the open SRD 5.1.
Summaries are paraphrased, not book text. Stat blocks and class lists were written from memory and
haven't been checked against the books, so treat them as needing a spot-check, especially less common
spells' class lists.

## License

Code is MIT licensed (see `LICENSE`). Dungeons & Dragons is a trademark of Wizards of the Coast; this is an unofficial fan project. Monster data is limited to the SRD 5.1 (CC-BY-4.0).
