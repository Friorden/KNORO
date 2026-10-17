class_name PixelUI
extends RefCounted
## UI pieces for the Tiny Swords look: nine-slice panels and buttons cut from the
## pack (tools/ts_prepare.py packs them into contiguous 3x3 textures), a pixel
## font, and small drawn helpers (paper tags, level badges).
##
## The API mirrors Style (label / hand / caps / button / cta / box) so a screen
## can switch look by swapping `Style.` for `PixelUI.`.

const UI := "res://assets/tinyswords/ui/"
const INK := Color("#2b2a33")
const CREAM := Color("#fbf3df")
const MUTED := Color("#6a5f55")
const VIOLET := Color("#4a2d6b")
const GOOD := Color("#2f6b35")
const BAD := Color("#b8433a")

# visible border depth of each nine-slice (texture margin), in source pixels
const MARGIN := {
	"nine_paper": 22, "nine_special": 24, "nine_wood": 40, "nine_banner": 40,
	"nine_blue": 18, "nine_red": 18, "nine_blue_pressed": 18, "nine_red_pressed": 18,
	"btn_blue": 14, "btn_red": 14, "btn_hover": 14, "btn_disable": 14, "btn_blue_pressed": 14, "btn_red_pressed": 14, "nine_carved": 18,
}

static var _font: Font
static var _cache: Dictionary = {}


static func font() -> Font:
	return Style.body_heavy


static func tex(name: String) -> Texture2D:
	if not _cache.has(name):
		_cache[name] = load(UI + name + ".png")
	return _cache[name]


## Nine-slice stylebox. pad = inner padding around the content.
## Pack panels (paper, wood, banner) keep their full corner pieces and tile the
## centre, which the pack draws as a seamless pattern; the old-pack buttons have
## thin rims and flat centres, so they use a small margin and stretch.
static func box(name: String = "nine_paper", pad: Vector4 = Vector4(18, 14, 18, 14), m: int = -1) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = tex(name)
	var mg: Array = _margins().get("ui/%s.png" % name, [])
	if m < 0 and mg.size() == 4:
		sb.texture_margin_left = int(mg[0])
		sb.texture_margin_top = int(mg[1])
		sb.texture_margin_right = int(mg[2])
		sb.texture_margin_bottom = int(mg[3])
		sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
		sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	else:
		var mm: int = m if m >= 0 else int(MARGIN.get(name, 20))
		sb.texture_margin_left = mm
		sb.texture_margin_top = mm
		sb.texture_margin_right = mm
		sb.texture_margin_bottom = mm
	sb.content_margin_left = pad.x
	sb.content_margin_top = pad.y
	sb.content_margin_right = pad.z
	sb.content_margin_bottom = pad.w
	return sb


static var _mg: Dictionary = {}


static func _margins() -> Dictionary:
	if _mg.is_empty():
		var f := FileAccess.open("res://assets/tinyswords/ui/nine_margins.json", FileAccess.READ)
		if f:
			_mg = JSON.parse_string(f.get_as_text())
	return _mg


static func label(text: String, size: int = 18, color: Color = INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func wrap(text: String, size: int = 15, color: Color = INK, min_w: float = 170.0) -> Label:
	var l := label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(min_w, 0)
	return l


static func title(text: String, size: int = 34, color: Color = VIOLET) -> Label:
	return label(text.to_upper(), size, color)


static func caps(text: String, color: Color = MUTED) -> Label:
	return label(text.to_upper(), 14, color)


## kind: "blue" (primary), "red" (danger / end), "gold" (selected), "paper" (neutral).
static func button(text: String, kind: String = "paper", size: int = 17) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", font())
	b.add_theme_font_size_override("font_size", size)
	var pad := Vector4(16, 8, 16, 10)
	var normal: String = {"blue": "btn_blue", "red": "btn_red", "gold": "btn_hover", "paper": "nine_paper"}.get(kind, "nine_paper")
	var pressed: String = {"blue": "btn_blue_pressed", "red": "btn_red_pressed", "gold": "btn_hover", "paper": "nine_paper"}.get(kind, "nine_paper")
	b.add_theme_stylebox_override("normal", box(normal, pad))
	b.add_theme_stylebox_override("hover", box("btn_hover" if kind != "gold" else normal, pad))
	b.add_theme_stylebox_override("pressed", box(pressed, pad + Vector4(0, 2, 0, -2)))
	b.add_theme_stylebox_override("hover_pressed", box(pressed, pad + Vector4(0, 2, 0, -2)))
	b.add_theme_stylebox_override("disabled", box("btn_disable", pad))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var fg := CREAM if kind in ["blue", "red"] else INK
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", INK)
	b.add_theme_color_override("font_pressed_color", fg)
	b.add_theme_color_override("font_hover_pressed_color", fg)
	b.add_theme_color_override("font_disabled_color", Color(MUTED, 0.8))
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.mouse_entered.connect(func(): Audio.play("hover", -14.0, 0.15))
	b.pressed.connect(func(): Audio.play("click"))
	return b


static func cta(text: String, kind: String = "blue", size: int = 24) -> Button:
	var b := button(text, kind, size)
	b.custom_minimum_size.y = 60
	return b


## A small paper label drawn directly on a CanvasItem (production tags on the city).
static func paper_tag(ci: CanvasItem, r: Rect2) -> void:
	var t := tex("nine_paper")
	var m := 12.0
	var src := Rect2(Vector2.ZERO, t.get_size())
	var sm := 22.0
	# corners / edges / centre from the 3x3 (source margin sm, drawn margin m)
	var xs := [r.position.x, r.position.x + m, r.end.x - m]
	var ys := [r.position.y, r.position.y + m, r.end.y - m]
	var ws := [m, r.size.x - 2 * m, m]
	var hs := [m, r.size.y - 2 * m, m]
	var sx := [0.0, sm, src.size.x - sm]
	var sy := [0.0, sm, src.size.y - sm]
	var sw := [sm, src.size.x - 2 * sm, sm]
	var sh := [sm, src.size.y - 2 * sm, sm]
	for i in 3:
		for j in 3:
			ci.draw_texture_rect_region(t, Rect2(xs[i], ys[j], ws[i], hs[j]), Rect2(sx[i], sy[j], sw[i], sh[j]))


## Gold level badge ("II", "III") with an ink rim.
static func badge(ci: CanvasItem, p: Vector2, text: String, f: Font, fs: int) -> void:
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 14.0
	var r := Rect2((p - Vector2(w / 2.0, 13)).round(), Vector2(w, 26))
	ci.draw_rect(r.grow(2), INK)
	ci.draw_rect(r, Color("#e2b43c"))
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x, 4)), Color("#fce678"))
	ci.draw_string(f, r.position + Vector2(7, 20), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, INK)


## Resource icon (pack art) as a TextureRect for lists and the HUD.
static func res_icon(kind: String, px: float = 32.0) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = res_tex(kind)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.custom_minimum_size = Vector2(px, px)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


static func res_tex(kind: String) -> Texture2D:
	var path: String = {"food": "tinyswords/ui/icon_04", "wood": "tinyswords/ui/icon_02", "gold": "tinyswords/ui/icon_03",
		"stone": "tinyswords/rock1", "iron": "icons/res_iron", "pop": "tinyswords/ui/avatar_10", "hp": "icons/res_hp",
		"xp": "icons/res_xp", "moves": "tinyswords/ui/icon_07", "sword": "tinyswords/ui/icon_05", "cargo": "props/chest"}.get(kind, "")
	if path == "":
		return null
	# cached: a texture drawn by _draw() must stay referenced, or its RID is freed and draws white
	if not _cache.has("res:" + kind):
		var p := "res://assets/%s.png" % path
		_cache["res:" + kind] = load(p) if ResourceLoader.exists(p) else null
	return _cache["res:" + kind]


## Full-screen pack backdrop (render/art.gd) with a violet wash, drifting slowly.
## Replaces the old paper background on menu-like screens.
static func backdrop(bg_name: String, wash: float = 0.45) -> Control:
	var c := Control.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	c.set_meta("t", 0.0)
	c.draw.connect(func():
		var t := Art.tex(bg_name)
		if t:
			Art.draw_cover(c, t, Rect2(Vector2.ZERO, c.size), float(c.get_meta("t")), 0.03)
		c.draw_rect(Rect2(Vector2.ZERO, c.size), Color(0.16, 0.08, 0.26, wash)))
	var tm := Timer.new()
	tm.wait_time = 0.1
	tm.autostart = true
	tm.timeout.connect(func():
		c.set_meta("t", float(c.get_meta("t")) + 0.1)
		c.queue_redraw())
	c.add_child(tm)
	return c


## Makes a label readable straight on a backdrop: cream text with a dark outline.
static func on_dark(l: Label, outline: int = 10, col: Color = CREAM) -> Label:
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color("#2b1d3d"))
	l.add_theme_constant_override("outline_size", outline)
	return l
