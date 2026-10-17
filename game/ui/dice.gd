class_name Dice
extends Control
## An animated die. sides = 6 draws a square with pips, 20 draws a d20 with a number.
## roll_to(value) tumbles for a moment, then lands on `value` with a bounce.

signal landed(value: int)

var sides := 6
var value := 1
var shown := 1
var spin := 0.0
var rolling := false
var tint := Color("#FFFDF6")
var px := 84.0


static func make(p_sides: int, p_px: float = 84.0) -> Dice:
	var d := Dice.new()
	d.sides = p_sides
	d.px = p_px
	d.custom_minimum_size = Vector2(p_px, p_px)
	d.pivot_offset = Vector2(p_px, p_px) / 2.0
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return d


func roll_to(v: int, duration: float = 0.9) -> void:
	value = v
	rolling = true
	Audio.play("dice", -2.0)
	var tw := create_tween()
	var steps := 12
	for i in steps:
		var t := duration / steps * (1.0 + float(i) / steps)
		tw.tween_callback(func():
			shown = randi_range(1, sides)
			spin = randf_range(-0.5, 0.5)
			queue_redraw())
		tw.tween_interval(t * 0.5)
	tw.tween_callback(func():
		shown = value
		spin = randf_range(-0.12, 0.12)
		rolling = false
		Audio.play("dice_land")
		queue_redraw())
	tw.tween_property(self, "scale", Vector2(1.25, 0.8), 0.06)
	tw.tween_property(self, "scale", Vector2(0.92, 1.1), 0.08)
	tw.tween_property(self, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func(): landed.emit(value))


func _process(_d: float) -> void:
	if rolling:
		position += Vector2(randf_range(-1.5, 1.5), randf_range(-1.5, 1.5)) * 0.0
		queue_redraw()


func _draw() -> void:
	var c := size / 2.0
	var r := px * 0.42
	draw_set_transform(c, spin, Vector2.ONE)
	if sides == 6:
		var rect := Rect2(Vector2(-r, -r), Vector2(r, r) * 2.0)
		var sb := StyleBoxFlat.new()
		sb.bg_color = tint
		sb.border_color = PixelUI.INK
		sb.set_border_width_all(3)
		sb.border_width_bottom = 6
		sb.set_corner_radius_all(int(r * 0.3))
		sb.corner_detail = 3
		sb.anti_aliasing = false
		sb.draw(get_canvas_item(), rect)
		var faces := {1: [Vector2(0, 0)], 2: [Vector2(-1, -1), Vector2(1, 1)], 3: [Vector2(-1, -1), Vector2(0, 0), Vector2(1, 1)],
			4: [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)],
			5: [Vector2(-1, -1), Vector2(1, -1), Vector2(0, 0), Vector2(-1, 1), Vector2(1, 1)],
			6: [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 0), Vector2(1, 0), Vector2(-1, 1), Vector2(1, 1)]}
		for p in faces[clampi(shown, 1, 6)]:
			draw_circle(p * r * 0.5, r * 0.15, Style.INK)
	else:
		var pts := PackedVector2Array()
		for k in 6:
			var a := deg_to_rad(60.0 * k - 90.0)
			pts.append(Vector2(cos(a), sin(a)) * r * 1.12)
		var sh := PackedVector2Array()
		for p in pts:
			sh.append(p + Vector2(4, 4))
		draw_colored_polygon(sh, Style.INK)
		draw_colored_polygon(pts, tint)
		var o := pts.duplicate()
		o.append(pts[0])
		draw_polyline(o, Style.INK, 2.6, true)
		var inner := PackedVector2Array([pts[0] * 0.15 + Vector2(0, -r * 0.55), Vector2(-r * 0.62, r * 0.42), Vector2(r * 0.62, r * 0.42)])
		inner.append(inner[0])
		draw_polyline(inner, Color(Style.INK, 0.35), 1.4, true)
		for k in [0, 2, 4]:
			draw_line(pts[k], inner[[0, 2, 1][k / 2]], Color(Style.INK, 0.25), 1.2, true)
		var txt := str(shown)
		var fs := int(px * 0.38)
		var w := Style.display.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(Style.display, Vector2(-w / 2.0, fs * 0.36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Style.INK)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
