extends Control
## Conversation scene: the camera "zooms" onto a character, the world stays
## visible behind them. Every conversation can hide an attribute check: a D20
## roll that opens a new branch, for better or worse.

var st: GameState
var id := ""
var dlg: Dictionary
var node_id := ""
var scene := Control.new()
var time := 0.0
var npc_color := Color("#5F8FC0")
var text_l: Label
var speaker_l: Label
var opts := VBoxContainer.new()
var roll_panel := PanelContainer.new()
var roll_box := VBoxContainer.new()
var slip := PanelContainer.new()
var slip_l: Label
var all_changes: Array = []
var mood := 0.0       # -1 annoyed .. 1 pleased (drives the NPC's face)
var talking := 0.0
var npc_kingdom := "purple"
var _npc_tex: Dictionary = {}

## Who stands in the scene: Tiny Swords unit sheet + draw scale + avatar in the name plate.
const NPC_LOOK := {
	"merchant": ["pawn_idle_gold", 4.0], "envoy": ["warrior_idle", 3.6], "harbor": ["archer_idle", 3.8],
	"smith": ["pawn_idle_hammer", 4.0], "hermit": ["monk_idle", 3.8],
}


func enter(data: Dictionary) -> void:
	st = Game.state
	id = str(data.get("id", "tobbin"))
	dlg = Data.dialogues()[id]
	var kref := str(dlg.get("kingdom", ""))
	var kid := st.world.merchant if kref == "merchant" else (st.world.rival if kref == "rival" else "")
	npc_color = Style.kingdom_color(kid) if kid != "" else Color("#9C8FB0")
	npc_kingdom = kid if kid != "" else "purple"
	_build()
	_show(str(dlg.start))


func _build() -> void:
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scene.draw.connect(_draw_scene)
	add_child(scene)
	var bgk := str(dlg.get("bg", "crossroads"))
	add_child(Atmosphere.make({"forge": "fire", "grove": "mist", "ruins": "mist", "harbor": "day"}.get(bgk, "dusk"), Vector2(0.28, 0.55)))
	var top := HBoxContainer.new()
	top.position = Vector2(34, 26)
	add_child(top)
	top.add_child(Style.caps("Week %d · Day %d · %s" % [st.week(), st.day_in_week(), _place_name()]))
	# name plate
	var plate := PanelContainer.new()
	plate.add_theme_stylebox_override("panel", Style.box(Style.CARD, 141, 4.0, Style.INK, 2.0, 12.0))
	plate.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	plate.offset_left = -360
	plate.offset_right = -60
	plate.offset_top = 70
	plate.rotation_degrees = 2
	add_child(plate)
	var pc := VBoxContainer.new()
	plate.add_child(pc)
	speaker_l = Style.hand(str(dlg.npc), 36)
	pc.add_child(speaker_l)
	var rel := ""
	var kref := str(dlg.get("kingdom", ""))
	if kref != "":
		var kid := st.world.merchant if kref == "merchant" else st.world.rival
		rel = " · relation: %s" % st.relation_label(kid)
	pc.add_child(Style.label(st.fmt(str(dlg.role)) + rel, 15, Style.body_bold, Style.PENCIL))
	# outcome slip (hidden until something lands)
	slip.add_theme_stylebox_override("panel", Style.box(Style.NOTE, 142, 6.0, Style.INK, 2.0, 16.0))
	slip.position = Vector2(48, 80)
	slip.rotation_degrees = -3
	slip.visible = false
	add_child(slip)
	slip_l = Style.hand("", 34, Style.GOOD)
	slip.add_child(slip_l)
	# dialogue box
	var bottom := HBoxContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 32
	bottom.offset_right = -32
	bottom.offset_top = -350
	bottom.offset_bottom = -26
	bottom.add_theme_constant_override("separation", 20)
	add_child(bottom)
	var dbox := PanelContainer.new()
	dbox.add_theme_stylebox_override("panel", Style.box(Style.CARD, 143, 5.0, Style.INK, 2.4, 26.0))
	dbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(dbox)
	var dc := VBoxContainer.new()
	dc.add_theme_constant_override("separation", 14)
	dbox.add_child(dc)
	text_l = Style.label("", 21, Style.body)
	text_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dc.add_child(text_l)
	opts.add_theme_constant_override("separation", 7)
	dc.add_child(opts)
	roll_panel.add_theme_stylebox_override("panel", Style.box(Style.CARD, 144, 5.0, Style.INK, 2.4, 18.0))
	roll_panel.custom_minimum_size = Vector2(340, 0)
	bottom.add_child(roll_panel)
	roll_box.alignment = BoxContainer.ALIGNMENT_CENTER
	roll_box.add_theme_constant_override("separation", 8)
	roll_panel.add_child(roll_box)
	_idle_roll_box()
	Fx.slide_in(dbox, Vector2(0, 80), 0.1)
	Fx.slide_in(roll_panel, Vector2(0, 80), 0.18)
	Fx.slide_in(plate, Vector2(60, 0), 0.25)


func _place_name() -> String:
	var t := st.world.tile(st.champ.pos)
	return str(t.name) if str(t.name) != "" else "on the road"


func _idle_roll_box() -> void:
	for c in roll_box.get_children():
		c.queue_free()
	roll_box.add_child(Style.caps("The roll"))
	var d := Dice.make(20, 110)
	d.shown = 20
	roll_box.add_child(d)
	var l := Style.label("Pick a [CHECK] option to gamble\non %s's attributes." % st.champ.name, 14, Style.body_bold, Style.PENCIL)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	roll_box.add_child(l)


func _process(d: float) -> void:
	time += d
	talking = maxf(0.0, talking - d)
	scene.queue_redraw()


# ------------------------------------------------------------------ flow

func _show(nid: String) -> void:
	node_id = nid
	var node: Dictionary = dlg.nodes[nid]
	for c in opts.get_children():
		c.queue_free()
	var txt := st.fmt(str(node.text))
	text_l.text = "%s:  %s" % [str(dlg.npc), txt]
	text_l.visible_ratio = 0.0
	talking = clampf(txt.length() * 0.025, 0.5, 2.5)
	Audio.play("paper", -10.0)
	var tw := text_l.create_tween()
	tw.tween_property(text_l, "visible_ratio", 1.0, clampf(txt.length() * 0.02, 0.4, 2.2))
	if node.has("effects"):
		var ch := st.apply(node.effects, str(dlg.npc), str(node.get("to", "cargo")))
		all_changes.append_array(ch)
		Game.touch()
		_show_changes(ch, str(node.get("stamp", "")))
	await tw.finished
	var i := 0
	for o in node.options:
		if o.has("once") and st.flags.has(str(o.once)):
			continue
		_add_option(o, i)
		i += 1


func _add_option(o: Dictionary, i: int) -> void:
	var is_check := o.has("check")
	var label := st.fmt(str(o.label))
	var sub := ""
	var enabled := true
	if is_check:
		var a := str(o.check.attr)
		var dc := int(o.check.dc)
		label = "[%s CHECK · DC %d]  %s" % [Champion.ATTR_NAMES[a].to_upper(), dc, label]
		sub = "you +%d · %d%%" % [st.champ.attr(a), GameState.chance(st.champ.attr(a), dc)]
	if o.has("cost"):
		var from := str(o.get("cost_from", "cargo"))
		enabled = st.can_afford(o.cost, from)
		var parts: Array[String] = []
		for k in o.cost.keys():
			parts.append("%d %s" % [int(o.cost[k]), k])
		sub = "costs " + ", ".join(parts) + (" · treasury" if from == "kingdom" else " · cargo")
	var b := Style.button("", Style.YELLOW if is_check else Style.CARD, 17, 150 + i)
	b.custom_minimum_size = Vector2(0, 50)
	b.disabled = not enabled
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 16
	row.offset_right = -16
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Style.label("%d.  %s" % [i + 1, label], 17, Style.body_heavy if is_check else Style.body_bold)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(l)
	if sub != "":
		var s := Style.label(sub, 14, Style.body_bold, Style.PENCIL)
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		s.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(s)
	b.add_child(row)
	b.pressed.connect(func(): _choose(o))
	opts.add_child(b)
	Fx.pop_in(b, 0.05 * i, 0.95)


func _choose(o: Dictionary) -> void:
	for c in opts.get_children():
		(c as Button).disabled = true
	if o.has("cost"):
		pass  # the destination node's effects pay it
	if o.has("check"):
		st.flags[str(o.get("once", "chk_" + node_id))] = st.day
		var res := st.check(str(o.check.attr), int(o.check.dc))
		await _animate_check(res)
		mood = 1.0 if res.success else -1.0
		_show(str(o.success if res.success else o.fail))
		return
	if o.get("end", false):
		_finish()
		return
	_show(str(o.next))


func _animate_check(res: Dictionary) -> void:
	for c in roll_box.get_children():
		c.queue_free()
	roll_box.add_child(Style.caps("%s check" % Champion.ATTR_NAMES[res.attr]))
	var d := Dice.make(20, 120)
	roll_box.add_child(d)
	var math := Style.hand("…", 32)
	math.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	roll_box.add_child(math)
	await get_tree().process_frame
	d.roll_to(int(res.roll), 1.1)
	await d.landed
	math.text = "%d + %s %d = %d · needs %d" % [res.roll, res.attr, res.bonus, res.total, res.dc]
	var stamp := Style.hand("Success" if res.success else "Failed", 46, Style.GOOD if res.success else Style.BAD)
	stamp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	roll_box.add_child(stamp)
	await get_tree().process_frame
	stamp.pivot_offset = stamp.size / 2.0
	stamp.rotation_degrees = -6
	stamp.scale = Vector2(2.0, 2.0)
	var tw := stamp.create_tween()
	tw.tween_property(stamp, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tw.finished
	Audio.play("stamp")
	Audio.play("success" if res.success else "fail", -4.0)
	if not res.success:
		var note := Style.label("Not a dead end. Listen to what happens.", 13, Style.body_bold, Style.PENCIL)
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		roll_box.add_child(note)
	await get_tree().create_timer(0.5).timeout


func _show_changes(ch: Array, stamp: String) -> void:
	var good := true
	for c in ch:
		if c.kind in ["food", "wood", "stone", "gold", "iron", "relation", "hp"] and int(c.amount) < 0:
			good = false
	if stamp != "":
		slip_l.text = st.fmt(stamp)
		slip_l.add_theme_color_override("font_color", Style.GOOD if good else Style.BAD)
		slip.visible = true
		slip.reset_size()
		Fx.pop_in(slip, 0.3, 0.6)
		Audio.play("coin" if good else "stamp", -2.0)
	var y := 0.0
	for c in ch:
		if c.kind in ["food", "wood", "stone", "gold", "iron", "xp", "hp"]:
			Fx.float_text(self, Vector2(size.x * 0.32, size.y * 0.45 - y), "%+d" % int(c.amount), Style.GOOD if int(c.amount) >= 0 else Style.BAD, c.kind, 0.4 + y / 200.0)
			y += 40
		elif c.kind == "relation":
			Fx.float_text(self, Vector2(size.x * 0.62, 190 + y), "%s %+d" % [c.label, int(c.amount)], Style.GOOD if int(c.amount) >= 0 else Style.BAD, "", 0.5)
			y += 40
		elif c.kind == "level":
			Audio.play("levelup")


func _finish() -> void:
	if id == "tobbin":
		pass
	Main.go("world", {"from": "dialogue", "changes": all_changes})


# ------------------------------------------------------------------ scene art

func _draw_scene() -> void:
	var ci := scene
	var bg := str(dlg.get("bg", "crossroads"))
	var bgt := Art.tex("bg_" + bg)
	if bgt:
		Art.draw_cover(ci, bgt, Rect2(Vector2.ZERO, size), time)
	else:
		ci.draw_rect(Rect2(Vector2.ZERO, size), Color("#3d3556"))
	# soft purple floor glow where the NPC stands, so the figure reads on any backdrop
	var base := Vector2(size.x * 0.72, size.y * 0.69)
	var sh := PackedVector2Array()
	for k in 24:
		var a := TAU * k / 24.0
		sh.append((base + Vector2(cos(a) * 210, sin(a) * 34)).round())
	ci.draw_colored_polygon(sh, Color(0.12, 0.06, 0.2, 0.45))
	_draw_npc(ci, base)


## The NPC: a Tiny Swords figure in their kingdom's colour, scaled up 4x (whole
## pixels), breathing with the sheet's idle animation, bobbing while talking.
func _draw_npc(ci: CanvasItem, base: Vector2) -> void:
	var portrait := str(dlg.get("portrait", "merchant"))
	if portrait == "ruins":
		var rt: Texture2D = load("res://assets/tinyswords/city/ruin_castle.png")
		var sz := rt.get_size() * 3.0
		ci.draw_texture_rect(rt, Rect2((base - Vector2(sz.x / 2.0, sz.y - 30)).round(), sz), false)
		return
	var look: Array = NPC_LOOK.get(portrait, NPC_LOOK.merchant)
	var col := npc_kingdom if npc_kingdom in ["red", "blue", "yellow", "purple", "black"] else "purple"
	var name := "%s_%s" % [col, look[0]]
	if not _npc_tex.has(name):
		var path := "res://assets/tinyswords/units/%s.png" % name
		if not ResourceLoader.exists(path):
			path = "res://assets/tinyswords/units/%s_%s.png" % [col, str(look[0]).replace("_gold", "").replace("_hammer", "")]
		_npc_tex[name] = load(path) if ResourceLoader.exists(path) else null
	var t: Texture2D = _npc_tex[name]
	if t == null:
		return
	var fw := t.get_height()
	var n := maxi(1, t.get_width() / fw)
	var frame := int(time * 8.0) % n
	var sc: float = look[1]
	var sz := Vector2(fw, fw) * sc
	var bob := (int(time * 6.0) % 2) * 4.0 if talking > 0.05 else 0.0
	ci.draw_set_transform(base.round(), 0.0, Vector2(-1, 1))
	ci.draw_texture_rect_region(t, Rect2(Vector2(-sz.x / 2.0, -sz.y * 0.74 - bob).round(), sz), Rect2(fw * frame, 0, fw, fw))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
