extends SceneTree
# Headless smoke test — run with:
#   godot --path . -s test/smoke.gd
# Instances the world, simulates frames across day/night cycles and exercises
# every system: gather, chop, mine, cook, craft, cauldron, wards, grimoire
# spells (Lume/Escudo/Eco), Blood Moon boss, the Arcane Portal win, death,
# roguelite reset and meta-save. Exits 0 on success, 1 on failure.

var fails := 0


func _check(cond: bool, name: String) -> void:
	if cond:
		print("  ok   ", name)
	else:
		fails += 1
		printerr("  FAIL ", name)


func _step(world, seconds: float) -> void:
	# drive the game loop manually (headless -s scripts don't run _process)
	var steps := int(seconds / 0.05)
	for _i in range(steps):
		world._process(0.05)


func _step_until_night(world, max_seconds := 200.0) -> bool:
	var elapsed := 0.0
	while elapsed < max_seconds:
		world._process(0.05)
		elapsed += 0.05
		if world.prev_night:
			return true
	return false


func _init() -> void:
	print("== Magic Survival smoke test ==")
	# fresh meta so learned-spell checks are deterministic
	var d := Directory.new()
	d.remove("user://magic_survival_meta.json")

	var scene = load("res://main.tscn").instance()
	root.add_child(scene)
	var w = scene

	# --- world spawn ---
	_check(w.player != null, "player built")
	_check(w.cam != null, "camera built")
	_check(w.mushrooms.size() > 0, "mushrooms scattered")
	_check(w.twigs.size() > 0, "twigs scattered")
	_check(w.trees.size() > 0, "trees scattered")
	_check(w.rocks.size() > 0, "rocks scattered")
	_check(w.pillars.size() > 0, "college ruins built (pillars)")
	_check(w.pages.size() == 3, "3 grimoire pages in the ruins")
	_check(w.portal != null, "Arcane Portal stands in the ruins")
	_check(w.spells.size() == 0, "no spells known on a fresh save")
	_check(w._day_light() > 0.5, "game starts in daylight")

	# --- gather: teleport onto the nearest mushroom, then interact ---
	var target = w.mushrooms[0]
	w.player.translation = target.translation
	var before = w.inv.mushroom
	w._interact()
	_check(w.inv.mushroom == before + 1, "interact picks up a mushroom")

	# --- chop a tree (3 strikes) ---
	var tree = w.trees[0]
	w.player.translation = tree.node.translation
	var tree_count = w.trees.size()
	for _i in range(3):
		w._interact()
	_check(w.inv.wood >= 2 and w.trees.size() == tree_count - 1, "tree falls after 3 strikes (+2 wood)")

	# --- mine a rock (2 strikes) ---
	var rock = w.rocks[0]
	w.player.translation = rock.node.translation
	var rock_count = w.rocks.size()
	for _i in range(2):
		w._interact()
	_check(w.inv.stone >= 2 and w.rocks.size() == rock_count - 1, "rock breaks after 2 strikes (+2 stone)")

	# --- eat / brew / feed wisp ---
	w.inv.mushroom = 3
	w.hunger = 40.0
	w._eat()
	_check(w.hunger > 40.0 and w.inv.mushroom == 2, "eat raw restores hunger")
	w.health = 50.0
	w._brew()
	_check(w.health > 50.0 and w.inv.mushroom == 0, "brew potion heals")
	w.inv.twig = 2
	w.wisp = 10.0
	w._feed_wisp()
	_check(w.wisp > 10.0 and w.inv.twig == 1, "feeding the wisp refuels light")

	# --- campfire craft + cook ---
	w.inv.wood = 2
	w.inv.stone = 1
	w._craft_campfire()
	_check(w.campfires.size() == 1, "campfire crafted (2 wood + 1 stone)")
	w.inv.mushroom = 1
	w.player.translation = w.campfires[0].translation
	w._cook()
	_check(w.inv.cooked == 1 and w.inv.mushroom == 0, "cook mushroom near fire")
	var corr = w.corruption
	w.hunger = 40.0
	w._eat()
	_check(w.hunger > 60.0 and w.corruption == corr, "cooked food: more hunger, no corruption")

	# --- cauldron craft + clean elixir ---
	w.inv.stone = 2
	w.inv.wood = 2
	w._craft_cauldron()
	_check(w.cauldrons.size() == 1, "cauldron crafted (2 stone + 2 wood)")
	w.player.translation = w.cauldrons[0].translation
	w.inv.mushroom = 2
	w.health = 40.0
	corr = w.corruption
	w._brew_elixir()
	_check(w.health > 80.0 and w.corruption == corr, "cauldron elixir: big heal, no corruption")

	# --- grimoire pages teach spells ---
	w.player.translation = w.pages[0].translation
	w._interact()
	_check("lume" in w.spells, "page 1 teaches LUME")
	w.player.translation = w.pages[0].translation
	w._interact()
	_check("escudo" in w.spells, "page 2 teaches ESCUDO")
	w.player.translation = w.pages[0].translation
	w._interact()
	_check("eco" in w.spells, "page 3 teaches ECO ARCANO")
	_check(w.mana_max > 100.0, "Eco Arcano deepens max mana")

	# --- Lume burns nearby shadows ---
	w._spawn_shadow()
	w.shadows[0].node.translation = w.player.translation + Vector3(4, 1, 0)
	var hp_before = w.shadows[0].hp
	w.mana = 100.0
	w._cast_lume()
	_check(w.shadows[0].hp < hp_before, "LUME burns a nearby shadow")

	# --- Escudo blocks contact damage ---
	w.mana = 100.0
	w._cast_shield()
	_check(w.shield_t > 0.0, "ESCUDO raises the shield")
	w.shadows[0].hp = 400.0
	w.shadows[0].node.translation = w.player.translation
	w.hunger = 80.0
	w.health = 80.0
	var sky = w._day_light()
	if sky > 0.5:
		# force night so the shadow is not burned by daylight during the check
		w.t = w.DAY_LENGTH * 0.62
	w.wisp = 0.0
	_step(w, 0.5)
	_check(w.health == 80.0, "ESCUDO blocks shadow contact damage")

	# --- basic bolt + bone drop ---
	w.shadows[0].hp = 30.0
	w.mana = 100.0
	var bones = w.inv.bone
	w._cast()
	w._process(0.05)
	_check(w.inv.bone == bones + 1, "spell kill drops a bone")

	# --- ward craft + repel ---
	w.inv.bone = 2
	w.inv.twig = 1
	w._craft_ward()
	_check(w.wards.size() == 1, "bone ward crafted (2 bone + 1 twig)")
	var wpos = w.wards[0].translation
	var inside = wpos + Vector3(1, 0, 0)
	var pushed = w._apply_wards(inside)
	var flat = pushed - wpos
	flat.y = 0
	_check(flat.length() >= w.WARD_RADIUS - 0.1, "ward pushes shadows to its edge")

	# --- wand upgrade ---
	w.inv.bone = 3
	w.inv.wood = 2
	w._upgrade_wand()
	_check(w.wand_level == 1, "bone wand crafted (3 bone + 2 wood)")
	_check(w._spell_damage() > 60.0 and w._spell_cost() < 20.0, "bone wand: stronger + cheaper spells")

	# --- Blood Moon: 3rd night spawns the boss ---
	w._reset()
	_check("lume" in w.spells, "learned spells survive the reset (knowledge persists)")
	w.nights = 2
	w.health = 100.0
	var reached = _step_until_night(w)
	_check(reached, "reached the 3rd night")
	_check(w.blood_moon, "3rd night is a Blood Moon")
	var boss = null
	for s in w.shadows:
		if s.boss:
			boss = s
	_check(boss != null, "Blood Moon spawns the boss")

	# --- kill the boss -> heart, but NOT the win ---
	if boss != null:
		boss.node.translation = w.player.translation + Vector3(2, 1.8, 0)
		var hearts_before = w.hearts
		boss.hp = 1.0
		w.mana = 100.0
		w._cast()
		w._process(0.05)
		_check(w.hearts == hearts_before + 1, "boss kill grants a Mist Heart")
		_check(not w.won, "boss kill alone does NOT win the game")
		_check(w.inv.bone >= 5, "boss drops 5 bones")

	# --- the Arcane Portal: locked below 3 hearts, opens at 3 ---
	w.player.translation = w.portal.translation
	w.hearts = 2
	w._try_portal()
	_check(not w.won, "portal stays dormant below 3 hearts")
	w.hearts = 3
	w._interact()
	_check(w.won, "3 Mist Hearts reopen the Portal (WIN)")
	_check(w.hearts == 0, "the Portal consumes the 3 hearts")

	# --- death and roguelite reset ---
	w._reset()
	w.health = 0.0
	_step(w, 0.2)
	_check(w.dead, "player dies at 0 health")
	var best = w.best_nights
	w._reset()
	_check(not w.dead and w.health == 100.0, "reset respawns on a new island")
	_check(w.mushrooms.size() > 0, "new island regenerates resources")
	_check(w.pages.size() == 3, "new island regenerates grimoire pages")
	_check(w.best_nights == best, "meta progression survives the reset")

	# --- meta save file exists ---
	var f = File.new()
	_check(f.file_exists(w.SAVE_PATH), "meta save file written to disk")

	print("== done: %s ==" % ("ALL GREEN" if fails == 0 else "%d FAILURES" % fails))
	quit(1 if fails > 0 else 0)
