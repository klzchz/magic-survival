extends Node3D
## Something an apprentice built: campfire (burns fuel, light + cooking),
## Arcane Altar (unlocks the Magia tab), bone ward (Shadows can't enter) or
## cauldron (unlocks Alquimia). Call setup() before adding it to the tree.

const Cfg = preload("res://src/core/config.gd")
const Art = preload("res://src/core/art.gd")
const Models = preload("res://src/core/models.gd")
const Fx = preload("res://src/core/fx.gd")
const Lanna = preload("res://src/core/lanna.gd")

const FIRE_START := 120.0  # seconds of fuel a new campfire starts with
const FIRE_MAX := 240.0
const TECH_RADIUS := 6.0   # how close you stand to use an altar / cauldron

var kind := "campfire"
var fuel := 0.0
var fuel_mult := 1.0       # Brasa's fires burn twice as long
var light: OmniLight3D
var flames: CPUParticles3D
var _base_energy := 1.0
var _clock := 0.0


func setup(k: String, burn_mult := 1.0) -> void:
	kind = k
	fuel_mult = burn_mult
	if kind == "campfire":
		fuel = FIRE_START


func _ready() -> void:
	_clock = randf() * TAU
	match kind:
		"campfire":
			for i in range(7):
				var a := TAU * i / 7.0
				if Models.spawn_variant(self, "rock", Vector3(cos(a), 0, sin(a)) * 0.95, 0.45) == null:
					Art.add_mesh(self, Art.sphere(0.18, 0.22), Art.mat(Color(0.4, 0.4, 0.42)), Vector3(cos(a), 0.08, sin(a)) * 0.95)
			for i in range(3):  # crossed logs
				Lanna.log_piece(self, Vector3.ZERO, 1.1, 0.12, TAU * i / 3.0)
			flames = Fx.flames(self, Vector3(0, 0.45, 0))
			light = Art.add_light(self, Color(1.0, 0.6, 0.25), Cfg.FIRE_RADIUS, 1.8, Vector3(0, 1.6, 0))
		"altar":
			if Models.spawn(self, "shrine", Vector3.ZERO, 1.4) == null:
				Art.add_mesh(self, Art.box(Vector3(1.2, 1.0, 1.2)), Art.mat(Color(0.5, 0.48, 0.55)), Vector3(0, 0.5, 0))
			light = Art.add_light(self, Color(0.7, 0.5, 1.0), 5.0, 1.0, Vector3(0, 2.5, 0))
			Fx.motes(self, Vector3(0, 2.0, 0), Color(0.75, 0.55, 1.0), 1.2, 20)
		"ward":
			if Models.spawn(self, "post_skull") == null:
				Art.add_mesh(self, Art.cylinder(0.08, 0.22, 1.6), Art.emissive(Color(0.75, 0.7, 0.9), Color(0.5, 0.3, 0.9)), Vector3(0, 0.8, 0))
			light = Art.add_light(self, Color(0.6, 0.35, 1.0), 4.0, 1.0, Vector3(0, 2.4, 0))
			Fx.motes(self, Vector3(0, 1.0, 0), Color(0.65, 0.4, 1.0), Cfg.WARD_RADIUS * 0.8, 24)
		"cauldron":
			var iron := Art.mat(Color(0.12, 0.12, 0.14))
			Art.add_mesh(self, Art.sphere(0.75, 1.2), iron, Vector3(0, 0.6, 0))
			var rim := TorusMesh.new()
			rim.inner_radius = 0.5
			rim.outer_radius = 0.66
			Art.add_mesh(self, rim, iron, Vector3(0, 1.08, 0))
			Art.add_mesh(self, Art.cylinder(0.52, 0.52, 0.04), Art.emissive(Color(0.2, 0.9, 0.35), Color(0.15, 0.8, 0.3)), Vector3(0, 1.02, 0))
			for i in range(3):
				var a := TAU * i / 3.0
				Art.add_mesh(self, Art.cylinder(0.06, 0.06, 0.4), iron, Vector3(cos(a) * 0.5, 0.15, sin(a) * 0.5))
			Fx.bubbles(self, Vector3(0, 1.1, 0), Color(0.3, 1.0, 0.45))
			light = Art.add_light(self, Color(0.3, 1.0, 0.45), 4.5, 1.0, Vector3(0, 1.6, 0))
	if light != null:
		_base_energy = light.light_energy


func _process(delta: float) -> void:
	if light == null:
		return
	_clock += delta
	var flicker := 0.12 if kind == "campfire" else 0.05
	var strength := 1.0
	if kind == "campfire":
		strength = clampf(fuel / 60.0, 0.0, 1.0)
	light.light_energy = _base_energy * strength * (1.0 + sin(_clock * 11.0) * flicker * 0.5 + sin(_clock * 23.0) * flicker * 0.5)


## Campfires burn down; at 0 fuel they are cold embers (no light, no cooking).
func burn(delta: float) -> void:
	if kind != "campfire" or fuel <= 0.0:
		return
	fuel = maxf(0.0, fuel - delta / fuel_mult)
	if flames != null:
		flames.emitting = fuel > 0.0


func add_fuel(seconds: float) -> void:
	fuel = minf(FIRE_MAX, fuel + seconds)
	if flames != null:
		flames.emitting = true


func burning() -> bool:
	return kind == "campfire" and fuel > 0.0


## Light / effect radius (campfire shrinks as it burns out).
func radius() -> float:
	match kind:
		"campfire":
			return Cfg.FIRE_RADIUS * clampf(fuel / 60.0, 0.4, 1.0) if fuel > 0.0 else 0.0
		"ward":
			return Cfg.WARD_RADIUS
	return TECH_RADIUS
