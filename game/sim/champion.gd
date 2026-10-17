class_name Champion
extends RefCounted
## The player's physical character. Pure data + rules, no drawing.

const ATTRS: Array[String] = ["STR", "DEX", "CON", "INT", "WIS", "CHA"]
const ATTR_NAMES := {
	"STR": "Strength", "DEX": "Dexterity", "CON": "Constitution",
	"INT": "Intelligence", "WIS": "Wisdom", "CHA": "Charisma",
}
const ATTR_DESC := {
	"STR": "melee, force, intimidation",
	"DEX": "movement, dodging, sleight of hand",
	"CON": "HP, endurance, poison, weather",
	"INT": "inscriptions, strategy, mechanisms",
	"WIS": "reading people, hidden opportunities",
	"CHA": "persuasion, leadership, diplomacy",
}

var name: String = "Mira"
var attrs: Dictionary = {"STR": 1, "DEX": 4, "CON": 3, "INT": 1, "WIS": 5, "CHA": 4}
var hp: int = 16
var extra_max_hp: int = 0
var xp: int = 0
var level: int = 1
var unspent_points: int = 0
var equip: Dictionary = {"weapon": "", "armor": "", "trinket": ""}   # item ids ("" = empty)
var bag: Array = []              # [{"id": item id, "n": count}] — consumables/valuables stack
## Old names kept so older code keeps working: weapon = equipped weapon, salves = salves in the bag.
var weapon: String:
	get: return str(equip.weapon)
	set(v): equip.weapon = v
var salves: int:
	get: return count("salve")
	set(v): set_count("salve", v)
var cargo: Dictionary = {"food": 0, "wood": 0, "stone": 0, "gold": 0, "iron": 0}
var pos: Vector2i = Vector2i.ZERO
var generation: int = 1          # 1 = founder, 2 = first heir...


func attr(a: String) -> int:
	return int(attrs.get(a, 0)) + item_bonus(a)


func base_attr(a: String) -> int:
	return int(attrs.get(a, 0))


func max_hp() -> int:
	var base: int = Data.B("champion.hp_base", 10)
	var per: int = Data.B("champion.hp_per_con", 2)
	var lvl_bonus: int = Data.B("champion.level_hp_bonus", 2)
	return base + per * attr("CON") + lvl_bonus * (level - 1) + extra_max_hp


## Movement bonus by DEX tier (guide): DEX 0-2 → +0, 3-4 → +1, 5+ → +2, then more tiers for later levels.
func move_bonus() -> int:
	var tiers: Array = Data.B("champion.dex_move_tiers", [0, 3, 5])
	var b := 0
	for i in tiers.size():
		if attr("DEX") >= int(tiers[i]):
			b = i
	return b + item_bonus("move")


func cargo_total() -> int:
	var t := 0
	for k in cargo.keys():
		t += int(cargo[k])
	return t


func defense() -> int:
	return int(Data.B("champion.defense_base", 10)) + int(attr("DEX") / int(Data.B("champion.defense_dex_divisor", 2))) + item_bonus("def")


func weapon_info() -> Dictionary:
	if str(equip.weapon) == "":
		return {"name": "Walking stick", "hit": 0, "dmg": 0}
	var it := Champion.item(str(equip.weapon))
	var b: Dictionary = it.get("bonus", {})
	return {"name": str(it.get("name", equip.weapon)), "hit": int(b.get("hit", 0)), "dmg": int(b.get("dmg", 0))}


# ---------------------------------------------------------------- inventory

static func item(id: String) -> Dictionary:
	return (Data.get_file("items").items as Dictionary).get(id, {})


static func stacks(id: String) -> bool:
	return str(Champion.item(id).get("slot", "")) in ["consumable", "valuable"]


## Sum of a bonus key over everything equipped (attributes, def, move, hit, dmg).
func item_bonus(key: String) -> int:
	var t := 0
	for sl in equip.keys():
		var id := str(equip[sl])
		if id != "":
			t += int((Champion.item(id).get("bonus", {}) as Dictionary).get(key, 0))
	return t


func count(id: String) -> int:
	var n := 0
	for e in bag:
		if str(e.id) == id:
			n += int(e.n)
	return n


func has_item(id: String) -> bool:
	return count(id) > 0 or id in equip.values()


func bag_full_for(id: String) -> bool:
	if Champion.stacks(id) and count(id) > 0:
		return false
	return bag.size() >= int(Data.get_file("items").get("bag_slots", 8))


## Adds n of an item. Returns how many fit (the rest is left on the road).
func add_item(id: String, n: int = 1) -> int:
	if Champion.item(id).is_empty():
		return 0
	var added := 0
	for i in n:
		if Champion.stacks(id):
			var found := false
			for e in bag:
				if str(e.id) == id:
					e.n = int(e.n) + 1
					found = true
					break
			if not found:
				if bag_full_for(id):
					break
				bag.append({"id": id, "n": 1})
		else:
			if bag_full_for(id):
				break
			bag.append({"id": id, "n": 1})
		added += 1
	return added


func remove_item(id: String, n: int = 1) -> bool:
	if count(id) < n:
		return false
	for i in n:
		for e in bag:
			if str(e.id) == id:
				e.n = int(e.n) - 1
				if int(e.n) <= 0:
					bag.erase(e)
				break
	return true


func set_count(id: String, v: int) -> void:
	var cur := count(id)
	if v > cur:
		add_item(id, v - cur)
	elif v < cur:
		remove_item(id, cur - v)


## Moves a bag item into its slot; whatever was there goes back to the bag.
func equip_item(id: String) -> bool:
	var sl := str(Champion.item(id).get("slot", ""))
	if not sl in equip or count(id) <= 0:
		return false
	remove_item(id)
	var old := str(equip[sl])
	equip[sl] = id
	if old != "":
		bag.append({"id": old, "n": 1})
	return true


func unequip(sl: String) -> bool:
	var old := str(equip.get(sl, ""))
	if old == "" or bag.size() >= int(Data.get_file("items").get("bag_slots", 8)):
		return false
	equip[sl] = ""
	bag.append({"id": old, "n": 1})
	return true


func xp_for_next() -> int:
	var levels: Array = Data.B("champion.xp_levels", [0, 40, 100])
	if level < levels.size():
		return int(levels[level])
	return int(levels[-1]) + 200 * (level - levels.size() + 1)


func xp_for_current() -> int:
	var levels: Array = Data.B("champion.xp_levels", [0, 40, 100])
	if level - 1 < levels.size():
		return int(levels[level - 1])
	return int(levels[-1])


## Returns number of levels gained.
func add_xp(amount: int) -> int:
	xp += amount
	var gained := 0
	while xp >= xp_for_next():
		level += 1
		unspent_points += 1
		hp += int(Data.B("champion.level_hp_bonus", 2))
		gained += 1
	return gained


func heal(amount: int) -> int:
	var before := hp
	hp = clampi(hp + amount, 0, max_hp())
	return hp - before


func archetype() -> String:
	var table := {
		"DEX+WIS": "the wandering scout", "CHA+WIS": "the perceptive talker",
		"CON+STR": "the iron wall", "DEX+STR": "the duelist",
		"INT+WIS": "the quiet scholar", "CHA+STR": "the loud captain",
		"CHA+DEX": "the silver-tongued rogue", "CON+WIS": "the stubborn pilgrim",
		"CHA+INT": "the court schemer", "DEX+INT": "the clever tinkerer",
		"CON+DEX": "the long-road runner", "INT+STR": "the siege-minded",
		"STR+WIS": "the hunter", "CHA+CON": "the hearty host", "CON+INT": "the patient engineer",
	}
	var sorted := ATTRS.duplicate()
	sorted.sort_custom(func(a, b):
		if attr(a) == attr(b):
			return ATTRS.find(a) < ATTRS.find(b)
		return attr(a) > attr(b))
	var total := 0
	for a in ATTRS:
		total += attr(a)
	if total == 0:
		return "nobody yet"
	var top := [sorted[0], sorted[1]]
	top.sort()
	return table.get("%s+%s" % [top[0], top[1]], "an odd one")


func to_dict() -> Dictionary:
	return {
		"name": name, "attrs": attrs.duplicate(), "hp": hp, "extra_max_hp": extra_max_hp,
		"xp": xp, "level": level, "unspent_points": unspent_points, "equip": equip.duplicate(), "bag": bag.duplicate(true), "cargo": cargo.duplicate(), "pos": [pos.x, pos.y], "generation": generation,
	}
