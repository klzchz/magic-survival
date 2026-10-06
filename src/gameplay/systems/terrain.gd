extends Node3D
## The island's ground: rolling relief from noise, lakes carved as basins,
## flat clearings at the spawn and the ruins, raised forest rim at the edge.
## Builds the ground mesh (vertex-coloured biomes), lake water, wind-swept
## grass, shore plants and the forest wall. Everything that stands on the
## island asks height_at(); movement asks is_walkable().
## Tuning: assets/data/terrain.json. Implements design/gdd/survival-loop-mvp.md.
##
## Example: `pos.y = terrain.height_at(pos.x, pos.z)`

const Cfg = preload("res://src/core/config.gd")
const Models = preload("res://src/core/models.gd")
const CONFIG_PATH := "res://assets/data/terrain.json"
const GROUND_SHADER := preload("res://assets/shaders/ground.gdshader")
const WATER_SHADER := preload("res://assets/shaders/water.gdshader")
const GRASS_SHADER := preload("res://assets/shaders/grass.gdshader")

const GRASS_GREEN := Color(0.24, 0.40, 0.15)
const GRASS_DRY := Color(0.46, 0.40, 0.18)
const MUD := Color(0.30, 0.24, 0.16)
const SAND := Color(0.55, 0.48, 0.32)
const ROCK := Color(0.36, 0.35, 0.36)

var cfg := {}
var water_level := -0.6
var lakes: Array = []        # [{center: Vector2, radius, depth}]
var clearings: Array = []    # [{center: Vector2, radius}] kept flat at height 0
var _relief := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _tint := FastNoiseLite.new()
var _built: Node3D


func _ready() -> void:
	var f := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if f != null:
		var parsed = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary:
			cfg = parsed
	water_level = float(cfg.get("water_level", -0.6))


func _c(key: String, default: float) -> float:
	return float(cfg.get(key, default))


## New island: reseeds the noise, places lakes away from the given clearings
## (spawn, ruins) and rebuilds every mesh.
func generate(clearing_list: Array) -> void:
	clearings = clearing_list
	_relief.seed = randi()
	_relief.frequency = _c("frequency", 0.022)
	_relief.fractal_octaves = 3
	_detail.seed = randi()
	_detail.frequency = _c("detail_frequency", 0.09)
	_tint.seed = randi()
	_tint.frequency = 0.04
	lakes.clear()
	var radius_range: Array = cfg.get("lake_radius", [7.0, 12.0])
	var tries := 0
	while lakes.size() < int(_c("lakes", 4)) and tries < 200:
		tries += 1
		var r := randf_range(float(radius_range[0]), float(radius_range[1]))
		var c := Vector2(randf_range(-Cfg.WORLD + r + 4, Cfg.WORLD - r - 4), randf_range(-Cfg.WORLD + r + 4, Cfg.WORLD - r - 4))
		var ok := true
		for cl in clearings:
			if c.distance_to(cl.center) < cl.radius + r + 8.0:
				ok = false
		for l in lakes:
			if c.distance_to(l.center) < l.radius + r + 6.0:
				ok = false
		if ok:
			lakes.append({"center": c, "radius": r, "depth": _c("lake_depth", 2.6)})
	_rebuild()


## Ground height at a world XZ point (analytic, cheap: safe to call per frame).
func height_at(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var h := _relief.get_noise_2d(x, z) * _c("amplitude", 3.2) + _detail.get_noise_2d(x, z) * _c("detail_amplitude", 0.5)
	for cl in clearings:  # flat clearings blend smoothly into the relief
		var d: float = p.distance_to(cl.center)
		h = lerpf(0.0, h, smoothstep(cl.radius, cl.radius + 9.0, d))
	for l in lakes:
		var d2: float = p.distance_to(l.center)
		var edge_noise := _detail.get_noise_2d(x * 2.0, z * 2.0) * 1.5
		var t := smoothstep(l.radius * 0.45, l.radius + edge_noise, d2)
		h = lerpf(-float(l.depth), h, t)
	var out := maxf(absf(x), absf(z)) - Cfg.WORLD
	if out > 0.0:  # the island rises into the forest rim
		h += out * _c("border_rise", 0.45)
	return h


func is_water(x: float, z: float) -> bool:
	return height_at(x, z) < water_level


## Apprentices can wade the shallow edge but not cross a lake.
func is_walkable(x: float, z: float) -> bool:
	return height_at(x, z) > water_level - _c("wade_depth", 0.25)


## Random dry point inside the playable square (y = ground height).
func random_land_pos(margin := 3.0) -> Vector3:
	for _i in range(40):
		var x := randf_range(-Cfg.WORLD + margin, Cfg.WORLD - margin)
		var z := randf_range(-Cfg.WORLD + margin, Cfg.WORLD - margin)
		var h := height_at(x, z)
		if h > water_level + 0.25:
			return Vector3(x, h, z)
	return Vector3(0, height_at(0, 0), 0)


func on_ground(p: Vector3) -> Vector3:
	return Vector3(p.x, height_at(p.x, p.z), p.z)


# ---------- meshes ----------

func _rebuild() -> void:
	if _built != null:
		remove_child(_built)
		_built.queue_free()
	_built = Node3D.new()
	add_child(_built)
	_build_ground()
	_build_water()
	_build_grass()
	_build_shores()
	_build_forest_wall()


func _ground_color(x: float, z: float, h: float, slope: float) -> Color:
	var t := _tint.get_noise_2d(x, z) * 0.5 + 0.5
	var c := GRASS_GREEN.lerp(GRASS_DRY, smoothstep(0.45, 0.85, t))
	c = c.lerp(GRASS_GREEN.darkened(0.25), smoothstep(1.5, 3.5, h) * 0.5)   # darker moss on the hills
	var shore := 1.0 - smoothstep(water_level + 0.05, water_level + 0.7, h)
	c = c.lerp(SAND if t > 0.5 else MUD, shore)
	c = c.lerp(MUD.darkened(0.3), 1.0 - smoothstep(water_level - 1.2, water_level, h))  # lake bed
	return c.lerp(ROCK, smoothstep(0.55, 0.9, slope))


func _build_ground() -> void:
	var step := _c("grid_step", 1.0)
	var extent := Cfg.WORLD + 32.0
	var n := int(extent * 2.0 / step)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	verts.resize((n + 1) * (n + 1))
	normals.resize(verts.size())
	colors.resize(verts.size())
	for iz in range(n + 1):
		for ix in range(n + 1):
			var x := -extent + ix * step
			var z := -extent + iz * step
			var h := height_at(x, z)
			var dx := height_at(x + 0.5, z) - height_at(x - 0.5, z)
			var dz := height_at(x, z + 0.5) - height_at(x, z - 0.5)
			var nrm := Vector3(-dx, 1.0, -dz).normalized()
			var i := iz * (n + 1) + ix
			verts[i] = Vector3(x, h, z)
			normals[i] = nrm
			colors[i] = _ground_color(x, z, h, 1.0 - nrm.y)
	for iz in range(n):
		for ix in range(n):
			var a := iz * (n + 1) + ix
			var b := a + 1
			var c := a + (n + 1)
			var d := c + 1
			indices.append_array([a, b, c, b, d, c])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := ShaderMaterial.new()
	mat.shader = GROUND_SHADER
	mat.set_shader_parameter("detail", _noise_texture(0.06))
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.name = "Ground"
	_built.add_child(mi)


func _noise_texture(freq: float) -> NoiseTexture2D:
	var nz := FastNoiseLite.new()
	nz.frequency = freq
	nz.seed = randi()
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.noise = nz
	return tex


func _build_water() -> void:
	if lakes.is_empty():
		return
	var plane := PlaneMesh.new()
	plane.size = Vector2(Cfg.WORLD * 2.0, Cfg.WORLD * 2.0)
	var mat := ShaderMaterial.new()
	mat.shader = WATER_SHADER
	mat.set_shader_parameter("ripples", _noise_texture(0.05))
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.material_override = mat
	mi.position.y = water_level
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.name = "Water"
	_built.add_child(mi)


func water_material() -> ShaderMaterial:
	var w := _built.get_node_or_null("Water") if _built != null else null
	return w.material_override if w != null else null


## A thin tapered blade, UV.y = 0 at the root and 1 at the tip (wind uses it).
func _blade_mesh() -> ArrayMesh:
	var v := PackedVector3Array([Vector3(-0.05, 0, 0), Vector3(0.05, 0, 0), Vector3(-0.025, 0.35, 0.01),
		Vector3(0.025, 0.35, 0.01), Vector3(0.0, 0.7, 0.03)])
	var uv := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(0, 0.5), Vector2(1, 0.5), Vector2(0.5, 1)])
	var nrm := PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_NORMAL] = nrm
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 2, 1, 1, 2, 3, 2, 4, 3])
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


func _build_grass() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = GRASS_SHADER
	var blade := _blade_mesh()
	blade.surface_set_material(0, mat)
	var count := int(_c("grass_blades", 9000))
	var xforms: Array = []
	var cols: Array = []
	var tries := 0
	while xforms.size() < count and tries < count * 3:
		tries += 1
		# clumps: pick a centre, scatter a few blades around it
		var cx := randf_range(-Cfg.WORLD, Cfg.WORLD)
		var cz := randf_range(-Cfg.WORLD, Cfg.WORLD)
		var dry := _tint.get_noise_2d(cx, cz) * 0.5 + 0.5
		for k in range(6):
			var x := cx + randf_range(-0.6, 0.6)
			var z := cz + randf_range(-0.6, 0.6)
			var h := height_at(x, z)
			if h < water_level + 0.15:
				continue
			var b := Basis(Vector3.UP, randf() * TAU).scaled(Vector3.ONE * randf_range(0.7, 1.5))
			xforms.append(Transform3D(b, Vector3(x, h - 0.02, z)))
			cols.append(Color(0.36, 0.56, 0.2).lerp(Color(0.68, 0.6, 0.26), clampf(dry + randf_range(-0.2, 0.2), 0.0, 1.0)))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = blade
	mm.instance_count = xforms.size()
	for i in range(xforms.size()):
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, cols[i])
	var grass := MultiMeshInstance3D.new()
	grass.multimesh = mm
	grass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	grass.name = "Grass"
	_built.add_child(grass)


## Lily pads on the water, reeds and plants along the shore.
func _build_shores() -> void:
	for l in lakes:
		var c: Vector2 = l.center
		var r: float = l.radius
		for i in range(int(r * 0.8)):
			var a := randf() * TAU
			var d := randf_range(0.2, 0.75) * r
			var pad := Models.spawn(_built, ["waterlily_A", "waterlily_B"].pick_random(), Vector3(c.x + cos(a) * d, water_level + 0.02, c.y + sin(a) * d), randf_range(3.0, 4.5))
			if pad != null:
				pad.rotation.y = randf() * TAU
		for i in range(int(r * 1.6)):
			var a2 := randf() * TAU
			var x := c.x + cos(a2) * (r + randf_range(-0.5, 1.5))
			var z := c.y + sin(a2) * (r + randf_range(-0.5, 1.5))
			var plant := Models.spawn(_built, ["waterplant_A", "waterplant_B", "waterplant_C"].pick_random(), Vector3(x, height_at(x, z), z), randf_range(3.0, 4.5))
			if plant != null:
				plant.rotation.y = randf() * TAU


func _build_forest_wall() -> void:
	var edge := Cfg.WORLD + 4.0
	for ring in [[edge, 6.0, 1.1, 1.5], [edge + 8.0, 8.0, 1.3, 1.8], [edge + 16.0, 9.0, 1.5, 2.0]]:
		var e: float = ring[0]
		var t := -e
		while t <= e:
			for side in [Vector3(t, 0, -e), Vector3(t, 0, e), Vector3(-e, 0, t), Vector3(e, 0, t)]:
				var p: Vector3 = side + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))
				p.y = height_at(p.x, p.z)
				Models.spawn_variant(_built, "border_tree", p, randf_range(ring[2], ring[3]))
			t += ring[1]
