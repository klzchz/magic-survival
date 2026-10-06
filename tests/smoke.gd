extends SceneTree
# Headless smoke test (Godot 4) - run with:
#   godot4 --headless --path . -s tests/smoke.gd
# Instances the world, drives the loop manually across day/night cycles and
# exercises every system: gather, chop, mine, cook, craft, cauldron, wards,
# grimoire spells (Lume/Escudo/Eco), Blood Moon boss, the Arcane Portal win,
# death, roguelite reset, meta-save and the co-op foundation.
# Exits 0 on success, 1 on failure.

const Cfg = preload("res://src/core/config.gd")

var fails := 0


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok   ", label)
	else:
		fails += 1
		printerr("  FAIL ", label)


func _step(w, seconds: float) -> void:
	for _i in range(int(seconds / 0.05)):
		w.tick(0.05)


func _step_until_night(w, max_seconds := 200.0) -> bool:
	var elapsed := 0.0
	while elapsed < max_seconds:
		w.tick(0.05)
		elapsed += 0.05
		if w.day_night.prev_night:
			return true
	return false


func _initialize() -> void:
	print("== Magical Survive smoke test (Godot 4) ==")
	# fresh meta so learned-spell checks are deterministic
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Cfg.SAVE_PATH))

	var w = load("res://scenes/main.tscn").instantiate()
	root.add_child(w)
	await process_frame  # Godot 4 runs _ready on the next frame here
	var p = w.local_player

	# --- architecture: entities are scenes under typed containers ---
	_check(p != null, "player built")
	_check(p.scene_file_path == "res://scenes/wizard.tscn", "apprentice is its own scene")
	_check(w.camera_rig != null and w.camera_rig.current, "camera built and current")
	_check(w.players().size() == 1, "one apprentice in single-player")

	# --- world spawn ---
	_check(w.resources_of("mushroom").size() > 0, "mushrooms scattered")
	_check(w.resources_of("twig").size() > 0, "twigs scattered")
	_check(w.resources_of("tree").size() > 0, "trees scattered")
	_check(w.resources_of("rock").size() > 0, "rocks scattered")
	_check(w.pillars().size() > 0, "college ruins built (pillars)")
	_check(w.resources_of("page").size() == 3, "3 grimoire pages in the ruins")
	_check(w.portal != null, "Arcane Portal stands in the ruins")
	_check(w.meta.spells.size() == 0, "no spells known on a fresh save")
	_check(w.day_night.light() > 0.5, "game starts in daylight")

	# --- gather: stand on the nearest mushroom, then interact ---
	p.position = w.resources_of("mushroom")[0].position
	var before: int = p.inv.mushroom
	w.perform(p, "interact")
	_check(p.inv.mushroom == before + 1, "interact picks up a mushroom")

	# --- chop a tree (3 strikes) ---
	p.position = w.resources_of("tree")[0].position
	var tree_count: int = w.resources_of("tree").size()
	for _i in range(3):
		w.perform(p, "interact")
	_check(p.inv.wood >= 2 and w.resources_of("tree").size() == tree_count - 1, "tree falls after 3 strikes (+2 wood)")

	# --- mine a rock (2 strikes) ---
	p.position = w.resources_of("rock")[0].position
	var rock_count: int = w.resources_of("rock").size()
	for _i in range(2):
		w.perform(p, "interact")
	_check(p.inv.stone >= 2 and w.resources_of("rock").size() == rock_count - 1, "rock breaks after 2 strikes (+2 stone)")

	# --- eat / brew / feed wisp ---
	p.inv.mushroom = 3
	p.hunger = 40.0
	w.perform(p, "eat")
	_check(p.hunger > 40.0 and p.inv.mushroom == 2, "eat raw restores hunger")
	p.health = 50.0
	w.perform(p, "brew")
	_check(p.health > 50.0 and p.inv.mushroom == 0, "brew potion heals")
	p.inv.twig = 2
	p.wisp = 10.0
	w.perform(p, "feed_wisp")
	_check(p.wisp > 10.0 and p.inv.twig == 1, "feeding the wisp refuels light")

	# --- campfire craft + cook ---
	p.inv.wood = 2
	p.inv.stone = 1
	w.perform(p, "campfire")
	_check(w.structures_of("campfire").size() == 1, "campfire crafted (2 wood + 1 stone)")
	p.inv.mushroom = 1
	p.position = w.structures_of("campfire")[0].position
	w.perform(p, "cook")
	_check(p.inv.cooked == 1 and p.inv.mushroom == 0, "cook mushroom near fire")
	var corr: float = p.corruption
	p.hunger = 40.0
	w.perform(p, "eat")
	_check(p.hunger > 60.0 and p.corruption == corr, "cooked food: more hunger, no corruption")

	# --- cauldron craft + clean elixir ---
	p.inv.stone = 2
	p.inv.wood = 2
	w.perform(p, "cauldron")
	_check(w.structures_of("cauldron").size() == 1, "cauldron crafted (2 stone + 2 wood)")
	p.position = w.structures_of("cauldron")[0].position
	p.inv.mushroom = 2
	p.health = 40.0
	corr = p.corruption
	w.perform(p, "elixir")
	_check(p.health > 80.0 and p.corruption == corr, "cauldron elixir: big heal, no corruption")

	# --- grimoire pages teach spells ---
	p.position = w.resources_of("page")[0].position
	w.perform(p, "interact")
	_check(w.meta.knows("lume"), "page 1 teaches LUME")
	p.position = w.resources_of("page")[0].position
	w.perform(p, "interact")
	_check(w.meta.knows("escudo"), "page 2 teaches ESCUDO")
	p.position = w.resources_of("page")[0].position
	w.perform(p, "interact")
	_check(w.meta.knows("eco"), "page 3 teaches ECO ARCANO")
	_check(p.mana_max > 100.0, "Eco Arcano deepens max mana")

	# --- Lume burns nearby shadows ---
	var sh = w.spawn_shadow()
	sh.position = p.position + Vector3(4, 1, 0)
	var hp_before: float = sh.hp
	p.mana = 100.0
	w.perform(p, "lume")
	_check(sh.hp < hp_before, "LUME burns a nearby shadow")

	# --- Escudo blocks contact damage ---
	p.mana = 100.0
	w.perform(p, "shield")
	_check(p.shield_t > 0.0, "ESCUDO raises the shield")
	sh.hp = 400.0
	sh.position = p.position
	p.hunger = 80.0
	p.health = 80.0
	if w.day_night.light() > 0.5:
		# force night so the shadow is not burned by daylight during the check
		w.day_night.t = Cfg.DAY_LENGTH * 0.62
	p.wisp = 0.0
	_step(w, 0.5)
	_check(p.health == 80.0, "ESCUDO blocks shadow contact damage")

	# --- basic bolt + bone drop ---
	sh.hp = 30.0
	p.mana = 100.0
	var bones: int = p.inv.bone
	w.perform(p, "bolt")
	w.tick(0.05)
	_check(p.inv.bone == bones + 1, "spell kill drops a bone")

	# --- ward craft + repel ---
	p.inv.bone = 2
	p.inv.twig = 1
	w.perform(p, "ward")
	_check(w.structures_of("ward").size() == 1, "bone ward crafted (2 bone + 1 twig)")
	var wpos: Vector3 = w.structures_of("ward")[0].position
	var pushed: Vector3 = w.apply_wards(wpos + Vector3(1, 0, 0))
	var flat := pushed - wpos
	flat.y = 0.0
	_check(flat.length() >= Cfg.WARD_RADIUS - 0.1, "ward pushes shadows to its edge")

	# --- wand upgrade ---
	p.inv.bone = 3
	p.inv.wood = 2
	w.perform(p, "wand")
	_check(p.wand_level == 1, "bone wand crafted (3 bone + 2 wood)")
	_check(p.spell_damage() > 60.0 and p.spell_cost() < 20.0, "bone wand: stronger + cheaper spells")

	# --- Blood Moon: 3rd night spawns the boss ---
	w.restart()
	_check(w.meta.knows("lume"), "learned spells survive the reset (knowledge persists)")
	w.day_night.nights = 2
	p.health = 100.0
	_check(_step_until_night(w), "reached the 3rd night")
	_check(w.day_night.blood_moon, "3rd night is a Blood Moon")
	var boss = null
	for s in w.shadows():
		if s.boss:
			boss = s
	_check(boss != null, "Blood Moon spawns the boss")

	# --- kill the boss -> heart, but NOT the win ---
	if boss != null:
		boss.position = p.position + Vector3(2, 1.8, 0)
		var hearts_before: int = w.meta.hearts
		boss.hp = 1.0
		p.mana = 100.0
		w.perform(p, "bolt")
		w.tick(0.05)
		_check(w.meta.hearts == hearts_before + 1, "boss kill grants a Mist Heart")
		_check(not w.won, "boss kill alone does NOT win the game")
		_check(p.inv.bone >= 5, "boss drops 5 bones")

	# --- the Arcane Portal: locked below 3 hearts, opens at 3 ---
	p.position = w.portal.position
	w.meta.hearts = 2
	w.perform(p, "interact")
	_check(not w.won, "portal stays dormant below 3 hearts")
	w.meta.hearts = 3
	w.perform(p, "interact")
	_check(w.won, "3 Mist Hearts reopen the Portal (WIN)")
	_check(w.meta.hearts == 0, "the Portal consumes the 3 hearts")

	# --- death and roguelite reset ---
	w.restart()
	p.health = 0.0
	_step(w, 0.2)
	_check(p.dead and w.game_over, "player dies at 0 health (game over when all fall)")
	var best: int = w.meta.best_nights
	w.restart()
	_check(not w.game_over and p.health == 100.0, "reset respawns on a new island")
	_check(w.resources_of("mushroom").size() > 0, "new island regenerates resources")
	_check(w.resources_of("page").size() == 3, "new island regenerates grimoire pages")
	_check(w.meta.best_nights == best, "meta progression survives the reset")
	_check(FileAccess.file_exists(Cfg.SAVE_PATH), "meta save file written to disk")

	# --- co-op foundation (Phase 2 hooks) ---
	var p2 = w.add_player(2)
	_check(w.players().size() == 2 and p2.slot == 1, "a second apprentice joins with its own slot")
	_check(p2.inv.mushroom == 0 and p2.health == 100.0, "each apprentice has its own stats and inventory")
	p2.position = Vector3(40, 0, 40)
	var hunter = w.spawn_shadow()
	hunter.position = Vector3(38, 1, 38)
	_check(w.nearest_player(hunter.position) == p2, "Shadows hunt the nearest apprentice")
	p.health = 0.0
	w.day_night.t = Cfg.DAY_LENGTH * 0.62
	_step(w, 0.1)
	_check(p.dead and not w.game_over, "one fallen apprentice does not end the run")
	p2.inv.mushroom = 1
	p2.hunger = 40.0
	w.perform(p2, "eat")
	_check(p2.hunger > 40.0 and p.inv.mushroom == 0, "dispatcher routes actions to the right apprentice")

	# leave the player's real save clean
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Cfg.SAVE_PATH))
	print("== done: %s ==" % ("ALL GREEN" if fails == 0 else "%d FAILURES" % fails))
	quit(1 if fails > 0 else 0)
