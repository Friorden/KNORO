extends Control
## The world map screen: pan/zoom the isometric map, roll the day's dice,
## preview a route, walk the Champion hex by hex and handle what happens.
##
## Controls: left-click a hex to walk there (after rolling). Drag with the
## right or middle mouse button (or WASD / arrows) to pan. Zoom with + / -
## (main keys or numpad) or the on-screen buttons. The mouse wheel / touchpad
## scroll is ignored on purpose. Space rolls, Enter ends the day, C opens the city.

var st: GameState
var bg: ColorRect
var view := Control.new()
var map := MapView.new()
var token := ChampionToken.new()
var hud := Hud.new()
var modal := Control.new()
var tip := PanelContainer.new()
var tip_label: Label
var side := PanelContainer.new()
var dice: Dice
var roll_btn: Button
var end_btn: Button
var moves_label: Label
var hint_label: Label
var actions := VBoxContainer.new()
var night := ColorRect.new()

var zoom := 1.0
var zoom_target := 1.0
var cam := Vector2.ZERO
var cam_target := Vector2.ZERO
var dragging := false
var drag_from := Vector2.ZERO
var drag_cam := Vector2.ZERO
var drag_moved := false
var walking := false
var busy := false
var _built := false
var _pending_ambush := -1


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _build() -> void:
	_built = true
	st = Game.state
	bg = ColorRect.new()
	bg.color = Color("#47aba9")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(view)
	map.setup(st)
	view.add_child(map)
	token.banner = Style.kingdom_color(st.kingdom)
	token.kingdom = st.kingdom
	map.add_child(token)
	# keep clouds above the token
	map.move_child(map.clouds, map.get_child_count() - 1)
	# colour grade over the world only (the HUD is added later, above it)
	var grade := ColorRect.new()
	grade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gm := ShaderMaterial.new()
	gm.shader = load("res://render/grade_screen.gdshader")
	grade.material = gm
	add_child(grade)
	night.color = Color("#2B2C4A", 0.0)
	night.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	night.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(night)
	add_child(hud)
	hud.zoom_pressed.connect(_on_rail)
	_build_side()
	tip.add_theme_stylebox_override("panel", Style.box(Style.NOTE, 61, 3.0, Style.INK, 1.5, 10.0))
	tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip_label = Style.label("", 15, Style.body_bold)
	tip.add_child(tip_label)
	tip.visible = false
	add_child(tip)
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(modal)
	cam = map.center_of(st.champ.pos)
	cam_target = cam
	zoom = 0.75
	zoom_target = 1.0
	_apply_cam()


func _build_side() -> void:
	side.add_theme_stylebox_override("panel", Style.box(Style.CARD, 71, 4.0, Style.INK, 2.0, 16.0))
	side.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	side.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	side.grow_vertical = Control.GROW_DIRECTION_BEGIN
	side.offset_right = -20
	side.offset_bottom = -18
	side.custom_minimum_size = Vector2(290, 0)
	add_child(side)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	side.add_child(col)
	col.add_child(Style.caps("Today"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	col.add_child(row)
	dice = Dice.make(6, 80)
	row.add_child(dice)
	var mcol := VBoxContainer.new()
	row.add_child(mcol)
	moves_label = Style.hand("Roll to move", 34)
	mcol.add_child(moves_label)
	hint_label = Style.label("", 13, Style.body_bold, Style.PENCIL)
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.custom_minimum_size = Vector2(170, 0)
	mcol.add_child(hint_label)
	roll_btn = Style.cta("Roll the die  ⚄", Style.YELLOW, 26)
	roll_btn.pressed.connect(_on_roll)
	col.add_child(roll_btn)
	actions.add_theme_constant_override("separation", 8)
	col.add_child(actions)
	end_btn = Style.cta("End day  ☾", Style.CORAL, 28)
	end_btn.pressed.connect(_on_end_day)
	col.add_child(end_btn)


func enter(data: Dictionary) -> void:
	if not _built:
		_build()
	st = Game.state
	hud.set_mode("world")
	hud.refresh()
	Audio.music("music_world")
	token.position = _token_spot(st.champ.pos)
	token.dead = not st.alive
	map.refresh_terrain()
	_refresh_side()
	if data.get("from_city", false):
		zoom = 1.5
		zoom_target = 1.0
		cam = map.center_of(st.world.capitals[st.kingdom])
		cam_target = cam
	var from := str(data.get("from", ""))
	if from == "battle":
		_after_battle(data)
	elif from == "dialogue":
		_after_dialogue(data)
	elif from == "week":
		_after_week()
	elif from == "dungeon":
		map.refresh_terrain()
		token.position = _token_spot(st.champ.pos)
	elif from == "load":
		cam = map.center_of(st.champ.pos)
		cam_target = cam
	elif from == "heir" or from == "start":
		cam = map.center_of(st.champ.pos)
		cam_target = cam
		if from == "start":
			_intro_messenger()
	if st.flags.has("envoy_waiting") and not st.flags.has("envoy_done") and st.at_capital() and from != "dialogue":
		_open_envoy()


func leave() -> void:
	tip.visible = false


func _intro_messenger() -> void:
	await get_tree().create_timer(0.8).timeout
	if not st.world.places.has("crossroads"):
		return
	var cr: Vector2i = st.world.places.crossroads
	var rv := st.reveal(cr, 1)
	st.check_discoveries()
	map.animate_reveal(rv)
	busy = true
	var card := Card.open(modal, "A messenger, out of breath", "A %s merchant caravan waits at the Crossroads. It will not stay there forever." % st.kname(st.world.merchant), "crossroads",
		[{"label": "Show me where", "sub": "marked on your map"}], Style.kingdom_color(st.kingdom))
	await card.chosen
	card.close()
	await card.closed
	busy = false
	cam_target = map.center_of(cr)
	map.pulse(cr)
	await get_tree().create_timer(1.6).timeout
	cam_target = map.center_of(st.champ.pos)
	Main.toast("Roll the die, then click a hex to travel")


## Big stamped banner across the top: discoveries, deliveries, ambushes.
func banner(title: String, sub: String = "", col: Color = Style.INK) -> void:
	var p := PanelContainer.new()
	var b := Style.box(Style.NOTE, randi() % 90, 6.0, Style.INK, 2.6, 14.0)
	b.content_margin_left = 30
	b.content_margin_right = 30
	p.add_theme_stylebox_override("panel", b)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var t := Style.hand(title, 46, col)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	if sub != "":
		var sl := Style.label(sub, 18, Style.body_heavy, Style.INK)
		sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(sl)
	p.add_child(v)
	modal.add_sibling(p)
	await get_tree().process_frame
	p.position = Vector2((size.x - p.size.x) / 2.0, 120)
	p.pivot_offset = p.size / 2.0
	p.rotation_degrees = -2.0
	p.scale = Vector2(1.8, 1.8)
	p.modulate.a = 0.0
	var tw := p.create_tween()
	tw.tween_property(p, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(p, "modulate:a", 1.0, 0.12)
	tw.tween_callback(func(): Audio.play("stamp", -3.0))
	tw.tween_interval(1.9)
	tw.tween_property(p, "modulate:a", 0.0, 0.4)
	tw.tween_callback(p.queue_free)


# ------------------------------------------------------------------ camera

## Where the token stands on a hex: centre, or beside the building on a place hex.
func _token_spot(h: Vector2i) -> Vector2:
	var c := map.center_of(h)
	if st.world.tile(h).get("place", "") != "" and st.place_visible(h):
		return c + Vector2(map.size * 0.8, map.size * 0.4)
	return c + Vector2(0, 4)


func _apply_cam() -> void:
	var vs := size if size.x > 0 else get_viewport_rect().size
	map.scale = Vector2(zoom, zoom)
	map.position = (vs / 2.0 - cam * zoom).round()


func _process(delta: float) -> void:
	if not _built:
		return
	var k := 1.0 - pow(0.001, delta)
	zoom = lerpf(zoom, zoom_target, k)
	if absf(zoom - zoom_target) < 0.004:
		zoom = zoom_target          # land exactly on a pixel-friendly level
	cam = cam.lerp(cam_target, k)
	var pan := Vector2.ZERO
	if not busy and modal.get_child_count() == 0:
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): pan.x -= 1
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): pan.x += 1
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): pan.y -= 1
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): pan.y += 1
	if pan != Vector2.ZERO:
		cam_target += pan.normalized() * 620.0 * delta / zoom
	var b := map.bounds()
	cam_target = cam_target.clamp(b.position, b.end)
	_apply_cam()


func _local_map(p: Vector2) -> Vector2:
	return (p - map.position) / zoom


# ------------------------------------------------------------------ input

func _unhandled_input(e: InputEvent) -> void:
	if not visible or not _built or modal.get_child_count() > 0 or Main.menu_open():
		return
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
			return  # scroll / touchpad is deliberately ignored; zoom with + and -
		if mb.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_LEFT]:
			if mb.pressed:
				dragging = true
				drag_moved = false
				drag_from = mb.position
				drag_cam = cam_target
			else:
				var was_drag := drag_moved
				dragging = false
				if mb.button_index == MOUSE_BUTTON_LEFT and not was_drag:
					_click(mb.position)
	elif e is InputEventMouseMotion:
		var mm := e as InputEventMouseMotion
		if dragging:
			var d := mm.position - drag_from
			if d.length() > 6.0:
				drag_moved = true
			if drag_moved:
				cam_target = drag_cam - d / zoom
				cam = cam_target
		_hover(mm.position)
	elif e is InputEventKey and e.pressed and not e.echo:
		var k := e as InputEventKey
		if k.keycode == KEY_SPACE and not roll_btn.disabled:
			_on_roll()
		elif k.keycode in [KEY_ENTER, KEY_KP_ENTER] and not end_btn.disabled:
			_on_end_day()
		elif k.keycode == KEY_C:
			_go_city()
		elif k.keycode == KEY_I:
			open_bag()
		elif k.keycode == KEY_J:
			QuestLog.open(Main.instance.menu_layer)
		elif k.keycode == KEY_ESCAPE and not busy and not walking:
			Menus.pause(Main.instance.menu_layer)
		elif k.keycode in [KEY_PLUS, KEY_EQUAL, KEY_KP_ADD] or k.unicode == 43:
			_zoom_step(1.2)
		elif k.keycode in [KEY_MINUS, KEY_KP_SUBTRACT] or k.unicode == 45:
			_zoom_step(1.0 / 1.2)


## Zoom on the screen centre (keys and on-screen buttons).
const ZOOMS := [0.5, 0.75, 1.0, 1.5, 2.0]


## Steps to the next zoom level up (f > 1) or down; levels keep pixel art crisp.
func _zoom_step(f: float) -> void:
	var i := 0
	var best := 1e9
	for j in ZOOMS.size():
		if absf(ZOOMS[j] - zoom_target) < best:
			best = absf(ZOOMS[j] - zoom_target)
			i = j
	zoom_target = ZOOMS[clampi(i + (1 if f > 1.0 else -1), 0, ZOOMS.size() - 1)]
	Audio.play("click", -10.0)


func _on_rail(t: String) -> void:
	match t:
		"city": _go_city()
		"in": _zoom_step(1.2)
		"out": _zoom_step(1.0 / 1.2)
		"center": cam_target = map.center_of(st.champ.pos)
		"bag": open_bag()
		"quests": QuestLog.open(Main.instance.menu_layer)
		"menu": Menus.pause(Main.instance.menu_layer)


func open_bag() -> void:
	if modal.get_child_count() > 0:
		return
	var inv := InventoryPanel.open(modal)
	inv.used.connect(func(ch): _float_changes(ch); _refresh_side())
	inv.closed.connect(func(): _refresh_side())


func _zoom_at(screen_p: Vector2, f: float) -> void:
	var before := _local_map(screen_p)
	_zoom_step(f)
	# keep the point under the mouse fixed
	var vs := size
	cam_target = before - (screen_p - vs / 2.0) / zoom_target


func _hover(p: Vector2) -> void:
	var h := map.hex_at(_local_map(p))
	if h == map.hover:
		_place_tip(p)
		return
	map.hover = h
	if st.world.has(h) and not walking:
		map.path = st.path_to(h) if st.alive else []
		_show_tip(h, p)
	else:
		map.path = []
		tip.visible = false
	map.refresh_overlay()


func _show_tip(h: Vector2i, p: Vector2) -> void:
	var t := st.world.tile(h)
	var lines: Array[String] = []
	if not st.is_explored(h):
		lines.append("Unexplored")
	else:
		var name := str(t.name) if t.name != "" and (t.place != "" and st.place_visible(h)) else str(t.terrain).capitalize()
		lines.append(name)
		if t.terrain in ["water", "mountain"]:
			lines.append("impassable")
		else:
			var c := st.move_cost(h)
			lines.append("costs %d move%s · %s" % [c, "" if c == 1 else "s", Data.B("danger.band_names")[int(t.band)]])
		if t.road:
			lines.append("road")
		if t.river:
			lines.append("river crossing")
		if t.owner != "":
			lines.append("%s land" % st.kname(t.owner))
		var pi := st.patrol_at(h)
		if pi >= 0 and Hex.distance(h, st.champ.pos) <= 4:
			lines.append("⚔ %s · %d foes" % [str(Data.enemies().groups[st.patrols[pi].group].title), (Data.enemies().groups[st.patrols[pi].group].foes as Array).size()])
		if str(t.get("camp", "")) != "" and st.place_visible(h):
			lines.append("⚔ %d foes guard it" % (Data.enemies().groups[t.camp].foes as Array).size())
	if not map.path.is_empty():
		var last: Dictionary = map.path[-1]
		if st.rolled:
			lines.append("%d of %d moves" % [last.total, st.moves] if last.reachable else "too far today (%d)" % last.total)
		else:
			lines.append("%d moves away" % last.total)
	tip_label.text = "\n".join(lines)
	tip.visible = true
	tip.reset_size()
	_place_tip(p)


func _place_tip(p: Vector2) -> void:
	tip.position = p + Vector2(22, 18)
	if tip.position.x + tip.size.x > size.x - 10:
		tip.position.x = p.x - tip.size.x - 16


# ------------------------------------------------------------------ side panel

func _refresh_side() -> void:
	token.army = st.units().size()
	for c in actions.get_children():
		c.queue_free()
	roll_btn.disabled = st.rolled or not st.alive or busy
	roll_btn.visible = not st.rolled
	end_btn.disabled = busy or walking
	if st.rolled:
		moves_label.text = "%d move%s left" % [st.moves, "" if st.moves == 1 else "s"]
		hint_label.text = "Rolled %d + DEX %d. Click a hex to walk." % [st.roll, st.champ.move_bonus()]
		if st.moves == 0:
			hint_label.text = "No moves left today."
	else:
		moves_label.text = "Roll to move"
		hint_label.text = "1D6 + DEX bonus (+%d)" % st.champ.move_bonus()
	map.show_reach = st.rolled and st.moves > 0 and not walking
	if map.show_reach:
		var f := st.flood(st.moves)
		map.reachable = f.cost
	else:
		map.reachable = {}
	map.refresh_overlay()
	# context actions
	if st.rolled and st.roll <= 2 and st.moves > 0 and not walking:
		var b := Style.button("Camp instead (heal or scout)", Style.SAGE, 15)
		b.pressed.connect(_on_camp)
		actions.add_child(b)
	if st.champ.unspent_points > 0:
		var lb := Style.button("Level up! Spend %d point%s" % [st.champ.unspent_points, "" if st.champ.unspent_points == 1 else "s"], Style.LAVENDER, 15)
		lb.pressed.connect(_on_level_up)
		actions.add_child(lb)
	var here := st.place_interaction(st.champ.pos)
	if here != "" and here != "home" and not walking:
		var ib := Style.button("Look around here", Style.CARD, 15)
		ib.pressed.connect(func(): _do_place(here))
		actions.add_child(ib)
	if st.at_capital():
		var cb := Style.button("Enter the city  ⌂", Style.CARD, 15)
		cb.pressed.connect(_go_city)
		actions.add_child(cb)
	if st.flags.has("envoy_waiting") and not st.flags.has("envoy_done"):
		var eb := Style.label("An envoy from %s waits in your capital." % st.kname(st.world.rival), 13, Style.body_heavy, Style.BAD)
		eb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		eb.custom_minimum_size = Vector2(250, 0)
		actions.add_child(eb)
	hud.refresh()


func _on_roll() -> void:
	if st.rolled or busy or not st.alive:
		return
	busy = true
	roll_btn.disabled = true
	var v := st.roll_moves()
	dice.roll_to(v)
	await dice.landed
	busy = false
	Fx.float_text(self, dice.global_position + Vector2(40, -10), "+%d moves" % st.moves, Style.INK, "moves")
	_refresh_side()
	if map.hover != Vector2i(-999, -999):
		map.path = st.path_to(map.hover)


# ------------------------------------------------------------------ walking

func _click(p: Vector2) -> void:
	if busy or walking or not st.alive:
		return
	var h := map.hex_at(_local_map(p))
	if h == st.champ.pos:
		var here := st.place_interaction(h)
		if here != "" and here != "home":
			_do_place(here)
		elif here == "home":
			_go_city()
		return
	if not st.rolled:
		Main.toast("Roll the die first")
		Fx.shake(roll_btn, 6.0)
		return
	var path := st.path_to(h)
	if path.is_empty():
		Main.toast("Can't get there")
		return
	var steps: Array = path.filter(func(s): return s.reachable)
	if steps.is_empty():
		Main.toast("Too far for today")
		return
	_walk(steps)


func _walk(steps: Array) -> void:
	walking = true
	map.path = []
	tip.visible = false
	_refresh_side()
	for s in steps:
		var res := st.step(s.h)
		if not res.ok:
			break
		Audio.play("step", -4.0)
		var tw := token.hop(_token_spot(s.h))
		cam_target = cam_target.lerp(map.center_of(s.h), 0.55)
		map.animate_reveal(res.revealed)
		moves_label.text = "%d move%s left" % [st.moves, "" if st.moves == 1 else "s"]
		await tw.finished
		map.refresh_terrain()
		hud.refresh()
		for n in res.get("discovered", []):
			banner(str(n).to_upper() + " DISCOVERED", "the map remembers", Style.GOLD)
			Audio.play("success", -8.0)
			await get_tree().create_timer(0.5).timeout
		if not res.get("delivered", {}).is_empty():
			var parts: Array[String] = []
			for k in res.delivered.keys():
				parts.append("+%d %s" % [int(res.delivered[k]), k])
			banner("CARGO DELIVERED", "%s → %s Kingdom" % ["  ".join(parts), st.kname(st.kingdom)], Style.GOOD)
			Audio.play("coin")
			var cap := map.to_global(map.center_of(st.world.capitals[st.kingdom]))
			var dd := 0.0
			for k in res.delivered.keys():
				Fx.float_text(self, cap + Vector2(0, -40), "+%d" % int(res.delivered[k]), Style.GOOD, k, dd)
				dd += 0.2
		if res.get("battle", "") != "":
			walking = false
			await _patrol_encounter(int(str(res.battle).substr(7)))
			break
		if res.place == "home":
			break
		if str(res.place).begins_with("camp:"):
			walking = false
			await _camp_encounter(str(res.place).substr(5))
			break
		if str(res.place).begins_with("dungeon:"):
			walking = false
			Main.go("dungeon", {"id": str(res.place).substr(8), "wipe_from": _screen_uv(token.global_position)})
			break
		if res.place != "":
			walking = false
			await _do_place(res.place)
			break
		if res.event != "":
			walking = false
			await _do_event(res.event)
			if not st.alive:
				break
			# remaining steps are dropped; the player re-plans with what's left
			break
		if st.moves <= 0:
			break
	walking = false
	_refresh_side()
	if not st.alive:
		_on_death()
	elif st.flags.has("envoy_waiting") and not st.flags.has("envoy_done") and st.at_capital():
		_open_envoy()


# ------------------------------------------------------------------ events & places

func _event_options(e: Dictionary) -> Array:
	var opts: Array = []
	for o in e.options:
		var sub := ""
		var enabled := true
		if o.has("check"):
			var bonus := st.champ.attr(o.check.attr)
			sub = "%s check · DC %d · %d%%" % [o.check.attr, int(o.check.dc), GameState.chance(bonus, int(o.check.dc))]
		elif o.has("combat"):
			sub = "fight · %d in your band" % st.party.size()
		if o.has("cost"):
			var parts: Array[String] = []
			for k in o.cost.keys():
				parts.append("%d %s" % [int(o.cost[k]), k])
			sub = "costs " + ", ".join(parts) + " from cargo"
			enabled = st.can_afford(o.cost, "cargo")
		if o.has("needs_item"):
			var nid := str(o.needs_item)
			var nm := str(Champion.item(nid).get("name", nid))
			var have := st.champ.has_item(nid)
			sub = ("uses your %s" % nm.to_lower()) if o.get("consume", false) else ("needs %s" % nm.to_lower())
			if not have:
				sub = "you have no %s" % nm.to_lower()
			enabled = enabled and have
		opts.append({"label": st.fmt(str(o.label)), "sub": sub, "enabled": enabled, "special": o.has("check") or o.has("needs_item")})
	return opts


func _do_event(id: String) -> void:
	busy = true
	var e: Dictionary = Data.events()[id]
	map.pulse(st.champ.pos)
	Audio.play("scratch", -6.0)
	var card := Card.open(modal, st.fmt(e.title), st.fmt(e.text), str(e.art), _event_options(e), Style.kingdom_color(st.kingdom))
	var idx: int = await card.chosen
	var res := st.resolve_event(id, idx)
	if res.combat != "" and res.check.is_empty() and res.text == "":
		card.close()
		await card.closed
		busy = false
		_start_combat(res.combat)
		return
	card.show_result(res)
	await card.closed
	_float_changes(res.changes)
	busy = false
	if res.combat != "":
		_start_combat(res.combat)
		return
	_refresh_side()


func _do_place(kind: String) -> void:
	if kind.begins_with("dialogue:"):
		Main.go("dialogue", {"id": kind.substr(9), "wipe_from": _screen_uv(token.global_position)})
		return
	busy = true
	var h := st.champ.pos
	var t := st.world.tile(h)
	var tint := Style.kingdom_color(st.kingdom)
	match kind:
		"card:outpost", "card:iron":
			var cost: Dictionary = Data.B("outpost.cost", {"wood": 10})
			var txt := "A seam of good grey stone breaks the hillside. Nobody's banner flies here." if kind == "card:outpost" else "Dark rock streaked with rust-red. Iron, if you know what you're looking at."
			if kind == "card:outpost" and st.flags.has("heard_deposit"):
				txt += " This must be the rock Tobbin talked about."
			var card := Card.open(modal, str(t.name), txt, "outpost" if kind == "card:outpost" else "iron",
				[{"label": "Raise an outpost and plant the %s banner" % st.kname(st.kingdom), "sub": "costs %d wood · ends your day" % int(cost.get("wood", 10)), "enabled": st.can_afford(cost), "special": true},
				{"label": "Leave it for now", "sub": ""}], tint)
			var idx: int = await card.chosen
			if idx == 0:
				var r := st.plant_outpost()
				Audio.play("build")
				map.refresh_terrain()
				var extra := ""
				if t.deposit == "stone":
					extra = " A Quarry can now be built in your capital. %s will not be pleased." % st.kname(st.world.rival)
				else:
					extra = " Iron now flows to your capital: smiths, foundries and better gear need it."
				card.show_result({"text": "Your banner goes up over %s.%s" % [t.name, extra], "changes": r.get("changes", [])})
				await card.closed
				_float_changes(r.get("changes", []))
			else:
				card.close()
				await card.closed
		"card:cove":
			var card := Card.open(modal, "Smugglers' cove", "A rotten boat, a rope ladder, and a strongbox nobody came back for.", "cove", [{"label": "Open the strongbox", "sub": ""}], tint)
			await card.chosen
			var ch := st.loot_cove()
			card.show_result({"text": "Forty gold in old coins. The capital will put it to better use.", "changes": ch})
			await card.closed
			_float_changes(ch)
		"card:tower":
			var card := Card.open(modal, "Old watchtower", "Two hundred worn steps. From the top you'd see half the world.", "tower", [{"label": "Climb it", "sub": ""}, {"label": "Not today", "sub": ""}], tint)
			var idx: int = await card.chosen
			if idx == 0:
				var ch := st.climb_tower()
				card.show_result({"text": "Wind, birds, and the whole map laid out like a quilt.", "changes": ch})
				await card.closed
				_float_changes(ch)
			else:
				card.close()
				await card.closed
		_:
			var msgs := {
				"card:crossroads_quiet": ["The Crossroads", "Cart ruts and an empty signpost. The caravan has moved on.", "crossroads"],
				"card:ruins_done": ["Old ruins", "The stones have told you what they know.", "ruins"],
				"card:own_outpost": [str(t.name), "Your banner snaps in the wind. Your people work the rock.", "outpost"],
				"card:empty_cove": ["Smugglers' cove", "Only the rotten boat is left.", "cove"],
				"card:tower_done": ["Old watchtower", "You've seen what there is to see from up there.", "tower"],
				"card:dungeon_done": [str(t.name), "Quiet now. Only the drip of water and your own footsteps.", "ruins"],
			}
			var m: Array = msgs.get(kind, ["Here", "Nothing happens.", "home"])
			var card := Card.open(modal, m[0], m[1], m[2], [{"label": "Carry on", "sub": ""}], tint)
			await card.chosen
			card.close()
			await card.closed
	busy = false
	_refresh_side()


func _float_changes(changes: Array) -> void:
	var p := token.global_position + Vector2(0, -60)
	var d := 0.0
	for ch in changes:
		if ch.kind in ["food", "wood", "stone", "gold", "iron", "hp", "xp"]:
			var amt := int(ch.amount)
			var suffix := " → CARGO" if str(ch.get("to", "")) == "cargo" and amt > 0 else ""
			Fx.float_text(self, p, "%+d%s" % [amt, suffix], Style.GOOD if amt >= 0 else Style.BAD, ch.kind, d)
			d += 0.18
		elif ch.kind == "level":
			Audio.play("levelup")
			Fx.float_text(self, p, "Level %d!" % int(ch.amount), Color("#6A4FA3"), "xp", d, 36)
			d += 0.2
		elif ch.kind == "reveal":
			map.animate_reveal(ch.get("hexes", []))
			map.refresh_terrain()
	hud.refresh()


func _screen_uv(p: Vector2) -> Vector2:
	var vs := get_viewport_rect().size
	return Vector2(p.x / vs.x, p.y / vs.y)


func _start_combat(group: String, source: String = "event") -> void:
	Main.go("battle", {"group": group, "source": source, "wipe_from": _screen_uv(token.global_position)})


func _army_line() -> String:
	var us := st.units()
	if us.is_empty():
		return "You're alone: %s, %d/%d HP." % [st.champ.name, st.champ.hp, st.champ.max_hp()]
	var names: Array[String] = []
	for u in us:
		names.append(st.unit_stats(u).name)
	return "%s and %d soldier%s: %s." % [st.champ.name, us.size(), "" if us.size() == 1 else "s", ", ".join(names)]


func _group_line(group: String) -> String:
	var g: Dictionary = Data.enemies().groups[group]
	var names: Array[String] = []
	for f in g.foes:
		names.append(str(Data.enemies().foes[f].name))
	return "%d foes: %s." % [names.size(), ", ".join(names)]


func _patrol_encounter(i: int) -> void:
	busy = true
	var p: Dictionary = st.patrols[i]
	var g: Dictionary = Data.enemies().groups[p.group]
	var card := Card.open(modal, "%s on the road!" % str(g.title), "%s\n%s" % [_group_line(p.group), _army_line()], "bandits" if p.group != "wolves" else "wolves",
		[{"label": "Fight", "sub": "battle · loot goes to your cargo", "special": true},
		{"label": "Try to slip away", "sub": "DEX check · DC 12 · %d%%" % GameState.chance(st.champ.attr("DEX"), 12)}], Style.kingdom_color(st.kingdom))
	var idx: int = await card.chosen
	if idx == 1:
		var c := st.check("DEX", 12)
		if c.success:
			st.apply({"end_day": true}, "slip away")
			card.show_result({"check": c, "text": "You leave the road and lose them in the brush. The day is spent.", "changes": []})
			await card.closed
			busy = false
			_refresh_side()
			return
		card.show_result({"check": c, "text": "They've seen you. No way around it.", "changes": []})
		await card.closed
	else:
		card.close()
		await card.closed
	busy = false
	_start_combat(p.group, "patrol:%d" % i)


func _camp_encounter(pid: String) -> void:
	busy = true
	var h: Vector2i = st.world.places[pid]
	var t := st.world.tile(h)
	var group := str(t.camp)
	var g: Dictionary = Data.enemies().groups[group]
	var loot: Array[String] = []
	for k in g.loot.keys():
		loot.append("%d %s" % [int(g.loot[k]), k])
	var card := Card.open(modal, str(t.name), "%s\nSpoils: %s.\n%s" % [_group_line(group), ", ".join(loot), _army_line()], "bandits" if group == "bandit_camp" else "wolves",
		[{"label": "Attack", "sub": "a hard fight · bring an army", "special": true}, {"label": "Not today", "sub": ""}], Style.kingdom_color(st.kingdom))
	var idx: int = await card.chosen
	card.close()
	await card.closed
	busy = false
	if idx == 0:
		_start_combat(group, "camp:" + pid)


func _after_battle(data: Dictionary) -> void:
	var result := str(data.get("result", ""))
	token.position = _token_spot(st.champ.pos)
	if result == "lose":
		_on_death()
		return
	_float_changes(data.get("changes", []))
	if st.at_capital():
		var moved := st.deliver_cargo()
		if not moved.is_empty():
			Main.toast("Cargo unloaded at home")
			Game.touch()
	_refresh_side()


func _after_dialogue(data: Dictionary) -> void:
	map.refresh_terrain()
	_refresh_side()
	for ch in data.get("changes", []):
		if ch.kind == "reveal":
			map.animate_reveal(ch.get("hexes", []))
	if not st.alive:
		_on_death()


func _after_week() -> void:
	_refresh_side()
	if _pending_ambush >= 0:
		var i := _pending_ambush
		_pending_ambush = -1
		await get_tree().create_timer(0.6).timeout
		banner("AMBUSH!", "%s caught up with you in the night" % str(Data.enemies().groups[st.patrols[i].group].title).to_lower(), Style.BAD)
		await get_tree().create_timer(1.4).timeout
		_start_combat(st.patrols[i].group, "patrol:%d" % i)
		return
	if st.quests.get("m8_city", {}).get("state", "") == "done" and not Game.demo_end_shown:
		Game.demo_end_shown = true
		Main.go("end")
		return
	_post_day_notices()


func _open_envoy() -> void:
	await get_tree().create_timer(0.4).timeout
	Main.toast("An envoy from %s is waiting for you" % st.kname(st.world.rival), Style.BAD)
	await get_tree().create_timer(1.2).timeout
	Main.go("dialogue", {"id": "envoy"})


func _on_camp() -> void:
	busy = true
	var card := Card.open(modal, "Make camp", "A short roll. Not much road today, but a quiet evening is worth something.", "camp",
		[{"label": "Rest and tend your wounds", "sub": "+%d HP" % int(Data.B("champion.camp_heal", 3))},
		{"label": "Climb a rise and scout around", "sub": "reveal radius %d" % int(Data.B("champion.camp_scout_radius", 3))},
		{"label": "Never mind", "sub": ""}], Style.kingdom_color(st.kingdom))
	var idx: int = await card.chosen
	if idx == 2:
		card.close()
		await card.closed
	else:
		var ch := st.camp("heal" if idx == 0 else "scout")
		card.show_result({"text": "The fire crackles. Tomorrow's another roll.", "changes": ch})
		await card.closed
		_float_changes(ch)
	busy = false
	_refresh_side()


func _on_level_up() -> void:
	busy = true
	var opts: Array = []
	for a in Champion.ATTRS:
		var v := st.champ.attr(a)
		opts.append({"label": "%s  %d → %d" % [Champion.ATTR_NAMES[a], v, v + 1], "sub": Champion.ATTR_DESC[a], "enabled": v < int(Data.B("champion.attr_max", 20))})
	opts.append({"label": "Later", "sub": ""})
	var card := Card.open(modal, "%s grows" % st.champ.name, "Level %d. Every road leaves a mark. Where did this one leave it?" % st.champ.level, "", opts)
	var idx: int = await card.chosen
	if idx < Champion.ATTRS.size():
		var a: String = Champion.ATTRS[idx]
		st.champ.attrs[a] = st.champ.attr(a) + 1
		st.champ.unspent_points -= 1
		Audio.play("levelup")
		card.show_result({"text": "%s +1. %s is now %s." % [Champion.ATTR_NAMES[a], st.champ.name, st.champ.archetype()], "changes": []})
		await card.closed
	else:
		card.close()
		await card.closed
	busy = false
	_refresh_side()


func _go_city() -> void:
	if busy or walking:
		return
	Main.go("city", {"wipe_from": _screen_uv(map.to_global(map.center_of(st.world.capitals[st.kingdom])))})


# ------------------------------------------------------------------ day end

func _on_end_day() -> void:
	if busy or walking:
		return
	busy = true
	end_btn.disabled = true
	map.path = []
	map.show_reach = false
	map.refresh_overlay()
	Audio.play("bell_day", -4.0)
	var tw := create_tween()
	tw.tween_property(night, "color:a", 0.42, 0.7).set_trans(Tween.TRANS_SINE)
	await tw.finished
	var rep := st.end_day()
	if rep.week_end:
		var nq := st.offer_side_quest()
		if nq != "":
			rep.week_report["new_quest"] = nq
	Game.touch()
	if Settings.autosave and st.alive:
		SaveGame.save(st, "auto")
	# production floats over the capital
	var cap := map.to_global(map.center_of(st.world.capitals[st.kingdom]))
	var d := 0.0
	for r in ["food", "wood", "stone", "gold", "iron"]:
		var v: int = rep.prod[r]
		if r == "food":
			v -= int(rep.eaten)
		if v != 0:
			Fx.float_text(self, cap + Vector2(randf_range(-30, 30), -30), "%+d" % v, Style.GOOD if v > 0 else Style.BAD, r, d)
			d += 0.2
	if d > 0:
		Audio.play("coin", -6.0)
	hud.refresh()
	await get_tree().create_timer(0.9).timeout
	var tw2 := create_tween()
	tw2.tween_property(night, "color:a", 0.0, 0.8).set_trans(Tween.TRANS_SINE)
	Main.toast("Week %d · Day %d" % [st.week(), st.day_in_week()])
	if rep.starving:
		Main.toast("The granary is empty. People are going hungry.", Style.BAD)
	if rep.tobbin_left:
		await get_tree().create_timer(0.6).timeout
		Main.toast("The caravan at the Crossroads has moved on")
	busy = false
	_refresh_side()
	if not str(rep.get("deserted", "")).is_empty():
		Main.toast("A hungry %s deserted the army" % str(rep.deserted).to_lower(), Style.BAD)
	if int(rep.get("ambush", -1)) >= 0 and rep.week_end:
		_pending_ambush = int(rep.ambush)
	elif int(rep.get("ambush", -1)) >= 0:
		await get_tree().create_timer(0.5).timeout
		banner("AMBUSH!", "%s caught up with you in the night" % str(Data.enemies().groups[st.patrols[int(rep.ambush)].group].title).to_lower(), Style.BAD)
		await get_tree().create_timer(1.4).timeout
		_start_combat(st.patrols[int(rep.ambush)].group, "patrol:%d" % int(rep.ambush))
		return
	if rep.week_end:
		await get_tree().create_timer(0.5).timeout
		Main.go("week", {"report": rep.week_report})
		return
	_post_day_notices(rep)


func _post_day_notices(rep: Dictionary = {}) -> void:
	if rep.get("envoy", false) or (st.flags.has("envoy_waiting") and not st.flags.has("envoy_done")):
		if st.at_capital():
			_open_envoy()
		elif rep.get("envoy", false):
			await get_tree().create_timer(0.7).timeout
			Main.toast("An envoy from %s waits in your capital" % st.kname(st.world.rival), Style.BAD)
	_refresh_side()


func _on_death() -> void:
	st.champion_died()
	token.dead = true
	busy = true
	Audio.play("fail")
	await get_tree().create_timer(0.8).timeout
	busy = false
	Main.go("heir")
