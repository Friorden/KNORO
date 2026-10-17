extends Control
## The end-of-week notebook: what the kingdom made and ate, who grew, who
## remembers what you did, and what the next week brings. Numbers count up.

var st: GameState
var rep: Dictionary


func enter(data: Dictionary) -> void:
	st = Game.state
	rep = data.get("report", {})
	Audio.play("bell_week", -2.0)
	_build()


func _build() -> void:
	add_child(PixelUI.backdrop("forest1", 0.45))
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for s in ["left", "right"]:
		m.add_theme_constant_override("margin_" + s, 56)
	m.add_theme_constant_override("margin_top", 34)
	m.add_theme_constant_override("margin_bottom", 30)
	add_child(m)
	var book := HBoxContainer.new()
	book.add_theme_constant_override("separation", 0)
	m.add_child(book)
	var left := _page(221)
	book.add_child(left)
	var spine := Control.new()
	spine.custom_minimum_size = Vector2(30, 0)
	spine.draw.connect(func():
		spine.draw_rect(Rect2(Vector2.ZERO, spine.size), Color("#E6DCCB"))
		for i in 8:
			var y := 30 + i * (spine.size.y - 60) / 7.0
			spine.draw_arc(Vector2(15, y), 9, 0, TAU, 14, Style.INK, 2.0, true)
		spine.draw_line(Vector2(0, 0), Vector2(0, spine.size.y), Style.INK, 2.0)
		spine.draw_line(Vector2(30, 0), Vector2(30, spine.size.y), Style.INK, 2.0))
	book.add_child(spine)
	var right := _page(222)
	book.add_child(right)
	_fill_left(left.get_child(0))
	_fill_right(right.get_child(0))
	var bp := book
	bp.pivot_offset = Vector2(800, 400)
	Fx.pop_in(bp, 0.0, 0.92)


func _page(seed: int) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Style.box(Style.CARD, seed, 6.0, Style.INK, 2.4, 30.0))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	p.add_child(v)
	return p


func _fill_left(v: VBoxContainer) -> void:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	head.add_child(Style.hand("Week %d" % int(rep.get("week", 1)), 64))
	head.add_child(Style.hand("%s Kingdom" % st.kname(st.kingdom), 26, Style.PENCIL))
	v.add_child(head)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 8)
	v.add_child(grid)
	var prod: Dictionary = rep.get("prod", {})
	var spent: Dictionary = rep.get("spent", {})
	var gifts: Array = rep.get("gifts", [])
	var delivered: Dictionary = rep.get("delivered", {})
	var delay := 0.2
	for r in ["food", "wood", "stone", "gold", "iron"]:
		var made := int(prod.get(r, 0))
		var brought := int(delivered.get(r, 0))
		var used := int(spent.get(r, 0)) + ((int(rep.get("eaten", 0)) + int(rep.get("upkeep", 0))) if r == "food" else 0)
		var net := made + brought - used
		grid.add_child(ResIcon.make(r, 28))
		grid.add_child(Style.label(r.capitalize(), 18, Style.body_heavy))
		var detail := "made +%d" % made
		if brought != 0:
			detail += " · cargo home +%d" % brought
		if used != 0:
			detail += " · %s −%d" % ["eaten, soldiers & spent" if r == "food" else "spent", used]
		grid.add_child(Style.label(detail, 15, Style.body, Style.PENCIL))
		var nl := Style.hand("0", 34, Style.GOOD if net >= 0 else Style.BAD)
		grid.add_child(nl)
		_count_later(nl, net, delay)
		delay += 0.15
	# what the road gave (it went into the cargo)
	for g in gifts:
		if str(g.get("from", "")) != "":
			var l := Style.hand("↳ %+d %s from %s → cargo" % [int(g.amount), g.res, g.from], 22, Style.BAD)
			v.add_child(l)
	# battles
	var battles: Array = rep.get("battles", [])
	if not battles.is_empty():
		v.add_child(HSeparator.new())
		var bh := HBoxContainer.new()
		bh.add_theme_constant_override("separation", 10)
		bh.add_child(ResIcon.make("sword", 26))
		var won := battles.filter(func(b): return str(b.result) == "win").size()
		bh.add_child(Style.label("Battles: %d fought, %d won" % [battles.size(), won], 18, Style.body_heavy))
		v.add_child(bh)
		for b in battles:
			var lost: Array = b.get("lost", [])
			var txt := "• %s — %s%s" % [_battle_name(str(b.source)), {"win": "won", "lose": "lost", "fled": "fled"}.get(str(b.result), str(b.result)), (" · fallen: " + ", ".join(lost)) if not lost.is_empty() else ""]
			v.add_child(Style.label(txt, 14, Style.body_bold, Style.BAD if not lost.is_empty() else Style.PENCIL))
	v.add_child(HSeparator.new())
	var pr := HBoxContainer.new()
	pr.add_theme_constant_override("separation", 12)
	pr.add_child(ResIcon.make("pop", 28))
	pr.add_child(Style.label("People", 18, Style.body_heavy))
	var growth := int(rep.get("growth", 0))
	var pl := Style.hand("%d → %d" % [int(rep.get("pop_before", st.pop)), int(rep.get("pop_after", st.pop))], 34, Style.GOOD if growth > 0 else (Style.BAD if growth < 0 else Style.INK))
	pr.add_child(pl)
	v.add_child(pr)
	var gr := Style.label(str(rep.get("growth_reason", "")), 15, Style.body_bold, Style.PENCIL)
	v.add_child(gr)
	var people := Control.new()
	people.custom_minimum_size = Vector2(0, 80)
	var after := int(rep.get("pop_after", st.pop))
	people.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var pawn_old: Texture2D = load("res://assets/tinyswords/units/%s_pawn_idle.png" % st.kingdom)
	var pawn_new: Texture2D = load("res://assets/tinyswords/units/%s_pawn_idle.png" % ("blue" if st.kingdom != "blue" else "yellow"))
	people.set_meta("tx", [pawn_old, pawn_new])     # keep the textures alive while the row draws them
	people.draw.connect(func():
		for i in mini(after, 30):
			var new := i >= after - maxi(0, growth)
			var t: Texture2D = pawn_new if new else pawn_old
			var fw := t.get_height()
			people.draw_texture_rect_region(t, Rect2(Vector2(i * 30 - 30, -30), Vector2(110, 110)), Rect2(0, 0, fw, fw)))
	v.add_child(people)
	var trade: Dictionary = rep.get("trade", {})
	if not trade.is_empty():
		var t := "Stone deal: −5 stone, +15 gold" if not trade.has("missing") else "Stone deal: not enough stone this week!"
		v.add_child(Style.label(t, 15, Style.body_heavy, Style.GOOD if not trade.has("missing") else Style.BAD))
	if rep.has("new_quest"):
		v.add_child(Style.label("New request: %s (J for the quest log)" % str(st.quest_def(str(rep.new_quest)).get("title", "")), 16, Style.body_heavy, PixelUI.VIOLET))
	var made: Array = rep.get("stash", [])
	if not made.is_empty():
		var ml := Style.label("Storehouse: " + ", ".join(PackedStringArray(made)) + (" · picked up when %s is home" % st.champ.name), 15, Style.body_heavy, Style.GOOD)
		ml.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(ml)
	v.add_child(HSeparator.new())
	v.add_child(Style.label("%s · Lv %d · %d/%d HP · %d XP · army %d/%d · upkeep %d food/day" % [st.champ.name, st.champ.level, st.champ.hp, st.champ.max_hp(), st.champ.xp, st.party.size(), int(Data.B("army.slots", 5)), st.upkeep()], 16, Style.body_heavy))
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sp)
	var biggest := _biggest_story(gifts)
	if biggest != "":
		var n := Style.hand(biggest, 24, Style.PENCIL)
		n.rotation_degrees = -1
		v.add_child(n)


func _battle_name(src: String) -> String:
	if src.begins_with("camp:"):
		var pid := src.substr(5)
		if st.world.places.has(pid):
			return str(st.world.tile(st.world.places[pid]).name)
	if src.begins_with("patrol"):
		return "a patrol on the road"
	return "a fight in the wilds"


func _biggest_story(gifts: Array) -> String:
	var best: Dictionary = {}
	for g in gifts:
		if best.is_empty() or int(g.amount) > int(best.amount):
			best = g
	if best.is_empty() or int(best.amount) < 15:
		return ""
	return "the biggest gift this week came from %s, not from a building." % str(best.get("from", "the road")).to_lower()


func _fill_right(v: VBoxContainer) -> void:
	v.add_child(Style.hand("Neighbours remember", 44))
	var rel_changes: Array = rep.get("rel", [])
	for kid in st.relations.keys():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		var dot := Control.new()
		dot.custom_minimum_size = Vector2(22, 22)
		var k: String = kid
		dot.draw.connect(func():
			dot.draw_circle(Vector2(11, 11), 10, Style.kingdom_color(k))
			dot.draw_arc(Vector2(11, 11), 10, 0, TAU, 16, Style.INK, 2.0, true))
		row.add_child(dot)
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(Style.label("%s · %s" % [st.kname(kid), st.relation_label(kid)], 18, Style.body_heavy))
		var total := 0
		var reasons: Array[String] = []
		for c in rel_changes:
			if c.kid == kid:
				total += int(c.amount)
				if str(c.reason) != "":
					reasons.append(str(c.reason))
		col.add_child(Style.label(", ".join(reasons) if not reasons.is_empty() else "nothing new between you", 14, Style.body, Style.PENCIL))
		row.add_child(col)
		row.add_child(Style.hand("%+d" % total if total != 0 else "·", 38, Style.GOOD if total > 0 else (Style.BAD if total < 0 else Style.PENCIL)))
		v.add_child(row)
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 18)
	v.add_child(cards)
	var wpanel := PanelContainer.new()
	wpanel.add_theme_stylebox_override("panel", Style.box(Style.POWDER, 231, 3.0, Style.INK, 2.0, 14.0))
	wpanel.rotation_degrees = -1.5
	var wc := VBoxContainer.new()
	wpanel.add_child(wc)
	wc.add_child(Style.caps("This week", Style.INK))
	var wd: Dictionary = GameState.WEATHERS[st.weather]
	wc.add_child(Style.hand(str(wd.name), 30))
	wc.add_child(Style.label(str(wd.text), 14, Style.body_bold))
	cards.add_child(wpanel)
	if st.flags.has("envoy_waiting") and not st.flags.has("envoy_done") or (st.envoy_day > 0 and not st.flags.has("envoy_done")):
		var letter := PanelContainer.new()
		letter.add_theme_stylebox_override("panel", Style.box(Style.NOTE, 232, 3.0, Style.INK, 1.6, 14.0))
		letter.rotation_degrees = 2
		var lc := VBoxContainer.new()
		letter.add_child(lc)
		lc.add_child(Style.caps("A letter from %s" % st.kname(st.world.rival), Style.GOLD))
		var lt := Style.hand("“Our scouts saw your banner on Greyrock. We will send someone to talk about it.”", 22)
		lt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lt.custom_minimum_size = Vector2(300, 0)
		lc.add_child(lt)
		cards.add_child(letter)
	v.add_child(Style.caps("The map remembers"))
	var hist := HFlowContainer.new()
	hist.add_theme_constant_override("h_separation", 10)
	hist.add_theme_constant_override("v_separation", 10)
	v.add_child(hist)
	var items: Array = rep.get("history", [])
	var d := 0.3
	for hh in items:
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", Style.box(Style.PAPER, 240 + int(hh.day), 0.0, Style.FAINT, 1.4, 8.0))
		var c := VBoxContainer.new()
		p.add_child(c)
		c.add_child(Style.label("Day %d" % int(hh.day), 12, Style.body_heavy, Style.PENCIL))
		var tl := Style.label(str(hh.text), 14, Style.body_bold)
		tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tl.custom_minimum_size = Vector2(200, 0)
		c.add_child(tl)
		hist.add_child(p)
		Fx.pop_in(p, d)
		d += 0.08
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sp)
	var go := Style.cta("Start week %d  →" % (int(rep.get("week", 1)) + 1), Style.CORAL, 30)
	go.size_flags_horizontal = Control.SIZE_SHRINK_END
	go.pressed.connect(func(): Main.go("world", {"from": "week"}))
	v.add_child(go)


func _count_later(l: Label, to: int, delay: float) -> void:
	await get_tree().create_timer(delay + 0.4).timeout
	Fx.count(l, 0, to, 0.7, "+" if to > 0 else "")
	Audio.play("click", -8.0)
