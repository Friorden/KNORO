class_name Main
extends Control
## Root of the game. Owns the screens and the ink-blot transition between them.
## World and City stay alive in the background so the map keeps its camera and
## animations; the other screens are built fresh each time they open.

const SCREENS := {
	"title": "res://ui/title_screen.gd",
	"story": "res://ui/story_screen.gd",
	"dungeon": "res://ui/dungeon_screen.gd",
	"select": "res://ui/select_screen.gd",
	"create": "res://ui/create_screen.gd",
	"world": "res://ui/world_screen.gd",
	"city": "res://ui/city_screen.gd",
	"dialogue": "res://ui/dialogue_screen.gd",
	"battle": "res://ui/battle_screen.gd",
	"week": "res://ui/week_screen.gd",
	"heir": "res://ui/heir_screen.gd",
	"end": "res://ui/end_screen.gd",
}
const PERSISTENT := ["world", "city"]

static var instance: Control

var holder := Control.new()
var wipe_layer := CanvasLayer.new()
var wipe := ColorRect.new()
var toast_layer := CanvasLayer.new()
var menu_layer := CanvasLayer.new()     # pause / save / settings / quest log modals
var screens: Dictionary = {}
var current := ""
var busy := false
var _queue: Array = []


func _ready() -> void:
	instance = self
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(holder)
	wipe_layer.layer = 50
	add_child(wipe_layer)
	wipe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wipe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = load("res://render/wipe.gdshader")
	wipe.material = m
	wipe_layer.add_child(wipe)
	toast_layer.layer = 60
	add_child(toast_layer)
	menu_layer.layer = 45
	add_child(menu_layer)
	_set_wipe(0.0)
	var start := "title"
	var shot := ""
	var delay := 2.0
	var script_cmds: Array = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--screen="):
			start = a.substr(9)
		elif a.begins_with("--shot="):
			shot = a.substr(7)
		elif a.begins_with("--delay="):
			delay = float(a.substr(8))
		elif a.begins_with("--seed="):
			Game.seed = int(a.substr(7))
		elif a.begins_with("--do="):
			script_cmds = a.substr(5).split(";")
	var pre := start.split(":")[0]
	if pre not in ["select", "create", "title", "story"] and Game.state == null:
		Game.start_campaign("red", Champion.new())
	var data := {}
	if start.begins_with("dialogue"):
		data = {"id": start.substr(9) if start.length() > 9 else "tobbin"}
		start = "dialogue"
	elif start.begins_with("battle"):
		data = {"group": start.substr(7) if start.length() > 7 else "boars"}
		start = "battle"
		_debug_party()
	elif start.begins_with("dungeon"):
		data = {"id": start.substr(8) if start.length() > 8 else "crystal_cave"}
		start = "dungeon"
		_debug_party()
	elif start == "week":
		Game.state.day = 7
		data = {"report": Game.state.end_day().get("week_report", {})}
	goto(start, data, false)
	if shot != "":
		_debug_run(script_cmds, shot, delay)


## Debug: a full war band for testing the battle screen directly.
func _debug_party() -> void:
	var st: GameState = Game.state
	st.res = {"food": 200, "wood": 200, "stone": 200, "gold": 200, "iron": 40}
	st.pop = 20
	st.city[Vector2i(-1, 0)] = {"type": "barracks", "day": 0}
	st.champ.salves = 2
	for u in ["shieldbearer", "spearman", "archer", "herbalist"]:
		st.recruit(u)


func _debug_town() -> void:
	var st: GameState = Game.state
	st.res = {"food": 300, "wood": 300, "stone": 300, "gold": 400, "iron": 80}
	st.pop = 40
	st.age = 2
	st.expand_city()
	st.flags["outpost_iron"] = 1
	st.flags["outpost_stone"] = 1
	var want := ["market", "farm", "mill", "bakery", "granary", "lumber", "hunter", "sawmill", "mine", "ironmine", "foundry", "fishery", "harbor",
		"workshop", "tannery", "apothecary", "winery", "tavern", "watchtower", "temple", "library", "blacksmith", "walls", "barracks", "house", "house", "farm", "quarry", "drillyard"]
	for t in want:
		for slot in st.city_terrain.keys():
			if st.can_build(t, slot).ok:
				st.city[slot] = {"type": t, "day": 0, "level": 1}
				var modes: Array = Data.buildings()[t].get("modes", [])
				if not modes.is_empty():
					st.city[slot].mode = str(modes[0].id)
				break
	var n := 0
	for slot in st.city.keys():
		var bd: Dictionary = Data.buildings()[st.city[slot].type]
		if bd.has("max_level") and n < 8:
			st.city[slot].level = 2 + n % 2
			if st.city[slot].level == 3 and bd.has("branches"):
				st.city[slot].branch = str(bd.branches[n % 2].id)
			n += 1
	for i in ["compass", "meteor_shard", "honey", "old_map"]:
		st.give_item(i)


## Debug/screenshot helper: --do="wait:1;key:space;click:800:450" then --shot=path.png
func _debug_run(cmds: Array, shot: String, delay: float) -> void:
	await get_tree().create_timer(0.5).timeout
	for c in cmds:
		var parts: PackedStringArray = str(c).split(":")
		match parts[0]:
			"wait":
				await get_tree().create_timer(float(parts[1])).timeout
			"key":
				var ev := InputEventKey.new()
				ev.keycode = OS.find_keycode_from_string(parts[1])
				ev.pressed = true
				Input.parse_input_event(ev)
				await get_tree().process_frame
				var up := ev.duplicate()
				up.pressed = false
				Input.parse_input_event(up)
			"click", "move":
				var pos := Vector2(float(parts[1]), float(parts[2]))
				var mm := InputEventMouseMotion.new()
				mm.position = pos
				mm.global_position = pos
				Input.parse_input_event(mm)
				await get_tree().process_frame
				if parts[0] == "click":
					for pressed in [true, false]:
						var mb := InputEventMouseButton.new()
						mb.button_index = MOUSE_BUTTON_LEFT
						mb.position = pos
						mb.global_position = pos
						mb.pressed = pressed
						Input.parse_input_event(mb)
						await get_tree().process_frame
			"go":
				goto(parts[1], {}, false)
			"quests":
				QuestLog.open(menu_layer)
			"reveal":
				for h in Game.state.world.tiles.keys():
					Game.state.explored[h] = true
				Game.state.check_discoveries()
				if screens.has("world"):
					screens["world"].map.refresh_terrain()
			"look":
				var w = screens["world"]
				w.cam_target = w.map.center_of(Game.state.world.places[parts[1]])
				w.cam = w.cam_target
			"pause":
				Menus.pause(menu_layer)
			"help":
				Menus.help(menu_layer, int(parts[1]) if parts.size() > 1 else 0)
			"settings":
				Menus.settings(menu_layer)
			"saves":
				Menus.saves(menu_layer, parts[1])
			"rich":
				_debug_party()
				Game.touch()
			"town":
				_debug_town()
				Game.touch()
			"call":
				var scr: Control = screens[current]
				if parts.size() > 2:
					scr.call(parts[1], parts[2])
				else:
					scr.call(parts[1])
			"wheel":
				var wb := InputEventMouseButton.new()
				wb.button_index = MOUSE_BUTTON_WHEEL_UP if parts[1] == "up" else MOUSE_BUTTON_WHEEL_DOWN
				wb.position = get_viewport_rect().size / 2
				wb.pressed = true
				Input.parse_input_event(wb)
			"shot":
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(parts[1])
	await get_tree().create_timer(delay).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shot)
	get_tree().quit()


func _unhandled_key_input(e: InputEvent) -> void:
	var k := e as InputEventKey
	if k and k.pressed and not k.echo and k.keycode == KEY_F11:
		Settings.fullscreen = not Settings.fullscreen
		Settings.apply()
		Settings.save_cfg()


## True while a menu (pause, settings, quest log ...) is open over the game.
static func menu_open() -> bool:
	return instance != null and instance.menu_layer.get_child_count() > 0


static func go(screen: String, data: Dictionary = {}, animate: bool = true) -> void:
	if instance:
		instance.goto(screen, data, animate)


func _set_wipe(p: float) -> void:
	(wipe.material as ShaderMaterial).set_shader_parameter("progress", p)
	var vs := get_viewport_rect().size
	(wipe.material as ShaderMaterial).set_shader_parameter("aspect", Vector2(vs.x / vs.y, 1.0))
	wipe.visible = p > 0.001


func goto(screen: String, data: Dictionary = {}, animate: bool = true) -> void:
	if busy:
		_queue.append([screen, data, animate])
		return
	busy = true
	if animate:
		Audio.play("whisper", -6.0, 0.1)
		var center: Vector2 = data.get("wipe_from", Vector2(0.5, 0.5))
		(wipe.material as ShaderMaterial).set_shader_parameter("center", center)
		var tw := create_tween()
		tw.tween_method(_set_wipe, 0.0, 1.0, 0.42).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		await tw.finished
	_swap(screen, data)
	if animate:
		await get_tree().process_frame
		var tw2 := create_tween()
		tw2.tween_method(_set_wipe, 1.0, 0.0, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		await tw2.finished
	busy = false
	if not _queue.is_empty():
		var q: Array = _queue.pop_front()
		goto(q[0], q[1], q[2])


func _swap(screen: String, data: Dictionary) -> void:
	for m in menu_layer.get_children():
		m.queue_free()
	if current != "" and screens.has(current):
		var old: Control = screens[current]
		if old.has_method("leave"):
			old.leave()
		if current in PERSISTENT:
			old.visible = false
			old.process_mode = Node.PROCESS_MODE_DISABLED
		else:
			old.queue_free()
			screens.erase(current)
	if not screens.has(screen) or not is_instance_valid(screens[screen]):
		var s: Control = load(SCREENS[screen]).new()
		s.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		holder.add_child(s)
		screens[screen] = s
	var scr: Control = screens[screen]
	scr.visible = true
	scr.process_mode = Node.PROCESS_MODE_INHERIT
	current = screen
	if scr.has_method("enter"):
		scr.enter(data)


## Drop the persistent screens (new campaign / heir).
func reset_world() -> void:
	for k in PERSISTENT:
		if screens.has(k) and is_instance_valid(screens[k]):
			screens[k].queue_free()
		screens.erase(k)


static func toast(text: String, color: Color = Color("#2F2A35")) -> void:
	if instance == null:
		return
	var l := Style.hand(text, 30, color)
	var p := PanelContainer.new()
	var b := Style.box(Style.NOTE, randi() % 50, 4.0, Style.INK, 2.0, 12.0)
	p.add_theme_stylebox_override("panel", b)
	p.add_child(l)
	instance.toast_layer.add_child(p)
	await instance.get_tree().process_frame
	var vs := instance.get_viewport_rect().size
	p.position = Vector2((vs.x - p.size.x) / 2.0, 110)
	p.rotation_degrees = randf_range(-2, 2)
	p.pivot_offset = p.size / 2.0
	p.scale = Vector2(0.6, 0.6)
	p.modulate.a = 0.0
	var tw := p.create_tween()
	tw.tween_property(p, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(p, "modulate:a", 1.0, 0.2)
	tw.tween_interval(1.8)
	tw.tween_property(p, "modulate:a", 0.0, 0.4)
	tw.parallel().tween_property(p, "position:y", p.position.y - 20, 0.4)
	tw.tween_callback(p.queue_free)
