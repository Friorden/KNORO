class_name Hex
extends RefCounted
## Hex math on axial coordinates (q, r), pointy-top hexes.
##
## Picture it like this: a hex grid is a slanted grid. Moving "east" changes
## q by +1. Moving "south-east" changes r by +1. A third, implied axis
## s = -q - r makes every neighbour exactly one step away on two axes, which
## is why distance becomes a simple max() of the three differences.
##
## Screen projection is isometric: we compute the flat (top-down) hex
## position, then squash y by SQUASH so the board looks tilted away from you.

const SQRT3 := 1.7320508075688772
const SQUASH := 0.62

const DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]


static func neighbors(h: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in DIRS:
		out.append(h + d)
	return out


static func distance(a: Vector2i, b: Vector2i) -> int:
	var dq := a.x - b.x
	var dr := a.y - b.y
	return int((absi(dq) + absi(dr) + absi(dq + dr)) / 2)


static func ring(center: Vector2i, radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for q in range(-radius, radius + 1):
		for r in range(maxi(-radius, -q - radius), mini(radius, -q + radius) + 1):
			out.append(center + Vector2i(q, r))
	return out


## Offset (col,row) "odd-r" layout -> axial. Lets us build a rectangular map.
static func from_offset(col: int, row: int) -> Vector2i:
	return Vector2i(col - (row - (row & 1)) / 2, row)


static func to_offset(h: Vector2i) -> Vector2i:
	return Vector2i(h.x + (h.y - (h.y & 1)) / 2, h.y)


## Flat-world centre of a hex (before iso squash), for hex radius `size`.
static func to_flat(h: Vector2i, size: float) -> Vector2:
	return Vector2(size * SQRT3 * (h.x + h.y * 0.5), size * 1.5 * h.y)


## Screen centre with isometric squash.
static func to_screen(h: Vector2i, size: float) -> Vector2:
	var f := to_flat(h, size)
	return Vector2(f.x, f.y * SQUASH)


## Screen point -> hex (inverse of to_screen), using cube rounding.
static func from_screen(p: Vector2, size: float) -> Vector2i:
	var fx := p.x
	var fy := p.y / SQUASH
	var q := (SQRT3 / 3.0 * fx - 1.0 / 3.0 * fy) / size
	var r := (2.0 / 3.0 * fy) / size
	return cube_round(q, r)


static func cube_round(qf: float, rf: float) -> Vector2i:
	var sf := -qf - rf
	var q := roundf(qf)
	var r := roundf(rf)
	var s := roundf(sf)
	var dq := absf(q - qf)
	var dr := absf(r - rf)
	var ds := absf(s - sf)
	if dq > dr and dq > ds:
		q = -r - s
	elif dr > ds:
		r = -q - s
	return Vector2i(int(q), int(r))


## Corner k (0..5) of a pointy-top hex in screen space. k=0 is the top point,
## then clockwise: 1 upper-right, 2 lower-right, 3 bottom, 4 lower-left, 5 upper-left.
static func corner(center: Vector2, size: float, k: int) -> Vector2:
	var a := deg_to_rad(60.0 * k - 90.0)
	return center + Vector2(size * cos(a), size * sin(a) * SQUASH)


static func corners(center: Vector2, size: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in 6:
		pts.append(corner(center, size, k))
	return pts


## The direction index whose shared edge is between corners k and k+1.
## DIRS order (E, NE, NW, W, SW, SE) mapped to the edge between corners.
static func edge_corners_for_dir(dir_index: int) -> Vector2i:
	# E -> edge 1-2, NE -> 0-1, NW -> 5-0, W -> 4-5, SW -> 3-4, SE -> 2-3
	match dir_index:
		0: return Vector2i(1, 2)
		1: return Vector2i(0, 1)
		2: return Vector2i(5, 0)
		3: return Vector2i(4, 5)
		4: return Vector2i(3, 4)
		_: return Vector2i(2, 3)


## Cheap deterministic hash for per-hex jitter and variation.
static func hash01(h: Vector2i, salt: int = 0) -> float:
	var n := int(h.x * 73856093) ^ int(h.y * 19349663) ^ int(salt * 83492791)
	n = (n ^ (n >> 13)) * 1274126177
	n = n ^ (n >> 16)
	return float(n & 0xFFFF) / 65535.0
