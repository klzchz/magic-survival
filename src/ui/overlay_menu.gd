extends CanvasLayer
## Reusable full-screen menu: title, optional subtitle and a column of
## buttons. Emits picked(id). Used for the main menu, pause, controls and
## game-over / victory screens. Keyboard and gamepad navigate the buttons
## (first one is focused), mouse clicks them.
##
## Example:
##   var m = OverlayMenuScene.instantiate()
##   m.setup("Pausado", "", [["resume", "Continuar"], ["menu", "Menu principal"]])
##   m.picked.connect(_on_menu_pick)
##   add_child(m)

signal picked(id: String)

const TITLE_FONT_PATH := "res://assets/fonts/Cinzel.ttf"
const GOLD := Color(0.85, 0.7, 0.4)
const VERSION := "Demo v0.4"

var title := ""
var subtitle := ""
var options: Array = []    # [[id, label], ...]
var big := false           # main-menu layout: huge title, lighter dim, version tag


func setup(t: String, sub: String, opts: Array, is_big := false) -> void:
	title = t
	subtitle = sub
	options = opts
	big = is_big


func _button_style(bg: Color, border_alpha: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = Color(GOLD.r, GOLD.g, GOLD.b, border_alpha)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(10)
	return sb


func _ready() -> void:
	var font: Font = load(TITLE_FONT_PATH) if ResourceLoader.exists(TITLE_FONT_PATH) else null
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.03, 0.02, 0.06, 0.35 if big else 0.72)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	if big:  # soft vignette band behind the title
		var band := ColorRect.new()
		band.set_anchors_preset(Control.PRESET_FULL_RECT)
		band.color = Color(0.02, 0.01, 0.05, 0.35)
		band.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(band)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(760, 0)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)

	var t := Label.new()
	t.text = title
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 76 if big else 46)
	t.add_theme_color_override("font_color", GOLD)
	t.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	t.add_theme_constant_override("outline_size", 10)
	if font != null:
		t.add_theme_font_override("font", font)
	box.add_child(t)

	if subtitle != "":
		var s := Label.new()
		s.text = subtitle
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		s.custom_minimum_size = Vector2(760, 0)
		s.add_theme_font_size_override("font_size", 18)
		s.add_theme_color_override("font_color", Color(0.88, 0.85, 0.95))
		s.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		s.add_theme_constant_override("outline_size", 6)
		box.add_child(s)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 18)
	box.add_child(spacer)

	var first: Button = null
	for opt in options:
		var b := Button.new()
		b.text = opt[1]
		b.custom_minimum_size = Vector2(340, 54)
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		b.add_theme_font_size_override("font_size", 22)
		if font != null:
			b.add_theme_font_override("font", font)
		b.add_theme_stylebox_override("normal", _button_style(Color(0.1, 0.07, 0.17, 0.92), 0.55))
		b.add_theme_stylebox_override("hover", _button_style(Color(0.2, 0.13, 0.3, 0.95), 1.0))
		b.add_theme_stylebox_override("focus", _button_style(Color(0.2, 0.13, 0.3, 0.95), 1.0))
		b.add_theme_stylebox_override("pressed", _button_style(Color(0.3, 0.2, 0.42, 1.0), 1.0))
		b.add_theme_color_override("font_color", Color(0.95, 0.9, 0.8))
		b.add_theme_color_override("font_hover_color", GOLD)
		b.add_theme_color_override("font_focus_color", GOLD)
		var id: String = opt[0]
		b.pressed.connect(func(): picked.emit(id))
		box.add_child(b)
		if first == null:
			first = b
	if first != null:
		first.call_deferred("grab_focus")

	if big:
		var v := Label.new()
		v.text = VERSION + "  ·  Modelos KayKit (CC0)  ·  Godot 4"
		v.position = Vector2(16, 690)
		v.add_theme_font_size_override("font_size", 12)
		v.add_theme_color_override("font_color", Color(0.8, 0.78, 0.7, 0.6))
		add_child(v)
