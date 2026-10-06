# Survival loop MVP (DST model, magical) - 2026-10-06

Studied Don't Starve Together and kept its load-bearing loops, re-skinned for an
arcane world. Values live in `assets/data/*.json` (data-driven, tune there).

| DST mechanic | Magical Survive version |
|---|---|
| 15-slot inventory, stacks, hand/body equip | Same: 15 slots, stack caps per item, `hand` + `body` slots |
| Tools with durability (axe, pickaxe) | Machado (trees), Picareta (rocks); uses drain per strike |
| Pick by hand, regrowing grass/saplings/berries | Tufo de capim, Muda, Arbusto de frutinha regrow after a timer |
| Flint on the ground (first axe) | Pederneira scattered on the ground |
| Food spoils, cook on fire | Freshness per stack; spoiled food = less hunger + corruption; right-click near fire cooks |
| Campfire burns fuel | Fogueira burns down; add grass/twig/log as fuel; dies to embers |
| Torch, grass armor | Tocha (hand light, burns over time), Armadura de Grama (absorbs 60%) |
| Science Machine prototyping | Altar Arcano unlocks the Magia tab; Caldeirão unlocks Alquimia |
| Darkness (Charlie) | The Mist wounds you at night with no light (wisp empty, no torch/fire) |
| Sanity + shadow creatures | Corrupção: raw magic/food raises it, slightly more Errantes |
| (new) Hunted for your magic | **Arcane noise** (option B, Lucas 2026-10-06): spells, potions, essence and magic crafting raise a 0-100 noise meter that fades 6/s. Errantes sense you within 10m; noise lets them hear you up to 40m. Night spawns: a few base Errantes, many more when someone is loud, born near the loudest apprentice. Unaware Errantes wander. The Blood Moon horror always hunts. A violet ring on the ground telegraphs each noise. Tuning: `assets/data/night.json`. |
| Nightmare fuel | Essência da Névoa (spell-killed Errantes) |
| Character select with perks | 3 apprentices (below) |

## Characters
- **Aldric, o Alquimista** (Mage): potions +50%, more mana; frail (80 hp).
- **Brasa, a Piromante** (Rogue hooded): her fires burn 2x longer, bolt +50% vs Shadows, starts with a torch; always hungry (+30% hunger drain).
- **Thorne, o Guardião** (Knight): 150 hp, takes 25% less damage, chops/mines with double strikes, starts with an axe; poor caster (60 mana, half regen).

## Controls
WASD move · Q/PgUp camera · E/Space act (pick, chop, mine, add fuel, portal) · F / left click spell · Z Lume · X Escudo ·
1-9,0 use slot · right click slot = secondary (cook / fuel / drop) · Tab crafting · R new island after death.

Connects to: `design/gdd/game-concept.md`.
