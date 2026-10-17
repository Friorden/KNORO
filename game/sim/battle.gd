class_name Battle
extends RefCounted
## Rank-based battle in the Darkest Dungeon tradition.
##
## Picture two lines facing each other across a gap. Rank 1 is the person at
## the front of each line. Every skill has two rules: which of YOUR ranks you
## must stand in to use it ("from"), and which of THEIR ranks it can reach
## ("to"). A spear can't be thrust from the back row; an arrow can fly over
## the front line. When someone falls, everyone behind steps forward.
##
## Each round, every fighter rolls initiative (speed + D8) and acts in that
## order. Actions return "beats" that the battle screen plays as animations.

var group_id := ""
var title := ""
var scene := "dusk_hills"
var loot: Dictionary = {}
var xp := 0
var allies: Array = []     # index 0 = rank 1
var enemies: Array = []
var order: Array = []      # combatants still to act this round
var round_no := 0
var result := ""           # "", "win", "lose", "fled"
var st: GameState
var rng: RandomNumberGenerator


# ------------------------------------------------------------------ setup

func setup(p_group: String, p_state: GameState) -> void:
	st = p_state
	rng = p_state.rng
	group_id = p_group
	var g: Dictionary = Data.enemies().groups[p_group]
	title = str(g.title)
	scene = str(g.get("scene", "dusk_hills"))
	loot = g.get("loot", {})
	xp = int(g.get("xp", 10))
	allies.clear()
	enemies.clear()
	for entry in st.party:
		if str(entry.kind) == "champion":
			allies.append(_champion_fighter())
		else:
			allies.append(_unit_fighter(entry))
	var foes: Dictionary = Data.enemies().foes
	for fid in g.foes:
		var f: Dictionary = foes[fid]
		enemies.append({"side": "enemy", "kind": "foe", "id": fid, "name": f.name, "art": f.art,
			"hp": int(f.hp), "max_hp": int(f.hp), "spd": int(f.spd), "def": int(f.def), "acc": int(f.acc),
			"dmg_bonus": 0, "skills": f.skills, "status": _fresh_status(), "uid": "e%d" % enemies.size()})
	if st.has_building("watchtower") and Hex.distance(st.champ.pos, st.world.capitals[st.kingdom]) <= 3:
		for a in allies:
			a.def += 1
	if st.has_building("walls") and Hex.distance(st.champ.pos, st.world.capitals[st.kingdom]) <= 3:
		for a in allies:
			a.def += 2
	if st.kdef(st.kingdom).get("bonus", {}).has("home_defense") and Hex.distance(st.champ.pos, st.world.capitals[st.kingdom]) <= 2:
		for a in allies:
			a.def += int(st.kdef(st.kingdom).bonus.home_defense)


func _fresh_status() -> Dictionary:
	return {"bleed": [0, 0], "stun": false, "mark": 0, "guarded_by": "", "buffs": []}


func _champion_fighter() -> Dictionary:
	var c := st.champ
	var w := c.weapon_info()
	return {"side": "ally", "kind": "champion", "id": "champion", "name": c.name, "art": "champion",
		"hp": c.hp, "max_hp": c.max_hp(), "spd": c.attr("DEX"), "def": c.defense(), "acc": 0,
		"dmg_bonus": int(w.get("dmg", 0)), "hit_bonus": int(w.get("hit", 0)),
		"skills": Data.get_file("units").champion.skills, "status": _fresh_status(), "uid": "champ"}


func _unit_fighter(u: Dictionary) -> Dictionary:
	var s := st.unit_stats(u)
	return {"side": "ally", "kind": "unit", "id": u.type, "name": s.name, "art": s.art,
		"hp": int(u.hp), "max_hp": s.max_hp, "spd": s.spd, "def": s.def, "acc": s.acc,
		"dmg_bonus": s.dmg, "skills": s.skills, "status": _fresh_status(), "uid": str(u.uid), "ref": u}


# ------------------------------------------------------------------ queries

func side_of(c: Dictionary) -> Array:
	return allies if c.side == "ally" else enemies


func other_side(c: Dictionary) -> Array:
	return enemies if c.side == "ally" else allies


func rank_of(c: Dictionary) -> int:
	return side_of(c).find(c) + 1


func usable(c: Dictionary, sk: Dictionary) -> bool:
	if not (rank_of(c) in sk.get("from", [1, 2, 3, 4, 5])):
		return false
	return not targets(c, sk).is_empty()


func usable_skills(c: Dictionary) -> Array:
	return (c.skills as Array).filter(func(sk): return usable(c, sk))


## Indices on the relevant side that this skill may target.
func targets(c: Dictionary, sk: Dictionary) -> Array:
	var out: Array = []
	match str(sk.target):
		"enemy":
			var foes := other_side(c)
			for i in foes.size():
				if (i + 1) in sk.get("to", [1, 2, 3, 4, 5]):
					out.append(i)
		"ally":
			var mine := side_of(c)
			for i in mine.size():
				if sk.has("guard") and mine[i] == c:
					continue
				out.append(i)
		"allies", "self":
			out.append(side_of(c).find(c))
	return out


func hit_chance(c: Dictionary, sk: Dictionary, t: Dictionary) -> int:
	if sk.get("auto", false):
		return 100
	var bonus := _hit_bonus(c, sk)
	var need := _defense(t) - bonus
	return int(clampf((21.0 - need) / 20.0, 0.05, 0.95) * 100)


func _scale(c: Dictionary, sk: Dictionary) -> int:
	if c.kind == "champion" and sk.has("scale"):
		return st.champ.attr(str(sk.scale))
	return 0


func _hit_bonus(c: Dictionary, sk: Dictionary) -> int:
	return int(c.acc) + int(sk.get("acc", 0)) + _scale(c, sk) + int(c.get("hit_bonus", 0) if sk.get("weapon", false) else 0)


func _defense(t: Dictionary) -> int:
	var d := int(t.def)
	for b in t.status.buffs:
		d += int(b.get("def", 0))
	if int(t.status.mark) > 0:
		d -= 3
	return d


func _dmg_buff(c: Dictionary) -> int:
	var d := 0
	for b in c.status.buffs:
		d += int(b.get("dmg", 0))
	return d


func living_allies() -> int:
	return allies.size()


# ------------------------------------------------------------------ round flow

func start_round() -> void:
	round_no += 1
	var all: Array = allies + enemies
	for c in all:
		c.init = int(c.spd) + rng.randi_range(1, 8)
	all.sort_custom(func(a, b): return a.init > b.init)
	order = all


## Returns the next fighter to act, plus beats for things that happen at the
## start of its turn (bleeding, being stunned). Returns {} when the round is over.
func next_turn() -> Dictionary:
	while not order.is_empty():
		var c: Dictionary = order.pop_front()
		if not (c in allies or c in enemies):
			continue
		var beats: Array = []
		var s: Dictionary = c.status
		if int(s.bleed[1]) > 0:
			var bd := int(s.bleed[0])
			s.bleed[1] = int(s.bleed[1]) - 1
			beats.append(_damage(c, bd, "bleed"))
			if result != "" or not (c in allies or c in enemies):
				return {"actor": {}, "beats": beats}
		# tick buffs / mark
		for b in s.buffs:
			b.turns = int(b.turns) - 1
			if int(b.turns) <= 0 and b.has("guarding"):
				for o in side_of(c):
					if o.uid == str(b.guarding) and str(o.status.guarded_by) == c.uid:
						o.status.guarded_by = ""
		s.buffs = (s.buffs as Array).filter(func(b): return int(b.turns) > 0)
		if int(s.mark) > 0:
			s.mark = int(s.mark) - 1
		if s.stun:
			s.stun = false
			beats.append({"kind": "stunned", "who": c.uid})
			return {"actor": c, "beats": beats, "skip": true}
		return {"actor": c, "beats": beats}
	return {}


# ------------------------------------------------------------------ actions

func act(c: Dictionary, sk: Dictionary, target_idx: int) -> Array:
	var beats: Array = [{"kind": "use", "who": c.uid, "skill": sk.name, "art": c.art}]
	var tside: Array = other_side(c) if sk.target == "enemy" else side_of(c)
	var tlist: Array = []
	match str(sk.target):
		"enemy":
			if sk.get("aoe", false):
				for i in tside.size():
					if (i + 1) in sk.get("to", []):
						tlist.append(tside[i])
			elif target_idx >= 0 and target_idx < tside.size():
				tlist.append(tside[target_idx])
		"ally":
			if target_idx >= 0 and target_idx < tside.size():
				tlist.append(tside[target_idx])
		"allies":
			tlist = tside.duplicate()
		"self":
			tlist = [c]
	for t in tlist:
		if not (t in allies or t in enemies):
			continue
		beats.append_array(_apply_skill(c, sk, t))
		if result != "":
			break
	if sk.has("move") and result == "":
		beats.append_array(_move(c, int(sk.move)))
	return beats


func _apply_skill(c: Dictionary, sk: Dictionary, t: Dictionary) -> Array:
	var out: Array = []
	var harmful := str(sk.target) == "enemy"
	if harmful:
		# guarded? the guardian takes it
		var gid := str(t.status.guarded_by)
		if gid != "":
			for g in side_of(t):
				if g.uid == gid and g != t:
					out.append({"kind": "guarded", "who": g.uid, "for": t.uid})
					t = g
					break
		var roll := rng.randi_range(1, 20)
		var hit: bool = bool(sk.get("auto", false)) or roll + _hit_bonus(c, sk) >= _defense(t)
		if roll == 1 and not sk.get("auto", false):
			hit = false
		if not hit:
			out.append({"kind": "miss", "who": t.uid, "by": c.uid, "roll": roll})
			return out
		if sk.has("dmg"):
			var d := rng.randi_range(int(sk.dmg[0]), int(sk.dmg[1])) + int(c.dmg_bonus) * (1 if (sk.get("weapon", false) or c.kind != "champion") else 0) + _dmg_buff(c)
			d += int(_scale(c, sk) / 2)
			if int(t.status.mark) > 0:
				d += 2 + int(sk.get("vs_marked", 0))
			var crit := roll == 20
			if crit:
				d = int(ceil(d * 1.5))
			out.append(_damage(t, maxi(1, d), "crit" if crit else "hit", c.uid, roll))
			if result != "" or not (t in allies or t in enemies):
				return out
		if sk.has("bleed"):
			t.status.bleed = [int(sk.bleed[0]), int(sk.bleed[1])]
			out.append({"kind": "status", "who": t.uid, "text": "bleeding"})
		if sk.has("stun") and rng.randi_range(1, 100) <= int(sk.stun):
			t.status.stun = true
			out.append({"kind": "status", "who": t.uid, "text": "stunned"})
		if sk.has("mark"):
			t.status.mark = int(sk.mark)
			out.append({"kind": "status", "who": t.uid, "text": "marked"})
		if sk.has("push"):
			out.append_array(_move(t, int(sk.push)))
	else:
		if sk.has("heal"):
			var hval := rng.randi_range(int(sk.heal[0]), int(sk.heal[1])) + int(_scale(c, sk) / 2)
			var before := int(t.hp)
			t.hp = mini(int(t.max_hp), int(t.hp) + hval)
			out.append({"kind": "heal", "who": t.uid, "amount": int(t.hp) - before})
		if sk.get("cure", false):
			t.status.bleed = [0, 0]
			t.status.stun = false
			out.append({"kind": "status", "who": t.uid, "text": "cured"})
		if sk.has("guard"):
			t.status.guarded_by = c.uid
			c.status.buffs.append({"guarding": t.uid, "turns": int(sk.guard)})
			out.append({"kind": "status", "who": t.uid, "text": "covered by %s" % c.name})
		if sk.has("buff"):
			var b: Dictionary = (sk.buff as Dictionary).duplicate()
			t.status.buffs.append(b)
			var parts: Array[String] = []
			if b.has("dmg"): parts.append("+%d dmg" % int(b.dmg))
			if b.has("def"): parts.append("+%d def" % int(b.def))
			out.append({"kind": "status", "who": t.uid, "text": " ".join(parts)})
	return out


func _damage(t: Dictionary, d: int, kind: String, by: String = "", roll: int = 0) -> Dictionary:
	t.hp = maxi(0, int(t.hp) - d)
	var beat := {"kind": kind, "who": t.uid, "dmg": d, "by": by, "roll": roll, "killed": int(t.hp) <= 0}
	if int(t.hp) <= 0:
		_kill(t)
	return beat


func _kill(t: Dictionary) -> void:
	var side := side_of(t)
	side.erase(t)
	order.erase(t)
	for o in side:
		if str(o.status.guarded_by) == t.uid:
			o.status.guarded_by = ""
	if t.kind == "champion":
		result = "lose"
	elif enemies.is_empty():
		result = "win"


func _move(c: Dictionary, steps: int) -> Array:
	var side := side_of(c)
	var i := side.find(c)
	var j := clampi(i + steps, 0, side.size() - 1)
	if i == j:
		return []
	side.remove_at(i)
	side.insert(j, c)
	return [{"kind": "moved", "who": c.uid, "to": j + 1}]


## Consumables usable in battle (by anyone on your side, from the Champion's bag).
func battle_items() -> Array:
	var out: Array = []
	for e in st.champ.bag:
		var u: Dictionary = Champion.item(str(e.id)).get("use", {})
		if u.has("hp") or u.has("cure") or u.has("flee"):
			out.append(str(e.id))
	return out


## Use a bag item on fighter t (the actor itself for most items). Costs the turn.
func use_item(c: Dictionary, id: String, t: Dictionary = {}) -> Array:
	if t.is_empty():
		t = c
	var it := Champion.item(id)
	var u: Dictionary = it.get("use", {})
	if u.is_empty() or not st.champ.remove_item(id):
		return []
	var beats: Array = [{"kind": "use", "who": c.uid, "skill": str(it.name), "art": c.art}]
	if u.get("flee", false):
		result = "fled"
		beats.append({"kind": "fled", "roll": 20, "total": 99})
		return beats
	if u.has("hp"):
		var before := int(t.hp)
		t.hp = mini(int(t.max_hp), int(t.hp) + int(u.hp))
		beats.append({"kind": "heal", "who": t.uid, "amount": int(t.hp) - before})
	if u.get("cure", false):
		t.status.bleed = [0, 0]
		t.status.stun = false
		beats.append({"kind": "status", "who": t.uid, "text": "cured"})
	if u.has("xp"):
		st.champ.add_xp(int(u.xp))
	return beats


## Champion drinks a salve from the pack (costs the turn).
func use_salve(c: Dictionary) -> Array:
	return use_item(c, "salve")


## Swap places with the neighbour in front (-1) or behind (+1). Costs the turn.
func shuffle(c: Dictionary, dir: int) -> Array:
	return [{"kind": "use", "who": c.uid, "skill": "Moves", "art": c.art}] + _move(c, dir)


func retreat() -> Array:
	var r := rng.randi_range(1, 20)
	var total := r + st.champ.attr("DEX")
	if total >= 11:
		result = "fled"
		return [{"kind": "fled", "roll": r, "total": total}]
	return [{"kind": "flee_fail", "roll": r, "total": total}]


# ------------------------------------------------------------------ enemy brain

func ai_act(c: Dictionary) -> Array:
	var skills := usable_skills(c)
	if skills.is_empty():
		# step forward if stuck at the back
		var moved := _move(c, -1)
		return [{"kind": "use", "who": c.uid, "skill": "advances", "art": c.art}] + moved
	# prefer damage; buff now and then
	var pick: Dictionary = skills[0]
	var dmg_skills := skills.filter(func(s): return s.has("dmg"))
	if not dmg_skills.is_empty() and (rng.randf() < 0.8 or dmg_skills.size() == skills.size()):
		pick = dmg_skills[rng.randi_range(0, dmg_skills.size() - 1)]
	else:
		pick = skills[rng.randi_range(0, skills.size() - 1)]
	var tg := targets(c, pick)
	var best: int = tg[0]
	if str(pick.target) == "enemy":
		var foes := other_side(c)
		var best_score := -1e9
		for i in tg:
			var t: Dictionary = foes[i]
			var score := -float(t.hp) + (6.0 if int(t.status.mark) > 0 else 0.0) + rng.randf() * 4.0
			if score > best_score:
				best_score = score
				best = i
	return act(c, pick, best)


# ------------------------------------------------------------------ finish

## Writes HP and losses back to the campaign. Returns a summary.
func finish() -> Dictionary:
	var out := {"result": result, "lost": [], "loot": {}, "xp": 0, "group": group_id}
	# champion hp
	var champ_f: Dictionary = {}
	for a in allies:
		if a.kind == "champion":
			champ_f = a
	if not champ_f.is_empty():
		st.champ.hp = int(champ_f.hp)
	elif result == "lose":
		st.champ.hp = 0
	# units: survivors keep their wounds, the fallen are gone
	var alive_uids := {}
	for a in allies:
		if a.kind == "unit":
			alive_uids[a.uid] = a
	var keep: Array = []
	for entry in st.party:
		if str(entry.kind) == "champion":
			keep.append(entry)
		elif alive_uids.has(str(entry.uid)):
			entry.hp = int(alive_uids[str(entry.uid)].hp)
			keep.append(entry)
		else:
			out.lost.append(st.unit_stats(entry).name)
	# keep the formation order the battle ended in
	var ordered: Array = []
	for a in allies:
		for e in keep:
			if (a.kind == "champion" and str(e.kind) == "champion") or (a.kind == "unit" and str(e.get("uid", "")) == a.uid):
				ordered.append(e)
	for e in keep:
		if not (e in ordered):
			ordered.append(e)
	st.party = ordered
	if result == "win":
		out.loot = loot
		out.xp = xp
	return out
