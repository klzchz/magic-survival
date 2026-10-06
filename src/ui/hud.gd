extends CanvasLayer
# Survival bars, inventory line, transient messages and the end screen for
# the local apprentice.

const Cfg = preload("res://src/core/config.gd")
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


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var y := 16.0
	for r in ROWS:
		var lab := Label.new()
		lab.text = r[1]
		lab.position = Vector2(16, y - 4)
		root.add_child(lab)
		var bg := ColorRect.new()
		bg.color = Color(0, 0, 0, 0.5)
		bg.position = Vector2(120, y)
		bg.size = Vector2(BAR_W, 14)
		root.add_child(bg)
		var bar := ColorRect.new()
		bar.color = r[2]
		bar.position = Vector2(120, y)
		bar.size = Vector2(BAR_W, 14)
		root.add_child(bar)
		bars[r[0]] = bar
		y += 24.0

	lbl_stats = Label.new()
	lbl_stats.position = Vector2(16, y + 6)
	root.add_child(lbl_stats)

	lbl_msg = Label.new()
	lbl_msg.position = Vector2(16, y + 80)
	lbl_msg.visible = false
	root.add_child(lbl_msg)

	var hint := Label.new()
	hint.text = "WASD mover · Q/PgUp câmera · E interagir · 1 comer · 2 fogo-fátuo · 3 poção · 4 assar · 5 fogueira · 6 ward · 7 varinha · 8 caldeirão · 9 elixir · F Lume · G Escudo · Espaço feitiço"
	hint.position = Vector2(16, 672)
	hint.size = Vector2(1248, 44)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(hint)

	lbl_end = Label.new()
	lbl_end.position = Vector2(380, 320)
	lbl_end.visible = false
	root.add_child(lbl_end)


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
