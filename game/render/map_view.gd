class_name MapView
extends Node2D
## Draws the hex world in Tiny Swords pixel art (see assets/LICENSES.md).
## It never changes the state; the world screen tells it what to highlight.
##
## Geometry: pointy-top hexes 128 px wide with 2:1 iso slopes (two pack tiles),
## rows 80 px apart, so the pack draws at 1x. Grass is sampled in world space
## so neighbouring hexes merge into one landscape; ink returns only where the
## land changes (coasts, cliffs), and a faint grid keeps the hexes readable.
## Hills stand 32 px tall, mountains 52 px, on cliff faces drawn in 2-px
## columns that step down the slope (pixels stay square, nothing is sheared).
##
## Layers, back to front:
##   water    - animated foam along every shore (redrawn ~10x a second)
##   terrain  - tops, cliffs, rivers, roads, borders, fog, nature (static)
##   fogfx    - mist lifting off newly revealed hexes
##   overlay  - reachable cells, hover, path preview
##   objects  - capitals, places, camps, patrols, caravans, cairns (y-sorted)
##   (the Champion token is added above these by the world screen)
##   clouds

var state: GameState
var size := 64.0                       # "radius" used by callers for offsets
var time := 0.0

var hover := Vector2i(-999, -999)
var path: Array = []
var reachable: Dictionary = {}
var show_reach := false
var reveal_t: Dictionary = {}
var flash: Dictionary = {}

var water := Node2D.new()
var terrain := Node2D.new()
var fogfx := Node2D.new()
var overlay := Node2D.new()
var objects := Node2D.new()
var clouds := Node2D.new()

var _order: Array = []
var _cloud_data: Array = []
var _caravans: Array = []
var _water_tick := 0.0
var _bounds := Rect2()
var tex: Dictionary = {}
var feet: Dictionary = {}

const W := 128.0
const ROW := 80.0
const HEX := [Vector2(0, -56), Vector2(64, -24), Vector2(64, 24), Vector2(0, 56), Vector2(-64, 24), Vector2(-64, -24)]
const ACROSS := [Vector2i(1, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(0, -1)]
const DIR_TO_EDGE := {0: 1, 1: 0, 2: 5, 3: 4, 4: 3, 5: 2}   # Hex.DIRS index -> edge index
const RAISE := {"hills": 32.0, "mountain": 52.0}
const TS := "res://assets/tinyswords/"
const INK := Color("#161c2e")
const CREAM := Color("#fbf3df")
const FOG := Color("#cfc6dc")
const FOG_DARK := Color("#b8aecb")
const BAND := [Color("#9fd38a"), Color("#ffd75e"), Color("#ff8a7a")]


func setup(p_state: GameState) -> void:
	state = p_state
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for n in [water, terrain, fogfx, overlay, objects, clouds]:
		add_child(n)
	terrain.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	water.draw.connect(_draw_water)
	terrain.draw.connect(_draw_terrain)
	fogfx.draw.connect(_draw_fogfx)
	overlay.draw.connect(_draw_overlay)
	objects.draw.connect(_draw_objects)
	clouds.draw.connect(_draw_clouds)
	_order = state.world.tiles.keys()
	_order.sort_custom(func(a, b):
		var pa := base_of(a)
		var pb := base_of(b)
		return pa.y < pb.y or (pa.y == pb.y and pa.x < pb.x))
	var r := Rect2()
	var first := true
	for h in state.world.tiles.keys():
		var p := base_of(h)
		if first:
			r = Rect2(p, Vector2.ZERO)
			first = false
		else:
			r = r.expand(p)
	_bounds = r.grow(64)
	var rng := RandomNumberGenerator.new()
	rng.seed = state.world.seed_value
	for i in 6:
		_cloud_data.append({"x": rng.randf_range(_bounds.position.x - 300, _bounds.end.x), "y": rng.randf_range(_bounds.position.y, _bounds.end.y),
			"v": rng.randf_range(8.0, 16.0), "k": i % 2})
	for i in state.world.road_paths.size():
		var p: Array = state.world.road_paths[i]
		if p.size() > 3:
			_caravans.append({"path": p, "t": rng.randf_range(0.0, float(p.size() - 1)), "dir": 1.0 if i % 2 == 0 else -1.0, "speed": rng.randf_range(0.3, 0.45), "kind": i})


# ------------------------------------------------------------------ textures

func t(name: String) -> Texture2D:
	if not tex.has(name):
		var path := TS + name + ".png"
		if not ResourceLoader.exists(path):
			path = "res://assets/" + name + ".png"     # packs outside Tiny Swords (assets/units, assets/props)
		tex[name] = load(path) if ResourceLoader.exists(path) else null
		if tex[name]:
			(tex[name] as Texture2D).set_meta("ts_name", name)
			var img: Image = (tex[name] as Texture2D).get_image()
			var used := img.get_region(Rect2i(0, 0, _frame_w(tex[name]), img.get_height())).get_used_rect()
			feet[name] = Vector2(used.position.x + used.size.x / 2.0, used.end.y)
	return tex[name]


## Frame width of a sheet: Tiny Swords animations use square frames, Pinero
## strips have 3 frames, everything else is a single still image.
static func frame_w(tx: Texture2D) -> int:
	var name := str(tx.get_meta("ts_name", ""))
	if name.contains("pinero_"):
		return tx.get_width() / 3
	if name.contains("woodtower"):
		return 256
	if name.contains("kp_kingpig"):
		return 152
	if name.contains("kp_pig"):
		return 136
	if name.contains("th_") or name.contains("pb_"):
		return tx.get_width() / maxi(1, int(Actor._frame_counts().get(name.get_file(), 1)))
	for pre in ["tree", "bush", "Sheep", "units/", "city/fire", "city/waterrock", "Water Foam", "city/sheep_grass"]:
		if name.begins_with(pre):
			return tx.get_height()
	return tx.get_width()


func _frame_w(tx: Texture2D) -> int:
	return MapView.frame_w(tx)


func spr(ci: CanvasItem, name: String, base: Vector2, frame: int = 0, flip := false, mod := Color.WHITE) -> void:
	var tx := t(name)
	if tx == null:
		return
	var fw := _frame_w(tx)
	var n := maxi(1, tx.get_width() / fw)
	var src := Rect2(fw * posmod(frame, n), 0, fw, tx.get_height())
	var f: Vector2 = feet[name]
	if flip:
		ci.draw_set_transform(base.round(), 0.0, Vector2(-1, 1))
		ci.draw_texture_rect_region(tx, Rect2(-f, src.size), src, mod)
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		ci.draw_texture_rect_region(tx, Rect2((base - f).round(), src.size), src, mod)


# ------------------------------------------------------------------ geometry / API

func bounds() -> Rect2:
	return _bounds


## Flat position of a hex (ground level).
func base_of(h: Vector2i) -> Vector2:
	return Vector2(W * (h.x + h.y * 0.5), ROW * h.y)


func _raise(h: Vector2i) -> float:
	if not state.world.has(h) or not state.is_explored(h):
		return 0.0
	return float(RAISE.get(str(state.world.tile(h).terrain), 0.0))


## Top-face centre of a hex (raised for hills and mountains).
func center_of(h: Vector2i) -> Vector2:
	return base_of(h) - Vector2(0, _raise(h))


func hex_at(local_point: Vector2) -> Vector2i:
	var r := int(round(local_point.y / ROW))
	var best := Vector2i(-999, -999)
	var bd := 1e12
	for dr in [-1, 0, 1, 2]:
		var rr: int = r + dr
		var q := int(round(local_point.x / W - rr * 0.5))
		for dq in [-1, 0, 1]:
			var h := Vector2i(q + dq, rr)
			if not state.world.has(h):
				continue
			var d := local_point - center_of(h)
			var dd := d.x * d.x + d.y * d.y * 1.8
			if dd < bd:
				bd = dd
				best = h
	return best


func refresh_terrain() -> void:
	terrain.queue_redraw()
	water.queue_redraw()


func refresh_overlay() -> void:
	overlay.queue_redraw()


func animate_reveal(hexes: Array) -> void:
	for h in hexes:
		reveal_t[h] = 0.0
	terrain.queue_redraw()
	water.queue_redraw()


func pulse(h: Vector2i) -> void:
	flash[h] = 1.2


func _process(delta: float) -> void:
	time += delta
	if not reveal_t.is_empty():
		for h in reveal_t.keys():
			reveal_t[h] = minf(1.0, reveal_t[h] + delta * 1.6)
			if reveal_t[h] >= 1.0:
				reveal_t.erase(h)
		fogfx.queue_redraw()
	if not flash.is_empty():
		for h in flash.keys():
			flash[h] -= delta
			if flash[h] <= 0.0:
				flash.erase(h)
		overlay.queue_redraw()
	_water_tick += delta
	if _water_tick > 0.1:
		_water_tick = 0.0
		water.queue_redraw()
	for c in _caravans:
		c.t += delta * c.speed * c.dir
		var last := float(c.path.size() - 1)
		if c.t >= last:
			c.t = last
			c.dir = -1.0
		elif c.t <= 0.0:
			c.t = 0.0
			c.dir = 1.0
	objects.queue_redraw()
	for cd in _cloud_data:
		cd.x += cd.v * delta
		if cd.x > _bounds.end.x + 300:
			cd.x = _bounds.position.x - 600
	clouds.queue_redraw()
	if show_reach or not path.is_empty():
		overlay.queue_redraw()


# ------------------------------------------------------------------ drawing helpers

func _pts(c: Vector2, inset := 0.0) -> PackedVector2Array:
	var p := PackedVector2Array()
	for v in HEX:
		p.append(c + v * (1.0 - inset / 64.0))
	return p


func _textured(ci: CanvasItem, c: Vector2, tx: Texture2D, mod := Color.WHITE) -> void:
	var pts := _pts(c)
	var uv := PackedVector2Array()
	for p in pts:
		uv.append(p / 64.0)
	ci.draw_colored_polygon(pts, mod, uv, tx)


func _outline(ci: CanvasItem, c: Vector2, col: Color, w: float, inset: float) -> void:
	var pts := _pts(c, inset)
	pts.append(pts[0])
	ci.draw_polyline(pts, col, w)


func _shadow(ci: CanvasItem, at: Vector2, rx: float, ry: float, a := 0.36) -> void:
	var sh := PackedVector2Array()
	for i in 18:
		var ang := TAU * i / 18.0
		sh.append((at + Vector2(cos(ang) * rx, sin(ang) * ry)).round())
	ci.draw_colored_polygon(sh, Color(0.24, 0.13, 0.36, a))


func _cliff(ci: CanvasItem, ctr: Vector2, height: float) -> void:
	var tx := t("cliff")
	var top := ctr - Vector2(0, height)
	var h := minf(height + 6.0, 64.0)
	for x in range(-64, 64, 2):
		var bottom := 56.0 - absf(x + 1) / 2.0
		var src_x := posmod(int(ctr.x) + x, 64)
		ci.draw_texture_rect_region(tx, Rect2(top + Vector2(x, bottom), Vector2(2, h)), Rect2(src_x, 0, 2, h))
	ci.draw_polyline(PackedVector2Array([ctr + Vector2(-64, 24), ctr + Vector2(0, 56), ctr + Vector2(64, 24)]), INK, 3.0)


func _land(h: Vector2i) -> bool:
	return state.world.has(h) and str(state.world.tile(h).terrain) != "water"


func _label(ci: CanvasItem, at: Vector2, text: String, fs: int = 18, col: Color = INK) -> void:
	var f := Style.body_heavy
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var r := Rect2((at - Vector2(w / 2.0 + 12, 14)).round(), Vector2(w + 24, 30))
	PixelUI.paper_tag(ci, r)
	ci.draw_string(f, r.position + Vector2(12, 21), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _bubble(ci: CanvasItem, at: Vector2, text: String, col: Color = Color("#ffd75e")) -> void:
	var p := (at + Vector2(0, int(time * 3.0) % 2 * 3)).round()
	ci.draw_rect(Rect2(p - Vector2(15, 15), Vector2(30, 30)), INK)
	ci.draw_rect(Rect2(p - Vector2(12, 12), Vector2(24, 24)), col)
	ci.draw_rect(Rect2(p - Vector2(12, 12), Vector2(24, 4)), col.lightened(0.35))
	ci.draw_colored_polygon(PackedVector2Array([p + Vector2(-6, 14), p + Vector2(6, 14), p + Vector2(0, 22)]), INK)
	var f := Style.body_heavy
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	ci.draw_string(f, p + Vector2(-w / 2.0, 8), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, INK)


func _flag(ci: CanvasItem, at: Vector2, col: Color) -> void:
	var p := at.round()
	ci.draw_rect(Rect2(p + Vector2(-2, -44), Vector2(4, 46)), INK)
	ci.draw_rect(Rect2(p + Vector2(-1, -43), Vector2(2, 44)), Color("#b48150"))
	var wv := int(time * 4.0) % 2 * 2
	var fl := PackedVector2Array([p + Vector2(2, -44), p + Vector2(26, -40 + wv), p + Vector2(20, -33), p + Vector2(26, -26 + wv), p + Vector2(2, -26)])
	ci.draw_colored_polygon(fl, col)
	fl.append(fl[0])
	ci.draw_polyline(fl, INK, 2.0)


# ------------------------------------------------------------------ water (foam)

func _draw_water() -> void:
	var ft := t("Water Foam")
	for h in _order:
		if not _land(h) or not state.is_explored(h):
			continue
		var c := base_of(h)
		for i in 6:
			var nb: Vector2i = h + ACROSS[i]
			if _land(nb):
				continue
			var mid: Vector2 = c + (HEX[i] + HEX[(i + 1) % 6]) / 2.0
			var fr := Rect2(192 * posmod(int(time * 9.0) + h.x * 5 + h.y * 3 + i * 2, 16), 0, 192, 192)
			water.draw_texture_rect_region(ft, Rect2((mid - Vector2(96, 100)).round(), Vector2(192, 192)), fr)
	for h in _order:
		var tl: Dictionary = state.world.tile(h)
		if tl.terrain == "water" and state.is_explored(h) and Hex.hash01(h, 4) < 0.18:
			spr(water, "city/waterrock%d" % (1 + int(Hex.hash01(h, 5) * 4) % 4), base_of(h) + Vector2(Hex.hash01(h, 6) * 50 - 25, 14), int(time * 6.0) + h.x)


# ------------------------------------------------------------------ terrain

func _draw_terrain() -> void:
	var ci := terrain
	var gp := t("grass_plains")
	var gh := t("grass_hills")
	for h in _order:
		var tl: Dictionary = state.world.tile(h)
		if not state.is_explored(h) or tl.terrain == "water":
			continue
		var b := base_of(h)
		match str(tl.terrain):
			"hills":
				_cliff(ci, b, RAISE.hills)
				_textured(ci, center_of(h), gh)
			"mountain":
				_cliff(ci, b, RAISE.mountain)
				_textured(ci, center_of(h), gh, Color(0.8, 0.84, 0.9))
			_:
				_textured(ci, b, gp)
		if tl.owner != "":
			ci.draw_colored_polygon(_pts(center_of(h), 2.0), Color(Style.kingdom_color(str(tl.owner)), 0.10))
	for h in _order:
		if not state.is_explored(h) or not _land(h):
			continue
		var c := center_of(h)
		for i in 6:
			var a: Vector2 = c + HEX[i]
			var b2: Vector2 = c + HEX[(i + 1) % 6]
			var nb: Vector2i = h + ACROSS[i]
			if not _land(nb):
				ci.draw_line(a, b2, Color("#d8f3e4"), 6.0)
				ci.draw_line(a, b2, INK, 3.0)
			elif _raise(h) > _raise(nb):
				ci.draw_line(a, b2, INK, 3.0)
			elif i < 3:
				ci.draw_line(a, b2, Color(0.08, 0.2, 0.1, 0.13), 2.0)
	_draw_rivers(ci)
	_draw_roads(ci)
	_draw_borders(ci)
	for h in _order:
		if state.is_explored(h):
			continue
		var c := base_of(h)
		ci.draw_colored_polygon(_pts(c, -1.0), FOG)
		if Hex.hash01(h, 41) < 0.5:
			ci.draw_rect(Rect2((c + Vector2(Hex.hash01(h, 42) * 60 - 40, Hex.hash01(h, 43) * 30 - 15)).round(), Vector2(28, 6)), FOG_DARK)
		for i in 6:
			var nb: Vector2i = h + ACROSS[i]
			if state.world.has(nb) and state.is_explored(nb):
				ci.draw_line(c + HEX[i], c + HEX[(i + 1) % 6], Color(1, 1, 1, 0.6), 4.0)
	for h in _order:
		if state.is_explored(h):
			_decorate(ci, h, state.world.tile(h))


func _decorate(ci: CanvasItem, h: Vector2i, tl: Dictionary) -> void:
	var c := center_of(h)
	var busy: bool = tl.place != "" or tl.road
	match str(tl.terrain):
		"forest":
			var offs := [Vector2(-28, -8), Vector2(24, -2), Vector2(-4, 22)]
			if busy:
				offs = [Vector2(-40, 4)]
			for i in offs.size():
				var p: Vector2 = c + offs[i] + Vector2(Hex.hash01(h, 20 + i) * 10 - 5, Hex.hash01(h, 30 + i) * 6 - 3)
				_shadow(ci, p + Vector2(8, 2), 30, 9)
				spr(ci, "tree%d" % (1 + int(Hex.hash01(h, 10 + i) * 4) % 4), p, int(Hex.hash01(h, 40 + i) * 6))
		"hills":
			if not busy:
				spr(ci, "rock%d" % (1 + int(Hex.hash01(h, 11) * 4) % 4), c + Vector2(Hex.hash01(h, 12) * 50 - 25, Hex.hash01(h, 13) * 20))
				if Hex.hash01(h, 14) < 0.4:
					spr(ci, "bush%d" % (1 + int(Hex.hash01(h, 15) * 4) % 4), c + Vector2(Hex.hash01(h, 16) * 40 - 30, 18))
		"mountain":
			spr(ci, "city/goldstone%d" % (4 + int(Hex.hash01(h, 80) * 3)), c + Vector2(-20, 20))
			spr(ci, "rock4", c + Vector2(26, 10))
			if Hex.hash01(h, 81) > 0.45:
				spr(ci, "rock%d" % (1 + int(Hex.hash01(h, 82) * 3)), c + Vector2(4, 34))
		"plains":
			if busy:
				return
			var v := Hex.hash01(h, 90)
			if v < 0.22:
				spr(ci, "bush%d" % (1 + int(Hex.hash01(h, 91) * 4) % 4), c + Vector2(Hex.hash01(h, 92) * 70 - 35, Hex.hash01(h, 93) * 30 - 6))
			elif v < 0.36:
				spr(ci, "city/deco_%02d" % (7 + int(Hex.hash01(h, 94) * 6)), c + Vector2(Hex.hash01(h, 95) * 70 - 35, Hex.hash01(h, 96) * 30 - 6))
			elif v < 0.42:
				spr(ci, "rock%d" % (1 + int(Hex.hash01(h, 97) * 3)), c + Vector2(Hex.hash01(h, 98) * 60 - 30, 10))
			elif v > 0.94:
				spr(ci, "tree%d" % (1 + int(Hex.hash01(h, 99) * 4) % 4), c + Vector2(26, 6))


func _known(pts: PackedVector2Array) -> Array:
	var segs: Array = []
	var cur := PackedVector2Array()
	for p in pts:
		if state.is_explored(hex_at(p)):
			cur.append(p)
		else:
			if cur.size() > 1:
				segs.append(cur)
			cur = PackedVector2Array()
	if cur.size() > 1:
		segs.append(cur)
	return segs


func _draw_rivers(ci: CanvasItem) -> void:
	var wc := Color("#47aba9")
	for rp in state.world.river_paths:
		if rp.size() < 2:
			continue
		var pts := PackedVector2Array()
		for h in rp:
			pts.append(center_of(h) + Vector2((Hex.hash01(h, 5) - 0.5) * 30.0, 6))
		for seg in _known(_smooth(pts, 5)):
			ci.draw_polyline(seg, INK, 20.0)
			ci.draw_polyline(seg, Color("#d8f3e4"), 16.0)
			ci.draw_polyline(seg, wc, 12.0)
			var hl := PackedVector2Array()
			for p in seg:
				hl.append(p + Vector2(-2, -2))
			_dashed(ci, hl, Color(1, 1, 1, 0.55), 2.0, 6.0, 14.0)


func _draw_roads(ci: CanvasItem) -> void:
	for p in state.world.road_paths:
		var pts := PackedVector2Array()
		for h in p:
			pts.append(center_of(h) + Vector2(0, 8))
		for seg in _known(_smooth(pts, 5)):
			ci.draw_polyline(seg, Color("#866353"), 16.0)
			ci.draw_polyline(seg, Color("#d5aa60"), 12.0)
			ci.draw_polyline(seg, Color("#e8c98a"), 6.0)


func _draw_borders(ci: CanvasItem) -> void:
	for kid in state.world.capitals.keys():
		var col := Style.kingdom_color(kid)
		for e in state.world.border_edges(kid):
			var h: Vector2i = e[0]
			if not state.is_explored(h):
				continue
			var i: int = DIR_TO_EDGE.get(int(e[1]), 0)
			var c := center_of(h)
			var a: Vector2 = c + HEX[i] * 0.88
			var b: Vector2 = c + HEX[(i + 1) % 6] * 0.88
			_dashed(ci, PackedVector2Array([a, b]), INK, 7.0, 10.0, 6.0)
			_dashed(ci, PackedVector2Array([a, b]), col, 4.0, 10.0, 6.0)


# ------------------------------------------------------------------ fog fx

func _draw_fogfx() -> void:
	for h in reveal_t.keys():
		var k: float = reveal_t[h]
		fogfx.draw_colored_polygon(_pts(base_of(h), -1.0), Color(FOG, 1.0 - ease(k, 0.6)))


# ------------------------------------------------------------------ overlay

func _draw_overlay() -> void:
	var ci := overlay
	if show_reach:
		var pulse_a := 0.75 + 0.25 * sin(time * 3.0)
		for h in reachable.keys():
			if h == state.champ.pos:
				continue
			_outline(ci, center_of(h), Color("#c9a6ff", pulse_a), 3.0, 6.0)
	for h in flash.keys():
		var k: float = flash[h]
		_outline(ci, center_of(h), Color("#ff8a7a", clampf(k, 0.0, 1.0)), 4.0, -(1.2 - k) * 18.0)
	if state.world.has(hover):
		_outline(ci, center_of(hover), CREAM, 4.0, 3.0)
	if path.is_empty():
		return
	for i in path.size():
		var st: Dictionary = path[i]
		var c := center_of(st.h)
		var tl: Dictionary = state.world.tile(st.h)
		var band: int = int(tl.band) if state.is_explored(st.h) else 1
		var a := 1.0 if st.reachable else 0.45
		if i < path.size() - 1:
			ci.draw_rect(Rect2(c - Vector2(8, 8), Vector2(16, 16)), Color(INK, a))
			ci.draw_rect(Rect2(c - Vector2(5, 5), Vector2(10, 10)), Color(BAND[band], a))
		else:
			_outline(ci, c, Color("#ffd75e", a), 4.0, 3.0)
			var bob := int(time * 5.0) % 2 * 3
			var arrow := PackedVector2Array([c + Vector2(-12, -44 - bob), c + Vector2(12, -44 - bob), c + Vector2(0, -26 - bob)])
			ci.draw_colored_polygon(arrow, Color(BAND[band], a))
			ci.draw_polyline(PackedVector2Array([arrow[0], arrow[1], arrow[2], arrow[0]]), INK, 3.0)
		var txt := str(st.total)
		var f := Style.body_heavy
		var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		var tp := c + Vector2(-w / 2.0, -12)
		for o in [Vector2(-2, 0), Vector2(2, 0), Vector2(0, -2), Vector2(0, 2)]:
			ci.draw_string(f, tp + o, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(INK, a))
		ci.draw_string(f, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(CREAM, a))


# ------------------------------------------------------------------ objects

func _draw_objects() -> void:
	var ci := objects
	var items: Array = []
	for kid in state.world.capitals.keys():
		var h: Vector2i = state.world.capitals[kid]
		if state.is_explored(h):
			items.append({"y": center_of(h).y, "kind": "capital", "h": h, "kid": kid})
	for id in state.world.places.keys():
		var h: Vector2i = state.world.places[id]
		if state.place_visible(h) and state.world.tile(h).place != "capital":
			items.append({"y": center_of(h).y, "kind": "place", "h": h, "id": id})
	for i in state.patrols.size():
		var p: Dictionary = state.patrols[i]
		if p.alive and state.is_explored(p.pos) and Hex.distance(p.pos, state.champ.pos) <= 4:
			items.append({"y": center_of(p.pos).y + 2, "kind": "patrol", "p": p})
	for c in _caravans:
		var i0 := int(floor(c.t))
		var i1 := mini(i0 + 1, c.path.size() - 1)
		var p := center_of(c.path[i0]).lerp(center_of(c.path[i1]), c.t - i0) + Vector2(0, 10)
		if state.is_explored(c.path[i0]):
			items.append({"y": p.y, "kind": "caravan", "p": p, "dir": c.dir, "k": c.kind})
	for e in state.history:
		if e.kind in ["death", "fallen"]:
			items.append({"y": center_of(e.h).y + 1, "kind": "cairn", "h": e.h})
	items.sort_custom(func(a, b): return a.y < b.y)
	for it in items:
		match it.kind:
			"capital": _draw_capital(ci, it.h, it.kid)
			"place": _draw_place(ci, it.h, it.id)
			"patrol": _draw_patrol(ci, it.p)
			"caravan": _draw_caravan(ci, it.p, it.dir, it.k)
			"cairn": spr(ci, "city/deco_16", center_of(it.h) + Vector2(34, 20))


func _draw_capital(ci: CanvasItem, h: Vector2i, kid: String) -> void:
	var c := center_of(h)
	var mine := kid == state.kingdom
	_shadow(ci, c + Vector2(10, 18), 120, 22, 0.32)
	spr(ci, "city/b_%s_house%d" % [kid, 1 + posmod(h.x, 3)], c + Vector2(-80, 10))
	spr(ci, "city/b_%s_castle" % kid, c + Vector2(0, 34))
	if mine and state.age >= 2:
		spr(ci, "city/b_%s_tower" % kid, c + Vector2(84, 20))
	_label(ci, c + Vector2(0, 66), state.kname(kid) + (" ★" if mine else ""), 18, Style.kingdom_color(kid).darkened(0.35))
	if mine and state.flags.has("envoy_waiting") and not state.flags.has("envoy_done"):
		var p := c + Vector2(96, 30)
		spr(ci, "units/%s_pawn_idle" % state.world.rival, p, int(time * 8.0))
		_bubble(ci, p + Vector2(0, -78), "!")
	if not mine:
		var inter := state.place_interaction(h)
		var once := "harbor_cha" if inter == "dialogue:harbor" else "forge_str"
		if inter.begins_with("dialogue:") and not state.flags.has(once):
			_bubble(ci, c + Vector2(70, -120), "!")


func _draw_place(ci: CanvasItem, h: Vector2i, id: String) -> void:
	var c := center_of(h)
	var tl: Dictionary = state.world.tile(h)
	var inter := state.place_interaction(h)
	match str(tl.place):
		"crossroads":
			spr(ci, "city/deco_17", c + Vector2(-22, 14))
			if inter == "dialogue:tobbin":
				_shadow(ci, c + Vector2(34, 22), 46, 10)
				spr(ci, "city/stall_%s" % state.world.merchant, c + Vector2(34, 26))
				_bubble(ci, c + Vector2(34, -76), "!")
			_label(ci, c + Vector2(0, 62), "Crossroads", 16)
		"ruins":
			_shadow(ci, c + Vector2(6, 18), 60, 14)
			spr(ci, "city/ruin_castle", c + Vector2(0, 40), 0, false, Color(0.92, 0.9, 0.95))
			if not state.flags.has("surveyor_map"):
				_bubble(ci, c + Vector2(0, -90), "?")
			_label(ci, c + Vector2(0, 62), "Old ruins", 16)
		"grove":
			spr(ci, "tree2", c + Vector2(-34, 0), int(time * 6.0))
			spr(ci, "tree3", c + Vector2(36, -4), int(time * 6.0) + 3)
			spr(ci, "city/b_purple_house1", c + Vector2(2, 26))
			if not state.flags.has("hermit_con") or not state.flags.has("hermit_wis"):
				_bubble(ci, c + Vector2(0, -96), "!")
			_label(ci, c + Vector2(0, 62), "Hermit's grove", 16)
		"deposit", "iron":
			var iron: bool = tl.deposit == "iron"
			for i in 3:
				var p := c + Vector2(-26 + i * 24, 14 - (i % 2) * 10)
				spr(ci, ("city/ironstone%d" % (1 + i % 2)) if iron else ("rock%d" % (2 + i % 3)), p)
			if tl.owner != "":
				_flag(ci, c + Vector2(40, 10), Style.kingdom_color(str(tl.owner)))
			elif state.flags.has("heard_deposit") or iron or id == "flint":
				_bubble(ci, c + Vector2(0, -60), "★")
			_label(ci, c + Vector2(0, 62), str(tl.name), 16)
		"cove":
			spr(ci, "city/pier", c + Vector2(0, 30))
			spr(ci, "props/barrel", c + Vector2(-40, 10))
			_label(ci, c + Vector2(0, 62), "Smugglers' cove", 16)
		"tower":
			_shadow(ci, c + Vector2(6, 20), 40, 10)
			spr(ci, "city/ruin_tower", c + Vector2(0, 34))
			_label(ci, c + Vector2(0, 62), "Old watchtower", 16)
		"dungeon":
			var did := str(tl.dungeon)
			var done := state.flags.has("dungeon_done_" + did)
			match did:
				"crystal_cave":
					_shadow(ci, c + Vector2(0, 18), 70, 14)
					spr(ci, "city/goldmine" if done else "city/goldmine_idle", c + Vector2(0, 34))
					spr(ci, "city/goldstone2", c + Vector2(-50, 24))
					spr(ci, "city/goldstone5", c + Vector2(52, 20))
					if not done:
						spr(ci, "units/pinero_bat_idle_map", c + Vector2(34, -56), int(time * 6.0))
				"old_crypt":
					_shadow(ci, c + Vector2(6, 20), 44, 10)
					spr(ci, "city/ruin_tower", c + Vector2(-10, 34), 0, false, Color(0.8, 0.78, 0.9))
					spr(ci, "props/skull", c + Vector2(36, 30))
					spr(ci, "props/skull", c + Vector2(-44, 26))
					if not done:
						spr(ci, "units/pinero_skeleton_idle_map", c + Vector2(40, 22), int(time * 5.0))
				_:
					_shadow(ci, c + Vector2(6, 20), 100, 18)
					spr(ci, "city/b_black_castle", c + Vector2(0, 40), 0, false, Color(0.78, 0.86, 0.9) if not done else Color.WHITE)
					spr(ci, "props/barrel", c + Vector2(-70, 30))
					if not done:
						spr(ci, "units/th_crabby_idle", c + Vector2(64, 34), int(time * 8.0))
			if not done:
				_bubble(ci, c + Vector2(0, -110), "!", Color("#c9a3ff"))
			_label(ci, c + Vector2(0, 66), str(tl.name) + (" (cleared)" if done else ""), 16, Color("#5a2f8a") if not done else INK)
		"camp":
			var cleared := state.flags.has("cleared_" + id)
			var wolves := str(tl.get("camp", "")) == "wolf_den"
			if wolves:
				spr(ci, "rock4", c + Vector2(-26, 10))
				spr(ci, "rock3", c + Vector2(28, 4))
				spr(ci, "city/deco_14", c + Vector2(4, 30))
				if not cleared:
					spr(ci, "units/pinero_alpha_idle_map", c + Vector2(4, 30), int(time * 5.0))
			else:
				spr(ci, "city/hut_ruin" if cleared else "city/hut", c + Vector2(-26, 22))
				spr(ci, "city/woodtower_ruin" if cleared else "city/woodtower_red", c + Vector2(36, 18), int(time * 6.0))
				if not cleared:
					spr(ci, "city/fire", c + Vector2(4, 40), int(time * 10.0))
			_label(ci, c + Vector2(0, 66), str(tl.name) + (" (broken)" if cleared else ""), 16, Color("#8a2f2f") if not cleared else INK)


func _draw_patrol(ci: CanvasItem, p: Dictionary) -> void:
	var c := center_of(p.pos) + Vector2(0, 22)
	var flip: bool = state.champ.pos.x > p.pos.x     # Pinero beasts face left by default
	if p.group in ["wolves", "wolf_den"]:
		_shadow(ci, c + Vector2(-10, 2), 34, 7)
		spr(ci, "units/pinero_wolf_idle_map", c + Vector2(-20, 0), int(time * 5.0), flip)
		spr(ci, "units/pinero_wolf_idle_map", c + Vector2(26, -10), int(time * 5.0) + 1, flip)
	elif p.group in ["boars"]:
		_shadow(ci, c, 30, 7)
		spr(ci, "units/kp_pig_idle", c + Vector2(-14, 0), int(time * 10.0), flip)
		spr(ci, "units/kp_pig_idle", c + Vector2(22, -8), int(time * 10.0) + 3, flip)
	else:
		_shadow(ci, c, 40, 8)
		spr(ci, "units/goblin_purple_idle", c + Vector2(-22, 0), int(time * 8.0), not flip)
		spr(ci, "units/goblin_purple_idle", c + Vector2(22, -8), int(time * 8.0) + 3, not flip)
	_bubble(ci, c + Vector2(0, -110), "!", Color("#ff8a7a"))


func _draw_caravan(ci: CanvasItem, p: Vector2, dir: float, k: int) -> void:
	var cols := ["blue", "yellow", "red"]
	spr(ci, "units/%s_pawn_run_gold" % cols[k % 3], p, int(time * 10.0) + k, dir < 0)


# ------------------------------------------------------------------ clouds

func _draw_clouds() -> void:
	for cd in _cloud_data:
		var ct := t("Clouds_01" if int(cd.k) == 0 else "Clouds_03")
		if ct:
			clouds.draw_texture(ct, Vector2(cd.x, cd.y).round(), Color(1, 1, 1, 0.8))


# ------------------------------------------------------------------ utils

func _smooth(pts: PackedVector2Array, sub: int) -> PackedVector2Array:
	if pts.size() < 3:
		return pts
	var out := PackedVector2Array()
	for i in pts.size() - 1:
		var p0 := pts[maxi(i - 1, 0)]
		var p1 := pts[i]
		var p2 := pts[i + 1]
		var p3 := pts[mini(i + 2, pts.size() - 1)]
		for k in sub:
			var tt := float(k) / sub
			var t2 := tt * tt
			var t3 := t2 * tt
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * tt + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	out.append(pts[pts.size() - 1])
	return out


func _dashed(ci: CanvasItem, pts: PackedVector2Array, col: Color, w: float, dash: float, gap: float, offset: float = 0.0) -> void:
	var dist := -offset
	var on := true
	var remaining := dash
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var seg := a.distance_to(b)
		if seg <= 0.001:
			continue
		var pos := 0.0
		while pos < seg:
			var step := minf(remaining, seg - pos)
			if on and dist >= 0.0:
				ci.draw_line(a.lerp(b, pos / seg), a.lerp(b, (pos + step) / seg), col, w)
			pos += step
			remaining -= step
			dist += step
			if remaining <= 0.0:
				on = not on
				remaining = dash if on else gap
