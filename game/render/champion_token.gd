class_name ChampionToken
extends Node2D
## The Champion on the map: the Tiny Swords Warrior in the kingdom's colour
## (idle while standing, running while moving hex to hex), with the war band
## following as small pawns. Pixel art, drawn at 1x (see assets/LICENSES.md).

var cloak := Color("#6B5E78")
var banner := Color("#D46A55")
var kingdom := "red"
var time := 0.0
var squash := 1.0
var face := 1.0
var hurt := 0.0
var scale_k := 1.0
var dead := false
var hopping := false
var army := 0          # recruited units following the Champion
var _tex: Dictionary = {}


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _process(delta: float) -> void:
	time += delta
	hurt = maxf(0.0, hurt - delta * 1.5)
	queue_redraw()


func hop(to: Vector2, duration: float = 0.3) -> Tween:
	hopping = true
	if absf(to.x - position.x) > 2.0:
		face = signf(to.x - position.x)
	var from := position
	var tw := create_tween()
	tw.tween_method(func(t: float): position = from.lerp(to, t).round(), 0.0, 1.0, duration)
	tw.tween_callback(func(): hopping = false)
	return tw


func _t(name: String) -> Texture2D:
	if not _tex.has(name):
		var p := "res://assets/tinyswords/units/%s.png" % name
		_tex[name] = load(p) if ResourceLoader.exists(p) else null
	return _tex[name]


## Draws one square-frame sheet with its feet (frame bottom minus `foot`) at `at`.
func _sheet(name: String, at: Vector2, fps: float, foot: float, flip: bool, mod := Color.WHITE) -> void:
	var t := _t(name)
	if t == null:
		return
	var fh := t.get_height()
	var n := maxi(1, t.get_width() / fh)
	var src := Rect2(fh * (int(time * fps) % n), 0, fh, fh)
	draw_set_transform(at.round(), 0.0, Vector2(-1 if flip else 1, 1))
	draw_texture_rect_region(t, Rect2(-fh / 2.0, -fh + foot, fh, fh), src, mod)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _shadow(at: Vector2, rx: float, ry: float) -> void:
	var sh := PackedVector2Array()
	for i in 16:
		var a := TAU * i / 16.0
		sh.append((at + Vector2(cos(a) * rx, sin(a) * ry)).round())
	draw_colored_polygon(sh, Color(0.24, 0.13, 0.36, 0.42))


func _draw() -> void:
	var k := kingdom
	for i in mini(army, 4):
		var fp := Vector2(-30.0 * face - i * 18.0 * face, 10 + (i % 2) * 8)
		_shadow(fp + Vector2(0, 2), 14, 5)
		_sheet("%s_pawn_run" % k if hopping else "%s_pawn_idle" % k, fp, 10.0 if hopping else 8.0, 52.0, face < 0)
	_shadow(Vector2(0, 4), 26, 8)
	if dead:
		var d := _t("dead")
		if d:
			var fw := d.get_height()
			draw_texture_rect_region(d, Rect2(Vector2(-fw / 2.0, -fw + 60), Vector2(fw, fw)), Rect2(fw * 6, 0, fw, fw))
		return
	var mod := Color(1, 1, 1).lerp(Color(1, 0.5, 0.5), hurt)
	_sheet("%s_warrior_run" % k if hopping else "%s_warrior_idle" % k, Vector2(0, 0), 12.0 if hopping else 9.0, 55.0, face < 0, mod)
