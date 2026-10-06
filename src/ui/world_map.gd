extends CanvasLayer
## World map (M): the real generated island, fog of war over unexplored
## cells, discovered landmarks, the apprentice's structures, the base and
## personal pins, and the apprentice's position + facing. Mouse wheel zooms,
## dragging pans, C recentres, left click toggles a pin, right click on a
## structure makes it the base. Reads the world; changes go through it.

const Cfg = preload("res://src/core/config.gd")
const TITLE_FONT_PATH := "res://assets/fonts/Cinzel.ttf"
const GOLD := Color(0.85, 0.7, 0.4)
const STRUCT_COLORS := {"campfire": Color(1.0, 0.55, 0.2), "altar": Color(0.7, 0.5, 1.0),
	"cauldron": Color(0.3, 0.9, 0.45), "ward": Color(0.8, 0.8, 1.0), "cabin": Color(0.95, 0.8, 0.5)}

var world = null
var canvas: Control
var zoom := 1.0             # 1 = whole island fits
var pan := Vector2.ZERO     # world XZ at the canvas centre
var map_tex: Texture2D
var fog_tex: ImageTexture
var _fog_rev := -1
var _drag_from := Vector2.ZERO
var _dragging := false
var _pressed := false
var font: Font


func _ready() -> void:
	font = load(TITLE_FONT_PATH) if ResourceLoader.exists(TITLE_FONT_PATH) else ThemeDB.fallback_font
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.03, 0.02, 0.06, 0.88)
	add_child(dim)
	var title := Label.new()
	title.text = "Mapa da Ilha"
	title.position = Vector2(0, 8)
	title.size = Vector2(1280, 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", font)
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", GOLD)
	add_child(title)
	var help := Label.new()
	help.text = "Roda: zoom · arrastar: mover · C: centralizar · clique: marcador · botão direito numa construção: definir base · M / Esc: fechar"
	help.position = Vector2(0, 690)
	help.size = Vector2(1280, 24)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.add_theme_color_override("font_color", Color(0.85, 0.82, 0.75))
	help.add_theme_font_size_override("font_size", 13)
	add_child(help)
	canvas = Control.new()
	canvas.position = Vector2(140, 50)
	canvas.size = Vector2(1000, 630)
	canvas.clip_contents = true
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.draw.connect(_draw_map)
	canvas.gui_input.connect(_on_input)
	add_child(canvas)


func open() -> void:
	visible = true
	if map_tex == null:
		map_tex = ImageTexture.create_from_image(world.terrain.build_map_image(256))
	if world.local_player != null:
		pan = Vector2(world.local_player.position.x, world.local_player.position.z)
	zoom = 1.6
	_refresh_fog()
	canvas.queue_redraw()


func close() -> void:
	visible = false


## A new island: the picture must be rebuilt on the next open.
func invalidate() -> void:
	map_tex = null


func _process(_delta: float) -> void:
	if visible:
		_refresh_fog()
		canvas.queue_redraw()


func _refresh_fog() -> void:
	var ex = world.exploration
	if ex == null or ex.revision == _fog_rev:
		return
	_fog_rev = ex.revision
	var img := Image.create(ex.size, ex.size, false, Image.FORMAT_RGBA8)
	for z in range(ex.size):
		for x in range(ex.size):
			img.set_pixel(x, z, Color(0.07, 0.05, 0.1, 0.0 if ex.cells[z * ex.size + x] > 0 else 1.0))
	fog_tex = ImageTexture.create_from_image(img)


# ---------- coordinates ----------

func _scale() -> float:  # canvas pixels per world metre
	return minf(canvas.size.x, canvas.size.y) / (Cfg.WORLD * 2.0) * zoom


func to_screen(x: float, z: float) -> Vector2:
	return canvas.size * 0.5 + (Vector2(x, z) - pan) * _scale()


func to_world(p: Vector2) -> Vector3:
	var w := pan + (p - canvas.size * 0.5) / _scale()
	return Vector3(w.x, 0, w.y)


# ---------- drawing ----------

func _draw_map() -> void:
	if world == null or map_tex == null:
		return
	var half: float = Cfg.WORLD
	var tl := to_screen(-half, -half)
	var rect := Rect2(tl, Vector2(half * 2.0, half * 2.0) * _scale())
	canvas.draw_rect(Rect2(Vector2.ZERO, canvas.size), Color(0.07, 0.05, 0.1))
	canvas.draw_texture_rect(map_tex, rect, false)
	if fog_tex != null:
		canvas.draw_texture_rect(fog_tex, rect, false)
	canvas.draw_rect(rect, Color(GOLD.r, GOLD.g, GOLD.b, 0.6), false, 2.0)
	var ex = world.exploration
	# discovered landmarks
	for poi in world.map_landmarks():
		var wp: Vector3 = poi.pos
		if ex.is_discovered(wp):
			var sp := to_screen(wp.x, wp.z)
			var status: String = poi.get("status", "")
			if status != "":  # special location: white ring = explored, gold + check = cleared
				var done := status == "cleared"
				canvas.draw_circle(sp, 9.0, GOLD if done else Color(1, 1, 1, 0.95))
				canvas.draw_circle(sp, 6.5, poi.color)
				canvas.draw_string(font, sp + Vector2(12, 5), poi.name + ("  ✓ concluído" if done else "  · explorado"), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, GOLD if done else Color(1, 0.95, 0.85))
				continue
			canvas.draw_circle(sp, 5.0, Color(1, 1, 1, 0.9))
			canvas.draw_circle(sp, 3.5, poi.color)
			canvas.draw_string(font, sp + Vector2(8, 4), poi.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 0.95, 0.85))
	# the apprentice's structures (only where explored)
	for st in world._children(world.structures_root):
		if not ex.is_discovered(st.position):
			continue
		var sp2 := to_screen(st.position.x, st.position.z)
		canvas.draw_rect(Rect2(sp2 - Vector2(4, 4), Vector2(8, 8)), STRUCT_COLORS.get(st.kind, Color.WHITE))
		canvas.draw_rect(Rect2(sp2 - Vector2(4, 4), Vector2(8, 8)), Color(0, 0, 0, 0.8), false, 1.0)
	# base
	if not ex.base.is_empty():
		var bp := to_screen(float(ex.base.pos[0]), float(ex.base.pos[1]))
		var star := PackedVector2Array()
		for k in range(10):
			var r := 11.0 if k % 2 == 0 else 5.0
			var a := -PI / 2.0 + k * PI / 5.0
			star.append(bp + Vector2(cos(a), sin(a)) * r)
		canvas.draw_colored_polygon(star, GOLD)
		canvas.draw_string(font, bp + Vector2(12, 4), "Base", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, GOLD)
	# personal pins
	for m in ex.markers:
		var mp := to_screen(float(m[0]), float(m[1]))
		canvas.draw_line(mp, mp + Vector2(0, -12), Color(0.2, 0.1, 0.1), 2.0)
		canvas.draw_circle(mp + Vector2(0, -14), 4.5, Color(0.95, 0.25, 0.3))
	# the apprentice: position + facing
	var p = world.local_player
	if p != null:
		var pp := to_screen(p.position.x, p.position.z)
		var yaw: float = p.model.rotation.y if p.model != null else 0.0
		var fwd := Vector2(sin(yaw), cos(yaw))
		var side := Vector2(-fwd.y, fwd.x)
		var tri := PackedVector2Array([pp + fwd * 11.0, pp - fwd * 7.0 + side * 6.0, pp - fwd * 4.0, pp - fwd * 7.0 - side * 6.0])
		canvas.draw_colored_polygon(tri, Color(0.45, 0.85, 1.0))
		canvas.draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[3], tri[0]]), Color(0, 0, 0, 0.9), 1.5)
	canvas.draw_string(font, Vector2(10, canvas.size.y - 10), "Explorado: %d%%" % int(ex.discovered_ratio() * 100.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, GOLD)


# ---------- input ----------

func _on_input(ev: InputEvent) -> void:
	var mb := ev as InputEventMouseButton
	if mb != null:
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(mb.position, 1.15)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(mb.position, 1.0 / 1.15)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_pressed = true
				_dragging = false
				_drag_from = mb.position
			else:
				if _pressed and not _dragging:
					world.map_toggle_marker(to_world(mb.position))
				_pressed = false
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			world.map_set_base(to_world(mb.position))
		canvas.queue_redraw()
		return
	var mm := ev as InputEventMouseMotion
	if mm != null and _pressed:
		if mm.position.distance_to(_drag_from) > 4.0:
			_dragging = true
		if _dragging:
			pan -= mm.relative / _scale()
			canvas.queue_redraw()


func _zoom_at(at: Vector2, factor: float) -> void:
	var before := to_world(at)
	zoom = clampf(zoom * factor, 0.8, 8.0)
	var after := to_world(at)
	pan += Vector2(before.x - after.x, before.z - after.z)


func center_on_player() -> void:
	if world.local_player != null:
		pan = Vector2(world.local_player.position.x, world.local_player.position.z)
		canvas.queue_redraw()
