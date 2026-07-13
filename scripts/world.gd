extends Spatial
# Magic Survival — 3D wizard-survival prototype (Godot 3.5), Don't Starve model.
# Original witchcraft universe (no licensed IP): an apprentice thrown out of a
# fallen college of sorcery through a broken arcane portal. Learn spells from
# grimoire pages, brew in the cauldron, survive the Blood Moon, gather Mist
# Hearts and reopen the Portal to find your way back to the school.
# Everything is built in code so the project runs with zero external assets.

const WORLD := 60.0        # ground half-extent (world spans -WORLD..WORLD on X/Z)
const SPEED := 8.0         # player move speed (units/s)
const DAY_LENGTH := 90.0   # seconds for a full day-night cycle
const FIRE_RADIUS := 9.0   # campfire light/burn radius
const WARD_RADIUS := 6.0   # bone ward repel radius
const RUINS_RADIUS := 12.0 # fallen-college ruins area radius
const PORTAL_HEARTS := 3   # Mist Hearts needed to reopen the Arcane Portal
const SAVE_PATH := "user://magic_survival_meta.json"
const SPELL_ORDER := ["lume", "escudo", "eco"]

# --- scene refs (created in _ready) ---
var player : Spatial
var cam : Camera
var sun : DirectionalLight
var wisp_light : OmniLight
var env : Environment

# --- player stats ---
var hunger := 100.0
var health := 100.0
var mana := 100.0
var mana_max := 100.0
var corruption := 0.0
var wisp := 100.0          # light fuel
var inv := {}              # set in _reset_inventory()
var wand_level := 0        # 0 = twig wand, 1 = bone wand
var shield_t := 0.0        # seconds of Escudo remaining

# --- world entities ---
var mushrooms := []        # Array of MeshInstance
var twigs := []            # Array of MeshInstance
var trees := []            # Array of {node, hp}
var rocks := []            # Array of {node, hp}
var shadows := []          # Array of {node, hp, boss, spell}
var campfires := []        # Array of Spatial (with OmniLight child)
var wards := []            # Array of Spatial
var cauldrons := []        # Array of Spatial
var pages := []            # Array of MeshInstance (grimoire pages, in the ruins)
var pillars := []          # Array of MeshInstance (ruins decoration)
var portal : Spatial       # the Arcane Portal (win condition)

# --- shared mesh resources ---
var mush_mesh : SphereMesh
var twig_mesh : CubeMesh
var trunk_mesh : CylinderMesh
var foliage_mesh : SphereMesh
var rock_mesh : SphereMesh
var shadow_mesh : SphereMesh
var boss_mesh : SphereMesh
var fire_mesh : CylinderMesh
var ward_mesh : CylinderMesh
var pillar_mesh : CylinderMesh
var page_mesh : CubeMesh
var cauldron_mesh : CylinderMesh

# --- state ---
var t := 0.0
var cam_angle := 0.0       # radians, Don't Starve style rotation
var prev_night := false
var nights := 0
var blood_moon := false
var dead := false
var won := false
var msg_t := 0.0

# --- meta progression (persists across runs) ---
var best_nights := 0
var hearts := 0
var spells := []           # learned spell ids; knowledge survives death

# --- HUD refs ---
var bars := {}
var lbl_stats : Label
var lbl_msg : Label
var lbl_end : Label


func _ready() -> void:
	randomize()
	_load_meta()
	_apply_meta()
	_reset_inventory()
	_build_environment()
	_build_player()
	_build_camera()
	_build_hud()
	_prepare_meshes()
	_generate_world()


func _reset_inventory() -> void:
	inv = {"mushroom": 0, "cooked": 0, "twig": 0, "wood": 0, "stone": 0, "bone": 0}


# ---------- meta save / load ----------

func _load_meta() -> void:
	var f := File.new()
	if f.file_exists(SAVE_PATH) and f.open(SAVE_PATH, File.READ) == OK:
		var data = parse_json(f.get_as_text())
		f.close()
		if typeof(data) == TYPE_DICTIONARY:
			best_nights = int(data.get("best_nights", 0))
			hearts = int(data.get("hearts", 0))
			var sp = data.get("spells", [])
			if typeof(sp) == TYPE_ARRAY:
				spells = sp


func _save_meta() -> void:
	var f := File.new()
	if f.open(SAVE_PATH, File.WRITE) == OK:
		f.store_string(to_json({"best_nights": best_nights, "hearts": hearts, "spells": spells}))
		f.close()


func _apply_meta() -> void:
	# Eco Arcano deepens the mana pool permanently
	mana_max = 130.0 if "eco" in spells else 100.0
	mana = min(mana, mana_max)


# ---------- builders ----------

func _mat(c: Color, unshaded := false) -> SpatialMaterial:
	var m := SpatialMaterial.new()
	m.albedo_color = c
	m.roughness = 0.95
	m.flags_unshaded = unshaded
	return m


func _emissive_mat(c: Color, glow: Color) -> SpatialMaterial:
	var m := _mat(c)
	m.emission_enabled = true
	m.emission = glow
	m.emission_energy = 1.4
	return m


func _spawn_mesh(mesh: Mesh, material: SpatialMaterial, pos: Vector3) -> MeshInstance:
	var mi := MeshInstance.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.translation = pos
	add_child(mi)
	return mi


func _build_environment() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.5, 0.65, 0.85)
	env.ambient_light_color = Color(0.6, 0.62, 0.72)
	env.ambient_light_energy = 1.0
	env.fog_enabled = true
	env.fog_color = Color(0.5, 0.6, 0.72)
	env.fog_depth_begin = 22.0
	env.fog_depth_end = 62.0
	we.environment = env
	add_child(we)

	sun = DirectionalLight.new()
	sun.rotation_degrees = Vector3(-55, -40, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)

	# ground
	var pm := PlaneMesh.new()
	pm.size = Vector2(WORLD * 2.0, WORLD * 2.0)
	_spawn_mesh(pm, _mat(Color(0.22, 0.30, 0.19)), Vector3.ZERO)


func _build_player() -> void:
	player = Spatial.new()
	add_child(player)

	var body := MeshInstance.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.42
	cyl.bottom_radius = 0.55
	cyl.height = 1.4
	body.mesh = cyl
	body.material_override = _mat(Color(0.80, 0.78, 0.90))
	body.translation.y = 0.7
	player.add_child(body)

	var hat := MeshInstance.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.02
	cone.bottom_radius = 0.62
	cone.height = 1.0
	hat.mesh = cone
	hat.material_override = _mat(Color(0.22, 0.16, 0.32))
	hat.translation.y = 1.75
	player.add_child(hat)

	wisp_light = OmniLight.new()
	wisp_light.translation = Vector3(0, 1.5, 0)
	wisp_light.light_color = Color(1.0, 0.8, 0.5)
	wisp_light.omni_range = 12.0
	wisp_light.light_energy = 1.5
	player.add_child(wisp_light)


func _build_camera() -> void:
	cam = Camera.new()
	cam.projection = Camera.PROJECTION_ORTHOGONAL
	cam.size = 22.0
	cam.far = 200.0
	add_child(cam)
	cam.current = true


func _prepare_meshes() -> void:
	mush_mesh = SphereMesh.new()
	mush_mesh.radius = 0.35
	mush_mesh.height = 0.7

	twig_mesh = CubeMesh.new()
	twig_mesh.size = Vector3(0.12, 0.12, 0.85)

	trunk_mesh = CylinderMesh.new()
	trunk_mesh.top_radius = 0.3
	trunk_mesh.bottom_radius = 0.42
	trunk_mesh.height = 3.0

	foliage_mesh = SphereMesh.new()
	foliage_mesh.radius = 1.7
	foliage_mesh.height = 3.4

	rock_mesh = SphereMesh.new()
	rock_mesh.radius = 0.75
	rock_mesh.height = 1.0

	shadow_mesh = SphereMesh.new()
	shadow_mesh.radius = 0.7
	shadow_mesh.height = 1.4

	boss_mesh = SphereMesh.new()
	boss_mesh.radius = 1.8
	boss_mesh.height = 3.6

	fire_mesh = CylinderMesh.new()
	fire_mesh.top_radius = 0.15
	fire_mesh.bottom_radius = 0.6
	fire_mesh.height = 0.9

	ward_mesh = CylinderMesh.new()
	ward_mesh.top_radius = 0.08
	ward_mesh.bottom_radius = 0.22
	ward_mesh.height = 1.6

	pillar_mesh = CylinderMesh.new()
	pillar_mesh.top_radius = 0.5
	pillar_mesh.bottom_radius = 0.6
	pillar_mesh.height = 4.0

	page_mesh = CubeMesh.new()
	page_mesh.size = Vector3(0.5, 0.06, 0.65)

	cauldron_mesh = CylinderMesh.new()
	cauldron_mesh.top_radius = 0.7
	cauldron_mesh.bottom_radius = 0.5
	cauldron_mesh.height = 0.8


func _rand_pos() -> Vector3:
	return Vector3(rand_range(-WORLD + 3.0, WORLD - 3.0), 0.0, rand_range(-WORLD + 3.0, WORLD - 3.0))


func _ruins_center() -> Vector3:
	return Vector3(-WORLD + RUINS_RADIUS + 4.0, 0.0, -WORLD + RUINS_RADIUS + 4.0)


func _ruins_pos() -> Vector3:
	var ang := rand_range(0.0, TAU)
	var r := rand_range(2.5, RUINS_RADIUS)
	return _ruins_center() + Vector3(cos(ang) * r, 0.0, sin(ang) * r)


func _generate_world() -> void:
	# clear old entities
	for n in mushrooms + twigs + campfires + wards + cauldrons + pages + pillars:
		if is_instance_valid(n):
			n.queue_free()
	for e in trees + rocks + shadows:
		if is_instance_valid(e.node):
			e.node.queue_free()
	if portal != null and is_instance_valid(portal):
		portal.queue_free()
	mushrooms = []
	twigs = []
	trees = []
	rocks = []
	shadows = []
	campfires = []
	wards = []
	cauldrons = []
	pages = []
	pillars = []
	portal = null

	var trunk_mat := _mat(Color(0.34, 0.24, 0.16))
	var foliage_mat := _mat(Color(0.11, 0.30, 0.15))
	var mush_mat := _emissive_mat(Color(0.70, 0.85, 1.0), Color(0.35, 0.55, 0.9))
	var twig_mat := _mat(Color(0.50, 0.38, 0.24))
	var rock_mat := _mat(Color(0.45, 0.46, 0.50))
	var pillar_mat := _mat(Color(0.55, 0.53, 0.58))
	var page_mat := _emissive_mat(Color(0.95, 0.9, 0.6), Color(0.9, 0.75, 0.2))

	for i in range(48):
		var pos := _rand_pos()
		if pos.distance_to(_ruins_center()) < RUINS_RADIUS + 4.0:
			continue  # keep the ruins clearing open
		var tr := Spatial.new()
		tr.translation = pos
		add_child(tr)
		var trunk := MeshInstance.new()
		trunk.mesh = trunk_mesh
		trunk.material_override = trunk_mat
		trunk.translation.y = 1.5
		tr.add_child(trunk)
		var foliage := MeshInstance.new()
		foliage.mesh = foliage_mesh
		foliage.material_override = foliage_mat
		foliage.translation.y = 3.6
		tr.add_child(foliage)
		trees.append({"node": tr, "hp": 3})

	for i in range(20):
		var r := _spawn_mesh(rock_mesh, rock_mat, _rand_pos() + Vector3(0, 0.35, 0))
		rocks.append({"node": r, "hp": 2})

	for i in range(40):
		mushrooms.append(_spawn_mesh(mush_mesh, mush_mat, _rand_pos() + Vector3(0, 0.35, 0)))

	for i in range(34):
		twigs.append(_spawn_mesh(twig_mesh, twig_mat, _rand_pos() + Vector3(0, 0.08, 0)))

	# --- Ruins of the Fallen College: pillars, grimoire pages, the Portal ---
	for i in range(10):
		var p := _spawn_mesh(pillar_mesh, pillar_mat, _ruins_pos() + Vector3(0, 2.0, 0))
		p.rotation_degrees.z = rand_range(-14.0, 14.0)  # broken, leaning
		pillars.append(p)

	for i in range(3):
		pages.append(_spawn_mesh(page_mesh, page_mat, _ruins_pos() + Vector3(0, 0.35, 0)))

	_build_portal()


func _build_portal() -> void:
	# a dormant arch of stone; feed it Mist Hearts to reopen the way back
	portal = Spatial.new()
	portal.translation = _ruins_center()
	add_child(portal)
	var arch_mat := _emissive_mat(Color(0.35, 0.3, 0.5), Color(0.45, 0.25, 0.9))
	for side in [-1.5, 1.5]:
		var post := MeshInstance.new()
		post.mesh = pillar_mesh
		post.material_override = arch_mat
		post.translation = Vector3(side, 2.0, 0)
		portal.add_child(post)
	var top := MeshInstance.new()
	var beam := CubeMesh.new()
	beam.size = Vector3(4.2, 0.7, 0.9)
	top.mesh = beam
	top.material_override = arch_mat
	top.translation = Vector3(0, 4.2, 0)
	portal.add_child(top)
	var glow := OmniLight.new()
	glow.translation = Vector3(0, 2.2, 0)
	glow.light_color = Color(0.6, 0.35, 1.0)
	glow.omni_range = 7.0
	glow.light_energy = 0.9
	portal.add_child(glow)


func _reset() -> void:
	hunger = 100.0
	health = 100.0
	corruption = 0.0
	wisp = 100.0
	wand_level = 0
	shield_t = 0.0
	_apply_meta()
	mana = mana_max
	_reset_inventory()
	t = 0.0
	nights = 0
	blood_moon = false
	dead = false
	won = false
	prev_night = false
	player.translation = Vector3.ZERO
	lbl_end.visible = false
	_generate_world()


# ---------- main loop ----------

func _day_light() -> float:
	# 0.0 = deep night, 1.0 = midday. Phase 0 = morning: the first day is a
	# grace period to learn the loop (Don't Starve rule), night comes later.
	var phase := fmod(t, DAY_LENGTH) / DAY_LENGTH
	return clamp(0.5 + 0.5 * sin(phase * TAU + PI / 6.0), 0.0, 1.0)


func _process(delta: float) -> void:
	if dead or won:
		_update_camera(delta)
		return

	t += delta
	var lit := _day_light()

	# --- movement (camera-relative, XZ plane) ---
	var off := Vector3(sin(cam_angle), 0, cos(cam_angle))
	var forward := (-off).normalized()
	var right := forward.cross(Vector3.UP).normalized()
	var mv := Vector3.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		mv += forward
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		mv -= forward
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		mv += right
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		mv -= right
	if mv.length() > 0.01:
		player.translation += mv.normalized() * SPEED * delta
		player.translation.x = clamp(player.translation.x, -WORLD, WORLD)
		player.translation.z = clamp(player.translation.z, -WORLD, WORLD)

	# camera rotate (Don't Starve style): Q left, PageUp right (E is used to interact)
	if Input.is_key_pressed(KEY_Q):
		cam_angle -= 1.4 * delta
	if Input.is_key_pressed(KEY_PAGEUP):
		cam_angle += 1.4 * delta

	# --- stat decay ---
	hunger = max(0.0, hunger - 1.2 * delta)
	if hunger <= 0.0:
		health = max(0.0, health - 3.0 * delta)
	mana = min(mana_max, mana + 4.0 * delta)
	wisp = max(0.0, wisp - 2.0 * delta)
	corruption = max(0.0, corruption - 0.4 * delta)
	shield_t = max(0.0, shield_t - delta)

	# --- day/night visuals ---
	sun.light_energy = 0.12 + lit * 1.15
	env.ambient_light_energy = 0.15 + lit * 0.85
	var sky_night := Color(0.05, 0.06, 0.11)
	if blood_moon:
		sky_night = Color(0.16, 0.03, 0.05)
	var sky_day := Color(0.5, 0.65, 0.85)
	env.background_color = sky_night.linear_interpolate(sky_day, lit)
	env.fog_color = env.background_color
	wisp_light.light_energy = (1.0 - lit) * (0.5 + wisp * 0.02)
	wisp_light.omni_range = 4.0 + wisp * 0.10

	var night := lit < 0.35
	if night and not prev_night:
		_on_night_start()
	elif prev_night and not night:
		_on_dawn()
	prev_night = night

	# --- shadows spawn at night ---
	var cap := 40
	if night and shadows.size() < cap:
		var spawn_rate := 0.5 + corruption * 0.03
		if blood_moon:
			spawn_rate *= 2.0
		if randf() < spawn_rate * delta:
			_spawn_shadow()

	# --- shadow behaviour ---
	var survivors := []
	for s in shadows:
		var sp : Vector3 = s.node.translation
		var to_p := player.translation - sp
		to_p.y = 0
		var d := to_p.length()
		if _in_light(sp, lit):
			s.hp -= 22.0 * delta
		else:
			var speed := 3.6
			if s.boss:
				speed = 2.6
			sp += to_p.normalized() * speed * delta
			sp = _apply_wards(sp)
			sp.y = (1.8 if s.boss else 1.0) + sin(t * 3.0 + s.hp) * 0.2
			s.node.translation = sp
			var reach := 2.4 if s.boss else 1.4
			if d < reach and shield_t <= 0.0:
				var dps := 25.0 if s.boss else 14.0
				health = max(0.0, health - dps * delta)
				corruption = min(100.0, corruption + 4.0 * delta)
		if s.hp > 0.0:
			survivors.append(s)
		else:
			_on_shadow_death(s)
	shadows = survivors

	if health <= 0.0 and not dead:
		dead = true
		if nights > best_nights:
			best_nights = nights
			_save_meta()
		lbl_end.visible = true
		lbl_end.text = "VOCÊ VIROU ADUBO. Sobreviveu %d noites (melhor: %d)\nO que você aprendeu permanece. R para renascer noutra ilha" % [nights, best_nights]

	if msg_t > 0.0:
		msg_t -= delta
		if msg_t <= 0.0:
			lbl_msg.visible = false

	_update_camera(delta)
	_update_hud()


func _on_night_start() -> void:
	var night_index := nights + 1
	blood_moon = (night_index % 3 == 0)
	if blood_moon:
		_flash("🌒 LUA DE SANGUE! Algo grande caça você esta noite.")
		_spawn_shadow(true)
	else:
		_flash("A Névoa desce. Mantenha o fogo-fátuo aceso.")


func _on_dawn() -> void:
	nights += 1
	blood_moon = false
	if nights > best_nights:
		best_nights = nights
		_save_meta()
	_flash("Amanheceu. Noites sobrevividas: %d" % nights)


func _in_light(pos: Vector3, lit: float) -> bool:
	if lit > 0.5:
		return true
	var pd := pos.distance_to(player.translation)
	if pd < wisp_light.omni_range:
		return true
	for fire in campfires:
		if pos.distance_to(fire.translation) < FIRE_RADIUS:
			return true
	return false


func _apply_wards(pos: Vector3) -> Vector3:
	# bone wards push shadows out to the edge of their circle
	for ward in wards:
		var wp : Vector3 = ward.translation
		var flat := pos - wp
		flat.y = 0
		var d := flat.length()
		if d < WARD_RADIUS:
			if d < 0.01:
				flat = Vector3(1, 0, 0)
				d = 1.0
			var pushed := wp + flat.normalized() * WARD_RADIUS
			pos.x = pushed.x
			pos.z = pushed.z
	return pos


func _on_shadow_death(s: Dictionary) -> void:
	if s.boss:
		hearts += 1
		inv.bone += 5
		_save_meta()
		_flash("💜 O CORAÇÃO DA NÉVOA CAIU! +5 ossos (corações: %d/%d p/ o Portal)" % [hearts, PORTAL_HEARTS])
	elif s.get("spell", false):
		inv.bone += 1
		_flash("A Sombra deixou um osso")
	s.node.queue_free()


func _update_camera(_delta: float) -> void:
	var off := Vector3(sin(cam_angle), 0, cos(cam_angle)) * 20.0
	cam.translation = player.translation + off + Vector3(0, 22, 0)
	cam.look_at(player.translation + Vector3(0, 1, 0), Vector3.UP)


func _spawn_shadow(boss := false) -> void:
	var ang := rand_range(0.0, TAU)
	var dist := 16.0 + rand_range(4.0, 14.0)
	var pos := player.translation + Vector3(cos(ang), 0, sin(ang)) * dist
	pos.x = clamp(pos.x, -WORLD, WORLD)
	pos.z = clamp(pos.z, -WORLD, WORLD)
	pos.y = 1.8 if boss else 1.0
	var mesh := boss_mesh if boss else shadow_mesh
	var color := Color(0.12, 0.01, 0.04) if boss else Color(0.05, 0.02, 0.09)
	var mi := _spawn_mesh(mesh, _mat(color, true), pos)
	shadows.append({"node": mi, "hp": 200.0 if boss else 40.0, "boss": boss, "spell": false})


# ---------- actions ----------

func _pt(kind: String) -> String:
	match kind:
		"mushroom": return "cogumelo-fantasma"
		"cooked": return "cogumelo assado"
		"twig": return "galho"
		"wood": return "madeira"
		"stone": return "pedra"
		"bone": return "osso"
	return kind


func _interact() -> void:
	# E: pick up reagents/pages, strike trees/rocks, or touch the Portal
	var best = null
	var bd := 2.8
	var kind := ""
	for mi in mushrooms:
		var d = mi.translation.distance_to(player.translation)
		if d < bd:
			bd = d
			best = mi
			kind = "mushroom"
	for mi in twigs:
		var d = mi.translation.distance_to(player.translation)
		if d < bd:
			bd = d
			best = mi
			kind = "twig"
	for mi in pages:
		var d = mi.translation.distance_to(player.translation)
		if d < bd:
			bd = d
			best = mi
			kind = "page"
	for e in trees:
		var d = e.node.translation.distance_to(player.translation)
		if d < bd:
			bd = d
			best = e
			kind = "tree"
	for e in rocks:
		var d = e.node.translation.distance_to(player.translation)
		if d < bd:
			bd = d
			best = e
			kind = "rock"
	if portal != null:
		var d = portal.translation.distance_to(player.translation)
		if d < 3.5 and d < bd:
			best = portal
			kind = "portal"

	if best == null:
		_flash("Nada por perto")
		return

	match kind:
		"mushroom":
			inv.mushroom += 1
			mushrooms.erase(best)
			best.queue_free()
			_flash("+1 " + _pt("mushroom"))
		"twig":
			inv.twig += 1
			twigs.erase(best)
			best.queue_free()
			_flash("+1 " + _pt("twig"))
		"page":
			pages.erase(best)
			best.queue_free()
			_learn_next_spell()
		"tree":
			best.hp -= 1
			if best.hp <= 0:
				inv.wood += 2
				trees.erase(best)
				best.node.queue_free()
				_flash("Árvore caiu: +2 madeira")
			else:
				_flash("Golpeou a árvore (%d)" % best.hp)
		"rock":
			best.hp -= 1
			if best.hp <= 0:
				inv.stone += 2
				rocks.erase(best)
				best.node.queue_free()
				_flash("Pedra quebrou: +2 pedra")
			else:
				_flash("Golpeou a pedra (%d)" % best.hp)
		"portal":
			_try_portal()


func _learn_next_spell() -> void:
	for id in SPELL_ORDER:
		if not (id in spells):
			spells.append(id)
			_apply_meta()
			_save_meta()
			match id:
				"lume":
					_flash("📜 Aprendeu LUME (F): explosão de luz que queima Sombras próximas")
				"escudo":
					_flash("📜 Aprendeu ESCUDO (G): barreira que bloqueia dano por 6s")
				"eco":
					_flash("📜 Aprendeu ECO ARCANO: sua mana máxima cresce para 130")
			return
	inv.bone += 1
	_flash("Página em branco... virou pó de osso (+1 osso)")


func _try_portal() -> void:
	if hearts >= PORTAL_HEARTS:
		hearts -= PORTAL_HEARTS
		won = true
		if nights > best_nights:
			best_nights = nights
		_save_meta()
		lbl_end.visible = true
		lbl_end.text = "🌀 O PORTAL SE REABRE: você encontrou o caminho de volta à escola.\nSobreviveu %d noites. R para uma nova ilha (o saber permanece)" % nights
	else:
		_flash("O Portal dorme. Precisa de %d Corações da Névoa (tem %d): mate o horror da Lua de Sangue" % [PORTAL_HEARTS, hearts])


func _eat() -> void:
	# cooked food first: more hunger, no corruption
	if inv.cooked > 0:
		inv.cooked -= 1
		hunger = min(100.0, hunger + 35.0)
		_flash("Comeu cogumelo assado (+fome, sem corrupção)")
	elif inv.mushroom > 0:
		inv.mushroom -= 1
		hunger = min(100.0, hunger + 22.0)
		corruption = min(100.0, corruption + 3.0)
		_flash("Comeu cogumelo cru (+fome, +corrupção)")
	else:
		_flash("Sem comida")


func _feed_wisp() -> void:
	if inv.twig > 0:
		inv.twig -= 1
		wisp = min(100.0, wisp + 35.0)
		_flash("Alimentou o fogo-fátuo")
	else:
		_flash("Sem galhos")


func _brew() -> void:
	if inv.mushroom >= 2:
		inv.mushroom -= 2
		health = min(100.0, health + 30.0)
		corruption = min(100.0, corruption + 6.0)
		_flash("Poção improvisada (+vida, +corrupção)")
	else:
		_flash("Precisa de 2 cogumelos")


func _near_fire() -> bool:
	for fire in campfires:
		if player.translation.distance_to(fire.translation) < FIRE_RADIUS:
			return true
	return false


func _near_cauldron() -> bool:
	for c in cauldrons:
		if player.translation.distance_to(c.translation) < 4.0:
			return true
	return false


func _cook() -> void:
	if not _near_fire():
		_flash("Precisa estar perto de uma fogueira")
		return
	if inv.mushroom > 0:
		inv.mushroom -= 1
		inv.cooked += 1
		_flash("Assou um cogumelo")
	else:
		_flash("Sem cogumelos crus")


func _craft_campfire() -> void:
	if inv.wood >= 2 and inv.stone >= 1:
		inv.wood -= 2
		inv.stone -= 1
		var fire := Spatial.new()
		fire.translation = player.translation + Vector3(1.5, 0, 0)
		add_child(fire)
		var mi := MeshInstance.new()
		mi.mesh = fire_mesh
		mi.material_override = _emissive_mat(Color(1.0, 0.55, 0.15), Color(1.0, 0.45, 0.1))
		mi.translation.y = 0.45
		fire.add_child(mi)
		var light := OmniLight.new()
		light.translation = Vector3(0, 1.6, 0)
		light.light_color = Color(1.0, 0.6, 0.25)
		light.omni_range = FIRE_RADIUS
		light.light_energy = 1.6
		fire.add_child(light)
		campfires.append(fire)
		_flash("🔥 Fogueira acesa (luz fixa + cozinhar)")
	else:
		_flash("Fogueira: precisa 2 madeira + 1 pedra")


func _craft_ward() -> void:
	if inv.bone >= 2 and inv.twig >= 1:
		inv.bone -= 2
		inv.twig -= 1
		var ward := Spatial.new()
		ward.translation = player.translation + Vector3(-1.5, 0, 0)
		add_child(ward)
		var mi := MeshInstance.new()
		mi.mesh = ward_mesh
		mi.material_override = _emissive_mat(Color(0.75, 0.7, 0.9), Color(0.5, 0.3, 0.9))
		mi.translation.y = 0.8
		ward.add_child(mi)
		wards.append(ward)
		_flash("🦴 Ward de ossos fincado (Sombras não entram)")
	else:
		_flash("Ward: precisa 2 ossos + 1 galho")


func _craft_cauldron() -> void:
	if inv.stone >= 2 and inv.wood >= 2:
		inv.stone -= 2
		inv.wood -= 2
		var c := Spatial.new()
		c.translation = player.translation + Vector3(0, 0, 1.5)
		add_child(c)
		var mi := MeshInstance.new()
		mi.mesh = cauldron_mesh
		mi.material_override = _emissive_mat(Color(0.12, 0.14, 0.16), Color(0.15, 0.7, 0.3))
		mi.translation.y = 0.4
		c.add_child(mi)
		cauldrons.append(c)
		_flash("🧪 Caldeirão montado (Elixir limpo com a tecla 9)")
	else:
		_flash("Caldeirão: precisa 2 pedras + 2 madeiras")


func _brew_elixir() -> void:
	if not _near_cauldron():
		_flash("Precisa estar perto de um caldeirão")
		return
	if inv.mushroom >= 2:
		inv.mushroom -= 2
		health = min(100.0, health + 50.0)
		_flash("Elixir do caldeirão (+50 vida, SEM corrupção)")
	else:
		_flash("Elixir: precisa 2 cogumelos")


func _upgrade_wand() -> void:
	if wand_level >= 1:
		_flash("A varinha de osso já é sua")
		return
	if inv.bone >= 3 and inv.wood >= 2:
		inv.bone -= 3
		inv.wood -= 2
		wand_level = 1
		_flash("🪄 Varinha de osso: feitiço mais forte, mana mais barata")
	else:
		_flash("Varinha: precisa 3 ossos + 2 madeiras")


func _spell_damage() -> float:
	return 110.0 if wand_level == 1 else 60.0


func _spell_cost() -> float:
	return 12.0 if wand_level == 1 else 20.0


func _cast() -> void:
	if dead or won:
		return
	if mana < _spell_cost():
		_flash("Mana insuficiente")
		return
	mana -= _spell_cost()
	corruption = min(100.0, corruption + 5.0)
	var best = null
	var bd := 16.0
	for s in shadows:
		var d = s.node.translation.distance_to(player.translation)
		if d < bd:
			bd = d
			best = s
	if best != null:
		best.hp -= _spell_damage()
		best.spell = true
		_flash("Feitiço atinge a Sombra" + (" GRANDE" if best.boss else ""))
	else:
		_flash("Feitiço lançado no vazio")


func _cast_lume() -> void:
	if dead or won:
		return
	if not ("lume" in spells):
		_flash("Você ainda não conhece LUME (ache páginas nas Ruínas)")
		return
	if mana < 15.0:
		_flash("Mana insuficiente")
		return
	mana -= 15.0
	corruption = min(100.0, corruption + 3.0)
	var burned := 0
	for s in shadows:
		if s.node.translation.distance_to(player.translation) < 10.0:
			s.hp -= 50.0
			s.spell = true
			burned += 1
	wisp = min(100.0, wisp + 10.0)
	_flash("✨ LUME! Luz explode (%d Sombras queimadas)" % burned)


func _cast_shield() -> void:
	if dead or won:
		return
	if not ("escudo" in spells):
		_flash("Você ainda não conhece ESCUDO (ache páginas nas Ruínas)")
		return
	if mana < 25.0:
		_flash("Mana insuficiente")
		return
	mana -= 25.0
	shield_t = 6.0
	_flash("🛡️ ESCUDO! Nada te toca por 6 segundos")


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.scancode:
			KEY_E:
				_interact()
			KEY_1:
				_eat()
			KEY_2:
				_feed_wisp()
			KEY_3:
				_brew()
			KEY_4:
				_cook()
			KEY_5:
				_craft_campfire()
			KEY_6:
				_craft_ward()
			KEY_7:
				_upgrade_wand()
			KEY_8:
				_craft_cauldron()
			KEY_9:
				_brew_elixir()
			KEY_F:
				_cast_lume()
			KEY_G:
				_cast_shield()
			KEY_SPACE:
				_cast()
			KEY_R:
				if dead or won:
					_reset()
	elif event is InputEventMouseButton and event.pressed and event.button_index == BUTTON_LEFT:
		_cast()


# ---------- HUD ----------

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.anchor_right = 1.0
	root.anchor_bottom = 1.0
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	var rows := [
		["hunger", "Fome", Color(0.90, 0.70, 0.30)],
		["health", "Vida", Color(0.85, 0.25, 0.30)],
		["mana", "Mana", Color(0.35, 0.60, 0.95)],
		["corruption", "Corrupção", Color(0.60, 0.20, 0.70)],
		["wisp", "Fogo-fátuo", Color(1.00, 0.75, 0.40)],
	]
	var y := 16
	for r in rows:
		var lab := Label.new()
		lab.text = r[1]
		lab.rect_position = Vector2(16, y - 2)
		root.add_child(lab)
		var bg := ColorRect.new()
		bg.color = Color(0, 0, 0, 0.5)
		bg.rect_position = Vector2(120, y)
		bg.rect_size = Vector2(180, 14)
		root.add_child(bg)
		var bar := ColorRect.new()
		bar.color = r[2]
		bar.rect_position = Vector2(120, y)
		bar.rect_size = Vector2(180, 14)
		root.add_child(bar)
		bars[r[0]] = bar
		y += 24

	lbl_stats = Label.new()
	lbl_stats.rect_position = Vector2(16, y + 6)
	root.add_child(lbl_stats)

	lbl_msg = Label.new()
	lbl_msg.rect_position = Vector2(16, y + 70)
	lbl_msg.visible = false
	root.add_child(lbl_msg)

	var hint := Label.new()
	hint.text = "WASD mover · Q/PgUp câmera · E interagir · 1 comer · 2 fogo-fátuo · 3 poção · 4 assar · 5 fogueira · 6 ward · 7 varinha · 8 caldeirão · 9 elixir · F Lume · G Escudo · Espaço feitiço"
	hint.rect_position = Vector2(16, 690)
	root.add_child(hint)

	lbl_end = Label.new()
	lbl_end.rect_position = Vector2(380, 320)
	lbl_end.visible = false
	root.add_child(lbl_end)


func _update_hud() -> void:
	bars["hunger"].rect_size = Vector2(180.0 * clamp(hunger, 0, 100) / 100.0, 14)
	bars["health"].rect_size = Vector2(180.0 * clamp(health, 0, 100) / 100.0, 14)
	bars["mana"].rect_size = Vector2(180.0 * clamp(mana, 0, mana_max) / mana_max, 14)
	bars["corruption"].rect_size = Vector2(180.0 * clamp(corruption, 0, 100) / 100.0, 14)
	bars["wisp"].rect_size = Vector2(180.0 * clamp(wisp, 0, 100) / 100.0, 14)
	var moon := "  ·  🌒 LUA DE SANGUE" if blood_moon else ""
	var shield := ("  ·  🛡️ %.1fs" % shield_t) if shield_t > 0.0 else ""
	var spell_names := []
	for s in spells:
		spell_names.append(str(s).to_upper())
	var spell_txt := "básico (ache páginas nas Ruínas)"
	if spells.size() > 0:
		spell_txt = "básico + " + PoolStringArray(spell_names).join(", ")
	lbl_stats.text = "Dia %d (melhor: %d) · Portal: %d/%d 💜%s%s\nFeitiços: %s\nCogumelo %d · Assado %d · Galho %d · Madeira %d · Pedra %d · Osso %d · Varinha: %s" % [
		nights + 1, best_nights, hearts, PORTAL_HEARTS, moon, shield,
		spell_txt,
		inv.mushroom, inv.cooked, inv.twig, inv.wood, inv.stone, inv.bone,
		("osso" if wand_level == 1 else "galho")]


func _flash(m: String) -> void:
	lbl_msg.text = m
	lbl_msg.visible = true
	msg_t = 2.2
