class_name Art
extends RefCounted
## Full-screen backdrops (assets/bg, imported by tools/packs_prepare.py from
## ansimuz's Mountain Dusk / Parallax Forest and CraftPix's Crystal Caves).
## Screens ask for a scene name ("bg_<scene>"); this table picks the picture.

const BG := {
	# battle scenes (enemies.json "scene")
	"bg_dusk_hills": "dusk_b", "bg_night_forest": "forest1", "bg_road_dusk": "dusk_a", "bg_camp_night": "forest2",
	"bg_cave": "cave1", "bg_cave2": "cave2", "bg_cave3": "cave3", "bg_cave4": "cave4", "bg_canyon": "canyon",
	# dialogue places (dialogues.json "bg")
	"bg_crossroads": "dusk_b", "bg_ruins": "canyon", "bg_hall": "dusk_a", "bg_harbor": "dusk_b",
	"bg_forge": "canyon", "bg_grove": "forest1", "bg_title": "dusk_a",
}

static var _cache: Dictionary = {}


static func tex(name: String) -> Texture2D:
	if _cache.has(name):
		return _cache[name]
	var t: Texture2D = null
	var file := str(BG.get(name, name.trim_prefix("bg_")))
	var p := "res://assets/bg/%s.png" % file
	if ResourceLoader.exists(p):
		t = load(p)
	_cache[name] = t
	return t


## Draws a texture covering `rect` (like CSS background-size: cover), pixel-sharp,
## with a very slow drift so still scenes never feel frozen.
static func draw_cover(ci: CanvasItem, t: Texture2D, rect: Rect2, time: float, drift: float = 0.02) -> void:
	var ts := t.get_size()
	var k := maxf(rect.size.x / ts.x, rect.size.y / ts.y) * (1.0 + drift)
	var sz := (ts * k).round()
	var off := (rect.size - sz) / 2.0
	off += Vector2(sin(time * 0.05), cos(time * 0.037)) * (sz - rect.size).abs() * 0.45
	ci.draw_texture_rect(t, Rect2((rect.position + off).round(), sz), false)
