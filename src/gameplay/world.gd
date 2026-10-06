extends Node3D
# Magical Survive - island orchestrator (Godot 4).
# Generates the island, spawns apprentices and Shadows, owns team progress
# (nights, Mist Hearts, the Arcane Portal) and the action dispatcher.
# Every apprentice action goes through perform(player, action), so Phase 2
# co-op only has to forward client input to the host with one RPC.

const Cfg = preload("res://src/core/config.gd")
const Art = preload("res://src/core/art.gd")
const Models = preload("res://src/core/models.gd")
const Fx = preload("res://src/core/fx.gd")
const MetaSave = preload("res://src/core/meta_save.gd")
const WizardScene = preload("res://scenes/wizard.tscn")
const ShadowScene = preload("res://scenes/shadow.tscn")
const GatherableScene = preload("res://scenes/gatherable.tscn")
const StructureScene = preload("res://scenes/structure.tscn")
const PortalScene = preload("res://scenes/portal.tscn")

const KEY_ACTIONS := {
	KEY_E: "interact", KEY_1: "eat", KEY_2: "feed_wisp", KEY_3: "brew", KEY_4: "cook",
	KEY_5: "campfire", KEY_6: "ward", KEY_7: "wand", KEY_8: "cauldron", KEY_9: "elixir",
	KEY_F: "lume", KEY_G: "shield", KEY_SPACE: "bolt",
}
const RECIPES := {
	"campfire": {"cost": {"wood": 2, "stone": 1}, "offset": Vector3(1.5, 0, 0),
		"ok": "Fogueira acesa (luz fixa + cozinhar)", "fail": "Fogueira: precisa 2 madeira + 1 pedra"},
	"ward": {"cost": {"bone": 2, "twig": 1}, "offset": Vector3(-1.5, 0, 0),
		"ok": "Ward de ossos fincado (Sombras não entram)", "fail": "Ward: precisa 2 ossos + 1 galho"},
	"cauldron": {"cost": {"stone": 2, "wood": 2}, "offset": Vector3(0, 0, 1.5),
		"ok": "Caldeirão montado (Elixir limpo com a tecla 9)", "fail": "Caldeirão: precisa 2 pedras + 2 madeiras"},
}
const ITEM_NAMES := {"mushroom": "cogumelo-fantasma", "twig": "galho"}

@onready var day_night = $DayNight
@onready var camera_rig = $CameraRig
@onready var hud = $HUD
@onready var players_root: Node3D = $Players
@onready var shadows_root: Node3D = $Shadows
@onready var resources_root: Node3D = $Resources
@onready var structures_root: Node3D = $Structures
@onready var decor_root: Node3D = $Decor

var meta := MetaSave.new()
var local_player = null
var portal = null
var won := false
var game_over := false
var shot_timer := -1.0     # dev: MAGIC_SHOT=1 saves user://shot.png after 3s
var shot_path := "user://shot.png"
var ambient: Node3D        # follows the local apprentice: fireflies + leaves
var fireflies: CPUParticles3D
var leaves: CPUParticles3D


func _ready() -> void:
	if OS.get_environment("MAGIC_SHOT") != "":
		shot_timer = float(OS.get_environment("MAGIC_SHOT_AT")) if OS.get_environment("MAGIC_SHOT_AT") != "" else 3.0
		if OS.get_environment("MAGIC_SHOT_PATH") != "":
			shot_path = OS.get_environment("MAGIC_SHOT_PATH")
	meta.load_from_disk()
	day_night.night_started.connect(_on_night_start)
	day_night.dawn.connect(_on_dawn)
	_build_scenery()
	local_player = add_player(1)
	camera_rig.target = local_player
	ambient = Node3D.new()
	add_child(ambient)
	fireflies = Fx.fireflies(ambient)
	leaves = Fx.leaves(ambient)
	_generate_world()
	# dev: MAGIC_TIME=<seconds> starts the clock later (e.g. 60 = first night)
	if OS.get_environment("MAGIC_TIME") != "":
		day_night.t = float(OS.get_environment("MAGIC_TIME"))


# ---------- scenery (built once: ground, grass, the forest wall) ----------

func _build_scenery() -> void:
	var scenery := Node3D.new()
	scenery.name = "Scenery"
	add_child(scenery)

	# mossy ground with autumn patches (noise texture, no image files)
	var noise := FastNoiseLite.new()
	noise.frequency = 0.012
	noise.fractal_octaves = 4
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.10, 0.17, 0.09))
	ramp.set_color(1, Color(0.30, 0.24, 0.13))
	ramp.add_point(0.45, Color(0.15, 0.25, 0.11))
	ramp.add_point(0.72, Color(0.22, 0.27, 0.12))
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.noise = noise
	tex.color_ramp = ramp
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_texture = tex
	ground_mat.roughness = 1.0
	ground_mat.uv1_scale = Vector3(3, 3, 3)
	var ground := PlaneMesh.new()
	var extent := Cfg.WORLD * 2.0 + 60.0
	ground.size = Vector2(extent, extent)
	Art.add_mesh(scenery, ground, ground_mat)

	# grass tufts (one MultiMesh draw call)
	var blade := PrismMesh.new()
	blade.size = Vector3(0.12, 0.55, 0.05)
	var grass_mat := StandardMaterial3D.new()
	grass_mat.vertex_color_use_as_albedo = true
	grass_mat.roughness = 1.0
	blade.material = grass_mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = blade
	mm.instance_count = 2400
	for i in range(mm.instance_count):
		var b := Basis(Vector3.UP, randf() * TAU).scaled(Vector3.ONE * randf_range(0.6, 1.4))
		b = b.rotated(Vector3(1, 0, 0), randf_range(-0.25, 0.25))
		mm.set_instance_transform(i, Transform3D(b, Vector3(randf_range(-Cfg.WORLD, Cfg.WORLD), 0.25, randf_range(-Cfg.WORLD, Cfg.WORLD))))
		mm.set_instance_color(i, Color(0.25, 0.42, 0.18).lerp(Color(0.6, 0.5, 0.2), randf() * 0.6))
	var grass := MultiMeshInstance3D.new()
	grass.multimesh = mm
	grass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scenery.add_child(grass)

	# the forest wall: dense trees and mountains just outside the playable square
	var edge := Cfg.WORLD + 4.0
	var step := 6.0
	var t := -edge
	while t <= edge:
		for side in [Vector3(t, 0, -edge), Vector3(t, 0, edge), Vector3(-edge, 0, t), Vector3(edge, 0, t)]:
			var jitter := Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))
			Models.spawn_variant(scenery, "border_tree", side + jitter, randf_range(1.1, 1.5))
		t += step
	# a second, darker ring of pines so the forest feels deep (hex-tile hills/mountains dropped: they read as board pieces)
	t = -edge - 8.0
	while t <= edge + 8.0:
		for side in [Vector3(t, 0, -edge - 8.0), Vector3(t, 0, edge + 8.0), Vector3(-edge - 8.0, 0, t), Vector3(edge + 8.0, 0, t)]:
			Models.spawn_variant(scenery, "border_tree", side + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2)), randf_range(1.3, 1.8))
		t += 8.0


# ---------- queries (untyped arrays so callers can duck-type entities) ----------

func _children(root: Node) -> Array:
	var out := []
	for n in root.get_children():
		out.append(n)
	return out


func players() -> Array:
	return _children(players_root)


func alive_players() -> Array:
	return players().filter(func(p): return not p.dead)


func shadows() -> Array:
	return _children(shadows_root)


func resources() -> Array:
	return _children(resources_root)


func resources_of(kind: String) -> Array:
	return resources().filter(func(g): return g.kind == kind)


func structures_of(kind: String) -> Array:
	return _children(structures_root).filter(func(s): return s.kind == kind)


func pillars() -> Array:
	return _children(decor_root).filter(func(n): return n.has_meta("ruin"))


func nearest_player(pos: Vector3):
	var best = null
	var bd := INF
	for p in alive_players():
		var flat: Vector3 = p.position - pos
		flat.y = 0.0
		if flat.length() < bd:
			bd = flat.length()
			best = p
	return best


func is_lit(pos: Vector3, lit: float) -> bool:
	if lit > 0.5:
		return true
	for p in alive_players():
		if pos.distance_to(p.position) < p.light_radius():
			return true
	for fire in structures_of("campfire"):
		if pos.distance_to(fire.position) < Cfg.FIRE_RADIUS:
			return true
	return false


# Bone wards push Shadows out to the edge of their circle.
func apply_wards(pos: Vector3) -> Vector3:
	for ward in structures_of("ward"):
		var wp: Vector3 = ward.position
		var flat := pos - wp
		flat.y = 0.0
		var d := flat.length()
		if d < Cfg.WARD_RADIUS:
			if d < 0.01:
				flat = Vector3(1, 0, 0)
			var pushed := wp + flat.normalized() * Cfg.WARD_RADIUS
			pos.x = pushed.x
			pos.z = pushed.z
	return pos


# ---------- spawning ----------

func add_player(peer_id: int):
	var w = WizardScene.instantiate()
	w.peer_id = peer_id
	w.slot = players_root.get_child_count()
	w.name = "Wizard%d" % peer_id
	players_root.add_child(w)
	w.respawn(_spawn_spot(w.slot), meta.knows("eco"))
	return w


func _spawn_spot(slot: int) -> Vector3:
	return Vector3(slot * 2.0, 0, 0)


func spawn_shadow(boss := false):
	var anchor = nearest_player(Vector3.ZERO) if local_player == null or local_player.dead else local_player
	var center: Vector3 = anchor.position if anchor != null else Vector3.ZERO
	var ang := randf_range(0.0, TAU)
	var pos := center + Vector3(cos(ang), 0, sin(ang)) * (16.0 + randf_range(4.0, 14.0))
	pos.x = clampf(pos.x, -Cfg.WORLD, Cfg.WORLD)
	pos.z = clampf(pos.z, -Cfg.WORLD, Cfg.WORLD)
	var s = ShadowScene.instantiate()
	s.setup(boss)
	pos.y = s.hover_height()
	s.position = pos
	shadows_root.add_child(s)
	return s


func spawn_structure(kind: String, pos: Vector3):
	var s = StructureScene.instantiate()
	s.setup(kind)
	s.position = pos
	structures_root.add_child(s)
	return s


func _spawn_resource(kind: String, pos: Vector3):
	var g = GatherableScene.instantiate()
	g.setup(kind)
	g.position = pos
	resources_root.add_child(g)
	return g


# Removes from the tree immediately (counts stay exact this frame), frees later.
func _despawn(n: Node) -> void:
	n.get_parent().remove_child(n)
	n.queue_free()


func _rand_pos() -> Vector3:
	return Vector3(randf_range(-Cfg.WORLD + 3.0, Cfg.WORLD - 3.0), 0.0, randf_range(-Cfg.WORLD + 3.0, Cfg.WORLD - 3.0))


func _ruins_center() -> Vector3:
	return Vector3(-Cfg.WORLD + Cfg.RUINS_RADIUS + 4.0, 0.0, -Cfg.WORLD + Cfg.RUINS_RADIUS + 4.0)


func _ruins_pos() -> Vector3:
	var ang := randf_range(0.0, TAU)
	var r := randf_range(2.5, Cfg.RUINS_RADIUS)
	return _ruins_center() + Vector3(cos(ang) * r, 0.0, sin(ang) * r)


func _generate_world() -> void:
	for root in [shadows_root, resources_root, structures_root, decor_root]:
		for n in root.get_children():
			_despawn(n)
	portal = null

	for i in range(48):
		var pos := _rand_pos()
		if pos.distance_to(_ruins_center()) < Cfg.RUINS_RADIUS + 4.0:
			continue  # keep the ruins clearing open
		_spawn_resource("tree", pos)
	for i in range(20):
		_spawn_resource("rock", _rand_pos())
	for i in range(40):
		_spawn_resource("mushroom", _rand_pos())
	for i in range(34):
		_spawn_resource("twig", _rand_pos())

	# Ruins of the Fallen College: broken pillars, graves, candles, a crypt
	var pillar_mat := Art.mat(Color(0.55, 0.53, 0.58))
	for i in range(16):
		var piece := Models.spawn_variant(decor_root, "ruin", _ruins_pos())
		if piece == null:
			piece = Art.add_mesh(decor_root, Art.cylinder(0.5, 0.6, 4.0), pillar_mat, _ruins_pos() + Vector3(0, 2.0, 0))
			piece.rotation_degrees.z = randf_range(-14.0, 14.0)
		piece.set_meta("ruin", true)
	var crypt := Models.spawn(decor_root, "crypt", _ruins_center() + Vector3(-9.0, 0, -9.0))
	if crypt != null:
		crypt.rotation.y = PI * 0.25
		crypt.set_meta("ruin", true)
	for i in range(6):
		var c := Models.spawn_variant(decor_root, "ruin", _ruins_pos()) if i > 3 else Models.spawn(decor_root, ["candles", "skull_candle", "lantern"].pick_random(), _ruins_pos())
		if c != null and i <= 3:
			Art.add_light(c, Color(1.0, 0.7, 0.35), 4.0, 0.9, Vector3(0, 1.0, 0))

	# litter across the island: pumpkins, bones, grave markers, small hills
	for i in range(60):
		var pos := _rand_pos()
		if pos.distance_to(_ruins_center()) < Cfg.RUINS_RADIUS or pos.length() < 5.0:
			continue
		Models.spawn_variant(decor_root, "litter", pos)
	for i in range(5):
		var jack := Models.spawn(decor_root, "jackolantern", _rand_pos())
		if jack != null:
			Art.add_light(jack, Color(1.0, 0.55, 0.15), 5.0, 1.1, Vector3(0, 0.8, 0))
	for i in range(3):
		_spawn_resource("page", _ruins_pos())
	portal = PortalScene.instantiate()
	portal.position = _ruins_center()
	decor_root.add_child(portal)


func restart() -> void:
	won = false
	game_over = false
	day_night.reset()
	for p in players():
		p.respawn(_spawn_spot(p.slot), meta.knows("eco"))
	hud.hide_end()
	_generate_world()


# ---------- main loop ----------

func _process(delta: float) -> void:
	tick(delta)


func tick(delta: float) -> void:
	if won or game_over:
		camera_rig.follow(delta)
		return

	day_night.advance(delta)
	var lit: float = day_night.light()
	if local_player != null and not local_player.dead:
		_drive_local(delta)
	for p in players():
		if not p.dead:
			p.tick_stats(delta)
		p.update_wisp_light(lit)
	day_night.apply_visuals(lit)
	if local_player != null:
		ambient.position = local_player.position
	fireflies.emitting = lit < 0.45
	leaves.emitting = lit > 0.5

	# Shadows rise at night; corruption and the Blood Moon make them thicker
	if lit < 0.35 and shadows_root.get_child_count() < Cfg.SHADOW_CAP:
		var rate := 0.5 + _team_corruption() * 0.03
		if day_night.blood_moon:
			rate *= 2.0
		if randf() < rate * delta:
			spawn_shadow()

	for s in shadows():
		s.tick(delta, self, lit, day_night.t)
		if s.hp <= 0.0:
			_on_shadow_death(s)

	_check_deaths()

	if shot_timer > 0.0:
		shot_timer -= delta
		if shot_timer <= 0.0:
			get_viewport().get_texture().get_image().save_png(shot_path)
			print("MAGIC_SHOT saved: ", shot_path)

	camera_rig.follow(delta)
	hud.refresh(local_player, self)


func _drive_local(delta: float) -> void:
	var mv := Vector3.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		mv += camera_rig.forward()
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		mv -= camera_rig.forward()
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		mv += camera_rig.right()
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		mv -= camera_rig.right()
	local_player.move(mv, delta)
	# camera rotate (Don't Starve style): Q left, PageUp right (E interacts)
	if Input.is_key_pressed(KEY_Q):
		camera_rig.angle -= 1.4 * delta
	if Input.is_key_pressed(KEY_PAGEUP):
		camera_rig.angle += 1.4 * delta


func _team_corruption() -> float:
	var alive := alive_players()
	if alive.is_empty():
		return 0.0
	var total := 0.0
	for p in alive:
		total += p.corruption
	return total / alive.size()


func _check_deaths() -> void:
	for p in players():
		if p.health <= 0.0 and not p.dead:
			p.die()
			_say(p, "Você caiu. Seus companheiros seguem.")
	if alive_players().is_empty() and not game_over:
		game_over = true
		meta.record_nights(day_night.nights)
		hud.show_end("VOCÊ VIROU ADUBO. Sobreviveu %d noites (melhor: %d)\nO que você aprendeu permanece. R para renascer noutra ilha" % [day_night.nights, meta.best_nights])


func _on_night_start(blood_moon: bool) -> void:
	if blood_moon:
		_announce("LUA DE SANGUE! Algo grande caça vocês esta noite.")
		spawn_shadow(true)
	else:
		_announce("A Névoa desce. Mantenha o fogo-fátuo aceso.")


func _on_dawn(nights: int) -> void:
	meta.record_nights(nights)
	_announce("Amanheceu. Noites sobrevividas: %d" % nights)


func _on_shadow_death(s) -> void:
	var who = s.last_hitter
	if who != null and not is_instance_valid(who):
		who = null
	if s.boss:
		meta.hearts += 1
		meta.save()
		if who == null:
			who = nearest_player(s.position)
		if who != null:
			who.gain({"bone": 5})
		_announce("O CORAÇÃO DA NÉVOA CAIU! +5 ossos (corações: %d/%d p/ o Portal)" % [meta.hearts, Cfg.PORTAL_HEARTS])
	elif who != null:
		who.gain({"bone": 1})
		_say(who, "A Sombra deixou um osso")
	_despawn(s)


# ---------- messages ----------

func _say(p, text: String) -> void:
	if p == local_player:
		hud.flash(text)


func _announce(text: String) -> void:
	hud.flash(text)


# ---------- actions ----------

func perform(p, action: String) -> void:
	if p == null or p.dead or won or game_over:
		return
	match action:
		"interact":
			_interact(p)
		"eat":
			p.play_action("use")
			_say(p, p.eat())
		"feed_wisp":
			p.play_action("use")
			_say(p, p.feed_wisp())
		"brew":
			p.play_action("use")
			_say(p, p.brew())
		"cook":
			p.play_action("build")
			_say(p, p.cook() if _near(p, "campfire") else "Precisa estar perto de uma fogueira")
		"elixir":
			p.play_action("use")
			_say(p, p.brew_elixir() if _near(p, "cauldron") else "Precisa estar perto de um caldeirão")
		"wand":
			p.play_action("build")
			_say(p, p.upgrade_wand())
		"campfire", "ward", "cauldron":
			_build(p, action)
		"lume":
			_cast_lume(p)
		"shield":
			_cast_shield(p)
		"bolt":
			_cast_bolt(p)


func _near(p, kind: String) -> bool:
	for s in structures_of(kind):
		if p.position.distance_to(s.position) < s.radius():
			return true
	return false


func _build(p, kind: String) -> void:
	var recipe: Dictionary = RECIPES[kind]
	if not p.pay(recipe.cost):
		_say(p, recipe.fail)
		return
	spawn_structure(kind, p.position + recipe.offset)
	p.play_action("build")
	_say(p, recipe.ok)


func _interact(p) -> void:
	# E: pick up reagents/pages, strike trees/rocks, or touch the Portal
	var best = null
	var bd := Cfg.INTERACT_RADIUS
	for g in resources():
		var d: float = p.position.distance_to(g.position)
		if d < bd:
			bd = d
			best = g
	if portal != null:
		var pd: float = p.position.distance_to(portal.position)
		if pd < Cfg.PORTAL_RADIUS and pd < bd:
			_try_portal(p)
			return
	if best == null:
		_say(p, "Nada por perto")
		return

	var kind: String = best.kind
	p.face(best.position)
	p.play_action("chop" if kind == "tree" or kind == "rock" else "pickup")
	if not best.strike():
		_say(p, "Golpeou a %s (%d)" % ["árvore" if kind == "tree" else "pedra", best.hp])
		return
	_despawn(best)
	match kind:
		"page":
			_learn_next_spell(p)
		"tree":
			p.gain(best.gives())
			_say(p, "Árvore caiu: +2 madeira")
		"rock":
			p.gain(best.gives())
			_say(p, "Pedra quebrou: +2 pedra")
		_:
			p.gain(best.gives())
			_say(p, "+1 " + ITEM_NAMES.get(kind, kind))


func _learn_next_spell(p) -> void:
	match meta.learn_next():
		"lume":
			_announce("Aprenderam LUME (F): explosão de luz que queima Sombras próximas")
		"escudo":
			_announce("Aprenderam ESCUDO (G): barreira que bloqueia dano por 6s")
		"eco":
			for q in players():
				q.apply_meta(true)
			_announce("Aprenderam ECO ARCANO: mana máxima cresce para 130")
		_:
			p.gain({"bone": 1})
			_say(p, "Página em branco... virou pó de osso (+1 osso)")


func _try_portal(p) -> void:
	if meta.hearts < Cfg.PORTAL_HEARTS:
		_say(p, "O Portal dorme. Precisa de %d Corações da Névoa (tem %d): mate o horror da Lua de Sangue" % [Cfg.PORTAL_HEARTS, meta.hearts])
		return
	meta.hearts -= Cfg.PORTAL_HEARTS
	won = true
	for q in alive_players():
		q.celebrate()
	meta.record_nights(day_night.nights)
	meta.save()
	hud.show_end("O PORTAL SE REABRE: vocês encontraram o caminho de volta à escola.\nSobreviveram %d noites. R para uma nova ilha (o saber permanece)" % day_night.nights)


func _cast_bolt(p) -> void:
	var cost: float = p.spell_cost()
	if p.mana < cost:
		_say(p, "Mana insuficiente")
		return
	p.mana -= cost
	p.corrupt(5.0)
	var best = null
	var bd := 16.0
	for s in shadows():
		var d: float = s.position.distance_to(p.position)
		if d < bd:
			bd = d
			best = s
	if best == null:
		p.play_action("bolt")
		_say(p, "Feitiço lançado no vazio")
		return
	best.hp -= p.spell_damage()
	best.last_hitter = p
	p.face(best.position)
	p.play_action("bolt")
	_say(p, "Feitiço atinge a Sombra" + (" GRANDE" if best.boss else ""))


func _cast_lume(p) -> void:
	if not meta.knows("lume"):
		_say(p, "Vocês ainda não conhecem LUME (ache páginas nas Ruínas)")
		return
	if p.mana < 15.0:
		_say(p, "Mana insuficiente")
		return
	p.mana -= 15.0
	p.corrupt(3.0)
	var burned := 0
	for s in shadows():
		if s.position.distance_to(p.position) < 10.0:
			s.hp -= 50.0
			s.last_hitter = p
			burned += 1
	p.wisp = minf(100.0, p.wisp + 10.0)
	p.play_action("lume")
	_say(p, "LUME! Luz explode (%d Sombras queimadas)" % burned)


func _cast_shield(p) -> void:
	if not meta.knows("escudo"):
		_say(p, "Vocês ainda não conhecem ESCUDO (ache páginas nas Ruínas)")
		return
	if p.mana < 25.0:
		_say(p, "Mana insuficiente")
		return
	p.mana -= 25.0
	p.shield_t = 6.0
	p.play_action("shield")
	_say(p, "ESCUDO! Nada te toca por 6 segundos")


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		if key.keycode == KEY_R and (won or game_over):
			restart()
		elif KEY_ACTIONS.has(key.keycode):
			perform(local_player, KEY_ACTIONS[key.keycode])
		return
	var mouse := event as InputEventMouseButton
	if mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
		perform(local_player, "bolt")
