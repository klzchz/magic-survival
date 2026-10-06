extends Control
## Small vector icons for the HUD, drawn in code (no image files): every stat,
## state and spell gets a recognisable shape so nothing relies on colour alone.
##
## Example: var i := HudIcon.make("heart", 18.0, Color.RED); parent.add_child(i)

const KINDS := ["heart", "hunger", "mana", "noise", "wisp", "corruption", "sun", "dusk", "moon",
	"shield", "guard", "hush", "dark", "fire", "rest", "lock", "bolt", "lume", "escudo", "skull"]

var kind := "heart"
var tint := Color.WHITE


static func make(k: String, px: float, c: Color) -> Control:
	var i = load("res://src/ui/hud_icon.gd").new()
	i.kind = k
	i.tint = c
	i.custom_minimum_size = Vector2(px, px)
	i.size = Vector2(px, px)
	i.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return i


func set_kind(k: String, c: Color) -> void:
	if k == kind and c == tint:
		return
	kind = k
	tint = c
	queue_redraw()


func _draw() -> void:
	var s := minf(size.x, size.y)
	var c := size * 0.5
	var o := Color(0, 0, 0, 0.75)  # outline keeps shapes readable on any ground
	match kind:
		"heart":
			var r := s * 0.24
			var pts := PackedVector2Array([c + Vector2(-s * 0.46, -s * 0.06), c + Vector2(0, s * 0.42), c + Vector2(s * 0.46, -s * 0.06)])
			draw_circle(c + Vector2(-r * 0.95, -s * 0.12), r + 1.2, o)
			draw_circle(c + Vector2(r * 0.95, -s * 0.12), r + 1.2, o)
			draw_colored_polygon(pts, tint)
			draw_circle(c + Vector2(-r * 0.95, -s * 0.12), r, tint)
			draw_circle(c + Vector2(r * 0.95, -s * 0.12), r, tint)
		"hunger":  # a bowl with steam
			draw_arc(c + Vector2(0, -s * 0.02), s * 0.38, 0.0, PI, 16, o, 4.0)
			draw_arc(c + Vector2(0, -s * 0.02), s * 0.38, 0.0, PI, 16, tint, 2.5)
			draw_line(c + Vector2(-s * 0.42, -s * 0.02), c + Vector2(s * 0.42, -s * 0.02), tint, 2.5)
			for dx in [-0.14, 0.0, 0.14]:
				draw_line(c + Vector2(s * dx, -s * 0.16), c + Vector2(s * (dx + 0.05), -s * 0.4), tint, 1.5)
		"mana":  # a droplet
			var drop := PackedVector2Array([c + Vector2(0, -s * 0.45), c + Vector2(s * 0.28, s * 0.05), c + Vector2(-s * 0.28, s * 0.05)])
			draw_circle(c + Vector2(0, s * 0.12), s * 0.29 + 1.2, o)
			draw_colored_polygon(drop, tint)
			draw_circle(c + Vector2(0, s * 0.12), s * 0.29, tint)
			draw_circle(c + Vector2(-s * 0.09, s * 0.06), s * 0.07, Color(1, 1, 1, 0.6))
		"noise":  # a source with sound waves
			draw_circle(c + Vector2(-s * 0.28, 0), s * 0.12, tint)
			for k in range(3):
				draw_arc(c + Vector2(-s * 0.28, 0), s * (0.22 + k * 0.14), -0.8, 0.8, 10, tint, 2.0)
		"wisp", "fire":  # a flame
			var fl := PackedVector2Array([c + Vector2(0, -s * 0.46), c + Vector2(s * 0.3, s * 0.1), c + Vector2(0, s * 0.42), c + Vector2(-s * 0.3, s * 0.1)])
			draw_colored_polygon(fl, tint)
			draw_circle(c + Vector2(0, s * 0.14), s * 0.26, tint)
			draw_circle(c + Vector2(0, s * 0.18), s * 0.12, Color(1, 1, 0.8, 0.85))
		"corruption":  # an eye
			draw_arc(c, s * 0.42, PI * 1.15, PI * 1.85, 12, tint, 2.5)
			draw_arc(c, s * 0.42, PI * 0.15, PI * 0.85, 12, tint, 2.5)
			draw_circle(c, s * 0.15, tint)
		"sun":
			draw_circle(c, s * 0.22, tint)
			for k in range(8):
				var a := TAU * k / 8.0
				draw_line(c + Vector2(cos(a), sin(a)) * s * 0.3, c + Vector2(cos(a), sin(a)) * s * 0.46, tint, 2.0)
		"dusk":  # half sun on the horizon
			draw_arc(c + Vector2(0, s * 0.12), s * 0.26, PI, TAU, 14, tint, 3.0)
			draw_line(c + Vector2(-s * 0.46, s * 0.14), c + Vector2(s * 0.46, s * 0.14), tint, 2.0)
			for k in range(3):
				var a2 := PI + PI * (k + 1) / 4.0
				draw_line(c + Vector2(0, s * 0.12) + Vector2(cos(a2), sin(a2)) * s * 0.34, c + Vector2(0, s * 0.12) + Vector2(cos(a2), sin(a2)) * s * 0.46, tint, 2.0)
		"moon":
			draw_circle(c, s * 0.38, tint)
			draw_circle(c + Vector2(s * 0.16, -s * 0.1), s * 0.32, Color(0.07, 0.05, 0.12))
		"shield", "escudo", "guard":
			var sh := PackedVector2Array([c + Vector2(-s * 0.36, -s * 0.38), c + Vector2(s * 0.36, -s * 0.38), c + Vector2(s * 0.32, s * 0.08), c + Vector2(0, s * 0.44), c + Vector2(-s * 0.32, s * 0.08)])
			draw_colored_polygon(sh, tint)
			draw_polyline(sh + PackedVector2Array([sh[0]]), o, 1.5)
			if kind == "guard":
				draw_line(c + Vector2(0, -s * 0.28), c + Vector2(0, s * 0.3), o, 2.0)
		"hush":  # crossed-out waves
			for k in range(2):
				draw_arc(c + Vector2(-s * 0.2, 0), s * (0.2 + k * 0.16), -0.8, 0.8, 10, tint, 2.0)
			draw_line(c + Vector2(-s * 0.4, s * 0.38), c + Vector2(s * 0.4, -s * 0.38), Color(1, 0.4, 0.4), 2.5)
		"dark":  # moon behind mist lines
			draw_circle(c + Vector2(0, -s * 0.1), s * 0.26, tint)
			for k in range(2):
				draw_line(c + Vector2(-s * 0.44, s * (0.18 + k * 0.16)), c + Vector2(s * 0.44, s * (0.18 + k * 0.16)), Color(0.75, 0.65, 0.95), 2.0)
		"rest":  # z z
			var f := get_theme_default_font()
			draw_string(f, c + Vector2(-s * 0.4, s * 0.3), "z", HORIZONTAL_ALIGNMENT_LEFT, -1, int(s * 0.7), tint)
			draw_string(f, c + Vector2(0, 0), "z", HORIZONTAL_ALIGNMENT_LEFT, -1, int(s * 0.5), tint)
		"lock":
			draw_arc(c + Vector2(0, -s * 0.08), s * 0.2, PI, TAU, 10, tint, 3.0)
			draw_rect(Rect2(c + Vector2(-s * 0.3, -s * 0.08), Vector2(s * 0.6, s * 0.48)), tint)
		"bolt":  # zig-zag arcane bolt
			var z := PackedVector2Array([c + Vector2(s * 0.12, -s * 0.46), c + Vector2(-s * 0.22, s * 0.04), c + Vector2(0, s * 0.04),
				c + Vector2(-s * 0.12, s * 0.46), c + Vector2(s * 0.24, -s * 0.06), c + Vector2(0.0, -s * 0.06)])
			draw_colored_polygon(z, tint)
		"lume":  # starburst
			for k in range(8):
				var a3 := TAU * k / 8.0
				var len := 0.46 if k % 2 == 0 else 0.3
				draw_line(c, c + Vector2(cos(a3), sin(a3)) * s * len, tint, 2.5)
			draw_circle(c, s * 0.14, Color(1, 1, 0.9))
		"skull":
			draw_circle(c + Vector2(0, -s * 0.06), s * 0.32, tint)
			draw_rect(Rect2(c + Vector2(-s * 0.16, s * 0.14), Vector2(s * 0.32, s * 0.2)), tint)
			draw_circle(c + Vector2(-s * 0.12, -s * 0.06), s * 0.08, Color(0, 0, 0))
			draw_circle(c + Vector2(s * 0.12, -s * 0.06), s * 0.08, Color(0, 0, 0))
