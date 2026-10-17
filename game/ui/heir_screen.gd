extends Control
## The Champion has fallen. The kingdom continues: what stays, what is lost,
## and a cairn on the map where it happened.

var st: GameState
var time := 0.0
var art := Control.new()


func enter(_data: Dictionary) -> void:
	st = Game.state
	Audio.music("", 2.0)
	_build()


func _process(d: float) -> void:
	time += d
	art.queue_redraw()


func _build() -> void:
	add_child(PixelUI.backdrop("forest2", 0.55))
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for s in ["left", "right"]:
		m.add_theme_constant_override("margin_" + s, 70)
	m.add_theme_constant_override("margin_top", 50)
	m.add_theme_constant_override("margin_bottom", 44)
	add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 20)
	m.add_child(v)
	v.add_child(PixelUI.on_dark(Style.caps("Week %d · Day %d" % [st.week(), st.day_in_week()]), 6, Color("#ffe3a6")))
	v.add_child(PixelUI.on_dark(Style.hand("%s fell. The kingdom didn't." % st.champ.name, 70), 14))
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 36)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)
	art.custom_minimum_size = Vector2(480, 380)
	art.draw.connect(_draw_art)
	body.add_child(art)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 18)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 18)
	right.add_child(cards)
	cards.add_child(_list("Stays", Style.GOOD, ["your city and every building", "stores, people and territory", "every relation, good and bad", "what the map knows"]))
	cards.add_child(_list("Gone", Style.BAD, ["%s's level and XP" % st.champ.name, "the weapon, where it fell", "%d days of travel" % int(Data.B("heir.days_lost", 2)), "anything carried"]))
	var q := _list("Open question", Style.INK, ["The kingdom's relations, quests and history carry on. The heir starts at level 1 with a fresh pack."])
	cards.add_child(q)
	var n := PixelUI.on_dark(Style.hand("this hex keeps a cairn for the rest of the campaign. walk past it in week 9 and you'll remember why.", 24), 8, Color("#ffe3a6"))
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(n)
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(sp)
	var go := Style.cta("Create the heir  →", Style.CORAL, 30)
	go.size_flags_horizontal = Control.SIZE_SHRINK_END
	go.pressed.connect(func(): Main.go("create", {"heir": true}))
	right.add_child(go)


func _list(title: String, col: Color, lines: Array) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Style.box(Style.CARD, title.length() * 7, 4.0, Style.INK, 2.0, 18.0))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var c := VBoxContainer.new()
	c.add_theme_constant_override("separation", 6)
	p.add_child(c)
	c.add_child(Style.hand(title, 32, col))
	for l in lines:
		var lb := Style.label(str(l), 16, Style.body_bold)
		lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lb.custom_minimum_size = Vector2(200, 0)
		c.add_child(lb)
	return p


var _tx: Dictionary = {}


func _t(path: String) -> Texture2D:
	if not _tx.has(path):
		_tx[path] = load(path) if ResourceLoader.exists(path) else null
	return _tx[path]


func _draw_art() -> void:
	# the fallen Champion's grave (Tiny Swords "dead" sheet), a cairn of rocks and the kingdom's banner tower
	var ci := art
	ci.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var c := Vector2(art.size.x / 2, art.size.y * 0.78)
	var pts := PackedVector2Array()
	for k in 24:
		var a := TAU * k / 24.0
		pts.append(c + Vector2(cos(a) * 200, sin(a) * 40))
	ci.draw_colored_polygon(pts, Color(0.12, 0.05, 0.2, 0.35))
	var tw := _t("res://assets/tinyswords/city/b_%s_tower.png" % st.kingdom)
	if tw:
		var ts := tw.get_size() * 1.2
		ci.draw_texture_rect(tw, Rect2((c + Vector2(40, -ts.y + 20)).round(), ts), false, Color(1, 1, 1, 0.85))
	for r in [["props/skull", -120, 2.6], ["props/skull", -60, 2.0]]:
		var rt := _t("res://assets/%s.png" % r[0])
		if rt:
			var rs := rt.get_size() * float(r[2])
			ci.draw_texture_rect(rt, Rect2((c + Vector2(float(r[1]) - rs.x / 2.0, -rs.y + 4)).round(), rs), false)
