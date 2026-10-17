class_name ItemIcon
extends Control
## An item slot: the item's icon from the icon packs (assets/icons/<item id>.png,
## see tools/packs_prepare.py and assets/LICENSES.md) on a pixel slot frame.
## Rarity shows as the frame colour: common = parchment, uncommon = sage, rare = violet.

var key := ""
var item_id := ""
var rarity := "common"
var count := 0
var empty_label := ""

const RARITY := {"common": Color("#efe1ab"), "uncommon": Color("#cfe3b4"), "rare": Color("#d9c3f2")}
static var _cache: Dictionary = {}


static func make(p_item_id: String, px: float = 56.0, n: int = 0) -> ItemIcon:
	var ic := ItemIcon.new()
	var it := Champion.item(p_item_id)
	ic.item_id = p_item_id
	ic.key = str(it.get("icon", ""))
	ic.rarity = str(it.get("rarity", "common"))
	ic.count = n
	ic.custom_minimum_size = Vector2(px, px)
	ic.mouse_filter = Control.MOUSE_FILTER_PASS
	ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return ic


static func icon_tex(id: String) -> Texture2D:
	if not _cache.has(id):
		var p := "res://assets/icons/%s.png" % id
		_cache[id] = load(p) if ResourceLoader.exists(p) else null
	return _cache[id]


func _draw() -> void:
	var s := size
	var ink := PixelUI.INK
	var r := Rect2(Vector2(2, 2), s - Vector2(4, 4))
	var filled := key != "" or item_id != ""
	draw_rect(r, RARITY.get(rarity, RARITY.common) if filled else Color("#e9dcc0"))
	draw_rect(Rect2(r.position, Vector2(r.size.x, 4)), Color(1, 1, 1, 0.35) if filled else Color(0, 0, 0, 0))
	draw_rect(r, ink if filled else Color(ink, 0.35), false, 3.0)
	if not filled:
		if empty_label != "":
			draw_string(Style.body_bold, Vector2(6, s.y / 2 + 5), empty_label, HORIZONTAL_ALIGNMENT_CENTER, s.x - 12, 12, Color(ink, 0.45))
		return
	var t := ItemIcon.icon_tex(item_id)
	if t:
		var inner := r.grow(-6)
		var k := floorf(minf(inner.size.x / t.get_width(), inner.size.y / t.get_height()) * 2.0) / 2.0
		k = maxf(k, 0.5)
		var sz := (t.get_size() * k).round()
		draw_texture_rect(t, Rect2((r.get_center() - sz / 2.0).round(), sz), false)
	else:
		draw_string(Style.body_heavy, Vector2(0, s.y / 2 + 8), "?", HORIZONTAL_ALIGNMENT_CENTER, s.x, 24, ink)
	if count > 1:
		var tx := "×%d" % count
		var f := Style.body_heavy
		for o in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
			draw_string(f, Vector2(s.x - 30, s.y - 6) + o * 2, tx, HORIZONTAL_ALIGNMENT_RIGHT, 26, 14, ink)
		draw_string(f, Vector2(s.x - 30, s.y - 6), tx, HORIZONTAL_ALIGNMENT_RIGHT, 26, 14, Color("#fbf3df"))
