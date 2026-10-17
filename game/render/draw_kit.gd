class_name DrawKit
extends RefCounted
## KNORO's drawing vocabulary: ink-fantasy shapes with graphic comic shading.
##
## Rules every shape follows (from graphguide §67–84):
##   - one light from the upper-left: lit faces lighter, right/under faces darker
##   - hard, flat cast shadows thrown to the lower-right (no gradients)
##   - confident dark ink contour, slightly irregular
##   - kingdom colour only on accents (banners, roof trim), never whole objects

const INK := Color("#2A2430")
const SHADOW := Color(0.16, 0.12, 0.2, 0.26)
const LIGHT_DIR := Vector2(1.0, 0.45)      # direction shadows are thrown


static func jitter(p: Vector2, s: float, k: int) -> Vector2:
	return p + Vector2(sin(k * 12.9898 + p.x * 0.07), cos(k * 78.233 + p.y * 0.05)) * s


static func wobbly(ci: CanvasItem, pts: PackedVector2Array, fill: Color, line: Color = INK, width: float = 2.0, seed: int = 0, closed: bool = true, wob: float = 0.8) -> void:
	if fill.a > 0.0 and pts.size() >= 3:
		ci.draw_colored_polygon(pts, fill)
	if width > 0.0:
		var j := PackedVector2Array()
		for i in pts.size():
			j.append(jitter(pts[i], wob, seed + i))
		if closed:
			j.append(j[0])
		ci.draw_polyline(j, line, width, true)


## Hard cast shadow: the shape squashed and thrown to the lower-right.
static func cast(ci: CanvasItem, pts: PackedVector2Array, base_y: float, length: float = 0.55, a: float = 1.0) -> void:
	var out := PackedVector2Array()
	for p in pts:
		var hgt := maxf(0.0, base_y - p.y)
		out.append(Vector2(p.x + hgt * length * LIGHT_DIR.x, base_y + hgt * 0.22))
	ci.draw_colored_polygon(out, Color(SHADOW, SHADOW.a * a))


static func shadow(ci: CanvasItem, at: Vector2, rx: float, ry: float, a: float = 0.22) -> void:
	var pts := PackedVector2Array()
	for i in 16:
		var ang := TAU * i / 16.0
		pts.append(at + Vector2(cos(ang) * rx, sin(ang) * ry))
	ci.draw_colored_polygon(pts, Color(SHADOW.r, SHADOW.g, SHADOW.b, a))


# ------------------------------------------------------------------ nature

## Pointed tree (conifer): two-tone, ink contour, cast shadow.
static func tree(ci: CanvasItem, base: Vector2, s: float = 1.0, col: Color = Color("#6F9466"), seed: int = 0, sway: float = 0.0) -> void:
	var w := 10.0 * s
	var h := 30.0 * s
	var lean := (fmod(seed * 0.618, 1.0) - 0.5) * 4.0 * s + sway * 1.5
	var top := base + Vector2(lean, -h)
	var body := PackedVector2Array([base + Vector2(-w, -3 * s), top, base + Vector2(w, -3 * s)])
	cast(ci, body, base.y, 0.6)
	ci.draw_line(base + Vector2(0, -4 * s), base + Vector2(0, 3 * s), INK, 2.4 * s, true)
	ci.draw_colored_polygon(body, col)
	# shaded right half
	ci.draw_colored_polygon(PackedVector2Array([top, base + Vector2(w, -3 * s), base + Vector2(lean * 0.3 + 1.0, -3 * s)]), col.darkened(0.28))
	# a notch of tiers
	ci.draw_line(base + Vector2(-w * 0.55, -h * 0.38), base + Vector2(w * 0.1, -h * 0.45), Color(INK, 0.35), 1.2, true)
	var o := body.duplicate()
	o.append(body[0])
	ci.draw_polyline(o, INK, 1.8, true)


## Broad round crown tree: lit blob + shadow blob.
static func round_tree(ci: CanvasItem, base: Vector2, s: float = 1.0, col: Color = Color("#9BB97E"), seed: int = 0) -> void:
	var c := base + Vector2(0, -17 * s)
	var pts := PackedVector2Array()
	for i in 12:
		var a := TAU * i / 12.0
		var r := 11.0 * s * (1.0 + 0.1 * sin(i * 2.3 + seed))
		pts.append(c + Vector2(cos(a) * r, sin(a) * r * 0.88))
	cast(ci, pts, base.y, 0.5)
	ci.draw_line(base, base + Vector2(1, -9 * s), INK, 2.6 * s, true)
	ci.draw_colored_polygon(pts, col)
	var shade := PackedVector2Array()
	for i in 7:
		var a := -PI * 0.25 + PI * i / 6.0
		shade.append(c + Vector2(cos(a) * 10.5 * s, sin(a) * 9.5 * s))
	shade.append(c + Vector2(2 * s, 2 * s))
	ci.draw_colored_polygon(shade, col.darkened(0.25))
	ci.draw_circle(c + Vector2(-4, -4) * s, 2.6 * s, col.lightened(0.25))
	var o := pts.duplicate()
	o.append(pts[0])
	ci.draw_polyline(o, INK, 1.8, true)


## A grove: several trees of different heights overlapping, one shadow mass under them.
static func grove(ci: CanvasItem, c: Vector2, size: float, seed: int, n: int = 5) -> void:
	shadow(ci, c + Vector2(size * 0.12, size * 0.16), size * 0.62, size * 0.2, 0.2)
	var spots: Array = []
	for i in n:
		var a := float(i) / n * TAU + seed * 0.7
		var r := size * (0.18 + 0.22 * fmod(seed * 0.37 + i * 0.61, 1.0))
		spots.append(c + Vector2(cos(a) * r, sin(a) * r * 0.45))
	spots.sort_custom(func(a, b): return a.y < b.y)
	for i in spots.size():
		var k := fmod(seed * 0.13 + i * 0.29, 1.0)
		var g := Color("#5E8A5E").lerp(Color("#86A86A"), k)
		if k > 0.62:
			round_tree(ci, spots[i], 0.9 + k * 0.5, Color("#8DB074").lerp(Color("#A7C285"), k), seed + i)
		else:
			tree(ci, spots[i], 0.85 + k * 0.6, g, seed + i)


## Angular brush ridge: lit face + dark underside, chunky ink outline.
static func hill(ci: CanvasItem, base: Vector2, s: float = 1.0, col: Color = Color("#D8BC88"), seed: int = 0) -> void:
	var w := 20.0 * s
	var peak := base + Vector2(-2 * s + fmod(seed * 0.7, 1.0) * 6 * s, -15 * s)
	var pts := PackedVector2Array([base + Vector2(-w, 0), base + Vector2(-w * 0.45, -9 * s), peak, base + Vector2(w * 0.5, -8 * s), base + Vector2(w, 0)])
	cast(ci, pts, base.y, 0.45)
	ci.draw_colored_polygon(pts, col)
	ci.draw_colored_polygon(PackedVector2Array([peak, base + Vector2(w * 0.5, -8 * s), base + Vector2(w, 0), Vector2(peak.x + 3 * s, base.y)]), col.darkened(0.22))
	ci.draw_line(base + Vector2(-w * 0.3, -5 * s), base + Vector2(-w * 0.05, -9 * s), Color(INK, 0.4), 1.2, true)
	var o := pts.duplicate()
	ci.draw_polyline(o, INK, 2.0, true)


static func mountain(ci: CanvasItem, base: Vector2, s: float = 1.0, seed: int = 0) -> void:
	var peak := base + Vector2(3 * s, -40 * s)
	var pts := PackedVector2Array([base + Vector2(-24, 0) * s, base + Vector2(-10, -22) * s, peak, base + Vector2(14, -20) * s, base + Vector2(26, 0) * s])
	cast(ci, pts, base.y, 0.5)
	ci.draw_colored_polygon(pts, Color("#C9BFB2"))
	ci.draw_colored_polygon(PackedVector2Array([peak, base + Vector2(14, -20) * s, base + Vector2(26, 0) * s, base + Vector2(5, 0) * s]), Color("#9C9082"))
	var cap := PackedVector2Array([peak, peak + Vector2(-9, 13) * s, peak + Vector2(-3, 10) * s, peak + Vector2(2, 15) * s, peak + Vector2(8, 11) * s])
	ci.draw_colored_polygon(cap, Color("#FFFDF6"))
	ci.draw_polyline(pts, INK, 2.2, true)
	ci.draw_line(peak + Vector2(2, 16) * s, base + Vector2(8, -2) * s, Color(INK, 0.35), 1.3, true)


static func wave(ci: CanvasItem, at: Vector2, s: float = 1.0, col: Color = Color("#FFFDF6"), phase: float = 0.0) -> void:
	var pts := PackedVector2Array()
	for i in 7:
		var t := float(i) / 6.0
		pts.append(at + Vector2((t - 0.5) * 18 * s, sin(t * PI + phase) * -2.0 * s))
	ci.draw_polyline(pts, col, 1.6, true)


static func tuft(ci: CanvasItem, p: Vector2, s: float = 1.0, col: Color = Color("#7E9A62")) -> void:
	ci.draw_line(p, p + Vector2(-3, -6) * s, col, 1.4, true)
	ci.draw_line(p, p + Vector2(0, -8) * s, col, 1.4, true)
	ci.draw_line(p, p + Vector2(3, -6) * s, col, 1.4, true)


static func flower(ci: CanvasItem, p: Vector2, col: Color) -> void:
	ci.draw_circle(p, 2.2, col)
	ci.draw_circle(p, 0.9, Color("#FFF6DC"))


# ------------------------------------------------------------------ settlements

## Cartoon house: oversized roof, compressed walls, stone foundation, crooked
## chimney, asymmetrical windows, kingdom-coloured banner/roof trim.
static func house(ci: CanvasItem, base: Vector2, s: float, accent: Color, wall: Color = Color("#F3E7D3"), seed: int = 0, roof: Color = Color("#B9644E")) -> void:
	var w := 11.0 * s
	var h := 9.0 * s
	var lean := (fmod(seed * 0.41, 1.0) - 0.5) * 3.0 * s
	var body := PackedVector2Array([base + Vector2(-w, 0), base + Vector2(-w, -h), base + Vector2(w, -h), base + Vector2(w, 0)])
	var roofp := PackedVector2Array([base + Vector2(-w - 5 * s, -h + 2 * s), base + Vector2(lean, -h - 17 * s), base + Vector2(w + 5 * s, -h + 2 * s)])
	var all := PackedVector2Array([base + Vector2(-w - 5 * s, -h + 2 * s), base + Vector2(lean, -h - 17 * s), base + Vector2(w + 5 * s, -h + 2 * s), base + Vector2(w, 0), base + Vector2(-w, 0)])
	cast(ci, all, base.y, 0.55)
	# foundation
	ci.draw_rect(Rect2(base + Vector2(-w - 1, -2 * s), Vector2(w * 2 + 2, 3 * s)), Color("#A69A8C"))
	ci.draw_colored_polygon(body, wall)
	ci.draw_colored_polygon(PackedVector2Array([base + Vector2(w * 0.35, 0), base + Vector2(w * 0.35, -h), base + Vector2(w, -h), base + Vector2(w, 0)]), wall.darkened(0.16))
	var bo := body.duplicate()
	bo.append(body[0])
	ci.draw_polyline(bo, INK, 1.8, true)
	# chimney
	var ch := base + Vector2(w * 0.45, -h - 9 * s)
	DrawKit.wobbly(ci, PackedVector2Array([ch, ch + Vector2(1.5, -7) * s, ch + Vector2(5.5, -6.5) * s, ch + Vector2(5, 2) * s]), Color("#8C7F74"), INK, 1.5, seed)
	ci.draw_colored_polygon(roofp, roof)
	ci.draw_colored_polygon(PackedVector2Array([roofp[1], roofp[2], base + Vector2(lean + 2 * s, -h + 2 * s)]), roof.darkened(0.25))
	ci.draw_line(roofp[0] + Vector2(1, 0), roofp[2] - Vector2(1, 0), accent, 2.6 * s, true)
	var ro := roofp.duplicate()
	ro.append(roofp[0])
	ci.draw_polyline(ro, INK, 2.0, true)
	ci.draw_rect(Rect2(base + Vector2(-w * 0.75, -h * 0.75), Vector2(3.5, 3.5) * s), Color("#F2C96A"))
	ci.draw_rect(Rect2(base + Vector2(-2 * s, -6 * s), Vector2(4.5, 6) * s), INK)


static func flag(ci: CanvasItem, pole_base: Vector2, s: float, col: Color, t: float, h: float = 30.0) -> void:
	var top := pole_base + Vector2(0, -h * s)
	ci.draw_line(pole_base, top, INK, 2.4 * s, true)
	var pts := PackedVector2Array()
	var n := 6
	for i in n + 1:
		var u := float(i) / n
		pts.append(top + Vector2(u * 19 * s, sin(t * 5.0 + u * 4.0) * 2.6 * s * u))
	for i in range(n, -1, -1):
		var u := float(i) / n
		pts.append(top + Vector2(u * 19 * s, 12 * s - u * 3.0 * s + sin(t * 5.0 + u * 4.0) * 2.6 * s * u))
	ci.draw_colored_polygon(pts, col)
	var o := pts.duplicate()
	o.append(pts[0])
	ci.draw_polyline(o, INK, 1.6 * s, true)


## Tiny person for crowds: big head, compact cloak, two tones.
static func person(ci: CanvasItem, base: Vector2, s: float, cloak: Color, t: float = 0.0, face: int = 1) -> void:
	shadow(ci, base + Vector2(3, 1), 8 * s, 2.6 * s)
	var bob := sin(t * 3.0) * 0.6 * s
	var body := PackedVector2Array([base + Vector2(0, -15 * s + bob), base + Vector2(7 * s, 0), base + Vector2(-7 * s, 0)])
	ci.draw_colored_polygon(body, cloak)
	ci.draw_colored_polygon(PackedVector2Array([base + Vector2(0, -15 * s + bob), base + Vector2(7 * s, 0), base + Vector2(1 * s, 0)]), cloak.darkened(0.22))
	var o := body.duplicate()
	o.append(body[0])
	ci.draw_polyline(o, INK, 1.5, true)
	var head := base + Vector2(0, -19 * s + bob)
	ci.draw_circle(head, 5.5 * s, Color("#F3D9C2"))
	ci.draw_arc(head, 5.5 * s, 0, TAU, 16, INK, 1.5, true)
	ci.draw_circle(head + Vector2(1.8 * face * s, -0.2 * s), 0.9 * s, INK)


# ------------------------------------------------------------------ icons

static func res_icon(ci: CanvasItem, kind: String, c: Vector2, s: float = 1.0) -> void:
	match kind:
		"food":
			ci.draw_line(c + Vector2(0, 8) * s, c + Vector2(0, -8) * s, INK, 1.6, true)
			for k in 3:
				var y := -6.0 + k * 5.0
				wobbly(ci, PackedVector2Array([c + Vector2(0, y) * s, c + Vector2(-5, y - 3) * s, c + Vector2(-1, y - 4) * s]), Color("#E2C36B"), INK, 1.2, k)
				wobbly(ci, PackedVector2Array([c + Vector2(0, y) * s, c + Vector2(5, y - 3) * s, c + Vector2(1, y - 4) * s]), Color("#E2C36B"), INK, 1.2, k + 5)
		"wood":
			var pts := PackedVector2Array([c + Vector2(-8, -4) * s, c + Vector2(6, -4) * s, c + Vector2(8, 0) * s, c + Vector2(6, 4) * s, c + Vector2(-8, 4) * s])
			wobbly(ci, pts, Color("#C79A6B"), INK, 1.5, 4)
			ci.draw_circle(c + Vector2(-8, 0) * s, 4 * s, Color("#E7D0AE"))
			ci.draw_arc(c + Vector2(-8, 0) * s, 4 * s, 0, TAU, 12, INK, 1.4, true)
		"stone":
			wobbly(ci, PackedVector2Array([c + Vector2(-9, 5) * s, c + Vector2(-6, -3) * s, c + Vector2(0, -7) * s, c + Vector2(7, -3) * s, c + Vector2(9, 5) * s]), Color("#C9C1B4"), INK, 1.5, 6)
		"iron":
			wobbly(ci, PackedVector2Array([c + Vector2(-9, 4) * s, c + Vector2(-5, -4) * s, c + Vector2(6, -4) * s, c + Vector2(9, 4) * s]), Color("#8D97A6"), INK, 1.5, 9)
			ci.draw_line(c + Vector2(-4, -2) * s, c + Vector2(4, -2) * s, Color("#D6DCE5"), 1.4, true)
		"gold":
			ci.draw_circle(c, 8 * s, Color("#E9C85A"))
			ci.draw_arc(c, 8 * s, 0, TAU, 18, INK, 1.6, true)
			ci.draw_arc(c, 5 * s, 0, TAU, 14, Color(INK, 0.4), 1.0, true)
		"pop":
			ci.draw_circle(c + Vector2(0, -3) * s, 3.6 * s, Color("#F7E4CF"))
			ci.draw_arc(c + Vector2(0, -3) * s, 3.6 * s, 0, TAU, 12, INK, 1.4, true)
			wobbly(ci, PackedVector2Array([c + Vector2(-7, 8) * s, c + Vector2(0, 1) * s, c + Vector2(7, 8) * s]), Color("#C6B8DC"), INK, 1.4, 7)
		"hp":
			var hp := PackedVector2Array()
			for i in 20:
				var a := TAU * i / 20.0
				hp.append(c + Vector2(16.0 * pow(sin(a), 3), -(13.0 * cos(a) - 5.0 * cos(2 * a) - 2.0 * cos(3 * a) - cos(4 * a))) * 0.45 * s)
			wobbly(ci, hp, Color("#E07A66"), INK, 1.4, 8)
		"xp":
			var st := PackedVector2Array()
			for i in 10:
				var a := -PI / 2 + TAU * i / 10.0
				st.append(c + Vector2(cos(a), sin(a)) * (8.0 if i % 2 == 0 else 3.6) * s)
			wobbly(ci, st, Color("#C6B8DC"), INK, 1.4, 9)
		"moves":
			wobbly(ci, PackedVector2Array([c + Vector2(-6, 6) * s, c + Vector2(-3, -6) * s, c + Vector2(3, -6) * s, c + Vector2(6, 6) * s]), Color("#B58F62"), INK, 1.4, 10)
		"cargo":
			wobbly(ci, PackedVector2Array([c + Vector2(-8, -3) * s, c + Vector2(8, -3) * s, c + Vector2(7, 7) * s, c + Vector2(-7, 7) * s]), Color("#C79A6B"), INK, 1.5, 11)
			ci.draw_line(c + Vector2(-4, -3) * s, c + Vector2(-2, -8) * s, INK, 1.4, true)
			ci.draw_line(c + Vector2(4, -3) * s, c + Vector2(2, -8) * s, INK, 1.4, true)
			ci.draw_line(c + Vector2(-2, -8) * s, c + Vector2(2, -8) * s, INK, 1.4, true)
		"sword":
			ci.draw_line(c + Vector2(-7, 7) * s, c + Vector2(7, -7) * s, Color("#D8D1C4"), 4.0 * s, true)
			ci.draw_line(c + Vector2(-7, 7) * s, c + Vector2(7, -7) * s, INK, 1.2, true)
			ci.draw_line(c + Vector2(-7, 0) * s, c + Vector2(0, 7) * s, INK, 2.4, true)
		_:
			ci.draw_circle(c, 6 * s, Color("#E3CFA6"))
			ci.draw_arc(c, 6 * s, 0, TAU, 12, INK, 1.4, true)
