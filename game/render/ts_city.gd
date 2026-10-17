class_name TsCity
extends Control
## The capital drawn in Tiny Swords pixel art (see assets/LICENSES.md).
##
## Pixel rules (same as the world benchmark): the island renders at 1x into a
## 1920x1080 SubViewport with nearest filtering and pixel snapping, so pack
## pixels stay square. Zoom is 1x (detail) or 0.5x (overview of a big capital).
## City hexes are 192 px wide (three pack tiles) so a barracks or a monastery
## fits on one plot; grass is sampled in world space so plots merge into one
## meadow, with a faint grid on top so the plots still read.
##
## Pure presentation: it reads GameState and the screen's picking/hover state.

const VIEW := Vector2i(1920, 1080)
const HW := 96.0                      # half hex width
const ROW := 120.0                    # row step
const HILL := 40.0
const HEX := [Vector2(0, -84), Vector2(96, -36), Vector2(96, 36), Vector2(0, 84), Vector2(-96, 36), Vector2(-96, -36)]
# axial neighbour across top-face edge i (edge i = HEX[i] -> HEX[i+1])
const ACROSS := [Vector2i(1, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(0, -1)]
const TS := "res://assets/tinyswords/"
const INK := Color("#161c2e")
const CREAM := Color("#fbf3df")
const NONE := Vector2i(-99, -99)

var st: GameState
var picking := ""
var hover := NONE
var valid: Dictionary = {}
var pop_anim: Dictionary = {}
var zoom := 1.0
var cam := Vector2.ZERO                # pan offset in view pixels
var time := 0.0
var center_x := 760.0

var vp := SubViewport.new()
var view := TextureRect.new()
var world := Node2D.new()
var tags := Control.new()
var tex: Dictionary = {}
var feet: Dictionary = {}             # texture name -> Vector2(x centre, bottom) of drawn pixels in frame 0
var walkers: Array = []
var smoke: Array = []
var water_col := Color("#47aba9")
var font: Font


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = PixelUI.font()
	var wimg: Image = (load(TS + "Water Background color.png") as Texture2D).get_image()
	water_col = wimg.get_pixel(8, 8)
	vp.size = VIEW
	vp.disable_3d = true
	vp.snap_2d_transforms_to_pixel = true
	vp.snap_2d_vertices_to_pixel = true
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(vp)
	var bg := ColorRect.new()
	bg.color = water_col
	bg.size = Vector2(VIEW)
	vp.add_child(bg)
	world.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	vp.add_child(world)
	world.draw.connect(_draw_world)
	view.texture = vp.get_texture()
	view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.stretch_mode = TextureRect.STRETCH_SCALE
	var grade := ShaderMaterial.new()
	grade.shader = load("res://render/grade.gdshader")
	grade.set_shader_parameter("vignette", 0.55)
	view.material = grade
	add_child(view)
	tags.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tags.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tags.draw.connect(_draw_tags)
	add_child(tags)


# ------------------------------------------------------------------ textures

func t(name: String) -> Texture2D:
	if not tex.has(name):
		var path := TS + name + ".png"
		if name.begins_with("props/") or name.begins_with("icons/"):
			path = "res://assets/" + name + ".png"
		tex[name] = load(path) if ResourceLoader.exists(path) else null
		if tex[name]:
			(tex[name] as Texture2D).set_meta("ts_name", name)
			var img: Image = (tex[name] as Texture2D).get_image()
			var fw := _frame_w(tex[name])
			var used := img.get_region(Rect2i(0, 0, fw, img.get_height())).get_used_rect()
			feet[name] = Vector2(used.position.x + used.size.x / 2.0, used.end.y)
	return tex[name]


## Frame width of a sprite sheet: square frames for the animated sheets, a few
## special widths, and the whole image for still sprites.
func _frame_w(tx: Texture2D) -> int:
	var name := str(tx.get_meta("ts_name", ""))
	if name.contains("woodtower"):
		return 256
	for pre in ["tree", "bush", "Sheep_Idle", "city/sheep_grass", "units/", "city/fire", "city/waterrock", "Water Foam"]:
		if name.begins_with(pre):
			return tx.get_height()
	return tx.get_width()


func _frames(tx: Texture2D) -> int:
	return maxi(1, tx.get_width() / _frame_w(tx))


## Draws sprite `name` so the bottom-centre of its drawn pixels sits on `base`.
func spr(name: String, base: Vector2, frame: int = 0, flip := false, alpha := 1.0) -> void:
	var tx := t(name)
	if tx == null:
		return
	var fw := _frame_w(tx)
	var n := _frames(tx)
	var src := Rect2(fw * (posmod(frame, n)), 0, fw, tx.get_height())
	var f: Vector2 = feet[name]
	var top_left := (base - f).round()
	if flip:
		world.draw_set_transform(base.round(), 0.0, Vector2(-1, 1))
		world.draw_texture_rect_region(tx, Rect2(-f, src.size), src, Color(1, 1, 1, alpha))
		world.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		world.draw_texture_rect_region(tx, Rect2(top_left, src.size), src, Color(1, 1, 1, alpha))


# ------------------------------------------------------------------ geometry

func cpos(s: Vector2i) -> Vector2:
	return Vector2(2.0 * HW * (s.x + s.y * 0.5), ROW * s.y)


func top(s: Vector2i) -> Vector2:
	return cpos(s) - Vector2(0, HILL if terr(s) == "hills" else 0.0)


func terr(s: Vector2i) -> String:
	return str(st.city_terrain.get(s, "sea"))


func land(s: Vector2i) -> bool:
	return terr(s) in ["plains", "forest", "hills"]


## Screen position (in this control's coordinates) of a point in island space.
func to_screen(p: Vector2) -> Vector2:
	return world.position + p * zoom


func slot_screen(s: Vector2i) -> Vector2:
	return to_screen(top(s))


func pick(screen: Vector2) -> Vector2i:
	if st == null:
		return NONE
	var lp := (screen - world.position) / zoom
	var best := NONE
	var bd := 1e12
	for s in st.city_terrain.keys():
		var d: Vector2 = lp - top(s)
		var dd := d.x * d.x + d.y * d.y * 1.7
		if dd < bd:
			bd = dd
			best = s
	return best if bd < 100.0 * 100.0 else NONE


const ZOOMS := [0.5, 0.75, 1.0]


func set_zoom(z: float) -> void:
	zoom = clampf(z, 0.5, 1.0)
	cam = Vector2.ZERO


## Steps through the zoom levels (+1 closer, -1 further out).
func zoom_step(dir: int) -> void:
	var i := ZOOMS.find(zoom)
	if i < 0:
		i = 2
	set_zoom(ZOOMS[clampi(i + dir, 0, ZOOMS.size() - 1)])


func pan(d: Vector2) -> void:
	cam += d
	var r := float(st.city_radius) * 2.0 * HW * zoom * 0.6
	cam = cam.clamp(Vector2(-r, -r), Vector2(r, r))


## Picks the zoom that fits the whole island beside the side panel.
func fit() -> void:
	var w := (st.city_radius * 2 + 1) * 2.0 * HW
	var h := (st.city_radius * 2 + 1) * ROW + 260.0
	zoom = 0.5
	for z in [1.0, 0.75]:
		if w * z <= size.x - 440 and h * z <= size.y - 120:
			zoom = z
			break
	cam = Vector2.ZERO


func _process(delta: float) -> void:
	if st == null or not is_visible_in_tree():
		return
	time += delta
	center_x = (size.x - 400.0) / 2.0 + 20.0
	world.scale = Vector2(zoom, zoom)
	world.position = (Vector2(center_x, size.y / 2.0 + 40.0) + cam).round()
	_update_walkers(delta)
	if randf() < delta * 4.0:
		for s in st.city.keys():
			if str(st.city[s].type) in ["hall", "house", "blacksmith", "bakery", "foundry", "tavern", "workshop"] and randf() < 0.3:
				smoke.append({"p": top(s) + Vector2(randf_range(-30, 30), -110), "t": 0.0})
	for sm in smoke:
		sm.t += delta * 0.35
	smoke = smoke.filter(func(x): return x.t < 1.0)
	world.queue_redraw()
	tags.queue_redraw()


# ------------------------------------------------------------------ walkers

func _update_walkers(delta: float) -> void:
	var want := clampi(st.pop / 2, 2, 12)
	var homes: Array = st.city.keys()
	while walkers.size() < want and homes.size() > 1:
		var a: Vector2i = homes[randi() % homes.size()]
		walkers.append({"from": a, "to": homes[randi() % homes.size()], "t": randf(), "speed": randf_range(0.12, 0.2), "load": ""})
	while walkers.size() > want:
		walkers.pop_back()
	for w in walkers:
		w.t += delta * w.speed
		if w.t >= 1.0:
			w.t = 0.0
			w.from = w.to
			w.to = homes[randi() % homes.size()]
			var src := str(st.city.get(w.from, {}).get("type", ""))
			w.load = {"farm": "meat", "hunter": "meat", "fishery": "meat", "bakery": "meat", "lumber": "wood", "sawmill": "wood",
				"market": "gold", "mine": "gold", "harbor": "gold", "tavern": "gold"}.get(src, "")


# ------------------------------------------------------------------ drawing

func _hex_pts(c: Vector2, inset := 0.0) -> PackedVector2Array:
	var p := PackedVector2Array()
	for v in HEX:
		p.append(c + v * (1.0 - inset / HW))
	return p


func _textured(c: Vector2, tx: Texture2D, inset := 0.0) -> void:
	var pts := _hex_pts(c, inset)
	var uv := PackedVector2Array()
	for p in pts:
		uv.append(p / 64.0)
	world.draw_colored_polygon(pts, Color.WHITE, uv, tx)


func _outline(c: Vector2, col: Color, w: float, inset: float) -> void:
	var pts := _hex_pts(c, inset)
	pts.append(pts[0])
	world.draw_polyline(pts, col, w)


func _shadow(at: Vector2, rx: float, ry: float, a := 0.38) -> void:
	var sh := PackedVector2Array()
	for i in 20:
		var ang := TAU * i / 20.0
		sh.append((at + Vector2(cos(ang) * rx, sin(ang) * ry)).round())
	world.draw_colored_polygon(sh, Color(0.24, 0.13, 0.36, a))


func _cliff(ctr: Vector2) -> void:
	var tx := t("cliff")
	for x in range(-96, 96, 2):
		var bottom := 84.0 - absf(x + 1) / 2.0
		var src_x := posmod(int(ctr.x) + x, 64)
		world.draw_texture_rect_region(tx, Rect2(ctr + Vector2(x, bottom - HILL), Vector2(2, HILL + 6)), Rect2(src_x, 0, 2, HILL + 6))
	world.draw_polyline(PackedVector2Array([ctr + Vector2(-96, 36), ctr + Vector2(0, 84), ctr + Vector2(96, 36)]), INK, 3.0)


func _draw_world() -> void:
	if st == null:
		return
	var slots: Array = st.city_terrain.keys()
	slots.sort_custom(func(a, b): return cpos(a).y < cpos(b).y or (cpos(a).y == cpos(b).y and cpos(a).x < cpos(b).x))
	# 1) foam where land meets water (inner ponds and the island shore)
	var ft := t("Water Foam")
	for s in slots:
		if not land(s):
			continue
		for i in 6:
			if not land(s + ACROSS[i]):
				var mid: Vector2 = cpos(s) + (HEX[i] + HEX[(i + 1) % 6]) / 2.0
				var fr := Rect2(192 * posmod(int(time * 9.0) + s.x * 5 + s.y * 3 + i * 2, 16), 0, 192, 192)
				world.draw_texture_rect_region(ft, Rect2((mid - Vector2(96, 100)).round(), Vector2(192, 192)), fr)
	# water plots: rocks bobbing
	for s in slots:
		if terr(s) == "water" and not st.city.has(s) and Hex.hash01(s, 3) < 0.5:
			spr("city/waterrock%d" % (1 + int(Hex.hash01(s, 4) * 4) % 4), cpos(s) + Vector2(Hex.hash01(s, 5) * 60 - 30, 20), int(time * 6.0) + s.x)
	# 2) ground
	for s in slots:
		if not land(s):
			continue
		if terr(s) == "hills":
			_cliff(cpos(s))
			_textured(top(s), t("grass_hills"))
		else:
			_textured(cpos(s), t("grass_plains"))
		if st.city.has(s) and str(st.city[s].type) == "farm" and str(st.city[s].get("branch", "")) != "pasture":
			_textured(top(s), t("city/soil"), 22.0)
			_outline(top(s), Color(INK, 0.55), 2.0, 22.0)
	# 3) shore ink, plot grid, hill rims
	for s in slots:
		if not land(s):
			continue
		var c := top(s)
		for i in 6:
			var a: Vector2 = c + HEX[i]
			var b: Vector2 = c + HEX[(i + 1) % 6]
			var n: Vector2i = s + ACROSS[i]
			if not land(n):
				world.draw_line(a, b, Color("#d8f3e4"), 6.0)
				world.draw_line(a, b, INK, 3.0)
			elif terr(s) == "hills" and terr(n) != "hills":
				world.draw_line(a, b, INK, 3.0)
			else:
				world.draw_line(a, b, Color(0.08, 0.2, 0.1, 0.16), 2.0)
	# 4) build overlays
	var pulse := 0.6 + 0.4 * sin(time * 5.0)
	for s in valid.keys():
		var c := top(s) if land(s) else cpos(s)
		_outline(c, Color("#ffd75e", pulse), 4.0, 8.0)
		var plus := c + Vector2(0, -4)
		world.draw_rect(Rect2(plus + Vector2(-12, -3), Vector2(24, 6)), INK)
		world.draw_rect(Rect2(plus + Vector2(-3, -12), Vector2(6, 24)), INK)
		world.draw_rect(Rect2(plus + Vector2(-10, -1), Vector2(20, 2)), Color("#ffd75e"))
		world.draw_rect(Rect2(plus + Vector2(-1, -10), Vector2(2, 20)), Color("#ffd75e"))
	if hover != NONE:
		var hc := top(hover) if land(hover) else cpos(hover)
		var bad := picking != "" and not valid.has(hover)
		_outline(hc, Color("#ff8a7a") if bad else CREAM, 4.0, 4.0)
	# 5) y-sorted objects
	var items: Array = []
	for s in slots:
		if st.city.has(s):
			items.append({"y": top(s).y + 30, "slot": s})
		else:
			for d in _empty_deco(s):
				items.append({"y": top(s).y + d[1].y, "deco": d, "s": s})
	for w in walkers:
		var p := _walker_pos(w)
		items.append({"y": p.y, "walker": w, "p": p})
	if st.has_building("walls"):
		for s in slots:
			if not land(s):
				continue
			for i in 6:
				var n: Vector2i = s + ACROSS[i]
				if not st.city_terrain.has(n):
					var mid: Vector2 = top(s) + (HEX[i] + HEX[(i + 1) % 6]) / 2.0
					items.append({"y": mid.y + (8 if i in [2, 3] else -8), "wall": [top(s) + HEX[i], top(s) + HEX[(i + 1) % 6]]})
	items.sort_custom(func(a, b): return a.y < b.y)
	for it in items:
		if it.has("slot"):
			_draw_building(it.slot)
		elif it.has("deco"):
			var d: Array = it.deco
			if str(d[0]).begins_with("tree"):
				_shadow(top(it.s) + d[1] + Vector2(8, 2), 34, 11)
			spr(str(d[0]), top(it.s) + d[1], int(time * 7.0) + int(d[2]))
		elif it.has("walker"):
			_draw_walker(it.walker, it.p)
		elif it.has("wall"):
			_wall(it.wall[0], it.wall[1])
	# 6) smoke puffs (pixel squares, fade upward)
	for sm in smoke:
		var p: Vector2 = (sm.p + Vector2(sin(sm.t * 6.0) * 6.0, -sm.t * 80.0)).round()
		var sz: float = 6.0 + sm.t * 10.0
		world.draw_rect(Rect2(p - Vector2(sz, sz) / 2.0, Vector2(sz, sz)), Color(0.93, 0.92, 0.95, 0.55 * (1.0 - sm.t)))
	# 7) clouds drifting over the sea
	for k in 2:
		var ct := t("Clouds_01" if k == 0 else "Clouds_03")
		var x := fmod(time * (12.0 + k * 5.0) + k * 1100.0, 3200.0) - 1600.0
		world.draw_texture(ct, Vector2(x, -520 + k * 820).round(), Color(1, 1, 1, 0.85))


## A low stone wall along one shore edge, built from the pack's cliff texture
## in 2-px columns (same trick as the hill cliffs, so pixels stay square).
func _wall(a: Vector2, b: Vector2) -> void:
	var tx := t("cliff")
	var n := int(absf(b.x - a.x) / 2.0)
	for k in n:
		var p := a.lerp(b, float(k) / maxf(1, n))
		var src_x := posmod(int(p.x), 64)
		world.draw_texture_rect_region(tx, Rect2((p + Vector2(0, -18)).round(), Vector2(2, 24)), Rect2(src_x, 0, 2, 24))
	world.draw_line(a + Vector2(0, -18), b + Vector2(0, -18), INK, 2.0)


func _empty_deco(s: Vector2i) -> Array:
	var out: Array = []
	match terr(s):
		"forest":
			var offs := [Vector2(-40, -10), Vector2(36, -4), Vector2(-6, 34), Vector2(44, 40)]
			for i in offs.size():
				out.append(["tree%d" % (1 + int(Hex.hash01(s, 10 + i) * 4) % 4), offs[i] + Vector2(Hex.hash01(s, 20 + i) * 12 - 6, Hex.hash01(s, 30 + i) * 8 - 4), int(Hex.hash01(s, 40 + i) * 8)])
		"hills":
			out.append(["rock%d" % (1 + int(Hex.hash01(s, 11) * 4) % 4), Vector2(Hex.hash01(s, 12) * 70 - 35, Hex.hash01(s, 13) * 30), 0])
			if Hex.hash01(s, 14) < 0.5:
				out.append(["bush%d" % (1 + int(Hex.hash01(s, 15) * 4) % 4), Vector2(Hex.hash01(s, 16) * 60 - 10, Hex.hash01(s, 17) * 20 + 10), int(Hex.hash01(s, 18) * 8)])
		"plains":
			var v := Hex.hash01(s, 21)
			if v < 0.3:
				out.append(["bush%d" % (1 + int(Hex.hash01(s, 22) * 4) % 4), Vector2(Hex.hash01(s, 23) * 100 - 50, Hex.hash01(s, 24) * 50 - 10), int(Hex.hash01(s, 25) * 8)])
			elif v < 0.5:
				out.append(["city/deco_%02d" % (7 + int(Hex.hash01(s, 26) * 6)), Vector2(Hex.hash01(s, 27) * 100 - 50, Hex.hash01(s, 28) * 50 - 10), 0])
			elif v < 0.6:
				out.append(["Sheep_Idle", Vector2(Hex.hash01(s, 29) * 80 - 40, 20), int(Hex.hash01(s, 30) * 6)])
	return out


func _walker_pos(w: Dictionary) -> Vector2:
	var a := top(w.from) + Vector2(40, 46)
	var b := top(w.to) + Vector2(40, 46)
	return a.lerp(b, w.t)


func _draw_walker(w: Dictionary, p: Vector2) -> void:
	var k := str(st.kingdom)
	var flip: bool = top(w.to).x < top(w.from).x
	var anim := "units/%s_pawn_run" % k + ("_" + str(w.load) if str(w.load) != "" else "")
	if w.from == w.to:
		anim = "units/%s_pawn_idle" % k
	_shadow(p + Vector2(0, 2), 18, 6, 0.3)
	spr(anim, p + Vector2(0, 0), int(time * 10.0 + w.speed * 50.0), flip)


# ------------------------------------------------------------------ buildings

## Sprite recipe per building: [name, offset from the plot's top centre, anim fps (0 = still), flip].
func recipe(type: String, s: Vector2i) -> Array:
	var k := str(st.kingdom) if st else "red"
	var lvl := st.level_of(s) if st and st.city.has(s) else 1
	var br := str(st.city[s].get("branch", "")) if st and st.city.has(s) else ""
	var v := int(Hex.hash01(s, 91) * 3)
	var r: Array = []
	match type:
		"hall":
			r = [["city/b_%s_castle" % k, Vector2(0, 40), 0]]
		"house":
			r = [["city/b_%s_house%d" % [k, 1 + v], Vector2(-34, 10), 0], ["city/b_%s_house%d" % [k, 1 + (v + 1) % 3], Vector2(38, 40), 0]]
			if lvl >= 2:
				r.append(["city/b_%s_house%d" % [k, 1 + (v + 2) % 3], Vector2(-48, 62), 0])
			if br == "manor":
				r = [["city/b_%s_house3" % k, Vector2(-30, 24), 0], ["city/b_%s_tower" % k, Vector2(44, 30), 0], ["city/barrel", Vector2(-70, 56), 0]]
			elif br == "artisan":
				r.append(["city/stall_%s" % k, Vector2(50, 70), 0])
		"farm":
			r = [["city/deco_18", Vector2(0, 30), 0], ["city/deco_13", Vector2(-50, 0), 0], ["city/deco_12", Vector2(-20, 20), 0], ["city/deco_13", Vector2(40, 50), 0],
				["Sheep_Idle", Vector2(50, 0), 7], ["bush1", Vector2(-60, 54), 6]]
			if lvl >= 2:
				r.append(["props/box", Vector2(-70, 30), 0])
			if br == "pasture":
				r += [["Sheep_Idle", Vector2(-40, 40), 7], ["city/sheep_grass", Vector2(10, 64), 6]]
			elif br == "orchard":
				r += [["tree4", Vector2(-56, -10), 6], ["tree3", Vector2(56, 10), 6]]
		"lumber":
			r = [["city/b_%s_house1" % k, Vector2(38, 10), 0], ["city/stump%d" % (1 + v), Vector2(-50, -10), 0], ["city/res_wood", Vector2(-36, 40), 0], ["city/res_wood", Vector2(-14, 50), 0], ["units/%s_pawn_interact_axe" % k, Vector2(-10, 30), 9]]
			if br == "charcoal":
				r.append(["city/fire", Vector2(50, 56), 10])
			if br == "forester":
				r.append(["tree2", Vector2(-60, 16), 6])
		"market":
			r = [["city/b_%s_house3" % k, Vector2(-20, 20), 0], ["props/table", Vector2(48, 44), 0], ["props/barrel", Vector2(70, 30), 0], ["city/res_gold", Vector2(-64, 50), 0], ["city/res_meat", Vector2(20, 62), 0]]
			if lvl >= 2:
				r.append(["props/box", Vector2(70, 60), 0])
			if br == "guild":
				r.append(["props/chest", Vector2(-40, 64), 0])
		"barracks":
			r = [["city/b_%s_barracks" % k, Vector2(0, 40), 0]]
		"quarry":
			r = [["rock4", Vector2(-40, 0), 0], ["rock3", Vector2(24, -8), 0], ["rock2", Vector2(52, 30), 0], ["city/goldstone4", Vector2(-56, 46), 0], ["units/%s_pawn_interact_pickaxe" % k, Vector2(0, 36), 9]]
			if br == "ironseam":
				r.append(["city/ironstone1", Vector2(40, 56), 0])
		"blacksmith":
			r = [["city/b_black_house2", Vector2(-14, 30), 0], ["city/fire", Vector2(58, 26), 10], ["props/box", Vector2(62, 52), 0], ["units/%s_pawn_interact_hammer" % k, Vector2(28, 60), 8]]
		"drillyard":
			r = [["city/b_%s_archery" % k, Vector2(0, 40), 0]]
		"mill":
			r = [["city/b_yellow_tower", Vector2(0, 36), 0], ["props/box", Vector2(56, 52), 0], ["props/box", Vector2(-56, 50), 0]]
		"granary":
			r = [["city/b_%s_tower" % k, Vector2(-14, 36), 0], ["props/box", Vector2(48, 44), 0], ["props/barrel", Vector2(-60, 56), 0]]
		"sawmill":
			r = [["city/b_%s_house1" % k, Vector2(36, 8), 0], ["city/res_wood", Vector2(-40, 30), 0], ["city/res_wood", Vector2(-20, 50), 0], ["city/stump2", Vector2(50, 54), 0], ["units/%s_pawn_interact_axe" % k, Vector2(10, 52), 9]]
		"mine":
			r = [["city/goldmine", Vector2(0, 30), 0], ["city/goldstone%d" % (1 + v), Vector2(64, 46), 0], ["units/%s_pawn_interact_pickaxe" % k, Vector2(-56, 50), 9]]
			if br == "gems":
				r.append(["city/goldstone5", Vector2(-70, 20), 0])
		"workshop":
			r = [["city/b_%s_house2" % k, Vector2(-10, 30), 0], ["props/barrel", Vector2(52, 40), 0], ["props/box", Vector2(-60, 54), 0], ["units/%s_pawn_interact_hammer" % k, Vector2(36, 62), 8]]
		"tavern":
			r = [["city/b_%s_house3" % k, Vector2(-14, 30), 0], ["city/deco_17", Vector2(58, 40), 0], ["props/barrel", Vector2(-62, 50), 0], ["props/table", Vector2(-30, 64), 0]]
		"watchtower":
			r = [["city/woodtower_%s" % k, Vector2(0, 40), 6]]
		"temple":
			r = [["city/b_%s_monastery" % k, Vector2(0, 44), 0]]
		"library":
			r = [["city/b_purple_tower", Vector2(40, 14), 0], ["city/b_purple_house3", Vector2(-28, 40), 0]]
		"ironmine":
			r = [["city/goldmine_idle", Vector2(0, 30), 0], ["city/ironstone1", Vector2(62, 44), 0], ["city/ironstone2", Vector2(-66, 40), 0], ["units/%s_pawn_interact_pickaxe" % k, Vector2(-30, 58), 9]]
		"foundry":
			r = [["city/b_black_house1", Vector2(-24, 26), 0], ["city/fire", Vector2(40, 30), 10], ["city/ironstone2", Vector2(60, 56), 0], ["props/barrel", Vector2(-64, 52), 0]]
		"fishery":
			r = [["city/pier", Vector2(0, 30), 0], ["units/%s_pawn_idle" % k, Vector2(40, 0), 8], ["props/barrel", Vector2(-50, 4), 0]]
			if br == "smokehouse":
				r.append(["city/fire", Vector2(-20, 6), 10])
		"bakery":
			r = [["city/b_%s_house1" % k, Vector2(-8, 30), 0], ["props/box", Vector2(52, 44), 0], ["city/res_meat", Vector2(-56, 52), 0]]
		"winery":
			r = [["city/b_%s_house2" % k, Vector2(-14, 26), 0], ["props/barrel", Vector2(46, 40), 0], ["props/barrel", Vector2(62, 54), 0], ["props/red_bottle", Vector2(28, 60), 0], ["bush3", Vector2(-60, 54), 6]]
		"hunter":
			r = [["city/hut", Vector2(-6, 34), 0], ["city/res_meat", Vector2(54, 46), 0], ["city/res_meat", Vector2(-62, 50), 0]]
		"tannery":
			r = [["city/b_%s_house1" % k, Vector2(-24, 24), 0], ["city/res_meat", Vector2(44, 34), 0], ["props/box", Vector2(56, 60), 0]]
		"apothecary":
			r = [["city/b_purple_house1", Vector2(-10, 28), 0], ["city/deco_03", Vector2(54, 40), 0], ["city/deco_02", Vector2(64, 54), 0], ["city/deco_11", Vector2(-56, 52), 0], ["city/deco_10", Vector2(-40, 60), 0]]
		"harbor":
			r = [["city/b_%s_tower" % k, Vector2(-40, 20), 0], ["city/pier", Vector2(30, 70), 0], ["props/barrel", Vector2(52, 30), 0], ["props/chest", Vector2(-70, 50), 0]]
		"walls":
			r = [["city/b_%s_tower" % k, Vector2(-40, 30), 0], ["city/b_%s_tower" % k, Vector2(40, 30), 0]]
		_:
			r = [["city/b_%s_house1" % k, Vector2(0, 30), 0]]
	return r


func _draw_building(s: Vector2i) -> void:
	var type := str(st.city[s].type)
	var base := top(s) if land(s) else cpos(s)
	var k: float = pop_anim.get(s, 1.0)
	if k < 1.0:
		spr("city/construction", base + Vector2(0, 40), 0, false, 1.0)
		var dust := int(time * 12.0)
		for d in 5:
			var a := TAU * d / 5.0 + time
			var p := (base + Vector2(cos(a) * 70.0 * k, 36 + sin(a) * 22.0 * k)).round()
			world.draw_rect(Rect2(p, Vector2(6, 6) * (1.0 - k) + Vector2(2, 2)), Color(0.94, 0.88, 0.74, 1.0 - k))
		if k < 0.5:
			return
	var staffed: bool = st.staffing().get(s, true)
	var big := type in ["hall", "barracks", "temple", "drillyard", "mine", "ironmine"]
	_shadow(base + Vector2(8, 34), 86 if big else 66, 20, 0.34)
	for part in recipe(type, s):
		var fps: float = absf(float(part[2]))
		var frame := int(time * fps + s.x * 3 + s.y) if fps > 0 else 0
		if part[2] is float or part[2] is int:
			if int(part[2]) < 0:
				frame = int(time * fps)
		spr(str(part[0]), base + part[1], frame, false, 1.0 if staffed else 0.55)


# ------------------------------------------------------------------ tags (screen space, ungraded)

const RES_ICON := {"food": "ui/icon_04", "wood": "ui/icon_02", "stone": "rock1", "gold": "ui/icon_03", "iron": "icons/res_iron"}


func _draw_tags() -> void:
	if st == null:
		return
	var prod := st.production_by_slot()
	var staff := st.staffing()
	var fs := 18 if zoom >= 1.0 else 14
	for s in st.city.keys():
		var p := slot_screen(s) + Vector2(0, (-150.0 if zoom >= 1.0 else -80.0))
		var lv := st.level_of(s)
		var pieces: Array = []
		for r in (prod.get(s, {}) as Dictionary).keys():
			pieces.append([r, int(prod[s][r])])
		if not staff.get(s, true):
			_tag(p, [], "NO WORKERS", Color("#b8433a"), fs)
		elif not pieces.is_empty():
			_tag(p, pieces, "", Color("#2f6b35"), fs)
		if lv > 1:
			var bp := slot_screen(s) + Vector2(-78, -20) * zoom
			PixelUI.badge(tags, bp, "I".repeat(lv), font, fs)


func _tag(p: Vector2, pieces: Array, text: String, col: Color, fs: int) -> void:
	var parts: Array = []
	var w := 16.0
	for pc in pieces:
		var txt := "%+d" % int(pc[1])
		parts.append([pc[0], txt, font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x])
		w += 26.0 + parts[-1][2] + 8.0
	if text != "":
		w = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 24.0
	var r := Rect2((p - Vector2(w / 2.0, 16)).round(), Vector2(w, 32))
	PixelUI.paper_tag(tags, r)
	if text != "":
		tags.draw_string(font, r.position + Vector2(12, 22), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		return
	var x := r.position.x + 10.0
	for pc in parts:
		var icon := t(RES_ICON.get(pc[0], "ui/icon_03"))
		if icon:
			tags.draw_texture_rect(icon, Rect2(x, r.position.y + 3, 26, 26), false)
		var c: Color = col if not str(pc[1]).begins_with("-") else Color("#b8433a")
		tags.draw_string(font, Vector2(x + 28, r.position.y + 23), pc[1], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c)
		x += 26.0 + float(pc[2]) + 8.0
