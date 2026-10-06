extends Node3D
## Magical Survive - island orchestrator (Godot 4).
## Generates the island, spawns apprentices and Shadows, owns team progress
## (nights, Mist Hearts, the Arcane Portal), the crafting rules and the action
## dispatcher. Every apprentice action goes through perform(player, action)
## so Phase 2 co-op only has to forward client input to the host with one RPC.
## Implements design/gdd/survival-loop-mvp.md.

const Cfg = preload("res://src/core/config.gd")
const Art = preload("res://src/core/art.gd")
const Models = preload("res://src/core/models.gd")
const Fx = preload("res://src/core/fx.gd")
const Data = preload("res://src/core/data.gd")
const Dev = preload("res://src/core/dev.gd")
const ItemArt = preload("res://src/core/item_art.gd")
const Lanna = preload("res://src/core/lanna.gd")
const Sfx = preload("res://src/core/sfx.gd")
const SchoolTemple = preload("res://src/gameplay/builders/school_temple.gd")
const GuardianScript = preload("res://src/ai/guardian.gd")
const SOLID := {"tree": 0.8, "rock": 0.85, "berry_bush": 0.6}   # collision radius per resource kind
const OBJECTIVES := ["gather", "tool", "fire", "shrine", "page"]
const FOOTPRINT := {"campfire": 1.4, "altar": 1.6, "ward": 1.0, "cauldron": 1.4, "cabin": 3.6}
const MetaSave = preload("res://src/core/meta_save.gd")
const Terrain = preload("res://src/gameplay/systems/terrain.gd")
const RunSave = preload("res://src/gameplay/run_save.gd")
const Exploration = preload("res://src/gameplay/exploration.gd")
const WorldMapScene = preload("res://scenes/world_map.tscn")
const Inventory = preload("res://src/gameplay/inventory.gd")
const WizardScene = preload("res://scenes/wizard.tscn")
const ShadowScene = preload("res://scenes/shadow.tscn")
const GatherableScene = preload("res://scenes/gatherable.tscn")
const StructureScene = preload("res://scenes/structure.tscn")
const PortalScene = preload("res://scenes/portal.tscn")
const SelectScene = preload("res://scenes/character_select.tscn")
const OverlayMenuScene = preload("res://scenes/overlay_menu.tscn")
const CONTROLS_TEXT := "WASD mover  ·  Q / PgUp girar câmera  ·  E agir (colher, cortar, minerar, pegar)  ·  Espaço: salto mágico\nF ou clique: feitiço  ·  Z Lume  ·  X Escudo  ·  1-0 usar item  ·  botão direito ou Shift+nº: assar / combustível / largar\nTab: criação  ·  Esc: pausa  ·  F11: tela cheia"

const KEY_ACTIONS := {
	KEY_E: "interact", KEY_SPACE: "jump", KEY_F: "bolt", KEY_Z: "lume", KEY_X: "shield",
}
const SLOT_KEYS := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0]
const DROP_TABLE := {"bone": 1.0, "essence": 0.5}   # per spell-killed Shadow (chance)
const BOSS_DROPS := {"bone": 5, "essence": 3}
const DEFAULT_CHARACTER := "aldric"

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
var started := false
var run_hearts := 0        # Mist Hearts of THIS run (records/spells stay permanent)
var world_seed := 0        # rebuilds the same island on Continue
var exploration: Exploration        # fog of war, base, personal pins (saved with the run)
var world_map = null                # the M map screen
var _last_reveal := Vector3(INF, 0, INF)
var shrine_center := Vector2.ZERO   # Shrine of the Sleeping Naga (end of the Lantern Trail)
var trail: Array = []               # Lantern Trail polyline (clearing -> shrine)
var old_trail: Array = []           # old trail to the Temple of the Portal
var gothic_center := Vector2(-95, -88)   # Sunken Cathedral
var desert_center := Vector2(95, -88)
var obelisk_pos := Vector2.ZERO          # the Great Obelisk (desert landmark)
var buried_temple := Vector2.ZERO        # half-buried chedi in the dunes
var lamp_road: Array = []                # flowered -> gothic (iron lamps)
var waystone_path: Array = []            # flowered -> desert (cairns)
var north_road: Array = []               # gothic <-> desert (alternative loop)
var objective_step := 0             # first-steps chain (see OBJECTIVES)
var obj_flags := {}                 # tool_made, reached_shrine, found_page
var _obj_done_t := 0.0              # shows "Concluído" briefly between steps
var _fps_t := 0.0
var _fps_frames := 0
var _fps_done := false
var _autopilot := false             # dev: walk the Lantern Trail and hop (movement video)
var _auto_i := 1
var _auto_jump_t := 1.5
var placing := ""          # structure recipe being placed (preview mode)
var place_ok := false
var place_why := ""
var _ghost: Node3D
var _ghost_ok_mat: StandardMaterial3D
var _ghost_bad_mat: StandardMaterial3D
var won := false
var game_over := false
var shot_timer := -1.0     # dev: MAGIC_SHOT=1 saves a screenshot after MAGIC_SHOT_AT s
var shot_path := "user://shot.png"
var ambient: Node3D        # follows the local apprentice: fireflies + leaves
var fireflies: CPUParticles3D
var leaves: CPUParticles3D
var select_screen = null
var terrain: Terrain
var state := "menu"        # menu · select · playing · paused · ended
var menu = null            # the open OverlayMenu, if any
var _menu_return := ""     # where "Voltar" from Controles goes
var last_character := DEFAULT_CHARACTER
var _approach = null       # resource the local apprentice is walking to (E from afar)
var _approach_t := 0.0
var _focus_ring: MeshInstance3D   # highlight under the E target
var _focus_label: Label3D         # "E — Coletar Tufo de palha" / why it fails
var _solid_boxes: Array = []      # [{c: Vector2, half: Vector2, rot: float, node}] walls of built places
var dungeons := {}                # id -> {"discovered": bool, "cleared": bool} (saved with the run)
var temple_center := Vector2.ZERO # School-Temple of a Thousand Lanterns
var temple_info := {}             # builder output: arena, reward, seal, loot spots
var guardians_root: Node3D


func _ready() -> void:
	if Dev.has("shot"):
		shot_timer = float(Dev.arg("shot")) if Dev.arg("shot").is_valid_float() and float(Dev.arg("shot")) > 1.0 else float(Dev.arg("shot-at") if Dev.has("shot-at") else "3")
		if Dev.has("shot-path"):
			shot_path = Dev.arg("shot-path")
	meta.load_from_disk()
	day_night.night_started.connect(_on_night_start)
	day_night.dawn.connect(_on_dawn)
	hud.world = self
	_build_scenery()
	world_map = WorldMapScene.instantiate()
	world_map.world = self
	add_child(world_map)
	ambient = Node3D.new()
	add_child(ambient)
	fireflies = Fx.fireflies(ambient)
	leaves = Fx.leaves(ambient)
	var forced := Dev.arg("char")
	if forced != "" or DisplayServer.get_name() == "headless":
		start_game(forced if forced != "" else DEFAULT_CHARACTER)
	else:
		_generate_world()  # the island is the main menu's backdrop
		day_night.t = 39.0  # dusk
		show_main_menu()


# ---------- screens: main menu · character select · pause · game over ----------

func _open_menu(title: String, sub: String, opts: Array, big := false) -> void:
	_close_menu()
	menu = OverlayMenuScene.instantiate()
	menu.setup(title, sub, opts, big)
	menu.picked.connect(_on_menu_pick)
	add_child(menu)


func _close_menu() -> void:
	if menu != null:
		menu.queue_free()
		menu = null


## Rebuilds a saved run: same island from the seed, then the saved state.
func continue_run() -> bool:
	var data := RunSave.read()
	if data.is_empty():
		return false
	start_game(String(data.character), int(data.world_seed))
	for g in resources():
		_despawn(g)
	for st in _children(structures_root):
		_despawn(st)
	for r in data.resources:
		var g
		if r.kind == "item":
			g = spawn_item(r.item_id, int(r.item_count), RunSave.vec(r.pos), r.item_stack if r.item_stack is Dictionary else {})
		else:
			g = _spawn_resource(r.kind, RunSave.vec(r.pos))
		g.hp = int(r.hp)
		g.grow_t = float(r.grow_t)
		if not r.grown:
			g.set_picked()
			g.regrow_t = float(r.regrow_t)
	for st in data.structures:
		var s = spawn_structure(st.kind, RunSave.vec(st.pos), float(st.fuel_mult))
		s.fuel = float(st.fuel)
	var c: Dictionary = data.clock
	day_night.t = float(c.t)
	day_night.nights = int(c.nights)
	day_night.blood_moon = bool(c.blood_moon)
	day_night.prev_night = bool(c.prev_night)
	run_hearts = int(data.run_hearts)
	objective_step = int(data.get("objective_step", 0))
	obj_flags = data.get("obj_flags", {})
	if data.has("exploration"):
		exploration.from_save(data.exploration)
	var saved_dungeons = data.get("dungeons", {})
	for id in saved_dungeons:
		if dungeons.has(id):
			dungeons[id]["discovered"] = bool(saved_dungeons[id].get("discovered", false))
			dungeons[id]["cleared"] = bool(saved_dungeons[id].get("cleared", false))
	_sync_dungeons()
	var p = local_player
	var ps: Dictionary = data.player
	p.position = RunSave.vec(ps.pos)
	for k in ["health", "hunger", "mana", "corruption", "wisp", "noise"]:
		p.set(k, float(ps[k]))
	for i in range(Inventory.SIZE):
		p.inventory.slots[i] = RunSave.stack(ps.slots[i])
	p.inventory.equip.hand = RunSave.stack(ps.equip.hand)
	p.inventory.equip.body = RunSave.stack(ps.equip.body)
	p.refresh_gear()
	_announce("Partida carregada: dia %d" % (day_night.nights + 1))
	return true


func save_run() -> bool:
	return started and not game_over and not won and RunSave.write(self)


func show_main_menu() -> void:
	_close_select()
	for p in players():
		_despawn(p)
	local_player = null
	camera_rig.target = null
	started = false
	won = false
	game_over = false
	state = "menu"
	hud.visible = false
	_open_menu("Magical Survive", "Aprendizes de magia presos na ilha da Névoa. Sobreviva, domine a magia e reabra o Portal.",
		([["continue", "Continuar partida"]] if RunSave.exists() else []) + [["play", "Novo jogo"], ["fullscreen", "Tela cheia"], ["controls", "Controles"], ["quit", "Sair"]], true)


func show_select() -> void:
	_close_menu()
	_close_select()
	state = "select"
	hud.visible = false
	select_screen = SelectScene.instantiate()
	select_screen.chosen.connect(start_game)
	select_screen.back.connect(show_main_menu)
	add_child(select_screen)


func _close_select() -> void:
	if select_screen != null:
		select_screen.queue_free()
		select_screen = null


func pause() -> void:
	if state != "playing":
		return
	cancel_placement()
	if world_map != null:
		world_map.close()
	state = "paused"
	_open_menu("Pausado", "", [["resume", "Continuar"], ["save", "Salvar partida"], ["controls", "Controles"], ["fullscreen", "Tela cheia"], ["save_menu", "Salvar e voltar ao menu"], ["save_quit", "Salvar e sair do jogo"]])


func resume() -> void:
	_close_menu()
	state = "playing"


func _show_end_menu(victory: bool) -> void:
	state = "ended"
	RunSave.erase()  # a finished run can't be continued (roguelite)
	var nights: int = day_night.nights
	if victory:
		_open_menu("O Portal se reabre!", "Vocês encontraram o caminho de volta ao Colégio em %d noites. O saber aprendido permanece." % nights,
			[["again", "Jogar de novo"], ["select", "Trocar de aprendiz"], ["menu", "Menu principal"]])
	else:
		_open_menu("Você virou adubo", "Sobreviveu %d noites (melhor: %d). Os feitiços aprendidos permanecem." % [nights, meta.best_nights],
			[["again", "Tentar de novo"], ["select", "Trocar de aprendiz"], ["menu", "Menu principal"]])


func _on_menu_pick(id: String) -> void:
	match id:
		"play", "select":
			show_select()
		"again":
			start_game(last_character)
		"continue":
			continue_run()
		"save":
			resume()
			_announce("Partida salva" if save_run() else "Não foi possível salvar")
		"save_menu":
			save_run()
			show_main_menu()
		"save_quit":
			save_run()
			get_tree().quit()
		"resume":
			resume()
		"menu":
			show_main_menu()
		"fullscreen":
			toggle_fullscreen()
		"controls":
			_menu_return = state
			_open_menu("Controles", CONTROLS_TEXT, [["controls_back", "Voltar"]])
		"controls_back":
			if _menu_return == "paused":
				state = "playing"
				pause()
			else:
				show_main_menu()
		"quit":
			get_tree().quit()


## Starts (or restarts) a run as the chosen character on a fresh island.
func start_game(character: String, seed_value := -1) -> void:
	_close_select()
	_close_menu()
	last_character = character
	state = "playing"
	run_hearts = 0
	objective_step = 0
	obj_flags = {}
	_autopilot = false  # dev autopilot never carries into a new run
	_auto_i = 1
	cancel_placement()
	camera_rig.angle = 0.0
	for p in players():
		_despawn(p)
	won = false
	game_over = false
	day_night.reset()
	_generate_world(seed_value)  # terrain first: apprentices spawn on its ground
	exploration = Exploration.new(Cfg.WORLD)
	_last_reveal = Vector3(INF, 0, INF)
	if world_map != null:
		world_map.invalidate()
		world_map.close()
	local_player = add_player(1, character)
	camera_rig.target = local_player
	hud.visible = true
	hud.hide_end()
	started = true
	# dev: MAGIC_TIME=<seconds> starts the clock later (e.g. 58 = first night)
	if Dev.has("time"):
		day_night.t = float(Dev.arg("time"))
	if Dev.has("scene"):
		_stage_scene.call_deferred(Dev.arg("scene"))
	_announce("%s %s chega à ilha. Colete palha dourada, galhos e pederneira (E perto do item)." % [local_player.stats.get("name", ""), local_player.stats.get("title", "")])


# ---------- scenery (built once: ground, grass, the forest wall) ----------

func _build_scenery() -> void:
	terrain = Terrain.new()
	terrain.name = "Terrain"
	add_child(terrain)


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


func ground_items(id := "") -> Array:
	return resources().filter(func(g): return g.kind == "item" and (id == "" or g.item_id == id))


func structures_of(kind: String) -> Array:
	return _children(structures_root).filter(func(s): return s.kind == kind)


func pillars() -> Array:
	return _children(decor_root).filter(func(n): return n.has_meta("ruin"))


## Who an Errante at `pos` is hunting: the nearest apprentice it can sense
## (close by) or hear (arcane noise carries far). null = nobody, it wanders.
func errante_target(pos: Vector3):
	var best = null
	var bd := INF
	for p in alive_players():
		var flat: Vector3 = p.position - pos
		flat.y = 0.0
		var d := flat.length()
		if d <= p.heard_from() and d < bd:
			bd = d
			best = p
	return best


## The loudest living apprentice (Errantes gather around them).
func loudest_player():
	var best = null
	for p in alive_players():
		if best == null or p.noise > best.noise:
			best = p
	return best


func _max_noise() -> float:
	var m := 0.0
	for p in alive_players():
		m = maxf(m, p.noise)
	return m


# ---------- first steps: one objective at a time ----------

func _objective_met(id: String, p) -> bool:
	match id:
		"gather":
			return (p.inventory.count("grass") >= 3 and p.inventory.count("twig") >= 2) or obj_flags.get("tool_made", false) or not structures_of("campfire").is_empty()
		"tool":
			return obj_flags.get("tool_made", false)
		"fire":
			return not structures_of("campfire").is_empty()
		"shrine":
			return obj_flags.get("reached_shrine", false)
		"page":
			return obj_flags.get("found_page", false)
	return true


func _update_objectives(p) -> void:
	if p == null:
		return
	if p.inventory.count("axe") > 0 or p.inventory.count("pickaxe") > 0:
		obj_flags["tool_made"] = true
	if Vector2(p.position.x, p.position.z).distance_to(shrine_center) < 8.0:
		obj_flags["reached_shrine"] = true
	while objective_step < OBJECTIVES.size() and _objective_met(OBJECTIVES[objective_step], p):
		objective_step += 1
		_obj_done_t = 2.5


## What the HUD shows: the current objective, its progress and completion.
func objective_info() -> Dictionary:
	var p = local_player
	if p == null:
		return {}
	if objective_step >= OBJECTIVES.size():
		return {"title": "Primeiros passos concluídos", "text": "Explore, sobreviva à noite e siga a trilha velha até o Templo do Portal.", "done": true, "fresh": _obj_done_t > 0.0}
	match OBJECTIVES[objective_step]:
		"gather":
			return {"title": "Colete materiais (E)", "text": "Palha %d/3  ·  Galho %d/2" % [mini(p.inventory.count("grass"), 3), mini(p.inventory.count("twig"), 2)], "fresh": _obj_done_t > 0.0}
		"tool":
			return {"title": "Fabrique uma ferramenta (Tab)", "text": "Machado: 1 galho + 1 pederneira (pederneira fica no chão)", "fresh": _obj_done_t > 0.0}
		"fire":
			return {"title": "Prepare uma fogueira", "text": "Tab › Luz › Fogueira: 3 palha + 2 toras (corte árvores)", "fresh": _obj_done_t > 0.0}
		"shrine":
			var dist := Vector2(p.position.x, p.position.z).distance_to(shrine_center)
			return {"title": "Siga a Trilha das Lanternas", "text": "Santuário da Naga Adormecida: faltam %d m" % int(dist), "fresh": _obj_done_t > 0.0}
		"page":
			return {"title": "Descubra a página do grimório", "text": "Pegue a página no altar do santuário (E)", "fresh": _obj_done_t > 0.0}
	return {}


## Records a grimoire discovery (permanent) and tells the player once.
func discover(id: String) -> void:
	if id in meta.discoveries:
		return
	meta.discoveries.append(id)
	meta.save()
	var text: String = Data.table("discoveries").get(id, "")
	if text != "":
		hud.flash("Nova descoberta no grimório (G): " + text, 6.0)


## Magic acts are loud: raise the apprentice's noise and show the ring.
func emit_noise(p, amount: float) -> void:
	if amount <= 0.0:
		return
	p.make_noise(amount)
	Fx.noise_ring(self, p.position, p.heard_from())
	if p.noise > 30.0:
		discover("noise")


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


## Lights that HURT Errantes: sunlight and a burning campfire (the Blood
## Moon horror resists fire). Wisp, torch and lantern only light the way:
## they keep the Mist's darkness off you but don't burn anything.
func burns_errante(pos: Vector3, lit: float, is_boss := false) -> bool:
	if lit > 0.5:
		return true
	if is_boss:
		return false
	for fire in structures_of("campfire"):
		if fire.burning() and pos.distance_to(fire.position) < fire.radius():
			return true
	return false


## Any light at all (protects apprentices from the darkness damage).
func is_lit(pos: Vector3, lit: float) -> bool:
	if lit > 0.5:
		return true
	for p in alive_players():
		if pos.distance_to(p.position) < p.light_radius():
			return true
	for fire in structures_of("campfire"):
		if fire.burning() and pos.distance_to(fire.position) < fire.radius():
			return true
	return false


## Nearest campfire you can use: lit_only for cooking; any (even cold
## embers) for adding fuel, so a dead fire can be relit.
func near_campfire(p, lit_only: bool):
	for s in structures_of("campfire"):
		if lit_only and not s.burning():
			continue
		var reach: float = s.radius() if s.burning() else 3.0
		if p.position.distance_to(s.position) < maxf(reach, 3.0):
			return s
	return null


## Nearest structure of a kind within its working radius (tech, cooking).
func near_structure(p, kind: String):
	for s in structures_of(kind):
		if kind == "campfire" and not s.burning():
			continue
		if p.position.distance_to(s.position) < s.radius():
			return s
	return null


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

func add_player(peer_id: int, character := DEFAULT_CHARACTER):
	var w = WizardScene.instantiate()
	w.peer_id = peer_id
	w.slot = players_root.get_child_count()
	w.name = "Wizard%d" % peer_id
	w.setup(character)
	w.terrain = terrain
	w.collider = resolve_collision
	players_root.add_child(w)
	w.respawn(_spawn_spot(w.slot), meta.knows("eco"))
	return w


func _spawn_spot(slot: int) -> Vector3:
	return terrain.on_ground(Vector3(slot * 2.0, 0, 0))


func spawn_shadow(boss := false):
	var anchor = loudest_player()
	var center: Vector3 = anchor.position if anchor != null else Vector3.ZERO
	var ang := randf_range(0.0, TAU)
	var pos := center + Vector3(cos(ang), 0, sin(ang)) * (16.0 + randf_range(4.0, 14.0))
	pos.x = clampf(pos.x, -Cfg.WORLD, Cfg.WORLD)
	pos.z = clampf(pos.z, -Cfg.WORLD, Cfg.WORLD)
	var s = ShadowScene.instantiate()
	s.setup(boss)
	pos.y = terrain.height_at(pos.x, pos.z) + s.hover_height()
	s.position = pos
	shadows_root.add_child(s)
	return s


func spawn_structure(kind: String, pos: Vector3, burn_mult := 1.0):
	var s = StructureScene.instantiate()
	s.setup(kind, burn_mult)
	s.position = terrain.on_ground(pos)
	structures_root.add_child(s)
	return s


func _spawn_resource(kind: String, pos: Vector3):
	var g = GatherableScene.instantiate()
	g.setup(kind)
	g.position = terrain.on_ground(pos)
	g.biome = terrain.biome_at(pos.x, pos.z)
	resources_root.add_child(g)
	return g


## Drops items on the ground (loot, overflow, manual drop).
func spawn_item(id: String, count: int, pos: Vector3, stack := {}):
	var g = GatherableScene.instantiate()
	g.setup_item(id, count, stack)
	g.position = terrain.on_ground(pos)
	resources_root.add_child(g)
	return g


## Gives items to an apprentice; whatever does not fit falls at their feet.
func give(p, items: Dictionary) -> void:
	for id in items:
		var left: int = p.inventory.add(id, int(items[id]))
		if left > 0:
			spawn_item(id, left, p.position + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)))
			_say(p, "Inventário cheio: %s caiu no chão" % Data.item_name(id))


# Removes from the tree immediately (counts stay exact this frame), frees later.
func _despawn(n: Node) -> void:
	n.get_parent().remove_child(n)
	n.queue_free()


func _rand_pos() -> Vector3:
	return terrain.random_land_pos(3.0)


func _ruins_center() -> Vector3:
	return Vector3(-58.0, 0.0, 72.0)  # Temple of the Portal, south-west of the flowered biome


func _ruins_pos() -> Vector3:
	var ang := randf_range(0.0, TAU)
	var r := randf_range(2.5, Cfg.RUINS_RADIUS)
	return terrain.on_ground(_ruins_center() + Vector3(cos(ang) * r, 0.0, sin(ang) * r))


func _generate_world(seed_value := -1) -> void:
	world_seed = seed_value if seed_value >= 0 else randi() % 2000000000
	seed(world_seed)  # same seed -> same island (relief, lakes, decor, resources)
	if guardians_root == null:
		guardians_root = Node3D.new()
		guardians_root.name = "Guardians"
		add_child(guardians_root)
	for root in [shadows_root, resources_root, structures_root, decor_root, guardians_root]:
		for n in root.get_children():
			_despawn(n)
	portal = null
	_solid_boxes.clear()
	dungeons = {"temple": {"discovered": false, "cleared": false}}

	# ---- layout (design/gdd/world-biomes.md) ----
	var rc := _ruins_center()
	var temple := Vector2(rc.x, rc.z)
	var ang := randf_range(0.5, 1.4)                 # the shrine lies south-east of the clearing
	var dir := Vector2(cos(ang), sin(ang))
	shrine_center = dir * 34.0
	var side := Vector2(-dir.y, dir.x)
	trail = [dir * 6.0, dir * 17.0 + side * randf_range(-5.0, 5.0), dir * 28.0]
	var to_t := temple.normalized()
	var t_side := Vector2(-to_t.y, to_t.x)
	old_trail = [to_t * 6.0, to_t * 35.0 + t_side * 7.0, to_t * 70.0 - t_side * 5.0, temple - to_t * (Cfg.RUINS_RADIUS + 1.0)]
	gothic_center = Vector2(-95, -88) + Vector2(randf_range(-8, 8), randf_range(-8, 8))
	desert_center = Vector2(95, -88) + Vector2(randf_range(-8, 8), randf_range(-8, 8))
	var gate := gothic_center + (Vector2.ZERO - gothic_center).normalized() * 26.0
	var d_entry := desert_center + (Vector2.ZERO - desert_center).normalized() * 30.0
	lamp_road = [Vector2(-8, -8), Vector2(-28, -32) + Vector2(randf_range(-6, 6), randf_range(-6, 6)), gate + (Vector2.ZERO - gate).normalized() * 30.0, gate]
	waystone_path = [Vector2(8, -8), Vector2(30, -35) + Vector2(randf_range(-6, 6), randf_range(-6, 6)), d_entry + (Vector2.ZERO - d_entry).normalized() * 28.0, d_entry]
	north_road = [gothic_center + Vector2(24, -14), Vector2(0, -132) + Vector2(randf_range(-10, 10), 0), desert_center + Vector2(-28, -18)]
	# the School-Temple lies past the Naga shrine, gate facing the shrine
	temple_center = shrine_center + dir * 52.0
	temple_center = temple_center.clamp(Vector2(-Cfg.WORLD + 34, -Cfg.WORLD + 34), Vector2(Cfg.WORLD - 34, Cfg.WORLD - 34))
	var temple_gate := temple_center + (shrine_center - temple_center).normalized() * 23.0
	obelisk_pos = desert_center + Vector2(-8, -34)
	buried_temple = desert_center + Vector2(30, 18)
	terrain.generate([
		{"center": Vector2.ZERO, "radius": 9.0}, {"center": temple, "radius": Cfg.RUINS_RADIUS + 3.0},
		{"center": shrine_center, "radius": 7.0}, {"center": gothic_center, "radius": 18.0},
		{"center": obelisk_pos, "radius": 6.0}, {"center": buried_temple, "radius": 11.0},
		{"center": temple_center, "radius": 25.0}],
		[trail + [shrine_center], old_trail, lamp_road, waystone_path, north_road, [shrine_center, temple_gate]])

	# flowered south (the start, kept as it was)
	_build_clearing(dir)
	_build_trail(trail + [shrine_center], true)
	_build_trail(old_trail, false)
	_build_shrine(shrine_center, dir)
	_build_school_temple(temple_center, shrine_center)
	_build_temple(temple)
	_build_forest()
	# gothic north-west and magic desert north-east
	_build_road(lamp_road, "lamp")
	_build_road(waystone_path, "cairn")
	_build_road(north_road, "cairn")
	_build_gothic(gothic_center, gate)
	_build_desert(desert_center)

	# resources come in readable patches: plenty near the start and along the
	# roads (the first torch never needs a long hunt), sparser in the wild
	_scatter_start()
	_scatter("flowered", {"rock": 14, "mushroom": 22, "grass_tuft": 70, "sapling": 50, "berry_bush": 16, "flint": 24})
	_scatter("gothic", {"tree": 26, "rock": 14, "mushroom": 18, "berry_bush": 5, "flint": 12, "grass_tuft": 24})
	_scatter("desert", {"rock": 22, "flint": 18, "grass_tuft": 30, "dry_shrub": 30})
	for path in [trail, old_trail, lamp_road, waystone_path, north_road]:
		_scatter_verges(path)
	for i in range(80):
		var mp := _wild_pos(1.5, "flowered")
		Models.cull(Models.spawn_variant(decor_root, "meadow", mp, randf_range(0.8, 1.2)), 70.0)
	randomize()  # gameplay randomness stays unpredictable


## Resources of a biome: {kind: count}, dropped in patches of 2-5 so a find
## pays off; flint lies on the ground as items.
func _scatter(biome: String, counts: Dictionary) -> void:
	for kind in counts:
		var left := int(counts[kind])
		while left > 0:
			var c := _wild_spot(3.0, biome)
			if c == Vector3.INF:
				break
			var n := mini(left, randi_range(2, 5))
			left -= n
			for i in range(n):
				var p := c if i == 0 else _near_pos(c, 4.0, biome)
				if p != Vector3.INF:
					_place_resource(kind, p)


## The first finds: straw, twigs, flint and berries ring the clearing.
func _scatter_start() -> void:
	for spec in [["grass_tuft", 10], ["sapling", 8], ["flint", 5], ["berry_bush", 3]]:
		for i in range(int(spec[1])):
			for _t in range(20):
				var a := randf() * TAU
				var r := randf_range(10.0, 24.0)
				var p := Vector3(cos(a) * r, 0.0, sin(a) * r)
				if _good_spot(p, "flowered", 1.0):
					_place_resource(spec[0], p)
					break


## Small clusters beside a road every ~16 m, matching the biome they sit in.
func _scatter_verges(path: Array) -> void:
	var by_biome := {"flowered": ["grass_tuft", "sapling", "grass_tuft", "flint"], "gothic": ["grass_tuft", "flint", "mushroom"], "desert": ["grass_tuft", "dry_shrub", "flint"]}
	for i in range(path.size() - 1):
		var a: Vector2 = path[i]
		var b: Vector2 = path[i + 1]
		var steps := int(a.distance_to(b) / 16.0)
		var side := Vector2(-(b - a).y, (b - a).x).normalized()
		for k in range(steps):
			var at := a.lerp(b, (k + 0.5) / maxf(1.0, steps)) + side * randf_range(4.0, 7.0) * (1.0 if randf() < 0.5 else -1.0)
			var c := Vector3(at.x, 0.0, at.y)
			var biome := terrain.biome_at(c.x, c.z)
			if not _good_spot(c, biome, 1.5):
				continue
			var kinds: Array = by_biome.get(biome, by_biome.flowered)
			for j in range(randi_range(2, 3)):
				var p := c if j == 0 else _near_pos(c, 2.5, biome)
				if p != Vector3.INF:
					_place_resource(kinds.pick_random(), p)


func _place_resource(kind: String, p: Vector3) -> void:
	if kind == "flint":
		spawn_item("flint", 1, p)
	else:
		_spawn_resource(kind, p)


## A dry, gentle spot of the given biome (no dune crests, cliffs or water).
func _good_spot(p: Vector3, biome: String, trail_gap := 3.0) -> bool:
	if absf(p.x) > Cfg.WORLD - 4.0 or absf(p.z) > Cfg.WORLD - 4.0:
		return false
	if terrain.biome_at(p.x, p.z) != biome or not terrain.is_walkable(p.x, p.z) or terrain.is_water(p.x, p.z):
		return false
	if terrain.slope(p.x, p.z) > 0.9 or terrain.on_trail(p.x, p.z, trail_gap):
		return false
	if Vector2(p.x, p.z).distance_to(temple_center) < 25.0:
		return false
	return true


func _near_pos(c: Vector3, spread: float, biome: String) -> Vector3:
	for _t in range(8):
		var p := c + Vector3(randf_range(-spread, spread), 0.0, randf_range(-spread, spread))
		if _good_spot(p, biome, 1.0):
			return p
	return Vector3.INF


## Like _wild_spot, but always returns a land position (decor placement).
func _wild_pos(trail_gap := 3.0, biome := "flowered") -> Vector3:
	var p := _wild_spot(trail_gap, biome)
	return _rand_pos() if p == Vector3.INF else p


## A random gentle spot in a biome that keeps roads, clearings and landmarks
## readable. Vector3.INF when the biome has no room left (caller skips).
func _wild_spot(trail_gap := 3.0, biome := "flowered") -> Vector3:
	for _i in range(80):
		var p := _rand_pos()
		if not _good_spot(p, biome, trail_gap) or p.length() < 9.0:
			continue
		var p2 := Vector2(p.x, p.z)
		if p2.distance_to(shrine_center) < 8.0 or p.distance_to(_ruins_center()) < Cfg.RUINS_RADIUS + 2.0:
			continue
		if p2.distance_to(gothic_center) < 16.0 or p2.distance_to(obelisk_pos) < 6.0 or p2.distance_to(buried_temple) < 10.0:
			continue
		return p
	return Vector3.INF


func _solid(node: Node3D, radius: float) -> void:
	node.set_meta("solid", radius)


## The apprentice's clearing: a lantern landmark, a log seat, ferns framing
## the way out to the Lantern Trail, and a starter kit to learn the loop.
func _build_clearing(dir: Vector2) -> void:
	_solid(Lanna.lantern_post(decor_root, terrain.on_ground(Vector3(-2.5, 0, -2.5))).get_parent(), 0.4)
	_solid(Lanna.log_piece(decor_root, terrain.on_ground(Vector3(-3.8, 0, 0.6)), 2.4, 0.32, 0.6), 0.6)
	for i in range(18):  # fern ring, open toward the trail
		var a := TAU * i / 18.0
		var v := Vector2(cos(a), sin(a))
		if v.dot(dir) > 0.8:
			continue
		var r := randf_range(8.5, 10.5)
		Models.spawn_variant(decor_root, "undergrowth", terrain.on_ground(Vector3(v.x * r, 0, v.y * r)), randf_range(0.8, 1.2))
	for k in [["grass_tuft", Vector3(4, 0, 2)], ["grass_tuft", Vector3(5, 0, -1)], ["grass_tuft", Vector3(-1, 0, 5)],
			["sapling", Vector3(-4, 0, 3)], ["sapling", Vector3(-3, 0, -5)], ["berry_bush", Vector3(2, 0, 6)]]:
		_spawn_resource(k[0], k[1])
	spawn_item("flint", 1, Vector3(-2, 0, 4))
	spawn_item("flint", 1, Vector3(3, 0, -4))


## Stepping stones along a trail; the Lantern Trail also gets lantern posts
## and bamboo groves on alternating sides (wayfinding at night).
func _build_trail(points: Array, lanterns: bool) -> void:
	var walked := 0.0
	var next_lantern := 6.0
	var flip := 1.0
	for i in range(points.size() - 1):
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var seg := b - a
		var n := Vector2(-seg.y, seg.x).normalized()
		var d := 0.0
		while d < seg.length():
			var p := a + seg.normalized() * d + n * randf_range(-0.5, 0.5)
			var st := Models.spawn_variant(decor_root, "stepping_stone", terrain.on_ground(Vector3(p.x, 0, p.y)), randf_range(0.8, 1.1))
			if st != null:
				st.position.y += 0.02
			if lanterns and walked + d >= next_lantern:
				var lp := terrain.on_ground(Vector3(p.x + n.x * 2.6 * flip, 0, p.y + n.y * 2.6 * flip))
				_solid(Lanna.lantern_post(decor_root, lp).get_parent(), 0.35)
				var bp := Vector2(p.x, p.y) - n * 5.0 * flip + seg.normalized() * 2.0
				var grove := Lanna.bamboo(decor_root, terrain.on_ground(Vector3(bp.x, 0, bp.y)), randi_range(5, 9))
				_solid(grove, 1.0)
				flip = -flip
				next_lantern += 8.0
			d += randf_range(2.2, 3.2) if lanterns else randf_range(3.5, 5.0)
		walked += seg.length()


## The Shrine of the Sleeping Naga: a small ruined chedi, broken walls, two
## columns, lanterns and an altar stone holding the first grimoire page.
func _build_shrine(c: Vector2, dir: Vector2) -> void:
	var at := terrain.on_ground(Vector3(c.x, 0, c.y))
	var back := Vector3(dir.x, 0, dir.y)
	var ch := Lanna.chedi(decor_root, at + back * 3.0, 0.55, true)
	_solid(ch, 2.0)
	ch.set_meta("ruin", true)
	var side := Vector3(-dir.y, 0, dir.x)
	for s2 in [-1.0, 1.0]:
		var w := Lanna.wall(decor_root, terrain.on_ground(at + side * 5.0 * s2 + back * 1.0), 3.0, atan2(dir.x, dir.y))
		w.set_meta("ruin", true)
		var col := Models.spawn(decor_root, "column", terrain.on_ground(at + side * 2.5 * s2 - back * 2.0))
		if col != null:
			col.set_meta("ruin", true)
		_solid(Lanna.lantern_post(decor_root, terrain.on_ground(at + side * 3.5 * s2 - back * 3.5)).get_parent(), 0.35)
	var altar := Art.add_mesh(decor_root, Art.box(Vector3(1.4, 0.8, 0.9)), Art.mat(Lanna.PLASTER.darkened(0.15)), at + Vector3(0, 0.4, 0))
	_solid(altar, 0.7)
	_spawn_resource("page", at + Vector3(0, 0.0, 0) - back * 1.2)
	for i in range(6):
		Models.spawn_variant(decor_root, "undergrowth", terrain.on_ground(at + Vector3(randf_range(-7, 7), 0, randf_range(-7, 7)) + back * 4.0), randf_range(0.8, 1.2))


## The Temple of the Portal: a great chedi behind the Arcane Portal, broken
## brick walls in a ring, columns, rubble, lanterns and two grimoire pages.
func _build_temple(t: Vector2) -> void:
	var center := terrain.on_ground(Vector3(t.x, 0, t.y))
	var big := Lanna.chedi(decor_root, center + Vector3(0, 0, -7.0), 1.0, true)
	_solid(big, 3.6)
	big.set_meta("ruin", true)
	for i in range(8):
		var a := TAU * i / 8.0 + 0.2
		if i == 2:
			continue  # gap: the old trail comes in here
		var p := center + Vector3(cos(a), 0, sin(a)) * (Cfg.RUINS_RADIUS - 1.0)
		var w := Lanna.wall(decor_root, terrain.on_ground(p), randf_range(3.0, 5.0), -a + PI * 0.5)
		w.set_meta("ruin", true)
	for i in range(7):
		var piece := Models.spawn_variant(decor_root, "ruin", _ruins_pos())
		if piece != null:
			piece.set_meta("ruin", true)
	for i in range(4):
		var a2 := TAU * i / 4.0 + 0.8
		_solid(Lanna.lantern_post(decor_root, terrain.on_ground(center + Vector3(cos(a2), 0, sin(a2)) * 6.0)).get_parent(), 0.35)
	for i in range(2):
		_spawn_resource("page", _ruins_pos())
	portal = PortalScene.instantiate()
	portal.position = center
	decor_root.add_child(portal)


## The School-Temple: build it, scatter its loot, wake its guardian.
func _build_school_temple(c: Vector2, face_to: Vector2) -> void:
	var center := terrain.on_ground(Vector3(c.x, 0, c.y))
	var to_gate := (face_to - c).normalized()
	temple_info = SchoolTemple.build(self, center, atan2(to_gate.x, to_gate.y))
	var spots: Array = temple_info.loot.duplicate()
	var loot: Dictionary = Data.dungeon("temple").get("loot", {})
	for kind in loot:
		for i in range(int(loot[kind])):
			if spots.is_empty():
				break
			var at: Vector3 = spots.pop_front()
			if Data.resource(kind).is_empty():
				spawn_item(kind, 1, at)    # loose items (flint, essence, elixir)
			else:
				_spawn_resource(kind, at)  # mushrooms, berry bushes
	_spawn_guardian("temple")


func _spawn_guardian(id: String) -> void:
	var g = GuardianScript.new()
	g.setup(id, temple_info.arena)
	g.position = temple_info.arena
	guardians_root.add_child(g)


func guardians() -> Array:
	return _children(guardians_root) if guardians_root != null else []


## A guardian under attack, near `pos` (alive only), or null.
func guardian_near(pos: Vector3, reach: float):
	for g in guardians():
		if g.alive() and _hdist(g.position, pos) <= reach:
			return g
	return null


func guardian_woke(g) -> void:
	_announce("%s desperta! Marcas vermelhas no chão = golpe vindo: saia delas (anel: salte)." % g.display_name())
	discover("guardian")


func guardian_reset(g) -> void:
	_announce("%s voltou a dormir e se curou." % g.display_name())


func guardian_hit_player(g, p, attack: String) -> void:
	_say(p, "%s acertou: %s" % [g.display_name(), "golpe de cauda" if attack == "sweep" else "cuspe de jade"])


func _damage_guardian(p, g, amount: float) -> void:
	g.take_hit(amount)
	_pop(g.position + Vector3(0, 2.6, 0), "-%d" % int(amount), Color(1.0, 0.85, 0.4))
	if not g.alive():
		_on_guardian_defeated(g)


func _on_guardian_defeated(g) -> void:
	var id: String = g.dungeon_id
	dungeons[id]["cleared"] = true
	_open_seal()
	# the reward appears ONCE, as a normal item: saving/loading never duplicates it
	spawn_item(String(Data.dungeon(id).get("reward", "essence")), 1, temple_info.reward)
	_announce("%s foi vencida! O selo de jade se abriu: a recompensa está no santuário." % g.display_name())
	Fx.magic_puff(decor_root, g.position, Color(0.4, 1.0, 0.6), 40)
	_despawn(g)


func _open_seal() -> void:
	var seal = temple_info.get("seal")
	if seal != null and is_instance_valid(seal):
		seal.visible = false


## After loading: a cleared place stays cleared (no guardian, seal open).
func _sync_dungeons() -> void:
	if dungeons.get("temple", {}).get("cleared", false):
		_open_seal()
		for g in guardians():
			_despawn(g)


func _tick_dungeons(delta: float) -> void:
	var info: Dictionary = dungeons.get("temple", {})
	if local_player != null and not info.get("discovered", false) and not temple_info.is_empty():
		if _hdist(local_player.position, temple_info.arena) < float(Data.dungeon("temple").get("discover_radius", 24)):
			info["discovered"] = true
			exploration.reveal(temple_info.arena, 26.0)
			_announce("Descoberto: %s" % Data.dungeon("temple").get("name", ""))
	for g in guardians():
		g.tick(delta, self)
	if local_player != null:
		var g2 = null
		for g in guardians():
			if g.awake() and _hdist(g.position, local_player.position) < 22.0:
				g2 = g
		hud.set_boss(g2.display_name() if g2 != null else "", g2.hp if g2 != null else 0.0, g2.hp_max if g2 != null else 1.0)


## Woods, not noise: clusters of trees with undergrowth, a few lone trees,
## and bamboo groves near water; trails and clearings stay open.
func _build_forest() -> void:
	for c in range(26):
		var center := _wild_pos(7.0, "flowered")
		for k in range(randi_range(4, 7)):
			var p := terrain.on_ground(center + Vector3(randf_range(-6, 6), 0, randf_range(-6, 6)))
			if terrain.on_trail(p.x, p.z, 4.0) or p.length() < 10.0 or terrain.is_water(p.x, p.z):
				continue
			_spawn_resource("tree", p)
		for k in range(randi_range(3, 6)):
			var u := terrain.on_ground(center + Vector3(randf_range(-7, 7), 0, randf_range(-7, 7)))
			if not terrain.on_trail(u.x, u.z, 1.5) and not terrain.is_water(u.x, u.z):
				Models.spawn_variant(decor_root, "undergrowth", u, randf_range(0.8, 1.3))
	for i in range(12):
		_spawn_resource("tree", _wild_pos(5.0, "flowered"))
	for l in terrain.lakes.filter(func(x): return x.get("biome", "") == "flowered"):  # bamboo likes the water's edge
		for k in range(2):
			var a := randf() * TAU
			var r: float = l.radius + randf_range(2.5, 4.5)
			var bp := terrain.on_ground(Vector3(l.center.x + cos(a) * r, 0, l.center.y + sin(a) * r))
			if not terrain.is_water(bp.x, bp.z):
				_solid(Lanna.bamboo(decor_root, bp, randi_range(5, 8)), 1.0)
	var landmark := Models.spawn(decor_root, "qn_twisted_1", _wild_pos(8.0, "flowered"))  # the old banyan: a far landmark
	if landmark != null:
		_solid(landmark, 2.0)



## Lamp posts (old iron road) or cairns (waystones) along a long road.
func _build_road(points: Array, marker: String) -> void:
	var walked := 0.0
	var next_mark := 10.0
	var flip := 1.0
	for i in range(points.size() - 1):
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var seg := b - a
		var n := Vector2(-seg.y, seg.x).normalized()
		var d := 0.0
		while d < seg.length():
			if walked + d >= next_mark:
				var p := a + seg.normalized() * d + n * 2.8 * flip
				var at := terrain.on_ground(Vector3(p.x, 0, p.y))
				if marker == "lamp":
					var lamp := Models.spawn(decor_root, "post_lantern", at, 0.9)
					if lamp != null:
						Art.add_light(lamp, Color(1.0, 0.75, 0.45), 6.0, 1.0, Vector3(0, 2.6, 0))
						_solid(lamp, 0.35)
					next_mark += 16.0
				else:
					_solid(Lanna.cairn(decor_root, at), 0.5)
					next_mark += 18.0
				flip = -flip
			d += 2.0
		walked += seg.length()


## The gothic north-west: Sunken Cathedral, iron gate, statue garden, black
## roses, graves, dead trees, dark ponds, candles. Dark but readable.
func _build_gothic(c: Vector2, gate: Vector2) -> void:
	var stone := Color(0.42, 0.42, 0.46)
	var stone_dark := Color(0.3, 0.3, 0.34)
	var at := terrain.on_ground(Vector3(c.x, 0, c.y))
	var face := (gate - c).normalized()
	var yaw := atan2(face.x, face.y)
	var fwd := Vector3(face.x, 0, face.y)
	var right := Vector3(face.y, 0, -face.x)
	# Sunken Cathedral: two rows of pillars with arches, broken side walls, an apse
	for i in range(6):
		for s2 in [-1.0, 1.0]:
			var pp: Vector3 = at + right * 6.0 * s2 + fwd * (8.0 - i * 4.0)
			var pil := Models.spawn(decor_root, "ruin_pillar", terrain.on_ground(pp), 1.5)
			if pil != null:
				pil.set_meta("ruin", true)
				Models.tint(pil, Color(0.75, 0.75, 0.82))
			if i % 2 == 0:
				var w := Lanna.wall(decor_root, terrain.on_ground(at + right * 8.5 * s2 + fwd * (6.0 - i * 4.0)), 3.5, yaw, stone, stone_dark)
				w.set_meta("ruin", true)
	for i in range(3):
		var arch := Models.spawn(decor_root, "arch", terrain.on_ground(at + fwd * (8.0 - i * 8.0)), 1.6)
		if arch != null:
			arch.rotation.y = yaw
			Models.tint(arch, Color(0.7, 0.7, 0.78))
	var apse := Lanna.wall(decor_root, terrain.on_ground(at - fwd * 14.0), 12.0, yaw + PI * 0.5, stone, stone_dark)
	apse.set_meta("ruin", true)
	for i in range(5):
		var cn := Models.spawn(decor_root, ["candles", "skull_candle"].pick_random(), terrain.on_ground(at - fwd * 11.0 + right * (i - 2) * 1.8), 1.2)
		if cn != null and i % 2 == 0:
			Art.add_light(cn, Color(1.0, 0.65, 0.35), 5.0, 1.0, Vector3(0, 1.0, 0))
	# iron gate on the road
	var g := Models.spawn(decor_root, "arch_gate", terrain.on_ground(Vector3(gate.x, 0, gate.y)), 1.7)
	if g != null:
		g.rotation.y = yaw
		Models.tint(g, Color(0.6, 0.6, 0.66))
	for s3 in [-1.0, 1.0]:
		var gl := Models.spawn(decor_root, "post_lantern", terrain.on_ground(Vector3(gate.x, 0, gate.y) + right * 4.2 * s3), 1.0)
		if gl != null:
			Art.add_light(gl, Color(0.75, 0.8, 1.0), 7.0, 1.1, Vector3(0, 2.6, 0))
			_solid(gl, 0.35)
		for k in range(4):  # iron fence running away from the gate
			var fp := terrain.on_ground(Vector3(gate.x, 0, gate.y) + right * (6.5 + k * 4.0) * s3)
			var fence := Models.spawn(decor_root, ["fence_broken", "fence_post"].pick_random(), fp, 1.0)
			if fence != null:
				fence.rotation.y = yaw
				fence.set_meta("ruin", true)
	# statue garden: frozen guardians on plinths beside the cathedral
	for i in range(6):
		var sp := terrain.on_ground(at + right * 16.0 + fwd * (8.0 - i * 4.5))
		var pl := Lanna.plinth(decor_root, sp)
		_solid(pl, 0.9)
		var st := Models.spawn(pl, ["skeleton_mage", "skeleton", "skeleton_boss"].pick_random(), Vector3(0, 1.35, 0), 0.75 if i % 3 != 2 else 0.5)
		if st != null:
			Models.overlay(st, null)
			for mi in st.find_children("*", "MeshInstance3D", true, false):
				(mi as MeshInstance3D).material_override = Art.mat(Color(0.5, 0.5, 0.54))
			st.rotation.y = -yaw
		Lanna.black_roses(decor_root, terrain.on_ground(sp + fwd * 2.0 + right * 1.5))
	# graves, dead trees and dark firs across the biome
	for i in range(30):
		var p := _wild_pos(2.0, "gothic")
		Models.cull(Models.spawn(decor_root, ["gravestone", "grave_a", "grave_b", "gravemarker_a", "gravemarker_b", "grave_a_broken"].pick_random(), p, 1.0), 80.0)
	for i in range(24):
		Lanna.black_roses(decor_root, _wild_pos(2.0, "gothic"))
	for i in range(70):  # dark hedges, ferns and wild grass between the ruins
		var gp := _wild_pos(1.5, "gothic")
		var hedge := Models.spawn(decor_root, ["qn_bush", "qn_fern", "qn_plant_1"].pick_random(), gp, randf_range(0.9, 1.5))
		Models.tint(hedge, Color(0.35, 0.45, 0.42))
		Models.cull(hedge, 80.0)
	for i in range(12):  # broken columns and fence remains along the way
		var cp := _wild_pos(3.0, "gothic")
		var piece := Models.spawn(decor_root, ["ruin_pillar", "fence_broken", "fence_post", "column"].pick_random(), cp, randf_range(0.9, 1.3))
		if piece != null:
			Models.tint(piece, Color(0.7, 0.7, 0.78))
			piece.rotation.y = randf() * TAU
			piece.set_meta("ruin", true)
	for i in range(22):
		var dt := Models.spawn(decor_root, ["dead_l", "dead_m", "dead_l_deco"].pick_random(), _wild_pos(4.0, "gothic"), randf_range(1.2, 1.8))
		if dt != null:
			_solid(dt, 0.5)


## The magic desert north-east: dunes (terrain), the Great Obelisk landmark,
## a buried temple, crystal fields, sandstone mesas, cairns, bones, the oasis.
func _build_desert(c: Vector2) -> void:
	_solid(Lanna.obelisk(decor_root, terrain.on_ground(Vector3(obelisk_pos.x, 0, obelisk_pos.y))), 2.2)
	var bt := terrain.on_ground(Vector3(buried_temple.x, 0, buried_temple.y))
	var sunk := Lanna.chedi(decor_root, bt + Vector3(0, -2.2, -3.0), 0.8, true)
	Models.tint(sunk, Color(1.15, 1.0, 0.85))
	_solid(sunk, 2.6)
	sunk.set_meta("ruin", true)
	for i in range(6):
		var a := TAU * i / 6.0
		var col := Models.spawn(decor_root, "column", terrain.on_ground(bt + Vector3(cos(a), 0, sin(a)) * 7.0) + Vector3(0, -randf_range(0.3, 1.2), 0), 1.0)
		if col != null:
			col.rotation.z = randf_range(-0.25, 0.25)
			col.set_meta("ruin", true)
			Models.tint(col, Color(1.2, 1.0, 0.8))
	for k in range(6):  # crystal field
		var cp := terrain.on_ground(Vector3(c.x - 34.0, 0, c.y + 8.0) + Vector3(randf_range(-10, 10), 0, randf_range(-10, 10)))
		_solid(Lanna.crystals(decor_root, cp, randi_range(4, 8), [Color(0.45, 0.85, 1.0), Color(0.75, 0.5, 1.0)].pick_random()), 0.9)
	for i in range(18):  # sandstone mesas
		var mp := _wild_pos(6.0, "desert")
		var mesa := Models.spawn(decor_root, "qn_rock_" + str(randi_range(1, 3)), mp, randf_range(2.2, 3.8))
		if mesa != null:
			mesa.rotation.y = randf() * TAU
			Models.tint(mesa, Color(1.35, 1.0, 0.72))
			_solid(mesa, 2.6)
	for i in range(45):
		var dp := _wild_pos(2.0, "desert")
		var prop := Models.spawn(decor_root, ["ribcage", "bone_c", "dead_s", "dead_s", "qn_rock_2", "qn_pebble_2"].pick_random(), dp, randf_range(0.7, 1.4))
		if prop != null and String(prop.name).begins_with("Rock"):
			Models.tint(prop, Color(1.35, 1.0, 0.72))
		Models.cull(prop, 80.0)
	for i in range(10):  # lone crystal outcrops reward wandering off the path
		_solid(Lanna.crystals(decor_root, _wild_pos(4.0, "desert"), randi_range(3, 5), [Color(0.45, 0.85, 1.0), Color(0.75, 0.5, 1.0)].pick_random()), 0.8)
	for l in terrain.lakes.filter(func(x): return x.get("biome", "") == "desert"):
		for k in range(3):  # bamboo and reeds ring the oasis
			var a2 := randf() * TAU
			var r: float = l.radius + randf_range(2.0, 4.0)
			_solid(Lanna.bamboo(decor_root, terrain.on_ground(Vector3(l.center.x + cos(a2) * r, 0, l.center.y + sin(a2) * r)), randi_range(4, 7)), 1.0)


## New island, same apprentices (knowledge persists).
func restart() -> void:
	exploration = Exploration.new(Cfg.WORLD)
	_last_reveal = Vector3(INF, 0, INF)
	if world_map != null:
		world_map.invalidate()
	run_hearts = 0
	won = false
	game_over = false
	day_night.reset()
	_generate_world()
	for p in players():
		p.respawn(_spawn_spot(p.slot), meta.knows("eco"))
	hud.hide_end()
	_generate_world()


# ---------- main loop ----------

func _process(delta: float) -> void:
	tick(delta)


func tick(delta: float) -> void:
	if Dev.has("fps"):
		_fps_t += delta
		if _fps_t > 3.0:
			_fps_frames += 1
			if _fps_t > 9.0 and not _fps_done:
				_fps_done = true
				print("FPS avg (3-9 s): %.1f over %d frames" % [_fps_frames / (_fps_t - 3.0), _fps_frames])
	if shot_timer > 0.0:
		shot_timer -= delta
		if shot_timer <= 0.0:
			get_viewport().get_texture().get_image().save_png(shot_path)
			print("MAGIC_SHOT saved: ", shot_path)
			if Dev.has("quit-after-shot"):
				get_tree().quit()
	if state == "menu" or state == "select":
		# main-menu backdrop: slow orbit over the island at dusk
		camera_rig.orbit(delta)
		var l: float = day_night.light()
		day_night.apply_visuals(l)
		fireflies.emitting = l < 0.45
		return
	if not started or state == "paused":
		return
	if won or game_over:
		camera_rig.follow(delta)
		return

	day_night.advance(delta)
	var lit: float = day_night.light()
	var night := lit < 0.35
	if local_player != null and not local_player.dead:
		_drive_local(delta)
	for p in players():
		if not p.dead:
			var note: String = p.tick_stats(delta)
			if note != "":
				_say(p, note)
			if p.tick_darkness(is_lit(p.position, lit), night, delta) and p.dark_t < Cfg.DARK_WARN_AT:
				discover("darkness")
				_say(p, "A Névoa te arranha no escuro! Acenda uma luz!")
		p.update_wisp_light(lit)
	var mix := Vector3(1, 0, 0)
	if local_player != null:
		ambient.position = local_player.position
		mix = terrain.biome_mix(local_player.position.x, local_player.position.z)
	day_night.apply_visuals(lit, mix)
	fireflies.emitting = lit < 0.45
	leaves.emitting = lit > 0.5 and mix.x > 0.5  # falling leaves only in the flowered south

	for fire in structures_of("campfire"):
		fire.burn(delta)
	for g in resources():
		if not g.grown:
			g.tick_regrow(delta)
		elif g.kind == "sapling" and g.tick_grow(delta):
			var at: Vector3 = g.position
			_despawn(g)
			_spawn_resource("tree", at)

	# Errantes rise at night: a few always, many more where magic is loud
	var loud := _max_noise()
	var cap := int(float(Data.night("cap_base", 5)) + loud * float(Data.night("cap_per_noise", 0.3)))
	if night and shadows_root.get_child_count() < mini(cap, Cfg.SHADOW_CAP):
		var rate: float = float(Data.night("base_rate", 0.12)) + loud * float(Data.night("noise_rate", 0.03)) + _team_corruption() * float(Data.night("corruption_rate", 0.01))
		if day_night.blood_moon:
			rate *= 2.0
		if randf() < rate * delta:
			spawn_shadow()

	_tick_dungeons(delta)
	for s in shadows():
		s.tick(delta, self, lit, day_night.t)
		if s.hp <= 0.0:
			_on_shadow_death(s)

	_check_deaths()

	if placing != "":
		_update_placement()
	_obj_done_t = maxf(0.0, _obj_done_t - delta)
	_update_objectives(local_player)
	if local_player != null and exploration != null and local_player.position.distance_to(_last_reveal) > 3.0:
		_last_reveal = local_player.position
		exploration.reveal(local_player.position)
	_update_focus()
	camera_rig.follow(delta)
	hud.refresh(local_player, self)


func _drive_local(delta: float) -> void:
	var mv := Vector3.ZERO
	if map_open():
		local_player.move(Vector3.ZERO, delta)
		return
	if _autopilot and (Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_D)
			or Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_RIGHT)):
		_autopilot = false  # a human took the controls: never fight their input
	if _autopilot:
		var pts: Array = trail + [shrine_center]
		if _auto_i < pts.size():
			var goal: Vector2 = pts[_auto_i]
			var to := goal - Vector2(local_player.position.x, local_player.position.z)
			if to.length() < 2.0:
				_auto_i += 1
			mv = Vector3(to.x, 0, to.y).normalized()
			camera_rig.angle = lerp_angle(camera_rig.angle, atan2(-mv.x, -mv.z), 1.5 * delta)
		_auto_jump_t -= delta
		if _auto_jump_t <= 0.0:
			_auto_jump_t = 2.2
			local_player.jump()
		local_player.move(mv, delta)
		return
	var manual := Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_D) \
			or Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_RIGHT)
	if _approach != null:
		_approach_t -= delta
		if manual or _approach_t <= 0.0 or not is_instance_valid(_approach) or not _approach.is_inside_tree() or not _approach.grown:
			_approach = null
		elif _hdist(local_player.position, _approach.position) <= Cfg.INTERACT_RADIUS * 0.8:
			_approach = null
			_interact(local_player)
		else:
			var to: Vector3 = _approach.position - local_player.position
			local_player.move(Vector3(to.x, 0, to.z).normalized(), delta)
			return
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		mv += camera_rig.forward()
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		mv -= camera_rig.forward()
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		mv += camera_rig.right()
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		mv -= camera_rig.right()
	local_player.move(mv, delta)
	# camera rotate (Don't Starve style): Q left, PageUp right
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
		_show_end_menu(false)


func _on_night_start(blood_moon: bool) -> void:
	if blood_moon:
		discover("blood_moon")
		_announce("LUA DE SANGUE! Algo grande caça vocês esta noite.")
		spawn_shadow(true)
	elif day_night.nights == 0:
		discover("first_night")
		hud.flash("Primeira noite: os ERRANTES despertam e caçam MAGIA. Quieto, eles só te notam de perto. Cada feitiço ou poção faz RUÍDO e os atrai de longe. A luz os queima, mas sem luz nenhuma a Névoa fere.", 10.0)
	else:
		_announce("A Névoa desce. Errantes vagam: cuidado com o ruído da magia.")


func _on_dawn(nights: int) -> void:
	meta.record_nights(nights)
	save_run()  # autosave every dawn
	_announce("Amanheceu. Noites sobrevividas: %d" % nights)


func _on_shadow_death(s) -> void:
	var who = s.last_hitter
	if who != null and not is_instance_valid(who):
		who = null
	var at: Vector3 = s.position
	if s.boss:
		run_hearts += 1
		for id in BOSS_DROPS:
			spawn_item(id, BOSS_DROPS[id], at + Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5)))
		discover("heart")
		_announce("O CORAÇÃO DA NÉVOA CAIU! (corações: %d/%d p/ o Portal) Recolha o butim." % [run_hearts, Cfg.PORTAL_HEARTS])
	elif who != null:
		for id in DROP_TABLE:
			if randf() < DROP_TABLE[id]:
				spawn_item(id, 1, at + Vector3(randf_range(-0.8, 0.8), 0, randf_range(-0.8, 0.8)))
		_say(who, "O Errante se desfez e deixou restos")
	_despawn(s)


# ---------- messages ----------

func _say(p, text: String) -> void:
	if p == local_player and text != "":
		hud.flash(text)


func _announce(text: String) -> void:
	hud.flash(text)


# ---------- actions ----------

## QA scenes (dev only): stage a situation for a screenshot / playtest.
func _stage_scene(scene: String) -> void:
	var p = local_player
	if p == null:
		return
	match scene:
		"night":
			for i in range(4):
				var s = spawn_shadow()
				var a := TAU * i / 4.0 + 0.4
				s.position = terrain.on_ground(p.position + Vector3(cos(a), 0, sin(a)) * randf_range(9.0, 13.0)) + Vector3(0, s.hover_height(), 0)
			p.noise = 40.0
		"camp":
			give(p, {"grass": 6, "log": 4, "rock": 6, "flint": 4, "twig": 6})
			craft(p, "campfire")
		"temple", "naga", "naga-spit", "temple-map":
			# the School-Temple: gate view · the guardian telegraphing · the map
			var arena: Vector3 = temple_info.arena
			var gate: Vector3 = temple_info.gate
			var inward := (arena - gate).normalized()
			if scene == "temple":
				p.position = terrain.on_ground(gate - inward * 4.0)
				camera_rig.zoom = 1.45
			else:
				p.position = terrain.on_ground(arena + inward * -4.5)
				camera_rig.zoom = 1.2
			camera_rig.angle = atan2(-inward.x, -inward.z)
			camera_rig._snapped = false
			_tick_dungeons(0.1)
			if scene == "naga" or scene == "naga-spit":
				var g = guardians()[0]
				g.tick(0.1, self)
				g._set_state("chase", 0.0)
				g.take_hit(70.0)
				g._start("sweep" if scene == "naga" else "spit", 30.0, p.position - g.position)
			if scene == "temple-map":
				_damage_guardian(p, guardians()[0], 9999.0)
				exploration.reveal(p.position, 40.0)
				toggle_map()
		"gather", "nogear":
			# the interaction prompt over the nearest straw / tree, a gain pop-up
			# and the Light tab with live ingredient counts
			var kind := "grass_tuft" if scene == "gather" else "tree"
			var best = null
			for g in resources_of(kind):
				if best == null or _hdist(g.position, p.position) < _hdist(best.position, p.position):
					best = g
			if best != null:
				var off := Vector3(2.2, 0, 2.2) if kind == "tree" else Vector3(1.6, 0, 1.6)
				p.position = terrain.on_ground(best.position + off)
				p.face(best.position)
			give(p, {"grass": 1, "twig": 2})
			_pop(p.position + Vector3(0, 2.4, 0), "+1 Palha", Color(0.75, 1.0, 0.6))
			hud.toggle_crafting()
			hud._select_tab("Luz")
			camera_rig.zoom = 0.8
		"trail", "walk":
			# stand on the Lantern Trail looking toward the shrine
			var t0: Vector2 = trail[0]
			var tdir := (shrine_center - t0).normalized()
			p.position = terrain.on_ground(Vector3(t0.x, 0, t0.y) + Vector3(tdir.x, 0, tdir.y) * 2.0)
			camera_rig.angle = atan2(-tdir.x, -tdir.y)
			camera_rig._snapped = false
			if scene == "walk":
				_autopilot = true
		"gothic", "desert":
			var target: Vector2 = gothic_center if scene == "gothic" else desert_center
			var from := target + (Vector2.ZERO - target).normalized() * 20.0
			p.position = terrain.on_ground(Vector3(from.x, 0, from.y))
			var look := (target - from).normalized()
			camera_rig.angle = atan2(-look.x, -look.y)
			camera_rig._snapped = false
			camera_rig.zoom = 1.3
		"overview":
			camera_rig.zoom = 1.45
		"shrine":
			var sd := shrine_center.normalized()
			p.position = terrain.on_ground(Vector3(shrine_center.x, 0, shrine_center.y) - Vector3(sd.x, 0, sd.y) * 9.0)
			camera_rig.angle = atan2(-sd.x, -sd.y)
			camera_rig._snapped = false
		"place":
			give(p, {"grass": 3, "log": 2})
			hud.toggle_crafting()
			craft(p, "campfire")


# ---------- world map (M) ----------

func map_open() -> bool:
	return world_map != null and world_map.visible


func toggle_map() -> void:
	if map_open():
		world_map.close()
	elif state == "playing" and exploration != null:
		cancel_placement()
		world_map.open()


## Landmarks shown on the map once their area has been explored.
func map_landmarks() -> Array:
	var out := [
		{"name": "Clareira do Aprendiz", "pos": Vector3(0, 0, 0), "color": Color(0.45, 0.85, 0.45)},
		{"name": "Santuário da Naga", "pos": Vector3(shrine_center.x, 0, shrine_center.y), "color": Color(0.95, 0.6, 0.3)},
		{"name": "Templo do Portal", "pos": _ruins_center(), "color": Color(0.7, 0.45, 1.0)},
		{"name": "Catedral Afundada", "pos": Vector3(gothic_center.x, 0, gothic_center.y), "color": Color(0.6, 0.6, 0.75)},
		{"name": "Grande Obelisco", "pos": Vector3(obelisk_pos.x, 0, obelisk_pos.y), "color": Color(0.4, 0.9, 1.0)},
		{"name": "Templo Soterrado", "pos": Vector3(buried_temple.x, 0, buried_temple.y), "color": Color(0.9, 0.7, 0.4)},
	]
	var temple: Dictionary = dungeons.get("temple", {})
	if temple.get("discovered", false) and not temple_info.is_empty():
		out.append({"name": Data.dungeon("temple").get("name", ""), "pos": temple_info.arena, "color": Color(0.35, 1.0, 0.55),
			"status": "cleared" if temple.get("cleared", false) else "explored"})
	for l in terrain.lakes.filter(func(x): return x.get("biome", "") == "desert"):
		out.append({"name": "Oásis", "pos": Vector3(l.center.x, 0, l.center.y), "color": Color(0.3, 0.7, 1.0)})
	return out


## Left click on the map: add a pin, or remove one near the click (explored areas only).
func map_toggle_marker(at: Vector3) -> void:
	if not exploration.is_discovered(at):
		_announce("Só dá pra marcar áreas já exploradas")
		return
	_announce("Marcador adicionado" if exploration.toggle_marker(at) else "Marcador removido")


## Right click on the map: the nearest structure (within 8 m) becomes the base.
func map_set_base(at: Vector3) -> bool:
	var best = null
	var bd := 8.0
	for st in _children(structures_root):
		var d := Vector2(st.position.x - at.x, st.position.z - at.z).length()
		if d < bd and exploration.is_discovered(st.position):
			bd = d
			best = st
	if best == null:
		_announce("Clique com o botão direito sobre uma construção para torná-la a base")
		return false
	exploration.set_base(best.kind, best.position)
	_announce("Base definida: %s" % Data.display_name(best.kind))
	return true


## F11 / Alt+Enter: fullscreen <-> window (the HUD scales with the window).
func toggle_fullscreen() -> void:
	var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)


## Single entry point for every apprentice action (network-ready).
## Actions: interact · bolt · lume · shield · use:<slot> · alt:<slot> ·
## craft:<recipe id> · unequip:hand
func perform(p, action: String) -> void:
	if p == null or p.dead or won or game_over:
		return
	var parts := action.split(":")
	match parts[0]:
		"interact":
			_interact(p)
		"jump":
			p.jump()
		"use":
			var before: float = p.noise
			_say(p, p.use_slot(int(parts[1])))
			if p.noise > before + 0.5:  # potions / essence are loud: show it
				Fx.noise_ring(self, p.position, p.heard_from())
		"alt":
			_alt_use(p, int(parts[1]))
		"craft":
			craft(p, parts[1])
		"unequip":
			_say(p, p.unequip_hand())
		"lume":
			_cast_lume(p)
		"shield":
			_cast_shield(p)
		"bolt":
			_cast_bolt(p)


## Why a recipe can't be crafted right now ("" = it can).
func craft_blocker(p, rid: String) -> String:
	var r := Data.recipe(rid)
	if r.is_empty():
		return "Receita desconhecida"
	var tech := Data.recipe_tech(r)
	if tech != "" and near_structure(p, tech) == null:
		return "Precisa estar perto de: %s" % Data.display_name(tech)
	if not p.inventory.has_all(r.cost):
		return "Faltam materiais"
	return ""


func craft(p, rid: String) -> bool:
	var why := craft_blocker(p, rid)
	if why != "":
		_say(p, why)
		return false
	var r := Data.recipe(rid)
	if r.get("structure", false) and p == local_player:
		_begin_placement(rid)
		return true
	p.inventory.pay(r.cost)
	p.play_action("build")
	if Data.tab_tech(r.tab) != "" or rid == "altar" or rid == "ward":  # magic work hums
		emit_noise(p, float(Data.night("noise", {}).get("magic_build" if r.get("structure", false) else "magic_craft", 12)))
	if r.get("structure", false):
		var fwd: Vector3 = camera_rig.forward() if p == local_player else Vector3(0, 0, 1)
		var mult: float = p.perk("fire_mult") if rid == "campfire" else 1.0
		spawn_structure(rid, p.position + fwd * 2.2, mult)
		_say(p, "Construiu: %s" % Data.display_name(rid))
	else:
		give(p, {rid: 1})
		_say(p, "Criou: %s" % Data.display_name(rid))
	return true


# ---------- collision (apprentices only; Errantes are spectral) ----------

## Pushes a walker at pos out of trees, rocks, bushes, structures, ruins and
## the Portal, so apprentices slide around obstacles instead of through them.
func resolve_collision(pos: Vector3, radius := 0.45) -> Vector3:
	var p2 := Vector2(pos.x, pos.z)
	for g in resources():
		if g.grown and SOLID.has(g.kind):
			p2 = _push_out(p2, Vector2(g.position.x, g.position.z), float(SOLID[g.kind]) + radius)
	for st in _children(structures_root):
		p2 = _push_out(p2, Vector2(st.position.x, st.position.z), _footprint(st.kind) * 0.7 + radius)
	for d in decor_root.get_children():
		if d.has_meta("solid"):
			p2 = _push_out(p2, Vector2(d.global_position.x, d.global_position.z), float(d.get_meta("solid")) + radius)
		elif d.has_meta("ruin") and d is Node3D and not d.has_meta("solid"):
			p2 = _push_out(p2, Vector2(d.position.x, d.position.z), 0.8 + radius)
	for b in _solid_boxes:
		if b.node != null and (not is_instance_valid(b.node) or not b.node.visible):
			continue  # an opened seal no longer blocks
		p2 = _push_out_box(p2, b.c, b.rot, b.half, radius)
	if portal != null:
		for side in [-2.0, 2.0]:  # the two arch posts; walk through the middle
			p2 = _push_out(p2, Vector2(portal.position.x + side, portal.position.z), 0.6 + radius)
	return Vector3(p2.x, pos.y, p2.y)


## Registers a rotated box collider (walls, pillars) at a world position.
## `node` (optional): the collider only blocks while that node is visible.
func add_solid_box(at: Vector3, half: Vector2, rot: float, node: Node3D = null) -> void:
	_solid_boxes.append({"c": Vector2(at.x, at.z), "half": half, "rot": rot, "node": node})


## Pushes a circle (radius) out of a box rotated `rot` around Y.
static func _push_out_box(p: Vector2, c: Vector2, rot: float, half: Vector2, radius: float) -> Vector2:
	var local := (p - c).rotated(rot)   # world (x, z) -> box space
	var q := Vector2(clampf(local.x, -half.x, half.x), clampf(local.y, -half.y, half.y))
	var diff := local - q
	var dist := diff.length()
	if dist >= radius:
		return p
	if dist > 0.0001:
		local = q + diff / dist * radius
	elif half.x - absf(local.x) < half.y - absf(local.y):  # inside: leave by the shallowest side
		local.x = signf(local.x if local.x != 0.0 else 1.0) * (half.x + radius)
	else:
		local.y = signf(local.y if local.y != 0.0 else 1.0) * (half.y + radius)
	return c + local.rotated(-rot)


func _push_out(p: Vector2, center: Vector2, min_dist: float) -> Vector2:
	var d := p - center
	var len := d.length()
	if len >= min_dist:
		return p
	if len < 0.001:
		d = Vector2(1, 0)
		len = 1.0
	return center + d / len * min_dist


# ---------- structure placement (preview, validation) ----------

func _footprint(kind: String) -> float:
	return float(FOOTPRINT.get(kind, 1.4))


## Why a structure can't stand at pos ("" = it can): water, steep ground,
## trees/rocks, other structures, the Portal and the temple ruins.
func placement_blocker(kind: String, pos: Vector3) -> String:
	var fp := _footprint(kind)
	if absf(pos.x) > Cfg.WORLD - 1.0 or absf(pos.z) > Cfg.WORLD - 1.0:
		return "Fora da ilha"
	var h := terrain.height_at(pos.x, pos.z)
	for o in [Vector2(fp, 0), Vector2(-fp, 0), Vector2(0, fp), Vector2(0, -fp)]:
		var h2 := terrain.height_at(pos.x + o.x, pos.z + o.y)
		if h2 < terrain.water_level + 0.1:
			return "Muito perto da água"
		if absf(h2 - h) > 0.9:
			return "Terreno inclinado demais"
	if h < terrain.water_level + 0.1:
		return "Não dá pra construir na água"
	for st in _children(structures_root):
		if Vector2(st.position.x - pos.x, st.position.z - pos.z).length() < fp + _footprint(st.kind):
			return "Sobrepõe outra construção"
	for g in resources():
		if g.kind in ["tree", "rock", "berry_bush", "page"] and Vector2(g.position.x - pos.x, g.position.z - pos.z).length() < fp + 0.8:
			return "Tem árvore ou rocha no caminho"
	if portal != null and Vector2(portal.position.x - pos.x, portal.position.z - pos.z).length() < fp + 3.5:
		return "Muito perto do Portal"
	for ruin in pillars():
		if Vector2(ruin.position.x - pos.x, ruin.position.z - pos.z).length() < fp + 1.5:
			return "Ruínas no caminho"
	return ""


func _placement_spot(p) -> Vector3:
	var reach := 2.2 + _footprint(placing)
	return terrain.on_ground(p.position + camera_rig.forward() * reach)


func _begin_placement(rid: String) -> void:
	cancel_placement()
	placing = rid
	_ghost_ok_mat = _ghost_mat(Color(0.35, 1.0, 0.45, 0.45))
	_ghost_bad_mat = _ghost_mat(Color(1.0, 0.3, 0.25, 0.45))
	_ghost = Node3D.new()
	add_child(_ghost)
	ItemArt.build(_ghost, rid)
	var disc := CylinderMesh.new()  # footprint on the ground: green ok / red blocked
	disc.top_radius = _footprint(rid)
	disc.bottom_radius = _footprint(rid)
	disc.height = 0.05
	var dmi := MeshInstance3D.new()
	dmi.mesh = disc
	dmi.position.y = 0.06
	_ghost.add_child(dmi)
	_update_placement()
	_announce("Posicione: %s  ·  E ou clique confirma  ·  Esc ou botão direito cancela" % Data.display_name(rid))


func _ghost_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = c
	return m


func _update_placement() -> void:
	if placing == "" or local_player == null:
		return
	var pos := _placement_spot(local_player)
	_ghost.position = pos
	place_why = placement_blocker(placing, pos)
	place_ok = place_why == ""
	for mi in _ghost.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = _ghost_ok_mat if place_ok else _ghost_bad_mat


## Builds the previewed structure if the spot is valid (pays the cost then).
func confirm_placement() -> bool:
	if placing == "":
		return false
	_update_placement()
	var p = local_player
	if not place_ok:
		_say(p, "Não dá pra construir aqui: " + place_why)
		return false
	var rid := placing
	var why := craft_blocker(p, rid)
	if why != "":
		_say(p, why)
		cancel_placement()
		return false
	p.inventory.pay(Data.recipe(rid).cost)
	p.play_action("build")
	if Data.tab_tech(Data.recipe(rid).tab) != "" or rid == "altar" or rid == "ward":
		emit_noise(p, float(Data.night("noise", {}).get("magic_build", 20)))
	spawn_structure(rid, _ghost.position, p.perk("fire_mult") if rid == "campfire" else 1.0)
	cancel_placement()
	_say(p, "Construiu: %s" % Data.display_name(rid))
	return true


func cancel_placement() -> void:
	placing = ""
	if _ghost != null:
		_ghost.queue_free()
		_ghost = null


## Secondary use (right click / Shift+number): cook food or feed a fire when
## next to a burning campfire, otherwise drop the stack on the ground.
func _alt_use(p, i: int) -> void:
	var s = p.inventory.slots[i]
	if s == null:
		return
	var d := Data.item(s.id)
	var fire = near_campfire(p, true)
	var embers = near_campfire(p, false)
	if fire != null and d.has("cooked"):
		p.inventory.take_from(i)
		give(p, {d.cooked: 1})
		p.play_action("build")
		_say(p, "Assou: %s" % Data.item_name(d.cooked))
	elif embers != null and d.has("fuel"):
		var was_out: bool = not embers.burning()
		p.inventory.take_from(i)
		embers.add_fuel(float(d.fuel) * p.perk("fire_mult"))
		p.play_action("build")
		_say(p, "Reacendeu a fogueira" if was_out else "Alimentou a fogueira")
	else:
		var stack: Dictionary = p.inventory.take_from(i, s.count)
		spawn_item(stack.id, stack.count, p.position + Vector3(0.8, 0, 0.8), stack)
		_say(p, "Largou: %s" % Data.item_name(stack.id))


static func _hdist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## The resource E would act on: nearest grown one within FOCUS_RADIUS
## (horizontal distance, so slopes and hops don't hide it).
func interact_target(p):
	var best = null
	var bd := Cfg.FOCUS_RADIUS
	for g in resources():
		if not g.grown:
			continue
		var d := _hdist(p.position, g.position)
		if d < bd:
			bd = d
			best = g
	return best


## Why E on `g` would fail right now ("" = it works). Distance is not a
## blocker: the apprentice walks over first.
func interact_blocker(p, g) -> String:
	var tool: String = g.tool_needed()
	if tool != "" and p.inventory.hand_data().get("tool", "") != tool:
		return "Precisa de %s (crie em Tab → Ferramentas)" % ("um Machado equipado" if tool == "axe" else "uma Picareta equipada")
	if g.kind == "item" and not g.item_stack.is_empty():
		if p.inventory.space_for(g.item_stack.get("id", "")) <= 0 and not p.inventory.slots.has(null):
			return "Inventário cheio: use ou largue algo (botão direito no item)"
	elif g.kind != "page" and (tool == "" or g.hp <= int(p.perk("strike_power"))) and not p.inventory.can_fit(g.gives()):
		return "Inventário cheio: use ou largue algo (botão direito no item)"
	return ""


## Prompt shown over the target: "E — Coletar Tufo de palha".
func interact_prompt(g) -> String:
	var text := "E — %s %s" % [g.verb(), g.display_name()]
	if g.tool_needed() != "":
		text += "  (%d golpe%s)" % [g.hp, "" if g.hp == 1 else "s"]
	return text


## E next to a guardian: a blow (tools hit harder, Thorne twice as hard).
func _strike_guardian(p, g) -> void:
	p.face(g.position)
	p.play_action("chop")
	var dmg := float(Data.dungeon(g.dungeon_id).get("guardian", {}).get("melee_damage", 10)) * float(p.perk("strike_power"))
	if p.inventory.hand_data().has("tool"):
		dmg *= 1.5
	_sfx(p, "thud")
	_damage_guardian(p, g, dmg)


func _interact(p) -> void:
	# E: strike a guardian, pick, chop (axe), mine (pickaxe), grab loot, or touch the Portal
	var foe = guardian_near(p.position, 2.8)
	if foe != null:
		_strike_guardian(p, foe)
		return
	var best = interact_target(p)
	var bd: float = _hdist(p.position, best.position) if best != null else Cfg.FOCUS_RADIUS
	if portal != null:
		var pd: float = _hdist(p.position, portal.position)
		if pd < Cfg.PORTAL_RADIUS and pd < bd:
			_try_portal(p)
			return
	if best == null:
		_deny(p, "Nada para coletar por perto: procure palha dourada, mudas e pedrinhas")
		return
	var why := interact_blocker(p, best)
	if why != "":
		p.face(best.position)
		_deny(p, why, best.position)
		return
	if bd > Cfg.INTERACT_RADIUS:
		if p == local_player:  # walk over, then act (cancelled by WASD)
			_approach = best
			_approach_t = 4.0
		else:
			_deny(p, "Longe demais: chegue mais perto", best.position)
		return

	var kind: String = best.kind
	var tool: String = best.tool_needed()
	p.face(best.position)
	p.play_action("chop" if tool != "" else "pickup")
	if tool != "":
		var broke: String = p.inventory.wear("hand", 1.0)
		if broke != "":
			p.refresh_gear()
			_say(p, "%s quebrou!" % Data.item_name(broke))
	var power: int = int(p.perk("strike_power")) if tool != "" else 1
	if not best.strike(power):
		_sfx(p, "thud")
		_pop(best.position + Vector3(0, 2.2, 0), "%s: falta%s %d golpe%s" % [best.display_name(), "" if best.hp == 1 else "m", best.hp, "" if best.hp == 1 else "s"], Color(1.0, 0.9, 0.7))
		return
	if kind == "page":
		_despawn(best)
		obj_flags["found_page"] = true
		_learn_next_spell(p)
		discover("page")
		_sfx(p, "craft")
		return
	if kind == "item" and not best.item_stack.is_empty():
		p.inventory.put_stack(best.item_stack)  # keeps durability / freshness
		_despawn(best)
		_gain(p, best.position, {best.item_stack.get("id", ""): int(best.item_stack.get("count", 1))})
		return
	var loot: Dictionary = best.gives()
	give(p, loot)
	if best.regrows():
		best.set_picked()
	else:
		_despawn(best)
		if kind == "tree":  # the forest renews: a sapling sprouts at the stump
			_spawn_resource("sapling", best.position)
	_gain(p, best.position, loot)


## Success feedback: "+2 Palha" floating up, a sparkle and a chime.
func _gain(p, at: Vector3, loot: Dictionary) -> void:
	var parts := []
	for id in loot:
		parts.append("+%d %s" % [int(loot[id]), Data.item_name(id)])
	var text := "  ".join(parts)
	_say(p, text)
	if p == local_player:
		_pop(p.position + Vector3(0, 2.4, 0), text, Color(0.75, 1.0, 0.6))
		Fx.magic_puff(decor_root, at, Color(1.0, 0.9, 0.5), 14)
		_sfx(p, "pickup")


## Failure feedback: the specific reason, in red, with a short buzz.
func _deny(p, reason: String, at := Vector3.INF) -> void:
	_say(p, reason)
	if p == local_player:
		_pop((p.position if at == Vector3.INF else at) + Vector3(0, 2.2, 0), reason, Color(1.0, 0.55, 0.45))
		_sfx(p, "deny")


func _sfx(p, cue: String) -> void:
	if p == local_player:
		Sfx.play(self, cue)


## A world-space text that rises and fades (frees itself).
func _pop(at: Vector3, text: String, c: Color) -> void:
	if not is_inside_tree():
		return
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.font_size = 44
	l.outline_size = 12
	l.pixel_size = 0.006
	l.modulate = c
	l.position = at
	add_child(l)
	var tw := l.create_tween().set_parallel(true)
	tw.tween_property(l, "position:y", at.y + 1.2, 1.1).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 1.1).set_delay(0.4)
	tw.chain().tween_callback(l.queue_free)


## Highlights what E would act on, with its prompt or why it can't.
func _update_focus() -> void:
	if _focus_ring == null:
		_focus_ring = MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.62
		torus.outer_radius = 0.72
		_focus_ring.mesh = torus
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(1.0, 0.85, 0.4)
		m.no_depth_test = true
		_focus_ring.material_override = m
		add_child(_focus_ring)
		_focus_label = Label3D.new()
		_focus_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_focus_label.no_depth_test = true
		_focus_label.font_size = 56
		_focus_label.outline_size = 14
		_focus_label.pixel_size = 0.005
		add_child(_focus_label)
	var g = null
	if local_player != null and not local_player.dead and not map_open() and placing == "":
		g = interact_target(local_player)
	_focus_ring.visible = g != null
	_focus_label.visible = false  # the HUD prompt carries the text (no duplicate)
	if g == null:
		hud.set_prompt("", true)
		return
	var big: bool = g.kind == "tree" or g.kind == "rock"
	var why := interact_blocker(local_player, g)
	_focus_ring.position = g.position + Vector3(0, 0.08, 0)
	_focus_ring.scale = Vector3.ONE * (1.8 if big else 1.0)
	(_focus_ring.material_override as StandardMaterial3D).albedo_color = Color(1.0, 0.85, 0.4) if why == "" else Color(1.0, 0.45, 0.35)
	hud.set_prompt(interact_prompt(g) if why == "" else "%s: %s" % [g.display_name(), why], why == "")


func _learn_next_spell(p) -> void:
	match meta.learn_next():
		"lume":
			_announce("Aprenderam LUME (Z): explosão de luz que queima Errantes próximos (barulhento!)")
		"escudo":
			_announce("Aprenderam ESCUDO (X): barreira que bloqueia dano por 6s")
		"eco":
			for q in players():
				q.apply_meta(true)
			_announce("Aprenderam ECO ARCANO: +30 de mana máxima")
		_:
			give(p, {"essence": 1})
			_say(p, "Página em branco... virou Essência (+1)")


func _try_portal(p) -> void:
	discover("portal")
	if run_hearts < Cfg.PORTAL_HEARTS:
		_say(p, "O Portal dorme. Precisa de %d Corações da Névoa (tem %d): vença o horror da Lua de Sangue" % [Cfg.PORTAL_HEARTS, run_hearts])
		return
	run_hearts -= Cfg.PORTAL_HEARTS
	won = true
	for q in alive_players():
		q.celebrate()
	meta.record_nights(day_night.nights)
	meta.save()
	_show_end_menu(true)


func _cast_bolt(p) -> void:
	var cost: float = p.spell_cost()
	if p.mana < cost:
		_say(p, "Mana insuficiente")
		return
	p.mana -= cost
	p.corrupt(5.0)
	emit_noise(p, float(Data.spell("bolt").get("noise", 18)) * p.wand_noise_mult())
	var best = null
	var bd := 16.0
	for s in shadows():
		var d: float = s.position.distance_to(p.position)
		if d < bd:
			bd = d
			best = s
	var hand_d: Dictionary = p.inventory.hand_data()
	if hand_d.has("spell_damage") and hand_d.has("uses"):
		var broke: String = p.inventory.wear("hand", 1.0)
		if broke != "":
			p.refresh_gear()
			_say(p, "%s se partiu!" % Data.item_name(broke))
	var gd = null
	for g in guardians():
		if g.alive() and g.position.distance_to(p.position) < bd:
			bd = g.position.distance_to(p.position)
			gd = g
	if gd != null:
		p.face(gd.position)
		p.play_action("bolt")
		_damage_guardian(p, gd, p.spell_damage())
		return
	if best == null:
		p.play_action("bolt")
		_say(p, "Feitiço lançado no vazio")
		return
	best.hp -= p.spell_damage()
	best.last_hitter = p
	p.face(best.position)
	p.play_action("bolt")
	_say(p, "Feitiço atinge o Errante" + (" GIGANTE" if best.boss else ""))


func _cast_lume(p) -> void:
	if not meta.knows("lume"):
		_say(p, "Vocês ainda não conhecem LUME (ache páginas nas Ruínas)")
		return
	var lume := Data.spell("lume")
	if p.mana < float(lume.mana):
		_say(p, "Mana insuficiente (Lume custa %d)" % int(lume.mana))
		return
	p.mana -= float(lume.mana)
	p.corrupt(3.0)
	emit_noise(p, float(Data.spell("lume").get("noise", 30)) * p.wand_noise_mult())
	var burned := 0
	for s in shadows():
		if s.position.distance_to(p.position) < float(lume.radius):
			s.hp -= float(lume.damage) * p.perk("bolt_mult")
			s.last_hitter = p
			burned += 1
	for g in guardians():
		if g.alive() and g.position.distance_to(p.position) < float(lume.radius):
			_damage_guardian(p, g, float(lume.damage) * p.perk("bolt_mult"))
	p.wisp = minf(100.0, p.wisp + 10.0)
	p.play_action("lume")
	_say(p, "LUME! Luz explode (%d Errantes queimados)" % burned)


func _cast_shield(p) -> void:
	if not meta.knows("escudo"):
		_say(p, "Vocês ainda não conhecem ESCUDO (ache páginas nas Ruínas)")
		return
	var esc := Data.spell("escudo")
	if p.mana < float(esc.mana):
		_say(p, "Mana insuficiente (Escudo custa %d)" % int(esc.mana))
		return
	p.mana -= float(esc.mana)
	p.shield_t = float(esc.duration)
	emit_noise(p, float(Data.spell("escudo").get("noise", 14)) * p.wand_noise_mult())
	p.play_action("shield")
	_say(p, "ESCUDO! Nada te toca por 6 segundos")


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and (key.keycode == KEY_F11 or (key.keycode == KEY_ENTER and key.alt_pressed)):
		toggle_fullscreen()
		return
	if key != null and key.pressed and not key.echo and key.keycode == KEY_M and state == "playing":
		toggle_map()
		return
	if map_open():
		if key != null and key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
			world_map.close()
		elif key != null and key.pressed and key.keycode == KEY_C:
			world_map.center_on_player()
		return  # the map screen owns the input while open
	if placing != "" and state == "playing":
		var mb := event as InputEventMouseButton
		if key != null and key.pressed and not key.echo and (key.keycode == KEY_E or key.keycode == KEY_ENTER):
			confirm_placement()
			return
		if (key != null and key.pressed and key.keycode == KEY_ESCAPE) or (mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT):
			cancel_placement()
			_announce("Construção cancelada")
			return
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			confirm_placement()
			return
	if key != null and key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
		match state:
			"playing":
				pause()
			"paused":
				resume()
			"select":
				show_main_menu()
		return
	if not started or (state != "playing" and state != "ended"):
		return
	if key != null and key.pressed and not key.echo:
		if key.keycode == KEY_R and (won or game_over):
			start_game(last_character)
		elif key.keycode == KEY_TAB:
			hud.toggle_crafting()
		elif SLOT_KEYS.has(key.keycode):
			var i := SLOT_KEYS.find(key.keycode)
			perform(local_player, ("alt:%d" if key.shift_pressed else "use:%d") % i)
		elif KEY_ACTIONS.has(key.keycode):
			perform(local_player, KEY_ACTIONS[key.keycode])
		return
	var mouse := event as InputEventMouseButton
	if mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_WHEEL_UP:
		camera_rig.zoom_by(-0.08)
	elif mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		camera_rig.zoom_by(0.08)
	elif mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
		perform(local_player, "bolt")
