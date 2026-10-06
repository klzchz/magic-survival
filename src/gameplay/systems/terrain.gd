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

const GRASS_GREEN := Color(0.30, 0.52, 0.18)
const GRASS_DRY := Color(0.52, 0.55, 0.22)
const MUD := Color(0.36, 0.27, 0.17)
const SAND := Color(0.62, 0.52, 0.34)
const ROCK := Color(0.42, 0.42, 0.40)
const TRAIL := Color(0.55, 0.42, 0.27)
# gothic: dark moss, slate, ash · desert: warm sand, darker ripples, sandstone
const GOTH_MOSS := Color(0.16, 0.21, 0.15)
const GOTH_SLATE := Color(0.24, 0.24, 0.27)
const COBBLE := Color(0.33, 0.32, 0.34)
const DUNE := Color(0.74, 0.58, 0.36)
const SAND_DARK := Color(0.56, 0.4, 0.25)
const SANDSTONE := Color(0.7, 0.5, 0.36)
const BIOMES := ["flowered", "gothic", "desert"]

var cfg := {}
var water_level := -0.6
var lakes: Array = []        # [{center: Vector2, radius, depth}]
var clearings: Array = []    # [{center: Vector2, radius}] kept flat at height 0
var paths: Array = []        # polylines (Array[Vector2]): trails painted and smoothed
var _relief := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _tint := FastNoiseLite.new()
var _warp := FastNoiseLite.new()
var _dune := FastNoiseLite.new()
var biome_seeds := {}         # biome id -> Vector2 centre (from terrain.json)
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
func generate(clearing_list: Array, path_list: Array = []) -> void:
	clearings = clearing_list
	paths = path_list
	_relief.seed = randi()
	_relief.frequency = _c("frequency", 0.022)
	_relief.fractal_octaves = 3
	_detail.seed = randi()
	_detail.frequency = _c("detail_frequency", 0.09)
	_tint.seed = randi()
	_tint.frequency = 0.04
	_warp.seed = randi()
	_warp.frequency = 0.008
	_dune.seed = randi()
	_dune.frequency = 0.03
	biome_seeds.clear()
	var bs: Dictionary = cfg.get("biomes", {"flowered": [0, 60], "gothic": [-95, -88], "desert": [95, -88]})
	for id in bs:
		biome_seeds[id] = Vector2(float(bs[id][0]), float(bs[id][1]))
	lakes.clear()
	var radius_range: Array = cfg.get("lake_radius", [7.0, 12.0])
	# lakes in the flowered south, dark ponds among the gothic ruins, one oasis
	for spec in [["flowered", int(_c("lakes", 3)), radius_range, 2.6], ["gothic", int(_c("gothic_ponds", 2)), [6.0, 9.0], 2.2], ["desert", 1, [8.0, 8.0], 2.0]]:
		var made := 0
		var tries := 0
		while made < spec[1] and tries < 300:
			tries += 1
			var r := randf_range(float(spec[2][0]), float(spec[2][1]))
			var c := Vector2(randf_range(-Cfg.WORLD + r + 10, Cfg.WORLD - r - 10), randf_range(-Cfg.WORLD + r + 10, Cfg.WORLD - r - 10))
			if biome_at(c.x, c.y) != spec[0] or biome_mix(c.x, c.y)[BIOMES.find(spec[0])] < 0.95:
				continue
			var ok := true
			for path in paths:
				if path_distance(c, path) < r + 6.0:
					ok = false
			for cl in clearings:
				if c.distance_to(cl.center) < cl.radius + r + 8.0:
					ok = false
			for l in lakes:
				if c.distance_to(l.center) < l.radius + r + 10.0:
					ok = false
			if ok:
				lakes.append({"center": c, "radius": r, "depth": float(spec[3]), "biome": spec[0]})
				made += 1
	_rebuild()


## Biome weights at a point (x = flowered, y = gothic, z = desert), sum 1.
## Nearest-seed regions with noise-warped borders and a soft blend band.
func biome_mix(x: float, z: float) -> Vector3:
	if biome_seeds.is_empty():
		return Vector3(1, 0, 0)
	var w := _c("biome_warp", 20.0)
	var p := Vector2(x + _warp.get_noise_2d(x, z) * w, z + _warp.get_noise_2d(z + 300.0, x) * w)
	var d := Vector3(p.distance_to(biome_seeds.flowered), p.distance_to(biome_seeds.gothic), p.distance_to(biome_seeds.desert))
	var nearest := minf(d.x, minf(d.y, d.z))
	var blend := _c("biome_blend", 22.0)
	var wts := Vector3(1.0 - smoothstep(0.0, blend, d.x - nearest), 1.0 - smoothstep(0.0, blend, d.y - nearest), 1.0 - smoothstep(0.0, blend, d.z - nearest))
	return wts / maxf(wts.x + wts.y + wts.z, 0.0001)


func biome_at(x: float, z: float) -> String:
	var m := biome_mix(x, z)
	if m.y > m.x and m.y > m.z:
		return "gothic"
	if m.z > m.x and m.z > m.y:
		return "desert"
	return "flowered"


## Distance from a point to a polyline trail.
static func path_distance(p: Vector2, path: Array) -> float:
	var best := INF
	for i in range(path.size() - 1):
		var a: Vector2 = path[i]
		var b: Vector2 = path[i + 1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best


func on_trail(x: float, z: float, extra := 0.0) -> bool:
	for path in paths:
		if path_distance(Vector2(x, z), path) < _c("path_width", 2.2) + extra:
			return true
	return false


## Ground height at a world XZ point (analytic, cheap: safe to call per frame).
func height_at(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var m := biome_mix(x, z)
	var h_flower := _relief.get_noise_2d(x, z) * _c("amplitude", 3.2) + _detail.get_noise_2d(x, z) * _c("detail_amplitude", 0.5)
	var h_goth := _relief.get_noise_2d(x * 1.4, z * 1.4) * _c("gothic_amplitude", 3.4) + absf(_detail.get_noise_2d(x * 0.6, z * 0.6)) * 1.2
	# dunes: long ridges across the wind plus broad swells, never below the water
	var ridge := 1.0 - absf(sin((x * 0.06 + z * 0.025) + _dune.get_noise_2d(x, z) * 2.5))
	var h_desert := 0.6 + ridge * ridge * _c("desert_amplitude", 4.5) + _relief.get_noise_2d(x * 0.5, z * 0.5) * 2.0
	var h := h_flower * m.x + h_goth * m.y + h_desert * m.z
	for path in paths:  # trails smooth the relief so walking them feels easy
		var dp := path_distance(p, path)
		h *= lerpf(0.3, 1.0, smoothstep(2.0, 9.0, dp))
	for cl in clearings:  # flat clearings blend smoothly into the relief
		var d: float = p.distance_to(cl.center)
		h = lerpf(0.0, h, smoothstep(cl.radius, cl.radius + 9.0, d))
	for l in lakes:
		var d2: float = p.distance_to(l.center)
		var edge_noise := _detail.get_noise_2d(x * 2.0, z * 2.0) * 1.5
		var t := smoothstep(l.radius * 0.45, l.radius + edge_noise, d2)
		h = lerpf(water_level - float(l.depth) * 0.7, h, t)
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
	var m := biome_mix(x, z)
	var flower := _flower_color(x, z, h, slope, t)
	var goth := GOTH_MOSS.lerp(GOTH_SLATE, smoothstep(0.4, 0.8, t)).lerp(GOTH_SLATE.darkened(0.2), smoothstep(0.5, 0.9, slope))
	var ripple := sin(x * 0.9 + z * 0.35 + _detail.get_noise_2d(x, z) * 3.0) * 0.5 + 0.5
	var desert := DUNE.lerp(SAND_DARK, ripple * 0.45 + smoothstep(0.55, 0.85, t) * 0.35).lerp(SANDSTONE, smoothstep(0.5, 0.85, slope))
	var c := flower * m.x + goth * m.y + desert * m.z
	for path in paths:  # roads take the local material: earth, cobbles, packed sand
		var dp := path_distance(Vector2(x, z), path)
		var road := TRAIL.lerp(MUD, t * 0.4) * m.x + COBBLE.lerp(GOTH_SLATE, t * 0.5) * m.y + SAND_DARK * m.z
		c = c.lerp(road, 1.0 - smoothstep(_c("path_width", 2.2) * 0.55, _c("path_width", 2.2), dp))
	return c


func _flower_color(x: float, z: float, h: float, slope: float, t: float) -> Color:
	var c := GRASS_GREEN.lerp(GRASS_DRY, smoothstep(0.45, 0.85, t))
	c = c.lerp(GRASS_GREEN.darkened(0.25), smoothstep(1.5, 3.5, h) * 0.5)   # darker moss on the hills
	var shore := 1.0 - smoothstep(water_level + 0.05, water_level + 0.7, h)
	c = c.lerp(SAND if t > 0.5 else MUD, shore)
	c = c.lerp(MUD.darkened(0.3), 1.0 - smoothstep(water_level - 1.2, water_level, h))  # lake bed
	return c.lerp(ROCK, smoothstep(0.55, 0.9, slope))


func _build_ground() -> void:
	var step := _c("grid_step", 2.0)
	var extent := Cfg.WORLD + 40.0
	var n := int(extent * 2.0 / step)
	var heights := PackedFloat32Array()
	heights.resize((n + 1) * (n + 1))
	for iz in range(n + 1):
		for ix in range(n + 1):
			heights[iz * (n + 1) + ix] = height_at(-extent + ix * step, -extent + iz * step)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	verts.resize(heights.size())
	normals.resize(heights.size())
	colors.resize(heights.size())
	for iz in range(n + 1):
		for ix in range(n + 1):
			var i := iz * (n + 1) + ix
			var x := -extent + ix * step
			var z := -extent + iz * step
			var hl := heights[i - 1] if ix > 0 else heights[i]
			var hr := heights[i + 1] if ix < n else heights[i]
			var hd := heights[i - (n + 1)] if iz > 0 else heights[i]
			var hu := heights[i + (n + 1)] if iz < n else heights[i]
			var nrm := Vector3((hl - hr) / (2.0 * step), 1.0, (hd - hu) / (2.0 * step)).normalized()
			verts[i] = Vector3(x, heights[i], z)
			normals[i] = nrm
			colors[i] = _ground_color(x, z, heights[i], 1.0 - nrm.y)
	for iz in range(n):
		for ix in range(n):
			var a2 := iz * (n + 1) + ix
			var b2 := a2 + 1
			var c2 := a2 + (n + 1)
			var d2 := c2 + 1
			indices.append_array([a2, b2, c2, b2, d2, c2])
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
	if biome_seeds.has("gothic"):
		mat.set_shader_parameter("gloom_center", biome_seeds.gothic)
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


func _mesh_of(id: String) -> Mesh:
	var n := Models.spawn(self, id)
	if n == null:
		return null
	var mi := n.find_children("*", "MeshInstance3D", true, false)
	var mesh: Mesh = (mi[0] as MeshInstance3D).mesh if mi.size() > 0 else null
	remove_child(n)
	n.queue_free()
	return mesh


## Stylized grass tufts (MegaKit meshes) in clumps: dense in meadows, thin on
## trails and in the clearings, none in the water.
func _build_grass() -> void:
	for spec in [["qn_grass_short", int(_c("grass_short", 3200)), 0.45, 0.8], ["qn_grass_wispy", int(_c("grass_wispy", 900)), 0.35, 0.6]]:
		var mesh := _mesh_of(spec[0])
		if mesh == null:
			continue
		var xforms: Array = []
		var tries := 0
		while xforms.size() < spec[1] and tries < spec[1] * 4:
			tries += 1
			var cx := randf_range(-Cfg.WORLD, Cfg.WORLD)
			var cz := randf_range(-Cfg.WORLD, Cfg.WORLD)
			var dens := _tint.get_noise_2d(cx * 0.7, cz * 0.7) * 0.5 + 0.5
			var bm := biome_mix(cx, cz)
			var allowed := bm.x if spec[0] == "qn_grass_short" else bm.x * 0.6 + bm.y * 0.5
			if randf() > allowed or randf() > dens + 0.25 or on_trail(cx, cz, 0.3):
				continue
			for k in range(3):
				var x := cx + randf_range(-0.8, 0.8)
				var z := cz + randf_range(-0.8, 0.8)
				var h := height_at(x, z)
				if h < water_level + 0.15:
					continue
				var b := Basis(Vector3.UP, randf() * TAU).scaled(Vector3.ONE * randf_range(spec[2], spec[3]))
				xforms.append(Transform3D(b, Vector3(x, h - 0.02, z)))
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = xforms.size()
		for i in range(xforms.size()):
			mm.set_instance_transform(i, xforms[i])
		var grass := MultiMeshInstance3D.new()
		grass.multimesh = mm
		grass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		grass.name = "Grass" if spec[0] == "qn_grass_short" else "GrassWispy"
		_built.add_child(grass)


## Lily pads on the water, reeds and plants along the shore.
func _build_shores() -> void:
	for l in lakes:
		var c: Vector2 = l.center
		var r: float = l.radius
		if l.get("biome", "flowered") == "desert":
			for i in range(10):
				var ao := randf() * TAU
				var po := Vector3(c.x + cos(ao) * (r + randf_range(0.5, 3.0)), 0, c.y + sin(ao) * (r + randf_range(0.5, 3.0)))
				Models.spawn(_built, ["qn_plant_1", "qn_fern", "waterplant_B"].pick_random(), on_ground(po), randf_range(1.0, 1.6))
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
	var edge := Cfg.WORLD + 5.0
	for ring in [[edge, 9.0], [edge + 12.0, 14.0]]:
		var e: float = ring[0]
		var t := -e
		while t <= e:
			for side in [Vector3(t, 0, -e), Vector3(t, 0, e), Vector3(-e, 0, t), Vector3(e, 0, t)]:
				var p: Vector3 = side + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3))
				p.y = height_at(p.x, p.z)
				match biome_at(p.x, p.z):
					"gothic":
						Models.spawn(_built, ["dead_l", "dead_m", "qn_pine_3"].pick_random(), p, randf_range(1.3, 2.0))
					"desert":
						Models.spawn(_built, "qn_rock_" + str(randi_range(1, 3)), p, randf_range(2.0, 3.5))
					_:
						Models.spawn_variant(_built, "border_tree", p, randf_range(1.2, 1.7))
			t += ring[1]
