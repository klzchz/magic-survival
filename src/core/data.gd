extends RefCounted
## Game data loaded once from assets/data/*.json (items, recipes, characters,
## world resources). Tune the game there, not in code.
##
## Example: `Data.item("axe").get("uses")` -> 60.0

const PATHS := {
	"items": "res://assets/data/items.json",
	"recipes": "res://assets/data/recipes.json",
	"characters": "res://assets/data/characters.json",
	"resources": "res://assets/data/resources.json",
}

static var _cache := {}


static func table(key: String) -> Dictionary:
	if not _cache.has(key):
		var data = {}
		var f := FileAccess.open(PATHS[key], FileAccess.READ)
		if f != null:
			var parsed = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				data = parsed
		_cache[key] = data
	return _cache[key]


static func item(id: String) -> Dictionary:
	return table("items").get(id, {})


static func item_name(id: String) -> String:
	return item(id).get("name", id)


static func character(id: String) -> Dictionary:
	return table("characters").get(id, {})


static func resource(kind: String) -> Dictionary:
	return table("resources").get(kind, {})


static func recipes() -> Array:
	return table("recipes").get("recipes", [])


static func recipe(id: String) -> Dictionary:
	for r in recipes():
		if r.id == id:
			return r
	return {}


static func tabs() -> Array:
	return table("recipes").get("tabs", [])


## Structure kind a crafting tab needs nearby ("" = craftable anywhere).
static func tab_tech(tab: String) -> String:
	return table("recipes").get("tech", {}).get(tab, "")


## Display name of an item or a structure recipe.
static func display_name(id: String) -> String:
	var r := recipe(id)
	if r.has("name"):
		return r.name
	return item_name(id)
