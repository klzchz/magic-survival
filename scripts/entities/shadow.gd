extends Node3D
# A creature of the Mist. Hunts the nearest living apprentice in the dark,
# burns in any light (sun, wisp, campfire) and is pushed out of bone-ward
# circles. The Blood Moon horror is the same creature with boss = true.

const Art = preload("res://scripts/core/art.gd")

var boss := false
var hp := 40.0
var last_hitter = null     # apprentice whose spell hit it last (gets the drop)


func setup(is_boss: bool) -> void:
	boss = is_boss
	hp = 200.0 if boss else 40.0


func _ready() -> void:
	var mesh := Art.sphere(1.8, 3.6) if boss else Art.sphere(0.7, 1.4)
	var color := Color(0.12, 0.01, 0.04) if boss else Color(0.05, 0.02, 0.09)
	Art.add_mesh(self, mesh, Art.mat(color, true))


func hover_height() -> float:
	return 1.8 if boss else 1.0


func tick(delta: float, world, lit: float, clock: float) -> void:
	if world.is_lit(position, lit):
		hp -= 22.0 * delta
		return
	var target = world.nearest_player(position)
	if target == null:
		return
	var to_p: Vector3 = target.position - position
	to_p.y = 0.0
	var d := to_p.length()
	var speed := 2.6 if boss else 3.6
	var p := position
	if d > 0.001:
		p += to_p.normalized() * speed * delta
	p = world.apply_wards(p)
	p.y = hover_height() + sin(clock * 3.0 + hp) * 0.2
	position = p
	var reach := 2.4 if boss else 1.4
	if d < reach:
		target.hurt(25.0 if boss else 14.0, delta)
