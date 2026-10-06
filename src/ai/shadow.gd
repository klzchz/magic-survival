extends Node3D
# An Errante of the Mist: a spectral skeleton that rises at night and HUNTS
# MAGIC. It notices an apprentice only up close, or from far away when that
# apprentice is loud with arcane noise (spells, potions, magic crafting);
# otherwise it wanders. Sunlight and burning campfires sear it (wisp, torch
# and lantern light don't); bone wards push it out of their circle. The Blood Moon horror is the same
# creature with boss = true (a giant red warrior). Design: GDD "Errantes".

const Art = preload("res://src/core/art.gd")
const Models = preload("res://src/core/models.gd")
const Rig = preload("res://src/core/rig.gd")
const Data = preload("res://src/core/data.gd")

var boss := false
var hp := 40.0
var last_hitter = null     # apprentice whose spell hit it last (gets the drop)
var model: Node3D
var rig: Rig
var _attack_cd := 0.0
var _wander := Vector3.ZERO
var _wander_t := 0.0
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
	if world.burns_errante(position, lit, boss):
		hp -= 22.0 * delta
		_set_burning(true)
		if lit <= 0.5:
			world.discover("burns")
		return
	_set_burning(false)
	var target = world.nearest_player(position) if boss else world.errante_target(position)  # the Blood Moon horror always hunts
	if target == null:  # nothing heard: drift through the dark
		_wander_t -= delta
		if _wander_t <= 0.0:
			_wander_t = randf_range(2.0, 5.0)
			var a := randf() * TAU
			_wander = Vector3(cos(a), 0, sin(a))
		var wp: Vector3 = world.apply_wards(position + _wander * float(Data.night("wander_speed", 1.2)) * delta)
		wp.y = world.terrain.height_at(wp.x, wp.z) + hover_height()
		if model != null:
			model.rotation.y = atan2(_wander.x, _wander.z)
		position = wp
		return
	var to_p: Vector3 = target.position - position
	to_p.y = 0.0
	var d := to_p.length()
	var speed := 2.6 if boss else 3.6
	var p := position
	var reach_stop := (2.4 if boss else 1.4) * 0.75
	if d > reach_stop:  # stop at striking distance instead of walking into the apprentice
		p += to_p.normalized() * minf(speed * delta, d - reach_stop)
		if model != null:
			model.rotation.y = atan2(to_p.x, to_p.z)
	p = world.apply_wards(p)
	p.y = world.terrain.height_at(p.x, p.z) + hover_height()
	position = p
	var reach := 2.4 if boss else 1.4
	if d < reach and _attack_cd <= 0.0:
		# discrete, telegraphed blows (no stacking damage-per-frame)
		_attack_cd = float(Data.night("hit_interval", 1.3)) * randf_range(0.9, 1.15)
		target.hit(float(Data.night("boss_hit_damage" if boss else "hit_damage", 8)))
		if rig != null:
			rig.action("1H_Melee_Attack_Chop")
