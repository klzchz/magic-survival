extends Node3D
# One apprentice: personal survival stats, inventory, wand and the wisp-light
# that follows them. The world drives it. peer_id is the network owner
# (1 = host / local) so Phase 2 co-op can map apprentices to peers.

const Cfg = preload("res://src/core/config.gd")
const Art = preload("res://src/core/art.gd")
const Models = preload("res://src/core/models.gd")
const Rig = preload("res://src/core/rig.gd")
const ROBES := [Color(0.80, 0.78, 0.90), Color(0.85, 0.70, 0.55), Color(0.60, 0.82, 0.70), Color(0.85, 0.62, 0.75)]
const WISP_COLORS := [Color(1.0, 0.8, 0.5), Color(0.55, 0.85, 1.0), Color(0.7, 1.0, 0.6), Color(1.0, 0.6, 0.85)]
# action id -> KayKit animation
const ACTION_ANIMS := {
	"chop": "1H_Melee_Attack_Chop", "pickup": "PickUp", "bolt": "Spellcast_Shoot",
	"lume": "Spellcast_Raise", "shield": "Block", "use": "Use_Item", "build": "Interact",
	"hurt": "Hit_A", "cheer": "Cheer",
}

var peer_id := 1
var slot := 0              # 0..3, picks the robe colour and spawn spot
var hunger := 100.0
var health := 100.0
var mana := 100.0
var mana_max := 100.0
var corruption := 0.0
var wisp := 100.0          # light fuel
var inv := {}
var wand_level := 0        # 0 = twig wand, 1 = bone wand
var shield_t := 0.0        # seconds of Escudo remaining
var dead := false
var wisp_light: OmniLight3D
var model: Node3D            # the KayKit mage (rotates to face movement)
var rig: Rig
var wisp_orb: Node3D         # the floating will-o'-wisp companion
var shield_bubble: MeshInstance3D
var _hurt_cd := 0.0
var _clock := 0.0


func _ready() -> void:
	model = Models.spawn(self, "mage", Vector3.ZERO, 1.1)
	if model == null:  # fallback: primitive robe + hat
		model = Node3D.new()
		add_child(model)
		Art.add_mesh(model, Art.cylinder(0.42, 0.55, 1.4), Art.mat(ROBES[slot % ROBES.size()]), Vector3(0, 0.7, 0))
		Art.add_mesh(model, Art.cylinder(0.02, 0.62, 1.0), Art.mat(Color(0.22, 0.16, 0.32)), Vector3(0, 1.75, 0))
	Models.set_parts_visible(model, ["Spellbook", "Spellbook_open", "2H_Staff"], false)
	rig = Rig.new(model)
	rig.set_base("Idle")

	var glow: Color = WISP_COLORS[slot % WISP_COLORS.size()]
	wisp_orb = Node3D.new()
	wisp_orb.position = Vector3(0.9, 2.4, -0.4)
	add_child(wisp_orb)
	Art.add_mesh(wisp_orb, Art.sphere(0.18, 0.36), Art.emissive(glow, glow))
	wisp_light = Art.add_light(wisp_orb, glow, 12.0, 1.5, Vector3.ZERO)
	wisp_light.shadow_enabled = false

	var bubble_mat := StandardMaterial3D.new()
	bubble_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bubble_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bubble_mat.albedo_color = Color(0.5, 0.8, 1.0, 0.18)
	bubble_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	shield_bubble = Art.add_mesh(self, Art.sphere(1.5, 3.0), bubble_mat, Vector3(0, 1.2, 0))
	shield_bubble.visible = false
	if inv.is_empty():
		reset_inventory()


func _process(delta: float) -> void:
	_clock += delta
	if rig != null:
		rig.tick(delta)
	_hurt_cd = maxf(0.0, _hurt_cd - delta)
	if wisp_orb != null:
		# the wisp drifts around the apprentice's shoulder
		wisp_orb.position = Vector3(cos(_clock * 1.3) * 0.9, 2.4 + sin(_clock * 2.1) * 0.25, sin(_clock * 1.3) * 0.9)
	if shield_bubble != null:
		shield_bubble.visible = shield_t > 0.0 and not dead


# Plays a one-shot body animation for an action id (see ACTION_ANIMS).
func play_action(id: String) -> void:
	if rig != null and ACTION_ANIMS.has(id):
		rig.action(ACTION_ANIMS[id])


func die() -> void:
	dead = true
	if rig != null:
		rig.hold("Death_A")
	if wisp_orb != null:
		wisp_orb.visible = false


func celebrate() -> void:
	if rig != null:
		rig.hold("Cheer")


func reset_inventory() -> void:
	inv = {"mushroom": 0, "cooked": 0, "twig": 0, "wood": 0, "stone": 0, "bone": 0}


func respawn(at: Vector3, eco: bool) -> void:
	hunger = 100.0
	health = 100.0
	corruption = 0.0
	wisp = 100.0
	wand_level = 0
	shield_t = 0.0
	dead = false
	visible = true
	if rig != null:
		rig.reset()
		rig.set_base("Idle")
	if wisp_orb != null:
		wisp_orb.visible = true
	_show_wand()
	apply_meta(eco)
	mana = mana_max
	reset_inventory()
	position = at


# Eco Arcano deepens the mana pool permanently.
func apply_meta(eco: bool) -> void:
	mana_max = 130.0 if eco else 100.0
	mana = minf(mana, mana_max)


func tick_stats(delta: float) -> void:
	hunger = maxf(0.0, hunger - 1.2 * delta)
	if hunger <= 0.0:
		health = maxf(0.0, health - 3.0 * delta)
	mana = minf(mana_max, mana + 4.0 * delta)
	wisp = maxf(0.0, wisp - 2.0 * delta)
	corruption = maxf(0.0, corruption - 0.4 * delta)
	shield_t = maxf(0.0, shield_t - delta)


func update_wisp_light(lit: float) -> void:
	wisp_light.light_energy = (1.0 - lit) * (0.5 + wisp * 0.02)
	wisp_light.omni_range = 4.0 + wisp * 0.10


func light_radius() -> float:
	return wisp_light.omni_range


func move(dir: Vector3, delta: float) -> void:
	if dir.length() < 0.01:
		if rig != null:
			rig.set_base("Idle")
		return
	if rig != null:
		rig.set_base("Running_A")
	if model != null:
		model.rotation.y = lerp_angle(model.rotation.y, atan2(dir.x, dir.z), minf(1.0, 12.0 * delta))
	position += dir.normalized() * Cfg.SPEED * delta
	position.x = clampf(position.x, -Cfg.WORLD, Cfg.WORLD)
	position.z = clampf(position.z, -Cfg.WORLD, Cfg.WORLD)


func hurt(dps: float, delta: float) -> void:
	if shield_t > 0.0 or dead:
		return
	health = maxf(0.0, health - dps * delta)
	corrupt(4.0 * delta)
	if _hurt_cd <= 0.0:
		_hurt_cd = 1.2
		play_action("hurt")


func face(target: Vector3) -> void:
	if model == null:
		return
	var d := target - position
	if Vector2(d.x, d.z).length() > 0.01:
		model.rotation.y = atan2(d.x, d.z)


# Twig wand by default; the bone-wand upgrade shows the staff instead.
func _show_wand() -> void:
	if model == null:
		return
	Models.set_parts_visible(model, ["1H_Wand"], wand_level == 0)
	Models.set_parts_visible(model, ["2H_Staff"], wand_level == 1)


func corrupt(amount: float) -> void:
	corruption = minf(100.0, corruption + amount)


func heal(amount: float) -> void:
	health = minf(100.0, health + amount)


func has(cost: Dictionary) -> bool:
	for k in cost:
		if inv.get(k, 0) < cost[k]:
			return false
	return true


func pay(cost: Dictionary) -> bool:
	if not has(cost):
		return false
	for k in cost:
		inv[k] -= cost[k]
	return true


func gain(items: Dictionary) -> void:
	for k in items:
		inv[k] = inv.get(k, 0) + items[k]


func spell_damage() -> float:
	return 110.0 if wand_level == 1 else 60.0


func spell_cost() -> float:
	return 12.0 if wand_level == 1 else 20.0


# ---------- personal actions (no world placement); each returns the HUD line ----------

func eat() -> String:
	# cooked food first: more hunger, no corruption
	if inv.cooked > 0:
		inv.cooked -= 1
		hunger = minf(100.0, hunger + 35.0)
		return "Comeu cogumelo assado (+fome, sem corrupção)"
	if inv.mushroom > 0:
		inv.mushroom -= 1
		hunger = minf(100.0, hunger + 22.0)
		corrupt(3.0)
		return "Comeu cogumelo cru (+fome, +corrupção)"
	return "Sem comida"


func feed_wisp() -> String:
	if not pay({"twig": 1}):
		return "Sem galhos"
	wisp = minf(100.0, wisp + 35.0)
	return "Alimentou o fogo-fátuo"


func brew() -> String:
	if not pay({"mushroom": 2}):
		return "Precisa de 2 cogumelos"
	heal(30.0)
	corrupt(6.0)
	return "Poção improvisada (+vida, +corrupção)"


func cook() -> String:
	if not pay({"mushroom": 1}):
		return "Sem cogumelos crus"
	gain({"cooked": 1})
	return "Assou um cogumelo"


func brew_elixir() -> String:
	if not pay({"mushroom": 2}):
		return "Elixir: precisa 2 cogumelos"
	heal(50.0)
	return "Elixir do caldeirão (+50 vida, SEM corrupção)"


func upgrade_wand() -> String:
	if wand_level >= 1:
		return "A varinha de osso já é sua"
	if not pay({"bone": 3, "wood": 2}):
		return "Varinha: precisa 3 ossos + 2 madeiras"
	wand_level = 1
	_show_wand()
	return "Varinha de osso: feitiço mais forte, mana mais barata"
