extends Node
## Renders item / recipe icons from their 3D look (ItemArt) into tiny offscreen
## SubViewports, once each, and caches the textures. Zero image files needed.
##
## Example: `slot_icon.texture = icons.get_icon("axe_1handed")`

const ItemArt = preload("res://src/core/item_art.gd")
const SIZE := 96

var _cache := {}


func get_icon(key: String) -> Texture2D:
	if _cache.has(key):
		return _cache[key]
	var vp := SubViewport.new()
	vp.size = Vector2i(SIZE, SIZE)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(vp)
	var stage := Node3D.new()
	vp.add_child(stage)
	var art := ItemArt.build(stage, key)
	art.rotation = Vector3(0.0, -0.7, 0.0)
	var box := _bounds(art)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -30, 0)
	sun.light_energy = 1.3
	stage.add_child(sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.78, 0.9)
	env.ambient_light_energy = 0.9
	var we := WorldEnvironment.new()
	we.environment = env
	stage.add_child(we)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	var radius := maxf(box.size.length() * 0.5, 0.1)
	cam.size = radius * 2.1
	stage.add_child(cam)
	var center := box.get_center()
	cam.position = center + Vector3(0, radius * 0.9, radius * 2.5)
	cam.look_at(center, Vector3.UP)
	cam.current = true
	var tex := vp.get_texture()
	_cache[key] = tex
	return tex


func _bounds(n: Node) -> AABB:
	var acc := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var b: AABB = _global_xf(m, n) * m.mesh.get_aabb()
		acc = b if first else acc.merge(b)
		first = false
	return acc


func _global_xf(m: Node3D, root: Node) -> Transform3D:
	var xf := m.transform
	var p := m.get_parent()
	while p != null and p != root.get_parent():
		if p is Node3D:
			xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf
