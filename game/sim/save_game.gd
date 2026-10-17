class_name SaveGame
extends RefCounted
## Saving and loading a campaign.
##
## A save is one text file in user://saves/ written with Godot's var_to_str():
## it keeps Dictionaries with Vector2i keys, Vectors and arrays exactly, so the
## whole GameState (plus its World and Champion) can be dumped field by field.
## Slots: "auto" (written at the end of every day when autosave is on) and 1..3.

const DIR := "user://saves"
const SLOTS := ["auto", "1", "2", "3"]
const VERSION := 2
const SKIP := ["weapon", "salves"]     # computed properties on Champion


static func _path(slot: String) -> String:
	return "%s/%s.sav" % [DIR, slot]


static func _dump(obj: Object) -> Dictionary:
	var out := {}
	for p in obj.get_property_list():
		if not (int(p.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var n := str(p.name)
		if n in SKIP:
			continue
		var v = obj.get(n)
		if v is Object:
			continue
		out[n] = v
	return out


static func _restore(obj: Object, data: Dictionary) -> void:
	for n in data.keys():
		if n in obj:
			obj.set(n, data[n])


static func save(st: GameState, slot: String) -> bool:
	DirAccess.make_dir_recursive_absolute(DIR)
	var data := {
		"version": VERSION,
		"meta": {"kingdom": st.kingdom, "kname": st.kname(st.kingdom), "day": st.day, "week": st.week(), "age": st.age_name(),
			"champion": st.champ.name, "level": st.champ.level, "time": Time.get_datetime_string_from_system(false, true)},
		"state": _dump(st),
		"world": _dump(st.world),
		"champ": _dump(st.champ),
		"rng": [st.rng.seed, st.rng.state],
	}
	var f := FileAccess.open(_path(slot), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(var_to_str(data))
	return true


static func exists(slot: String) -> bool:
	return FileAccess.file_exists(_path(slot))


static func meta(slot: String) -> Dictionary:
	if not exists(slot):
		return {}
	var d = _read(slot)
	return d.get("meta", {}) if d is Dictionary else {}


static func _read(slot: String):
	var f := FileAccess.open(_path(slot), FileAccess.READ)
	if f == null:
		return null
	return str_to_var(f.get_as_text())


static func load_into(slot: String) -> GameState:
	var d = _read(slot)
	if not (d is Dictionary) or not d.has("state"):
		return null
	var st := GameState.new()
	_restore(st, d.state)
	_restore(st.world, d.world)
	_restore(st.champ, d.champ)
	var r: Array = d.get("rng", [0, 0])
	st.rng.seed = int(r[0])
	st.rng.state = int(r[1])
	return st


## The most recently written slot (for "Continue"), or "".
static func latest() -> String:
	var best := ""
	var best_t := 0
	for s in SLOTS:
		if exists(s):
			var t := FileAccess.get_modified_time(_path(s))
			if t > best_t:
				best_t = t
				best = s
	return best


static func delete(slot: String) -> void:
	if exists(slot):
		DirAccess.remove_absolute(_path(slot))
