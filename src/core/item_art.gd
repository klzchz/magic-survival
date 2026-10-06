extends RefCounted
## Builds the 3D look of an item / structure icon key: a KayKit model when one
## fits, otherwise a small code-made shape. Used for ground drops, inventory
## icons and crafting-recipe icons, so every item looks the same everywhere.
##
## Example: `ItemArt.build(parent, Data.item("axe").icon)`

const Art = preload("res://src/core/art.gd")
const Models = preload("res://src/core/models.gd")


static func build(parent: Node3D, key: String) -> Node3D:
	var root := Node3D.new()
	parent.add_child(root)
	match key:
		"grass":
			var blade := Art.mat(Color(0.62, 0.68, 0.28))
			for i in range(7):
				var b := Art.add_mesh(root, Art.box(Vector3(0.05, 0.7, 0.05)), blade, Vector3(randf_range(-0.08, 0.08), 0.35, randf_range(-0.08, 0.08)))
				b.rotation.z = randf_range(-0.35, 0.35)
			Art.add_mesh(root, Art.cylinder(0.1, 0.1, 0.06), Art.mat(Color(0.5, 0.35, 0.18)), Vector3(0, 0.3, 0))
		"twig":
			var bark := Art.mat(Color(0.45, 0.32, 0.2))
			for i in range(3):
				var st := Art.add_mesh(root, Art.cylinder(0.035, 0.05, 0.9), bark, Vector3(0, 0.08 + i * 0.05, 0))
				st.rotation = Vector3(PI / 2.0, i * 0.5, 0)
		"flint":
			var shard := PrismMesh.new()
			shard.size = Vector3(0.35, 0.3, 0.2)
			Art.add_mesh(root, shard, Art.mat(Color(0.22, 0.23, 0.27)), Vector3(0, 0.15, 0))
			var shard2 := Art.add_mesh(root, shard, Art.mat(Color(0.3, 0.3, 0.36)), Vector3(0.15, 0.1, 0.05))
			shard2.rotation.y = 1.2
		"essence":
			Art.add_mesh(root, Art.sphere(0.2, 0.4), Art.emissive(Color(0.5, 0.25, 0.9), Color(0.6, 0.3, 1.2)), Vector3(0, 0.3, 0))
			Art.add_mesh(root, Art.sphere(0.1, 0.2), Art.emissive(Color(0.9, 0.8, 1.0), Color(1.2, 1.0, 1.4)), Vector3(0, 0.3, 0))
		"mushroom", "mushroom_cooked":
			var cooked := key == "mushroom_cooked"
			var cap := Art.mat(Color(0.45, 0.28, 0.15)) if cooked else Art.emissive(Color(0.55, 0.75, 1.0), Color(0.3, 0.55, 1.0))
			for off in [Vector3(-0.1, 0, 0), Vector3(0.12, 0, 0.06)]:
				Art.add_mesh(root, Art.cylinder(0.05, 0.06, 0.3), Art.mat(Color(0.85, 0.8, 0.72)), off + Vector3(0, 0.15, 0))
				Art.add_mesh(root, Art.sphere(0.17, 0.18), cap, off + Vector3(0, 0.32, 0))
		"berries", "berries_cooked":
			var red := Art.mat(Color(0.45, 0.08, 0.1)) if key == "berries_cooked" else Art.emissive(Color(0.85, 0.1, 0.2), Color(0.3, 0.0, 0.05))
			for i in range(6):
				Art.add_mesh(root, Art.sphere(0.09, 0.18), red, Vector3(randf_range(-0.14, 0.14), 0.1 + (i % 2) * 0.12, randf_range(-0.14, 0.14)))
		"pickaxe":
			var wood := Art.mat(Color(0.45, 0.3, 0.18))
			Art.add_mesh(root, Art.cylinder(0.04, 0.04, 1.0), wood, Vector3(0, 0.5, 0))
			var head := Art.add_mesh(root, Art.box(Vector3(0.75, 0.1, 0.1)), Art.mat(Color(0.55, 0.56, 0.6)), Vector3(0, 0.95, 0))
			head.rotation.z = 0.1
		"grass_armor":
			Art.add_mesh(root, Art.cylinder(0.32, 0.42, 0.75), Art.mat(Color(0.5, 0.6, 0.25)), Vector3(0, 0.4, 0))
			Art.add_mesh(root, Art.cylinder(0.33, 0.33, 0.06), Art.mat(Color(0.45, 0.3, 0.15)), Vector3(0, 0.45, 0))
		"rot":
			Art.add_mesh(root, Art.sphere(0.22, 0.3), Art.mat(Color(0.3, 0.32, 0.18)), Vector3(0, 0.12, 0))
		"campfire":
			for i in range(3):
				var lg := Models.spawn(root, "log_s", Vector3.ZERO, 0.8)
				if lg != null:
					lg.rotation.y = TAU * i / 3.0
			Art.add_mesh(root, Art.cylinder(0.05, 0.3, 0.45), Art.emissive(Color(1.0, 0.55, 0.15), Color(1.0, 0.45, 0.1)), Vector3(0, 0.3, 0))
		"altar":
			Models.spawn(root, "shrine")
		"ward":
			Models.spawn(root, "post_skull")
		"cauldron":
			var iron := Art.mat(Color(0.14, 0.14, 0.16))
			Art.add_mesh(root, Art.sphere(0.5, 0.8), iron, Vector3(0, 0.4, 0))
			Art.add_mesh(root, Art.cylinder(0.36, 0.36, 0.04), Art.emissive(Color(0.2, 0.9, 0.35), Color(0.15, 0.8, 0.3)), Vector3(0, 0.72, 0))
		_:
			if Models.spawn(root, key) == null:
				Art.add_mesh(root, Art.box(Vector3(0.3, 0.3, 0.3)), Art.mat(Color(0.6, 0.5, 0.7)), Vector3(0, 0.15, 0))
	return root
