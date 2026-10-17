extends Node
## Player settings, kept in user://settings.cfg and applied at start.
##   master / music / sfx  volume 0..1 (separate audio buses)
##   fullscreen            window mode
##   shake                 screen shake in battles
##   battle_speed          1, 1.5 or 2 (animation speed in battles)
##   autosave              save to the "auto" slot at the end of every day
##   tips                  show the first-day hints

const PATH := "user://settings.cfg"

var master := 0.9
var music := 0.7
var sfx := 0.9
var fullscreen := false
var shake := true
var battle_speed := 1.0
var autosave := true
var tips := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for b in ["Music", "SFX"]:
		if AudioServer.get_bus_index(b) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, b)
			AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	load_cfg()
	apply.call_deferred()


func load_cfg() -> void:
	var c := ConfigFile.new()
	if c.load(PATH) != OK:
		return
	for k in ["master", "music", "sfx", "fullscreen", "shake", "battle_speed", "autosave", "tips"]:
		set(k, c.get_value("settings", k, get(k)))


func save_cfg() -> void:
	var c := ConfigFile.new()
	for k in ["master", "music", "sfx", "fullscreen", "shake", "battle_speed", "autosave", "tips"]:
		c.set_value("settings", k, get(k))
	c.save(PATH)


func apply() -> void:
	_vol("Master", master)
	_vol("Music", music)
	_vol("SFX", sfx)
	for p in Audio.pool:
		p.bus = "SFX"
	for m in [Audio.music_a, Audio.music_b]:
		m.bus = "Music"
	if not Engine.is_editor_hint() and DisplayServer.get_name() != "headless":
		var want := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_MAXIMIZED
		if DisplayServer.window_get_mode() != want and (fullscreen or DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN):
			DisplayServer.window_set_mode(want)


func _vol(bus: String, v: float) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i >= 0:
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.0001)))
		AudioServer.set_bus_mute(i, v <= 0.001)
