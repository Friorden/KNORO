class_name QuestLog
extends RefCounted
## The quest log (J): the main story on top, side quests below, finished quests
## folded at the end. Every objective shows its progress (e.g. 12/40 stone).

static func open(parent: Node) -> Control:
	var st: GameState = Game.state
	var f := Menus._frame(parent, "Quest log", 980, 660)
	var root: Control = f[0]
	var col: VBoxContainer = f[1]
	if st == null:
		col.add_child(PixelUI.label("No campaign running.", 18, PixelUI.MUTED))
		return root
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 540)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 12)
	scroll.add_child(list)
	var groups := [["Main story", st.active_quests("main")], ["Side quests", st.active_quests("side")]]
	var done: Array = []
	for id in st.quests.keys():
		if st.quests[id].state == "done":
			done.append(id)
	groups.append(["Finished", done])
	for g in groups:
		list.add_child(PixelUI.caps(str(g[0])))
		if (g[1] as Array).is_empty():
			list.add_child(PixelUI.label("— nothing here yet —" if g[0] != "Side quests" else "— new requests arrive at the end of each week —", 16, PixelUI.MUTED))
		for id in g[1]:
			list.add_child(_card(st, str(id), g[0] == "Finished"))
	return root


static func _card(st: GameState, id: String, finished: bool) -> Control:
	var q := st.quest_def(id)
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#f7ecd2") if not finished else Color("#e6dcc4")
	if str(q.get("kind", "")) == "main" and not finished:
		sb.bg_color = Color("#fff1c2")
	sb.border_color = PixelUI.INK
	sb.set_border_width_all(2)
	sb.border_width_bottom = 4
	sb.set_content_margin_all(14)
	p.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	var h := HBoxContainer.new()
	h.add_child(PixelUI.label(str(q.title), 22, PixelUI.VIOLET if not finished else PixelUI.MUTED))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sp)
	h.add_child(PixelUI.label("from " + str(q.get("giver", "")), 14, PixelUI.MUTED))
	v.add_child(h)
	if finished:
		v.add_child(PixelUI.label("Done on day %d" % int(st.quests[id].get("done_day", 0)), 14, PixelUI.GOOD))
		return p
	v.add_child(PixelUI.wrap(str(q.text), 16, PixelUI.INK, 860))
	for o in q.objectives:
		var pr := st.objective_progress(o)
		var ok: bool = pr[0] >= pr[1]
		var line := "%s  %s" % ["■" if ok else "□", str(o.get("text", o.type))]
		if int(pr[1]) > 1:
			line += "  (%d/%d)" % [pr[0], pr[1]]
		v.add_child(PixelUI.label(line, 17, PixelUI.GOOD if ok else PixelUI.INK))
	var rw: Dictionary = q.get("reward", {})
	var rr := HBoxContainer.new()
	rr.add_theme_constant_override("separation", 6)
	rr.add_child(PixelUI.label("Reward:", 15, PixelUI.MUTED))
	for k in rw.keys():
		if k in GameState.RES or k == "xp":
			rr.add_child(PixelUI.res_icon(k, 22))
			rr.add_child(PixelUI.label(str(rw[k]), 15))
		elif k == "item":
			rr.add_child(ItemIcon.make(str(rw[k]), 30))
			rr.add_child(PixelUI.label(str(Champion.item(str(rw[k])).get("name", rw[k])), 15))
		elif k == "relation_all":
			rr.add_child(PixelUI.label("+%d relations with everyone" % int(rw[k]), 15))
	v.add_child(rr)
	return p


## Short lines for the on-screen tracker: the main quest and up to two side quests.
static func tracker_lines(st: GameState) -> Array:
	var out: Array = []
	for id in st.active_quests("main") + st.active_quests("side").slice(0, 2):
		var q := st.quest_def(id)
		var objs: Array = []
		for o in q.objectives:
			var pr := st.objective_progress(o)
			var s := str(o.get("text", ""))
			if int(pr[1]) > 1:
				s += " %d/%d" % [pr[0], pr[1]]
			objs.append([s, pr[0] >= pr[1]])
		out.append({"title": str(q.title), "main": str(q.kind) == "main", "objs": objs})
	return out
