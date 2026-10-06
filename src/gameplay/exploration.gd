extends RefCounted
## Fog of war for the world map: a grid of explored cells over the island.
## Walking reveals a soft circle around the apprentice (never a whole biome);
## once seen, a cell stays seen. Also holds the player's base and personal
## map pins. Pure logic + JSON-safe save (base64), tested in tests/smoke.gd.
##
## Example:
##   explo.reveal(player.position)          # every few metres walked
##   explo.is_discovered(Vector3(40, 0, 10))

const CELL := 5.0              # metres per fog cell
const REVEAL_RADIUS := 18.0    # how far the apprentice "sees" while walking

var half := 160.0              # world half-extent (set from Cfg.WORLD)
var size := 64                 # cells per side
var cells := PackedByteArray() # 0 = hidden, 255 = explored
var base := {}                 # {"kind": "cabin", "pos": [x, z]} or {}
var markers: Array = []        # personal pins: [[x, z], ...]
var revision := 0              # bumps when cells change (map redraws the fog)


func _init(world_half := 160.0) -> void:
	half = world_half
	size = int(ceil(half * 2.0 / CELL))
	cells.resize(size * size)
	cells.fill(0)


func _cell(x: float, z: float) -> Vector2i:
	return Vector2i(clampi(int((x + half) / CELL), 0, size - 1), clampi(int((z + half) / CELL), 0, size - 1))


func is_discovered(p: Vector3) -> bool:
	var c := _cell(p.x, p.z)
	return cells[c.y * size + c.x] > 0


## Reveals a circle around p. Returns true if anything new was seen.
func reveal(p: Vector3, radius := REVEAL_RADIUS) -> bool:
	var changed := false
	var r := int(ceil(radius / CELL))
	var c := _cell(p.x, p.z)
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var cx := c.x + dx
			var cz := c.y + dz
			if cx < 0 or cz < 0 or cx >= size or cz >= size:
				continue
			var center := Vector2((cx + 0.5) * CELL - half, (cz + 0.5) * CELL - half)
			if center.distance_to(Vector2(p.x, p.z)) > radius:
				continue
			var i := cz * size + cx
			if cells[i] == 0:
				cells[i] = 255
				changed = true
	if changed:
		revision += 1
	return changed


func discovered_ratio() -> float:
	var n := 0
	for v in cells:
		if v > 0:
			n += 1
	return float(n) / float(cells.size())


func set_base(kind: String, p: Vector3) -> void:
	base = {"kind": kind, "pos": [snappedf(p.x, 0.1), snappedf(p.z, 0.1)]}


## Adds a pin, or removes the nearest pin within `grab` metres (toggle).
func toggle_marker(p: Vector3, grab := 6.0) -> bool:
	for i in range(markers.size()):
		if Vector2(markers[i][0], markers[i][1]).distance_to(Vector2(p.x, p.z)) < grab:
			markers.remove_at(i)
			return false
	markers.append([snappedf(p.x, 0.1), snappedf(p.z, 0.1)])
	return true


func to_save() -> Dictionary:
	return {"cells": Marshalls.raw_to_base64(cells), "size": size, "base": base, "markers": markers}


func from_save(d: Dictionary) -> void:
	if int(d.get("size", 0)) == size:
		var raw := Marshalls.base64_to_raw(String(d.get("cells", "")))
		if raw.size() == cells.size():
			cells = raw
	base = d.get("base", {})
	markers = d.get("markers", [])
	revision += 1
