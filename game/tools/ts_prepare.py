#!/usr/bin/env python3
"""Prepares Tiny Swords art for KNORO (city screen + pixel UI).

Usage (from game/):
    python3 tools/ts_prepare.py "<Tiny Swords (Free Pack) dir>" "<Tiny Swords (Update 010) dir>"

What it does
  1. Copies the sprites the city needs out of the two packs into assets/tinyswords/city|ui|units/.
     (Free Pack: Pixel Frog licence, no redistribution of the raw files. Update 010: CC0.)
  2. Re-packs the pack's 3x3 "gapped" panel sheets (pieces at 0/128/256) into contiguous
     192x192 nine-slices so Godot's StyleBoxTexture can stretch them.
  3. Recolours the pack's gold stones into iron ore (a palette swap; nothing is drawn).
"""
import os
import shutil
import sys

from PIL import Image

FREE, OLD = sys.argv[1], sys.argv[2]
OUT = "assets/tinyswords"
for d in ("city", "ui", "units"):
    os.makedirs(os.path.join(OUT, d), exist_ok=True)

INK = (22, 28, 46, 255)          # #161c2e, the pack's outline colour
WOOD = [(101, 72, 72), (134, 99, 83), (180, 129, 80), (218, 181, 112)]
CREAM = [(200, 168, 118), (213, 170, 96), (239, 225, 171)]
STONE = [(80, 106, 105), (102, 157, 157), (140, 195, 196)]
GREY = [(110, 104, 110), (152, 142, 132), (187, 174, 147), (225, 220, 200)]
KCOL = {  # roof / cloth colours per kingdom: dark, mid, light
    "red": [(101, 50, 59), (141, 72, 72), (222, 84, 84)],
    "blue": [(44, 70, 101), (61, 112, 140), (92, 168, 190)],
    "yellow": [(120, 86, 40), (196, 150, 52), (240, 205, 92)],
}
GOLD = [(176, 120, 40), (226, 180, 60), (252, 230, 120)]


def cp(src, dst):
    shutil.copyfile(src, os.path.join(OUT, dst))


# ---------------------------------------------------------------- 1. copies
COLORS = {"Red": "red", "Blue": "blue", "Yellow": "yellow", "Purple": "purple", "Black": "black"}
for cname, cid in COLORS.items():
    for b in ("Archery", "Barracks", "Castle", "House1", "House2", "House3", "Monastery", "Tower"):
        cp(f"{FREE}/Buildings/{cname} Buildings/{b}.png", f"city/b_{cid}_{b.lower()}.png")
for cname, cid in list(COLORS.items())[:3]:
    for a in ("Pawn_Run", "Pawn_Run Wood", "Pawn_Run Meat", "Pawn_Run Gold", "Pawn_Idle",
              "Pawn_Interact Axe", "Pawn_Interact Pickaxe", "Pawn_Interact Hammer"):
        cp(f"{FREE}/Units/{cname} Units/Pawn/{a}.png", f"units/{cid}_{a.lower().replace(' ', '_')}.png")
for i in range(1, 19):
    cp(f"{OLD}/Deco/{i:02d}.png", f"city/deco_{i:02d}.png")
cp(f"{OLD}/Resources/Gold Mine/GoldMine_Active.png", "city/goldmine.png")
cp(f"{OLD}/Resources/Gold Mine/GoldMine_Inactive.png", "city/goldmine_idle.png")
cp(f"{OLD}/Factions/Goblins/Buildings/Wood_House/Goblin_House.png", "city/hut.png")
cp(f"{OLD}/Factions/Knights/Buildings/House/House_Construction.png", "city/construction.png")
for c in ("Red", "Blue", "Yellow"):
    cp(f"{OLD}/Factions/Goblins/Buildings/Wood_Tower/Wood_Tower_{c}.png", f"city/woodtower_{c.lower()}.png")
cp(f"{OLD}/Effects/Fire/Fire.png", "city/fire.png")
cp(f"{FREE}/Terrain/Resources/Wood/Wood Resource/Wood Resource.png", "city/res_wood.png")
cp(f"{FREE}/Terrain/Resources/Meat/Meat Resource/Meat Resource.png", "city/res_meat.png")
cp(f"{FREE}/Terrain/Resources/Gold/Gold Resource/Gold_Resource.png", "city/res_gold.png")
for i in range(1, 7):
    cp(f"{FREE}/Terrain/Resources/Gold/Gold Stones/Gold Stone {i}.png", f"city/goldstone{i}.png")
for i in range(1, 5):
    cp(f"{FREE}/Terrain/Resources/Wood/Trees/Stump {i}.png", f"city/stump{i}.png")
    cp(f"{FREE}/Terrain/Resources/Tools/Tool_{i:02d}.png", f"ui/tool{i}.png")
    cp(f"{FREE}/Terrain/Decorations/Rocks in the Water/Water Rocks_{i:02d}.png", f"city/waterrock{i}.png")
cp(f"{FREE}/Terrain/Resources/Meat/Sheep/Sheep_Grass.png", "city/sheep_grass.png")
cp(f"{FREE}/Terrain/Decorations/Rocks/Rock4.png", "rock4.png")
for f in ("Bushe3", "Bushe4"):
    cp(f"{FREE}/Terrain/Decorations/Bushes/{f}.png", f"{f.lower().replace('bushe', 'bush')}.png")
for i in range(1, 13):
    cp(f"{FREE}/UI Elements/UI Elements/Icons/Icon_{i:02d}.png", f"ui/icon_{i:02d}.png")
for i in range(1, 26):
    cp(f"{FREE}/UI Elements/UI Elements/Human Avatars/Avatars_{i:02d}.png", f"ui/avatar_{i:02d}.png")
cp(f"{FREE}/UI Elements/UI Elements/Ribbons/BigRibbons.png", "ui/bigribbons.png")
cp(f"{FREE}/UI Elements/UI Elements/Ribbons/SmallRibbons.png", "ui/smallribbons.png")
cp(f"{FREE}/UI Elements/UI Elements/Swords/Swords.png", "ui/swords.png")
for n in ("BigBar_Base", "BigBar_Fill", "SmallBar_Base", "SmallBar_Fill"):
    cp(f"{FREE}/UI Elements/UI Elements/Bars/{n}.png", f"ui/{n.lower()}.png")
for n in ("01", "02", "03"):
    cp(f"{OLD}/UI/Pointers/{n}.png", f"ui/pointer_{n}.png")


# ---------------------------------------------------------------- 2. nine-slices
def _runs(alpha, axis):
    w, h = alpha.size
    n = w if axis == 0 else h
    used = []
    for i in range(n):
        box = (i, 0, i + 1, h) if axis == 0 else (0, i, w, i + 1)
        if alpha.crop(box).getbbox():
            used.append(i)
    runs, start, prev = [], used[0], used[0]
    for v in used[1:]:
        if v != prev + 1:
            runs.append((start, prev + 1))
            start = v
        prev = v
    runs.append((start, prev + 1))
    return runs


def compact(src, dst, *_, flat_center=False):
    """Packs a gapped 3x3 sheet into one contiguous image, cropped to the drawn pixels.
    Prints the resulting margins (left, top, right, bottom) for StyleBoxTexture."""
    im = Image.open(src).convert("RGBA")
    a = im.split()[3]
    cx, cy = _runs(a, 0), _runs(a, 1)
    assert len(cx) == 3 and len(cy) == 3, (src, cx, cy)
    ws = [r[1] - r[0] for r in cx]
    hs = [r[1] - r[0] for r in cy]
    out = Image.new("RGBA", (sum(ws), sum(hs)))
    for i in range(3):
        for j in range(3):
            out.paste(im.crop((cx[i][0], cy[j][0], cx[i][1], cy[j][1])), (sum(ws[:i]), sum(hs[:j])))
    if flat_center:
        # the pack's centre piece carries crumple marks that read as a grid when
        # tiled; replace it with its own most common colour (a fill, not new art)
        cx0, cy0 = ws[0], hs[0]
        cen = out.crop((cx0, cy0, cx0 + ws[1], cy0 + hs[1]))
        col = max(cen.getcolors(ws[1] * hs[1]), key=lambda c: c[0])[1]
        out.paste(Image.new("RGBA", (ws[1], hs[1]), col), (cx0, cy0))
    out.save(os.path.join(OUT, dst))
    MARGINS[dst] = [ws[0], hs[0], ws[2], hs[2]]


MARGINS = {}


U = f"{FREE}/UI Elements/UI Elements"
compact(f"{U}/Papers/RegularPaper.png", "ui/nine_paper.png", flat_center=True)
compact(f"{U}/Papers/SpecialPaper.png", "ui/nine_special.png")
compact(f"{U}/Buttons/BigBlueButton_Regular.png", "ui/nine_blue.png")
compact(f"{U}/Buttons/BigBlueButton_Pressed.png", "ui/nine_blue_pressed.png")
compact(f"{U}/Buttons/BigRedButton_Regular.png", "ui/nine_red.png")
compact(f"{U}/Buttons/BigRedButton_Pressed.png", "ui/nine_red_pressed.png")
compact(f"{U}/Wood Table/WoodTable.png", "ui/nine_wood.png", 64, 192)
compact(f"{U}/Banners/Banner.png", "ui/nine_banner.png", 64, 192)
for n in ("Hover", "Disable", "Blue", "Red", "Blue_9Slides_Pressed", "Red_9Slides_Pressed"):
    name = n if "Pressed" in n else n + "_9Slides"
    cp(f"{OLD}/UI/Buttons/Button_{name}.png", f"ui/btn_{n.lower().replace('_9slides', '')}.png")
cp(f"{OLD}/UI/Banners/Carved_9Slides.png", "ui/nine_carved.png")
import json
json.dump(MARGINS, open(os.path.join(OUT, "ui/nine_margins.json"), "w"), indent=1)
cp(f"{U}/Wood Table/WoodTable_Slots.png", "ui/woodtable_slots.png")
cp(f"{U}/Banners/Banner_Slots.png", "ui/banner_slots.png")

# pier planks out of the CC0 bridge sheet
br = Image.open(f"{OLD}/Terrain/Bridge/Bridge_All.png").convert("RGBA")
br.crop((0, 0, 192, 64)).save(os.path.join(OUT, "city/pier.png"))


# ---------------------------------------------------------------- 3. drawn props
# iron ore: the pack's gold stones recoloured to cold steel
for i in range(1, 4):
    src = Image.open(f"{FREE}/Terrain/Resources/Gold/Gold Stones/Gold Stone {i}.png").convert("RGBA")
    px = src.load()
    for y in range(src.height):
        for x in range(src.width):
            r, g, b, a = px[x, y]
            if a and r > 150 and g > 100 and b < 120:      # gold flecks -> rust-red ore
                px[x, y] = (196, 104, 78, a) if r > 220 else (150, 70, 62, a)
    src.save(os.path.join(OUT, f"city/ironstone{i}.png"))

# ---------------------------------------------------------------- battle / map units
UN = {"Red": "red", "Blue": "blue", "Yellow": "yellow", "Black": "black", "Purple": "purple"}
for cname, cid in UN.items():
    base = f"{FREE}/Units/{cname} Units"
    for src, dst in (("Warrior/Warrior_Idle", "warrior_idle"), ("Warrior/Warrior_Attack1", "warrior_attack"), ("Warrior/Warrior_Guard", "warrior_guard"),
                     ("Warrior/Warrior_Run", "warrior_run"), ("Archer/Archer_Idle", "archer_idle"), ("Archer/Archer_Shoot", "archer_attack"),
                     ("Lancer/Lancer_Idle", "lancer_idle"), ("Lancer/Lancer_Right_Attack", "lancer_attack"), ("Monk/Idle", "monk_idle"),
                     ("Monk/Heal", "monk_attack"), ("Pawn/Pawn_Idle Knife", "pawn_knife_idle"), ("Pawn/Pawn_Interact Knife", "pawn_knife_attack"),
                     ("Pawn/Pawn_Idle Gold", "pawn_idle_gold"), ("Pawn/Pawn_Idle Hammer", "pawn_idle_hammer"), ("Pawn/Pawn_Idle", "pawn_idle"),
                     ("Pawn/Pawn_Run", "pawn_run"), ("Pawn/Pawn_Run Gold", "pawn_run_gold")):
        cp(f"{base}/{src}.png", f"units/{cid}_{dst}.png")
G = f"{OLD}/Factions/Goblins/Troops"
for c in ("Purple", "Red"):
    # old goblin sheets are grids of 192 px cells: row 0 idle, row 2 attack
    sh = Image.open(f"{G}/Torch/{c}/Torch_{c}.png").convert("RGBA")
    sh.crop((0, 0, 192 * 7, 192)).save(os.path.join(OUT, f"units/goblin_{c.lower()}_idle.png"))
    sh.crop((0, 384, 192 * 6, 576)).save(os.path.join(OUT, f"units/goblin_{c.lower()}_attack.png"))
cp(f"{OLD}/Factions/Knights/Troops/Dead/Dead.png", "units/dead.png")
for src, dst in (("Factions/Knights/Buildings/Castle/Castle_Destroyed", "ruin_castle"), ("Factions/Knights/Buildings/Tower/Tower_Destroyed", "ruin_tower"),
                 ("Factions/Knights/Buildings/House/House_Destroyed", "ruin_house"), ("Factions/Goblins/Buildings/Wood_House/Goblin_House_Destroyed", "hut_ruin"),
                 ("Factions/Goblins/Buildings/Wood_Tower/Wood_Tower_Destroyed", "woodtower_ruin")):
    cp(f"{OLD}/{src}.png", f"city/{dst}.png")

print("done")
