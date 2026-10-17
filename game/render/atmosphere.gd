class_name Atmosphere
extends Control
## Light and air on top of painted scenes: drifting dust motes or rising
## embers, a flickering warm glow, light shafts and a soft vignette.
## mode: "day", "dusk", "night", "fire", "mist".

var mode := "day"
var glow_at := Vector2(0.5, 0.6)     # fire position, 0..1 of the screen
var time := 0.0
var parts: Array = []
var _vig: GradientTexture2D


static func make(p_mode: String, p_glow: Vector2 = Vector2(0.5, 0.6)) -> Atmosphere:
	var a := Atmosphere.new()
	a.mode = p_mode
	a.glow_at = p_glow
	a.mouse_filter = Control.MOUSE_FILTER_IGNORE
	a.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return a


func _ready() -> void:
	for i in (70 if mode == "fire" else 55):
		parts.append(_new_part(true))


func _new_part(anywhere: bool) -> Dictionary:
	var vs := Vector2(1920, 1080)
	if mode == "fire":
		var c := glow_at * vs
		return {"p": c + Vector2(randf_range(-120, 120), randf_range(-40, 20) - (randf() * 500 if anywhere else 0.0)),
			"v": Vector2(randf_range(-14, 14), randf_range(-70, -30)), "r": randf_range(1.5, 3.5), "life": randf(), "ph": randf() * TAU}
	return {"p": Vector2(randf() * vs.x, randf() * vs.y), "v": Vector2(randf_range(4, 14), randf_range(-6, 3)),
		"r": randf_range(1.2, 3.2), "life": randf(), "ph": randf() * TAU}


func _process(d: float) -> void:
	time += d
	for i in parts.size():
		var p: Dictionary = parts[i]
		p.p += (p.v + Vector2(sin(time * 1.3 + p.ph) * 8, 0)) * d
		p.life += d * (0.25 if mode == "fire" else 0.06)
		if p.life > 1.0 or p.p.y < -20 or p.p.x > size.x + 20:
			parts[i] = _new_part(false)
			parts[i].life = 0.0
	queue_redraw()


func _draw() -> void:
	var vs := size
	var flick := 0.5 + 0.3 * sin(time * 9.0) + 0.2 * sin(time * 23.0)
	# warm/cool light
	match mode:
		"fire":
			var c := glow_at * vs
			for k in 6:
				var r := 140.0 + k * 90.0 + flick * 18.0
				draw_circle(c, r, Color(1.0, 0.62, 0.3, 0.045 - k * 0.006))
		"dusk", "day":
			# light shafts from the upper left
			for k in 4:
				var x := vs.x * (0.08 + k * 0.11) + sin(time * 0.2 + k) * 20
				var shaft := PackedVector2Array([Vector2(x, 0), Vector2(x + 60 + k * 10, 0), Vector2(x + 420, vs.y), Vector2(x + 300, vs.y)])
				draw_colored_polygon(shaft, Color(1.0, 0.93, 0.75, 0.035 + 0.01 * sin(time * 0.5 + k)))
		"mist":
			for k in 5:
				var y := vs.y * (0.45 + k * 0.1)
				draw_rect(Rect2(-100 + sin(time * 0.1 + k) * 80, y, vs.x + 200, 60), Color(1, 1, 1, 0.05))
	# particles
	for p in parts:
		var a: float = sin(p.life * PI)
		if mode == "fire":
			var col := Color(1.0, 0.75 - p.life * 0.4, 0.35, a * 0.9)
			draw_circle(p.p, p.r * (1.0 - p.life * 0.5), col)
			draw_circle(p.p, p.r * 2.6, Color(1.0, 0.6, 0.3, a * 0.12))
		else:
			var col := Color(1.0, 0.97, 0.88, a * (0.35 if mode != "night" else 0.25))
			draw_circle(p.p, p.r, col)
	# vignette: one radial gradient, transparent centre -> dark corners
	if _vig == null:
		var g := Gradient.new()
		g.set_color(0, Color(0.08, 0.05, 0.1, 0.0))
		g.set_color(1, Color(0.08, 0.05, 0.1, 0.55 if mode in ["night", "fire"] else 0.35))
		g.add_point(0.55, Color(0.08, 0.05, 0.1, 0.0))
		_vig = GradientTexture2D.new()
		_vig.gradient = g
		_vig.fill = GradientTexture2D.FILL_RADIAL
		_vig.fill_from = Vector2(0.5, 0.5)
		_vig.fill_to = Vector2(1.08, 1.08)
		_vig.width = 256
		_vig.height = 256
	draw_texture_rect(_vig, Rect2(Vector2.ZERO, vs), false)
