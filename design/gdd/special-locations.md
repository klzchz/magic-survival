# Special locations, guardians, wands and signature spells (2026-10-06)

Conecta: `design/gdd/world-biomes.md` · `design/gdd/survival-loop-mvp.md`

## Plan table

| | Flowered (south) | Gothic (north-west) | Magic desert (north-east) |
|---|---|---|---|
| Location | **School-Temple of a Thousand Lanterns**: Lanna-inspired school temple, gate with lantern posts, garden courtyard, red-carpet colonnade, main hall (arena), sanctum behind a jade seal | **Vesper Keep**: small dark castle, iron gate, great hall with arches and statues, torch-lit dramatic light, reliquary room | **Starmosaic Sanctuary**: half-buried shrine, mosaic floor, crystal clusters, open courtyard (arena), buried vault |
| Guardian | **Jade Naga** (statue that wakes when you enter the hall) | **Sentinel Gargoyle** (stone while lit, flies in the dark) | **Crystal Scarab King** (burrows, charges) |
| Behaviour | slithers toward you; rests 1.6 s after every attack (punish window) | perches, then dives; stone phase near torches (no damage taken) | burrows under the sand, surfaces under you, charges in straight lines |
| Telegraphed attacks | **Tail sweep**: red ring 4 m, 0.9 s; jump or step out. **Jade spit**: red lane 10 m, 0.8 s; side-step | **Dive**: shadow grows at the landing spot 1.0 s. **Screech**: ring 6 m, pushes back | **Charge**: lane 12 m, 0.9 s. **Eruption**: sand ring under you, 1.0 s |
| Main reward (behind the guardian) | **Jade Core** (wand core: balanced) | **Spell page: Ethereal Step** (common dash) | **Rare recipe: Solar Lantern** (portable light that sears Errantes) |
| Loose loot in the location | mushrooms, berries, flint, Mist Essence, an elixir | Old Iron, Statue Dust, Black Rose | Arcane Crystal, Star Sand, Oasis Lotus |
| Map | hidden until discovered; white marker = explored, gold marker with check = cleared | same | same |

Flee and return: if every apprentice stays out of the arena for 6 s, the guardian goes back to sleep and heals fully. Rewards never duplicate: the reward appears once (on the guardian's defeat) as a normal ground item; `cleared` is saved with the run, so loading or returning never respawns the guardian or the reward.

## Wands (assembled at the Arcane Altar)

| Wood (base) | Where | Base stats |
|---|---|---|
| Twig (starter) | saplings | damage 60, mana 20, noise 18 |
| Bamboo | flowered groves | damage x0.85, mana x0.8, faster recast |
| Deadwood | gothic dead trees | damage x1.2, noise x1.2 |

| Core | Effect | Cost |
|---|---|---|
| Naga Scale | damage x1.7 | mana x1.1, noise x1.4 |
| Hongsa Feather | noise x0.45, mana x0.9 | no damage bonus |
| **Jade (temple reward)** | damage x1.35, mana x0.9 | noise x1.1 |

The starter wand (5 bolts, 300 damage at 100 mana) plus melee with E is enough for the Jade Naga (HP 260). Stage 1 ships the Jade Core; wood bases come with the gothic stage.

## Signature spells (key V), common spells kept (Bolt F, Lume Z, Shield X, Echo)

| Apprentice | Spell | Function | Mana | Cooldown | Noise | Visual |
|---|---|---|---|---|---|---|
| Aldric, the Alchemist | **Healing Mist** | green cloud 3 m, heals 4/s for 5 s (allies) | 30 | 20 s | 12 | green bubbling cloud |
| Brasa, the Pyromancer | **Ember Ring** | ring of fire 4 m for 4 s; burns enemies crossing it, counts as fire light vs Errantes | 35 | 18 s | 28 | ring of flames |
| Thorne, the Guardian | **Guardian's Charge** | 6 m dash, knocks back and stuns 1.5 s; passes through telegraphs | 20 | 10 s | 10 | silver trail + shockwave |

Shown on the character select cards and on the spell bar (name, key, mana, cooldown, noise).

## Stages
1. School-Temple + Jade Naga + Jade Core + map status + save (this commit).
2. Signature spells + spell bar + character select info.
3. Vesper Keep + Sentinel Gargoyle + Ethereal Step + wood bases.
4. Starmosaic Sanctuary + Crystal Scarab King + Solar Lantern.
