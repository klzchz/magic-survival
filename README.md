# 🪄 Magic Survival

A 3D wizard-survival game on the **Don't Starve model**, set in an **original
witchcraft universe**. You are an apprentice hurled out of a fallen college of
sorcery through a broken arcane portal, stranded on a haunted island. Learn
spells from grimoire pages, brew in your cauldron, keep the wisp-light burning
through the night, survive the **Blood Moon**, and gather **Mist Hearts** to
reopen the Portal: the way back to the school.

> Engine: **Godot 3.5.x** · everything generated in code, zero external assets.
> Verified headless: **50/50 smoke checks green**.
>
> The original Go/Ebitengine prototype that started this project lives in
> [`legacy-go/`](legacy-go/) — same vision, first steps.

## Run it

1. Open **Godot 3.5.x** (this is a Godot 3 project, not 4).
2. Import this folder (`project.godot`).
3. Press **F5** (Play).

## The loop

1. **Day** — gather ghost-mushrooms and twigs, chop trees, mine rocks,
   explore toward the **Ruins of the Fallen College**.
2. **Night** — the Mist falls and Shadows hunt you. Light burns them
   (wisp-light, campfires, dawn). Spell-kills drop **bones**.
3. **Grimoire pages** (in the ruins) teach real magic — and **knowledge
   survives death**:
   - **LUME** (`F`) — burst of light, burns every Shadow around you.
   - **ESCUDO** (`G`) — 6s barrier, nothing touches you.
   - **ECO ARCANO** — permanently deepens your mana pool.
4. **Every 3rd night is a Blood Moon** — red sky, double spawns, and a
   200hp horror. Kill it for a **Mist Heart** + 5 bones.
5. **3 Mist Hearts reopen the Arcane Portal** in the ruins = you win the run
   and find the way back to the school.
6. Die → new procedural island. Best nights, Hearts and learned spells
   persist (`user://magic_survival_meta.json`).

## The 4 + 1 meters

| Meter | What it does |
| --- | --- |
| **Hunger** | Drains over time; at 0 it eats your Health. Cooked food is stronger and clean. |
| **Health** | Die and it's a new island (roguelite). |
| **Mana** | Regenerates; spent on spells. Eco Arcano raises the cap. |
| **Corruption** | This world's "sanity": raw magic and raw food mark you, and marked prey spawns hungrier Shadows. |
| **Wisp-light** | Your walking light. Feed it twigs or the dark closes in. |

## Controls

| Key | Action |
| --- | --- |
| `WASD` / arrows | Move (camera-relative) |
| `Q` / `PageUp` | Rotate camera (Don't Starve style) |
| `E` | Interact: pick up reagents/pages, chop trees (3 hits), mine rocks (2 hits), touch the Portal |
| `1` | Eat (cooked first, then raw) |
| `2` | Feed a twig to the wisp-light |
| `3` | Improvised potion — 2 mushrooms (+30 hp, +corruption) |
| `4` | Cook a mushroom (near a campfire) |
| `5` | Craft campfire — 2 wood + 1 stone |
| `6` | Craft bone ward — 2 bones + 1 twig (Shadows can't enter) |
| `7` | Craft bone wand — 3 bones + 2 wood (stronger, cheaper bolts) |
| `8` | Craft cauldron — 2 stones + 2 wood |
| `9` | Cauldron elixir — 2 mushrooms (+50 hp, **no** corruption) |
| `F` | Cast **LUME** (after learning it) |
| `G` | Cast **ESCUDO** (after learning it) |
| `Click` / `Space` | Bolt at the nearest Shadow |
| `R` | New island (after death or victory) |

## Verification

Headless smoke suite (no editor needed):

```sh
godot-headless --path . -s test/smoke.gd   # 50 checks, exits 0 on green
```

Covers: world + ruins spawn, gather/chop/mine, eat/brew/cook, campfire,
cauldron elixir, all 3 grimoire spells, shield damage-block, bone drops,
ward repel, wand upgrade, full day/night cycle, Blood Moon boss, the Portal
win (locked below 3 hearts, consumes them at 3), death, roguelite reset and
the persistent meta-save.

## Roadmap

1. Art direction pass (reference scenario: lighting, palette, models).
2. More spell schools + recipe discovery; more creatures per biome.
3. Sound + juice (hit feedback, particles, screen shake).
4. Co-op ("together" mode) — the endgame of the Don't Starve model.
