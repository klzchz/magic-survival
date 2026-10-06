extends Node3D
## One apprentice: a character from assets/data/characters.json with its own
## stats, perks, DST-style inventory + equipment, wand/staff and the floating
## will-o'-wisp. The world drives it through perform(); peer_id is the network
## owner (1 = host / local) so Phase 2 co-op can map apprentices to peers.
## Implements design/gdd/survival-loop-mvp.md.

const Cfg = preload("res://src/core/config.gd")
const Art = preload("res://src/core/art.gd")
const Models = preload("res://src/core/models.gd")
const Rig = preload("res://src/core/rig.gd")
const Data = preload("res://src/core/data.gd")
const Inventory = preload("res://src/gameplay/inventory.gd")
# action id -> KayKit animation
const ACTION_ANIMS := {
	"chop": "1H_Melee_Attack_Chop", "pickup": "PickUp", "bolt": "Spellcast_Shoot",
	"lume": "Spellcast_Raise", "shield": "Block", "use": "Use_Item", "build": "Interact",
	"hurt": "Hit_A", "cheer": "Cheer",
}
const DARK_GRACE := 2.0    # seconds of darkness before the Mist bites
const DARK_DPS := 10.0

var peer_id := 1
var slot := 0              # 0..3, spawn spot in co-op
var char_id := "aldric"
var stats := {}            # the character definition (perks and multipliers)
var health_max := 100.0
var hunger_max := 150.0
var hunger := 150.0
var health := 100.0
var mana := 100.0
var mana_max := 100.0
var corruption := 0.0
var wisp := 100.0          # the wisp companion's light fuel
var inventory: Inventory
var shield_t := 0.0        # seconds of Escudo remaining
var dark_t := 0.0          # seconds spent in total darkness at night
var noise := 0.0           # arcane noise 0..100: magic use draws the Errantes
var dead := false
var wisp_light: OmniLight3D
var terrain = null         # set by the world: ground height + lakes
var collider: Callable     # set by the world: pushes out of solid things
var model: Node3D
var rig: Rig
var wisp_orb: Node3D
var torch_light: OmniLight3D
var shield_bubble: MeshInstance3D
var _hurt_cd := 0.0
var _clock := 0.0


## Call before adding to the tree.
func setup(character: String) -> void:
	char_id = character
	stats = Data.character(character)


func _ready() -> void:
	if stats.is_empty():
		setup(char_id)
	model = Models.spawn(self, stats.get("model", "mage"), Vector3.ZERO, 1.1)
	if model == null:  # fallback: primitive robe + hat
		model = Node3D.new()
		add_child(model)
		Art.add_mesh(model, Art.cylinder(0.42, 0.55, 1.4), Art.mat(Color(0.8, 0.78, 0.9)), Vector3(0, 0.7, 0))
		Art.add_mesh(model, Art.cylinder(0.02, 0.62, 1.0), Art.mat(Color(0.22, 0.16, 0.32)), Vector3(0, 1.75, 0))
	Models.set_parts_visible(model, stats.get("hide", []), false)
	rig = Rig.new(model)
	rig.set_base("Idle")

	var g: Array = stats.get("glow", [1.0, 0.8, 0.5])
	var glow := Color(g[0], g[1], g[2])
	wisp_orb = Node3D.new()
	wisp_orb.position = Vector3(0.9, 2.4, -0.4)
	add_child(wisp_orb)
	Art.add_mesh(wisp_orb, Art.sphere(0.18, 0.36), Art.emissive(glow, glow))
	wisp_light = Art.add_light(wisp_orb, glow, 12.0, 1.5, Vector3.ZERO)
	torch_light = Art.add_light(self, Color(1.0, 0.65, 0.3), 8.0, 1.6, Vector3(0.4, 2.2, 0.3))
	torch_light.visible = false

	var bubble_mat := StandardMaterial3D.new()
	bubble_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bubble_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bubble_mat.albedo_color = Color(0.5, 0.8, 1.0, 0.18)
	bubble_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	shield_bubble = Art.add_mesh(self, Art.sphere(1.5, 3.0), bubble_mat, Vector3(0, 1.2, 0))
	shield_bubble.visible = false
	if inventory == null:
		inventory = Inventory.new()


func _process(delta: float) -> void:
	_clock += delta
	if rig != null:
		rig.tick(delta)
	_hurt_cd = maxf(0.0, _hurt_cd - delta)
	if wisp_orb != null:
		wisp_orb.position = Vector3(cos(_clock * 1.3) * 0.9, 2.4 + sin(_clock * 2.1) * 0.25, sin(_clock * 1.3) * 0.9)
	if shield_bubble != null:
		shield_bubble.visible = shield_t > 0.0 and not dead


func perk(key: String, default := 1.0) -> float:
	return float(stats.get(key, default))


func respawn(at: Vector3, eco: bool) -> void:
	health_max = perk("health", 100.0)
	hunger_max = perk("hunger", 150.0)
	health = health_max
	hunger = hunger_max
	corruption = 0.0
	wisp = 100.0
	shield_t = 0.0
	dark_t = 0.0
	noise = 0.0
	dead = false
	visible = true
	if rig != null:
		rig.reset()
		rig.set_base("Idle")
	if wisp_orb != null:
		wisp_orb.visible = true
	apply_meta(eco)
	mana = mana_max
	inventory = Inventory.new()
	var start: Dictionary = stats.get("start", {})
	for id in start:
		inventory.add(id, int(start[id]))
	for i in range(Inventory.SIZE):  # starting gear goes straight to the hands
		var s = inventory.slots[i]
		if s != null and Data.item(s.id).has("equip"):
			inventory.equip_from(i)
	refresh_gear()
	position = at


## Eco Arcano deepens the mana pool permanently (+30 on top of the character).
func apply_meta(eco: bool) -> void:
	mana_max = perk("mana", 100.0) + (30.0 if eco else 0.0)
	mana = minf(mana, mana_max)


func tick_stats(delta: float) -> String:
	var note := ""
	hunger = maxf(0.0, hunger - 1.2 * perk("hunger_rate") * delta)
	if hunger <= 0.0:
		health = maxf(0.0, health - 3.0 * delta)
	mana = minf(mana_max, mana + 4.0 * perk("mana_regen") * delta)
	wisp = maxf(0.0, wisp - 1.5 * delta)
	corruption = maxf(0.0, corruption - 0.4 * delta)
	shield_t = maxf(0.0, shield_t - delta)
	noise = maxf(0.0, noise - float(Data.night("noise_decay", 6.0)) * delta)
	if inventory.tick_spoil(delta) > 0:
		note = "Alguma comida apodreceu"
	if inventory.hand_id() == "torch":
		var broke := inventory.wear("hand", delta)
		if broke != "":
			note = "A tocha se apagou"
			refresh_gear()
	return note


## Night darkness (DST's Charlie): with no light at all, the Mist wounds you.
func tick_darkness(in_light: bool, night: bool, delta: float) -> bool:
	if not night or in_light or dead:
		dark_t = 0.0
		return false
	dark_t += delta
	if dark_t > DARK_GRACE:
		health = maxf(0.0, health - DARK_DPS * delta)
		return true
	return false


func update_wisp_light(lit: float) -> void:
	wisp_light.light_energy = (1.0 - lit) * (0.5 + wisp * 0.02) if wisp > 0.0 else 0.0
	wisp_light.omni_range = 4.0 + wisp * 0.10
	torch_light.light_energy = (1.0 - lit * 0.7) * 1.6


func light_radius() -> float:
	var r := 0.0
	if wisp > 0.0:
		r = 4.0 + wisp * 0.10
	if inventory != null and inventory.hand_id() == "torch":
		r = maxf(r, float(inventory.hand_data().get("light", 8.0)))
	return r


## Shows the equipped hand item (staff / torch) on the model.
func refresh_gear() -> void:
	if model == null:
		return
	var hand := inventory.hand_id() if inventory != null else ""
	if char_id == "aldric":
		Models.set_parts_visible(model, ["1H_Wand"], hand != "bone_staff")
		Models.set_parts_visible(model, ["2H_Staff"], hand == "bone_staff")
	if torch_light != null:
		torch_light.visible = hand == "torch"


func move(dir: Vector3, delta: float) -> void:
	if dir.length() < 0.01:
		if rig != null:
			rig.set_base("Idle")
		return
	if rig != null:
		rig.set_base("Running_A")
	if model != null:
		model.rotation.y = lerp_angle(model.rotation.y, atan2(dir.x, dir.z), minf(1.0, 12.0 * delta))
	var step := dir.normalized() * Cfg.SPEED * delta
	var next := position + step
	if collider.is_valid():
		next = collider.call(next)
	next.x = clampf(next.x, -Cfg.WORLD, Cfg.WORLD)
	next.z = clampf(next.z, -Cfg.WORLD, Cfg.WORLD)
	if terrain != null:
		if not terrain.is_walkable(next.x, next.z):
			# slide along the shore instead of stopping dead
			var along_x := Vector3(position.x + step.x, 0, position.z)
			var along_z := Vector3(position.x, 0, position.z + step.z)
			if terrain.is_walkable(along_x.x, along_x.z):
				next = along_x
			elif terrain.is_walkable(along_z.x, along_z.z):
				next = along_z
			else:
				return
		next.y = terrain.height_at(next.x, next.z)
	position = next


## A single blow (Errante attack): armor, perks and the shield apply.
func hit(amount: float) -> void:
	hurt(amount, 1.0)


func hurt(dps: float, delta: float) -> void:
	if shield_t > 0.0 or dead:
		return
	var dmg := dps * delta * perk("damage_taken")
	var body = inventory.equip.body
	if body != null:
		var absorbed := dmg * float(Data.item(body.id).get("armor", 0.0))
		dmg -= absorbed
		inventory.wear("body", absorbed)
	health = maxf(0.0, health - dmg)
	corrupt(minf(4.0, 4.0 * delta))
	if _hurt_cd <= 0.0:
		_hurt_cd = 1.2
		play_action("hurt")


## Magic is loud: raises the arcane noise the Errantes hear (see night.json).
func make_noise(amount: float) -> void:
	noise = clampf(noise + amount, 0.0, 100.0)


## How far away an Errante hears this apprentice right now.
func heard_from() -> float:
	return maxf(float(Data.night("sense_radius", 10.0)), float(Data.night("hear_radius", 40.0)) * noise / 100.0)


func corrupt(amount: float) -> void:
	corruption = clampf(corruption + amount, 0.0, 100.0)


func heal(amount: float) -> void:
	health = minf(health_max, health + amount)


func spell_damage() -> float:
	return 60.0 * float(inventory.hand_data().get("spell_damage", 1.0)) * perk("bolt_mult")


func spell_cost() -> float:
	return 20.0 * float(inventory.hand_data().get("spell_cost", 1.0))


## Primary use of an inventory slot (number key / left click). Returns the HUD line.
func use_slot(i: int) -> String:
	var s = inventory.slots[i]
	if s == null:
		return ""
	var d := Data.item(s.id)
	if d.has("equip"):
		inventory.equip_from(i)
		refresh_gear()
		play_action("build")
		return "Equipou: %s" % d.name
	if d.has("hunger") or d.has("potion") or d.has("mana") and not d.has("wisp"):
		return _consume(i, d)
	if s.id == "essence":
		inventory.take_from(i)
		make_noise(float(d.get("noise", 0.0)))
		mana = minf(mana_max, mana + float(d.mana))
		wisp = minf(100.0, wisp + float(d.wisp))
		play_action("use")
		return "A Essência restaura mana e reacende o fogo-fátuo"
	if d.has("wisp"):
		inventory.take_from(i)
		wisp = minf(100.0, wisp + float(d.wisp))
		play_action("use")
		return "Alimentou o fogo-fátuo com %s" % d.name
	return "%s: não dá pra usar assim (receitas / combustível)" % d.name


func _consume(i: int, d: Dictionary) -> String:
	inventory.take_from(i)
	make_noise(float(d.get("noise", 0.0)))
	var mult := perk("potion_mult") if d.get("potion", false) else 1.0
	hunger = minf(hunger_max, hunger + float(d.get("hunger", 0.0)))
	heal(float(d.get("health", 0.0)) * mult)
	mana = minf(mana_max, mana + float(d.get("mana", 0.0)) * mult)
	corrupt(float(d.get("corruption", 0.0)) * (mult if float(d.get("corruption", 0.0)) < 0.0 else 1.0))
	play_action("use")
	return ("Bebeu: %s" if d.get("potion", false) else "Comeu: %s") % d.name


func unequip_hand() -> String:
	if inventory.equip.hand == null:
		return ""
	if not inventory.unequip("hand"):
		return "Inventário cheio"
	refresh_gear()
	return "Guardou o item da mão"


# ---------- body animation hooks ----------

func play_action(id: String) -> void:
	if rig != null and ACTION_ANIMS.has(id):
		rig.action(ACTION_ANIMS[id])


func face(target: Vector3) -> void:
	if model == null:
		return
	var d := target - position
	if Vector2(d.x, d.z).length() > 0.01:
		model.rotation.y = atan2(d.x, d.z)


func die() -> void:
	dead = true
	if rig != null:
		rig.hold("Death_A")
	if wisp_orb != null:
		wisp_orb.visible = false


func celebrate() -> void:
	if rig != null:
		rig.hold("Cheer")
