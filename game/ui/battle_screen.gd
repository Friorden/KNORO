extends Control
## Darkest-Dungeon-style battle. Two lines face each other across the middle
## of the screen: your party on the left (rank 1 nearest the centre), the
## enemy on the right. A ribbon at the top shows who acts next. On your turn,
## pick a skill (the little dot diagram shows which of YOUR ranks can use it
## and which of THEIR ranks it reaches), then click a glowing target.
##
## All rules live in sim/battle.gd; this screen only plays back the "beats"
## the simulation returns.

signal player_done

const GROUND_Y := 790.0
const GAP := 150.0         # half the gap between the two front ranks
const STEP := 165.0        # distance between ranks
const ACTOR_W := 220.0
const ACTOR_H := 300.0

var st: GameState
var battle := Battle.new()
var source := ""
var actors: Dictionary = {}      # uid -> Actor
var fighters: Dictionary = {}    # uid -> fighter dict (incl. dead ones, for labels)
var time := 0.0
var scene_c := Control.new()
var stage := Control.new()
var overlay := Control.new()
var fx_layer := Control.new()
var ribbon := HBoxContainer.new()
var round_l: Label
var panel := PanelContainer.new()
var who_l: Label
var info_l: Label
var skills_box := HBoxContainer.new()
var extra_box := HBoxContainer.new()
var cur: Dictionary = {}
var cur_skill: Dictionary = {}
var mode := ""                   # "", "skill", "target"
var hover_uid := ""
var auto := false
var bursts: Array = []           # [pos, t, col, size]
var flicker := 0.0


func enter(data: Dictionary) -> void:
	st = Game.state
	source = str(data.get("source", "debug"))
	battle.setup(str(data.get("group", "boars")), st)
	Audio.music("music_combat")
	Engine.time_scale = float(Settings.battle_speed)
	_build()
	_spawn_actors()
	_layout(false)
	_intro()


func leave() -> void:
	Engine.time_scale = 1.0
	Audio.music("music_world")


func auto_play() -> void:
	auto = true
	if mode != "":
		_auto_pick()


# ==========================================================================
# build
# ==========================================================================

func _build() -> void:
	scene_c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scene_c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scene_c.draw.connect(_draw_scene)
	add_child(scene_c)
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stage)
	add_child(Atmosphere.make({"camp_night": "fire", "night_forest": "night"}.get(battle.scene, "dusk"), Vector2(0.5, 0.56)))
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(_draw_overlay)
	add_child(overlay)
	fx_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fx_layer)
	# title, top-left
	var tbox := VBoxContainer.new()
	tbox.position = Vector2(40, 26)
	tbox.add_theme_constant_override("separation", -4)
	add_child(tbox)
	tbox.add_child(Style.caps("Battle · " + _place_line(), Color(Style.NOTE, 0.8)))
	var tl := Style.hand(battle.title, 54, Style.NOTE)
	tl.add_theme_color_override("font_outline_color", Style.INK)
	tl.add_theme_constant_override("outline_size", 10)
	tbox.add_child(tl)
	round_l = Style.label("", 16, Style.body_heavy, Color(Style.NOTE, 0.85))
	tbox.add_child(round_l)
	# turn ribbon, top-centre
	var rp := PanelContainer.new()
	rp.add_theme_stylebox_override("panel", Style.box(Color(Style.NOTE, 0.92), 77, 3.0, Style.INK, 2.0, 8.0))
	rp.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	rp.offset_top = 26
	rp.offset_left = -330
	rp.offset_right = 330
	rp.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(rp)
	var rv := HBoxContainer.new()
	rv.add_theme_constant_override("separation", 10)
	rp.add_child(rv)
	rv.add_child(Style.caps("Next ›"))
	ribbon.add_theme_constant_override("separation", 6)
	rv.add_child(ribbon)
	# bottom command panel
	panel.add_theme_stylebox_override("panel", Style.box(Style.CARD, 91, 6.0, Style.INK, 2.4, 16.0))
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_left = 40
	panel.offset_right = -40
	panel.offset_top = -210
	panel.offset_bottom = -22
	add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	panel.add_child(row)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 330
	row.add_child(left)
	who_l = Style.hand("", 40)
	left.add_child(who_l)
	info_l = Style.label("", 16, Style.body_bold, Style.PENCIL)
	info_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_l.custom_minimum_size = Vector2(330, 90)
	left.add_child(info_l)
	skills_box.add_theme_constant_override("separation", 12)
	skills_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(skills_box)
	extra_box.add_theme_constant_override("separation", 10)
	extra_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(extra_box)
	panel.modulate.a = 0.0


func _place_line() -> String:
	var t: Dictionary = st.world.tile(st.champ.pos)
	if str(t.get("name", "")) != "":
		return str(t.name)
	return str(t.terrain).capitalize()


func _spawn_actors() -> void:
	var kc := Style.kingdom_color(st.kingdom)
	Actor.kingdom = st.kingdom
	for f in battle.allies:
		var a := Actor.make(str(f.art), kc, ACTOR_W, ACTOR_H)
		a.face = 1.0
		if f.kind == "champion":
			a.weapon = st.champ.weapon if st.champ.weapon in ["spear", "sword"] else ""
		stage.add_child(a)
		actors[f.uid] = a
		fighters[f.uid] = f
	for f in battle.enemies:
		var a := Actor.make(str(f.art), Style.BAD, ACTOR_W, ACTOR_H)
		a.face = -1.0
		stage.add_child(a)
		actors[f.uid] = a
		fighters[f.uid] = f


func _slot(side: String, rank: int) -> Vector2:
	var x := 960.0 - GAP - (rank - 1) * STEP if side == "ally" else 960.0 + GAP + (rank - 1) * STEP
	var y := GROUND_Y - (8.0 if rank % 2 == 0 else 0.0)
	return Vector2(x - ACTOR_W / 2.0, y - ACTOR_H + 24.0)


func _layout(animate: bool = true) -> void:
	for side in [["ally", battle.allies], ["enemy", battle.enemies]]:
		var arr: Array = side[1]
		for i in arr.size():
			var a: Actor = actors.get(arr[i].uid)
			if a == null:
				continue
			var to := _slot(str(side[0]), i + 1)
			if animate and a.position.distance_to(to) > 2.0:
				var tw := a.create_tween()
				tw.tween_property(a, "position", to, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			else:
				a.position = to
	# stage order: back ranks first so the front overlaps them
	var all: Array = battle.allies + battle.enemies
	all.sort_custom(func(p, q): return battle.rank_of(p) > battle.rank_of(q))
	for f in all:
		var a: Actor = actors.get(f.uid)
		if a:
			stage.move_child(a, -1)


func _intro() -> void:
	var kids := stage.get_children()
	for a in kids:
		var c := a as Actor
		var to := c.position
		c.position = to + Vector2(-500.0 * c.face, 0)
		c.modulate.a = 0.0
		var tw := c.create_tween()
		tw.tween_interval(randf() * 0.25)
		tw.tween_property(c, "position", to, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(c, "modulate:a", 1.0, 0.3)
	await get_tree().create_timer(0.5).timeout
	await _stamp(battle.title.to_upper() + "!", Style.CORAL)
	var tw2 := create_tween()
	tw2.tween_property(panel, "modulate:a", 1.0, 0.3)
	_run()


## A big rotated stamp across the middle of the screen.
func _stamp(text: String, col: Color, hold: float = 0.7) -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Style.box(col, 9, 8.0, Style.INK, 3.0, 18.0))
	var l := Style.hand(text, 72, Style.INK)
	p.add_child(l)
	fx_layer.add_child(p)
	await get_tree().process_frame
	p.position = Vector2(960, 380) - p.size / 2.0
	p.pivot_offset = p.size / 2.0
	p.rotation_degrees = -4
	p.scale = Vector2(1.8, 1.8)
	p.modulate.a = 0.0
	Audio.play("stamp")
	var tw := p.create_tween()
	tw.tween_property(p, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(p, "modulate:a", 1.0, 0.12)
	tw.tween_interval(hold)
	tw.tween_property(p, "modulate:a", 0.0, 0.3)
	tw.tween_callback(p.queue_free)
	await get_tree().create_timer(0.35 + hold).timeout


# ==========================================================================
# battle loop
# ==========================================================================

func _run() -> void:
	while battle.result == "":
		battle.start_round()
		round_l.text = "Round %d" % battle.round_no
		while battle.result == "":
			_refresh_ribbon()
			var t := battle.next_turn()
			if t.is_empty():
				break
			await _play(t.get("beats", []))
			if battle.result != "":
				break
			var a: Dictionary = t.get("actor", {})
			if a.is_empty() or t.get("skip", false):
				continue
			_set_active(a)
			if a.side == "enemy":
				who_l.text = a.name
				info_l.text = "…"
				_clear_skills()
				await get_tree().create_timer(0.3).timeout
				await _play(battle.ai_act(a))
			else:
				cur = a
				_show_skills(a)
				await player_done
			_set_active({})
			await get_tree().create_timer(0.08).timeout
	_finish()


func _set_active(f: Dictionary) -> void:
	for uid in actors.keys():
		(actors[uid] as Actor).active = not f.is_empty() and uid == str(f.uid)


func _refresh_ribbon() -> void:
	for c in ribbon.get_children():
		c.queue_free()
	var n := 0
	for f in battle.order:
		if not (f in battle.allies or f in battle.enemies):
			continue
		var chip := PanelContainer.new()
		var col := Style.kingdom_color(st.kingdom).lightened(0.35) if f.side == "ally" else Color("#E7B9AE")
		chip.add_theme_stylebox_override("panel", Style.box(col, n + 3, 0.0, Style.INK, 1.5, 5.0))
		chip.add_child(Style.label(str(f.name), 14, Style.body_heavy))
		ribbon.add_child(chip)
		n += 1
		if n >= 7:
			break
	if n == 0:
		ribbon.add_child(Style.label("new round", 14, Style.body_bold, Style.PENCIL))


# ==========================================================================
# player turn
# ==========================================================================

func _clear_skills() -> void:
	for c in skills_box.get_children():
		c.queue_free()
	for c in extra_box.get_children():
		c.queue_free()
	_clear_targets()


func _clear_targets() -> void:
	for a in actors.values():
		(a as Actor).targetable = false
		(a as Actor).selected = false
	hover_uid = ""


func _show_skills(f: Dictionary) -> void:
	_clear_skills()
	mode = "skill"
	who_l.text = "%s · rank %d" % [f.name, battle.rank_of(f)]
	info_l.text = "Pick a skill, then click a glowing target."
	var first: Dictionary = {}
	var idx := 0
	for sk in f.skills:
		idx += 1
		var ok := battle.usable(f, sk)
		var b := _skill_button(sk, ok, idx)
		skills_box.add_child(b)
		if ok:
			b.pressed.connect(_pick_skill.bind(sk))
			if first.is_empty():
				first = sk
	# extra actions
	var rank := battle.rank_of(f)
	var side := battle.side_of(f)
	var mv := Style.button("⇄ Move", Style.SAND, 16)
	mv.tooltip_text = "Swap places with the fighter behind you (or in front, if you're last)."
	mv.disabled = side.size() < 2
	mv.pressed.connect(func(): _do(battle.shuffle(f, 1 if rank < side.size() else -1)))
	extra_box.add_child(mv)
	var bi := battle.battle_items()
	var ib := Style.button("Items (%d)" % bi.size(), Style.SAGE, 16)
	ib.tooltip_text = "Use something from the Champion's bag (costs this turn)."
	ib.disabled = bi.is_empty()
	ib.pressed.connect(func(): _show_items(f))
	extra_box.add_child(ib)
	var rt := Style.button("Retreat", Style.PINK, 16)
	rt.tooltip_text = "D20 + DEX ≥ 11 to escape. You lose the rest of the day."
	rt.pressed.connect(func(): _do(battle.retreat()))
	extra_box.add_child(rt)
	for i in skills_box.get_child_count():
		Fx.pop_in(skills_box.get_child(i), i * 0.04, 0.9)
	if auto:
		_auto_pick()
	elif not first.is_empty():
		_pick_skill(first)


func _show_items(f: Dictionary) -> void:
	for c in skills_box.get_children():
		c.queue_free()
	_clear_targets()
	info_l.text = "Pick an item. It is used by %s and costs the turn." % f.name
	for id in battle.battle_items():
		var it := Champion.item(id)
		var b := Style.button("", Style.NOTE, 15, id.length())
		b.custom_minimum_size = Vector2(170, 128)
		var v := VBoxContainer.new()
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		v.offset_left = 10
		v.offset_top = 8
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		b.add_child(v)
		var ic := ItemIcon.make(id, 56, st.champ.count(id))
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(ic)
		var nl := Style.label(str(it.name), 14, Style.body_heavy)
		nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(nl)
		var iid: String = id
		b.pressed.connect(func(): _do(battle.use_item(f, iid)))
		skills_box.add_child(b)
	var back := Style.button("← Skills", Style.CARD, 15)
	back.pressed.connect(func(): _show_skills(f))
	skills_box.add_child(back)


func _skill_button(sk: Dictionary, ok: bool, idx: int) -> Button:
	var b := Style.button("", Style.NOTE if ok else Color("#E9E2D4"), 16, idx * 7)
	b.custom_minimum_size = Vector2(210, 128)
	b.disabled = not ok
	b.tooltip_text = str(sk.get("desc", ""))
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 12
	v.offset_top = 8
	v.offset_right = -10
	v.offset_bottom = -8
	v.add_theme_constant_override("separation", 2)
	b.add_child(v)
	var nl := Style.label("%d  %s" % [idx, sk.name], 18, Style.body_heavy, Style.INK if ok else Style.FAINT)
	nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(nl)
	var dots := Control.new()
	dots.custom_minimum_size = Vector2(170, 26)
	dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dots.draw.connect(_draw_dots.bind(dots, sk, ok))
	v.add_child(dots)
	var dl := Style.label(_skill_line(sk), 13, Style.body_bold, Style.PENCIL)
	dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dl.custom_minimum_size.x = 170
	dl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(dl)
	var ds := Style.label(str(sk.get("desc", "")), 12, Style.body, Style.PENCIL if ok else Style.FAINT)
	ds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ds.custom_minimum_size.x = 186
	ds.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(ds)
	b.set_meta("skill", sk)
	return b


func _skill_line(sk: Dictionary) -> String:
	var parts: Array[String] = []
	if sk.has("dmg"):
		parts.append("%d–%d dmg" % [int(sk.dmg[0]), int(sk.dmg[1])])
	if sk.has("heal"):
		parts.append("heal %d–%d" % [int(sk.heal[0]), int(sk.heal[1])])
	if sk.has("bleed"):
		parts.append("bleed")
	if sk.has("stun"):
		parts.append("stun %d%%" % int(sk.stun))
	if sk.has("mark"):
		parts.append("mark")
	if sk.has("guard"):
		parts.append("guard")
	if sk.has("buff"):
		parts.append("buff")
	if sk.get("aoe", false):
		parts.append("hits all")
	if sk.has("push"):
		parts.append("push")
	if sk.has("move"):
		parts.append("move back")
	return " · ".join(parts)


## The rank diagram: 5 dots for your line (rank 1 nearest the middle) and 5
## for theirs. Yellow = ranks you may stand in; coral = ranks it reaches.
func _draw_dots(c: Control, sk: Dictionary, ok: bool) -> void:
	var y := 13.0
	var mine: Array = sk.get("from", [1, 2, 3, 4, 5])
	var their: Array = sk.get("to", [])
	var tgt := str(sk.target)
	var my_rank := battle.rank_of(cur) if not cur.is_empty() else 0
	for r in range(1, 6):
		var p := Vector2(78 - (r - 1) * 15, y)
		var on := r in mine
		c.draw_circle(p, 6, (Style.YELLOW if on else Color("#E6DED0")) if ok else Color("#E6DED0"))
		c.draw_arc(p, 6, 0, TAU, 12, Style.INK if r == my_rank else Color(Style.INK, 0.45), 2.4 if r == my_rank else 1.2, true)
	c.draw_line(Vector2(89, 3), Vector2(89, 23), Color(Style.INK, 0.5), 1.5, true)
	for r in range(1, 6):
		var p := Vector2(100 + (r - 1) * 15, y)
		var on := false
		var col := Style.CORAL
		match tgt:
			"enemy":
				on = r in their
			"ally", "allies":
				col = Style.SAGE
				on = true
			_:
				on = false
		if tgt in ["ally", "allies", "self"]:
			# friendly skills: show your own line again, mirrored, in sage
			p = Vector2(100 + (r - 1) * 15, y)
			on = tgt != "self"
		c.draw_circle(p, 6, col if on else Color("#E6DED0"))
		c.draw_arc(p, 6, 0, TAU, 12, Color(Style.INK, 0.45), 1.2, true)


func _pick_skill(sk: Dictionary) -> void:
	if mode == "" or cur.is_empty():
		return
	cur_skill = sk
	for b in skills_box.get_children():
		var bb := b as Button
		if bb.has_meta("skill"):
			bb.modulate = Color(1, 1, 1) if bb.get_meta("skill") == sk else Color(1, 1, 1, 0.75)
			bb.scale = Vector2(1.04, 1.04) if bb.get_meta("skill") == sk else Vector2.ONE
	_clear_targets()
	var tg := battle.targets(cur, sk)
	var tside: Array = battle.other_side(cur) if str(sk.target) == "enemy" else battle.side_of(cur)
	var single: bool = str(sk.target) in ["enemy", "ally"] and not sk.get("aoe", false)
	if single:
		for i in tg:
			(actors[tside[i].uid] as Actor).targetable = true
		mode = "target"
		info_l.text = "%s — %s\nClick a glowing target." % [sk.name, sk.get("desc", "")]
	else:
		# self / everyone / area: one click on the button again or any lit fighter
		for i in tg:
			(actors[tside[i].uid] as Actor).targetable = true
		if sk.get("aoe", false):
			for i in tside.size():
				if (i + 1) in sk.get("to", []):
					(actors[tside[i].uid] as Actor).targetable = true
		if str(sk.target) == "allies":
			for f in tside:
				(actors[f.uid] as Actor).targetable = true
		mode = "target"
		info_l.text = "%s — %s\nClick any lit fighter to use it." % [sk.name, sk.get("desc", "")]


func _input(e: InputEvent) -> void:
	if mode == "" or cur.is_empty() or auto:
		return
	if e is InputEventKey and e.pressed and not e.echo:
		var n: int = e.keycode - KEY_1
		if n >= 0 and n < skills_box.get_child_count():
			var b := skills_box.get_child(n) as Button
			if not b.disabled:
				_pick_skill(b.get_meta("skill"))
				accept_event()
		return
	if mode != "target":
		return
	if e is InputEventMouseMotion:
		var hu := _actor_at(e.position)
		if hu != hover_uid:
			hover_uid = hu
			for uid in actors.keys():
				(actors[uid] as Actor).selected = uid == hu
			if hu != "" and str(cur_skill.target) == "enemy":
				info_l.text = "%s → %s\nHit chance %d%%" % [cur_skill.name, fighters[hu].name, battle.hit_chance(cur, cur_skill, fighters[hu])]
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var hu := _actor_at(e.position)
		if hu == "":
			return
		accept_event()
		var f: Dictionary = fighters[hu]
		var tside: Array = battle.other_side(cur) if str(cur_skill.target) == "enemy" else battle.side_of(cur)
		_do(battle.act(cur, cur_skill, tside.find(f)))


func _actor_at(p: Vector2) -> String:
	var best := ""
	var best_d := 1e9
	for uid in actors.keys():
		var a: Actor = actors[uid]
		if not a.targetable or a.dead:
			continue
		var r := Rect2(a.position + Vector2(20, 30), Vector2(ACTOR_W - 40, ACTOR_H - 20))
		if r.has_point(p):
			var d := absf(p.x - (a.position.x + ACTOR_W / 2.0))
			if d < best_d:
				best_d = d
				best = uid
	return best


func _do(beats: Array) -> void:
	if mode == "":
		return
	mode = ""
	_clear_skills()
	await _play(beats)
	cur = {}
	player_done.emit()


## Auto-battle (debug / screenshots): same choices the headless test makes.
func _auto_pick() -> void:
	await get_tree().create_timer(0.35).timeout
	if cur.is_empty() or mode == "":
		return
	var sk := battle.usable_skills(cur)
	if sk.is_empty():
		_do(battle.shuffle(cur, -1))
		return
	var pick: Dictionary = sk[0]
	for s in sk:
		if s.has("heal"):
			for ally in battle.allies:
				if int(ally.hp) < int(ally.max_hp) / 2:
					pick = s
		elif s.has("dmg") and not pick.has("heal"):
			pick = s
	var tg := battle.targets(cur, pick)
	_do(battle.act(cur, pick, tg[0]))


# ==========================================================================
# beat playback
# ==========================================================================

func _center(uid: String) -> Vector2:
	var a: Actor = actors.get(uid)
	if a == null:
		return Vector2(960, 500)
	return a.position + Vector2(ACTOR_W / 2.0, ACTOR_H * 0.45)


func _play(beats: Array) -> void:
	for b in beats:
		var who := str(b.get("who", ""))
		var a: Actor = actors.get(who)
		match str(b.kind):
			"use":
				var f: Dictionary = fighters.get(who, {})
				_skill_tag(who, str(b.skill))
				if a and not f.is_empty():
					var sk := _skill_by_name(f, str(b.skill))
					if not sk.is_empty() and str(sk.target) == "enemy" and not sk.has("mark"):
						Audio.play("whoosh", -4.0)
						a.lunge(a.face, 120.0 if (sk.get("from", []) as Array).has(1) or (sk.get("from", []) as Array).has(2) else 50.0)
						await get_tree().create_timer(0.24).timeout
					else:
						var tw := a.create_tween()
						tw.tween_property(a, "position:y", a.position.y - 22, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
						tw.tween_property(a, "position:y", a.position.y, 0.18).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
						await get_tree().create_timer(0.2).timeout
			"hit", "crit", "bleed":
				var crit := str(b.kind) == "crit"
				if a:
					a.hit()
				var col := Style.BAD if str(b.kind) != "bleed" else Color("#B0413E")
				Fx.float_text(fx_layer, _center(who) + Vector2(0, -90), ("-%d" % int(b.dmg)) + ("  CRIT!" if crit else (" bleed" if str(b.kind) == "bleed" else "")), col, "", 0.0, 44 if crit else 36)
				_burst(_center(who), Style.YELLOW if crit else Style.NOTE, 90.0 if crit else 60.0)
				Audio.play("hit", 0.0 if crit else -3.0)
				if crit:
					Fx.shake(stage, 16.0, 0.35)
				await get_tree().create_timer(0.32).timeout
				if bool(b.get("killed", false)):
					await _kill(who)
			"miss":
				if a:
					a.dodge()
				Fx.float_text(fx_layer, _center(who) + Vector2(0, -90), "miss", Style.PENCIL, "", 0.0, 32)
				Audio.play("block", -4.0)
				await get_tree().create_timer(0.35).timeout
			"heal":
				Fx.float_text(fx_layer, _center(who) + Vector2(0, -90), "+%d HP" % int(b.amount), Style.GOOD, "hp", 0.0, 34)
				_burst(_center(who), Style.SAGE, 50.0)
				Audio.play("success", -8.0)
				await get_tree().create_timer(0.3).timeout
			"status":
				Fx.float_text(fx_layer, _center(who) + Vector2(0, -130), str(b.text), Style.INK, "", 0.05, 24)
				await get_tree().create_timer(0.22).timeout
			"guarded":
				Fx.float_text(fx_layer, _center(who) + Vector2(0, -130), "covers!", Style.GOLD, "", 0.0, 28)
				if a:
					var tw := a.create_tween()
					tw.tween_property(a, "position:x", a.position.x + 30 * a.face, 0.1)
					tw.tween_property(a, "position:x", a.position.x, 0.2)
				await get_tree().create_timer(0.25).timeout
			"moved":
				_layout(true)
				await get_tree().create_timer(0.35).timeout
			"stunned":
				Fx.float_text(fx_layer, _center(who) + Vector2(0, -120), "stunned — skips", Style.GOLD, "", 0.0, 28)
				await get_tree().create_timer(0.5).timeout
			"fled":
				await _stamp("Escaped! (%d + DEX = %d)" % [int(b.roll), int(b.total)], Style.SAGE, 0.5)
			"flee_fail":
				await _stamp("No way out! (%d + DEX = %d)" % [int(b.roll), int(b.total)], Style.PINK, 0.4)
		overlay.queue_redraw()


func _skill_by_name(f: Dictionary, n: String) -> Dictionary:
	for sk in f.get("skills", []):
		if str(sk.name) == n:
			return sk
	return {}


func _skill_tag(uid: String, text: String) -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Style.box(Style.NOTE, text.length(), 3.0, Style.INK, 2.0, 6.0))
	p.add_child(Style.label(text, 18, Style.body_heavy))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx_layer.add_child(p)
	p.position = _center(uid) + Vector2(-60, -230)
	p.rotation_degrees = randf_range(-4, 4)
	p.modulate.a = 0.0
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.1)
	tw.tween_interval(0.8)
	tw.tween_property(p, "modulate:a", 0.0, 0.3)
	tw.tween_callback(p.queue_free)


func _kill(uid: String) -> void:
	var a: Actor = actors.get(uid)
	if a == null:
		return
	a.dead = true
	a.targetable = false
	Audio.play("fail", -6.0)
	Fx.float_text(fx_layer, _center(uid) + Vector2(0, -160), "falls", Style.INK, "", 0.1, 30)
	await get_tree().create_timer(0.55).timeout
	actors.erase(uid)
	var tw := a.create_tween()
	tw.tween_property(a, "modulate:a", 0.0, 0.25)
	tw.tween_callback(a.queue_free)
	_layout(true)


func _burst(p: Vector2, col: Color, r: float) -> void:
	bursts.append([p, 0.0, col, r])


# ==========================================================================
# finish
# ==========================================================================

func _finish() -> void:
	mode = ""
	_clear_skills()
	var summary := battle.finish()
	var changes := st.battle_over(source, summary)
	var res := str(summary.result)
	var title: String = {"win": "Victory", "lose": "Defeat", "fled": "Retreated"}.get(res, res)
	var col: Color = {"win": Style.YELLOW, "lose": Style.CORAL, "fled": Style.SAND}.get(res, Style.SAND)
	if res == "win":
		Audio.play("levelup", -4.0)
	await _stamp(str(title).to_upper(), col, 0.6)
	# result card
	var cardp := PanelContainer.new()
	cardp.add_theme_stylebox_override("panel", Style.box(Style.NOTE, 33, 8.0, Style.INK, 2.4, 26.0))
	cardp.custom_minimum_size = Vector2(620, 0)
	fx_layer.add_child(cardp)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	cardp.add_child(v)
	v.add_child(Style.hand(str(title), 52, Style.INK))
	var line := ""
	match res:
		"win":
			line = "The field is yours. What they carried goes into your cargo — bring it home." if not source.begins_with("dungeon:") else "The room is yours. Deeper, then."
		"fled":
			line = "You got away, but the day is spent licking wounds."
		"lose":
			line = "%s has fallen." % st.champ.name
	var ll := Style.label(line, 18, Style.body_bold, Style.PENCIL)
	ll.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(ll)
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 8)
	chips.add_theme_constant_override("v_separation", 8)
	v.add_child(chips)
	for ch in changes:
		var c := Card.change_chip(ch)
		if c:
			chips.add_child(c)
	if not summary.lost.is_empty():
		var lost := Style.label("Fallen: " + ", ".join(summary.lost), 17, Style.body_heavy, Style.BAD)
		v.add_child(lost)
	var in_dungeon := source.begins_with("dungeon:") and res != "lose"
	var btn := Style.cta(("Onward" if in_dungeon else "Back to the map") if res != "lose" else "Continue")
	btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	v.add_child(btn)
	await get_tree().process_frame
	cardp.position = Vector2(960, 470) - cardp.size / 2.0
	Fx.pop_in(cardp)
	if auto:
		await get_tree().create_timer(1.5).timeout
	else:
		await btn.pressed
	if in_dungeon:
		Main.go("dungeon", {"from": "battle", "result": res, "changes": changes})
		return
	if source.begins_with("dungeon:"):
		st.leave_dungeon()
	Main.go("world", {"from": "battle", "result": res, "changes": changes})


# ==========================================================================
# drawing
# ==========================================================================

func _process(d: float) -> void:
	time += d
	flicker = sin(time * 9.0) * 0.5 + sin(time * 23.0) * 0.3
	for b in bursts:
		b[1] = float(b[1]) + d * 3.0
	bursts = bursts.filter(func(b): return float(b[1]) < 1.0)
	scene_c.queue_redraw()
	overlay.queue_redraw()


func _draw_overlay() -> void:
	var ink := Style.INK
	# HP bars + status marks under every living fighter
	for f in battle.allies + battle.enemies:
		var a: Actor = actors.get(f.uid)
		if a == null or a.dead:
			continue
		var c := a.position + Vector2(ACTOR_W / 2.0, ACTOR_H - 2)
		var w := 120.0
		var r := Rect2(c + Vector2(-w / 2.0, 0), Vector2(w, 12))
		overlay.draw_rect(r.grow(2), ink)
		overlay.draw_rect(r, Color("#E6DED0"))
		var k := clampf(float(f.hp) / float(f.max_hp), 0.0, 1.0)
		var hc := Style.SAGE.darkened(0.15) if f.side == "ally" else Style.CORAL
		overlay.draw_rect(Rect2(r.position, Vector2(w * k, 12)), hc)
		var font := Style.body_heavy
		overlay.draw_string(font, c + Vector2(-w / 2.0, 10), "%d/%d" % [int(f.hp), int(f.max_hp)], HORIZONTAL_ALIGNMENT_CENTER, w, 12, ink)
		overlay.draw_string_outline(font, c + Vector2(-90, 34), str(f.name), HORIZONTAL_ALIGNMENT_CENTER, 180, 15, 6, Color(ink, 0.8))
		overlay.draw_string(font, c + Vector2(-90, 34), str(f.name), HORIZONTAL_ALIGNMENT_CENTER, 180, 15, Style.NOTE)
		# rank number badge
		var rb := c + Vector2(-w / 2.0 - 18, 6)
		overlay.draw_circle(rb, 12, Style.NOTE)
		overlay.draw_arc(rb, 12, 0, TAU, 14, ink, 2.0, true)
		overlay.draw_string(font, rb + Vector2(-5, 6), str(battle.rank_of(f)), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, ink)
		# statuses
		var s: Dictionary = f.status
		var x := c.x + w / 2.0 + 14
		var y := c.y + 6
		if int(s.bleed[1]) > 0:
			_drop(Vector2(x, y), Color("#B0413E"))
			x += 22
		if s.stun:
			_star(Vector2(x, y), Style.YELLOW)
			x += 22
		if int(s.mark) > 0:
			overlay.draw_arc(Vector2(x, y), 8, 0, TAU, 14, Style.CORAL, 3.0, true)
			overlay.draw_line(Vector2(x - 11, y), Vector2(x + 11, y), Style.CORAL, 2.0, true)
			overlay.draw_line(Vector2(x, y - 11), Vector2(x, y + 11), Style.CORAL, 2.0, true)
			x += 24
		if str(s.guarded_by) != "":
			_shield(Vector2(x, y), Style.POWDER)
			x += 22
		for bf in s.buffs:
			if bf.has("dmg") or bf.has("def"):
				overlay.draw_colored_polygon(PackedVector2Array([Vector2(x, y - 9), Vector2(x + 8, y + 3), Vector2(x - 8, y + 3)]), Style.GOOD)
				x += 18
	# impact starbursts
	for b in bursts:
		var p: Vector2 = b[0]
		var t := float(b[1])
		var rr := float(b[3]) * (0.4 + t)
		var pts := PackedVector2Array()
		for i in 16:
			var ang := TAU * i / 16.0 + 0.2
			pts.append(p + Vector2(cos(ang), sin(ang)) * (rr if i % 2 == 0 else rr * 0.45))
		var col: Color = b[2]
		overlay.draw_colored_polygon(pts, Color(col, 1.0 - t))
		pts.append(pts[0])
		overlay.draw_polyline(pts, Color(ink, 1.0 - t), 3.0, true)


func _drop(p: Vector2, col: Color) -> void:
	overlay.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -10), p + Vector2(7, 2), p + Vector2(0, 9), p + Vector2(-7, 2)]), col)


func _star(p: Vector2, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var ang := TAU * i / 10.0 - PI / 2
		pts.append(p + Vector2(cos(ang), sin(ang)) * (10.0 if i % 2 == 0 else 4.0))
	overlay.draw_colored_polygon(pts, col)
	pts.append(pts[0])
	overlay.draw_polyline(pts, Style.INK, 1.5, true)


func _shield(p: Vector2, col: Color) -> void:
	var pts := PackedVector2Array([p + Vector2(-8, -9), p + Vector2(8, -9), p + Vector2(7, 3), p + Vector2(0, 10), p + Vector2(-7, 3)])
	overlay.draw_colored_polygon(pts, col)
	pts.append(pts[0])
	overlay.draw_polyline(pts, Style.INK, 1.5, true)


## Backdrop: flat colour bands, an ink horizon, scene props, a dark
## foreground frame (graphguide: landscape first, comic framing).
func _draw_scene() -> void:
	var bgt := Art.tex("bg_" + battle.scene)
	if bgt:
		Art.draw_cover(scene_c, bgt, Rect2(Vector2.ZERO, size), time, 0.015)
		# ground band where the fighters stand, so feet read against the art
		scene_c.draw_rect(Rect2(0, GROUND_Y - 30, size.x, 80), Color(0.1, 0.07, 0.12, 0.18))
		return
	var W := 1920.0
	var H := 1080.0
	var ink := Style.INK
	var sky: Array
	var far := Color()
	var ground := Color()
	var night := false
	match battle.scene:
		"night_forest":
			sky = [Color("#3B3A5C"), Color("#4E4C72"), Color("#6A6488")]
			far = Color("#3F4A52")
			ground = Color("#56664E")
			night = true
		"camp_night":
			sky = [Color("#2F3150"), Color("#45456A"), Color("#6B5A78")]
			far = Color("#3A3A4E")
			ground = Color("#6A5E4E")
			night = true
		"road_dusk":
			sky = [Color("#E9A98F"), Color("#F0C49A"), Color("#F5DDAE")]
			far = Color("#B88A86")
			ground = Color("#CDB283")
		_:
			sky = [Color("#E59A86"), Color("#F0BE95"), Color("#F6DDA8")]
			far = Color("#A9A07E")
			ground = Color("#C2B47E")
	var horizon := 560.0
	# sky bands
	for i in sky.size():
		var y0 := horizon * i / sky.size()
		scene_c.draw_rect(Rect2(0, y0, W, horizon / sky.size() + 2), sky[i])
	# sun / moon
	if night:
		scene_c.draw_circle(Vector2(1500, 170), 54, Color("#F5EEDF"))
		scene_c.draw_circle(Vector2(1522, 156), 50, sky[0])
		for i in 40:
			var sp := Vector2(fmod(i * 397.0, W), fmod(i * 131.0, horizon * 0.7))
			var tw := 0.5 + 0.5 * sin(time * 2.0 + i)
			scene_c.draw_circle(sp, 1.6 + tw, Color(1, 1, 0.9, 0.5 + tw * 0.4))
	else:
		scene_c.draw_circle(Vector2(1380, 300), 90, Color("#FBE7B0"))
		scene_c.draw_arc(Vector2(1380, 300), 90, 0, TAU, 40, Color(ink, 0.25), 2.0, true)
		for i in 3:
			var cy := 140.0 + i * 70
			var cx := fmod(200.0 + i * 610 + time * (8 + i * 3), W + 400) - 200
			_cloud(Vector2(cx, cy), 1.0 - i * 0.2)
	# far range of hills / trees
	var fpts := PackedVector2Array([Vector2(0, horizon)])
	for i in 25:
		var x := W * i / 24.0
		fpts.append(Vector2(x, horizon - 100 - sin(i * 1.7) * 36 - sin(i * 0.6) * 46))
	fpts.append(Vector2(W, horizon))
	scene_c.draw_colored_polygon(fpts, far)
	scene_c.draw_polyline(fpts, Color(ink, 0.6), 2.4, true)
	if battle.scene == "night_forest" or battle.scene == "camp_night":
		for i in 18:
			var bx := 40.0 + i * 108 + sin(i * 3.1) * 30
			var bh := 160.0 + fmod(i * 47.0, 90.0)
			var tree := PackedVector2Array([Vector2(bx - 46, horizon + 20), Vector2(bx, horizon + 20 - bh), Vector2(bx + 46, horizon + 20)])
			scene_c.draw_colored_polygon(tree, far.darkened(0.25))
			scene_c.draw_polyline(PackedVector2Array([tree[0], tree[1], tree[2]]), Color(ink, 0.5), 2.0, true)
	# ground
	scene_c.draw_rect(Rect2(0, horizon, W, H - horizon), ground)
	scene_c.draw_rect(Rect2(0, horizon, W, 30), ground.darkened(0.08))
	scene_c.draw_line(Vector2(0, horizon), Vector2(W, horizon), ink, 3.0, true)
	if battle.scene == "road_dusk":
		var road := PackedVector2Array([Vector2(860, horizon), Vector2(1060, horizon), Vector2(1500, H), Vector2(420, H)])
		scene_c.draw_colored_polygon(road, Color("#E3CFA6"))
		scene_c.draw_line(road[0], road[3], Color(ink, 0.5), 2.0, true)
		scene_c.draw_line(road[1], road[2], Color(ink, 0.5), 2.0, true)
		for i in 6:
			var fx := 160.0 + i * 120
			scene_c.draw_line(Vector2(fx, horizon + 40 + i * 6), Vector2(fx, horizon - 6 + i * 6), ink, 5.0, true)
		scene_c.draw_line(Vector2(140, horizon + 10), Vector2(800, horizon + 40), ink, 3.0, true)
	if battle.scene == "camp_night":
		for tx in [480.0, 1500.0]:
			var tent := PackedVector2Array([Vector2(tx - 110, horizon + 60), Vector2(tx, horizon - 70), Vector2(tx + 110, horizon + 60)])
			scene_c.draw_colored_polygon(tent, Color("#8C7A62"))
			scene_c.draw_colored_polygon(PackedVector2Array([Vector2(tx, horizon - 70), Vector2(tx + 110, horizon + 60), Vector2(tx + 20, horizon + 60)]), Color("#6E5F4C"))
			tent.append(tent[0])
			scene_c.draw_polyline(tent, ink, 3.0, true)
		# campfire glow in the gap between the lines
		var fire := Vector2(960, horizon + 90)
		scene_c.draw_circle(fire, 260 + flicker * 12, Color(1.0, 0.7, 0.35, 0.10))
		scene_c.draw_circle(fire, 150 + flicker * 8, Color(1.0, 0.75, 0.4, 0.14))
		var fl := PackedVector2Array([fire + Vector2(-24, 0), fire + Vector2(-8, -50 - flicker * 10), fire + Vector2(2, -24), fire + Vector2(14, -62 + flicker * 8), fire + Vector2(26, 0)])
		scene_c.draw_colored_polygon(fl, Style.CORAL)
		scene_c.draw_polyline(fl, ink, 2.4, true)
		scene_c.draw_line(fire + Vector2(-34, 4), fire + Vector2(34, -4), Color("#6B4E35"), 9.0, true)
	# ground scribbles
	for i in 60:
		var gp := Vector2(fmod(i * 331.0, W), horizon + 50 + fmod(i * 97.0, H - horizon - 60))
		scene_c.draw_line(gp, gp + Vector2(10, -4), Color(ink, 0.18), 2.0, true)
	# ground shadow band where the fighters stand
	scene_c.draw_rect(Rect2(0, GROUND_Y - 10, W, 50), Color(ink, 0.06))
	# foreground framing: dark grass along the bottom, a leaning branch top-left
	var fg := ground.darkened(0.55)
	var gpts := PackedVector2Array([Vector2(0, H)])
	for i in 97:
		var x := W * i / 96.0
		var hgt := 40.0 + fmod(i * 37.0, 50.0) + sin(time * 1.5 + i) * 3
		gpts.append(Vector2(x, H - (hgt if i % 2 == 0 else 14.0)))
	gpts.append(Vector2(W, H))
	scene_c.draw_colored_polygon(gpts, fg)
	var br := PackedVector2Array([Vector2(-20, 0), Vector2(380, 0), Vector2(240, 40), Vector2(80, 120), Vector2(-20, 170)])
	scene_c.draw_colored_polygon(br, Color(fg, 0.85))
	for i in 9:
		var lp := Vector2(30 + i * 40, 30 + sin(i * 1.3) * 26 + sin(time + i) * 2)
		var lv := Vector2(18, 34).rotated(sin(i * 2.1) * 0.6)
		var leaf := PackedVector2Array([lp, lp + lv * 0.5 + lv.orthogonal() * 0.35, lp + lv, lp + lv * 0.5 - lv.orthogonal() * 0.35])
		scene_c.draw_colored_polygon(leaf, Color(fg.lightened(0.12), 0.95))
		scene_c.draw_line(lp, lp + lv, Color(ink, 0.5), 1.5, true)
	# vignette
	if night:
		scene_c.draw_rect(Rect2(0, 0, W, H), Color(0.1, 0.08, 0.2, 0.12))


func _cloud(p: Vector2, s: float) -> void:
	var col := Color(1, 0.98, 0.93, 0.85)
	for o in [Vector2(-50, 6), Vector2(0, -8), Vector2(50, 6), Vector2(20, 12), Vector2(-20, 12)]:
		scene_c.draw_circle(p + o * s, 34 * s, col)
	scene_c.draw_arc(p + Vector2(0, -8) * s, 34 * s, PI * 1.05, PI * 1.95, 12, Color(Style.INK, 0.3), 2.0, true)
