extends RefCounted
## Save / continue for the current run (the roguelite meta lives in
## meta_save.gd). The island is rebuilt from its seed (relief, lakes, decor),
## then everything that changed is restored: resources (regrowth, saplings),
## structures (fuel), ground items, the apprentice (stats, inventory, gear),
## the clock and this run's Mist Hearts. Deleted on death and on victory.
##
## Example: RunSave.write(world) · RunSave.exists() · RunSave.read() -> Dictionary

const PATH := "user://run_save.json"
const VERSION := 1


static func exists() -> bool:
	return FileAccess.file_exists(PATH)


static func erase() -> void:
	if exists():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


static func _v(v: Vector3) -> Array:
	return [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]


static func vec(a) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


static func snapshot(w) -> Dictionary:
	var p = w.local_player
	var res := []
	for g in w.resources():
		res.append({"kind": g.kind, "pos": _v(g.position), "hp": g.hp, "grown": g.grown,
			"regrow_t": g.regrow_t, "grow_t": g.grow_t, "item_id": g.item_id,
			"item_count": g.item_count, "item_stack": g.item_stack})
	var sts := []
	for s in w._children(w.structures_root):
		sts.append({"kind": s.kind, "pos": _v(s.position), "fuel": s.fuel, "fuel_mult": s.fuel_mult})
	return {
		"version": VERSION,
		"world_seed": w.world_seed,
		"character": p.char_id,
		"clock": {"t": w.day_night.t, "nights": w.day_night.nights, "blood_moon": w.day_night.blood_moon, "prev_night": w.day_night.prev_night},
		"run_hearts": w.run_hearts,
		"objective_step": w.objective_step,
		"obj_flags": w.obj_flags,
		"player": {"pos": _v(p.position), "health": p.health, "hunger": p.hunger, "mana": p.mana,
			"corruption": p.corruption, "wisp": p.wisp, "noise": p.noise,
			"slots": p.inventory.slots, "equip": p.inventory.equip},
		"resources": res,
		"structures": sts,
	}


static func write(w) -> bool:
	if w.local_player == null or w.local_player.dead:
		return false
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(snapshot(w)))
	return true


static func read() -> Dictionary:
	if not exists():
		return {}
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return {}
	var data = JSON.parse_string(f.get_as_text())
	return data if data is Dictionary and int(data.get("version", 0)) == VERSION else {}


## JSON turns ints into floats: normalise a saved stack back to game types.
static func stack(s):
	if s == null or not (s is Dictionary) or s.is_empty():
		return null
	var out: Dictionary = s.duplicate()
	out.count = int(out.count)
	return out
