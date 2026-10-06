extends Node3D
# Sun, sky, fog and the day/night clock. Emits night_started / dawn so the
# world can react (every 3rd night is a Blood Moon).

signal night_started(blood_moon: bool)
signal dawn(nights: int)

const Cfg = preload("res://src/core/config.gd")
const SKY_DAY := Color(0.38, 0.6, 0.86)
const SKY_NIGHT := Color(0.04, 0.05, 0.12)
const SKY_BLOOD := Color(0.20, 0.03, 0.05)
const HORIZON_DAY := Color(0.82, 0.8, 0.7)     # humid tropical haze    # warm autumn haze
const HORIZON_NIGHT := Color(0.16, 0.10, 0.26)  # violet dusk
const SUN_DAY := Color(1.0, 0.86, 0.68)
const MOON := Color(0.55, 0.65, 1.0)

var t := 0.0
var nights := 0
var blood_moon := false
var prev_night := false
var sun: DirectionalLight3D
var env: Environment
var sky_mat: ProceduralSkyMaterial


func _ready() -> void:
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = SKY_DAY
	sky_mat.sky_horizon_color = HORIZON_DAY
	sky_mat.ground_horizon_color = HORIZON_DAY
	sky_mat.ground_bottom_color = Color(0.1, 0.1, 0.12)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.6, 0.75)
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.15
	env.glow_hdr_threshold = 0.9
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = HORIZON_DAY
	env.fog_depth_begin = 38.0
	env.fog_depth_end = 110.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -42, 0)
	sun.light_energy = 1.1
	sun.light_color = SUN_DAY
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 70.0
	add_child(sun)


func reset() -> void:
	t = 0.0
	nights = 0
	blood_moon = false
	prev_night = false


# 0.0 = deep night, 1.0 = midday. Phase 0 = morning: the first day is a
# grace period to learn the loop (Don't Starve rule), night comes later.
func light() -> float:
	var phase := fmod(t, Cfg.DAY_LENGTH) / Cfg.DAY_LENGTH
	return clampf(0.5 + 0.5 * sin(phase * TAU + PI / 6.0), 0.0, 1.0)


func advance(delta: float) -> void:
	t += delta
	var night := light() < 0.35
	if night and not prev_night:
		prev_night = true
		blood_moon = (nights + 1) % 3 == 0
		night_started.emit(blood_moon)
	elif prev_night and not night:
		prev_night = false
		nights += 1
		blood_moon = false
		dawn.emit(nights)


## lit: 0 night .. 1 midday · mix: biome weights at the camera's focus
## (x flowered, y gothic, z desert) so fog, light and haze follow the region.
func apply_visuals(lit: float, mix := Vector3(1, 0, 0)) -> void:
	# the sun becomes a cold moon at night (Blood Moon tints everything red)
	var moon := Color(1.0, 0.35, 0.35) if blood_moon else MOON
	sun.light_color = moon.lerp(SUN_DAY, lit)
	sun.light_energy = 0.3 + lit * 1.15
	env.ambient_light_energy = 0.2 + lit * 0.45
	env.ambient_light_color = Color(0.32, 0.30, 0.55).lerp(Color(0.62, 0.6, 0.75), lit)
	var night_sky := SKY_BLOOD if blood_moon else SKY_NIGHT
	var top := night_sky.lerp(SKY_DAY, lit)
	var horizon := (Color(0.35, 0.06, 0.08) if blood_moon else HORIZON_NIGHT).lerp(HORIZON_DAY, lit)
	sky_mat.sky_top_color = top
	sky_mat.sky_horizon_color = horizon
	sky_mat.ground_horizon_color = horizon
	# regional atmosphere
	var goth_fog := Color(0.32, 0.36, 0.45).lerp(Color(0.1, 0.11, 0.16), 1.0 - lit)
	var desert_fog := Color(0.96, 0.84, 0.62).lerp(Color(0.3, 0.22, 0.25), 1.0 - lit)
	env.fog_light_color = horizon * mix.x + goth_fog * mix.y + desert_fog * mix.z
	env.fog_depth_begin = 38.0 * mix.x + 14.0 * mix.y + 55.0 * mix.z
	env.fog_depth_end = 110.0 * mix.x + 70.0 * mix.y + 160.0 * mix.z
	sun.light_energy *= 1.0 * mix.x + 0.62 * mix.y + 1.12 * mix.z
	env.ambient_light_energy *= 1.0 * mix.x + 0.75 * mix.y + 1.1 * mix.z
	env.ambient_light_color = env.ambient_light_color * mix.x + Color(0.42, 0.45, 0.6) * mix.y + Color(0.75, 0.68, 0.55) * mix.z
