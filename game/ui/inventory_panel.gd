class_name InventoryPanel
extends Control
## The Champion's equipment (weapon, armour, trinket) and bag. Click an item to
## see it; equip, use, sell (at your Market, in the capital) or drop it.
## Opened with I or the Bag button on the world and city screens.

signal closed
signal used(changes: Array)

var st: GameState
var panel := PanelContainer.new()
var eq_box := HBoxContainer.new()
var grid := GridContainer.new()
var stats_l: Label
var detail := VBoxContainer.new()
var sel_id := ""
var sel_slot := ""          # equipment slot if the selection is equipped


static func open(parent: Node) -> InventoryPanel:
	var p := InventoryPanel.new()
	parent.add_child(p)
	return p


func _ready() -> void:
	st = Game.state
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.1, 0.07, 0.14, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: close())
	add_child(dim)
	panel.add_theme_stylebox_override("panel", Style.box(Style.CARD, 61, 8.0, Style.INK, 2.4, 22.0))
	panel.custom_minimum_size = Vector2(900, 0)
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)
	var head := HBoxContainer.new()
	head.add_child(Style.hand("%s's pack" % st.champ.name, 42))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var x := Style.button("✕", Style.CARD, 18)
	x.pressed.connect(close)
	head.add_child(x)
	v.add_child(head)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 26)
	v.add_child(row)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	row.add_child(left)
	left.add_child(Style.caps("Equipped"))
	eq_box.add_theme_constant_override("separation", 10)
	left.add_child(eq_box)
	stats_l = Style.label("", 14, Style.body_bold, Style.PENCIL)
	left.add_child(stats_l)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	row.add_child(right)
	right.add_child(Style.caps("Bag · %d slots" % int(Data.get_file("items").get("bag_slots", 8))))
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	right.add_child(grid)
	v.add_child(HSeparator.new())
	detail.add_theme_constant_override("separation", 6)
	detail.custom_minimum_size = Vector2(0, 120)
	v.add_child(detail)
	_refresh()
	await get_tree().process_frame
	panel.position = ((size - panel.size) / 2.0).floor()
	Fx.pop_in(panel)
	Audio.play("paper", -4.0)


func _unhandled_key_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.keycode in [KEY_ESCAPE, KEY_I]:
		get_viewport().set_input_as_handled()
		close()


func close() -> void:
	closed.emit()
	queue_free()


func _refresh() -> void:
	var c := st.champ
	for ch in eq_box.get_children():
		ch.queue_free()
	for sl: String in ["weapon", "armor", "trinket"]:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 2)
		var id := str(c.equip[sl])
		var ic := ItemIcon.make(id, 84) if id != "" else ItemIcon.new()
		if id == "":
			ic.custom_minimum_size = Vector2(84, 84)
			ic.empty_label = sl
		ic.tooltip_text = str(Champion.item(id).get("name", "empty " + sl))
		var s2: String = sl
		ic.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed and id != "": _select(id, s2))
		col.add_child(ic)
		col.add_child(Style.label(sl.capitalize(), 13, Style.body_heavy, Style.PENCIL))
		eq_box.add_child(col)
	var w := c.weapon_info()
	var parts: Array[String] = []
	for a in Champion.ATTRS:
		var b := c.item_bonus(a)
		parts.append("%s %d%s" % [a, c.attr(a), (" (+%d)" % b) if b > 0 else ""])
	stats_l.text = "%s\n%s · hit +%d · dmg +%d\ndefence %d · moves 1D6+%d" % ["   ".join(parts.slice(0, 3)) + "\n" + "   ".join(parts.slice(3, 6)), w.name, int(w.hit), int(w.dmg), c.defense(), c.move_bonus()]
	for ch in grid.get_children():
		ch.queue_free()
	var slots := int(Data.get_file("items").get("bag_slots", 8))
	for i in slots:
		var ic: ItemIcon
		if i < c.bag.size():
			var e: Dictionary = c.bag[i]
			ic = ItemIcon.make(str(e.id), 76, int(e.n))
			ic.tooltip_text = str(Champion.item(str(e.id)).get("name", ""))
			var iid := str(e.id)
			ic.gui_input.connect(func(ev): if ev is InputEventMouseButton and ev.pressed: _select(iid, ""))
		else:
			ic = ItemIcon.new()
			ic.custom_minimum_size = Vector2(76, 76)
		grid.add_child(ic)
	_show_detail()


func _select(id: String, slot: String) -> void:
	sel_id = id
	sel_slot = slot
	Audio.play("click", -6.0)
	_show_detail()


func _bonus_text(it: Dictionary) -> String:
	var parts: Array[String] = []
	var b: Dictionary = it.get("bonus", {})
	for k in b.keys():
		var label: String = {"hit": "hit", "dmg": "damage", "def": "defence", "move": "move a day"}.get(k, k)
		parts.append("%+d %s" % [int(b[k]), label])
	var u: Dictionary = it.get("use", {})
	if u.has("hp"): parts.append("heals %d" % int(u.hp))
	if u.has("moves"): parts.append("+%d moves today" % int(u.moves))
	if u.get("cure", false): parts.append("cures bleed/stun")
	if u.get("flee", false): parts.append("escape a battle")
	if u.has("reveal_secrets"): parts.append("reveals hidden places")
	return " · ".join(parts)


func _show_detail() -> void:
	for ch in detail.get_children():
		ch.queue_free()
	if sel_id == "" or (sel_slot == "" and st.champ.count(sel_id) <= 0) or (sel_slot != "" and str(st.champ.equip[sel_slot]) != sel_id):
		sel_id = ""
		detail.add_child(Style.label("Pick an item to see what it does.", 15, Style.body_bold, Style.PENCIL))
		return
	var it := Champion.item(sel_id)
	var rcol: Color = {"common": Style.INK, "uncommon": Style.GOOD, "rare": Color("#6B3FA0")}.get(str(it.get("rarity", "common")), Style.INK)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.add_child(Style.hand(str(it.name), 30, rcol))
	h.add_child(Style.label("%s · %s · worth %d gold" % [str(it.rarity), str(it.slot), int(it.get("value", 0))], 13, Style.body_bold, Style.PENCIL))
	detail.add_child(h)
	var d := Style.label(str(it.get("desc", "")) + "   " + _bonus_text(it), 15, Style.body_bold, Style.INK)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(d)
	var acts := HBoxContainer.new()
	acts.add_theme_constant_override("separation", 10)
	detail.add_child(acts)
	if sel_slot != "":
		_act(acts, "Take off", Style.CARD, func(): return st.champ.unequip(sel_slot), "bag is full")
	elif str(it.slot) in ["weapon", "armor", "trinket"]:
		_act(acts, "Equip", Style.YELLOW, func(): return st.champ.equip_item(sel_id), "")
	var u: Dictionary = it.get("use", {})
	if sel_slot == "" and not u.is_empty() and not u.get("flee", false):
		_act(acts, "Use", Style.SAGE, func():
			var ch := st.use_item(sel_id)
			if not ch.is_empty():
				used.emit(ch)
			return not ch.is_empty()
		, "")
	if sel_slot == "":
		var can_sell := st.at_capital() and st.has_building("market")
		var sb := Style.button("Sell (+%d gold)" % int(it.get("value", 1)), Style.SAND, 15)
		sb.disabled = not can_sell
		sb.tooltip_text = "" if can_sell else "Sell at your Market, in the capital."
		sb.pressed.connect(func():
			if st.sell_item(sel_id).ok:
				Audio.play("coin")
				Game.touch()
				_refresh())
		acts.add_child(sb)
		_act(acts, "Drop", Style.PINK, func(): return st.champ.remove_item(sel_id), "")


func _act(parent: Node, label: String, fill: Color, fn: Callable, fail: String) -> void:
	var b := Style.button(label, fill, 15)
	b.pressed.connect(func():
		var okk: bool = fn.call()
		if okk:
			Game.touch()
		elif fail != "":
			Main.toast(fail.capitalize(), Style.BAD)
		_refresh())
	parent.add_child(b)
