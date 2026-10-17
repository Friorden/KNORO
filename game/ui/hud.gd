class_name Hud
extends Control
## Top resource bar, the Champion card and the World/City zoom rail.
## Shared by the world and city screens. Refreshes on Game.changed.

signal zoom_pressed(target: String)

var top := PanelContainer.new()
var res_labels: Dictionary = {}
var res_delta: Dictionary = {}
var day_label: Label
var weather_label: Label
var kname: Label
var flag: Control
var pop_label: Label
var champ_card := PanelContainer.new()
var c_name: Label
var c_level: Label
var hp_bar: Control
var xp_bar: Control
var c_hp_text: Label
var c_gear: Label
var portrait: Control
var age_label: Label
var cargo_row := HBoxContainer.new()
var army_row := HBoxContainer.new()
var rail := PanelContainer.new()
var rail_world: Button
var rail_city: Button
var zoom_box: VBoxContainer
var mode := "world"
var _last: Dictionary = {}
var tracker := PanelContainer.new()
var tracker_box := VBoxContainer.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_top()
	_build_champ()
	_build_rail()
	_build_tracker()
	Game.changed.connect(refresh)
	Game.quest_done.connect(_on_quest_done)
	refresh()


func _build_top() -> void:
	top.add_theme_stylebox_override("panel", Style.box(Style.CARD, 21, 3.0, Style.INK, 2.0, 10.0))
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 20
	top.offset_right = -20
	top.offset_top = 14
	add_child(top)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	top.add_child(row)
	flag = Control.new()
	flag.custom_minimum_size = Vector2(26, 34)
	flag.draw.connect(func():
		var col := Style.kingdom_color(Game.state.kingdom) if Game.state else Style.CORAL
		var pts := PackedVector2Array([Vector2(2, 0), Vector2(24, 0), Vector2(24, 32), Vector2(13, 25), Vector2(2, 32)])
		flag.draw_colored_polygon(pts, col)
		var o := pts.duplicate()
		o.append(pts[0])
		flag.draw_polyline(o, Style.INK, 2.0, true))
	row.add_child(flag)
	kname = Style.hand("Red Kingdom", 28)
	row.add_child(kname)
	var chip := PanelContainer.new()
	var cb := Style.box(Style.YELLOW, 22, 0.0, Style.INK, 1.5, 4.0)
	cb.content_margin_left = 12
	cb.content_margin_right = 12
	chip.add_theme_stylebox_override("panel", cb)
	chip.rotation_degrees = -2
	day_label = Style.hand("Week 1 · Day 1", 24)
	chip.add_child(day_label)
	row.add_child(chip)
	var achip := PanelContainer.new()
	var ab := Style.box(Style.LAVENDER, 25, 0.0, Style.INK, 1.5, 4.0)
	ab.content_margin_left = 10
	ab.content_margin_right = 10
	achip.add_theme_stylebox_override("panel", ab)
	achip.rotation_degrees = 1.5
	achip.tooltip_text = "Your age. Advance it in the City (Age tab)."
	age_label = Style.label("Age I", 15, Style.body_heavy)
	achip.add_child(age_label)
	row.add_child(achip)
	weather_label = Style.label("", 14, Style.body_bold, Style.PENCIL)
	row.add_child(weather_label)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sp)
	for r in ["food", "wood", "stone", "gold", "iron"]:
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 6)
		box.tooltip_text = r.capitalize()
		box.mouse_filter = Control.MOUSE_FILTER_PASS
		box.add_child(ResIcon.make(r, 24))
		var v := Style.label("0", 21, Style.body_heavy)
		box.add_child(v)
		var d := Style.label("+0", 14, Style.body_bold, Style.GOOD)
		box.add_child(d)
		res_labels[r] = v
		res_delta[r] = d
		row.add_child(box)
	var pb := HBoxContainer.new()
	pb.add_theme_constant_override("separation", 6)
	pb.add_child(ResIcon.make("pop", 24))
	pop_label = Style.label("6", 19, Style.body_heavy)
	pb.add_child(pop_label)
	row.add_child(pb)


func _build_champ() -> void:
	champ_card.add_theme_stylebox_override("panel", Style.box(Style.CARD, 23, 3.0, Style.INK, 2.0, 12.0))
	champ_card.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	champ_card.offset_left = 20
	champ_card.offset_bottom = -18
	champ_card.offset_top = -170
	champ_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(champ_card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	champ_card.add_child(row)
	portrait = Control.new()
	portrait.custom_minimum_size = Vector2(56, 74)
	portrait.draw.connect(func():
		if _pixel:
			var av := PixelUI.tex("avatar_%02d" % {"blue": 1, "red": 6, "yellow": 11}.get(Game.state.kingdom if Game.state else "red", 6))
			portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			portrait.draw_texture_rect_region(av, Rect2(0, 0, 84, 84), Rect2(36, 30, 184, 184))
			return
		var col := Style.kingdom_color(Game.state.kingdom) if Game.state else Style.CORAL
		DrawKit.person(portrait, Vector2(28, 66), 2.2, col, 0.0))
	row.add_child(portrait)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	row.add_child(col)
	var nr := HBoxContainer.new()
	nr.add_theme_constant_override("separation", 10)
	c_name = Style.hand("Mira", 28)
	nr.add_child(c_name)
	c_level = Style.label("Lv 1", 15, Style.body_heavy, Style.PENCIL)
	nr.add_child(c_level)
	col.add_child(nr)
	hp_bar = _bar(Style.SAGE)
	col.add_child(hp_bar)
	c_hp_text = Style.label("16/16 HP", 13, Style.body_bold, Style.PENCIL)
	col.add_child(c_hp_text)
	xp_bar = _bar(Style.LAVENDER, 6)
	col.add_child(xp_bar)
	c_gear = Style.label("", 13, Style.body_bold, Style.PENCIL)
	col.add_child(c_gear)
	col.add_child(HSeparator.new())
	cargo_row.add_theme_constant_override("separation", 6)
	cargo_row.tooltip_text = "Cargo: what the Champion carries. Loot lands here and reaches the kingdom when you walk into your capital."
	cargo_row.mouse_filter = Control.MOUSE_FILTER_PASS
	col.add_child(cargo_row)
	army_row.add_theme_constant_override("separation", 4)
	army_row.tooltip_text = "Your war band, rank 1 first (5 slots: Champion + 4). Recruit at the Barracks."
	army_row.mouse_filter = Control.MOUSE_FILTER_PASS
	col.add_child(army_row)


func _bar(fill: Color, h: float = 11.0) -> Control:
	var b := Control.new()
	b.custom_minimum_size = Vector2(190, h)
	b.set_meta("v", 1.0)
	b.set_meta("fill", fill)
	b.draw.connect(func():
		var v: float = b.get_meta("v")
		var f: Color = b.get_meta("fill")
		var r := Rect2(Vector2.ZERO, b.size)
		b.draw_rect(r, Style.PAPER)
		b.draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(v, 0, 1), r.size.y)), f)
		b.draw_rect(r, Style.INK, false, 1.6))
	return b


func _build_rail() -> void:
	rail.add_theme_stylebox_override("panel", Style.box(Style.CARD, 24, 3.0, Style.INK, 2.0, 8.0))
	rail.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	rail.offset_left = 20
	rail.offset_top = -170
	add_child(rail)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	rail.add_child(col)
	rail_world = Style.button("World", Style.CARD, 14)
	rail_world.custom_minimum_size = Vector2(76, 44)
	rail_world.tooltip_text = "The world map"
	rail_world.pressed.connect(func(): zoom_pressed.emit("world"))
	col.add_child(rail_world)
	var dots := Style.hand("⋮", 22, Style.PENCIL)
	dots.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(dots)
	rail_city = Style.button("City", Style.CARD, 14)
	rail_city.custom_minimum_size = Vector2(76, 44)
	rail_city.tooltip_text = "Your capital (C)"
	rail_city.pressed.connect(func(): zoom_pressed.emit("city"))
	col.add_child(rail_city)
	zoom_box = VBoxContainer.new()
	zoom_box.add_theme_constant_override("separation", 6)
	col.add_child(zoom_box)
	zoom_box.add_child(HSeparator.new())
	for z in [["＋", "in", "Zoom in (+)"], ["−", "out", "Zoom out (-)"], ["⌖", "center", "Back to your Champion"]]:
		var b := Style.button(z[0], Style.CARD, 22)
		b.custom_minimum_size = Vector2(76, 44)
		b.tooltip_text = z[2]
		var key: String = z[1]
		b.pressed.connect(func(): zoom_pressed.emit(key))
		zoom_box.add_child(b)
	var bag := Style.button("Bag", Style.LAVENDER, 14)
	bag.custom_minimum_size = Vector2(76, 44)
	bag.tooltip_text = "Equipment and bag (I)"
	bag.pressed.connect(func(): zoom_pressed.emit("bag"))
	col.add_child(bag)
	var qb := Style.button("Quests", Style.LAVENDER, 14)
	qb.custom_minimum_size = Vector2(76, 44)
	qb.tooltip_text = "Quest log (J)"
	qb.pressed.connect(func(): zoom_pressed.emit("quests"))
	col.add_child(qb)
	var mb := Style.button("Menu", Style.CARD, 14)
	mb.custom_minimum_size = Vector2(76, 44)
	mb.tooltip_text = "Pause, save, settings (Esc)"
	mb.pressed.connect(func(): zoom_pressed.emit("menu"))
	col.add_child(mb)


## Quest tracker under the top bar on the right: current main quest + two side quests.
func _build_tracker() -> void:
	tracker.add_theme_stylebox_override("panel", PixelUI.box("nine_paper", Vector4(22, 14, 22, 16)))
	tracker.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	tracker.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	tracker.offset_right = -20
	tracker.offset_top = 112
	tracker.custom_minimum_size = Vector2(330, 0)
	tracker.mouse_filter = Control.MOUSE_FILTER_STOP
	tracker.tooltip_text = "Open the quest log (J)"
	tracker.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			zoom_pressed.emit("quests"))
	add_child(tracker)
	tracker_box.add_theme_constant_override("separation", 3)
	tracker.add_child(tracker_box)


func _refresh_tracker(st: GameState) -> void:
	for c in tracker_box.get_children():
		c.queue_free()
	var lines := QuestLog.tracker_lines(st)
	tracker.visible = mode == "world" and not lines.is_empty()
	for q in lines:
		var t := PixelUI.label(("★ " if q.main else "• ") + str(q.title), 17 if q.main else 15, PixelUI.VIOLET if q.main else PixelUI.INK)
		tracker_box.add_child(t)
		for o in q.objs:
			var l := PixelUI.label(("   ■ " if o[1] else "   □ ") + str(o[0]), 14, PixelUI.GOOD if o[1] else PixelUI.MUTED)
			tracker_box.add_child(l)


func _on_quest_done(info: Dictionary) -> void:
	Audio.play("levelup", -6.0)
	var parts: Array[String] = []
	for ch in info.get("changes", []):
		if ch.kind in ["food", "wood", "stone", "gold", "iron", "xp"]:
			parts.append("%+d %s" % [int(ch.amount), ch.kind])
		elif ch.kind == "item":
			parts.append(str(ch.label))
	Main.toast("Quest done: %s  %s" % [str(info.title), ("(" + ", ".join(parts) + ")") if not parts.is_empty() else ""], PixelUI.GOOD)
	var nxt := str(Game.state.quest_def(str(info.id)).get("next", ""))
	if nxt != "":
		await get_tree().create_timer(2.4).timeout
		Main.toast("New quest: %s" % str(Game.state.quest_def(nxt).get("title", nxt)), PixelUI.VIOLET)


var _pixel := false


## Swaps the HUD between the sketch look (world) and the Tiny Swords look (city).
func _skin(px: bool) -> void:
	if px == _pixel:
		return
	_pixel = px
	for p in [top, champ_card, rail]:
		if not p.has_meta("orig_panel"):
			p.set_meta("orig_panel", p.get_theme_stylebox("panel"))
		p.add_theme_stylebox_override("panel", PixelUI.box("nine_paper", Vector4(20, 14, 20, 14)) if px else p.get_meta("orig_panel"))
	_skin_walk(self, px)
	if portrait:
		portrait.custom_minimum_size = Vector2(84, 84) if px else Vector2(56, 74)
		portrait.queue_redraw()


func _skin_walk(n: Node, px: bool) -> void:
	for c in n.get_children():
		if c is Label:
			if not c.has_meta("orig_font"):
				c.set_meta("orig_font", c.get_theme_font("font"))
				c.set_meta("orig_col", c.get_theme_color("font_color"))
			c.add_theme_font_override("font", PixelUI.font() if px else c.get_meta("orig_font"))
			var oc: Color = c.get_meta("orig_col")
			c.add_theme_color_override("font_color", (PixelUI.INK if oc.is_equal_approx(Style.INK) else oc) if px else oc)
		elif c is Button:
			if not c.has_meta("orig_font"):
				c.set_meta("orig_font", c.get_theme_font("font"))
				for k in ["normal", "hover", "pressed", "hover_pressed"]:
					c.set_meta("orig_" + k, c.get_theme_stylebox(k))
			c.add_theme_font_override("font", PixelUI.font() if px else c.get_meta("orig_font"))
			for k in ["normal", "hover", "pressed", "hover_pressed"]:
				var pb := PixelUI.box({"normal": "nine_paper", "hover": "btn_hover", "pressed": "btn_hover", "hover_pressed": "btn_hover"}[k], Vector4(10, 6, 10, 8))
				c.add_theme_stylebox_override(k, pb if px else c.get_meta("orig_" + k))
		_skin_walk(c, px)


func set_mode(m: String) -> void:
	mode = m
	_skin(true)
	if Game.state:
		_refresh_tracker(Game.state)
	if zoom_box:
		zoom_box.visible = m in ["world", "city"]
	var on: StyleBox = PixelUI.box("btn_hover", Vector4(10, 6, 10, 8)) if _pixel else Style.box(Style.kingdom_color(Game.state.kingdom, "tint") if Game.state else Style.PINK, 3, 0.0, Style.INK, 2.0, 8.0)
	for pair in [[rail_world, "world"], [rail_city, "city"]]:
		var b: Button = pair[0]
		if pair[1] == m:
			b.add_theme_stylebox_override("normal", on)
		elif _pixel:
			b.add_theme_stylebox_override("normal", PixelUI.box("nine_paper", Vector4(10, 6, 10, 8)))
		elif b.has_meta("orig_normal"):
			b.add_theme_stylebox_override("normal", b.get_meta("orig_normal"))
		else:
			b.remove_theme_stylebox_override("normal")


func refresh() -> void:
	var st := Game.state
	if st == null:
		return
	kname.text = "%s Kingdom" % st.kname(st.kingdom)
	day_label.text = "Week %d · Day %d" % [st.week(), st.day_in_week()]
	weather_label.text = GameState.WEATHERS[st.weather].name
	var tot := st.daily_totals()
	for r in res_labels.keys():
		var lbl: Label = res_labels[r]
		var v: int = int(st.res.get(r, 0))
		var old: int = _last.get(r, v)
		if old != v:
			Fx.count(lbl, old, v, 0.5)
			var tw := lbl.create_tween()
			lbl.pivot_offset = lbl.size / 2
			tw.tween_property(lbl, "scale", Vector2(1.25, 1.25), 0.1)
			tw.tween_property(lbl, "scale", Vector2.ONE, 0.25)
		else:
			lbl.text = str(v)
		_last[r] = v
		var d: int = int(tot.get(r, 0))
		var dl: Label = res_delta[r]
		dl.text = ("+%d" % d) if d >= 0 else str(d)
		dl.add_theme_color_override("font_color", Style.GOOD if d > 0 else (Style.BAD if d < 0 else Style.PENCIL))
	pop_label.text = "%d/%d · %d idle" % [st.pop, st.housing(), st.idle_workers()]
	var c := st.champ
	c_name.text = c.name
	c_level.text = "Lv %d%s" % [c.level, ("  (+%d pt)" % c.unspent_points) if c.unspent_points > 0 else ""]
	c_hp_text.text = "%d/%d HP · %s" % [c.hp, c.max_hp(), "in the capital" if st.at_capital() else "on the road"]
	var hpv := float(c.hp) / float(c.max_hp())
	hp_bar.set_meta("v", hpv)
	hp_bar.set_meta("fill", Style.SAGE if hpv > 0.5 else (Style.YELLOW if hpv > 0.25 else Style.CORAL))
	hp_bar.queue_redraw()
	var lo := c.xp_for_current()
	var hi := c.xp_for_next()
	xp_bar.set_meta("v", float(c.xp - lo) / float(maxi(1, hi - lo)))
	xp_bar.queue_redraw()
	var arm := str(Champion.item(str(c.equip.armor)).get("name", "no armour"))
	c_gear.text = "%s · %s · bag %d/%d · %d/%d XP" % [c.weapon_info().name, arm, c.bag.size(), int(Data.get_file("items").get("bag_slots", 8)), c.xp, hi]
	flag.queue_redraw()
	portrait.queue_redraw()
	age_label.text = "Age %s · %s" % ["I".repeat(st.age) if st.age < 4 else str(st.age), st.age_name()]
	_refresh_cargo(st)
	_refresh_army(st)
	_refresh_tracker(st)
	if _pixel:
		_skin_walk(cargo_row, true)
		_skin_walk(army_row, true)


func _refresh_cargo(st: GameState) -> void:
	for ch in cargo_row.get_children():
		ch.queue_free()
	cargo_row.add_child(ResIcon.make("cargo", 20))
	var any := false
	for r in ["food", "wood", "stone", "gold", "iron"]:
		var v := int(st.champ.cargo.get(r, 0))
		if v <= 0:
			continue
		any = true
		cargo_row.add_child(ResIcon.make(r, 18))
		cargo_row.add_child(Style.label(str(v), 14, Style.body_heavy))
	if not any:
		cargo_row.add_child(Style.label("cargo empty", 13, Style.body_bold, Style.FAINT))


func _refresh_army(st: GameState) -> void:
	for ch in army_row.get_children():
		ch.queue_free()
	army_row.add_child(ResIcon.make("sword", 20))
	var n := 0
	for e in st.party:
		n += 1
		var chip := PanelContainer.new()
		var champ := str(e.kind) == "champion"
		var nm := st.champ.name if champ else str(st.unit_stats(e).name)
		var fill := Style.kingdom_color(st.kingdom, "tint") if champ else (Style.YELLOW if e.get("veteran", false) else Style.NOTE)
		var b := Style.box(fill, n * 5, 0.0, Style.INK, 1.2, 2.0)
		b.content_margin_left = 5
		b.content_margin_right = 5
		chip.add_theme_stylebox_override("panel", b)
		chip.tooltip_text = "Rank %d · %s" % [n, nm]
		chip.mouse_filter = Control.MOUSE_FILTER_PASS
		chip.add_child(Style.label(nm.substr(0, 3), 12, Style.body_heavy))
		army_row.add_child(chip)
	for i in range(n, int(Data.B("army.slots", 5))):
		var emp := Style.label("·", 16, Style.body_heavy, Style.FAINT)
		army_row.add_child(emp)
