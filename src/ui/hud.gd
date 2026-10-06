extends CanvasLayer
# Survival bars, inventory line, transient messages and the end screen for
# the local apprentice.

const Cfg = preload("res://src/core/config.gd")
const TITLE_FONT_PATH := "res://assets/fonts/Cinzel.ttf"
const GOLD := Color(0.85, 0.7, 0.4)
const BAR_W := 180.0
const ROWS := [
	["hunger", "Fome", Color(0.90, 0.70, 0.30)],
	["health", "Vida", Color(0.85, 0.25, 0.30)],
	["mana", "Mana", Color(0.35, 0.60, 0.95)],
	["corruption", "Corrupção", Color(0.60, 0.20, 0.70)],
	["wisp", "Fogo-fátuo", Color(1.00, 0.75, 0.40)],
]

var bars := {}
var lbl_stats: Label
var lbl_msg: Label
var lbl_end: Label
var msg_t := 0.0


var title_font: Font


func _panel_style(alpha := 0.62) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.05, 0.12, alpha)
	sb.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.55)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(10)
	return sb


func _label(parent: Control, text: String, pos: Vector2, size_px: int, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 4)
	if font != null:
		l.add_theme_font_override("font", font)
	parent.add_child(l)
	return l


func _ready() -> void:
	if ResourceLoader.exists(TITLE_FONT_PATH):
		title_font = load(TITLE_FONT_PATH)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var panel := Panel.new()
	panel.position = Vector2(10, 10)
	panel.size = Vector2(330, 214)
	panel.add_theme_stylebox_override("panel", _panel_style())
	root.add_child(panel)

	var y := 22.0
	for r in ROWS:
		var lab := _label(root, r[1], Vector2(24, y - 5), 15, title_font)
		lab.add_theme_color_override("font_color", GOLD)
		var bg := Panel.new()
		var bg_style := StyleBoxFlat.new()
		bg_style.bg_color = Color(0, 0, 0, 0.55)
		bg_style.set_corner_radius_all(5)
		bg.add_theme_stylebox_override("panel", bg_style)
		bg.position = Vector2(140, y)
		bg.size = Vector2(BAR_W, 12)
		root.add_child(bg)
		var bar := Panel.new()
		var bar_style := StyleBoxFlat.new()
		bar_style.bg_color = r[2]
		bar_style.set_corner_radius_all(5)
		bar.add_theme_stylebox_override("panel", bar_style)
		bar.position = Vector2(140, y)
		bar.size = Vector2(BAR_W, 12)
		root.add_child(bar)
		bars[r[0]] = bar
		y += 24.0

	lbl_stats = _label(root, "", Vector2(24, y + 2), 13)
	lbl_stats.add_theme_color_override("font_color", Color(0.92, 0.9, 0.85))

	lbl_msg = _label(root, "", Vector2(0, 560), 22, title_font)
	lbl_msg.size = Vector2(1280, 40)
	lbl_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_msg.add_theme_color_override("font_color", Color(1.0, 0.92, 0.75))
	lbl_msg.visible = false

	var hint := _label(root, "WASD mover · Q/PgUp câmera · E interagir · 1 comer · 2 fogo-fátuo · 3 poção · 4 assar · 5 fogueira · 6 ward · 7 varinha · 8 caldeirão · 9 elixir · F Lume · G Escudo · Espaço/clique feitiço", Vector2(16, 682), 12)
	hint.size = Vector2(1248, 34)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color(0.85, 0.82, 0.75, 0.8))

	lbl_end = _label(root, "", Vector2(140, 300), 26, title_font)
	lbl_end.size = Vector2(1000, 120)
	lbl_end.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_end.add_theme_color_override("font_color", Color(1.0, 0.85, 0.55))
	lbl_end.visible = false


func _process(delta: float) -> void:
	if msg_t > 0.0:
		msg_t -= delta
		if msg_t <= 0.0:
			lbl_msg.visible = false


func flash(m: String) -> void:
	if m == "":
		return
	lbl_msg.text = m
	lbl_msg.visible = true
	msg_t = 2.2


func show_end(text: String) -> void:
	lbl_end.text = text
	lbl_end.visible = true


func hide_end() -> void:
	lbl_end.visible = false


func _fill(id: String, value: float, max_value: float) -> void:
	bars[id].size = Vector2(BAR_W * clampf(value, 0.0, max_value) / max_value, 14)


func refresh(p, world) -> void:
	if p == null:
		return
	_fill("hunger", p.hunger, 100.0)
	_fill("health", p.health, 100.0)
	_fill("mana", p.mana, p.mana_max)
	_fill("corruption", p.corruption, 100.0)
	_fill("wisp", p.wisp, 100.0)
	var dn = world.day_night
	var meta = world.meta
	var moon := "  ·  LUA DE SANGUE" if dn.blood_moon else ""
	var shield := ("  ·  Escudo %.1fs" % p.shield_t) if p.shield_t > 0.0 else ""
	var spell_txt := "básico (ache páginas nas Ruínas)"
	if meta.spells.size() > 0:
		var names := PackedStringArray()
		for s in meta.spells:
			names.append(str(s).to_upper())
		spell_txt = "básico + " + ", ".join(names)
	var inv: Dictionary = p.inv
	lbl_stats.text = "Dia %d (melhor: %d) · Portal: %d/%d · Aprendizes: %d%s%s\nFeitiços: %s\nCogumelo %d · Assado %d · Galho %d · Madeira %d · Pedra %d · Osso %d · Varinha: %s" % [
		dn.nights + 1, meta.best_nights, meta.hearts, Cfg.PORTAL_HEARTS, world.players().size(), moon, shield,
		spell_txt,
		inv.mushroom, inv.cooked, inv.twig, inv.wood, inv.stone, inv.bone,
		("osso" if p.wand_level == 1 else "galho")]
