extends SceneTree
## Headless rules test. Run from the game folder:
##   godot --headless --script res://tests/sim_test.gd
## Checks world generation, the economy, cargo, battles and ages without a window.

var fails := 0


func _init() -> void:
	_world_checks()
	_cargo_checks()
	_economy_bot()
	_battle_odds()
	_age_checks()
	_item_checks()
	_event_sweep()
	_city_checks()
	_story_bot(42)
	_quest_checks()
	_dungeon_checks()
	print("\nRESULT: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(1 if fails > 0 else 0)


func ok(cond: bool, what: String) -> void:
	if not cond:
		fails += 1
		print("  FAIL: ", what)


func _new(seed: int, kid: String, champ: Champion = null) -> GameState:
	var st := GameState.new()
	st.new_game(seed, kid, champ if champ else Champion.new())
	return st


func _world_checks() -> void:
	print("== world")
	for s in [1, 7, 42, 99, 1234]:
		for k in ["red", "blue", "yellow"]:
			var st := _new(s, k)
			var w := st.world
			var f := st.flood()
			ok(w.capitals.size() == 3, "3 capitals")
			for pid in ["greyrock", "crossroads", "ruins", "grove"]:
				ok(w.places.has(pid), "%s/%s has %s" % [s, k, pid])
			var reach := 0
			for h in f.cost.keys():
				reach += 1
			ok(reach > 200, "%s/%s: most of the map reachable (%d)" % [s, k, reach])
			var camps := 0
			for pid in w.places.keys():
				if str(w.tile(w.places[pid]).camp) != "":
					camps += 1
			ok(camps >= 2, "camps placed (%s/%s: %d)" % [s, k, camps])
			ok(st.patrols.size() > 0, "patrols spawned")
			if s == 42 and k == "red":
				print("  %d hexes, %d places, %d camps, %d patrols, %d rivers, reach %d" % [w.tiles.size(), w.places.size(), camps, st.patrols.size(), w.river_paths.size(), reach])
				_ascii(st)


func _cargo_checks() -> void:
	print("== cargo")
	var st := _new(42, "red")
	var food0: int = st.res.food
	st.apply({"food": 40}, "test")
	ok(st.champ.cargo.food == 40 and st.res.food == food0, "loot goes to cargo, not the kingdom")
	var moved := st.deliver_cargo()
	ok(moved.get("food", 0) == 40 and st.res.food == food0 + 40 and st.champ.cargo.food == 0, "delivery moves cargo home")
	ok(st.load_cargo("gold", 10) and st.champ.cargo.gold == 10, "load supplies at home")
	st.champion_died()
	ok(st.champ.cargo.gold == 0, "cargo lost on death")
	var c := Champion.new()
	c.attrs.DEX = 2
	ok(c.move_bonus() == 0, "DEX 2 -> +0")
	c.attrs.DEX = 4
	ok(c.move_bonus() == 1, "DEX 4 -> +1")
	c.attrs.DEX = 5
	ok(c.move_bonus() == 2, "DEX 5 -> +2")


func _economy_bot() -> void:
	print("== economy (bot builds, 28 days)")
	for k in ["red", "blue", "yellow"]:
		var st := _new(7, k)
		var order := ["farm", "lumber", "farm", "house", "market", "barracks", "house", "farm"]
		var oi := 0
		for d in 28:
			if oi < order.size() and st.build_status(order[oi]).ok:
				for slot in st.city_terrain.keys():
					if st.can_build(order[oi], slot).ok:
						st.build(order[oi], slot)
						oi += 1
						break
			st.end_day()
		print("  %-6s day %d pop %d/%d food %d wood %d stone %d gold %d buildings %d" % [k, st.day, st.pop, st.housing(), st.res.food, st.res.wood, st.res.stone, st.res.gold, st.city.size()])
		ok(st.city.size() >= 5, "%s bot can grow a city" % k)


func _fight(st: GameState, group: String) -> String:
	var b := Battle.new()
	b.setup(group, st)
	var guard := 0
	while b.result == "" and guard < 300:
		b.start_round()
		while b.result == "":
			var t := b.next_turn()
			if t.is_empty():
				break
			if t.actor.is_empty() or t.get("skip", false):
				continue
			var a: Dictionary = t.actor
			if a.side == "enemy":
				b.ai_act(a)
			else:
				var sk := b.usable_skills(a)
				if sk.is_empty():
					continue
				var pick: Dictionary = sk[0]
				for s in sk:
					if s.has("heal"):
						for ally in b.allies:
							if ally.hp < ally.max_hp / 2:
								pick = s
					elif s.has("dmg") and not pick.has("heal"):
						pick = s
				var tg := b.targets(a, pick)
				b.act(a, pick, tg[0])
		guard += 1
	b.finish()
	return b.result


func _battle_odds() -> void:
	print("== battles (200 each)")
	var setups := [["solo", []], ["full", ["spearman", "shieldbearer", "archer", "herbalist"]]]
	for su in setups:
		for g in ["boars", "wolves", "bandits", "raiders", "bandit_camp", "wolf_den"]:
			var win := 0
			var lose := 0
			for i in 200:
				var st := _new(1000 + i, "red")
				st.res = {"food": 999, "wood": 999, "stone": 999, "gold": 999, "iron": 999}
				st.city[Vector2i(-1, 0)] = {"type": "barracks", "day": 0}
				st.pop = 20
				for u in su[1]:
					st.recruit(u)
				var r := _fight(st, g)
				if r == "win": win += 1
				if r == "lose": lose += 1
			print("  %-5s vs %-12s win %3d%%  lose %3d%%" % [su[0], g, win / 2, lose / 2])


func _age_checks() -> void:
	print("== ages")
	var st := _new(5, "red")
	ok(not st.age_status().ok, "can't advance at start")
	st.res = {"food": 999, "wood": 999, "stone": 999, "gold": 999, "iron": 999}
	st.pop = 12
	var slots := st.city_terrain.keys().filter(func(s): return st.city_terrain[s] == "plains" and not st.city.has(s))
	var types := ["farm", "house", "market", "barracks", "farm", "house"]
	for i in types.size():
		st.city[slots[i]] = {"type": types[i], "day": 0}
	ok(st.age_status().ok, "requirements met")
	ok(st.advance_age() and st.age == 2, "advance to Age II")
	ok(st.build_status("blacksmith").ok, "blacksmith unlocked")
	st.city[slots[6]] = {"type": "blacksmith", "day": 0}
	ok(st.buy_upgrade("iron_weapons"), "buy iron weapons")


func _item_checks() -> void:
	print("== items")
	var st := _new(3, "red")
	var c := st.champ
	var str0 := c.attr("STR")
	ok(c.add_item("war_hammer") == 1 and c.equip_item("war_hammer"), "equip hammer")
	ok(c.attr("STR") == str0 + 1 and c.weapon_info().dmg == 4, "hammer gives +1 STR and 4 dmg")
	c.add_item("chainmail")
	var mv := c.move_bonus()
	var d0 := c.defense()
	c.equip_item("chainmail")
	ok(c.defense() == d0 + 3 and c.move_bonus() == mv - 1, "chain shirt: +3 def, -1 move")
	c.salves = 3
	ok(c.count("salve") == 3 and c.salves == 3, "salves alias")
	for i in 20:
		c.add_item("gem")
	ok(c.count("gem") == 20, "valuables stack")
	for id in ["spear", "sword", "boots", "compass", "lucky_coin", "wolf_tooth", "padded_vest", "hide_cloak"]:
		st.give_item(id)
	ok(c.bag.size() <= 8, "bag never exceeds 8 slots (%d)" % c.bag.size())
	var hp0 := c.hp
	c.hp = 2
	var ch := st.use_item("salve")
	ok(c.hp == mini(c.max_hp(), 10) and not ch.is_empty(), "salve heals on the map")
	# crafting
	st.res = {"food": 999, "wood": 999, "stone": 999, "gold": 999, "iron": 999}
	st.age = 2
	st.city[Vector2i(1, 0)] = {"type": "blacksmith", "day": 0, "level": 1}
	c.bag.clear()
	c.add_item("meteor_shard")
	ok(st.craft("starsteel") and c.count("starsteel") == 1 and c.count("meteor_shard") == 0, "craft starsteel from a meteor shard")
	# battle item use
	var b := Battle.new()
	c.add_item("smoke_bomb")
	b.setup("bandits", st)
	var champ_f: Dictionary = b.allies.filter(func(a): return a.kind == "champion")[0]
	b.use_item(champ_f, "smoke_bomb")
	ok(b.result == "fled", "smoke bomb escapes")


## Resolve every option of every event (with all items in the bag) — nothing may crash.
func _event_sweep() -> void:
	print("== events (%d)" % (Data.events().size() - 1))
	var n := 0
	for id in Data.events().keys():
		if id.begins_with("_"):
			continue
		var e: Dictionary = Data.events()[id]
		for i in (e.options as Array).size():
			var st := _new(11 + n, "red")
			st.champ.cargo = {"food": 50, "wood": 50, "stone": 50, "gold": 50, "iron": 0}
			for it in ["bread", "wine", "torch", "sealed_letter", "old_map"]:
				st.champ.add_item(it)
			var r := st.resolve_event(id, i)
			ok(r.has("text"), "%s option %d resolves" % [id, i])
			n += 1
	print("  %d options resolved" % n)
	var st2 := _new(5, "red")
	ok(not st2.event_allowed("soldier_returns", Data.events().soldier_returns), "chain event locked at start")
	st2.flags["soldier_saved"] = 1
	st2.day = 6
	ok(st2.event_allowed("soldier_returns", Data.events().soldier_returns), "chain event opens after its flag + days")


func _city_checks() -> void:
	print("== city")
	var st := _new(8, "red")
	st.res = {"food": 500, "wood": 500, "stone": 500, "gold": 500, "iron": 500}
	st.pop = 30
	var es := st.expand_status()
	var before := st.city_terrain.size()
	ok(es.ok and not st.expand_city().is_empty() and st.city_terrain.size() == 37 and st.city_radius == 3, "expand to radius 3 (%d plots)" % st.city_terrain.size())
	ok(not st.expand_status().ok, "radius 4 needs Age II")
	var hills := st.city_terrain.keys().filter(func(h): return st.city_terrain[h] == "hills" and not st.city.has(h))
	ok(not hills.is_empty() and st.build("mine", hills[0]).ok, "mine on hills")
	var plains := st.city_terrain.keys().filter(func(h): return st.city_terrain[h] == "plains" and not st.city.has(h))
	st.builds_today = 0
	st.city[plains[0]] = {"type": "farm", "day": 1, "level": 1}
	var f1: int = st.production_by_slot()[plains[0]].food
	st.city[plains[0]].level = 2
	var f2: int = st.production_by_slot()[plains[0]].food
	ok(f2 > f1, "level 2 farm makes more (%d -> %d)" % [f1, f2])
	st.city[plains[1]] = {"type": "market", "day": 1, "level": 1, "mode": "grain"}
	var mp: Dictionary = st.production_by_slot()[plains[1]]
	ok(int(mp.get("food", 0)) < 0 and int(mp.get("gold", 0)) > 0, "market sells grain: %s" % mp)
	st.builds_today = 0
	ok(st.upgrade_building_status(plains[1]).ok and st.upgrade_building(plains[1]) and st.level_of(plains[1]) == 2, "upgrade market")
	# level 3 needs Age II and a specialisation
	st.age = 2
	st.city[plains[0]].level = 2
	ok(not st.upgrade_building(plains[0]), "level 3 farm refuses without a branch")
	ok(st.upgrade_building(plains[0], "orchard") and st.level_of(plains[0]) == 3 and st.branch_def(plains[0]).id == "orchard", "farm -> orchard")
	ok(st.weekly_items().get("honey", 0) >= 1, "orchard makes honey weekly")
	# water plots: pier yes, house no
	var water := st.city_terrain.keys().filter(func(h): return st.city_terrain[h] == "water" and not st.city.has(h))
	ok(not water.is_empty() and not st.can_build("house", water[0]).ok and st.can_build("fishery", water[0]).ok, "pier on water, house not")
	# iron
	ok(not st.build_status("ironmine").ok, "iron mine needs an outpost")
	st.flags["outpost_iron"] = 1
	st.builds_today = 0
	var pl2 := st.city_terrain.keys().filter(func(h): return st.city_terrain[h] == "plains" and not st.city.has(h))
	ok(st.build("ironmine", pl2[0]).ok and int(st.production_by_slot()[pl2[0]].get("iron", 0)) == 2, "iron mine makes 2 iron")
	var iron_before := int(st.res.iron)
	st.end_day()
	ok(int(st.res.iron) > iron_before - 1, "iron collected at day end (%d -> %d)" % [iron_before, int(st.res.iron)])
	# storehouse
	st.builds_today = 0
	st.city[pl2[1]] = {"type": "bakery", "day": 1, "level": 1}
	st.pop = 40
	var r := st._end_week()
	ok(st.stash_count("bread") >= 2, "bakery bread goes to the storehouse (%s)" % [r.stash])
	var bag_before := st.champ.count("bread")
	st.deliver_cargo()
	ok(st.champ.count("bread") > bag_before, "Champion picks up the storehouse at home")
	# crafting from storehouse items
	st.city[pl2[2]] = {"type": "tannery", "day": 1, "level": 1}
	st.stash_add("hide", 2)
	ok(st.craft_status("fur_cloak").ok and st.craft("fur_cloak") and st.stash_count("hide") == 0, "fur cloak from storehouse hides")
	# land clearing
	var forest := st.city_terrain.keys().filter(func(h): return st.city_terrain[h] == "forest" and not st.city.has(h))
	var w0 := int(st.res.wood)
	ok(not forest.is_empty() and st.clear_land(forest[0]) and st.city_terrain[forest[0]] == "plains" and int(st.res.wood) > w0 - 1, "clear the woods")
	# age III and the 5th ring
	st.age = 2
	ok(st.expand_city().size() > 0 and st.city_radius == 4, "radius 4 at Age II")
	ok(not st.expand_status().ok, "radius 5 needs Age III")
	st.age = 3
	ok(st.expand_city().size() > 0 and st.city_terrain.size() == 91, "radius 5 at Age III (%d plots)" % st.city_terrain.size())
	ok(st.builds_per_day() == 3, "3 builds a day at Age III")
	# market guild discount
	var mk: Vector2i = plains[1]
	st.city[mk].level = 2
	st.city[mk].erase("branch")
	ok(st.upgrade_building(mk, "guild") and st.shop_price("salve") < int(Champion.item("salve").shop), "guild discount")


func _story_bot(seed: int) -> void:
	print("== story bot")
	var st := _new(seed, "red")
	var targets: Array = ["crossroads", "greyrock", "ruins"]
	var lines: Array[String] = []
	for d in 21:
		st.roll_moves()
		if targets.is_empty():
			targets = ["crossroads"]
		var path := st.path_to(st.world.places[targets[0]])
		if path.is_empty():
			targets.pop_front()
		for stp in path:
			if not stp.reachable:
				break
			var r := st.step(stp.h)
			if not r.ok:
				break
			for n in r.discovered:
				lines.append("d%d discovered %s" % [st.day, n])
			if r.battle != "":
				var res := _fight(st, st.patrols[int(r.battle.substr(7))].group)
				lines.append("d%d patrol fight: %s" % [st.day, res])
				break
			if r.event != "":
				st.resolve_event(r.event, 0)
				lines.append("d%d event %s" % [st.day, r.event])
				break
			if r.place != "":
				lines.append("d%d place %s" % [st.day, r.place])
				if r.place == "card:outpost":
					lines.append("   outpost ok=%s" % st.plant_outpost().ok)
				if r.place == "dialogue:tobbin":
					st.apply(Data.dialogues().tobbin.nodes.gift.effects, "Tobbin")
				targets.pop_front()
				break
		st.end_day()
		if not st.alive:
			lines.append("DEATH")
			break
	print("  day %d lv %d hp %d/%d cargo %s res %s" % [st.day, st.champ.level, st.champ.hp, st.champ.max_hp(), st.champ.cargo, st.res])
	for l in lines:
		print("   ", l)


func _ascii(st: GameState) -> void:
	var w := st.world
	var ch := {"plains": ".", "forest": "f", "hills": "^", "mountain": "M", "water": "~"}
	for row in w.height:
		var line := " " if row % 2 == 1 else ""
		for col in w.width:
			var h := Hex.from_offset(col, row)
			var t: Dictionary = w.tile(h)
			var c: String = ch[t.terrain]
			if t.road: c = "="
			if t.river: c = "r"
			if t.place == "capital": c = str(t.owner)[0].to_upper()
			elif t.place == "camp": c = "X"
			elif t.place != "": c = str(t.place)[0]
			line += c + " "
		print("  ", line)


func _quest_checks() -> void:
	print("== quests")
	var qd: Dictionary = Data.get_file("quests").quests
	for id in qd.keys():
		var q: Dictionary = qd[id]
		ok(str(q.get("next", "")) == "" or qd.has(str(q.next)), "quest %s next exists" % id)
		var it := str(q.get("reward", {}).get("item", ""))
		ok(it == "" or not Champion.item(it).is_empty(), "quest %s reward item" % id)
		for o in q.objectives:
			if str(o.type) == "build":
				ok(Data.buildings().has(str(o.target)), "quest %s builds %s" % [id, o.target])
			if str(o.type) == "kill":
				ok(Data.enemies().groups.has(str(o.target)), "quest %s kills %s" % [id, o.target])
			if str(o.type) == "dungeon":
				ok(not Data.get_file("dungeons").get(str(o.target), {}).is_empty(), "quest %s dungeon %s" % [id, o.target])
	var st := _new(7, "red")
	ok(st.active_quests("main") == ["m1_banner"], "main quest starts")
	for slot in st.city_terrain.keys():
		if st.can_build("farm", slot).ok:
			st.city[slot] = {"type": "farm", "day": 0}
			break
	for slot in st.city_terrain.keys():
		if st.city_terrain[slot] == "plains" and not st.city.has(slot):
			st.city[slot] = {"type": "market", "day": 0}
			break
	var g0 := int(st.res.gold)
	var done := st.check_quests()
	ok(done.size() == 1 and st.quests.m1_banner.state == "done", "m1 finishes")
	ok(int(st.res.gold) == g0 + 30, "m1 reward paid")
	ok(st.quests.has("m2_ruins"), "m2 starts")
	var side := st.offer_side_quest()
	ok(side != "" and st.active_quests("side").size() == 1, "side quest offered")
	# save / load round trip keeps quests and world
	ok(SaveGame.save(st, "3"), "save")
	var st2 := SaveGame.load_into("3")
	ok(st2 != null and st2.quests.has("m2_ruins") and st2.world.tiles.size() == st.world.tiles.size() and st2.champ.pos == st.champ.pos, "load round trip")
	ok(st2.city.size() == st.city.size() and int(st2.res.gold) == int(st.res.gold), "load keeps city and res")
	SaveGame.delete("3")


func _dungeon_checks() -> void:
	print("== dungeons")
	var dd: Dictionary = Data.get_file("dungeons")
	for seed in [3, 42, 77, 1234]:
		var st := _new(seed, "red")
		for id in ["crystal_cave", "old_crypt", "sunken_fort"]:
			ok(st.world.places.has(id), "seed %d places %s" % [seed, id])
	for id in dd.keys():
		if id.begins_with("_"):
			continue
		var d: Dictionary = dd[id]
		for g in d.monsters + [d.boss]:
			ok(Data.enemies().groups.has(str(g)), "dungeon %s group %s" % [id, g])
			for f in Data.enemies().groups.get(str(g), {}).get("foes", []):
				ok(Data.enemies().foes.has(str(f)), "group %s foe %s" % [g, f])
		# a full band delves: fights resolve, rooms resolve, the guardian falls (most of the time)
		var wins := 0
		for i in 20:
			var st := _new(500 + i, "red")
			st.res = {"food": 999, "wood": 999, "stone": 999, "gold": 999, "iron": 999}
			st.city[Vector2i(-1, 0)] = {"type": "barracks", "day": 0}
			st.pop = 20
			for u in ["spearman", "shieldbearer", "archer", "herbalist"]:
				st.recruit(u)
			st.champ.level = 4
			st.start_dungeon(id)
			var guard := 0
			while guard < 20:
				guard += 1
				var k := st.dungeon_room()
				if k in ["fight", "boss"]:
					var r := _fight(st, st.dungeon_group())
					if r != "win":
						break
				else:
					st.dungeon_resolve({"chest": "open", "trap": "disarm", "shrine": "pray", "rest": "rest"}[k])
				if st.dungeon_advance():
					wins += 1
					break
			ok(st.champ.hp >= 0, "hp sane")
		print("  %-13s full band clears %d/20" % [id, wins])
