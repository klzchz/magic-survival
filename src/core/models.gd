extends RefCounted
# Catalog of the CC0 KayKit models under assets/kaykit (credited in CREDITS.md).
# spawn() instances a model under a parent at its catalog scale; spawn_variant()
# picks a random member of a group so the island never looks copy-pasted.
# Returns null when a model is missing, so callers can fall back to Art shapes.

const ROOT := "res://assets/kaykit/"

# id: [path under ROOT, uniform scale]
const CATALOG := {
	# characters
	"mage": ["characters/Mage.glb", 0.8],
	"skeleton": ["characters/Skeleton_Minion.glb", 0.8],
	"skeleton_mage": ["characters/Skeleton_Mage.glb", 0.8],
	"skeleton_boss": ["characters/Skeleton_Warrior.glb", 1.5],
	"rogue_hooded": ["characters/Rogue_Hooded.glb", 0.8],
	"knight": ["characters/Knight.glb", 0.8],
	# props
	"spellbook": ["props/spellbook_open.gltf", 1.0],
	"axe_1handed": ["props/axe_1handed.gltf", 1.0],
	"staff": ["props/staff.gltf", 1.0],
	"bottle_A_green": ["dungeon/bottle_A_green.glb", 1.0],
	"bottle_B_green": ["dungeon/bottle_B_green.glb", 1.0],
	"bottle_C_brown": ["dungeon/bottle_C_brown.glb", 1.0],
	# forest (Halloween Bits)
	"pine_orange_l": ["halloween/tree_pine_orange_large.gltf", 1.0],
	"pine_orange_m": ["halloween/tree_pine_orange_medium.gltf", 1.0],
	"pine_orange_s": ["halloween/tree_pine_orange_small.gltf", 1.0],
	"pine_yellow_l": ["halloween/tree_pine_yellow_large.gltf", 1.0],
	"pine_yellow_m": ["halloween/tree_pine_yellow_medium.gltf", 1.0],
	"pine_yellow_s": ["halloween/tree_pine_yellow_small.gltf", 1.0],
	"dead_l": ["halloween/tree_dead_large.gltf", 1.1],
	"dead_l_deco": ["halloween/tree_dead_large_decorated.gltf", 1.1],
	"dead_m": ["halloween/tree_dead_medium.gltf", 1.1],
	"dead_s": ["halloween/tree_dead_small.gltf", 1.1],
	# forest (Medieval Hexagon nature, authored at tile scale)
	"green_a": ["nature/tree_single_A.gltf", 4.5],
	"green_b": ["nature/tree_single_B.gltf", 4.5],
	"grove_a": ["nature/trees_A_medium.gltf", 3.6],
	"grove_b": ["nature/trees_B_medium.gltf", 3.6],
	"rock_a": ["nature/rock_single_A.gltf", 6.0],
	"rock_b": ["nature/rock_single_B.gltf", 6.0],
	"rock_c": ["nature/rock_single_C.gltf", 5.0],
	"rock_d": ["nature/rock_single_D.gltf", 5.5],
	"rock_e": ["nature/rock_single_E.gltf", 4.5],
	"hill_a": ["nature/hill_single_A.gltf", 7.0],
	"hill_b": ["nature/hill_single_B.gltf", 6.0],
	"hill_c": ["nature/hill_single_C.gltf", 6.0],
	"waterlily_A": ["nature/waterlily_A.gltf", 1.0],
	"waterlily_B": ["nature/waterlily_B.gltf", 1.0],
	"waterplant_A": ["nature/waterplant_A.gltf", 1.0],
	"waterplant_B": ["nature/waterplant_B.gltf", 1.0],
	"waterplant_C": ["nature/waterplant_C.gltf", 1.0],
	"mountain_a": ["nature/mountain_A_grass_trees.gltf", 9.0],
	"mountain_b": ["nature/mountain_B_grass_trees.gltf", 9.0],
	"mountain_c": ["nature/mountain_C_grass_trees.gltf", 9.0],
	# graveyard / ruins (Halloween Bits)
	"arch_gate": ["halloween/arch_gate.gltf", 1.35],
	"arch": ["halloween/arch.gltf", 1.0],
	"ruin_pillar": ["halloween/pillar.gltf", 1.0],
	"gravestone": ["halloween/gravestone.gltf", 1.0],
	"grave_a": ["halloween/grave_A.gltf", 1.0],
	"grave_a_broken": ["halloween/grave_A_destroyed.gltf", 1.0],
	"grave_b": ["halloween/grave_B.gltf", 1.0],
	"gravemarker_a": ["halloween/gravemarker_A.gltf", 1.0],
	"gravemarker_b": ["halloween/gravemarker_B.gltf", 1.0],
	"post_skull": ["halloween/post_skull.gltf", 0.8],
	"post_lantern": ["halloween/post_lantern.gltf", 0.9],
	"lantern": ["halloween/lantern_standing.gltf", 1.0],
	"candles": ["halloween/candle_triple.gltf", 1.0],
	"skull": ["halloween/skull.gltf", 0.6],
	"skull_candle": ["halloween/skull_candle.gltf", 0.7],
	"bone_a": ["halloween/bone_A.gltf", 1.0],
	"bone_b": ["halloween/bone_B.gltf", 1.0],
	"bone_c": ["halloween/bone_C.gltf", 1.0],
	"ribcage": ["halloween/ribcage.gltf", 1.0],
	"pumpkin": ["halloween/pumpkin_orange.gltf", 1.0],
	"pumpkin_s": ["halloween/pumpkin_orange_small.gltf", 1.0],
	"pumpkin_ys": ["halloween/pumpkin_yellow_small.gltf", 1.0],
	"jackolantern": ["halloween/pumpkin_orange_jackolantern.gltf", 0.8],
	"fence_broken": ["halloween/fence_broken.gltf", 1.0],
	"fence_post": ["halloween/fence_pillar_broken.gltf", 1.0],
	"shrine": ["halloween/shrine_candles.gltf", 1.2],
	"crypt": ["halloween/crypt.gltf", 1.0],
	# dungeon (Dungeon Remastered)
	"log_s": ["dungeon/trunk_small_A.glb", 1.0],
	"log_m": ["dungeon/trunk_medium_A.glb", 1.0],
	"column": ["dungeon/column.glb", 1.8],
	"pillar_deco": ["dungeon/pillar_decorated.glb", 1.0],
	"rubble_l": ["dungeon/rubble_large.glb", 0.9],
	"rubble_h": ["dungeon/rubble_half.glb", 0.9],
	"torch": ["dungeon/torch_lit.glb", 1.4],
	"barrel": ["dungeon/barrel_small.glb", 1.0],
}

const VARIANTS := {
	"tree": ["pine_orange_l", "pine_orange_m", "pine_yellow_l", "pine_yellow_m", "pine_orange_s",
		"dead_l", "dead_m", "green_a", "green_b", "grove_a", "grove_b"],
	"border_tree": ["pine_orange_l", "pine_yellow_l", "pine_orange_m", "dead_l", "dead_l_deco", "grove_a", "grove_b"],
	"rock": ["rock_a", "rock_b", "rock_c", "rock_d", "rock_e"],
	"mountain": ["mountain_a", "mountain_b", "mountain_c"],
	"hill": ["hill_a", "hill_b", "hill_c"],
	"ruin": ["ruin_pillar", "column", "pillar_deco", "rubble_l", "rubble_h", "gravestone",
		"grave_a", "grave_a_broken", "grave_b", "shrine", "fence_broken"],
	"litter": ["pumpkin", "pumpkin_s", "pumpkin_ys", "bone_a", "bone_b", "bone_c", "ribcage",
		"skull", "gravemarker_a", "gravemarker_b", "fence_post", "dead_s", "pine_yellow_s"],
}

static var _cache := {}


static func scene(id: String) -> PackedScene:
	if _cache.has(id):
		return _cache[id]
	var ps: PackedScene = null
	if CATALOG.has(id):
		var path: String = ROOT + CATALOG[id][0]
		if ResourceLoader.exists(path):
			ps = load(path)
	_cache[id] = ps
	return ps


static func spawn(parent: Node3D, id: String, pos := Vector3.ZERO, extra_scale := 1.0) -> Node3D:
	var ps := scene(id)
	if ps == null:
		return null
	var n := ps.instantiate() as Node3D
	n.scale = Vector3.ONE * float(CATALOG[id][1]) * extra_scale
	n.position = pos
	parent.add_child(n)
	return n


static func spawn_variant(parent: Node3D, group: String, pos := Vector3.ZERO, extra_scale := 1.0) -> Node3D:
	var n := spawn(parent, VARIANTS[group].pick_random(), pos, extra_scale)
	if n != null:
		n.rotation.y = randf() * TAU
	return n


# Applies a material pass on top of every mesh under a model (spectral tint, burn).
static func overlay(model: Node, material: Material) -> void:
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_overlay = material


static func set_parts_visible(model: Node, names: Array, on: bool) -> void:
	for part in names:
		var n := model.find_child(part, true, false)
		if n is Node3D:
			(n as Node3D).visible = on
