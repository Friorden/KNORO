class_name Fx
extends RefCounted
## Small reusable animations: floating numbers, pops, shakes, count-ups.


## A "+40 food" that rises and fades from a screen position (on `parent`).
static func float_text(parent: Node, at: Vector2, text: String, color: Color, icon: String = "", delay: float = 0.0, size: int = 28) -> void:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if icon != "":
		box.add_child(ResIcon.make(icon, 24))
	var l := Style.hand(text, size, color)
	l.add_theme_color_override("font_outline_color", Style.NOTE)
	l.add_theme_constant_override("outline_size", 8)
	box.add_child(l)
	parent.add_child(box)
	box.position = at - Vector2(40, 20)
	box.modulate.a = 0.0
	box.scale = Vector2(0.7, 0.7)
	var tw := box.create_tween()
	tw.tween_interval(delay)
	tw.tween_property(box, "modulate:a", 1.0, 0.15)
	tw.parallel().tween_property(box, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(box, "position:y", box.position.y - 46, 1.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(box, "modulate:a", 0.0, 0.45)
	tw.tween_callback(box.queue_free)


static func pop_in(c: Control, delay: float = 0.0, from_scale: float = 0.85) -> void:
	c.pivot_offset = c.size / 2.0
	c.modulate.a = 0.0
	c.scale = Vector2(from_scale, from_scale)
	var tw := c.create_tween()
	tw.tween_interval(delay)
	tw.tween_property(c, "modulate:a", 1.0, 0.18)
	tw.parallel().tween_property(c, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


static func slide_in(c: Control, offset: Vector2, delay: float = 0.0, dur: float = 0.4) -> void:
	var target := c.position
	c.position = target + offset
	c.modulate.a = 0.0
	var tw := c.create_tween()
	tw.tween_interval(delay)
	tw.tween_property(c, "position", target, dur).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(c, "modulate:a", 1.0, dur * 0.6)


static func shake(n: CanvasItem, amount: float = 8.0, dur: float = 0.3) -> void:
	if not Settings.shake:
		return
	var base: Vector2 = n.position
	var tw := n.create_tween()
	var steps := 8
	for i in steps:
		var k := 1.0 - float(i) / steps
		tw.tween_property(n, "position", base + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * amount * k, dur / steps)
	tw.tween_property(n, "position", base, 0.05)


static func count(label: Label, from: int, to: int, dur: float = 0.6, prefix: String = "", suffix: String = "") -> void:
	var tw := label.create_tween()
	tw.tween_method(func(v: float): label.text = prefix + str(int(round(v))) + suffix, float(from), float(to), dur).set_trans(Tween.TRANS_SINE)
