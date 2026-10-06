extends Node3D
# The dormant Arcane Portal in the college ruins: a graveyard arch gate with a
# violet glow and drifting motes. Feed it Mist Hearts to reopen the way back
# to the school (the win condition).

const Art = preload("res://src/core/art.gd")
const Models = preload("res://src/core/models.gd")
const Fx = preload("res://src/core/fx.gd")

var _veil: MeshInstance3D
var _clock := 0.0


func _ready() -> void:
	if Models.spawn(self, "arch_gate") == null:
		var arch := Art.emissive(Color(0.35, 0.3, 0.5), Color(0.45, 0.25, 0.9))
		for side in [-1.5, 1.5]:
			Art.add_mesh(self, Art.cylinder(0.5, 0.6, 4.0), arch, Vector3(side, 2.0, 0))
		Art.add_mesh(self, Art.box(Vector3(4.2, 0.7, 0.9)), arch, Vector3(0, 4.2, 0))
	# a shimmering veil inside the arch
	var veil_mat := StandardMaterial3D.new()
	veil_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	veil_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	veil_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	veil_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	veil_mat.albedo_color = Color(0.55, 0.3, 1.0, 0.35)
	var quad := QuadMesh.new()
	quad.size = Vector2(3.4, 3.8)
	_veil = Art.add_mesh(self, quad, veil_mat, Vector3(0, 2.1, 0))
	Art.add_light(self, Color(0.6, 0.35, 1.0), 8.0, 1.2, Vector3(0, 2.2, 0.8))
	Fx.motes(self, Vector3(0, 2.0, 0), Color(0.7, 0.45, 1.0), 2.2, 36)


func _process(delta: float) -> void:
	_clock += delta
	if _veil != null:
		var m := _veil.material_override as StandardMaterial3D
		m.albedo_color.a = 0.25 + sin(_clock * 2.0) * 0.1
