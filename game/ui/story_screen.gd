extends Control
## The prologue before a new campaign: a few illustrated pages, then the
## kingdom choice. Space / Enter / click turns the page, Esc skips.

const PAGES := [
	["dusk_a", "Long ago there was one crown.", "It was forged from starsteel for the first king of the valley. When he died, his nine children broke it into nine pieces, and each carried a shard home to found a kingdom of their own."],
	["canyon", "The shards were lost.", "Wars came and went. The shards were stolen, traded, buried. Today only songs and ruins remember them, and the nine kingdoms remember only that they once were one."],
	["cave2", "Something stirs below.", "Kobolds hoard what shines in the crystal caves. The dead walk in the old crypt. A troll king beats his drums in a fortress the sea half swallowed. Each of them holds a piece of the old crown."],
	["dusk_b", "A new banner is raised.", "You are the Champion of a small settlement: a hall, a field, a handful of people. Build it into a kingdom. Walk the roads yourself. Make friends, make enemies — and find the crown that makes a king."],
]

var page := 0
var time := 0.0
var scene := Control.new()
var title_l: Label
var text_l: Label
var hint: Label
var bg: Texture2D


func enter(_data: Dictionary) -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scene.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scene.draw.connect(_draw_scene)
	add_child(scene)
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", PixelUI.box("nine_paper", Vector4(52, 36, 52, 40)))
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	box.offset_left = -620
	box.offset_right = 620
	box.offset_top = -330
	box.offset_bottom = -60
	add_child(box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	box.add_child(v)
	title_l = PixelUI.label("", 40, PixelUI.VIOLET)
	v.add_child(title_l)
	text_l = PixelUI.wrap("", 24, PixelUI.INK, 1100)
	text_l.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(text_l)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	v.add_child(row)
	hint = PixelUI.label("", 16, PixelUI.MUTED)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(hint)
	var skip := PixelUI.button("Skip", "paper", 18)
	skip.pressed.connect(_done)
	row.add_child(skip)
	var nxt := PixelUI.button("Next", "blue", 20)
	nxt.custom_minimum_size = Vector2(160, 54)
	nxt.pressed.connect(_next)
	row.add_child(nxt)
	_show()


func _show() -> void:
	var p: Array = PAGES[page]
	bg = Art.tex(str(p[0]))
	title_l.text = str(p[1])
	text_l.text = str(p[2])
	text_l.visible_ratio = 0.0
	var tw := create_tween()
	tw.tween_property(text_l, "visible_ratio", 1.0, 1.6)
	hint.text = "%d / %d   ·   Space or click to continue, Esc to skip" % [page + 1, PAGES.size()]
	Audio.play("paper", -6.0)


func _next() -> void:
	if text_l.visible_ratio < 1.0:
		text_l.visible_ratio = 1.0
		return
	page += 1
	if page >= PAGES.size():
		_done()
	else:
		_show()


func _done() -> void:
	Main.go("select")


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		if e.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
			_next()
		elif e.keycode == KEY_ESCAPE:
			_done()
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		_next()


func _process(d: float) -> void:
	time += d
	scene.queue_redraw()


func _draw_scene() -> void:
	var vs := get_viewport_rect().size
	if bg:
		Art.draw_cover(scene, bg, Rect2(Vector2.ZERO, vs), time, 0.04)
	scene.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.12, 0.05, 0.2, 0.25))
