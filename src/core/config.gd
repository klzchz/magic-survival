extends RefCounted
# Tuning constants shared by every system. Preload as `Cfg` and read Cfg.X.

const WORLD := 160.0          # ground half-extent (world spans -WORLD..WORLD on X/Z): 320 x 320 m, three biomes
const SPEED := 10.5           # apprentice top speed (units/s)
const ACCEL := 42.0           # ground acceleration (units/s^2)
const DECEL := 36.0           # ground braking (units/s^2)
const AIR_CONTROL := 0.35     # fraction of acceleration available mid-air
const JUMP_VELOCITY := 7.2    # take-off speed of the magic hop
const GRAVITY := 22.0
const DAY_LENGTH := 240.0     # seconds for a full day-night cycle (tune after playtests)
const FIRE_RADIUS := 9.0      # campfire light/burn radius
const WARD_RADIUS := 6.0      # bone ward repel radius
const CAULDRON_RADIUS := 4.0  # how close you must stand to brew
const RUINS_RADIUS := 12.0    # fallen-college ruins area radius
const INTERACT_RADIUS := 2.8  # reach for E
const FOCUS_RADIUS := 6.0     # E highlights / walks to targets this close
const PORTAL_RADIUS := 3.5    # reach to touch the Portal
const PORTAL_HEARTS := 3      # Mist Hearts needed to reopen the Arcane Portal
const SHADOW_CAP := 40        # max Shadows alive at once
const MAX_PLAYERS := 4        # co-op cap (Phase 2)
const SAVE_PATH := "user://magic_survival_meta.json"
const SPELL_ORDER := ["lume", "escudo", "eco"]
const DARK_WARN_AT := 2.3     # show the darkness warning only at its start
