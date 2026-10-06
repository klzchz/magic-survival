extends Node3D
# Something on the island you pick up or strike: mushroom, twig, grimoire page
# (one touch) or tree / rock (several strikes). Call setup() before adding it
# to the tree; strike() returns true once it is depleted.

const Art = preload("res://src/core/art.gd")
const KINDS := {
	"mushroom": {"hp": 1, "gives": {"mushroom": 1}},
	"twig": {"hp": 1, "gives": {"twig": 1}},
	"page": {"hp": 1, "gives": {}},
	"tree": {"hp": 3, "gives": {"wood": 2}},
	"rock": {"hp": 2, "gives": {"stone": 2}},
}

var kind := "mushroom"
var hp := 1


func setup(k: String) -> void:
	kind = k
	hp = KINDS[k]["hp"]


func _ready() -> void:
	match kind:
		"mushroom":
			Art.add_mesh(self, Art.sphere(0.35, 0.7), Art.emissive(Color(0.70, 0.85, 1.0), Color(0.35, 0.55, 0.9)), Vector3(0, 0.35, 0))
		"twig":
			Art.add_mesh(self, Art.box(Vector3(0.12, 0.12, 0.85)), Art.mat(Color(0.50, 0.38, 0.24)), Vector3(0, 0.08, 0))
		"page":
			Art.add_mesh(self, Art.box(Vector3(0.5, 0.06, 0.65)), Art.emissive(Color(0.95, 0.9, 0.6), Color(0.9, 0.75, 0.2)), Vector3(0, 0.35, 0))
		"tree":
			Art.add_mesh(self, Art.cylinder(0.3, 0.42, 3.0), Art.mat(Color(0.34, 0.24, 0.16)), Vector3(0, 1.5, 0))
			Art.add_mesh(self, Art.sphere(1.7, 3.4), Art.mat(Color(0.11, 0.30, 0.15)), Vector3(0, 3.6, 0))
		"rock":
			Art.add_mesh(self, Art.sphere(0.75, 1.0), Art.mat(Color(0.45, 0.46, 0.50)), Vector3(0, 0.35, 0))


func strike() -> bool:
	hp -= 1
	return hp <= 0


func gives() -> Dictionary:
	return KINDS[kind]["gives"].duplicate()
