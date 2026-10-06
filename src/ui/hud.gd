extends CanvasLayer
## Don't Starve style HUD for the local apprentice: status bars, day clock,
## the 15-slot inventory bar + hand/body equipment (icons rendered from the
## 3D items), the crafting panel with tabs and tech locks, messages and the
## end screen. Talks to the world only through world.perform() (network-ready).

const Cfg = preload("res://src/core/config.gd")
const Data = preload("res://src/core/data.gd")
const Inventory = preload("res://src/gameplay/inventory.gd")
const IconFactory = preload("res://src/ui/icon_factory.gd")
const TITLE_FONT_PATH := "res://assets/fonts/Cinzel.ttf"
const GOLD := Color(0.85, 0.7, 0.4)
const BAR_W := 170.0
const SLOT := 54.0
const ROWS := [
	["health", "Vida", Color(0.85, 0.25, 0.30)],
	["hunger", "Fome", Color(0.90, 0.70, 0.30)],
	["mana", "Mana", Color(0.35, 0.60, 0.95)],
	["corruption", "Corrupção", Color(0.60, 0.20, 0.70)],
	["wisp", "Fogo-fátuo", Color(1.00, 0.75, 0.40)],
	["noise", "Ruído", Color(0.72, 0.42, 1.00)],
]

var world = null
var title_font: Font
var icons: IconFactory
var bars := {}
var bar_values := {}
var lbl_who: Label
var lbl_clock: Label
var lbl_msg: Label
var lbl_end: Label
var slot_views: Array = []      # [{panel, icon, count, wear, sig}]
var equip_views := {}
var craft_panel: Panel
var craft_list: VBoxContainer
var craft_tab := "Ferramentas"
var craft_buttons := {}          # recipe id -> {button, cost_label, reason_label}
var tab_buttons := {}
var msg_t := 0.0
var _craft_refresh_t := 0.0


func _panel_style(alpha := 0.62, radius := 8) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.05, 0.12, alpha)
	sb.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.55)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(6)
	return sb


func _label(parent: Control, text: String, pos: Vector2, size_px: int, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	icons = IconFactory.new()
	add_child(icons)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_status(root)
	_build_inventory(root)
	_build_crafting(root)

	lbl_msg = _label(root, "", Vector2(240, 548), 20, title_font)
	lbl_msg.size = Vector2(800, 60)
	lbl_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_msg.add_theme_color_override("font_color", Color(1.0, 0.92, 0.75))
	lbl_msg.visible = false

	var hint := _label(root, "WASD mover · Q/PgUp câmera · E/Espaço agir · F/clique feitiço · Z Lume · X Escudo · 1-0 usar · botão direito ou Shift+nº: assar / combustível / largar · Tab criação · F11 tela cheia", Vector2(140, 624), 12)
	hint.size = Vector2(1000, 20)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color(0.85, 0.82, 0.75, 0.75))

	lbl_end = _label(root, "", Vector2(140, 300), 26, title_font)
	lbl_end.size = Vector2(1000, 120)
	lbl_end.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_end.add_theme_color_override("font_color", Color(1.0, 0.85, 0.55))
	lbl_end.visible = false


# ---------- status (top-left) and clock (top-right) ----------

func _build_status(root: Control) -> void:
	var panel := Panel.new()
	panel.position = Vector2(10, 10)
	panel.size = Vector2(330, 196)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _panel_style())
	root.add_child(panel)
	lbl_who = _label(root, "", Vector2(24, 14), 16, title_font)
	lbl_who.add_theme_color_override("font_color", GOLD)
	var y := 46.0
	for r in ROWS:
		var lab := _label(root, r[1], Vector2(24, y - 5), 14, title_font)
		lab.add_theme_color_override("font_color", Color(0.9, 0.85, 0.75))
		var bg := Panel.new()
		var bg_style := StyleBoxFlat.new()
		bg_style.bg_color = Color(0, 0, 0, 0.55)
		bg_style.set_corner_radius_all(5)
		bg.add_theme_stylebox_override("panel", bg_style)
		bg.position = Vector2(132, y)
		bg.size = Vector2(BAR_W, 12)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(bg)
		var bar := Panel.new()
		var bar_style := StyleBoxFlat.new()
		bar_style.bg_color = r[2]
		bar_style.set_corner_radius_all(5)
		bar.add_theme_stylebox_override("panel", bar_style)
		bar.position = Vector2(132, y)
		bar.size = Vector2(BAR_W, 12)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(bar)
		bars[r[0]] = bar
		var val := _label(root, "", Vector2(132 + BAR_W + 6, y - 4), 11)
		bar_values[r[0]] = val
		y += 24.0

	var clock := Panel.new()
	clock.position = Vector2(1060, 10)
	clock.size = Vector2(210, 64)
	clock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clock.add_theme_stylebox_override("panel", _panel_style())
	root.add_child(clock)
	lbl_clock = _label(root, "", Vector2(1072, 16), 15, title_font)
	lbl_clock.add_theme_color_override("font_color", GOLD)


# ---------- inventory bar (bottom) ----------

func _build_inventory(root: Control) -> void:
	var total := Inventory.SIZE * (SLOT + 4) + 24 + 2 * (SLOT + 4)
	var x0 := (1280.0 - total) / 2.0
	var y0 := 720.0 - SLOT - 14.0
	var back := Panel.new()
	back.position = Vector2(x0 - 8, y0 - 8)
	back.size = Vector2(total + 12, SLOT + 16)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.add_theme_stylebox_override("panel", _panel_style(0.7, 10))
	root.add_child(back)
	for i in range(Inventory.SIZE):
		var key_txt := str((i + 1) % 10) if i < 10 else ""
		slot_views.append(_slot(root, Vector2(x0 + i * (SLOT + 4), y0), key_txt, i, ""))
	var ex := x0 + Inventory.SIZE * (SLOT + 4) + 24
	equip_views["hand"] = _slot(root, Vector2(ex, y0), "Mão", -1, "hand")
	equip_views["body"] = _slot(root, Vector2(ex + SLOT + 4, y0), "Corpo", -1, "body")


func _slot(root: Control, pos: Vector2, key_txt: String, index: int, equip_where: String) -> Dictionary:
	var panel := Panel.new()
	panel.position = pos
	panel.size = Vector2(SLOT, SLOT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.16, 0.12, 0.22, 0.9) if equip_where == "" else Color(0.22, 0.16, 0.1, 0.9)
	sb.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.35)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", sb)
	root.add_child(panel)
	var icon := TextureRect.new()
	icon.position = Vector2(3, 3)
	icon.size = Vector2(SLOT - 6, SLOT - 6)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(icon)
	var key_l := _label(panel, key_txt, Vector2(3, 0), 10)
	key_l.add_theme_color_override("font_color", Color(0.8, 0.75, 0.65, 0.8))
	var count := _label(panel, "", Vector2(SLOT - 26, SLOT - 20), 13)
	count.size = Vector2(23, 18)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var wear := ColorRect.new()
	wear.position = Vector2(4, SLOT - 6)
	wear.size = Vector2(SLOT - 8, 3)
	wear.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wear.visible = false
	panel.add_child(wear)
	panel.gui_input.connect(func(ev): _on_slot_input(ev, index, equip_where))
	panel.tooltip_text = ""
	return {"panel": panel, "icon": icon, "count": count, "wear": wear, "sig": ""}


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


func _fill_slot(view: Dictionary, s) -> void:
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
		view.panel.tooltip_text = ""
		return
	var d := Data.item(s.id)
	view.icon.texture = icons.get_icon(d.get("icon", s.id))
	view.count.text = str(s.count) if s.count > 1 else ""
	view.panel.tooltip_text = d.get("name", s.id)
	var frac := -1.0
	if s.has("uses"):
		frac = s.uses / float(d.get("uses", d.get("burn", 1.0)))
	elif s.has("fresh"):
		frac = s.fresh / float(d.get("spoil", 1.0))
	view.wear.visible = frac >= 0.0
	if frac >= 0.0:
		view.wear.size.x = (SLOT - 8) * clampf(frac, 0.0, 1.0)
		view.wear.color = Color(0.9, 0.3, 0.2).lerp(Color(0.4, 0.9, 0.4), frac) if s.has("fresh") else Color(0.95, 0.85, 0.5)


# ---------- crafting panel (left) ----------

func _build_crafting(root: Control) -> void:
	craft_panel = Panel.new()
	craft_panel.position = Vector2(10, 216)
	craft_panel.size = Vector2(330, 400)
	craft_panel.add_theme_stylebox_override("panel", _panel_style(0.72))
	root.add_child(craft_panel)
	var head := _label(craft_panel, "Criação  (Tab)", Vector2(12, 6), 16, title_font)
	head.add_theme_color_override("font_color", GOLD)
	var tabs: Array = Data.tabs()
	for i in range(tabs.size()):
		var b := Button.new()
		b.text = tabs[i]
		b.position = Vector2(10 + (i % 3) * 104, 34 + int(i / 3.0) * 32)
		b.size = Vector2(100, 28)
		b.toggle_mode = true
		b.add_theme_font_size_override("font_size", 12)
		b.focus_mode = Control.FOCUS_NONE
		var tab_name: String = tabs[i]
		b.pressed.connect(func(): _select_tab(tab_name))
		craft_panel.add_child(b)
		tab_buttons[tab_name] = b
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(8, 104)
	scroll.size = Vector2(314, 288)
	craft_panel.add_child(scroll)
	craft_list = VBoxContainer.new()
	craft_list.custom_minimum_size = Vector2(300, 0)
	scroll.add_child(craft_list)
	_select_tab(craft_tab)


func toggle_crafting() -> void:
	craft_panel.visible = not craft_panel.visible


func _select_tab(tab: String) -> void:
	craft_tab = tab
	for t in tab_buttons:
		tab_buttons[t].button_pressed = t == tab
	for c in craft_list.get_children():
		c.queue_free()
	craft_buttons.clear()
	var tech := Data.tab_tech(tab)
	if tech != "":
		var lock := _label(craft_list, "Requer estar perto de: %s" % Data.display_name(tech), Vector2.ZERO, 12)
		lock.add_theme_color_override("font_color", Color(0.75, 0.65, 1.0))
	for r in Data.recipes():
		if r.tab != tab:
			continue
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(296, 58)
		btn.focus_mode = Control.FOCUS_NONE
		var rid: String = r.id
		btn.pressed.connect(func(): if world != null: world.perform(world.local_player, "craft:" + rid))
		var icon := TextureRect.new()
		icon.position = Vector2(4, 4)
		icon.size = Vector2(50, 50)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var icon_key: String = rid if r.get("structure", false) else Data.item(rid).get("icon", rid)
		icon.texture = icons.get_icon(icon_key)
		btn.add_child(icon)
		var nm := _label(btn, Data.display_name(rid), Vector2(60, 4), 15, title_font)
		nm.add_theme_color_override("font_color", Color(1.0, 0.92, 0.75))
		var parts := []
		for k in r.cost:
			parts.append("%d %s" % [int(r.cost[k]), Data.item_name(k)])
		var cost := _label(btn, ", ".join(parts), Vector2(60, 26), 11)
		cost.size = Vector2(230, 30)
		cost.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		craft_list.add_child(btn)
		craft_buttons[rid] = {"button": btn, "cost": cost}
	_craft_refresh_t = 0.0


func _refresh_crafting(p) -> void:
	for rid in craft_buttons:
		var why: String = world.craft_blocker(p, rid)
		var v: Dictionary = craft_buttons[rid]
		v.button.modulate = Color(1, 1, 1, 1) if why == "" else Color(1, 1, 1, 0.55)
		v.cost.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6) if why == "" else Color(1.0, 0.65, 0.55))


# ---------- per-frame refresh ----------

func _process(delta: float) -> void:
	if msg_t > 0.0:
		msg_t -= delta
		if msg_t <= 0.0:
			lbl_msg.visible = false


func flash(m: String, seconds := 2.6) -> void:
	if m == "":
		return
	lbl_msg.text = m
	lbl_msg.visible = true
	msg_t = seconds


func show_end(text: String) -> void:
	lbl_end.text = text
	lbl_end.visible = true


func hide_end() -> void:
	lbl_end.visible = false


func _fill(id: String, value: float, max_value: float) -> void:
	bars[id].size = Vector2(BAR_W * clampf(value, 0.0, max_value) / max_value, 12)
	bar_values[id].text = "%d" % int(value)


func refresh(p, w) -> void:
	if p == null:
		return
	_fill("health", p.health, p.health_max)
	_fill("hunger", p.hunger, p.hunger_max)
	_fill("mana", p.mana, p.mana_max)
	_fill("corruption", p.corruption, 100.0)
	_fill("wisp", p.wisp, 100.0)
	_fill("noise", p.noise, 100.0)
	lbl_who.text = "%s, %s" % [p.stats.get("name", ""), p.stats.get("title", "")]
	var dn = w.day_night
	var lit: float = dn.light()
	var phase := "Dia claro" if lit > 0.6 else ("Crepúsculo" if lit > 0.35 else "Noite")
	if dn.blood_moon:
		phase = "LUA DE SANGUE"
	var shield := ("  Escudo %.0fs" % p.shield_t) if p.shield_t > 0.0 else ""
	lbl_clock.text = "Dia %d · %s\nPortal %d/%d · Melhor: %d%s" % [dn.nights + 1, phase, w.run_hearts, Cfg.PORTAL_HEARTS, w.meta.best_nights, shield]
	for i in range(slot_views.size()):
		_fill_slot(slot_views[i], p.inventory.slots[i])
	_fill_slot(equip_views.hand, p.inventory.equip.hand)
	_fill_slot(equip_views.body, p.inventory.equip.body)
	_craft_refresh_t -= get_process_delta_time()
	if _craft_refresh_t <= 0.0 and craft_panel.visible:
		_craft_refresh_t = 0.25
		_refresh_crafting(p)
