extends Node3D
# One apprentice: personal survival stats, inventory, wand and the wisp-light
# that follows them. The world drives it. peer_id is the network owner
# (1 = host / local) so Phase 2 co-op can map apprentices to peers.

const Cfg = preload("res://src/core/config.gd")
const Art = preload("res://src/core/art.gd")
const ROBES := [Color(0.80, 0.78, 0.90), Color(0.85, 0.70, 0.55), Color(0.60, 0.82, 0.70), Color(0.85, 0.62, 0.75)]

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


func _ready() -> void:
	Art.add_mesh(self, Art.cylinder(0.42, 0.55, 1.4), Art.mat(ROBES[slot % ROBES.size()]), Vector3(0, 0.7, 0))
	Art.add_mesh(self, Art.cylinder(0.02, 0.62, 1.0), Art.mat(Color(0.22, 0.16, 0.32)), Vector3(0, 1.75, 0))
	wisp_light = Art.add_light(self, Color(1.0, 0.8, 0.5), 12.0, 1.5, Vector3(0, 1.5, 0))
	if inv.is_empty():
		reset_inventory()


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
		return
	position += dir.normalized() * Cfg.SPEED * delta
	position.x = clampf(position.x, -Cfg.WORLD, Cfg.WORLD)
	position.z = clampf(position.z, -Cfg.WORLD, Cfg.WORLD)


func hurt(dps: float, delta: float) -> void:
	if shield_t > 0.0 or dead:
		return
	health = maxf(0.0, health - dps * delta)
	corrupt(4.0 * delta)


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
	return "Varinha de osso: feitiço mais forte, mana mais barata"
