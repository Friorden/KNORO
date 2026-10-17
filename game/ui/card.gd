class_name Card
extends Control
## A modal paper card: illustration, title, text and choices. Used for hex
## events, places, camping and level-ups. After a choice the same card plays
## the dice roll and shows the outcome, then waits for "Continue".

signal chosen(idx: int)
signal closed

var dim := ColorRect.new()
var panel := PanelContainer.new()
var body := VBoxContainer.new()
var options_box := VBoxContainer.new()
var result_box := VBoxContainer.new()
var art: EventArt
var text_label: Label


static func open(parent: Node, title: String, text: String, art_key: String, options: Array, tint: Color = Color("#D46A55")) -> Card:
	var c := Card.new()
	parent.add_child(c)
	c._build(title, text, art_key, options, tint)
	return c


func _build(title: String, text: String, art_key: String, options: Array, tint: Color) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	dim.color = Color(Style.INK, 0.0)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	create_tween().tween_property(dim, "color:a", 0.38, 0.25)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	panel.add_theme_stylebox_override("panel", PixelUI.box("nine_paper", Vector4(34, 28, 34, 30)))
	panel.custom_minimum_size = Vector2(640, 0)
	center.add_child(panel)
	body.add_theme_constant_override("separation", 12)
	panel.add_child(body)
	if art_key != "":
		art = EventArt.make(art_key, 596, 196)
		art.tint = tint
		body.add_child(art)
	var t := PixelUI.label(title, 34, PixelUI.VIOLET)
	body.add_child(t)
	text_label = PixelUI.wrap(text, 18, PixelUI.INK, 596)
	body.add_child(text_label)
	options_box.add_theme_constant_override("separation", 8)
	body.add_child(options_box)
	for i in options.size():
		var o: Dictionary = options[i]
		var b := PixelUI.button("", "paper" if not o.get("special", false) else "gold", 17)
		b.custom_minimum_size = Vector2(596, 52)
		b.disabled = not o.get("enabled", true)
		var row := HBoxContainer.new()
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row.offset_left = 16
		row.offset_right = -16
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var l := PixelUI.label(o.label, 17, PixelUI.INK if not b.disabled else PixelUI.MUTED)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(l)
		if o.get("sub", "") != "":
			var s := PixelUI.label(o.sub, 14, PixelUI.MUTED)
			s.mouse_filter = Control.MOUSE_FILTER_IGNORE
			s.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			row.add_child(s)
		b.add_child(row)
		var idx := i
		b.pressed.connect(func(): chosen.emit(idx))
		options_box.add_child(b)
	result_box.add_theme_constant_override("separation", 10)
	result_box.visible = false
	body.add_child(result_box)
	Audio.play("paper")
	await get_tree().process_frame
	panel.pivot_offset = panel.size / 2.0
	Fx.pop_in(panel, 0.0, 0.8)


## Plays the outcome: optional d20 check, the result text, and resource changes.
func show_result(res: Dictionary) -> void:
	options_box.visible = false
	result_box.visible = true
	var chk: Dictionary = res.get("check", {})
	if not chk.is_empty():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 22)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		result_box.add_child(row)
		var d := Dice.make(20, 96)
		row.add_child(d)
		var math := VBoxContainer.new()
		row.add_child(math)
		var m1 := PixelUI.label("%s check · needs %d" % [chk.attr, chk.dc], 15, PixelUI.MUTED)
		math.add_child(m1)
		var m2 := PixelUI.label("…", 34)
		math.add_child(m2)
		await get_tree().process_frame
		d.roll_to(int(chk.roll))
		await d.landed
		m2.text = "%d + %d = %d" % [chk.roll, chk.bonus, chk.total]
		var stamp := PixelUI.label("SUCCESS" if chk.success else "FAILED", 40, PixelUI.GOOD if chk.success else PixelUI.BAD)
		var sp := PanelContainer.new()
		var sbx := Style.box(Color(0, 0, 0, 0), 77, 0.0, Style.GOOD if chk.success else Style.BAD, 3.0, 4.0)
		sbx.content_margin_left = 12
		sbx.content_margin_right = 12
		sp.add_theme_stylebox_override("panel", sbx)
		sp.add_child(stamp)
		row.add_child(sp)
		await get_tree().process_frame
		sp.pivot_offset = sp.size / 2.0
		sp.rotation_degrees = -8
		sp.scale = Vector2(2.2, 2.2)
		sp.modulate.a = 0.0
		var tw := sp.create_tween()
		tw.tween_property(sp, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(sp, "modulate:a", 1.0, 0.1)
		await tw.finished
		Audio.play("stamp")
		Audio.play("success" if chk.success else "fail", -4.0)
		Fx.shake(panel, 5.0, 0.2)
	var txt := str(res.get("text", ""))
	if txt != "":
		var l := PixelUI.wrap("", 18, PixelUI.INK, 596)
		result_box.add_child(l)
		l.text = txt
		l.visible_ratio = 0.0
		var tw2 := l.create_tween()
		tw2.tween_property(l, "visible_ratio", 1.0, clampf(txt.length() * 0.018, 0.3, 1.4))
		await tw2.finished
	var changes: Array = res.get("changes", [])
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 10)
	result_box.add_child(chips)
	var delay := 0.0
	for ch in changes:
		var chip := Card.change_chip(ch)
		if chip:
			chips.add_child(chip)
			Fx.pop_in(chip, delay)
			delay += 0.08
			if ch.kind in ["food", "wood", "stone", "gold", "iron"] and int(ch.amount) > 0:
				Audio.play("coin", -6.0)
	var cont := PixelUI.cta("Continue →", "blue", 22)
	cont.size_flags_horizontal = Control.SIZE_SHRINK_END
	result_box.add_child(cont)
	await cont.pressed
	close()


static func change_chip(ch: Dictionary) -> Control:
	var kind := str(ch.kind)
	var amt := int(ch.amount)
	var text := ""
	var icon := ""
	match kind:
		"food", "wood", "stone", "gold", "iron", "pop", "hp", "xp", "moves":
			icon = kind
			text = ("%+d " % amt) + ({"hp": "HP", "xp": "XP", "pop": "people", "moves": "moves"}.get(kind, kind))
		"max_hp":
			icon = "hp"
			text = "+%d max HP" % amt
		"level":
			icon = "xp"
			text = "Level %d!" % amt
		"relation":
			text = "%s %+d" % [ch.get("label", ""), amt]
		"item":
			text = "Got: %s" % ch.get("label", "")
		"item_lost":
			text = "Used: %s" % ch.get("label", "")
		"reveal":
			text = "Map revealed"
		"end_day":
			text = "Day ends"
		_:
			return null
	if str(ch.get("to", "")) == "cargo" and amt > 0 and kind in ["food", "wood", "stone", "gold", "iron"]:
		text += " → cargo"
	var p := PanelContainer.new()
	var good := amt >= 0 and kind != "end_day"
	var fill := Color("#E6EFD9") if good else Color("#F6DCD3")
	if kind == "item" and str(ch.get("rarity", "")) == "rare":
		fill = Color("#E3D6F7")
	elif kind == "item_lost":
		fill = Color("#ECE6DA")
		good = true
	var b := Style.box(fill, amt + 3, 0.0, Style.INK, 1.5, 6.0)
	b.content_margin_left = 10
	b.content_margin_right = 12
	p.add_theme_stylebox_override("panel", b)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	if icon != "":
		row.add_child(ResIcon.make(icon, 20))
	row.add_child(PixelUI.label(text, 15, PixelUI.GOOD if good else PixelUI.BAD))
	p.add_child(row)
	return p


func close() -> void:
	Audio.play("paper", -4.0)
	var tw := create_tween()
	tw.tween_property(panel, "modulate:a", 0.0, 0.18)
	tw.parallel().tween_property(panel, "position:y", panel.position.y + 30, 0.2)
	tw.parallel().tween_property(dim, "color:a", 0.0, 0.2)
	await tw.finished
	closed.emit()
	queue_free()
