extends Node
## The look of the game in one place: palette, fonts, and the hand-drawn
## panel/button style used by every screen. Change a colour here and the
## whole game follows.

const PAPER := Color("#F5EEDF")
const CARD := Color("#FBF7EE")
const NOTE := Color("#FFFDF6")
const INK := Color("#2A2430")
const PENCIL := Color("#6E6573")
const FAINT := Color("#B8AE9C")

const CORAL := Color("#E08A76")
const PINK := Color("#EBC1BC")
const YELLOW := Color("#F2DC97")
const SAGE := Color("#AFC79E")
const TEAL := Color("#82B5AF")
const POWDER := Color("#A8C3DD")
const LAVENDER := Color("#C6B8DC")
const SAND := Color("#E3CFA6")

const GOOD := Color("#3F6B3A")
const BAD := Color("#A0412C")
const GOLD := Color("#8A6A12")

const BAND_COLORS := [Color("#AFC79E"), Color("#F2DC97"), Color("#E08A76")]

const TERRAIN := {
	"plains": [Color("#E8DDB5"), Color("#E3D7AA"), Color("#EAE0BC"), Color("#DED6A8")],
	"forest": [Color("#A9C08C"), Color("#A2BA86"), Color("#AEC592")],
	"hills": [Color("#DCC496"), Color("#D6BD8C"), Color("#E0C99D")],
	"mountain": [Color("#CFC5B6"), Color("#C9BFAF")],
	"water": [Color("#7FAFC2"), Color("#78A9BE"), Color("#84B3C5")],
}
const TERRAIN_SIDE := {
	"plains": Color("#B9A577"), "forest": Color("#7F9867"), "hills": Color("#B39463"),
	"mountain": Color("#958877"), "water": Color("#4F8199"),
}

var display: Font
var body: Font
var body_bold: Font
var body_heavy: Font
var theme: Theme
var paper_shader: Shader


func _ready() -> void:
	# Tiny Swords look: every text uses the Pixelify Sans pixel font (OFL), at
	# different weights. Nunito stays as a fallback for symbols Pixelify lacks.
	display = _pixel(700)
	body = _pixel(400)
	body_bold = _pixel(500)
	body_heavy = _pixel(650)
	theme = _build_theme()
	get_tree().root.theme = theme
	paper_shader = load("res://render/paper.gdshader")


func _font(file: String, fallback: String) -> Font:
	var f: FontFile = load("res://assets/fonts/%s.woff2" % file)
	var fb: FontFile = load("res://assets/fonts/%s.woff2" % fallback)
	var fv := FontVariation.new()
	fv.base_font = f
	if fb:
		fv.fallbacks = [fb]
	return fv


func _pixel(weight: int) -> Font:
	var f: FontFile = load("res://assets/fonts/PixelifySans.ttf")
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	f.hinting = TextServer.HINTING_NONE
	var fv := FontVariation.new()
	fv.base_font = f
	fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	var fb: FontFile = load("res://assets/fonts/Nunito-800.woff2")
	var fb2: FontFile = load("res://assets/fonts/Nunito-800-LatinExt.woff2")
	fv.fallbacks = [fb, fb2]
	return fv


func kingdom_color(kid: String, which: String = "color") -> Color:
	var k: Dictionary = Data.kingdoms().get(kid, {})
	return Color(str(k.get(which, "#888888")))


func res_color(r: String) -> Color:
	match r:
		"food": return Color("#7FA36B")
		"wood": return Color("#B58F62")
		"stone": return Color("#9C9488")
		"gold": return Color("#D9B443")
		"iron": return Color("#7D8796")
		"pop": return Color("#C6B8DC")
	return INK


# ------------------------------------------------------------------ boxes

## Panel / chip / button background in the Tiny Swords look.
## Paper colours become the pack's parchment nine-slice; any other colour is a
## flat pixel box (square-stepped corners, ink rim, thicker bottom edge as the
## hard shadow). `seed` is kept for older callers; nothing is random any more.
func box(fill: Color = CARD, seed: int = 1, shadow: float = 0.0, border: Color = INK, width: float = 2.0, margin: float = 14.0) -> StyleBox:
	var paper := fill.is_equal_approx(CARD) or fill.is_equal_approx(NOTE) or fill.is_equal_approx(PAPER)
	if paper and width >= 1.5 and margin >= 8.0:
		return PixelUI.box("nine_paper", Vector4(margin + 4, margin, margin + 4, margin + 2))
	var b := StyleBoxFlat.new()
	b.bg_color = fill
	b.border_color = Color(PixelUI.INK, border.a) if border.a > 0.0 else Color(0, 0, 0, 0)
	var w := 0 if width <= 0.0 else maxi(2, int(round(width)))
	b.border_width_left = w
	b.border_width_top = w
	b.border_width_right = w
	b.border_width_bottom = w + (3 if shadow > 0.0 else 1) if w > 0 else 0
	b.corner_radius_top_left = 4
	b.corner_radius_top_right = 4
	b.corner_radius_bottom_left = 4
	b.corner_radius_bottom_right = 4
	b.corner_detail = 2
	b.anti_aliasing = false
	b.set_content_margin_all(margin)
	return b


func _build_theme() -> Theme:
	var t := Theme.new()
	t.default_font = body_bold
	t.default_font_size = 18

	t.set_color("font_color", "Label", INK)
	t.set_color("font_color", "RichTextLabel", INK)
	t.set_color("default_color", "RichTextLabel", INK)
	t.set_font("normal_font", "RichTextLabel", body)
	t.set_font("bold_font", "RichTextLabel", body_heavy)

	# buttons: pack parchment, gold-rimmed when hovered / pressed
	var pad := Vector4(16, 8, 16, 10)
	t.set_stylebox("normal", "Button", PixelUI.box("nine_paper", pad))
	t.set_stylebox("hover", "Button", PixelUI.box("btn_hover", pad))
	t.set_stylebox("pressed", "Button", PixelUI.box("btn_hover", pad + Vector4(0, 2, 0, -2)))
	t.set_stylebox("hover_pressed", "Button", PixelUI.box("btn_hover", pad + Vector4(0, 2, 0, -2)))
	t.set_stylebox("disabled", "Button", PixelUI.box("btn_disable", pad))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", INK)
	t.set_color("font_pressed_color", "Button", INK)
	t.set_color("font_disabled_color", "Button", Color("#8E8679"))
	t.set_font("font", "Button", body_heavy)
	t.set_font_size("font_size", "Button", 17)

	t.set_stylebox("panel", "PanelContainer", box(CARD, 5, 0.0))
	t.set_stylebox("panel", "Panel", box(CARD, 5, 0.0))

	var tip := box(NOTE, 9, 3.0, INK, 1.5, 10.0)
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", INK)
	t.set_font("font", "TooltipLabel", body_bold)

	var le := box(Color(0, 0, 0, 0), 11, 0.0, INK, 0.0, 4.0)
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", StyleBoxEmpty.new())
	t.set_font("font", "LineEdit", display)
	t.set_font_size("font_size", "LineEdit", 40)
	t.set_color("font_color", "LineEdit", INK)
	t.set_color("caret_color", "LineEdit", BAD)
	return t


# ------------------------------------------------------------------ labels

func label(text: String, size: int = 18, font: Font = null, color: Color = INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font if font else body_bold)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func hand(text: String, size: int = 28, color: Color = INK) -> Label:
	return label(text, size, display, color)


func caps(text: String, color: Color = PENCIL) -> Label:
	var l := label(text.to_upper(), 13, body_heavy, color)
	return l


func button(text: String, fill: Color = CARD, size: int = 17, seed: int = 3) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	if fill != CARD:
		var kind := _button_kind(fill)
		var pad := Vector4(18, 8, 18, 10)
		if kind != "":
			b.add_theme_stylebox_override("normal", PixelUI.box(kind, pad))
			b.add_theme_stylebox_override("hover", PixelUI.box("btn_hover", pad))
			var pk: String = {"btn_blue": "btn_blue_pressed", "btn_red": "btn_red_pressed"}.get(kind, kind)
			b.add_theme_stylebox_override("pressed", PixelUI.box(pk, pad + Vector4(0, 2, 0, -2)))
			b.add_theme_stylebox_override("hover_pressed", PixelUI.box(pk, pad + Vector4(0, 2, 0, -2)))
			if kind in ["btn_blue", "btn_red"]:
				b.add_theme_color_override("font_color", PixelUI.CREAM)
				b.add_theme_color_override("font_pressed_color", PixelUI.CREAM)
		else:
			b.add_theme_stylebox_override("normal", box(fill, seed, 3.0, INK, 2.0, 10.0))
			b.add_theme_stylebox_override("hover", box(fill.lightened(0.12), seed, 3.0, INK, 2.0, 10.0))
			b.add_theme_stylebox_override("pressed", box(fill.darkened(0.08), seed, 0.0, INK, 2.0, 10.0))
			b.add_theme_stylebox_override("hover_pressed", box(fill.darkened(0.08), seed, 0.0, INK, 2.0, 10.0))
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.mouse_entered.connect(func(): Audio.play("hover", -14.0, 0.15))
	b.pressed.connect(func(): Audio.play("click"))
	return b


## Which pack button a fill colour maps to ("" = keep a flat pixel box in that colour).
func _button_kind(fill: Color) -> String:
	if fill.is_equal_approx(YELLOW):
		return "btn_hover"
	if fill.is_equal_approx(CORAL) or fill.is_equal_approx(PINK):
		return "btn_red"
	if fill.is_equal_approx(SAGE) or fill.is_equal_approx(TEAL) or fill.is_equal_approx(POWDER):
		return "btn_blue"
	return ""


## A big hand-lettered call-to-action button (coral, display font).
func cta(text: String, fill: Color = CORAL, size: int = 28) -> Button:
	var b := button(text, fill, size, 7)
	b.add_theme_font_override("font", display)
	b.custom_minimum_size.y = 56
	return b


func paper_rect(tint: Color = PAPER, grain: float = 1.0) -> ColorRect:
	var r := ColorRect.new()
	r.color = tint
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = load("res://render/paper.gdshader")
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("grain", grain)
	r.material = m
	return r
