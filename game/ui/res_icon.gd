class_name ResIcon
extends Control
## A tiny hand-drawn icon (food, wood, stone, gold, pop, hp, xp, moves).

var kind := "food"
var s := 1.0
var pixel := true       # pack icon when one exists (falls back to the old ink drawing)


static func make(p_kind: String, px: float = 22.0) -> ResIcon:
	var i := ResIcon.new()
	i.kind = p_kind
	i.s = px / 22.0
	i.custom_minimum_size = Vector2(px, px)
	i.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return i


func _draw() -> void:
	if pixel:
		var t := PixelUI.res_tex(kind)
		if t:
			texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			draw_texture_rect(t, Rect2(Vector2.ZERO, size), false)
			return
	DrawKit.res_icon(self, kind, size / 2.0, s)
