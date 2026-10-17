extends Node
## Sound effects and music. Every sound is a generated .wav in assets/audio
## (see tools/gen_audio.py). M toggles music, N toggles sound effects.

const SFX := ["click", "hover", "paper", "scratch", "dice", "dice_land", "coin", "build", "step",
	"hit", "whoosh", "block", "success", "fail", "levelup", "stamp", "bell_day", "bell_week", "whisper"]

var streams: Dictionary = {}
var pool: Array[AudioStreamPlayer] = []
var music_a := AudioStreamPlayer.new()
var music_b := AudioStreamPlayer.new()
var current_music := ""
var music_on := true
var sfx_on := true
var music_db := -13.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for s in SFX:
		var st: AudioStream = load("res://assets/audio/%s.wav" % s)
		if st:
			streams[s] = st
	for n in 10:
		var p := AudioStreamPlayer.new()
		add_child(p)
		pool.append(p)
	for m in [music_a, music_b]:
		add_child(m)
		m.volume_db = -60.0


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		if e.keycode == KEY_M:
			music_on = not music_on
			var target := music_db if music_on else -60.0
			for m in [music_a, music_b]:
				if m.playing:
					create_tween().tween_property(m, "volume_db", target, 0.6)
		elif e.keycode == KEY_N:
			sfx_on = not sfx_on


func play(name: String, db: float = 0.0, pitch_jitter: float = 0.06) -> void:
	if not sfx_on or not streams.has(name):
		return
	for p in pool:
		if not p.playing:
			p.stream = streams[name]
			p.volume_db = db
			p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
			p.play()
			return


func music(name: String, fade: float = 1.5) -> void:
	if name == current_music:
		return
	current_music = name
	var st: AudioStreamWAV = load("res://assets/audio/%s.wav" % name) if name != "" else null
	var old := music_a if music_a.playing else music_b
	var nxt := music_b if old == music_a else music_a
	if old.playing:
		var tw := create_tween()
		tw.tween_property(old, "volume_db", -60.0, fade)
		tw.tween_callback(old.stop)
	if st == null:
		return
	# music .wav files are imported with loop_mode = forward (see their .import files)
	nxt.stream = st
	nxt.volume_db = -50.0
	nxt.play()
	if music_on:
		create_tween().tween_property(nxt, "volume_db", music_db, fade)
