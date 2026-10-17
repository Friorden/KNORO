@tool
class_name SketchBox
extends StyleBox
## A StyleBox that draws like a pen on paper: a slightly wobbly outline, a
## second faint pencil line that never quite matches, and an optional hard
## ink shadow. Used by every button and panel through the theme.
##
## The wobble is deterministic (seeded from `seed` and the box size), so a
## panel doesn't shimmer frame to frame — it just looks hand-drawn.

@export var fill := Color("#FBF7EE")
@export var ink := Color("#2F2A35")
@export var line_width := 2.0
@export var seed := 1
@export var shadow := 0.0
@export var wobble := 1.6
@export var corner := 10.0
@export var offset := Vector2.ZERO
@export var pencil := true


func _get_points(rect: Rect2, s: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var r := minf(corner, minf(rect.size.x, rect.size.y) * 0.3)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(s, int(rect.size.x), int(rect.size.y)))
	# uneven corner radii, like the mockups: big-small-big-small
	var radii := [r * rng.randf_range(0.6, 1.4), r * rng.randf_range(0.3, 0.8), r * rng.randf_range(0.6, 1.4), r * rng.randf_range(0.3, 0.8)]
	var centers := [
		rect.position + Vector2(radii[0], radii[0]),
		Vector2(rect.end.x - radii[1], rect.position.y + radii[1]),
		rect.end - Vector2(radii[2], radii[2]),
		Vector2(rect.position.x + radii[3], rect.end.y - radii[3]),
	]
	var starts := [PI, PI * 1.5, 0.0, PI * 0.5]
	for c in 4:
		var steps := 4
		for i in steps + 1:
			var a: float = starts[c] + (PI * 0.5) * float(i) / float(steps)
			var p: Vector2 = centers[c] + Vector2(cos(a), sin(a)) * radii[c]
			pts.append(p)
		# a couple of points along each straight edge, nudged off the line
		var nxt: Vector2 = centers[(c + 1) % 4] + Vector2(cos(starts[(c + 1) % 4]), sin(starts[(c + 1) % 4])) * radii[(c + 1) % 4]
		var cur: Vector2 = pts[pts.size() - 1]
		var segs := clampi(int(cur.distance_to(nxt) / 90.0), 1, 6)
		for k in range(1, segs + 1):
			var p2 := cur.lerp(nxt, float(k) / float(segs + 1))
			var n := (nxt - cur).orthogonal().normalized()
			pts.append(p2 + n * rng.randf_range(-wobble, wobble))
	return pts


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	rect.position += offset
	var pts := _get_points(rect, seed)
	if shadow > 0.0:
		var sh := PackedVector2Array()
		for p in pts:
			sh.append(p + Vector2(shadow, shadow))
		RenderingServer.canvas_item_add_polygon(to_canvas_item, sh, PackedColorArray([ink]))
	if fill.a > 0.0:
		RenderingServer.canvas_item_add_polygon(to_canvas_item, pts, PackedColorArray([fill]))
	if line_width > 0.0:
		var closed := pts.duplicate()
		closed.append(pts[0])
		RenderingServer.canvas_item_add_polyline(to_canvas_item, closed, PackedColorArray([ink]), line_width, true)
		if pencil:
			var p2 := _get_points(rect.grow(-1.5), seed + 17)
			p2.append(p2[0])
			var faint := Color(ink, 0.22)
			RenderingServer.canvas_item_add_polyline(to_canvas_item, p2, PackedColorArray([faint]), 0.9, true)
