extends CanvasLayer
## The apprentice's HUD (design: a quiet frame around the island, readable in
## combat). Top-left: who you are, health, hunger/mana/noise, active states.
## Top-right: day, phase and time to the next phase. Top-centre: a discreet
## objective. Bottom: spell bar (key, mana, recharge) over the inventory
## (amounts, durability/fuel, actions on hover). Tab: the crafting book with
## search, categories, "can craft" filter and a detail pane.
## Display only: every request goes through world.perform() (network-ready).
## Laid out with anchors so it holds at 16:9 and 16:10 (stretch "expand").

const Cfg = preload("res://src/core/config.gd")
const Data = preload("res://src/core/data.gd")
const Inventory = preload("res://src/gameplay/inventory.gd")
const IconFactory = preload("res://src/ui/icon_factory.gd")
const HudIcon = preload("res://src/ui/hud_icon.gd")
const TITLE_FONT_PATH := "res://assets/fonts/Cinzel.ttf"
const GOLD := Color(0.88, 0.72, 0.42)
const INK := Color(0.96, 0.92, 0.84)
const MUTED := Color(0.76, 0.72, 0.66)
const OK := Color(0.55, 0.95, 0.6)
const WARN := Color(1.0, 0.72, 0.4)
const DANGER := Color(1.0, 0.45, 0.4)
const ARCANE := Color(0.75, 0.6, 1.0)
const SLOT := 50.0
const SPELLS := [["bolt", "F", "bolt"], ["lume", "Z", "lume"], ["escudo", "X", "escudo"]]
const METERS := [
	# id, label, icon, colour, tooltip
	["hunger", "Fome", "hunger", Color(0.95, 0.72, 0.32), "Fome: cai com o tempo. Em 0 você perde vida. Coma frutinhas e cogumelos (assados rendem mais)."],
	["mana", "Mana", "mana", Color(0.42, 0.66, 1.0), "Mana: paga os feitiços (F, Z, X). Recupera devagar; Essência e poções aceleram."],
	["noise", "Ruído", "noise", Color(0.78, 0.5, 1.0), "Ruído arcano: magia faz barulho. Ruído alto atrai Errantes de longe à noite. Baixa sozinho."],
	["wisp", "Fogo-fátuo", "wisp", Color(1.0, 0.75, 0.4), "Fogo-fátuo: sua luz pessoal. Protege da escuridão enquanto durar. Reacenda com Essência."],
	["corruption", "Corrupção", "corruption", Color(0.72, 0.35, 0.85), "Corrupção: feitiços e cogumelos crus a aumentam. Alta, ela drena sua vida."],
]

var world = null
var title_font: Font
var icons: IconFactory
var root: Control

# status card
var lbl_name: Label
var lbl_title: Label
var hp_fill: ColorRect
var hp_text: Label
var meters := {}                 # id -> {fill: ColorRect, val: Label, max_w}
var chips: HFlowContainer
var _chip_sig := ""
# clock
var clock_icon
var lbl_day: Label
var lbl_phase: Label
var lbl_next: Label
var lbl_portal: Label
var day_bar: Control
var _next_t := 0.0
var _next_info := {}
# objective, boss, prompt, messages, end
var obj_panel: Panel
var obj_title: Label
var obj_text: Label
var boss_panel: Panel
var boss_name: Label
var boss_fill: ColorRect
var lbl_prompt: Label
var lbl_msg: Label
var msg_t := 0.0
var lbl_end: Label
# bottom bars
var spell_views := {}            # id -> {panel, icon, cost, shade, cd, lock}
var slot_views: Array = []
var equip_views := {}
# crafting book
var craft_panel: Panel
var craft_search: LineEdit
var craft_only: CheckBox
var craft_cat := "Todas"
var craft_sel := "torch"
var cat_buttons := {}
var craft_list: VBoxContainer
var craft_rows := {}             # recipe id -> {button, status: Label}
var det := {}                    # detail pane widgets
var _craft_refresh_t := 0.0


# ---------- helpers ----------

func _panel_style(alpha := 0.78, radius := 10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.05, 0.12, alpha)
	sb.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.45)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(6)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 4
	return sb


func _label(parent: Control, text: String, pos: Vector2, size_px: int, font: Font = null, color := INK) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 4)
	if font != null:
		l.add_theme_font_override("font", font)
	parent.add_child(l)
	return l


func _rect(parent: Control, pos: Vector2, sz: Vector2, c: Color) -> ColorRect:
	var r := ColorRect.new()
	r.position = pos
	r.size = sz
	r.color = c
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	return r


## Anchors a control to a screen point (0..1) with a pixel offset and size.
func _place(c: Control, anchor: Vector2, offset: Vector2, sz: Vector2) -> void:
	c.anchor_left = anchor.x
	c.anchor_right = anchor.x
	c.anchor_top = anchor.y
	c.anchor_bottom = anchor.y
	c.offset_left = offset.x
	c.offset_top = offset.y
	c.offset_right = offset.x + sz.x
	c.offset_bottom = offset.y + sz.y


func _card(anchor: Vector2, offset: Vector2, sz: Vector2, alpha := 0.78) -> Panel:
	var p := Panel.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", _panel_style(alpha))
	root.add_child(p)
	_place(p, anchor, offset, sz)
	return p


static func _mmss(seconds: float) -> String:
	var s := int(ceil(seconds))
	return "%d:%02d" % [s / 60, s % 60]


func _ready() -> void:
	if ResourceLoader.exists(TITLE_FONT_PATH):
		title_font = load(TITLE_FONT_PATH)
	icons = IconFactory.new()
	add_child(icons)
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_status()
	_build_clock()
	_build_objective()
	_build_bottom()
	_build_crafting()

	lbl_prompt = _label(root, "", Vector2.ZERO, 20, title_font)
	_place(lbl_prompt, Vector2(0.5, 1.0), Vector2(-400, -186), Vector2(800, 30))
	lbl_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_prompt.visible = false

	lbl_msg = _label(root, "", Vector2.ZERO, 17, title_font, Color(1.0, 0.92, 0.75))
	_place(lbl_msg, Vector2(0.5, 1.0), Vector2(-420, -246), Vector2(840, 56))
	lbl_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_msg.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	lbl_msg.visible = false

	var keys := _label(root, "Tab Criação  ·  M Mapa  ·  Esc Pausa e controles", Vector2.ZERO, 12, null, Color(MUTED.r, MUTED.g, MUTED.b, 0.85))
	_place(keys, Vector2(0.5, 1), Vector2(160, -SLOT - 44), Vector2(330, 18))
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	lbl_end = _label(root, "", Vector2.ZERO, 26, title_font, Color(1.0, 0.85, 0.55))
	_place(lbl_end, Vector2(0.5, 0.5), Vector2(-500, -80), Vector2(1000, 120))
	lbl_end.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_end.visible = false


# ---------- status card (top-left) ----------

func _build_status() -> void:
	var card := _card(Vector2.ZERO, Vector2(12, 12), Vector2(300, 152))
	lbl_name = _label(card, "", Vector2(14, 6), 19, title_font, GOLD)
	lbl_title = _label(card, "", Vector2(14, 32), 12, null, MUTED)
	card.add_child(HudIcon.make("heart", 20.0, Color(0.92, 0.3, 0.35)))
	card.get_child(card.get_child_count() - 1).position = Vector2(12, 54)
	_rect(card, Vector2(40, 54), Vector2(246, 20), Color(0, 0, 0, 0.6))
	hp_fill = _rect(card, Vector2(40, 54), Vector2(246, 20), Color(0.82, 0.22, 0.28))
	hp_text = _label(card, "", Vector2(40, 54), 13, null, INK)
	hp_text.size = Vector2(246, 20)
	hp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var hp_hit := Control.new()
	hp_hit.position = Vector2(12, 52)
	hp_hit.size = Vector2(276, 24)
	hp_hit.tooltip_text = "Vida: chega a 0 e o aprendiz cai. Perde-se por golpes de Errantes, fome zerada, escuridão total e corrupção alta. Comida e poções curam."
	card.add_child(hp_hit)
	for i in range(METERS.size()):
		var m: Array = METERS[i]
		var small := i >= 3
		var w := 88.0 if not small else 134.0
		var x := 12.0 + (i % 3) * 94.0 if not small else 12.0 + (i - 3) * 142.0
		var y := 84.0 if not small else 120.0
		var box := Control.new()
		box.position = Vector2(x, y)
		box.size = Vector2(w, 28)
		box.tooltip_text = m[4]
		card.add_child(box)
		var ic: Control = HudIcon.make(m[2], 16.0, m[3])
		ic.position = Vector2(0, 2)
		box.add_child(ic)
		_label(box, m[1], Vector2(20, -2), 11, null, MUTED)
		var val := _label(box, "", Vector2(20, -2), 11, null, INK)
		val.size = Vector2(w - 20, 14)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_rect(box, Vector2(20, 16), Vector2(w - 20, 7), Color(0, 0, 0, 0.6))
		var fill := _rect(box, Vector2(20, 16), Vector2(w - 20, 7), m[3])
		meters[m[0]] = {"fill": fill, "val": val, "max_w": w - 20}
	chips = HFlowContainer.new()
	chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chips.add_theme_constant_override("h_separation", 6)
	chips.add_theme_constant_override("v_separation", 6)
	root.add_child(chips)
	_place(chips, Vector2.ZERO, Vector2(12, 170), Vector2(300, 60))


func _chip(icon: String, text: String, c: Color, tip: String) -> void:
	var pc := PanelContainer.new()
	var sb := _panel_style(0.82, 8)
	sb.border_color = Color(c.r, c.g, c.b, 0.8)
	sb.set_content_margin_all(4)
	sb.content_margin_left = 6
	sb.content_margin_right = 8
	pc.add_theme_stylebox_override("panel", sb)
	pc.tooltip_text = tip
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 5)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(hb)
	hb.add_child(HudIcon.make(icon, 14.0, c))
	var l := _label(hb, text, Vector2.ZERO, 12, null, c.lerp(INK, 0.35))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chips.add_child(pc)


## Active states as chips (icon + words, never colour alone).
func _refresh_chips(p, w) -> void:
	var list := []
	if p.shield_t > 0.0:
		list.append(["escudo", "Escudo %ds" % int(ceil(p.shield_t)), Color(0.5, 0.75, 1.0), "Escudo: nenhum golpe te atinge."])
	if p.guard_t > 0.0:
		list.append(["guard", "Proteção %ds" % int(ceil(p.guard_t)), GOLD, "Talismã do Guardião: -50% de dano recebido."])
	if p.hush_t > 0.0:
		list.append(["hush", "Silêncio %ds" % int(ceil(p.hush_t)), Color(0.6, 0.8, 1.0), "Talismã do Silêncio: quase nenhum ruído arcano."])
	if p.dark_t > 0.0:
		list.append(["dark", "No escuro: a Névoa fere", DANGER, "Escuridão total à noite tira vida. Fique perto de luz: fogueira, tocha, lanterna ou fogo-fátuo."])
	if p.hunger <= 0.0:
		list.append(["skull", "Faminto: perdendo vida", DANGER, "Fome em 0 tira vida. Coma algo (1-0 ou clique no item)."])
	elif p.hunger < p.hunger_max * 0.25:
		list.append(["hunger", "Com fome", WARN, "Coma logo: em 0 você começa a perder vida."])
	if p.noise >= 60.0:
		list.append(["noise", "Ruidoso: atrai Errantes", ARCANE, "Muito ruído arcano. À noite, Errantes ouvem de longe."])
	if p.corruption >= 60.0:
		list.append(["corruption", "Corrompido", Color(0.8, 0.4, 0.9), "Corrupção alta drena vida. Poções e comida assada ajudam."])
	if p.resting:
		list.append(["rest", "Descansando", OK, "Descansando: cura, o tempo passa mais rápido."])
	if w.near_campfire(p, true) != null:
		list.append(["fire", "Perto da fogueira", Color(1.0, 0.65, 0.3), "Fogueira acesa: luz segura, queima Errantes, cozinha comida."])
	var sig := ""
	for c in list:
		sig += String(c[1]) + "|"
	if sig == _chip_sig:
		return
	_chip_sig = sig
	for n in chips.get_children():
		n.queue_free()
	for c in list:
		_chip(c[0], c[1], c[2], c[3])


# ---------- clock (top-right) ----------

class DayBar extends Control:
	## The day-night cycle as a strip: day (gold), dusk (amber), night (navy),
	## with a marker for now. Segments come from the real light curve.
	var pos := 0.0
	var segments: Array = []   # [[from, to, phase]]

	func _draw() -> void:
		var cols := {"day": Color(0.95, 0.8, 0.4), "dusk": Color(0.95, 0.5, 0.3), "night": Color(0.2, 0.22, 0.45)}
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.6))
		for s in segments:
			draw_rect(Rect2(Vector2(size.x * s[0], 1), Vector2(size.x * (s[1] - s[0]), size.y - 2)), cols.get(s[2], Color.WHITE))
		var x := size.x * pos
		draw_rect(Rect2(Vector2(x - 1.5, -3), Vector2(3, size.y + 6)), Color(1, 1, 1))
		draw_rect(Rect2(Vector2(x - 1.5, -3), Vector2(3, size.y + 6)), Color(0, 0, 0), false, 1.0)


func _build_clock() -> void:
	var card := _card(Vector2(1, 0), Vector2(-252, 12), Vector2(240, 112))
	clock_icon = HudIcon.make("sun", 30.0, Color(1.0, 0.85, 0.4))
	clock_icon.position = Vector2(12, 10)
	card.add_child(clock_icon)
	lbl_day = _label(card, "", Vector2(52, 6), 19, title_font, GOLD)
	lbl_phase = _label(card, "", Vector2(52, 32), 13, null, INK)
	day_bar = DayBar.new()
	day_bar.position = Vector2(12, 58)
	day_bar.size = Vector2(216, 10)
	day_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(day_bar)
	lbl_next = _label(card, "", Vector2(12, 72), 13, null, INK)
	lbl_portal = _label(card, "", Vector2(12, 90), 11, null, MUTED)
	var tip := Control.new()
	tip.position = Vector2.ZERO
	tip.size = Vector2(240, 112)
	tip.tooltip_text = "Ciclo: dia → crepúsculo → noite. À noite os Errantes surgem do chão e caçam magia; luz de fogueira os queima. O 1º dia é calmo para aprender."
	card.add_child(tip)


func _refresh_clock(w) -> void:
	var dn = w.day_night
	_next_t -= get_process_delta_time()
	if _next_t <= 0.0 or _next_info.is_empty():
		_next_t = 0.5
		_next_info = dn.next_phase()
		if day_bar.segments.is_empty():  # the cycle shape never changes: sample once
			var segs := []
			var prev := ""
			for i in range(97):
				var f := float(i) / 96.0
				var ph: String = dn.phase_of(dn.light_at(dn.t - dn.cycle_pos() * Cfg.DAY_LENGTH + f * Cfg.DAY_LENGTH))
				if ph != prev:
					if not segs.is_empty():
						segs[-1][1] = f
					segs.append([f, 1.0, ph])
					prev = ph
			day_bar.segments = segs
	var phase: String = _next_info.get("phase", "day")
	var names := {"day": "Dia claro", "dusk": "Crepúsculo", "night": "Noite"}
	lbl_day.text = "Dia %d" % (dn.nights + 1)
	lbl_phase.text = ("LUA DE SANGUE" if dn.blood_moon and phase == "night" else names.get(phase, ""))
	lbl_phase.add_theme_color_override("font_color", DANGER if dn.blood_moon and phase == "night" else INK)
	clock_icon.set_kind({"day": "sun", "dusk": "dusk", "night": "moon"}.get(phase, "sun"),
		{"day": Color(1.0, 0.85, 0.4), "dusk": Color(1.0, 0.6, 0.35), "night": Color(0.7, 0.78, 1.0)}.get(phase, INK))
	var nxt: String = _next_info.get("next", "")
	var secs := maxf(0.0, float(_next_info.get("seconds", 0.0)) - (0.5 - maxf(_next_t, 0.0)))
	lbl_next.text = "%s em %s" % [names.get(nxt, ""), _mmss(secs)]
	lbl_next.add_theme_color_override("font_color", WARN if nxt == "night" and secs < 30.0 else INK)
	day_bar.pos = dn.cycle_pos()
	day_bar.queue_redraw()
	lbl_portal.text = "Portal %d/%d  ·  Recorde: %d noites" % [w.run_hearts, Cfg.PORTAL_HEARTS, w.meta.best_nights]


# ---------- objective (top centre, discreet) ----------

func _build_objective() -> void:
	obj_panel = _card(Vector2(0.5, 0), Vector2(-220, 12), Vector2(440, 50), 0.55)
	obj_title = _label(obj_panel, "", Vector2(12, 4), 13, title_font, GOLD)
	obj_text = _label(obj_panel, "", Vector2(12, 24), 13, null, INK)
	obj_text.size = Vector2(416, 20)
	obj_text.clip_text = true
	boss_panel = _card(Vector2(0.5, 0), Vector2(-250, 70), Vector2(500, 46), 0.75)
	boss_panel.visible = false
	boss_name = _label(boss_panel, "", Vector2(10, 2), 15, title_font, Color(0.6, 1.0, 0.7))
	boss_name.size = Vector2(480, 20)
	boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rect(boss_panel, Vector2(12, 26), Vector2(476, 12), Color(0, 0, 0, 0.6))
	boss_fill = _rect(boss_panel, Vector2(12, 26), Vector2(476, 12), Color(0.3, 0.9, 0.5))


func _refresh_objective(w) -> void:
	var info: Dictionary = w.objective_info()
	obj_panel.visible = not info.is_empty()
	if info.is_empty():
		return
	var fresh: bool = info.get("fresh", false)
	obj_title.text = ("✓ Concluído: " if fresh else "Objetivo: ") + String(info.title)
	obj_text.text = info.text
	obj_title.add_theme_color_override("font_color", OK if fresh else GOLD)


## Guardian health bar (empty name hides it).
func set_boss(n: String, hp: float, hp_max: float) -> void:
	if boss_panel == null:
		return
	boss_panel.visible = n != ""
	if n == "":
		return
	boss_name.text = "%s  %d/%d" % [n, int(hp), int(hp_max)]
	boss_fill.size.x = 476.0 * clampf(hp / maxf(1.0, hp_max), 0.0, 1.0)


# ---------- spell bar + inventory (bottom) ----------

func _build_bottom() -> void:
	var total := Inventory.SIZE * (SLOT + 4) + 20 + 2 * (SLOT + 4)
	var inv := _card(Vector2(0.5, 1), Vector2(-total / 2.0 - 8, -SLOT - 22), Vector2(total + 12, SLOT + 14), 0.78)
	for i in range(Inventory.SIZE):
		var key_txt := str((i + 1) % 10) if i < 10 else ""
		slot_views.append(_slot(inv, Vector2(6 + i * (SLOT + 4), 7), key_txt, i, ""))
	var ex := 6 + Inventory.SIZE * (SLOT + 4) + 16
	equip_views["hand"] = _slot(inv, Vector2(ex, 7), "Mão", -1, "hand")
	equip_views["body"] = _slot(inv, Vector2(ex + SLOT + 4, 7), "Corpo", -1, "body")
	inv.mouse_filter = Control.MOUSE_FILTER_PASS

	var sw := SPELLS.size() * (SLOT + 8) + 8
	var bar := _card(Vector2(0.5, 1), Vector2(-sw / 2.0, -SLOT * 2 - 40), Vector2(sw, SLOT + 12), 0.78)
	bar.mouse_filter = Control.MOUSE_FILTER_PASS
	for i in range(SPELLS.size()):
		var sp: Array = SPELLS[i]
		var panel := Panel.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.14, 0.1, 0.24, 0.95)
		sb.border_color = Color(ARCANE.r, ARCANE.g, ARCANE.b, 0.6)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(8)
		panel.add_theme_stylebox_override("panel", sb)
		panel.position = Vector2(8 + i * (SLOT + 8), 6)
		panel.size = Vector2(SLOT, SLOT)
		bar.add_child(panel)
		var ic: Control = HudIcon.make(sp[2], 28.0, Color(0.85, 0.75, 1.0))
		ic.position = Vector2(11, 9)
		panel.add_child(ic)
		var key := _label(panel, sp[1], Vector2(4, -2), 15, title_font, Color(1.0, 0.86, 0.5))
		key.add_theme_constant_override("outline_size", 5)
		var cost := _label(panel, "", Vector2(SLOT - 30, SLOT - 18), 11, null, Color(0.6, 0.8, 1.0))
		cost.size = Vector2(26, 14)
		cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var shade := _rect(panel, Vector2.ZERO, Vector2(SLOT, 0), Color(0, 0, 0, 0.62))
		var cd := _label(panel, "", Vector2(0, 14), 15, null, INK)
		cd.size = Vector2(SLOT, 20)
		cd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var lock: Control = HudIcon.make("lock", 18.0, MUTED)
		lock.position = Vector2(SLOT - 22, 4)
		panel.add_child(lock)
		spell_views[sp[0]] = {"panel": panel, "icon": ic, "cost": cost, "shade": shade, "cd": cd, "lock": lock, "style": sb}


func _refresh_spells(p, w) -> void:
	for id in spell_views:
		var v: Dictionary = spell_views[id]
		var d := Data.spell(id)
		var known: bool = id == "bolt" or w.meta.knows(id)
		var cost: float = p.spell_cost() if id == "bolt" else float(d.get("mana", 0))
		var left := float(p.spell_cd.get(id, 0.0))
		var total := maxf(0.01, float(d.get("cooldown", 1.0)))
		var poor: bool = p.mana < cost
		v.lock.visible = not known
		v.cost.text = "%d" % int(cost)
		v.cost.add_theme_color_override("font_color", DANGER if poor else Color(0.6, 0.8, 1.0))
		v.shade.size.y = SLOT if not known else SLOT * clampf(left / total, 0.0, 1.0)
		v.shade.position.y = SLOT - v.shade.size.y
		v.cd.text = ("%.1f" % left) if known and left > 0.05 else ""
		v.icon.modulate = Color(1, 1, 1, 0.35 if (not known or poor) else 1.0)
		v.style.border_color = Color(DANGER.r, DANGER.g, DANGER.b, 0.8) if known and poor else Color(ARCANE.r, ARCANE.g, ARCANE.b, 0.6)
		var state := "Ainda não aprendido: ache páginas do grimório nas ruínas." if not known else (
			"Sem mana suficiente." if poor else ("Recarregando: %.1f s" % left if left > 0.05 else "Pronto."))
		v.panel.tooltip_text = "%s  [%s]\n%s\nMana %d · Ruído %d · Recarga %s s\n%s" % [d.get("name", id), d.get("key", ""), d.get("desc", ""),
			int(cost), int(d.get("noise", 0)), str(d.get("cooldown", 0)), state]


func _slot(parent: Control, pos: Vector2, key_txt: String, index: int, equip_where: String) -> Dictionary:
	var panel := Panel.new()
	panel.position = pos
	panel.size = Vector2(SLOT, SLOT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.16, 0.12, 0.22, 0.92) if equip_where == "" else Color(0.24, 0.17, 0.1, 0.92)
	sb.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.35 if equip_where == "" else 0.7)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", sb)
	parent.add_child(panel)
	var icon := TextureRect.new()
	icon.position = Vector2(4, 3)
	icon.size = Vector2(SLOT - 8, SLOT - 10)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(icon)
	var key_l := _label(panel, key_txt, Vector2(3, -1), 10, null, Color(0.85, 0.8, 0.7, 0.9))
	var count := _label(panel, "", Vector2(SLOT - 28, SLOT - 21), 13)
	count.size = Vector2(25, 18)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var wear := ColorRect.new()
	wear.position = Vector2(4, SLOT - 5)
	wear.size = Vector2(SLOT - 8, 3)
	wear.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wear.visible = false
	panel.add_child(wear)
	panel.gui_input.connect(func(ev): _on_slot_input(ev, index, equip_where))
	return {"panel": panel, "icon": icon, "count": count, "wear": wear, "key": key_l, "sig": "", "where": equip_where}


func _on_slot_input(ev: InputEvent, index: int, equip_where: String) -> void:
	var mb := ev as InputEventMouseButton
	if mb == null or not mb.pressed or world == null:
		return
	if equip_where != "":
		if mb.button_index == MOUSE_BUTTON_LEFT and equip_where == "hand":
			world.perform(world.local_player, "unequip:hand")
		return
	if mb.button_index == MOUSE_BUTTON_LEFT:
		world.perform(world.local_player, "use:%d" % index)
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		world.perform(world.local_player, "alt:%d" % index)


## What clicking / right-clicking an item does, in words (shown on hover).
static func item_actions(id: String, key: String, equipped := "") -> String:
	var d := Data.item(id)
	var k := ("%s ou clique" % key) if key != "" else "Clique"
	if equipped == "hand":
		return "Clique: guardar na bolsa"
	if equipped != "":
		return "Equipado no corpo"
	var acts := []
	if d.has("equip"):
		acts.append("%s: equipar (%s)" % [k, "mão" if d.equip == "hand" else "corpo"])
	elif d.has("buff"):
		acts.append("%s: ativar" % k)
	elif d.get("potion", false):
		acts.append("%s: beber" % k)
	elif d.has("hunger"):
		acts.append("%s: comer" % k)
	elif d.has("wisp") or id == "essence":
		acts.append("%s: usar (fogo-fátuo / mana)" % k)
	var alt := "Botão direito%s" % ((" ou Shift+" + key) if key != "" else "")
	if d.has("cooked"):
		acts.append("%s perto de fogueira acesa: assar" % alt)
	if d.has("fuel"):
		acts.append("%s perto de fogueira: abastecer (+%ds)" % [alt, int(d.fuel)])
	acts.append("%s longe do fogo: largar no chão" % alt)
	return "\n".join(acts)


func _fill_slot(view: Dictionary, s, key_txt := "") -> void:
	var sig := ""
	if s != null:
		sig = "%s|%d|%d|%d" % [s.id, s.count, int(s.get("uses", -1)), int(s.get("fresh", -1) / 10.0)]
	if sig == view.sig:
		return
	view.sig = sig
	if s == null:
		view.icon.texture = null
		view.count.text = ""
		view.wear.visible = false
		view.panel.tooltip_text = "Mão vazia" if view.where == "hand" else ("Corpo: sem armadura" if view.where == "body" else "")
		return
	var d := Data.item(s.id)
	view.icon.texture = icons.get_icon(d.get("icon", s.id))
	view.count.text = str(s.count) if s.count > 1 else ""
	var frac := -1.0
	var state := ""
	if s.has("uses"):
		var full := float(d.get("uses", d.get("burn", 1.0)))
		frac = s.uses / full
		state = ("Combustível: %d s de luz" % int(s.uses)) if d.has("burn") else ("Durabilidade: %d/%d usos" % [int(s.uses), int(full)])
	elif s.has("fresh"):
		frac = s.fresh / float(d.get("spoil", 1.0))
		state = "Frescor: %d%%" % int(frac * 100.0)
	view.wear.visible = frac >= 0.0
	if frac >= 0.0:
		view.wear.size.x = (SLOT - 8) * clampf(frac, 0.0, 1.0)
		view.wear.color = Color(0.9, 0.3, 0.2).lerp(Color(0.4, 0.9, 0.4), frac) if s.has("fresh") else Color(0.95, 0.85, 0.5)
	var lines := ["%s%s" % [d.get("name", s.id), (" ×%d" % s.count) if s.count > 1 else ""], String(d.get("desc", ""))]
	if state != "":
		lines.append(state)
	lines.append("")
	lines.append(item_actions(s.id, key_txt, view.where))
	view.panel.tooltip_text = "\n".join(lines)


# ---------- crafting book (Tab) ----------

func _build_crafting() -> void:
	craft_panel = Panel.new()
	craft_panel.add_theme_stylebox_override("panel", _panel_style(0.92, 12))
	root.add_child(craft_panel)
	_place(craft_panel, Vector2.ZERO, Vector2(324, 134), Vector2(880, 446))
	craft_panel.visible = false
	_label(craft_panel, "Criação", Vector2(18, 12), 22, title_font, GOLD)
	craft_search = LineEdit.new()
	craft_search.placeholder_text = "Buscar receita…"
	craft_search.position = Vector2(170, 14)
	craft_search.size = Vector2(300, 32)
	craft_search.text_changed.connect(func(_t): _rebuild_list())
	craft_panel.add_child(craft_search)
	craft_only = CheckBox.new()
	craft_only.text = "Só o que posso fabricar"
	craft_only.position = Vector2(486, 16)
	craft_only.focus_mode = Control.FOCUS_NONE
	craft_only.toggled.connect(func(_on): _rebuild_list())
	craft_panel.add_child(craft_only)
	_label(craft_panel, "Tab fecha", Vector2(780, 20), 12, null, MUTED)

	var cats := VBoxContainer.new()
	cats.position = Vector2(14, 60)
	cats.size = Vector2(150, 370)
	cats.add_theme_constant_override("separation", 6)
	craft_panel.add_child(cats)
	for t in ["Todas"] + Data.tabs():
		var b := Button.new()
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(150, 34)
		b.add_theme_font_size_override("font_size", 13)
		var tab_name: String = t
		b.pressed.connect(func(): _select_tab(tab_name))
		cats.add_child(b)
		cat_buttons[t] = b

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(176, 60)
	scroll.size = Vector2(316, 372)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	craft_panel.add_child(scroll)
	craft_list = VBoxContainer.new()
	craft_list.custom_minimum_size = Vector2(304, 0)
	craft_list.add_theme_constant_override("separation", 4)
	scroll.add_child(craft_list)

	var pane := Panel.new()
	var psb := _panel_style(0.6, 10)
	psb.bg_color = Color(0.12, 0.09, 0.18, 0.9)
	pane.add_theme_stylebox_override("panel", psb)
	pane.position = Vector2(502, 60)
	pane.size = Vector2(364, 374)
	craft_panel.add_child(pane)
	det["pane"] = pane
	var big := TextureRect.new()
	big.position = Vector2(12, 12)
	big.size = Vector2(64, 64)
	big.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	big.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pane.add_child(big)
	det["icon"] = big
	det["name"] = _label(pane, "", Vector2(88, 12), 20, title_font, GOLD)
	det["kind"] = _label(pane, "", Vector2(88, 44), 12, null, MUTED)
	var desc := _label(pane, "", Vector2(14, 84), 13, null, INK)
	desc.size = Vector2(336, 40)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	det["desc"] = desc
	_label(pane, "Ingredientes", Vector2(14, 128), 14, title_font, GOLD)
	var ing := VBoxContainer.new()
	ing.position = Vector2(14, 150)
	ing.size = Vector2(336, 120)
	ing.add_theme_constant_override("separation", 2)
	pane.add_child(ing)
	det["ing"] = ing
	var station := _label(pane, "", Vector2(14, 276), 13, null, INK)
	station.size = Vector2(336, 20)
	det["station"] = station
	var why := _label(pane, "", Vector2(14, 296), 12, null, WARN)
	why.size = Vector2(336, 30)
	why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	det["why"] = why
	var make := Button.new()
	make.position = Vector2(14, 324)
	make.size = Vector2(336, 40)
	make.focus_mode = Control.FOCUS_NONE
	make.add_theme_font_size_override("font_size", 17)
	if title_font != null:
		make.add_theme_font_override("font", title_font)
	make.pressed.connect(_on_make)
	pane.add_child(make)
	det["make"] = make
	_select_tab("Todas")


func toggle_crafting() -> void:
	craft_panel.visible = not craft_panel.visible
	if craft_panel.visible:
		_rebuild_list()
	else:
		craft_search.release_focus()


## True while the player types in the search box (the world stops reading WASD).
func typing() -> bool:
	return craft_panel != null and craft_panel.visible and craft_search.has_focus()


func _input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo or not craft_panel.visible:
		return
	if k.keycode == KEY_TAB or (k.keycode == KEY_ESCAPE and craft_search.has_focus()):
		toggle_crafting()  # Tab always closes, even while typing
		get_viewport().set_input_as_handled()


func _select_tab(tab: String) -> void:
	craft_cat = tab if cat_buttons.has(tab) else "Todas"
	for t in cat_buttons:
		cat_buttons[t].button_pressed = t == craft_cat
	_rebuild_list()


func _recipe_matches(r: Dictionary) -> bool:
	if craft_cat != "Todas" and r.tab != craft_cat:
		return false
	var q := craft_search.text.strip_edges().to_lower() if craft_search != null else ""
	if q != "" and not Data.display_name(r.id).to_lower().contains(q):
		return false
	if craft_only != null and craft_only.button_pressed and world != null and world.local_player != null:
		return world.craft_blocker(world.local_player, r.id) == ""
	return true


func _rebuild_list() -> void:
	if craft_list == null:
		return
	for c in craft_list.get_children():
		c.queue_free()
	craft_rows.clear()
	var first := ""
	for r in Data.recipes():
		if not _recipe_matches(r):
			continue
		var rid: String = r.id
		if first == "":
			first = rid
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(300, 46)
		btn.focus_mode = Control.FOCUS_NONE
		btn.toggle_mode = true
		btn.pressed.connect(func(): _select_recipe(rid))
		var icon := TextureRect.new()
		icon.position = Vector2(6, 5)
		icon.size = Vector2(36, 36)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.texture = icons.get_icon(rid if r.get("structure", false) else Data.item(rid).get("icon", rid))
		btn.add_child(icon)
		_label(btn, Data.display_name(rid), Vector2(50, 4), 14, title_font, INK)
		var st := _label(btn, "", Vector2(50, 24), 11, null, MUTED)
		craft_list.add_child(btn)
		craft_rows[rid] = {"button": btn, "status": st}
	if craft_list.get_child_count() == 0:
		var none := _label(craft_list, "Nada encontrado. Limpe a busca ou o filtro.", Vector2.ZERO, 13, null, MUTED)
		none.custom_minimum_size = Vector2(300, 40)
	if not craft_rows.has(craft_sel) and first != "":
		craft_sel = first
	_select_recipe(craft_sel)


func _select_recipe(rid: String) -> void:
	craft_sel = rid
	for id in craft_rows:
		craft_rows[id].button.button_pressed = id == rid
	_craft_refresh_t = 0.0
	if world != null and world.local_player != null:
		_refresh_crafting(world.local_player)


func _on_make() -> void:
	if world == null or world.local_player == null or craft_sel == "":
		return
	world.perform(world.local_player, "craft:" + craft_sel)
	_refresh_crafting(world.local_player)  # counts update at once; selection stays


func _refresh_crafting(p) -> void:
	if world == null or p == null:
		return
	# list statuses (words + colour)
	for rid in craft_rows:
		var why: String = world.craft_blocker(p, rid)
		var st: Label = craft_rows[rid].status
		if why == "":
			st.text = "✓ Pronto para fabricar"
			st.add_theme_color_override("font_color", OK)
		else:
			var tech := Data.recipe_tech(Data.recipe(rid))
			var missing := _missing(p, rid)
			st.text = ("✗ Falta: " + ", ".join(missing)) if not missing.is_empty() else ("✗ Perto de: " + Data.display_name(tech) if tech != "" else "✗ " + why)
			st.add_theme_color_override("font_color", WARN if not missing.is_empty() else ARCANE)
	# category counts
	for t in cat_buttons:
		var ready := 0
		for r in Data.recipes():
			if (t == "Todas" or r.tab == t) and world.craft_blocker(p, r.id) == "":
				ready += 1
		var tech2 := Data.tab_tech(t) if t != "Todas" else ""
		cat_buttons[t].text = "%s%s%s" % [t, ("  · %d" % ready) if ready > 0 else "", ("  (%s)" % Data.display_name(tech2)) if tech2 != "" else ""]
	_refresh_detail(p)


func _missing(p, rid: String) -> Array:
	var out := []
	var cost: Dictionary = Data.recipe(rid).get("cost", {})
	for k in cost:
		if p.inventory.count(k) < int(cost[k]):
			out.append(Data.item_name(k))
	return out


func _refresh_detail(p) -> void:
	var r := Data.recipe(craft_sel)
	det.pane.visible = not r.is_empty()
	if r.is_empty():
		return
	var structure: bool = r.get("structure", false)
	det.icon.texture = icons.get_icon(craft_sel if structure else Data.item(craft_sel).get("icon", craft_sel))
	det.name.text = Data.display_name(craft_sel)
	var item := Data.item(craft_sel)
	det.kind.text = "Estrutura · você escolhe onde colocar" if structure else (
		"Equipamento (%s)" % ("mão" if item.get("equip", "") == "hand" else "corpo") if item.has("equip") else "Item · vai para a bolsa")
	det.desc.text = Data.describe(craft_sel)
	for c in det.ing.get_children():
		c.queue_free()
	var cost: Dictionary = r.get("cost", {})
	for k in cost:
		var have: int = p.inventory.count(k)
		var need := int(cost[k])
		var row := Control.new()
		row.custom_minimum_size = Vector2(336, 30 if have >= need else 58)
		det.ing.add_child(row)
		var ic := TextureRect.new()
		ic.size = Vector2(28, 28)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.texture = icons.get_icon(Data.item(k).get("icon", k))
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(ic)
		var ok := have >= need
		_label(row, "%s %s   %d/%d" % ["✓" if ok else "✗", Data.item_name(k), mini(have, need), need], Vector2(36, 2), 14, null, OK if ok else WARN)
		if not ok:
			var where := _label(row, "Onde achar: " + String(Data.item(k).get("where", "receita ou drop")).get_slice(".", 0), Vector2(36, 22), 11, null, MUTED)
			where.size = Vector2(300, 34)
			where.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			where.max_lines_visible = 2
			row.tooltip_text = String(Data.item(k).get("where", ""))
	var tech := Data.recipe_tech(r)
	if tech == "":
		det.station.text = "Estação: nenhuma (fabrique em qualquer lugar)"
		det.station.add_theme_color_override("font_color", MUTED)
	else:
		var near: bool = world.near_structure(p, tech) != null
		det.station.text = "Estação: %s  %s" % [Data.display_name(tech), "✓ por perto" if near else "✗ longe (construa ou aproxime-se)"]
		det.station.add_theme_color_override("font_color", OK if near else ARCANE)
	var why: String = world.craft_blocker(p, craft_sel)
	det.why.text = "" if why == "" else "Bloqueado: " + why
	det.make.text = "Posicionar" if structure else "Fabricar"
	det.make.disabled = why != ""
	det.make.tooltip_text = "Escolha o lugar com o mouse; clique para confirmar, Esc cancela." if structure else "Cria o item agora."


# ---------- messages ----------

## Bottom-centre prompt for the E target; red when it can't be done.
func set_prompt(text: String, ok: bool) -> void:
	if lbl_prompt == null:
		return
	lbl_prompt.visible = text != "" and not craft_panel.visible
	lbl_prompt.text = text
	lbl_prompt.add_theme_color_override("font_color", Color(1.0, 0.92, 0.7) if ok else Color(1.0, 0.6, 0.5))


## One message at a time; repeating the same one only extends it (no flood).
func flash(m: String, seconds := 2.6) -> void:
	if m == "":
		return
	if lbl_msg.visible and lbl_msg.text == m:
		msg_t = maxf(msg_t, seconds)
		return
	lbl_msg.text = m
	lbl_msg.visible = true
	msg_t = seconds


func show_end(text: String) -> void:
	lbl_end.text = text
	lbl_end.visible = true


func hide_end() -> void:
	lbl_end.visible = false


# ---------- per-frame refresh ----------

func _process(delta: float) -> void:
	if msg_t > 0.0:
		msg_t -= delta
		if msg_t <= 0.0:
			lbl_msg.visible = false


func refresh(p, w) -> void:
	if p == null:
		return
	lbl_name.text = String(p.stats.get("name", ""))
	lbl_title.text = String(p.stats.get("title", ""))
	hp_fill.size.x = 246.0 * clampf(p.health / p.health_max, 0.0, 1.0)
	hp_fill.color = Color(0.82, 0.22, 0.28) if p.health > p.health_max * 0.3 else Color(1.0, 0.3, 0.2)
	hp_text.text = "%d / %d" % [int(ceil(p.health)), int(p.health_max)]
	var maxes := {"hunger": p.hunger_max, "mana": p.mana_max, "noise": 100.0, "wisp": 100.0, "corruption": 100.0}
	for id in meters:
		var v := float(p.get(id))
		var m: Dictionary = meters[id]
		m.fill.size.x = float(m.max_w) * clampf(v / float(maxes[id]), 0.0, 1.0)
		m.val.text = "%d" % int(v)
	_refresh_chips(p, w)
	_refresh_clock(w)
	_refresh_objective(w)
	_refresh_spells(p, w)
	for i in range(slot_views.size()):
		_fill_slot(slot_views[i], p.inventory.slots[i], str((i + 1) % 10) if i < 10 else "")
	_fill_slot(equip_views.hand, p.inventory.equip.hand)
	_fill_slot(equip_views.body, p.inventory.equip.body)
	_craft_refresh_t -= get_process_delta_time()
	if _craft_refresh_t <= 0.0 and craft_panel.visible:
		_craft_refresh_t = 0.25
		_refresh_crafting(p)
