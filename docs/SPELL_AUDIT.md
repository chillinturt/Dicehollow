# Spell audit: untested and suspect spells

Audit and fixes: 2026-11-26. Scope: the 315 spells that had a `combat` block. 42 of them had a
targeted test. The other 273 were covered only by the "Sweep" test in `tests/spell_test.gd`, which
checks that a spell casts without a script error, not that it does what its summary says.

**Status: all items below are fixed or deliberately settled.** Checks for them live in
`tests/spell_audit_test.gd` (run `--headless --path . res://tests/spell_audit_test.tscn`). New data
keys are documented in `docs/DATA_SCHEMA.md` under "More `combat` keys", "More `effect` keys" and
"More `zone` keys".

Legend: ✅ fixed and tested · ✔ fixed (covered by the Sweep / indirectly) · ⚖ judgment call, see notes ·
◐ improved but still approximate (see "Still approximate" at the end).

---------------------------------------------------------------------------------------------------
## Tier 1: did nothing, or never fired

| Spell | Was | Now |
|---|---|---|
| ✅ absorb_elements | no handler, no reaction hook | Cast automatically when the creature takes ≥6 acid/cold/fire/lightning/thunder from an enemy: resists it, and the next melee hit deals +1d6 per slot of that type |
| ✅ darkness | did nothing | Zone that heavily obscures (`obscure: "darkness"`); truesight, blindsight and Devil's Sight see through |
| ✅ fog_cloud | did nothing | Obscuring zone, +20 ft radius per slot |
| ✅ silvery_barbs | never triggered | Reaction: forces an enemy that succeeded on an attack or a save against a spell to reroll and keep the lower; an ally gets advantage on its next roll |
| ✅ temporal_shunt | never triggered | Reaction: an enemy attacking or casting fails a WIS save and vanishes until the end of the shunter's next turn (used only for a leveled spell or an attack on an ally at half HP or less) |
| ✅ gust | nothing happened | Push 5 ft (Medium or smaller) on a failed STR save |
| ✅ vortex_warp | nothing happened | Teleports the target to the chosen point (or as far from the caster as range allows); allies may fail willingly |
| ✅ summon_beast | nothing summoned | Bestial spirit (TCoE statistics by slot; air, land or water via `opts.beast`), acts after the caster, gone when concentration ends |
| ✅ warding_wind / investiture_of_ice | aura difficult terrain ignored | `is_difficult()` honours auras; Warding Wind also gives ranged weapon attacks against the caster disadvantage. (Warding Wind's own effect was also being overwritten by its aura marker: fixed.) |

## Tier 2: wrong mechanics

| Spell | Now |
|---|---|
| ✅ zephyr_strike | No opportunity attacks for the duration; one charged attack (advantage, +1d8 force) spent on a hit or miss, keeping concentration |
| ✅ blinding_smite | +3d8 radiant; CON save or blinded, repeating the save; melee only |
| ✅ staggering_smite | +4d6 psychic; WIS save or disadvantage and no reactions until the end of its next turn; melee only |
| ✅ banishing_smite | +5d10 force; a target at 50 HP or fewer is banished while the caster concentrates |
| ✅ immolation | 4d6 at the end of each of the target's turns until a DEX save succeeds (which ends the spell) |
| ✅ vitriolic_sphere | 5d4 more acid at the end of the target's next turn, once |
| ✅ tashas_caustic_brew | No damage on casting (matches the summary); 2d4 (+2d4/slot) at the start of each turn; an action scrapes it off |
| ✅ weird | No damage on casting; 4d10 at the end of each turn until a WIS save, which frees only that creature |
| ✅ phantasmal_force | 1d6 at the start of each of the target's turns; an INT check (action) ends it |
| ✅ tashas_hideous_laughter | Prone as well as incapacitated; damage gives a new save with advantage instead of ending the spell outright |
| ✅ dominate_beast / person / monster | Target fights for the caster's side (`dominated` tag swaps its team); a new save each time it takes damage; type limits (beast / humanoid) |
| ✅ enervation | Drains on later turns with the action (sustain, 60 ft), caster heals half each time; a successful initial save ends the spell |
| ✅ enlarge_reduce | Allies enlarged (+1d4 weapon damage, advantage on STR saves); enemies reduced on a failed CON save (−1d4, disadvantage); `opts.mode: "reduce"` for an ally |
| ✅ entangle | Restrains only on casting; the plants stay difficult terrain |
| ✅ cordon_of_arrows | Four pieces (+2 per slot), each one shot at an enemy entering or ending its turn within 30 ft; spent afterwards |
| ✅ compelled_duel | Disadvantage only against creatures other than the caster; can't willingly move beyond 30 ft of the caster |
| ✅ ray_of_sickness | Poisoned only on a failed CON save after the hit |
| ✅ divine_word | By current HP: ≤50 deafened 1 min, ≤40 also blinded 10 min, ≤30 also stunned 1 hour, ≤20 killed |
| ✅ power_word_pain | Only ≤100 HP; speed 10 max, disadvantage on attacks and non-CON saves; CON save at the end of each turn |
| ✅ ottos_irresistible_dance | The target can use its action for a WIS save to stop dancing |
| ✅ maze | The target is cut off from the fight (`pocket`) until it beats DC 20 with an INT check as an action |
| ✅ flesh_to_stone | Three failed CON saves petrify (outlasting concentration); three successes end the spell |
| ✅ contagion | Poisoned; three failed saves bring Blinding Sickness (blinded, disadvantage on WIS saves, 7 days); three successes cure it |
| ✅ negative_energy_flood | Undead gain 5d12 temp HP instead of damage |
| ✅ harm | Can't drop the target below 1 HP; a failed save cuts max HP by the damage |
| ✅ lightning_lure | Pulls 10 ft (Large or smaller); lightning only if the target ends within 5 ft |
| ✅ invulnerability | Immunity to all damage, not resistance |
| ✅ otilukes_resilient_sphere | The target is sealed off: nothing gets in or out, speed 0 |
| ⚖ forcecage | Left as is: no save and traps everyone in the cube, which is what the cage version does |
| ✅ fire_shield | Melee attackers within 5 ft take 2d8; warm (cold resistance, fire damage) or chill (`dtype: "cold"`) |
| ✅ warding_bond | The caster takes the same damage the warded creature takes |
| ✅ silence | No verbal spells inside (actions disabled, reactions blocked); immune to thunder inside |
| ✅ ashardalons_stride | +20 ft (+5/slot); creatures the caster passes within 5 ft take 1d6 (+1d6/slot) fire, once a turn each |
| ✅ kinetic_jaunt | +10 ft, no opportunity attacks, moves through creatures |
| ✅ chaos_bolt | 2d8 + 1d6 (+1d6/slot) of a type set by the d8s; matching d8s leap to another creature within 30 ft |
| ✅ ice_knife | 1d10 piercing on a hit; the burst (DEX save, 2d6 cold, +1d6/slot) hits the target and all within 5 ft, hit or miss |
| ✅ hail_of_thorns | Rides on the next ranged weapon hit: burst around the target |
| ✅ lightning_arrow | Next ranged weapon attack: +4d8 lightning (half on a miss) and a 10-ft burst |
| ✅ healing_spirit | Lasting heal zone (1 + modifier uses, min 2; allies only), movable 30 ft as a bonus action |
| ✅ aura_of_vitality | Bonus action each turn (including the casting turn) heals one creature within 30 ft 2d6 |
| ✅ animal_friendship / charm_person / charm_monster | Type limits (beasts with INT ≤3 / humanoids / any). Charmed creatures now actually can't attack their charmer (previously the condition had no effect at all) |

## Tier 3: cast-turn only → repeatable

All now use the generic `repeat` mechanism (an action shown while the spell lasts; the AI uses it too).

| Spell | Repeat |
|---|---|
| ✅ call_lightning | Action, later turns: another bolt |
| ✅ melfs_minute_meteors | Bonus action: two meteors at a point; 1 on casting + 5 more (+2/slot) |
| ✅ crown_of_stars | Bonus action (from the casting turn): a mote, 7 (+2/slot) |
| ✅ mordenkainens_sword / bigbys_hand / blade_of_disaster | Bonus action strikes |
| ✅ flame_blade | Action (from the casting turn): melee spell attack |
| ✅ shadow_blade | Attack action (Extra Attack applies): finesse weapon attack, 2d8 psychic (3d8 at 3rd–4th, 4d8 at 5th–6th, 5d8 at 7th+) |
| ✅ sunbeam | Action: another line |
| ✅ draconic_transformation | Fly 60 ft; bonus action breath |
| ✅ eyebite | Action: a new target; asleep (default), panicked or sickened via `opts.eyebite` |
| ✅ illusory_dragon | Frightens on casting; bonus action breath from the dragon's position |
| ✅ investiture_of_flame / ice / stone / wind | Their blast actions; Flame's aura now hits at end of turn; Ice and Flame get immunity; Wind flies and gives ranged attacks disadvantage |
| ✅ storm_sphere / wall_of_light | Bonus-action bolt / action ray |
| ✅ holy_weapon | Bonus action: end the spell in a 30-ft burst (the blindness outlasts the spell) |
| ✅ delayed_blast_fireball | Bursts when the spell ends for any reason (or on a free "detonate"), +1d6 for each turn it waited |
| ✅ storm_of_vengeance | Round 2 acid rain, round 3 six lightning bolts, round 4 hail, round 5+ difficult and obscured |
| ✅ flaming_sphere / dust_devil / dawn / whirlwind / healing_spirit | Zone can be moved (flaming sphere and whirlwind ram creatures where they stop) |

## Tier 4: approximations

| Item | Now |
|---|---|
| ✅ Wall spells | New `wall` shape: centred on the chosen point, across the caster's line of sight (wall of fire/thorns/ice/light/sand/water, wind wall, blade barrier, tidal wave, tsunami). Wall of Fire burns at end of turn |
| ✅ Forced movement | thorn_whip (pull 10), pulse_wave (push 15 +5/slot), gravity_sinkhole (pull to centre), gravity_fissure (line + pull of creatures within 10 ft), dust_devil, maelstrom, gust_of_wind, infestation |
| ✅ Zone timing | dust_devil, storm_sphere, incendiary_cloud, maddening_darkness, dawn trigger at end of turn |
| ⚖ Prone durations | Already handled: the engine makes any prone effect last until the creature stands, whatever its duration. Data tidied to 0 |
| ✅ confusion | d10 each turn: wander / do nothing / lash out at a random creature in reach / act normally; +5 ft radius per slot |
| ✅ crown_of_madness | Humanoids only; at the start of its turn it attacks one of its own allies in reach if it can |
| ✅ dissonant_whispers | The target uses its reaction to flee |
| ✅ spirit_shroud | Any attack (spell attacks too) on a creature within 10 ft; no healing until the caster's next turn; upcast every 2 levels; damage type choice |
| ✅ chain_lightning / acid_splash | Arcs within 30 ft of the first target / second target within 5 ft |
| ✅ prismatic_spray | Random ray per creature (5 elements, indigo petrification countdown, violet blindness, double ray on 8) |
| ◐ meteor_swarm | Accepts up to four points via `opts.cells` (a creature is hit once); the UI still picks one point |
| ✅ mass_heal | 700 HP shared among chosen creatures, most hurt first; also cures blindness and deafness |
| ✅ goodberry | Casting feeds one berry; "Feed a Goodberry" action for the other nine (24 hours) |
| ✅ frostbite | Disadvantage on the target's next attack roll only, before the end of its next turn |
| ✅ sickening_radiance | Each failure adds a level of exhaustion (removed when the spell ends); nothing inside can be invisible. Exhaustion now affects speed, attacks and saves |
| ✅ cause_fear | Undead and constructs immune |
| ✅ mind_blank / protection_from_evil_and_good | Psychic immunity + charm immunity / no charm or fear from the listed types |
| ✅ blink | d20 at the end of each turn; 11+ goes to the Ethereal Plane (out of reach) until the start of the next turn |
| ✅ foresight | Advantage on all saves added |
| ✅ magic_weapon / elemental_weapon | +2/+3 at slots 4/6 and +2/2d4, +3/3d4 at slots 5/7; Elemental Weapon picks its element |
| ✅ levitate | Allies can choose to fail the save |
| ✅ tasha's mind whip, stinking cloud, sleet storm, earthquake, maddening darkness, dark star | Mind Whip limits the next turn to the action; Stinking Cloud costs the action (poison-immune unaffected); Sleet Storm and Earthquake force concentration saves; darkness spells obscure |

## Tier 5: label-only effects

| Spell | Decision |
|---|---|
| ⚖ alter_self, enthrall, feather_fall, fortunes_favor, gift_of_alacrity, jump, spider_climb | `combat` set to `null`: nothing in the engine models what they do (falling, jumping, climbing, initiative, appearance), so they now show "[Not automated in combat]" and the DM resolves them rather than appearing to work |
| ✅ calm_emotions | Allies lose charmed/frightened; hostile humanoids that fail a CHA save won't harm the caster's side until harmed |
| ✅ earthbind | Grounds fliers (`no_fly`) |
| ✅ elemental_bane | Chosen type ignores resistance and adds 2d6 once a turn |
| ✅ feeblemind | 4d6 always; on a failure, no spellcasting |
| ✅ reality_break | d10 table on a failed save and at the end of each turn until a save: stunned / 6d12 psychic / 8d12 force + teleport / 10d12 cold + blinded (follows the summary's four outcomes) |
| ⚖ mislead | Was already right: its invisibility doesn't break on attacking |

## Tier 6: special handlers

Exercised by `tests/spell_audit_test.gd` or the existing tests where they matter. Changes:
magic_missile now reads `darts_per_slot` from data (done in a parallel session); far_step can teleport
again each turn (repeat). Polymorph still turns an enemy into the weakest suitable beast (a cat), which
is the usual intent; there is no form picker for enemy targets.

## Audit corrections

Things the original list got wrong, found while fixing:
- **hypnotic_pattern** already ended on damage (it's in `END_ON_DAMAGE_SPELLS`); no change needed.
- **Prone with duration 1** was harmless (see Tier 4).
- **The charmed condition** had no mechanical effect anywhere. That was broader than the audit noticed;
  `charm_blocks()` in `engine_base.gd` now stops a charmed creature from attacking or targeting its charmer.

## Still approximate (deliberately)

- Crown of Madness doesn't make the caster spend an action each turn to maintain it.
- Compelled Duel doesn't end when the caster attacks someone else.
- Mind Whip always leaves the action (the target can't choose movement or bonus action instead).
- Wind Wall doesn't block arrows; Wall of Water doesn't halve fire; Wall of Ice leaves no frigid air.
- Walls have no "hot side"; Incendiary Cloud doesn't drift; Melf's meteors fired together land on one point.
- Bigby's Hand only punches (no grasp, shove or interpose); Mordenkainen's Sword attacks from the caster's range.
- Zephyr Strike's +30 ft speed on the charged attack isn't applied.
- Branding Smite doesn't stop invisibility.
- Blade of Disaster crits on 20 only.
- Temporal Shunt and Silvery Barbs use simple rules for when to spend the reaction.
- Meteor Swarm's extra points need `opts.cells`; the UI picks one point.
