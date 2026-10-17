extends Control
## A delve into a cave or dungeon (data/dungeons.json).
##
## The dungeon is a string of rooms shown as a path along the top: fights,
## chests, traps, shrines and quiet corners, with the guardian at the end.
## Fights go to the battle screen and come back here; between rooms the player
## can always turn back (progress is lost, cleared rooms stay cleared until then).
## All art comes from the packs: CraftPix cave backdrops, Pinero / Pixel Frog
## monsters, Treasure Hunters chests, Tiny Swords units and props.

const ROOM_ICON := {
	"fight": "res://assets/tinyswords/ui/icon_05.png", "boss": "res://assets/props/skull.png",
	"chest": "res://assets/props/chest.png", "trap": "res://assets/props/box.png",
	"shrine": "res://assets/props/red_bottle.png", "rest": "res://assets/props/table.png",
}
const ROOM_NAME := {"fight": "Monsters", "boss": "The guardian", "chest": "A chest", "trap": "A trap",
	"shrine": "An old shrine", "rest": "A quiet corner"}

var st: GameState
var did := ""
var d: Dictionary
var time := 0.0
var bg: Texture2D
var scene := Control.new()
var path_row := HBoxContainer.new()
var title_l: Label
var text_l: Label
var opts := HBoxContainer.new()
var hero: Actor
var foe: Actor
var foes: Array = []          # the rest of the group behind the lead
var prop := ""            # prop drawn in the room (chest / skull / fire ...)
var prop_open := false
var group := ""
var intro := false
var _tx: Dictionary = {}     # textures drawn in _draw_scene stay referenced here


func _tex_of(path: String) -> Texture2D:
	if not _tx.has(path):
		_tx[path] = load(path) if ResourceLoader.exists(path) else null
	return _tx[path]


func enter(data: Dictionary) -> void:
	st = Game.state
	Actor.kingdom = st.kingdom
	var from := str(data.get("from", ""))
	if from == "battle":
		did = str(st.dungeon_run.get("id", ""))
	else:
		did = str(data.get("id", "crystal_cave"))
		if st.dungeon_run.get("id", "") != did:
			st.start_dungeon(did)
		intro = true
	d = st.dungeon_def(did)
	var bgs: Array = d.get("bg", ["cave1"])
	bg = Art.tex(str(bgs[int(st.dungeon_run.get("room", 0)) % bgs.size()]))
	_build()
	Audio.music("music_combat")
	if from == "battle":
		_after_fight(str(data.get("result", "")), data.get("changes", []))
	elif intro:
		_show_intro()
	else:
		_show_room()


func _build() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scene.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scene.draw.connect(_draw_scene)
	add_child(scene)
	# heading
	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", PixelUI.box("nine_paper", Vector4(28, 14, 28, 18)))
	top.position = Vector2(36, 28)
	add_child(top)
	var tv := VBoxContainer.new()
	top.add_child(tv)
	tv.add_child(PixelUI.title(str(d.get("name", "Dungeon")), 34))
	tv.add_child(PixelUI.caps("%s · %d rooms and a guardian" % [st.kname(st.kingdom) + " expedition", int(d.get("rooms", 5))]))
	# room path
	var pathp := PanelContainer.new()
	pathp.add_theme_stylebox_override("panel", PixelUI.box("nine_paper", Vector4(22, 12, 22, 14)))
	pathp.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	pathp.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pathp.offset_top = 30
	add_child(pathp)
	path_row.add_theme_constant_override("separation", 6)
	pathp.add_child(path_row)
	# party: soldiers behind the Champion
	var us := st.units()
	for i in mini(us.size(), 4):
		var a := Actor.make(str(st.unit_stats(us[i]).art), Style.kingdom_color(st.kingdom), 200, 270)
		a.position = Vector2(250 - i * 70 + (i % 2) * 20, 520 - (i % 2) * 40)
		add_child(a)
	hero = Actor.make("champion", Style.kingdom_color(st.kingdom), 260, 330)
	hero.position = Vector2(380, 470)
	add_child(hero)
	foe = Actor.make("thug", Color.WHITE, 300, 340)
	foe.position = Vector2(1200, 460)
	foe.face = -1.0
	foe.visible = false
	add_child(foe)
	for i in 3:
		var a := Actor.make("thug", Color.WHITE, 240, 300)
		a.position = Vector2(1420 + i * 120, 440 - (i % 2) * 50)
		a.face = -1.0
		a.visible = false
		add_child(a)
		foes.append(a)
	# text box
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", PixelUI.box("nine_paper", Vector4(40, 28, 40, 30)))
	box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	box.offset_left = 120
	box.offset_right = -120
	box.offset_top = -290
	box.offset_bottom = -34
	add_child(box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	box.add_child(v)
	title_l = PixelUI.label("", 28, PixelUI.VIOLET)
	v.add_child(title_l)
	text_l = PixelUI.wrap("", 20, PixelUI.INK, 1200)
	text_l.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(text_l)
	opts.add_theme_constant_override("separation", 14)
	v.add_child(opts)
	_refresh_path()


func _refresh_path() -> void:
	for c in path_row.get_children():
		c.queue_free()
	var rooms: Array = st.dungeon_run.get("rooms", [])
	var cur := int(st.dungeon_run.get("room", 0))
	for i in rooms.size():
		var k := str(rooms[i])
		var cell := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("#ffd75e") if i == cur else (Color("#b9d98a") if i < cur else Color("#e9dcc0"))
		sb.border_color = PixelUI.INK
		sb.set_border_width_all(2)
		sb.border_width_bottom = 4
		sb.set_content_margin_all(4)
		cell.add_theme_stylebox_override("panel", sb)
		var ic := TextureRect.new()
		var known := i <= cur or k == "boss"
		ic.texture = load(ROOM_ICON.get(k, ROOM_ICON.fight)) if known else load("res://assets/tinyswords/ui/icon_07.png")
		ic.custom_minimum_size = Vector2(44, 44)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		ic.modulate = Color(1, 1, 1, 1.0 if known else 0.55)
		ic.tooltip_text = ROOM_NAME.get(k, k) if known else "Unknown"
		cell.add_child(ic)
		path_row.add_child(cell)


func _process(dt: float) -> void:
	time += dt
	scene.queue_redraw()


# ------------------------------------------------------------------ rooms

func _clear_opts() -> void:
	for c in opts.get_children():
		c.queue_free()


func _opt(text: String, kind: String, fn: Callable, sub: String = "") -> Button:
	var b := PixelUI.button(text + (("   " + sub) if sub != "" else ""), kind, 19)
	b.custom_minimum_size = Vector2(300, 58)
	b.pressed.connect(fn)
	opts.add_child(b)
	return b


func _show_intro() -> void:
	intro = false
	title_l.text = "At the entrance"
	text_l.text = str(d.get("intro", ""))
	prop = ""
	foe.visible = false
	_clear_opts()
	_opt("Delve in", "blue", _show_room)
	_opt("Turn back", "red", _leave)


func _show_room() -> void:
	var k := st.dungeon_room()
	var n := int(st.dungeon_run.room) + 1
	title_l.text = "Room %d · %s" % [n, ROOM_NAME.get(k, k)] if k != "boss" else "The guardian"
	foe.visible = false
	for a in foes:
		a.visible = false
	prop = ""
	prop_open = false
	_clear_opts()
	_refresh_path()
	match k:
		"fight", "boss":
			group = st.dungeon_group()
			var g: Dictionary = Data.enemies().groups.get(group, {})
			var lead := str(g.foes[0]) if k == "fight" else _boss_foe(g)
			var fd: Dictionary = Data.enemies().foes.get(lead, {})
			foe.art = str(fd.get("art", "thug"))
			foe.visible = true
			foe.scale = Vector2.ONE * (1.3 if k == "boss" else 1.0)
			var rest: Array = (g.foes as Array).duplicate()
			rest.erase(lead)
			for i in foes.size():
				var a: Actor = foes[i]
				a.visible = i < rest.size()
				if a.visible:
					a.art = str(Data.enemies().foes[rest[i]].art)
			var names: Array[String] = []
			for f in g.foes:
				names.append(str(Data.enemies().foes[f].name).to_lower())
			text_l.text = ("Something moves in the dark: %s." % ", ".join(names)) if k == "fight" else \
				("%s waits at the heart of the %s, with %s." % [str(g.title), str(d.name).to_lower(), ", ".join(names)])
			_opt("Fight", "red" if k == "boss" else "blue", _fight, "· %d in your band" % st.party.size())
			_opt("Turn back", "paper", _leave)
		"chest":
			prop = "chest"
			text_l.text = "An iron-bound chest sits under a drip of water. The lock looks old. So does the needle beside it."
			_opt("Pick the lock", "blue", func(): _resolve("open"), _chance("DEX", int(d.dc)))
			_opt("Leave it", "paper", _next)
		"trap":
			prop = "trap"
			text_l.text = "The floor ahead is too clean. Scratches on the walls at knee height. Somebody built a trap here."
			_opt("Find the trigger", "blue", func(): _resolve("disarm"), _chance("INT", int(d.dc)))
			_opt("Run for it", "paper", func(): _resolve("rush"), _chance("DEX", int(d.dc) - 2))
		"shrine":
			prop = "shrine"
			text_l.text = "A shrine to a god nobody remembers. Candle stubs, old coins, a cracked bowl of water."
			_opt("Kneel and pray", "blue", func(): _resolve("pray"), _chance("WIS", int(d.dc) - 1))
			_opt("Walk past", "paper", _next)
		"rest":
			prop = "fire"
			text_l.text = "A dry corner out of the wind, with the ashes of somebody else's fire."
			_opt("Rest a while", "blue", func(): _resolve("rest"), "+4 HP, band +3")
			_opt("Push on", "paper", _next)


func _boss_foe(g: Dictionary) -> String:
	var best := str(g.foes[0])
	for f in g.foes:
		if int(Data.enemies().foes[f].hp) > int(Data.enemies().foes[best].hp):
			best = str(f)
	return best


func _chance(attr: String, dc: int) -> String:
	return "· %s DC %d · %d%%" % [attr, dc, GameState.chance(st.champ.attr(attr), dc)]


func _resolve(choice: String) -> void:
	_clear_opts()
	var r := st.dungeon_resolve(choice)
	if prop == "chest" and r.ok:
		prop_open = true
		Audio.play("coin")
	elif not r.ok:
		Audio.play("fail", -4.0)
		hero.hit()
	else:
		Audio.play("success", -6.0)
	var line := str(r.text)
	if r.has("roll"):
		var ck: Dictionary = r.roll
		line = "[%s roll %d + %d = %d vs DC %d]  %s" % [ck.attr, int(ck.roll), int(ck.bonus), int(ck.total), int(ck.dc), line]
	text_l.text = line
	_float(r.changes)
	Game.touch()
	_opt("Onward", "blue", _next)
	_opt("Turn back", "paper", _leave)


func _float(changes: Array) -> void:
	var p := hero.global_position + Vector2(130, 20)
	var dl := 0.0
	for ch in changes:
		if ch.kind in ["food", "wood", "stone", "gold", "iron", "hp", "xp"]:
			Fx.float_text(self, p, "%+d" % int(ch.amount), PixelUI.GOOD if int(ch.amount) >= 0 else PixelUI.BAD, ch.kind, dl)
			dl += 0.18
		elif ch.kind == "item":
			Fx.float_text(self, p, "+ " + str(ch.get("label", "item")), PixelUI.VIOLET, "", dl, 26)
			dl += 0.2


func _fight() -> void:
	Main.go("battle", {"group": group, "source": "dungeon:" + did, "wipe_from": Vector2(0.62, 0.5)})


func _after_fight(result: String, changes: Array) -> void:
	_refresh_path()
	if result == "win":
		var cleared := st.dungeon_advance()
		if cleared:
			_victory()
			return
		_show_room()
		await get_tree().process_frame
		_float(changes)
	else:
		# retreated: the delve is over for today
		title_l.text = "Driven out"
		text_l.text = "You fall back to daylight, bruised. The %s will still be here tomorrow." % str(d.name).to_lower()
		_clear_opts()
		_opt("Back to the map", "blue", _leave)


func _next() -> void:
	if st.dungeon_advance():
		_victory()
		return
	_show_room()


func _victory() -> void:
	foe.visible = false
	for a in foes:
		a.visible = false
	prop = "chest"
	prop_open = true
	_refresh_path()
	Audio.play("levelup", -4.0)
	title_l.text = "%s cleared!" % str(d.name)
	text_l.text = "The guardian is down. What it hoarded goes into your cargo. Bring it home."
	_float(st.dungeon_run.get("reward_changes", []))
	Game.touch()
	_clear_opts()
	_opt("Back to the map", "blue", _leave)


func _leave() -> void:
	st.leave_dungeon()
	Game.touch()
	Main.go("world", {"from": "dungeon"})


# ------------------------------------------------------------------ drawing

func _draw_scene() -> void:
	var vs := get_viewport_rect().size
	if bg:
		Art.draw_cover(scene, bg, Rect2(Vector2.ZERO, vs), time, 0.03)
	scene.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.1, 0.05, 0.18, 0.28))
	# torchlight pool under the party
	for i in 6:
		var r := 360.0 - i * 50.0
		_ellipse(Vector2(vs.x * 0.5, 780), r * 1.9, r * 0.32, Color(1.0, 0.85, 0.55, 0.035))
	var base := Vector2(1340, 790)
	match prop:
		"chest":
			_tex("res://assets/props/chest_open.png" if prop_open else "res://assets/props/chest.png", base, 3.0)
		"trap":
			_tex("res://assets/props/skull.png", base + Vector2(-80, 0), 3.0)
			_tex("res://assets/props/skull.png", base + Vector2(90, -6), 2.4)
			_tex("res://assets/props/box.png", base + Vector2(0, 0), 3.0)
		"shrine":
			_tex("res://assets/tinyswords/city/b_purple_monastery.png", base + Vector2(0, 10), 1.3)
			_tex("res://assets/props/red_bottle.png", base + Vector2(-150, 0), 3.0)
		"fire":
			_anim("res://assets/tinyswords/city/fire.png", base, 2.0)
			_tex("res://assets/props/barrel.png", base + Vector2(-150, 0), 2.5)


func _tex(path: String, feet: Vector2, sc: float) -> void:
	var t := _tex_of(path)
	if t == null:
		return
	var sz := t.get_size() * sc
	_ellipse(feet + Vector2(0, 2), sz.x * 0.4, 12, Color(0.12, 0.05, 0.2, 0.4))
	scene.draw_texture_rect(t, Rect2((feet - Vector2(sz.x / 2.0, sz.y)).round(), sz), false)


func _anim(path: String, feet: Vector2, sc: float) -> void:
	var t := _tex_of(path)
	if t == null:
		return
	var fw := t.get_height()
	var n := maxi(1, t.get_width() / fw)
	var fr := int(time * 10.0) % n
	var sz := Vector2(fw, fw) * sc
	scene.draw_texture_rect_region(t, Rect2((feet - Vector2(sz.x / 2.0, sz.y * 0.8)).round(), sz), Rect2(fr * fw, 0, fw, fw))


func _ellipse(c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 24:
		var a := TAU * i / 24.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	scene.draw_colored_polygon(pts, col)


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and (e as InputEventKey).keycode == KEY_ESCAPE:
		Menus.pause(Main.instance.menu_layer)
