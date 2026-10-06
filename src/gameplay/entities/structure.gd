extends Node3D
# Something an apprentice built: campfire (light + cooking), bone ward
# (Shadows can't enter) or cauldron (clean elixir). Call setup() before
# adding it to the tree. Lights flicker; fire and brew are particles.

const Cfg = preload("res://src/core/config.gd")
const Art = preload("res://src/core/art.gd")
const Models = preload("res://src/core/models.gd")
const Fx = preload("res://src/core/fx.gd")

var kind := "campfire"
var light: OmniLight3D
var _base_energy := 1.0
var _clock := 0.0


func setup(k: String) -> void:
	kind = k


func _ready() -> void:
	_clock = randf() * TAU
	match kind:
		"campfire":
			# ring of stones around crossed logs, flames and warm light
			for i in range(7):
				var a := TAU * i / 7.0
				var stone := Models.spawn_variant(self, "rock", Vector3(cos(a), 0, sin(a)) * 0.95, 0.45)
				if stone == null:
					Art.add_mesh(self, Art.sphere(0.18, 0.22), Art.mat(Color(0.4, 0.4, 0.42)), Vector3(cos(a), 0.08, sin(a)) * 0.95)
			for i in range(3):
				var log_node := Models.spawn(self, "log_s", Vector3.ZERO, 0.9)
				if log_node == null:
					log_node = Art.add_mesh(self, Art.cylinder(0.12, 0.12, 1.0), Art.mat(Color(0.35, 0.22, 0.12)), Vector3(0, 0.12, 0))
				log_node.rotation.y = TAU * i / 3.0
			Fx.flames(self, Vector3(0, 0.45, 0))
			light = Art.add_light(self, Color(1.0, 0.6, 0.25), Cfg.FIRE_RADIUS, 1.8, Vector3(0, 1.6, 0))
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
	light.light_energy = _base_energy * (1.0 + sin(_clock * 11.0) * flicker * 0.5 + sin(_clock * 23.0) * flicker * 0.5)


func radius() -> float:
	match kind:
		"campfire":
			return Cfg.FIRE_RADIUS
		"ward":
			return Cfg.WARD_RADIUS
	return Cfg.CAULDRON_RADIUS
