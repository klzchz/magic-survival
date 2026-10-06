extends Node3D
# A creature of the Mist: a spectral skeleton that rises from the ground at
# night, hunts the nearest living apprentice in the dark, burns in any light
# (sun, wisp, campfire) and is pushed out of bone-ward circles. The Blood
# Moon horror is the same creature with boss = true (a giant red warrior).

const Art = preload("res://src/core/art.gd")
const Models = preload("res://src/core/models.gd")
const Rig = preload("res://src/core/rig.gd")

var boss := false
var hp := 40.0
var last_hitter = null     # apprentice whose spell hit it last (gets the drop)
var model: Node3D
var rig: Rig
var _attack_cd := 0.0
var _burning := false
var _spectral: StandardMaterial3D
var _burn: StandardMaterial3D


func setup(is_boss: bool) -> void:
	boss = is_boss
	hp = 200.0 if boss else 40.0


func _ready() -> void:
	var tint := Color(0.85, 0.1, 0.15) if boss else Color(0.45, 0.25, 1.0)
	_spectral = _overlay(tint, 0.35)
	_burn = _overlay(Color(1.0, 0.6, 0.2), 0.6)
	var pivot := Node3D.new()
	pivot.position.y = -hover_height()   # feet on the ground, logic stays at hover height
	add_child(pivot)
	model = Models.spawn(pivot, "skeleton_boss" if boss else ["skeleton", "skeleton", "skeleton_mage"].pick_random())
	if model == null:
		model = pivot
		Art.add_mesh(pivot, Art.sphere(1.8, 3.6) if boss else Art.sphere(0.7, 1.4), Art.mat(Color(0.05, 0.02, 0.09), true), Vector3(0, hover_height(), 0))
	else:
		Models.overlay(model, _spectral)
		for eyes in model.find_children("*Eyes*", "MeshInstance3D", true, false):
			(eyes as MeshInstance3D).material_override = Art.emissive(tint, tint * 2.0)
	if boss:
		Art.add_light(self, Color(1.0, 0.2, 0.2), 9.0, 1.4, Vector3(0, 1.0, 0))
	rig = Rig.new(model)
	rig.set_base("Walking_D_Skeletons")
	rig.action("Spawn_Ground_Skeletons")


func _overlay(c: Color, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(c.r, c.g, c.b, alpha)
	return m


func hover_height() -> float:
	return 1.8 if boss else 1.0


func _process(delta: float) -> void:
	if rig != null:
		rig.tick(delta)


func _set_burning(on: bool) -> void:
	if on == _burning or model == null:
		return
	_burning = on
	Models.overlay(model, _burn if on else _spectral)
	if on and rig != null:
		rig.action("Hit_A")


func tick(delta: float, world, lit: float, _clock: float) -> void:
	_attack_cd = maxf(0.0, _attack_cd - delta)
	if world.is_lit(position, lit):
		hp -= 22.0 * delta
		_set_burning(true)
		return
	_set_burning(false)
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
		if model != null:
			model.rotation.y = atan2(to_p.x, to_p.z)
	p = world.apply_wards(p)
	p.y = world.terrain.height_at(p.x, p.z) + hover_height()
	position = p
	var reach := 2.4 if boss else 1.4
	if d < reach:
		target.hurt(25.0 if boss else 14.0, delta)
		if _attack_cd <= 0.0 and rig != null:
			_attack_cd = 1.0
			rig.action("1H_Melee_Attack_Chop")
