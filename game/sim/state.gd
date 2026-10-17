class_name GameState
extends RefCounted
## The whole campaign as plain data plus the rules that change it.
## Nothing here draws or waits for animations — the screens read this state,
## call its actions, and animate the results it returns. That split is what
## lets tests/sim_test.gd play hundreds of days without a window.
##
## Two stores of resources exist on purpose:
##   res          - the kingdom's storehouse (what buildings make and spend)
##   champ.cargo  - what the Champion carries. Loot found on the road goes here
##                  and only reaches the kingdom when the Champion walks home.

const RES: Array[String] = ["food", "wood", "stone", "gold", "iron"]
const WEATHERS := {
	"clear": {"name": "Clear skies", "text": "Fair walking weather."},
	"rain": {"name": "Rainy week", "text": "River crossings cost +1 move."},
	"fair": {"name": "Market fair", "text": "Markets earn +2 gold a day."},
	"harvest": {"name": "Harvest week", "text": "Farms yield +2 food a day."},
}

var world := World.new()
var champ := Champion.new()
var rng := RandomNumberGenerator.new()

var kingdom := "red"
var day := 1
var res := {"food": 20, "wood": 20, "stone": 10, "gold": 20, "iron": 0}
var stash: Array = []               # storehouse items made by buildings each week: [{"id", "n"}]
var pop := 5
var age := 1
var upgrades: Dictionary = {}       # upgrade id -> day bought
var city: Dictionary = {}           # local slot Vector2i -> {"type", "day"}
var city_terrain: Dictionary = {}   # local slot Vector2i -> terrain string
var builds_today := 0
var city_radius := 2                # grows with expand_city()

var party: Array = []               # formation, front first: {"kind": "champion"} or unit dicts
var next_uid := 1
var patrols: Array = []             # roaming enemy groups {id, group, pos, alive}

var rolled := false
var roll := 0
var moves := 0
var events_today := 0
var alive := true

var explored: Dictionary = {}       # discovered hexes
var visited: Dictionary = {}        # hexes the Champion has stood on
var discovered_places: Dictionary = {}
var place_ids: Dictionary = {}      # hex -> place id
var relations: Dictionary = {}
var flags: Dictionary = {}
var history: Array = []
var weather := "clear"
var next_weather := "rain"
var envoy_day := -1
var week_acc: Dictionary = {}
var last_week_report: Dictionary = {}
var quests: Dictionary = {}         # quest id -> {"state": "active"|"done", "day", "progress": [int per objective]}
var kills: Dictionary = {}          # enemy group id -> times beaten
var dungeon_run: Dictionary = {}    # the delve in progress: {"id", "room", "rooms": [kinds], "log"}


# ==========================================================================
# Setup
# ==========================================================================

func new_game(p_seed: int, p_kingdom: String, p_champ: Champion) -> void:
	rng.seed = p_seed
	kingdom = p_kingdom
	world.generate(p_seed, p_kingdom)
	place_ids.clear()
	for pid in world.places.keys():
		place_ids[world.places[pid]] = pid
	champ = p_champ
	champ.hp = champ.max_hp()
	champ.pos = world.capitals[kingdom]
	var start: Dictionary = Data.B("start", {})
	for r in RES:
		res[r] = int(start.get(r, 0))
	pop = int(start.get("pop", 5))
	day = 1
	age = 1
	alive = true
	party = [{"kind": "champion"}]
	relations = {}
	var rel: Dictionary = kdef(kingdom).get("relations", {})
	for k in Data.kingdoms().keys():
		if k != kingdom:
			relations[k] = int(rel.get(k, 0))
	_setup_city(str(kdef(kingdom).home))
	explored.clear()
	visited.clear()
	discovered_places.clear()
	reveal(world.capitals[kingdom], int(Data.B("map.start_reveal", 3)))
	for k in world.capitals.keys():
		reveal(world.capitals[k], 1)
	visited[champ.pos] = true
	_spawn_patrols()
	_reset_week()
	weather = "clear"
	next_weather = "rain"
	add_history("found", "%s raised the %s banner" % [champ.name, kname(kingdom)], world.capitals[kingdom])
	quests.clear()
	kills.clear()
	for q in Data.get_file("quests").get("start", []):
		start_quest(str(q))


func _setup_city(home: String) -> void:
	city.clear()
	city_terrain.clear()
	for h in Hex.ring(Vector2i.ZERO, 2):
		city_terrain[h] = "plains"
	var forest: Array = []
	var water: Array = []
	var hills: Array = []
	match home:
		"plains_west":
			forest = [Vector2i(0, -2), Vector2i(1, -2), Vector2i(2, -2)]
			water = [Vector2i(2, 0), Vector2i(1, 1), Vector2i(0, 2)]
		"lakes_east":
			forest = [Vector2i(-2, 0), Vector2i(-2, 1), Vector2i(-1, -1), Vector2i(0, -2)]
			water = [Vector2i(2, -2), Vector2i(2, -1), Vector2i(1, 1)]
		_:
			forest = [Vector2i(-2, 2), Vector2i(-1, 2)]
			hills = [Vector2i(0, -2), Vector2i(1, -2), Vector2i(2, -2), Vector2i(2, -1)]
	for h in forest:
		city_terrain[h] = "forest"
	for h in water:
		city_terrain[h] = "water"
	for h in hills:
		city_terrain[h] = "hills"
	city[Vector2i.ZERO] = {"type": "hall", "day": 0}
	if home == "hills_north":
		flags["outpost_stone"] = 0   # Yellow starts with a quarry seam


func _reset_week() -> void:
	week_acc = {
		"prod": _zero(),
		"spent": _zero(),
		"delivered": _zero(),
		"eaten": 0, "upkeep": 0, "gifts": [], "rel": [], "battles": [], "pop_start": pop, "start_day": day,
	}


# ==========================================================================
# Helpers
# ==========================================================================

func _zero() -> Dictionary:
	var z := {}
	for r in RES:
		z[r] = 0
	return z


func kdef(kid: String) -> Dictionary:
	return Data.kingdoms().get(kid, {})


func kname(kid: String) -> String:
	return str(kdef(kid).get("name", kid))


func week() -> int:
	return int((day - 1) / 7) + 1


func day_in_week() -> int:
	return (day - 1) % 7 + 1


func at_capital() -> bool:
	return champ.pos == world.capitals[kingdom]


func relation_label(kid: String) -> String:
	var v: int = relations.get(kid, 0)
	if v <= -15: return "hostile"
	if v <= -6: return "competitive"
	if v < 0: return "wary"
	if v < 5: return "neutral"
	if v < 10: return "curious"
	if v < 20: return "warm"
	return "friendly"


func vars() -> Dictionary:
	var m := world.merchant
	var r := world.rival
	return {
		"player": kname(kingdom), "merchant": kname(m), "rival": kname(r),
		"cargo": kdef(m).get("cargo", "goods"), "gift_text": kdef(m).get("gift_text", "a gift"),
		"name": champ.name,
	}


func fmt(s: String) -> String:
	return s.format(vars())


func add_history(kind: String, text: String, h: Vector2i) -> void:
	history.append({"day": day, "kind": kind, "text": text, "h": h})


func change_relation(kid: String, amount: int, reason: String) -> void:
	if kid == "" or kid == kingdom or not relations.has(kid):
		return
	relations[kid] = clampi(int(relations[kid]) + amount, -50, 50)
	week_acc.rel.append({"kid": kid, "amount": amount, "reason": reason})


func is_explored(h: Vector2i) -> bool:
	return explored.has(h)


func reveal(center: Vector2i, radius: int) -> Array:
	var out: Array = []
	for h in Hex.ring(center, radius):
		if world.has(h) and not explored.has(h):
			explored[h] = true
			out.append(h)
	return out


func place_visible(h: Vector2i) -> bool:
	var t: Dictionary = world.tile(h)
	if t.is_empty() or t.place == "":
		return false
	if t.secret and not flags.has("surveyor_map") and not flags.has("found_" + str(place_ids.get(h, ""))):
		return false
	return is_explored(h)


## Names of places that just became visible (for "DISCOVERED" banners).
func check_discoveries() -> Array:
	var out: Array = []
	for h in place_ids.keys():
		var pid: String = place_ids[h]
		if discovered_places.has(pid):
			continue
		if place_visible(h):
			discovered_places[pid] = day
			var t: Dictionary = world.tile(h)
			if str(t.place) != "capital" or h != world.capitals[kingdom]:
				out.append(str(t.name))
				add_history("discover", "%s discovered" % str(t.name), h)
	return out


# ==========================================================================
# Movement
# ==========================================================================

func roll_moves() -> int:
	if rolled or not alive:
		return roll
	roll = rng.randi_range(1, 6)
	moves = roll + champ.move_bonus()
	rolled = true
	return roll


func move_cost(h: Vector2i) -> int:
	return world.cost(h, weather == "rain")


func flood(max_cost: int = 9999) -> Dictionary:
	var start := champ.pos
	var cost := {start: 0}
	var prev := {}
	var open: Array = [start]
	while not open.is_empty():
		var bi := 0
		for i in open.size():
			if cost[open[i]] < cost[open[bi]]:
				bi = i
		var cur: Vector2i = open[bi]
		open.remove_at(bi)
		if cur != start and ((world.tile(cur).place != "" and place_visible(cur)) or patrol_at(cur) >= 0):
			continue
		for nb in Hex.neighbors(cur):
			if not world.passable(nb):
				continue
			var nc: int = cost[cur] + move_cost(nb)
			if nc > max_cost:
				continue
			if not cost.has(nb) or nc < cost[nb]:
				cost[nb] = nc
				prev[nb] = cur
				open.append(nb)
	return {"cost": cost, "prev": prev}


func path_to(target: Vector2i) -> Array:
	if not world.passable(target) or target == champ.pos:
		return []
	var f := flood()
	if not f.cost.has(target):
		return []
	var chain: Array = [target]
	var c := target
	while f.prev.has(c) and f.prev[c] != champ.pos:
		c = f.prev[c]
		chain.push_front(c)
	var out: Array = []
	var total := 0
	for h in chain:
		var mc := move_cost(h)
		total += mc
		out.append({"h": h, "cost": mc, "total": total, "reachable": rolled and total <= moves})
	return out


## Move one hex (must be adjacent). Returns what happened there.
func step(h: Vector2i) -> Dictionary:
	var out := {"ok": false}
	if not rolled or Hex.distance(h, champ.pos) != 1 or not world.passable(h):
		return out
	var c := move_cost(h)
	if c > moves:
		return out
	moves -= c
	champ.pos = h
	visited[h] = true
	out.ok = true
	out.cost = c
	out.revealed = reveal(h, int(Data.B("map.sight", 2)))
	var t: Dictionary = world.tile(h)
	if t.secret:
		flags["found_" + str(place_ids.get(h, ""))] = true
	out.discovered = check_discoveries()
	out.place = ""
	out.event = ""
	out.battle = ""
	out.delivered = {}
	var pi := patrol_at(h)
	if pi >= 0:
		out.battle = "patrol:%d" % pi
		return out
	if h == world.capitals[kingdom]:
		out.delivered = deliver_cargo()
		out.place = place_interaction(h)
		return out
	if t.place != "":
		if place_ids.has(h):
			flags["visited_" + str(place_ids[h])] = day
		out.place = place_interaction(h)
	elif events_today < 2:
		var chance: float = (Data.B("danger.event_chance", [0.06, 0.2, 0.36]) as Array)[int(t.band)]
		if rng.randf() < chance:
			out.event = pick_event(t)
			if out.event != "":
				events_today += 1
	return out


func place_interaction(h: Vector2i) -> String:
	var t: Dictionary = world.tile(h)
	var pid := str(place_ids.get(h, ""))
	match str(t.place):
		"capital":
			if h == world.capitals[kingdom]:
				return "home"
			if h == world.capitals.get(world.merchant):
				return "dialogue:harbor"
			if h == world.capitals.get(world.rival):
				return "dialogue:forge"
		"crossroads":
			if day <= 4 and not flags.has("tobbin_done"):
				return "dialogue:tobbin"
			return "card:crossroads_quiet"
		"ruins":
			if flags.has("surveyor_map"):
				return "card:ruins_done"
			return "dialogue:ruins"
		"grove":
			return "dialogue:hermit"
		"deposit":
			if t.owner == kingdom:
				return "card:own_outpost"
			return "card:outpost"
		"iron":
			if t.owner == kingdom:
				return "card:own_outpost"
			return "card:iron"
		"cove":
			return "card:empty_cove" if flags.has("cove_looted") else "card:cove"
		"tower":
			return "card:tower_done" if flags.has("tower_climbed") else "card:tower"
		"dungeon":
			if flags.has("dungeon_done_" + str(t.dungeon)):
				return "card:dungeon_done"
			return "dungeon:" + str(t.dungeon)
		"camp":
			if flags.has("cleared_" + pid):
				return "card:camp_cleared"
			return "camp:" + pid
	return ""


## Story conditions on an event: once-only, flags set by earlier events (chains), earliest day.
func event_allowed(id: String, e: Dictionary) -> bool:
	if e.get("once", false) and flags.has("ev_" + id):
		return false
	if e.has("requires_flag") and not flags.has(str(e.requires_flag)):
		return false
	if e.has("forbids_flag") and flags.has(str(e.forbids_flag)):
		return false
	if e.has("after_flag_days"):
		var fl := str(e.requires_flag)
		if not flags.has(fl) or day - int(flags[fl]) < int(e.after_flag_days):
			return false
	if day < int(e.get("min_day", 0)):
		return false
	if e.has("needs_item") and not champ.has_item(str(e.needs_item)):
		return false
	if str(e.get("skip_if_item", "")) != "" and champ.has_item(str(e.skip_if_item)):
		return false
	return true


func pick_event(t: Dictionary) -> String:
	var pool: Array = []
	var total := 0.0
	for id in Data.events().keys():
		var e: Dictionary = Data.events()[id]
		if not (t.terrain in e.terrain) or int(t.band) < int(e.band):
			continue
		if not event_allowed(id, e):
			continue
		pool.append([id, float(e.weight)])
		total += float(e.weight)
	if pool.is_empty():
		return ""
	var pick := rng.randf() * total
	for p in pool:
		pick -= p[1]
		if pick <= 0.0:
			return p[0]
	return pool[-1][0]


# ==========================================================================
# Cargo
# ==========================================================================

## Moves everything the Champion carries into the kingdom. Returns what moved.
func deliver_cargo() -> Dictionary:
	var picked := collect_stash()
	if not picked.is_empty():
		add_history("delivery", "%s took %s from the storehouse" % [champ.name, ", ".join(picked)], world.capitals[kingdom])
	var moved := {}
	for r in RES:
		var v := int(champ.cargo.get(r, 0))
		if v > 0:
			res[r] += v
			week_acc.delivered[r] += v
			moved[r] = v
			champ.cargo[r] = 0
	if not moved.is_empty():
		var parts: Array[String] = []
		for k in moved.keys():
			parts.append("%d %s" % [moved[k], k])
		add_history("delivery", "%s brought home %s" % [champ.name, ", ".join(parts)], world.capitals[kingdom])
	return moved


## Load supplies from the kingdom into the cargo (only at home). amount may be negative to unload.
func load_cargo(r: String, amount: int) -> bool:
	if not at_capital():
		return false
	if amount > 0 and int(res[r]) < amount:
		return false
	if amount < 0 and int(champ.cargo[r]) < -amount:
		return false
	res[r] -= amount
	champ.cargo[r] = int(champ.cargo[r]) + amount
	return true


# ==========================================================================
# Checks and effects
# ==========================================================================

func check(attr: String, dc: int) -> Dictionary:
	var r := rng.randi_range(1, 20)
	var bonus := champ.attr(attr)
	return {"attr": attr, "roll": r, "bonus": bonus, "total": r + bonus, "dc": dc, "success": r + bonus >= dc}


static func chance(bonus: int, dc: int) -> int:
	return int(clampf((21.0 - (dc - bonus)) / 20.0, 0.0, 1.0) * 100.0)


func store(to: String) -> Dictionary:
	return champ.cargo if to == "cargo" else res


func can_afford(cost: Dictionary, from: String = "kingdom") -> bool:
	var s := store(from)
	for k in cost.keys():
		if int(s.get(k, 0)) < int(cost[k]):
			return false
	return true


func pay(cost: Dictionary, from: String = "kingdom") -> void:
	var s := store(from)
	for k in cost.keys():
		s[k] = int(s[k]) - int(cost[k])
		if from == "kingdom":
			week_acc.spent[k] += int(cost[k])


## Applies an effects dictionary. Resource changes go to `to` ("cargo" or "kingdom").
## Returns a list of {kind, amount, label, to} changes for floating text.
func apply(effects: Dictionary, source: String = "", to: String = "cargo") -> Array:
	var changes: Array = []
	var s := store(to)
	for r in RES:
		if effects.has(r):
			var amt := int(effects[r])
			s[r] = maxi(0, int(s.get(r, 0)) + amt)
			changes.append({"kind": r, "amount": amt, "to": to})
			if amt > 0:
				week_acc.gifts.append({"res": r, "amount": amt, "from": source, "to": to})
			elif to == "kingdom":
				week_acc.spent[r] += -amt
	if effects.has("gift_from"):
		var giver := str(effects.gift_from)
		var kid := world.merchant if giver == "merchant" else (world.rival if giver == "rival" else giver)
		changes.append_array(apply(kdef(kid).get("gift", {}), source, to))
	if effects.has("pop"):
		pop += int(effects.pop)
		changes.append({"kind": "pop", "amount": int(effects.pop)})
	if effects.has("max_hp"):
		champ.extra_max_hp += int(effects.max_hp)
		changes.append({"kind": "max_hp", "amount": int(effects.max_hp)})
	if effects.has("hp"):
		var amt := int(effects.hp)
		if amt >= 0:
			amt = champ.heal(amt)
		else:
			champ.hp = maxi(0, champ.hp + amt)
		if amt != 0:
			changes.append({"kind": "hp", "amount": amt})
		if champ.hp <= 0:
			alive = false
	if effects.has("xp"):
		var lv := champ.add_xp(int(effects.xp))
		changes.append({"kind": "xp", "amount": int(effects.xp)})
		if lv > 0:
			changes.append({"kind": "level", "amount": champ.level})
			add_history("level", "%s reached level %d" % [champ.name, champ.level], champ.pos)
	if effects.has("moves"):
		var m := int(effects.moves)
		moves = maxi(0, moves + m)
		changes.append({"kind": "moves", "amount": m})
	if effects.has("end_day"):
		moves = 0
		changes.append({"kind": "end_day", "amount": 0})
	if effects.has("item"):
		var list: Array = effects.item if effects.item is Array else [effects.item]
		for iid in list:
			changes.append_array(give_item(str(iid)))
	if effects.has("remove_item"):
		var rid := str(effects.remove_item)
		if champ.remove_item(rid):
			changes.append({"kind": "item_lost", "amount": -1, "label": str(Champion.item(rid).get("name", rid))})
	if effects.has("relation"):
		for who in (effects.relation as Dictionary).keys():
			var kid := world.merchant if who == "merchant" else (world.rival if who == "rival" else str(who))
			var amt := int(effects.relation[who])
			change_relation(kid, amt, source)
			changes.append({"kind": "relation", "amount": amt, "label": kname(kid)})
	if effects.has("reveal"):
		var rv := reveal(champ.pos, int(effects.reveal))
		changes.append({"kind": "reveal", "amount": rv.size(), "hexes": rv})
	if effects.has("reveal_secrets"):
		flags["surveyor_map"] = true
		var rv: Array = []
		for id in ["iron", "cove", "tower"]:
			if world.places.has(id):
				rv.append_array(reveal(world.places[id], 1))
		changes.append({"kind": "reveal", "amount": rv.size(), "hexes": rv})
		add_history("map", "A surveyor's map was found in the ruins", champ.pos)
	for fk in ["flag", "flag2"]:
		if effects.has(fk):
			flags[str(effects[fk])] = day
	return changes


## Resolve option `idx` of hex event `id`. Costs come out of the cargo.
func resolve_event(id: String, idx: int) -> Dictionary:
	var e: Dictionary = Data.events()[id]
	var opt: Dictionary = e.options[idx]
	var out := {"text": "", "changes": [], "combat": "", "check": {}}
	if opt.has("cost") and not can_afford(opt.cost, "cargo"):
		out.text = "You aren't carrying enough for that."
		return out
	if opt.has("needs_item"):
		var nid := str(opt.needs_item)
		if not champ.has_item(nid):
			out.text = "You don't have that with you."
			return out
		if opt.get("consume", false):
			champ.remove_item(nid)
			out.changes.append({"kind": "item_lost", "amount": -1, "label": str(Champion.item(nid).get("name", nid))})
	if e.get("once", false):
		flags["ev_" + id] = day
	if opt.has("combat"):
		out.combat = opt.combat
		return out
	if opt.has("check"):
		var c := check(opt.check.attr, int(opt.check.dc))
		out.check = c
		var branch: Dictionary = opt.success if c.success else opt.fail
		out.text = fmt(str(branch.get("text", "")))
		out.changes.append_array(apply(branch.get("effects", {}), e.title))
		var then := str(branch.get("then", ""))
		if then.begins_with("combat:"):
			out.combat = then.substr(7)
		return out
	out.text = fmt(str(opt.get("text", "")))
	out.changes.append_array(apply(opt.get("effects", {}), e.title))
	return out


# ==========================================================================
# Places
# ==========================================================================

func plant_outpost() -> Dictionary:
	var h := champ.pos
	var t: Dictionary = world.tile(h)
	var cost: Dictionary = Data.B("outpost.cost", {"wood": 10})
	if t.deposit == "" or t.owner == kingdom:
		return {"ok": false, "text": "Nothing to claim here."}
	var from := "cargo" if can_afford(cost, "cargo") else "kingdom"
	if not can_afford(cost, from):
		return {"ok": false, "text": "You need %d wood (cargo or treasury) to raise an outpost." % int(cost.get("wood", 0))}
	pay(cost, from)
	t.owner = kingdom
	t.band = 0
	moves = 0
	flags["outpost_" + str(t.deposit)] = day
	var changes: Array = [{"kind": "wood", "amount": -int(cost.get("wood", 0)), "to": from}]
	if str(place_ids.get(h, "")) == "greyrock":
		var amt: int = Data.B("outpost.rival_relation", -10)
		change_relation(world.rival, amt, "your banner on %s" % t.name)
		changes.append({"kind": "relation", "amount": amt, "label": kname(world.rival)})
		if envoy_day < 0 and not flags.has("envoy_done"):
			envoy_day = day + 1
	elif t.deposit == "iron":
		change_relation(world.merchant, -4, "your banner on %s" % t.name)
		changes.append({"kind": "relation", "amount": -4, "label": kname(world.merchant)})
	add_history("outpost", "%s claimed %s for %s" % [champ.name, t.name, kname(kingdom)], h)
	changes.append_array(apply({"xp": 10}, str(t.name)))
	return {"ok": true, "changes": changes}


func loot_cove() -> Array:
	flags["cove_looted"] = day
	add_history("place", "Smugglers' gold was found in the cove", champ.pos)
	return apply({"gold": 40, "xp": 10}, "Smugglers' cove")


func climb_tower() -> Array:
	flags["tower_climbed"] = day
	add_history("place", "%s climbed the old watchtower" % champ.name, champ.pos)
	return apply({"reveal": 6, "xp": 8}, "Old watchtower")


func camp(kind: String) -> Array:
	var changes: Array = []
	if kind == "heal":
		changes = apply({"hp": int(Data.B("champion.camp_heal", 3))}, "camp")
	else:
		changes = apply({"reveal": int(Data.B("champion.camp_scout_radius", 2))}, "camp")
	moves = 0
	return changes


# ==========================================================================
# Army
# ==========================================================================

func units() -> Array:
	return party.filter(func(e): return str(e.kind) == "unit")


func party_full() -> bool:
	return party.size() >= int(Data.B("army.slots", 5))


func unit_stats(u: Dictionary) -> Dictionary:
	var d: Dictionary = Data.get_file("units")[u.type]
	var vet: bool = bool(u.get("veteran", false))
	var v: Dictionary = d.get("veteran", {})
	var s := {"name": str(v.get("name", d.name)) if vet else str(d.name), "art": str(d.art),
		"max_hp": int(d.hp), "spd": int(d.spd), "def": int(d.def), "acc": int(d.acc), "dmg": 0,
		"skills": (d.skills as Array).duplicate(), "role": str(d.get("role", "")), "veteran": vet}
	if vet:
		s.max_hp += int(v.get("hp", 0))
		s.dmg += int(v.get("dmg", 0))
		if v.has("skill"):
			s.skills.append(v.skill)
	var ups: Dictionary = Data.get_file("ages").upgrades
	for id in upgrades.keys():
		var ef: Dictionary = ups[id].effect
		s.max_hp += int(ef.get("hp", 0))
		s.def += int(ef.get("def", 0))
		s.dmg += int(ef.get("dmg", 0))
		s.spd += int(ef.get("spd", 0))
		s.acc += int(ef.get("acc", 0))
	return s


func recruit_status(type: String) -> Dictionary:
	if not has_building("barracks"):
		return {"ok": false, "reason": "needs a Barracks"}
	if party_full():
		return {"ok": false, "reason": "army is full (%d slots)" % int(Data.B("army.slots", 5))}
	if not can_afford(Data.get_file("units")[type].cost):
		return {"ok": false, "reason": "not enough resources"}
	if pop - _workers_used() < 1:
		return {"ok": false, "reason": "no idle people to recruit"}
	return {"ok": true, "reason": ""}


func recruit(type: String) -> Dictionary:
	var st := recruit_status(type)
	if not st.ok:
		return st
	var d: Dictionary = Data.get_file("units")[type]
	pay(d.cost)
	pop -= 1
	var u := {"kind": "unit", "type": type, "uid": "u%d" % next_uid, "veteran": false, "hp": 0}
	next_uid += 1
	u.hp = unit_stats(u).max_hp
	# front-line soldiers step in ahead of the Champion; everyone else lines up behind
	var front: bool = 1 in d.skills[0].get("from", [])
	if front and not d.skills[0].get("from", []).has(4):
		var ci := 0
		for i in party.size():
			if str(party[i].kind) == "champion":
				ci = i
		party.insert(ci, u)
	else:
		party.append(u)
	return {"ok": true, "unit": u}


func dismiss(uid: String) -> void:
	for e in party:
		if str(e.get("uid", "")) == uid:
			party.erase(e)
			pop += 1
			return


## Swap a formation slot with its neighbour (dir -1 = forward, +1 = back).
func move_in_party(i: int, dir: int) -> void:
	var j := i + dir
	if i < 0 or j < 0 or i >= party.size() or j >= party.size():
		return
	var tmp = party[i]
	party[i] = party[j]
	party[j] = tmp


func veteran_cost() -> Dictionary:
	return {"gold": 25, "food": 10}


func can_make_veteran(uid: String) -> Dictionary:
	if not has_building("drillyard"):
		return {"ok": false, "reason": "needs a Drill yard (Age II)"}
	for e in party:
		if str(e.get("uid", "")) == uid:
			if e.get("veteran", false):
				return {"ok": false, "reason": "already a veteran"}
			if not can_afford(veteran_cost()):
				return {"ok": false, "reason": "not enough resources"}
			return {"ok": true, "reason": ""}
	return {"ok": false, "reason": "unknown unit"}


func make_veteran(uid: String) -> bool:
	if not can_make_veteran(uid).ok:
		return false
	pay(veteran_cost())
	for e in party:
		if str(e.get("uid", "")) == uid:
			e.veteran = true
			e.hp = unit_stats(e).max_hp
	return true


# ==========================================================================
# Patrols and camps (enemies on the map)
# ==========================================================================

func _spawn_patrols() -> void:
	patrols.clear()
	for i in int(Data.B("patrols.count", 4)):
		_spawn_patrol()


func _spawn_patrol() -> void:
	var cands: Array = []
	for h in world.tiles.keys():
		var t: Dictionary = world.tile(h)
		if not world.passable(h) or t.owner != "" or t.place != "" or int(t.band) < 1:
			continue
		var dmin := 99
		for k in world.capitals.keys():
			dmin = mini(dmin, Hex.distance(h, world.capitals[k]))
		if dmin < 5:
			continue
		cands.append(h)
	if cands.is_empty():
		return
	var h: Vector2i = cands[rng.randi_range(0, cands.size() - 1)]
	var groups := ["raiders", "wolves", "bandits", "raiders"]
	patrols.append({"id": next_uid, "group": groups[patrols.size() % groups.size()], "pos": h, "alive": true})
	next_uid += 1


func patrol_at(h: Vector2i) -> int:
	for i in patrols.size():
		if patrols[i].alive and patrols[i].pos == h:
			return i
	return -1


## Patrols wander, and chase the Champion if close. Returns index of a patrol that caught you, or -1.
func _move_patrols() -> int:
	var caught := -1
	var chase := int(Data.B("patrols.chase_range", 4))
	for i in patrols.size():
		var p: Dictionary = patrols[i]
		if not p.alive:
			continue
		for s in int(Data.B("patrols.move_per_day", 2)):
			var best: Vector2i = p.pos
			var opts: Array = []
			for nb in Hex.neighbors(p.pos):
				if world.passable(nb) and world.tile(nb).owner == "" and world.tile(nb).place == "" and patrol_at(nb) < 0:
					if has_building("watchtower") and Hex.distance(nb, world.capitals[kingdom]) <= 3:
						continue
					if has_building("walls") and Hex.distance(nb, world.capitals[kingdom]) <= 4:
						continue
					opts.append(nb)
			if opts.is_empty():
				break
			if Hex.distance(p.pos, champ.pos) <= chase and not at_capital():
				opts.sort_custom(func(a, b): return Hex.distance(a, champ.pos) < Hex.distance(b, champ.pos))
				best = opts[0]
				if Hex.distance(champ.pos, p.pos) == 1 and world.tile(champ.pos).owner == "" and world.tile(champ.pos).place == "":
					best = champ.pos
			else:
				best = opts[rng.randi_range(0, opts.size() - 1)]
			p.pos = best
			if p.pos == champ.pos:
				caught = i
				break
	return caught


## Called after a won / lost battle.
func battle_over(source: String, summary: Dictionary) -> Array:
	var changes: Array = []
	var res_str := str(summary.result)
	if source.begins_with("patrol:"):
		var i := int(source.substr(7))
		if i < patrols.size() and res_str == "win":
			patrols[i].alive = false
	elif source.begins_with("camp:"):
		var pid := source.substr(5)
		if res_str == "win":
			flags["cleared_" + pid] = day
			add_history("battle", "The %s at %s was broken" % [world.tile(world.places[pid]).name.to_lower(), world.tile(world.places[pid]).name], world.places[pid])
	if res_str == "win":
		var gid := str(summary.get("group", ""))
		kills[gid] = int(kills.get(gid, 0)) + 1
		changes = apply(summary.loot, "battle")
		var g: Dictionary = Data.enemies().groups.get(str(summary.get("group", "")), {})
		for d in g.get("drops", []):
			if rng.randf() < float(d[1]):
				changes.append_array(give_item(str(d[0])))
		changes.append_array(apply({"xp": int(summary.xp)}, "battle"))
		add_history("battle", "%s won a fight here" % champ.name, champ.pos)
	elif res_str == "fled":
		changes = apply({"end_day": true}, "flee")
	week_acc.battles.append({"source": source, "result": res_str, "lost": summary.get("lost", [])})
	for n in summary.get("lost", []):
		add_history("fallen", "%s fell in battle" % n, champ.pos)
	return changes


# ==========================================================================
# City
# ==========================================================================

func has_building(type: String) -> bool:
	for s in city.keys():
		if city[s].type == type:
			return true
	return false


func housing() -> int:
	var total := 0
	for s in city.keys():
		var hb := int(Data.buildings()[city[s].type].get("housing", 0))
		if city[s].type == "house":
			hb *= int(city[s].get("level", 1))
		hb += int(branch_def(s).get("housing", 0))
		total += hb
	return total


func builds_per_day() -> int:
	var arr: Array = Data.B("economy.builds_per_day", [1, 2, 2])
	return int(arr[clampi(age - 1, 0, arr.size() - 1)])


func build_cost(type: String) -> Dictionary:
	var base: Dictionary = Data.buildings()[type].cost
	var out := {}
	var disc: float = Data.B("economy.capital_build_discount", 0.2) if at_capital() else 0.0
	for k in base.keys():
		out[k] = int(round(int(base[k]) * (1.0 - disc)))
	return out


func build_status(type: String) -> Dictionary:
	var b: Dictionary = Data.buildings()[type]
	if int(b.get("age", 1)) > age:
		return {"ok": false, "reason": "needs Age %s" % ["I", "II", "III"][int(b.age) - 1]}
	if b.get("unique", false) and has_building(type):
		return {"ok": false, "reason": "already built"}
	if str(b.get("needs", "")) == "stone_outpost" and not flags.has("outpost_stone"):
		return {"ok": false, "reason": "needs a stone outpost"}
	if str(b.get("needs", "")) == "iron_outpost" and not flags.has("outpost_iron"):
		return {"ok": false, "reason": "needs an iron outpost (Iron cliffs)"}
	if builds_today >= builds_per_day():
		return {"ok": false, "reason": "no builds left today"}
	if not can_afford(build_cost(type)):
		return {"ok": false, "reason": "not enough resources"}
	return {"ok": true, "reason": ""}


func can_build(type: String, slot: Vector2i) -> Dictionary:
	var b: Dictionary = Data.buildings()[type]
	if not b.get("buildable", false):
		return {"ok": false, "reason": "can't be built"}
	if not city_terrain.has(slot) or city.has(slot):
		return {"ok": false, "reason": "plot taken"}
	if str(b.get("on", "")) != "" and city_terrain[slot] != str(b.on):
		return {"ok": false, "reason": "must stand on " + str(b.on)}
	if city_terrain[slot] in ["water", "forest"] and str(b.get("on", "")) != city_terrain[slot]:
		return {"ok": false, "reason": "can't build on " + str(city_terrain[slot])}
	for need in [["forest_adjacent", "forest"], ["water_adjacent", "water"]]:
		if str(b.get("needs", "")) == need[0]:
			var ok := false
			for nb in Hex.neighbors(slot):
				if city_terrain.get(nb, "") == need[1]:
					ok = true
			if not ok:
				return {"ok": false, "reason": "needs %s beside it" % need[1]}
	return build_status(type)


func build(type: String, slot: Vector2i) -> Dictionary:
	var c := can_build(type, slot)
	if not c.ok:
		return c
	var cost := build_cost(type)
	pay(cost)
	city[slot] = {"type": type, "day": day, "level": 1}
	var modes: Array = Data.buildings()[type].get("modes", [])
	if not modes.is_empty():
		city[slot].mode = str(modes[0].id)
	builds_today += 1
	if type in ["market", "quarry", "barracks", "blacksmith", "drillyard"]:
		add_history("build", "A %s was built in the capital" % str(Data.buildings()[type].name).to_lower(), world.capitals[kingdom])
	return {"ok": true, "cost": cost}


func _workers_used() -> int:
	var used := 0
	var st := staffing()
	for s in st.keys():
		if st[s]:
			used += int(Data.buildings()[city[s].type].get("workers", 0))
	return used


func staffing() -> Dictionary:
	var order: Array = city.keys()
	order.sort_custom(func(a, b): return int(city[a].day) < int(city[b].day))
	var free := pop
	var out := {}
	for s in order:
		var w := int(Data.buildings()[city[s].type].get("workers", 0))
		out[s] = w <= free
		if w <= free:
			free -= w
	return out


func staffing_ok(type: String) -> bool:
	var st := staffing()
	for sl in city.keys():
		if city[sl].type == type and st.get(sl, false):
			return true
	return false


func idle_workers() -> int:
	return pop - _workers_used()


func level_of(slot: Vector2i) -> int:
	return int(city[slot].get("level", 1))


func _mult(lvl: int) -> float:
	var m: Array = Data.B("city.level_mult", [1.0, 1.5, 2.0])
	return float(m[clampi(lvl - 1, 0, m.size() - 1)])


func mode_def(slot: Vector2i) -> Dictionary:
	var modes: Array = Data.buildings()[city[slot].type].get("modes", [])
	for m in modes:
		if str(m.id) == str(city[slot].get("mode", "")):
			return m
	return modes[0] if not modes.is_empty() else {}


## Net daily output per building (inputs show as negatives). Buildings whose
## inputs can't be paid from today's stock stand idle.
func production_by_slot() -> Dictionary:
	var bonus: Dictionary = kdef(kingdom).get("bonus", {})
	var st := staffing()
	var out := {}
	var stock: Dictionary = res.duplicate()
	var order: Array = city.keys()
	order.sort_custom(func(a, b): return int(city[a].day) < int(city[b].day))
	var granary := has_building("granary")
	for s in order:
		var type: String = city[s].type
		if not st.get(s, false):
			continue
		var def: Dictionary = Data.buildings()[type]
		var p: Dictionary = (def.get("prod", {}) as Dictionary).duplicate()
		match type:
			"farm":
				p.food = int(p.get("food", 0)) + int(bonus.get("farm_food", 0)) + (2 if weather == "harvest" else 0) + (1 if granary else 0)
			"quarry":
				p.stone = int(p.get("stone", 0)) + int(bonus.get("quarry_stone", 0))
			"lumber":
				p.wood = int(p.get("wood", 0)) + int(bonus.get("lumber_wood", 0))
		var adj: Dictionary = def.get("adj", {})
		for nb in Hex.neighbors(s):
			if city.has(nb) and adj.has(city[nb].type):
				for r in adj[city[nb].type].keys():
					p[r] = int(p.get(r, 0)) + int(adj[city[nb].type][r])
		var mult := _mult(level_of(s))
		var md := mode_def(s) if def.has("modes") else {}
		if not md.is_empty():
			var ok := true
			for r in md.get("in", {}).keys():
				if int(stock.get(r, 0)) < int(ceil(int(md["in"][r]) * mult)):
					ok = false
			if not ok:
				continue
			for r in md.get("in", {}).keys():
				var need := int(ceil(int(md["in"][r]) * mult))
				stock[r] -= need
				p[r] = int(p.get(r, 0)) - need
			for r in md.get("out", {}).keys():
				var amt := int(md["out"][r])
				if type == "market" and r == "gold":
					amt += int(bonus.get("market_gold", 0)) + (2 if weather == "fair" else 0)
				p[r] = int(p.get(r, 0)) + amt
		for r in p.keys():
			if int(p[r]) > 0:
				p[r] = int(ceil(int(p[r]) * mult))
		var bp: Dictionary = branch_def(s).get("prod", {})
		for r in bp.keys():
			p[r] = int(p.get(r, 0)) + int(bp[r])
		if not p.is_empty():
			out[s] = p
	return out


func upgrade_building_status(slot: Vector2i) -> Dictionary:
	if not city.has(slot):
		return {"ok": false, "reason": "nothing here"}
	var def: Dictionary = Data.buildings()[city[slot].type]
	var lvl := level_of(slot)
	if lvl >= int(def.get("max_level", 1)):
		return {"ok": false, "reason": "fully upgraded" if def.has("max_level") else "can't be upgraded"}
	if lvl + 1 >= 3 and age < 2:
		return {"ok": false, "reason": "level 3 needs Age II"}
	if not can_afford(upgrade_cost(slot)):
		return {"ok": false, "reason": "not enough resources"}
	return {"ok": true, "reason": ""}


func upgrade_cost(slot: Vector2i) -> Dictionary:
	var def: Dictionary = Data.buildings()[city[slot].type]
	var nxt := level_of(slot) + 1
	var out := {}
	for k in def.cost.keys():
		out[k] = int(def.cost[k]) * nxt
	out.stone = int(out.get("stone", 0)) + 5 * nxt
	return out


## The two specialisations offered when this building reaches level 3 ([] if none).
func branches_of(slot: Vector2i) -> Array:
	return Data.buildings()[city[slot].type].get("branches", [])


func needs_branch(slot: Vector2i) -> bool:
	return level_of(slot) + 1 >= 3 and not branches_of(slot).is_empty() and str(city[slot].get("branch", "")) == ""


func branch_def(slot: Vector2i) -> Dictionary:
	if not city.has(slot):
		return {}
	var id := str(city[slot].get("branch", ""))
	if id == "":
		return {}
	for br in branches_of(slot):
		if str(br.id) == id:
			return br
	return {}


## branch: the specialisation id, required when the upgrade reaches level 3 on a building that has them.
func upgrade_building(slot: Vector2i, branch: String = "") -> bool:
	if not upgrade_building_status(slot).ok:
		return false
	if needs_branch(slot):
		var valid := false
		for br in branches_of(slot):
			valid = valid or str(br.id) == branch
		if not valid:
			return false
		city[slot].branch = branch
	pay(upgrade_cost(slot))
	city[slot].level = level_of(slot) + 1
	add_history("build", "The %s was improved to level %d" % [str(Data.buildings()[city[slot].type].name).to_lower(), level_of(slot)], world.capitals[kingdom])
	return true


func set_mode(slot: Vector2i, mode: String) -> void:
	if city.has(slot):
		city[slot].mode = mode


func expand_status() -> Dictionary:
	var steps: Array = Data.B("city.expand", [])
	for st_ in steps:
		if int(st_.radius) > city_radius:
			if int(st_.get("age", 1)) > age:
				return {"ok": false, "reason": "needs Age %s" % ["I", "II", "III"][int(st_.age) - 1], "cost": st_.cost, "radius": int(st_.radius)}
			if not can_afford(st_.cost):
				return {"ok": false, "reason": "not enough resources", "cost": st_.cost, "radius": int(st_.radius)}
			return {"ok": true, "reason": "", "cost": st_.cost, "radius": int(st_.radius)}
	return {"ok": false, "reason": "the capital can't grow further yet", "cost": {}, "radius": city_radius}


## Claims the next ring of land around the capital (new building plots).
func expand_city() -> Array:
	var es := expand_status()
	if not es.ok:
		return []
	pay(es.cost)
	city_radius = int(es.radius)
	var added: Array = []
	var hills_made := 0
	for h in Hex.ring(Vector2i.ZERO, city_radius):
		if city_terrain.has(h):
			continue
		var v := Hex.hash01(h, 77)
		var t := "plains"
		if v < 0.12:
			t = "water"
		elif v < 0.32:
			t = "forest"
		elif v < 0.47:
			t = "hills"
		if t == "hills":
			hills_made += 1
		city_terrain[h] = t
		added.append(h)
	if hills_made < 2:
		for h in added:
			if city_terrain[h] == "plains" and hills_made < 2:
				city_terrain[h] = "hills"
				hills_made += 1
	add_history("build", "%s's capital grew to claim new land" % kname(kingdom), world.capitals[kingdom])
	return added


func upkeep() -> int:
	return units().size() * int(Data.B("army.upkeep_food_per_unit", 1))


func eaten_per_day() -> int:
	return int(ceil(pop * float(Data.B("economy.food_per_pop", 0.5))))


func daily_totals() -> Dictionary:
	var tot := _zero()
	var pbs := production_by_slot()
	for s in pbs.keys():
		for r in pbs[s].keys():
			tot[r] += int(pbs[s][r])
	if flags.has("harbor_trade"):
		tot.gold += 2
	tot.food -= eaten_per_day() + upkeep()
	return tot


func buy(item: String) -> Dictionary:
	var it := Champion.item(item)
	if it.is_empty() or not it.has("shop"):
		return {"ok": false, "reason": "not sold here"}
	if not has_building("market"):
		return {"ok": false, "reason": "needs a market"}
	if int(it.get("needs_age", 1)) > age:
		return {"ok": false, "reason": "needs Age %s" % ["I", "II", "III"][int(it.needs_age) - 1]}
	var cost := {"gold": shop_price(item)}
	if not can_afford(cost):
		return {"ok": false, "reason": "not enough gold in the treasury"}
	if champ.bag_full_for(item):
		return {"ok": false, "reason": "the bag is full"}
	pay(cost)
	champ.add_item(item)
	return {"ok": true}


func shop_price(item: String) -> int:
	var disc := 0.0
	for s in city.keys():
		disc = maxf(disc, float(branch_def(s).get("discount", 0.0)))
	return int(round(int(Champion.item(item).get("shop", 0)) * (1.0 - disc)))


## Things the Market sells, in data order.
func shop_list() -> Array:
	var out: Array = []
	var items: Dictionary = Data.get_file("items").items
	for id in items.keys():
		if items[id].has("shop"):
			out.append(id)
	return out


func sell_item(id: String) -> Dictionary:
	if not at_capital() or not has_building("market"):
		return {"ok": false, "reason": "sell at your Market, in the capital"}
	if not champ.remove_item(id):
		return {"ok": false, "reason": "not in the bag"}
	var v := int(Champion.item(id).get("value", 1))
	res.gold += v
	return {"ok": true, "gold": v}


## Puts an item in the bag. If it doesn't fit, it is sold on the spot for cargo gold.
func give_item(id: String) -> Array:
	var it := Champion.item(id)
	if it.is_empty():
		return []
	if champ.add_item(id) == 1:
		return [{"kind": "item", "amount": 1, "label": str(it.name), "rarity": str(it.get("rarity", "common"))}]
	var v := int(it.get("value", 1))
	champ.cargo.gold = int(champ.cargo.gold) + v
	return [{"kind": "item", "amount": 1, "label": "%s (bag full: sold, +%d gold)" % [it.name, v]}]


## Use an item from the bag on the map. Returns the changes, or [] if it can't be used here.
func use_item(id: String) -> Array:
	var it := Champion.item(id)
	var u: Dictionary = it.get("use", {})
	if u.is_empty() or champ.count(id) <= 0 or u.get("flee", false):
		return []
	champ.remove_item(id)
	var eff := {}
	for k in ["hp", "moves", "xp", "reveal_secrets"]:
		if u.has(k):
			eff[k] = u[k]
	var ch := apply(eff, str(it.name))
	ch.push_front({"kind": "item_lost", "amount": -1, "label": str(it.name)})
	return ch


func craft_list() -> Array:
	var out: Array = []
	var items: Dictionary = Data.get_file("items").items
	for id in items.keys():
		if items[id].has("craft"):
			out.append(id)
	return out


func craft_status(id: String) -> Dictionary:
	var c: Dictionary = Champion.item(id).get("craft", {})
	if c.is_empty():
		return {"ok": false, "reason": "can't be made"}
	if not has_building(str(c.at)):
		return {"ok": false, "reason": "needs a %s" % str(Data.buildings()[c.at].name)}
	if int(Champion.item(id).get("needs_age", 1)) > age:
		return {"ok": false, "reason": "needs Age %s" % ["I", "II", "III"][int(Champion.item(id).needs_age) - 1]}
	if not can_afford(c.get("cost", {})):
		return {"ok": false, "reason": "not enough resources"}
	for need in (c.get("items", {}) as Dictionary).keys():
		if have_item(need) < int(c.items[need]):
			return {"ok": false, "reason": "needs %s" % str(Champion.item(need).get("name", need))}
	if champ.bag_full_for(id):
		return {"ok": false, "reason": "the bag is full"}
	return {"ok": true, "reason": ""}


func craft(id: String) -> bool:
	if not craft_status(id).ok:
		return false
	var c: Dictionary = Champion.item(id).craft
	pay(c.get("cost", {}))
	for need in (c.get("items", {}) as Dictionary).keys():
		take_item(need, int(c.items[need]))
	champ.add_item(id)
	add_history("craft", "%s was made in the capital" % str(Champion.item(id).name), world.capitals[kingdom])
	return true


# ==========================================================================
# Storehouse (items buildings make each week)
# ==========================================================================

func stash_count(id: String) -> int:
	for e in stash:
		if str(e.id) == id:
			return int(e.n)
	return 0


func stash_add(id: String, n: int = 1) -> void:
	for e in stash:
		if str(e.id) == id:
			e.n = int(e.n) + n
			return
	stash.append({"id": id, "n": n})


func stash_remove(id: String, n: int = 1) -> int:
	for e in stash:
		if str(e.id) == id:
			var k := mini(n, int(e.n))
			e.n = int(e.n) - k
			if int(e.n) <= 0:
				stash.erase(e)
			return k
	return 0


## Items in the bag plus, when the Champion is home, the storehouse.
func have_item(id: String) -> int:
	return champ.count(id) + (stash_count(id) if at_capital() else 0)


## Uses items for crafting: the storehouse first, then the bag.
func take_item(id: String, n: int) -> void:
	var left := n
	if at_capital():
		left -= stash_remove(id, left)
	if left > 0:
		champ.remove_item(id, left)


## Moves one storehouse item into the bag (Champion must be home).
func take_from_stash(id: String) -> Dictionary:
	if not at_capital():
		return {"ok": false, "reason": "the Champion must be home"}
	if stash_count(id) <= 0:
		return {"ok": false, "reason": "none left"}
	if champ.bag_full_for(id):
		return {"ok": false, "reason": "the bag is full"}
	stash_remove(id)
	champ.add_item(id)
	return {"ok": true, "reason": ""}


## Takes everything that fits from the storehouse. Returns the item names moved.
func collect_stash() -> Array:
	var moved: Array = []
	if not at_capital():
		return moved
	for e in stash.duplicate(true):
		for i in int(e.n):
			if take_from_stash(str(e.id)).ok:
				moved.append(str(Champion.item(str(e.id)).get("name", e.id)))
	return moved


## Items each staffed building adds to the storehouse at the end of the week.
func weekly_items() -> Dictionary:
	var out := {}
	var stf := staffing()
	for s in city.keys():
		if not stf.get(s, false):
			continue
		var w: Dictionary = (Data.buildings()[city[s].type].get("weekly", {}) as Dictionary).duplicate()
		var bw: Dictionary = branch_def(s).get("weekly", {})
		for id in bw.keys():
			w[id] = int(w.get(id, 0)) + int(bw[id])
		for id in w.keys():
			out[id] = int(out.get(id, 0)) + int(w[id])
	return out


# ==========================================================================
# Land clearing
# ==========================================================================

func clear_status(slot: Vector2i) -> Dictionary:
	var t := str(city_terrain.get(slot, ""))
	var defs: Dictionary = Data.B("city.clear", {})
	if not defs.has(t):
		return {"ok": false, "reason": "nothing to clear", "cost": {}, "gain": {}}
	var d: Dictionary = defs[t]
	if city.has(slot):
		return {"ok": false, "reason": "a building stands here", "cost": d.cost, "gain": d.get("gain", {})}
	if int(d.get("age", 1)) > age:
		return {"ok": false, "reason": "needs Age %s" % ["I", "II", "III"][int(d.age) - 1], "cost": d.cost, "gain": d.get("gain", {})}
	if not can_afford(d.cost):
		return {"ok": false, "reason": "not enough resources", "cost": d.cost, "gain": d.get("gain", {})}
	return {"ok": true, "reason": "", "cost": d.cost, "gain": d.get("gain", {}), "name": str(d.name)}


## Turns a forest, hill or pond plot into open plains.
func clear_land(slot: Vector2i) -> bool:
	var cs := clear_status(slot)
	if not cs.ok:
		return false
	pay(cs.cost)
	for r in (cs.gain as Dictionary).keys():
		res[r] = int(res.get(r, 0)) + int(cs.gain[r])
	var was := str(city_terrain[slot])
	city_terrain[slot] = "plains"
	add_history("build", "A %s by the capital was cleared for building" % {"forest": "wood", "hills": "hill", "water": "pond"}.get(was, was), world.capitals[kingdom])
	return true


# ==========================================================================
# Ages and upgrades
# ==========================================================================

func age_def(n: int) -> Dictionary:
	var ages: Array = Data.get_file("ages").ages
	return ages[clampi(n - 1, 0, ages.size() - 1)]


func age_name() -> String:
	return str(age_def(age).name)


func age_status() -> Dictionary:
	var nxt := age_def(age + 1)
	if age + 1 > (Data.get_file("ages").ages as Array).size() or nxt.get("locked", false):
		return {"ok": false, "checks": [], "reason": "locked"}
	var req: Dictionary = nxt.get("requires", {})
	var checks: Array = []
	checks.append({"text": "%d buildings (you have %d)" % [int(req.get("buildings", 0)), city.size()], "ok": city.size() >= int(req.get("buildings", 0))})
	checks.append({"text": "%d people (you have %d)" % [int(req.get("pop", 0)), pop], "ok": pop >= int(req.get("pop", 0))})
	for b in req.get("has", []):
		checks.append({"text": "a %s" % str(Data.buildings()[b].name), "ok": has_building(str(b))})
	var cost: Dictionary = nxt.get("cost", {})
	var parts: Array[String] = []
	for k in cost.keys():
		parts.append("%d %s" % [int(cost[k]), k])
	checks.append({"text": "pay " + ", ".join(parts), "ok": can_afford(cost)})
	var all_ok := true
	for c in checks:
		all_ok = all_ok and c.ok
	return {"ok": all_ok, "checks": checks, "reason": ""}


func advance_age() -> bool:
	if not age_status().ok:
		return false
	pay(age_def(age + 1).get("cost", {}))
	age += 1
	add_history("age", "%s entered the age of the %s" % [kname(kingdom), str(age_def(age).name)], world.capitals[kingdom])
	return true


func upgrade_status(id: String) -> Dictionary:
	var u: Dictionary = Data.get_file("ages").upgrades[id]
	if upgrades.has(id):
		return {"ok": false, "reason": "done"}
	if int(u.get("age", 1)) > age:
		return {"ok": false, "reason": "needs Age %s" % ["I", "II", "III"][int(u.age) - 1]}
	if not has_building(str(u.at)):
		return {"ok": false, "reason": "needs a %s" % str(Data.buildings()[u.at].name)}
	if not can_afford(u.cost):
		return {"ok": false, "reason": "not enough resources"}
	return {"ok": true, "reason": ""}


func buy_upgrade(id: String) -> bool:
	if not upgrade_status(id).ok:
		return false
	var u: Dictionary = Data.get_file("ages").upgrades[id]
	pay(u.cost)
	upgrades[id] = day
	for e in units():
		var hpb := int(u.effect.get("hp", 0))
		e.hp = int(e.hp) + hpb
	add_history("upgrade", "%s: %s" % [str(u.name), str(u.does)], world.capitals[kingdom])
	return true


# ==========================================================================
# Day / week flow
# ==========================================================================

func end_day() -> Dictionary:
	var rep := {"day": day, "prod": {}, "slots": production_by_slot(), "eaten": 0, "upkeep": 0, "starving": false,
		"week_end": false, "envoy": false, "tobbin_left": false, "heal": 0, "trade": 0, "deserted": "", "ambush": -1}
	var tot := _zero()
	for s in rep.slots.keys():
		for r in rep.slots[s].keys():
			tot[r] += int(rep.slots[s][r])
	if flags.has("harbor_trade"):
		tot.gold += 2
		rep.trade = 2
	for r in RES:
		res[r] += tot[r]
		week_acc.prod[r] += tot[r]
	rep.prod = tot
	var eaten := eaten_per_day()
	var up := upkeep()
	res.food -= eaten + up
	week_acc.eaten += eaten
	week_acc.upkeep += up
	rep.eaten = eaten
	rep.upkeep = up
	if res.food < 0:
		res.food = 0
		rep.starving = true
		flags["starving"] = day
		var us := units()
		if not us.is_empty():
			var gone: Dictionary = us[-1]
			party.erase(gone)
			pop += 1
			rep.deserted = unit_stats(gone).name
			add_history("desert", "A hungry %s went home" % rep.deserted.to_lower(), world.capitals[kingdom])
	if alive:
		var home := at_capital()
		rep.heal = champ.heal(int(Data.B("champion.home_heal_per_day", 4)) if home else int(Data.B("champion.road_heal_per_day", 1)))
		var uh := int(Data.B("army.home_heal_per_day", 3)) if home else int(Data.B("army.road_heal_per_day", 1))
		for u in units():
			u.hp = mini(unit_stats(u).max_hp, int(u.hp) + uh)
	if alive and has_building("library") and staffing_ok("library"):
		champ.add_xp(1)
	if day == 4 and not flags.has("tobbin_done"):
		rep.tobbin_left = true
		flags["tobbin_done"] = day
	if alive:
		rep.ambush = _move_patrols()
	if day % 7 == 0:
		rep.week_end = true
		rep.week_report = _end_week()
	day += 1
	if envoy_day > 0 and day >= envoy_day and not flags.has("envoy_done"):
		rep.envoy = true
		flags["envoy_waiting"] = day
	builds_today = 0
	rolled = false
	roll = 0
	moves = 0
	events_today = 0
	return rep


func _end_week() -> Dictionary:
	var r := {"week": week(), "prod": week_acc.prod.duplicate(), "spent": week_acc.spent.duplicate(),
		"delivered": week_acc.delivered.duplicate(), "eaten": week_acc.eaten, "upkeep": week_acc.upkeep,
		"gifts": week_acc.gifts.duplicate(), "rel": week_acc.rel.duplicate(), "battles": week_acc.battles.duplicate(),
		"pop_before": week_acc.pop_start, "growth": 0, "growth_reason": "", "trade": {}, "weather": "", "history": []}
	var net_food: int = int(week_acc.prod.food) + int(week_acc.delivered.food) - int(week_acc.eaten) - int(week_acc.upkeep)
	var room := housing() - pop
	if flags.has("starving") and int(flags.starving) > day - 7:
		pop = maxi(1, pop - int(Data.B("economy.starve_pop_loss", 1)))
		r.growth = -1
		r.growth_reason = "the granary ran dry"
		flags.erase("starving")
	elif net_food >= int(Data.B("economy.growth_surplus_needed", 15)) and room > 0:
		var g := mini(int(Data.B("economy.growth_pop", 2)), room)
		pop += g
		r.growth = g
		r.growth_reason = "a food surplus brought new families"
	elif room <= 0:
		r.growth_reason = "no room: build houses"
	else:
		r.growth_reason = "not enough spare food to grow"
	if has_building("tavern") and staffing_ok("tavern") and housing() > pop:
		pop += 1
		r.growth = int(r.growth) + 1
		r.growth_reason = str(r.growth_reason) + " · a traveller settled at the tavern"
	if has_building("temple") and staffing_ok("temple"):
		for kid in relations.keys():
			change_relation(kid, 1, "temple offerings")
	var stf := staffing()
	for s in city.keys():
		if stf.get(s, false) and int(branch_def(s).get("relations", 0)) > 0:
			for kid in relations.keys():
				change_relation(kid, int(branch_def(s).relations), "songs from the bards' hall")
	var made := weekly_items()
	r.stash = []
	for id in made.keys():
		stash_add(id, int(made[id]))
		r.stash.append("%d× %s" % [int(made[id]), str(Champion.item(id).get("name", id))])
	r.pop_after = pop
	if flags.has("stone_trade"):
		if res.stone >= 5:
			res.stone -= 5
			res.gold += 15
			r.trade = {"stone": -5, "gold": 15}
		else:
			r.trade = {"missing": true}
	weather = next_weather
	var pool: Array = ["clear", "rain", "fair", "harvest", "clear"]
	next_weather = pool[rng.randi_range(0, pool.size() - 1)]
	r.weather = weather
	for hist in history:
		if int(hist.day) > day - 7:
			r.history.append(hist)
	r.relations = relations.duplicate()
	# keep the wilds dangerous
	var living := patrols.filter(func(p): return p.alive).size()
	for i in int(Data.B("patrols.count", 4)) - living:
		_spawn_patrol()
	last_week_report = r
	_reset_week()
	return r


# ==========================================================================
# Death and heirs
# ==========================================================================

func champion_died() -> void:
	alive = false
	for r in RES:
		champ.cargo[r] = 0
	add_history("death", "%s fell here" % champ.name, champ.pos)


func crown_heir(heir: Champion) -> void:
	var gen := champ.generation + 1
	champ = heir
	champ.generation = gen
	champ.hp = champ.max_hp()
	champ.pos = world.capitals[kingdom]
	alive = true
	day += int(Data.B("heir.days_lost", 2))
	rolled = false
	moves = 0
	add_history("heir", "%s took up the banner" % champ.name, champ.pos)


# ==========================================================================
# Quests (data/quests.json)
# ==========================================================================

func quest_def(id: String) -> Dictionary:
	return Data.get_file("quests").get("quests", {}).get(id, {})


func start_quest(id: String) -> bool:
	if id == "" or quests.has(id) or quest_def(id).is_empty():
		return false
	var q := quest_def(id)
	quests[id] = {"state": "active", "day": day, "progress": []}
	for o in q.objectives:
		quests[id].progress.append(0)
	add_history("quest", "New quest: %s" % str(q.title), champ.pos)
	return true


func active_quests(kind: String = "") -> Array:
	var out: Array = []
	for id in quests.keys():
		if quests[id].state == "active" and (kind == "" or str(quest_def(id).get("kind", "")) == kind):
			out.append(id)
	return out


func _built_count(type: String) -> int:
	var n := 0
	for s in city.keys():
		if city[s].type == type:
			n += 1
	return n


## Current value and goal of one objective.
func objective_progress(o: Dictionary) -> Array:
	var goal := int(o.get("count", 1))
	var v := 0
	match str(o.type):
		"build":
			v = mini(_built_count(str(o.target)), goal)
		"place":
			v = 1 if (flags.has("visited_" + str(o.target)) or (str(o.target) == "ruins" and flags.has("surveyor_map"))) else 0
		"res":
			v = int(res.get(str(o.target), 0)) + (int(champ.cargo.get(str(o.target), 0)) if not o.get("deliver", false) else 0)
		"item":
			v = champ.count(str(o.target)) + stash_count(str(o.target))
		"dungeon":
			v = 1 if flags.has("dungeon_done_" + str(o.target)) else 0
		"clear":
			v = 1 if (flags.has("cleared_" + str(o.target)) or flags.has("cleared_" + str(o.get("alt", "")))) else 0
		"age":
			v = age
		"kill":
			v = int(kills.get(str(o.target), 0))
		"discover":
			v = discovered_places.size() - 1
		"pop":
			v = pop
		"army":
			v = party.size()
		"level":
			v = champ.level
	return [mini(v, goal), goal]


func quest_ready(id: String) -> bool:
	var q := quest_def(id)
	for o in q.get("objectives", []):
		var pr := objective_progress(o)
		if pr[0] < pr[1]:
			return false
	return true


## Finishes every quest whose objectives are met. Returns [{id, title, changes}] for banners.
## Rewards go straight to the kingdom (the quest giver sends them home).
func check_quests() -> Array:
	var out: Array = []
	for id in active_quests():
		var q := quest_def(id)
		if not quest_ready(id):
			continue
		for o in q.objectives:
			if str(o.type) == "res" and o.get("deliver", false):
				res[str(o.target)] = maxi(0, int(res[str(o.target)]) - int(o.count))
		quests[id].state = "done"
		quests[id].done_day = day
		var rw: Dictionary = q.get("reward", {}).duplicate()
		var changes: Array = []
		if rw.has("relation_all"):
			for k in relations.keys():
				change_relation(k, int(rw.relation_all), str(q.title))
			changes.append({"kind": "relation", "amount": int(rw.relation_all), "label": "all kingdoms"})
			rw.erase("relation_all")
		changes.append_array(apply(rw, str(q.title), "kingdom"))
		add_history("quest", "Quest done: %s" % str(q.title), champ.pos)
		out.append({"id": id, "title": str(q.title), "changes": changes, "kind": str(q.kind)})
		start_quest(str(q.get("next", "")))
	return out


## At the end of a week a new side quest is offered (at most 3 open at once).
func offer_side_quest() -> String:
	if active_quests("side").size() >= 3:
		return ""
	var pool: Array = []
	for id in Data.get_file("quests").get("pool", []):
		if not quests.has(str(id)):
			pool.append(str(id))
	if pool.is_empty():
		return ""
	var id: String = pool[rng.randi_range(0, pool.size() - 1)]
	start_quest(id)
	return id


# ==========================================================================
# Dungeons (data/dungeons.json): a string of rooms, a guardian at the end
# ==========================================================================

func dungeon_def(id: String) -> Dictionary:
	return Data.get_file("dungeons").get(id, {})


func start_dungeon(id: String) -> Dictionary:
	var d := dungeon_def(id)
	var kinds := ["fight", "fight", "chest", "trap", "shrine", "rest", "fight", "chest"]
	var rooms: Array = []
	var n := int(d.get("rooms", 5))
	for i in n:
		var k: String = kinds[rng.randi_range(0, kinds.size() - 1)]
		if i == 0:
			k = "fight"
		if i > 0 and rooms[i - 1] == k and k != "fight":
			k = "fight"
		rooms.append(k)
	rooms.append("boss")
	dungeon_run = {"id": id, "room": 0, "rooms": rooms, "done": [], "loot": {}}
	flags["visited_" + id] = day
	return dungeon_run


func dungeon_room() -> String:
	if dungeon_run.is_empty():
		return ""
	return str(dungeon_run.rooms[int(dungeon_run.room)])


## Fight group for the current room.
func dungeon_group() -> String:
	var d := dungeon_def(str(dungeon_run.id))
	if dungeon_room() == "boss":
		return str(d.boss)
	var m: Array = d.monsters
	return str(m[rng.randi_range(0, m.size() - 1)])


## Resolves a non-fight room. `choice` is "open"/"leave" for chests, "disarm"/"rush" for traps,
## "pray"/"leave" for shrines, "rest" for camps. Returns {text, changes, ok}.
func dungeon_resolve(choice: String) -> Dictionary:
	var d := dungeon_def(str(dungeon_run.id))
	var dc := int(d.get("dc", 11))
	var out := {"text": "", "changes": [], "ok": true}
	match dungeon_room():
		"chest":
			if choice == "open":
				var ck := check("DEX", dc)
				out.roll = ck
				if ck.success:
					var g := rng.randi_range(8, 20) + dc
					out.changes = apply({"gold": g}, str(d.name))
					var pool := ["salve", "potion", "torch", "gem", "smoke_bomb", "vigor_tonic", "lucky_coin", "pearl"]
					if rng.randf() < 0.55:
						out.changes.append_array(give_item(pool[rng.randi_range(0, pool.size() - 1)]))
					out.text = "The lock gives. Coins, and something wrapped in oilcloth."
				else:
					out.changes = apply({"hp": -rng.randi_range(2, 4)}, str(d.name))
					out.ok = false
					out.text = "A needle trap! The chest stays shut and your hand burns."
		"trap":
			if choice == "disarm":
				var ck := check("INT", dc)
				out.roll = ck
				if ck.success:
					out.changes = apply({"xp": 6}, str(d.name))
					out.text = "You find the tripwire and step over it. A good lesson."
				else:
					out.changes = apply({"hp": -rng.randi_range(3, 5)}, str(d.name))
					out.ok = false
					out.text = "Click. Darts hiss from the walls."
			else:
				var ck := check("DEX", dc - 2)
				out.roll = ck
				if ck.success:
					out.text = "You sprint through as stones crash down behind you."
				else:
					out.changes = apply({"hp": -rng.randi_range(2, 6)}, str(d.name))
					out.ok = false
					out.text = "Not fast enough. The ceiling clips you on the way through."
		"shrine":
			if choice == "pray":
				var ck := check("WIS", dc - 1)
				out.roll = ck
				if ck.success:
					out.changes = apply({"hp": 6, "xp": 8}, str(d.name))
					out.text = "Warmth fills the room. Your wounds close a little."
				else:
					out.changes = apply({"hp": -2}, str(d.name))
					out.ok = false
					out.text = "The old god does not like strangers. A cold wind bites."
			else:
				out.text = "You leave the shrine alone."
		"rest":
			out.changes = apply({"hp": 4}, str(d.name))
			for u in units():
				u.hp = mini(unit_stats(u).max_hp, int(u.hp) + 3)
			out.text = "A quiet corner. The band shares bread and binds wounds."
	if champ.hp <= 0:
		champ.hp = 1          # a dungeon room never kills outright; the fights do
		alive = true
	return out


## Move to the next room (after a won fight or a resolved room). Returns true when the dungeon is cleared.
func dungeon_advance() -> bool:
	if dungeon_run.is_empty():
		return false
	dungeon_run.done.append(dungeon_room())
	if dungeon_room() == "boss":
		var id := str(dungeon_run.id)
		var d := dungeon_def(id)
		flags["dungeon_done_" + id] = day
		dungeon_run.reward_changes = apply(d.get("reward", {}), str(d.name))
		add_history("dungeon", "%s cleared the %s" % [champ.name, str(d.name)], champ.pos)
		return true
	dungeon_run.room = int(dungeon_run.room) + 1
	return false


func leave_dungeon() -> void:
	dungeon_run = {}
	moves = 0
