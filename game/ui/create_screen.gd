extends Control
## Champion creation: 18 points across six attributes, none above 5.
## Also used for heirs (data.heir = true).

var champ := Champion.new()
var heir := false
var rows: Dictionary = {}
var left_label: Label
var arche: Label
var move_l: Label
var hp_l: Label
var name_edit := LineEdit.new()
var portrait := Control.new()
var go_btn: Button
var time := 0.0
var kid := "red"


func enter(data: Dictionary) -> void:
	heir = data.get("heir", false)
	kid = Game.state.kingdom if heir and Game.state else Game.chosen_kingdom
	champ.attrs = {"STR": 0, "DEX": 0, "CON": 0, "INT": 0, "WIS": 0, "CHA": 0}
	if not heir:
		champ.attrs = {"STR": 1, "DEX": 4, "CON": 3, "INT": 1, "WIS": 5, "CHA": 4}
		champ.name = "Mira"
	else:
		champ.name = ["Tamsin", "Oren", "Ilka", "Bram", "Sefa"][randi() % 5]
	_build()
	_refresh()


func _points_left() -> int:
	var total := 0
	for a in Champion.ATTRS:
		total += champ.attr(a)
	return int(Data.B("champion.attr_points", 18)) - total


func _build() -> void:
	add_child(PixelUI.backdrop("dusk_a" if not heir else "forest2", 0.5))
	var root := MarginContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("margin_left", 70)
	root.add_theme_constant_override("margin_right", 70)
	root.add_theme_constant_override("margin_top", 44)
	root.add_theme_constant_override("margin_bottom", 40)
	add_child(root)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 22)
	root.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	var tc := VBoxContainer.new()
	head.add_child(tc)
	tc.add_child(PixelUI.on_dark(Style.caps("%s Kingdom · %s" % [Data.kingdoms()[kid].name, "the heir" if heir else "Day 1"]), 6, Color("#ffe3a6")))
	tc.add_child(PixelUI.on_dark(Style.hand("Who carries the banner now?" if heir else "Who rides out for you?", 68), 14))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var pts := PanelContainer.new()
	pts.add_theme_stylebox_override("panel", Style.box(Style.YELLOW, 91, 4.0, Style.INK, 2.0, 12.0))
	var ph := HBoxContainer.new()
	ph.add_theme_constant_override("separation", 12)
	pts.add_child(ph)
	left_label = Style.hand("0", 54)
	ph.add_child(left_label)
	var pl := Style.label("points left\nof %d · max %d each" % [int(Data.B("champion.attr_points", 18)), int(Data.B("champion.attr_start_max", 5))], 15, Style.body_heavy)
	ph.add_child(pl)
	head.add_child(pts)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 30)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)
	# portrait card
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", Style.box(Style.CARD, 92, 5.0, Style.INK, 2.0, 20.0))
	pc.custom_minimum_size = Vector2(330, 0)
	body.add_child(pc)
	var pcol := VBoxContainer.new()
	pcol.alignment = BoxContainer.ALIGNMENT_CENTER
	pcol.add_theme_constant_override("separation", 10)
	pc.add_child(pcol)
	portrait.custom_minimum_size = Vector2(280, 330)
	portrait.draw.connect(_draw_portrait)
	pcol.add_child(portrait)
	pcol.add_child(Style.caps("Name"))
	name_edit.text = champ.name
	name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_edit.max_length = 14
	name_edit.text_changed.connect(func(t): champ.name = t if t.strip_edges() != "" else "Nameless")
	pcol.add_child(name_edit)
	arche = Style.hand("", 30, Style.BAD)
	arche.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pcol.add_child(arche)
	# attribute rows
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 10)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(list)
	for a in Champion.ATTRS:
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", Style.box(Style.CARD, 100 + a.length() + Champion.ATTRS.find(a), 0.0, Style.INK, 2.0, 10.0))
		list.add_child(row)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 14)
		row.add_child(h)
		var key := Style.hand(a, 34)
		key.custom_minimum_size = Vector2(76, 0)
		h.add_child(key)
		var nc := VBoxContainer.new()
		nc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nc.add_child(Style.label(Champion.ATTR_NAMES[a], 17, Style.body_heavy))
		nc.add_child(Style.label(Champion.ATTR_DESC[a], 14, Style.body_bold, Style.PENCIL))
		h.add_child(nc)
		var minus := Style.button("−", Style.PAPER, 22)
		minus.custom_minimum_size = Vector2(48, 48)
		minus.pressed.connect(func(): _change(a, -1))
		h.add_child(minus)
		var pips := Control.new()
		pips.custom_minimum_size = Vector2(150, 30)
		var aa := a
		pips.draw.connect(func():
			var v := champ.attr(aa)
			for i in 5:
				var c := Vector2(14 + i * 30, 15)
				var pts2 := PackedVector2Array()
				for k in 12:
					var ang := TAU * k / 12.0
					pts2.append(c + Vector2(cos(ang), sin(ang)) * (10.0 + sin(k * 3.1 + i) * 0.8))
				if i < v:
					pips.draw_colored_polygon(pts2, Style.kingdom_color(kid))
				pts2.append(pts2[0])
				pips.draw_polyline(pts2, Style.INK, 2.0, true))
		h.add_child(pips)
		var plus := Style.button("+", Style.PAPER, 22)
		plus.custom_minimum_size = Vector2(48, 48)
		plus.pressed.connect(func(): _change(a, 1))
		h.add_child(plus)
		var odds := Style.label("", 13, Style.body_bold, Style.PENCIL)
		odds.custom_minimum_size = Vector2(96, 0)
		odds.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		h.add_child(odds)
		rows[a] = {"pips": pips, "odds": odds}
	# right column: derived numbers
	var rc := VBoxContainer.new()
	rc.add_theme_constant_override("separation", 16)
	rc.custom_minimum_size = Vector2(300, 0)
	body.add_child(rc)
	var dp := PanelContainer.new()
	dp.add_theme_stylebox_override("panel", Style.box(Style.CARD, 93, 5.0, Style.INK, 2.0, 20.0))
	rc.add_child(dp)
	var dc := VBoxContainer.new()
	dc.add_theme_constant_override("separation", 10)
	dp.add_child(dc)
	dc.add_child(Style.caps("On the road"))
	move_l = Style.hand("", 40)
	dc.add_child(move_l)
	dc.add_child(Style.label("hexes a day: 1D6 + DEX bonus (DEX 0–2 +0 · 3–4 +1 · 5 +2)", 14, Style.body_bold, Style.PENCIL))
	hp_l = Style.hand("", 40)
	dc.add_child(hp_l)
	dc.add_child(Style.label("10 + 2 × CON · wounds carry over", 14, Style.body_bold, Style.PENCIL))
	dc.add_child(Style.label("Weapon: walking stick (+0)", 15, Style.body_heavy))
	var note := PixelUI.on_dark(Style.hand("strong where you spend, fragile where you don't. a talker who picks fights will bleed.", 22), 8, Color("#ffe3a6"))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(290, 0)
	rc.add_child(note)
	var sp2 := Control.new()
	sp2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rc.add_child(sp2)
	go_btn = Style.cta("Into the capital  →" if not heir else "Raise the banner again  →", Style.CORAL, 28)
	go_btn.pressed.connect(_go)
	rc.add_child(go_btn)


func _change(a: String, d: int) -> void:
	var v := champ.attr(a) + d
	if v < 0 or v > int(Data.B("champion.attr_start_max", 5)):
		Audio.play("fail", -10.0)
		return
	if d > 0 and _points_left() <= 0:
		Audio.play("fail", -10.0)
		Fx.shake(left_label, 6.0)
		return
	champ.attrs[a] = v
	var p: Control = rows[a].pips
	p.pivot_offset = Vector2(14 + (v - (1 if d > 0 else 0)) * 30, 15)
	var tw := p.create_tween()
	tw.tween_property(p, "scale", Vector2(1.06, 1.06), 0.06)
	tw.tween_property(p, "scale", Vector2.ONE, 0.12)
	_refresh()


func _refresh() -> void:
	left_label.text = str(_points_left())
	for a in Champion.ATTRS:
		rows[a].pips.queue_redraw()
		rows[a].odds.text = "check +%d\n%d%% vs DC 12" % [champ.attr(a), GameState.chance(champ.attr(a), 12)]
	arche.text = champ.archetype()
	var mb := champ.move_bonus()
	move_l.text = "%d–%d moves" % [1 + mb, 6 + mb]
	hp_l.text = "%d HP" % champ.max_hp()
	go_btn.disabled = _points_left() != 0
	go_btn.tooltip_text = "" if _points_left() == 0 else "Spend all your points first"
	portrait.queue_redraw()


func _process(d: float) -> void:
	time += d
	portrait.queue_redraw()


func _draw_portrait() -> void:
	# the Champion as a Tiny Swords warrior in the kingdom's colour, under a banner
	var ci := portrait
	ci.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var c := Vector2(portrait.size.x / 2.0, portrait.size.y - 10)
	if _ptex.is_empty():
		_ptex = {"warrior": load("res://assets/tinyswords/units/%s_warrior_idle.png" % kid),
			"tower": load("res://assets/tinyswords/city/b_%s_tower.png" % kid)}
	var tw: Texture2D = _ptex.tower
	if tw:
		var ts := tw.get_size() * 1.1
		ci.draw_texture_rect(tw, Rect2((c - Vector2(ts.x / 2.0 + 60, ts.y - 10)).round(), ts), false, Color(1, 1, 1, 0.55))
	var t: Texture2D = _ptex.warrior
	if t:
		var fw := t.get_height()
		var n := maxi(1, t.get_width() / fw)
		var fr := int(time * 8.0) % n
		var sc := 2.4 + champ.attr("STR") * 0.06
		var sz := Vector2(fw, fw) * sc
		var pts := PackedVector2Array()
		for k in 20:
			var a := TAU * k / 20.0
			pts.append(c + Vector2(cos(a) * 70, sin(a) * 14 - 6))
		ci.draw_colored_polygon(pts, Color(0.12, 0.05, 0.2, 0.3))
		ci.draw_texture_rect_region(t, Rect2((c - Vector2(sz.x / 2.0, sz.y * 0.74)).round(), sz), Rect2(fr * fw, 0, fw, fw))


var _ptex: Dictionary = {}


func _go() -> void:
	if _points_left() != 0:
		return
	champ.name = name_edit.text.strip_edges() if name_edit.text.strip_edges() != "" else champ.name
	if heir:
		Game.state.crown_heir(champ)
		Game.touch()
		Main.go("world", {"from": "heir"})
	else:
		Game.start_campaign(kid, champ)
		Main.instance.reset_world()
		Main.go("world", {"from": "start"})
