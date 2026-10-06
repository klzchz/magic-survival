extends RefCounted
## Don't Starve style inventory: 15 slots of stacks plus `hand` / `body`
## equipment. A stack is {"id", "count"} plus "uses" (durability or burn
## seconds left) for gear and "fresh" (seconds until it rots) for food.
## Pure logic, no nodes: unit-tested in tests/smoke.gd.
##
## Example:
##   var inv := Inventory.new()
##   var overflow := inv.add("twig", 50)   # 40 fit in one stack, 10 in the next
##   inv.pay({"twig": 2, "flint": 2})      # false if anything is missing

const Data = preload("res://src/core/data.gd")
const SIZE := 15

var slots: Array = []
var equip := {"hand": null, "body": null}


func _init() -> void:
	slots.resize(SIZE)
	slots.fill(null)


static func make(id: String, count := 1) -> Dictionary:
	var d := Data.item(id)
	var s := {"id": id, "count": count}
	if d.has("uses"):
		s.uses = float(d.uses)
	elif d.has("burn"):
		s.uses = float(d.burn)
	if d.has("spoil"):
		s.fresh = float(d.spoil)
	return s


static func stack_max(id: String) -> int:
	return int(Data.item(id).get("stack", 1))


## Adds items and returns how many did NOT fit (the caller drops them).
func add(id: String, count := 1) -> int:
	var left := count
	var cap := stack_max(id)
	var spoil := float(Data.item(id).get("spoil", 0.0))
	for s in slots:
		if left <= 0:
			break
		if s != null and s.id == id and s.count < cap:
			var n: int = mini(cap - s.count, left)
			if spoil > 0.0:  # new items are fresh: average the stack
				s.fresh = (s.fresh * s.count + spoil * n) / float(s.count + n)
			s.count += n
			left -= n
	for i in range(SIZE):
		if left <= 0:
			break
		if slots[i] == null:
			var n2: int = mini(cap, left)
			slots[i] = make(id, n2)
			left -= n2
	return left


## Puts an existing stack (keeps durability/freshness) into the first free slot.
func put_stack(stack: Dictionary) -> bool:
	for i in range(SIZE):
		if slots[i] == null:
			slots[i] = stack
			return true
	return false


func count(id: String) -> int:
	var n := 0
	for s in slots:
		if s != null and s.id == id:
			n += s.count
	return n


func has_all(cost: Dictionary) -> bool:
	for k in cost:
		if count(k) < int(cost[k]):
			return false
	return true


func remove(id: String, n: int) -> bool:
	if count(id) < n:
		return false
	for i in range(SIZE - 1, -1, -1):
		var s = slots[i]
		if n <= 0:
			break
		if s != null and s.id == id:
			var take: int = mini(s.count, n)
			s.count -= take
			n -= take
			if s.count <= 0:
				slots[i] = null
	return true


func pay(cost: Dictionary) -> bool:
	if not has_all(cost):
		return false
	for k in cost:
		remove(k, int(cost[k]))
	return true


## Removes n items from slot i and returns them as a stack ({} if empty).
func take_from(i: int, n := 1) -> Dictionary:
	var s = slots[i]
	if s == null:
		return {}
	var take: int = mini(n, s.count)
	var out: Dictionary = s.duplicate()
	out.count = take
	s.count -= take
	if s.count <= 0:
		slots[i] = null
	return out


## Equips slot i into its equipment slot, swapping out what was there.
func equip_from(i: int) -> bool:
	var s = slots[i]
	if s == null:
		return false
	var where: String = Data.item(s.id).get("equip", "")
	if where == "":
		return false
	slots[i] = equip[where]
	equip[where] = s
	return true


func unequip(where: String) -> bool:
	if equip[where] == null or not put_stack(equip[where]):
		return false
	equip[where] = null
	return true


func hand_id() -> String:
	return equip.hand.id if equip.hand != null else ""


func hand_data() -> Dictionary:
	return Data.item(hand_id()) if equip.hand != null else {}


## Spends durability of an equipped item; returns the item id if it broke.
func wear(where: String, amount: float) -> String:
	var s = equip[where]
	if s == null or not s.has("uses"):
		return ""
	s.uses -= amount
	if s.uses <= 0.0:
		equip[where] = null
		return s.id
	return ""


## Ages food; spoiled stacks turn into rot. Returns how many stacks rotted.
func tick_spoil(delta: float) -> int:
	var rotted := 0
	for i in range(SIZE):
		var s = slots[i]
		if s != null and s.has("fresh"):
			s.fresh -= delta
			if s.fresh <= 0.0:
				slots[i] = {"id": "rot", "count": s.count}
				rotted += 1
	return rotted
