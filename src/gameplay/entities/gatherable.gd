extends Node3D
# Something on the island you pick up or strike: ghost-mushroom cluster, twig
# bundle, floating grimoire (one touch) or tree / rock (several strikes).
# Call setup() before adding it to the tree; strike() returns true once it is
# depleted and gives a little shake while it still stands.

const Art = preload("res://src/core/art.gd")
const Models = preload("res://src/core/models.gd")
const KINDS := {
	"mushroom": {"hp": 1, "gives": {"mushroom": 1}},
	"twig": {"hp": 1, "gives": {"twig": 1}},
	"page": {"hp": 1, "gives": {}},
	"tree": {"hp": 3, "gives": {"wood": 2}},
	"rock": {"hp": 2, "gives": {"stone": 2}},
}

var kind := "mushroom"
var hp := 1
var visual: Node3D
var _clock := 0.0


func setup(k: String) -> void:
	kind = k
	hp = KINDS[k]["hp"]


func _ready() -> void:
	_clock = randf() * TAU
	match kind:
		"mushroom":
			visual = _mushrooms()
		"twig":
			visual = _twigs()
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
			visual = Models.spawn_variant(self, "rock")
			if visual == null:
				visual = Art.add_mesh(self, Art.sphere(0.75, 1.0), Art.mat(Color(0.45, 0.46, 0.50)), Vector3(0, 0.35, 0))
	set_process(kind == "page")


func _process(delta: float) -> void:
	# grimoires float and turn slowly above the ruins
	_clock += delta
	visual.position.y = sin(_clock * 1.6) * 0.18
	visual.rotation.y += delta * 0.6


# A cluster of glowing ghost-mushrooms: pale stems, luminous blue caps.
func _mushrooms() -> Node3D:
	var root := Node3D.new()
	add_child(root)
	var stem := Art.mat(Color(0.85, 0.85, 0.8))
	var cap := Art.emissive(Color(0.55, 0.75, 1.0), Color(0.3, 0.55, 1.0))
	for i in range(randi_range(2, 4)):
		var off := Vector3(randf_range(-0.35, 0.35), 0, randf_range(-0.35, 0.35))
		var h := randf_range(0.25, 0.55)
		Art.add_mesh(root, Art.cylinder(0.05, 0.07, h), stem, off + Vector3(0, h * 0.5, 0))
		var r := randf_range(0.14, 0.26)
		Art.add_mesh(root, Art.sphere(r, r * 1.1), cap, off + Vector3(0, h, 0))
	return root


# A small bundle of fallen branches.
func _twigs() -> Node3D:
	var root := Node3D.new()
	add_child(root)
	var bark := Art.mat(Color(0.42, 0.30, 0.18))
	for i in range(3):
		var stick := Art.add_mesh(root, Art.cylinder(0.04, 0.06, 0.9), bark, Vector3(0, 0.06, 0))
		stick.rotation = Vector3(PI / 2.0, randf() * TAU, 0)
	return root


func strike() -> bool:
	hp -= 1
	if hp > 0 and visual != null and is_inside_tree():
		var tw := create_tween()
		tw.tween_property(visual, "rotation:z", 0.12, 0.06)
		tw.tween_property(visual, "rotation:z", -0.08, 0.08)
		tw.tween_property(visual, "rotation:z", 0.0, 0.08)
	return hp <= 0


func gives() -> Dictionary:
	return KINDS[kind]["gives"].duplicate()
