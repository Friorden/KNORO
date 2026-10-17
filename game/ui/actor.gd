class_name Actor
extends Control
## A fighter on the battle screen, played from third-party sprite sheets
## (Tiny Swords units and goblins, Kings and Pigs, Pirate Bomb, Treasure Hunters,
## Robert Pinero's monsters — see assets/LICENSES.md). Idles, plays its attack
## animation while lunging, its hurt animation when hit, and its death pose.
##
## Sheet families and how their frames are laid out:
##   ts      Tiny Swords: square frames (frame width = image height), face right
##   pinero  RPG Maker side-view strips cut to 3 frames, face left
##   strip   Pixel Frog strips: frame count from assets/units/frames.json or
##           a fixed frame width, face given per entry

static var kingdom := "red"          # colour of the player's troops (set by the battle screen)
static var _tex: Dictionary = {}
static var _frames: Dictionary = {}

## art id -> [family, base sheet name (without _idle/_attack...), draw scale, native facing (1 = right), colour]
## colour "k" = the player's kingdom colour, otherwise a fixed pack colour.
const SPRITES := {
	"champion": ["ts", "warrior", 2.0, 1, "k"],
	"spearman": ["ts", "lancer", 1.5, 1, "k"],
	"shieldbearer": ["ts", "warrior", 1.8, 1, "k", "guard"],
	"skirmisher": ["ts", "pawn_knife", 2.0, 1, "k"],
	"archer": ["ts", "archer", 2.0, 1, "k"],
	"herbalist": ["ts", "monk", 2.0, 1, "k"],
	"thug": ["ts", "goblin_purple", 1.9, 1, ""],
	"cutthroat": ["ts", "pawn_knife", 2.0, 1, "black"],
	"bandit_archer": ["ts", "archer", 2.0, 1, "black"],
	"raider": ["ts", "lancer", 1.5, 1, "black"],
	"chief": ["ts", "warrior", 2.3, 1, "purple"],
	"brute": ["strip", "pb_bigguy", 1.6, -1, ""],
	"boar_big": ["strip", "kp_kingpig", 1.1, -1, ""],
	"boar_small": ["strip", "kp_pig", 1.0, -1, ""],
	"wolf": ["pinero", "wolf", 1.5, -1, ""],
	"alpha": ["pinero", "alpha", 1.5, -1, ""],
	"rat": ["pinero", "rat", 1.5, -1, ""],
	"bat": ["pinero", "bat", 1.5, -1, ""],
	"skeleton": ["pinero", "skeleton", 1.5, -1, ""],
	"slime": ["pinero", "slime", 1.5, -1, ""],
	"goblin": ["pinero", "goblin", 1.5, -1, ""],
	"kobold": ["pinero", "kobold", 1.5, -1, ""],
	"gnoll": ["pinero", "gnoll", 1.5, -1, ""],
	"troll": ["pinero", "troll", 1.5, -1, ""],
	"zombie": ["pinero", "zombie", 1.5, -1, ""],
	"crabby": ["strip", "th_crabby", 1.0, 1, ""],
	"fiercetooth": ["strip", "th_fiercetooth", 1.0, 1, ""],
	"pinkstar": ["strip", "th_pinkstar", 1.0, 1, ""],
	"captain": ["strip", "pb_captain", 1.6, -1, ""],
	"baldpirate": ["strip", "pb_baldpirate", 1.6, -1, ""],
}
const KP_FRAME := {"kp_pig": 136, "kp_kingpig": 152}

var art := "champion"
var tint := Color("#D46A55")
var time := 0.0
var flash := 0.0
var hurt_t := 0.0
var dead := false
var fall := 0.0
var face := 1.0
var selected := false
var targetable := false
var active := false
var weapon := ""
var pose := 0.0          # 0 idle .. 1 weapon raised (driven by lunge())


static func make(p_art: String, p_tint: Color, w: float = 220, h: float = 300) -> Actor:
	var a := Actor.new()
	a.art = p_art
	a.tint = p_tint
	a.custom_minimum_size = Vector2(w, h)
	a.size = Vector2(w, h)
	a.pivot_offset = Vector2(w / 2.0, h)
	a.mouse_filter = Control.MOUSE_FILTER_IGNORE
	a.time = randf() * 5.0
	a.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return a


func _process(d: float) -> void:
	time += d
	flash = maxf(0.0, flash - d * 3.0)
	hurt_t = maxf(0.0, hurt_t - d)
	if dead:
		fall = minf(1.0, fall + d * 2.0)
	queue_redraw()


func lunge(dir: float, dist: float = 110.0) -> Tween:
	var base := position
	var tw := create_tween()
	tw.tween_property(self, "position", base + Vector2(-20 * dir, 0), 0.12).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(self, "pose", 0.35, 0.12)
	tw.tween_property(self, "position", base + Vector2(dist * dir, 0), 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(self, "pose", 0.8, 0.14)
	tw.tween_property(self, "pose", 1.0, 0.1)
	tw.tween_property(self, "position", base, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(self, "pose", 0.0, 0.05)
	return tw


func hit() -> void:
	flash = 1.0
	hurt_t = 0.35
	Fx.shake(self, 10.0, 0.25)


func dodge() -> void:
	var base := position
	var tw := create_tween()
	tw.tween_property(self, "position", base + Vector2(-34 * face, 0), 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "position", base, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# ------------------------------------------------------------------ sheets

static func _load(name: String) -> Texture2D:
	if not _tex.has(name):
		var p := "res://assets/tinyswords/units/%s.png" % name
		if not ResourceLoader.exists(p):
			p = "res://assets/units/%s.png" % name
		_tex[name] = load(p) if ResourceLoader.exists(p) else null
	return _tex[name]


static func _frame_counts() -> Dictionary:
	if _frames.is_empty():
		var f := FileAccess.open("res://assets/units/frames.json", FileAccess.READ)
		if f:
			_frames = JSON.parse_string(f.get_as_text())
	return _frames


## Texture + frame width for one animation of this actor ("" if missing).
func _sheet(motion: String) -> Array:
	var sd: Array = SPRITES.get(art, SPRITES.thug)
	var fam := str(sd[0])
	var base := str(sd[1])
	var col := str(sd[4])
	if col == "k":
		col = Actor.kingdom
	var name := ""
	match fam:
		"ts":
			var m: String = motion
			if motion == "idle" and sd.size() > 5:
				m = str(sd[5])
			if motion in ["hurt", "dead"]:
				return []
			name = ("%s_%s_%s" % [col, base, m]) if col != "" else ("%s_%s" % [base, m])
		"pinero":
			name = "pinero_%s_%s" % [base, motion]
		"strip":
			name = "%s_%s" % [base, motion]
	var t := Actor._load(name)
	if t == null:
		return []
	var fw: int
	match fam:
		"ts":
			fw = t.get_height()
		"pinero":
			fw = t.get_width() / 3
		_:
			if KP_FRAME.has(base):
				fw = KP_FRAME[base]
			else:
				var n := int(Actor._frame_counts().get(name, 1))
				fw = t.get_width() / maxi(1, n)
	return [t, fw]


func _draw() -> void:
	var w := size.x
	var h := size.y
	var base := Vector2(w / 2.0, h - 24)
	if active and not dead:
		_ring(base + Vector2(0, 6), w * 0.36, Color("#ffd75e"), 4.0)
	if targetable and not dead:
		var p := 1.0 + sin(time * 6.0) * 0.06
		_ring(base + Vector2(0, 6), w * 0.4 * p, Color("#ff8a7a"), 5.0)
	_shadow(base + Vector2(0, 4), w * 0.3, 12.0, 0.4 * (1.0 - fall * 0.6))
	var sd: Array = SPRITES.get(art, SPRITES.thug)
	var sc := float(sd[2])
	var native := float(sd[3])
	var motion := "idle"
	var frame_f := time * 8.0
	if dead:
		motion = "dead"
	elif pose > 0.05:
		motion = "attack"
	elif hurt_t > 0.0:
		motion = "hurt"
	var sh := _sheet(motion)
	if sh.is_empty():
		sh = _sheet("idle")
		motion = "idle"
	if sh.is_empty():
		return
	var t: Texture2D = sh[0]
	var fw: int = sh[1]
	var n := maxi(1, t.get_width() / fw)
	var frame := int(frame_f) % n
	if motion == "attack":
		frame = clampi(int(pose * n), 0, n - 1)
	elif motion == "dead":
		frame = clampi(int(fall * n), 0, n - 1)
	var src := Rect2(fw * frame, 0, fw, t.get_height())
	var sz := src.size * sc
	var mod := Color.WHITE.lerp(Color(1.0, 0.45, 0.45), flash * 0.8)
	if dead and _sheet("dead").is_empty():
		mod.a = 1.0 - fall * 0.85
	# feet: Tiny Swords frames keep ~28% empty space under the figure; others are bottom-aligned
	var foot := 0.28 * sz.y if str(sd[0]) == "ts" else 0.06 * sz.y
	if art in ["spearman", "raider"]:
		foot = 0.36 * sz.y
	var flip := face * native
	draw_set_transform(base.round(), 0.0, Vector2(flip, 1))
	draw_texture_rect_region(t, Rect2(Vector2(-sz.x / 2.0, -sz.y + foot).round(), sz), src, mod)
	if flash > 0.05:
		draw_texture_rect_region(t, Rect2(Vector2(-sz.x / 2.0, -sz.y + foot).round(), sz), src, Color(1, 1, 1, flash * 0.4))
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	if selected and not dead:
		var tp := Vector2(w / 2.0, 6 + int(time * 4.0) % 2 * 4)
		var tri := PackedVector2Array([tp + Vector2(-13, -10), tp + Vector2(13, -10), tp + Vector2(0, 9)])
		draw_colored_polygon(tri, Color("#ff8a7a"))
		tri.append(tri[0])
		draw_polyline(tri, PixelUI.INK, 3.0)


func _ring(c: Vector2, r: float, col: Color, wd: float) -> void:
	var pts := PackedVector2Array()
	for i in 33:
		var a := TAU * i / 32.0
		pts.append((c + Vector2(cos(a) * r, sin(a) * r * 0.28)).round())
	draw_polyline(pts, Color(col, 0.95), wd)


func _shadow(c: Vector2, rx: float, ry: float, a: float) -> void:
	var pts := PackedVector2Array()
	for i in 20:
		var ang := TAU * i / 20.0
		pts.append((c + Vector2(cos(ang) * rx, sin(ang) * ry)).round())
	draw_colored_polygon(pts, Color(0.16, 0.08, 0.24, a))
