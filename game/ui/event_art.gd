class_name EventArt
extends Control
## Illustrations for event cards, built only from pack art: a backdrop
## (ansimuz / CraftPix, see render/art.gd) with animated sprites standing on it
## (Tiny Swords units and props, Pinero monsters, Pixel Frog characters).
##
## SCENES: art key -> [backdrop, [[sprite, x (0..1), scale, flip], ...]]
## Sprite names: "k_" is replaced by the player's kingdom colour;
##   "units/..."  Tiny Swords units (assets/tinyswords/units) or pack units (assets/units)
##   "city/..."   Tiny Swords buildings and deco, "props/..." Pixel Frog props,
##   anything else is looked up in assets/tinyswords/.

const SCENES := {
	"trail": ["dusk_a", [["tree2", 0.12, 1.0, false], ["units/k_pawn_run", 0.5, 1.6, false], ["bush1", 0.82, 1.4, false]]],
	"fog": ["forest2", [["tree3", 0.15, 1.1, false], ["units/pinero_bat_idle_map", 0.55, 1.2, false], ["tree4", 0.88, 1.0, false]]],
	"boars": ["forest1", [["units/kp_pig_idle", 0.35, 1.3, true], ["units/kp_kingpig_idle", 0.6, 1.4, true], ["bush2", 0.86, 1.4, false]]],
	"wolves": ["forest2", [["units/pinero_wolf_idle_map", 0.32, 1.3, false], ["units/pinero_alpha_idle_map", 0.62, 1.4, false]]],
	"bandits": ["dusk_b", [["units/goblin_purple_idle", 0.25, 1.4, false], ["units/black_pawn_knife_idle", 0.5, 1.5, true], ["units/black_archer_idle", 0.75, 1.5, true]]],
	"berries": ["forest1", [["bush1", 0.25, 1.8, false], ["units/k_pawn_idle", 0.52, 1.6, false], ["bush3", 0.78, 1.8, false]]],
	"chest": ["canyon", [["units/k_pawn_idle", 0.3, 1.6, false], ["props/chest", 0.6, 2.2, false]]],
	"traveler": ["dusk_a", [["units/k_pawn_idle", 0.3, 1.6, false], ["units/blue_pawn_idle", 0.65, 1.6, true]]],
	"pilgrim": ["dusk_a", [["units/k_pawn_idle", 0.3, 1.6, false], ["units/purple_monk_idle", 0.65, 1.5, true]]],
	"spring": ["forest1", [["city/waterrock2", 0.35, 1.6, false], ["units/k_pawn_idle", 0.65, 1.6, true]]],
	"rain": ["forest2", [["Clouds_03", 0.5, 0.5, false], ["units/k_pawn_run", 0.4, 1.6, false], ["tree1", 0.82, 1.0, false]]],
	"rocks": ["canyon", [["rock2", 0.22, 2.0, false], ["units/k_pawn_interact_pickaxe", 0.5, 1.6, false], ["rock4", 0.8, 2.0, false]]],
	"woodpile": ["forest1", [["city/stump2", 0.25, 1.6, false], ["units/k_pawn_interact_axe", 0.5, 1.6, false], ["city/res_wood", 0.78, 1.6, false]]],
	"peddler": ["dusk_b", [["props/barrel", 0.22, 2.2, false], ["units/yellow_pawn_idle_gold", 0.5, 1.6, true], ["props/box", 0.75, 2.2, false]]],
	"shrine": ["dusk_a", [["city/b_purple_monastery", 0.45, 0.8, false], ["units/purple_monk_idle", 0.78, 1.4, true]]],
	"outpost": ["canyon", [["city/goldstone3", 0.25, 1.6, false], ["units/k_pawn_interact_pickaxe", 0.55, 1.6, false], ["city/goldstone5", 0.8, 1.6, false]]],
	"iron": ["canyon", [["city/ironstone1", 0.25, 1.6, false], ["units/k_pawn_interact_pickaxe", 0.55, 1.6, false], ["city/ironstone2", 0.8, 1.6, false]]],
	"cove": ["dusk_b", [["city/pier", 0.3, 0.9, false], ["props/barrel", 0.55, 2.0, false], ["units/th_crabby_idle", 0.78, 1.0, false]]],
	"tower": ["dusk_a", [["city/ruin_tower", 0.5, 0.75, false], ["units/k_pawn_idle", 0.75, 1.4, true]]],
	"crossroads": ["dusk_b", [["city/deco_17", 0.3, 1.6, false], ["units/yellow_pawn_idle_gold", 0.6, 1.6, true]]],
	"home": ["dusk_a", [["city/b_k_castle", 0.5, 0.6, false]]],
	"camp": ["forest2", [["city/fire", 0.45, 1.4, false], ["units/k_pawn_idle", 0.68, 1.5, true]]],
	"ruins": ["canyon", [["city/ruin_castle", 0.5, 0.65, false]]],
	"skeletons": ["crypt", [["units/pinero_skeleton_idle_map", 0.4, 1.3, false], ["units/pinero_zombie_idle_map", 0.65, 1.3, false]]],
	"goblins": ["forest2", [["units/goblin_red_idle", 0.35, 1.4, false], ["units/goblin_purple_idle", 0.62, 1.4, true]]],
	"pirates": ["dusk_b", [["units/pb_baldpirate_idle", 0.35, 1.2, false], ["units/pb_captain_idle", 0.62, 1.2, false]]],
	"crabs": ["dusk_b", [["units/th_crabby_idle", 0.35, 1.2, false], ["units/th_pinkstar_idle", 0.6, 1.2, false]]],
	"sheep": ["forest1", [["Sheep_Idle", 0.3, 1.5, false], ["Sheep_Idle", 0.55, 1.4, true], ["units/k_pawn_idle", 0.78, 1.5, true]]],
	"merchant": ["dusk_a", [["units/blue_pawn_run_gold", 0.35, 1.6, false], ["units/blue_pawn_run_meat", 0.6, 1.6, false]]],
	"knight": ["dusk_b", [["units/k_pawn_idle", 0.3, 1.5, false], ["units/yellow_warrior_idle", 0.65, 1.5, true]]],
	"archers": ["forest1", [["units/k_archer_idle", 0.35, 1.5, false], ["units/blue_archer_idle", 0.62, 1.5, true]]],
	"monk": ["dusk_a", [["units/purple_monk_idle", 0.5, 1.6, false]]],
	"cave": ["cave1", [["city/goldmine_idle", 0.5, 1.1, false]]],
	"bats": ["cave2", [["units/pinero_bat_idle_map", 0.35, 1.3, false], ["units/pinero_bat_idle_map", 0.6, 1.1, true]]],
	"slime": ["cave3", [["units/pinero_slime_idle_map", 0.5, 1.4, false]]],
	"kobolds": ["canyon", [["units/pinero_kobold_idle_map", 0.35, 1.3, false], ["units/pinero_gnoll_idle_map", 0.62, 1.3, false]]],
	"dead": ["dusk_b", [["units/dead", 0.45, 1.5, false], ["props/skull", 0.7, 2.0, false]]],
}

var art := "trail"
var time := 0.0
var tint := Color("#D46A55")
static var _tx: Dictionary = {}


static func make(p_art: String, w: float = 560, h: float = 210) -> EventArt:
	var a := EventArt.new()
	a.art = p_art
	a.custom_minimum_size = Vector2(w, h)
	a.clip_contents = true
	a.mouse_filter = Control.MOUSE_FILTER_IGNORE
	a.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return a


func _process(d: float) -> void:
	time += d
	queue_redraw()


static func _tex(name: String) -> Texture2D:
	if not _tx.has(name):
		_tx[name] = null
		for p in ["res://assets/tinyswords/%s.png" % name, "res://assets/%s.png" % name]:
			if ResourceLoader.exists(p):
				_tx[name] = load(p)
				break
	return _tx[name]


## Frame width of a sheet (same rules as the map and battle renderers).
static func _frame_w(name: String, t: Texture2D) -> int:
	if name.contains("pinero_"):
		return t.get_width() / 3
	if name.contains("kp_kingpig"):
		return 152
	if name.contains("kp_pig"):
		return 136
	if name.contains("th_") or name.contains("pb_"):
		return t.get_width() / maxi(1, int(Actor._frame_counts().get(name.get_file(), 1)))
	if name.contains("woodtower"):
		return 256
	for pre in ["tree", "bush", "Sheep", "units/", "city/fire", "city/waterrock"]:
		if name.begins_with(pre):
			return t.get_height()
	return t.get_width()


func _draw() -> void:
	var sc: Array = SCENES.get(art, SCENES.trail)
	var bg := Art.tex(str(sc[0]))
	if bg:
		Art.draw_cover(self, bg, Rect2(Vector2.ZERO, size), time, 0.05)
	var ground := size.y * 0.9
	draw_rect(Rect2(0, ground - 6, size.x, size.y - ground + 6), Color(0.12, 0.06, 0.2, 0.22))
	var k := Game.state.kingdom if Game.state else "red"
	var i := 0
	for s in sc[1]:
		var name := str(s[0]).replace("k_", k + "_")
		var t := _tex(name)
		i += 1
		if t == null:
			continue
		var fw := _frame_w(name, t)
		var n := maxi(1, t.get_width() / fw)
		var fr := int(time * 9.0 + i * 2) % n
		var src := Rect2(fw * fr, 0, fw, t.get_height())
		var sz := src.size * float(s[2])
		var x := size.x * float(s[1])
		if name.begins_with("Clouds"):
			draw_texture_rect(t, Rect2(Vector2(x - sz.x / 2.0 + sin(time * 0.3) * 20.0, 6).round(), sz), false, Color(1, 1, 1, 0.85))
			continue
		var ts_unit := name.begins_with("units/") and not (name.contains("pinero") or name.contains("kp_") or name.contains("th_") or name.contains("pb_"))
		var foot := (0.26 if ts_unit else 0.04) * sz.y
		if name in ["tree1", "tree2", "tree3", "tree4"] or name.begins_with("bush"):
			foot = 0.12 * sz.y
		_shadow(Vector2(x, ground), sz.x * (0.18 if ts_unit else 0.3))
		var top := roundf(ground - sz.y + foot)
		if bool(s[3]):
			draw_set_transform(Vector2(roundf(x), 0), 0.0, Vector2(-1, 1))
			draw_texture_rect_region(t, Rect2(Vector2(-sz.x / 2.0, top), sz), src)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			draw_texture_rect_region(t, Rect2(Vector2(roundf(x - sz.x / 2.0), top), sz), src)
	draw_rect(Rect2(Vector2.ZERO, size), PixelUI.INK, false, 3.0)


func _shadow(c: Vector2, rx: float) -> void:
	var pts := PackedVector2Array()
	for j in 16:
		var a := TAU * j / 16.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * rx * 0.22))
	draw_colored_polygon(pts, Color(0.12, 0.05, 0.2, 0.35))
