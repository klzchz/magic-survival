extends SceneTree
# Headless smoke test (Godot 4) - run with:
#   godot4 --headless --path . -s tests/smoke.gd
# Covers the DST-style survival loop MVP (design/gdd/survival-loop-mvp.md):
# inventory logic, tools + durability, regrowing resources, crafting + tech,
# cooking + spoilage, campfire fuel, darkness, armor, the 3 characters, and
# the magic layer (spells, Blood Moon boss, Portal, roguelite reset, co-op).
# Exits 0 on success, 1 on failure.

const Cfg = preload("res://src/core/config.gd")
const Data = preload("res://src/core/data.gd")
const Inventory = preload("res://src/gameplay/inventory.gd")

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


func _step_until_night(w, max_seconds := 400.0) -> bool:
	var elapsed := 0.0
	while elapsed < max_seconds:
		w.tick(0.05)
		elapsed += 0.05
		if w.day_night.prev_night:
			return true
	return false


## Builds a structure through the real placement flow on cleared flat ground.
func _build(w, p, rid: String, at := Vector3(0, 0, 0)) -> bool:
	for g in w.resources():
		if Vector2(g.position.x - at.x, g.position.z - at.z).length() < 9.0:
			w._despawn(g)
	for st in w._children(w.structures_root):
		if Vector2(st.position.x - at.x, st.position.z - at.z).length() < 9.0 and st.kind != "campfire" and rid == "x":
			w._despawn(st)
	p.position = w.terrain.on_ground(at)
	if not w.craft(p, rid):
		return false
	return w.confirm_placement()


func _force_day(w) -> void:
	w.day_night.t = 5.0


func _force_night(w) -> void:
	w.day_night.t = Cfg.DAY_LENGTH * 0.62
	w.day_night.prev_night = true


func _initialize() -> void:
	print("== Magical Survive smoke test (survival loop MVP) ==")
	seed(20261006)  # deterministic island
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Cfg.SAVE_PATH))

	# ---------- inventory (pure logic) ----------
	var inv := Inventory.new()
	_check(inv.add("twig", 50) == 0 and inv.count("twig") == 50, "stacks split at the stack cap (40 + 10)")
	_check(inv.slots[0].count == 40 and inv.slots[1].count == 10, "first stack full, remainder in the next slot")
	_check(inv.pay({"twig": 12}) and inv.count("twig") == 38, "pay removes exactly the cost")
	_check(not inv.pay({"flint": 1}), "pay fails when an ingredient is missing")
	inv.add("axe", 1)
	var axe_slot := -1
	for i in range(Inventory.SIZE):
		if inv.slots[i] != null and inv.slots[i].id == "axe":
			axe_slot = i
	_check(inv.equip_from(axe_slot) and inv.hand_id() == "axe", "equip moves the axe to the hand")
	for _i in range(59):
		inv.wear("hand", 1.0)
	_check(inv.hand_id() == "axe", "axe survives 59 strikes")
	_check(inv.wear("hand", 1.0) == "axe" and inv.hand_id() == "", "axe breaks on its 60th strike")
	inv.add("berries", 2)
	inv.tick_spoil(1000.0)
	_check(inv.count("rot") == 2 and inv.count("berries") == 0, "food spoils into rot")
	var full := Inventory.new()
	for i in range(Inventory.SIZE):
		full.add("log", 20)
	_check(full.add("log", 3) == 3, "overflow is reported when the bag is full")

	# ---------- boot: headless starts as the default character ----------
	var w = load("res://scenes/main.tscn").instantiate()
	root.add_child(w)
	await process_frame  # Godot 4 runs _ready on the next frame here
	var p = w.local_player
	_check(p != null and p.char_id == "aldric" and w.started, "headless boot starts as Aldric")
	_check(p.scene_file_path == "res://scenes/wizard.tscn", "apprentice is its own scene")
	_check(w.resources_of("grass_tuft").size() > 0 and w.resources_of("sapling").size() > 0, "grass tufts and saplings scattered")
	_check(w.resources_of("berry_bush").size() > 0 and w.ground_items("flint").size() > 0, "berry bushes and flint on the ground")
	_check(w.resources_of("page").size() == 3 and w.portal != null and w.pillars().size() > 0, "ruins, 3 grimoire pages and the Portal")
	_check(p.inventory.count("mushroom") == 2 and p.inventory.count("elixir") == 1, "Aldric's starting items")
	_force_day(w)

	# ---------- terrain: relief, lakes, everything on the ground ----------
	var ter = w.terrain
	_check(ter.lakes.size() >= 2, "the island has lakes")
	var lake: Dictionary = ter.lakes[0]
	var lc: Vector2 = lake.center
	_check(ter.is_water(lc.x, lc.y) and not ter.is_walkable(lc.x, lc.y), "a lake centre is water and can't be walked")
	_check(absf(ter.height_at(0, 0)) < 0.05 and absf(ter.height_at(w._ruins_center().x, w._ruins_center().z)) < 0.05, "spawn and ruins clearings are flat")
	var on_ground := true
	for g in w.resources():
		if absf(g.position.y - ter.height_at(g.position.x, g.position.z)) > 0.01:
			on_ground = false
	_check(on_ground, "every resource stands on the ground")
	var relief := 0.0
	for i in range(40):
		relief = maxf(relief, absf(ter.height_at(randf_range(-50, 50), randf_range(-50, 50))))
	_check(relief > 1.0, "the island has real relief (hills and basins)")
	var walker = w.add_player(9, "aldric")
	var into := Vector3(-1, 0, 0)
	for dv in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:  # a dry, in-bounds start
		var cand: Vector3 = Vector3(lc.x, 0, lc.y) + dv * (float(lake.radius) + 6.0)
		if absf(cand.x) < 55.0 and absf(cand.z) < 55.0 and ter.is_walkable(cand.x, cand.z):
			walker.position = ter.on_ground(cand)
			into = -dv
			break
	for _i in range(80):  # walk straight at the lake
		walker.move(into, 0.05)
	_check(ter.is_walkable(walker.position.x, walker.position.z), "walking into a lake stops at the shore")
	# collision: walk straight into a tree and slide around it instead of through it
	var blocker = w.resources_of("tree")[0]
	walker.position = ter.on_ground(blocker.position + Vector3(-3, 0, 0.2))
	var min_d := INF
	for _i in range(40):
		walker.move(Vector3(1, 0, 0), 0.05)
		min_d = minf(min_d, Vector2(walker.position.x - blocker.position.x, walker.position.z - blocker.position.z).length())
	_check(min_d >= 1.2, "apprentices can't walk through trees")
	# movement feel: acceleration, top speed, braking, magic hop
	walker.position = ter.on_ground(Vector3(0, 0, 0))
	walker.velocity = Vector3.ZERO
	walker.move(Vector3(1, 0, 0), 0.05)
	_check(walker.velocity.length() > 0.5 and walker.velocity.length() < Cfg.SPEED * 0.5, "movement accelerates instead of snapping to full speed")
	for _i in range(20):
		walker.move(Vector3(1, 0, 0), 0.05)
	_check(is_equal_approx(walker.velocity.length(), Cfg.SPEED), "top speed is reached (10.5)")
	for _i in range(10):
		walker.move(Vector3.ZERO, 0.05)
	_check(walker.velocity.length() < 0.01, "releasing the keys brakes to a stop")
	walker.position = ter.on_ground(Vector3(0, 0, 0))
	_check(walker.jump(), "Space starts a magic hop")
	_check(not walker.jump(), "no double jump mid-air")
	var peak := 0.0
	for _i in range(40):
		walker.move(Vector3.ZERO, 0.025)
		peak = maxf(peak, walker.air)
	_check(peak > 0.8 and peak < 1.6 and walker.on_ground(), "the hop arcs ~1.2 m and lands back on the ground")
	_check(absf(walker.position.y - ter.height_at(walker.position.x, walker.position.z)) < 0.01, "after landing the apprentice stands on the terrain")
	_check(absf(walker.position.y - ter.height_at(walker.position.x, walker.position.z)) < 0.01, "apprentices follow the ground height")
	w._despawn(walker)
	var grass = ter.find_child("Grass", true, false)
	_check(grass != null and grass.multimesh.instance_count > 1500, "dense grass field (MultiMesh)")

	# ---------- three biomes, roads, landmarks ----------
	_check(ter.biome_at(0, 0) == "flowered", "the clearing is in the flowered biome")
	_check(ter.biome_at(w.gothic_center.x, w.gothic_center.y) == "gothic", "the Sunken Cathedral stands in the gothic biome")
	_check(ter.biome_at(w.desert_center.x, w.desert_center.y) == "desert", "the desert centre is desert")
	var dry := true
	for road in [w.lamp_road, w.waystone_path, w.north_road, w.trail, w.old_trail]:
		for i in range(road.size() - 1):
			for k in range(11):
				var q: Vector2 = road[i].lerp(road[i + 1], k / 10.0)
				if ter.is_water(q.x, q.y):
					dry = false
	_check(dry, "every road reaches its biome without crossing water")
	var kinds := {}
	for l in ter.lakes:
		kinds[l.get("biome", "")] = true
	_check(kinds.has("flowered") and kinds.has("gothic") and kinds.has("desert"), "lakes in the south, dark ponds in the gothic, an oasis in the desert")
	_check(Cfg.WORLD >= 150.0, "the island spans 300+ m (three biomes)")

	# ---------- gather by hand, regrow ----------
	# each tested node is moved to an isolated spot so neighbours never interfere
	var tuft = w.resources_of("grass_tuft")[0]
	tuft.position = Vector3(55, 0, -55)
	p.position = tuft.position
	w.perform(p, "interact")
	_check(p.inventory.count("grass") == 1 and not tuft.grown, "picking a tuft gives grass and leaves it bare")
	w.perform(p, "interact")
	_check(p.inventory.count("grass") == 1, "a bare tuft can't be picked again")
	tuft.tick_regrow(500.0)
	_check(tuft.grown, "the tuft regrows over time")
	var sap = w.resources_of("sapling")[0]
	sap.position = Vector3(55, 0, -45)
	p.position = sap.position
	w.perform(p, "interact")
	_check(p.inventory.count("twig") == 1, "sapling gives a twig")

	# ---------- finding resources + clear interaction feedback ----------
	var near := {"grass_tuft": 0, "sapling": 0, "flint": 0}
	var steep := 0
	var wrong_biome := 0
	for g in w.resources():
		var k: String = g.item_id if g.kind == "item" else g.kind
		if near.has(k) and Vector2(g.position.x, g.position.z).length() < 26.0:
			near[k] += 1
		if k in ["grass_tuft", "sapling", "flint", "dry_shrub"]:
			if w.terrain.slope(g.position.x, g.position.z) > 0.9 or w.terrain.is_water(g.position.x, g.position.z):
				steep += 1
			if k == "sapling" and g.biome == "desert":  # biome where it spawned (earlier tests move nodes)
				wrong_biome += 1
	_check(near.grass_tuft >= 8 and near.sapling >= 6 and near.flint >= 3, "a torch's worth of straw, twigs and flint rings the start (%s)" % str(near))
	_check(steep == 0, "no gatherable sits on a dune crest, cliff or in water")
	_check(wrong_biome == 0 and w.resources_of("dry_shrub").size() > 0, "the desert gets dry shrubs (twigs), not saplings")
	var desert_straw := 0
	for g in w.resources_of("grass_tuft"):
		if w.terrain.biome_at(g.position.x, g.position.z) == "desert":
			desert_straw += 1
	_check(desert_straw >= 10, "dry straw grows in the desert too")
	var tuft2 = w.resources_of("grass_tuft")[1]
	tuft2.position = Vector3(45, 0, -55)
	_check(w.interact_prompt(tuft2) == "E — Coletar Tufo de palha", "the target shows 'E — Coletar Tufo de palha'")
	p.position = Vector3(45, 0, -51)  # 4 m away: in focus, out of reach
	_check(w.interact_target(p) == tuft2, "E targets the nearest resource within focus range")
	w.perform(p, "interact")
	_check(tuft2.grown and w._approach == tuft2, "from 4 m, E walks over instead of failing")
	w._approach = null
	var stuffed := Inventory.new()
	for i in range(Inventory.SIZE):
		stuffed.slots[i] = Inventory.make("rock", Inventory.stack_max("rock"))
	var bag = p.inventory
	p.inventory = stuffed
	_check(w.interact_blocker(p, tuft2).begins_with("Inventário cheio"), "a stuffed bag is the reason given")
	p.position = tuft2.position
	w.perform(p, "interact")
	_check(tuft2.grown and w.resources_of("grass_tuft").has(tuft2), "with a stuffed bag nothing is picked or dropped")
	p.inventory = bag
	var tree2 = w.resources_of("tree")[0]
	_check(w.interact_blocker(p, tree2).contains("Machado"), "a tree without an axe says which tool is needed")
	_check(bag.can_fit({"grass": 2}) and not stuffed.can_fit({"grass": 1}), "can_fit checks room before picking")
	_check(Data.item("grass").get("where", "") != "" and Data.item("twig").get("where", "") != "" and Data.item("flint").get("where", "") != "", "materials say where to find them")
	var fl = w.ground_items("flint")[0]
	fl.position = Vector3(55, 0, -35)
	var flint_count: int = w.ground_items("flint").size()
	p.position = fl.position
	w.perform(p, "interact")
	_check(p.inventory.count("flint") == 1 and w.ground_items("flint").size() == flint_count - 1, "flint is picked off the ground")

	# ---------- tools gate trees and rocks ----------
	var tree = w.resources_of("tree")[0]
	tree.position = Vector3(45, 0, -55)
	p.position = tree.position
	w.perform(p, "interact")
	_check(tree.hp == 4 and p.inventory.count("log") == 0, "no axe: the tree can't be chopped")
	p.inventory.add("twig", 1)
	_check(w.craft(p, "axe") and p.inventory.count("axe") == 1, "craft an axe (1 twig + 1 flint)")
	for i in range(Inventory.SIZE):
		if p.inventory.slots[i] != null and p.inventory.slots[i].id == "axe":
			w.perform(p, "use:%d" % i)
	_check(p.inventory.hand_id() == "axe", "using the axe equips it")
	var trees_before: int = w.resources_of("tree").size()
	for _i in range(4):
		w.perform(p, "interact")
	_check(p.inventory.count("log") == 2 and w.resources_of("tree").size() == trees_before - 1, "tree falls after 4 axe strikes (+2 logs)")
	_check(p.inventory.equip.hand.uses == 56.0, "each strike wears the axe")
	var rock = w.resources_of("rock")[0]
	rock.position = Vector3(35, 0, -55)
	p.position = rock.position
	w.perform(p, "interact")
	_check(rock.hp == 4, "an axe can't mine rocks")
	p.inventory.add("twig", 2)
	p.inventory.add("flint", 2)
	w.craft(p, "pickaxe")
	for i in range(Inventory.SIZE):
		if p.inventory.slots[i] != null and p.inventory.slots[i].id == "pickaxe":
			w.perform(p, "use:%d" % i)
	_check(p.inventory.hand_id() == "pickaxe" and p.inventory.count("axe") == 1, "equipping the pickaxe swaps the axe back to the bag")
	for _i in range(4):
		w.perform(p, "interact")
	_check(p.inventory.count("rock") == 2 and p.inventory.count("flint") >= 1, "mining a rock gives stone and flint")

	# ---------- crafting tech: altar unlocks Magia, cauldron unlocks Alquimia ----------
	p.inventory.add("bone", 2)
	p.inventory.add("twig", 1)
	_check(w.craft_blocker(p, "ward").begins_with("Precisa estar perto"), "Magia recipes are locked away from an altar")
	p.inventory.add("rock", 4)
	p.inventory.add("log", 3)
	p.inventory.add("flint", 2)
	_check(_build(w, p, "altar", Vector3(-6, 0, 6)) and w.structures_of("altar").size() == 1, "build the Arcane Altar (placement preview)")
	p.position = w.structures_of("altar")[0].position + Vector3(2.5, 0, 0)
	_check(w.craft(p, "ward") and w.confirm_placement() and w.structures_of("ward").size() == 1, "near the altar the bone ward unlocks")
	var wpos: Vector3 = w.structures_of("ward")[0].position
	var pushed: Vector3 = w.apply_wards(wpos + Vector3(1, 0, 0))
	_check(Vector2(pushed.x - wpos.x, pushed.z - wpos.z).length() >= Cfg.WARD_RADIUS - 0.1, "ward pushes shadows to its edge")
	p.inventory.add("rock", 3)
	p.inventory.add("log", 2)
	_build(w, p, "cauldron", Vector3(6, 0, -6))
	p.position = w.structures_of("cauldron")[0].position + Vector3(2.5, 0, 0)
	p.inventory.add("mushroom", 2)
	p.inventory.add("berries", 1)
	_check(w.craft(p, "elixir") and p.inventory.count("elixir") == 2, "brew an Elixir at the cauldron")
	p.health = 20.0
	for i in range(Inventory.SIZE):
		if p.inventory.slots[i] != null and p.inventory.slots[i].id == "elixir":
			w.perform(p, "use:%d" % i)
			break
	_check(is_equal_approx(p.health, 80.0), "Aldric's potions are 50% stronger (+60 instead of +40)")

	# ---------- campfire: fuel, cooking, light ----------
	p.inventory.add("grass", 3)
	p.inventory.add("log", 2)
	_build(w, p, "campfire", Vector3(6, 0, 6))
	var fire = w.structures_of("campfire")[0]
	_check(fire.burning() and fire.fuel == 120.0, "a new campfire starts with 120s of fuel")
	fire.burn(100.0)
	_check(is_equal_approx(fire.fuel, 20.0), "campfire burns its fuel")
	p.position = fire.position
	p.inventory.add("log", 1)
	for i in range(Inventory.SIZE):
		if p.inventory.slots[i] != null and p.inventory.slots[i].id == "log":
			w.perform(p, "alt:%d" % i)
			break
	_check(is_equal_approx(fire.fuel, 65.0), "a log adds 45s of fuel")
	p.inventory.add("mushroom", 1)
	var raw: int = p.inventory.count("mushroom")
	for i in range(Inventory.SIZE):
		if p.inventory.slots[i] != null and p.inventory.slots[i].id == "mushroom":
			w.perform(p, "alt:%d" % i)
			break
	_check(p.inventory.count("mushroom_cooked") == 1 and p.inventory.count("mushroom") == raw - 1, "secondary use near the fire cooks food")
	fire.burn(1000.0)
	_check(not fire.burning() and fire.radius() == 0.0, "a burnt-out fire gives no light")
	p.position = fire.position + Vector3(1.5, 0, 0)
	p.inventory.add("log", 1)
	for i in range(Inventory.SIZE):
		if p.inventory.slots[i] != null and p.inventory.slots[i].id == "log":
			w.perform(p, "alt:%d" % i)
			break
	_check(fire.burning(), "a dead fire accepts fuel and relights")

	# ---------- placement validation ----------
	var lake2: Dictionary = w.terrain.lakes[0]
	_check(w.placement_blocker("campfire", Vector3(lake2.center.x, 0, lake2.center.y)) != "", "can't build in a lake")
	_check(w.placement_blocker("campfire", fire.position) != "", "can't build on top of another structure")
	var tr = w.resources_of("tree")[0]
	_check(w.placement_blocker("campfire", tr.position) != "", "can't build on a tree")
	p.inventory.add("grass", 3)
	p.inventory.add("log", 2)
	var logs_before: int = p.inventory.count("log")
	w.craft(p, "campfire")
	w.cancel_placement()
	_check(p.inventory.count("log") == logs_before and w.placing == "", "cancelling a placement spends nothing")

	# ---------- darkness, torch, armor ----------
	p.position = Vector3(40, 0, 40)
	p.wisp = 0.0
	p.health = 80.0
	_force_night(w)
	_step(w, 3.0)
	_check(p.health < 80.0, "with no light at night the Mist wounds you")
	p.inventory.add("torch", 1)
	for i in range(Inventory.SIZE):
		if p.inventory.slots[i] != null and p.inventory.slots[i].id == "torch":
			w.perform(p, "use:%d" % i)
	_check(p.light_radius() >= 8.0 and w.is_lit(p.position, 0.0), "an equipped torch lights the dark")
	var hp_now: float = p.health
	_step(w, 1.0)
	_check(p.health >= hp_now - 0.5, "lit by the torch, the darkness stops hurting")
	p.inventory.add("grass_armor", 1)
	for i in range(Inventory.SIZE):
		if p.inventory.slots[i] != null and p.inventory.slots[i].id == "grass_armor":
			w.perform(p, "use:%d" % i)
	p.health = 80.0
	p.hurt(10.0, 1.0)
	_check(is_equal_approx(p.health, 76.0), "grass armor absorbs 60% of damage")

	# ---------- spells, Shadows and loot ----------
	_force_day(w)
	p.position = Vector3.ZERO
	w.meta.spells = ["lume", "escudo"]
	var sh = w.spawn_shadow()
	sh.position = p.position + Vector3(4, 1, 0)
	var hp_before: float = sh.hp
	p.mana = 100.0
	w.perform(p, "lume")
	_check(sh.hp < hp_before, "LUME burns a nearby shadow")
	p.mana = 100.0
	w.perform(p, "shield")
	_check(p.shield_t > 0.0, "ESCUDO raises the shield")
	var spot_hp_save: Vector3 = p.position
	p.position = w.terrain.on_ground(Vector3(-40, 0, 40))  # far from any campfire
	sh.position = p.position + Vector3(0.5, 1, 0)
	var hp_shield: float = p.health
	sh._attack_cd = 0.0
	sh.tick(0.05, w, 0.0, 0.0)
	_check(p.health == hp_shield, "ESCUDO blocks an Errante's blow")
	p.shield_t = 0.0
	var hp_hit: float = p.health
	sh._attack_cd = 0.0
	sh.tick(0.05, w, 0.0, 0.0)
	var one_hit: float = hp_hit - p.health
	sh.tick(0.05, w, 0.0, 0.0)
	_check(one_hit > 0.0 and is_equal_approx(hp_hit - p.health, one_hit), "Errantes strike in discrete blows with a cooldown, not every frame")
	p.position = spot_hp_save
	sh.position = p.position + Vector3(4, 1, 0)
	sh.hp = 30.0
	p.mana = 100.0
	var bones_on_ground: int = w.ground_items("bone").size()
	w.perform(p, "bolt")
	w.tick(0.05)
	_check(w.ground_items("bone").size() == bones_on_ground + 1, "a spell-killed Shadow drops a bone on the ground")

	# ---------- option B: Errantes hunt magic (arcane noise) ----------
	p.position = Vector3(10, 0, 10)
	p.noise = 0.0
	var lurker = w.spawn_shadow()
	lurker.position = p.position + Vector3(20, 1, 0)
	_check(w.errante_target(lurker.position) == null, "a quiet apprentice 20m away goes unnoticed")
	var close = w.spawn_shadow()
	close.position = p.position + Vector3(6, 1, 0)
	_check(w.errante_target(close.position) == p, "up close, Errantes sense you even when quiet")
	p.mana = 100.0
	w.perform(p, "bolt")
	_check(is_equal_approx(p.noise, 18.0), "a spell bolt makes 18 arcane noise")
	p.noise = 80.0
	_check(w.errante_target(lurker.position) == p, "loud magic is heard from far away (80 noise = 32m)")
	p.tick_stats(5.0)
	_check(is_equal_approx(p.noise, 50.0), "arcane noise fades while you stay quiet (6/s)")
	p.inventory.add("mana_potion", 1)
	p.noise = 0.0
	for i in range(Inventory.SIZE):
		if p.inventory.slots[i] != null and p.inventory.slots[i].id == "mana_potion":
			w.perform(p, "use:%d" % i)
	_check(p.noise > 0.0, "drinking a potion is loud too")
	var pos_before: Vector3 = lurker.position
	p.noise = 0.0
	_force_night(w)
	w.tick(0.5)
	_check(lurker.position.distance_to(pos_before) > 0.01 and w.errante_target(lurker.position) == null, "unaware Errantes wander instead of hunting")

	# ---------- which lights hurt Errantes ----------
	_force_night(w)
	var probe = w.spawn_shadow()
	probe.position = p.position + Vector3(2, 1, 0)
	_check(w.is_lit(probe.position, 0.0) and not w.burns_errante(probe.position, 0.0), "the wisp lights the way but does not burn Errantes")
	_check(w.burns_errante(probe.position, 0.9), "sunlight burns Errantes")

	# ---------- Blood Moon boss, Portal ----------
	w.restart()
	p = w.local_player
	w.day_night.nights = 2
	_check(_step_until_night(w), "reached the 3rd night")
	_check(w.day_night.blood_moon, "3rd night is a Blood Moon")
	var boss = null
	for s in w.shadows():
		if s.boss:
			boss = s
	_check(boss != null, "Blood Moon spawns the boss")
	if boss != null:
		boss.position = p.position + Vector3(2, 1.8, 0)
		var hearts_before: int = w.run_hearts
		boss.hp = 1.0
		p.mana = 100.0
		w.perform(p, "bolt")
		w.tick(0.05)
		_check(w.run_hearts == hearts_before + 1, "boss kill grants a Mist Heart")
		_check(w.ground_items("bone").size() > 0 and w.ground_items("essence").size() > 0, "boss drops bones and essence")
	p.position = w.portal.position
	w.run_hearts = 2
	w.perform(p, "interact")
	_check(not w.won, "portal stays dormant below 3 hearts")
	w.run_hearts = 3
	w.perform(p, "interact")
	_check(w.won and w.run_hearts == 0, "3 Mist Hearts reopen the Portal (WIN)")

	# ---------- death and roguelite reset ----------
	w.restart()
	p.health = 0.0
	_step(w, 0.2)
	_check(p.dead and w.game_over, "game over when every apprentice falls")
	w.restart()
	_check(not w.game_over and p.health == p.health_max, "R respawns on a new island")
	_check(w.meta.knows("lume") and FileAccess.file_exists(Cfg.SAVE_PATH), "learned spells persist on disk")

	# ---------- the three characters ----------
	w.start_game("brasa")
	p = w.local_player
	_check(p.char_id == "brasa" and p.inventory.hand_id() == "torch", "Brasa starts holding a torch")
	p.inventory.add("grass", 3)
	p.inventory.add("log", 2)
	_build(w, p, "campfire", Vector3(0, 0, 0))
	var bfire = w.structures_of("campfire")[0]
	bfire.burn(100.0)
	_check(is_equal_approx(bfire.fuel, 70.0), "Brasa's fires burn twice as long")
	var h0: float = p.hunger
	p.tick_stats(10.0)
	_check(is_equal_approx(h0 - p.hunger, 15.6), "Brasa gets hungry 30% faster")
	w.start_game("thorne")
	p = w.local_player
	_check(p.health_max == 150.0 and p.inventory.hand_id() == "axe", "Thorne: 150 hp and starts with an axe")
	p.health = 100.0
	p.hurt(10.0, 1.0)
	_check(is_equal_approx(p.health, 92.5), "Thorne takes 25% less damage")
	_force_day(w)
	var t2 = w.resources_of("tree")[0]
	t2.position = Vector3(45, 0, -55)
	p.position = t2.position
	w.perform(p, "interact")
	w.perform(p, "interact")
	_check(p.inventory.count("log") == 2, "Thorne fells a tree in 2 strikes")
	_check(p.mana_max < 100.0, "Thorne is a poor caster")

	# ---------- co-op foundation ----------
	var p2 = w.add_player(2, "aldric")
	_check(w.players().size() == 2 and p2.slot == 1, "a second apprentice joins with its own slot")
	_check(p2.inventory != p.inventory, "each apprentice has its own inventory")
	p2.position = Vector3(40, 0, 40)
	var hunter = w.spawn_shadow()
	hunter.position = Vector3(38, 1, 38)
	_check(w.nearest_player(hunter.position) == p2, "Shadows hunt the nearest apprentice")
	p.health = 0.0
	_force_day(w)
	_step(w, 0.1)
	_check(p.dead and not w.game_over, "one fallen apprentice does not end the run")

	# ---------- first-steps objectives ----------
	w.start_game("aldric")
	p = w.local_player
	_force_day(w)
	_check(w.objective_step == 0 and w.objective_info().title.begins_with("Colete"), "objective 1: gather materials")
	p.inventory.add("grass", 3)
	p.inventory.add("twig", 3)
	w.tick(0.05)
	_check(w.objective_step == 1, "gathering completes and the tool objective appears")
	p.inventory.add("flint", 1)
	w.craft(p, "axe")
	w.tick(0.05)
	_check(w.objective_step == 2, "crafting an axe completes the tool objective")
	p.inventory.add("log", 2)
	_build(w, p, "campfire", Vector3(3, 0, -3))
	w.tick(0.05)
	_check(w.objective_step == 3 and w.objective_info().text.contains("faltam"), "a campfire leads on to the Lantern Trail (shows distance)")
	p.position = w.terrain.on_ground(Vector3(w.shrine_center.x, 0, w.shrine_center.y) + Vector3(2, 0, 0))
	w.tick(0.05)
	_check(w.objective_step == 4, "reaching the shrine asks for the grimoire page")
	var shrine_page = null
	for g in w.resources_of("page"):
		if Vector2(g.position.x, g.position.z).distance_to(w.shrine_center) < 4.0:
			shrine_page = g
	_check(shrine_page != null, "the shrine altar holds a grimoire page")
	p.position = shrine_page.position
	w.perform(p, "interact")
	w.tick(0.05)
	_check(w.objective_step == 5 and w.objective_info().get("done", false), "picking the page completes the first steps")
	w.start_game("thorne")
	p = w.local_player
	p.inventory.add("grass", 3)
	p.inventory.add("twig", 2)
	w.tick(0.05)
	_check(w.objective_step == 2, "Thorne already holds an axe: the tool step is skipped")

	# ---------- world map: fog of war, base, pins ----------
	w.start_game("aldric")
	p = w.local_player
	w.tick(0.05)
	var ex = w.exploration
	_check(ex.is_discovered(Vector3.ZERO) and not ex.is_discovered(Vector3(w.gothic_center.x, 0, w.gothic_center.y)), "the map starts hidden except around the clearing")
	var edge := Vector2(w.gothic_center.x, w.gothic_center.y) + (Vector2.ZERO - Vector2(w.gothic_center.x, w.gothic_center.y)).normalized() * 30.0
	p.position = w.terrain.on_ground(Vector3(edge.x, 0, edge.y))
	w.tick(0.05)
	_check(ex.is_discovered(p.position), "walking reveals the ground around the apprentice")
	_check(not ex.is_discovered(Vector3(w.gothic_center.x, 0, w.gothic_center.y) + Vector3(0, 0, -40)), "entering a biome does not reveal all of it")
	var ratio_before: float = ex.discovered_ratio()
	for k in range(8):
		p.position = w.terrain.on_ground(p.position + Vector3(6, 0, 0))
		w.tick(0.05)
	_check(ex.discovered_ratio() > ratio_before, "the explored share grows gradually as you walk")
	_check(ex.discovered_ratio() < 0.2, "most of the island stays hidden early on")
	p.position = w.terrain.on_ground(Vector3(0, 0, 0))
	p.inventory.add("grass", 3)
	p.inventory.add("log", 2)
	_build(w, p, "campfire", Vector3(4, 0, 4))
	var fire_pos: Vector3 = w.structures_of("campfire")[0].position
	_check(ex.is_discovered(fire_pos), "the base candidate stands in explored land (shown on the map)")
	_check(w.map_set_base(fire_pos + Vector3(1, 0, 1)) and ex.base.kind == "campfire", "right click near a structure makes it the base")
	_check(not w.map_set_base(Vector3(0, 0, -30)), "no structure nearby: the base is not changed")
	w.map_toggle_marker(Vector3(2, 0, -3))
	_check(ex.markers.size() == 1, "a personal pin is added on explored land")
	w.map_toggle_marker(Vector3(3, 0, -3))
	_check(ex.markers.size() == 0, "clicking an existing pin removes it")
	w.map_toggle_marker(Vector3(w.desert_center.x, 0, w.desert_center.y))
	_check(ex.markers.size() == 0, "unexplored land can't be pinned")
	w.map_toggle_marker(Vector3(-2, 0, 2))
	var img: Image = w.terrain.build_map_image(64)
	var cg: Color = img.get_pixel(int((w.gothic_center.x + Cfg.WORLD) / (Cfg.WORLD * 2.0) * 64), int((w.gothic_center.y + Cfg.WORLD) / (Cfg.WORLD * 2.0) * 64))
	var cd: Color = img.get_pixel(int((w.desert_center.x + Cfg.WORLD) / (Cfg.WORLD * 2.0) * 64), int((w.desert_center.y + Cfg.WORLD) / (Cfg.WORLD * 2.0) * 64))
	_check(cd.r > cg.r and cd.g > cg.g, "the map picture paints the biomes in distinct colours")
	w.toggle_map()
	_check(w.map_open(), "M opens the map")
	var before_move: Vector3 = p.position
	w.tick(0.2)
	_check(p.position.is_equal_approx(before_move), "the apprentice does not walk while the map is open")
	w.toggle_map()
	_check(not w.map_open(), "M closes the map")
	var revealed: float = ex.discovered_ratio()
	_check(w.save_run() and w.continue_run(), "save + continue with map data")
	_check(is_equal_approx(w.exploration.discovered_ratio(), revealed), "explored area survives save/continue")
	_check(w.exploration.base.get("kind", "") == "campfire" and w.exploration.markers.size() == 1, "base and pins survive save/continue")

	# ---------- School-Temple + Jade Naga (design/gdd/special-locations.md) ----------
	w.start_game("aldric")
	p = w.local_player
	_force_day(w)
	var ti: Dictionary = w.temple_info
	_check(not ti.is_empty() and w.guardians().size() == 1, "the School-Temple is built with its guardian")
	var arena: Vector3 = ti.arena
	_check(w.terrain.biome_at(arena.x, arena.z) == "flowered" and absf(arena.x) < Cfg.WORLD - 20 and absf(arena.z) < Cfg.WORLD - 20, "the temple sits in the flowered biome, inside the island")
	var loose := 0
	var to_local: Transform3D = ti.root.transform.affine_inverse()
	for g in w.resources():
		var lp: Vector3 = to_local * g.position
		if absf(lp.x) < 9.0 and lp.z > -20.0 and lp.z < 18.0:  # inside the walls
			loose += 1
	_check(loose <= 9 and loose >= 5, "only the temple's own loot lies inside (%d)" % loose)
	var seal_at: Vector3 = ti.seal.global_position  # the sanctum door
	var seal_push: Vector3 = w.resolve_collision(Vector3(seal_at.x, 0, seal_at.z))
	_check(Vector2(seal_push.x - seal_at.x, seal_push.z - seal_at.z).length() > 0.2, "the jade seal blocks the sanctum")
	_check(not w.dungeons.temple.discovered and w.map_landmarks().filter(func(l): return l.has("status")).is_empty(), "undiscovered: not on the map")
	p.position = w.terrain.on_ground(ti.gate.lerp(arena, 0.4))  # at the courtyard
	w._tick_dungeons(0.1)
	var marks: Array = w.map_landmarks().filter(func(l): return l.has("status"))
	_check(w.dungeons.temple.discovered and marks.size() == 1 and marks[0].status == "explored", "approaching discovers it: 'explored' on the map")
	var naga = w.guardians()[0]
	_check(naga.state == "dormant", "the Jade Naga sleeps until someone enters the hall")
	p.position = w.terrain.on_ground(arena + Vector3(3, 0, 0))
	naga.tick(0.1, w)
	_check(naga.awake(), "stepping into the arena wakes it")
	naga._start("sweep", 0.9, p.position - naga.position)
	_check(naga.hits(p.position, 0.0), "the tail sweep ring covers a body standing in it")
	_check(not naga.hits(p.position, 1.0), "jumping clears the tail sweep")
	_check(not naga.hits(naga.position + Vector3(6, 0, 0), 0.0), "stepping out of the ring dodges it")
	var naga_hp_before: float = p.health
	naga.state_t = 0.01
	naga.tick(0.05, w)
	_check(p.health < naga_hp_before and naga.state == "recover", "the blow lands only when the telegraph ends, then it rests")
	naga._start("spit", 0.8, Vector3(0, 0, 1))
	_check(naga.hits(naga.position + Vector3(0, 0, 6), 0.0) and not naga.hits(naga.position + Vector3(3, 0, 6), 0.0), "the spit lane hits in line, a side-step dodges it")
	naga._clear_telegraph()
	naga._set_state("chase", 0.0)
	p.mana = 150.0
	var naga_hp: float = naga.hp
	w.perform(p, "bolt")
	_check(naga.hp < naga_hp, "the Arcane Bolt hits the guardian")
	_check(naga.hp_max <= 5.0 * 60.0 + 60.0, "the starter wand (5 bolts) + a few blows can beat it")
	p.position = w.terrain.on_ground(naga.position + Vector3(1.5, 0, 0))
	naga_hp = naga.hp
	w.perform(p, "interact")
	_check(naga.hp < naga_hp, "E next to the guardian strikes it")
	p.position = w.terrain.on_ground(arena + Vector3(40, 0, 0))  # flee
	for i in range(8):
		naga.tick(1.0, w)
	_check(naga.state == "dormant" and is_equal_approx(naga.hp, naga.hp_max), "fleeing lets it sleep and heal (flee and come back)")
	p.position = w.terrain.on_ground(arena + Vector3(2, 0, 0))
	w._damage_guardian(p, naga, 9999.0)
	_check(w.dungeons.temple.cleared and w.guardians().is_empty(), "defeated: the temple is cleared")
	_check(not ti.seal.visible, "the jade seal opens")
	var rewards: Array = w.ground_items("core_jade")
	_check(rewards.size() == 1, "the Jade Core appears once in the sanctum")
	marks = w.map_landmarks().filter(func(l): return l.has("status"))
	_check(marks[0].status == "cleared", "the map marks it as cleared")
	_check(w.save_run() and w.continue_run(), "save + continue after clearing")
	_check(w.guardians().is_empty() and w.dungeons.temple.cleared and not w.temple_info.seal.visible, "loading keeps it cleared: no guardian, seal open")
	_check(w.ground_items("core_jade").size() == 1, "loading does not duplicate the reward")
	p = w.local_player
	var core = w.ground_items("core_jade")[0]
	p.position = core.position
	w.perform(p, "interact")
	_check(p.inventory.count("core_jade") == 1 and w.ground_items("core_jade").is_empty(), "the reward is picked up")
	_check(w.save_run() and w.continue_run(), "save + continue after taking it")
	_check(w.ground_items("core_jade").is_empty() and w.local_player.inventory.count("core_jade") == 1 and w.guardians().is_empty(), "returning never respawns the reward or the guardian")
	_check(Data.recipe("wand_jade").get("cost", {}).has("core_jade"), "the Altar sets the Jade Core into a Jade Wand")

	# ---------- save / continue ----------
	w.start_game("aldric")
	p = w.local_player
	_force_day(w)
	p.inventory.add("log", 9)
	p.inventory.add("grass", 3)
	p.health = 55.0
	_check(_build(w, p, "campfire", Vector3(5, 0, 5)), "campfire placed for the save test")
	var saved_fire = w.structures_of("campfire")[0]
	saved_fire.burn(30.0)
	var picked = w.resources_of("grass_tuft")[0]
	picked.set_picked()
	var picked_pos: Vector3 = picked.position
	w.run_hearts = 2
	w.day_night.nights = 4
	var seed_saved: int = w.world_seed
	var lake_saved: Vector2 = w.terrain.lakes[0].center
	var res_count: int = w.resources().size()
	var logs_saved: int = p.inventory.count("log")
	_check(w.save_run(), "the run is saved to disk")
	w.start_game("thorne")  # play something else in between
	_check(w.continue_run(), "Continuar loads the saved run")
	p = w.local_player
	_check(p.char_id == "aldric" and is_equal_approx(p.health, 55.0), "apprentice and vitals restored")
	_check(p.inventory.count("log") == logs_saved, "inventory restored")
	_check(w.world_seed == seed_saved and w.terrain.lakes[0].center.is_equal_approx(lake_saved), "same island rebuilt from the seed")
	_check(w.structures_of("campfire").size() == 1 and is_equal_approx(w.structures_of("campfire")[0].fuel, 90.0), "structures and their fuel restored")
	_check(w.resources().size() == res_count, "resources restored")
	var bare := false
	for g in w.resources_of("grass_tuft"):
		if g.position.distance_to(picked_pos) < 0.05 and not g.grown:
			bare = true
	_check(bare, "picked (regrowing) resources stay picked")
	_check(w.run_hearts == 2 and w.day_night.nights == 4, "run hearts and day count restored")
	p.health = 0.0
	_step(w, 0.1)
	_check(not FileAccess.file_exists("user://run_save.json"), "dying deletes the run save (roguelite)")

	# ---------- menus: main menu · select · pause · game over ----------
	w.show_main_menu()
	_check(w.state == "menu" and w.players().is_empty() and w.menu != null, "main menu clears the island of apprentices")
	w._on_menu_pick("play")
	_check(w.state == "select" and w.select_screen != null and w.menu == null, "Jogar opens the character select")
	w.select_screen.back.emit()
	_check(w.state == "menu", "Voltar returns from the select to the main menu")
	w._on_menu_pick("play")
	w.select_screen.chosen.emit("brasa")
	_check(w.state == "playing" and w.local_player.char_id == "brasa" and w.select_screen == null, "choosing a card starts the run")
	w.pause()
	var t_paused: float = w.day_night.t
	_step(w, 1.0)
	_check(w.state == "paused" and w.day_night.t == t_paused, "pause freezes the world")
	w._on_menu_pick("controls")
	w._on_menu_pick("controls_back")
	_check(w.state == "paused" and w.menu != null, "Controles returns to the pause menu")
	w._on_menu_pick("resume")
	_check(w.state == "playing" and w.menu == null, "Continuar resumes")
	w.local_player.health = 0.0
	_step(w, 0.1)
	_check(w.state == "ended" and w.menu != null, "death opens the game-over menu")
	w._on_menu_pick("again")
	_check(w.state == "playing" and w.local_player.char_id == "brasa" and not w.local_player.dead, "Tentar de novo restarts with the same apprentice")
	w.local_player.health = 0.0
	_step(w, 0.1)
	w._on_menu_pick("select")
	_check(w.state == "select", "Trocar de aprendiz goes back to the character select")
	w.select_screen.chosen.emit("thorne")
	_check(w.local_player.char_id == "thorne" and w.players().size() == 1, "a new apprentice starts a fresh run")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(Cfg.SAVE_PATH))
	print("== done: %s ==" % ("ALL GREEN" if fails == 0 else "%d FAILURES" % fails))
	quit(1 if fails > 0 else 0)
