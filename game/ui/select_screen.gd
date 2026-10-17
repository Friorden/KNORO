extends Control
## Kingdom choice. The generated world is shown with the real map renderer
## (Tiny Swords tiles, fully revealed, scaled down) on the left; the selected
## kingdom's land, traits, starting stores and motto on the right.

const KINGDOMS := ["red", "blue", "yellow"]

var sel := "red"
var info := VBoxContainer.new()
var tabs := HBoxContainer.new()
var time := 0.0
var bg := Control.new()
var vpc := SubViewportContainer.new()
var vp := SubViewport.new()
var sea := ColorRect.new()
var map: MapView
var preview_state: GameState
var seed_l: Label


func enter(_data: Dictionary) -> void:
	Audio.music("music_world")
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.draw.connect(func():
		var t := Art.tex("dusk_b")
		if t:
			Art.draw_cover(bg, t, Rect2(Vector2.ZERO, bg.size), time, 0.03)
		bg.draw_rect(Rect2(Vector2.ZERO, bg.size), Color(0.14, 0.06, 0.24, 0.35)))
	add_child(bg)
	_build()
	_make_preview()


func _build() -> void:
	var root := MarginContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		root.add_theme_constant_override("margin_" + side, 60)
	root.add_theme_constant_override("margin_top", 36)
	root.add_theme_constant_override("margin_bottom", 36)
	add_child(root)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	root.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 22)
	col.add_child(head)
	var tcol := VBoxContainer.new()
	head.add_child(tcol)
	var t := PixelUI.label("Choose your kingdom", 64, PixelUI.CREAM)
	t.add_theme_color_override("font_outline_color", Color("#2b1d3d"))
	t.add_theme_constant_override("outline_size", 14)
	tcol.add_child(t)
	var st := PixelUI.label("Nine kingdoms share the valley. You were born to one of three.", 22, Color("#ffe3a6"))
	st.add_theme_color_override("font_outline_color", Color("#2b1d3d"))
	st.add_theme_constant_override("outline_size", 8)
	tcol.add_child(st)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var seed_box := PanelContainer.new()
	seed_box.add_theme_stylebox_override("panel", PixelUI.box("nine_paper", Vector4(20, 12, 20, 14)))
	seed_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(seed_box)
	var sbv := HBoxContainer.new()
	sbv.add_theme_constant_override("separation", 12)
	seed_box.add_child(sbv)
	seed_l = PixelUI.label("World seed %d" % Game.seed, 16, PixelUI.MUTED)
	seed_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sbv.add_child(seed_l)
	var reroll := PixelUI.button("New world ↻", "paper", 16)
	reroll.pressed.connect(func():
		Game.seed = randi() % 100000
		seed_l.text = "World seed %d" % Game.seed
		_make_preview())
	sbv.add_child(reroll)
	var back := PixelUI.button("Back", "red", 16)
	back.pressed.connect(func(): Main.go("title"))
	sbv.add_child(back)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 30)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 12)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(left)
	tabs.add_theme_constant_override("separation", 12)
	left.add_child(tabs)
	var map_panel := PanelContainer.new()
	map_panel.add_theme_stylebox_override("panel", PixelUI.box("nine_paper", Vector4(22, 22, 22, 22)))
	map_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(map_panel)
	vpc.stretch = true
	vpc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vpc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_panel.add_child(vpc)
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	vpc.add_child(vp)
	sea.color = Color("#47aba9")
	sea.size = Vector2(8000, 8000)
	sea.position = Vector2(-4000, -4000)
	vp.add_child(sea)
	vpc.resized.connect(_fit)

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", PixelUI.box("nine_paper", Vector4(36, 30, 36, 32)))
	card.custom_minimum_size = Vector2(560, 0)
	body.add_child(card)
	info.add_theme_constant_override("separation", 14)
	card.add_child(info)
	_rebuild_tabs()
	_rebuild_info()


## A throwaway campaign state, fully explored, so the real map renderer can draw the world.
func _make_preview() -> void:
	preview_state = GameState.new()
	preview_state.new_game(Game.seed, sel, Champion.new())
	for h in preview_state.world.tiles.keys():
		preview_state.explored[h] = true
	preview_state.flags["surveyor_map"] = true
	if map:
		map.queue_free()
	map = MapView.new()
	vp.add_child(map)
	map.setup(preview_state)
	map.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_fit.call_deferred()


func _fit() -> void:
	if map == null:
		return
	var b := map.bounds()
	var vs := vpc.size
	if b.size.x <= 0 or vs.x <= 0:
		return
	var k := minf(vs.x / b.size.x, vs.y / b.size.y) * 0.98
	map.scale = Vector2(k, k)
	map.position = vs / 2.0 - b.get_center() * k


func _process(d: float) -> void:
	time += d
	bg.queue_redraw()


func _rebuild_tabs() -> void:
	for c in tabs.get_children():
		c.queue_free()
	for kid in KINGDOMS:
		var on: bool = kid == sel
		var b := PixelUI.button(str(Data.kingdoms()[kid].name), "gold" if on else "paper", 20)
		b.custom_minimum_size = Vector2(190, 56)
		b.icon = _castle_icon(kid)
		var k: String = kid
		b.pressed.connect(func():
			sel = k
			_rebuild_tabs()
			_rebuild_info()
			_make_preview())
		tabs.add_child(b)


static var _icons: Dictionary = {}


static func _castle_icon(kid: String) -> Texture2D:
	if not _icons.has(kid):
		var t: Texture2D = load("res://assets/tinyswords/city/b_%s_castle.png" % kid)
		var img := t.get_image()
		img.resize(int(img.get_width() * 0.16), int(img.get_height() * 0.16), Image.INTERPOLATE_NEAREST)
		_icons[kid] = ImageTexture.create_from_image(img)
	return _icons[kid]


func _rebuild_info() -> void:
	for c in info.get_children():
		c.queue_free()
	var k: Dictionary = Data.kingdoms()[sel]
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 18)
	info.add_child(head)
	var castle := TextureRect.new()
	castle.texture = load("res://assets/tinyswords/city/b_%s_castle.png" % sel)
	castle.custom_minimum_size = Vector2(150, 120)
	castle.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	castle.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	castle.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	head.add_child(castle)
	var hc := VBoxContainer.new()
	hc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(hc)
	hc.add_child(PixelUI.label("%s Kingdom" % k.name, 44, Style.kingdom_color(sel).darkened(0.35)))
	hc.add_child(PixelUI.wrap(str(k.land), 16, PixelUI.MUTED, 320))
	for tr in k.traits:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var good: bool = tr[0] == "+"
		row.add_child(PixelUI.label("+" if good else "−", 28, PixelUI.GOOD if good else PixelUI.BAD))
		row.add_child(PixelUI.label(str(tr[1]), 19))
		info.add_child(row)
	info.add_child(PixelUI.caps("Starting stores"))
	var stores := HBoxContainer.new()
	stores.add_theme_constant_override("separation", 18)
	for r in ["food", "wood", "stone", "gold"]:
		var b := HBoxContainer.new()
		b.add_theme_constant_override("separation", 5)
		b.add_child(PixelUI.res_icon(r, 28))
		b.add_child(PixelUI.label(str(int((k.get("start", Data.B("start", {})) as Dictionary).get(r, 0))), 20))
		stores.add_child(b)
	info.add_child(stores)
	info.add_child(PixelUI.label("“%s”" % k.motto, 26, PixelUI.VIOLET))
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info.add_child(sp)
	var go := PixelUI.cta("Rule the %s kingdom  →" % str(k.name), "blue", 26)
	go.pressed.connect(func():
		Game.chosen_kingdom = sel
		Main.go("create"))
	info.add_child(go)
	for i in info.get_child_count():
		var c := info.get_child(i)
		if c is Control:
			Fx.pop_in(c, i * 0.04, 0.95)
