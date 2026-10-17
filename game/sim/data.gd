class_name Data
extends RefCounted
## Loads the JSON files in res://data once and hands out read-only dictionaries.
## Tuning the game = editing those JSON files.

static var _cache: Dictionary = {}


static func get_file(file_name: String) -> Dictionary:
	if _cache.has(file_name):
		return _cache[file_name]
	var path := "res://data/%s.json" % file_name
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Data: cannot open %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Data: %s is not a JSON object" % path)
		return {}
	var d: Dictionary = _ints(parsed)
	d.erase("_note")
	_cache[file_name] = d
	return d


## JSON numbers arrive as floats; whole numbers become ints so `1 in [1, 2]` works.
static func _ints(v: Variant) -> Variant:
	match typeof(v):
		TYPE_FLOAT:
			if is_equal_approx(v, round(v)) and absf(v) < 1e9:
				return int(round(v))
			return v
		TYPE_ARRAY:
			var a: Array = []
			for x in v:
				a.append(_ints(x))
			return a
		TYPE_DICTIONARY:
			var d := {}
			for k in v.keys():
				d[k] = _ints(v[k])
			return d
	return v


static func balance() -> Dictionary:
	return get_file("balance")


static func kingdoms() -> Dictionary:
	return get_file("kingdoms")


static func buildings() -> Dictionary:
	return get_file("buildings")


static func events() -> Dictionary:
	return get_file("events")


static func enemies() -> Dictionary:
	return get_file("enemies")


static func dialogues() -> Dictionary:
	return get_file("dialogues")


## balance value by dotted path, e.g. B("champion.hp_base")
static func B(path: String, fallback: Variant = null) -> Variant:
	var node: Variant = balance()
	for part in path.split("."):
		if typeof(node) != TYPE_DICTIONARY or not (node as Dictionary).has(part):
			return fallback
		node = (node as Dictionary)[part]
	return node
