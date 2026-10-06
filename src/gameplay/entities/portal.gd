extends Node3D
# The dormant Arcane Portal in the college ruins. Feed it Mist Hearts to
# reopen the way back to the school (the win condition).

const Art = preload("res://src/core/art.gd")


func _ready() -> void:
	var arch := Art.emissive(Color(0.35, 0.3, 0.5), Color(0.45, 0.25, 0.9))
	for side in [-1.5, 1.5]:
		Art.add_mesh(self, Art.cylinder(0.5, 0.6, 4.0), arch, Vector3(side, 2.0, 0))
	Art.add_mesh(self, Art.box(Vector3(4.2, 0.7, 0.9)), arch, Vector3(0, 4.2, 0))
	Art.add_light(self, Color(0.6, 0.35, 1.0), 7.0, 0.9, Vector3(0, 2.2, 0))
