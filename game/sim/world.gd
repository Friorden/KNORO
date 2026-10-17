class_name World
extends RefCounted
## The hex world: terrain, owners, roads, rivers and special places.
## generate(seed, player) builds a new map; the same seed always gives the same map.
##
## Regions (offset grid, 28 x 20 by default):
##   west   - Red river plains
##   east   - Blue lake country (lakes + woods)
##   north  - Yellow high grasslands and hills, a mountain ridge on top
##   south  - wildlands: forests, hills, bandit camps, wolf dens

const ELEV := {"plains": 0.0, "forest": 1.0, "hills": 7.0, "mountain": 15.0, "water": -6.0}

var width: int
var height: int
var seed_value: int
var tiles: Dictionary = {}          # Vector2i -> Dictionary
var capitals: Dictionary = {}       # kingdom id -> Vector2i
var places: Dictionary = {}         # place id -> Vector2i
var player: String = "red"
var merchant: String = "blue"
var rival: String = "yellow"
var road_paths: Array = []
var river_paths: Array = []         # Array of Array[Vector2i]

var _rng := RandomNumberGenerator.new()


func has(h: Vector2i) -> bool:
	return tiles.has(h)


func tile(h: Vector2i) -> Dictionary:
	return tiles.get(h, {})


func passable(h: Vector2i) -> bool:
	if not tiles.has(h):
		return false
	return bool(Data.B("terrain.%s.passable" % tiles[h].terrain, true))


## Movement cost to ENTER hex h.
func cost(h: Vector2i, rainy: bool = false) -> int:
	var t: Dictionary = tiles.get(h, {})
	if t.is_empty() or not passable(h):
		return 999
	var c: int
	if t.road:
		c = int(Data.B("terrain.road_cost", 1))
	else:
		c = int(Data.B("terrain.%s.cost" % t.terrain, 1))
	if t.river and not t.road:
		c += int(Data.B("terrain.river_extra", 1))
		if rainy:
			c += int(Data.B("rain_extra_cost", 1))
	return c


# --------------------------------------------------------------------------
# Generation
# --------------------------------------------------------------------------

func generate(p_seed: int, p_player: String) -> void:
	seed_value = p_seed
	player = p_player
	_rng.seed = p_seed
	width = int(Data.B("map.width", 28))
	height = int(Data.B("map.height", 20))
	tiles.clear()
	capitals.clear()
	places.clear()
	road_paths.clear()
	river_paths.clear()

	var noise := FastNoiseLite.new()
	noise.seed = p_seed
	noise.frequency = 0.11
	var moist := FastNoiseLite.new()
	moist.seed = p_seed + 77
	moist.frequency = 0.09

	# 1) base terrain from regions + noise
	for row in height:
		for col in width:
			var h := Hex.from_offset(col, row)
			var n := noise.get_noise_2d(col * 3.0, row * 3.0)
			var m := moist.get_noise_2d(col * 3.0, row * 3.0)
			var east := float(col) / float(width)
			var north := 1.0 - float(row) / float(height)
			var south := float(row) / float(height)
			var terrain := "plains"
			if row <= 1 and n > -0.05 and col > 3 and col < width - 3:
				terrain = "mountain"
			elif north > 0.7 and n > -0.35:
				terrain = "hills"
			elif m + east * 0.35 > 0.32:
				terrain = "forest"
			elif south > 0.68 and (m > 0.0 or n > 0.15):
				terrain = "forest" if m > n else "hills"
			elif n > 0.38:
				terrain = "hills"
			tiles[h] = {
				"h": h, "terrain": terrain, "owner": "", "road": false, "river": false,
				"place": "", "deposit": "", "secret": false, "name": "", "band": 0, "camp": "", "dungeon": "",
				"elev": float(ELEV[terrain]) + Hex.hash01(h, 3) * 2.0, "var": Hex.hash01(h, 9),
			}

	# 2) capitals in their home regions
	var homes := {
		"plains_west": Vector2i(5, height / 2),
		"lakes_east": Vector2i(width - 7, height / 2 - 1),
		"hills_north": Vector2i(width / 2, 3),
	}
	for kid in Data.kingdoms().keys():
		var home := str(Data.kingdoms()[kid].home)
		var spot: Vector2i = homes.get(home, Vector2i(width / 2, height / 2))
		spot += Vector2i(_rng.randi_range(-1, 1), _rng.randi_range(-1, 1))
		var cap := Hex.from_offset(clampi(spot.x, 2, width - 3), clampi(spot.y, 2, height - 3))
		capitals[kid] = cap
		_set_terrain(cap, "hills" if home == "hills_north" else "plains")
		for nb in Hex.ring(cap, 1):
			if nb == cap or not tiles.has(nb):
				continue
			match home:
				"plains_west":
					_set_terrain(nb, "forest" if Hex.hash01(nb, 5) < 0.25 else "plains")
				"lakes_east":
					_set_terrain(nb, "forest" if Hex.hash01(nb, 5) < 0.35 else "plains")
				_:
					_set_terrain(nb, "hills" if Hex.hash01(nb, 5) < 0.6 else "plains")
		tiles[cap].place = "capital"
		tiles[cap].name = "%s capital" % Data.kingdoms()[kid].name

	# 3) Blue lake country: several lakes around the eastern capital, plus a couple elsewhere
	for kid in capitals.keys():
		if str(Data.kingdoms()[kid].home) == "lakes_east":
			for i in 5:
				var a := _rng.randf() * TAU
				var d := _rng.randf_range(2.6, 5.5)
				var off := Hex.to_offset(capitals[kid])
				var lc := Hex.from_offset(clampi(off.x + int(round(cos(a) * d)), 1, width - 2), clampi(off.y + int(round(sin(a) * d * 0.8)), 1, height - 2))
				_lake(lc, _rng.randi_range(1, 2), capitals[kid])
	for i in 2:
		var lc := Hex.from_offset(_rng.randi_range(4, width - 5), _rng.randi_range(height / 2 + 2, height - 3))
		_lake(lc, 1, Vector2i(-999, -999))

	# 4) territories
	for kid in capitals.keys():
		for h in Hex.ring(capitals[kid], 2):
			if tiles.has(h) and tiles[h].terrain != "water" and tiles[h].owner == "":
				tiles[h].owner = kid

	# 5) rivers: one from the northern hills down through the west, one into the eastern lakes
	_make_river(Hex.from_offset(_rng.randi_range(7, 10), 2), Vector2i(-1, 0))
	_make_river(Hex.from_offset(_rng.randi_range(width - 10, width - 8), 2), Vector2i(1, 0))

	# 6) roads between all capitals
	var keys: Array = capitals.keys()
	for i in keys.size():
		for j in range(i + 1, keys.size()):
			var path := _road_path(capitals[keys[i]], capitals[keys[j]])
			for h in path:
				if tiles[h].terrain != "water":
					tiles[h].road = true
			road_paths.append(path)

	# 7) contested stone deposit between the player and the nearest neighbour
	var others: Array = capitals.keys().filter(func(k): return k != player)
	var pc: Vector2i = capitals[player]
	var best := Vector2i(-999, -999)
	var best_score := 1e9
	for h in tiles.keys():
		var t: Dictionary = tiles[h]
		if t.owner != "" or t.terrain in ["water", "mountain"] or t.road or t.place != "":
			continue
		var dp := Hex.distance(h, pc)
		if dp < 5 or dp > 8:
			continue
		var d_other := 99
		for k in others:
			d_other = mini(d_other, Hex.distance(h, capitals[k]))
		var score := absf(dp - 6.0) * 2.0 + d_other + (0.0 if t.terrain == "hills" else 1.5) + Hex.hash01(h, 21)
		if score < best_score:
			best_score = score
			best = h
	if best.x > -999:
		_set_terrain(best, "hills")
		tiles[best].place = "deposit"
		tiles[best].deposit = "stone"
		tiles[best].name = "Greyrock"
		places["greyrock"] = best
	others.sort_custom(func(a, b): return Hex.distance(capitals[a], best) < Hex.distance(capitals[b], best))
	rival = others[0]
	merchant = others[1]

	# 8) crossroads on the player -> merchant road
	for path in road_paths:
		var ends := [path[0], path[-1]]
		if pc in ends and capitals[merchant] in ends:
			var p: Array = path.duplicate()
			if p[0] != pc:
				p.reverse()
			var idx := clampi(int(p.size() * 0.38), 4, p.size() - 4)
			var cr: Vector2i = p[idx]
			tiles[cr].place = "crossroads"
			tiles[cr].name = "the Crossroads"
			places["crossroads"] = cr

	# 9) places: ruins, grove, a second stone seam, surveyor secrets
	_place("ruins", "Old ruins", ["forest", "hills"], pc, 5, 8, false)
	_place("grove", "Hermit's grove", ["forest", "plains"], pc, 7, 12, false, true)
	_place("flint", "Flint ridge", ["hills"], pc, 9, 16, false, true)
	if places.has("flint"):
		tiles[places["flint"]].deposit = "stone"
		tiles[places["flint"]].place = "deposit"
	var mc: Vector2i = capitals[merchant]
	_place("iron", "Iron cliffs", ["hills", "plains", "forest"], mc, 3, 7, true, false, true)
	_place("cove", "Smugglers' cove", ["plains", "forest", "hills"], pc, 8, 18, true, false, true)
	_place("tower", "Old watchtower", ["hills", "plains", "forest"], pc, 10, 18, true)
	if places.has("iron"):
		tiles[places["iron"]].deposit = "iron"

	# 9b) caves and dungeons (data/dungeons.json): a cave close to home, a crypt further out, a fort on the coast
	_place("crystal_cave", "Crystal cave", ["hills", "forest"], pc, 5, 9, false)
	_place("old_crypt", "Old crypt", ["forest", "plains", "hills"], pc, 9, 15, false, true)
	_place("sunken_fort", "Sunken fort", ["plains", "forest", "hills"], pc, 12, 22, false, false, true)
	if not places.has("sunken_fort"):
		_place("sunken_fort", "Sunken fort", ["plains", "forest", "hills"], pc, 10, 30, false)
	for did in ["crystal_cave", "old_crypt", "sunken_fort"]:
		if places.has(did):
			tiles[places[did]].place = "dungeon"
			tiles[places[did]].dungeon = did

	# 10) enemy camps far from capitals, mostly south
	var camps := [["camp1", "Bandit camp", "bandit_camp", ["plains", "forest", "hills"]],
		["den1", "Wolf den", "wolf_den", ["forest", "hills"]],
		["camp2", "Bandit camp", "bandit_camp", ["plains", "forest", "hills"]],
		["den2", "Wolf den", "wolf_den", ["forest"]]]
	for c in camps:
		_place_camp(c[0], c[1], c[2], c[3])

	# 11) danger bands
	var wild_d: int = Data.B("danger.wild_distance", 6)
	for h in tiles.keys():
		var t: Dictionary = tiles[h]
		var band := int(Data.B("terrain.%s.danger" % t.terrain, 0))
		var dmin := 99
		for k in capitals.keys():
			dmin = mini(dmin, Hex.distance(h, capitals[k]))
		if dmin > wild_d:
			band += 1
		for pid in places.keys():
			if str(tiles[places[pid]].camp) != "" and Hex.distance(h, places[pid]) <= 2:
				band += 1
		if t.owner != "":
			band -= 1
		if t.road:
			band = mini(band, 0)
		if t.place in ["capital", "crossroads"]:
			band = 0
		t.band = clampi(band, 0, 2)


func _set_terrain(h: Vector2i, terrain: String) -> void:
	if not tiles.has(h):
		return
	tiles[h].terrain = terrain
	tiles[h].elev = float(ELEV[terrain]) + Hex.hash01(h, 3) * 2.0


func _lake(center: Vector2i, radius: int, avoid: Vector2i) -> void:
	for h in Hex.ring(center, radius):
		if not tiles.has(h):
			continue
		if avoid.x > -999 and Hex.distance(h, avoid) <= 1:
			continue
		if tiles[h].place != "":
			continue
		if Hex.distance(h, center) == radius and Hex.hash01(h, 44) < 0.35:
			continue
		_set_terrain(h, "water")


func _place(id: String, label: String, terrains: Array, from: Vector2i, dmin: int, dmax: int, secret: bool, south: bool = false, coast: bool = false) -> void:
	var candidates: Array = []
	for h in tiles.keys():
		var t: Dictionary = tiles[h]
		if t.place != "" or t.road or t.terrain in ["water", "mountain"] or t.owner != "":
			continue
		if not (t.terrain in terrains):
			continue
		var d := Hex.distance(h, from)
		if d < dmin or d > dmax:
			continue
		var near_other := false
		for k in capitals.keys():
			if capitals[k] != from and Hex.distance(h, capitals[k]) < 4:
				near_other = true
		if near_other:
			continue
		if coast:
			var near := false
			for nb in Hex.neighbors(h):
				if tiles.has(nb) and tiles[nb].terrain == "water":
					near = true
			if not near:
				continue
		var crowded := false
		for k in places.keys():
			if Hex.distance(places[k], h) < 3:
				crowded = true
		if crowded:
			continue
		var score := Hex.hash01(h, id.hash())
		if south:
			score -= float(h.y) / float(height)
		candidates.append([score, h])
	if candidates.is_empty():
		return
	candidates.sort_custom(func(a, b): return a[0] < b[0])
	var pick: Vector2i = candidates[0][1]
	tiles[pick].place = id
	tiles[pick].name = label
	tiles[pick].secret = secret
	places[id] = pick


func _place_camp(id: String, label: String, group: String, terrains: Array) -> void:
	var candidates: Array = []
	for h in tiles.keys():
		var t: Dictionary = tiles[h]
		if t.place != "" or t.road or t.owner != "" or not (t.terrain in terrains):
			continue
		var dmin := 99
		for k in capitals.keys():
			dmin = mini(dmin, Hex.distance(h, capitals[k]))
		if dmin < 6:
			continue
		var crowded := false
		for k in places.keys():
			if Hex.distance(places[k], h) < 4:
				crowded = true
		if crowded:
			continue
		candidates.append([Hex.hash01(h, id.hash()) - float(h.y) / float(height) * 0.6, h])
	if candidates.is_empty():
		return
	candidates.sort_custom(func(a, b): return a[0] < b[0])
	var pick: Vector2i = candidates[0][1]
	tiles[pick].place = "camp"
	tiles[pick].camp = group
	tiles[pick].name = label
	places[id] = pick


func _make_river(start: Vector2i, drift: Vector2i) -> void:
	var h := start
	var path: Array[Vector2i] = []
	var avoid: Array = capitals.values()
	for steps in 40:
		if not tiles.has(h):
			break
		var t: Dictionary = tiles[h]
		if t.terrain == "water":
			break
		if t.place == "" and t.terrain != "mountain":
			t.river = true
			path.append(h)
		var options: Array[Vector2i] = [Vector2i(0, 1), Vector2i(-1, 1)]
		var choice: Vector2i = options[_rng.randi_range(0, 1)]
		var off := Hex.to_offset(h)
		if drift.x < 0 and off.x > 9:
			choice = Vector2i(-1, 1)
		elif drift.x < 0 and off.x < 4:
			choice = Vector2i(0, 1)
		elif drift.x > 0 and off.x < width - 11:
			choice = Vector2i(0, 1) if _rng.randf() < 0.5 else Vector2i(1, 0)
		var nxt := h + choice
		if nxt in avoid:
			nxt = h + (Vector2i(-1, 1) if choice != Vector2i(-1, 1) else Vector2i(0, 1))
		h = nxt
	if path.size() > 1:
		river_paths.append(path)


func _road_path(a: Vector2i, b: Vector2i) -> Array:
	var weight := func(h: Vector2i) -> float:
		var t: Dictionary = tiles[h]
		match t.terrain:
			"water", "mountain":
				return 999.0
			"forest":
				return 2.2
			"hills":
				return 1.8
		var w := 1.0 + (0.6 if t.river else 0.0)
		if t.road:
			w = 0.5
		return w
	return dijkstra_path(a, b, weight)


func dijkstra_path(a: Vector2i, b: Vector2i, weight: Callable) -> Array:
	var dist := {a: 0.0}
	var prev := {}
	var open: Array = [a]
	var done := {}
	while not open.is_empty():
		var bi := 0
		for i in open.size():
			if dist[open[i]] < dist[open[bi]]:
				bi = i
		var cur: Vector2i = open[bi]
		open.remove_at(bi)
		if done.has(cur):
			continue
		done[cur] = true
		if cur == b:
			break
		for nb in Hex.neighbors(cur):
			if not tiles.has(nb) or done.has(nb):
				continue
			var w: float = weight.call(nb)
			if w >= 999.0 and nb != b:
				continue
			var nd: float = dist[cur] + w
			if not dist.has(nb) or nd < dist[nb]:
				dist[nb] = nd
				prev[nb] = cur
				open.append(nb)
	if not prev.has(b) and a != b:
		return []
	var path: Array = [b]
	var c: Vector2i = b
	while c != a:
		c = prev[c]
		path.push_front(c)
	return path


func border_edges(kid: String) -> Array:
	var out: Array = []
	for h in tiles.keys():
		if tiles[h].owner != kid:
			continue
		for i in 6:
			var nb: Vector2i = h + Hex.DIRS[i]
			if not tiles.has(nb) or tiles[nb].owner != kid:
				out.append([h, i])
	return out
