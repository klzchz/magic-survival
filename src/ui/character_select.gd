extends CanvasLayer
## Character select (DST style): one card per apprentice in
## assets/data/characters.json with a live 3D preview (idle animation),
## perks and flaw. Emits `chosen(character_id)`.

signal chosen(character_id: String)

const Data = preload("res://src/core/data.gd")
const Models = preload("res://src/core/models.gd")
const Rig = preload("res://src/core/rig.gd")
const TITLE_FONT_PATH := "res://assets/fonts/Cinzel.ttf"
const GOLD := Color(0.85, 0.7, 0.4)
const CARD := Vector2(340, 500)

var _turntables: Array = []
var _rigs: Array = []


func _ready() -> void:
	var font: Font = load(TITLE_FONT_PATH) if ResourceLoader.exists(TITLE_FONT_PATH) else null
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.06, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var title := Label.new()
	title.text = "Escolha seu Aprendiz"
	title.position = Vector2(0, 28)
	title.size = Vector2(1280, 60)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", GOLD)
	if font != null:
		title.add_theme_font_override("font", font)
	add_child(title)

	var sub := Label.new()
	sub.text = "Presos na ilha da Névoa, longe do Colégio. Sobrevivam, dominem a magia, reabram o Portal."
	sub.position = Vector2(0, 84)
	sub.size = Vector2(1280, 30)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", Color(0.85, 0.82, 0.92))
	add_child(sub)

	var ids: Array = Data.table("characters").keys()
	var gap := 30.0
	var x0 := (1280.0 - ids.size() * CARD.x - (ids.size() - 1) * gap) / 2.0
	for i in range(ids.size()):
		_card(ids[i], Vector2(x0 + i * (CARD.x + gap), 130), font)


func _card(id: String, pos: Vector2, font: Font) -> void:
	var c := Data.character(id)
	var panel := Panel.new()
	panel.position = pos
	panel.size = CARD
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.06, 0.15, 0.95)
	sb.border_color = GOLD
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)

	# live 3D preview
	var holder := SubViewportContainer.new()
	holder.position = Vector2(20, 14)
	holder.size = Vector2(CARD.x - 40, 230)
	holder.stretch = true
	panel.add_child(holder)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	holder.add_child(vp)
	var stage := Node3D.new()
	vp.add_child(stage)
	var turn := Node3D.new()
	stage.add_child(turn)
	var model := Models.spawn(turn, c.get("model", "mage"), Vector3.ZERO, 1.1)
	if model != null:
		Models.set_parts_visible(model, c.get("hide", []), false)
		var rig := Rig.new(model)
		rig.set_base("Idle")
		_rigs.append(rig)
	_turntables.append(turn)
	var g: Array = c.get("glow", [1, 1, 1])
	var key := OmniLight3D.new()
	key.light_color = Color(g[0], g[1], g[2])
	key.light_energy = 2.0
	key.omni_range = 8.0
	key.position = Vector3(1.5, 3.0, 2.5)
	stage.add_child(key)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 20, 0)
	sun.light_energy = 0.9
	stage.add_child(sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.55, 0.75)
	var we := WorldEnvironment.new()
	we.environment = env
	stage.add_child(we)
	var cam := Camera3D.new()
	cam.fov = 32.0
	stage.add_child(cam)
	cam.position = Vector3(0, 1.8, 6.2)
	cam.look_at(Vector3(0, 1.35, 0), Vector3.UP)
	cam.current = true

	var name_l := _text(panel, "%s, %s" % [c.get("name", id), c.get("title", "")], Vector2(0, 252), 22, GOLD, font)
	name_l.size.x = CARD.x
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var y := 292.0
	for perk in c.get("perks", []):
		_text(panel, "+ " + perk, Vector2(26, y), 15, Color(0.6, 0.95, 0.6))
		y += 24.0
	_text(panel, "- " + c.get("flaw", ""), Vector2(26, y + 4), 15, Color(1.0, 0.55, 0.5))
	var btn := Button.new()
	btn.text = "Escolher %s" % c.get("name", id)
	btn.position = Vector2(60, CARD.y - 58)
	btn.size = Vector2(CARD.x - 120, 42)
	if font != null:
		btn.add_theme_font_override("font", font)
	btn.add_theme_font_size_override("font_size", 18)
	btn.pressed.connect(func(): chosen.emit(id))
	panel.add_child(btn)


func _text(parent: Control, t: String, pos: Vector2, size_px: int, color: Color, font: Font = null) -> Label:
	var l := Label.new()
	l.text = t
	l.position = pos
	l.size = Vector2(CARD.x - 40, 24)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", color)
	if font != null:
		l.add_theme_font_override("font", font)
	parent.add_child(l)
	return l


var _clock := 0.0


func _process(delta: float) -> void:
	_clock += delta
	for i in range(_turntables.size()):  # sway facing the camera, never show the back
		_turntables[i].rotation.y = sin(_clock * 0.7 + i) * 0.6
	for r in _rigs:
		r.tick(delta)
