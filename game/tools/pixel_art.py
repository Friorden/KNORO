#!/usr/bin/env python3
"""KNORO pixel-art benchmark generator.

Builds every benchmark sprite pixel by pixel (no downscaled paintings, no
filters): one fixed palette, deliberate clusters, 1px selective ink outline,
light from the upper left. Output: game/assets/pixel/*.png (+ glyphs.json).

Logical unit: a hex tile is 64 px wide (pointy-top, 2:1 iso slopes), drawn on
a 64x96 canvas (32 px headroom for trees, hills, buildings). Row step 29 px,
column step 64 px. Everything is shown at an integer scale with nearest filtering.

Run:  python3 tools/pixel_art.py      (from the game/ folder)
"""
import json, math, os, random
from PIL import Image

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "pixel")
os.makedirs(OUT, exist_ok=True)

H = lambda s: tuple(int(s[i:i + 2], 16) for i in (1, 3, 5)) + (255,)
P = {k: H(v) for k, v in {
    "ink": "#1b1420", "ink2": "#2e2233",
    "g0": "#2c4a2e", "g1": "#3d6a36", "g2": "#55893e", "g3": "#76a84a", "g4": "#a2cc64", "g5": "#c9e48a",
    "d0": "#3a2618", "d1": "#56381f", "d2": "#7a5130", "d3": "#9e6d40",
    "h1": "#7f7037", "h2": "#a69248", "h3": "#cdb763", "h4": "#e6d68e",
    "r0": "#3b3741", "r1": "#5b5664", "r2": "#88828d", "r3": "#b9b3bb", "r4": "#e0dbdf",
    "w0": "#1a3150", "w1": "#25507a", "w2": "#3478a4", "w3": "#5aa6cc", "w4": "#a6dcef", "w5": "#e8f8fc",
    "t0": "#16291e", "t1": "#24452d", "t2": "#356a3c", "t3": "#4f8f48", "t4": "#7cb85a",
    "k1": "#5e3b22", "k2": "#8a5a32", "k3": "#b07d47",
    "c0": "#4e1520", "c1": "#86262c", "c2": "#bb3f37", "c3": "#e2684f", "c4": "#f39a74",
    "s0": "#57504d", "s1": "#857a72", "s2": "#b3a798", "s3": "#d9cdb8", "s4": "#f1e8d6",
    "f1": "#b97a55", "f2": "#e7b48b", "f3": "#f6d2ae",
    "y1": "#b3801f", "y2": "#e8b93c", "y3": "#ffe27a",
    "p0": "#2b1d33", "p1": "#46304f", "p2": "#664670", "p3": "#8a6992",
    "hair": "#2a1c24", "hair2": "#4a3240",
    "pa1": "#b8a27e", "pa2": "#d8c49c", "pa3": "#efe0bd", "pa4": "#fbf3df",
}.items()}
CLEAR = (0, 0, 0, 0)

# palette sheet for reference / review
def save(img, name):
    img.save(os.path.join(OUT, name))


def new(w, h):
    return Image.new("RGBA", (w, h), CLEAR)


def outline(img, col=None, skip_below=None):
    """1px ink outline around every opaque pixel (4-neighbourhood)."""
    col = col or P["ink"]
    w, h = img.size
    px = img.load()
    add = []
    for y in range(h):
        for x in range(w):
            if px[x, y][3] == 0:
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h and px[nx, ny][3] > 0 and px[nx, ny] != col:
                        add.append((x, y))
                        break
    for x, y in add:
        if skip_below is None or y < skip_below:
            px[x, y] = col
    return img


def noise(seed):
    r = random.Random(seed)
    g = [[r.random() for _ in range(12)] for _ in range(12)]
    def f(x, y, s=10.0):
        fx, fy = x / s, y / s
        x0, y0 = int(fx) % 11, int(fy) % 11
        tx, ty = fx - int(fx), fy - int(fy)
        tx, ty = tx * tx * (3 - 2 * tx), ty * ty * (3 - 2 * ty)
        a = g[y0][x0] * (1 - tx) + g[y0][x0 + 1] * tx
        b = g[y0 + 1][x0] * (1 - tx) + g[y0 + 1][x0 + 1] * tx
        return a * (1 - ty) + b * ty
    return f


# ----------------------------------------------------------------- hex geometry
TW, TH, Y0 = 64, 96, 36          # tile canvas, top vertex y


def dxo(x):
    return int(abs(x - 31.5) - 0.5)        # 0..31


def ytop(x):
    return Y0 + dxo(x) // 2


def ybot(x):
    return Y0 + 44 - dxo(x) // 2


SIDE = 8


def in_top(x, y):
    return ytop(x) <= y <= ybot(x)


def in_side(x, y):
    return ybot(x) < y <= ybot(x) + SIDE


# ----------------------------------------------------------------- terrain tiles
def base_tile(kind, seed, drop=0):
    img = new(TW, TH)
    px = img.load()
    n = noise(seed)
    r = random.Random(seed)
    top_cols = {
        "plains": ["g2", "g3", "g4"], "forest": ["g1", "g2", "g3"],
        "hills": ["h1", "h2", "h3"], "water": ["w1", "w2", "w3"],
    }[kind]
    for x in range(TW):
        for y in range(TH):
            if in_top(x, y - drop):
                v = n(x, y, 9.0) * 0.75 + n(x + 40, y * 2, 4.0) * 0.25
                # light from upper-left: brighter toward the top-left edge
                v += (31 - x) * 0.004 + (58 - y) * 0.006
                lo, hi = (0.30, 0.78) if kind == "plains" else (0.42, 0.68)
                c = top_cols[0] if v < lo else (top_cols[1] if v < hi else top_cols[2])
                px[x, y] = P[c]
            elif in_side(x, y - drop) or (drop and in_top(x, y) and y < ytop(x) + drop):
                yy = y - ybot(x) - drop
                if kind == "water":
                    px[x, y] = P["w0"] if x >= 32 else P["w1"]
                else:
                    c = "d2" if x < 32 else "d1"
                    if yy == 1:
                        c = "g1" if kind != "hills" else "h1"     # grass lip
                    elif yy in (4, 5) and (x + yy) % 5 == 0:
                        c = "d3" if x < 32 else "d2"              # strata pebbles
                    elif yy == SIDE:
                        c = "d0"
                    px[x, y] = P[c]
    # edge light: upper-left rim lighter, lower-right rim darker -> subtle grid
    for x in range(TW):
        t, b = ytop(x) + drop, ybot(x) + drop
        if x < 32:
            px[x, t] = P[{"plains": "g5", "forest": "g4", "hills": "h4", "water": "w4"}[kind]]
        else:
            px[x, t] = P[{"plains": "g4", "forest": "g3", "hills": "h3", "water": "w3"}[kind]]
        if x >= 32:
            px[x, b] = P[{"plains": "g2", "forest": "g1", "hills": "h1", "water": "w1"}[kind]]
        px[x, ybot(x) + SIDE + 1] = P["ink"] if kind != "water" else P["w0"]
    return img, px, r


def tuft(px, x, y, c1, c2):
    px[x, y] = P[c1]
    px[x - 1, y - 1] = P[c1]
    px[x + 1, y - 1] = P[c2]


def plains(seed):
    img, px, r = base_tile("plains", seed)
    for _ in range(9):
        x, y = r.randint(6, 57), r.randint(Y0 + 6, Y0 + 40)
        if in_top(x, y) and in_top(x - 1, y - 1) and in_top(x + 1, y - 1):
            tuft(px, x, y, "g1", "g2")
    for _ in range(3):
        x, y = r.randint(10, 53), r.randint(Y0 + 10, Y0 + 36)
        if in_top(x, y):
            px[x, y] = P[r.choice(["y3", "c4", "s4"])]
            px[x, y + 1] = P["g1"]
    return img


def pine(px, bx, by, s, sway=0):
    """Pine tree with three tiers, trunk at (bx, by)."""
    for y in range(by - 3, by + 1):
        px[bx, y] = P["k1"]
        px[bx + 1, y] = P["k1"]
    tiers = [(by - 3, 6 * s // 3 + 3), (by - 8, 5 * s // 3 + 2), (by - 13, 4 * s // 3 + 1)]
    for ti, (ty, half) in enumerate(tiers):
        for row in range(7):
            yy = ty - row
            w = max(0, half - row)
            off = sway if yy < by - 9 else 0
            for xx in range(bx - w + 1, bx + w + 1):
                lx = xx - bx
                c = "t2"
                if lx < -w // 2:
                    c = "t3"
                if lx > w // 2:
                    c = "t1"
                if row == 0:
                    c = "t1" if lx > 0 else "t2"
                px[xx + off, yy] = P[c]
    px[bx + (sway if True else 0), tiers[-1][0] - 7] = P["t3"]


def oak(px, bx, by, sway=0):
    for y in range(by - 5, by + 1):
        px[bx, y] = P["k1"]
        px[bx + 1, y] = P["k2"] if y < by - 2 else P["k1"]
    cx, cy, rr = bx, by - 11, 7
    for y in range(cy - rr, cy + rr):
        for x in range(cx - rr - 1, cx + rr + 2):
            d = ((x - cx) / 1.15) ** 2 + (y - cy) ** 2
            if d <= rr * rr:
                off = sway if y < cy - 2 else 0
                c = "t2"
                if (x - cx) + (y - cy) < -5:
                    c = "t4" if (x - cx) + (y - cy) < -8 else "t3"
                elif (x - cx) + (y - cy) > 4:
                    c = "t1"
                px[x + off, y] = P[c]


def forest(seed, frame=0):
    img, px, r = base_tile("forest", seed)
    sw = [0, 0, 1, 0][frame % 4]
    trees = [(15, Y0 + 24, "p"), (33, Y0 + 14, "o"), (47, Y0 + 27, "p"), (27, Y0 + 34, "p"), (42, Y0 + 40, "o")]
    tl = new(TW, TH)
    tp = tl.load()
    for i, (x, y, kind) in enumerate(trees):
        s = 3 + (i % 2)
        if kind == "p":
            pine(tp, x, y, s, sw if i % 2 == 0 else -sw)
        else:
            oak(tp, x, y, sw)
    outline(tl)
    # tree shadows on the ground (cast to the lower right)
    for (x, y, _) in trees:
        for dx in range(-2, 6):
            for dy in range(0, 2):
                if in_top(x + dx + 2, y + dy) and px[x + dx + 2, y + dy][3]:
                    px[x + dx + 2, y + dy] = P["g0"]
    img.alpha_composite(tl)
    return img


def hills(seed):
    img, px, r = base_tile("hills", seed)
    hl = new(TW, TH)
    hp = hl.load()
    base_rows = set()
    lay = [[(23, Y0 + 30, 18, 14), (44, Y0 + 38, 13, 10)], [(36, Y0 + 26, 16, 12), (20, Y0 + 38, 12, 9)], [(31, Y0 + 32, 20, 16)]][seed % 3]
    for (cx, by, w, hgt) in lay:
        for x in range(cx - w, cx + w + 1):
            t = (x - cx) / w
            top = by - int(hgt * max(0.0, 1 - t * t) ** 0.75)
            for y in range(top, by + 1):
                lx = x - cx
                c = "h3" if lx < -w // 3 else ("h2" if lx < w // 3 else "h1")
                if y - top < 2 and lx < w // 3:
                    c = "h4"
                if y >= by - 1:
                    c = "h1"
                if (x * 7 + y * 3) % 19 == 0 and top + 2 < y < by - 2:
                    c = "g2" if lx < 0 else "g1"
                hp[x, y] = P[c]
            base_rows.add((x, by + 1))
        for (rx, ry) in [(cx + 4, by - 5), (cx - 7, by - 3)]:
            hp[rx, ry] = P["r3"]; hp[rx + 1, ry] = P["r2"]; hp[rx + 1, ry + 1] = P["r1"]; hp[rx, ry + 1] = P["r2"]
    outline(hl)
    for (x, y) in base_rows:                 # mounds sit in the ground: no ink at the foot
        if hp[x, y] == P["ink"]:
            hp[x, y] = CLEAR
    img.alpha_composite(hl)
    return img


def water(seed, frame, inner=False):
    img, px, r = base_tile("water", seed, drop=3)
    if inner:
        for x in range(TW):
            for y in range(TH):
                if px[x, y][3] and not in_top(x, y - 3):
                    px[x, y] = CLEAR if y > ybot(x) + 3 else P["w2"]
            px[x, ytop(x) + 3] = P["w2"]
            px[x, ybot(x) + 3] = P["w2"]
    rr = random.Random(seed)
    waves = [(rr.randint(10, 50), rr.randint(Y0 + 10, Y0 + 40), rr.randint(3, 6)) for _ in range(7)]
    for i, (x, y, l) in enumerate(waves):
        ph = (frame + i) % 4
        xs = x + [0, 1, 2, 1][ph]
        for k in range(l):
            if in_top(xs + k, y - 3) and ph != 3:
                px[xs + k, y] = P["w4" if k < l - 1 else "w3"]
        if ph == 1 and in_top(xs + l, y - 4):
            px[xs + l, y - 1] = P["w5"]
    return img


# ----------------------------------------------------------------- buildings
def keep(frame=0):
    """Red capital: stone keep + hall, lit windows, palisade."""
    img = new(TW, TH)
    px = img.load()
    def rect(x0, y0, x1, y1, c):
        for x in range(x0, x1 + 1):
            for y in range(y0, y1 + 1):
                px[x, y] = P[c]
    # hall (right, behind)
    rect(34, 46, 53, 62, "s3"); rect(46, 46, 53, 62, "s2")
    for i in range(12):                                   # gable roof
        rect(32 + i, 46 - i // 2 - 1, 55 - i, 46 - i // 2 - 1, "c2" if i < 7 else "c3")
    for x in range(32, 56):
        px[x, 46] = P["c1"]
    rect(38, 52, 40, 55, "y2"); rect(49, 52, 50, 55, "y1")
    rect(43, 56, 45, 62, "k1")
    # keep tower (left, front)
    rect(14, 34, 31, 66, "s3"); rect(25, 34, 31, 66, "s2")
    for x in range(14, 32):
        for y in (40, 47, 54, 61):
            if (x + y // 7) % 6 == 0:
                px[x, y] = P["s1"]
    for x in range(13, 33, 4):                             # battlements
        rect(x, 30, x + 1, 33, "s3" if x < 25 else "s2")
    for i in range(10):                                   # cone roof
        rect(16 + i, 29 - i * 2, 29 - i, 30 - i * 2, "c2" if i < 5 else "c3")
        if 16 + i <= 22:
            px[16 + i, 30 - i * 2] = P["c3"]
    rect(20, 42, 22, 46, "y2"); px[20, 42] = P["y3"]
    rect(19, 58, 25, 66, "k1"); rect(20, 59, 24, 66, "k2")
    for x in range(20, 25):
        px[x, 58] = P["ink2"]
    # palisade / low wall in front
    for x in range(8, 58, 3):
        h = 6 if x % 2 else 5
        rect(x, 68 - h, x + 1, 68, "k2"); px[x, 68 - h] = P["k3"]
    outline(img)
    # flag pole on the roof tip
    for y in range(4, 12):
        px[22, y] = P["ink"]
    return img


def banner(frame):
    """Red kingdom pennant, 4-frame wave (12x9)."""
    img = new(14, 10)
    px = img.load()
    wave = [0, 1, 1, 0]
    for x in range(11):
        off = wave[(x // 3 + frame) % 4]
        top = 1 + off + (x // 6)
        bot = 7 + off - (x // 5)
        for y in range(top, bot + 1):
            c = "c2"
            if y == top:
                c = "c3"
            if y == bot or (x > 7 and y > bot - 1):
                c = "c1"
            if x in (4, 5) and top + 2 <= y <= top + 3:
                c = "y2"                                   # small gold mark
            px[x + 1, y] = P[c]
    outline(img)
    return img


# ----------------------------------------------------------------- champion
def champion(mode, f):
    """32x48 frame. mode: idle (4) | walk (6). Faces right."""
    img = new(32, 48)
    px = img.load()
    def put(x, y, c):
        if 0 <= x < 32 and 0 <= y < 48:
            px[x, y] = P[c]
    def rect(x0, y0, x1, y1, c):
        for x in range(x0, x1 + 1):
            for y in range(y0, y1 + 1):
                put(x, y, c)
    if mode == "walk":
        bob = [0, -1, -1, 0, -1, -1][f]
        stride = [5, 2, -2, -5, -2, 2][f]
        hem = [0, 1, 0, 0, -1, 0][f]
    else:
        bob = [0, 0, 1, 1][f]
        stride = 0
        hem = 0
    # legs + boots (back leg darker)
    for leg, (lx, dark) in enumerate([(13 - stride // 2, True), (17 + stride // 2, False)]):
        lift = 0
        if mode == "walk":
            lift = 1 if (leg == 0 and f in (1, 2)) or (leg == 1 and f in (4, 5)) else 0
        rect(lx, 36 + bob, lx + 2, 42 - lift, "k1" if dark else "d2")
        rect(lx, 43 - lift, lx + 3, 45 - lift, "hair" if dark else "p0")
        put(lx + 3, 43 - lift, "k1" if dark else "d1")
    # cloak: flared trapezoid
    for y in range(24 + bob, 38 + bob):
        t = (y - 24 - bob) / 13
        half = int(5 + t * 4)
        sx = (hem if y > 33 + bob else 0)
        for x in range(16 - half + sx, 16 + half + 1 + sx):
            c = "p2"
            if x <= 16 - half + sx + 1:
                c = "p3"
            elif x >= 16 + half + sx - 2:
                c = "p1"
            if y >= 36 + bob:
                c = "p1" if x > 16 else "p2"
            put(x, y, c)
    for y in range(33 + bob, 39 + bob):                  # one deep fold
        put(14 + (y - 33 - bob) // 3, y, "p1")
    # belt + buckle
    rect(11, 32 + bob, 21, 32 + bob, "k1"); put(17, 32 + bob, "y2")
    # scarf (kingdom red) with flapping tail behind
    rect(11, 23 + bob, 21, 25 + bob, "c2"); rect(11, 25 + bob, 21, 25 + bob, "c1")
    tail = [0, 1, 1, 0][(f if mode == "idle" else f) % 4] if mode == "idle" else [0, 1, 2, 1, 0, 1][f]
    for i in range(5):
        put(10 - i, 24 + bob + (i + tail) // 3, "c2" if i < 4 else "c1")
        put(10 - i, 25 + bob + (i + tail) // 3, "c1")
    # head: oversized, hair, face looking right
    for y in range(9 + bob, 23 + bob):
        for x in range(10, 23):
            d = ((x - 16) / 6.5) ** 2 + ((y - 15 - bob) / 7.0) ** 2
            if d <= 1.0:
                put(x, y, "f2")
                if (x >= 21 and y >= 18 + bob) or (x >= 18 and y >= 21 + bob):
                    put(x, y, "f1")
    for y in range(8 + bob, 17 + bob):                   # hair cap + fringe
        for x in range(9, 23):
            d = ((x - 15.5) / 7.0) ** 2 + ((y - 14 - bob) / 6.0) ** 2
            if d <= 1.0 and (y < 13 + bob or x < 13):
                put(x, y, "hair2" if (x < 14 and y < 11 + bob) else "hair")
    put(17, 8 + bob, "hair"); put(18, 7 + bob, "hair"); put(19, 7 + bob, "hair2")  # tuft
    blink = mode == "idle" and f == 3
    if blink:
        put(19, 16 + bob, "ink"); put(20, 16 + bob, "ink")
    else:
        put(19, 15 + bob, "ink"); put(19, 16 + bob, "ink"); put(20, 15 + bob, "s4")
    put(16, 18 + bob, "c3")                              # cheek
    put(20, 19 + bob, "f1"); put(21, 19 + bob, "ink2")   # mouth corner
    # arm + hand holding the staff
    arm = [0, 0, 0, 0][0] if mode == "idle" else [1, 0, -1, -1, 0, 1][f]
    rect(19, 26 + bob, 21, 30 + bob + arm, "p1")
    rect(21, 30 + bob + arm, 22, 31 + bob + arm, "f2")
    # staff + pennant
    sx = 23
    for y in range(6 + bob, 46):
        put(sx, y, "k2" if y % 6 else "k3")
    put(sx, 5 + bob, "y2")
    pw = [0, 1, 1, 0][f % 4] if mode == "idle" else [0, 1, 1, 0, 1, 1][f]
    for x in range(5):
        for y in range(2):
            put(sx + 1 + x, 7 + bob + y + (pw if x > 2 else 0), "c2" if y == 0 else "c1")
    outline(img)
    return img


def shadow():
    img = new(20, 6)
    px = img.load()
    for x in range(20):
        for y in range(6):
            if ((x - 9.5) / 10) ** 2 + ((y - 2.5) / 3) ** 2 <= 1:
                px[x, y] = (27, 20, 32, 110)
    return img


# ----------------------------------------------------------------- overlays
def hex_reach():
    img = new(TW, TH); px = img.load()
    for x in range(TW):
        for y in (ytop(x) + 1, ybot(x) - 1):
            if (x // 2) % 2 == 0:
                px[x, y] = P["y3"]
        for y in range(ytop(x) + 2, ybot(x) - 1):
            if (x + y) % 2 == 0 and (y - ytop(x) < 3 or ybot(x) - y < 4):
                px[x, y] = (255, 226, 122, 120)
    for y in range(Y0 + 16, Y0 + 29):
        if (y // 2) % 2 == 0:
            px[1, y] = P["y3"]; px[62, y] = P["y3"]
    return img


def hex_hover():
    img = new(TW, TH); px = img.load()
    for x in range(TW):
        px[x, ytop(x)] = P["s4"]; px[x, ybot(x)] = P["s4"]
        px[x, ytop(x) + 1] = P["y3"]; px[x, ybot(x) - 1] = P["y3"]
    for y in range(Y0 + 15, Y0 + 30):
        px[0, y] = P["s4"]; px[63, y] = P["s4"]; px[1, y] = P["y3"]; px[62, y] = P["y3"]
    return img


def path_dot():
    img = new(8, 6); px = img.load()
    for (x, y) in [(1, 1), (2, 1), (1, 2), (2, 2), (5, 3), (6, 3), (5, 4), (6, 4)]:
        px[x, y] = P["y3"]
    outline(img)
    return img


def target(frame):
    img = new(16, 20); px = img.load()
    off = [0, 1, 2, 1][frame]
    for i in range(6):
        for x in range(8 - (5 - i), 8 + (5 - i)):
            px[x, 4 + i + off] = P["y3" if x < 8 else "y2"]
    for y in range(0, 4):
        for x in range(6, 10):
            px[x, y + off] = P["y3" if x < 8 else "y2"]
    outline(img)
    return img


# ----------------------------------------------------------------- UI
def icons():
    """16x16 icons: food wood stone gold pop moves (row)."""
    img = new(16 * 6, 16); px = img.load()
    def put(i, x, y, c):
        px[i * 16 + x, y] = P[c]
    # food: wheat sheaf
    for y in range(3, 14):
        put(0, 7, y, "y1"); put(0, 8, y, "y2")
    for k in range(4):
        put(0, 5 + k % 2 * 4, 3 + k * 2, "y2"); put(0, 6 + k % 2 * 2, 3 + k * 2, "y3")
    for x in range(5, 11):
        put(0, x, 10, "k2")
    # wood: log
    for x in range(2, 13):
        for y in range(6, 11):
            put(1, x, y, "k2" if y > 6 else "k3")
    for y in range(6, 11):
        put(1, 13, y, "d3")
        put(1, 14, y, "d3" if 7 <= y <= 9 else "k2")
    put(1, 13, 8, "k1")
    # stone
    for x in range(3, 13):
        for y in range(5, 13):
            if ((x - 7.5) / 5) ** 2 + ((y - 9) / 4) ** 2 <= 1:
                put(2, x, y, "r3" if x + y < 15 else ("r2" if x + y < 20 else "r1"))
    # gold coin
    for x in range(3, 13):
        for y in range(3, 13):
            d = (x - 7.5) ** 2 + (y - 7.5) ** 2
            if d <= 22:
                put(3, x, y, "y2" if d > 9 else "y3")
                if d <= 5 and x > 7:
                    put(3, x, y, "y1")
    # pop: little person
    for x in range(6, 10):
        for y in range(3, 7):
            put(4, x, y, "f2")
    for x in range(4, 12):
        for y in range(8, 14):
            if abs(x - 7.5) <= 2 + (y - 8) * 0.5:
                put(4, x, y, "c2")
    # moves: boot
    for x in range(5, 10):
        for y in range(3, 10):
            put(5, x, y, "k2")
    for x in range(5, 13):
        for y in range(10, 13):
            put(5, x, y, "k1" if y == 12 else "k2")
    outline(img)
    return img


def panel():
    """12x12 nine-slice source (4px corners): ink frame, bevelled parchment."""
    img = new(12, 12); px = img.load()
    for x in range(12):
        for y in range(12):
            c = "pa3"
            if x == 0 or y == 0 or x == 11 or y == 11:
                c = "ink"
            elif x == 1 or y == 1:
                c = "pa4"
            elif x == 10 or y == 10:
                c = "pa1"
            elif x == 2 or y == 2:
                c = "pa3"
            px[x, y] = P[c]
    for (x, y) in [(0, 0), (11, 0), (0, 11), (11, 11)]:
        px[x, y] = CLEAR
    return img


def button(state):
    img = new(12, 12); px = img.load()
    base = {"normal": ("c2", "c3", "c1"), "hover": ("c3", "c4", "c2")}[state]
    for x in range(12):
        for y in range(12):
            c = base[0]
            if x == 0 or y == 0 or x == 11 or y == 11:
                c = "ink"
            elif y == 1:
                c = base[1]
            elif y >= 9:
                c = base[2]
            px[x, y] = P[c]
    for (x, y) in [(0, 0), (11, 0), (0, 11), (11, 11)]:
        px[x, y] = CLEAR
    return img


GLYPHS = {
    "A": "01110 10001 10001 11111 10001 10001 10001", "B": "11110 10001 11110 10001 10001 10001 11110",
    "C": "01111 10000 10000 10000 10000 10000 01111", "D": "11110 10001 10001 10001 10001 10001 11110",
    "E": "11111 10000 11110 10000 10000 10000 11111", "F": "11111 10000 11110 10000 10000 10000 10000",
    "G": "01111 10000 10000 10011 10001 10001 01111", "H": "10001 10001 11111 10001 10001 10001 10001",
    "I": "11111 00100 00100 00100 00100 00100 11111", "J": "00111 00001 00001 00001 10001 10001 01110",
    "K": "10001 10010 11100 10010 10001 10001 10001", "L": "10000 10000 10000 10000 10000 10000 11111",
    "M": "10001 11011 10101 10001 10001 10001 10001", "N": "10001 11001 10101 10011 10001 10001 10001",
    "O": "01110 10001 10001 10001 10001 10001 01110", "P": "11110 10001 10001 11110 10000 10000 10000",
    "Q": "01110 10001 10001 10001 10101 10010 01101", "R": "11110 10001 10001 11110 10010 10001 10001",
    "S": "01111 10000 01110 00001 00001 00001 11110", "T": "11111 00100 00100 00100 00100 00100 00100",
    "U": "10001 10001 10001 10001 10001 10001 01110", "V": "10001 10001 10001 10001 01010 01010 00100",
    "W": "10001 10001 10001 10101 10101 11011 10001", "X": "10001 01010 00100 00100 01010 10001 10001",
    "Y": "10001 10001 01010 00100 00100 00100 00100", "Z": "11111 00010 00100 01000 10000 10000 11111",
    "0": "01110 10011 10101 10101 11001 10001 01110", "1": "00100 01100 00100 00100 00100 00100 01110",
    "2": "01110 10001 00001 00110 01000 10000 11111", "3": "11110 00001 01110 00001 00001 00001 11110",
    "4": "10010 10010 10010 11111 00010 00010 00010", "5": "11111 10000 11110 00001 00001 10001 01110",
    "6": "01110 10000 11110 10001 10001 10001 01110", "7": "11111 00001 00010 00100 01000 01000 01000",
    "8": "01110 10001 01110 10001 10001 10001 01110", "9": "01110 10001 10001 01111 00001 00001 01110",
    " ": "00000 00000 00000 00000 00000 00000 00000", ".": "00000 00000 00000 00000 00000 00000 00100",
    ":": "00000 00100 00000 00000 00000 00100 00000", "-": "00000 00000 00000 01110 00000 00000 00000",
    "+": "00000 00100 00100 11111 00100 00100 00000", "/": "00001 00010 00010 00100 01000 01000 10000",
    "·": "00000 00000 00000 00100 00000 00000 00000", "!": "00100 00100 00100 00100 00100 00000 00100",
    "?": "01110 10001 00010 00100 00100 00000 00100", "'": "00100 00100 00000 00000 00000 00000 00000",
    ",": "00000 00000 00000 00000 00000 00100 01000", "(": "00010 00100 01000 01000 01000 00100 00010",
    ")": "01000 00100 00010 00010 00010 00100 01000",
}


def font():
    keys = list(GLYPHS.keys())
    img = new(6 * len(keys), 8); px = img.load()
    for i, k in enumerate(keys):
        rows = GLYPHS[k].split()
        for y, row in enumerate(rows):
            for x, b in enumerate(row):
                if b == "1":
                    px[i * 6 + x, y] = (255, 255, 255, 255)
    json.dump({"chars": "".join(keys), "w": 6, "h": 8}, open(os.path.join(OUT, "font.json"), "w"), ensure_ascii=False)
    return img


def palette_sheet():
    keys = list(P.keys())
    img = new(8 * len(keys), 8); px = img.load()
    for i, k in enumerate(keys):
        for x in range(8):
            for y in range(8):
                px[i * 8 + x, y] = P[k]
    return img


def strip(frames):
    w, h = frames[0].size
    img = new(w * len(frames), h)
    for i, f in enumerate(frames):
        img.alpha_composite(f, (i * w, 0))
    return img


if __name__ == "__main__":
    for v in range(3):
        save(plains(10 + v), f"tile_plains_{v}.png")
        save(hills(30 + v), f"tile_hills_{v}.png")
        save(strip([forest(20 + v, f) for f in range(4)]), f"tile_forest_{v}.png")
    save(strip([water(40, f) for f in range(4)]), "tile_water.png")
    save(strip([water(40, f, True) for f in range(4)]), "tile_water_inner.png")
    save(keep(), "building_capital.png")
    save(strip([banner(f) for f in range(4)]), "banner_red.png")
    save(strip([champion("idle", f) for f in range(4)]), "champion_idle.png")
    save(strip([champion("walk", f) for f in range(6)]), "champion_walk.png")
    save(shadow(), "shadow.png")
    save(hex_reach(), "hex_reach.png")
    save(hex_hover(), "hex_hover.png")
    save(path_dot(), "path_dot.png")
    save(strip([target(f) for f in range(4)]), "target.png")
    save(icons(), "icons.png")
    save(panel(), "ui_panel.png")
    save(button("normal"), "ui_button.png")
    save(button("hover"), "ui_button_hover.png")
    save(font(), "font.png")
    save(palette_sheet(), "palette.png")
    print("pixel assets ->", os.path.abspath(OUT))
