extends RefCounted
## The School-Temple of a Thousand Lanterns (flowered biome), a Lanna-inspired
## magic school built from code (original design, no real temple copied):
## lantern gate -> garden courtyard -> red-carpet colonnade -> main hall (the
## Jade Naga's arena) -> sanctum sealed by jade until the guardian falls.
## Open-roofed so the top-down camera can follow the fight. Walls register
## box colliders with the world. See design/gdd/special-locations.md.
##
## Example: var info := SchoolTemple.build(world, center, facing)

const Art = preload("res://src/core/art.gd")
const Models = preload("res://src/core/models.gd")
const Lanna = preload("res://src/core/lanna.gd")
const Fx = preload("res://src/core/fx.gd")

const PLASTER := Color(0.9, 0.86, 0.78)
const LACQUER := Color(0.62, 0.12, 0.1)
const GOLD := Color(0.95, 0.75, 0.3)
const TILE := Color(0.78, 0.32, 0.16)
const TEAK := Color(0.42, 0.24, 0.13)
const CARPET := Color(0.6, 0.07, 0.1)
const STONE := Color(0.74, 0.68, 0.56)
const WALL_H := 2.6


## Builds the temple at `center` with its gate facing `facing` (radians, the
## local +Z axis). Returns world positions: arena, sleep, reward, gate, loot
## spots, and the seal node (hide it to open the sanctum).
static func build(w, center: Vector3, facing: float) -> Dictionary:
	var root := Node3D.new()
	root.name = "SchoolTemple"
	root.position = center
	root.rotation.y = facing
	w.decor_root.add_child(root)
	var to_w := func(x: float, z: float) -> Vector3: return root.transform * Vector3(x, 0, z)

	# floors and carpets (thin, so feet stay on them)
	_slab(root, Vector3(4.0, 0.06, 10.0), STONE, Vector3(0, 0.0, 13.0))
	_slab(root, Vector3(7.0, 0.06, 8.0), TEAK, Vector3(0, 0.0, 4.0))
	_slab(root, Vector3(18.0, 0.06, 14.0), TEAK, Vector3(0, 0.0, -7.0))
	_slab(root, Vector3(8.0, 0.06, 6.0), STONE.lightened(0.15), Vector3(0, 0.0, -17.0))
	_slab(root, Vector3(2.2, 0.04, 8.0), CARPET, Vector3(0, 0.05, 4.0))
	_slab(root, Vector3(2.2, 0.04, 13.0), CARPET, Vector3(0, 0.05, -6.5))
	_slab(root, Vector3(12.0, 0.04, 2.2), CARPET, Vector3(0, 0.05, -7.0))
	_slab(root, Vector3(9.0, 0.03, 9.0), GOLD.darkened(0.35), Vector3(0, 0.035, -7.0))  # arena medallion

	# outer walls (front wall has the gate gap)
	_wall(w, root, Vector3(-9, 0, -1), 38.0, true)
	_wall(w, root, Vector3(9, 0, -1), 38.0, true)
	_wall(w, root, Vector3(0, 0, -20), 18.6, false)
	for sx in [-5.5, 5.5]:
		_wall(w, root, Vector3(sx, 0, 18), 7.0, false)
		_wall(w, root, Vector3(sx * 1.14, 0, 8), 5.5, false)      # courtyard | colonnade
		_wall(w, root, Vector3(sx * 1.14, 0, 0), 5.5, false)      # colonnade | hall
		_wall(w, root, Vector3(sx * 0.96, 0, -14), 7.4, false)    # hall | sanctum
		_wall(w, root, Vector3(sx * 0.64, 0, 4), 8.0, true, 1.1)  # colonnade balustrades

	# lantern gate: lacquered pillars, gilded lintel, tiled gable
	for gx in [-2.3, 2.3]:
		_box(root, Vector3(0.8, 4.2, 0.8), LACQUER, Vector3(gx, 2.1, 18))
		_box(root, Vector3(1.0, 0.2, 1.0), GOLD, Vector3(gx, 4.3, 18))
		w.add_solid_box(to_w.call(gx, 18.0), Vector2(0.45, 0.45), facing)
	_box(root, Vector3(5.8, 0.5, 1.1), GOLD, Vector3(0, 4.55, 18))
	_gable(root, Vector3(0, 4.8, 18), 6.4, 1.8, 1.3)
	for k in range(3):  # entry steps
		_slab(root, Vector3(4.4 - k * 0.4, 0.12 + k * 0.08, 0.6), STONE.darkened(0.1), Vector3(0, 0.06, 20.2 - k * 0.6))
	for lx in [-4.0, 4.0]:
		var post := Lanna.lantern_post(root, Vector3(lx, 0, 20.5))
		if post != null:
			post.get_parent().rotation.y = PI if lx > 0.0 else 0.0
		w.add_solid_box(to_w.call(lx, 20.5), Vector2(0.3, 0.3), facing)

	# garden courtyard: flower beds and bamboo in the corners
	for bx in [-5.5, 5.5]:
		_slab(root, Vector3(3.4, 0.25, 6.0), Color(0.36, 0.26, 0.16), Vector3(bx, 0.12, 13.0))
		for i in range(5):
			Models.spawn_variant(root, "meadow", Vector3(bx + randf_range(-1.2, 1.2), 0.25, 13.0 + randf_range(-2.4, 2.4)), randf_range(0.8, 1.1))
		Lanna.bamboo(root, Vector3(bx * 1.35, 0, 16.6), 5)
		w.add_solid_box(to_w.call(bx * 1.35, 16.6), Vector2(0.9, 0.9), facing)

	# colonnade: lacquered pillars with gold capitals, hanging paper lanterns
	for z in [1.2, 3.8, 6.4]:
		for cx in [-2.6, 2.6]:
			_box(root, Vector3(0.5, 3.4, 0.5), LACQUER, Vector3(cx, 1.7, z))
			_box(root, Vector3(0.7, 0.25, 0.7), GOLD, Vector3(cx, 3.5, z))
			Art.add_mesh(root, Art.cylinder(0.22, 0.22, 0.45), Art.emissive(Lanna.LANTERN, Lanna.LANTERN * 1.3), Vector3(cx * 0.55, 2.9, z))
			w.add_solid_box(to_w.call(cx, z), Vector2(0.3, 0.3), facing)
	Art.add_light(root, Color(1.0, 0.65, 0.35), 8.0, 1.2, Vector3(0, 3.0, 4.0))

	# main hall: four great pillars, dais, small corner chedis, warm light
	for hp in [Vector2(-6, -3), Vector2(6, -3), Vector2(-6, -11), Vector2(6, -11)]:
		_box(root, Vector3(1.0, 4.6, 1.0), LACQUER, Vector3(hp.x, 2.3, hp.y))
		_box(root, Vector3(1.3, 0.3, 1.3), GOLD, Vector3(hp.x, 4.7, hp.y))
		_box(root, Vector3(1.3, 0.3, 1.3), GOLD, Vector3(hp.x, 0.15, hp.y))
		w.add_solid_box(to_w.call(hp.x, hp.y), Vector2(0.6, 0.6), facing)
	_slab(root, Vector3(6.0, 0.3, 2.4), TEAK.darkened(0.2), Vector3(0, 0.15, -12.3))
	for cx2 in [-7.6, 7.6]:
		Lanna.chedi(root, Vector3(cx2, 0, -12.6), 0.3, false)
		w.add_solid_box(to_w.call(cx2, -12.6), Vector2(1.0, 1.0), facing)
	for lx2 in [-4.5, 4.5]:
		Art.add_light(root, Color(1.0, 0.7, 0.4), 9.0, 1.1, Vector3(lx2, 3.6, -7.0))
	_gable(root, Vector3(0, WALL_H, -20), 14.0, 3.2, 1.0)  # the hall's great back gable

	# jade seal over the sanctum door (solid until the guardian falls)
	var seal := Node3D.new()
	seal.name = "JadeSeal"
	seal.position = Vector3(0, 0, -14)
	root.add_child(seal)
	var jade := Art.emissive(Color(0.3, 0.95, 0.55), Color(0.15, 0.7, 0.35))
	jade.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	jade.albedo_color.a = 0.6
	Art.add_mesh(seal, Art.box(Vector3(3.2, 3.0, 0.3)), jade, Vector3(0, 1.5, 0))
	Fx.motes(seal, Vector3(0, 1.5, 0), Color(0.4, 1.0, 0.6), 1.6, 18)
	w.add_solid_box(to_w.call(0.0, -14.0), Vector2(1.7, 0.3), facing, seal)

	# sanctum: a gilded plinth that will hold the reward
	_box(root, Vector3(1.4, 1.0, 1.4), PLASTER, Vector3(0, 0.5, -18.6))
	_box(root, Vector3(1.6, 0.15, 1.6), GOLD, Vector3(0, 1.05, -18.6))
	w.add_solid_box(to_w.call(0.0, -18.6), Vector2(0.8, 0.8), facing)
	Art.add_light(root, Color(1.0, 0.85, 0.5), 6.0, 1.3, Vector3(0, 3.0, -17.0))

	var loot := []
	for lp in [Vector2(-5.2, 10.5), Vector2(5.2, 10.5), Vector2(-5.6, 15.4), Vector2(5.6, 15.4),
			Vector2(-1.4, 2.4), Vector2(1.4, 5.6), Vector2(-7.5, -1.5), Vector2(7.5, -1.5), Vector2(-3.0, -18.0)]:
		loot.append(to_w.call(lp.x, lp.y))
	return {"root": root, "arena": to_w.call(0.0, -7.0), "sleep": to_w.call(0.0, -10.5),
		"reward": to_w.call(0.0, -16.6), "gate": to_w.call(0.0, 22.0), "seal": seal, "loot": loot}


static func _box(root: Node3D, size: Vector3, c: Color, pos: Vector3) -> MeshInstance3D:
	return Art.add_mesh(root, Art.box(size), Art.mat(c), pos)


static func _slab(root: Node3D, size: Vector3, c: Color, pos: Vector3) -> void:
	var mi := _box(root, size, c, pos)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## A plastered wall with a lacquer band and a gold cap; registers its collider.
## `along_z` = runs along local Z (side walls), else along X.
static func _wall(w, root: Node3D, pos: Vector3, length: float, along_z: bool, h := WALL_H) -> void:
	var size := Vector3(0.6, h, length) if along_z else Vector3(length, h, 0.6)
	_box(root, size, PLASTER, pos + Vector3(0, h * 0.5, 0))
	var band := size
	band.y = 0.25
	band.x += 0.04
	band.z += 0.04
	_box(root, band, LACQUER, pos + Vector3(0, h - 0.45, 0))
	var cap := size
	cap.y = 0.12
	cap.x += 0.15
	cap.z += 0.15
	_box(root, cap, GOLD, pos + Vector3(0, h + 0.06, 0))
	var half := Vector2(size.x * 0.5, size.z * 0.5)
	w.add_solid_box(root.transform * pos, half, root.rotation.y)


## A steep Lanna-style tiled gable with a gilded ridge.
static func _gable(root: Node3D, pos: Vector3, width: float, height: float, depth: float) -> void:
	var prism := PrismMesh.new()
	prism.size = Vector3(width, height, depth)
	Art.add_mesh(root, prism, Art.mat(TILE), pos + Vector3(0, height * 0.5, 0))
	for side in [-1.0, 1.0]:
		var finial := Art.add_mesh(root, Art.cylinder(0.02, 0.1, 0.9), Art.emissive(GOLD, GOLD * 0.4), pos + Vector3(side * width * 0.5, 0.45, 0))
		finial.rotation.z = -side * 0.5
