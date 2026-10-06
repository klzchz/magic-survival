extends Node3D
## Something on the island you pick or strike (assets/data/resources.json):
## grass tufts, saplings and berry bushes regrow after being picked; trees need
## an axe, rocks a pickaxe; mushrooms, flint and dropped items are picked once;
## grimoire pages teach spells. Call setup() / setup_item() before add_child.

const Art = preload("res://src/core/art.gd")
const Models = preload("res://src/core/models.gd")
const Data = preload("res://src/core/data.gd")
const ItemArt = preload("res://src/core/item_art.gd")

var kind := "mushroom"
var hp := 1
var item_id := ""          # for kind "item": what lies on the ground
var item_count := 1
var item_stack := {}       # optional full stack (keeps durability / freshness)
var grown := true          # false while a regrowable is picked
var regrow_t := 0.0
var visual: Node3D
var _fruit: Node3D         # berries / blades that vanish when picked
var _clock := 0.0


func setup(k: String) -> void:
	kind = k
	hp = int(Data.resource(k).get("hp", 1))


func setup_item(id: String, count := 1, stack := {}) -> void:
	setup("item")
	item_id = id
	item_count = count
	item_stack = stack


func info() -> Dictionary:
	return Data.resource(kind)


func tool_needed() -> String:
	return info().get("tool", "")


func regrows() -> bool:
	return info().has("regrow")


func display_name() -> String:
	return Data.item_name(item_id) if kind == "item" else info().get("name", kind)


func _ready() -> void:
	_clock = randf() * TAU
	match kind:
		"mushroom":
			visual = ItemArt.build(self, "mushroom")
			visual.scale = Vector3.ONE * 1.4
		"grass_tuft":
			visual = Node3D.new()
			add_child(visual)
			Art.add_mesh(visual, Art.cylinder(0.25, 0.35, 0.15), Art.mat(Color(0.35, 0.3, 0.15)), Vector3(0, 0.07, 0))
			_fruit = Node3D.new()
			visual.add_child(_fruit)
			var blade := Art.mat(Color(0.6, 0.66, 0.25))
			for i in range(9):
				var b := Art.add_mesh(_fruit, Art.box(Vector3(0.06, 1.0, 0.06)), blade, Vector3(randf_range(-0.2, 0.2), 0.5, randf_range(-0.2, 0.2)))
				b.rotation = Vector3(randf_range(-0.3, 0.3), 0, randf_range(-0.3, 0.3))
		"sapling":
			visual = Node3D.new()
			add_child(visual)
			var bark := Art.mat(Color(0.42, 0.3, 0.18))
			Art.add_mesh(visual, Art.cylinder(0.05, 0.08, 0.5), bark, Vector3(0, 0.25, 0))
			_fruit = Node3D.new()
			visual.add_child(_fruit)
			Art.add_mesh(_fruit, Art.cylinder(0.03, 0.05, 1.2), bark, Vector3(0, 0.9, 0))
			for i in range(4):
				var tw := Art.add_mesh(_fruit, Art.cylinder(0.02, 0.03, 0.6), bark, Vector3(0, 0.8 + i * 0.2, 0))
				tw.rotation = Vector3(0.9, i * 1.6, 0)
			Art.add_mesh(_fruit, Art.sphere(0.25, 0.4), Art.mat(Color(0.75, 0.45, 0.15)), Vector3(0, 1.55, 0))
		"berry_bush":
			visual = Node3D.new()
			add_child(visual)
			Art.add_mesh(visual, Art.sphere(0.75, 1.1), Art.mat(Color(0.18, 0.32, 0.14)), Vector3(0, 0.5, 0))
			Art.add_mesh(visual, Art.sphere(0.5, 0.8), Art.mat(Color(0.22, 0.38, 0.16)), Vector3(0.4, 0.45, 0.2))
			_fruit = Node3D.new()
			visual.add_child(_fruit)
			var red := Art.emissive(Color(0.85, 0.1, 0.2), Color(0.35, 0.0, 0.05))
			for i in range(8):
				var a := randf() * TAU
				Art.add_mesh(_fruit, Art.sphere(0.08, 0.16), red, Vector3(cos(a) * 0.62, randf_range(0.35, 0.9), sin(a) * 0.62))
		"item":
			visual = ItemArt.build(self, Data.item(item_id).get("icon", item_id))
			visual.scale = Vector3.ONE * 0.9
			visual.rotation.y = randf() * TAU
		"page":
			visual = Node3D.new()
			add_child(visual)
			var book := Models.spawn(visual, "spellbook", Vector3(0, 0.9, 0), 1.3)
			if book == null:
				Art.add_mesh(visual, Art.box(Vector3(0.5, 0.06, 0.65)), Art.emissive(Color(0.95, 0.9, 0.6), Color(0.9, 0.75, 0.2)), Vector3(0, 0.9, 0))
			Art.add_light(visual, Color(1.0, 0.85, 0.4), 5.0, 1.2, Vector3(0, 1.3, 0))
		"tree":
			visual = Models.spawn_variant(self, "tree")
			if visual == null:
				visual = Node3D.new()
				add_child(visual)
				Art.add_mesh(visual, Art.cylinder(0.3, 0.42, 3.0), Art.mat(Color(0.34, 0.24, 0.16)), Vector3(0, 1.5, 0))
				Art.add_mesh(visual, Art.sphere(1.7, 3.4), Art.mat(Color(0.11, 0.30, 0.15)), Vector3(0, 3.6, 0))
		"rock":
			visual = Models.spawn_variant(self, "rock", Vector3.ZERO, 1.6)
			if visual == null:
				visual = Art.add_mesh(self, Art.sphere(0.75, 1.0), Art.mat(Color(0.45, 0.46, 0.50)), Vector3(0, 0.35, 0))
	set_process(kind == "page" or kind == "item")


func _process(delta: float) -> void:
	_clock += delta
	if kind == "page":  # grimoires float and turn slowly above the ruins
		visual.position.y = sin(_clock * 1.6) * 0.18
		visual.rotation.y += delta * 0.6
	else:               # dropped items bob a little so they read as loot
		visual.position.y = 0.1 + sin(_clock * 2.5) * 0.06


## What one successful pick / final strike yields.
func gives() -> Dictionary:
	if kind == "item":
		return {item_id: item_count}
	return info().get("gives", {}).duplicate()


## One strike (or pick). Returns true when it yields: depleted or picked.
func strike(power := 1) -> bool:
	hp -= power
	if hp > 0 and visual != null and is_inside_tree():
		var tw := create_tween()
		tw.tween_property(visual, "rotation:z", 0.12, 0.06)
		tw.tween_property(visual, "rotation:z", -0.08, 0.08)
		tw.tween_property(visual, "rotation:z", 0.0, 0.08)
	return hp <= 0


## Regrowables become bare instead of disappearing.
func set_picked() -> void:
	grown = false
	regrow_t = float(info().get("regrow", 120.0))
	if _fruit != null:
		_fruit.visible = false


## Called by the world every tick for picked regrowables.
func tick_regrow(delta: float) -> void:
	if grown:
		return
	regrow_t -= delta
	if regrow_t <= 0.0:
		grown = true
		hp = int(info().get("hp", 1))
		if _fruit != null:
			_fruit.visible = true
