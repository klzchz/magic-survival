extends Node3D
# Something an apprentice built: campfire (light + cooking), bone ward
# (Shadows can't enter) or cauldron (clean elixir). Call setup() before
# adding it to the tree.

const Cfg = preload("res://src/core/config.gd")
const Art = preload("res://src/core/art.gd")

var kind := "campfire"


func setup(k: String) -> void:
	kind = k


func _ready() -> void:
	match kind:
		"campfire":
			Art.add_mesh(self, Art.cylinder(0.15, 0.6, 0.9), Art.emissive(Color(1.0, 0.55, 0.15), Color(1.0, 0.45, 0.1)), Vector3(0, 0.45, 0))
			Art.add_light(self, Color(1.0, 0.6, 0.25), Cfg.FIRE_RADIUS, 1.6, Vector3(0, 1.6, 0))
		"ward":
			Art.add_mesh(self, Art.cylinder(0.08, 0.22, 1.6), Art.emissive(Color(0.75, 0.7, 0.9), Color(0.5, 0.3, 0.9)), Vector3(0, 0.8, 0))
		"cauldron":
			Art.add_mesh(self, Art.cylinder(0.7, 0.5, 0.8), Art.emissive(Color(0.12, 0.14, 0.16), Color(0.15, 0.7, 0.3)), Vector3(0, 0.4, 0))


func radius() -> float:
	match kind:
		"campfire":
			return Cfg.FIRE_RADIUS
		"ward":
			return Cfg.WARD_RADIUS
	return Cfg.CAULDRON_RADIUS
