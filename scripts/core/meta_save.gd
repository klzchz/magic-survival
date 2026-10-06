extends RefCounted
# Roguelite meta progression that survives death: best night count, Mist
# Hearts and learned spells (knowledge persists between islands). Shared by
# the whole party in co-op.

const Cfg = preload("res://scripts/core/config.gd")

var path: String
var best_nights := 0
var hearts := 0
var spells: Array = []


func _init(save_path: String = Cfg.SAVE_PATH) -> void:
	path = save_path


func load_from_disk() -> void:
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	if data is Dictionary:
		best_nights = int(data.get("best_nights", 0))
		hearts = int(data.get("hearts", 0))
		var sp = data.get("spells", [])
		if sp is Array:
			spells = sp


func save() -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"best_nights": best_nights, "hearts": hearts, "spells": spells}))


func knows(id: String) -> bool:
	return id in spells


# Learns the next unknown spell and returns its id, or "" when all are known.
func learn_next() -> String:
	for id in Cfg.SPELL_ORDER:
		if not knows(id):
			spells.append(id)
			save()
			return id
	return ""


func record_nights(n: int) -> void:
	if n > best_nights:
		best_nights = n
		save()
