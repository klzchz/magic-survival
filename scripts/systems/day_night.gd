extends Node3D
# Sun, sky, fog and the day/night clock. Emits night_started / dawn so the
# world can react (every 3rd night is a Blood Moon).

signal night_started(blood_moon: bool)
signal dawn(nights: int)

const Cfg = preload("res://scripts/core/config.gd")
const SKY_DAY := Color(0.5, 0.65, 0.85)
const SKY_NIGHT := Color(0.05, 0.06, 0.11)
const SKY_BLOOD := Color(0.16, 0.03, 0.05)

var t := 0.0
var nights := 0
var blood_moon := false
var prev_night := false
var sun: DirectionalLight3D
var env: Environment


func _ready() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = SKY_DAY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.62, 0.72)
	env.ambient_light_energy = 1.0
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = SKY_DAY
	env.fog_depth_begin = 22.0
	env.fog_depth_end = 62.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -40, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
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


func apply_visuals(lit: float) -> void:
	sun.light_energy = 0.12 + lit * 1.15
	env.ambient_light_energy = 0.15 + lit * 0.85
	var night_sky := SKY_BLOOD if blood_moon else SKY_NIGHT
	env.background_color = night_sky.lerp(SKY_DAY, lit)
	env.fog_light_color = env.background_color
