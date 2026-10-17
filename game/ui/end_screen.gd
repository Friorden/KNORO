extends Control
## The crown is whole: shown when the last main quest is done. The campaign's
## story so far, the kingdom in numbers, quests and dungeons, and the choice to
## keep playing (the world goes on) or start a new campaign.

var st: GameState


func enter(_data: Dictionary) -> void:
	st = Game.state
	Audio.play("bell_week")
	_build()


func _build() -> void:
	add_child(PixelUI.backdrop("dusk_a", 0.5))
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for s in ["left", "right"]:
		m.add_theme_constant_override("margin_" + s, 70)
	m.add_theme_constant_override("margin_top", 44)
	m.add_theme_constant_override("margin_bottom", 40)
	add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	m.add_child(v)
	var cap := PixelUI.label("The crown is whole · week %d · day %d" % [st.week(), st.day_in_week()], 18, Color("#ffe3a6"))
	cap.add_theme_color_override("font_outline_color", Color("#2b1d3d"))
	cap.add_theme_constant_override("outline_size", 6)
	v.add_child(cap)
	var tl := PixelUI.label("The map remembers", 72, PixelUI.CREAM)
	tl.add_theme_color_override("font_outline_color", Color("#2b1d3d"))
	tl.add_theme_constant_override("outline_size", 14)
	v.add_child(tl)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 30)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)
	var story := PanelContainer.new()
	story.add_theme_stylebox_override("panel", Style.box(Style.CARD, 301, 5.0, Style.INK, 2.0, 24.0))
	story.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(story)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	story.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 10)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var d := 0.2
	for h in st.history:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		var day := Style.hand("Day %d" % int(h.day), 26, Style.PENCIL)
		day.custom_minimum_size = Vector2(90, 0)
		row.add_child(day)
		var t := Style.label(str(h.text), 18, Style.body_bold)
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(t)
		list.add_child(row)
		Fx.pop_in(row, d, 0.95)
		d += 0.1
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 14)
	right.custom_minimum_size = Vector2(500, 0)
	body.add_child(right)
	var nums := PanelContainer.new()
	nums.add_theme_stylebox_override("panel", Style.box(Style.CARD, 302, 5.0, Style.INK, 2.0, 20.0))
	right.add_child(nums)
	var nc := VBoxContainer.new()
	nc.add_theme_constant_override("separation", 6)
	nums.add_child(nc)
	nc.add_child(Style.hand("%s Kingdom" % st.kname(st.kingdom), 36))
	nc.add_child(Style.label("%d people · %d buildings · %d food · %d wood · %d stone · %d gold" % [st.pop, st.city.size(), st.res.food, st.res.wood, st.res.stone, st.res.gold], 15, Style.body_bold))
	nc.add_child(Style.label("%s, %s · level %d" % [st.champ.name, st.champ.archetype(), st.champ.level], 15, Style.body_bold, Style.PENCIL))
	for kid in st.relations.keys():
		nc.add_child(Style.label("%s: %s" % [st.kname(kid), st.relation_label(kid)], 15, Style.body_heavy, Style.kingdom_color(kid).darkened(0.35)))
	var q := PanelContainer.new()
	q.add_theme_stylebox_override("panel", Style.box(Style.YELLOW, 303, 4.0, Style.INK, 2.0, 20.0))
	right.add_child(q)
	var qc := VBoxContainer.new()
	qc.add_theme_constant_override("separation", 6)
	q.add_child(qc)
	qc.add_child(Style.hand("Your reign so far", 30))
	var qd := 0
	for id in st.quests.keys():
		if st.quests[id].state == "done":
			qd += 1
	var dn := 0
	for f in st.flags.keys():
		if str(f).begins_with("dungeon_done_"):
			dn += 1
	var won := 0
	for g in st.kills.keys():
		won += int(st.kills[g])
	for line in ["%d quests finished" % qd, "%d of 3 dungeons cleared" % dn, "%d battles won" % won, "%d places discovered" % st.discovered_places.size(), "Age %s · %s" % ["I".repeat(st.age), st.age_name()]]:
		qc.add_child(Style.label("·  " + line, 16, Style.body_bold))
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(sp)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.alignment = BoxContainer.ALIGNMENT_END
	right.add_child(row)
	var again := Style.button("New campaign", Style.CARD, 17)
	again.custom_minimum_size = Vector2(0, 56)
	again.pressed.connect(func():
		Game.seed = randi() % 100000
		Main.instance.reset_world()
		Main.go("select"))
	row.add_child(again)
	var cont := Style.cta("Keep playing  →", Style.CORAL, 28)
	cont.pressed.connect(func(): Main.go("world", {}))
	row.add_child(cont)
