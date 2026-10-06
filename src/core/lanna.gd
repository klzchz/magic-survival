extends RefCounted
## Code-built pieces inspired by northern-Thai (Lanna) temples and forests:
## brick chedi (stupa), broken brick walls, paper lanterns on posts and
## bamboo groves. Original stylisation, no real temple reproduced.
##
## Example: `Lanna.lantern_post(parent, pos)` returns the lantern's light.

const Art = preload("res://src/core/art.gd")

const BRICK := Color(0.62, 0.36, 0.26)
const BRICK_DARK := Color(0.45, 0.27, 0.2)
const PLASTER := Color(0.82, 0.78, 0.68)
const GOLD := Color(0.95, 0.75, 0.3)
const MOSS := Color(0.32, 0.45, 0.22)
const LANTERN := Color(1.0, 0.55, 0.2)


static func _box(parent: Node3D, size: Vector3, c: Color, pos: Vector3) -> MeshInstance3D:
	return Art.add_mesh(parent, Art.box(size), Art.mat(c), pos)


## A weathered brick chedi: square plinths, octagonal tiers, bell, spire.
static func chedi(parent: Node3D, pos: Vector3, scale := 1.0, ruined := true) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	root.scale = Vector3.ONE * scale
	parent.add_child(root)
	var y := 0.0
	for i in range(3):  # stepped square plinths
		var w := 6.0 - i * 1.3
		_box(root, Vector3(w, 0.8, w), BRICK if i % 2 == 0 else BRICK_DARK, Vector3(0, y + 0.4, 0))
		y += 0.8
	for i in range(3):  # octagonal tiers
		var r := 1.9 - i * 0.35
		var tier := Art.cylinder(r, r + 0.15, 0.55)
		tier.radial_segments = 8
		Art.add_mesh(root, tier, Art.mat(PLASTER if i == 1 else BRICK), Vector3(0, y + 0.27, 0))
		y += 0.55
	var bell := Art.sphere(1.3, 2.6)
	var bell_mi := Art.add_mesh(root, bell, Art.mat(PLASTER), Vector3(0, y + 0.9, 0))
	bell_mi.scale = Vector3(1, 0.85, 1)
	y += 2.0
	if ruined:  # broken spire, moss creeping
		var stub := Art.cylinder(0.25, 0.5, 1.4)
		Art.add_mesh(root, stub, Art.mat(BRICK_DARK), Vector3(0.1, y + 0.6, 0)).rotation.z = 0.12
		Art.add_mesh(root, Art.sphere(0.9, 0.6), Art.mat(MOSS), Vector3(0.6, 2.5, 1.3))
	else:
		for i in range(5):
			var ring := Art.cylinder(0.32 - i * 0.05, 0.36 - i * 0.05, 0.35)
			Art.add_mesh(root, ring, Art.mat(GOLD), Vector3(0, y + 0.2 + i * 0.35, 0))
		Art.add_mesh(root, Art.cylinder(0.01, 0.12, 1.4), Art.emissive(GOLD, GOLD * 0.6), Vector3(0, y + 2.4, 0))
	return root


## A broken brick wall segment (length in metres) with a ragged top.
static func wall(parent: Node3D, pos: Vector3, length := 5.0, rot := 0.0) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = rot
	parent.add_child(root)
	var x := -length * 0.5
	while x < length * 0.5:
		var h := randf_range(0.6, 2.2)
		_box(root, Vector3(1.0, h, 0.6), BRICK if randf() > 0.3 else BRICK_DARK, Vector3(x + 0.5, h * 0.5, 0))
		x += 1.0
	return root


## Wooden post with a Lanna paper lantern. Guide light only (never burns Errantes).
static func lantern_post(parent: Node3D, pos: Vector3, with_light := true) -> OmniLight3D:
	var root := Node3D.new()
	root.position = pos
	parent.add_child(root)
	var wood := Art.mat(Color(0.35, 0.22, 0.14))
	Art.add_mesh(root, Art.box(Vector3(0.16, 2.6, 0.16)), wood, Vector3(0, 1.3, 0))
	Art.add_mesh(root, Art.box(Vector3(0.9, 0.1, 0.1)), wood, Vector3(0.38, 2.55, 0))
	var paper := Art.emissive(LANTERN, LANTERN * 1.4)
	var body := Art.cylinder(0.26, 0.26, 0.5)
	Art.add_mesh(root, body, paper, Vector3(0.75, 2.1, 0))
	Art.add_mesh(root, Art.sphere(0.27, 0.2), paper, Vector3(0.75, 2.35, 0))
	Art.add_mesh(root, Art.sphere(0.27, 0.2), paper, Vector3(0.75, 1.85, 0))
	Art.add_mesh(root, Art.cylinder(0.02, 0.06, 0.35), Art.mat(Color(0.8, 0.2, 0.15)), Vector3(0.75, 1.6, 0))
	if not with_light:
		return null
	return Art.add_light(root, Color(1.0, 0.6, 0.3), 7.0, 1.4, Vector3(0.75, 2.1, 0))


## A grove of bamboo culms with joints and leaf tufts.
static func bamboo(parent: Node3D, pos: Vector3, culms := 7) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	parent.add_child(root)
	var green := Art.mat(Color(0.42, 0.62, 0.25))
	var joint := Art.mat(Color(0.32, 0.48, 0.18))
	var leaf := Art.mat(Color(0.3, 0.55, 0.2))
	for i in range(culms):
		var off := Vector3(randf_range(-0.9, 0.9), 0, randf_range(-0.9, 0.9))
		var h := randf_range(5.0, 8.0)
		var culm := Node3D.new()
		culm.position = off
		culm.rotation = Vector3(randf_range(-0.08, 0.08), 0, randf_range(-0.08, 0.08))
		root.add_child(culm)
		Art.add_mesh(culm, Art.cylinder(0.09, 0.11, h), green, Vector3(0, h * 0.5, 0))
		var y := 0.9
		while y < h:
			Art.add_mesh(culm, Art.cylinder(0.12, 0.12, 0.06), joint, Vector3(0, y, 0))
			y += randf_range(0.8, 1.1)
		for k in range(5):
			var l := Art.add_mesh(culm, Art.box(Vector3(0.9, 0.03, 0.18)), leaf, Vector3(0, h - k * 0.45, 0))
			l.rotation = Vector3(0.3, randf() * TAU, -0.5)
	return root


## A cut log lying on its side (bark, pale end rings). length in metres.
static func log_piece(parent: Node3D, pos: Vector3, length := 1.2, radius := 0.18, yaw := 0.0) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = yaw
	parent.add_child(root)
	var bark := Art.add_mesh(root, Art.cylinder(radius, radius * 1.05, length), Art.mat(Color(0.36, 0.24, 0.15)), Vector3(0, radius, 0))
	bark.rotation.z = PI / 2.0
	for side in [-1.0, 1.0]:
		var ring := Art.add_mesh(root, Art.cylinder(radius * 0.92, radius * 0.92, 0.02), Art.mat(Color(0.78, 0.62, 0.42)), Vector3(side * length * 0.5, radius, 0))
		ring.rotation.z = PI / 2.0
	return root
