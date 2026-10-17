extends Control
## The capital up close, drawn in Tiny Swords pixel art (render/ts_city.gd).
## Pick a building on the right, valid plots light up, click one to build.
## Click a building to see it in the side panel: upgrade it (level 3 asks you
## to pick a specialisation), switch its production mode, or open its shop.
## Click an empty forest / hill / pond plot to clear it for building.
## + / − zoom, drag (right or middle button) or WASD to pan. The mouse wheel is ignored on purpose.

var st: GameState
var hud := Hud.new()
var city := TsCity.new()
var side := PanelContainer.new()
var list := VBoxContainer.new()
var info_l: Label
var title_l: Label
var modal := Control.new()
var tab := "build"
var tabs_row := HBoxContainer.new()
var picking := ""
var selected := Vector2i(-99, -99)     # building / plot shown in the "plot" tab
var dragging := false
var _built := false

const NONE := Vector2i(-99, -99)
const TABS := [["build", "Build"], ["army", "Army"], ["age", "Age"], ["cargo", "Store"], ["shop", "Shop"]]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _build() -> void:
	_built = true
	add_child(city)
	add_child(hud)
	hud.zoom_pressed.connect(_on_rail)
	side.add_theme_stylebox_override("panel", PixelUI.box("nine_paper", Vector4(22, 20, 22, 20)))
	side.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	side.offset_left = -400
	side.offset_right = -16
	side.offset_top = 104
	side.offset_bottom = -16
	add_child(side)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	side.add_child(col)
	tabs_row.add_theme_constant_override("separation", 3)
	col.add_child(tabs_row)
	var head := HBoxContainer.new()
	title_l = PixelUI.title("Build", 30)
	head.add_child(title_l)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	info_l = PixelUI.label("", 15, PixelUI.MUTED)
	head.add_child(info_l)
	col.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	list.add_theme_constant_override("separation", 8)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var back := PixelUI.cta("Back to the world", "blue", 22)
	back.pressed.connect(_go_world)
	col.add_child(back)
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(modal)


func _on_rail(t: String) -> void:
	match t:
		"world":
			_go_world()
		"bag":
			open_bag()
		"in":
			city.zoom_step(1)
		"out":
			city.zoom_step(-1)
		"center":
			city.cam = Vector2.ZERO
		"quests":
			QuestLog.open(Main.instance.menu_layer)
		"menu":
			Menus.pause(Main.instance.menu_layer)


func enter(data: Dictionary) -> void:
	if not _built:
		_build()
	st = Game.state
	city.st = st
	hud.set_mode("city")
	hud.refresh()
	picking = ""
	selected = NONE
	tab = str(data.get("tab", "build"))
	_rebuild_list()
	city.fit()
	city.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(city, "modulate:a", 1.0, 0.35)


func _process(d: float) -> void:
	if not _built or st == null:
		return
	city.picking = picking
	var v := {}
	if picking != "":
		for s in st.city_terrain.keys():
			if st.can_build(picking, s).ok:
				v[s] = true
	city.valid = v
	for s in city.pop_anim.keys():
		city.pop_anim[s] = minf(1.0, city.pop_anim[s] + d * 0.9)
		if city.pop_anim[s] >= 1.0:
			city.pop_anim.erase(s)
	if modal.get_child_count() == 0 and is_visible_in_tree():
		var pan := Vector2.ZERO
		for k in [[KEY_A, Vector2.LEFT], [KEY_D, Vector2.RIGHT], [KEY_W, Vector2.UP], [KEY_S, Vector2.DOWN],
				[KEY_LEFT, Vector2.LEFT], [KEY_RIGHT, Vector2.RIGHT], [KEY_UP, Vector2.UP], [KEY_DOWN, Vector2.DOWN]]:
			if Input.is_physical_key_pressed(k[0]):
				pan += k[1]
		if pan != Vector2.ZERO:
			city.pan(-pan.normalized() * 700.0 * d)


# ------------------------------------------------------------------ input

func _unhandled_input(e: InputEvent) -> void:
	if not visible or not _built or modal.get_child_count() > 0 or Main.menu_open():
		return
	if e is InputEventMouseMotion:
		if dragging:
			city.pan(e.relative)
		var on_side: bool = e.position.x > size.x - 410
		city.hover = NONE if on_side else city.pick(e.position)
	elif e is InputEventMouseButton:
		if e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
			return
		if e.button_index in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT] and not e.pressed:
			dragging = false
		if not e.pressed:
			return
		if e.button_index == MOUSE_BUTTON_LEFT and city.hover != NONE:
			_click_slot(city.hover)
		elif e.button_index == MOUSE_BUTTON_MIDDLE:
			dragging = true
		elif e.button_index == MOUSE_BUTTON_RIGHT:
			dragging = true
			if picking != "":
				picking = ""
				_rebuild_list()
	elif e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_I:
				open_bag()
			KEY_EQUAL, KEY_KP_ADD, KEY_PLUS:
				city.zoom_step(1)
			KEY_MINUS, KEY_KP_SUBTRACT:
				city.zoom_step(-1)
			KEY_ESCAPE:
				if picking != "" or selected != NONE:
					picking = ""
					selected = NONE
					if tab == "plot":
						tab = "build"
					_rebuild_list()
				else:
					Menus.pause(Main.instance.menu_layer)
			KEY_C:
				_go_world()
			KEY_J:
				QuestLog.open(Main.instance.menu_layer)


func _click_slot(s: Vector2i) -> void:
	if picking != "":
		var r := st.build(picking, s)
		if r.ok:
			Audio.play("build")
			city.pop_anim[s] = 0.0
			var p := city.slot_screen(s)
			for k in r.cost.keys():
				Fx.float_text(self, p + Vector2(0, -60), "-%d" % int(r.cost[k]), Style.BAD, k)
			Main.toast("%s built" % str(Data.buildings()[picking].name))
			picking = ""
			Game.touch()
			_show_plot(s)
		else:
			Main.toast(str(r.reason).capitalize(), Style.BAD)
		return
	if st.city.has(s) and str(st.city[s].type) == "barracks":
		_set_tab("army")
		return
	_show_plot(s)


func _show_plot(s: Vector2i) -> void:
	selected = s
	tab = "plot"
	Audio.play("paper", -6.0)
	_rebuild_list()


func open_bag() -> void:
	if modal.get_child_count() > 0:
		return
	var inv := InventoryPanel.open(modal)
	inv.closed.connect(func(): hud.refresh(); _rebuild_list())


func _go_world() -> void:
	Main.go("world", {"from_city": true, "wipe_from": Vector2(0.4, 0.5)})


# ------------------------------------------------------------------ side panel helpers

func _set_tab(t: String) -> void:
	tab = t
	picking = ""
	selected = NONE
	Audio.play("paper", -6.0)
	_rebuild_list()


func _row(parent: Node, kind: String = "plain") -> VBoxContainer:
	var row := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = {"plain": Color("#f7ecd2"), "on": Color("#fbe7a1"), "good": Color("#dfe9c4"), "violet": Color("#e7dcf3"), "warn": Color("#f6d8cf")}.get(kind, Color("#f7ecd2"))
	sb.border_color = Color(PixelUI.INK, 0.85)
	sb.set_border_width_all(2)
	sb.border_width_bottom = 4
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	row.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	row.add_child(v)
	parent.add_child(row)
	return v


func _cost_text(cost: Dictionary) -> String:
	var parts: Array[String] = []
	for k in cost.keys():
		parts.append("%d %s" % [int(cost[k]), k])
	return " · ".join(parts)


## A row of resource icons + amounts (for costs).
func _cost_row(cost: Dictionary, color: Color = PixelUI.INK) -> HFlowContainer:
	var h := HFlowContainer.new()
	h.add_theme_constant_override("h_separation", 3)
	for k in cost.keys():
		h.add_child(PixelUI.res_icon(str(k), 24))
		h.add_child(PixelUI.label(str(int(cost[k])), 15, color))
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(6, 0)
		h.add_child(gap)
	return h


## Small preview of a building's main sprite (half size, nearest filter).
func _thumb(type: String, px: float = 64.0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(px, px)
	c.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	c.draw.connect(func():
		var parts: Array = city.recipe(type, Vector2i(97, 97))
		var name := ""
		var area := 0
		for pt in parts:
			var tx := city.t(str(pt[0]))
			if tx and city._frame_w(tx) * tx.get_height() > area and not str(pt[0]).begins_with("units/") and not str(pt[0]).contains("res_") and not str(pt[0]).contains("blades"):
				area = city._frame_w(tx) * tx.get_height()
				name = str(pt[0])
		var t := city.t(name) if name != "" else null
		if t == null:
			return
		var fw := city._frame_w(t)
		var sc := 0.5 if maxf(fw, t.get_height()) <= 2.2 * px else 0.25
		var sz := Vector2(fw, t.get_height()) * sc
		c.draw_texture_rect_region(t, Rect2(((Vector2(px, px) - sz) / 2.0).round(), sz), Rect2(0, 0, fw, t.get_height())))
	return c


func _rebuild_list() -> void:
	for c in list.get_children():
		c.queue_free()
	for c in tabs_row.get_children():
		c.queue_free()
	for t in TABS:
		var on: bool = tab == t[0]
		var b := PixelUI.button(t[1], "gold" if on else "paper", 14)
		b.custom_minimum_size = Vector2(66, 40)
		var key: String = t[0]
		b.pressed.connect(func(): _set_tab(key))
		tabs_row.add_child(b)
	match tab:
		"plot":
			_list_plot()
		"army":
			_list_army()
		"age":
			_list_age()
		"cargo":
			_list_cargo()
		"shop":
			_list_shop()
		_:
			_list_build()


# ------------------------------------------------------------------ build tab

func _list_build() -> void:
	title_l.text = "BUILD"
	var bpd := st.builds_per_day()
	info_l.text = "%d of %d today" % [maxi(0, bpd - st.builds_today), bpd]
	var es := st.expand_status()
	if int(es.radius) > st.city_radius:
		var v := _row(list, "violet")
		var h := HBoxContainer.new()
		v.add_child(h)
		var c := VBoxContainer.new()
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.add_child(PixelUI.label("Claim more land", 17))
		c.add_child(PixelUI.wrap("+%d plots around the capital" % (Hex.ring(Vector2i.ZERO, int(es.radius)).size() - st.city_terrain.size()), 13, PixelUI.MUTED))
		c.add_child(_cost_row(es.cost))
		if not es.ok:
			c.add_child(PixelUI.wrap("✕ " + str(es.reason), 13, PixelUI.BAD))
		h.add_child(c)
		var eb := PixelUI.button("Expand", "blue" if es.ok else "paper", 15)
		eb.disabled = not es.ok
		eb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		eb.pressed.connect(func():
			if not st.expand_city().is_empty():
				Audio.play("build")
				Main.toast("The capital grows")
				Game.touch()
				city.fit()
			_rebuild_list())
		h.add_child(eb)
	if st.at_capital():
		list.add_child(PixelUI.label("%s is home · −%d%% cost" % [st.champ.name, int(float(Data.B("economy.capital_build_discount", 0.2)) * 100)], 16, PixelUI.GOOD))
	else:
		list.add_child(PixelUI.wrap("Building remotely: full price. Bring %s home for −20%%." % st.champ.name, 14, PixelUI.MUTED))
	list.add_child(PixelUI.wrap("Click a building on the island to upgrade it. Click woods, hills or ponds to clear them.", 13, PixelUI.MUTED))
	var groups := [["Food", ["farm", "mill", "granary", "bakery", "fishery", "hunter"]],
		["Materials", ["lumber", "sawmill", "quarry", "mine", "ironmine", "foundry"]],
		["Trade & crafts", ["market", "workshop", "winery", "tannery", "apothecary", "tavern", "harbor"]],
		["People & power", ["house", "barracks", "watchtower", "temple", "library", "blacksmith", "drillyard", "walls"]]]
	var shown := {}
	for g in groups:
		list.add_child(PixelUI.caps(str(g[0])))
		for type in g[1]:
			if Data.buildings().has(type):
				_build_row(type)
				shown[type] = true
	for type in Data.buildings().keys():
		if not shown.has(type) and Data.buildings()[type].get("buildable", false):
			_build_row(type)


func _build_row(type: String) -> void:
	var b: Dictionary = Data.buildings()[type]
	if not b.get("buildable", false):
		return
	var status := st.build_status(type)
	var on: bool = picking == type
	var v := _row(list, "on" if on else "plain")
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	v.add_child(h)
	h.add_child(_thumb(type, 64))
	var c := VBoxContainer.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.add_theme_constant_override("separation", 1)
	c.add_child(PixelUI.label(str(b.name), 17))
	c.add_child(PixelUI.wrap(str(b.does), 13, PixelUI.MUTED, 150))
	c.add_child(_cost_row(st.build_cost(type)))
	if not status.ok:
		c.add_child(PixelUI.wrap("✕ " + str(status.reason), 13, PixelUI.BAD, 150))
	h.add_child(c)
	var btn := PixelUI.button("Pick" if not on else "…", "blue" if status.ok else "paper", 15)
	btn.disabled = not status.ok
	btn.custom_minimum_size = Vector2(64, 44)
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.pressed.connect(func():
		picking = "" if picking == type else type
		if picking != "":
			Main.toast("Click a glowing plot")
		_rebuild_list())
	h.add_child(btn)


# ------------------------------------------------------------------ plot tab (a building or an empty plot)

func _list_plot() -> void:
	var s := selected
	if not st.city_terrain.has(s):
		_set_tab("build")
		return
	if not st.city.has(s):
		_list_empty_plot(s)
		return
	var type: String = st.city[s].type
	var b: Dictionary = Data.buildings()[type]
	var lvl := st.level_of(s)
	var br := st.branch_def(s)
	title_l.text = str(b.name).to_upper()
	info_l.text = ("level %d" % lvl) + ((" / %d" % int(b.max_level)) if b.has("max_level") else "")
	var head := _row(list, "violet")
	var hh := HBoxContainer.new()
	hh.add_theme_constant_override("separation", 8)
	head.add_child(hh)
	hh.add_child(_thumb(type, 72))
	var hc := VBoxContainer.new()
	hc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hc.add_child(PixelUI.wrap(str(b.does), 14, PixelUI.INK, 180))
	if not br.is_empty():
		hc.add_child(PixelUI.wrap("★ %s: %s" % [br.name, br.does], 14, PixelUI.VIOLET, 180))
	hh.add_child(hc)
	var staffed: bool = st.staffing().get(s, false)
	if int(b.get("workers", 0)) > 0:
		list.add_child(PixelUI.wrap("Workers: " + ("staffed" if staffed else "NOT staffed: needs %d idle people" % int(b.workers)), 14, PixelUI.GOOD if staffed else PixelUI.BAD))
	var prod: Dictionary = st.production_by_slot().get(s, {})
	if not prod.is_empty():
		var pr := HFlowContainer.new()
		pr.add_child(PixelUI.label("Today:", 15))
		for k in prod.keys():
			pr.add_child(PixelUI.res_icon(str(k), 24))
			pr.add_child(PixelUI.label("%+d" % int(prod[k]), 15, PixelUI.GOOD if int(prod[k]) > 0 else PixelUI.BAD))
		list.add_child(pr)
	elif b.has("modes") and staffed:
		list.add_child(PixelUI.wrap("Idle today: not enough %s in store." % ", ".join(PackedStringArray((st.mode_def(s).get("in", {}) as Dictionary).keys())), 14, PixelUI.BAD))
	var weekly := {}
	for id in (b.get("weekly", {}) as Dictionary).keys():
		weekly[id] = int(b.weekly[id])
	for id in (br.get("weekly", {}) as Dictionary).keys():
		weekly[id] = int(weekly.get(id, 0)) + int(br.weekly[id])
	if not weekly.is_empty():
		var parts: Array[String] = []
		for id in weekly.keys():
			parts.append("%d× %s" % [weekly[id], Champion.item(id).get("name", id)])
		list.add_child(PixelUI.wrap("Every week → storehouse: " + ", ".join(parts), 14, PixelUI.VIOLET))
	if b.has("max_level"):
		_upgrade_section(s, b, lvl)
	if b.has("modes"):
		_modes_section(s, b)
	if type in ["market", "blacksmith", "workshop", "tannery", "apothecary"]:
		var sb := PixelUI.button("Shop & crafting", "gold", 15)
		sb.pressed.connect(func(): _set_tab("shop"))
		list.add_child(sb)
	if type in ["blacksmith", "drillyard"]:
		var ab := PixelUI.button("Army upgrades (Age tab)", "paper", 15)
		ab.pressed.connect(func(): _set_tab("age"))
		list.add_child(ab)


func _upgrade_section(s: Vector2i, b: Dictionary, lvl: int) -> void:
	var us := st.upgrade_building_status(s)
	if lvl >= int(b.max_level):
		list.add_child(PixelUI.label("Fully upgraded", 15, PixelUI.GOOD))
		return
	if st.needs_branch(s):
		list.add_child(PixelUI.caps("Level 3 · choose a specialisation"))
		list.add_child(_cost_row(st.upgrade_cost(s)))
		if not us.ok:
			list.add_child(PixelUI.wrap("✕ " + str(us.reason), 13, PixelUI.BAD))
		for opt in st.branches_of(s):
			var v := _row(list, "plain")
			var h := HBoxContainer.new()
			v.add_child(h)
			var c := VBoxContainer.new()
			c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			c.add_child(PixelUI.label(str(opt.name), 16, PixelUI.VIOLET))
			c.add_child(PixelUI.wrap(str(opt.does), 13, PixelUI.MUTED, 160))
			h.add_child(c)
			var ob := PixelUI.button("Choose", "blue" if us.ok else "paper", 14)
			ob.disabled = not us.ok
			ob.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			var bid := str(opt.id)
			var bname := str(opt.name)
			ob.pressed.connect(func():
				if st.upgrade_building(s, bid):
					Audio.play("levelup", -4.0)
					city.pop_anim[s] = 0.5
					Main.toast("%s: %s" % [str(b.name), bname])
					Game.touch()
				_rebuild_list())
			h.add_child(ob)
		return
	var v := _row(list, "plain")
	var h := HBoxContainer.new()
	v.add_child(h)
	var c := VBoxContainer.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.add_child(PixelUI.label("Upgrade to level %d" % (lvl + 1), 16))
	c.add_child(PixelUI.wrap("output ×%s" % ["1.5", "2"][mini(lvl - 1, 1)], 13, PixelUI.MUTED))
	c.add_child(_cost_row(st.upgrade_cost(s)))
	if not us.ok:
		c.add_child(PixelUI.wrap("✕ " + str(us.reason), 13, PixelUI.BAD))
	h.add_child(c)
	var ub := PixelUI.button("Upgrade", "blue" if us.ok else "paper", 14)
	ub.disabled = not us.ok
	ub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ub.pressed.connect(func():
		if st.upgrade_building(s):
			Audio.play("build")
			city.pop_anim[s] = 0.5
			Main.toast("%s is now level %d" % [str(b.name), st.level_of(s)])
			Game.touch()
		_rebuild_list())
	h.add_child(ub)


func _modes_section(s: Vector2i, b: Dictionary) -> void:
	list.add_child(PixelUI.caps("Production"))
	for m in b.modes:
		var cur: bool = str(st.city[s].get("mode", "")) == str(m.id)
		var v := _row(list, "on" if cur else "plain")
		var h := HBoxContainer.new()
		v.add_child(h)
		var c := VBoxContainer.new()
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.add_child(PixelUI.label(("● " if cur else "○ ") + str(m.name), 15))
		var io := HFlowContainer.new()
		for r in (m.get("in", {}) as Dictionary).keys():
			io.add_child(PixelUI.res_icon(str(r), 22))
			io.add_child(PixelUI.label("−%d" % int(m["in"][r]), 14, PixelUI.BAD))
		if not (m.get("in", {}) as Dictionary).is_empty():
			io.add_child(PixelUI.label(" → ", 14, PixelUI.MUTED))
		for r in (m.get("out", {}) as Dictionary).keys():
			io.add_child(PixelUI.res_icon(str(r), 22))
			io.add_child(PixelUI.label("+%d" % int(m["out"][r]), 14, PixelUI.GOOD))
		c.add_child(io)
		h.add_child(c)
		if not cur:
			var mb := PixelUI.button("Use", "paper", 14)
			mb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			var mid := str(m.id)
			mb.pressed.connect(func():
				st.set_mode(s, mid)
				Game.touch()
				_rebuild_list())
			h.add_child(mb)


func _list_empty_plot(s: Vector2i) -> void:
	var t := str(st.city_terrain[s])
	title_l.text = {"plains": "OPEN LAND", "forest": "WOODS", "hills": "HILL", "water": "POND"}.get(t, t.to_upper())
	info_l.text = "empty plot"
	var cs := st.clear_status(s)
	var hint: String = {"plains": "Open meadow. Pick a building in the Build tab, then click here.",
		"water": "A pond. A Fishing pier stands on water; a Harbour must stand beside it.",
		"forest": "Lumber camps and hunters need woods beside them, so think before you cut.",
		"hills": "Mines must stand on hills."}.get(t, "")
	list.add_child(PixelUI.wrap(hint, 14, PixelUI.MUTED))
	if (cs.cost as Dictionary).is_empty():
		return
	var v := _row(list, "plain")
	var h := HBoxContainer.new()
	v.add_child(h)
	var c := VBoxContainer.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.add_child(PixelUI.label(str(Data.B("city.clear", {}).get(t, {}).get("name", "Clear")), 16))
	c.add_child(_cost_row(cs.cost))
	if not (cs.gain as Dictionary).is_empty():
		var g := HFlowContainer.new()
		g.add_child(PixelUI.label("gives ", 13, PixelUI.MUTED))
		for k in cs.gain.keys():
			g.add_child(PixelUI.res_icon(str(k), 22))
			g.add_child(PixelUI.label("+%d" % int(cs.gain[k]), 14, PixelUI.GOOD))
		c.add_child(g)
	if not cs.ok:
		c.add_child(PixelUI.wrap("✕ " + str(cs.reason), 13, PixelUI.BAD))
	h.add_child(c)
	var b := PixelUI.button("Clear", "blue" if cs.ok else "paper", 15)
	b.disabled = not cs.ok
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(func():
		if st.clear_land(s):
			Audio.play("build")
			city.pop_anim[s] = 0.5
			Main.toast("The plot is open land now")
			Game.touch()
		_rebuild_list())
	h.add_child(b)


# ------------------------------------------------------------------ army tab

func _list_army() -> void:
	title_l.text = "ARMY"
	var slots := int(Data.B("army.slots", 5))
	info_l.text = "%d / %d slots" % [st.party.size(), slots]
	list.add_child(PixelUI.wrap("Rank 1 stands in front. Upkeep: %d food a day." % st.upkeep(), 13, PixelUI.MUTED))
	list.add_child(PixelUI.caps("Formation"))
	for i in st.party.size():
		var e: Dictionary = st.party[i]
		var champ := str(e.kind) == "champion"
		var v := _row(list, "violet" if champ else "plain")
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 6)
		v.add_child(h)
		h.add_child(PixelUI.label("%d" % (i + 1), 24, PixelUI.VIOLET))
		var nm: String
		var line: String
		if champ:
			nm = st.champ.name + " (Champion)"
			line = "%d/%d HP · %s" % [st.champ.hp, st.champ.max_hp(), st.champ.weapon_info().name]
		else:
			var us := st.unit_stats(e)
			nm = str(us.name) + (" ★" if e.get("veteran", false) else "")
			line = "%d/%d HP · %s" % [int(e.hp), int(us.max_hp), str(Data.get_file("units")[e.type].role)]
		var c := VBoxContainer.new()
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.add_theme_constant_override("separation", 0)
		c.add_child(PixelUI.label(nm, 16))
		c.add_child(PixelUI.wrap(line, 13, PixelUI.MUTED, 140))
		h.add_child(c)
		var idx := i
		var up := PixelUI.button("▲", "paper", 13)
		up.custom_minimum_size = Vector2(36, 36)
		up.disabled = i == 0
		up.tooltip_text = "Move forward"
		up.pressed.connect(func(): st.move_in_party(idx, -1); Game.touch(); _rebuild_list())
		h.add_child(up)
		var dn := PixelUI.button("▼", "paper", 13)
		dn.custom_minimum_size = Vector2(36, 36)
		dn.disabled = i == st.party.size() - 1
		dn.tooltip_text = "Move back"
		dn.pressed.connect(func(): st.move_in_party(idx, 1); Game.touch(); _rebuild_list())
		h.add_child(dn)
		if not champ:
			var uid := str(e.uid)
			var acts := HBoxContainer.new()
			acts.add_theme_constant_override("separation", 6)
			v.add_child(acts)
			if not e.get("veteran", false):
				var vs := st.can_make_veteran(uid)
				var vb := PixelUI.button("Train veteran", "blue" if vs.ok else "paper", 13)
				vb.disabled = not vs.ok
				vb.tooltip_text = ("%s → %s" % [_cost_text(st.veteran_cost()), str(Data.get_file("units")[e.type].veteran.name)]) if vs.ok else str(vs.reason)
				vb.pressed.connect(func():
					if st.make_veteran(uid):
						Audio.play("levelup", -6.0)
						Main.toast("A veteran now")
						Game.touch()
					_rebuild_list())
				acts.add_child(vb)
			var db := PixelUI.button("Dismiss", "red", 13)
			db.tooltip_text = "Send them home (they rejoin the population)."
			db.pressed.connect(func(): st.dismiss(uid); Game.touch(); _rebuild_list())
			acts.add_child(db)
	list.add_child(PixelUI.caps("Recruit at the Barracks"))
	if not st.has_building("barracks"):
		list.add_child(PixelUI.wrap("Build a Barracks to recruit soldiers.", 14, PixelUI.BAD))
	var units: Dictionary = Data.get_file("units")
	for type in units.keys():
		if type == "champion" or str(type).begins_with("_"):
			continue
		var d: Dictionary = units[type]
		var rs := st.recruit_status(type)
		var v := _row(list, "plain")
		var h := HBoxContainer.new()
		v.add_child(h)
		var c := VBoxContainer.new()
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.add_theme_constant_override("separation", 0)
		c.add_child(PixelUI.label(str(d.name), 16))
		c.add_child(PixelUI.wrap("%s · HP %d · spd %d · def %d" % [d.role, int(d.hp), int(d.spd), int(d.def)], 13, PixelUI.MUTED, 160))
		c.add_child(_cost_row(d.cost))
		if not rs.ok:
			c.add_child(PixelUI.wrap("✕ " + str(rs.reason), 13, PixelUI.BAD, 160))
		h.add_child(c)
		var tt: String = type
		var b := PixelUI.button("Hire", "blue" if rs.ok else "paper", 14)
		b.disabled = not rs.ok
		b.custom_minimum_size = Vector2(64, 42)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.pressed.connect(func():
			var r := st.recruit(tt)
			if r.ok:
				Audio.play("coin")
				Main.toast("%s joins the band" % str(d.name))
				Game.touch()
			_rebuild_list())
		h.add_child(b)


# ------------------------------------------------------------------ age tab

func _list_age() -> void:
	title_l.text = "AGE"
	info_l.text = "now: %s" % st.age_name()
	var ages: Array = Data.get_file("ages").ages
	var cur: Dictionary = st.age_def(st.age)
	var v := _row(list, "violet")
	v.add_child(PixelUI.label("Age %s · %s" % ["I".repeat(st.age), cur.name], 22, PixelUI.VIOLET))
	v.add_child(PixelUI.wrap(str(cur.text), 13, PixelUI.MUTED))
	if st.age < ages.size():
		var nxt: Dictionary = st.age_def(st.age + 1)
		var as_ := st.age_status()
		var v2 := _row(list, "plain")
		v2.add_child(PixelUI.label("Next: Age %s · %s" % ["I".repeat(st.age + 1), nxt.name], 17))
		if nxt.get("locked", false):
			v2.add_child(PixelUI.wrap("Not in this demo yet.", 13, PixelUI.MUTED))
		else:
			for chk in as_.checks:
				v2.add_child(PixelUI.wrap(("✓ " if chk.ok else "✕ ") + str(chk.text), 13, PixelUI.GOOD if chk.ok else PixelUI.BAD))
			v2.add_child(PixelUI.caps("Unlocks"))
			for u in nxt.get("unlocks", []):
				v2.add_child(PixelUI.wrap("• " + str(u), 13, PixelUI.MUTED))
			var b := PixelUI.cta("Advance the age", "blue" if as_.ok else "paper", 20)
			b.disabled = not as_.ok
			b.pressed.connect(func():
				if st.advance_age():
					Audio.play("levelup")
					Main.toast("A new age: %s!" % st.age_name())
					Game.touch()
				_rebuild_list())
			v2.add_child(b)
	list.add_child(PixelUI.caps("Army upgrades"))
	var ups: Dictionary = Data.get_file("ages").upgrades
	for id in ups.keys():
		var u: Dictionary = ups[id]
		var us := st.upgrade_status(id)
		var done: bool = st.upgrades.has(id)
		var v3 := _row(list, "good" if done else "plain")
		var h := HBoxContainer.new()
		v3.add_child(h)
		var c := VBoxContainer.new()
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.add_theme_constant_override("separation", 0)
		c.add_child(PixelUI.label(str(u.name), 16))
		c.add_child(PixelUI.wrap(str(u.does), 13, PixelUI.MUTED, 160))
		if done:
			c.add_child(PixelUI.label("owned", 13, PixelUI.GOOD))
		else:
			c.add_child(_cost_row(u.cost))
			if not us.ok:
				c.add_child(PixelUI.wrap("✕ " + str(us.reason), 13, PixelUI.BAD, 160))
		h.add_child(c)
		if not done:
			var b := PixelUI.button("Buy", "blue" if us.ok else "paper", 14)
			b.disabled = not us.ok
			b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			var uid: String = id
			b.pressed.connect(func():
				if st.buy_upgrade(uid):
					Audio.play("build")
					Main.toast(str(u.name))
					Game.touch()
				_rebuild_list())
			h.add_child(b)


# ------------------------------------------------------------------ store tab (cargo + storehouse)

func _list_cargo() -> void:
	title_l.text = "STORE"
	info_l.text = "%d carried" % st.champ.cargo_total()
	var home := st.at_capital()
	list.add_child(PixelUI.caps("Storehouse · made by buildings"))
	if st.stash.is_empty():
		list.add_child(PixelUI.wrap("Empty. Bakeries, hunters, apothecaries and specialised buildings fill it every week.", 13, PixelUI.MUTED))
	else:
		list.add_child(PixelUI.wrap("%s takes these automatically when entering the capital, as far as the bag allows." % st.champ.name, 13, PixelUI.MUTED))
		for e in st.stash.duplicate(true):
			var id := str(e.id)
			var v := _row(list, "plain")
			var h := HBoxContainer.new()
			h.add_theme_constant_override("separation", 8)
			v.add_child(h)
			h.add_child(ItemIcon.make(id, 44, int(e.n)))
			var c := VBoxContainer.new()
			c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			c.add_child(PixelUI.label(str(Champion.item(id).get("name", id)), 15))
			c.add_child(PixelUI.wrap(str(Champion.item(id).get("desc", "")), 12, PixelUI.MUTED, 140))
			h.add_child(c)
			var tb := PixelUI.button("Take", "blue" if home else "paper", 14)
			tb.disabled = not home
			tb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			tb.pressed.connect(func():
				var r := st.take_from_stash(id)
				if r.ok:
					Audio.play("coin", -6.0)
					Game.touch()
				else:
					Main.toast(str(r.reason).capitalize(), Style.BAD)
				_rebuild_list())
			h.add_child(tb)
	list.add_child(PixelUI.caps("Champion's cargo"))
	list.add_child(PixelUI.wrap("Loot rides in %s's cargo and reaches the kingdom at the capital. Supplies loaded here pay for things on the road. Lost if %s falls." % [st.champ.name, st.champ.name], 13, PixelUI.MUTED))
	if not home:
		list.add_child(PixelUI.wrap("%s is away: loading needs the Champion at home." % st.champ.name, 14, PixelUI.BAD))
	for r in GameState.RES:
		var v := _row(list, "plain")
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 6)
		v.add_child(h)
		h.add_child(PixelUI.res_icon(r, 32))
		var c := VBoxContainer.new()
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.add_child(PixelUI.label(r.capitalize(), 15))
		c.add_child(PixelUI.label("cargo %d · kingdom %d" % [int(st.champ.cargo.get(r, 0)), int(st.res[r])], 12, PixelUI.MUTED))
		h.add_child(c)
		for amt in [-5, 5]:
			var b := PixelUI.button(("+%d" % amt) if amt > 0 else ("−%d" % -amt), "paper", 14)
			b.custom_minimum_size = Vector2(46, 36)
			b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			b.tooltip_text = "Load into the cargo" if amt > 0 else "Unload into the kingdom"
			var rr: String = r
			var a: int = amt
			b.disabled = not home or (a > 0 and int(st.res[r]) < a) or (a < 0 and int(st.champ.cargo.get(r, 0)) < -a)
			b.pressed.connect(func():
				if st.load_cargo(rr, a):
					Audio.play("coin", -6.0)
					Game.touch()
				_rebuild_list())
			h.add_child(b)


# ------------------------------------------------------------------ shop & crafting tab

func _list_shop() -> void:
	title_l.text = "SHOP"
	info_l.text = "bag %d/%d" % [st.champ.bag.size(), int(Data.get_file("items").get("bag_slots", 8))]
	var bag := PixelUI.button("Open the bag (I)", "gold", 15)
	bag.pressed.connect(open_bag)
	list.add_child(bag)
	list.add_child(PixelUI.caps("Market · paid from the treasury"))
	if not st.has_building("market"):
		list.add_child(PixelUI.wrap("Build a Market to buy gear for your Champion.", 13, PixelUI.BAD))
	for id in st.shop_list():
		_item_row(id, "Buy", {"gold": st.shop_price(id)}, "", func(): return st.buy(id), st.has_building("market"))
	var by_at := {}
	for id in st.craft_list():
		var at := str(Champion.item(id).craft.at)
		if not by_at.has(at):
			by_at[at] = []
		by_at[at].append(id)
	for at in by_at.keys():
		list.add_child(PixelUI.caps("Made at the %s" % str(Data.buildings()[at].name)))
		for id in by_at[at]:
			var cs := st.craft_status(id)
			var c: Dictionary = Champion.item(id).craft
			var extra := ""
			for iid in (c.get("items", {}) as Dictionary).keys():
				extra += "+ %d× %s (have %d)  " % [int(c.items[iid]), str(Champion.item(iid).name), st.have_item(iid)]
			if not cs.ok:
				extra += "✕ " + str(cs.reason)
			_item_row(id, "Make", c.get("cost", {}), extra, func(): return {"ok": st.craft(id), "reason": cs.reason}, cs.ok)


func _item_row(id: String, verb: String, cost: Dictionary, sub: String, fn: Callable, enabled: bool) -> void:
	var it := Champion.item(id)
	var v := _row(list, "violet" if str(it.rarity) == "rare" else "plain")
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	v.add_child(h)
	h.add_child(ItemIcon.make(id, 46))
	var c := VBoxContainer.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.add_theme_constant_override("separation", 0)
	c.add_child(PixelUI.label(str(it.name), 15, PixelUI.VIOLET if str(it.rarity) == "rare" else PixelUI.INK))
	c.add_child(_cost_row(cost))
	if sub != "":
		c.add_child(PixelUI.wrap(sub, 12, PixelUI.BAD if sub.contains("✕") else PixelUI.MUTED, 150))
	h.add_child(c)
	var b := PixelUI.button(verb, "blue" if enabled else "paper", 14)
	b.disabled = not enabled
	b.tooltip_text = str(it.get("desc", ""))
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(func():
		var r = fn.call()
		if r is Dictionary and r.get("ok", false):
			Audio.play("coin")
			Main.toast("%s → bag" % str(it.name))
			Game.touch()
		elif r is Dictionary:
			Main.toast(str(r.get("reason", "can't")).capitalize(), Style.BAD)
		_rebuild_list())
	h.add_child(b)


## Debug / tests: re-fit the camera after the state changed under the screen.
func refit() -> void:
	city.fit()
	_rebuild_list()
