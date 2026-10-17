extends Control
## Main menu. A slow parallax of ansimuz's Mountain Dusk layers, a little
## procession of Tiny Swords travellers along the ridge, and the menu on a
## parchment panel: Continue, New game, Load, Settings, How to play, Credits, Quit.

const LAYERS := [["title_sky", 0.0], ["title_far_clouds", 4.0], ["title_far_mountains", 7.0],
	["title_near_clouds", 12.0], ["title_mountains", 16.0], ["title_trees", 30.0]]
const WALKERS := [["red_warrior_run", 0.0], ["red_pawn_run_gold", 120.0], ["blue_pawn_run_wood", 250.0],
	["yellow_archer_idle", -1.0], ["blue_warrior_run", 520.0], ["yellow_pawn_run_meat", 640.0]]

var time := 0.0
var scene := Control.new()
var tex: Dictionary = {}
var menu := VBoxContainer.new()


func enter(_data: Dictionary) -> void:
	Audio.music("music_world")
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for l in LAYERS:
		tex[l[0]] = load("res://assets/bg/%s.png" % l[0])
	for w in WALKERS:
		tex[w[0]] = load("res://assets/tinyswords/units/%s.png" % w[0])
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scene.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scene.draw.connect(_draw_scene)
	add_child(scene)
	_build()


func _build() -> void:
	# logo
	var logo := VBoxContainer.new()
	logo.position = Vector2(120, 120)
	logo.add_theme_constant_override("separation", -6)
	add_child(logo)
	var t := PixelUI.label("KNORO", 150, Color("#fbf3df"))
	t.add_theme_color_override("font_outline_color", Color("#2b1d3d"))
	t.add_theme_constant_override("outline_size", 26)
	t.add_theme_color_override("font_shadow_color", Color(0.1, 0.04, 0.18, 0.6))
	t.add_theme_constant_override("shadow_offset_y", 10)
	logo.add_child(t)
	var sub := PixelUI.label("Nine crowns · one road · your kingdom", 30, Color("#ffe3a6"))
	sub.add_theme_color_override("font_outline_color", Color("#2b1d3d"))
	sub.add_theme_constant_override("outline_size", 10)
	logo.add_child(sub)
	Fx.slide_in(logo, Vector2(0, -40), 0.1)
	# menu panel
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", PixelUI.box("nine_paper", Vector4(40, 32, 40, 36)))
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.offset_right = -150
	panel.offset_top = -330
	panel.custom_minimum_size = Vector2(440, 0)
	add_child(panel)
	menu.add_theme_constant_override("separation", 12)
	panel.add_child(menu)
	var last := SaveGame.latest()
	if last != "":
		var m := SaveGame.meta(last)
		var b := _btn("Continue", "blue", func(): Menus.load_slot(last))
		b.tooltip_text = "%s · %s Kingdom · week %d" % [m.get("champion", "?"), m.get("kname", "?"), int(m.get("week", 1))]
		menu.add_child(PixelUI.label("%s · %s · Week %d" % [m.get("champion", "?"), m.get("kname", "?"), int(m.get("week", 1))], 15, PixelUI.MUTED))
	_btn("New game", "blue" if last == "" else "gold", func(): Main.go("story"))
	_btn("Load game", "paper", func(): Menus.saves(Main.instance.menu_layer, "load"))
	_btn("Settings", "paper", func(): Menus.settings(Main.instance.menu_layer))
	_btn("How to play", "paper", func(): Menus.help(Main.instance.menu_layer))
	_btn("Credits", "paper", func(): Menus.credits(Main.instance.menu_layer))
	_btn("Quit", "red", func(): get_tree().quit())
	Fx.slide_in(panel, Vector2(60, 0), 0.2)
	var ver := PixelUI.label("v1.0 · Godot 4 · art credits in Credits", 15, Color("#fbf3df"))
	ver.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	ver.offset_left = 24
	ver.offset_top = -40
	ver.add_theme_color_override("font_outline_color", Color("#2b1d3d"))
	ver.add_theme_constant_override("outline_size", 6)
	add_child(ver)


func _btn(text: String, kind: String, fn: Callable) -> Button:
	var b := PixelUI.button(text, kind, 24)
	b.custom_minimum_size = Vector2(0, 62)
	b.pressed.connect(fn)
	menu.add_child(b)
	return b


func _process(d: float) -> void:
	time += d
	scene.queue_redraw()


func _draw_scene() -> void:
	var vs := get_viewport_rect().size
	var k := vs.y / 240.0
	for l in LAYERS:
		var t: Texture2D = tex[l[0]]
		if t == null:
			continue
		var w := t.get_width() * k
		var off := fmod(time * float(l[1]), w)
		var x := -off
		while x < vs.x:
			scene.draw_texture_rect(t, Rect2(Vector2(roundf(x), 0), Vector2(ceilf(w) + 1, vs.y)), false)
			x += w
	# travellers on the ridge, walking right
	var ground := vs.y * 0.86
	for i in WALKERS.size():
		var wd: Array = WALKERS[i]
		var t: Texture2D = tex[wd[0]]
		if t == null:
			continue
		var fw := t.get_height()
		var n := maxi(1, t.get_width() / fw)
		var fr := int(time * 9.0 + i) % n
		var sc := 1.2
		var x: float
		if float(wd[1]) < 0.0:
			x = vs.x * 0.36
		else:
			x = fmod(time * 70.0 + float(wd[1]), vs.x + 400.0) - 200.0
		var sz := Vector2(fw, fw) * sc
		scene.draw_texture_rect_region(t, Rect2(Vector2(roundf(x - sz.x / 2.0), roundf(ground - sz.y * 0.72)), sz), Rect2(fr * fw, 0, fw, fw))
	scene.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.18, 0.06, 0.28, 0.12))
