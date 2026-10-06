# World: three explorable biomes (2026-10-06)

Conecta: `design/gdd/game-concept.md` · `design/gdd/survival-loop-mvp.md`

## Scale (measured, then proposed)
| | Today | Proposed |
|---|---|---|
| Playable area | 120 x 120 m (WORLD = 60) | **320 x 320 m** (WORLD = 160), ~7x the area |
| Edge-to-edge at 10.5 m/s | ~11 s (16 s diagonal) | ~30 s straight, ~60-90 s on foot with trails/obstacles |
| Crossings per 240 s day | ~20 | ~3: one biome = one expedition (go, explore, return before night) |
| Each biome | n/a | ~34,000 m2 (2.4x the whole current map) |

## Layout
```
   GOTHIC (NW)  ----- North Road -----  DESERT (NE)
   Sunken Cathedral, abandoned           Dunes, buried ruins,
   gardens, statues, iron gates          crystals, oasis, obelisk
            \                            /
   Old Lamp Road (cobbles, iron lamps)   Waystone Path (cairns)
              \                        /
                 FLOWERED (S) - start
     clearing, Lantern Trail, Naga shrine, Portal temple, woods, lakes
```
- Biome = nearest of three seeds with noise-warped borders; ~20 m blended transition (ground, plants, light).
- Every biome is reachable by road without crossing water; the North Road gives a loop (alternative route). Lakes and the oasis never sit on roads.

## Biomes
| | Flowered (start) | Gothic | Magic Desert |
|---|---|---|---|
| Look | current look kept: tropical, Lanna lanterns, bamboo | dark foliage, dead trees, iron fences, arches, statues, ponds, fog, point lights | dunes, sandstone formations, crystals, oasis, buried ruins |
| Role | basic survival, first base, potion ingredients | enchantments and protection (talismans, wards) | rare materials and upgrades (wand cores) |
| Key materials | grass, twig, log, flint, berries, mushrooms, Moon Petal | Old Iron, Statue Dust, Black Rose | Arcane Crystal, Naga Scale, Star Sand, Oasis Lotus |
| Points of interest | clearing, Naga shrine, Portal temple, small hidden ruins | Sunken Cathedral (guardian + page), statue garden, iron gate maze, reliquary | buried temple (page), crystal field, oasis (base spot), great obelisk (landmark) |
| Functional creatures | passive fauna (flees, drops) | territorial Gargoyles (wake in their zone), a Guardian | flying Dune Raptor (ground shadow + screech before diving), crystal Scarab (charges) |
| Decorative | butterflies, fireflies | crows, drifting fog wisps | dust devils, heat shimmer |

Errantes and the Blood Moon keep working everywhere (magic noise still attracts danger).

## Progression and reasons to return
- Flowered: food, logs, base; potions need Moon Petal (only here).
- Gothic: Old Iron + Statue Dust -> talismans, wards, iron lantern; Guardian drops a grimoire page.
- Desert: Arcane Crystal + Naga Scale -> wand cores; Oasis Lotus -> strongest potion; buried temple page.
- Loops: desert cores need gothic iron to set; gothic talismans need flowered petals; food stays in the flowered biome.
- Expedition objectives chain after the first steps: reach the Gothic gate -> craft a talisman -> reach the oasis -> craft a wand core -> return to the Portal.

## Performance budget
Terrain grid 2 m (~26k vertices); grass instances mostly in the flowered biome; small decor uses visibility ranges (culled beyond ~70 m); light count capped; measured on the RTX build (FPS log) at each stage.

## Stages
1. Scale + biome field + terrain per biome + roads + scenery (visual, navigation, FPS check)
2. Biome materials, resources, recipes
3. Functional creatures per biome
4. Exploration objectives, secrets, discoveries
