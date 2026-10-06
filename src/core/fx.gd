extends RefCounted
# Particle recipes (CPUParticles3D, so they also run on the Compatibility
# renderer): campfire flames, cauldron bubbles, portal motes, fireflies, leaves.

const Art = preload("res://src/core/art.gd")


static func _particles(parent: Node3D, amount: int, lifetime: float, mesh: Mesh, mat: Material, pos := Vector3.ZERO) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.mesh = mesh
	p.material_override = mat
	p.position = pos
	parent.add_child(p)
	return p


static var _soft_dot: GradientTexture2D


# Radial white-to-transparent dot so particles read as glows, not squares.
static func soft_dot() -> GradientTexture2D:
	if _soft_dot == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		_soft_dot = GradientTexture2D.new()
		_soft_dot.gradient = g
		_soft_dot.fill = GradientTexture2D.FILL_RADIAL
		_soft_dot.fill_from = Vector2(0.5, 0.5)
		_soft_dot.fill_to = Vector2(1.0, 0.5)
		_soft_dot.width = 64
		_soft_dot.height = 64
	return _soft_dot


static func _glow_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = soft_dot()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.emission_enabled = true
	m.emission = Color(c.r, c.g, c.b)
	m.emission_energy_multiplier = 2.5
	return m


static func _fade(c1: Color, c2: Color) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, c1)
	g.set_color(1, c2)
	return g


static func flames(parent: Node3D, pos: Vector3) -> CPUParticles3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.45, 0.45)
	var p := _particles(parent, 40, 0.8, quad, _glow_mat(Color(1.0, 0.7, 0.3)), pos)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.35
	p.direction = Vector3.UP
	p.spread = 12.0
	p.gravity = Vector3(0, 1.5, 0)
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 1.8
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	p.color_ramp = _fade(Color(1.0, 0.85, 0.4, 1.0), Color(0.9, 0.2, 0.05, 0.0))
	return p


static func bubbles(parent: Node3D, pos: Vector3, c: Color) -> CPUParticles3D:
	var s := SphereMesh.new()
	s.radius = 0.09
	s.height = 0.18
	var p := _particles(parent, 18, 1.4, s, _glow_mat(c), pos)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.45
	p.direction = Vector3.UP
	p.gravity = Vector3(0, 0.6, 0)
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.6
	p.color_ramp = _fade(Color(c.r, c.g, c.b, 0.9), Color(c.r, c.g, c.b, 0.0))
	return p


static func motes(parent: Node3D, pos: Vector3, c: Color, radius: float, amount := 40) -> CPUParticles3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.32, 0.32)
	var p := _particles(parent, amount, 3.0, quad, _glow_mat(c), pos)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius
	p.direction = Vector3.UP
	p.spread = 180.0
	p.gravity = Vector3(0, 0.25, 0)
	p.initial_velocity_min = 0.1
	p.initial_velocity_max = 0.5
	p.color_ramp = _fade(Color(c.r, c.g, c.b, 0.0), Color(c.r, c.g, c.b, 0.0))
	p.color_ramp.add_point(0.5, Color(c.r, c.g, c.b, 1.0))
	return p


# Night fireflies around the camera target; the world toggles emitting.
static func fireflies(parent: Node3D) -> CPUParticles3D:
	var p := motes(parent, Vector3(0, 1.5, 0), Color(0.75, 1.0, 0.45), 18.0, 70)
	p.lifetime = 5.0
	p.gravity = Vector3.ZERO
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(18, 2.5, 18)
	return p


# Daytime falling leaves in autumn tones.
static func leaves(parent: Node3D) -> CPUParticles3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.14, 0.1)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.95, 0.55, 0.15)
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var p := _particles(parent, 40, 6.0, quad, m, Vector3(0, 6, 0))
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(20, 1, 20)
	p.gravity = Vector3(0.4, -0.9, 0.2)
	p.angular_velocity_min = -180.0
	p.angular_velocity_max = 180.0
	p.color = Color(1, 1, 1)
	var g := Gradient.new()
	g.set_color(0, Color(0.95, 0.6, 0.15))
	g.set_color(1, Color(0.7, 0.25, 0.1))
	p.color_initial_ramp = g
	return p
