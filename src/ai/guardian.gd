extends Node3D
## A special location's guardian (design/gdd/special-locations.md). The Jade
## Naga sleeps coiled as a statue in the temple hall; it wakes when an
## apprentice steps into the arena, slithers after them and attacks only
## after a readable telegraph on the ground (red ring = tail sweep, red lane
## = jade spit), then rests (punish window). If everyone leaves for a few
## seconds it goes back to sleep and heals: flee and come back.
## Values come from assets/data/dungeons.json; the world drives tick().
##
## Example: g.setup("temple", arena_center); g.tick(delta, world)

const Art = preload("res://src/core/art.gd")
const Data = preload("res://src/core/data.gd")

const SEGMENTS := 9
const STATUE := Color(0.55, 0.58, 0.55)
const JADE := Color(0.25, 0.85, 0.5)
const GOLD := Color(0.95, 0.75, 0.3)

var dungeon_id := "temple"
var cfg: Dictionary = {}
var home := Vector3.ZERO        # arena centre (where it sleeps)
var hp := 260.0
var hp_max := 260.0
var state := "dormant"          # dormant · waking · chase · telegraph · recover · dead
var attack := ""                # sweep · spit while telegraphing
var state_t := 0.0
var away_t := 0.0               # seconds with nobody inside the leash
var spit_cd := 2.0              # seconds until the next jade spit
var _aim := Vector3.FORWARD     # spit direction, locked when the telegraph starts
var _telegraph: MeshInstance3D
var _parts: Array = []          # body spheres (head first)
var _skin: StandardMaterial3D
var _flash_t := 0.0
var _clock := 0.0


func setup(id: String, at: Vector3) -> void:
	dungeon_id = id
	cfg = Data.dungeon(id).get("guardian", {})
	home = at
	hp_max = float(cfg.get("hp", 260))
	hp = hp_max


func _ready() -> void:
	_skin = StandardMaterial3D.new()
	_skin.albedo_color = STATUE
	_skin.emission_enabled = true
	_skin.emission = Color.BLACK
	var gold := Art.emissive(GOLD, GOLD * 0.4)
	for i in range(SEGMENTS):
		var r := 0.62 - i * 0.045
		var seg := Art.add_mesh(self, Art.sphere(r, r * 2.0), _skin, Vector3.ZERO)
		if i == 0:  # the head: a gold crest fanned like a naga hood
			for k in range(5):
				var fin := Art.add_mesh(seg, Art.cylinder(0.02, 0.12, 0.9), gold, Vector3(0, 0.55, -0.1))
				fin.rotation = Vector3(-0.35, 0, (k - 2) * 0.32)
			for side in [-0.22, 0.22]:
				Art.add_mesh(seg, Art.sphere(0.08, 0.16), Art.emissive(Color(1.0, 0.3, 0.2), Color(1.0, 0.2, 0.1)), Vector3(side, 0.15, 0.48))
		_parts.append(seg)
	_coil()


## Sleeping pose: a grey statue lying in an S on the dais.
func _coil() -> void:
	_pose(0.0, 0.0, null)


## The body trails behind the head in an S that ripples while it moves;
## the head rears up to telegraph an attack.
func _pose(wiggle: float, rear: float, world) -> void:
	var fwd := Vector3(sin(rotation.y), 0, cos(rotation.y))
	var side := Vector3(fwd.z, 0, -fwd.x)
	for i in range(SEGMENTS):
		var r := 0.62 - i * 0.045
		var k := float(i) / float(SEGMENTS - 1)
		var wp := global_position - fwd * (i * 0.62 - 0.4) + side * sin(i * 0.9 - _clock * 4.0 * wiggle) * 0.45 * k
		var ground := position.y
		if world != null:
			ground = world.terrain.height_at(wp.x, wp.z)
		wp.y = ground + r
		if i == 0:
			wp.y += 0.9 + rear
		elif i == 1:
			wp.y += (0.9 + rear) * 0.45
		if is_inside_tree():
			_parts[i].global_position = wp
		else:
			_parts[i].position = wp - global_position


func alive() -> bool:
	return state != "dead"


func awake() -> bool:
	return state != "dormant" and state != "dead"


func display_name() -> String:
	return String(cfg.get("name", "Guardião"))


## Damage from spells or blows. Hitting a sleeping guardian wakes it.
func take_hit(amount: float) -> void:
	if not alive():
		return
	hp = maxf(0.0, hp - amount)
	_flash_t = 0.15
	if state == "dormant":
		_set_state("waking", 0.6)
	if hp <= 0.0:
		_set_state("dead", 0.0)
		_clear_telegraph()


func _set_state(s: String, t: float) -> void:
	state = s
	state_t = t
	_skin.albedo_color = STATUE if s == "dormant" else JADE
	_skin.emission = Color.BLACK if s == "dormant" else JADE * (0.6 if s == "recover" else 0.25)


## Back to sleep with full health (everyone fled).
func reset() -> void:
	_clear_telegraph()
	hp = hp_max
	position = home
	_set_state("dormant", 0.0)
	_coil()


func tick(delta: float, world) -> void:
	_clock += delta
	if _flash_t > 0.0:
		_flash_t -= delta
		_skin.emission = Color(1, 1, 1) if _flash_t > 0.0 else JADE * 0.25
	if state == "dead":
		return
	var d_cfg: Dictionary = Data.dungeon(dungeon_id)
	var target = _nearest(world, float(d_cfg.get("leash_radius", 15)))
	if state == "dormant":
		if target != null and _flat(target.position, home) < float(cfg.get("wake_radius", 7)):
			_set_state("waking", 1.2)
			world.guardian_woke(self)
		return
	# flee and return: nobody near the arena for a while -> sleep and heal
	if target == null:
		away_t += delta
		if away_t >= float(d_cfg.get("reset_after", 6)):
			away_t = 0.0
			reset()
			world.guardian_reset(self)
		return
	away_t = 0.0
	state_t -= delta
	match state:
		"waking":
			if state_t <= 0.0:
				_set_state("chase", 0.0)
		"chase":
			_chase(delta, world, target, float(d_cfg.get("arena_radius", 9)))
		"telegraph":
			if state_t <= 0.0:
				_resolve(world)
				_set_state("recover", float(cfg.get("recover", 1.6)))
		"recover":
			if state_t <= 0.0:
				_set_state("chase", 0.0)
	_animate(delta, world)


func _nearest(world, leash: float):
	var best = null
	var bd := INF
	for p in world.alive_players():
		var d := _flat(p.position, home)
		if d > leash:
			continue
		var dp := _flat(p.position, position)
		if dp < bd:
			bd = dp
			best = p
	return best


func _chase(delta: float, world, target, arena: float) -> void:
	var to: Vector3 = target.position - position
	to.y = 0.0
	var d := to.length()
	var atk: Dictionary = cfg.get("attacks", {})
	var sweep: Dictionary = atk.get("sweep", {})
	var spit: Dictionary = atk.get("spit", {})
	if d <= float(sweep.get("range", 3.5)):
		_start("sweep", float(sweep.get("telegraph", 0.9)), to)
		return
	spit_cd -= delta
	if d <= float(spit.get("range", 9.0)) and spit_cd <= 0.0:
		spit_cd = float(spit.get("cooldown", 5.0))
		_start("spit", float(spit.get("telegraph", 0.8)), to)
		return
	var step := to.normalized() * minf(float(cfg.get("speed", 2.6)) * delta, maxf(0.0, d - 1.6))
	var next := position + step
	var off := Vector3(next.x - home.x, 0, next.z - home.z)
	if off.length() > arena:  # it never leaves its hall
		off = off.normalized() * arena
		next = home + off
	next.y = world.terrain.height_at(next.x, next.z)
	position = next
	if d > 0.1:
		rotation.y = atan2(to.x, to.z)


## Shows the telegraph on the ground: nothing hurts before it fills.
func _start(kind: String, seconds: float, to: Vector3) -> void:
	attack = kind
	_aim = to.normalized() if to.length() > 0.01 else Vector3.FORWARD
	rotation.y = atan2(_aim.x, _aim.z)
	_set_state("telegraph", seconds)
	_clear_telegraph()
	var a: Dictionary = cfg.get("attacks", {}).get(kind, {})
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1.0, 0.15, 0.1, 0.5)  # depth-tested: drawn on the floor, under the bodies
	_telegraph = MeshInstance3D.new()
	_telegraph.material_override = m
	if kind == "sweep":
		var r := float(a.get("radius", 4.0))
		_telegraph.mesh = Art.cylinder(r, r, 0.04)
		_telegraph.position = Vector3(0, 0.14, 0)
	else:
		var box := BoxMesh.new()
		var length := float(a.get("length", 10.0))
		box.size = Vector3(float(a.get("width", 1.6)), 0.04, length)
		_telegraph.mesh = box
		_telegraph.position = Vector3(0, 0.14, length * 0.5)
	add_child(_telegraph)
	_telegraph.scale = Vector3(0.2, 1, 0.2) if kind == "sweep" else Vector3(1, 1, 0.1)
	var tw := _telegraph.create_tween()
	tw.tween_property(_telegraph, "scale", Vector3.ONE, minf(seconds * 0.85, 0.8))


## Lands the attack on whoever is still inside the marked area.
func _resolve(world) -> void:
	var a: Dictionary = cfg.get("attacks", {}).get(attack, {})
	for p in world.alive_players():
		if hits(p.position, p.air):
			p.hit(float(a.get("damage", 15)))
			world.guardian_hit_player(self, p, attack)
	_clear_telegraph()


## True if a body at `pos` (hopping `air` metres up) is inside the current
## attack area. Jumping clears the tail sweep; only a side-step clears the spit.
func hits(pos: Vector3, air := 0.0) -> bool:
	var a: Dictionary = cfg.get("attacks", {}).get(attack, {})
	var rel := Vector3(pos.x - position.x, 0, pos.z - position.z)
	if attack == "sweep":
		return rel.length() <= float(a.get("radius", 4.0)) and air < 0.5
	if attack == "spit":
		var along := rel.dot(_aim)
		var side := absf(rel.dot(Vector3(_aim.z, 0, -_aim.x)))
		return along >= 0.0 and along <= float(a.get("length", 10.0)) and side <= float(a.get("width", 1.6)) * 0.5 + 0.4
	return false


func _clear_telegraph() -> void:
	if _telegraph != null and is_instance_valid(_telegraph):
		_telegraph.queue_free()
	_telegraph = null


func _animate(_delta: float, world) -> void:
	var rear := 0.6 if state == "telegraph" else (0.0 if state == "recover" else 0.25)
	_pose(1.0 if state == "chase" else 0.3, rear + sin(_clock * 3.0) * 0.06, world)
	if attack == "sweep" and state == "telegraph":
		rotation.y += 0.12  # winds up the tail


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
